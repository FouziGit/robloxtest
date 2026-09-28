--!strict
-- The Legendary ribbon's shimmer, run (tests/engine.luau): the real RarityRibbon, Motion, Theme and Trove.
--
-- A screen the player closes is disabled, not destroyed (ScreenRoot), so a ribbon on it stays in the
-- DataModel. The shimmer only asked for the DataModel, and swept every ShimmerPauseSeconds for the rest of
-- the session on the Shop's Legendary card and the Daily's seventh day, keeping the Heartbeat awake for
-- nobody.
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function setup()
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
	})
	local RarityRibbon = world.require("src/ui/components/RarityRibbon")
	local screen = Engine.instance("ScreenGui", world.game)
	local card = Engine.instance("Frame", screen)
	local ribbon = RarityRibbon.new("Legendary", "Legendary", card)
	local gradient = ribbon.Instance:FindFirstChild("Shine"):FindFirstChildOfClass("UIGradient")
	return world, screen, ribbon, gradient
end

-- How many frames of `seconds` moved the gradient.
local function moving(world: any, gradient: any, seconds: number): number
	local count = 0
	local last = gradient.Offset
	for _ = 1, math.floor(seconds * 60) do
		world:frames(1)
		if gradient.Offset ~= last then
			count += 1
			last = gradient.Offset
		end
	end
	return count
end

describe("the shimmer, run", function()
	it("sweeps while its screen is open", function()
		local world, _screen, _ribbon, gradient = setup()
		expect(gradient).never.toBeNil()
		expect(moving(world, gradient, 8)).toBeGreaterThan(30)
	end)

	it("stops on a closed screen and starts again when it opens", function()
		local world, screen, _ribbon, gradient = setup()
		world:advance(1)
		screen.Enabled = false
		-- The sweep in flight lands and the pause runs out; after that nothing moves.
		world:advance(5)
		expect(moving(world, gradient, 12)).toBe(0)
		expect(world.Heartbeat:count()).toBe(0)
		screen.Enabled = true
		expect(moving(world, gradient, 2)).toBeGreaterThan(10)
	end)

	it("follows the ribbon to another screen", function()
		local world, screen, ribbon, gradient = setup()
		local other = Engine.instance("ScreenGui", world.game)
		other.Enabled = false
		ribbon.Instance.Parent = other
		world:advance(5)
		expect(moving(world, gradient, 8)).toBe(0)
		-- The first screen no longer holds it: opening it wakes nothing.
		screen.Enabled = false
		screen.Enabled = true
		expect(moving(world, gradient, 2)).toBe(0)
		other.Enabled = true
		expect(moving(world, gradient, 2)).toBeGreaterThan(10)
	end)

	it("stops for good once destroyed", function()
		local world, screen, ribbon, gradient = setup()
		world:advance(1)
		ribbon:Destroy()
		screen.Enabled = false
		screen.Enabled = true
		world:advance(8)
		expect(world.Heartbeat:count()).toBe(0)
		expect(gradient.Parent).toBeNil()
	end)
end)

return nil
