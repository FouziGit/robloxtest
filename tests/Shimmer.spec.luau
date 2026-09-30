--!strict
-- The shimmer, run (tests/engine.luau): the real Shimmer, Motion, Theme and Trove.
--
-- A screen the player closes is disabled, not destroyed (ScreenRoot), so what a shine is laid on stays in the
-- DataModel. The shimmer only asked for the DataModel, and swept every ShimmerPauseSeconds for the rest of the
-- session on the Shop's Legendary card and the Daily's seventh day, keeping the Heartbeat awake for nobody.
-- It was RarityRibbon's until the card and the seals needed it too; these cases moved with it.
local Engine = require("./engine")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CORNER = roblox.UDim.new(0.5, 0)
local ZINDEX = 7

-- A shine laid on a frame that is then put on a screen, as a ribbon puts its pill.
local function setup(prefs: { [string]: any }?)
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(prefs),
	})
	local Shimmer = world.require("src/ui/components/Shimmer")
	local screen = Engine.instance("ScreenGui", world.game)
	local host = Engine.instance("Frame")
	local shimmer = Shimmer.new(host, CORNER, ZINDEX)
	host.Parent = Engine.instance("Frame", screen)
	local gradient = if shimmer.Instance ~= nil then shimmer.Instance:FindFirstChildOfClass("UIGradient") else nil
	return world, screen, shimmer, gradient, host
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
		local world, _screen, _shimmer, gradient = setup()
		expect(gradient).never.toBeNil()
		expect(moving(world, gradient, 8)).toBeGreaterThan(30)
	end)

	it("stops on a closed screen and starts again when it opens", function()
		local world, screen, _shimmer, gradient = setup()
		world:advance(1)
		screen.Enabled = false
		-- The sweep in flight lands and the pause runs out; after that nothing moves.
		world:advance(5)
		expect(moving(world, gradient, 12)).toBe(0)
		expect(world.Heartbeat:count()).toBe(0)
		screen.Enabled = true
		expect(moving(world, gradient, 2)).toBeGreaterThan(10)
	end)

	it("follows what it is laid on to another screen", function()
		local world, screen, _shimmer, gradient, host = setup()
		local other = Engine.instance("ScreenGui", world.game)
		other.Enabled = false
		host.Parent = other
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
		local world, screen, shimmer, gradient = setup()
		world:advance(1)
		shimmer:Destroy()
		screen.Enabled = false
		screen.Enabled = true
		world:advance(8)
		expect(world.Heartbeat:count()).toBe(0)
		expect(gradient.Parent).toBeNil()
	end)

	it("lets go of its screen when what it is laid on is destroyed without it", function()
		local world, screen, _shimmer, gradient, host = setup()
		world:advance(1)
		local enabled = screen:GetPropertyChangedSignal("Enabled")
		expect(enabled:count()).toBe(1)
		host:Destroy()
		expect(enabled:count()).toBe(0)
		world:advance(5)
		expect(world.Heartbeat:count()).toBe(0)
		expect(gradient.Parent).toBeNil()
	end)

	it("sweeps on what is already on an open screen when it is laid there", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Shimmer = world.require("src/ui/components/Shimmer")
		local screen = Engine.instance("ScreenGui", world.game)
		local card = Engine.instance("Frame", screen)
		local shimmer = Shimmer.new(card, CORNER, ZINDEX)
		local gradient = shimmer.Instance:FindFirstChildOfClass("UIGradient")
		expect(moving(world, gradient, 2)).toBeGreaterThan(10)
		-- And it still hears its screen close.
		world:advance(1)
		screen.Enabled = false
		world:advance(5)
		expect(moving(world, gradient, 8)).toBe(0)
	end)
end)

describe("the shine, run", function()
	it("covers what it is laid on, above it, rounded as it is, and takes no input", function()
		local _world, _screen, shimmer, gradient, host = setup()
		local shine = shimmer.Instance
		expect(shine.Name).toBe("Shine")
		expect(shine.Parent).toBe(host)
		expect(shine.Size).toBe(roblox.UDim2.fromScale(1, 1))
		expect(shine.ZIndex).toBe(ZINDEX)
		expect(shine:FindFirstChildOfClass("UICorner").CornerRadius).toBe(CORNER)
		-- The buttons under a card's shine still take the clicks.
		expect(shine.Active).toBe(false)
		expect(shine.Interactable).toBe(false)
		expect(gradient.Rotation).toBe(ThemeConfig.Gradients.Shimmer.Rotation)
	end)

	for _, pref in ipairs({ "reducedMotion", "lowQuality" }) do
		it(("is not laid at all for a player who asked for %s"):format(pref), function()
			local _world, _screen, shimmer, _gradient, host = setup({ [pref] = true })
			expect(shimmer.Instance).toBeNil()
			expect(host:FindFirstChild("Shine")).toBeNil()
			shimmer:Destroy()
		end)
	end
end)

describe("the shimmers of a screen, run", function()
	it("sweep the screen's budget of them, and hold the next one still", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Shimmer = world.require("src/ui/components/Shimmer")
		local screen = Engine.instance("ScreenGui", world.playerGui)
		local budget = ThemeConfig.Budget.MaxAnimatedGradients
		local gradients = {}
		for _ = 1, budget + 1 do
			local host = Engine.instance("Frame")
			local shimmer = Shimmer.new(host, CORNER, ZINDEX)
			host.Parent = Engine.instance("Frame", screen)
			table.insert(gradients, shimmer.Instance:FindFirstChildOfClass("UIGradient"))
		end
		-- Watched together, over one sweep.
		local moved: { [number]: boolean } = {}
		local last = {}
		for index, gradient in ipairs(gradients) do
			last[index] = gradient.Offset
		end
		for _ = 1, 60 do
			world:frames(1)
			for index, gradient in ipairs(gradients) do
				if gradient.Offset ~= last[index] then
					moved[index] = true
				end
				last[index] = gradient.Offset
			end
		end
		local swept = 0
		for _ in pairs(moved) do
			swept += 1
		end
		expect(swept).toBe(budget)
		-- Another screen has its own.
		local other = Engine.instance("ScreenGui", world.playerGui)
		local host = Engine.instance("Frame")
		local shimmer = Shimmer.new(host, CORNER, ZINDEX)
		host.Parent = Engine.instance("Frame", other)
		expect(moving(world, shimmer.Instance:FindFirstChildOfClass("UIGradient"), 1)).toBeGreaterThan(0)
	end)
end)

return nil
