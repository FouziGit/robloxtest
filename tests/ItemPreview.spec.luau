--!strict
-- An item's preview, run (tests/engine.luau): the real ItemPreview and Theme.
--
-- The board draws an item's colour as a blot on the page's vellum -- a little wider than tall, tipped, in its
-- ink outline -- where the game drew a round swatch, which read as a coin beside the Folios coin. A title
-- stays its own words on a scrap of paper.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function bench(): (any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local ItemPreview = world.require("src/ui/components/ItemPreview")
	local Theme = world.require("src/ui/Theme")
	local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.game))
	return ItemPreview, Theme, parent
end

local localize = {
	t = function(key: string): string
		return key
	end,
}

describe("an item's preview, run", function()
	it("draws a colour as a tipped blot in its ink outline, three fifths of the height it is given", function()
		local ItemPreview, Theme, parent = bench()
		local drawn = 0
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Slot == "Title" then
				continue
			end
			drawn += 1
			local blot = ItemPreview.new(item, parent, localize)
			expect(blot.Name).toBe("Swatch")
			expect(blot.Parent).toBe(parent)
			expect(blot.BackgroundColor3).toBe(ItemPreview.color(item))
			-- As wide as it may be and 0.58 of the height, its own shape fitted inside: 8 wide for 7 tall.
			expect(blot.Size.X.Scale).toBe(1)
			expect(blot.Size.Y.Scale).toBeCloseTo(0.58, 5)
			local shape = blot:FindFirstChildOfClass("UIAspectRatioConstraint")
			expect(shape.AspectRatio).toBeCloseTo(8 / 7, 6)
			expect(shape.AspectType.Name).toBe("FitWithinMaxSize")
			expect(blot.AnchorPoint.X).toBe(0.5)
			expect(blot.Position.Y.Scale).toBe(0.5)
			expect(blot.Rotation).toBe(-6)
			expect(blot:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
			local stroke = blot:FindFirstChildOfClass("UIStroke")
			expect(stroke.Color).toBe(Theme.Colors.Accent)
			expect(stroke.Thickness).toBe(Theme.Sizes.Stroke)
			blot:Destroy()
		end
		expect(drawn).toBeGreaterThan(5)
	end)

	it("keeps a title on its scrap of paper, never a blot", function()
		local ItemPreview, _Theme, parent = bench()
		local titles = 0
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Slot ~= "Title" or item.Look.TextKey == nil then
				continue
			end
			titles += 1
			local scrap = ItemPreview.new(item, parent, localize)
			expect(scrap.Name).toBe("Scrap")
			expect(scrap.Rotation).toBe(0)
			expect(scrap:FindFirstChild("Title").Text).toBe(item.Look.TextKey)
			expect(parent:FindFirstChild("Swatch")).toBeNil()
			scrap:Destroy()
		end
		expect(titles).toBeGreaterThan(0)
	end)
end)

return nil
