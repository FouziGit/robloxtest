--!strict
-- The rarity ribbon, run (tests/engine.luau): the real RarityRibbon, Shimmer, Theme and Trove.
--
-- The sweep itself, its screen and its budget are Shimmer's (tests/Shimmer.spec.luau); the ribbon only lays it
-- over its pill, and only for a rarity that shimmers.
local Engine = require("./engine")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("a rarity ribbon, run", function()
	it("lays the shimmer over its pill exactly where its rarity shimmers", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local RarityRibbon = world.require("src/ui/components/RarityRibbon")
		local screen = Engine.instance("ScreenGui", world.game)
		local shimmering = 0
		for rarity, def in pairs(ThemeConfig.Rarity) do
			local ribbon = RarityRibbon.new(rarity, rarity, Engine.instance("Frame", screen))
			local shine = ribbon.Instance:FindFirstChild("Shine")
			if def.Shimmer == true then
				shimmering += 1
				assert(shine ~= nil, rarity .. " shimmers and its ribbon has no shine")
				-- Over the whole pill and its words, inside its ink outline, rounded as the pill is.
				local outline = ribbon.Instance:FindFirstChildOfClass("UIStroke").Thickness
				expect(shine.Size.X.Scale).toBe(1)
				expect(shine.Size.Y.Scale).toBe(1)
				expect(shine.Size.Y.Offset).toBe(-outline * 2)
				expect(shine.Position.Y.Offset).toBe(outline)
				expect(shine.ZIndex).toBeGreaterThan(ribbon.Instance:FindFirstChild("Content").ZIndex)
				expect(shine:FindFirstChildOfClass("UICorner").CornerRadius.Scale).toBe(0.5)
				local gradient = shine:FindFirstChildOfClass("UIGradient")
				local start = gradient.Offset
				world:advance(0.5)
				expect(gradient.Offset ~= start).toBe(true)
			else
				expect(shine).toBeNil()
			end
			ribbon:Destroy()
		end
		expect(shimmering).toBeGreaterThan(0)
	end)

	it("wears no ring beside its word, even Legendary", function()
		-- Seen in Studio: the Legendary's seal ring, the blurred ring the spells draw, read as a Folio coin beside
		-- the item's name on the purchase sheet and the week's seventh day.
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local RarityRibbon = world.require("src/ui/components/RarityRibbon")
		local screen = Engine.instance("ScreenGui", world.game)
		for rarity in pairs(ThemeConfig.Rarity) do
			local ribbon = RarityRibbon.new(rarity, rarity, Engine.instance("Frame", screen))
			for _, part in ipairs(ribbon.Instance:GetDescendants()) do
				if part:IsA("ImageLabel") then
					error(("the %s ribbon draws an image, %s"):format(rarity, part.Name))
				end
			end
			ribbon:Destroy()
		end
	end)
end)

return nil
