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
--
-- The helpers below the primitives (loop, countTo, stagger, punch, shake) ride the same Heartbeat: a badge
-- that breathes, a counter that counts and a list that enters add no loop of their own (tests/Loops.spec
-- .luau), and their waits are task.delay. They follow the player's reduced-motion setting (UiPrefs): the
-- overshooting presets fall back to plain springs, and what only decorates stands still.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FeelConfig = require(Shared.Config.FeelConfig)
local Spring = require(Shared.Pure.Spring)
local ThemeConfig = require(Shared.Config.ThemeConfig)
local UiPrefs = require(script.Parent.UiPrefs)
local UiSound = require(script.Parent.UiSound)

export type Preset = "Ui" | "UiSnappy" | "UiGhost" | "UiPop" | "UiExit"
export type Goals = { [string]: any }

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
-- How far a punch overshoots by default.
local PUNCH_PEAK = 1.15
-- A shake's reach in design units, and how long each of its legs pulls before the next retargets it: UiPop
-- is 95 % of the way in 0.08 s, so a leg cut shorter than that is still a visible jolt.
local SHAKE_AMPLITUDE = 8
local SHAKE_LEG_SECONDS = 0.06

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

-- Under reduced motion the pop loses its overshoot and the exit its length: the same movement, calmer.
local REDUCED: { [string]: Preset } = { UiPop = "Ui", UiExit = "UiSnappy" }

local function presetOf(name: Preset?): { Tension: number, Friction: number }
	local chosen: Preset = name or "Ui"
	if UiPrefs.reducedMotion() then
		chosen = REDUCED[chosen] or chosen
	end
	return FeelConfig.Springs[chosen]
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

-- Goes back and forth between the goals `a` and `b` for as long as it runs, holding `holdSeconds` at each
-- end: a badge that breathes, a pending button's dots, a claim that wiggles. It sets out toward `b` from
-- wherever the properties are. Returns the function that stops it (a Trove holds it), which springs the
-- properties back to `a`. A loop owns its properties: another Motion.to on them ends it. Under reduced
-- motion nothing moves: `a` is written once and the stop does nothing; a loop already running when the
-- player turns reduced motion on stands still at `a` from its next leg.
function Motion.loop(instance: Instance, a: Goals, b: Goals, preset: Preset?, holdSeconds: number?): () -> ()
	if UiPrefs.reducedMotion() then
		Motion.set(instance, a)
		return function() end
	end
	local running = true
	local hold = holdSeconds or 0
	local function leg(goals: Goals, after: Goals)
		if not running then
			return
		end
		if UiPrefs.reducedMotion() then
			running = false
			Motion.set(instance, a)
			return
		end
		Motion.to(instance, goals, preset, function()
			if not running then
				return
			end
			if hold > 0 then
				task.delay(hold, leg, after, goals)
			else
				leg(after, goals)
			end
		end)
	end
	leg(b, a)
	return function()
		if not running then
			return
		end
		running = false
		if instance:IsDescendantOf(game) then
			Motion.to(instance, a, preset)
		end
	end
end

-- A count in progress on a label: the value it springs, and what its ticks are measured against.
type Count = {
	Value: NumberValue,
	Format: (number) -> string,
	Start: number,
	Distance: number,
	Ticks: number,
}

-- A label that counts plays a click at every tenth of the way, and no more than ten.
local COUNT_TICKS = 10

local counts: { [Instance]: Count } = setmetatable({}, { __mode = "k" }) :: any

-- Counts `label` from `from` to `to` on a spring, writing `format` of the whole number it passes through,
-- with a UiClick at every tenth of the distance. A count already running on the label carries on from
-- where it is toward the new `to`. Under reduced motion the final text is written at once.
function Motion.countTo(label: TextLabel, from: number, to: number, format: (number) -> string, preset: Preset?)
	local count = counts[label]
	if UiPrefs.reducedMotion() then
		if count ~= nil then
			counts[label] = nil
			Motion.cancel(count.Value)
			count.Value:Destroy()
		end
		label.Text = format(math.floor(to + 0.5))
		return
	end
	if count == nil then
		local value = Instance.new("NumberValue")
		value.Name = "Count"
		value.Value = from
		local created: Count = { Value = value, Format = format, Start = from, Distance = 0, Ticks = 0 }
		value.Changed:Connect(function(current: number)
			label.Text = created.Format(math.floor(current + 0.5))
			if created.Distance <= 0 then
				return
			end
			local reached =
				math.min(COUNT_TICKS, math.floor(math.abs(current - created.Start) / created.Distance * COUNT_TICKS))
			if reached > created.Ticks then
				created.Ticks = reached
				UiSound.play("UiClick")
			end
		end)
		value.Parent = label
		counts[label] = created
		count = created
	end
	local running = count :: Count
	running.Format = format
	running.Start = running.Value.Value
	running.Distance = math.abs(to - running.Start)
	running.Ticks = 0
	label.Text = format(math.floor(running.Start + 0.5))
	Motion.to(running.Value, { Value = to }, preset, function()
		if counts[label] == running then
			counts[label] = nil
		end
		running.Value:Destroy()
		label.Text = format(math.floor(to + 0.5))
	end)
end

-- Moves each of `children` to `goals`, one every `stepSeconds`: the first `max` of them in turn, the rest
-- at once, so a long list costs no more than a short one (ThemeConfig.Timing, Budget.MaxStaggered). Under
-- reduced motion every child is set at once.
function Motion.stagger(children: { Instance }, goals: Goals, preset: Preset?, stepSeconds: number?, max: number?)
	local interval = stepSeconds or ThemeConfig.Timing.StaggerSeconds
	local limit = max or ThemeConfig.Timing.StaggerMax
	local reduced = UiPrefs.reducedMotion()
	for index, child in ipairs(children) do
		if reduced or index > limit then
			Motion.set(child, goals)
		elseif index == 1 then
			Motion.to(child, goals, preset)
		else
			task.delay((index - 1) * interval, function()
				if child:IsDescendantOf(game) then
					Motion.to(child, goals, preset)
				end
			end)
		end
	end
end

-- A punch: `scale` jumps to `peak` and pops back to 1. What a reward, a level or a ready glyph does.
function Motion.punch(scale: UIScale, peak: number?)
	Motion.set(scale, { Scale = peak or PUNCH_PEAK })
	Motion.to(scale, { Scale = 1 }, "UiPop")
end

-- The shake running on each GuiObject, and where it started: a shake on a shake takes over the first and
-- returns to where the first began.
type Shake = { Origin: UDim2 }
local shaking: { [Instance]: Shake } = setmetatable({}, { __mode = "k" }) :: any

-- A refusal: `object` jolts sideways by `amplitude`, back by half of it, and home, each leg retargeting the
-- last so the whole reads as one shake. Skipped under reduced motion: it only says "no" twice.
function Motion.shake(object: GuiObject, amplitude: number?)
	if UiPrefs.reducedMotion() then
		return
	end
	local reach = amplitude or SHAKE_AMPLITUDE
	local previous = shaking[object]
	local current: Shake = { Origin = if previous ~= nil then previous.Origin else object.Position }
	shaking[object] = current
	local origin = current.Origin
	local function at(offset: number): UDim2
		return UDim2.new(origin.X.Scale, origin.X.Offset + offset, origin.Y.Scale, origin.Y.Offset)
	end
	Motion.to(object, { Position = at(reach) }, "UiPop")
	task.delay(SHAKE_LEG_SECONDS, function()
		if shaking[object] ~= current then
			return
		end
		Motion.to(object, { Position = at(-reach / 2) }, "UiPop")
		task.delay(SHAKE_LEG_SECONDS, function()
			if shaking[object] ~= current then
				return
			end
			Motion.to(object, { Position = origin }, "UiPop", function()
				if shaking[object] == current then
					shaking[object] = nil
				end
			end)
		end)
	end)
end

return Motion
