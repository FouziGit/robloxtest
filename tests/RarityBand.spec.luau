--!strict
-- The rarity band, run (tests/engine.luau): the real RarityBand, Pips and Theme.
--
-- The board heads each item card with a band in the rarity's colour, its word on the left and its pips on the
-- right, over a rule of ink, inside the card's own outline. A pill in the corner of a preview said the same
-- thing smaller, over the picture it was about.
local Engine = require("./engine")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function bench(): (any, any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local RarityBand = world.require("src/ui/components/RarityBand")
	local Theme = world.require("src/ui/Theme")
	local face = Engine.instance("Frame", Engine.instance("ScreenGui", world.game))
	return world, RarityBand, Theme, face
end

-- The pips a band shows, in order.
local function pipsOf(band: any): { any }
	local row = band.Instance:FindFirstChild("Pips", true)
	assert(row ~= nil, "the band shows no pips")
	local found = {}
	for _, pip in ipairs(row:GetChildren()) do
		if pip:IsA("TextLabel") then
			table.insert(found, pip)
		end
	end
	table.sort(found, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return found
end

describe("a rarity band, run", function()
	it("says each rarity in its colour, its word and its pips, over a rule of ink", function()
		local _world, RarityBand, Theme, face = bench()
		local count = 0
		for rarity, def in pairs(ThemeConfig.Rarity) do
			count += 1
			local look = Theme.rarity(rarity)
			local band = RarityBand.new({ Rarity = rarity, Word = "word." .. rarity, Parent = face })
			local fill = band.Instance:FindFirstChild("Fill")
			expect(fill.BackgroundColor3).toBe(Theme.color(def.Fill))
			expect(fill:FindFirstChild("Square").BackgroundColor3).toBe(look.Fill)
			local word = band.Instance:FindFirstChild("Word", true)
			expect(word.Text).toBe("word." .. rarity)
			expect(word.TextColor3).toBe(Theme.color(ThemeConfig.labelRole(def.Fill)))
			expect(word.FontFace).toBe(Theme.Fonts.Label)
			expect(word.TextSize).toBe(14)
			expect(word.TextXAlignment.Name).toBe("Left")
			-- As many pips as the rarity has, all in its ink.
			local pips = pipsOf(band)
			expect(#pips).toBe(def.Pips)
			for _, pip in ipairs(pips) do
				expect(pip.TextColor3).toBe(look.Ink)
				expect(pip.TextSize).toBe(14)
			end
			-- The word first, the pips last, pushed apart by what fills the row between them.
			local content = word.Parent
			local spacer = content:FindFirstChild("Spacer")
			expect(spacer:FindFirstChildOfClass("UIFlexItem").FlexMode.Name).toBe("Fill")
			expect(word.LayoutOrder).toBeLessThan(spacer.LayoutOrder)
			expect(spacer.LayoutOrder).toBeLessThan(pips[1].Parent.LayoutOrder)
			-- The rule of ink under the colour, a stroke thick, the band's whole width.
			local rule = band.Instance:FindFirstChild("Rule")
			expect(rule.BackgroundColor3).toBe(Theme.Colors.Accent)
			expect(rule.Size.Y.Offset).toBe(Theme.Sizes.Stroke)
			expect(rule.Size.X.Scale).toBe(1)
			expect(rule.Position.Y.Offset).toBe(fill.Size.Y.Offset)
			band:Destroy()
			expect(face:FindFirstChild("RarityBand")).toBeNil()
		end
		expect(count).toBe(4)
	end)

	it("sits inside the card's outline, its top corners on the outline's inner curve", function()
		local _world, RarityBand, Theme, face = bench()
		local stroke = Theme.Sizes.Stroke
		local band = RarityBand.new({ Rarity = "Rare", Word = "Rare", Parent = face })
		expect(band.Instance.Parent).toBe(face)
		expect(band.Instance.Position.X.Offset).toBe(stroke)
		expect(band.Instance.Position.Y.Offset).toBe(stroke)
		expect(band.Instance.Size.X.Scale).toBe(1)
		expect(band.Instance.Size.X.Offset).toBe(-stroke * 2)
		local fill = band.Instance:FindFirstChild("Fill")
		local round = fill:FindFirstChildOfClass("UICorner").CornerRadius
		expect(round.Scale).toBe(0)
		expect(round.Offset).toBe(Theme.Sizes.CornerCard - stroke)
		-- Square at the bottom, on the rule.
		local square = fill:FindFirstChild("Square")
		expect(square.Position.Y.Scale).toBe(1)
		expect(square.Position.Y.Offset).toBe(-round.Offset)
		expect(square.Size.Y.Offset).toBe(round.Offset)
		-- A thinner outline, a band inset by it.
		local thin = RarityBand.new({ Rarity = "Rare", Word = "Rare", Parent = face, Inset = Theme.Sizes.StrokeThin })
		expect(thin.Instance.Position.Y.Offset).toBe(Theme.Sizes.StrokeThin)
		expect(thin.Bottom).toBe(Theme.Sizes.StrokeThin + thin.Height)
	end)

	it("is 37 and 3 with a pointer, 22 and 3 compact, 13 and 3 without its word", function()
		local _world, RarityBand, Theme, face = bench()
		local stroke = Theme.Sizes.Stroke
		local cases = {
			{ Compact = false, ShowWord = true, Fill = 37, Pips = 14 },
			{ Compact = true, ShowWord = true, Fill = 22, Pips = 14 },
			{ Compact = true, ShowWord = false, Fill = 13, Pips = 12 },
		}
		for _, case in ipairs(cases) do
			local band = RarityBand.new({
				Rarity = "Legendary",
				Word = "Legendary",
				Parent = face,
				Compact = case.Compact,
				ShowWord = case.ShowWord,
			})
			local label = ("compact %s, word %s"):format(tostring(case.Compact), tostring(case.ShowWord))
			local fill = band.Instance:FindFirstChild("Fill")
			if fill.Size.Y.Offset ~= case.Fill then
				error(("%s: a fill of %d"):format(label, fill.Size.Y.Offset))
			end
			expect(band.Height).toBe(case.Fill + stroke)
			expect(band.Instance.Size.Y.Offset).toBe(band.Height)
			expect(RarityBand.height(case.Compact, case.ShowWord)).toBe(band.Height)
			expect(band.Bottom).toBe(stroke + band.Height)
			expect(RarityBand.bottom(case.Compact, case.ShowWord)).toBe(band.Bottom)
			expect(band.Instance:FindFirstChild("Word", true) ~= nil).toBe(case.ShowWord)
			for _, pip in ipairs(pipsOf(band)) do
				expect(pip.TextSize).toBe(case.Pips)
			end
		end
	end)

	it("wears no seal ring and no shine, even Legendary", function()
		local _world, RarityBand, _Theme, face = bench()
		local band = RarityBand.new({ Rarity = "Legendary", Word = "Legendary", Parent = face })
		for _, part in ipairs(band.Instance:GetDescendants()) do
			if
				part:IsA("ImageLabel")
				or part.ClassName == "UIGradient"
				or part.Name == "Seal"
				or part.Name == "Shine"
			then
				error(("the band draws %s (%s)"):format(part.Name, part.ClassName))
			end
		end
		expect(face:FindFirstChild("Shine")).toBeNil()
	end)
end)

describe("pips, run", function()
	it("are 12 unless told otherwise", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Pips = world.require("src/ui/components/Pips")
		for _, pip in ipairs(Pips.new(2, 4).Instance:GetChildren()) do
			if pip:IsA("TextLabel") then
				expect(pip.TextSize).toBe(12)
			end
		end
		for _, pip in ipairs(Pips.new(2, 4, nil, 20).Instance:GetChildren()) do
			if pip:IsA("TextLabel") then
				expect(pip.TextSize).toBe(20)
			end
		end
	end)
end)

return nil
