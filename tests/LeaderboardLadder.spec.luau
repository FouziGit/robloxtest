--!strict
-- The ladder of ranks, run (tests/engine.luau): the real LeaderboardScreen and Standings.
--
-- The board shows the whole ladder at once -- Vierge, Esquisse, Écriture, Enluminure, Codex -- each seal over
-- its word, so a player sees where their rank stands and what the next one looks like. The game showed only
-- the tiers the board's rows happened to hold.
--
-- Read from Theme.rank: a rim is expected exactly where a rank has one and a shine exactly where it shimmers.
local Engine = require("./engine")
local Harness = require("./harness")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ME = 42

-- The Leaderboard in French on a desktop, over a board of twenty, the player twelfth on `mine`.
local function open(mine: string): (any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	world.player.UserId = ME
	local Screen = world.require("src/ui/screens/LeaderboardScreen")
	local entries = {}
	for rank = 1, 20 do
		table.insert(entries, {
			Rank = rank,
			UserId = if rank == 12 then ME else 1000 + rank,
			Name = "Player" .. rank,
			Rating = 2000 - rank,
			RankKey = if rank == 12 then mine else "",
		})
	end
	local screen = Screen.new({
		Localize = {
			t = function(key: string, params: any?): string
				return Strings.t(key, params, "fr")
			end,
		},
		ClientData = {
			get = function(): any
				return { Rank = { Modes = {} } }
			end,
			Changed = Engine.signal(),
		},
		RemoteClient = {
			fire = function() end,
			invoke = function(): (boolean, any)
				return true, { Entries = entries }
			end,
		},
		SoundController = { play = function() end },
		OnClose = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	return screen, world, world.require("src/ui/Theme")
end

-- The GuiObjects directly under `frame`, in their layout's order.
local function placed(frame: any): { any }
	local found = {}
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(found, child)
		end
	end
	table.sort(found, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return found
end

describe("the ladder of ranks, run", function()
	it("heads the board with every rank, first to last, each seal over its word", function()
		local screen, _world, Theme = open("rank.codex")
		local ladder = screen.Instance:FindFirstChild("Ladder", true)
		assert(ladder ~= nil, "the leaderboard has no ladder")
		local rungs = placed(ladder)
		expect(#rungs).toBe(#RankingConfig.Tiers)
		for index, tier in ipairs(RankingConfig.Tiers) do
			local rung = rungs[index]
			expect(rung.Name).toBe(tier.Id)
			local rank = Theme.rank(tier.Id)
			local parts = placed(rung)
			expect(#parts).toBe(2)
			local seal, word = parts[1], parts[2]
			-- The seal: 58, the rank's fill in a 3-unit ink outline, its initial in the heavy roman.
			expect(seal.Size.X.Offset).toBe(58)
			expect(seal.BackgroundColor3).toBe(rank.Fill)
			local outline = seal:FindFirstChildOfClass("UIStroke")
			expect(outline.Color).toBe(Theme.Colors.Accent)
			expect(outline.Thickness).toBe(3)
			local letter = seal:FindFirstChild("Text")
			expect(letter.Text).toBe((ThemeConfig.dropCap(Strings.t(tier.NameKey, nil, "fr"))))
			expect(letter.FontFace).toBe(Theme.Fonts.Initial)
			expect(letter.TextSize).toBe(24)
			expect(letter.TextColor3).toBe(rank.Ink)
			-- Rims exactly where the rank has one, gold leaf exactly where it shimmers.
			local rings = 0
			for _, child in ipairs(seal:GetChildren()) do
				if child:IsA("Frame") and child:FindFirstChildOfClass("UIStroke") ~= nil then
					rings += 1
				end
			end
			expect(rings).toBe(if rank.Rim ~= nil then 2 else 0)
			expect(seal:FindFirstChild("Shine") ~= nil).toBe(rank.Shimmer)
			-- The word, in the bold face at 14, in ink.
			expect(word.Text).toBe(Strings.t(tier.NameKey, nil, "fr"))
			expect(word.FontFace).toBe(Theme.Fonts.Bold)
			expect(word.TextSize).toBe(14)
			expect(word.TextColor3).toBe(Theme.Colors.Text)
			local stack = rung:FindFirstChildOfClass("UIListLayout")
			expect(stack.FillDirection.Name).toBe("Vertical")
			expect(stack.HorizontalAlignment.Name).toBe("Center")
			expect(stack.Padding.Offset).toBe(8)
		end
		-- Side by side, centred, standing on one line, 22 apart.
		local layout = ladder:FindFirstChildOfClass("UIListLayout")
		expect(layout.FillDirection.Name).toBe("Horizontal")
		expect(layout.HorizontalAlignment.Name).toBe("Center")
		expect(layout.VerticalAlignment.Name).toBe("Bottom")
		expect(layout.Padding.Offset).toBe(22)
		-- Room for the rims above the seals.
		expect(ladder:FindFirstChildOfClass("UIPadding").PaddingTop.Offset).toBeGreaterThanOrEqual(6)
	end)

	it("scrolls first in the board, under the header, and outlives every board shown", function()
		local screen, world = open("rank.blank")
		local ladder = screen.Instance:FindFirstChild("Ladder", true)
		local content = ladder.Parent
		expect(content.ClassName).toBe("ScrollingFrame")
		expect(screen.Instance:FindFirstChild("Header", true):FindFirstChild("Ladder", true)).toBeNil()
		-- First: everything else the board lists comes after it.
		local order = placed(content)
		expect(order[1]).toBe(ladder)
		expect(ladder.LayoutOrder).toBe(0)
		for index = 2, #order do
			expect(order[index].LayoutOrder).toBeGreaterThan(0)
		end
		-- Another board is drawn under the same ladder.
		local tab = screen.Instance:FindFirstChild("Duel1v1", true)
		tab.Activated:Fire()
		world:advance(0.5)
		expect(screen.Instance:FindFirstChild("Ladder", true)).toBe(ladder)
		expect(Engine.destroyed(ladder)).toBe(false)
		screen:Destroy()
		expect(Engine.destroyed(ladder)).toBe(true)
	end)

	it("keeps the screen's gold leaf within the gradients a screen may sweep", function()
		for _, tier in ipairs(RankingConfig.Tiers) do
			local screen = open(tier.NameKey)
			local shines = 0
			for _, part in ipairs(screen.Instance:GetDescendants()) do
				if part.Name == "Shine" then
					shines += 1
				end
			end
			expect(shines).toBeLessThanOrEqual(ThemeConfig.Budget.MaxAnimatedGradients)
		end
	end)

	it("marks the player's rank in their standing with a pip", function()
		local screen, _world, Theme = open("rank.illumination")
		local standing = screen.Instance:FindFirstChild("Standing", true)
		expect(standing:FindFirstChild("Tier").Text).toBe(
			Theme.Glyphs.Pip .. " " .. Strings.t("rank.illumination", nil, "fr")
		)
	end)
end)

return nil
