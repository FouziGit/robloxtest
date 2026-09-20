--!strict
-- VfxLibrary: client renderers for the Vfx / VfxReliable packets broadcast by the server. One function
-- per packet Id, called by VfxController with a fresh trove that is destroyed after the packet lifetime.
-- Every part, connection and delayed thread is tracked by that trove and nothing yields on the caller
-- thread. What remains imperative here is the guard kit and the few renderers that have to decide
-- something before they play: everything else is a timeline in Config/VfxTimelineConfig, played through
-- Api.Timeline, and a renderer's whole job is to say where it happened, which way it was aimed, in what
-- colour, and against what shape.
-- The server never builds visuals; it only sends {Id, Origin, Direction, Caster, Targets, Params}.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local FeelConfig = require(Shared.Config.FeelConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Trove = require(Packages.Trove)
local VfxTimelineConfig = require(Shared.Config.VfxTimelineConfig)

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
	PigmentColor: (pigment: string) -> Color3,
	LocalCharacter: () -> Model?,
	-- The Feel controller, untyped here on purpose: this module is required by the client only, and a
	-- concrete type would make ReplicatedStorage depend on a controller in StarterPlayerScripts.
	Feel: any,
	-- The timeline runtime. A reworked effect declares its layers in Config/VfxTimelineConfig and
	-- plays them through this instead of building instances by hand.
	Timeline: any,
	LocalUserId: number,
	-- The model of a player by user id, for effects that have to adorn the person who was hit rather
	-- than draw at a point in space. nil for a training dummy or an enemy, which has no player.
	CharacterOf: (userId: number) -> Model?,
}

-- What api.Timeline.play takes. Written here rather than imported because VfxTimeline lives in
-- StarterPlayerScripts and this module is required from ReplicatedStorage -- the same reason Api.Timeline
-- is untyped -- and a renderer that hands one of these around needs to say what it is handing around.
type TimelineContext = {
	Origin: Vector3,
	Direction: Vector3,
	Color: Color3,
	Scale: number?,
	Window: number?,
	Radius: number?,
	Reach: number?,
	Follow: BasePart?,
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
-- Brand's blast radius (GlyphConfig), which the Explosion timeline is authored at. A packet carrying
-- a different radius scales the whole timeline by the ratio.
local DEFAULT_BLAST_RADIUS = 7
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local WHITE = Color3.fromRGB(255, 245, 220)
local SHIELD_COLOR = Color3.fromRGB(120, 190, 255)
local GUARD_BREAK_COLOR = Color3.fromRGB(255, 120, 90)

local MELEE_SFX_VARIANTS = 3 -- SoundConfig has Melee1..Melee3 plus MeleeFinisher

-- L'Effacement (docs/GAME_DESIGN.md §7). Red is danger to you whatever painted it, which is the same rule
-- HIT_TAKEN_COLOR follows; green is the one place inside an attack that it does not reach.
local ERASURE_DANGER_COLOR = Color3.fromRGB(255, 96, 72)
local ERASURE_SAFE_COLOR = Color3.fromRGB(110, 210, 150)
-- The boss itself is the colour of the page it leaves behind: vélin (docs/ART_BIBLE.md). It is the only
-- thing in the game tinted by the paper instead of by a pigment, which is the point -- it is what comes to
-- erase the page. What it replaced was a purple energy column, and a purple energy column is the single
-- most copy-pasteable visual in Roblox.
local ERASURE_COLOR = Color3.fromRGB(232, 224, 206)
-- The body height the spawn and defeat timelines are drawn against (WorldBossConfig.Boss.BodySize.Y at the
-- time they were authored). The renderer scales them by the height the packet carries, so a boss built
-- bigger arrives bigger instead of arriving wrong.
local AUTHORED_BOSS_HEIGHT_STUDS = 14

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

-- The root of the player who sent this packet, for a timeline that follows the caster's body.
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
-- L'Effacement (docs/GAME_DESIGN.md §7)
----------------------------------------------------------------

-- Floor of the boss arena. The server sends it in the packet: the boss body is fourteen studs tall and a
-- downward probe started at its centre would begin inside it, so the probe here is only a fallback. The
-- timeline is played AT the floor rather than at the body, because everything it draws is on the ground.
local function bossGround(packet: Packet): Vector3
	local params = packet.Params
	if params ~= nil and isFinite(params.Ground) then
		return Vector3.new(packet.Origin.X, params.Ground, packet.Origin.Z)
	end
	return groundAt(packet.Origin)
end

-- What the Erasure leaves behind: bare page, in the colour of the page, laid where the ink was once the
-- damage is over. The attack's own play cannot draw it, because that play carries the colour of danger
-- and a timeline carries one colour (art bible rule 2), so it is a second play scheduled on the attack's
-- own Residue phase -- the same seam the safe disc uses.
local function scourAfter(
	id: string,
	context: TimelineContext,
	trove: TroveType,
	api: Api,
	origin: Vector3,
	radius: number
)
	local residueAt = VfxTimelineConfig.phaseAt(id, "Residue", context.Window)
	if residueAt == nil then
		return
	end
	after(trove, residueAt, function()
		api.Timeline.play("BossScour", {
			Origin = origin,
			Direction = context.Direction,
			Color = ERASURE_COLOR,
			Radius = radius,
		})
	end)
end

-- One of L'Effacement's four attacks, which are the only effects in Vellum whose visual is load-bearing:
-- the paint on the floor IS the rule, and six players read it at once.
--
-- So nothing about the shape is decided here. The window the server is really waiting (Params.Telegraph,
-- between 0.6 and 2 seconds depending on the attack and on the phase of the fight) and the shape it will
-- damage both come off the packet, and the timeline measures itself against them
-- (Config/VfxTimelineConfig): a radius changed in WorldBossConfig moves the paint with it, and
-- tests/BossTelegraph.spec.luau samples the shipped numbers to prove the paint covers the damage.
--
-- The impact sound is scheduled on the same resolved window the visual uses, through
-- VfxTimelineConfig.phaseAt, rather than on the raw parameter. They clamp the same way, so the hit can
-- never be heard before it is seen -- and never heard at all for a timeline that was not drawn.
local function playBossAttack(id: string, packet: Packet, trove: TroveType, api: Api): TimelineContext?
	local ground = bossGround(packet)
	local radius = math.max(numberParam(packet, "Radius", 20), 1)
	local window = numberParam(packet, "Telegraph", 1)
	local context: TimelineContext = {
		Origin = ground,
		Direction = flatDirectionOf(packet),
		Color = ERASURE_DANGER_COLOR,
		Window = window,
		Radius = radius,
		-- A Circle attack reaches no further than its radius and the server sends the two equal. Holding
		-- the reach at or above the radius means a timeline measuring either one can never draw a shape
		-- turned inside out.
		Reach = math.max(numberParam(packet, "Range", radius), radius),
	}
	if not api.Timeline.play(id, context) then
		return nil
	end
	local impactAt = VfxTimelineConfig.phaseAt(id, "Impact", window)
	if impactAt ~= nil then
		after(trove, impactAt, function()
			api.Sound.play("ImpactExplosion", ground)
		end)
	end
	return context
end

VfxLibrary.BossSlam = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossSlam", packet, trove, api)
	if context ~= nil then
		scourAfter("BossSlam", context, trove, api, context.Origin, context.Radius or 1)
	end
end

VfxLibrary.BossFury = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossFury", packet, trove, api)
	if context ~= nil then
		scourAfter("BossFury", context, trove, api, context.Origin, context.Radius or 1)
	end
end

VfxLibrary.BossSweep = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossSweep", packet, trove, api)
	if context ~= nil then
		-- A blot at mid-stroke: the residue is not the rule, so a disc over a wedge is allowed to spill.
		local reach = context.Reach or 1
		local origin = context.Origin + context.Direction * (reach * 0.5)
		scourAfter("BossSweep", context, trove, api, origin, context.Radius or 1)
	end
end

VfxLibrary.BossEruption = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossEruption", packet, trove, api)
	if context == nil then
		return
	end
	-- The safe middle, in the one colour on this floor that does not mean danger. It is a second play and
	-- not a layer because a timeline carries a single colour (art bible rule 2: one glyph, one pigment, one
	-- colour), and the boss is not a reason to break the rule that keeps a glyph from ever showing two
	-- pigments at once. It takes the same window, so the bare page fills for exactly as long as there is
	-- still time to get inside it.
	local safe = table.clone(context)
	safe.Color = ERASURE_SAFE_COLOR
	api.Timeline.play("BossEruptionSafe", safe)
	-- The ring was erased out to the reach; the safe disc's own residue stays on top of the scour.
	scourAfter("BossEruption", context, trove, api, context.Origin, context.Reach or 1)
end

-- The arrival and the end. They damage nobody, so they measure nothing: they are authored in studs against
-- the body the config ships and scaled by the height the packet carries.
local function playBossEvent(id: string, packet: Packet, trove: TroveType, api: Api)
	local ground = bossGround(packet)
	local height = math.max(numberParam(packet, "Height", AUTHORED_BOSS_HEIGHT_STUDS), 1)
	api.Timeline.play(id, {
		Origin = ground,
		Direction = flatDirectionOf(packet),
		Color = ERASURE_COLOR,
		Scale = height / AUTHORED_BOSS_HEIGHT_STUDS,
	})
	local impactAt = VfxTimelineConfig.phaseAt(id, "Impact", nil)
	if impactAt ~= nil then
		after(trove, impactAt, function()
			api.Sound.play("ImpactExplosion", ground)
		end)
	end
end

VfxLibrary.BossSpawn = function(packet: Packet, trove: TroveType, api: Api)
	playBossEvent("BossSpawn", packet, trove, api)
end

VfxLibrary.BossDefeated = function(packet: Packet, trove: TroveType, api: Api)
	playBossEvent("BossDefeated", packet, trove, api)
end

return VfxLibrary
