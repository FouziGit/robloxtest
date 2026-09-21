--!strict
-- Motion: every movement in the interface, driven by springs from one loop.
--
-- docs/JUICE_AUDIT.md counted the interface's interpolations: seven Quad, six Linear, four Back, one Sine,
-- and zero springs. A tween is a curve chosen in advance; a spring is a body with a velocity, which is why
-- a spring retargeted mid-flight keeps moving instead of restarting, and why a pop overshoots by exactly
-- as much as it was pushed. The plan's phase 6 asks for springs everywhere, and this is the one place
-- they are.
--
-- One Heartbeat drives every property of every instance in motion, the way VfxTimeline drives every
-- layer: twenty things moving cost one connection, and the total is a number this file knows.
--
-- A property is animated by a scalar spring from 0 to 1 and interpolated between where the property was
-- and where it is going. That is what lets one spring serve a number, a colour, a UDim2 or a Vector2:
-- the type only decides how to lerp.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FeelConfig = require(Shared.Config.FeelConfig)
local Spring = require(Shared.Pure.Spring)

export type Preset = "Ui" | "UiSnappy" | "UiGhost"

-- Spring's handle type is the metatable-wrapped record Spring.new returns; it is not exported.
type SpringHandle = typeof(Spring.new(0, 0, 0))

type Track = {
	Spring: SpringHandle,
	From: any,
	To: any,
	-- Called once, when the property arrives. Replaced by a retarget: only the last goal's arrival counts.
	OnSettled: (() -> ())?,
}

type Entry = { [string]: Track }

local Motion = {}

-- Past this the spring is at rest and the property is written exactly; a spring that is never
-- declared settled is a Heartbeat that never ends.
local SETTLE_EPSILON = 0.0015

local entries: { [Instance]: Entry } = {}
local connection: RBXScriptConnection? = nil

local function lerp(from: any, to: any, alpha: number): any
	local kind = typeof(to)
	if kind == "number" then
		return from + (to - from) * alpha
	end
	-- The engine's lerps clamp nothing, and a colour past its target is a different colour: only a
	-- number is allowed to overshoot.
	local clamped = math.clamp(alpha, 0, 1)
	if kind == "Color3" then
		return (from :: Color3):Lerp(to, clamped)
	elseif kind == "UDim2" then
		return (from :: UDim2):Lerp(to, clamped)
	elseif kind == "Vector2" then
		return (from :: Vector2):Lerp(to, clamped)
	elseif kind == "Vector3" then
		return (from :: Vector3):Lerp(to, clamped)
	elseif kind == "UDim" then
		local a = from :: UDim
		local b = to :: UDim
		return UDim.new(a.Scale + (b.Scale - a.Scale) * clamped, a.Offset + (b.Offset - a.Offset) * clamped)
	end
	return to
end

local function presetOf(name: Preset?): { Tension: number, Friction: number }
	return FeelConfig.Springs[name or "Ui"]
end

local function step(deltaTime: number)
	for instance, entry in pairs(entries) do
		if not instance:IsDescendantOf(game) then
			-- Destroyed under us: a Trove destroyed the screen. Nothing to write to, nothing to keep.
			entries[instance] = nil
			continue
		end
		local remaining = 0
		for property, track in pairs(entry) do
			local alpha = Spring.step(track.Spring, deltaTime)
			if Spring.isSettled(track.Spring, SETTLE_EPSILON) then
				(instance :: any)[property] = track.To
				entry[property] = nil
				local onSettled = track.OnSettled
				if onSettled ~= nil then
					onSettled()
				end
			else
				(instance :: any)[property] = lerp(track.From, track.To, alpha)
				remaining += 1
			end
		end
		if remaining == 0 then
			entries[instance] = nil
		end
	end
	if next(entries) == nil and connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureLoop()
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

-- Moves each property of `instance` to its value in `goals`, on the spring `preset`. A property already
-- in motion is retargeted from where it is now, keeping its velocity: the spring's whole point.
-- `onSettled` runs once the LAST of the goals arrives -- a toast that releases itself after fading, a
-- chip that destroys itself after shrinking.
function Motion.to(instance: Instance, goals: { [string]: any }, preset: Preset?, onSettled: (() -> ())?)
	local def = presetOf(preset)
	local pending = 0
	for _ in pairs(goals) do
		pending += 1
	end
	local function arrive()
		pending -= 1
		if pending == 0 and onSettled ~= nil then
			onSettled()
		end
	end
	local entry = entries[instance]
	if entry == nil then
		entry = {}
		entries[instance] = entry
	end
	for property, goal in pairs(goals) do
		local current = (instance :: any)[property]
		local track = entry[property]
		if track ~= nil then
			-- Restart from the interpolated value with the spring's velocity carried over, so a bar hit
			-- twice keeps moving rather than stalling on the second hit.
			local velocity = track.Spring.Velocity
			track.From = current
			track.To = goal
			track.OnSettled = arrive
			-- The preset of THIS call, not the one the property happened to be moving on: a bar caught
			-- mid-regeneration and then hit has to drop on UiSnappy like any other hit.
			track.Spring.Tension = def.Tension
			track.Spring.Friction = def.Friction
			Spring.snap(track.Spring, 0)
			Spring.setGoal(track.Spring, 1)
			Spring.impulse(track.Spring, velocity)
		else
			local spring = Spring.new(0, def.Tension, def.Friction)
			Spring.setGoal(spring, 1)
			entry[property] = { Spring = spring, From = current, To = goal, OnSettled = arrive }
		end
	end
	ensureLoop()
end

-- Writes the properties now and forgets any motion on them: for a first render, or a screen that opens
-- already in place.
function Motion.set(instance: Instance, values: { [string]: any })
	local entry = entries[instance]
	for property, value in pairs(values) do
		(instance :: any)[property] = value
		if entry ~= nil then
			entry[property] = nil
		end
	end
end

-- Forgets every motion on `instance`. A Trove holds this for anything it destroys, so a screen that
-- closes mid-motion does not keep a spring alive on a dead frame until the next sweep notices.
function Motion.cancel(instance: Instance)
	entries[instance] = nil
end

return Motion
