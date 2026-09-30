--!strict
-- The balance of the 28 glyphs, read from two events (E8-S7). How often a glyph is taken into a queue, how often a
-- player who cast it won, and how much damage it dealt were nowhere: a glyph that wins too much, or that nobody
-- takes, could only be guessed at. GlyphPick counts the glyphs a player takes into a queue; GlyphMatch, at the result
-- of a match, names each glyph a player cast in it, the mode and whether they won, and is worth the damage it dealt.
--
-- Two events, under Roblox's caps: at most 28 glyphs x 2 modes x 2 outcomes = 112 combinations of custom fields
-- (Roblox groups what comes past 8,000), and no key but CustomField01 to 03. The real MatchService,
-- MatchmakingService, GlyphService and AnalyticsService run in a pretend server (tests/server.luau); the damage a
-- glyph deals arrives as CombatService reports it, on its Damaged signal, and the sources are read for the rest.
local Analytics = require("./analytics")
local AnalyticsConfig = require("../src/server/Config/AnalyticsConfig")
local DeveloperConfig = require("../src/server/Config/DeveloperConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local Server = require("./server")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
local TEAM = MatchConfig.Modes.Team3v3

-- The custom events `name` that reached Roblox, as { player, value, fields }.
local function sent(world: Server.World, name: string): { { any } }
	local found = {}
	for _, call in ipairs(world.analytics:of("LogCustomEvent", name)) do
		table.insert(found, { call.Player, call.Args[2], call.Args[3] })
	end
	return found
end

-- The GlyphMatch events of `player`, by glyph: { value, fields }.
local function matchOf(world: Server.World, player: any): { [string]: { any } }
	local byGlyph: { [string]: { any } } = {}
	for _, event in ipairs(sent(world, "GlyphMatch")) do
		if event[1] == player then
			local glyphId = event[3].CustomField01
			assert(byGlyph[glyphId] == nil, glyphId .. " was told twice for the same match")
			byGlyph[glyphId] = { event[2], event[3] }
		end
	end
	return byGlyph
end

-- The events of the catalogue whose fields name a glyph.
local function glyphEvents(): { string }
	local names: { string } = {}
	for name, fields in pairs(AnalyticsConfig.Events) do
		if table.find(fields, "Glyph") ~= nil then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- How many combinations of custom field values `name` can send at most.
local function combinations(name: string): number
	local domains = Analytics.domains()
	local product = 1
	for _, field in ipairs(AnalyticsConfig.Events[name]) do
		product *= #domains[field]
	end
	return product
end

-- The first glyph of `player`'s loadout that deals damage, the second, and the first that deals none.
local function loadoutOf(setup: Server.Services, player: any): (string, string, string)
	local striking: { string } = {}
	local utility: string? = nil
	for _, glyphId in ipairs(setup.data.get(player).Loadout.Slots) do
		if GlyphConfig.isUtility(glyphId) then
			utility = utility or glyphId
		else
			table.insert(striking, glyphId)
		end
	end
	assert(#striking >= 2 and utility ~= nil, "the starting loadout lacks two striking glyphs and a utility one")
	return striking[1], striking[2], utility :: string
end

-- Two players in a ranked duel, past the countdown.
local function duel(): (Server.Services, any, any)
	local setup = Server.services()
	local a = setup.world:join(601, "Ada")
	local b = setup.world:join(602, "Bea")
	expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBe(nil)
	setup.world:advance(DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(a).Phase).toBe("Playing")
	return setup, a, b
end

-- A hit that landed, as CombatService reports it.
local function strike(setup: Server.Services, source: any, target: any, applied: number, glyphId: string?)
	setup.combat.Damaged:Fire(source.UserId, target.Character, applied, "Glyph", glyphId)
end

local function knockOut(setup: Server.Services, player: any)
	player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.world:advance(0.2)
end

-- `a` wins 2-0: the match stands on its result.
local function sweep(setup: Server.Services, a: any, b: any)
	knockOut(setup, b)
	setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
	knockOut(setup, b)
	setup.world:advance(MatchConfig.RoundOverSeconds + 0.1)
	expect(setup.match.getMatch(a).Phase).toBe("Result")
end

-- A queue, run for real.
local function queue(setup: Server.Services): (player: any, modeId: string) -> ()
	local handlers: { [string]: (...any) -> () } = {}
	local matchmaking = setup.world.require("src/server/Services/MatchmakingService")
	matchmaking.Init({
		Registry = {
			on = function(name: string, handler: (...any) -> ())
				handlers[name] = handler
			end,
			fire = function() end,
		},
		Notify = { send = function() end },
		Ranking = setup.ranking,
		Match = setup.match,
		WorldBoss = {
			isLive = function(): boolean
				return false
			end,
		},
		DataService = setup.data,
		Loadout = setup.loadout,
		Analytics = setup.analytics,
	})
	matchmaking.Start()
	return function(player: any, modeId: string)
		handlers.JoinQueue(player, modeId)
	end
end

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

----------------------------------------------------------------
-- Specs
----------------------------------------------------------------

describe("the glyph balance events, under Roblox's caps (E8-S7)", function()
	it("are two, and only two", function()
		expect(glyphEvents()).toEqual({ "GlyphMatch", "GlyphPick" })
		expect(AnalyticsConfig.Events.GlyphMatch).toEqual({ "Glyph", "Mode", "GlyphOutcome" })
		expect(AnalyticsConfig.Events.GlyphPick).toEqual({ "Glyph", "Mode" })
	end)

	it("hold at most 28 x 2 x 2 = 112 combinations, far under the 8,000 Roblox keeps apart", function()
		expect(#GlyphConfig.Glyphs).toBe(28)
		expect(#MatchConfig.ModeOrder).toBe(2)
		expect(AnalyticsConfig.Vocabulary.GlyphOutcome).toEqual({ "Win", "Loss" })
		expect(combinations("GlyphMatch")).toBe(112)
		expect(combinations("GlyphPick")).toBe(56)
		local total = 0
		for name in pairs(AnalyticsConfig.Events) do
			local each = combinations(name)
			expect(each).toBeLessThanOrEqual(AnalyticsConfig.Limits.FieldCombinations)
			total += each
		end
		expect(total).toBeLessThanOrEqual(AnalyticsConfig.Limits.FieldCombinations)
	end)
end)

describe("GlyphMatch, at the result of a match (E8-S7)", function()
	it("names every glyph each player cast, the mode and the outcome, worth the damage it dealt", function()
		local setup, a, b = duel()
		local first, second, utility = loadoutOf(setup, a)
		expect(setup.cast(a, first)).toBe(true)
		expect(setup.cast(a, utility)).toBe(true)
		strike(setup, a, b, 30, first)
		strike(setup, a, b, 12.4, first)
		expect(setup.cast(b, second)).toBe(true)
		strike(setup, b, a, 9, second)
		sweep(setup, a, b)

		expect(matchOf(setup.world, a)).toEqual({
			[first] = { 42, { CustomField01 = first, CustomField02 = DUEL.Id, CustomField03 = "Win" } },
			[utility] = { 0, { CustomField01 = utility, CustomField02 = DUEL.Id, CustomField03 = "Win" } },
		})
		expect(matchOf(setup.world, b)).toEqual({
			[second] = { 9, { CustomField01 = second, CustomField02 = DUEL.Id, CustomField03 = "Loss" } },
		})
	end)

	it("adds up a glyph's hits from every round of the match", function()
		local setup, a, b = duel()
		local first = loadoutOf(setup, a)
		strike(setup, a, b, 20, first)
		knockOut(setup, b)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		strike(setup, a, b, 15, first)
		knockOut(setup, b)
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.1)
		expect(matchOf(setup.world, a)[first][1]).toBe(35)
	end)

	it("tells a draw as no win", function()
		local setup, a, b = duel()
		local first = loadoutOf(setup, a)
		expect(setup.cast(a, first)).toBe(true)
		for round = 1, 3 do
			setup.world:advance(DUEL.DurationSeconds / 3 + 0.5)
			if round < 3 then
				setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
			end
		end
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.5)
		expect(setup.match.getMatch(a).Phase).toBe("Result")
		expect(matchOf(setup.world, a)[first][2].CustomField03).toBe("Loss")
		expect(matchOf(setup.world, b)).toEqual({})
	end)

	it("ignores damage that names no glyph of the roster", function()
		local setup, a, b = duel()
		strike(setup, a, b, 25, nil)
		strike(setup, a, b, 25, "NotAGlyph")
		sweep(setup, a, b)
		expect(matchOf(setup.world, a)).toEqual({})
	end)
end)

describe("GlyphPick, at the entry of a queue (E8-S7)", function()
	it("counts each glyph a player takes into the queue, with the mode", function()
		local setup = Server.services()
		local join = queue(setup)
		local cleo = setup.world:join(611, "Cleo")
		join(cleo, TEAM.Id)
		local expected = {}
		for _, glyphId in ipairs(setup.data.get(cleo).Loadout.Slots) do
			table.insert(expected, { cleo, 1, { CustomField01 = glyphId, CustomField02 = TEAM.Id } })
		end
		expect(#expected).toBeGreaterThan(0)
		expect(sent(setup.world, "GlyphPick")).toEqual(expected)
		-- Asked again while queued, nothing more is counted.
		join(cleo, TEAM.Id)
		expect(#sent(setup.world, "GlyphPick")).toBe(#expected)
	end)

	it("counts a developer's picks as the loadout they will play the match with, not the whole roster", function()
		local setup = Server.services()
		local join = queue(setup)
		local developer = setup.world:join(DeveloperConfig.UserIds[1], "Developer")
		-- The whole roster equipped, as the developer list lets them in the hub (D-208).
		local data = setup.data.get(developer)
		data.Loadout.Slots = {}
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			table.insert(data.Unlocks.Glyphs, glyph.Id)
			table.insert(data.Loadout.Slots, glyph.Id)
		end
		local _, fielded = setup.loadout.fielded(data)
		expect(#data.Loadout.Slots).toBeGreaterThan(#fielded)
		join(developer, DUEL.Id)
		expect(#sent(setup.world, "GlyphPick")).toBe(#fielded)
	end)
end)

describe("the glyph a hit names (E8-S7)", function()
	it("is the id GlyphEffects puts first in every tracker's tags", function()
		local effects = code("src/server/Effects/GlyphEffects.luau")
		local trackers = 0
		for tags in effects:gmatch("Tags = (%b{})") do
			trackers += 1
			if tags:match("^{%s*def%.Id[,%s}]") == nil then
				error("a glyph tracker does not put the glyph id first: " .. tags)
			end
		end
		expect(trackers).toBeGreaterThanOrEqual(2)
	end)

	it("is what CombatService's Damaged carries for glyph damage, and only for it", function()
		local combat = code("src/server/Services/CombatService.luau")
		expect(combat).toContain(
			'CombatService.Damaged:Fire(source.UserId, targetModel, applied, kind, if kind == "Glyph" then tags[1] else nil)'
		)
	end)
end)

return nil
