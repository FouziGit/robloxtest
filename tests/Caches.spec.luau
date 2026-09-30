--!strict
-- What a long-lived server remembers per player, and what survives a server hop (E9-S7, D-222).
--
-- Three memories grew for the life of a server, one entry per player it ever saw: RankingService's last known
-- ratings and debited forfeits, and LeaderboardService's usernames. The first two now keep only the rosters of the
-- live ranked matches (Pure/RatingMemory, held by MatchService from a match's start to its end); the names are a
-- least-recently-used cache of RankingConfig.Leaderboard.NameCacheSize. The opposite fault was the practice's gap
-- against the Erasure: kept in a server's memory, it reset on a hop to another server. It is in the profile's Daily
-- section now.
local Engine = require("./engine")
local Harness = require("./harness")
local Lru = require("../src/server/Pure/Lru")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local RatingMemory = require("../src/server/Pure/RatingMemory")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function count(map: { [any]: any }): number
	local n = 0
	for _ in pairs(map) do
		n += 1
	end
	return n
end

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""):gsub("%s+", " "))
end

----------------------------------------------------------------
-- The ranked rosters
----------------------------------------------------------------

describe("RatingMemory, over a thousand ranked players", function()
	-- A deterministic stream of duels: up to twenty at once, a third with a player who walks out, one in ten ending
	-- with no result at all (abandoned by both, or cancelled), and the leaderboard asking about players in no match.
	local PLAYERS = 1000
	local MATCHES = 3000
	local MODE = "Duel1v1"

	-- Runs the whole stream on a fresh memory and returns it, with the most it ever held at once. Throws on the first
	-- moment it remembers more ratings or forfeits than there are live participants.
	local function simulate(): (RatingMemory.Memory, { Ratings: number, Settled: number })
		local seed = 7
		local function roll(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n + 1
		end

		type Live = { Id: string, Users: { number }, Leaver: number? }

		local memory = RatingMemory.new()
		local busy: { [number]: boolean } = {}
		local live: { Live } = {}
		local worst = { Ratings = 0, Settled = 0 }

		local function liveParticipants(): number
			local held = 0
			for _ in pairs(busy) do
				held += 1
			end
			return held
		end

		local function measure()
			local ratings = count(memory.Ratings[MODE] or {})
			local settled = count(memory.Settled)
			local participants = liveParticipants()
			if ratings > participants or settled > participants then
				error(
					("%d ratings and %d forfeits remembered for %d live participants"):format(
						ratings,
						settled,
						participants
					)
				)
			end
			worst.Ratings = math.max(worst.Ratings, ratings)
			worst.Settled = math.max(worst.Settled, settled)
		end

		local function start(index: number)
			local users: { number } = {}
			while #users < 2 do
				local candidate = roll(PLAYERS)
				if not busy[candidate] and table.find(users, candidate) == nil then
					table.insert(users, candidate)
				end
			end
			local match: Live = { Id = "Duel1v1-" .. index, Users = users, Leaver = nil }
			for _, userId in ipairs(users) do
				busy[userId] = true
				RatingMemory.hold(memory, match.Id, userId)
				RatingMemory.remember(memory, MODE, userId, 900 + userId)
			end
			if roll(3) == 1 then
				local leaver = users[roll(2)]
				match.Leaver = leaver
				RatingMemory.remember(memory, MODE, leaver, 880 + leaver)
				RatingMemory.settle(memory, leaver, match.Id)
			end
			table.insert(live, match)
		end

		local function finish(match: Live)
			if roll(10) ~= 1 then
				-- A result: the leaver's forfeit is consumed, the others move.
				for _, userId in ipairs(match.Users) do
					if not RatingMemory.consume(memory, userId, match.Id) then
						RatingMemory.remember(memory, MODE, userId, 950 + userId)
					end
				end
			end
			RatingMemory.release(memory, match.Id)
			for _, userId in ipairs(match.Users) do
				busy[userId] = nil
			end
		end

		for index = 1, MATCHES do
			start(index)
			-- The leaderboard and the queue read ratings of players in no match: nothing is kept for them.
			local idle = roll(PLAYERS)
			if not busy[idle] then
				RatingMemory.remember(memory, MODE, idle, 1234)
			end
			measure()
			if #live >= 20 or roll(2) == 1 then
				finish(table.remove(live, roll(#live)) :: Live)
				measure()
			end
		end
		while #live > 0 do
			finish(table.remove(live) :: Live)
			measure()
		end
		return memory, worst
	end

	it("never remembers more ratings or forfeits than there are live participants", function()
		-- measure() throws on the first breach; this proves it ran on a real load.
		local _, worst = simulate()
		expect(worst.Ratings).toBeGreaterThan(10)
		expect(worst.Settled).toBeGreaterThan(0)
	end)

	it("forgets everybody once no match is live", function()
		local memory = simulate()
		expect(count(memory.Ratings[MODE] or {})).toBe(0)
		expect(count(memory.Settled)).toBe(0)
		expect(count(memory.Holders)).toBe(0)
	end)

	it("keeps a player two live matches hold until both are over", function()
		local fresh = RatingMemory.new()
		RatingMemory.hold(fresh, "A", 5)
		RatingMemory.hold(fresh, "B", 5)
		RatingMemory.remember(fresh, MODE, 5, 1300)
		RatingMemory.settle(fresh, 5, "A")
		RatingMemory.release(fresh, "A")
		expect(RatingMemory.known(fresh, MODE, 5)).toBe(1300)
		-- A's forfeit went with A: no result of A will ever come to consume it.
		expect(RatingMemory.isSettled(fresh, 5, "A")).toBe(false)
		RatingMemory.release(fresh, "B")
		expect(RatingMemory.known(fresh, MODE, 5)).toBeNil()
	end)

	it("debits a forfeit once, and skips it in the result once", function()
		local fresh = RatingMemory.new()
		RatingMemory.hold(fresh, "A", 9)
		RatingMemory.settle(fresh, 9, "A")
		expect(RatingMemory.isSettled(fresh, 9, "A")).toBe(true)
		expect(RatingMemory.isSettled(fresh, 9, "B")).toBe(false)
		expect(RatingMemory.consume(fresh, 9, "A")).toBe(true)
		expect(RatingMemory.consume(fresh, 9, "A")).toBe(false)
		-- Nobody holds user 42: nothing is kept for them, a rating or a forfeit.
		RatingMemory.settle(fresh, 42, "Z")
		RatingMemory.remember(fresh, "Duel1v1", 42, 1500)
		expect(RatingMemory.isSettled(fresh, 42, "Z")).toBe(false)
		expect(RatingMemory.known(fresh, "Duel1v1", 42)).toBeNil()
	end)
end)

describe("RankingService", function()
	it("remembers a roster from its match's start to its end, and nobody else", function()
		local players = Engine.instance("Players")
		players.GetPlayerByUserId = function(self: any, userId: number): any
			for _, each in ipairs(self:GetChildren()) do
				if each.UserId == userId then
					return each
				end
			end
			return nil
		end
		local world = Engine.world({ Services = { Players = players } })
		local profiles: { [any]: any } = {}
		local function player(userId: number, rating: number): any
			local each = Engine.instance("Player", players)
			each.Name = "P" .. userId
			each.UserId = userId
			profiles[each] = {
				Rank = {
					Modes = { Duel1v1 = { Rating = rating, Matches = 30, Wins = 15, Losses = 15, PeakRating = rating } },
				},
			}
			return each
		end
		local stays, leaves, idle = player(1, 1400), player(2, 1600), player(3, 1800)
		local RankingService = world.require("src/server/Services/RankingService")
		RankingService.Init({
			DataService = {
				get = function(who: any)
					return profiles[who]
				end,
				push = function() end,
				ProfileLoaded = Engine.signal(),
			},
			Currency = { add = function() end },
			Cosmetic = {
				grant = function()
					return true
				end,
			},
			Notify = { send = function() end },
		} :: any)
		local initial = RankingConfig.InitialRating

		-- Asked about while in no match: nothing kept.
		RankingService.getRating(idle, "Duel1v1")
		expect(RankingService.lastKnownRating("Duel1v1", 3)).toBe(initial)

		RankingService.hold("Duel1v1-1", "Duel1v1", { stays, leaves })
		expect(RankingService.lastKnownRating("Duel1v1", 1)).toBe(1400)
		expect(RankingService.lastKnownRating("Duel1v1", 2)).toBe(1600)

		-- The leaver's forfeit is debited once, however many times it is asked for.
		local debit = RankingService.applyAbandon(leaves, "Duel1v1-1", "Duel1v1", 1400)
		expect(debit).never.toBeNil()
		expect(RankingService.applyAbandon(leaves, "Duel1v1-1", "Duel1v1", 1400)).toBeNil()
		leaves.Parent = nil
		-- Gone from the server, still scored at the rating they had.
		expect(RankingService.lastKnownRating("Duel1v1", 2)).toBe(debit.After)

		RankingService.release("Duel1v1-1")
		expect(RankingService.lastKnownRating("Duel1v1", 1)).toBe(initial)
		expect(RankingService.lastKnownRating("Duel1v1", 2)).toBe(initial)
	end)

	it("is held and released by every match MatchService starts, whatever ends it", function()
		local match = code("src/server/Services/MatchService.luau")
		expect(match).toContain('log.try("Ranking.hold " .. match.Id, ranking.hold, match.Id, def.Id, roster)')
		-- On the match's Trove: finish and cancel both destroy it.
		expect(match).toContain(
			'trove:Add(function() log.try("Ranking.release " .. match.Id, ranking.release, match.Id) end)'
		)
		local ranking = code("src/server/Services/RankingService.luau")
		expect(ranking).toContain("local memory = RatingMemory.new()")
		expect(ranking:find("lastRating", 1, true)).toBeNil()
		expect(ranking:find("settled[", 1, true)).toBeNil()
	end)
end)

----------------------------------------------------------------
-- The leaderboard's names
----------------------------------------------------------------

describe("the leaderboard's names", function()
	it("are capped at 500, the least recently used let go first", function()
		expect(RankingConfig.Leaderboard.NameCacheSize).toBe(500)
		local names = Lru.new(RankingConfig.Leaderboard.NameCacheSize)
		for userId = 1, 1000 do
			Lru.set(names, userId, "P" .. userId)
			-- A name read on every refresh stays however many others arrive.
			expect(Lru.get(names, 1)).toBe("P1")
			expect(names.Size).toBeLessThanOrEqual(500)
		end
		expect(names.Size).toBe(500)
		expect(Lru.get(names, 1)).toBe("P1")
		expect(Lru.get(names, 2)).toBeNil()
		expect(Lru.get(names, 501)).toBeNil()
		expect(Lru.get(names, 502)).toBe("P502")
		expect(Lru.get(names, 1000)).toBe("P1000")
		-- A rename overwrites in place and costs no other entry.
		Lru.set(names, 1000, "Renamed")
		expect(names.Size).toBe(500)
		expect(Lru.get(names, 1000)).toBe("Renamed")
	end)

	it("keeps its list whole through every move", function()
		local cache = Lru.new(3)
		for _, step in ipairs({ 1, 2, 3, 1, 4, 2, 5, 5, 3 }) do
			Lru.set(cache, step, step)
			local forward, node = 0, cache.Newest
			local last = nil
			while node ~= nil do
				forward += 1
				last = node
				node = node.Older
			end
			expect(forward).toBe(cache.Size)
			-- Compared, never printed: a node links to its neighbours both ways.
			expect(last == cache.Oldest).toBe(true)
		end
		expect(cache.Size).toBe(3)
	end)

	it("are the only per-player memory LeaderboardService keeps of names", function()
		local board = code("src/server/Services/LeaderboardService.luau")
		expect(board).toContain(
			"local names: Lru.Cache<number, string> = Lru.new(RankingConfig.Leaderboard.NameCacheSize)"
		)
		expect(board:find("names[", 1, true)).toBeNil()
	end)
end)

----------------------------------------------------------------
-- The practice's gap
----------------------------------------------------------------

describe("the practice's gap against the Erasure", function()
	local GAP = WorldBossConfig.Practice.RewardGapSeconds

	-- A server: its own world and its own Rewards module, paying `profile`'s owner for a practice they fought alone.
	local function server(profile: any): (any, () -> (), { string })
		local players = Engine.instance("Players")
		players.GetPlayerByUserId = function(self: any, userId: number): any
			for _, each in ipairs(self:GetChildren()) do
				if each.UserId == userId then
					return each
				end
			end
			return nil
		end
		local world = Engine.world({ Services = { Players = players } })
		local player = Engine.instance("Player", players)
		player.Name = "Scribe"
		player.UserId = 77
		local told: { string } = {}
		local credited = { Folios = 0 }
		local deps = {
			DataService = {
				get = function()
					return profile
				end,
				push = function() end,
			},
			Notify = {
				send = function(_player: any, key: string)
					table.insert(told, key)
				end,
			},
			Progression = {
				addXp = function(_player: any, amount: number): number
					return amount
				end,
			},
			Currency = {
				add = function(_player: any, amount: number): number
					credited.Folios += amount
					return amount
				end,
			},
		}
		local Rewards = world.require("src/server/Services/WorldBossService/Rewards")
		local WorldBossMode = world.require("src/server/GameModes/WorldBossMode")
		local function pay()
			local state = WorldBossMode.newState(1, 0, 1000)
			WorldBossMode.recordDamage(state, 77, 1000)
			Rewards.pay({ Deps = deps :: any, State = state, Participants = { 77 }, Kind = "Practice" })
		end
		return credited, pay, told
	end

	local function profile(): any
		return {
			Daily = {
				LastClaimDay = 0,
				Streak = 0,
				FirstWinDay = 0,
				PremiumBonusDay = 0,
				ForgerDay = 0,
				ForgerFolios = 0,
				PracticeDay = 0,
				PracticePaid = 0,
				PracticeLastPaidAt = 0,
			},
		}
	end

	it("is written in the profile when a practice pays", function()
		local saved = profile()
		local credited, pay = server(saved)
		local before = os.time()
		pay()
		expect(credited.Folios).toBeGreaterThan(0)
		expect(saved.Daily.PracticeLastPaidAt).toBeGreaterThanOrEqual(before)
		expect(saved.Daily.PracticePaid).toBe(1)
	end)

	it("holds after a rejoin on another server", function()
		local saved = profile()
		local _, payHere = server(saved)
		payHere()
		-- The same profile, loaded by a server that never saw this player pay.
		local credited, payThere, told = server(saved)
		payThere()
		expect(credited.Folios).toBe(0)
		expect(told).toContain("boss.practice.noReward")
		expect(saved.Daily.PracticePaid).toBe(1)
	end)

	it("lets a practice pay again once the gap has run, wherever it is fought", function()
		local saved = profile()
		saved.Daily.PracticeLastPaidAt = os.time() - GAP
		saved.Daily.PracticePaid = 0
		local credited, pay = server(saved)
		pay()
		expect(credited.Folios).toBeGreaterThan(0)
	end)

	it("starts at zero on a new profile, and is part of the Daily section", function()
		-- The Trials' counts follow it in the section since the wave 2 merge (D-243), and the match Folios' since
		-- the wave 3 merge (D-255).
		expect(code("src/server/Services/DataService.luau")).toContain(
			"PracticePaid = 0, PracticeLastPaidAt = 0, TrialDay = 0, TrialKills = 0, TrialFolios = 0, "
				.. "MatchDay = 0, MatchFolios = 0, },"
		)
		expect(code("src/shared/Types.luau")).toContain("PracticeLastPaidAt: number,")
		expect(code("src/server/Services/WorldBossService/init.luau"):find("lastPaidAt", 1, true)).toBeNil()
	end)
end)
