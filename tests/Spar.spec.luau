--!strict
-- The practice duel against a Forger, run (E10-S6): the real SparService, MatchmakingService, DataService and
-- CurrencyService in a pretend server (tests/server.luau). The pit is a stand-in whose Forger the spec brings down
-- (BattlegroundService's pits and their Forger need the engine); MatchService is a stand-in that records the
-- matches the queue forms. RankingService is a trap: anything that asks it for anything fails the spec.
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Engine = require("./engine")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local Server = require("./server")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SPAR = MatchConfig.Spar
local DEF = MatchConfig.Modes.Spar1v1
local DUEL = SPAR.QueueModeId
local ROUND_OVER = MatchConfig.RoundOverSeconds
local MAX_ROUNDS = (DEF.RoundsToWin - 1) * DEF.Teams + 1
local ROUND_SECONDS = DEF.DurationSeconds / MAX_ROUNDS

type Fired = { Name: string, Player: any, Payload: any }
type Setup = {
	world: Server.World,
	data: any,
	spar: any,
	matchmaking: any,
	handlers: { [string]: (...any) -> () },
	fired: { Fired },
	notices: { { Player: any, Key: string } },
	-- The stand-in pit: its Forger, what it was asked, and whether it is lent.
	pit: { Alive: boolean, Health: number, Seated: number, Live: { [any]: boolean }, Open: { [any]: boolean } },
	-- The matches the queue formed, as the user ids of their teams, and whoever still sparred when one started.
	matches: { { { number } } },
	-- While On, the match stand-in refuses every start, as MatchService does with no free arena.
	refusing: { On: boolean },
	overlapped: { any },
	inMatch: { [number]: boolean },
	xp: { number },
	teleported: { any },
	ratings: { [number]: number },
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function setup(): Setup
	local world = Server.world()
	local handlers: { [string]: (...any) -> () } = {}
	local fired: { Fired } = {}
	local registry = {
		on = function(name: string, handler: (...any) -> ())
			handlers[name] = handler
		end,
		fire = function(name: string, player: any, payload: any)
			table.insert(fired, { Name = name, Player = player, Payload = payload })
		end,
	}
	local notices: { { Player: any, Key: string } } = {}
	local notify = {
		send = function(player: any, key: string)
			table.insert(notices, { Player = player, Key = key })
		end,
	}
	local pit = { Alive = true, Health = 160, Seated = 0, Live = {}, Open = {} }
	local overlapped: { any } = {}
	local inMatch: { [number]: boolean } = {}
	local matches: { { { number } } } = {}
	local refusing = { On = false }
	local ratings: { [number]: number } = {}
	local match = {
		isInMatch = function(player: any): boolean
			return inMatch[player.UserId] == true
		end,
		isFinishing = function(): boolean
			return false
		end,
		releaseFromResult = function(): boolean
			return false
		end,
		start = function(_modeId: string, teams: { { number } }): string?
			if refusing.On then
				return nil
			end
			-- The spar of a player the match takes has ended before it starts: two fights never hold one body.
			for _, members in ipairs(teams) do
				for _, userId in ipairs(members) do
					local player = world.players:GetPlayerByUserId(userId)
					if player ~= nil and pit.Open[player] then
						table.insert(overlapped, player)
					end
				end
			end
			table.insert(matches, teams)
			for _, members in ipairs(teams) do
				for _, userId in ipairs(members) do
					inMatch[userId] = true
				end
			end
			return "match-" .. #matches
		end,
	}
	local worldBoss = {
		isLive = function(): boolean
			return false
		end,
		isEngaged = function(): boolean
			return false
		end,
	}
	local forgerModel = Engine.instance("Model")
	local battleground = {
		openPit = function(player: any): boolean
			pit.Open[player] = true
			return true
		end,
		seatPit = function(player: any, _character: any): boolean
			pit.Seated += 1
			pit.Alive = true
			pit.Health = 160
			return pit.Open[player] == true
		end,
		setPitLive = function(player: any, live: boolean)
			pit.Live[player] = live
		end,
		pitForger = function(_player: any): (boolean, number, number, any)
			return pit.Alive, if pit.Alive then pit.Health else 0, 160, forgerModel
		end,
		closePit = function(player: any)
			pit.Open[player] = nil
		end,
	}
	local xp: { number } = {}
	local teleported: { any } = {}
	-- Every service is handed the bootstrap's whole table: a spar that reached for the ranking would find this.
	local ranking = setmetatable({}, {
		__index = function(_self: any, name: string): any
			error(("a spar asked RankingService for %s"):format(name), 2)
		end,
	})

	local data = world.require("src/server/Services/DataService")
	local currency = world.require("src/server/Services/CurrencyService")
	local matchmaking = world.require("src/server/Services/MatchmakingService")
	local spar = world.require("src/server/Services/SparService")
	local deps = {
		Registry = registry,
		DataService = data,
		Notify = notify,
		Currency = currency,
		Ranking = ranking,
		Match = match,
		WorldBoss = worldBoss,
		Battleground = battleground,
		Matchmaking = matchmaking,
		Movement = {
			applyFreeze = function() end,
			clearStun = function() end,
		},
		Glyph = { Cast = Engine.signal(), CastLanded = Engine.signal() },
		Combat = { Damaged = Engine.signal() },
		Progression = {
			addXp = function(_player: any, amount: number): number
				table.insert(xp, amount)
				return amount
			end,
		},
		Hub = {
			teleportToHub = function(player: any)
				table.insert(teleported, player)
			end,
		},
	}
	-- The matchmaker reads the ranking for a player's rating: the real rule, on a table of the spec's.
	local matchmakingDeps = table.clone(deps)
	matchmakingDeps.Ranking = {
		getRating = function(player: any): number
			return ratings[player.UserId] or 1000
		end,
	}
	data.Init(deps)
	currency.Init(deps)
	matchmaking.Init(matchmakingDeps)
	spar.Init(deps)
	data.Start()
	matchmaking.Start()
	spar.Start()
	return {
		world = world,
		data = data,
		spar = spar,
		matchmaking = matchmaking,
		handlers = handlers,
		fired = fired,
		notices = notices,
		pit = pit,
		matches = matches,
		refusing = refusing,
		overlapped = overlapped,
		inMatch = inMatch,
		xp = xp,
		teleported = teleported,
		ratings = ratings,
	}
end

local function last(s: Setup, name: string, player: any): any
	for index = #s.fired, 1, -1 do
		local entry = s.fired[index]
		if entry.Name == name and entry.Player == player then
			return entry.Payload
		end
	end
	return nil
end

local function count(s: Setup, name: string, player: any): number
	local found = 0
	for _, entry in ipairs(s.fired) do
		if entry.Name == name and entry.Player == player then
			found += 1
		end
	end
	return found
end

-- Whether `player` fights a spar, as the server last told them (SparChanged).
local function sparring(s: Setup, player: any): boolean
	local snapshot = last(s, "SparChanged", player)
	return snapshot ~= nil and snapshot.Sparring == true
end

local function noticed(s: Setup, player: any, key: string): boolean
	for _, notice in ipairs(s.notices) do
		if notice.Player == player and notice.Key == key then
			return true
		end
	end
	return false
end

-- A player alone in the 1v1 queue for `seconds`.
local function queued(s: Setup, userId: number, name: string, seconds: number): any
	local player = s.world:join(userId, name)
	s.world:advance(0.1)
	s.handlers.JoinQueue(player, DUEL)
	s.world:advance(seconds)
	return player
end

-- The spar started and its first round played.
local function fight(s: Setup, player: any)
	s.handlers.StartSpar(player)
	-- Past the count, and past the next snapshot after it (MatchConfig.SnapshotHz).
	s.world:advance(DEF.CountdownSeconds + 0.5)
	expect(last(s, "MatchChanged", player).Phase).toBe("Playing")
end

-- The Forger brought down, and the tick that sees it close the round.
local function downForger(s: Setup)
	s.pit.Alive = false
	s.world:advance(0.2)
end

-- Two rounds won in a row from a round being played, and the spar brought to its result.
local function win(s: Setup, player: any)
	downForger(s)
	s.world:advance(ROUND_OVER + DEF.CountdownSeconds + 0.5)
	expect(last(s, "MatchChanged", player).Phase).toBe("Playing")
	downForger(s)
	s.world:advance(ROUND_OVER + 0.5)
	expect(last(s, "MatchChanged", player).Phase).toBe("Result")
end

describe("the practice duel's offer, run", function()
	it("comes after twenty seconds alone in the 1v1 queue, and is gone once another player waits there", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 15)
		local early = last(s, "SparChanged", ada)
		expect(early == nil or early.Offered == false).toBe(true)
		s.world:advance(6)
		expect(last(s, "SparChanged", ada).Offered).toBe(true)
		expect(last(s, "SparChanged", ada).PaidLeft).toBe(SPAR.PaidPerDay)
		-- Far apart in rating, so the queue cannot pair them: Ada is no longer alone.
		s.ratings[12] = 3000
		queued(s, 12, "Bea", 1.5)
		expect(last(s, "SparChanged", ada).Offered).toBe(false)
		expect(#s.matches).toBe(0)
	end)

	it("refuses a start the server does not offer", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 5)
		s.handlers.StartSpar(ada)
		expect(noticed(s, ada, "spar.unavailable")).toBe(true)
		expect(sparring(s, ada)).toBe(false)
		expect(s.pit.Open[ada]).toBeNil()
	end)
end)

describe("a practice duel, run", function()
	it("is fought first to two, unranked, and pays half the duel's win, never touching the rank", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		local profile = s.data.get(ada)
		local rank = deepCopy(profile.Rank)
		local stats = deepCopy(profile.Stats)
		local folios = profile.Currency.Folios
		fight(s, ada)
		expect(s.pit.Live[ada]).toBe(true)
		expect(last(s, "MatchChanged", ada).ModeId).toBe(DEF.Id)
		win(s, ada)
		local outcome = last(s, "MatchEnded", ada)
		expect(outcome.ModeId).toBe(DEF.Id)
		expect(outcome.Won).toBe(true)
		expect(outcome.Scores).toEqual({ 2, 0 })
		expect(outcome.Xp).toBe(math.floor(ProgressionConfig.XP.MatchWin * SPAR.RewardFactor + 0.5))
		expect(outcome.Folios).toBe(math.floor(ProgressionConfig.Folios.MatchWin * SPAR.RewardFactor + 0.5))
		expect(outcome.RankKeyBefore).toBe("")
		expect(outcome.FirstWinOfDay).toBe(false)
		expect(profile.Currency.Folios).toBe(folios + outcome.Folios)
		expect(s.xp).toEqual({ outcome.Xp })
		-- The spec the story asks for: a spar never writes Rank.Modes, nor anything of the rank.
		expect(profile.Rank).toEqual(rank)
		expect(profile.Stats).toEqual(stats)
		expect(profile.Daily.SparPaid).toBe(1)
		expect(profile.Daily.SparDay).toBe(DailyStreak.dayIndex(os.time()))
		-- The result shown, it ends: the HUD let go, the player home, the pit given back, still in the queue.
		s.world:advance(DEF.ResultSeconds + 0.2)
		expect(last(s, "MatchChanged", ada)).toBeNil()
		expect(s.teleported).toEqual({ ada })
		expect(s.pit.Open[ada]).toBeNil()
		expect((s.matchmaking.waiting(ada))).toBe(DUEL)
	end)

	it("pays nothing past the day's three paid spars, and says so", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		local daily = s.data.get(ada).Daily
		daily.SparDay = DailyStreak.dayIndex(os.time())
		daily.SparPaid = SPAR.PaidPerDay
		local folios = s.data.get(ada).Currency.Folios
		s.world:advance(1.1)
		expect(last(s, "SparChanged", ada).PaidLeft).toBe(0)
		fight(s, ada)
		win(s, ada)
		local outcome = last(s, "MatchEnded", ada)
		expect(outcome.Xp).toBe(0)
		expect(outcome.Folios).toBe(0)
		expect(s.data.get(ada).Currency.Folios).toBe(folios)
		expect(#s.xp).toBe(0)
		expect(daily.SparPaid).toBe(SPAR.PaidPerDay)
		expect(noticed(s, ada, "spar.unpaid")).toBe(true)
	end)

	it("lets a human who arrives take over at the next round break, and not during the round", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		fight(s, ada)
		-- Bea arrives while the round is played: the queue scans, and pairs nobody.
		local bea = queued(s, 12, "Bea", MatchConfig.Matchmaking.TickSeconds * 2 + 0.2)
		expect(#s.matches).toBe(0)
		expect(sparring(s, ada)).toBe(true)
		-- The round ends: the next scan pairs them, and the spar ends before the match starts.
		downForger(s)
		s.world:advance(MatchConfig.Matchmaking.TickSeconds + 0.2)
		expect(#s.matches).toBe(1)
		expect(s.matches[1][1][1] == ada.UserId or s.matches[1][2][1] == ada.UserId).toBe(true)
		expect(#s.overlapped).toBe(0)
		expect(sparring(s, ada)).toBe(false)
		expect(noticed(s, ada, "spar.handover")).toBe(true)
		expect(count(s, "MatchEnded", ada)).toBe(0)
		expect(s.pit.Open[ada]).toBeNil()
		-- The match takes the body: the spar sends nobody home.
		expect(#s.teleported).toBe(0)
		expect(s.data.get(ada).Daily.SparPaid).toBe(0)
		expect(bea.Parent).never.toBeNil()
	end)

	it("sends home, still queued, a player handed over to a match that then refuses to start", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		fight(s, ada)
		queued(s, 12, "Bea", MatchConfig.Matchmaking.TickSeconds * 2 + 0.2)
		-- No arena free: the queue pairs them at the break, the spar ends, and the match refuses.
		s.refusing.On = true
		downForger(s)
		s.world:advance(MatchConfig.Matchmaking.TickSeconds + 0.2)
		expect(#s.matches).toBe(0)
		expect(sparring(s, ada)).toBe(false)
		expect(s.pit.Open[ada]).toBeNil()
		-- Nothing else would fetch them from an empty pit.
		expect(s.teleported).toEqual({ ada })
		expect((s.matchmaking.waiting(ada))).toBe(DUEL)
		expect(s.data.get(ada).Daily.SparPaid).toBe(0)
	end)

	it("is walked out of for nothing, back to the hub, still in the queue", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		fight(s, ada)
		s.handlers.LeaveSpar(ada)
		expect(sparring(s, ada)).toBe(false)
		expect(last(s, "MatchChanged", ada)).toBeNil()
		expect(count(s, "MatchEnded", ada)).toBe(0)
		expect(s.teleported).toEqual({ ada })
		expect(noticed(s, ada, "spar.left")).toBe(true)
		expect((s.matchmaking.waiting(ada))).toBe(DUEL)
		expect(s.data.get(ada).Daily.SparPaid).toBe(0)
	end)

	it("keeps its player in the queue however long it lasts, and the queue gives up only once it ends", function()
		local s = setup()
		-- Long alone first, then a spar of three drawn rounds on the timer.
		local ada = queued(s, 11, "Ada", 100)
		fight(s, ada)
		local limit = MatchConfig.Matchmaking.MaxQueueSeconds
		s.world:advance(limit - 100 + 5)
		expect((s.matchmaking.waiting(ada))).toBe(DUEL)
		expect(sparring(s, ada)).toBe(true)
		s.world:advance(MAX_ROUNDS * (ROUND_SECONDS + ROUND_OVER + DEF.CountdownSeconds) + DEF.ResultSeconds)
		expect(sparring(s, ada)).toBe(false)
		s.world:advance(MatchConfig.Matchmaking.TickSeconds + 0.2)
		expect((s.matchmaking.waiting(ada))).toBeNil()
		expect(noticed(s, ada, "queue.timedOut")).toBe(true)
	end)

	it("ends, paying nothing, when a round's body cannot be loaded", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		fight(s, ada)
		ada.LoadCharacterAsync = function()
			error("the engine gave no body")
		end
		downForger(s)
		s.world:advance(ROUND_OVER + 0.2)
		expect(sparring(s, ada)).toBe(false)
		expect(noticed(s, ada, "spar.unavailable")).toBe(true)
		expect(s.pit.Open[ada]).toBeNil()
		expect(count(s, "MatchEnded", ada)).toBe(0)
		expect(s.teleported).toEqual({ ada })
		expect(s.data.get(ada).Daily.SparPaid).toBe(0)
	end)

	it("ends with its player, and gives the pit back", function()
		local s = setup()
		local ada = queued(s, 11, "Ada", 21)
		fight(s, ada)
		s.world:leave(ada)
		s.world:advance(0.2)
		expect(s.pit.Open[ada]).toBeNil()
		-- Nothing more is sent to a player who is gone: no round goes on for them.
		local sent = #s.fired
		s.world:advance(2)
		expect(#s.fired).toBe(sent)
	end)
end)

describe("what a practice duel may touch", function()
	it("never names the rank, the ranking, the quests, the first win or the matches played", function()
		local source = (fs.readFile("src/server/Services/SparService.luau"):gsub("%-%-[^\n]*", ""))
		for _, banned in ipairs({ ".Rank", "Ranking", "Quest", "markFirstWin", "MatchesPlayed", "Elo" }) do
			if source:find(banned, 1, true) ~= nil then
				error(("SparService names %s: a spar is practice against the server"):format(banned))
			end
		end
	end)

	it("is taken and left by two remotes, each guarded and rate-limited, with no argument", function()
		local remotes = fs.readFile("src/shared/Remotes.luau")
		for _, name in ipairs({ "StartSpar", "LeaveSpar" }) do
			local definition = remotes:match("\n\t" .. name .. " = (%b{})")
			assert(definition ~= nil, name .. " is not a remote")
			expect(definition:find('Direction = "ClientToServer"', 1, true)).never.toBeNil()
			expect(definition:find("Args = {},", 1, true)).never.toBeNil()
			expect(definition:find("Rate = { Capacity = 2, Refill = 0.2 }", 1, true)).never.toBeNil()
		end
	end)
end)

return nil
