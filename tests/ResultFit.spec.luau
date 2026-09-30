--!strict
-- The Result at the window it was seen scrolling in, run (tests/engine.luau, tests/measure.luau): the real
-- ResultScreen and ResultCard, on Studio's 1529 x 886 window under its top bar of 58, with a pointer.
--
-- Its rows stand in the card's window there, whatever the match paid. Seen in Studio, they scrolled by 17 units:
-- the "Details" toggle was drawn with a pointer too, a row of 52 and its gap, where the details it folds were
-- already open and could only be hidden. The details are folded on a phone, and there the toggle opens them.
local Engine = require("./engine")
local Harness = require("./harness")
local Measure = require("./measure")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local STUDIO_WINDOW = { 1529, 886 }
local STUDIO_TOP_BAR = 58
local SCREEN = "src/ui/screens/ResultScreen.luau"

-- The fullest card a match ends on: a new rank, the first win of the day, a glyph to unlock next, a best chain.
local OUTCOME = {
	ModeId = "Duel1v1",
	Won = true,
	Draw = false,
	Scores = { 3, 1 },
	Xp = 120,
	Folios = 40,
	RatingBefore = RankingConfig.Tiers[2].Min - 10,
	RatingAfter = RankingConfig.Tiers[2].Min + 10,
	RankKeyBefore = RankingConfig.Tiers[1].NameKey,
	RankKeyAfter = RankingConfig.Tiers[2].NameKey,
	FirstWinOfDay = true,
	Casts = 24,
	Hits = 17,
	DamageDealt = 640,
	DamageTaken = 310,
	Grade = "grade.clean",
}

local PROFILE = {
	Progression = { Level = 1, XP = 20, TotalXP = 20 },
	Stats = { GlyphsCast = 24, GlyphsHit = 17, Kills = 1, Deaths = 0, MatchesPlayed = 1, BestChain = 4 },
}

-- The card seen scrolling in Studio: a ranked win that kept its rank, the first of the day, no chain of two.
local SEEN = table.clone(OUTCOME)
SEEN.RatingBefore = 1000
SEEN.RatingAfter = 1018
SEEN.RankKeyBefore = RankingConfig.Tiers[1].NameKey
SEEN.RankKeyAfter = RankingConfig.Tiers[1].NameKey
local SEEN_PROFILE = {
	Progression = { Level = 1, XP = 0, TotalXP = 0 },
	Stats = { GlyphsCast = 0, GlyphsHit = 0, Kills = 0, Deaths = 0, MatchesPlayed = 0, BestChain = 0 },
}

-- The Result, open on `outcome` and `profile` in a window `width` x `height` points with a top bar of `topBar`,
-- touch-only when `phone`. Returns the card's rows, the height of the screen in design units, and its Theme.
local function build(
	width: number,
	height: number,
	topBar: number,
	phone: boolean,
	outcome: any?,
	profile: any?
): (any, number, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local screenHeight: number
	if phone then
		screenHeight = Engine.phone(world, width, height)
	else
		world.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(width, height)
		world.guiService.GetGuiInset = function(): (any, any)
			return roblox.Vector2.new(0, topBar), roblox.Vector2.zero
		end
		screenHeight = height / world.require("src/ui/Theme").activeScale()
	end
	local Screen = world.require("src/ui/screens/ResultScreen")
	local screen = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		ClientData = {
			get = function(): any
				return profile or PROFILE
			end,
			Changed = Engine.signal(),
		},
		SoundController = { play = function() end },
		MatchController = {
			getLastOutcome = function(): any
				return outcome or OUTCOME
			end,
			joinQueue = function() end,
		},
		OnClose = function() end,
	})
	screen:Open()
	world:advance(1)
	local rows = screen.Instance:FindFirstChild("Rows", true)
	assert(rows ~= nil, "the Result has no rows: this gate would check nothing")
	return rows, screenHeight, world.require("src/ui/Theme")
end

-- The takeover the rows stand in.
local function takeoverOf(rows: any): any
	local current = rows
	while current ~= nil and current.Name ~= "Takeover" do
		current = current.Parent
	end
	assert(current ~= nil, "the rows stand in no takeover: this gate would check nothing")
	return current
end

describe("the Result, run", function()
	it("is measured as Studio measured it: the card seen scrolling overran its window by 17", function()
		local rows, screenHeight = build(STUDIO_WINDOW[1], STUDIO_WINDOW[2], STUDIO_TOP_BAR, false, SEEN, SEEN_PROFILE)
		-- As it was: the toggle drawn with a pointer. Studio read a canvas of 436.48 on a window of 421.56 pixels,
		-- through the 0.88 its exit scales the card to: 496 and 479.04 units.
		rows:FindFirstChild("DetailsToggle").Visible = true
		expect(Measure.listHeight(rows)).toBe(496)
		expect(Measure.heightOf(rows, screenHeight)).toBeCloseTo(479.04, 2)
	end)

	it("holds its fullest card without scrolling in Studio's 886-high window, with a pointer", function()
		local rows, screenHeight, Theme = build(STUDIO_WINDOW[1], STUDIO_WINDOW[2], STUDIO_TOP_BAR, false)
		-- Every row the card can show is showing.
		for _, name in ipairs({ "Score", "Grade", "RankUp", "Rewards", "Level", "NextUnlock", "FirstWin" }) do
			local row = rows:FindFirstChild(name)
			assert(row ~= nil, ("the card has no %s"):format(name))
			expect(row.Visible).toBe(true)
		end
		local details = rows:FindFirstChild("Details")
		expect(details.Visible).toBe(true)
		expect(details:FindFirstChild("BestChain").Visible).toBe(true)
		-- The details are open, and nothing is drawn to fold them.
		expect(rows:FindFirstChild("DetailsToggle").Visible).toBe(false)
		local window = Measure.heightOf(rows, screenHeight)
		expect(Measure.listHeight(rows)).toBeLessThanOrEqual(window)
		-- Held by its layout, not by smaller words: no line on it under the smallest the interface sets.
		local lines = 0
		for _, label in ipairs(rows:GetDescendants()) do
			if label:IsA("TextLabel") and (label.Parent == rows or label.Parent == details) then
				lines += 1
				expect(label.TextSize).toBeGreaterThanOrEqual(Theme.Sizes.TextSmall)
			end
		end
		expect(lines).toBeGreaterThanOrEqual(6)
	end)

	-- Seen in Studio at 1529 x 771: the fullest card scrolled by 53. A 1366 x 768 screen is as short.
	for _, window in ipairs({ { 1529, 771 }, { 1366, 768 } }) do
		it(
			("holds its fullest card without scrolling in a %d x %d window, with a pointer"):format(
				window[1],
				window[2]
			),
			function()
				local rows, screenHeight = build(window[1], window[2], STUDIO_TOP_BAR, false)
				expect(rows:FindFirstChild("Details").Visible).toBe(true)
				expect(Measure.listHeight(rows)).toBeLessThanOrEqual(Measure.heightOf(rows, screenHeight))
				-- The card rose into the outcome's share, which keeps room for its word.
				local banner = takeoverOf(rows):FindFirstChild("Banner")
				local least = tonumber(string.match(fs.readFile(SCREEN), "\nlocal BANNER_MIN = (%d+)\n"))
				assert(
					least ~= nil and least >= 120,
					"the outcome keeps no room for its word: this gate would check nothing"
				)
				expect(Measure.heightOf(banner, screenHeight)).toBeGreaterThanOrEqual(least :: number)
			end
		)
	end

	it("keeps the outcome's third where the card already holds its rows", function()
		local rows = build(STUDIO_WINDOW[1], STUDIO_WINDOW[2], STUDIO_TOP_BAR, false)
		local takeover = takeoverOf(rows)
		expect(takeover:FindFirstChild("Banner").Size).toBe(roblox.UDim2.fromScale(1, 0.3))
		expect(takeover:FindFirstChild("Card").Size).toBe(roblox.UDim2.fromScale(0.94, 0.68))
	end)

	for _, phone in ipairs({ { 667, 375 }, { 844, 390 } }) do
		it(
			("folds the details on a %d x %d phone, under the toggle that opens them"):format(phone[1], phone[2]),
			function()
				local rows = build(phone[1], phone[2], 0, true)
				local toggle = rows:FindFirstChild("DetailsToggle")
				local details = rows:FindFirstChild("Details")
				expect(details.Visible).toBe(false)
				expect(toggle.Visible).toBe(true)
			end
		)
	end
end)

return nil
