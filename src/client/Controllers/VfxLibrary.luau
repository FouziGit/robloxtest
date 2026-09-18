--!strict
-- VfxLibrary: client renderers for the Vfx / VfxReliable packets broadcast by the server. One function
-- per packet Id, called by VfxController with a fresh trove that is destroyed after the packet lifetime.
-- Every part, tween, connection and delayed thread is tracked by that trove, particle rates are capped,
-- and nothing yields on the caller thread: timed steps run in task.delay threads owned by the trove.
-- Effects that need a frame step share one Heartbeat (see `animate`), which lays them out once at
-- registration and then skips frames while they play farther than GameConfig.Vfx.AnimateRadiusStuds
-- from the local character.
-- The server never builds visuals; it only sends {Id, Origin, Direction, Caster, Targets, Params}.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local FeelConfig = require(Shared.Config.FeelConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Trove = require(Packages.Trove)

export type Packet = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}

export type Api = {
	Sound: { play: (sfxId: string, position: Vector3?) -> () },
	Shake: (intensity: number) -> (),
	HitStop: (seconds: number) -> (),
	PigmentColor: (pigment: string) -> Color3,
	LocalCharacter: () -> Model?,
	-- The Feel controller, untyped here on purpose: this module is required by the client only, and a
	-- concrete type would make ReplicatedStorage depend on a controller in StarterPlayerScripts.
	-- Phase 3 replaces Shake and HitStop above with calls through this (docs/JUICE_PLAN.md).
	Feel: any,
	-- The timeline runtime. A reworked effect declares its layers in Config/VfxTimelineConfig and
	-- plays them through this instead of building instances by hand.
	Timeline: any,
	LocalUserId: number,
	-- The model of a player by user id, for effects that have to adorn the person who was hit rather
	-- than draw at a point in space. nil for a training dummy or an enemy, which has no player.
	CharacterOf: (userId: number) -> Model?,
}

type TroveType = typeof(Trove.new())

export type Effect = (packet: Packet, trove: TroveType, api: Api) -> ()

type PartProps = {
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	Color: Color3?,
	Size: Vector3?,
	Transparency: number?,
	CFrame: CFrame?,
}

type EmitterProps = {
	Color: Color3,
	Rate: number?,
	Lifetime: NumberRange?,
	Speed: NumberRange?,
	Size: NumberSequence?,
	Transparency: NumberSequence?,
	Spread: Vector2?,
	Acceleration: Vector3?,
}

-- VfxController destroys the packet trove after the same delay: every effect fits inside it.
local MAX_LIFETIME_SECONDS = GameConfig.Vfx.LifetimeSeconds
local MAX_PARTICLE_RATE = 40
local MAX_PARTICLE_BURST = 40
local FOLDER_NAME = "ClientVfx"
local ROOT_PART_NAME = "HumanoidRootPart"
local ROOT_HEIGHT_STUDS = 3 -- HumanoidRootPart center above the ground for a standing rig
local GROUND_PROBE_STUDS = 24
-- Damage at or above which an impact uses the heavy profile instead of the light one. It is the
-- roster's own midpoint, not a guess: tests/Config.spec.luau holds it between the jab and the
-- heaviest ultimate.
local HEAVY_HIT_DAMAGE = 25
-- How much of a shake survives for a fight the local player is not in.
local DISTANT_HIT_SCALE = 0.55
-- Damage you took is red, whatever pigment dealt it (docs/ART_BIBLE.md: red means danger to you).
local HIT_TAKEN_COLOR = Color3.fromRGB(217, 58, 34)
-- Magnitude at or above which a renderer that still asks for a bare shake intensity gets the heavy
-- profile rather than the light one. The old scale ran 0 to 1, with 0.9 meaning "an ultimate landed".
local HEAVY_SHAKE_INTENSITY = 0.7
-- Brand's blast radius (GlyphConfig), which the Explosion timeline is authored at. A packet carrying
-- a different radius scales the whole timeline by the ratio.
local DEFAULT_BLAST_RADIUS = 7
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local WHITE = Color3.fromRGB(255, 245, 220)
local SHIELD_COLOR = Color3.fromRGB(120, 190, 255)
local GUARD_BREAK_COLOR = Color3.fromRGB(255, 120, 90)

local MELEE_SFX_VARIANTS = 3 -- SoundConfig has Melee1..Melee3 plus MeleeFinisher

-- Phase 2 roster tuning (docs/GAME_DESIGN.md §5)
local LYING_CYLINDER = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: stand it upright
local SMOKE_COLOR = Color3.fromRGB(70, 62, 58)

-- World Boss (docs/GAME_DESIGN.md §7). Every boss attack is painted on the arena floor for its whole
-- telegraph window, so the warning shows exactly the area the server will damage.
local BOSS_DANGER_COLOR = Color3.fromRGB(255, 96, 72)
local BOSS_SAFE_COLOR = Color3.fromRGB(110, 210, 150)
local BOSS_ENERGY_COLOR = Color3.fromRGB(168, 120, 235)
local BOSS_WARNING_TRANSPARENCY = 0.85 -- the paint starts faint and fills in as the hit approaches
local BOSS_WARNING_PEAK_TRANSPARENCY = 0.3
local BOSS_IMPACT_SECONDS = 0.35
local BOSS_DISC_THICKNESS_STUDS = 0.4
local BOSS_DISC_LIFT_STUDS = 0.15 -- above the floor, so the paint never z-fights with it
local BOSS_CONE_SEGMENTS = 5
local BOSS_PILLAR_COUNT = 8
local BOSS_PILLAR_WIDTH_STUDS = 4
local BOSS_SPAWN_SECONDS = 1
local BOSS_DEFEAT_SECONDS = 1.4
local BOSS_DEFEAT_COLLAPSE_FACTOR = 0.4 -- share of the defeat spent collapsing before the blast

local VfxLibrary: { [string]: Effect } = {}

local folder: Folder? = nil

-- Set whenever the ground probe's exclude list stops describing the world (see `groundAt`).
local groundExcludeStale = true

local function markGroundExcludeStale()
	groundExcludeStale = true
end

local function getFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	markGroundExcludeStale()
	return created
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function numberParam(packet: Packet, key: string, default: number): number
	local params = packet.Params
	if params == nil then
		return default
	end
	local value = params[key]
	if isFinite(value) then
		return value
	end
	return default
end

local function stringParam(packet: Packet, key: string, default: string): string
	local params = packet.Params
	if params == nil then
		return default
	end
	local value = params[key]
	if type(value) == "string" then
		return value
	end
	return default
end

local function directionOf(packet: Packet): Vector3
	local direction = packet.Direction
	if direction == nil or direction.Magnitude < 1e-3 then
		return DEFAULT_DIRECTION
	end
	return direction.Unit
end

-- Horizontal direction for ground effects (spikes, waves, walls).
local function flatDirectionOf(packet: Packet): Vector3
	local direction = directionOf(packet)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return DEFAULT_DIRECTION
	end
	return flat.Unit
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

-- Assigning FilterDescendantsInstances makes the engine resolve every descendant of the list, and a
-- full server of characters is a few hundred instances. The list only changes when the effect folder or
-- a character does, so it is rebuilt then and not on every probe (one glyph can fire several).
local function refreshGroundExclude()
	local exclude: { Instance } = { getFolder() }
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character ~= nil then
			table.insert(exclude, character)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
	groundExcludeStale = false
end

-- A respawn swaps the character model, so both edges have to invalidate or the filter would keep
-- excluding a destroyed rig and stop excluding the live one. A join invalidates as well: the joiner's
-- first CharacterAdded can land before PlayerAdded reaches this client, and the filter would then miss
-- that character until its next respawn.
local function watchCharacters(player: Player)
	markGroundExcludeStale()
	player.CharacterAdded:Connect(markGroundExcludeStale)
	player.CharacterRemoving:Connect(markGroundExcludeStale)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchCharacters(player)
end
Players.PlayerAdded:Connect(watchCharacters)
Players.PlayerRemoving:Connect(markGroundExcludeStale)

-- Ground point under `position` (a root-height origin); falls back to root height when nothing is hit.
local function groundAt(position: Vector3): Vector3
	if groundExcludeStale then
		refreshGroundExclude()
	end
	local result = Workspace:Raycast(
		position + Vector3.new(0, ROOT_HEIGHT_STUDS, 0),
		Vector3.new(0, -GROUND_PROBE_STUDS, 0),
		groundParams
	)
	if result ~= nil then
		return result.Position
	end
	return Vector3.new(position.X, position.Y - ROOT_HEIGHT_STUDS, position.Z)
end

local function newPart(trove: TroveType, name: string, props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = props.Shape or Enum.PartType.Block
	part.Material = props.Material or Enum.Material.Neon
	part.Color = props.Color or WHITE
	part.Size = props.Size or Vector3.one
	part.Transparency = props.Transparency or 0
	part.CFrame = props.CFrame or CFrame.identity
	trove:Add(part)
	part.Parent = getFolder()
	return part
end

local function play(
	trove: TroveType,
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, goal)
	trove:Add(tween)
	tween:Play()
	return tween
end

local function after(trove: TroveType, seconds: number, fn: () -> ())
	trove:Add(task.delay(seconds, fn))
end

local function newEmitter(parent: Instance, props: EmitterProps): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(props.Color)
	emitter.Rate = math.min(props.Rate or 0, MAX_PARTICLE_RATE)
	emitter.Lifetime = props.Lifetime or NumberRange.new(0.4, 0.8)
	emitter.Speed = props.Speed or NumberRange.new(4, 10)
	emitter.Size = props.Size or NumberSequence.new(1, 0)
	emitter.Transparency = props.Transparency or NumberSequence.new(0.2, 1)
	emitter.SpreadAngle = props.Spread or Vector2.new(180, 180)
	emitter.Acceleration = props.Acceleration or Vector3.zero
	emitter.LightEmission = 0.6
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = parent
	return emitter
end

local function burst(emitter: ParticleEmitter, count: number)
	emitter:Emit(math.min(count, MAX_PARTICLE_BURST))
end

local function rootOf(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local root: Instance? = character:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Shakes the local camera with an intensity that fades with the distance to `origin`. The falloff and
-- the radius belong to Feel, so a spell reworked in phase 4 and one that has not been yet still fade
-- the same way and still read against the same radius; only the way the caller names its weight
-- changes. `intensity` is the old 0-to-1 magnitude, mapped onto a profile the way VfxController does.
local function shakeNear(api: Api, origin: Vector3, intensity: number)
	if intensity <= 0 then
		return
	end
	api.Feel.shakeAt(if intensity >= HEAVY_SHAKE_INTENSITY then "Heavy" else "Light", origin, math.min(intensity, 1))
end

local function casterRoot(packet: Packet): BasePart?
	local userId = packet.Caster
	if userId == nil then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return nil
	end
	return rootOf(player.Character)
end

----------------------------------------------------------------
-- Frame ticker
----------------------------------------------------------------

-- One live frame-stepped effect. `Center` is where it plays and is what the distance gate measures;
-- `Follow` is the root it rides, when it tracks its caster.
type Animation = {
	Center: Vector3,
	Follow: BasePart?,
	Elapsed: number,
	Live: boolean,
	Step: (elapsed: number, center: Vector3, viewer: BasePart?) -> (),
}

local function shieldFlash(trove: TroveType, origin: Vector3, startTransparency: number, seconds: number)
	local shield = newPart(trove, "Shield", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = SHIELD_COLOR,
		Size = Vector3.one * 6,
		Transparency = startTransparency,
		CFrame = CFrame.new(origin),
	})
	play(trove, shield, seconds, { Transparency = 1, Size = Vector3.one * 7.5 })
end

local function clampLifetime(seconds: number, reserve: number): number
	return math.clamp(seconds, 0.1, MAX_LIFETIME_SECONDS - reserve)
end

-- Fades a group of parts out together (bolt segments, stone plates).
local function fadeParts(trove: TroveType, parts: { Part }, seconds: number)
	for _, part in ipairs(parts) do
		play(trove, part, seconds, { Transparency = 1 })
	end
end

-- Plays the glyph's own sound when the server attached one to the packet (as the Cast packet does).
local function playPacketSound(packet: Packet, api: Api)
	local sfxId = stringParam(packet, "SfxId", "")
	if sfxId ~= "" then
		api.Sound.play(sfxId, packet.Origin)
	end
end

-- Casting flash at the caster, colored by the glyph pigment, with its cast sound.
VfxLibrary.Cast = function(packet: Packet, _trove: TroveType, api: Api)
	-- What this replaced was one ball that grew and one spark burst, played identically by all twenty
	-- glyphs: two layers, no wind-up, nothing left behind, and no way to tell a Cinnabar cast from an
	-- Orpiment one except the tint. docs/JUICE_AUDIT.md lists it as the single worst offender in the game.
	--
	-- It is now the Cast timeline: a seal drawn in the air, held, and folded into a point that releases.
	-- The renderer's whole job is to say who cast it, where, and in what pigment.
	api.Timeline.play("Cast", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = api.PigmentColor(stringParam(packet, "Pigment", "")),
		Follow = casterRoot(packet),
	})
	local sfxId = stringParam(packet, "SfxId", "")
	if sfxId ~= "" then
		api.Sound.play(sfxId, packet.Origin)
	end
	-- The field of view and the pad belong to the person who cast it, and to nobody else. The timeline's
	-- own shake layer is distance-attenuated, so bystanders feel the cast without being punched by it.
	if packet.Caster == api.LocalUserId then
		api.Feel.fovPunch(FeelConfig.Fov.CastImpulse)
		api.Feel.haptic("Cast")
	end
end

-- Neon ball with fire and a trail, flying along Direction for the fuse duration.
-- Brand (Cinnabar, projectile). The first glyph every player learns and the one they throw most.
--
-- What it replaced was a ball wearing Roblox's own Fire class, flying a straight line at a constant speed
-- for a full second. Its detonation is a separate packet -- the server emits Explosion when it lands --
-- and that split is correct rather than accidental: the projectile does not know where it will end.
VfxLibrary.Brand = function(packet: Packet, _trove: TroveType, api: Api)
	api.Timeline.play("Brand", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = api.PigmentColor("Cinnabar"),
	})
end

-- Expanding sphere and ember burst where a projectile or blast lands.
-- The detonation every exploding projectile shares. The server sends the blast radius it actually used,
-- so the visual is the size of the damage rather than a constant that happens to look right for one
-- glyph: a blast drawn smaller than it hurts is the most expensive lie a fighting game can tell.
VfxLibrary.Explosion = function(packet: Packet, _trove: TroveType, api: Api)
	local radius = numberParam(packet, "Radius", numberParam(packet, "BlastRadius", DEFAULT_BLAST_RADIUS))
	api.Timeline.play("Explosion", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = api.PigmentColor(stringParam(packet, "Pigment", "")),
		Scale = radius / DEFAULT_BLAST_RADIUS,
	})
	api.Sound.play("ImpactExplosion", packet.Origin)
end

-- Every glyph's visual is its timeline (Config/VfxTimelineConfig). The renderer's whole job is to say
-- where it happened, which way it was aimed, in which pigment, and whose body it is attached to.
--
-- The pigment comes from GlyphConfig rather than from the packet. A packet MAY carry one -- several
-- effects put Params.Pigment in -- but not all of them do, and a glyph's school is a fixed fact about the
-- glyph rather than a thing worth sending over the wire sixty times a second. One source, and it is the
-- one the gameplay already reads.
--
-- The caster's body is passed unconditionally. It costs one lookup, and only a layer that declared
-- Follow ever uses it, so a timeline that does not need one is not paying for a decision the renderer
-- would otherwise have to remember to make per glyph.
local function playGlyph(id: string, packet: Packet, api: Api)
	local def = GlyphConfig.ById[id]
	api.Timeline.play(id, {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = api.PigmentColor(if def ~= nil then def.Pigment else stringParam(packet, "Pigment", "")),
		Follow = casterRoot(packet),
	})
	playPacketSound(packet, api)
end

VfxLibrary.Wash = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Wash", packet, api)
end

VfxLibrary.Serif = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Serif", packet, api)
end

VfxLibrary.Sweep = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Sweep", packet, api)
end

VfxLibrary.Bleed = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Bleed", packet, api)
end

VfxLibrary.Margin = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Margin", packet, api)
end

VfxLibrary.Scorch = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Scorch", packet, api)
end

VfxLibrary.Rupture = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Rupture", packet, api)
end

----------------------------------------------------------------
-- Phase 2 roster (docs/GAME_DESIGN.md §5), grouped by pigment like GlyphConfig
----------------------------------------------------------------

VfxLibrary.Ligature = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Ligature", packet, api)
end

VfxLibrary.Blot = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Blot", packet, api)
end

VfxLibrary.Binding = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Binding", packet, api)
end

VfxLibrary.Stipple = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Stipple", packet, api)
end

VfxLibrary.Gilding = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Gilding", packet, api)
end

VfxLibrary.Hairline = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Hairline", packet, api)
end

VfxLibrary.Spiral = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Spiral", packet, api)
end

VfxLibrary.Pounce = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Pounce", packet, api)
end

VfxLibrary.Strike = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Strike", packet, api)
end

VfxLibrary.Caret = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Caret", packet, api)
end

VfxLibrary.Watermark = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Watermark", packet, api)
end

-- Colophon is the one glyph whose packet carries a PATH rather than a point. The server chains from body
-- to body and sends Targets as one position per link, in the order the arcs fired, so the visual is the
-- signature struck at the caster plus one ruled stroke per link, each aimed at the body the chain went to
-- next. Drawing only the first would hide the whole reason the ultimate costs fifty-five ink.
VfxLibrary.Colophon = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Colophon", packet, api)

	local points = packet.Targets
	if points == nil then
		return
	end
	local def = GlyphConfig.ById.Colophon
	local color = api.PigmentColor(if def ~= nil then def.Pigment else "Orpiment")
	for index, point in ipairs(points) do
		-- Aimed at the next link, or along the cast for the last one, which has nowhere further to go.
		-- Typed optional explicitly: Luau reads a list index as non-optional, so the guard below would be
		-- dead to the analyser and the last link would subtract nil.
		local nextPoint: Vector3? = points[index + 1]
		local direction = if nextPoint ~= nil then nextPoint - point else directionOf(packet)
		if direction.Magnitude < 1e-3 then
			direction = directionOf(packet)
		end
		api.Timeline.play("ColophonLink", { Origin = point, Direction = direction.Unit, Color = color })
	end
end

-- Impact. Everything a player learns about a hit in the first tenth of a second happens here: how hard it
-- was, who took it, from which side, and whether it was their own.
--
-- The visible half is the Hit timeline -- the ring, the sparks along the blow, the light, the page flash,
-- and the ink burn the ground keeps for a couple of seconds. The half that stays here is the half that
-- depends on WHO is watching, which no timeline can know: the same hit is a different event for the
-- person who landed it, the person who took it, and the four people who did not.
--
-- The previous version keyed all of that off one four-stud radius test, so in a six-player arena the
-- camera jolted for fights the player was not in and stayed calm for the one they were.
VfxLibrary.Hit = function(packet: Packet, _trove: TroveType, api: Api)
	local pigment = stringParam(packet, "Pigment", "")
	local color = api.PigmentColor(pigment)
	local amount = numberParam(packet, "Amount", 0)
	local targetUserId = numberParam(packet, "Target", 0)
	local amplified = packet.Params ~= nil and packet.Params.StatusKey ~= nil
	local heavy = amount >= HEAVY_HIT_DAMAGE

	api.Timeline.play("Hit", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = color,
		-- A heavier hit is the same effect, larger. One timeline serves a jab and an ultimate, which is
		-- what keeps the roster's visual language consistent as it grows.
		Scale = if heavy then 1.35 else 1,
	})
	api.Sound.play("ImpactHit", packet.Origin)

	local feel = api.Feel
	local dealtByMe = packet.Caster == api.LocalUserId
	local takenByMe = targetUserId == api.LocalUserId and targetUserId ~= 0

	if takenByMe then
		feel.hitStopForDamage(amount, "Taken")
		feel.fovPunch(FeelConfig.Fov.HitTakenImpulse)
		feel.shake(if heavy then "Heavy" else "Light")
		feel.haptic("HitTaken")
	elseif dealtByMe then
		feel.hitStopForDamage(amount, "Dealt")
		feel.fovPunch(FeelConfig.Fov.HitDealtImpulse)
		feel.shake(if heavy then "Heavy" else "Melee")
		feel.haptic("HitDealt")
	else
		-- Somebody else's exchange: the camera acknowledges it, faded by how far away it was.
		feel.shakeAt(if heavy then "Heavy" else "Light", packet.Origin, DISTANT_HIT_SCALE)
	end

	-- The outline is what tells you your hit landed on the right person through a crowd and through a
	-- wall. Only ever drawn for the two people in the exchange; everybody else's is noise.
	if dealtByMe or takenByMe then
		local targetModel = api.CharacterOf(targetUserId)
		if targetModel ~= nil then
			feel.flash(targetModel, if takenByMe then HIT_TAKEN_COLOR else color)
		end
		feel.damageNumber(packet.Origin, amount, if takenByMe then HIT_TAKEN_COLOR else color, amplified)
	end
end

-- The punch. The most repeated action in the game, which is why docs/JUICE_PLAN.md rebuilt it before any
-- ultimate: a player throws hundreds of these a match and one Colophon.
--
-- What it replaced was a flat white rectangle rotated seventy degrees and tweened back, with no wind-up,
-- nothing left behind, and the same shape whichever hand threw it. The swing is the Melee timeline now;
-- what stays here is the sound, which follows the combo index, and the caster's own field of view.
VfxLibrary.Melee = function(packet: Packet, _trove: TroveType, api: Api)
	local index = math.max(1, math.floor(numberParam(packet, "Index", 1)))
	local finisherIndex = #CombatConfig.Melee.Damage
	local finisher = index >= finisherIndex

	api.Timeline.play("Melee", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		-- The melee kit belongs to no school, so it is drawn in the world's own colour rather than in a
		-- pigment: art bible rule 2 says a colour on screen names a school, and this one names none.
		Color = WHITE,
		-- The finisher is the same stroke, heavier. One timeline, two weights.
		Scale = if finisher then 1.4 else 1,
		Follow = casterRoot(packet),
	})

	if finisher then
		api.Sound.play("MeleeFinisher", packet.Origin)
	else
		api.Sound.play("Melee" .. math.clamp(index, 1, MELEE_SFX_VARIANTS), packet.Origin)
	end

	-- Felt by whoever threw it, whether or not it connects. A whiff that feels like nothing is most of
	-- why melee read as weightless.
	if packet.Caster == api.LocalUserId then
		api.Feel.fovPunch(if finisher then FeelConfig.Fov.HeavyCastImpulse else FeelConfig.Fov.CastImpulse)
		api.Feel.shake(if finisher then "Melee" else "Cast")
		api.Feel.haptic("Cast")
	end
end

-- Streak left behind by a dash.
VfxLibrary.Dash = function(packet: Packet, _trove: TroveType, api: Api)
	-- The dodge is the third most repeated action in a match, and the plan sequences the pass by exactly
	-- that. What it replaced slid a trail along at a constant speed beside a body that was decelerating,
	-- which is the most visible way there is to make a dash look fake; the trail now rides the real root
	-- and the body follows FeelMath.impulseSpeed, so the two agree.
	local root = casterRoot(packet)
	api.Timeline.play("Dash", {
		Origin = if root ~= nil then root.Position else packet.Origin,
		Direction = directionOf(packet),
		Color = api.PigmentColor("Verdigris"),
		Follow = root,
	})
	api.Sound.play("Dash", packet.Origin)
end

VfxLibrary.BlockStart = function(packet: Packet, trove: TroveType, api: Api)
	shieldFlash(trove, packet.Origin, 0.4, 0.3)
	api.Sound.play("BlockStart", packet.Origin)
end

VfxLibrary.BlockHit = function(packet: Packet, trove: TroveType, api: Api)
	shieldFlash(trove, packet.Origin, 0.15, 0.3)
	api.Sound.play("ImpactBlock", packet.Origin)
end

-- Cracking flash when a guard is broken.
VfxLibrary.GuardBreak = function(packet: Packet, trove: TroveType, _api: Api)
	local crack = newPart(trove, "GuardBreak", {
		Shape = Enum.PartType.Ball,
		Color = GUARD_BREAK_COLOR,
		Size = Vector3.one * 2,
		CFrame = CFrame.new(packet.Origin),
	})
	play(trove, crack, 0.35, { Size = Vector3.one * 7, Transparency = 1 })
	local shards = newEmitter(crack, {
		Color = GUARD_BREAK_COLOR,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(15, 25),
		Size = NumberSequence.new(0.6, 0),
		Acceleration = Vector3.new(0, -30, 0),
	})
	burst(shards, 24)
end

----------------------------------------------------------------
-- World Boss (docs/GAME_DESIGN.md §7)
----------------------------------------------------------------

-- Floor of the boss arena. The server sends it in the packet: the boss body is 14 studs tall and a
-- downward probe started at its centre would begin inside it, so the ground probe is only a fallback.
local function bossGround(packet: Packet): Vector3
	local params = packet.Params
	if params ~= nil and isFinite(params.Ground) then
		return Vector3.new(packet.Origin.X, params.Ground, packet.Origin.Z)
	end
	return groundAt(packet.Origin)
end

-- Warning window the server announced, bounded so the whole effect (warning plus impact) fits inside
-- the packet lifetime.
local function bossTelegraph(packet: Packet): number
	return clampLifetime(numberParam(packet, "Telegraph", 1), BOSS_IMPACT_SECONDS * 2)
end

-- Flat disc painted on the arena floor: the shape of a Circle attack and the two radii of a Ring one.
local function bossDisc(trove: TroveType, ground: Vector3, radius: number, color: Color3, lift: number): Part
	return newPart(trove, "BossWarning", {
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Size = Vector3.new(BOSS_DISC_THICKNESS_STUDS, radius * 2, radius * 2),
		Transparency = BOSS_WARNING_TRANSPARENCY,
		CFrame = CFrame.new(ground + Vector3.new(0, BOSS_DISC_LIFT_STUDS + lift, 0)) * LYING_CYLINDER,
	})
end

-- Fills the warning paint over the telegraph window, then clears it when the attack lands.
local function bossFill(trove: TroveType, parts: { Part }, seconds: number)
	for _, part in ipairs(parts) do
		play(trove, part, seconds, { Transparency = BOSS_WARNING_PEAK_TRANSPARENCY }, Enum.EasingStyle.Linear)
	end
	after(trove, seconds, function()
		fadeParts(trove, parts, BOSS_IMPACT_SECONDS)
	end)
end

-- The hit itself: a shockwave running out to the damaged radius, dust, impact sound and a shake that
-- fades with the distance.
local function bossImpact(trove: TroveType, api: Api, ground: Vector3, radius: number, shake: number)
	local wave = newPart(trove, "BossImpact", {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Slate,
		Color = BOSS_DANGER_COLOR,
		Size = Vector3.new(BOSS_DISC_THICKNESS_STUDS, 2, 2),
		Transparency = 0.2,
		CFrame = CFrame.new(ground + Vector3.new(0, BOSS_DISC_LIFT_STUDS, 0)) * LYING_CYLINDER,
	})
	play(trove, wave, BOSS_IMPACT_SECONDS, {
		Size = Vector3.new(BOSS_DISC_THICKNESS_STUDS, radius * 2, radius * 2),
		Transparency = 1,
	})
	local dust = newEmitter(wave, {
		Color = SMOKE_COLOR,
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(radius * 0.6, radius),
		Size = NumberSequence.new(2, 0),
		Spread = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -20, 0),
	})
	burst(dust, 24)
	api.Sound.play("ImpactExplosion", ground)
	shakeNear(api, ground, shake)
end

-- Circle attacks (Slam, and Fury with its wider disc and harder landing): the whole area under the
-- boss is painted, then it drops.
local function bossCircleAttack(packet: Packet, trove: TroveType, api: Api, shake: number)
	local radius = math.max(numberParam(packet, "Radius", 20), 1)
	local ground = bossGround(packet)
	local seconds = bossTelegraph(packet)
	bossFill(trove, { bossDisc(trove, ground, radius, BOSS_DANGER_COLOR, 0) }, seconds)
	after(trove, seconds, function()
		bossImpact(trove, api, ground, radius, shake)
	end)
end

VfxLibrary.BossSlam = function(packet: Packet, trove: TroveType, api: Api)
	bossCircleAttack(packet, trove, api, CombatConfig.Hit.CameraShakeSmall)
end

VfxLibrary.BossFury = function(packet: Packet, trove: TroveType, api: Api)
	bossCircleAttack(packet, trove, api, CombatConfig.Hit.CameraShakeLarge)
end

-- Sweep: a wedge in front of the boss, drawn as segments that widen with the distance exactly like the
-- server opens it (WorldBossMode.isInShape), so standing at the edge really is standing at the edge.
VfxLibrary.BossSweep = function(packet: Packet, trove: TroveType, api: Api)
	local radius = math.max(numberParam(packet, "Radius", 14), 1)
	local range = math.max(numberParam(packet, "Range", 40), 1)
	local direction = flatDirectionOf(packet)
	local ground = bossGround(packet)
	local seconds = bossTelegraph(packet)
	local step = range / BOSS_CONE_SEGMENTS

	local segments: { Part } = {}
	for index = 1, BOSS_CONE_SEGMENTS do
		local forward = (index - 0.5) * step
		local center = ground + direction * forward + Vector3.new(0, BOSS_DISC_LIFT_STUDS, 0)
		segments[index] = newPart(trove, "BossWarning", {
			Color = BOSS_DANGER_COLOR,
			Size = Vector3.new(math.max(radius * (forward / range), 1) * 2, BOSS_DISC_THICKNESS_STUDS, step),
			Transparency = BOSS_WARNING_TRANSPARENCY,
			CFrame = CFrame.lookAt(center, center + direction),
		})
	end
	bossFill(trove, segments, seconds)
	after(trove, seconds, function()
		bossImpact(trove, api, ground + direction * (range / 2), radius, CombatConfig.Hit.CameraShakeSmall)
	end)
end

-- Eruption: everything between the safe centre and the outer reach goes up. The safe disc keeps its
-- own colour for the whole warning, so the way out is readable at a glance.
VfxLibrary.BossEruption = function(packet: Packet, trove: TroveType, api: Api)
	local inner = math.max(numberParam(packet, "Radius", 16), 1)
	local outer = math.max(numberParam(packet, "Range", 46), inner + 1)
	local ground = bossGround(packet)
	local seconds = bossTelegraph(packet)
	local danger = bossDisc(trove, ground, outer, BOSS_DANGER_COLOR, 0)
	local safe = bossDisc(trove, ground, inner, BOSS_SAFE_COLOR, BOSS_DISC_LIFT_STUDS)
	bossFill(trove, { danger, safe }, seconds)
	after(trove, seconds, function()
		local distance = (inner + outer) / 2
		for index = 1, BOSS_PILLAR_COUNT do
			local angle = (index - 1) * (2 * math.pi / BOSS_PILLAR_COUNT)
			local base = ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local pillar = newPart(trove, "BossPillar", {
				Material = Enum.Material.Slate,
				Color = BOSS_DANGER_COLOR,
				Size = Vector3.new(BOSS_PILLAR_WIDTH_STUDS, 1, BOSS_PILLAR_WIDTH_STUDS),
				Transparency = 0.1,
				CFrame = CFrame.new(base),
			})
			play(trove, pillar, BOSS_IMPACT_SECONDS, {
				Size = Vector3.new(BOSS_PILLAR_WIDTH_STUDS, outer / 2, BOSS_PILLAR_WIDTH_STUDS),
				CFrame = CFrame.new(base + Vector3.new(0, outer / 4, 0)),
				Transparency = 1,
			})
		end
		bossImpact(trove, api, ground, outer, CombatConfig.Hit.CameraShakeLarge)
	end)
end

-- The boss lands: a column of energy at the centre of the arena and a shockwave on the floor.
VfxLibrary.BossSpawn = function(packet: Packet, trove: TroveType, api: Api)
	local height = math.max(numberParam(packet, "Height", 14), 1)
	local radius = math.max(numberParam(packet, "Radius", 4), 1)
	local ground = bossGround(packet)

	local column = newPart(trove, "BossSpawn", {
		Shape = Enum.PartType.Cylinder,
		Color = BOSS_ENERGY_COLOR,
		Size = Vector3.new(height * 2, radius, radius),
		Transparency = 0.15,
		CFrame = CFrame.new(ground + Vector3.new(0, height, 0)) * LYING_CYLINDER,
	})
	play(trove, column, BOSS_SPAWN_SECONDS, {
		Size = Vector3.new(height * 2, radius * 5, radius * 5),
		Transparency = 1,
	})
	local motes = newEmitter(column, {
		Color = BOSS_ENERGY_COLOR,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(6, 14),
		Size = NumberSequence.new(1.4, 0),
		Acceleration = Vector3.new(0, 8, 0),
	})
	burst(motes, 28)
	bossImpact(trove, api, ground, radius * 4, CombatConfig.Hit.CameraShakeLarge)
end

-- The boss goes down: its energy collapses into the floor, then blows out across the arena.
VfxLibrary.BossDefeated = function(packet: Packet, trove: TroveType, api: Api)
	local height = math.max(numberParam(packet, "Height", 14), 1)
	local radius = math.max(numberParam(packet, "Radius", 4), 1)
	local ground = bossGround(packet)
	local collapse = BOSS_DEFEAT_SECONDS * BOSS_DEFEAT_COLLAPSE_FACTOR

	local core = newPart(trove, "BossCore", {
		Shape = Enum.PartType.Ball,
		Color = BOSS_ENERGY_COLOR,
		Size = Vector3.one * radius * 2,
		Transparency = 0.1,
		CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0)),
	})
	play(trove, core, collapse, { Size = Vector3.one, CFrame = CFrame.new(ground) }, Enum.EasingStyle.Back)
	after(trove, collapse, function()
		play(trove, core, BOSS_DEFEAT_SECONDS - collapse, { Size = Vector3.one * radius * 8, Transparency = 1 })
		local shards = newEmitter(core, {
			Color = BOSS_ENERGY_COLOR,
			Lifetime = NumberRange.new(0.6, 1.2),
			Speed = NumberRange.new(20, 40),
			Size = NumberSequence.new(1.2, 0),
			Acceleration = Vector3.new(0, -25, 0),
		})
		burst(shards, 36)
		bossImpact(trove, api, ground, radius * 6, CombatConfig.Hit.CameraShakeLarge)
	end)
end

return VfxLibrary
