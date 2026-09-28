--!strict
-- Motion, run: the real src/ui/Motion.luau and its springs, on a pretend Heartbeat (tests/engine.luau).
--
-- A movement that starts where another arrives -- a loop's next leg, a flash that goes out and comes back, a
-- claim that wiggles one way then the other -- is started from inside the loop's own pass. That pass used to
-- drop the instance's whole entry once nothing was left moving in it, the new track included: every
-- zero-hold loop stopped after its first leg and every chained flash stayed on its first colour.
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function setup()
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
	})
	local Motion = world.require("src/ui/Motion")
	local frame = Engine.instance("Frame", world.game)
	return world, Motion, frame
end

describe("Motion, run on a Heartbeat", function()
	it("keeps a zero-hold loop going past its first leg", function()
		local world, Motion, frame = setup()
		frame.BackgroundTransparency = 0
		local stop = Motion.loop(frame, { BackgroundTransparency = 0 }, { BackgroundTransparency = 1 }, "UiSnappy")
		local reachedB, backToA = false, false
		for _ = 1, 360 do
			world:frames(1)
			local value = frame.BackgroundTransparency
			if value >= 0.999 then
				reachedB = true
			elseif reachedB and value <= 0.001 then
				backToA = true
			end
		end
		expect(reachedB).toBe(true)
		expect(backToA).toBe(true)
		-- Still moving six seconds in: the loop is not waiting on a spring nobody steps.
		expect(world.Heartbeat:count()).toBe(1)
		stop()
		world:advance(2)
		expect(frame.BackgroundTransparency).toBeCloseTo(0, 3)
		expect(world.Heartbeat:count()).toBe(0)
	end)

	it("ends a set, spring, set, spring flash on its goal (the hotbar's and the dock's refusal)", function()
		local world, Motion, frame = setup()
		local chalk, pigment = 5, 9
		Motion.set(frame, { Rotation = chalk })
		Motion.to(frame, { Rotation = pigment }, "UiPop", function()
			Motion.set(frame, { Rotation = chalk })
			Motion.to(frame, { Rotation = pigment }, "UiPop")
		end)
		local backToChalk = false
		for _ = 1, 180 do
			world:frames(1)
			if frame.Rotation == chalk then
				backToChalk = true
			end
		end
		expect(backToChalk).toBe(true)
		expect(frame.Rotation).toBe(pigment)
		expect(world.Heartbeat:count()).toBe(0)
	end)

	it("runs a wiggle's three legs to rest (the quest card's claim)", function()
		local world, Motion, frame = setup()
		local extremes = {}
		Motion.to(frame, { Rotation = 2 }, "UiSnappy", function()
			table.insert(extremes, frame.Rotation)
			Motion.to(frame, { Rotation = -2 }, "UiSnappy", function()
				table.insert(extremes, frame.Rotation)
				Motion.to(frame, { Rotation = 0 }, "UiPop")
			end)
		end)
		world:advance(3)
		expect(extremes).toEqual({ 2, -2 })
		expect(frame.Rotation).toBe(0)
	end)

	it("starts a property the entry did not have from an arrival, in the same frame", function()
		local world, Motion, frame = setup()
		frame.BackgroundTransparency = 0
		local arrivedAt: number? = nil
		Motion.to(frame, { Rotation = 10 }, "UiSnappy", function()
			arrivedAt = world.now
			Motion.to(frame, { BackgroundTransparency = 1 }, "UiSnappy")
		end)
		world:advance(3)
		expect(arrivedAt).never.toBeNil()
		expect(frame.Rotation).toBe(10)
		expect(frame.BackgroundTransparency).toBe(1)
	end)

	it("closes its one loop when nothing moves, and forgets a destroyed instance", function()
		local world, Motion, frame = setup()
		Motion.to(frame, { Rotation = 45 }, "Ui")
		expect(world.Heartbeat:count()).toBe(1)
		world:advance(0.1)
		frame:Destroy()
		world:frames(1)
		expect(world.Heartbeat:count()).toBe(0)
	end)
end)

return nil
