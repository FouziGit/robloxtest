--!strict
-- VfxLibrary: client renderers for the Vfx / VfxReliable packets broadcast by the server. One function
-- per packet Id, called by VfxController with a fresh trove that is destroyed after the packet lifetime.
-- Every part, tween, connection and delayed thread is tracked by that trove, particle rates are capped,
-- and nothing yields on the caller thread: timed steps run in task.delay threads owned by the trove.
-- The server never builds visuals; it only sends {Id, Origin, Direction, Caster, Targets, Params}.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
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
	ElementColor: (element: string) -> Color3,
	LocalCharacter: () -> Model?,
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
local HIT_FEEDBACK_RADIUS_STUDS = 4
local SHAKE_FALLOFF_STUDS = 45 -- large shakes fade linearly with the distance to the local character
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local WHITE = Color3.fromRGB(255, 245, 220)
local SHIELD_COLOR = Color3.fromRGB(120, 190, 255)
local GUARD_BREAK_COLOR = Color3.fromRGB(255, 120, 90)
local FIRE_SECONDARY_COLOR = Color3.fromRGB(255, 220, 120)

local SPIKE_RISE_SECONDS = 0.12
local SPIKE_HOLD_SECONDS = 1.5
local SPIKE_SINK_SECONDS = 0.4
local WALL_RISE_SECONDS = 0.3
local WALL_SINK_SECONDS = 0.5
local RING_FADE_SECONDS = 0.5
local EMBER_COUNT = 8
local EMBER_SPIN_RADIANS_PER_SECOND = math.pi * 1.5
local SHOCKWAVE_COUNT = 3
local SHOCKWAVE_STAGGER_SECONDS = 0.12
local MELEE_SFX_VARIANTS = 3 -- SoundConfig has Melee1..Melee3 plus MeleeFinisher

-- Phase 2 roster tuning (docs/GAME_DESIGN.md §5)
local LYING_CYLINDER = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: stand it upright
local SMOKE_COLOR = Color3.fromRGB(70, 62, 58)
local EMBER_POOL_THICKNESS = 0.4
local METEOR_SPIN_RADIANS_PER_SECOND = math.pi
local METEOR_BREAK_SECONDS = 0.35
local PRISON_RADIUS_STUDS = 4.5
local MUD_SPLAT_SECONDS = 0.45
local EMBER_TRAIL_SEGMENTS = 5 -- fallback when a packet carries no trail points
local EMBER_TRAIL_SPACING_STUDS = 4
local STONE_PLATE_COUNT = 6
local STONE_PLATE_GAP_FACTOR = 0.9 -- plate width as a share of its arc: slits the caster sees through
local STONE_PLATE_TRANSPARENCY = 0.3 -- an opaque shell would blind the caster it protects
local STONE_SPIN_RADIANS_PER_SECOND = math.pi * 0.35
local STONE_CRUMBLE_SECONDS = 0.3
local BLADE_SPIN_RADIANS = math.rad(170) -- CFrame tweens slerp: a spin past half a turn plays backwards
local CYCLONE_RING_COUNT = 4
local CYCLONE_RING_THICKNESS = 1.2
local CYCLONE_HEIGHT_STUDS = 16
local CYCLONE_SPIN_RADIANS_PER_SECOND = math.pi * 1.2
local CYCLONE_WISP_COUNT = 6
local CYCLONE_TICK_SECONDS = 0.6 -- fallback tick: one wisp spiral per zone tick
local BOLT_SEGMENTS = 4
local BOLT_JITTER_STUDS = 1.6
local STATIC_ARC_JITTER_STUDS = 0.5 -- ground arcs stay flat so no joint sinks under the floor
local BOLT_THICKNESS_STUDS = 0.45
local BOLT_FADE_SECONDS = 0.18
local STATIC_ARCS_PER_TICK = 2
local STATIC_TICK_SECONDS = 0.7
local RAIJIN_LINK_DELAY_SECONDS = 0.07
local RAIJIN_SKY_HEIGHT_STUDS = 40
local RAIJIN_BOLT_THICKNESS_STUDS = 0.7

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

local function getFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
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

-- Ground point under `position` (a root-height origin); falls back to root height when nothing is hit.
local function groundAt(position: Vector3): Vector3
	local exclude: { Instance } = { getFolder() }
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character ~= nil then
			table.insert(exclude, character)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
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

local function addTrail(parent: BasePart, color: Color3, halfWidth: number, lifetime: number): Trail
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, halfWidth, 0)
	top.Parent = parent
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -halfWidth, 0)
	bottom.Parent = parent
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = lifetime
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = parent
	return trail
end

local function localRoot(api: Api): BasePart?
	local character = api.LocalCharacter()
	if character == nil then
		return nil
	end
	local root: Instance? = character:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Shakes the local camera with an intensity that fades with the distance to `origin`.
local function shakeNear(api: Api, origin: Vector3, intensity: number)
	local root = localRoot(api)
	if root == nil then
		return
	end
	local distance = (root.Position - origin).Magnitude
	local falloff = 1 - math.clamp(distance / SHAKE_FALLOFF_STUDS, 0, 1)
	if falloff > 0 then
		api.Shake(intensity * falloff)
	end
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
	local character = player.Character
	if character == nil then
		return nil
	end
	local root: Instance? = character:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
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

local function clampLifetime(seconds: number, reserve: number): number
	return math.clamp(seconds, 0.1, MAX_LIFETIME_SECONDS - reserve)
end

-- Vector3 entries of packet.Targets (VfxController only checks that Targets is a table).
local function targetsOf(packet: Packet): { Vector3 }
	local points: { Vector3 } = {}
	local targets = packet.Targets
	if targets == nil then
		return points
	end
	for _, value in ipairs(targets) do
		if typeof(value) == "Vector3" then
			table.insert(points, value)
		end
	end
	return points
end

-- Endpoint of a hitscan or a teleport: the server sends the point it validated in Targets; without
-- one the effect draws the full declared distance.
local function endPointOf(packet: Packet, from: Vector3, direction: Vector3, distance: number): Vector3
	local points = targetsOf(packet)
	if #points > 0 then
		return points[1]
	end
	return from + direction * distance
end

-- Studs a fused projectile actually covers: the server also stops it at Range (stepProjectile), so
-- Speed x Fuse alone would fly the visual past the real hit point.
local function travelDistance(packet: Packet, speed: number, fuse: number, range: number): number
	return math.max(math.min(speed * fuse, numberParam(packet, "Range", range)), 0.1)
end

-- Thin neon segment spanning two points (lightning arcs).
local function newBeam(trove: TroveType, from: Vector3, to: Vector3, color: Color3, thickness: number): Part
	local offset = to - from
	local length = offset.Magnitude
	local center = from + offset * 0.5
	return newPart(trove, "Bolt", {
		Color = color,
		Size = Vector3.new(thickness, thickness, math.max(length, 0.2)),
		Transparency = 0.1,
		CFrame = if length > 1e-3 then CFrame.lookAt(center, to) else CFrame.new(center),
	})
end

-- Jagged bolt: BOLT_SEGMENTS beams from `from` to `to`, every inner joint pushed off the straight
-- line so the arc reads as lightning instead of a laser.
local function newBolt(
	trove: TroveType,
	from: Vector3,
	to: Vector3,
	color: Color3,
	thickness: number,
	jitter: number
): { Part }
	local segments: { Part } = {}
	local offset = to - from
	local length = offset.Magnitude
	if length < 1e-3 then
		return segments
	end
	local forward = offset / length
	local side = forward:Cross(Vector3.yAxis)
	if side.Magnitude < 1e-3 then
		side = forward:Cross(Vector3.xAxis)
	end
	side = side.Unit
	local up = side:Cross(forward).Unit
	local previous = from
	for index = 1, BOLT_SEGMENTS do
		local point = from + offset * (index / BOLT_SEGMENTS)
		if index < BOLT_SEGMENTS then
			local sideways = (math.random() * 2 - 1) * jitter
			local vertical = (math.random() * 2 - 1) * jitter
			point += side * sideways + up * vertical
		end
		table.insert(segments, newBeam(trove, previous, point, color, thickness))
		previous = point
	end
	return segments
end

-- Fades a group of parts out together (bolt segments, stone plates).
local function fadeParts(trove: TroveType, parts: { Part }, seconds: number)
	for _, part in ipairs(parts) do
		play(trove, part, seconds, { Transparency = 1 })
	end
end

-- Spark flash used by both ends of a lightning teleport and by every bolt impact.
local function sparkFlash(trove: TroveType, position: Vector3, color: Color3, radius: number): Part
	local flash = newPart(trove, "SparkFlash", {
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.one * 1.5,
		Transparency = 0.1,
		CFrame = CFrame.new(position),
	})
	play(trove, flash, 0.3, { Size = Vector3.one * radius, Transparency = 1 })
	local sparks = newEmitter(flash, {
		Color = color,
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(10, 20),
		Size = NumberSequence.new(0.6, 0),
	})
	burst(sparks, 16)
	return flash
end

-- Plays the jutsu's own sound when the server attached one to the packet (as the Cast packet does).
local function playPacketSound(packet: Packet, api: Api)
	local sfxId = stringParam(packet, "SfxId", "")
	if sfxId ~= "" then
		api.Sound.play(sfxId, packet.Origin)
	end
end

-- Casting flash at the caster, colored by the jutsu element, with its cast sound.
VfxLibrary.Cast = function(packet: Packet, trove: TroveType, api: Api)
	local color = api.ElementColor(stringParam(packet, "Element", ""))
	local flash = newPart(trove, "CastFlash", {
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.one * 1.5,
		Transparency = 0.15,
		CFrame = CFrame.new(packet.Origin),
	})
	play(trove, flash, 0.35, { Size = Vector3.one * 6, Transparency = 1 })
	local sparks = newEmitter(flash, {
		Color = color,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(6, 12),
		Size = NumberSequence.new(0.8, 0),
	})
	burst(sparks, 16)
	local sfxId = stringParam(packet, "SfxId", "")
	if sfxId ~= "" then
		api.Sound.play(sfxId, packet.Origin)
	end
end

-- Neon ball with fire and a trail, flying along Direction for the fuse duration.
VfxLibrary.Fireball = function(packet: Packet, trove: TroveType, api: Api)
	local direction = directionOf(packet)
	local speed = numberParam(packet, "Speed", 90)
	local fuse = clampLifetime(numberParam(packet, "Fuse", 1), 0.5)
	local spawnOffset = numberParam(packet, "SpawnOffset", 4)
	local color = api.ElementColor("Fire")
	local start = packet.Origin + direction * spawnOffset

	local ball = newPart(trove, "Fireball", {
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.one * 3,
		CFrame = CFrame.new(start),
	})
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 12
	fire.Color = color
	fire.SecondaryColor = FIRE_SECONDARY_COLOR
	fire.Parent = ball
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = 14
	light.Parent = ball
	addTrail(ball, color, 1.2, 0.35)

	play(trove, ball, fuse, { CFrame = CFrame.new(start + direction * speed * fuse) }, Enum.EasingStyle.Linear)
end

-- Expanding sphere and ember burst where a projectile or blast lands.
VfxLibrary.Explosion = function(packet: Packet, trove: TroveType, api: Api)
	local radius = numberParam(packet, "Radius", numberParam(packet, "BlastRadius", 7))
	local color = api.ElementColor(stringParam(packet, "Element", ""))
	local sphere = newPart(trove, "Explosion", {
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.one * 2,
		Transparency = 0.2,
		CFrame = CFrame.new(packet.Origin),
	})
	play(trove, sphere, 0.45, { Size = Vector3.one * radius * 2, Transparency = 1 })
	local embers = newEmitter(sphere, {
		Color = color,
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(radius * 1.5, radius * 3),
		Size = NumberSequence.new(2, 0),
		Acceleration = Vector3.new(0, -10, 0),
	})
	burst(embers, 32)
	shakeNear(api, packet.Origin, CombatConfig.Hit.CameraShakeLarge)
	api.Sound.play("ImpactExplosion", packet.Origin)
end

-- Translucent glass wave sweeping from the caster to the end of its range.
VfxLibrary.WaterWave = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local range = numberParam(packet, "Range", 40)
	local spawnOffset = numberParam(packet, "SpawnOffset", 6)
	local travelTime = clampLifetime(numberParam(packet, "TravelTime", 0.8), 0.5)
	local width = numberParam(packet, "HitRadius", 8) * 2
	local color = api.ElementColor("Water")
	local startPosition = packet.Origin + direction * spawnOffset
	local endPosition = packet.Origin + direction * range

	local wave = newPart(trove, "WaterWave", {
		Material = Enum.Material.Glass,
		Color = color,
		Size = Vector3.new(width, 6, 3),
		Transparency = 0.35,
		CFrame = CFrame.lookAt(startPosition, startPosition + direction),
	})
	local spray = newEmitter(wave, {
		Color = color,
		Rate = 30,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(4, 9),
		Size = NumberSequence.new(1.2, 0),
		Spread = Vector2.new(40, 40),
	})
	play(
		trove,
		wave,
		travelTime,
		{ CFrame = CFrame.lookAt(endPosition, endPosition + direction) },
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out
	)
	after(trove, travelTime, function()
		spray.Enabled = false
		play(trove, wave, 0.3, { Transparency = 1, Size = Vector3.new(width, 1, 3) })
	end)
end

-- Slate spikes rising one after another along Direction, then sinking back into the ground.
VfxLibrary.EarthSpikes = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local count = math.clamp(math.floor(numberParam(packet, "Count", 5)), 1, 12)
	local spacing = numberParam(packet, "Spacing", 5)
	local startOffset = numberParam(packet, "StartOffset", 6)
	local stepDelay = math.max(numberParam(packet, "StepDelay", 0.08), 0)
	local color = api.ElementColor("Earth")

	for index = 1, count do
		local center = packet.Origin + direction * (startOffset + (index - 1) * spacing)
		after(trove, (index - 1) * stepDelay, function()
			local ground = groundAt(center)
			local height = 5 + index % 3
			local rotation = CFrame.Angles(0, math.rad(index * 47), 0) * CFrame.Angles(math.rad(8), 0, math.rad(6))
			local buried = CFrame.new(ground - Vector3.new(0, height, 0)) * rotation
			local raised = CFrame.new(ground + Vector3.new(0, height * 0.45, 0)) * rotation
			local spike = newPart(trove, "EarthSpike", {
				Material = Enum.Material.Slate,
				Color = color,
				Size = Vector3.new(1.6, height, 1.6),
				CFrame = buried,
			})
			local dust = newEmitter(spike, {
				Color = color,
				Lifetime = NumberRange.new(0.4, 0.8),
				Speed = NumberRange.new(3, 6),
				Size = NumberSequence.new(1.5, 0),
			})
			burst(dust, 8)
			play(trove, spike, SPIKE_RISE_SECONDS, { CFrame = raised }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			after(trove, SPIKE_HOLD_SECONDS, function()
				play(
					trove,
					spike,
					SPIKE_SINK_SECONDS,
					{ CFrame = buried, Transparency = 1 },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
			end)
		end)
	end
end

-- Force-field sphere bursting outward in front of the caster with wind streaks along Direction.
VfxLibrary.WindGust = function(packet: Packet, trove: TroveType, api: Api)
	local direction = directionOf(packet)
	local radius = numberParam(packet, "Radius", 12)
	local offset = numberParam(packet, "Offset", 10)
	local center = packet.Origin + direction * offset
	local color = api.ElementColor("Wind")
	-- Top face oriented along Direction so the emitter streaks fly with the gust.
	local orientation = CFrame.lookAt(center, center + direction) * CFrame.Angles(math.rad(-90), 0, 0)

	local gust = newPart(trove, "WindGust", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = color,
		Size = Vector3.one * 2,
		Transparency = 0.1,
		CFrame = orientation,
	})
	play(trove, gust, 0.4, { Size = Vector3.one * radius * 2, Transparency = 1 })
	local streaks = newEmitter(gust, {
		Color = color,
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(20, 40),
		Size = NumberSequence.new(0.6, 0),
		Spread = Vector2.new(25, 25),
	})
	burst(streaks, 24)
end

-- Steaming cloud that lingers at Origin for the zone duration.
VfxLibrary.BoilingMist = function(packet: Packet, trove: TroveType, api: Api)
	local radius = numberParam(packet, "Radius", 9)
	local defaultDuration = numberParam(packet, "Ticks", 3) * numberParam(packet, "TickInterval", 1)
	local duration = clampLifetime(numberParam(packet, "Duration", defaultDuration), 0.5)
	local color = api.ElementColor("Water")

	local mist = newPart(trove, "BoilingMist", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.SmoothPlastic,
		Color = color,
		Size = Vector3.one * 2,
		Transparency = 1,
		CFrame = CFrame.new(packet.Origin),
	})
	play(trove, mist, 0.3, { Size = Vector3.one * radius * 2, Transparency = 0.65 })
	local steam = newEmitter(mist, {
		Color = color,
		Rate = 30,
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new(3, 5),
		Transparency = NumberSequence.new(0.6, 1),
		Acceleration = Vector3.new(0, 2, 0),
	})
	after(trove, math.max(duration - 0.4, 0), function()
		steam.Enabled = false
		play(trove, mist, 0.4, { Transparency = 1 })
	end)
end

-- Mud wall rising out of the ground at Origin (the wall center chosen by the server), then sinking.
VfxLibrary.MudWall = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local width = numberParam(packet, "Width", 14)
	local height = numberParam(packet, "Height", 9)
	local thickness = numberParam(packet, "Thickness", 2.5)
	local duration = clampLifetime(numberParam(packet, "Duration", 6), 0)
	local color = api.ElementColor("Earth")
	local ground = groundAt(packet.Origin)
	local rotation = CFrame.lookAt(ground, ground + direction).Rotation
	local buried = CFrame.new(ground - Vector3.new(0, height / 2, 0)) * rotation
	local raised = CFrame.new(ground + Vector3.new(0, height / 2, 0)) * rotation

	local wall = newPart(trove, "MudWall", {
		Material = Enum.Material.Mud,
		Color = color,
		Size = Vector3.new(width, height, thickness),
		CFrame = buried,
	})
	local dust = newEmitter(wall, {
		Color = color,
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(4, 8),
		Size = NumberSequence.new(2, 0),
	})
	burst(dust, 24)
	play(trove, wall, WALL_RISE_SECONDS, { CFrame = raised }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	after(trove, math.max(duration - WALL_SINK_SECONDS, WALL_RISE_SECONDS), function()
		play(trove, wall, WALL_SINK_SECONDS, { CFrame = buried }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
end

-- Ring of spinning embers around the caster (follows the caster's root while it exists).
VfxLibrary.EmberStorm = function(packet: Packet, trove: TroveType, api: Api)
	local radius = numberParam(packet, "Radius", 13)
	local defaultDuration = numberParam(packet, "Ticks", 3) * numberParam(packet, "TickInterval", 0.8)
	local duration = clampLifetime(numberParam(packet, "Duration", defaultDuration), 0.5)
	local color = api.ElementColor("Fire")
	local follow = casterRoot(packet)
	local center = packet.Origin
	local ringTrove = trove:Extend()

	local ring = newPart(ringTrove, "EmberRing", {
		Transparency = 1,
		Size = Vector3.new(radius * 2, 1, radius * 2),
		CFrame = CFrame.new(center),
	})
	local sparks = newEmitter(ring, {
		Color = color,
		Rate = 30,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(2, 6),
		Size = NumberSequence.new(1, 0),
		Acceleration = Vector3.new(0, 6, 0),
	})
	local embers: { Part } = {}
	for index = 1, EMBER_COUNT do
		embers[index] = newPart(ringTrove, "Ember", {
			Shape = Enum.PartType.Ball,
			Color = color,
			Size = Vector3.one * 1.2,
			Transparency = 0.1,
		})
	end

	local angle = 0
	local elapsed = 0
	ringTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		angle += deltaTime * EMBER_SPIN_RADIANS_PER_SECOND
		if follow ~= nil and follow.Parent ~= nil then
			center = follow.Position
		end
		local fade = math.clamp((elapsed - (duration - RING_FADE_SECONDS)) / RING_FADE_SECONDS, 0, 1)
		for index, ember in ipairs(embers) do
			local emberAngle = angle + (index - 1) * (2 * math.pi / EMBER_COUNT)
			local bob = math.sin(elapsed * 4 + index) * 0.8
			ember.CFrame =
				CFrame.new(center + Vector3.new(math.cos(emberAngle) * radius, bob, math.sin(emberAngle) * radius))
			ember.Transparency = 0.1 + 0.9 * fade
		end
		ring.CFrame = CFrame.new(center)
		sparks.Enabled = fade < 1
	end)
	after(trove, duration, function()
		ringTrove:Destroy()
	end)
end

-- Three staggered shockwave rings expanding on the ground, with a large camera shake nearby.
VfxLibrary.Earthquake = function(packet: Packet, trove: TroveType, api: Api)
	local radius = numberParam(packet, "Radius", 18)
	local color = api.ElementColor("Earth")
	local ground = groundAt(packet.Origin)
	local lying = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis is X: stand it upright

	local debris = newPart(trove, "QuakeDust", { Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(ground) })
	local dust = newEmitter(debris, {
		Color = color,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(radius * 0.8, radius * 1.4),
		Size = NumberSequence.new(2, 0),
		Spread = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -20, 0),
	})
	burst(dust, 40)

	for index = 1, SHOCKWAVE_COUNT do
		after(trove, (index - 1) * SHOCKWAVE_STAGGER_SECONDS, function()
			local ring = newPart(trove, "Shockwave", {
				Shape = Enum.PartType.Cylinder,
				Material = Enum.Material.Slate,
				Color = color,
				Size = Vector3.new(0.6, 2, 2),
				Transparency = 0.2,
				CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0)) * lying,
			})
			play(trove, ring, 0.55, { Size = Vector3.new(0.6, radius * 2, radius * 2), Transparency = 1 })
		end)
	end
	shakeNear(api, packet.Origin, CombatConfig.Hit.CameraShakeLarge)
end

----------------------------------------------------------------
-- Phase 2 roster (docs/GAME_DESIGN.md §5), grouped by element like JutsuConfig
----------------------------------------------------------------

-- EmberStep: fire streak carried along the short dash, then the burning pools it leaves behind.
-- The pool centres are the very points the server damages (Targets), so the trail never lies.
VfxLibrary.EmberStep = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local distance = numberParam(packet, "Distance", 20)
	local dashDuration = math.clamp(numberParam(packet, "DashDuration", 0.25), 0.05, 1)
	local poolRadius = math.max(numberParam(packet, "TrailRadius", 5), 1)
	local duration = clampLifetime(numberParam(packet, "Duration", 2), 0.5)
	local color = api.ElementColor(stringParam(packet, "Element", "Fire"))
	local pools = targetsOf(packet)
	if #pools == 0 then
		for index = 1, EMBER_TRAIL_SEGMENTS do
			table.insert(pools, packet.Origin + direction * ((index - 1) * EMBER_TRAIL_SPACING_STUDS))
		end
	end

	local streak = newPart(trove, "EmberStepStreak", {
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.one * 2,
		Transparency = 0.2,
		CFrame = CFrame.new(packet.Origin),
	})
	addTrail(streak, color, 2, 0.35)
	local sparks = newEmitter(streak, {
		Color = color,
		Rate = 25,
		Lifetime = NumberRange.new(0.3, 0.7),
		Speed = NumberRange.new(3, 8),
		Size = NumberSequence.new(1, 0),
		Acceleration = Vector3.new(0, 6, 0),
	})
	play(
		trove,
		streak,
		dashDuration,
		{ CFrame = CFrame.new(packet.Origin + direction * distance) },
		Enum.EasingStyle.Linear
	)
	after(trove, dashDuration, function()
		sparks.Enabled = false
		play(trove, streak, 0.2, { Transparency = 1 })
	end)

	-- One smouldering pool per trail point, dropped as the dash passes over it.
	local poolLife = math.max(duration - dashDuration - 0.4, 0.1)
	for index, center in ipairs(pools) do
		after(trove, dashDuration * ((index - 1) / #pools), function()
			local ground = groundAt(center)
			local pool = newPart(trove, "EmberPool", {
				Shape = Enum.PartType.Cylinder,
				Color = color,
				Size = Vector3.new(EMBER_POOL_THICKNESS, 1, 1),
				Transparency = 0.4,
				CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * LYING_CYLINDER,
			})
			play(trove, pool, 0.2, { Size = Vector3.new(EMBER_POOL_THICKNESS, poolRadius * 2, poolRadius * 2) })
			local flames = newEmitter(pool, {
				Color = color,
				Rate = 10,
				Lifetime = NumberRange.new(0.4, 0.9),
				Speed = NumberRange.new(2, 5),
				Size = NumberSequence.new(1.6, 0),
				Acceleration = Vector3.new(0, 8, 0),
			})
			after(trove, poolLife, function()
				flames.Enabled = false
				play(trove, pool, 0.4, { Transparency = 1 })
			end)
		end)
	end
	playPacketSound(packet, api)
end

-- Meteor: burning rock arcing toward its target behind a smoke tail, breaking apart on impact. It
-- re-simulates the server ballistic (Rise, Gravity); the blast ring is the shared "Explosion" packet
-- the server emits at the real detonation point.
VfxLibrary.Meteor = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local speed = math.max(numberParam(packet, "Speed", 55), 1)
	local arcHeight = numberParam(packet, "ArcHeight", 20)
	local fuse = numberParam(packet, "Fuse", 1.4)
	local rise = numberParam(packet, "Rise", 4 * arcHeight / math.max(fuse, 0.1))
	local gravity = numberParam(packet, "Gravity", 2 * rise / math.max(fuse, 0.1))
	local spawnOffset = numberParam(packet, "SpawnOffset", 5)
	local blastRadius = numberParam(packet, "BlastRadius", 10)
	-- The server also stops the projectile at Range: the rock must not fly past its blast.
	local flight = clampLifetime(math.min(fuse, numberParam(packet, "Range", 75) / speed), METEOR_BREAK_SECONDS + 0.2)
	local color = api.ElementColor(stringParam(packet, "Element", "Fire"))
	local start = packet.Origin + direction * spawnOffset

	local rock = newPart(trove, "Meteor", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.CrackedLava,
		Color = color,
		Size = Vector3.one * 5,
		CFrame = CFrame.new(start),
	})
	local fire = Instance.new("Fire")
	fire.Size = 12
	fire.Heat = 18
	fire.Color = color
	fire.SecondaryColor = FIRE_SECONDARY_COLOR
	fire.Parent = rock
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = 24
	light.Parent = rock
	local smoke = newEmitter(rock, {
		Color = SMOKE_COLOR,
		Rate = 28,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(1, 4),
		Size = NumberSequence.new(3, 6),
		Transparency = NumberSequence.new(0.35, 1),
		Acceleration = Vector3.new(0, 4, 0),
	})
	addTrail(rock, color, 2.5, 0.5)

	-- Ballistic arc: a tween cannot drive it, so the rock is stepped every frame.
	local arc = trove:Extend()
	local elapsed = 0
	arc:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed = math.min(elapsed + deltaTime, flight)
		local spin = elapsed * METEOR_SPIN_RADIANS_PER_SECOND
		local lift = rise * elapsed - 0.5 * gravity * elapsed * elapsed
		rock.CFrame = CFrame.new(start + direction * (speed * elapsed) + Vector3.new(0, lift, 0))
			* CFrame.Angles(spin, spin * 0.6, 0)
	end)

	after(trove, flight, function()
		arc:Destroy()
		fire.Enabled = false
		smoke.Enabled = false
		local debris = newEmitter(rock, {
			Color = color,
			Lifetime = NumberRange.new(0.4, 0.9),
			Speed = NumberRange.new(blastRadius, blastRadius * 2.5),
			Size = NumberSequence.new(2.5, 0),
			Acceleration = Vector3.new(0, -20, 0),
		})
		burst(debris, 36)
		play(trove, rock, METEOR_BREAK_SECONDS, { Size = Vector3.one * blastRadius, Transparency = 1 })
		shakeNear(api, rock.Position, CombatConfig.Hit.CameraShakeLarge)
	end)
	playPacketSound(packet, api)
end

-- WaterPrison: glass sphere of water closing around every rooted target for the root duration.
-- Origin is already the grab centre; Targets holds the roots the server actually pinned.
VfxLibrary.WaterPrison = function(packet: Packet, trove: TroveType, api: Api)
	local radius = math.max(numberParam(packet, "Radius", PRISON_RADIUS_STUDS), 1)
	local duration = clampLifetime(numberParam(packet, "Duration", 1.5), 0.5)
	local color = api.ElementColor(stringParam(packet, "Element", "Water"))
	local points = targetsOf(packet)
	if #points == 0 then
		points = { packet.Origin }
	end

	for _, point in ipairs(points) do
		local sphere = newPart(trove, "WaterPrison", {
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.Glass,
			Color = color,
			Size = Vector3.one * 2,
			Transparency = 0.45,
			CFrame = CFrame.new(point),
		})
		play(trove, sphere, 0.25, { Size = Vector3.one * radius * 2 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local swirl = newEmitter(sphere, {
			Color = color,
			Rate = 22,
			Lifetime = NumberRange.new(0.4, 0.9),
			Speed = NumberRange.new(2, 6),
			Size = NumberSequence.new(1.2, 0),
			Acceleration = Vector3.new(0, 3, 0),
		})
		burst(swirl, 16)
		after(trove, math.max(duration - 0.35, 0.1), function()
			swirl.Enabled = false
			play(trove, sphere, 0.35, { Transparency = 1, Size = Vector3.one * radius * 2.6 })
		end)
	end
	playPacketSound(packet, api)
end

-- MudShot: mud ball flying flat, then a splat facing the way it travelled.
VfxLibrary.MudShot = function(packet: Packet, trove: TroveType, api: Api)
	local direction = directionOf(packet)
	local speed = math.max(numberParam(packet, "Speed", 110), 1)
	local spawnOffset = numberParam(packet, "SpawnOffset", 4)
	local splatRadius = math.max(numberParam(packet, "HitRadius", 4), 1)
	local color = api.ElementColor(stringParam(packet, "Element", "Earth"))
	local distance = travelDistance(packet, speed, numberParam(packet, "Fuse", 0.9), 70)
	local travelTime = clampLifetime(distance / speed, MUD_SPLAT_SECONDS + 0.2)
	local start = packet.Origin + direction * spawnOffset
	local finish = start + direction * distance

	local ball = newPart(trove, "MudShot", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Mud,
		Color = color,
		Size = Vector3.one * 2.2,
		CFrame = CFrame.new(start),
	})
	addTrail(ball, color, 1, 0.25)
	local spatter = newEmitter(ball, {
		Color = color,
		Rate = 20,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(1, 4),
		Size = NumberSequence.new(0.8, 0),
		Acceleration = Vector3.new(0, -20, 0),
	})
	play(trove, ball, travelTime, { CFrame = CFrame.new(finish) }, Enum.EasingStyle.Linear)
	after(trove, travelTime, function()
		spatter.Enabled = false
		play(trove, ball, 0.15, { Transparency = 1 })
		-- Cylinder axis is X: yaw the look frame by 90 degrees so the disc faces the flight path.
		local splat = newPart(trove, "MudSplat", {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Mud,
			Color = color,
			Size = Vector3.new(0.5, 1, 1),
			Transparency = 0.15,
			CFrame = CFrame.lookAt(finish, finish + direction) * CFrame.Angles(0, math.rad(90), 0),
		})
		play(
			trove,
			splat,
			MUD_SPLAT_SECONDS,
			{ Size = Vector3.new(0.5, splatRadius * 2, splatRadius * 2), Transparency = 1 }
		)
		local clods = newEmitter(splat, {
			Color = color,
			Lifetime = NumberRange.new(0.3, 0.7),
			Speed = NumberRange.new(6, 14),
			Size = NumberSequence.new(1, 0),
			Acceleration = Vector3.new(0, -25, 0),
		})
		burst(clods, 18)
	end)
	playPacketSound(packet, api)
end

-- StoneSkin: ring of slate plates orbiting the caster for the buff duration, then crumbling. The
-- plates keep slits and stay see-through: an opaque shell would blind the caster it protects.
VfxLibrary.StoneSkin = function(packet: Packet, trove: TroveType, api: Api)
	local duration = clampLifetime(
		numberParam(packet, "Duration", CombatConfig.Status.StoneSkin.DurationSeconds),
		STONE_CRUMBLE_SECONDS
	)
	local radius = math.max(numberParam(packet, "Radius", 6), 1.5)
	local color = api.ElementColor(stringParam(packet, "Element", "Earth"))
	local follow = casterRoot(packet)
	local center = packet.Origin
	local shellTrove = trove:Extend()
	local plateWidth = (2 * math.pi * radius / STONE_PLATE_COUNT) * STONE_PLATE_GAP_FACTOR

	local plates: { Part } = {}
	for index = 1, STONE_PLATE_COUNT do
		plates[index] = newPart(shellTrove, "StonePlate", {
			Material = Enum.Material.Slate,
			Color = color,
			Size = Vector3.new(plateWidth, radius * 1.2, 0.8),
			Transparency = STONE_PLATE_TRANSPARENCY,
		})
	end
	local grit = newEmitter(plates[1], {
		Color = color,
		Rate = 12,
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(1, 4),
		Size = NumberSequence.new(0.8, 0),
		Acceleration = Vector3.new(0, -12, 0),
	})
	burst(grit, 18)

	local elapsed = 0
	shellTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		if follow ~= nil and follow.Parent ~= nil then
			center = follow.Position
		end
		local spin = elapsed * STONE_SPIN_RADIANS_PER_SECOND
		for index, plate in ipairs(plates) do
			local angle = spin + (index - 1) * (2 * math.pi / STONE_PLATE_COUNT)
			local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
			plate.CFrame = CFrame.lookAt(center + outward * radius, center)
		end
	end)
	after(trove, math.max(duration - STONE_CRUMBLE_SECONDS, 0.1), function()
		grit.Enabled = false
		fadeParts(shellTrove, plates, STONE_CRUMBLE_SECONDS)
	end)
	after(trove, duration, function()
		shellTrove:Destroy()
	end)
	playPacketSound(packet, api)
end

-- WindBlade: thin blade flying flat along Direction, rolling as it goes, behind a tight trail.
VfxLibrary.WindBlade = function(packet: Packet, trove: TroveType, api: Api)
	local direction = directionOf(packet)
	local speed = math.max(numberParam(packet, "Speed", 130), 1)
	local spawnOffset = numberParam(packet, "SpawnOffset", 4)
	local color = api.ElementColor(stringParam(packet, "Element", "Wind"))
	local distance = travelDistance(packet, speed, numberParam(packet, "Fuse", 0.6), 60)
	local travelTime = clampLifetime(distance / speed, 0.3)
	local start = packet.Origin + direction * spawnOffset
	local finish = start + direction * distance

	local blade = newPart(trove, "WindBlade", {
		Color = color,
		Size = Vector3.new(0.35, 5, 1.6),
		Transparency = 0.1,
		CFrame = CFrame.lookAt(start, start + direction),
	})
	addTrail(blade, color, 2.5, 0.25)
	local slipstream = newEmitter(blade, {
		Color = color,
		Rate = 18,
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(2, 6),
		Size = NumberSequence.new(0.6, 0),
		Spread = Vector2.new(20, 20),
	})
	play(
		trove,
		blade,
		travelTime,
		{ CFrame = CFrame.lookAt(finish, finish + direction) * CFrame.Angles(0, 0, BLADE_SPIN_RADIANS) },
		Enum.EasingStyle.Linear
	)
	after(trove, travelTime, function()
		slipstream.Enabled = false
		play(trove, blade, 0.15, { Transparency = 1 })
	end)
	playPacketSound(packet, api)
end

-- Cyclone: funnel of widening rings wobbling over the zone centre, debris spiralling inward once
-- per server tick so the pull the player feels has a visible rhythm.
VfxLibrary.Cyclone = function(packet: Packet, trove: TroveType, api: Api)
	local radius = math.max(numberParam(packet, "Radius", 11), 1)
	local duration = clampLifetime(numberParam(packet, "Duration", 2.4), 0.5)
	local spirals = 1 / math.max(numberParam(packet, "TickInterval", CYCLONE_TICK_SECONDS), 0.1)
	local color = api.ElementColor(stringParam(packet, "Element", "Wind"))
	local ground = groundAt(packet.Origin)
	local funnelTrove = trove:Extend()

	local rings: { Part } = {}
	for index = 1, CYCLONE_RING_COUNT do
		rings[index] = newPart(funnelTrove, "CycloneRing", {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.ForceField,
			Color = color,
			Size = Vector3.new(CYCLONE_RING_THICKNESS, 2, 2),
			Transparency = 0.5,
			CFrame = CFrame.new(ground) * LYING_CYLINDER,
		})
	end
	local wisps: { Part } = {}
	for index = 1, CYCLONE_WISP_COUNT do
		wisps[index] = newPart(funnelTrove, "CycloneWisp", {
			Shape = Enum.PartType.Ball,
			Color = color,
			Size = Vector3.one * 0.9,
			Transparency = 0.2,
		})
	end
	local dust = newEmitter(rings[1], {
		Color = color,
		Rate = 30,
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(2, 6),
		Size = NumberSequence.new(1.5, 0),
		Acceleration = Vector3.new(0, 14, 0),
	})

	local elapsed = 0
	funnelTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		local spin = elapsed * CYCLONE_SPIN_RADIANS_PER_SECOND
		local fade = math.clamp((elapsed - (duration - RING_FADE_SECONDS)) / RING_FADE_SECONDS, 0, 1)
		for index, ring in ipairs(rings) do
			local factor = index / CYCLONE_RING_COUNT
			local wobbleAngle = spin + index
			local wobble = Vector3.new(math.cos(wobbleAngle), 0, math.sin(wobbleAngle)) * (radius * 0.12)
			local diameter = radius * 2 * factor
			ring.Size = Vector3.new(CYCLONE_RING_THICKNESS, diameter, diameter)
			ring.CFrame = CFrame.new(ground + Vector3.new(0, CYCLONE_HEIGHT_STUDS * factor, 0) + wobble)
				* LYING_CYLINDER
			ring.Transparency = 0.5 + 0.5 * fade
		end
		-- Each wisp rides the funnel from the rim up to the eye, then restarts at the rim.
		for index, wisp in ipairs(wisps) do
			local progress = (elapsed * spirals + (index - 1) / CYCLONE_WISP_COUNT) % 1
			local angle = spin * 2 + (index - 1) * (2 * math.pi / CYCLONE_WISP_COUNT)
			local ringRadius = radius * (1 - progress)
			wisp.CFrame = CFrame.new(
				ground
					+ Vector3.new(
						math.cos(angle) * ringRadius,
						CYCLONE_HEIGHT_STUDS * progress,
						math.sin(angle) * ringRadius
					)
			)
			wisp.Transparency = math.clamp(0.2 + 0.8 * math.max(fade, progress), 0, 1)
		end
		dust.Enabled = fade < 1
	end)
	after(trove, duration, function()
		funnelTrove:Destroy()
	end)
	playPacketSound(packet, api)
end

-- Sandstorm: dusty dome over the zone, with grit blowing around the local player while inside it.
VfxLibrary.Sandstorm = function(packet: Packet, trove: TroveType, api: Api)
	local radius = math.max(numberParam(packet, "Radius", 13), 1)
	local duration = clampLifetime(numberParam(packet, "Duration", 2.7), 0.5)
	local color = api.ElementColor(stringParam(packet, "Element", "Wind"))
	local ground = groundAt(packet.Origin)
	local domeTrove = trove:Extend()

	local dome = newPart(domeTrove, "Sandstorm", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Sand,
		Color = color,
		Size = Vector3.one * 2,
		Transparency = 1,
		CFrame = CFrame.new(ground),
	})
	play(domeTrove, dome, 0.35, { Size = Vector3.one * radius * 2, Transparency = 0.55 })
	local sand = newEmitter(dome, {
		Color = color,
		Rate = 26,
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(3, 8),
		Size = NumberSequence.new(2.5, 5),
		Transparency = NumberSequence.new(0.5, 1),
		Spread = Vector2.new(60, 60),
	})
	local grit = newPart(domeTrove, "SandstormGrit", {
		Transparency = 1,
		Size = Vector3.one,
		CFrame = CFrame.new(ground),
	})
	local gritEmitter = newEmitter(grit, {
		Color = color,
		Rate = 24,
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(6, 14),
		Size = NumberSequence.new(1.2, 2.5),
		Transparency = NumberSequence.new(0.35, 1),
	})
	gritEmitter.Enabled = false
	domeTrove:Connect(RunService.Heartbeat, function()
		local root = localRoot(api)
		if root == nil then
			gritEmitter.Enabled = false
			return
		end
		grit.CFrame = CFrame.new(root.Position)
		gritEmitter.Enabled = (root.Position - ground).Magnitude <= radius
	end)
	after(trove, math.max(duration - 0.4, 0.1), function()
		sand.Enabled = false
		gritEmitter.Enabled = false
		play(domeTrove, dome, 0.4, { Transparency = 1 })
	end)
	after(trove, duration, function()
		domeTrove:Destroy()
	end)
	playPacketSound(packet, api)
end

-- LightningBolt: instant jagged beam along the hitscan ray, flashing on whatever it struck. Origin
-- already carries the spawn offset the server fired from.
VfxLibrary.LightningBolt = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local color = api.ElementColor(stringParam(packet, "Element", "Lightning"))
	local points = targetsOf(packet)
	local impact = if #points > 0 then points[1] else packet.Origin + direction * numberParam(packet, "Length", 70)

	fadeParts(
		trove,
		newBolt(trove, packet.Origin, impact, color, BOLT_THICKNESS_STUDS, BOLT_JITTER_STUDS),
		BOLT_FADE_SECONDS
	)
	sparkFlash(trove, impact, color, 5)
	playPacketSound(packet, api)
end

-- LightningStep: flash at both ends of the teleport, plus a shimmer marking the i-frame window.
-- Targets carries the landing the server validated against walls and ground.
VfxLibrary.LightningStep = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local color = api.ElementColor(stringParam(packet, "Element", "Lightning"))
	local destination = endPointOf(packet, packet.Origin, direction, numberParam(packet, "Distance", 18))
	local iFrames = clampLifetime(numberParam(packet, "IFrameSeconds", 0.4), 0.5)

	fadeParts(
		trove,
		newBolt(trove, packet.Origin, destination, color, BOLT_THICKNESS_STUDS, BOLT_JITTER_STUDS),
		BOLT_FADE_SECONDS
	)
	sparkFlash(trove, packet.Origin, color, 6)
	sparkFlash(trove, destination, color, 6)
	local shimmer = newPart(trove, "StepIFrames", {
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.ForceField,
		Color = color,
		Size = Vector3.one * 5,
		Transparency = 0.5,
		CFrame = CFrame.new(destination),
	})
	play(trove, shimmer, iFrames, { Transparency = 1 })
	playPacketSound(packet, api)
end

-- StaticField: crackling disc on the ground that throws arcs out to its rim on every tick.
VfxLibrary.StaticField = function(packet: Packet, trove: TroveType, api: Api)
	local radius = math.max(numberParam(packet, "Radius", 12), 1)
	local interval = math.max(numberParam(packet, "TickInterval", STATIC_TICK_SECONDS), 0.1)
	local duration = clampLifetime(numberParam(packet, "Duration", 4 * interval), 0.5)
	local ticks = math.clamp(math.floor(duration / interval + 0.5), 1, 8)
	local color = api.ElementColor(stringParam(packet, "Element", "Lightning"))
	local ground = groundAt(packet.Origin) + Vector3.new(0, 0.3, 0)

	local disc = newPart(trove, "StaticField", {
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Size = Vector3.new(0.4, 2, 2),
		Transparency = 0.6,
		CFrame = CFrame.new(ground) * LYING_CYLINDER,
	})
	play(trove, disc, 0.25, { Size = Vector3.new(0.4, radius * 2, radius * 2) })
	local sparks = newEmitter(disc, {
		Color = color,
		Rate = 26,
		Lifetime = NumberRange.new(0.3, 0.7),
		Speed = NumberRange.new(4, 10),
		Size = NumberSequence.new(1, 0),
		Spread = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, 5, 0),
	})

	for tick = 1, ticks do
		after(trove, math.min((tick - 1) * interval, duration), function()
			for _ = 1, STATIC_ARCS_PER_TICK do
				local angle = math.random() * 2 * math.pi
				local reach = radius * (0.35 + math.random() * 0.65)
				local rim = ground + Vector3.new(math.cos(angle) * reach, 0.2, math.sin(angle) * reach)
				fadeParts(trove, newBolt(trove, ground, rim, color, 0.3, STATIC_ARC_JITTER_STUDS), BOLT_FADE_SECONDS)
			end
			burst(sparks, 12)
		end)
	end
	after(trove, math.max(duration - 0.35, 0.1), function()
		sparks.Enabled = false
		play(trove, disc, 0.35, { Transparency = 1 })
	end)
	playPacketSound(packet, api)
end

-- Raijin: bolt out of the sky onto the first target, then arcs chaining to every position the server
-- struck (Targets, in chain order), each link flashing and shaking the cameras nearby.
VfxLibrary.Raijin = function(packet: Packet, trove: TroveType, api: Api)
	local direction = flatDirectionOf(packet)
	local color = api.ElementColor(stringParam(packet, "Element", "Lightning"))
	local points = targetsOf(packet)
	if #points == 0 then
		points = { packet.Origin + direction * numberParam(packet, "Length", 60) }
	end

	local previous = packet.Origin
	for index, point in ipairs(points) do
		local from = previous
		previous = point
		after(trove, (index - 1) * RAIJIN_LINK_DELAY_SECONDS, function()
			if index == 1 then
				local sky = point + Vector3.new(0, RAIJIN_SKY_HEIGHT_STUDS, 0)
				fadeParts(
					trove,
					newBolt(trove, sky, point, color, RAIJIN_BOLT_THICKNESS_STUDS, BOLT_JITTER_STUDS),
					BOLT_FADE_SECONDS * 2
				)
			end
			fadeParts(
				trove,
				newBolt(trove, from, point, color, RAIJIN_BOLT_THICKNESS_STUDS, BOLT_JITTER_STUDS),
				BOLT_FADE_SECONDS * 2
			)
			local flash = sparkFlash(trove, point, color, 9)
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 4
			light.Range = 26
			light.Parent = flash
			shakeNear(api, point, CombatConfig.Hit.CameraShakeLarge)
		end)
	end
	playPacketSound(packet, api)
end

-- Small impact flash; hit-stop and a small shake when the local character is the one being hit.
VfxLibrary.Hit = function(packet: Packet, trove: TroveType, api: Api)
	local color = api.ElementColor(stringParam(packet, "Element", ""))
	local flash = newPart(trove, "HitFlash", {
		Shape = Enum.PartType.Ball,
		Color = color,
		Size = Vector3.one,
		Transparency = 0.1,
		CFrame = CFrame.new(packet.Origin),
	})
	play(trove, flash, 0.2, { Size = Vector3.one * 3.5, Transparency = 1 })
	local sparks = newEmitter(flash, {
		Color = color,
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(8, 14),
		Size = NumberSequence.new(0.5, 0),
	})
	burst(sparks, 10)
	api.Sound.play("ImpactHit", packet.Origin)

	local root = localRoot(api)
	if root ~= nil and (root.Position - packet.Origin).Magnitude <= HIT_FEEDBACK_RADIUS_STUDS then
		api.HitStop(CombatConfig.Hit.HitStopSeconds)
		api.Shake(CombatConfig.Hit.CameraShakeSmall)
	end
end

-- Slash arc swiped in front of the attacker; the sound follows the combo index.
VfxLibrary.Melee = function(packet: Packet, trove: TroveType, api: Api)
	local direction = directionOf(packet)
	local index = math.max(1, math.floor(numberParam(packet, "Index", 1)))
	local finisherIndex = #CombatConfig.Melee.Damage
	local center = packet.Origin + direction * (CombatConfig.Melee.Range * 0.45)
	local base = CFrame.lookAt(center, center + direction)
	local swing = math.rad(70) * (if index % 2 == 0 then -1 else 1)

	local arc = newPart(trove, "MeleeArc", {
		Color = WHITE,
		Size = Vector3.new(CombatConfig.Melee.Width * 1.2, 0.25, 1.4),
		Transparency = 0.15,
		CFrame = base * CFrame.Angles(0, 0, swing),
	})
	play(trove, arc, 0.12, { CFrame = base * CFrame.Angles(0, 0, -swing) })
	after(trove, 0.12, function()
		play(trove, arc, 0.12, { Transparency = 1 })
	end)

	if index >= finisherIndex then
		api.Sound.play("MeleeFinisher", packet.Origin)
	else
		api.Sound.play("Melee" .. math.clamp(index, 1, MELEE_SFX_VARIANTS), packet.Origin)
	end
end

-- Streak left behind by a dash.
VfxLibrary.Dash = function(packet: Packet, trove: TroveType, api: Api)
	local direction = directionOf(packet)
	local distance = numberParam(packet, "Distance", CombatConfig.Dash.Distance)
	local duration = math.clamp(numberParam(packet, "Duration", CombatConfig.Dash.DurationSeconds), 0.05, 1)
	local color = api.ElementColor("Wind")

	local streak = newPart(trove, "DashTrail", {
		Transparency = 1,
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(packet.Origin),
	})
	addTrail(streak, color, 1.5, 0.3)
	local puff = newEmitter(streak, {
		Color = color,
		Lifetime = NumberRange.new(0.2, 0.4),
		Speed = NumberRange.new(2, 5),
		Size = NumberSequence.new(1.2, 0),
	})
	burst(puff, 12)
	play(
		trove,
		streak,
		duration,
		{ CFrame = CFrame.new(packet.Origin + direction * distance) },
		Enum.EasingStyle.Linear
	)
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
