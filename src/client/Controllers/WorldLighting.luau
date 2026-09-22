--!strict
-- WorldLighting: the one place that writes Lighting, the Atmosphere and the five post-processing effects.
-- Every number it uses comes from Config/LightingConfig; nothing here decides how the world looks.
--
-- docs/JUICE_AUDIT.md found no script in the repository touching Lighting at all: the game ran on the
-- default sky and the default light, which is why a screenshot of it could have come from any other game.
-- The resting configuration applied at Start is the answer to that, and it is applied to whatever is
-- already in the place rather than to instances of our own -- an arena that ships with its own
-- ColorCorrectionEffect gets driven, not shadowed by a second one, because two effects of the same class
-- multiply and the result depends on which one loaded last.
--
-- Pulses are the other half. A gameplay event names a profile, and that profile's offsets ride a spring
-- from rest and back to rest. They are offsets rather than target values on purpose: the applied value is
-- rebuilt every frame as rest plus the sum of what is live, so an interrupted pulse, two overlapping
-- pulses and a pulse whose envelope was re-armed mid-release all end at exactly the resting value. Nothing
-- in this file can leave a permanent post-processing effect behind, which is what docs/JUICE_PLAN.md
-- phase 3 forbids.
--
-- One connection drives all of it, on Heartbeat rather than on the render step: post-processing is not
-- coupled to the camera, and the render step belongs to Feel, which owns the camera. While no pulse is
-- live the connection returns on its first line.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local LightingConfig = require(Shared.Config.LightingConfig)
local Log = require(Shared.Util.Log)
local QualityConfig = require(Shared.Config.QualityConfig)
local Spring = require(Shared.Pure.Spring)

local log = Log.new("WorldLighting")

type Deps = { ClientData: any, QualityController: any }

type SpringType = typeof(Spring.new(0, 1, 1))

-- One live envelope. Phase is where it is in attack -> hold -> release; the weight is a spring whose
-- position is the 0-to-1 fraction of the profile's offsets currently applied.
type ActivePulse = {
	Profile: LightingConfig.PulseProfile,
	Weight: SpringType,
	Phase: "Attack" | "Hold" | "Release",
	HoldRemaining: number,
}

-- One property of one effect, resolved once at Start: the instance to write, the resting value, the band
-- to clamp into, and the shared bucket its live offset accumulates in. Flattened so the frame loop walks
-- an array of numbers instead of three levels of config table.
type Plan = {
	Target: Instance,
	Property: string,
	Rest: number,
	Min: number,
	Max: number,
	Bucket: { [string]: number },
}

-- Prefix for instances this controller had to create, so a human opening the place can tell them from one
-- the level put there. An instance we found keeps the name it came with: renaming somebody else's is how
-- a reference in their own script stops resolving.
local CREATED_PREFIX = "Vellum"

local WorldLighting = {}

local clientData: any
local quality: any

-- False only when the player has asked for less motion on screen. Absent data means yes: a pulse
-- suppressed because a profile had not loaded yet would make the first impact of a session feel
-- different from every one after it.
local function motionAllowed(): boolean
	if clientData == nil then
		return true
	end
	local data = clientData.get()
	if data == nil then
		return true
	end
	return data.Settings.CameraShake ~= false
end

local plan: { Plan } = {}
-- The five instances buildEffects resolved, in EffectOrder. Held so the tier can switch exactly those.
local effectTargets: { Instance } = {}
local buckets: { [string]: { [string]: number } } = {}
local live: { [string]: ActivePulse } = {}
local liveCount = 0
-- True while the effects are showing something other than their resting values. It is what lets the
-- connection return immediately when nothing is happening, and it stays true for the one frame after the
-- last pulse ends, which is the frame that writes rest back.
local offset = false

local lightingColors: { [string]: Color3 } = {}
local atmosphereColors: { [string]: Color3 } = {}
local effectColors: { [string]: { [string]: Color3 } } = {}

local function toColor(rgb: LightingConfig.Rgb): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- One assignment per call, inside a pcall. A property Roblox turns read-only in a later version, or drops
-- with a graphics technology, must cost one warning and leave the rest of the configuration applied:
-- losing the whole look of the world over one renamed property is not a trade worth taking.
local function assign(target: Instance, property: string, value: any)
	local ok, err = pcall(function()
		(target :: any)[property] = value
	end)
	if not ok then
		log.warn("could not set %s.%s: %s", target.ClassName, property, tostring(err))
	end
end

--------------------------------------------------------------------------------------------------
-- The resting configuration
--------------------------------------------------------------------------------------------------

local function applyLighting()
	for property, color in pairs(lightingColors) do
		assign(Lighting, property, color)
	end
	for property, value in pairs(LightingConfig.Lighting.Numbers) do
		assign(Lighting, property, value)
	end
	for property, value in pairs(LightingConfig.Lighting.Flags) do
		assign(Lighting, property, value)
	end
	-- The technology is a plain string in the config, which has to stay engine-free. An unknown name
	-- leaves the place on whatever it already had rather than throwing: a world lit by the wrong
	-- technology is still a world.
	local name = LightingConfig.Lighting.Technology
	local technology = (Enum.Technology :: any)[name]
	if technology == nil then
		log.warn("unknown lighting technology %s", name)
	else
		assign(Lighting, "Technology", technology)
	end
end

-- The instance of `className` under Lighting, created and parented if the place has none. nil only when
-- creation itself failed, which is a client too old to know the class.
local function findOrCreate(className: string): Instance?
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing ~= nil then
		return existing
	end
	local ok, result = pcall(Instance.new, className)
	if not ok or typeof(result) ~= "Instance" then
		log.warn("could not create %s: %s", className, tostring(result))
		return nil
	end
	local created = result :: Instance
	created.Name = CREATED_PREFIX .. className
	created.Parent = Lighting
	return created
end

-- The sky (LightingConfig.Sky): a Sky object whose six faces are empty, which removes Roblox's stock
-- skybox and hands the horizon to the Atmosphere.
local function applySky()
	local sky = findOrCreate("Sky")
	if sky == nil then
		return
	end
	assign(sky, "CelestialBodiesShown", LightingConfig.Sky.CelestialBodiesShown)
	for _, face in ipairs(LightingConfig.Sky.Faces) do
		assign(sky, face, "")
	end
end

local function applyAtmosphere()
	local atmosphere = findOrCreate("Atmosphere")
	if atmosphere == nil then
		return
	end
	for property, value in pairs(LightingConfig.Atmosphere.Numbers) do
		assign(atmosphere, property, value)
	end
	for property, color in pairs(atmosphereColors) do
		assign(atmosphere, property, color)
	end
end

-- Finds or creates the five effects and builds the frame plan. Each one is left Enabled and driven by its
-- value instead of being toggled: switching Enabled compiles a shader, and the first pulse of a fight is
-- exactly when a compile hitch is least affordable.
local function buildEffects()
	for _, name in ipairs(LightingConfig.EffectOrder) do
		local def = LightingConfig.Effects[name]
		local target = findOrCreate(def.ClassName)
		if target ~= nil then
			table.insert(effectTargets, target)
			assign(target, "Enabled", true)
			local colors = effectColors[name]
			if colors ~= nil then
				for property, color in pairs(colors) do
					assign(target, property, color)
				end
			end
			local bucket: { [string]: number } = {}
			buckets[name] = bucket
			for property, rest in pairs(def.Rest) do
				local band = def.Limits[property]
				if band == nil then
					-- tests/LightingConfig.spec.luau fails the build for this, so it can only happen on a
					-- client running a config this repository never gated.
					log.warn("%s.%s has no band and is left alone", name, property)
				else
					bucket[property] = 0
					table.insert(plan, {
						Target = target,
						Property = property,
						Rest = rest,
						Min = band[1],
						Max = band[2],
						Bucket = bucket,
					})
				end
			end
		end
	end
end

-- Whether this client is drawing post-processing at all (QualityConfig's lowest tier cuts it).
local function postProcessing(): boolean
	if quality == nil then
		return true
	end
	local tier: QualityConfig.TierDef = quality.def()
	return tier.PostProcessing == true
end

-- Writes rest plus whatever is currently in the buckets. The only writer of the five effects.
local function applyPlan()
	for _, entry in ipairs(plan) do
		local value = math.clamp(entry.Rest + entry.Bucket[entry.Property], entry.Min, entry.Max);
		(entry.Target :: any)[entry.Property] = value
	end
end

-- The five effects, on or off as a whole. Off is the Performance tier: every effect disabled, so the
-- client pays for none of them, and the world is still lit high and pale because that is Lighting itself
-- and not these. Re-enabling compiles shaders, which is why QualityController gives a tier back slowly.
--
-- It toggles the instances buildEffects resolved, not whatever FindFirstChildOfClass returns now: a place
-- can hold a second ColorCorrectionEffect somebody else owns, and disabling theirs -- or missing ours --
-- is a look nobody chose.
local function setEffectsEnabled(enabled: boolean)
	for _, target in ipairs(effectTargets) do
		assign(target, "Enabled", enabled)
	end
end

--------------------------------------------------------------------------------------------------
-- Pulses
--------------------------------------------------------------------------------------------------

-- Turns a phase duration into the critically damped spring that covers it (see Envelope in the config).
-- Critical rather than under-damped: an overshoot here would push a value past the peak the config
-- declares and into its clamp, which is a safety net and not a look.
local function shape(spring: SpringType, seconds: number)
	local frequency = LightingConfig.Envelope.Settle / math.max(seconds, LightingConfig.Envelope.MinPhaseSeconds)
	spring.Tension = frequency * frequency
	spring.Friction = Spring.criticalFriction(spring.Tension)
end

-- Drives the named profile. Composable across profiles, self-cancelling within one: a second PageFlash
-- while the first is still fading re-arms that one envelope instead of stacking a second, so twenty
-- impacts in a second read as one sustained bleach rather than as a white screen. The re-armed spring
-- keeps its position and its velocity, so it accelerates back up from wherever it had got to.
-- `strength` is how much of the profile to apply, 0 to 1, and it defaults to all of it. Without it the
-- only thing a caller could do about distance was fire or not fire, so an impact at the edge of the
-- falloff radius bleached the page exactly as hard as one in the player's face -- which is the same
-- defect the four-stud radius test used to cause for camera shake, in the other direction.
--
-- A stronger pulse re-arming a weaker one wins; a weaker one arriving mid-pulse does not pull it down,
-- because a far explosion must not soften the near one that is already playing.
function WorldLighting.pulse(name: string, strength: number?)
	if not motionAllowed() or not postProcessing() then
		return
	end
	local profile = LightingConfig.Pulses[name]
	if profile == nil then
		log.warn("unknown lighting pulse %s", name)
		return
	end
	if #plan == 0 then
		return
	end
	local goal = math.clamp(strength or 1, 0, 1)
	if goal <= 0 then
		return
	end

	local existing = live[name]
	if existing ~= nil then
		shape(existing.Weight, profile.AttackSeconds)
		existing.Weight:setGoal(math.max(goal, existing.Weight.Goal))
		existing.Phase = "Attack"
		existing.HoldRemaining = profile.HoldSeconds
		offset = true
		return
	end

	local weight = Spring.new(0, 1, 1)
	shape(weight, profile.AttackSeconds)
	weight:setGoal(goal)
	live[name] = { Profile = profile, Weight = weight, Phase = "Attack", HoldRemaining = profile.HoldSeconds }
	liveCount += 1
	offset = true
end

-- Advances one envelope. The phase ends on the spring's POSITION rather than on a timer, so the peak a
-- pulse reaches is the offset the config declares and not whatever the spring happened to be passing when
-- a timer expired.
local function advance(pulse: ActivePulse, deltaTime: number)
	local epsilon = LightingConfig.Envelope.SettleEpsilon
	local weight = pulse.Weight
	if pulse.Phase == "Attack" then
		weight:step(deltaTime)
		if weight.Position >= 1 - epsilon then
			weight:snap(1)
			pulse.Phase = "Hold"
		end
	elseif pulse.Phase == "Hold" then
		pulse.HoldRemaining -= deltaTime
		if pulse.HoldRemaining <= 0 then
			shape(weight, pulse.Profile.ReleaseSeconds)
			weight:setGoal(0)
			pulse.Phase = "Release"
		end
	else
		weight:step(deltaTime)
	end
end

--------------------------------------------------------------------------------------------------
-- The one loop
--------------------------------------------------------------------------------------------------

local function onHeartbeat(deltaTime: number)
	if liveCount == 0 and not offset then
		return
	end

	for name, pulse in pairs(live) do
		advance(pulse, deltaTime)
		if pulse.Phase == "Release" and pulse.Weight.Position <= LightingConfig.Envelope.SettleEpsilon then
			live[name] = nil
			liveCount -= 1
		end
	end

	-- Rebuilt from zero every frame, never adjusted in place. That is the whole reason a pulse cannot
	-- leave anything behind: once the last one is gone every bucket is zero and the next write is rest.
	for _, entry in ipairs(plan) do
		entry.Bucket[entry.Property] = 0
	end
	for _, pulse in pairs(live) do
		local weight = pulse.Weight.Position
		for effectName, deltas in pairs(pulse.Profile.Deltas) do
			local bucket = buckets[effectName]
			if bucket ~= nil then
				for property, delta in pairs(deltas) do
					local current = bucket[property]
					if current ~= nil then
						bucket[property] = current + delta * weight
					end
				end
			end
		end
	end

	applyPlan()
	offset = liveCount > 0
end

--------------------------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------------------------

-- Init converts, Start writes.
--
-- ClientData is taken for one reason: Settings.CameraShake. A pulse is a full-screen brightness and
-- saturation change, and it is driven by the same events Feel shakes the camera for. A player who turns
-- camera shake off is almost always turning it off because motion on screen makes them ill, and bleaching
-- their whole screen on every nearby impact is a worse version of the thing they asked to stop.
--
-- It is that toggle rather than a new one because it is the only motion-reduction control the profile
-- has (SettingsData in src/shared/Types.luau is two keybind maps, two volumes and this), and a setting
-- invented here would be one no screen exposes and nothing persists. Phase 6 of docs/JUICE_PLAN.md
-- reworks the settings screen and can widen its label to what it now governs.
function WorldLighting.Init(deps: Deps)
	clientData = deps.ClientData
	quality = deps.QualityController
	for property, rgb in pairs(LightingConfig.Lighting.Colors) do
		lightingColors[property] = toColor(rgb)
	end
	for property, rgb in pairs(LightingConfig.Atmosphere.Colors) do
		atmosphereColors[property] = toColor(rgb)
	end
	for _, name in ipairs(LightingConfig.EffectOrder) do
		local restColors = LightingConfig.Effects[name].RestColors
		if restColors ~= nil then
			local converted: { [string]: Color3 } = {}
			for property, rgb in pairs(restColors) do
				converted[property] = toColor(rgb)
			end
			effectColors[name] = converted
		end
	end
end

function WorldLighting.Start()
	applyLighting()
	applyAtmosphere()
	applySky()
	buildEffects()
	applyPlan()
	setEffectsEnabled(postProcessing())
	quality.Changed:Connect(function()
		local on = postProcessing()
		if on then
			-- Back from the floor: the buckets are already zero (nothing can pulse while it is off), so
			-- writing the plan puts every effect at its resting value before it is shown again.
			applyPlan()
		end
		setEffectsEnabled(on)
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started, %d driven effect properties", #plan)
end

return WorldLighting
