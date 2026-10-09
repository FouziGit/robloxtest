--!strict
-- VfxLibrary: client renderers for the Vfx / VfxReliable packets broadcast by the server. One function
-- per packet Id, called by VfxController with a fresh trove that is destroyed after the packet lifetime.
-- Every part, connection and delayed thread is tracked by that trove and nothing yields on the caller
-- thread. What remains imperative here is the guard kit and the few renderers that have to decide
-- something before they play: everything else is a timeline in Config/VfxTimelineConfig, played through
-- Api.Timeline, and a renderer's whole job is to say where it happened, which way it was aimed, in what
-- colour, and against what shape.
-- The server never builds visuals; it only sends {Id, Origin, Direction, Caster, Targets, Params}.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local AssetIds = require(Shared.Config.AssetIds)
local CombatConfig = require(Shared.Config.CombatConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local FeelConfig = require(Shared.Config.FeelConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Palette = require(Shared.Util.Palette)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Trove = require(Packages.Trove)
local VfxConfig = require(Shared.Config.VfxConfig)
local VfxTimelineConfig = require(Shared.Config.VfxTimelineConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

export type Packet = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}

export type Api = {
	Sound: { play: (sfxId: string, position: Vector3?, options: any?) -> (), duck: (seconds: number) -> () },
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
	Ink: Color3?,
	Scale: number?,
	Window: number?,
	Radius: number?,
	Reach: number?,
	Pigment: string?,
	Shot: string?,
	Follow: BasePart?,
	Hand: BasePart?,
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
	Lifetime: NumberRange?,
	Speed: NumberRange?,
	Size: NumberSequence?,
	Transparency: NumberSequence?,
	Spread: Vector2?,
	Acceleration: Vector3?,
}

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
-- The music dips under a heavy hit for this long (docs/JUICE_PLAN.md phase 5: ducking on the heavy
-- impacts). Short: a duck that outlives the hit-stop is a mixer move, not a blow. The bar is above the
-- shake's: Brand is heavy enough to shake the camera and not heavy enough to be a mixer event, or the
-- music would dip on the most-thrown projectile in the game.
local HEAVY_HIT_DUCK_SECONDS = 0.45
local DUCK_HIT_DAMAGE = 35
-- Damage you took is red, whatever pigment dealt it (docs/ART_BIBLE.md: red means danger to you).
local HIT_TAKEN_COLOR = Color3.fromRGB(217, 58, 34)
-- Brand's blast radius (GlyphConfig), which the Explosion timeline is authored at. A packet carrying
-- a different radius scales the whole timeline by the ratio.
local DEFAULT_BLAST_RADIUS = 7
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local WHITE = Color3.fromRGB(255, 245, 220)
-- The kit -- the punch, its hit, the dodge -- belongs to no school, so it is drawn in the page's own
-- charcoal (D-114, the developer's choice): white was nearly invisible on vellum and is the colour art
-- bible rule 7 keeps for "cannot be hurt", and the dodge's Verdigris named a school it is not.
local KIT_INK = Palette.rgb(WorldConfig.Colors.Ink)
-- What a fist's hit tells the two people in it. The number in the page's vellum, on its charcoal
-- stroke: charcoal on charcoal was no number at all (review). The outline through a crowd in the wash
-- between the two: vellum vanished against the page behind the target and turned it white, charcoal
-- against the ink cover walls (review).
local KIT_NUMBER = Palette.rgb(WorldConfig.Colors.Page)
local KIT_OUTLINE = Palette.rgb(CosmeticConfig.Tones.Wash)
local SHIELD_COLOR = Color3.fromRGB(120, 190, 255)
local GUARD_BREAK_COLOR = Color3.fromRGB(255, 120, 90)

local MELEE_SFX_VARIANTS = 3 -- SoundConfig has Melee1..Melee3 plus MeleeFinisher

-- L'Effacement (docs/GAME_DESIGN.md §7). Red is danger to you whatever painted it, which is the same rule
-- HIT_TAKEN_COLOR follows; green is the one place inside an attack that it does not reach.
local ERASURE_DANGER_COLOR = Color3.fromRGB(255, 96, 72)
local ERASURE_SAFE_COLOR = Color3.fromRGB(110, 210, 150)
-- The Erasure's light and its dust are the colour of the page it leaves behind: vélin (docs/ART_BIBLE.md).
-- It is the only thing in the game tinted by the paper instead of by a pigment, which is the point -- it is
-- what comes to erase the page. What it replaced was a purple energy column, and a purple energy column is
-- the single most copy-pasteable visual in Roblox.
local ERASURE_COLOR = Color3.fromRGB(232, 224, 206)
-- What it leaves ON the floor, which since the world became a page (D-86) can no longer be the page's own
-- colour: its seals and rings are drawn in ink, and what it erased stays as the grey ghost of what was
-- written there. Both come from WorldConfig, so the floor and the marks on it cannot be set from two
-- places again -- which is exactly how every mark of the arrival, the phases and the end came to be
-- painted in the colour of the floor they were painted on.
local ERASURE_INK = Palette.world(WorldConfig.Erasure.Mark)
local ERASURE_ERASED = Palette.world(WorldConfig.Erasure.Erased)
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

local INK_RGB = WorldConfig.Colors.Ink
local PAGE_RGB = WorldConfig.Colors.Page

-- A glyph's colour as its caster wears it: the pigment, moved by the skin shade the server wrote into the
-- packet (GlyphService). PigmentConfig.shade clamps it to the measured range, so even a packet with an
-- absurd shade cannot move a spell out of its school (docs/ART_BIBLE.md rule 2).
local function glyphColor(pigment: string, packet: Packet, api: Api): Color3
	local base = api.PigmentColor(pigment)
	local shade = numberParam(packet, "Shade", 0)
	if shade == 0 then
		return base
	end
	local rgb = PigmentConfig.shade({ base.R * 255, base.G * 255, base.B * 255 }, shade, INK_RGB, PAGE_RGB)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
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
	-- The page's one material by default (docs/ART_BIBLE.md: no metal, no glass, no neon). Neon and
	-- ForceField add light, and on a cream page added light is the one colour that cannot be seen --
	-- the same finding as VfxConfig.LightEmission.
	part.Material = props.Material or Palette.material()
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
	-- Never on its own: it only bursts, and only what the screen's budget grants (burst below).
	emitter.Rate = 0
	emitter.Lifetime = props.Lifetime or NumberRange.new(0.4, 0.8)
	emitter.Speed = props.Speed or NumberRange.new(4, 10)
	emitter.Size = props.Size or NumberSequence.new(1, 0)
	emitter.Transparency = props.Transparency or NumberSequence.new(0.2, 1)
	emitter.SpreadAngle = props.Spread or Vector2.new(180, 180)
	emitter.Acceleration = props.Acceleration or Vector3.zero
	emitter.LightEmission = VfxConfig.LightEmission
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = parent
	return emitter
end

-- As many of `count` particles as the screen's particle budget still holds (VfxTimeline.grant), each living up to
-- the emitter's longest life.
local function burst(emitter: ParticleEmitter, count: number, api: Api)
	local granted = api.Timeline.grant(math.min(count, MAX_PARTICLE_BURST), emitter.Lifetime.Max)
	if granted > 0 then
		emitter:Emit(granted)
	end
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
		Color = SHIELD_COLOR,
		Size = Vector3.one * 6,
		Transparency = startTransparency,
		CFrame = CFrame.new(origin),
	})
	play(trove, shield, seconds, { Transparency = 1, Size = Vector3.one * 7.5 })
end

-- The hand the caster throws with, for the layers born in it (Layer.Anchor).
local function casterHand(packet: Packet): BasePart?
	local root = casterRoot(packet)
	local character = if root ~= nil then root.Parent else nil
	local hand = if character ~= nil then character:FindFirstChild(VfxConfig.Hand) else nil
	return if hand ~= nil and hand:IsA("BasePart") then hand else nil
end

-- Casting flash at the caster, colored by the glyph pigment, with its cast sound.
VfxLibrary.Cast = function(packet: Packet, _trove: TroveType, api: Api)
	-- What this replaced was one ball that grew and one spark burst, played identically by all twenty
	-- glyphs: two layers, no wind-up, nothing left behind, and no way to tell a Cinnabar cast from an
	-- Orpiment one except the tint. docs/JUICE_AUDIT.md lists it as the single worst offender in the game.
	--
	-- It is now the Cast timeline: the glyph lighting in the casting hand, a seal snapping open round it
	-- and folding as the spell leaves (D-119). The renderer's whole job is to say who cast it, with which
	-- hand, and in what pigment.
	local pigment = stringParam(packet, "Pigment", "")
	api.Timeline.play("Cast", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(pigment, packet, api),
		Pigment = pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
	})
	-- The field of view and the pad belong to the person who cast it, and to nobody else. The timeline's
	-- own shake layer is distance-attenuated, so bystanders feel the cast without being punched by it.
	if packet.Caster == api.LocalUserId then
		api.Feel.fovPunch(FeelConfig.Fov.CastImpulse)
		api.Feel.haptic("Cast")
	end
end

-- Brand (Cinnabar, projectile). The first glyph every player learns and the one they throw most.
--
-- What it replaced was a ball wearing Roblox's own Fire class, flying a straight line at a constant speed
-- for a full second. Its detonation is a separate packet -- the server emits Explosion when it lands --
-- and that split is correct rather than accidental: the projectile does not know where it will end.
-- The name a thrown Brand is known by between its throw and its burst: its thrower and the server's shot
-- number (GlyphEffects.Brand, D-114). nil for a packet that carries neither -- a Blot's burst, say.
local function shotKey(packet: Packet): string?
	local params = packet.Params
	local shot = if params ~= nil then params.Shot else nil
	local caster = packet.Caster
	if type(shot) ~= "number" or type(caster) ~= "number" then
		return nil
	end
	return string.format("%d:%d", caster, shot)
end

VfxLibrary.Brand = function(packet: Packet, _trove: TroveType, api: Api)
	api.Timeline.play("Brand", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor("Cinnabar", packet, api),
		Pigment = "Cinnabar",
		Shade = numberParam(packet, "Shade", 0),
		Shot = shotKey(packet),
		Hand = casterHand(packet),
	})
end

-- A thrown Brand that never burst: the drawn one comes down where the real one was, instead of flying on
-- alone to the end of its range.
VfxLibrary.Fizzle = function(packet: Packet, _trove: TroveType, api: Api)
	local shot = shotKey(packet)
	if shot ~= nil then
		api.Timeline.land(shot, packet.Origin)
	end
end

-- The detonation every exploding projectile shares. The server sends the blast radius it actually used,
-- so the visual is the size of the damage rather than a constant that happens to look right for one
-- glyph: a blast drawn smaller than it hurts is the most expensive lie a fighting game can tell.
VfxLibrary.Explosion = function(packet: Packet, _trove: TroveType, api: Api)
	local radius = numberParam(packet, "Radius", numberParam(packet, "BlastRadius", DEFAULT_BLAST_RADIUS))
	local pigment = stringParam(packet, "Pigment", "")
	-- The Brand that burst here comes down here, however far short of its range (D-114).
	local shot = shotKey(packet)
	if shot ~= nil then
		api.Timeline.land(shot, packet.Origin)
	end
	api.Timeline.play("Explosion", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(pigment, packet, api),
		Pigment = pigment,
		Shade = numberParam(packet, "Shade", 0),
		Scale = radius / DEFAULT_BLAST_RADIUS,
		-- The volumes are sized to the radius itself: the ensō's ink stops exactly where the damage does.
		Radius = radius,
	})
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
local function playGlyph(id: string, packet: Packet, api: Api): number?
	local def = GlyphConfig.ById[id]
	local pigment = if def ~= nil then def.Pigment else stringParam(packet, "Pigment", "")
	-- The radius the server struck with, when the packet carries one: what a zone's edge is drawn at.
	local radius = numberParam(packet, "Radius", 0)
	local _, playId = api.Timeline.play(id, {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(pigment, packet, api),
		Pigment = pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Radius = if radius > 0 then radius else nil,
		-- A thrown glyph's name (the Blot's, D-123): its burst lands the drawn one where it burst.
		Shot = shotKey(packet),
	})
	return playId
end

-- A charge held for exactly the time the server waits (GlyphEffects' charge, D-141): the Anticipation of `id`
-- lasts the glyph's Params.Windup (tests/Flight.spec.luau), on the caster's body, which may walk while it
-- winds. A lane it paints starts where the server's will: SpawnOffset ahead, Range long, both measured at
-- the press, and Radius either side of it, the width the release strikes.
local function playCharge(id: string, glyphId: string, packet: Packet, api: Api): number?
	local def = GlyphConfig.ById[glyphId]
	local direction = directionOf(packet)
	local radius = numberParam(packet, "Radius", 0)
	local _, playId = api.Timeline.play(id, {
		Origin = packet.Origin + direction * numberParam(packet, "SpawnOffset", 0),
		Direction = direction,
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Reach = math.max(numberParam(packet, "Range", 1), 1),
		Radius = if radius > 0 then radius else nil,
	})
	return playId
end

-- The play each caster has running of an effect the server may still take back (GlyphEffects' retract, D-141):
-- a charge broken before its release, a rush a dash ended, a zone or a frame its caster stopped. By caster, then
-- by effect: a caster has one of each at a time. Cut and forgotten with the player.
local retractable: { [number]: { [string]: number? } } = {}
-- The runtime those plays were given to (Api.Timeline), for the one cut no packet asks for: a caster who leaves.
local retractRuntime: any = nil

-- Keeps `playId` as the play of `id` that `packet`'s caster may have taken back.
local function remember(id: string, packet: Packet, playId: number?)
	local caster = packet.Caster
	if type(caster) ~= "number" then
		return
	end
	local plays = retractable[caster]
	if plays == nil then
		plays = {}
		retractable[caster] = plays
	end
	plays[id] = playId
end

-- Whether `packet` is the server taking back its caster's play of `id` (Params.Cancel): that play is cut on the
-- spot -- nothing of it still to come is drawn, and what it has on screen goes -- and nothing else is played.
local function retracted(id: string, packet: Packet, api: Api): boolean
	retractRuntime = api.Timeline
	local params = packet.Params
	if params == nil or params.Cancel ~= true then
		return false
	end
	local caster = packet.Caster
	local plays = if type(caster) == "number" then retractable[caster] else nil
	local playId = if plays ~= nil then plays[id] else nil
	if plays ~= nil then
		plays[id] = nil
	end
	if playId ~= nil then
		api.Timeline.cancel(playId)
	end
	return true
end

-- A caster who leaves is forgotten before the server's retraction of what he left running can arrive: it comes on
-- the effect's next tick, and names somebody this screen no longer keeps plays for. The server stops each of them
-- (a caster gone is a caster stopped), so they are cut here, now.
Players.PlayerRemoving:Connect(function(player: Player)
	local plays = retractable[player.UserId]
	retractable[player.UserId] = nil
	if plays ~= nil and retractRuntime ~= nil then
		for _, playId in pairs(plays) do
			retractRuntime.cancel(playId)
		end
	end
end)

VfxLibrary.Wash = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Wash", packet, api)
end

VfxLibrary.Serif = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Serif", packet, api)
end

-- Drawn at the centre the server damaged: it sends the caster's position and the offset it struck at
-- along the aim (GlyphEffects.Sweep), and a wipe drawn round the caster is a wipe of nobody (D-119).
VfxLibrary.Sweep = function(packet: Packet, _trove: TroveType, api: Api)
	local centre = packet.Origin + directionOf(packet) * numberParam(packet, "Offset", 0)
	local def = GlyphConfig.ById.Sweep
	api.Timeline.play("Sweep", {
		Origin = centre,
		Direction = directionOf(packet),
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Radius = numberParam(packet, "Radius", 12),
	})
end

-- The zone's edge is drawn at the radius the server drinks from (the packet's), not a constant. Taken back
-- when its caster stops it before its last drink: the pool no longer burns.
VfxLibrary.Bleed = function(packet: Packet, _trove: TroveType, api: Api)
	if retracted("Bleed", packet, api) then
		return
	end
	local def = GlyphConfig.ById.Bleed
	local _, playId = api.Timeline.play("Bleed", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Radius = numberParam(packet, "Radius", 9),
	})
	remember("Bleed", packet, playId)
end

-- The slab this packet announced: tagged glyph collision, named for the Margin, standing where the packet
-- says in plan (it rises, so its height is not yet the packet's).
local function marginSlab(origin: Vector3): BasePart?
	local glyphs = WorldConfig.Glyphs
	for _, tagged in ipairs(CollectionService:GetTagged(glyphs.CollisionTag)) do
		if tagged.Name == glyphs.WallName and tagged:IsA("BasePart") then
			local offset = (tagged.Position - origin) * Vector3.new(1, 0, 1)
			if offset.Magnitude < 0.5 then
				return tagged
			end
		end
	end
	return nil
end

local WALL_FACES =
	{ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }

-- The ink on the slab (VfxConfig.WallPaint): courses of brush strokes in the glyph's colour and the
-- page's grain under them, on every face. Parented to the slab, so they go when the server takes it.
local function paintSlab(slab: BasePart, color: Color3)
	local paint = VfxConfig.WallPaint
	local grainRgb =
		PigmentConfig.shade({ color.R * 255, color.G * 255, color.B * 255 }, paint.Grain.Shade, INK_RGB, PAGE_RGB)
	local grainColor = Color3.fromRGB(grainRgb[1], grainRgb[2], grainRgb[3])
	local stroke = AssetIds.Textures.BrushStroke.Id
	local grain = AssetIds.Textures.PaperGrain.Id
	for _, face in ipairs(WALL_FACES) do
		for _, course in ipairs(paint.Courses) do
			local texture = Instance.new("Texture")
			texture.Texture = stroke
			texture.Face = face
			texture.Color3 = color
			texture.Transparency = course.Transparency
			texture.StudsPerTileU = course.U
			texture.StudsPerTileV = course.V
			texture.OffsetStudsU = course.OffsetU
			texture.OffsetStudsV = course.OffsetV
			texture.Parent = slab
		end
		local texture = Instance.new("Texture")
		texture.Texture = grain
		texture.Face = face
		texture.Color3 = grainColor
		texture.Transparency = paint.Grain.Transparency
		texture.StudsPerTileU = paint.Grain.U
		texture.StudsPerTileV = paint.Grain.V
		texture.Parent = slab
	end
end

VfxLibrary.Margin = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Margin", packet, api)
	local def = GlyphConfig.ById.Margin
	local color = glyphColor(if def ~= nil then def.Pigment else "Umber", packet, api)
	local origin = packet.Origin
	-- The slab is parented before the packet is sent, but replication gives no promise that it lands
	-- first on every client: look again for a moment rather than leave a wall unpainted.
	task.spawn(function()
		local deadline = os.clock() + VfxConfig.WallPaint.FindSeconds
		repeat
			local slab = marginSlab(origin)
			if slab ~= nil then
				paintSlab(slab, color)
				return
			end
			task.wait()
		until os.clock() > deadline
	end)
end

-- Taken back when its caster stops it before its last tick: the ring round him no longer burns.
VfxLibrary.Scorch = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("Scorch", packet, api) then
		remember("Scorch", packet, playGlyph("Scorch", packet, api))
	end
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

-- On the one it caught (the packet's first target, where the server rooted it), or at the centre of the grab
-- when it caught nobody (D-123): a prison drawn beside its prisoner holds nobody.
VfxLibrary.Binding = function(packet: Packet, _trove: TroveType, api: Api)
	local targets = packet.Targets
	local caught = if targets ~= nil then targets[1] else nil
	local def = GlyphConfig.ById.Binding
	api.Timeline.play("Binding", {
		Origin = if typeof(caught) == "Vector3" then caught else packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
	})
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

-- Taken back when its caster stops it before its last tick: the storm no longer pulls.
VfxLibrary.Spiral = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("Spiral", packet, api) then
		remember("Spiral", packet, playGlyph("Spiral", packet, api))
	end
end

-- Taken back when its caster stops it before its last tick: the grain no longer slows.
VfxLibrary.Pounce = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("Pounce", packet, api) then
		remember("Pounce", packet, playGlyph("Pounce", packet, api))
	end
end

-- A line ruled from the muzzle to where the server's ray stopped (D-126): the packet's Origin is the caster
-- and its Range the length from SpawnOffset ahead of him, past the body it hit and up to the wall.
VfxLibrary.Strike = function(packet: Packet, _trove: TroveType, api: Api)
	local def = GlyphConfig.ById.Strike
	local direction = directionOf(packet)
	api.Timeline.play("Strike", {
		Origin = packet.Origin + direction * numberParam(packet, "SpawnOffset", 0),
		Direction = direction,
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Reach = math.max(numberParam(packet, "Range", def.Range), 1),
	})
end

-- A step to where the server put the body (D-126): Range is the distance it validated against walls and
-- ground, shorter than the glyph's reach whenever something was in the way.
VfxLibrary.Caret = function(packet: Packet, _trove: TroveType, api: Api)
	local def = GlyphConfig.ById.Caret
	api.Timeline.play("Caret", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Reach = math.max(numberParam(packet, "Range", def.Range), 1),
	})
end

-- Taken back when its caster stops it before its last tick: the mark no longer holds.
VfxLibrary.Watermark = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("Watermark", packet, api) then
		remember("Watermark", packet, playGlyph("Watermark", packet, api))
	end
end

-- Colophon is the one glyph whose packet carries a PATH rather than a point. The server chains from body
-- to body in one frame and sends Targets as one position per link, in the order the arcs fired. So the
-- visual is the signature ruled from the muzzle to the first body it struck (or to the wall, when it struck
-- nobody), then one stroke per JUMP, from each body to the next, each exactly as long as the jump (D-127).
-- It used to rule a fixed sixty studs from the caster and draw a stroke from every body toward the next --
-- the last one toward nothing -- a fixed twenty-six studs long: the contract its timeline describes was
-- never played.
VfxLibrary.Colophon = function(packet: Packet, _trove: TroveType, api: Api)
	local def = GlyphConfig.ById.Colophon
	local color = glyphColor(def.Pigment, packet, api)
	local shade = numberParam(packet, "Shade", 0)
	local muzzle = packet.Origin + directionOf(packet) * numberParam(packet, "SpawnOffset", 0)
	local points = packet.Targets or {}
	local first: Vector3? = points[1]
	local toFirst = if first ~= nil then first - muzzle else Vector3.zero
	local struck = toFirst.Magnitude > 1e-3
	api.Timeline.play("Colophon", {
		Origin = muzzle,
		Direction = if struck then toFirst.Unit else directionOf(packet),
		Color = color,
		Pigment = def.Pigment,
		Shade = shade,
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Reach = if struck then toFirst.Magnitude else math.max(numberParam(packet, "Range", def.Range), 1),
		Radius = def.Params.HitRadius,
	})
	for index = 1, #points - 1 do
		local from, to = points[index], points[index + 1]
		local jump = to - from
		if jump.Magnitude > 1e-3 then
			api.Timeline.play("ColophonLink", {
				Origin = from,
				Direction = jump.Unit,
				Color = color,
				-- The link's impact voice is the Colophon's own: an Orpiment glyph, whatever body it jumps to.
				Pigment = def.Pigment,
				Shade = shade,
				Reach = jump.Magnitude,
				Radius = def.Params.HitRadius,
			})
		end
	end
end

----------------------------------------------------------------
-- Second roster (D-145), grouped by pigment
----------------------------------------------------------------

-- The coil wound in the hand for the Windup the server holds the caster through (D-141), taken back when the
-- charge breaks: no release will come.
VfxLibrary.VoluteCharge = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("VoluteCharge", packet, api) then
		remember("VoluteCharge", packet, playCharge("VoluteCharge", "Volute", packet, api))
	end
end

-- Pressed into the nearest body, at the centre the server struck and by the radius it struck with.
VfxLibrary.Volute = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Volute", packet, api)
end

-- Taken back when its caster stops it before its last tick: the frame no longer hurts.
VfxLibrary.Cartouche = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("Cartouche", packet, api) then
		remember("Cartouche", packet, playGlyph("Cartouche", packet, api))
	end
end

-- The drop swelling in the hands and the locked lane on the floor, measured at the press (D-141), taken back
-- when the charge breaks: a lane left painted would tell a player to leave a line that will not be ruled.
VfxLibrary.RubricCharge = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("RubricCharge", packet, api) then
		remember("RubricCharge", packet, playCharge("RubricCharge", "Rubric", packet, api))
	end
end

-- The Strike's ruling (D-126), from the release packet: Origin is where the caster pressed, the lane the charge
-- painted (D-141), SpawnOffset the gap to where the line starts (shorter against a wall, D-144), Range its
-- length up to where the ray stopped.
VfxLibrary.Rubric = function(packet: Packet, _trove: TroveType, api: Api)
	local def = GlyphConfig.ById.Rubric
	local direction = directionOf(packet)
	api.Timeline.play("Rubric", {
		Origin = packet.Origin + direction * numberParam(packet, "SpawnOffset", 0),
		Direction = direction,
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Reach = math.max(numberParam(packet, "Range", def.Range), 1),
	})
end

-- Taken back when a dash, a stun or a guard breaks the rush: its strokes still to come are never struck.
VfxLibrary.Hatching = function(packet: Packet, _trove: TroveType, api: Api)
	if not retracted("Hatching", packet, api) then
		remember("Hatching", packet, playGlyph("Hatching", packet, api))
	end
end

-- Named like the Brand (D-114): the Fizzle at its end lands the drawn flourish where the server's stopped.
VfxLibrary.Swash = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Swash", packet, api)
end

VfxLibrary.Emboss = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Emboss", packet, api)
end

-- The Caret's step (D-126): Range is the distance from where the caster stood to where the server put him,
-- behind the body he strikes, and Direction the flight's own, climbing to a ledge or down to a floor.
VfxLibrary.Dagger = function(packet: Packet, _trove: TroveType, api: Api)
	local def = GlyphConfig.ById.Dagger
	api.Timeline.play("Dagger", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = casterRoot(packet),
		Hand = casterHand(packet),
		Reach = math.max(numberParam(packet, "Range", def.Range), 1),
	})
end

-- Named like the Brand (D-114): the Fizzle, or the catch below, lands the drawn thread where the server's
-- stopped.
VfxLibrary.Stitch = function(packet: Packet, _trove: TroveType, api: Api)
	playGlyph("Stitch", packet, api)
end

-- The thread came down on a body it could hurt: it lands there, and the catch is drawn on that body (the
-- server names it, Params.Victim), which the server drags and roots. Of a body this client has not
-- streamed in, only the print where it was caught is drawn.
VfxLibrary.StitchCatch = function(packet: Packet, _trove: TroveType, api: Api)
	local shot = shotKey(packet)
	if shot ~= nil then
		api.Timeline.land(shot, packet.Origin)
	end
	local def = GlyphConfig.ById.Stitch
	local victim = if packet.Params ~= nil then packet.Params.Victim else nil
	local body = if typeof(victim) == "Instance" and victim:IsA("Model") then rootOf(victim) else nil
	api.Timeline.play("StitchCatch", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = glyphColor(def.Pigment, packet, api),
		Pigment = def.Pigment,
		Shade = numberParam(packet, "Shade", 0),
		Follow = body,
	})
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
	-- In the caster's skin when the hit came from a skinned glyph (CombatService writes the shade); in the
	-- kit's charcoal when it came from a fist -- the server names the kind -- told to the two people in it
	-- in vellum and wash.
	local fist = stringParam(packet, "Kind", "") == "Melee"
	local color = if fist then KIT_INK else glyphColor(pigment, packet, api)
	local number = if fist then KIT_NUMBER else color
	local outline = if fist then KIT_OUTLINE else color
	local amount = numberParam(packet, "Amount", 0)
	local targetUserId = numberParam(packet, "Target", 0)
	-- The status that amplified the hit, which the server names by its Strings key (CombatService).
	local status = stringParam(packet, "StatusKey", "")
	local amplified = status ~= ""
	local heavy = amount >= HEAVY_HIT_DAMAGE

	api.Timeline.play("Hit", {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = color,
		-- What dries: the pigment the damage carried (none for a melee hit) and its skin shade.
		Pigment = if pigment ~= "" then pigment else nil,
		Shade = numberParam(packet, "Shade", 0),
		-- A heavier hit is the same effect, larger. One timeline serves a jab and an ultimate, which is
		-- what keeps the roster's visual language consistent as it grows.
		Scale = if heavy then 1.35 else 1,
		-- Ink does not shine: a fist's hit lights nothing (D-116).
		Unlit = fist,
	})
	-- The page slap is the melee kit's. A glyph's landing is its pigment's Impact voice, played by its
	-- own timeline once at the point it landed; playing the slap here as well put two thumps under every
	-- glyph hit, and the one that names no school on top of the one that does.
	if pigment == "" then
		api.Sound.play("ImpactHit", packet.Origin)
	end
	if amount >= DUCK_HIT_DAMAGE then
		api.Sound.duck(HEAVY_HIT_DUCK_SECONDS)
	end

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
		-- The body the server named, or the player's by id: a dummy and the boss have only the first.
		local victim = packet.Params ~= nil and packet.Params.Victim or nil
		local targetModel = if typeof(victim) == "Instance" and victim:IsA("Model")
			then victim
			else api.CharacterOf(targetUserId)
		if targetModel ~= nil then
			feel.flash(targetModel, if takenByMe then HIT_TAKEN_COLOR else outline)
			-- A heavy hit or the end of a chain prints both bodies in ink for a few frames, over the outline
			-- (D-112). A finisher is a light hit and a heavy moment, so the server names it.
			local finisher = packet.Params ~= nil and packet.Params.Finisher == true
			if heavy or finisher then
				local bodies = { targetModel }
				local casterModel = api.CharacterOf(packet.Caster or 0)
				if casterModel ~= nil then
					table.insert(bodies, casterModel)
				end
				feel.impactFrame(bodies)
			end
		end
		-- A glyph's number wears its pigment's form on ink, and an amplified one says what paid off (§4.12).
		feel.damageNumber(packet.Origin, amount, number, {
			Kind = if takenByMe then "Taken" elseif fist then "Fist" else "Glyph",
			Amplified = amplified,
			Pigment = if fist or pigment == "" then nil else pigment,
			Status = if amplified then { Key = status, Percent = numberParam(packet, "StatusPercent", 0) } else nil,
		})
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
		-- The melee kit belongs to no school, so it is drawn in the page's charcoal rather than in a
		-- pigment: art bible rule 2 says a colour on screen names a school, and this one names none.
		Color = KIT_INK,
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
		Color = KIT_INK,
		Follow = root,
		-- The length of the path the sketches are laid along (D-116).
		Reach = CombatConfig.Dash.Distance,
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
VfxLibrary.GuardBreak = function(packet: Packet, trove: TroveType, api: Api)
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
	burst(shards, 24, api)
end

-- A killer's KillEffect cosmetic, where the victim fell (CosmeticService). Tinted in the page's inks,
-- never a pigment (docs/ART_BIBLE.md rule 1): a kill is not a spell and must not be read as one. An id
-- this client does not know, or that is not a kill effect, draws nothing.
VfxLibrary.KillEffect = function(packet: Packet, _trove: TroveType, api: Api)
	local item = CosmeticConfig.ById[stringParam(packet, "Effect", "")]
	if item == nil or item.Slot ~= "KillEffect" or item.Look.Timeline == nil then
		return
	end
	local tone = CosmeticConfig.Tones[(item.Look.Tone or "Ink") :: string] or CosmeticConfig.Tones.Ink
	local color = Color3.fromRGB(tone[1], tone[2], tone[3])
	api.Timeline.play(item.Look.Timeline, {
		Origin = packet.Origin,
		Direction = directionOf(packet),
		Color = color,
		Ink = color,
	})
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
			Ink = ERASURE_ERASED,
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
-- The sound is the timeline's: BossWarn is a Sound layer fitted to the window, BossImpact one in the
-- Impact phase, so the ear and the eye are scheduled by the same phase arithmetic and cannot disagree.
local function playBossAttack(id: string, packet: Packet, api: Api): TimelineContext?
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
	return context
end

VfxLibrary.BossSlam = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossSlam", packet, api)
	if context ~= nil then
		scourAfter("BossSlam", context, trove, api, context.Origin, context.Radius or 1)
	end
end

VfxLibrary.BossFury = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossFury", packet, api)
	if context ~= nil then
		scourAfter("BossFury", context, trove, api, context.Origin, context.Radius or 1)
	end
end

VfxLibrary.BossSweep = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossSweep", packet, api)
	if context ~= nil then
		-- A blot at mid-stroke: the residue is not the rule, so a disc over a wedge is allowed to spill.
		local reach = context.Reach or 1
		local origin = context.Origin + context.Direction * (reach * 0.5)
		scourAfter("BossSweep", context, trove, api, origin, context.Radius or 1)
	end
end

VfxLibrary.BossEruption = function(packet: Packet, trove: TroveType, api: Api)
	local context = playBossAttack("BossEruption", packet, api)
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
local function playBossEvent(id: string, packet: Packet, api: Api)
	local ground = bossGround(packet)
	local height = math.max(numberParam(packet, "Height", AUTHORED_BOSS_HEIGHT_STUDS), 1)
	api.Timeline.play(id, {
		Origin = ground,
		Direction = flatDirectionOf(packet),
		Color = ERASURE_COLOR,
		Ink = ERASURE_INK,
		Scale = height / AUTHORED_BOSS_HEIGHT_STUDS,
	})
end

VfxLibrary.BossSpawn = function(packet: Packet, _trove: TroveType, api: Api)
	playBossEvent("BossSpawn", packet, api)
end

VfxLibrary.BossDefeated = function(packet: Packet, _trove: TroveType, api: Api)
	playBossEvent("BossDefeated", packet, api)
end

-- A new phase: the band widened on the body, and the page around it takes the blow.
VfxLibrary.BossPhase = function(packet: Packet, _trove: TroveType, api: Api)
	playBossEvent("BossPhase", packet, api)
end

----------------------------------------------------------------
-- The Battleground's Forgers (D-131)
----------------------------------------------------------------

-- A Forger's tell is drawn in the Forger's own two inks, never in the Erasure's danger colour (FORGER_TELL in
-- Config/VfxTimelineConfig): its body's charcoal on the floor (a mark takes the play's Ink), and the chalk of
-- the bars on its chest in the flash at its hand.
local FORGER_INK = Palette.world(WorldConfig.Forgers.Body)
local FORGER_CHALK = Palette.world(WorldConfig.Forgers.Mark)

-- The hand a Forger strikes with (Params.Actor, the body the server owns), for the flash at the end of its
-- tell. nil when the body is gone or has not streamed in: the flash is then drawn at the Forger's feet.
local function actorHand(packet: Packet): BasePart?
	local params = packet.Params
	local actor = if params ~= nil then params.Actor else nil
	if typeof(actor) ~= "Instance" or not actor:IsA("Model") then
		return nil
	end
	local hand = actor:FindFirstChild(VfxConfig.Hand)
	return if hand ~= nil and hand:IsA("BasePart") then hand else nil
end

-- A length the packet measures the tell by, or nil when it carried none that can be drawn: every layer measured
-- by a missing length is then left out (and the runtime says so) rather than painted at a guess, which would
-- tell a player they stand outside a blow that reaches them.
local function measureParam(packet: Packet, key: string): number?
	local value = numberParam(packet, key, 0)
	return if value > 0 then value else nil
end

-- The play of the tell each Forger shows, by its slot (Params.Forger): what a retraction takes back. A slot
-- holds one Forger and a Forger shows one tell at a time, so this never holds more than BotConfig.MaxBots, and
-- one per pit of the practice duel (BattlegroundConfig.Pits.Count), whose slots come after the page's.
local forgerTells: { [number]: number } = {}

-- A Forger winding up a blow (D-131): the floor it will cover, for exactly the window the server waits
-- (Params.Seconds), measured on what the server will hit -- Width across the aim, Range along it from the
-- Forger (BattlegroundService's Attacks.windup). The Origin is already the floor under the Forger. A packet
-- with Params.Cancel is the server taking that Forger's tell back (Attacks.retract): its blow will not come.
VfxLibrary.ForgerTell = function(packet: Packet, _trove: TroveType, api: Api)
	local forger = numberParam(packet, "Forger", 0)
	local params = packet.Params
	if params ~= nil and params.Cancel == true then
		local playId = forgerTells[forger]
		forgerTells[forger] = nil
		if playId ~= nil then
			api.Timeline.cancel(playId)
		end
		return
	end
	local width = measureParam(packet, "Width")
	local _, playId = api.Timeline.play("ForgerTell", {
		Origin = packet.Origin,
		Direction = flatDirectionOf(packet),
		Color = FORGER_CHALK,
		Ink = FORGER_INK,
		-- A packet with no window warns for the phase's own Duration, which a zero asks for.
		Window = numberParam(packet, "Seconds", 0),
		Radius = if width ~= nil then width / 2 else nil,
		Reach = measureParam(packet, "Range"),
		-- A Forger is no glyph: nothing of it shines (docs/ART_BIBLE.md rule 10).
		Unlit = true,
		Hand = actorHand(packet),
	})
	forgerTells[forger] = playId
end

return VfxLibrary
