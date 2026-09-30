--!strict
-- Motion, run: the real src/ui/Motion.luau and its springs, on a pretend Heartbeat (tests/engine.luau).
--
-- A movement that starts where another arrives -- a loop's next leg, a flash that goes out and comes back, a
-- tilt one way then the other -- is started from inside the loop's own pass. That pass used to
-- drop the instance's whole entry once nothing was left moving in it, the new track included: every
-- zero-hold loop stopped after its first leg and every chained flash stayed on its first colour.
local Engine = require("./engine")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")

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

	it("runs a tilt's three legs to rest, each started from the arrival of the last", function()
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

-- Whether `frame` moved over the next `seconds`.
local function moves(world: any, frame: any, property: string, seconds: number): boolean
	local start = frame[property]
	for _ = 1, math.floor(seconds * 60) do
		world:frames(1)
		if frame[property] ~= start then
			return true
		end
	end
	return false
end

describe("Motion's loops on a screen, run", function()
	local function loopOn(Motion: any, parent: any): (any, () -> ())
		local frame = Engine.instance("Frame", parent)
		frame.BackgroundTransparency = 0
		local stop = Motion.loop(frame, { BackgroundTransparency = 0 }, { BackgroundTransparency = 1 }, "Ui")
		return frame, stop
	end

	it("runs a screen's budget of loops, and stands the next one still, said once", function()
		local world, Motion = setup()
		local screen = Engine.instance("ScreenGui", world.playerGui)
		local budget = ThemeConfig.Budget.MaxIdleLoops
		local frames = {}
		for _ = 1, budget do
			table.insert(frames, (loopOn(Motion, screen)))
		end
		local extra = loopOn(Motion, screen)
		local another = loopOn(Motion, screen)
		for _, frame in ipairs(frames) do
			expect(moves(world, frame, "BackgroundTransparency", 0.5)).toBe(true)
		end
		expect(moves(world, extra, "BackgroundTransparency", 1)).toBe(false)
		expect(moves(world, another, "BackgroundTransparency", 1)).toBe(false)
		local said = 0
		for _, line in ipairs(world.warnings) do
			if string.find(line, "[Motion]", 1, true) ~= nil then
				said += 1
			end
		end
		expect(said).toBe(1)
	end)

	it("counts each screen apart, and nothing on no screen", function()
		local world, Motion = setup()
		local first = Engine.instance("ScreenGui", world.playerGui)
		local second = Engine.instance("ScreenGui", world.playerGui)
		for _ = 1, ThemeConfig.Budget.MaxIdleLoops do
			loopOn(Motion, first)
		end
		expect(moves(world, (loopOn(Motion, second)), "BackgroundTransparency", 0.5)).toBe(true)
		-- A shared breath lives in the PlayerGui, on no screen (Breath).
		expect(moves(world, (loopOn(Motion, world.playerGui)), "BackgroundTransparency", 0.5)).toBe(true)
	end)

	it("gives a loop's place back when it stops, or when its frame goes", function()
		local world, Motion = setup()
		local screen = Engine.instance("ScreenGui", world.playerGui)
		local stops, frames = {}, {}
		for _ = 1, ThemeConfig.Budget.MaxIdleLoops do
			local frame, stop = loopOn(Motion, screen)
			table.insert(frames, frame)
			table.insert(stops, stop)
		end
		stops[1]()
		expect(moves(world, (loopOn(Motion, screen)), "BackgroundTransparency", 0.5)).toBe(true)
		frames[2]:Destroy()
		expect(moves(world, (loopOn(Motion, screen)), "BackgroundTransparency", 0.5)).toBe(true)
	end)
end)

describe("a pending button, run", function()
	it("bounces its three dots on one of its screen's loops", function()
		local world, Motion = setup()
		local Button = world.require("src/ui/components/Button")
		local screen = Engine.instance("ScreenGui", world.playerGui)
		local button = Button.new({ Text = "", Parent = screen })
		button:SetPending(true)
		local dots = {}
		for _, child in ipairs(button.Instance:FindFirstChild("Pending", true):GetChildren()) do
			if child.Name == "Dot" then
				table.insert(dots, child)
			end
		end
		expect(#dots).toBe(3)
		-- The rest of the screen's budget still moves beside it.
		local others = {}
		for _ = 1, ThemeConfig.Budget.MaxIdleLoops - 1 do
			local frame = Engine.instance("Frame", screen)
			frame.BackgroundTransparency = 0
			Motion.loop(frame, { BackgroundTransparency = 0 }, { BackgroundTransparency = 1 }, "Ui")
			table.insert(others, frame)
		end
		local moved: { [any]: boolean } = {}
		local last: { [any]: any } = {}
		local watched = table.clone(dots)
		for _, frame in ipairs(others) do
			table.insert(watched, frame)
		end
		for _, part in ipairs(watched) do
			last[part] = if part.Name == "Dot" then part.Position else part.BackgroundTransparency
		end
		for _ = 1, 120 do
			world:frames(1)
			for _, part in ipairs(watched) do
				local now = if part.Name == "Dot" then part.Position else part.BackgroundTransparency
				if now ~= last[part] then
					moved[part] = true
				end
				last[part] = now
			end
		end
		for _, part in ipairs(watched) do
			expect(moved[part]).toBe(true)
		end
		expect(#world.warnings).toBe(0)
	end)
end)

return nil
