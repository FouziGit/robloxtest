--!strict
-- VfxClock: the clock every drawn effect runs on (Pure/EffectClock, D-118). Real time, except while an
-- impact holds it -- the burst, its sparks and its light stop dead together for a few hundredths of a
-- second, and nothing else does: inputs, movement and the server keep their own time -- and, in Studio
-- only, while the VFX lab (tools/vfxlab/) runs it slower or stops it to look at an effect frame by frame.
--
-- A sibling module, not a controller: VfxTimeline reads it on its own Heartbeat and calls tick() there,
-- Feel asks it for holds. It has no loop of its own; the time is computed from os.clock() when asked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local EffectClock = require(Shared.Pure.EffectClock)
local FeelConfig = require(Shared.Config.FeelConfig)

local VfxClock = {}

-- The attribute the Studio lab sets on the client's ReplicatedStorage to scale effect time; absent when
-- the lab is not running. Read in Studio only: a published game ignores it, whoever sets it.
VfxClock.LabAttribute = "VfxLabTimeScale"

local state = EffectClock.new(os.clock())

-- Effect time now.
function VfxClock.now(): number
	return EffectClock.read(state, os.clock())
end

-- How fast effect time runs now (0 while held or stopped), for what the engine animates on its own:
-- particles (ParticleEmitter.TimeScale) and trails.
function VfxClock.rate(): number
	return EffectClock.rate(state, os.clock())
end

-- Holds effect time still for `seconds` (capped at FeelConfig.EffectHold.Longest).
function VfxClock.hold(seconds: number)
	EffectClock.hold(state, os.clock(), seconds, FeelConfig.EffectHold.Longest)
end

-- The lab. While it runs, what the server sends is played when effect time reaches the moment it would
-- have arrived at had the whole world been slowed with it (VfxController holds the packets), so a slowed
-- or stopped frame shows the server's events in their true order and spacing. Never active in a published
-- game.
local labActive = false
local epochEffect = 0
local epochReal = 0
local ticks: { () -> () } = {}

function VfxClock.labActive(): boolean
	return labActive
end

-- The effect time something arriving now is due at, while the lab runs.
function VfxClock.due(): number
	return epochEffect + (os.clock() - epochReal)
end

-- Registers `callback` to run at the start of every effect frame (VfxTimeline's Heartbeat).
function VfxClock.onTick(callback: () -> ())
	table.insert(ticks, callback)
end

-- Runs the registered per-frame callbacks. Called by VfxTimeline only.
function VfxClock.tick()
	for _, callback in ipairs(ticks) do
		callback()
	end
end

if RunService:IsStudio() then
	local function follow()
		local scale = ReplicatedStorage:GetAttribute(VfxClock.LabAttribute)
		local real = os.clock()
		if type(scale) ~= "number" then
			labActive = false
			EffectClock.rescale(state, real, 1)
			return
		end
		if not labActive then
			labActive = true
			epochEffect = EffectClock.read(state, real)
			epochReal = real
		end
		EffectClock.rescale(state, real, scale)
	end
	ReplicatedStorage:GetAttributeChangedSignal(VfxClock.LabAttribute):Connect(follow)
	follow()
end

return VfxClock
