--!strict
-- RankingService: the only writer of ProfileData.Rank. Turns a finished ranked match into Elo ratings
-- with Pure/Elo (team rating, K factor decreasing with experience, floor / ceiling from
-- RankingConfig), keeps Matches / Wins / Losses / PeakRating, pushes "Rank" and announces every move
-- through RatingChanged so LeaderboardService can persist it on the season ladder.
--
-- A pair of players who meet again and again in one UTC day stops moving each other's rating once past
-- RankingConfig.Opponents.FullMatchesPerDay (D-255): every ranked result is written into both profiles'
-- Rank.Opponents (Pure/OpponentLedger), and a repeat is reported in its delta so MatchService pays it less.
--
-- It also runs the end-of-season pass. DataService resets Rank.Modes when GameConfig.SeasonId changes,
-- so the profile itself no longer knows what the player reached last season: the durable record is the
-- previous season's ladder, read once per player through LeaderboardService. Rank.LastRewardedSeason
-- is written before any payout and re-checked after the read, so a reward can never be granted twice.
--
-- In a private server a player bought, nothing here moves (Pure/ServerKind, E4-S4): its owner chooses who
-- fights, so no Elo is written and no rating reaches a ladder. RankingService.rankedHere says which it is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local DailyStreak = require(Shared.Pure.DailyStreak)
local Elo = require(script.Parent.Parent.Pure.Elo)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local OpponentLedger = require(script.Parent.Parent.Pure.OpponentLedger)
local RankTiers = require(Shared.Pure.RankTiers)
local RankedGate = require(Shared.Pure.RankedGate)
local RankingConfig = require(Shared.Config.RankingConfig)
local RatingMemory = require(script.Parent.Parent.Pure.RatingMemory)
local ServerKind = require(script.Parent.Parent.Pure.ServerKind)
local Signal = require(Packages.Signal)
local StudioConfig = require(script.Parent.Parent.Config.StudioConfig)
local Types = require(Shared.Types)

local log = Log.new("RankingService")

type ProfileData = Types.ProfileData
type RankModeData = Types.RankModeData
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
}
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> () }
-- CosmeticService owns Cosmetics.Owned (docs/DECISIONS.md D-26): it validates the id against
-- CosmeticConfig, dedupes, pushes the section and fires the signal the shop listens to.
type CosmeticApi = { grant: (player: Player, cosmeticId: string) -> boolean }
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
-- LeaderboardService owns the seasonal OrderedDataStores; `false` means the store could not be read.
type LeaderboardApi = {
	getArchivedValue: (seasonId: string, boardId: string, userId: number) -> (boolean, number?),
}
type Deps = {
	DataService: DataApi,
	Currency: CurrencyApi,
	Cosmetic: CosmeticApi,
	Notify: NotifyApi,
	Leaderboard: LeaderboardApi?,
}

-- Rating move of one participant, keyed by user id in the map applyResult returns. Repeat: the match was
-- past the day's full matches against one of their opponents, so the rating was held (D-255).
export type RatingDelta = {
	Before: number,
	After: number,
	RankKeyBefore: string,
	RankKeyAfter: string,
	Repeat: boolean,
}

-- One participant of a finished match: Entry and Rank are nil when the player already left (their profile is
-- released, so nothing can be written for them).
type Participant = { UserId: number, Player: Player?, Entry: RankModeData?, Rank: Types.RankData? }

local RANK_SECTION = "Rank"
-- Currency reason strings feed logs and telemetry only; they are never shown to a player.
local SEASON_REWARD_REASON = "SeasonReward"
-- Elo needs exactly two sides to score a result.
local TEAMS_PER_MATCH = 2

local BOUNDS: Elo.Bounds = { Floor = RankingConfig.RatingFloor, Ceiling = RankingConfig.RatingCeiling }
local OPPONENTS = RankingConfig.Opponents

local RankingService = {}

RankingService.RatingChanged = Signal.new() -- (player: Player, modeId: string, before: number, after: number)

local dataService: DataApi
local currency: CurrencyApi
local cosmeticService: CosmeticApi
local notify: NotifyApi
local leaderboard: LeaderboardApi?
-- Players whose end-of-season pass is reading the ladder: one attempt in flight at a time.
local rewarding: { [Player]: boolean } = {}
-- Whether ranked play counts on this server, read once at Init: a server never changes kind.
local rankedHere = true

----------------------------------------------------------------
-- Rank data
----------------------------------------------------------------

local function isRankedMode(modeId: string): boolean
	local mode = MatchConfig.Modes[modeId]
	return rankedHere and mode ~= nil and mode.Ranked
end

-- Of the players of the live ranked matches (MatchService holds them from start to end), the last rating this
-- server saw per mode, and the match whose forfeit is already debited (RatingMemory). A player who left mid-match is
-- gone from Players and their profile is released, so applyResult can no longer read their rating: without the
-- first, the opposing team was averaged against RankingConfig.InitialRating and the remaining player gained almost
-- nothing for beating a high-rated opponent who quit. The second is keyed by match, so applyAbandon can never debit
-- the same match twice for one player, whoever calls it again. Neither outlives the match: a long-lived server keeps
-- the rosters in play, not every ranked player it ever saw.
local memory = RatingMemory.new()

local function remember(modeId: string, userId: number, rating: number)
	RatingMemory.remember(memory, modeId, userId, rating)
end

local function knownRating(modeId: string, userId: number): number
	return RatingMemory.known(memory, modeId, userId) or RankingConfig.InitialRating
end

-- The player's entry for `modeId`, created at RankingConfig.InitialRating the first time it is needed.
local function modeEntry(data: ProfileData, modeId: string): RankModeData
	local existing = data.Rank.Modes[modeId]
	if existing ~= nil then
		return existing
	end
	local created: RankModeData = {
		Rating = RankingConfig.InitialRating,
		Matches = 0,
		Wins = 0,
		Losses = 0,
		PeakRating = RankingConfig.InitialRating,
	}
	data.Rank.Modes[modeId] = created
	return created
end

-- A match starts: its participants are held until it is released, each remembered at the rating their profile
-- holds now, so a roster average is still right once one of them has disconnected.
function RankingService.hold(matchId: string, modeId: string, players: { Player })
	for _, player in ipairs(players) do
		RatingMemory.hold(memory, matchId, player.UserId)
		RankingService.getRating(player, modeId)
	end
end

-- A match is over, however it ended: whoever it held and no other live match holds is forgotten.
function RankingService.release(matchId: string)
	RatingMemory.release(memory, matchId)
end

-- The rating this server last saw for `userId` in `modeId` while a live match held them,
-- RankingConfig.InitialRating otherwise. Unlike getRating this needs no live Player, so a roster average
-- stays right after somebody disconnects.
function RankingService.lastKnownRating(modeId: string, userId: number): number
	return knownRating(modeId, userId)
end

-- False in a private server a player bought: no match there moves a rating (applyResult and applyAbandon write
-- nothing), and MatchService pays its matches a share of their rewards.
function RankingService.rankedHere(): boolean
	return rankedHere
end

-- Whether `player` still plays the newcomer's quick duel (E10-S7, Pure/RankedGate): below MatchConfig.Newcomer's
-- level, or short of its matches. One answer for the queue (MatchmakingService, the newcomer's window) and the match
-- (MatchService, unranked). A player whose profile is not loaded is one, so the cap protects whoever the server cannot
-- tell about; in Studio, StudioConfig.RankedFromTheStart lets the test players play ranked.
function RankingService.isNewcomer(player: Player): boolean
	if RunService:IsStudio() and StudioConfig.RankedFromTheStart then
		return false
	end
	local data = dataService.get(player)
	if data == nil then
		return true
	end
	return not RankedGate.status(data.Stats.MatchesPlayed, data.Progression.Level, MatchConfig.Newcomer).Ranked
end

-- Strings key of the tier a rating sits in (single source of tier naming for every service).
function RankingService.rankKeyFor(rating: number): string
	return RankTiers.tierFor(rating, RankingConfig.Tiers).NameKey
end

-- Stored rating, or RankingConfig.InitialRating for a player who never played that mode (or whose
-- profile is not loaded yet), so matchmaking always has a number to work with.
function RankingService.getRating(player: Player, modeId: string): number
	local data = dataService.get(player)
	if data == nil then
		return RankingConfig.InitialRating
	end
	local mode = data.Rank.Modes[modeId]
	if mode == nil then
		return RankingConfig.InitialRating
	end
	remember(modeId, player.UserId, mode.Rating)
	return mode.Rating
end

----------------------------------------------------------------
-- Match results
----------------------------------------------------------------

-- The user ids a participant of `teamIndex` faced.
local function opponentIds(teams: { { Participant } }, teamIndex: number): { number }
	local ids: { number } = {}
	for _, opponent in ipairs(teams[TEAMS_PER_MATCH + 1 - teamIndex]) do
		table.insert(ids, opponent.UserId)
	end
	return ids
end

-- The participants for whom this match is a repeat: past the day's full matches against at least one player
-- they faced, by the higher of the two ledgers. Judged for everybody before any ledger takes this match, so
-- both sides of a pair read the same count.
local function repeatsOf(teams: { { Participant } }, today: number): { [number]: boolean }
	local repeats: { [number]: boolean } = {}
	for teamIndex, participants in ipairs(teams) do
		for _, participant in ipairs(participants) do
			local own = participant.Rank
			if own == nil then
				continue
			end
			for _, opponent in ipairs(teams[TEAMS_PER_MATCH + 1 - teamIndex]) do
				local theirs = if opponent.Rank ~= nil then opponent.Rank.Opponents else nil
				local meeting =
					OpponentLedger.meeting(own.Opponents, theirs, today, participant.UserId, opponent.UserId)
				if OpponentLedger.isRepeat(meeting, OPPONENTS.FullMatchesPerDay) then
					repeats[participant.UserId] = true
				end
			end
		end
	end
	return repeats
end

-- Applies a finished ranked match and returns the rating move of every participant still on the
-- server with a loaded profile, keyed by user id. A participant who already left counts at the last
-- rating this server saw for them, so the opposing team is scored against the opponent they actually
-- faced, and is absent from the result: callers treat a missing entry as "rating unchanged". Their own
-- loss was already written by applyAbandon at the moment they left.
-- An unranked mode (World Boss), any match of a server that is not ranked (rankedHere) and a match that did
-- not report two teams return an empty map.
function RankingService.applyResult(result: Types.MatchResult): { [number]: RatingDelta }
	local deltas: { [number]: RatingDelta } = {}
	if not isRankedMode(result.ModeId) then
		return deltas
	end
	if #result.Teams ~= TEAMS_PER_MATCH then
		log.warn("applyResult ignored: %s reported %d teams", result.ModeId, #result.Teams)
		return deltas
	end

	local teams: { { Participant } } = {}
	local teamRatings: { number } = {}
	for teamIndex, userIds in ipairs(result.Teams) do
		local participants: { Participant } = {}
		local ratings: { number } = {}
		for _, userId in ipairs(userIds) do
			local player = Players:GetPlayerByUserId(userId)
			local data = if player ~= nil then dataService.get(player) else nil
			local entry = if data ~= nil then modeEntry(data, result.ModeId) else nil
			local rank = if data ~= nil then data.Rank else nil
			table.insert(participants, { UserId = userId, Player = player, Entry = entry, Rank = rank })
			if entry ~= nil then
				remember(result.ModeId, userId, entry.Rating)
			end
			table.insert(ratings, if entry ~= nil then entry.Rating else knownRating(result.ModeId, userId))
		end
		teams[teamIndex] = participants
		teamRatings[teamIndex] = Elo.teamRating(ratings)
	end

	local today = DailyStreak.dayIndex(os.time())
	local repeats = repeatsOf(teams, today)
	local draw = result.WinnerTeam == nil
	for teamIndex, participants in ipairs(teams) do
		local opponentRating = teamRatings[TEAMS_PER_MATCH + 1 - teamIndex]
		local won = result.WinnerTeam == teamIndex
		local score = if draw then 0.5 elseif won then 1 else 0
		for _, participant in ipairs(participants) do
			local entry = participant.Entry
			local player = participant.Player
			if RatingMemory.consume(memory, participant.UserId, result.MatchId) then
				-- applyAbandon already debited THIS match for them when they left.
				continue
			end
			local rank = participant.Rank
			if entry == nil or player == nil or rank == nil then
				continue
			end
			rank.Opponents = OpponentLedger.record(rank.Opponents, today, opponentIds(teams, teamIndex))
			local repeated = repeats[participant.UserId] == true
			local before = entry.Rating
			local kFactor = Elo.kFactor(entry.Matches, RankingConfig.KFactorSchedule)
			-- A repeat is still a match played, won or lost: only the rating holds.
			local after = if repeated
				then before
				else Elo.update(before, opponentRating, score, kFactor, kFactor, BOUNDS)
			entry.Rating = after
			entry.Matches += 1
			if not draw then
				if won then
					entry.Wins += 1
				else
					entry.Losses += 1
				end
			end
			entry.PeakRating = math.max(entry.PeakRating, after)
			dataService.push(player, RANK_SECTION)
			deltas[participant.UserId] = {
				Before = before,
				After = after,
				RankKeyBefore = RankingService.rankKeyFor(before),
				RankKeyAfter = RankingService.rankKeyFor(after),
				Repeat = repeated,
			}
			remember(result.ModeId, participant.UserId, after)
			RankingService.RatingChanged:Fire(player, result.ModeId, before, after)
			log.info(
				"%s %s %d -> %d (k %d, opponent %.0f%s)",
				player.Name,
				result.ModeId,
				before,
				after,
				kFactor,
				opponentRating,
				if repeated then ", a repeat of today's pair: rating held" else ""
			)
		end
	end
	return deltas
end

-- Debits the forfeit of a ranked match the player is walking out of, while their profile is still
-- loaded. Returns the rating move, or nil when there is nothing to write.
--
-- Called from DataService.BeforeRelease, the final write of their session: after it the profile is gone
-- and nothing can ever be written for them on this server again, which is exactly how quitting used to be
-- free. The match resolves in their absence, applyResult skips them, and the opposing team is still scored
-- against the rating they actually had.
--
-- The loss is scored against `opponentRating` with the same Elo call a real defeat uses, so abandoning
-- costs the same as losing, never less: there is no cheaper exit than playing the match out.
function RankingService.applyAbandon(
	player: Player,
	matchId: string,
	modeId: string,
	opponentRating: number
): RatingDelta?
	if not isRankedMode(modeId) then
		return nil
	end
	if RatingMemory.isSettled(memory, player.UserId, matchId) then
		-- Already debited for this match.
		return nil
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("applyAbandon for %s (%s) came too late: the profile is already released", player.Name, modeId)
		return nil
	end
	local entry = modeEntry(data, modeId)
	local before = entry.Rating
	local kFactor = Elo.kFactor(entry.Matches, RankingConfig.KFactorSchedule)
	local after = Elo.update(before, opponentRating, 0, kFactor, kFactor, BOUNDS)
	entry.Rating = after
	entry.Matches += 1
	entry.Losses += 1
	entry.PeakRating = math.max(entry.PeakRating, after)
	dataService.push(player, RANK_SECTION)
	remember(modeId, player.UserId, after)
	RatingMemory.settle(memory, player.UserId, matchId)
	RankingService.RatingChanged:Fire(player, modeId, before, after)
	log.info(
		"%s abandoned %s: %d -> %d (k %d, opponent %.0f)",
		player.Name,
		modeId,
		before,
		after,
		kFactor,
		opponentRating
	)
	return {
		Before = before,
		After = after,
		RankKeyBefore = RankingService.rankKeyFor(before),
		RankKeyAfter = RankingService.rankKeyFor(after),
		Repeat = false,
	}
end

----------------------------------------------------------------
-- End-of-season rewards
----------------------------------------------------------------

-- GameConfig names the live season only; `GameConfig.PreviousSeasonId` (a string, added to the config
-- when the season is bumped) names the season that just ended. While it is absent — the first season —
-- there is nothing to pay and the pass below stays inert instead of guessing an id.
local function previousSeasonId(): string
	local configured = (GameConfig :: any).PreviousSeasonId
	if type(configured) == "string" and configured ~= "" and configured ~= GameConfig.SeasonId then
		return configured
	end
	return ""
end

-- Highest rating the player ended `seasonId` with, across ranked modes, read from that season's
-- ladders. Returns false when a store could not be read, so the pass retries on the next join instead
-- of marking the season done. Yields.
local function archivedRating(api: LeaderboardApi, seasonId: string, userId: number): (boolean, number?)
	local best: number? = nil
	for _, modeId in ipairs(RankingConfig.Modes) do
		local ok, value = api.getArchivedValue(seasonId, modeId, userId)
		if not ok then
			return false, nil
		end
		if value ~= nil then
			if best == nil or value > best then
				best = value
			end
		end
	end
	return true, best
end

-- Pays the RankingConfig.SeasonRewards of the tier the player reached last season, once ever.
-- Runs on ProfileLoaded; the ladder read yields, so the profile is re-checked afterwards and
-- LastRewardedSeason is written before any payout.
local function grantSeasonRewards(player: Player, data: ProfileData)
	local season = previousSeasonId()
	if season == "" or data.Rank.LastRewardedSeason == season or rewarding[player] then
		return
	end
	local api = leaderboard
	if api == nil then
		return
	end
	rewarding[player] = true
	task.spawn(function()
		local ok, rating = archivedRating(api, season, player.UserId)
		rewarding[player] = nil
		if not ok then
			return
		end
		local live = dataService.get(player)
		if live == nil or live ~= data or live.Rank.LastRewardedSeason == season then
			return
		end
		live.Rank.LastRewardedSeason = season
		dataService.push(player, RANK_SECTION)
		if rating == nil then
			log.info("%s was not ranked in season %s: nothing to pay", player.Name, season)
			return
		end
		local tier = RankTiers.tierFor(rating, RankingConfig.Tiers)
		local reward = RankingConfig.SeasonRewards[tier.Id]
		if reward == nil then
			log.warn("no season reward configured for tier %s", tier.Id)
			return
		end
		if reward.Folios > 0 then
			currency.add(player, reward.Folios, SEASON_REWARD_REASON)
		end
		local cosmetic = reward.Cosmetic
		if cosmetic ~= nil then
			log.try("cosmetic grant " .. cosmetic, cosmeticService.grant, player, cosmetic)
		end
		-- The payout happens on join, long after the season ended: without this toast the player is paid
		-- in silence and never learns their rank earned anything.
		notify.send(player, "season.rewardGranted", { rank = tier.NameKey, amount = reward.Folios }, "Success", "Claim")
		log.info("%s rewarded for season %s: tier %s, %d Folios", player.Name, season, tier.Id, reward.Folios)
	end)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function RankingService.Init(deps: Deps)
	dataService = deps.DataService
	currency = deps.Currency
	cosmeticService = deps.Cosmetic
	notify = deps.Notify
	leaderboard = deps.Leaderboard
	rankedHere = ServerKind.ranked(ServerKind.of(game.PrivateServerId, game.PrivateServerOwnerId))
end

function RankingService.Start()
	local ok, reason = RankTiers.validate(RankingConfig.Tiers)
	if not ok then
		log.warn("tier list rejected: %s", tostring(reason))
	end
	if leaderboard == nil then
		log.warn("Leaderboard dependency missing: end-of-season rewards stay pending")
	end
	dataService.ProfileLoaded:Connect(grantSeasonRewards)
	if not rankedHere then
		-- What the queue reads to tell the players (MatchController.rankedHere).
		Workspace:SetAttribute(MatchConfig.PrivateServer.UnrankedAttribute, true)
		log.info("a private server bought by a player: ranked play is off here")
	end
	log.info("started (season %s, rating %d..%d)", GameConfig.SeasonId, BOUNDS.Floor, BOUNDS.Ceiling)
end

return RankingService
