--!strict
-- The splat pool, run (tests/engine.luau): the real Splat, Burst, Motion and Theme.
--
-- A burst hands its splats back 0.6 s after it plays. A sheet that closes in that time destroys them with
-- it, and a destroyed splat handed back to the pool used to be the next one Splat.new took: its Parent is
-- locked, so the next purchase's burst threw inside the handler that was about to close the sheet.
local Engine = require("./engine")
local Harness = require("./harness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function setup()
	local world = Engine.world({
		Stubs = {
			["src/ui/UiPrefs"] = {
				reducedMotion = function(): boolean
					return false
				end,
			},
			["src/ui/UiSound"] = { play = function(_id: string) end },
		},
	})
	local Splat = world.require("src/ui/components/Splat")
	local Burst = world.require("src/ui/components/Burst")
	local Theme = world.require("src/ui/Theme")
	local screen = Engine.instance("ScreenGui", world.game)
	return world, Splat, Burst, Theme, screen
end

local function props(Theme: any, parent: any): any
	return {
		Size = roblox.UDim2.fromScale(1, 1),
		Tint = Theme.Colors.Primary,
		Parent = parent,
	}
end

describe("Splat's pool, run", function()
	it("never hands out a splat that was destroyed before it came back", function()
		local world, Splat, Burst, Theme, screen = setup()
		local sheet = Engine.instance("Frame", screen)
		local swatch = Engine.instance("Frame", sheet)
		Burst.play(swatch, { Theme.Colors.Primary, Theme.Colors.Epic, Theme.Colors.Info })
		local burst = {}
		for _, child in ipairs(swatch:GetChildren()) do
			if child.Name == "Burst" then
				table.insert(burst, child)
			end
		end
		expect(#burst).toBe(3)
		-- The sheet closes before the burst hands its splats back.
		world:advance(0.3)
		sheet:Destroy()
		world:advance(0.5)
		-- The next purchase's burst, and a list's empty state, on the same screen.
		local shelf = Engine.instance("Frame", screen)
		for _ = 1, 3 do
			local splat = Splat.new(props(Theme, shelf))
			expect(splat).never.toBeNil()
			expect(Engine.destroyed(splat)).toBe(false)
			expect(splat.Parent).toBe(shelf)
		end
	end)

	it("still reuses a splat that came back alive", function()
		local world, Splat, _Burst, Theme, screen = setup()
		local first = Splat.new(props(Theme, screen))
		Splat.release(first)
		world:frames(1)
		local second = Splat.new(props(Theme, screen))
		expect(second).toBe(first)
		expect(second.Visible).toBe(true)
	end)

	it("counts a destroyed splat out of the screen's budget", function()
		local _world, Splat, _Burst, Theme, screen = setup()
		local holder = Engine.instance("Frame", screen)
		for _ = 1, Theme.Budget.MaxSplats do
			expect(Splat.new(props(Theme, holder))).never.toBeNil()
		end
		expect(Splat.new(props(Theme, screen))).toBeNil()
		holder:Destroy()
		expect(Splat.new(props(Theme, screen))).never.toBeNil()
	end)
end)

return nil
