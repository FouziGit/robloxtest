--!strict
-- The seal, run (tests/engine.luau): the real Seal, Shimmer and Theme.
--
-- The board draws a rank as a flat disc in a 3-unit ink outline, its initial in the heavy roman at 24 on 58,
-- and the higher ranks with crisp rings around it: the rim's colour, then ink. The game ringed every seal with
-- the SealRing texture the casts draw in the air, a soft brush ring standing off the wax, and scaled its text
-- into the disc.
local Engine = require("./engine")
local Harness = require("./harness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function bench(): (any, any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Seal = world.require("src/ui/components/Seal")
	local Theme = world.require("src/ui/Theme")
	local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
	return world, Seal, Theme, parent
end

-- The rings of a seal's rim, from the inside out.
local function rings(seal: any): { any }
	local found = {}
	for _, child in ipairs(seal.Instance:GetChildren()) do
		if child:IsA("Frame") and child:FindFirstChildOfClass("UIStroke") ~= nil then
			table.insert(found, child)
		end
	end
	table.sort(found, function(a: any, b: any): boolean
		return a.Size.X.Offset < b.Size.X.Offset
	end)
	return found
end

describe("a seal, run", function()
	it("is a flat disc in its ink outline, thin under a thumb's size, with no ring drawn from a texture", function()
		local _world, Seal, Theme, parent = bench()
		for _, case in ipairs({ { Size = 58, Stroke = 3 }, { Size = 32, Stroke = 3 }, { Size = 24, Stroke = 2 } }) do
			local seal = Seal.new({ Text = "", Fill = Theme.Colors.Chalk, Size = case.Size, Parent = parent })
			local disc = seal.Instance
			expect(disc.Size).toBe(roblox.UDim2.fromOffset(case.Size, case.Size))
			expect(disc.BackgroundColor3).toBe(Theme.Colors.Chalk)
			expect(disc:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
			local outline = disc:FindFirstChildOfClass("UIStroke")
			expect(outline.Color).toBe(Theme.Colors.Accent)
			expect(outline.Thickness).toBe(case.Stroke)
			expect(outline.BorderStrokePosition.Name).toBe("Inner")
			for _, part in ipairs(disc:GetDescendants()) do
				expect(part:IsA("ImageLabel")).toBe(false)
			end
			expect(#rings(seal)).toBe(0)
			seal:Destroy()
		end
	end)

	it("wears a rim as two crisp rings around its outline: the rim's colour, then ink", function()
		local _world, Seal, Theme, parent = bench()
		local seal = Seal.new({
			Text = "E",
			Fill = Theme.Colors.Epic,
			Rim = Theme.Colors.Primary,
			Size = 58,
			Parent = parent,
		})
		local found = rings(seal)
		expect(#found).toBe(2)
		for index, frame in ipairs(found) do
			-- Centred on the disc, a stroke wider each, each stroke on the ring's inside.
			expect(frame.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
			expect(frame.Position).toBe(roblox.UDim2.fromScale(0.5, 0.5))
			expect(frame.Size).toBe(roblox.UDim2.new(1, 6 * index, 1, 6 * index))
			expect(frame.BackgroundTransparency).toBe(1)
			expect(frame:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			expect(stroke.Thickness).toBe(3)
			expect(stroke.BorderStrokePosition.Name).toBe("Inner")
		end
		expect(found[1]:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Primary)
		expect(found[2]:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Accent)
		-- A new fill without a rim takes the rings off; with one puts them back, once.
		seal:SetFill(Theme.Colors.Chalk)
		expect(#rings(seal)).toBe(0)
		seal:SetFill(Theme.Colors.Epic, Theme.Colors.Primary)
		seal:SetFill(Theme.Colors.Epic, Theme.Colors.Bronze)
		found = rings(seal)
		expect(#found).toBe(2)
		expect(found[1]:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Bronze)
	end)

	it("sets an initial in the heavy roman at the board's 24 on 58, whatever its diameter", function()
		local _world, Seal, Theme, parent = bench()
		for _, case in ipairs({
			{ Size = 58, Text = 24 },
			{ Size = 40, Text = 17 },
			{ Size = 48, Text = 20 },
			{ Size = 36, Text = 15 },
		}) do
			local seal = Seal.new({
				Text = "C",
				Fill = Theme.Colors.Primary,
				Size = case.Size,
				Face = "Initial",
				Parent = parent,
			})
			local label = seal.Instance:FindFirstChild("Text")
			expect(label.FontFace).toBe(Theme.Fonts.Initial)
			expect(label.TextSize).toBe(case.Text)
			expect(label.TextScaled == true).toBe(false)
			expect(label.Text).toBe("C")
			seal:Destroy()
		end
		-- The other faces still scale their text into the disc.
		local number =
			Seal.new({ Text = "24", Fill = Theme.Colors.Primary, Size = 56, Face = "Numeric", Parent = parent })
		expect(number.Instance:FindFirstChild("Text").FontFace).toBe(Theme.Fonts.Numeric)
		expect(number.Instance:FindFirstChild("Text").TextScaled).toBe(true)
	end)

	it("writes in charcoal on a light fill and in the sheet on Tyrian and on ink, unless told otherwise", function()
		local _world, Seal, Theme, parent = bench()
		local function ink(fill: any, given: any?): any
			local seal =
				Seal.new({ Text = "E", Fill = fill, Ink = given, Size = 58, Face = "Initial", Parent = parent })
			return seal.Instance:FindFirstChild("Text").TextColor3, seal
		end
		expect((ink(Theme.Colors.Primary))).toBe(Theme.Colors.Text)
		expect((ink(Theme.Colors.Chalk))).toBe(Theme.Colors.Text)
		expect((ink(Theme.Colors.InfoFill))).toBe(Theme.Colors.Text)
		expect((ink(Theme.Colors.Epic))).toBe(Theme.Colors.PanelRaised)
		expect((ink(Theme.Colors.Plate))).toBe(Theme.Colors.PanelRaised)
		expect((ink(Theme.Colors.Bronze))).toBe(Theme.Colors.PanelRaised)
		expect((ink(Theme.Colors.Epic, Theme.Colors.Primary))).toBe(Theme.Colors.Primary)
		-- A new fill takes its ink, or the one it is given.
		local _, seal = ink(Theme.Colors.Chalk)
		seal:SetFill(Theme.Colors.Epic)
		expect(seal.Instance:FindFirstChild("Text").TextColor3).toBe(Theme.Colors.PanelRaised)
		seal:SetFill(Theme.Colors.Epic, nil, Theme.Colors.Text)
		expect(seal.Instance:FindFirstChild("Text").TextColor3).toBe(Theme.Colors.Text)
	end)

	it("shimmers only when asked, and stops when told", function()
		local world, Seal, Theme, parent = bench()
		local plain = Seal.new({ Text = "", Fill = Theme.Colors.Primary, Size = 58, Parent = parent })
		expect(plain.Instance:FindFirstChild("Shine")).toBeNil()
		local gold = Seal.new({ Text = "C", Fill = Theme.Colors.Primary, Size = 58, Shimmer = true, Parent = parent })
		local shine = gold.Instance:FindFirstChild("Shine")
		assert(shine ~= nil, "a shimmering seal has no shine")
		-- Over the disc and its letter.
		expect(shine.ZIndex).toBeGreaterThan(gold.Instance:FindFirstChild("Text").ZIndex)
		expect(shine:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
		gold:SetShimmer(false)
		expect(gold.Instance:FindFirstChild("Shine")).toBeNil()
		plain:SetShimmer(true)
		expect(plain.Instance:FindFirstChild("Shine")).never.toBeNil()
		plain:Destroy()
		gold:Destroy()
		world:advance(8)
		expect(world.Heartbeat:count()).toBe(0)
	end)

	it("stamps in from a size and a half, its rims and its letter with it", function()
		local world, Seal, Theme, parent = bench()
		local seal = Seal.new({
			Text = "E",
			Fill = Theme.Colors.Epic,
			Rim = Theme.Colors.Primary,
			Size = 48,
			Face = "Initial",
			Stamp = true,
			Parent = parent,
		})
		local scale = seal.Instance:FindFirstChildOfClass("UIScale")
		expect(scale.Scale).toBe(1.5)
		-- One scale on the disc, which holds the rims and the letter.
		for _, frame in ipairs(rings(seal)) do
			expect(frame.Parent).toBe(seal.Instance)
		end
		world:advance(1)
		expect(scale.Scale).toBeCloseTo(1, 2)
	end)
end)

return nil
