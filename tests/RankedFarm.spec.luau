--!strict
-- Two accounts farming each other in ranked, and the honest rematch series that must not pay for it (E4-S3,
-- D-255). A main and an alt queue together, the alt walks out on the countdown, the main takes the forfeit:
-- twenty times a sitting, that was twenty wins of Elo, Folios and quests for nothing played. DataService,
-- RankingService and MatchService run for real in a pretend server (tests/server.luau); the rules are
-- MatchConfig.MinPlayedSeconds, MatchConfig.DailyFolioCap and RankingConfig.Opponents.
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Elo = require("../src/server/Pure/Elo")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Server = require("./server")
local ZoneConfig = require("../src/shared/Config/ZoneConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
local TEAM = MatchConfig.Modes.Team3v3
local GRACE = GameConfig.Server.LeaveGraceSeconds
local FULL = RankingConfig.Opponents.FullMatchesPerDay
-- The honest series the rule must leave whole: a duel, and five rematches by Play again.
local SERIES = 1 + 5
local SCALE = RankingConfig.Opponents.RepeatRewardScale
local BOUNDS = { Floor = RankingConfig.RatingFloor, Ceiling = RankingConfig.RatingCeiling }
local WIN_FOLIOS = ProgressionConfig.Folios.MatchWin
local KILL_FOLIOS = ProgressionConfig.Folios.PlayerKill
local KILL_XP = ProgressionConfig.XP.PlayerKill

local function today(): number
	return DailyStreak.dayIndex(os.time())
end

local function rating(setup: Server.Services, player: any): number
	local entry = setup.data.get(player).Rank.Modes[DUEL.Id]
	return if entry ~= nil then entry.Rating else RankingConfig.InitialRating
end

-- The K factor a duel of `player` is scored with now, from the matches their profile has played.
local function kFactor(setup: Server.Services, player: any): number
	local entry = setup.data.get(player).Rank.Modes[DUEL.Id]
	return Elo.kFactor(if entry ~= nil then entry.Matches else 0, RankingConfig.KFactorSchedule)
end

local function folios(setup: Server.Services, player: any): number
	return setup.data.get(player).Currency.Folios
end

local function reported(setup: Server.Services, player: any, event: string): number
	local count = 0
	for _, report in ipairs(setup.reports) do
		if report.Player.UserId == player.UserId and report.Event == event then
			count += report.Amount
		end
	end
	return count
end

-- The XP of `player`'s last grant for `reason`.
local function lastXp(setup: Server.Services, player: any, reason: string): number?
	local amount: number? = nil
	for _, gain in ipairs(setup.gains) do
		if gain.Player.UserId == player.UserId and gain.Reason == reason then
			amount = gain.Amount
		end
	end
	return amount
end

local function told(setup: Server.Services, player: any, key: string): number
	local count = 0
	for _, notice in ipairs(setup.notices) do
		if notice.Player.UserId == player.UserId and notice.Key == key then
			count += 1
		end
	end
	return count
end

-- A player past the quick duel (E10-S7, D-269), at the level and with the matches ranked asks for: their matches are
-- ranked, so the farm rules have a rating to hold. Again on every return, whatever the profile kept.
local function join(setup: Server.Services, userId: number, name: string): any
	local player = setup.world:join(userId, name)
	local data = setup.data.get(player)
	assert(data ~= nil, "no profile loaded for " .. name)
	data.Stats.MatchesPlayed = math.max(data.Stats.MatchesPlayed, MatchConfig.Newcomer.MinMatches)
	data.Progression.Level = math.max(data.Progression.Level, MatchConfig.Newcomer.MinLevel)
	return player
end

-- A duel between `a` and `b`, past its countdown: the first round is being played.
local function begin(setup: Server.Services, a: any, b: any)
	expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBeNil()
	setup.world:advance(DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(a).Phase).toBe("Playing")
end

-- The duel is fought: a hit each way, and the rounds played past MatchConfig.MinPlayedSeconds.
local function fight(setup: Server.Services, a: any, b: any)
	setup.hit(a, b, 10)
	setup.hit(b, a, 10)
	setup.world:advance(MatchConfig.MinPlayedSeconds)
end

local function knockOut(setup: Server.Services, player: any)
	player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.world:advance(0.2)
end

-- `winner` takes the duel 2-0 on the field, and both press Play again on the result: the next duel can start.
local function winSeries(setup: Server.Services, winner: any, loser: any)
	knockOut(setup, loser)
	setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(winner).Phase).toBe("Playing")
	knockOut(setup, loser)
	setup.world:advance(MatchConfig.RoundOverSeconds + 0.2)
	expect(setup.match.getMatch(winner).Phase).toBe("Result")
	expect(setup.match.releaseFromResult(winner)).toBe(true)
	expect(setup.match.releaseFromResult(loser)).toBe(true)
end

-- The alt walks out; the forfeit is judged once the grace has run, the main presses Play again on a result, and
-- the alt comes back for the next one.
local function altWalksOut(setup: Server.Services, main: any, alt: any): any
	setup.world:leave(alt)
	setup.world:advance(GRACE + 1)
	if setup.match.isFinishing(main) then
		expect(setup.match.releaseFromResult(main)).toBe(true)
	end
	expect(setup.match.isInMatch(main)).toBe(false)
	return join(setup, alt.UserId, alt.Name)
end

describe("a main and an alt farming ranked (E4-S3)", function()
	it("earns nothing in twenty rounds of the alt leaving on the countdown", function()
		local setup = Server.services()
		local main = join(setup, 401, "Main")
		local alt = join(setup, 402, "Alt")
		for _ = 1, 20 do
			expect(setup.match.start(DUEL.Id, { { main.UserId }, { alt.UserId } })).never.toBeNil()
			setup.world:advance(1)
			expect(setup.match.getMatch(main).Phase).toBe("Countdown")
			alt = altWalksOut(setup, main, alt)
		end
		expect(rating(setup, main)).toBe(RankingConfig.InitialRating)
		expect(folios(setup, main)).toBeLessThanOrEqual(MatchConfig.DailyFolioCap)
		expect(folios(setup, main)).toBe(0)
		expect(reported(setup, main, "MatchWin")).toBe(0)
		expect(reported(setup, main, "MatchPlayed")).toBe(0)
		expect(told(setup, main, "match.voided")).toBe(20)
		-- The one who walked out paid for every one of them.
		local alts = setup.data.get(alt).Rank.Modes[DUEL.Id]
		expect(alts.Losses).toBe(20)
		expect(alts.Rating < RankingConfig.InitialRating).toBe(true)
	end)

	it(
		"moves the pair's Elo for the day's full matches when the alt fights, then holds it, under the Folio cap",
		function()
			-- The farm that plays along: thirty seconds, a hit each way, then the alt walks out. Every one is a real
			-- forfeit, and only the day's first few move a rating.
			local setup = Server.services()
			local main = join(setup, 411, "Main")
			local alt = join(setup, 412, "Alt")
			local ratings: { number } = {}
			for _ = 1, 20 do
				begin(setup, main, alt)
				fight(setup, main, alt)
				alt = altWalksOut(setup, main, alt)
				table.insert(ratings, rating(setup, main))
			end
			expect(ratings[1] > RankingConfig.InitialRating).toBe(true)
			for index = 2, FULL do
				expect(ratings[index] > ratings[index - 1]).toBe(true)
			end
			for index = FULL + 1, 20 do
				expect(ratings[index]).toBe(ratings[FULL])
			end
			local expected = FULL * WIN_FOLIOS + (20 - FULL) * math.floor(WIN_FOLIOS * SCALE + 0.5)
			expect(folios(setup, main)).toBe(expected)
			expect(folios(setup, main)).toBeLessThanOrEqual(MatchConfig.DailyFolioCap)
			expect(told(setup, main, "match.repeatOpponent")).toBe(20 - FULL)
			expect(setup.data.get(main).Rank.Opponents).toEqual({ Day = today(), Counts = { ["412"] = 20 } })
		end
	)

	it("keeps counting the pair on another server, and starts over on a new UTC day", function()
		local setup = Server.services()
		local main = join(setup, 421, "Main")
		local alt = join(setup, 422, "Alt")
		for _ = 1, FULL do
			begin(setup, main, alt)
			fight(setup, main, alt)
			alt = altWalksOut(setup, main, alt)
		end
		-- The main hops: the count comes back with the profile.
		setup.world:leave(main)
		setup.world:advance(GRACE + 1)
		main = join(setup, 421, "Main")
		local held = rating(setup, main)
		begin(setup, main, alt)
		fight(setup, main, alt)
		alt = altWalksOut(setup, main, alt)
		expect(rating(setup, main)).toBe(held)
		-- Yesterday's count is no count at all.
		setup.data.get(main).Rank.Opponents.Day = today() - 1
		begin(setup, main, alt)
		fight(setup, main, alt)
		altWalksOut(setup, main, alt)
		expect(rating(setup, main) > held).toBe(true)
	end)
end)

describe("an honest rematch series (E4-S3)", function()
	it("keeps every point of Elo over a duel and five rematches by Play again, with damage traded", function()
		local setup = Server.services()
		local a = join(setup, 431, "Ada")
		local b = join(setup, 432, "Bea")
		expect(FULL >= SERIES).toBe(true)
		for match = 1, FULL do
			local winner, loser = if match % 2 == 1 then a else b, if match % 2 == 1 then b else a
			local winnerBefore, loserBefore = rating(setup, winner), rating(setup, loser)
			local winnerK = kFactor(setup, winner)
			local loserK = kFactor(setup, loser)
			begin(setup, a, b)
			fight(setup, a, b)
			winSeries(setup, winner, loser)
			expect(rating(setup, winner)).toBe(Elo.update(winnerBefore, loserBefore, 1, winnerK, winnerK, BOUNDS))
			expect(rating(setup, loser)).toBe(Elo.update(loserBefore, winnerBefore, 0, loserK, loserK, BOUNDS))
			expect(lastXp(setup, winner, "MatchWin")).toBe(ProgressionConfig.XP.MatchWin)
		end
		expect(told(setup, a, "match.repeatOpponent")).toBe(0)
		expect(told(setup, b, "match.repeatOpponent")).toBe(0)
		-- One more is past the day's full matches: played, counted, paid a quarter, and neither rating moves.
		local aBefore, bBefore, foliosBefore = rating(setup, a), rating(setup, b), folios(setup, a)
		local winsBefore = setup.data.get(a).Rank.Modes[DUEL.Id].Wins
		begin(setup, a, b)
		fight(setup, a, b)
		winSeries(setup, a, b)
		expect(rating(setup, a)).toBe(aBefore)
		expect(rating(setup, b)).toBe(bBefore)
		expect(setup.data.get(a).Rank.Modes[DUEL.Id].Wins).toBe(winsBefore + 1)
		expect(folios(setup, a) - foliosBefore).toBe(math.floor(WIN_FOLIOS * SCALE + 0.5))
		expect(lastXp(setup, a, "MatchWin")).toBe(math.floor(ProgressionConfig.XP.MatchWin * SCALE + 0.5))
		expect(lastXp(setup, b, "MatchLoss")).toBe(math.floor(ProgressionConfig.XP.MatchLoss * SCALE + 0.5))
		expect(told(setup, a, "match.repeatOpponent")).toBe(1)
		expect(told(setup, b, "match.repeatOpponent")).toBe(1)
	end)
end)

describe("a forfeit nobody fought is void (E4-S3)", function()
	it("gives whoever stayed nothing, debits whoever left, and lets the survivor go at once", function()
		local setup = Server.services()
		local a = join(setup, 441, "Ada")
		local b = join(setup, 442, "Bea")
		begin(setup, a, b)
		setup.hit(a, b, 10)
		setup.hit(b, a, 10)
		setup.world:advance(MatchConfig.MinPlayedSeconds - 5)
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(setup.match.isInMatch(a)).toBe(false)
		expect(setup.data.get(a).Rank.Modes[DUEL.Id]).toBeNil()
		expect(folios(setup, a)).toBe(0)
		expect(reported(setup, a, "MatchWin")).toBe(0)
		expect(told(setup, a, "match.voided")).toBe(1)
		expect(setup.world.store.written["Player_442"].Rank.Modes[DUEL.Id].Losses).toBe(1)
		expect(setup.world:said("match Duel1v1-1 void")).toBe(true)
	end)

	it("lets the survivor of a walk-out on the countdown move and cast at once", function()
		local setup = Server.services()
		local a = join(setup, 445, "Ada")
		local b = join(setup, 446, "Bea")
		expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBeNil()
		setup.world:advance(1)
		setup.world:leave(b)
		setup.world:advance(GRACE + 0.5)
		-- Still inside what was the countdown's freeze: the void lifts it.
		expect(setup.match.isInMatch(a)).toBe(false)
		expect(setup.cast(a, "Brand")).toBe(true)
	end)

	it("is void however long it lasted when not a point of damage was exchanged", function()
		local setup = Server.services()
		local a = join(setup, 451, "Ada")
		local b = join(setup, 452, "Bea")
		begin(setup, a, b)
		setup.world:advance(MatchConfig.MinPlayedSeconds + 5)
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(setup.data.get(a).Rank.Modes[DUEL.Id]).toBeNil()
		expect(told(setup, a, "match.voided")).toBe(1)
	end)

	it("is a real forfeit once fought past the minimum: the one who stayed wins it", function()
		local setup = Server.services()
		local a = join(setup, 461, "Ada")
		local b = join(setup, 462, "Bea")
		begin(setup, a, b)
		fight(setup, a, b)
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(setup.match.getMatch(a).Phase).toBe("Result")
		expect(setup.data.get(a).Rank.Modes[DUEL.Id].Wins).toBe(1)
		expect(reported(setup, a, "MatchWin")).toBe(1)
		expect(folios(setup, a)).toBe(WIN_FOLIOS)
		expect(told(setup, a, "match.voided")).toBe(0)
	end)

	it("counts the play from the first round's start, not the latest one's", function()
		-- Round one fought past the minimum and won; the loser walks out as round two begins.
		local setup = Server.services()
		local a = join(setup, 475, "Ada")
		local b = join(setup, 476, "Bea")
		begin(setup, a, b)
		fight(setup, a, b)
		knockOut(setup, b)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		expect(setup.match.getMatch(a).Round).toBe(2)
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(setup.data.get(a).Rank.Modes[DUEL.Id].Wins).toBe(1)
		expect(told(setup, a, "match.voided")).toBe(0)
	end)

	it("never voids a series already won on the field (D-34)", function()
		local setup = Server.services()
		local a = join(setup, 471, "Ada")
		local b = join(setup, 472, "Bea")
		begin(setup, a, b)
		knockOut(setup, b)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		knockOut(setup, b)
		-- 2-0 in under the minimum and without a hit: the loser leaves during the pause before the result.
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(setup.data.get(a).Rank.Modes[DUEL.Id].Wins).toBe(1)
		expect(told(setup, a, "match.voided")).toBe(0)
	end)
end)

describe("a day of matches pays at most its Folio cap", function()
	it("pays what is left under the cap, then nothing, and says so; the count survives a hop", function()
		local setup = Server.services()
		local a = join(setup, 481, "Ada")
		local b = join(setup, 482, "Bea")
		local daily = setup.data.get(a).Daily
		daily.MatchDay = today()
		daily.MatchFolios = MatchConfig.DailyFolioCap - 10
		begin(setup, a, b)
		fight(setup, a, b)
		winSeries(setup, a, b)
		expect(folios(setup, a)).toBe(10)
		expect(told(setup, a, "match.folioCap")).toBe(1)
		setup.world:leave(a)
		setup.world:advance(GRACE + 1)
		a = join(setup, 481, "Ada")
		expect(setup.data.get(a).Daily.MatchFolios).toBe(MatchConfig.DailyFolioCap)
		begin(setup, a, b)
		fight(setup, a, b)
		winSeries(setup, a, b)
		expect(folios(setup, a)).toBe(10)
		expect(told(setup, a, "match.folioCap")).toBe(2)
		expect(reported(setup, a, "MatchWin")).toBe(2)
	end)
end)

-- `killer` takes `victim` down as CombatService reports a killing blow: the body dies, then Killed says whose it was.
local function takeDown(setup: Server.Services, killer: any, victim: any)
	victim.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.kill(killer, victim)
	setup.world:advance(0.2)
end

-- `winner` takes the duel 2-0 on the field, each round by a kill of their own: the result is on screen.
local function winByKills(setup: Server.Services, winner: any, loser: any)
	takeDown(setup, winner, loser)
	setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(winner).Phase).toBe("Playing")
	takeDown(setup, winner, loser)
	setup.world:advance(MatchConfig.RoundOverSeconds + 0.2)
	expect(setup.match.getMatch(winner).Phase).toBe("Result")
end

-- The last MatchEnded `player` was sent: what the Result shows them.
local function outcomeOf(setup: Server.Services, player: any): any
	local found = nil
	for _, event in ipairs(setup.fired) do
		if event.Name == "MatchEnded" and event.Player == player then
			found = event.Payload
		end
	end
	return found
end

describe("a match's kills are paid with its result, under its rules (E4-S3)", function()
	-- The farm the forfeit rules leave open: the alt stays and is knocked out twice a duel. Paid on the spot by
	-- CombatService, outside the private server's share, the repeated pair's quarter and the void, those kills paid
	-- the main 240 XP a duel without end.
	it("pays a 2-0's two kills with its result, under the day's cap, and nothing before it", function()
		local setup = Server.services()
		local a = join(setup, 483, "Ada")
		local b = join(setup, 484, "Bea")
		begin(setup, a, b)
		fight(setup, a, b)
		takeDown(setup, a, b)
		-- Told at once; paid with the result.
		expect(told(setup, a, "match.takedown")).toBe(1)
		expect(folios(setup, a)).toBe(0)
		expect(lastXp(setup, a, "PlayerKill")).toBeNil()
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		takeDown(setup, a, b)
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.2)
		expect(setup.match.getMatch(a).Phase).toBe("Result")
		expect(lastXp(setup, a, "PlayerKill")).toBe(2 * KILL_XP)
		expect(lastXp(setup, a, "MatchWin")).toBe(ProgressionConfig.XP.MatchWin)
		expect(folios(setup, a)).toBe(WIN_FOLIOS + 2 * KILL_FOLIOS)
		local daily = setup.data.get(a).Daily
		expect(daily.MatchDay).toBe(today())
		expect(daily.MatchFolios).toBe(WIN_FOLIOS + 2 * KILL_FOLIOS)
		-- The Result counts the kills with the rest of what the match paid.
		local outcome = outcomeOf(setup, a)
		expect(outcome.Xp).toBe(ProgressionConfig.XP.MatchWin + 2 * KILL_XP)
		expect(outcome.Folios).toBe(WIN_FOLIOS + 2 * KILL_FOLIOS)
		-- The loser killed nobody, and is paid for none.
		expect(lastXp(setup, b, "PlayerKill")).toBeNil()
	end)

	it("pays the kills what is left under the cap once the result is paid, their XP in full", function()
		local setup = Server.services()
		local a = join(setup, 485, "Ada")
		local b = join(setup, 486, "Bea")
		local daily = setup.data.get(a).Daily
		daily.MatchDay = today()
		daily.MatchFolios = MatchConfig.DailyFolioCap - WIN_FOLIOS - 5
		begin(setup, a, b)
		fight(setup, a, b)
		winByKills(setup, a, b)
		expect(folios(setup, a)).toBe(WIN_FOLIOS + 5)
		expect(daily.MatchFolios).toBe(MatchConfig.DailyFolioCap)
		expect(told(setup, a, "match.folioCap")).toBe(1)
		expect(lastXp(setup, a, "PlayerKill")).toBe(2 * KILL_XP)
	end)

	it("pays a pair past its day's full matches a quarter of its kills, as of its result", function()
		local setup = Server.services()
		local a = join(setup, 490, "Ada")
		local b = join(setup, 498, "Bea")
		setup.data.get(a).Rank.Opponents = { Day = today(), Counts = { ["498"] = FULL } }
		begin(setup, a, b)
		fight(setup, a, b)
		winByKills(setup, a, b)
		expect(told(setup, a, "match.repeatOpponent")).toBe(1)
		expect(lastXp(setup, a, "PlayerKill")).toBe(math.floor(2 * KILL_XP * SCALE + 0.5))
		local expected = math.floor(WIN_FOLIOS * SCALE + 0.5) + math.floor(2 * KILL_FOLIOS * SCALE + 0.5)
		expect(folios(setup, a)).toBe(expected)
	end)

	it("pays no kill of a match nobody fought", function()
		-- The alt is knocked out once in the first seconds, then walks out on the next countdown: void (D-255).
		local setup = Server.services()
		local main = join(setup, 499, "Main")
		local alt = join(setup, 500, "Alt")
		begin(setup, main, alt)
		takeDown(setup, main, alt)
		setup.world:advance(MatchConfig.RoundOverSeconds + 1)
		expect(setup.match.getMatch(main).Phase).toBe("Countdown")
		setup.world:leave(alt)
		setup.world:advance(GRACE + 1)
		expect(told(setup, main, "match.voided")).toBe(1)
		expect(lastXp(setup, main, "PlayerKill")).toBeNil()
		expect(folios(setup, main)).toBe(0)
		expect(setup.data.get(main).Daily.MatchFolios).toBe(0)
	end)

	-- Found by review: CombatService credits a death to the last attacker for six seconds, and the pause after a round
	-- lasts three. The winner of a round pressed Reset on it and handed the loser a kill that changed no score: two
	-- kills a duel for the pair, the second for nothing played.
	it("pays no kill credited after the round's verdict: a winner's Reset on the pause is nobody's", function()
		local setup = Server.services()
		local a = join(setup, 503, "Ada")
		local b = join(setup, 504, "Bea")
		begin(setup, a, b)
		fight(setup, a, b)
		takeDown(setup, a, b)
		expect(setup.match.getMatch(a).Phase).toBe("RoundOver")
		-- The credit heard at once...
		takeDown(setup, b, a)
		expect(told(setup, b, "match.takedown")).toBe(0)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		expect(setup.match.getMatch(a).Phase).toBe("Playing")
		expect(setup.match.getMatch(a).Scores).toEqual({ 1, 0 })
		takeDown(setup, a, b)
		expect(setup.match.getMatch(a).Phase).toBe("RoundOver")
		-- ...and, on the last pause, heard only once a tick has seen the body fall.
		knockOut(setup, a)
		setup.kill(b, a)
		expect(told(setup, b, "match.takedown")).toBe(0)
		setup.world:advance(MatchConfig.RoundOverSeconds)
		expect(setup.match.getMatch(a).Phase).toBe("Result")
		expect(lastXp(setup, b, "PlayerKill")).toBeNil()
		expect(outcomeOf(setup, b).Folios).toBe(ProgressionConfig.Folios.MatchLoss)
		expect(lastXp(setup, a, "PlayerKill")).toBe(2 * KILL_XP)
	end)

	it("counts once a kill the round already judged, when CombatService names the killer after the verdict", function()
		-- A fall off the arena: the tick that kills under the kill zone gives the verdict too, and the death's Died,
		-- which CombatService credits from, comes after it.
		local setup = Server.services()
		local a = join(setup, 505, "Ada")
		local b = join(setup, 506, "Bea")
		begin(setup, a, b)
		fight(setup, a, b)
		knockOut(setup, b)
		expect(setup.match.getMatch(a).Phase).toBe("RoundOver")
		setup.kill(a, b)
		setup.kill(a, b)
		expect(told(setup, a, "match.takedown")).toBe(1)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		takeDown(setup, a, b)
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.2)
		expect(setup.match.getMatch(a).Phase).toBe("Result")
		expect(lastXp(setup, a, "PlayerKill")).toBe(2 * KILL_XP)
	end)

	it("pays nothing for a player the killer is not in a match with", function()
		local setup = Server.services()
		local a = join(setup, 487, "Ada")
		local b = join(setup, 488, "Bea")
		local c = join(setup, 489, "Cyd")
		c:LoadCharacterAsync()
		begin(setup, a, b)
		fight(setup, a, b)
		setup.kill(a, c)
		expect(told(setup, a, "match.takedown")).toBe(0)
		winSeries(setup, a, b)
		expect(lastXp(setup, a, "PlayerKill")).toBeNil()
		expect(folios(setup, a)).toBe(WIN_FOLIOS)
	end)

	it("leaves CombatService no part of a match's kill: two payers would pay it twice, one past every rule", function()
		expect(ZoneConfig.Rules.Match.CombatPaysKills).toBe(false)
		local combat = fs.readFile("src/server/Services/CombatService.luau")
		local onKill = string.match(combat, "\nfunction onKill%(.-\nend\n")
		expect(onKill).never.toBeNil()
		expect(string.find(onKill :: string, "DamageZones.combatPays(ZONE_RULES, zone)", 1, true)).never.toBeNil()
		expect(string.find(onKill :: string, "ProgressionConfig.Folios", 1, true)).toBeNil()
		expect(string.find(onKill :: string, "currency", 1, true)).toBeNil()
	end)
end)

describe("a 3v3 with a pair met too often (E4-S3)", function()
	it("holds the rating of both sides of that pair, and only theirs", function()
		local setup = Server.services()
		local team1 = { join(setup, 491, "A1"), join(setup, 492, "A2"), join(setup, 493, "A3") }
		local team2 = { join(setup, 494, "B1"), join(setup, 495, "B2"), join(setup, 496, "B3") }
		-- A1 has already played B1 the day's full matches; B1's own ledger knows nothing of it.
		setup.data.get(team1[1]).Rank.Opponents = { Day = today(), Counts = { ["494"] = FULL } }
		local ids = function(team: { any }): { number }
			local list = {}
			for _, player in ipairs(team) do
				table.insert(list, player.UserId)
			end
			return list
		end
		expect(setup.match.start(TEAM.Id, { ids(team1), ids(team2) })).never.toBeNil()
		setup.world:advance(TEAM.CountdownSeconds + 0.5)
		setup.hit(team1[2], team2[2], 10)
		setup.world:advance(MatchConfig.MinPlayedSeconds)
		for _, player in ipairs(team2) do
			player.Character:FindFirstChildOfClass("Humanoid").Health = 0
		end
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.5)
		expect(setup.match.getMatch(team1[1]).Phase).toBe("Result")
		local function teamRating(player: any): number
			return setup.data.get(player).Rank.Modes[TEAM.Id].Rating
		end
		expect(teamRating(team1[1])).toBe(RankingConfig.InitialRating)
		expect(teamRating(team2[1])).toBe(RankingConfig.InitialRating)
		expect(teamRating(team1[2]) > RankingConfig.InitialRating).toBe(true)
		expect(teamRating(team2[2]) < RankingConfig.InitialRating).toBe(true)
		-- Every participant still here now counts each of the three they faced.
		expect(setup.data.get(team2[1]).Rank.Opponents.Counts["491"]).toBe(1)
		expect(setup.data.get(team1[1]).Rank.Opponents.Counts["494"]).toBe(FULL + 1)
	end)
end)
