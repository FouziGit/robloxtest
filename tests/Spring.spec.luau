--!strict
-- A spring that is wrong is worse than a tween: it either never arrives, or it gains energy and throws
-- whatever it drives off the screen. Both failures look like "the camera is broken" and neither is
-- obvious from reading the integrator.
local Harness = require("./harness")
local Spring = require("../src/shared/Pure/Spring")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local FRAME = 1 / 60

-- Advances a spring for `seconds` of frames and returns the largest position it ever reached.
local function run(spring: any, seconds: number): number
	local peak = spring.Position
	local elapsed = 0
	while elapsed < seconds do
		local position = spring:step(FRAME)
		if math.abs(position) > math.abs(peak) then
			peak = position
		end
		elapsed += FRAME
	end
	return peak
end

describe("Spring", function()
	it("arrives at its goal and stops there", function()
		local spring = Spring.new(0, 260, 24)
		spring:setGoal(10)
		run(spring, 3)
		expect(math.abs(spring.Position - 10) < 0.01).toBe(true)
		expect(spring:isSettled()).toBe(true)
	end)

	it("overshoots when it is underdamped, and not when it is critically damped", function()
		-- This is the whole reason the tension/friction pair is exposed in FeelConfig: the same spring
		-- with two frictions is two different feelings.
		local bouncy = Spring.new(0, 400, 10)
		bouncy:setGoal(1)
		expect(run(bouncy, 2) > 1.05).toBe(true)

		local critical = Spring.new(0, 400, Spring.criticalFriction(400))
		critical:setGoal(1)
		expect(run(critical, 2) <= 1.0001).toBe(true)
	end)

	it("survives a frame long enough to blow up a naive integrator", function()
		-- The first frame after a place loads can be a quarter of a second, and a level-streaming hitch
		-- can be worse. Integrated in one step at that dt, a tension-400 spring diverges immediately.
		local spring = Spring.new(0, 400, 12)
		spring:setGoal(1)
		spring:step(0.25)
		expect(spring.Position == spring.Position).toBe(true) -- not NaN
		expect(math.abs(spring.Position) < 10).toBe(true)
		run(spring, 3)
		expect(math.abs(spring.Position - 1) < 0.01).toBe(true)
	end)

	it("ignores a frame that did not advance, and a NaN one", function()
		local spring = Spring.new(5, 200, 20)
		spring:setGoal(9)
		expect(spring:step(0)).toBe(5)
		expect(spring:step(-1)).toBe(5)
		expect(spring:step(0 / 0)).toBe(5)
		expect(spring.Velocity).toBe(0)
	end)

	it("returns to its goal after an impulse instead of staying where it was kicked", function()
		-- A FOV punch is an impulse, not a goal. If the spring kept the kick, one cast would leave the
		-- view permanently wrong for the rest of the session.
		local spring = Spring.new(70, 220, 22)
		spring:setGoal(70)
		spring:impulse(-40)
		local moved = false
		for _ = 1, 10 do
			spring:step(FRAME)
			if math.abs(spring.Position - 70) > 0.5 then
				moved = true
			end
		end
		expect(moved).toBe(true)
		run(spring, 3)
		expect(math.abs(spring.Position - 70) < 0.05).toBe(true)
	end)

	it("composes two impulses in the same frame", function()
		local one = Spring.new(0, 220, 22)
		one:impulse(-20)
		local two = Spring.new(0, 220, 22)
		two:impulse(-20)
		two:impulse(-20)
		one:step(FRAME)
		two:step(FRAME)
		expect(two.Position < one.Position).toBe(true)
	end)

	it("snaps without animating", function()
		local spring = Spring.new(0, 200, 20)
		spring:setGoal(100)
		spring:step(FRAME)
		spring:snap(3)
		expect(spring.Position).toBe(3)
		expect(spring.Velocity).toBe(0)
		expect(spring:isSettled()).toBe(true)
	end)
end)
