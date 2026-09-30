--!strict
-- The rank seals, run (tests/engine.luau): the real Standings, LeaderboardScreen, ResultCard and Seal.
--
-- The board seals each rank with its initial in the heavy roman -- V, E, É, E, C in French -- on the rank's
-- colour, rims round the higher ones and gold leaf shimmering on the last. The game's rank seals were bare
-- discs of colour, 24 across in a row, with nothing to read on them.
--
-- Everything here reads the ladder from Theme.rank: a rim is expected exactly where a rank has one and a
-- shine exactly where a rank shimmers, so these hold whatever ThemeConfig.Ranks gives each rank.
local Engine = require("./engine")
local Harness = require("./harness")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ME = 42

local function localizer(locale: string): any
	return {
		t = function(key: string, params: any?): string
			return Strings.t(key, params, locale)
		end,
	}
end

-- The rings of a seal's rim, from the inside out.
local function rims(disc: any): { any }
	local found = {}
	for _, child in ipairs(disc:GetChildren()) do
		if child:IsA("Frame") and child:FindFirstChildOfClass("UIStroke") ~= nil then
			table.insert(found, child)
		end
	end
	table.sort(found, function(a: any, b: any): boolean
		return a.Size.X.Offset < b.Size.X.Offset
	end)
	return found
end

-- `disc` is the seal of `tierId` in `locale`, `size` across, shining exactly when `shines`.
local function expectSeal(Theme: any, disc: any, tierId: string, locale: string, size: number, shines: boolean)
	local rank = Theme.rank(tierId)
	local word = Strings.t(rank.NameKey, nil, locale)
	local letter = ThemeConfig.dropCap(word)
	assert(letter ~= nil, word .. " has no initial")
	local label = disc:FindFirstChild("Text")
	local where = ("%s (%s)"):format(tierId, locale)
	if label.Text ~= letter then
		error(("%s: the seal reads %q, not %q"):format(where, label.Text, letter :: string))
	end
	expect(disc.Size).toBe(roblox.UDim2.fromOffset(size, size))
	expect(disc.BackgroundColor3).toBe(rank.Fill)
	expect(label.FontFace).toBe(Theme.Fonts.Initial)
	expect(label.TextSize).toBe(math.round(size * 24 / 58))
	expect(label.TextColor3).toBe(rank.Ink)
	expect(disc:FindFirstChildOfClass("UIStroke").Thickness).toBe(3)
	local rings = rims(disc)
	if rank.Rim ~= nil then
		expect(#rings).toBe(2)
		expect(rings[1]:FindFirstChildOfClass("UIStroke").Color).toBe(rank.Rim)
		expect(rings[2]:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Accent)
	else
		expect(#rings).toBe(0)
	end
	if (disc:FindFirstChild("Shine") ~= nil) ~= shines then
		error(("%s: a shine %s"):format(where, if shines then "missing" else "where none is spent"))
	end
end

describe("a tier's seal, run", function()
	it("carries every rank's initial, ink, fill and rims, in either language", function()
		for _, locale in ipairs(Strings.Locales) do
			local world = Engine.world({ Stubs = Engine.interfaceStubs() })
			local Standings = world.require("src/ui/components/Standings")
			local Theme = world.require("src/ui/Theme")
			local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
			for _, tier in ipairs(RankingConfig.Tiers) do
				local seal = Standings.seal(tier.Id, 58, parent, 1, localizer(locale), true)
				expectSeal(Theme, seal.Instance, tier.Id, locale, 58, Theme.rank(tier.Id).Shimmer)
				seal:Destroy()
				local still = Standings.seal(tier.Id, 58, parent, 1, localizer(locale))
				expectSeal(Theme, still.Instance, tier.Id, locale, 58, false)
				still:Destroy()
			end
		end
		-- The French ladder's third rank opens on its accent.
		expect((ThemeConfig.dropCap(Strings.t("rank.script", nil, "fr")))).toBe("É")
	end)

	it("moves to another tier whole: its letter, its colours, its rims and its gold leaf", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Standings = world.require("src/ui/components/Standings")
		local Theme = world.require("src/ui/Theme")
		local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
		local seal = Standings.seal(RankingConfig.Tiers[1].Id, 40, parent, 1, localizer("fr"), true)
		for _, tier in ipairs(RankingConfig.Tiers) do
			seal:SetTier(tier.Id)
			expectSeal(Theme, seal.Instance, tier.Id, "fr", 40, Theme.rank(tier.Id).Shimmer)
		end
		seal:SetTier(RankingConfig.Tiers[1].Id)
		expectSeal(Theme, seal.Instance, RankingConfig.Tiers[1].Id, "fr", 40, false)
	end)
end)

-- The Leaderboard open on a desktop over a board whose rows walk the ladder, the player twelfth on `mine`.
local function board(mine: string): (any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	world.player.UserId = ME
	local Screen = world.require("src/ui/screens/LeaderboardScreen")
	local entries = {}
	for rank = 1, 20 do
		local tier = RankingConfig.Tiers[(rank - 1) % #RankingConfig.Tiers + 1]
		table.insert(entries, {
			Rank = rank,
			UserId = if rank == 12 then ME else 1000 + rank,
			Name = "Player" .. rank,
			Rating = 2000 - rank,
			RankKey = if rank == 12 then mine else tier.NameKey,
		})
	end
	local screen = Screen.new({
		Localize = localizer("fr"),
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
	return screen, world.require("src/ui/Theme"), entries
end

local function tierOfKey(key: string): string
	for _, tier in ipairs(RankingConfig.Tiers) do
		if tier.NameKey == key then
			return tier.Id
		end
	end
	return RankingConfig.Tiers[1].Id
end

describe("the leaderboard's seals, run", function()
	it("seals every row with its tier at 40, rims inside the row, and no gold leaf", function()
		local screen, Theme, entries = board("rank.codex")
		local checked = 0
		for _, entry in ipairs(entries) do
			local row = screen.Instance:FindFirstChild("Row" .. entry.Rank, true)
			if row == nil then
				continue
			end
			checked += 1
			local seal = row:FindFirstChild("Tier", true)
			assert(seal ~= nil, ("row %d has no tier seal"):format(entry.Rank))
			expectSeal(Theme, seal, tierOfKey(entry.RankKey), "fr", 40, false)
			-- The seal and its rims stand inside the row.
			local rings = rims(seal)
			local across = 40 + (if #rings > 0 then rings[#rings].Size.Y.Offset else 0)
			expect(across).toBeLessThanOrEqual(Theme.Sizes.RowHeight)
		end
		expect(checked).toBeGreaterThanOrEqual(15)
	end)

	it("seals each place of the podium with its tier at the foot of its headshot, still", function()
		local screen, Theme, entries = board("")
		for place = 1, 3 do
			local column = screen.Instance:FindFirstChild("Place" .. place, true)
			local head = column:FindFirstChild("Headshot")
			local seal = head:FindFirstChild("Tier")
			assert(seal ~= nil, ("place %d has no tier seal"):format(place))
			expect(seal.AnchorPoint).toBe(roblox.Vector2.new(1, 1))
			expect(seal.Position).toBe(roblox.UDim2.fromScale(1, 1))
			expectSeal(Theme, seal, tierOfKey(entries[place].RankKey), "fr", 36, false)
		end
	end)

	for _, tier in ipairs(RankingConfig.Tiers) do
		it(("gives the player's standing the seal and the word of their tier: %s"):format(tier.Id), function()
			local screen, Theme = board(tier.NameKey)
			local standing = screen.Instance:FindFirstChild("Standing", true)
			local seal = standing:FindFirstChild("Seal")
			expect(seal.Visible).toBe(true)
			-- The standing may spend a gradient on its gold leaf.
			expectSeal(Theme, seal, tier.Id, "fr", 40, Theme.rank(tier.Id).Shimmer)
			local rings = rims(seal)
			local across = 40 + (if #rings > 0 then rings[#rings].Size.Y.Offset else 0)
			expect(across).toBeLessThanOrEqual(standing.Size.Y.Offset)
			-- Its word, between the seal and where the player stands.
			local word = standing:FindFirstChild("Tier")
			expect(word.Text).toBe(Theme.Glyphs.Pip .. " " .. Strings.t(tier.NameKey, nil, "fr"))
			expect(word.FontFace).toBe(Theme.Fonts.Bold)
			expect(word.TextSize).toBe(Theme.Sizes.TextBody)
			local you = standing:FindFirstChild("You")
			expect(seal.LayoutOrder).toBeLessThan(word.LayoutOrder)
			expect(word.LayoutOrder).toBeLessThan(you.LayoutOrder)
		end)
	end

	it("finds the player's row with its own button on the sheet", function()
		local screen, Theme = board("rank.blank")
		local find = screen.Instance:FindFirstChild("Standing", true):FindFirstChild("FindMe")
		assert(find ~= nil and find.Visible, "the standing has no Find me")
		-- A Secondary sticker: a face of the sheet on its chalk lip, not a Ghost's underline.
		local face = find:FindFirstChild("Face")
		assert(face ~= nil, "Find me has no face")
		expect(face.BackgroundColor3).toBe(Theme.Colors.PanelRaised)
		expect(find:FindFirstChild("Base").BackgroundColor3).toBe(Theme.lip("Secondary"))
		expect(find:FindFirstChild("Rule")).toBeNil()
	end)
end)

describe("the Result's new rank, run", function()
	it("is stamped on the seal of the rank reached, its initial and its gold leaf", function()
		for index = 2, #RankingConfig.Tiers do
			local world = Engine.world({ Stubs = Engine.interfaceStubs() })
			local ResultCard = world.require("src/ui/components/ResultCard")
			local Theme = world.require("src/ui/Theme")
			local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
			local card = ResultCard.new(localizer("fr"), parent)
			local before, after = RankingConfig.Tiers[index - 1], RankingConfig.Tiers[index]
			card:Render({
				ModeId = "Duel1v1",
				Won = true,
				Draw = false,
				Scores = { 3, 1 },
				Xp = 0,
				Folios = 0,
				RatingBefore = after.Min - 10,
				RatingAfter = after.Min + 10,
				RankKeyBefore = before.NameKey,
				RankKeyAfter = after.NameKey,
				FirstWinOfDay = false,
				Casts = 1,
				Hits = 1,
				DamageDealt = 1,
				DamageTaken = 1,
				Grade = "grade.clean",
			})
			local row = card.Instance:FindFirstChild("RankUp")
			expect(row.Visible).toBe(true)
			local seal = row:FindFirstChildWhichIsA("Frame")
			expectSeal(Theme, seal, after.Id, "fr", 48, Theme.rank(after.Id).Shimmer)
			-- With its rims, it stands inside its row.
			local rings = rims(seal)
			local across = 48 + (if #rings > 0 then rings[#rings].Size.Y.Offset else 0)
			expect(across).toBeLessThanOrEqual(row.Size.Y.Offset)
			card:Celebrate({ Xp = 0, Folios = 0 })
			expect(seal:FindFirstChildOfClass("UIScale").Scale).toBe(1.5)
			card:Destroy()
		end
	end)
end)

return nil
