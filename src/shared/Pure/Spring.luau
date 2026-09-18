--!strict
-- One spring, used by the camera, the HUD and the damage numbers. docs/JUICE_AUDIT.md measured five
-- linear tweens and three durations for the whole game, which is why nothing in it has weight: a linear
-- move has the same speed at the start, in the middle and at the end, and nothing in the physical world
-- does that.
--
-- Pure (no require, no Roblox global), so it is unit-tested under Lune rather than eyeballed in Studio.
-- That is also why this is not littensy/ripple (D-47): ripple resolves its own modules through Luau
-- string requires, which Lune cannot follow here, so no gate in this repository could ever have told
-- us whether it worked. A spring is sixty lines. A spring nobody can test is a liability.
--
-- The integrator is semi-implicit Euler at a fixed internal step. A spring integrated at the frame rate
-- diverges when a frame is long -- on the first frame after a level loads, dt can be a quarter of a
-- second -- and a diverging spring throws the camera across the map. Substepping is what makes it safe
-- to call with any dt at all.

local Spring = {}
Spring.__index = Spring

export type Spring = {
	Position: number,
	Velocity: number,
	Goal: number,
	Tension: number,
	Friction: number,
}

-- Fixed internal step. 240 Hz is stable for every tension in FeelConfig and costs four iterations at
-- 60 fps.
local STEP_SECONDS = 1 / 240
-- A frame longer than this is a hitch, not motion: the spring advances by this much and no more, so a
-- three second freeze does not become three seconds of catch-up the player watches.
local MAX_STEP_SECONDS = 0.1
local DEFAULT_EPSILON = 0.001

type SpringImpl = typeof(setmetatable({} :: Spring, Spring))

function Spring.new(value: number, tension: number, friction: number): SpringImpl
	return setmetatable({
		Position = value,
		Velocity = 0,
		Goal = value,
		Tension = tension,
		Friction = friction,
	}, Spring)
end

-- Where the spring is pulled toward. Motion continues from wherever it currently is.
function Spring.setGoal(self: SpringImpl, goal: number)
	self.Goal = goal
end

-- Teleports the spring and kills its motion: for a value that must not animate, such as the first frame
-- after a character respawns.
function Spring.snap(self: SpringImpl, value: number)
	self.Position = value
	self.Goal = value
	self.Velocity = 0
end

-- Adds velocity without moving the spring. This is what a punch is: the FOV is kicked and the spring
-- carries it out and back, so two punches in the same frame compose instead of the second replacing the
-- first.
function Spring.impulse(self: SpringImpl, velocity: number)
	self.Velocity += velocity
end

-- Advances by `deltaTime` and returns the new position.
function Spring.step(self: SpringImpl, deltaTime: number): number
	if deltaTime ~= deltaTime or deltaTime <= 0 then
		-- NaN or a non-advancing frame: hold, never integrate by an unknown amount.
		return self.Position
	end
	local remaining = math.min(deltaTime, MAX_STEP_SECONDS)
	local position = self.Position
	local velocity = self.Velocity
	local goal = self.Goal
	local tension = self.Tension
	local friction = self.Friction

	while remaining > 0 do
		local step = math.min(STEP_SECONDS, remaining)
		remaining -= step
		-- Semi-implicit: velocity is updated first, then position uses the NEW velocity. That one
		-- ordering is the difference between a spring that settles and a spring that gains energy.
		local acceleration = tension * (goal - position) - friction * velocity
		velocity += acceleration * step
		position += velocity * step
	end

	self.Position = position
	self.Velocity = velocity
	return position
end

-- True when the spring has arrived and stopped. Callers use it to disconnect: a spring that is stepped
-- forever is a per-object loop, which the conventions forbid.
function Spring.isSettled(self: SpringImpl, epsilon: number?): boolean
	local limit = epsilon or DEFAULT_EPSILON
	return math.abs(self.Goal - self.Position) <= limit and math.abs(self.Velocity) <= limit
end

-- The friction that makes a spring of this tension settle without overshooting at all. Anything below
-- it overshoots and comes back, which is what makes UI feel alive; anything above it crawls.
function Spring.criticalFriction(tension: number): number
	return 2 * math.sqrt(tension)
end

return Spring
