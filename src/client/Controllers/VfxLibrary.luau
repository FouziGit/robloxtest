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

return VfxLibrary
