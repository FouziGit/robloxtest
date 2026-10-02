--!strict
-- The leaderboard screen (D-147, slice B): the board read from the server's payload, the first three on
-- the podium in the order a podium stands, the player found in it, each row's tier taken from the key the
-- server wrote (the Global board's number is not a rating), and the screen's states read from its source:
-- skeletons while it waits, a way to retry when it fails, the player's own row ringed and pinned.
local Harness = require("./harness")
local LeaderboardView = require("../src/shared/Pure/LeaderboardView")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SCREEN = "src/ui/screens/LeaderboardScreen.luau"
local STANDINGS = "src/ui/components/Standings.luau"

local function stripComments(source: string): string
	local lines = {}
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function entry(rank: number, userId: number): LeaderboardView.Entry
	return { Rank = rank, UserId = userId, Name = "P" .. tostring(rank), Rating = 2000 - rank, RankKey = "rank.codex" }
end

describe("a board", function()
	it("is read from the server's payload, dropping what is not a row", function()
		local nan = 0 / 0
		local entries = LeaderboardView.read({
			{ Rank = 1, UserId = 7, Name = "Ada", Rating = 1712.6, RankKey = "rank.codex" },
			{ Rank = 2, UserId = 8, Rating = 1500 }, -- no name: dropped
			"not a row",
			{ Rank = nan, UserId = -3, Name = "Bea", Rating = math.huge },
		})
		expect(#entries).toBe(2)
		expect(entries[1]).toEqual({ Rank = 1, UserId = 7, Name = "Ada", Rating = 1712, RankKey = "rank.codex" })
		-- A number that is not one falls back: the place follows the list, the rest is zero.
		expect(entries[2]).toEqual({ Rank = 2, UserId = 0, Name = "Bea", Rating = 0, RankKey = "" })
		expect(LeaderboardView.read(nil)).toEqual({})
		expect(LeaderboardView.read("rows")).toEqual({})
	end)

	it("puts the first three on the podium and the rest in rows, and finds the player", function()
		local entries = { entry(1, 11), entry(2, 12), entry(3, 13), entry(4, 14), entry(5, 15) }
		local podium, rows, own = LeaderboardView.split(entries, 14)
		expect(#podium).toBe(3)
		expect(podium[1].Rank).toBe(1)
		expect(podium[3].Rank).toBe(3)
		expect(#rows).toBe(2)
		expect(rows[1].Rank).toBe(4)
		expect(own).toBe(4)
		local _, _, onPodium = LeaderboardView.split(entries, 12)
		expect(onPodium).toBe(2)
		local _, _, absent = LeaderboardView.split(entries, 99)
		expect(absent).toBeNil()
		local short, none = LeaderboardView.split({ entry(1, 11) }, 11)
		expect(#short).toBe(1)
		expect(#none).toBe(0)
	end)

	it("stands its podium second, first, third, left to right", function()
		expect(LeaderboardView.PodiumSize).toBe(3)
		expect(LeaderboardView.PodiumOrder).toEqual({ 2, 1, 3 })
		local standings = stripComments(fs.readFile(STANDINGS))
		expect(standings).toContain("column.LayoutOrder = table.find(LeaderboardView.PodiumOrder, place) or place")
		-- Gold on the tallest, chalk, then bronze: the colours of first, second and third.
		local first = string.find(standings, "{ Fill = Theme.Colors.Primary, Height = 120 },", 1, true)
		local second = string.find(standings, "{ Fill = Theme.Colors.Chalk, Height = 96 },", 1, true)
		local third = string.find(standings, "{ Fill = Theme.Colors.Bronze, Height = 80 },", 1, true)
		assert(first ~= nil and second ~= nil and third ~= nil, "the plinths are no longer gold, chalk and bronze")
		expect(first :: number).toBeLessThan(second :: number)
		expect(second :: number).toBeLessThan(third :: number)
	end)

	it("names each row's tier by the key the server wrote, never by its number", function()
		for _, tier in ipairs(RankingConfig.Tiers) do
			expect(LeaderboardView.tierId(tier.NameKey, RankingConfig.Tiers)).toBe(tier.Id)
		end
		expect(LeaderboardView.tierId("", RankingConfig.Tiers)).toBeNil()
		expect(LeaderboardView.tierId("rank.nothing", RankingConfig.Tiers)).toBeNil()
		-- The Global board stores the gains above the starting rating: a tier cut from that number is wrong.
		for _, path in ipairs({ SCREEN, STANDINGS }) do
			local source = stripComments(fs.readFile(path))
			expect(string.find(source, "tierFor(entry.Rating", 1, true)).toBeNil()
			expect(string.find(source, "tierFor(mine.Rating", 1, true)).toBeNil()
		end
		expect(stripComments(fs.readFile(STANDINGS))).toContain(
			"return LeaderboardView.tierId(entry.RankKey, RankingConfig.Tiers) or RankingConfig.Tiers[1].Id"
		)
	end)
end)

describe("the leaderboard screen", function()
	local screen = stripComments(fs.readFile(SCREEN))

	it("waits in skeletons, and tells a failure it can retry after five seconds of silence", function()
		expect(screen).toContain("local LOAD_TIMEOUT = 5")
		expect(screen).toContain('deps.RemoteClient.invoke("RequestLeaderboard", LOAD_TIMEOUT, boardId)')
		expect(screen).toContain(
			'ListRow.new({ Variant = "Skeleton", Left = "", LayoutOrder = index, Parent = panel.Content })'
		)
		expect(screen).toContain('emptyState(t("common.loadFailed"), true)')
		expect(screen).toContain("fetch(currentBoard, true)")
		-- A failure never wipes rows already shown: the error is drawn only where there is nothing to keep.
		expect(screen).toContain(
			"if boardId == currentBoard and entriesByBoard[boardId] == nil then\n\t\t\t\t\trenderBoard()"
		)
	end)

	it("clicks on a tab, which makes no sound of its own", function()
		expect(screen).toContain('OnSelect = function(id: string)\n\t\t\tdeps.SoundController.play("UiClick")')
	end)

	it("rings the player's own row, and pins a copy at the foot while it is out of sight", function()
		expect(screen).toContain('Variant = if mine then "Highlight" else "Item",')
		local pinned = string.match(screen, "local function refreshPinned%(%)(.-)\n\tend\n")
		assert(pinned ~= nil, "LeaderboardScreen has no refreshPinned: this gate would check nothing")
		expect(pinned).toContain("hidden = rowTop + row.AbsoluteSize.Y < top or rowTop > bottom")
		expect(pinned).toContain('Variant = "Highlight",')
		expect(pinned).toContain("Parent = panel.Footer,")
	end)

	it("fetches a headshot off the thread and says so when it cannot", function()
		local standings = stripComments(fs.readFile(STANDINGS))
		local head = string.match(standings, "local function headshot%(.-\nend\n")
		assert(head ~= nil, "Standings has no headshot: this gate would check nothing")
		expect(head).toContain("task.spawn(function()")
		expect(head).toContain("local ok, image = pcall(function(): string")
		expect(head).toContain('log.warn("no headshot for %s (%d) on the podium: %s"')
	end)
end)
