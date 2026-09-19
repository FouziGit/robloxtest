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
local VfxTimelineConfig = require(Shared.Config.VfxTimelineConfig)

local log = Log.new("VfxTimeline")

type Deps = { VfxPool: any, Feel: any, WorldLighting: any }

export type Context = {
	Origin: Vector3,
	Direction: Vector3,
	Color: Color3,
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
	Instances: { Instance },
	Primary: Instance?,
	-- Which call to play() this layer came from. Layers of one play share a carrier, and two casts in
	-- flight at once must not ride each other's.
	PlayId: number,
}

type Pending = {
	Id: string,
	Layer: Layer,
	Context: Context,
	At: number,
	-- Seconds, resolved against the window of the phase it belongs to.
	Seconds: number,
	PlayId: number,
}

local VfxTimeline = {}

local pool: any
local feel: any
local worldLighting: any

local player = Players.LocalPlayer
local pending: { Pending } = {}
local live: { Live } = {}
local warnedTextures: { [string]: boolean } = {}
-- The travelling body of each play that has one, while it has one. Cleared when its Carrier layer
-- ends, so a layer that outlives the flight falls back to standing still rather than following a
-- part that has gone back to the pool.
local carriers: { [number]: BasePart } = {}
local warnedFollow: { [string]: boolean } = {}
local warnedMeasures: { [string]: boolean } = {}
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

-- The ground under a point, for the marks every impact leaves. Falls back to the point itself rather than
-- skipping the mark: a trace slightly off the floor is better than a world that forgets.
local function groundAt(position: Vector3): (Vector3, Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	if character ~= nil then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(position + Vector3.yAxis, Vector3.yAxis * -GROUND_PROBE_STUDS, params)
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
		log.warn("texture %s has no id yet: upload %s and paste it into AssetIds", key, asset.Source)
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
	if textureMissing(layer) then
		return
	end
	local position, normal = groundAt(place.Position)
	local offset: { number }? = layer.Offset
	-- Lifted a hair off the floor, plus whatever the layer's up offset asks for: a decal coplanar with
	-- the ground z-fights, and so do two decals coplanar with each other.
	local lift = if offset ~= nil then offset[2] * entry.Scales.Offset else 0
	local part = host(entry, markFrame(position, normal, place.LookVector, lift), planeSize(entry, 0))
	local decalInstance = borrow(entry, "Decal")
	if part == nil or decalInstance == nil then
		return
	end
	part.Transparency = 1
	local id = textureOf(layer)
	local decal = decalInstance :: Decal
	decal.Texture = id
	decal.Face = Enum.NormalId.Front
	decal.Color3 = entry.Context.Color
	decal.Transparency = layer.Transparency or 0.3
	decal.Parent = part
	entry.Primary = part
end

local function buildEmitter(entry: Live, layer: Layer, place: CFrame)
	local scale = entry.Scales.Effect
	local part = host(entry, place, Vector3.one * 0.2)
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
	emitter.Color = ColorSequence.new(entry.Context.Color)
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
	local speed = layer.Speed or { 0, 0 }
	emitter.Speed = NumberRange.new(speed[1] * scale, speed[2] * scale)
	local lifetime = layer.Lifetime or { 0.3, 0.6 }
	emitter.Lifetime = NumberRange.new(lifetime[1], lifetime[2])
	emitter.SpreadAngle = Vector2.new(layer.Spread or 0, layer.Spread or 0)
	emitter.Drag = layer.Drag or 0
	-- Squash below 1 stretches a particle along its travel, which is what makes a spark read as moving
	-- rather than as a dot that is somewhere else next frame.
	emitter.Squash = NumberSequence.new(layer.Squash or 0)
	-- Wind drags the residue with the world instead of leaving it hanging in still air.
	emitter.WindAffectsDrag = true
	emitter.LightEmission = 0.35
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = part

	local flipbookKey = layer.Texture
	if flipbookKey ~= nil and AssetIds.frameCount(flipbookKey) == 64 then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
		emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end

	if layer.Burst ~= nil then
		emitter:Emit(math.floor(layer.Burst))
	end
	if layer.Rate ~= nil then
		emitter.Rate = layer.Rate
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
	beam.LightEmission = 0.4
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
	trail.Color = ColorSequence.new(entry.Context.Color)
	trail.Lifetime = entry.Seconds
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, layer.Transparency or 0.3),
		NumberSequenceKeypoint.new(1, layer.EndTransparency or 1),
	})
	trail.LightEmission = 0.3
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

local function stepSprite(entry: Live, alpha: number, deltaTime: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local part = primary :: BasePart
	local layer = entry.Layer
	part.Size = planeSize(entry, alpha)
	local transparency = math.clamp(lerp(layer.Transparency, layer.EndTransparency, alpha, 0), 0, 1)
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

local function stepMark(entry: Live, alpha: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local part = primary :: BasePart
	local layer = entry.Layer
	part.Size = planeSize(entry, alpha)
	local transparency = math.clamp(lerp(layer.Transparency, layer.EndTransparency, alpha, 0.3), 0, 1)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") then
			child.Transparency = transparency
		end
	end
end

local function stepLight(entry: Live, alpha: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local light = primary :: PointLight
	-- A light changes by brightness, never by being removed: an instant cut reads as a bug, and art bible
	-- rule 3 forbids anything appearing or vanishing outright. EndBrightness absent means zero, so the
	-- default is the fade it always was, and a telegraph can ask for the opposite.
	local layer = entry.Layer
	light.Brightness = math.max(lerp(layer.Brightness, layer.EndBrightness or 0, alpha, 1), 0)
end

local function stepBeam(entry: Live, alpha: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local beam = primary :: Beam
	local layer = entry.Layer
	local width = lerp(layer.Size, layer.EndSize, alpha, 1) * entry.Scales.Size
	beam.Width0 = math.max(width, 0)
	beam.Width1 = math.max(width * 0.35, 0)
	beam.Transparency =
		NumberSequence.new(math.clamp(lerp(layer.Transparency, layer.EndTransparency, alpha, 0.2), 0, 1))
end

-- Flight. The body travels its declared distance over its own duration, eased, and rises and falls by
-- Arc along the way: a thrown thing does not travel a straight line at a constant speed, and art bible
-- rule 4 forbids the linear version outright.
local function stepCarrier(entry: Live, alpha: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local part = primary :: BasePart
	local layer = entry.Layer
	local scale = entry.Scales.Effect
	local distance = (layer.Travel or 0) * scale * alpha
	-- A half sine: zero at both ends, highest in the middle. Multiplied by the arc rather than added to
	-- it, so a timeline with no Arc travels flat and pays nothing for the option.
	local rise = (layer.Arc or 0) * scale * math.sin(math.clamp(alpha, 0, 1) * math.pi)
	part.CFrame = entry.Frame * CFrame.new(0, 0, -distance) + Vector3.new(0, rise, 0)
	local spin = layer.Spin
	if spin ~= nil then
		part.CFrame = part.CFrame * CFrame.Angles(0, 0, spin * (1 / 60))
	end
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

local function stepEmitter(entry: Live, alpha: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local emitter = primary :: ParticleEmitter
	-- A continuous emitter is switched off before its layer ends so the particles already in the air have
	-- time to finish, instead of the whole cloud disappearing with its emitter.
	if entry.Layer.Rate ~= nil and alpha > 0.85 then
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

	if #live >= VfxTimelineConfig.MaxLiveLayers then
		-- Art bible rule 8: density is capped. Past the cap the oldest layer is retired early, so a
		-- six-player exchange loses effects rather than frames.
		local oldest = table.remove(live, 1)
		if oldest ~= nil then
			releaseLive(oldest)
		end
		if not overBudgetWarned then
			overBudgetWarned = true
			log.warn("vfx layer budget of %d reached; oldest layers are retired early", VfxTimelineConfig.MaxLiveLayers)
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
	local entry: Live = {
		Layer = layer,
		Context = context,
		Scales = scales,
		Frame = place,
		StartedAt = now,
		Seconds = seconds,
		EndsAt = now + seconds,
		Instances = {},
		Primary = nil,
		PlayId = item.PlayId,
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
	local alpha = if span > 0 then eased(entry.Layer, (now - entry.StartedAt) / span) else 1
	local kind = entry.Layer.Kind
	if kind == "Carrier" then
		stepCarrier(entry, alpha)
		return
	end
	if entry.Layer.Ride == true then
		followCarrier(entry)
	elseif entry.Layer.Follow == true then
		followBody(entry)
	end
	if kind == "Sprite" then
		stepSprite(entry, alpha, deltaTime)
	elseif kind == "Mark" then
		stepMark(entry, alpha)
	elseif kind == "Light" then
		stepLight(entry, alpha)
	elseif kind == "Beam" then
		stepBeam(entry, alpha)
	elseif kind == "Emitter" then
		stepEmitter(entry, alpha)
	end
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
		if now >= entry.EndsAt then
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
						At = now + phaseStart + layer.At * factor,
						Seconds = layer.For * factor,
						PlayId = playId,
					})
				end
				phaseStart += seconds
			end
		end
	end
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
end

-- What the runtime is carrying right now. docs/PERFORMANCE.md reads it, and so does anyone wondering
-- whether an effect leaked.
function VfxTimeline.stats(): { Pending: number, Live: number }
	return { Pending = #pending, Live = #live }
end

function VfxTimeline.Init(deps: Deps)
	pool = deps.VfxPool
	feel = deps.Feel
	worldLighting = deps.WorldLighting
end

function VfxTimeline.Start()
	-- One connection for every layer of every effect, for the life of the session. It is never
	-- disconnected because there is no moment at which the client stops wanting effects; clear()
	-- handles the only thing that actually has to be released, which is the instances.
	RunService.Heartbeat:Connect(onHeartbeat)
	player.CharacterRemoving:Connect(VfxTimeline.clear)
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
