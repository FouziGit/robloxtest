--!strict
-- Only players reach the season ladders (D-203). Studio's multi-client tests give their local players ids of
-- zero and below, and with API access those ids were written into the real S1_Global, S1_Duel1v1 and
-- S1_Team3v3, where they had no name to resolve and showed as raw numbers (docs/QA.md R5).
--
-- The rule is pure (LadderGate); the real LeaderboardService is then run over a pretend DataStoreService, so
-- what is checked is what reaches SetAsync and what the boards show.
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local LadderGate = require("../src/shared/Pure/LadderGate")
local LogStub = require("./logstub")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local StudioConfig = require("../src/server/Config/StudioConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Write = { Store: string, Key: string, Value: number }
type Ladder = {
	world: any,
	service: any,
	writes: { Write },
	lines: { string },
	rated: (userId: number, modeId: string, rating: number) -> (),
}

-- The real LeaderboardService, started on a server that is Studio or not, with `rows` already in the
-- ladders (store name -> sorted rows) and `writeLadders` as StudioConfig.WriteLadders.
local function ladder(isStudio: boolean, writeLadders: boolean, rows: { [string]: { any } }?): Ladder
	local writes: { Write } = {}
	local dataStores = {
		GetOrderedDataStore = function(_self: any, name: string): any
			return {
				SetAsync = function(_store: any, key: string, value: number)
					table.insert(writes, { Store = name, Key = key, Value = value })
				end,
				GetSortedAsync = function(_store: any, _ascending: boolean, _count: number): any
					return {
						GetCurrentPage = function(_pages: any): { any }
							return if rows ~= nil then rows[name] or {} else {}
						end,
					}
				end,
				GetAsync = function(): any
					return nil
				end,
			}
		end,
	}
	local Log, lines = LogStub.new()
	local stubs = Engine.interfaceStubs()
	stubs["src/shared/Util/Log"] = Log
	stubs["src/server/Config/StudioConfig"] = { WriteLadders = writeLadders }
	local world = Engine.world({ Services = { DataStoreService = dataStores }, Stubs = stubs })
	world.game:GetService("RunService").IsStudio = function(): boolean
		return isStudio
	end
	world.game.BindToClose = function() end

	local players = world.game:GetService("Players")
	local online: { [number]: any } = {}
	players.GetPlayers = function(): { any }
		local list = {}
		for _, player in pairs(online) do
			table.insert(list, player)
		end
		return list
	end
	players.GetPlayerByUserId = function(_self: any, userId: number): any
		return online[userId]
	end
	players.GetNameFromUserIdAsync = function(_self: any, userId: number): string
		return "Account" .. userId
	end

	local ratings: { [number]: { [string]: number } } = {}
	local ratingChanged = Engine.signal()
	local service = world.require("src/server/Services/LeaderboardService")
	service.Init({
		Registry = { setCallback = function() end },
		Ranking = {
			getRating = function(player: any, modeId: string): number
				local own = ratings[player.UserId]
				return if own ~= nil and own[modeId] ~= nil then own[modeId] else RankingConfig.InitialRating
			end,
			rankKeyFor = function(_rating: number): string
				return ""
			end,
			RatingChanged = ratingChanged,
		},
		Hub = {
			getLeaderboardEntries = function(_boardId: string): any
				return nil
			end,
		},
	})
	service.Start()

	return {
		world = world,
		service = service,
		writes = writes,
		lines = lines,
		rated = function(userId: number, modeId: string, rating: number)
			local player = online[userId]
			if player == nil then
				player = Engine.instance("Player", players)
				player.Name = "Tester" .. userId
				player.UserId = userId
				online[userId] = player
			end
			ratings[userId] = ratings[userId] or {}
			local before = ratings[userId][modeId] or RankingConfig.InitialRating
			ratings[userId][modeId] = rating
			ratingChanged:Fire(player, modeId, before, rating)
		end,
	}
end

-- The keys written to the ladders, sorted.
local function writtenKeys(session: Ladder): { string }
	local keys: { string } = {}
	for _, write in ipairs(session.writes) do
		if table.find(keys, write.Key) == nil then
			table.insert(keys, write.Key)
		end
	end
	table.sort(keys)
	return keys
end

local function linesContaining(session: Ladder, needle: string): number
	local count = 0
	for _, line in ipairs(session.lines) do
		if string.find(line, needle, 1, true) ~= nil then
			count += 1
		end
	end
	return count
end

describe("the ladder gate", function()
	it("takes only positive whole ids for players", function()
		expect(LadderGate.isPlayerId(1)).toBe(true)
		expect(LadderGate.isPlayerId(3721321390)).toBe(true)
		for _, id in ipairs({ 0, -1, -2, -999999, 1.5, math.huge, 0 / 0 }) do
			expect(LadderGate.isPlayerId(id)).toBe(false)
		end
	end)

	it("refuses a test id whatever the switch says, and Studio unless the switch allows it", function()
		expect(LadderGate.refusal(-1, false, false)).toBe("TestId")
		expect(LadderGate.refusal(-1, true, true)).toBe("TestId")
		expect(LadderGate.refusal(0, false, true)).toBe("TestId")
		expect(LadderGate.refusal(42, true, false)).toBe("Studio")
		expect(LadderGate.refusal(42, true, true)).toBeNil()
		expect(LadderGate.refusal(42, false, false)).toBeNil()
	end)

	it("ships with Studio kept off the ladders", function()
		expect(StudioConfig.WriteLadders).toBe(false)
	end)
end)

describe("the season ladders, run", function()
	it("never receive a test player's rating, on a live server or in Studio", function()
		for _, isStudio in ipairs({ false, true }) do
			local session = ladder(isStudio, true)
			session.rated(-1, "Duel1v1", 1100)
			session.rated(-2, "Team3v3", 1080)
			session.rated(0, "Duel1v1", 1050)
			session.world:advance(3)
			expect(#session.writes).toBe(0)
		end
	end)

	it("write a player's rating on a live server, to the mode board and the cumulative one", function()
		local session = ladder(false, false)
		session.rated(42, "Duel1v1", 1100)
		session.world:advance(3)
		expect(writtenKeys(session)).toEqual({ "42" })
		expect(#session.writes).toBe(2)
	end)

	it("keep a Studio session's ratings out unless StudioConfig.WriteLadders is on", function()
		local closed = ladder(true, false)
		closed.rated(42, "Duel1v1", 1100)
		closed.world:advance(3)
		expect(#closed.writes).toBe(0)

		local open = ladder(true, true)
		open.rated(42, "Duel1v1", 1100)
		open.rated(-3, "Duel1v1", 1100)
		open.world:advance(3)
		expect(writtenKeys(open)).toEqual({ "42" })
	end)

	it("say why once per server, not once per rating", function()
		local session = ladder(true, false)
		for step = 1, 5 do
			session.rated(-step, "Duel1v1", 1000 + step)
			session.rated(40 + step, "Duel1v1", 1000 + step)
		end
		expect(linesContaining(session, "test id")).toBe(1)
		expect(linesContaining(session, "StudioConfig.WriteLadders is off")).toBe(1)
	end)

	it("never show a row a test player left in a ladder, and close the ranks over it", function()
		-- The ladder of the season in play, whichever it is: S1_Duel1v1 today.
		local store = GameConfig.SeasonId .. "_Duel1v1"
		local session = ladder(false, false, {
			[store] = {
				{ key = "-1", value = 1400 },
				{ key = "77", value = 1300 },
				{ key = "0", value = 1250 },
				{ key = "88", value = 1200 },
			},
		})
		local entries = session.service.getBoard("Duel1v1").Entries
		expect(#entries).toBe(2)
		expect(entries[1].UserId).toBe(77)
		expect(entries[1].Rank).toBe(1)
		expect(entries[1].Name).toBe("Account77")
		expect(entries[2].UserId).toBe(88)
		expect(entries[2].Rank).toBe(2)
	end)
end)
