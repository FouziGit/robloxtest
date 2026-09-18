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
	-- A part the effect rides: a projectile, or the caster's root. Layers that need a moving anchor
	-- (Trail, and anything whose Offset should follow the body) use it; the rest are placed once in world
	-- space, which is what an impact wants.
	Follow: BasePart?,
}

type Layer = VfxTimelineConfig.Layer

-- One layer in flight. `Instances` is everything it borrowed, released together when it ends.
type Live = {
	Layer: Layer,
	Context: Context,
	Frame: CFrame,
	StartedAt: number,
	EndsAt: number,
	Instances: { Instance },
	Primary: Instance?,
}

type Pending = {
	Layer: Layer,
	Context: Context,
	At: number,
}

local VfxTimeline = {}

local pool: any
local feel: any
local worldLighting: any

local player = Players.LocalPlayer
local pending: { Pending } = {}
local live: { Live } = {}
local warnedTextures: { [string]: boolean } = {}
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

local function buildSprite(entry: Live, layer: Layer, place: CFrame, scale: number)
	local size = (layer.Size or 1) * scale
	local part = host(entry, place, Vector3.new(size, size, 0.05))
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

local function buildMark(entry: Live, layer: Layer, place: CFrame, scale: number)
	local position, normal = groundAt(place.Position)
	local size = (layer.Size or 1) * scale
	-- Lifted a hair off the floor: a decal coplanar with the ground z-fights, which reads as flicker.
	local part =
		host(entry, CFrame.lookAt(position + normal * 0.03, position + normal) * LYING, Vector3.new(size, size, 0.05))
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

local function buildEmitter(entry: Live, layer: Layer, place: CFrame, scale: number)
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
	local size = (layer.Size or 1) * scale
	local endSize = (layer.EndSize or size / scale) * scale
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

local function buildLight(entry: Live, layer: Layer, place: CFrame, scale: number)
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
	light.Range = (layer.Range or 8) * scale
	light.Brightness = layer.Brightness or 1
	light.Shadows = false
	light.Parent = part
	entry.Primary = light
end

-- Two attachments and a Beam between them. CurveSize is what draws a stroke rather than a laser: the art
-- direction's "un trait qui se dessine est un Beam dont on anime CurveSize".
local function buildBeam(entry: Live, layer: Layer, place: CFrame, scale: number)
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

local function buildTrail(entry: Live, layer: Layer, place: CFrame, scale: number)
	local anchor: BasePart? = entry.Context.Follow or host(entry, place, Vector3.one * 0.2)
	local a0Instance = borrow(entry, "Attachment")
	local a1Instance = borrow(entry, "Attachment")
	local trailInstance = borrow(entry, "Trail")
	if anchor == nil or a0Instance == nil or a1Instance == nil or trailInstance == nil then
		return
	end
	local width = (layer.Size or 1) * scale
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
	trail.Lifetime = layer.For
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
	local scale = entry.Context.Scale or 1
	local size = lerp(layer.Size, layer.EndSize, alpha, 1) * scale
	part.Size = Vector3.new(size, size, 0.05)
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
	local scale = entry.Context.Scale or 1
	local size = lerp(layer.Size, layer.EndSize, alpha, 1) * scale
	part.Size = Vector3.new(size, size, 0.05)
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
	-- A light fades by brightness, never by being removed: an instant cut reads as a bug, and art bible
	-- rule 3 forbids anything appearing or vanishing outright.
	light.Brightness = (entry.Layer.Brightness or 1) * (1 - alpha)
end

local function stepBeam(entry: Live, alpha: number)
	local primary = entry.Primary
	if primary == nil or primary.Parent == nil then
		return
	end
	local beam = primary :: Beam
	local layer = entry.Layer
	local scale = entry.Context.Scale or 1
	local width = lerp(layer.Size, layer.EndSize, alpha, 1) * scale
	beam.Width0 = math.max(width, 0)
	beam.Width1 = math.max(width * 0.35, 0)
	beam.Transparency =
		NumberSequence.new(math.clamp(lerp(layer.Transparency, layer.EndTransparency, alpha, 0.2), 0, 1))
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
	local layer = item.Layer
	local context = item.Context
	local scale = context.Scale or 1

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
		-- WorldLighting owns the warning for an unknown pulse, and tests/VfxTimeline.spec.luau already
		-- fails the build for a timeline naming one that LightingConfig does not declare, so there is
		-- nothing left for this call to check.
		worldLighting.pulse(profile)
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

	local base = frameOf(context)
	local place = placeOf(base, layer, scale)
	local entry: Live = {
		Layer = layer,
		Context = context,
		Frame = place,
		StartedAt = now,
		EndsAt = now + math.min(layer.For, VfxTimelineConfig.MaxLayerSeconds),
		Instances = {},
		Primary = nil,
	}

	if layer.Kind == "Sprite" then
		buildSprite(entry, layer, place, scale)
	elseif layer.Kind == "Mark" then
		buildMark(entry, layer, place, scale)
	elseif layer.Kind == "Emitter" then
		buildEmitter(entry, layer, place, scale)
	elseif layer.Kind == "Light" then
		buildLight(entry, layer, place, scale)
	elseif layer.Kind == "Beam" then
		buildBeam(entry, layer, place, scale)
	elseif layer.Kind == "Trail" then
		buildTrail(entry, layer, place, scale)
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
	local phaseStart = 0
	for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == name then
				for _, layer in ipairs(phase.Layers) do
					table.insert(pending, { Layer = layer, Context = context, At = now + phaseStart + layer.At })
				end
				phaseStart += phase.Duration
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
