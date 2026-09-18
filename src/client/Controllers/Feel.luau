--!strict
-- Feel: the one place that decides what an action feels like. Every system that wants the camera to
-- move, the world to pause, a number to fly or a pad to buzz calls this, and every number it uses comes
-- from Config/FeelConfig. Nothing here decides anything about gameplay.
--
-- One render binding drives all of it. docs/JUICE_AUDIT.md found the previous version jittering the
-- camera with math.random on its own RenderStepped and pulsing the field of view through two chained
-- tweens; both are replaced. Random jitter reads as a broken camera, Perlin noise reads as weight, and
-- a field of view driven by overlapping tweens can be left permanently wrong when two of them land in
-- the same frame. Here it is a spring around zero offset, re-based against whatever the camera's own
-- field of view is, so it cannot drift whatever else writes to it.
--
-- The binding sits one priority above Camera so it runs after the default camera script has written
-- this frame's CFrame; anything earlier is overwritten and does nothing.

local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local DamageNumber = require(UI.components.DamageNumber)
local FeelConfig = require(Shared.Config.FeelConfig)
local FeelMath = require(Shared.Pure.FeelMath)
local Log = require(Shared.Util.Log)
local Shake = require(Packages.Shake)
local Spring = require(Shared.Pure.Spring)

local log = Log.new("Feel")

type Deps = { ClientData: any, MovementController: any }
type SpringType = typeof(Spring.new(0, 1, 1))

export type Role = "Dealt" | "Taken" | "None"

local RENDER_NAME = "VellumFeel"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local ROOT_PART_NAME = "HumanoidRootPart"
local GAMEPAD = Enum.UserInputType.Gamepad1

local Feel = {}

local clientData: any
local movementController: any

local player = Players.LocalPlayer
local fovSpring: SpringType = Spring.new(0, FeelConfig.Fov.Tension, FeelConfig.Fov.Friction)
local appliedFovOffset = 0

-- Live camera shakes. Each entry owns a sleitnick/shake instance and the scale distance gave it.
type ActiveShake = { Handle: any, Scale: number }
local shakes: { ActiveShake } = {}
local heldPosition = Vector3.zero
local heldRotation = Vector3.zero

-- A number in flight. Origin plus a per-number drift, so two hits in one spot do not print on top of
-- each other, and a pop spring that overshoots its size and settles back.
type FlyingNumber = {
	Marker: DamageNumber.Marker,
	Origin: Vector3,
	Drift: Vector3,
	Elapsed: number,
	Pop: SpringType,
}
local numbers: { FlyingNumber } = {}
local numberSeed = 0

type ActiveFlash = { Highlight: Highlight, Remaining: number }
local flashes: { ActiveFlash } = {}

local hitStopRemaining = 0
local hitStopRole: Role = "None"

local function localCharacter(): Model?
	return player.Character
end

local function localRoot(): BasePart?
	local character = localCharacter()
	if character == nil then
		return nil
	end
	local part = character:FindFirstChild(ROOT_PART_NAME)
	if part ~= nil and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function shakeEnabled(): boolean
	if clientData == nil then
		return true
	end
	local data = clientData.get()
	if data == nil then
		return true
	end
	return data.Settings.CameraShake ~= false
end

local function toVector(triple: FeelConfig.Triple): Vector3
	return Vector3.new(triple[1], triple[2], triple[3])
end

--------------------------------------------------------------------------------------------------
-- Camera shake
--------------------------------------------------------------------------------------------------

-- Starts a shake from a named FeelConfig profile, scaled by `scale` (distance attenuation, or 1).
-- Ignored below FeelConfig.Shake.MinScale: a shake nobody can see still costs a frame.
function Feel.shake(profileName: string, scale: number?)
	local profile = FeelConfig.Shake.Profiles[profileName]
	if profile == nil then
		log.warn("unknown shake profile %s", profileName)
		return
	end
	local strength = math.clamp(scale or 1, 0, 1)
	if strength < FeelConfig.Shake.MinScale or not shakeEnabled() then
		return
	end

	-- A six-player fight can start twenty shakes in a frame. Summed, that is noise rather than weight,
	-- so only the strongest few are ever live: the weakest is dropped to make room.
	if #shakes >= FeelConfig.Shake.MaxConcurrent then
		local weakestIndex, weakest = 1, math.huge
		for index, entry in ipairs(shakes) do
			if entry.Scale < weakest then
				weakestIndex, weakest = index, entry.Scale
			end
		end
		if weakest >= strength then
			return
		end
		local dropped = table.remove(shakes, weakestIndex)
		if dropped ~= nil then
			dropped.Handle:Destroy()
		end
	end

	local handle = Shake.new()
	handle.Amplitude = profile.Amplitude * strength
	handle.Frequency = profile.Frequency
	handle.FadeInTime = profile.FadeInSeconds
	handle.SustainTime = profile.SustainSeconds
	handle.FadeOutTime = profile.FadeOutSeconds
	handle.PositionInfluence = toVector(profile.PositionInfluence)
	handle.RotationInfluence = toVector(profile.RotationInfluence)
	handle:Start()
	table.insert(shakes, { Handle = handle, Scale = strength })
end

-- The same, attenuated by how far the impact was from the local player. This is the one every impact
-- should use: a hit across the arena that shakes the camera as hard as one in your face is why a fight
-- reads as noise.
function Feel.shakeAt(profileName: string, position: Vector3, scale: number?)
	local root = localRoot()
	if root == nil then
		return
	end
	local distance = (root.Position - position).Magnitude
	local falloff = FeelMath.falloff(distance, FeelConfig.Shake.FalloffRadiusStuds)
	if falloff <= 0 then
		return
	end
	Feel.shake(profileName, falloff * (scale or 1))
end

local function stepShakes(): (Vector3, Vector3)
	local position = Vector3.zero
	local rotation = Vector3.zero
	local index = 1
	while index <= #shakes do
		local entry = shakes[index]
		local offset, angles, done = entry.Handle:Update()
		position += offset
		rotation += angles
		if done then
			entry.Handle:Destroy()
			table.remove(shakes, index)
		else
			index += 1
		end
	end
	return position, rotation
end

--------------------------------------------------------------------------------------------------
-- Hit-stop
--------------------------------------------------------------------------------------------------

-- Stops the world for `seconds`. Never stacks: an overlapping stop resolves to the longer of the two,
-- because three quick hits adding to 270 ms read as a freeze and a dropped input, not as impact.
--
-- `role` is who the local player was. Landing a hit plants their feet, which is most of what makes a
-- melee blow feel heavy; taking one does not, because the knockback has to land.
function Feel.hitStop(seconds: number, role: Role?)
	if seconds <= 0 then
		return
	end
	local merged = FeelMath.mergeHitStop(hitStopRemaining, seconds)
	if merged > hitStopRemaining or hitStopRole == "None" then
		hitStopRole = role or "None"
	end
	hitStopRemaining = merged
end

-- Scales the stop by the damage that caused it, so a jab and an ultimate do not pause for the same time.
function Feel.hitStopForDamage(damage: number, role: Role?)
	Feel.hitStop(FeelMath.hitStopSeconds(damage, FeelConfig.HitStop), role)
end

local function plantFeet()
	if not FeelConfig.HitStop.PlantOnDealt or hitStopRole ~= "Dealt" then
		return
	end
	-- Never during a server-approved displacement: cancelling a dash the server already granted would
	-- desynchronise the travel budget and cost the player their i-frames.
	if movementController ~= nil and movementController.isDisplacing() then
		return
	end
	local root = localRoot()
	if root == nil then
		return
	end
	-- Horizontal only. Zeroing the vertical component would hang the player in mid-air and, worse,
	-- cancel a fall they were relying on.
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
end

--------------------------------------------------------------------------------------------------
-- Field of view
--------------------------------------------------------------------------------------------------

-- Kicks the field of view. This is an impulse on a spring, not a target, so two punches in one frame
-- compose, and the view always returns to whatever the camera's own base is.
function Feel.fovPunch(degrees: number)
	if degrees == 0 then
		return
	end
	fovSpring:impulse(degrees)
end

local function stepFov(camera: Camera, deltaTime: number)
	-- Re-base every frame: read back what we added last frame so anything else writing FieldOfView --
	-- a future cutscene, the engine, a player setting -- wins instead of fighting us.
	local base = camera.FieldOfView - appliedFovOffset
	fovSpring:setGoal(0)
	local offset = fovSpring:step(deltaTime)
	if fovSpring:isSettled(FeelConfig.Fov.SettleEpsilon) and offset ~= 0 then
		fovSpring:snap(0)
		offset = 0
	end
	offset = math.clamp(offset, -FeelConfig.Fov.MaxOffsetDegrees, FeelConfig.Fov.MaxOffsetDegrees)
	camera.FieldOfView = base + offset
	appliedFovOffset = offset
end

--------------------------------------------------------------------------------------------------
-- Hit flash
--------------------------------------------------------------------------------------------------

-- A brief outline on whatever was just hit, drawn through walls and through other players. In a
-- six-player fight this is the only way to tell that YOUR hit landed.
function Feel.flash(model: Model, color: Color3)
	if model.Parent == nil then
		return
	end
	if #flashes >= FeelConfig.Flash.MaxConcurrent then
		local oldest = table.remove(flashes, 1)
		if oldest ~= nil then
			oldest.Highlight:Destroy()
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "FeelFlash"
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = FeelConfig.Flash.FillTransparency
	highlight.OutlineTransparency = FeelConfig.Flash.OutlineTransparency
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = model
	highlight.Parent = model
	table.insert(flashes, { Highlight = highlight, Remaining = FeelConfig.Flash.Seconds })
end

local function stepFlashes(deltaTime: number)
	local index = 1
	while index <= #flashes do
		local entry = flashes[index]
		entry.Remaining -= deltaTime
		if entry.Remaining <= 0 or entry.Highlight.Adornee == nil then
			entry.Highlight:Destroy()
			table.remove(flashes, index)
		else
			index += 1
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Damage numbers
--------------------------------------------------------------------------------------------------

-- Spawns a floating number. `critical` is the amplified hit (docs/GAME_DESIGN.md §6), which gets its
-- own size and its own colour so a player learns the interaction by seeing it pay off.
function Feel.damageNumber(position: Vector3, amount: number, color: Color3, critical: boolean?)
	local config = FeelConfig.DamageNumbers
	if #numbers >= config.MaxConcurrent then
		local oldest = table.remove(numbers, 1)
		if oldest ~= nil then
			DamageNumber.release(oldest.Marker)
		end
	end

	local severity = FeelMath.severity(amount, FeelConfig.HitStop)
	local sizeScale = FeelMath.lerp(1, config.MaxSizeScale, severity)
	if critical then
		sizeScale *= 1.15
	end

	local marker = DamageNumber.acquire()
	DamageNumber.dress(marker, tostring(math.floor(amount + 0.5)), color, sizeScale)

	-- Deterministic scatter: a counter through a sine rather than math.random, so two clients watching
	-- the same fight scatter their numbers the same way and a recording is reproducible.
	numberSeed += 1
	local angle = numberSeed * 2.39996
	local drift = Vector3.new(math.cos(angle), 0, math.sin(angle)) * config.SpreadStuds

	local pop = Spring.new(0, config.Tension, config.Friction)
	pop:setGoal(1)
	pop:impulse(config.PopScale * config.Tension / config.Friction)

	table.insert(numbers, {
		Marker = marker,
		Origin = position + Vector3.new(0, config.HeightStuds, 0),
		Drift = drift,
		Elapsed = 0,
		Pop = pop,
	})
end

local function stepNumbers(deltaTime: number)
	local config = FeelConfig.DamageNumbers
	local index = 1
	while index <= #numbers do
		local entry = numbers[index]
		entry.Elapsed += deltaTime
		local alpha = entry.Elapsed / config.Seconds
		if alpha >= 1 then
			DamageNumber.release(entry.Marker)
			table.remove(numbers, index)
		else
			-- Rises fast then slows, the way a thrown thing does, instead of sliding up at one speed.
			local rise = config.RiseStuds * (1 - (1 - alpha) * (1 - alpha))
			local position = entry.Origin + Vector3.new(0, rise, 0) + entry.Drift * alpha
			local transparency = 1 - FeelMath.holdThenFade(alpha, config.HoldFraction)
			DamageNumber.place(entry.Marker, position, transparency, entry.Pop:step(deltaTime))
			index += 1
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Haptics
--------------------------------------------------------------------------------------------------

-- Buzzes the gamepad. Gamepad only: Roblox exposes no vibration API for phones, so the mobile half of
-- the plan's haptics line cannot be built and is not pretended (D-49).
function Feel.haptic(name: string)
	if not FeelConfig.Haptics.Enabled then
		return
	end
	local pulse = FeelConfig.Haptics[name]
	if type(pulse) ~= "table" then
		log.warn("unknown haptic %s", name)
		return
	end
	if not HapticService:IsVibrationSupported(GAMEPAD) then
		return
	end
	local motors: { { Enum.VibrationMotor } } = {
		{ Enum.VibrationMotor.Small },
		{ Enum.VibrationMotor.Large },
	}
	local amounts = { pulse.Small, pulse.Large }
	for index, entry in ipairs(motors) do
		local motor = entry[1]
		if amounts[index] > 0 and HapticService:IsMotorSupported(GAMEPAD, motor) then
			HapticService:SetMotor(GAMEPAD, motor, amounts[index])
			task.delay(pulse.Seconds, function()
				HapticService:SetMotor(GAMEPAD, motor, 0)
			end)
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Springs for everyone else
--------------------------------------------------------------------------------------------------

-- A spring with one of FeelConfig's named constants, for the HUD and the screens. Handed out rather
-- than required directly so every spring in the game is tuned from the same file.
function Feel.newSpring(name: string, value: number?): SpringType
	local preset = FeelConfig.Springs[name]
	if preset == nil then
		log.warn("unknown spring preset %s", name)
		preset = FeelConfig.Springs.Ui
	end
	return Spring.new(value or 0, preset.Tension, preset.Friction)
end

--------------------------------------------------------------------------------------------------
-- The one render loop
--------------------------------------------------------------------------------------------------

local function onRender(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	if hitStopRemaining > 0 then
		hitStopRemaining -= deltaTime
		plantFeet()
		-- Held, not recomputed: the camera stops dead where the impact caught it. Everything else keeps
		-- its own time, so the release is a snap rather than a rewind.
		camera.CFrame = camera.CFrame
			* CFrame.new(heldPosition)
			* CFrame.Angles(heldRotation.X, heldRotation.Y, heldRotation.Z)
		stepNumbers(deltaTime)
		stepFlashes(deltaTime)
		return
	end

	local position, rotation = stepShakes()
	heldPosition = position
	heldRotation = rotation
	if position ~= Vector3.zero or rotation ~= Vector3.zero then
		camera.CFrame = camera.CFrame * CFrame.new(position) * CFrame.Angles(rotation.X, rotation.Y, rotation.Z)
	end

	stepFov(camera, deltaTime)
	stepNumbers(deltaTime)
	stepFlashes(deltaTime)
end

local function releaseAll()
	for _, entry in ipairs(shakes) do
		entry.Handle:Destroy()
	end
	table.clear(shakes)
	for _, entry in ipairs(flashes) do
		entry.Highlight:Destroy()
	end
	table.clear(flashes)
	for _, entry in ipairs(numbers) do
		DamageNumber.release(entry.Marker)
	end
	table.clear(numbers)
	heldPosition = Vector3.zero
	heldRotation = Vector3.zero
	hitStopRemaining = 0
	hitStopRole = "None"
	fovSpring:snap(0)
	appliedFovOffset = 0
end

function Feel.Init(deps: Deps)
	clientData = deps.ClientData
	movementController = deps.MovementController
end

function Feel.Start()
	RunService:BindToRenderStep(RENDER_NAME, RENDER_PRIORITY, onRender)
	-- A shake, a flash or a number outliving the character it belonged to would follow the player into
	-- their next life, adorned to a model that no longer exists.
	player.CharacterRemoving:Connect(releaseAll)
	log.info("started")
end

return Feel
