--!strict
-- The interface's scale and its smallest text (D-128). In a Studio window 700 points tall the whole
-- interface was scaled to 0.62 and body text drawn at nine points: the developer could read neither a
-- menu nor a board, and did not find the screens at all. The scale is pure data (ThemeConfig), held
-- here without an engine.
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local THEME = "src/ui/Theme.luau"

local function stripComments(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- A base size from src/ui/Theme.luau, which needs an engine to require.
local function baseSize(name: string): number
	local source = stripComments(fs.readFile(THEME))
	local value = source:match("\t" .. name .. " = (%d+),")
	if value == nil then
		error(("Theme.Sizes.%s is not a number in %s: this gate would check nothing"):format(name, THEME))
	end
	return tonumber(value) :: number
end

-- Viewport heights, in points: phones in landscape, laptop and Studio windows, monitors up to 4K.
local HEIGHTS = { 320, 375, 414, 499, 500, 600, 650, 700, 720, 800, 900, 1000, 1080, 1200, 1440, 2160, 2880 }

describe("the interface's scale", function()
	it("never shrinks as the viewport grows, on any device", function()
		for _, touchOnly in ipairs({ false, true }) do
			local previous = 0
			for height = 200, 3200, 10 do
				local scale = ThemeConfig.scaleFor(height, touchOnly)
				if scale < previous then
					error(
						("a %d-point viewport is drawn smaller than a shorter one (%.3f < %.3f)"):format(
							height,
							scale,
							previous
						)
					)
				end
				previous = scale
			end
		end
	end)

	it("never draws a mouse or gamepad interface smaller than designed", function()
		for _, height in ipairs(HEIGHTS) do
			expect(ThemeConfig.scaleFor(height, false) >= 1).toBe(true)
		end
		-- And grows with a tall screen, up to its ceiling.
		expect(ThemeConfig.scaleFor(1440, false) > 1.3).toBe(true)
		expect(ThemeConfig.scaleFor(5000, false)).toBe(ThemeConfig.Scale.Max)
	end)

	it("keeps a phone at the floor its layouts are measured at", function()
		for _, height in ipairs(HEIGHTS) do
			expect(ThemeConfig.scaleFor(height, true) >= ThemeConfig.Scale.TouchFloor).toBe(true)
		end
		expect(ThemeConfig.scaleFor(375, true)).toBe(ThemeConfig.Scale.TouchFloor)
	end)

	it("is the one scale the runtime applies", function()
		local source = stripComments(fs.readFile(THEME))
		expect(source:find("return ThemeConfig.scaleFor(viewportSize.Y, touchOnly())", 1, true)).never.toBe(nil)
		expect(source:find("MinScale", 1, true)).toBe(nil)
		expect(source:find("MaxScale", 1, true)).toBe(nil)
	end)
end)

describe("the smallest text", function()
	it("reads at a readable size on a desktop, whatever the window", function()
		-- Points as drawn: the base size times the smallest scale a mouse or gamepad player gets.
		local floor = ThemeConfig.Scale.PointerFloor
		expect(baseSize("TextSmall") * floor >= 14).toBe(true)
		expect(baseSize("TextBody") * floor >= 16).toBe(true)
	end)

	it("stays legible on a phone", function()
		local floor = ThemeConfig.Scale.TouchFloor
		expect(baseSize("TextSmall") * floor >= 9).toBe(true)
		expect(baseSize("TextBody") * floor >= 10.5).toBe(true)
	end)
end)
