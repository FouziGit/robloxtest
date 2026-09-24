--!strict
-- The runtime that plays a VfxTimelineConfig entry.
--
-- One Heartbeat connection drives every layer of every effect on screen. That is not a micro-optimisation:
-- the previous version gave each effect its own tweens and its own task.delay chains, so the cost of a
-- fight was the number of effects times the number of layers, and nothing could see the total. Here there
-- is one schedule, so the total is a number the runtime knows, which is what makes art bible rule 8 --
-- particle density is capped -- something the code can actually enforce rather than something the author
-- is asked to remember.
--
-- Instances come from VfxPool and go back to it. Nothing here calls Instance.new in a loop.
--
-- A layer whose texture has not been uploaded yet still plays, untextured. AssetIds carries "" for a
-- missing id and this warns once per key, naming the PNG to upload. An effect that refuses to draw
-- because an artist has not finished is worse than an effect that draws plainly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local AssetIds = require(Shared.Config.AssetIds)
local FeelConfig = require(Shared.Config.FeelConfig)
local FeelMath = require(Shared.Pure.FeelMath)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Util.Palette)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local QualityConfig = require(Shared.Config.QualityConfig)
local SoundConfig = require(Shared.Config.SoundConfig)
local VfxConfig = require(Shared.Config.VfxConfig)
local VfxTimelineConfig = require(Shared.Config.VfxTimelineConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("VfxTimeline")

type Deps = { VfxPool: any, Feel: any, WorldLighting: any, SoundController: any, QualityController: any }

export type Context = {
	Origin: Vector3,
	Direction: Vector3,
	Color: Color3,
	-- The colour of what the effect leaves on the FLOOR, when that is not its own colour. A glyph's burn
	-- is its pigment and needs none of this; the Erasure's marks do, because its colour is the pale page
	-- (its light and its dust are the page overexposed) and a pale mark on a vellum floor is nothing at
	-- all. Mark layers only.
	Ink: Color3?,
	-- Multiplies every distance and size in the timeline, so one timeline serves a jab and an ultimate.
	Scale: number?,
	-- How long a phase that declared Window lasts: the warning the server is really waiting through
	-- before it deals the damage. Ignored by every other phase.
	Window: number?,
	-- Studs of the shape the server will damage, for the layers that measure themselves against it
	-- instead of against Scale. Radius is the inner measure and Reach the outer one. A layer naming one
	-- the renderer did not pass is skipped rather than drawn at the wrong size.
	Radius: number?,
	Reach: number?,
	-- The pigment whose four voices a Sound layer that names a Voice resolves against. A layer naming a
	-- voice in a play that carries no pigment is not played, and the runtime says so once. It is also what
	-- dries: only a play with a pigment has its ink go from wet to dry (VfxConfig.InkRamp).
	Pigment: string?,
	-- The caster's skin shade (PigmentConfig.ShadeRange), already in Color. The drying adds to it from the
	-- pigment itself and is clamped once, so a skin and its drying never compound out of the school.
	Shade: number?,
	-- A thrown thing's name between its throw and its burst (thrower and server shot number): the burst
	-- lands the play that carries it where the server burst it (VfxTimeline.land, D-114).
	Shot: string?,
	-- A part the effect rides: a projectile, or the caster's root. Layers that need a moving anchor
	-- (Trail, and anything whose Offset should follow the body) use it; the rest are placed once in world
	-- space, which is what an impact wants.
	Follow: BasePart?,
}

type Layer = VfxTimelineConfig.Layer
type Measure = VfxTimelineConfig.Measure

-- What a layer's own numbers are multiplied by. Effect is Context.Scale, which is what everything used
-- before a layer could measure itself against the damage; the other three are studs of a measure the
-- packet carried when the layer named one, and the same Scale when it did not. Resolved once when the
-- layer starts rather than per frame: a warning that changed size halfway through is a warning about
-- nothing.
type Scales = { Effect: number, Size: number, Span: number, Offset: number }

-- One layer in flight. `Instances` is everything it borrowed, released together when it ends.
type Live = {
	Layer: Layer,
	Context: Context,
	Scales: Scales,
	Frame: CFrame,
	StartedAt: number,
	-- Its own length, resolved: a layer inside a windowed phase declares a fraction of the window, so
	-- this is not layer.For.
	Seconds: number,
	EndsAt: number,
	-- Part of a windowed phase: a warning about damage that has not landed yet. The budget never retires
	-- one early, and one whose texture is not uploaded yet is drawn as a bare plate rather than skipped,
	-- because a warning is a rule and the rules do not go missing while the art is late.
	Warning: boolean,
	Instances: { Instance },
	Primary: Instance?,
	-- A floor mark's ink, wet when its play begins and dry InkRamp.Seconds later (VfxConfig.InkRamp).
	Wet: Color3?,
	Dry: Color3?,
	-- Which call to play() this layer came from. Layers of one play share a carrier, and two casts in
	-- flight at once must not ride each other's.
	PlayId: number,
	-- When that play began: the clock its floor marks dry on.
	PlayStartedAt: number,
	-- A carrier brought down where its projectile burst (VfxTimeline.land): from where it was, to there.
	Landing: { From: CFrame, To: Vector3, At: number }?,
	-- A riding light dimming out after a landing, from the brightness it had when it began to.
	Ending: { At: number, From: number }?,
}

type Pending = {
	Id: string,
	Layer: Layer,
	Context: Context,
	At: number,
	-- Seconds, resolved against the window of the phase it belongs to.
	Seconds: number,
	Warning: boolean,
	PlayId: number,
	PlayStartedAt: number,
	-- The phase it belongs to: a landing drops what is still to fly and re-places what is to linger.
	Phase: string,
}

local VfxTimeline = {}

local pool: any
local feel: any
local quality: any
local worldLighting: any
local sound: any

local player = Players.LocalPlayer
local pending: { Pending } = {}
local live: { Live } = {}
local warnedTextures: { [string]: boolean } = {}
-- The travelling body of each play that has one, while it has one. Cleared when its Carrier layer
-- ends, so a layer that outlives the flight falls back to standing still rather than following a
-- part that has gone back to the pool.
local carriers: { [number]: BasePart } = {}
-- The play each thrown thing in flight belongs to, by its Shot, until it lands or its carrier ends.
local shots: { [string]: number } = {}
local warnedFollow: { [string]: boolean } = {}
local warnedMeasures: { [string]: boolean } = {}
local warnedVoices: { [string]: boolean } = {}
local nextPlayId = 0
local overBudgetWarned = false

local FORWARD_FALLBACK = Vector3.new(0, 0, -1)
local GROUND_PROBE_STUDS = 24
-- A mark is laid flat: a Decal's face normal is +Z, so the part it sits on is rotated to lie down.
local LYING = CFrame.Angles(-math.pi / 2, 0, 0)

--------------------------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------------------------

local function localRoot(): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local part = character:FindFirstChild("HumanoidRootPart")
	if part ~= nil and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function frameOf(context: Context): CFrame
	local direction = context.Direction
	if direction.Magnitude < 1e-3 then
		direction = FORWARD_FALLBACK
	end
	return CFrame.lookAt(context.Origin, context.Origin + direction.Unit)
end

-- A layer's own frame: the effect's frame offset by {right, up, forward}. Forward is negated because a
-- lookAt frame's LookVector is its -Z axis, and an author writing Offset = {0, 0, 3} means three studs
-- in front of the caster, not three studs behind them.
local function placeOf(base: CFrame, layer: Layer, scale: number): CFrame
	local offset: { number }? = layer.Offset
	if offset == nil then
		return base
	end
	local right, up, forward = offset[1], offset[2], offset[3]
	return base * CFrame.new(right * scale, up * scale, -forward * scale)
end

-- The ground probe ignores every character on the server, not only the local one. A mark under a point
-- that happens to be another player is otherwise drawn on that player's body, tilted to whatever surface
-- of theirs the ray met, and a boss telegraph drawn across somebody's shoulders warns nobody. Pooled parts
-- are already invisible to the ray (VfxPool sets CanQuery false).
--
-- Assigning FilterDescendantsInstances resolves every descendant of the list, so it is rebuilt only when
-- a character comes or goes rather than on every probe -- one boss attack lays a dozen marks at once.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
local groundExcludeStale = true

local function markGroundExcludeStale()
	groundExcludeStale = true
end

local function refreshGroundExclude()
	local exclude: { Instance } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		if character ~= nil then
			table.insert(exclude, character)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
	groundExcludeStale = false
end

-- Both edges of a respawn invalidate, or the filter keeps excluding a destroyed rig and stops excluding
-- the live one; a join invalidates too, because the joiner's first CharacterAdded can land before this
-- client sees the PlayerAdded.
local function watchCharacters(other: Player)
	markGroundExcludeStale()
	other.CharacterAdded:Connect(markGroundExcludeStale)
	other.CharacterRemoving:Connect(markGroundExcludeStale)
end

-- The ground under a point, for the marks every impact leaves. Falls back to the point itself rather than
-- skipping the mark: a trace slightly off the floor is better than a world that forgets.
local function groundAt(position: Vector3): (Vector3, Vector3)
	if groundExcludeStale then
		refreshGroundExclude()
	end
	local result = Workspace:Raycast(position + Vector3.yAxis, Vector3.yAxis * -GROUND_PROBE_STUDS, groundParams)
	if result == nil then
		return position, Vector3.yAxis
	end
	return result.Position, result.Normal
end

--------------------------------------------------------------------------------------------------
-- Easing
--------------------------------------------------------------------------------------------------

-- TweenService owns the curves the engine already ships; reimplementing them would be a second set of
-- easing functions to keep in agreement with the tweens the rest of the client still uses.
-- The frame a ground mark is drawn in: flat on the floor the probe found, its depth axis along the
-- effect's own direction, and lifted by the layer's up offset so that two marks in one place do not
-- z-fight. The direction is new and it matters, because a mark can now be longer than it is wide: a
-- lookAt straight up has no answer for which way a stroke points, and Roblox picks one for it.
local function markFrame(position: Vector3, normal: Vector3, forward: Vector3, lift: number): CFrame
	local flat = forward - normal * forward:Dot(normal)
	if flat.Magnitude < 1e-3 then
		-- Aimed straight at the floor: any horizontal axis will do, so long as it is not the normal.
		flat = Vector3.xAxis - normal * normal.X
		if flat.Magnitude < 1e-3 then
			flat = Vector3.zAxis
		end
	end
	local base = position + normal * (0.03 + math.max(lift, 0))
	return CFrame.lookAt(base, base + flat.Unit, normal) * LYING
end

-- Studs of the measure `name`, or nil when the packet did not carry it. A measure that arrived as zero,
-- negative or NaN counts as absent: it comes off a remote, so it is not trusted to be a number that
-- behaves, and drawing a warning at zero studs is the failure this whole mechanism exists to prevent.
local function geometryScale(context: Context, name: Measure?, effect: number): number?
	if name == nil then
		return effect
	end
	local studs: number? = if name == "Radius" then context.Radius else context.Reach
	if studs == nil then
		return nil
	end
	if studs ~= studs or studs <= 0 then
		return nil
	end
	return studs
end

-- nil when the layer measures itself against a length this play has not got.
local function scalesOf(context: Context, layer: Layer): Scales?
	local effect = context.Scale or 1
	local size = geometryScale(context, layer.SizeFrom, effect)
	local span = geometryScale(context, layer.SpanFrom, effect)
	local offset = geometryScale(context, layer.OffsetFrom, effect)
	if size == nil or span == nil or offset == nil then
		return nil
	end
	return { Effect = effect, Size = size, Span = span, Offset = offset }
end

local function eased(layer: Layer, alpha: number): number
	local style = layer.Ease
	if style == nil then
		return math.clamp(alpha, 0, 1)
	end
	local direction = layer.EaseDirection or "Out"
	return TweenService:GetValue(
		math.clamp(alpha, 0, 1),
		(Enum.EasingStyle :: any)[style],
		(Enum.EasingDirection :: any)[direction]
	)
end

local function lerp(from: number?, to: number?, alpha: number, fallback: number): number
	local start = from or fallback
	local finish = to
	if finish == nil then
		return start
	end
	return start + (finish - start) * alpha
end

--------------------------------------------------------------------------------------------------
-- Textures
--------------------------------------------------------------------------------------------------

-- "" when the PNG has not been uploaded, warned once per key so the output names the file to upload
-- instead of repeating itself sixty times a second.
local function textureOf(layer: Layer): string
	local key = layer.Texture
	if key == nil then
		return ""
	end
	local id, known = AssetIds.get(key)
	if not known then
		if not warnedTextures[key] then
			warnedTextures[key] = true
			log.warn("timeline names texture %s, which AssetIds does not declare", key)
		end
		return ""
	end
	if id == "" and not warnedTextures[key] then
		warnedTextures[key] = true
		local asset = AssetIds.Textures[key]
		log.warn("texture %s has no id yet: upload %s with python3 scripts/upload_assets.py upload", key, asset.Source)
	end
	return id
end

--------------------------------------------------------------------------------------------------
-- Layer construction
--------------------------------------------------------------------------------------------------

-- nil when the pool is at capacity for that class. Every caller has to handle it: a layer that cannot
-- get its instances is simply not drawn, which is the degradation art bible rule 8 asks for -- "un effet
-- qu'on ne peut pas afficher est un effet qu'on ne joue pas" -- rather than an error inside a builder.
local function borrow(entry: Live, className: string): Instance?
	local instance = pool.acquire(className)
	if instance == nil then
		return nil
	end
	table.insert(entry.Instances, instance)
	return instance
end

-- An anchored, non-colliding host part. Everything visual hangs off one of these.
local function host(entry: Live, place: CFrame, size: Vector3): BasePart?
	local instance = borrow(entry, "Part")
	if instance == nil then
		return nil
	end
	local part = instance :: BasePart
	part.Size = size
	part.CFrame = place
	part.Parent = Workspace
	return part
end

-- A sprite and a mark are flat planes whose entire purpose is to carry a texture. Drawn without one
-- they are coloured rectangles hanging in the air, which is worse than drawing nothing: a missing
-- upload would make the game look broken rather than plain. So a layer that NAMES a texture and cannot
-- get one is skipped, exactly like a layer the pool refused. A layer that names none was authored that
-- way and still draws.
local function textureMissing(layer: Layer): boolean
	return layer.Texture ~= nil and textureOf(layer) == ""
end

-- A plane's size at `alpha`: Size across, Span along, and thin. A layer with no Span is square and both
-- axes follow the size animation, which is every plane authored before Span existed.
local function planeSize(entry: Live, alpha: number): Vector3
	local layer = entry.Layer
	local width = lerp(layer.Size, layer.EndSize, alpha, 1) * entry.Scales.Size
	local span = layer.Span
	return Vector3.new(width, if span ~= nil then span * entry.Scales.Span else width, 0.05)
end

local INK_RGB = WorldConfig.Colors.Ink
local PAGE_RGB = WorldConfig.Colors.Page

-- The colour a thing of this play is at birth (wet) and at the end of its life (dry): VfxConfig.InkRamp
-- added to the caster's skin shade and applied to the PIGMENT, clamped once by PigmentConfig.shade --
-- shading an already shaded colour compounded a -0.25 skin and a -0.2 drying to -0.45, where a Cinnabar
-- reads as Umber. Only a pigment dries: a play with none (the page-coloured Erasure, a kill effect's
-- inks, a melee hit) keeps the colour it was given.
local function wetAndDry(context: Context, color: Color3): (Color3, Color3)
	local pigment = context.Pigment
	local base: { number }? = if pigment ~= nil then (PigmentConfig.Colors :: any)[pigment] else nil
	if base == nil then
		return color, color
	end
	local ramp = VfxConfig.InkRamp
	local shade = context.Shade or 0
	return Palette.rgb(PigmentConfig.shade(base, shade + ramp.Wet, INK_RGB, PAGE_RGB)),
		Palette.rgb(PigmentConfig.shade(base, shade + ramp.Dry, INK_RGB, PAGE_RGB))
end

local function inkRamp(context: Context, color: Color3): ColorSequence
	local wet, dry = wetAndDry(context, color)
	return ColorSequence.new(wet, dry)
end

-- How dry a floor mark is at `now`, on its PLAY's clock rather than its own life: a stain drawn as a chain
-- of marks then picks up at the colour the last link reached instead of flashing wet at the hand-off.
local function driedBy(entry: Live, now: number): number
	return math.clamp((now - entry.PlayStartedAt) / VfxConfig.InkRamp.Seconds, 0, 1)
end

local function buildSprite(entry: Live, layer: Layer, place: CFrame)
	if textureMissing(layer) then
		return
	end
	local part = host(entry, place, planeSize(entry, 0))
	if part == nil then
		return
	end
	part.Color = entry.Context.Color
	part.Transparency = layer.Transparency or 0
	local id = textureOf(layer)
	if id ~= "" then
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local instance = borrow(entry, "Decal")
			if instance == nil then
				break
			end
			local decal = instance :: Decal
			decal.Texture = id
			decal.Face = face
			decal.Color3 = entry.Context.Color
			decal.Transparency = layer.Transparency or 0
			decal.Parent = part
		end
	end
	entry.Primary = part
end

local function buildMark(entry: Live, layer: Layer, place: CFrame)
	-- A plane that names a texture it cannot get is not drawn -- except a warning. A warning is a rule
	-- six players read, and a bare tinted plate on the floor still says where not to stand; nothing at
	-- all says nothing. It draws untextured until the PNG is uploaded, and STUDIO_SETUP names the file.
	if textureMissing(layer) and not entry.Warning then
		return
	end
	local position, normal = groundAt(place.Position)
	local offset: { number }? = layer.Offset
	-- Lifted a hair off the floor, plus whatever the layer's up offset asks for: a decal coplanar with
	-- the ground z-fights, and so do two decals coplanar with each other. The lift is studs scaled with
	-- the effect, never with a measure: a z-fight gap is a stud quantity, and a layer whose offset is
	-- measured against a forty-stud reach would otherwise float its mark a metre above the page.
	local lift = if offset ~= nil then offset[2] * entry.Scales.Effect else 0
	local part = host(entry, markFrame(position, normal, place.LookVector, lift), planeSize(entry, 0))
	if part == nil then
		return
	end
	local id = textureOf(layer)
	-- What is drawn on the page is drawn in the effect's ink where it has one (see Context.Ink).
	local ink = entry.Context.Ink or entry.Context.Color
	if id == "" then
		part.Color = ink
		part.Transparency = layer.Transparency or 0.3
		entry.Primary = part
		return
	end
	local decalInstance = borrow(entry, "Decal")
	if decalInstance == nil then
		return
	end
	part.Transparency = 1
	local decal = decalInstance :: Decal
	decal.Texture = id
	-- markFrame leaves the part's +Z along the ground normal, and Front is the -Z face: the face that
	-- looks up is Back. Front here pointed every mark in the game into the floor.
	decal.Face = Enum.NormalId.Back
	-- A mark drawn in its own ink (the Erasure's page-coloured burns) is not the pigment and does not dry.
	local wet, dry = ink, ink
	if entry.Context.Ink == nil then
		wet, dry = wetAndDry(entry.Context, ink)
	end
	entry.Wet = wet
	entry.Dry = dry
	decal.Color3 = wet:Lerp(dry, driedBy(entry, entry.StartedAt))
	decal.Transparency = layer.Transparency or 0.3
	decal.Parent = part
	entry.Primary = part
end

-- Studs a particle covers over its life, at the middle of its speed and lifetime ranges. This is the
-- radius of the shell an inward emitter spawns on, so a particle born at the edge of it arrives at the
-- centre as it dies -- which is what "pulled inward" has to mean, and what forty layers in the data ask
-- for with a negative speed.
-- How many particles a layer really asks for at `density`: its burst (floored at one when it asked for
-- any) plus its rate over its own life. Under one, the layer is invisible and is not drawn at all.
local function expectedParticles(layer: Layer, seconds: number, density: number): number
	local burst = if layer.Burst ~= nil then math.max(1, math.floor(layer.Burst * density)) else 0
	local rate = if layer.Rate ~= nil then layer.Rate * density * math.max(seconds, 0) else 0
	return burst + rate
end

local function convergeRadius(speed: { number }, lifetime: { number }, scale: number): number
	local meanSpeed = (math.abs(speed[1]) + math.abs(speed[2])) * 0.5 * scale
	local meanLife = (lifetime[1] + lifetime[2]) * 0.5
	return math.max(meanSpeed * meanLife, 0.25)
end

local function buildEmitter(entry: Live, layer: Layer, place: CFrame)
	local scale = entry.Scales.Effect
	local speed = layer.Speed or { 0, 0 }
	local lifetime = layer.Lifetime or VfxTimelineConfig.DefaultParticleLifetime
	-- Negative speed is written as "pulls inward", and from a point-sized host that is not what happens:
	-- a particle born at the point and sent the opposite way is still a particle leaving the point. So
	-- an inward layer emits from the surface of a sphere, facing in, and its particles run toward the
	-- point instead of away from it. The sphere's size comes from the data the layer already declares.
	local inward = speed[1] < 0 or speed[2] < 0
	local hostSize = if inward then Vector3.one * (2 * convergeRadius(speed, lifetime, scale)) else Vector3.one * 0.2
	local part = host(entry, place, hostSize)
	if part == nil then
		return
	end
	part.Transparency = 1
	local emitterInstance = borrow(entry, "ParticleEmitter")
	if emitterInstance == nil then
		return
	end
	local emitter = emitterInstance :: ParticleEmitter
	local id = textureOf(layer)
	if id ~= "" then
		emitter.Texture = id
	end
	emitter.Color = inkRamp(entry.Context, entry.Context.Color)
	-- Particle size is a size, so it follows the layer's size measure; speed is a distance through the
	-- world and follows the effect's own scale.
	local size = (layer.Size or 1) * entry.Scales.Size
	local endSize = (layer.EndSize or layer.Size or 1) * entry.Scales.Size
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, math.max(endSize, 0)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, layer.Transparency or 0),
		NumberSequenceKeypoint.new(1, layer.EndTransparency or 1),
	})
	if inward then
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		-- The shell already faces inward, so the speed is the magnitude: {-9, -5} runs 5 to 9 studs a
		-- second toward the point, ordered low to high as NumberRange demands.
		emitter.Speed = NumberRange.new(math.abs(speed[2]) * scale, math.abs(speed[1]) * scale)
	else
		emitter.Speed = NumberRange.new(speed[1] * scale, speed[2] * scale)
	end
	emitter.Lifetime = NumberRange.new(lifetime[1], lifetime[2])
	emitter.SpreadAngle = Vector2.new(layer.Spread or 0, layer.Spread or 0)
	emitter.Drag = layer.Drag or 0
	-- A spark stretched along its travel reads as moving rather than as a dot that is somewhere else next
	-- frame. A streak is drawn along its flight (VfxConfig.StreakTextures). VelocityParallel lays the image's +X
	-- on the velocity, and spark_streak.png has its head at -X, so the image is turned half a turn or every
	-- spark flies tail first. And Squash scales the image's own axes, so along the flight a NEGATIVE value
	-- lengthens it: the layer's Squash (written as "how stretched") is applied negated. Both found by
	-- review with a live probe, sparks thrown straight up (D-111).
	local squash = layer.Squash or 0
	local streak = layer.Texture ~= nil and VfxConfig.StreakTextures[layer.Texture] == true
	if streak then
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
		emitter.Rotation = NumberRange.new(180, 180)
		squash = -squash
	end
	-- Stretched at birth, when it is fastest, and relaxed by the time drag has stopped it.
	emitter.Squash = NumberSequence.new({
		NumberSequenceKeypoint.new(0, squash),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- Wind drags the residue with the world instead of leaving it hanging in still air.
	emitter.WindAffectsDrag = true
	emitter.LightEmission = VfxConfig.LightEmission
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = part

	local flipbookKey = layer.Texture
	if flipbookKey ~= nil and AssetIds.frameCount(flipbookKey) == 64 then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end

	-- Art bible rule 8: the density falls with the graphics setting. A burst that asked for particles never
	-- rounds to none -- an impact with no grit reads as a missing effect rather than as a thin one -- so a
	-- burst floors at one. A RATE has no such floor, and a thin rate scaled to a fifth emitted nothing at
	-- all while still costing a part, an emitter and a layer of the budget: those layers are skipped
	-- outright now (see expectedParticles), which is what a graphics tier is supposed to do.
	local tier: QualityConfig.TierDef = quality.def()
	local density = tier.ParticleScale
	if layer.Burst ~= nil then
		emitter:Emit(math.max(1, math.floor(layer.Burst * density)))
	end
	if layer.Rate ~= nil then
		emitter.Rate = layer.Rate * density
		emitter.Enabled = true
	end
	entry.Primary = emitter
end

local function buildLight(entry: Live, layer: Layer, place: CFrame)
	local part = host(entry, place, Vector3.one * 0.2)
	if part == nil then
		return
	end
	part.Transparency = 1
	local lightInstance = borrow(entry, "PointLight")
	if lightInstance == nil then
		return
	end
	local light = lightInstance :: PointLight
	light.Color = entry.Context.Color
	light.Range = (layer.Range or 8) * entry.Scales.Effect
	light.Brightness = layer.Brightness or 1
	light.Shadows = false
	light.Parent = part
	entry.Primary = light
end

-- Two attachments and a Beam between them. CurveSize is what draws a stroke rather than a laser: the art
-- direction's "un trait qui se dessine est un Beam dont on anime CurveSize".
local function buildBeam(entry: Live, layer: Layer, place: CFrame)
	local scale = entry.Scales.Size
	local length = (layer.Size or 1) * 8 * scale
	local from = host(entry, place, Vector3.one * 0.1)
	local to = host(entry, place * CFrame.new(0, 0, -length), Vector3.one * 0.1)
	local a0Instance = borrow(entry, "Attachment")
	local a1Instance = borrow(entry, "Attachment")
	local beamInstance = borrow(entry, "Beam")
	if from == nil or to == nil or a0Instance == nil or a1Instance == nil or beamInstance == nil then
		return
	end
	from.Transparency = 1
	to.Transparency = 1

	local a0 = a0Instance :: Attachment
	a0.Parent = from
	local a1 = a1Instance :: Attachment
	a1.Parent = to

	local beam = beamInstance :: Beam
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(entry.Context.Color)
	beam.Width0 = (layer.Size or 1) * scale
	beam.Width1 = (layer.Size or 1) * scale * 0.35
	beam.Transparency = NumberSequence.new(layer.Transparency or 0.2)
	beam.FaceCamera = true
	beam.LightEmission = VfxConfig.LightEmission
	local id = textureOf(layer)
	if id ~= "" then
		beam.Texture = id
		beam.TextureMode = Enum.TextureMode.Stretch
	end
	beam.Parent = from
	entry.Primary = beam
end

-- An invisible part that flies. Everything visible about a projectile is some other layer riding it,
-- which is what keeps the motion in one place: a trail, a light and a spark stream cannot disagree about
-- where the thing is, because there is only one thing.
local function buildCarrier(entry: Live, place: CFrame)
	local part = host(entry, place, Vector3.one * 0.2)
	if part == nil then
		return
	end
	part.Transparency = 1
	carriers[entry.PlayId] = part
	entry.Primary = part
end

local function buildTrail(entry: Live, layer: Layer, place: CFrame)
	-- The caster's body only when the layer said Follow. A riding trail gets its own host, which
	-- followCarrier then moves with the projectile: preferring Context.Follow unconditionally is how
	-- a trail meant to ride a fireball ended up drawn from the caster's chest instead.
	local anchor: BasePart? = if layer.Follow == true
		then entry.Context.Follow
		else host(entry, place, Vector3.one * 0.2)
	local a0Instance = borrow(entry, "Attachment")
	local a1Instance = borrow(entry, "Attachment")
	local trailInstance = borrow(entry, "Trail")
	if anchor == nil or a0Instance == nil or a1Instance == nil or trailInstance == nil then
		return
	end
	local width = (layer.Size or 1) * entry.Scales.Size
	local a0 = a0Instance :: Attachment
	a0.Position = Vector3.new(0, width * 0.5, 0)
	a0.Parent = anchor
	local a1 = a1Instance :: Attachment
	a1.Position = Vector3.new(0, -width * 0.5, 0)
	a1.Parent = anchor

	local trail = trailInstance :: Trail
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	-- Wet at the head, dry at the tail: a trail's length is its age.
	trail.Color = inkRamp(entry.Context, entry.Context.Color)
	trail.Lifetime = entry.Seconds
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, layer.Transparency or 0.3),
		NumberSequenceKeypoint.new(1, layer.EndTransparency or 1),
	})
	trail.LightEmission = VfxConfig.LightEmission
	-- A thrown ribbon turns its face to whoever is looking. Spanned between two attachments one above the
	-- other, it is a sheet standing along the flight line -- seen edge-on, as a hairline, by exactly the two
	-- people who matter: the one who threw it and the one it is flying at. Beams already face the camera.
	-- A ribbon on the caster's own body stays the standing curtain it was authored as: turned to a chase
	-- camera it would lie flat, a band across the caster's legs and the floor behind them.
	trail.FaceCamera = layer.Follow ~= true
	-- Size at the head, EndSize at the tail: the taper the timelines declare, which a ribbon of constant
	-- width read as a band rather than a thing moving.
	local tail = layer.EndSize
	if tail ~= nil and (layer.Size or 1) > 0 then
		trail.WidthScale = NumberSequence.new(1, math.max(tail / (layer.Size or 1), 0))
	end
	local id = textureOf(layer)
	if id ~= "" then
		trail.Texture = id
		trail.TextureMode = Enum.TextureMode.Static
	end
	trail.Enabled = true
	trail.Parent = anchor
	entry.Primary = trail
end

--------------------------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------------------------

-- How far a layer's transparency has travelled (FeelMath.layerFade): no faster than ink dries when it
-- fades out, on its own ease when it darkens or when its author tied the fade to its size.
local function fadeOf(layer: Layer, elapsed: number, alpha: number, fallback: number): number
	local from = layer.Transparency or fallback
	return FeelMath.layerFade(from, layer.EndTransparency or from, elapsed, alpha, layer.FadesWithSize == true)
end

local function stepSprite(entry: Live, alpha: number, elapsed: number, deltaTime: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local part = primary :: BasePart
	local layer = entry.Layer
	part.Size = planeSize(entry, alpha)
	local transparency =
		math.clamp(lerp(layer.Transparency, layer.EndTransparency, fadeOf(layer, elapsed, alpha, 0), 0), 0, 1)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") then
			child.Transparency = transparency
		end
	end
	part.Transparency = if #part:GetChildren() > 0 then 1 else transparency
	local spin = layer.Spin
	if spin ~= nil then
		part.CFrame = part.CFrame * CFrame.Angles(0, 0, spin * deltaTime)
	end
end

local function stepMark(entry: Live, alpha: number, elapsed: number, now: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local part = primary :: BasePart
	local layer = entry.Layer
	part.Size = planeSize(entry, alpha)
	local fade = fadeOf(layer, elapsed, alpha, 0.3)
	local transparency = math.clamp(lerp(layer.Transparency, layer.EndTransparency, fade, 0.3), 0, 1)
	-- The stain darkens as it dries, on its play's clock.
	local wet, dry = entry.Wet, entry.Dry
	local children = part:GetChildren()
	for _, child in ipairs(children) do
		if child:IsA("Decal") then
			child.Transparency = transparency
			if wet ~= nil and dry ~= nil then
				child.Color3 = wet:Lerp(dry, driedBy(entry, now))
			end
		end
	end
	-- A warning drawn bare, before its texture exists, fades on the part itself.
	part.Transparency = if #children > 0 then 1 else transparency
end

local function stepLight(entry: Live, alpha: number, now: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local light = primary :: PointLight
	local ending = entry.Ending
	if ending ~= nil then
		-- Landed: it dims from where it was, never from where its shortened life would put it, fast and
		-- then easing out, like every other fade (rule 4).
		local left = 1 - math.clamp((now - ending.At) / VfxTimelineConfig.Land.Fade, 0, 1)
		light.Brightness = ending.From * left * left
		return
	end
	-- A light changes by brightness, never by being removed: an instant cut reads as a bug, and art bible
	-- rule 3 forbids anything appearing or vanishing outright. EndBrightness absent means zero, so the
	-- default is the fade it always was, and a telegraph can ask for the opposite.
	local layer = entry.Layer
	light.Brightness = math.max(lerp(layer.Brightness, layer.EndBrightness or 0, alpha, 1), 0)
end

local function stepBeam(entry: Live, alpha: number, elapsed: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local beam = primary :: Beam
	local layer = entry.Layer
	local width = lerp(layer.Size, layer.EndSize, alpha, 1) * entry.Scales.Size
	beam.Width0 = math.max(width, 0)
	beam.Width1 = math.max(width * 0.35, 0)
	local fade = fadeOf(layer, elapsed, alpha, 0.2)
	beam.Transparency = NumberSequence.new(math.clamp(lerp(layer.Transparency, layer.EndTransparency, fade, 0.2), 0, 1))
end

-- Where a carrier is `progress` of the way through its flight: its declared distance forward, and a half
-- sine of Arc above it -- zero at both ends, highest in the middle, multiplied rather than added so a
-- timeline with no Arc travels flat and pays nothing for the option.
local function flightPoint(entry: Live, progress: number): Vector3
	local layer = entry.Layer
	local scale = entry.Scales.Effect
	local distance = (layer.Travel or 0) * scale * progress
	local rise = (layer.Arc or 0) * scale * math.sin(math.clamp(progress, 0, 1) * math.pi)
	return (entry.Frame * CFrame.new(0, 0, -distance)).Position + Vector3.new(0, rise, 0)
end

-- Flight. The body travels its declared distance over its own duration, eased, and rises and falls by
-- Arc along the way: a thrown thing does not travel a straight line at a constant speed, and art bible
-- rule 4 forbids the linear version outright. EaseShare mixes the ease with time itself, for a carrier
-- drawing a projectile the server steps at a constant speed (D-114). Timed on its own Seconds, not on its
-- life: a thrown carrier lives a grace longer, holding at its end for its burst, and must not fly slower
-- for it.
local function stepCarrier(entry: Live, now: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local part = primary :: BasePart
	local landing = entry.Landing
	if landing ~= nil then
		-- Brought down where it burst: the last few studs, accelerating into the point (Quint In).
		local t = math.clamp((now - landing.At) / VfxTimelineConfig.Land.Seconds, 0, 1)
		part.CFrame = landing.From:Lerp(CFrame.new(landing.To) * landing.From.Rotation, t ^ 5)
		return
	end
	local layer = entry.Layer
	local flight = if entry.Seconds > 0 then math.clamp((now - entry.StartedAt) / entry.Seconds, 0, 1) else 1
	local share = layer.EaseShare or 1
	local progress = (1 - share) * flight + share * eased(layer, flight)
	local here = flightPoint(entry, progress)
	-- Along its own path, so what rides it pitches with the arc and points where it is going.
	local ahead = flightPoint(entry, progress + 1e-3) - here
	local frame = if ahead.Magnitude > 1e-6 then CFrame.lookAlong(here, ahead) else entry.Frame.Rotation + here
	local spin = layer.Spin
	if spin ~= nil then
		-- An angle, never an increment: added each frame to a frame rebuilt each frame, it was one
		-- sixtieth of the spin, and a clot said to tumble did not (D-114).
		frame = frame * CFrame.Angles(0, 0, spin * (now - entry.StartedAt))
	end
	part.CFrame = frame
end

-- A layer riding the carrier is moved with it every frame rather than being parented to it: the pool
-- hands out parts, not a hierarchy, and reparenting a pooled instance into another pooled instance is
-- how a release ends up destroying something it does not own.
local function followCarrier(entry: Live)
	-- Typed optional explicitly: Luau reads a table index as non-optional, so without this the nil
	-- guard below is dead to the analyser and a play whose carrier has already ended would index it.
	local carrier: BasePart? = carriers[entry.PlayId]
	if carrier == nil or carrier.Parent == nil then
		return
	end
	local primary = entry.Primary
	if primary == nil then
		return
	end
	local anchor = if primary:IsA("BasePart") then primary :: BasePart else primary.Parent
	if anchor ~= nil and anchor:IsA("BasePart") then
		local layer = entry.Layer
		local scale = entry.Scales.Offset
		local offset = layer.Offset
		if offset == nil then
			anchor.CFrame = carrier.CFrame
		else
			anchor.CFrame = carrier.CFrame * CFrame.new(offset[1] * scale, offset[2] * scale, -offset[3] * scale)
		end
	end
end

-- The same as followCarrier, against the body the renderer passed rather than against a carrier this
-- timeline created. This is what keeps a zone drawn where the server is actually damaging.
local function followBody(entry: Live)
	local body = entry.Context.Follow
	if body == nil or body.Parent == nil then
		return
	end
	local primary = entry.Primary
	if primary == nil then
		return
	end
	local anchor = if primary:IsA("BasePart") then primary :: BasePart else primary.Parent
	-- A following Trail is adorned to the body itself, so the anchor IS the body: writing its CFrame
	-- back is a same-value write today and, with an Offset, would compound that offset every frame
	-- and fling the character. A layer that follows the caster must never be able to move the caster.
	if anchor == body then
		return
	end
	if anchor ~= nil and anchor:IsA("BasePart") then
		local layer = entry.Layer
		local scale = entry.Scales.Offset
		local offset = layer.Offset
		if offset == nil then
			anchor.CFrame = body.CFrame
		else
			anchor.CFrame = body.CFrame * CFrame.new(offset[1] * scale, offset[2] * scale, -offset[3] * scale)
		end
	end
end

local function stepEmitter(entry: Live, now: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local emitter = primary :: ParticleEmitter
	-- A continuous emitter emits for exactly the life its layer declares. The entry itself is kept until
	-- its last particle can have died (VfxTimelineConfig.layerSeconds), so the cloud thins out by itself
	-- instead of vanishing with its emitter. It used to stop at 85 % of the layer -- read off the eased
	-- value, 65 % for 26 of them -- and was released at 100 % with the cloud still in the air.
	if entry.Layer.Rate ~= nil and now - entry.StartedAt >= entry.Seconds then
		emitter.Enabled = false
	end
end

--------------------------------------------------------------------------------------------------
-- Scheduling
--------------------------------------------------------------------------------------------------

local function releaseLive(entry: Live)
	local carrier: BasePart? = carriers[entry.PlayId]
	if entry.Layer.Kind == "Carrier" and carrier == entry.Primary then
		carriers[entry.PlayId] = nil
		-- Flown out with no burst to land it: nothing is left to land.
		local shot = entry.Context.Shot
		if shot ~= nil and shots[shot] == entry.PlayId then
			shots[shot] = nil
		end
	end
	-- Each instance is released on its own. A Trail rides a part the effect does not own -- the caster's
	-- root -- and that part can be destroyed mid-effect by a respawn, taking the attachments parented to
	-- it with it. One dead instance must not strand the dozen live ones behind it in the same layer, and
	-- swallowing the error silently would hide a real pooling bug, so it goes through Log.try and is
	-- named in the output.
	for index = #entry.Instances, 1, -1 do
		local instance = entry.Instances[index]
		log.try("release " .. instance.ClassName, pool.release, instance)
	end
	table.clear(entry.Instances)
	entry.Primary = nil
end

local function activate(item: Pending, now: number)
	local id = item.Id
	local layer = item.Layer
	local context = item.Context

	if layer.Kind == "Shake" then
		local profile = layer.Profile
		if profile ~= nil then
			feel.shakeAt(profile, context.Origin)
		end
		return
	end
	if layer.Kind == "Flash" then
		local profile = layer.Profile
		if profile == nil then
			return
		end
		-- A screen pulse is a sensation, not a thing in the world, so it is gated by distance exactly the
		-- way a camera shake is. Without this, a hit landing across the arena would overexpose the page
		-- for a player who is not in that fight, which is the same defect the four-stud radius test used
		-- to cause in reverse.
		local root = localRoot()
		if root == nil then
			return
		end
		local reach = FeelMath.falloff((root.Position - context.Origin).Magnitude, FeelConfig.Shake.FalloffRadiusStuds)
		if reach <= FeelConfig.Shake.MinScale then
			return
		end
		-- The same falloff that decided whether to flash at all decides how hard, so a hit across the
		-- arena is a hint of a bleach and one in your face is the full page.
		--
		-- WorldLighting owns the warning for an unknown pulse, and tests/VfxTimeline.spec.luau already
		-- fails the build for a timeline naming one that LightingConfig does not declare, so there is
		-- nothing left for this call to check.
		worldLighting.pulse(profile, reach)
		return
	end

	if layer.Kind == "Sound" then
		-- Fire and forget, like the two above: the sound owns its own lifetime through SoundController.
		local key: string? = layer.Sfx
		if key == nil then
			local voice = layer.Voice
			local pigment = context.Pigment
			if voice ~= nil and pigment ~= nil then
				key = SoundConfig.voiceKey(pigment, voice)
			end
		end
		if key == nil then
			if not warnedVoices[id] then
				warnedVoices[id] = true
				log.warn("timeline %s has a sound that names a voice, and the renderer passed no pigment", id)
			end
			return
		end
		-- Placed where the layer would be drawn: on the carrier for a flight, on the body for a zone
		-- the server moves with the caster, at its offset otherwise. A projectile's tail heard from the
		-- cast point is a tail that stays behind.
		local carrier: BasePart? = if layer.Ride == true then carriers[item.PlayId] else nil
		local body: BasePart? = if layer.Follow == true then context.Follow else nil
		local anchor: BasePart? = nil
		local position: Vector3
		if carrier ~= nil and carrier.Parent ~= nil then
			anchor = carrier
			position = carrier.Position
		elseif body ~= nil and body.Parent ~= nil then
			anchor = body
			position = body.Position
		else
			position = placeOf(frameOf(context), layer, context.Scale or 1).Position
		end
		-- Anchored to the part rather than to a point, so a tail flies with the body it is the tail of.
		-- The Sound is parented to a pooled part; SoundController's Debris net destroys the Sound itself,
		-- so the part goes back to the pool clean.
		sound.play(key, position, { Fit = if layer.Fit == true then item.Seconds else nil, Anchor = anchor })
		local duck = layer.Duck
		if duck ~= nil and duck > 0 then
			sound.duck(duck)
		end
		return
	end

	-- What this client may hold right now: the player's graphics setting, lowered by the frame rate if it
	-- has had to be (Config/QualityConfig). Read per layer, so a tier that changes mid-fight thins the
	-- next layer rather than the next effect.
	local tier: QualityConfig.TierDef = quality.def()
	if layer.Kind == "Emitter" and expectedParticles(layer, item.Seconds, tier.ParticleScale) < 1 then
		-- At this density the layer would emit nothing: a part, an emitter and a slot of the budget spent
		-- on no particles at all. Not drawn, which is the whole point of a tier.
		return
	end
	if layer.Kind == "Light" and not tier.Lights then
		-- A light is the first thing a struggling client stops paying for: Roblox pays for a local light
		-- whether or not it ends up lit. Nothing a player has to READ is a light -- every telegraph is a
		-- mark -- so dropping them thins the picture without touching a rule.
		return
	end

	if #live >= tier.Layers then
		-- Art bible rule 8: density is capped. Past the cap the oldest layer is retired early, so a
		-- six-player exchange loses effects rather than frames -- but never a warning. A telegraph is
		-- laid at the start of a two-second window and is the longest-lived thing on screen, so "oldest
		-- first" would retire exactly the layers six players are reading, in the fight that fills the
		-- budget. The oldest ordinary layer goes instead; if there is none, an ordinary newcomer is the
		-- one not drawn, and a warning is drawn over budget.
		-- Never a warning, and never a CARRIER. A carrier is an invisible part that flies, and everything
		-- visible about a projectile is some other layer riding it: retiring the carrier frees one layer of
		-- budget, keeps every instance it was carrying, and leaves the trail and the smoke frozen at the
		-- cast point while the server's projectile flies on. It is also the oldest layer of its own play,
		-- so "oldest first" chose it first -- which never mattered while the budget was ninety and became
		-- routine the moment the lower tiers arrived.
		local victim: number? = nil
		for index, entry in ipairs(live) do
			if not entry.Warning and entry.Layer.Kind ~= "Carrier" then
				victim = index
				break
			end
		end
		if victim ~= nil then
			local retired = table.remove(live, victim)
			if retired ~= nil then
				releaseLive(retired)
			end
		elseif not item.Warning then
			return
		end
		if not overBudgetWarned then
			overBudgetWarned = true
			log.warn("vfx layer budget of %d reached; oldest layers are retired early", tier.Layers)
		end
	end

	if layer.Follow == true and context.Follow == nil then
		-- Nothing to follow: a ribbon between two attachments that never separate draws nothing, and a
		-- zone pinned to a body that was never passed would sit at the cast point lying about where the
		-- damage is. Skipped, and said once so the gap is visible rather than merely invisible.
		if not warnedFollow[id] then
			warnedFollow[id] = true
			log.warn("timeline %s has a layer that follows the caster, and the renderer passed no body", id)
		end
		return
	end
	local scales = scalesOf(context, layer)
	if scales == nil then
		-- The layer is written against the shape the server is damaging and this play did not carry it.
		-- Drawing it against the effect's scale instead would paint a warning a fraction of the size of
		-- the danger, which is worse than painting none, so it is skipped and named once.
		if not warnedMeasures[id] then
			warnedMeasures[id] = true
			log.warn("timeline %s measures a layer against a length the renderer did not pass", id)
		end
		return
	end

	local base = frameOf(context)
	local rider = if layer.Ride == true then carriers[item.PlayId] else nil
	if rider ~= nil then
		-- The carrier's own frame, not the origin: a layer that rides is placed where the body IS at the
		-- moment it starts, which for a layer scheduled mid-flight is not where the cast began.
		base = rider.CFrame
	end
	local place = placeOf(base, layer, scales.Offset)
	local seconds = math.min(item.Seconds, VfxTimelineConfig.MaxLayerSeconds)
	-- Kept past its drawn life by whatever it leaves in the air (an emitter's particles), up to the backstop.
	local lives = math.min(VfxTimelineConfig.layerSeconds(layer, item.Seconds), VfxTimelineConfig.MaxLayerSeconds)
	if context.Shot ~= nil and (layer.Kind == "Carrier" or layer.Ride == true) then
		-- A thrown flight waits at its end for its burst, and what rides it waits with it.
		lives += VfxTimelineConfig.Land.Grace
	end
	local entry: Live = {
		Layer = layer,
		Context = context,
		Scales = scales,
		Frame = place,
		StartedAt = now,
		Seconds = seconds,
		EndsAt = now + lives,
		Warning = item.Warning,
		Instances = {},
		Primary = nil,
		PlayId = item.PlayId,
		PlayStartedAt = item.PlayStartedAt,
	}

	if layer.Kind == "Carrier" then
		buildCarrier(entry, place)
	elseif layer.Kind == "Sprite" then
		buildSprite(entry, layer, place)
	elseif layer.Kind == "Mark" then
		buildMark(entry, layer, place)
	elseif layer.Kind == "Emitter" then
		buildEmitter(entry, layer, place)
	elseif layer.Kind == "Light" then
		buildLight(entry, layer, place)
	elseif layer.Kind == "Beam" then
		buildBeam(entry, layer, place)
	elseif layer.Kind == "Trail" then
		buildTrail(entry, layer, place)
	end

	if entry.Primary == nil then
		-- The pool refused, so this layer is not drawn. Whatever it did manage to borrow goes straight
		-- back rather than sitting in `live` for its full duration rendering nothing.
		releaseLive(entry)
		return
	end
	table.insert(live, entry)
end

local function stepLive(entry: Live, now: number, deltaTime: number)
	local span = entry.EndsAt - entry.StartedAt
	-- Two clocks. `elapsed` is how much of the layer's life has passed; `alpha` is where its ease has
	-- carried its shape. Whatever is about time -- how far a fade has got, when an emitter stops -- reads
	-- `elapsed`: an Exponential Out layer is 85 % grown a fifth of the way in, not 85 % over.
	local elapsed = if span > 0 then math.clamp((now - entry.StartedAt) / span, 0, 1) else 1
	local alpha = eased(entry.Layer, elapsed)
	local kind = entry.Layer.Kind
	if kind == "Carrier" then
		stepCarrier(entry, now)
		return
	end
	if entry.Layer.Ride == true then
		followCarrier(entry)
	elseif entry.Layer.Follow == true then
		followBody(entry)
	end
	if kind == "Sprite" then
		stepSprite(entry, alpha, elapsed, deltaTime)
	elseif kind == "Mark" then
		stepMark(entry, alpha, elapsed, now)
	elseif kind == "Light" then
		stepLight(entry, alpha, now)
	elseif kind == "Beam" then
		stepBeam(entry, alpha, elapsed)
	elseif kind == "Emitter" then
		stepEmitter(entry, now)
	end
end

-- Whether an entry at its end must stay out of the pool a little longer. A thrown carrier that nothing
-- landed comes down where it is -- its own landing: its riders drain and what lingers is drawn there --
-- and a carrier still carrying a sound holds still, unseen, until the sound is over: released with it, a
-- tail went on playing inside the pool and could follow the next effect that borrowed the part (review).
local function settle(entry: Live, now: number): boolean
	local primary = entry.Primary
	if entry.Layer.Kind ~= "Carrier" or primary == nil or not primary:IsA("BasePart") then
		return false
	end
	local shot = entry.Context.Shot
	if entry.Landing == nil and shot ~= nil and shots[shot] == entry.PlayId then
		return VfxTimeline.land(shot, primary.Position)
	end
	local tail = 0
	for _, child in ipairs(primary:GetChildren()) do
		if child:IsA("Sound") and child.IsPlaying and not child.Looped then
			tail = math.max(tail, (child.TimeLength - child.TimePosition) / math.max(child.PlaybackSpeed, 1e-3))
		end
	end
	if tail <= 0 then
		return false
	end
	entry.EndsAt = now + math.min(tail, VfxTimelineConfig.MaxLayerSeconds)
	return true
end

local function onHeartbeat(deltaTime: number)
	local now = os.clock()

	local index = 1
	while index <= #pending do
		local item = pending[index]
		if now >= item.At then
			table.remove(pending, index)
			activate(item, now)
		else
			index += 1
		end
	end

	index = 1
	while index <= #live do
		local entry = live[index]
		if now >= entry.EndsAt and not settle(entry, now) then
			releaseLive(entry)
			table.remove(live, index)
		else
			stepLive(entry, now, deltaTime)
			index += 1
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------------------------

-- Queues every layer of `id` against `context`. Returns false for an unknown id, which the caller logs
-- once; a missing timeline must not stop the packet that asked for it from doing everything else.
function VfxTimeline.play(id: string, context: Context): boolean
	local timeline = VfxTimelineConfig.Timelines[id]
	if timeline == nil then
		return false
	end
	local now = os.clock()
	nextPlayId += 1
	local playId = nextPlayId
	if context.Shot ~= nil then
		shots[context.Shot] = playId
	end
	local phaseStart = 0
	for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == name then
				-- A windowed phase lasts as long as the packet says, and its layers declare fractions of
				-- it rather than seconds. Everything after it is pushed back by the same amount, which is
				-- what keeps an impact landing at the end of the warning instead of at a time this file
				-- guessed.
				local seconds = VfxTimelineConfig.phaseSeconds(phase, context.Window)
				local factor = if phase.Window == true then seconds else 1
				for _, layer in ipairs(phase.Layers) do
					table.insert(pending, {
						Id = id,
						Layer = layer,
						Context = context,
						-- What lingers after a thrown thing is drawn where it came down, so it waits for the
						-- landing (VfxTimeline.land), which every thrown flight ends in.
						At = if context.Shot ~= nil and name == "Residue"
							then math.huge
							else now + phaseStart + layer.At * factor,
						Seconds = layer.For * factor,
						Warning = phase.Window == true,
						PlayId = playId,
						PlayStartedAt = now,
						Phase = name :: string,
					})
				end
				phaseStart += seconds
			end
		end
	end
	return true
end

-- Brings the play carrying `shot` down at `point`, where the server burst it or where it fizzled (D-114).
-- Without this a Brand that hit at twenty studs flew on alone to ninety -- trail, smoke and light included
-- -- and one whose caster was stunned mid-flight did the same. What is still to fly is dropped; the carrier
-- glides the last few studs to the point and holds; what rode it drains out on its own terms; and what
-- lingers after the flight is re-placed at the point. False when no play is flying that shot.
function VfxTimeline.land(shot: string, point: Vector3): boolean
	local playId = shots[shot]
	if playId == nil then
		return false
	end
	shots[shot] = nil
	local now = os.clock()
	local settings = VfxTimelineConfig.Land
	local index = 1
	while index <= #pending do
		local item = pending[index]
		if item.PlayId == playId and item.Phase == "Travel" then
			table.remove(pending, index)
		else
			if item.PlayId == playId and item.Phase == "Residue" then
				local moved = table.clone(item.Context)
				moved.Origin = point
				item.Context = moved
				item.At = now + settings.Seconds + item.Layer.At
			end
			index += 1
		end
	end
	for _, entry in ipairs(live) do
		local primary = entry.Primary
		if entry.PlayId == playId and primary ~= nil then
			if entry.Layer.Kind == "Carrier" and primary:IsA("BasePart") then
				entry.Landing = { From = primary.CFrame, To = point, At = now }
				entry.EndsAt = now + settings.Seconds + settings.Hold
			elseif entry.Layer.Ride == true then
				if primary:IsA("Trail") then
					-- It stops drawing and its ribbon runs out behind it.
					primary.Enabled = false
					entry.EndsAt = now + primary.Lifetime
				elseif primary:IsA("ParticleEmitter") then
					primary.Enabled = false
					entry.EndsAt = now + primary.Lifetime.Max
				elseif primary:IsA("PointLight") then
					entry.Ending = { At = now, From = primary.Brightness }
					entry.EndsAt = now + settings.Fade
				end
			end
		end
	end
	return true
end

-- Queues ONE layer that belongs to no timeline -- a footprint, drawn by FootprintController -- through
-- the same pool, ground probe, budget and eviction as every timeline layer. `id` names it in the
-- runtime's warnings. A layer that is not a Mark is refused: everything else is an effect, and effects
-- are timelines.
function VfxTimeline.stamp(id: string, layer: Layer, context: Context): boolean
	if layer.Kind ~= "Mark" then
		return false
	end
	nextPlayId += 1
	local now = os.clock()
	table.insert(pending, {
		Id = id,
		Layer = layer,
		Context = context,
		At = now + layer.At,
		Seconds = layer.For,
		Warning = false,
		PlayId = nextPlayId,
		PlayStartedAt = now,
		Phase = "Residue",
	})
	return true
end

-- Everything on screen, released. Called when the local character goes away: a layer adorned to a part of
-- the previous life would otherwise follow the player into the next one.
function VfxTimeline.clear()
	table.clear(pending)
	for index = #live, 1, -1 do
		releaseLive(live[index])
	end
	table.clear(live)
	table.clear(carriers)
	table.clear(shots)
end

-- What the runtime is carrying right now. docs/PERFORMANCE.md reads it, and so does anyone wondering
-- whether an effect leaked.
function VfxTimeline.stats(): { Pending: number, Live: number }
	return { Pending = #pending, Live = #live }
end

function VfxTimeline.Init(deps: Deps)
	pool = deps.VfxPool
	feel = deps.Feel
	quality = deps.QualityController
	worldLighting = deps.WorldLighting
	sound = deps.SoundController
end

function VfxTimeline.Start()
	-- One connection for every layer of every effect, for the life of the session. It is never
	-- disconnected because there is no moment at which the client stops wanting effects; clear()
	-- handles the only thing that actually has to be released, which is the instances.
	RunService.Heartbeat:Connect(onHeartbeat)
	player.CharacterRemoving:Connect(VfxTimeline.clear)
	for _, other in ipairs(Players:GetPlayers()) do
		watchCharacters(other)
	end
	Players.PlayerAdded:Connect(watchCharacters)
	Players.PlayerRemoving:Connect(markGroundExcludeStale)
	local missing = AssetIds.missing()
	if #missing > 0 then
		log.warn(
			"%d texture(s) not uploaded yet, effects draw untextured until they are: %s",
			#missing,
			table.concat(missing, ", ")
		)
	end
	log.info("started (%d timelines)", #VfxTimelineConfig.PhaseOrder)
end

return VfxTimeline
