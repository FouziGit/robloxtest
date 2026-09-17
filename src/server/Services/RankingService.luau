--!strict
-- RankingService: the only writer of ProfileData.Rank. Turns a finished ranked match into Elo ratings
-- with Pure/Elo (team rating, K factor decreasing with experience, floor / ceiling from
-- RankingConfig), keeps Matches / Wins / Losses / PeakRating, pushes "Rank" and announces every move
-- through RatingChanged so LeaderboardService can persist it on the season ladder.
--
-- It also runs the end-of-season pass. DataService resets Rank.Modes when GameConfig.SeasonId changes,
-- so the profile itself no longer knows what the player reached last season: the durable record is the
-- previous season's ladder, read once per player through LeaderboardService. Rank.LastRewardedSeason
-- is written before any payout and re-checked after the read, so a reward can never be granted twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Elo = require(Shared.Pure.Elo)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local RankTiers = require(Shared.Pure.RankTiers)
local RankingConfig = require(Shared.Config.RankingConfig)
local Signal = require(Packages.Signal)
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
-- LeaderboardService owns the seasonal OrderedDataStores; `false` means the store could not be read.
type LeaderboardApi = {
	getArchivedValue: (seasonId: string, boardId: string, userId: number) -> (boolean, number?),
}
type Deps = { DataService: DataApi, Currency: CurrencyApi, Leaderboard: LeaderboardApi? }

-- Rating move of one participant, keyed by user id in the map applyResult returns.
export type RatingDelta = {
	Before: number,
	After: number,
	RankKeyBefore: string,
	RankKeyAfter: string,
}

-- One participant of a finished match: Entry is nil when the player already left (their profile is
-- released, so nothing can be written for them).
type Participant = { UserId: number, Player: Player?, Entry: RankModeData? }

local RANK_SECTION = "Rank"
local COSMETICS_SECTION = "Cosmetics"
-- Currency reason strings feed logs and telemetry only; they are never shown to a player.
local SEASON_REWARD_REASON = "SeasonReward"
-- Elo needs exactly two sides to score a result.
local TEAMS_PER_MATCH = 2

local BOUNDS: Elo.Bounds = { Floor = RankingConfig.RatingFloor, Ceiling = RankingConfig.RatingCeiling }

local RankingService = {}

RankingService.RatingChanged = Signal.new() -- (player: Player, modeId: string, before: number, after: number)

local dataService: DataApi
local currency: CurrencyApi
local leaderboard: LeaderboardApi?
-- Players whose end-of-season pass is reading the ladder: one attempt in flight at a time.
local rewarding: { [Player]: boolean } = {}

----------------------------------------------------------------
-- Rank data
----------------------------------------------------------------

local function isRankedMode(modeId: string): boolean
	local mode = MatchConfig.Modes[modeId]
	return mode ~= nil and mode.Ranked
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
	return mode.Rating
end

----------------------------------------------------------------
-- Match results
----------------------------------------------------------------

-- Applies a finished ranked match and returns the rating move of every participant still on the
-- server with a loaded profile, keyed by user id. A participant who already left counts at
-- RankingConfig.InitialRating in their team's average (so an abandon cannot distort the opposing
-- team's Elo) but is absent from the result: callers treat a missing entry as "rating unchanged".
-- An unranked mode (World Boss) and a match that did not report two teams return an empty map.
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
			table.insert(participants, { UserId = userId, Player = player, Entry = entry })
			table.insert(ratings, if entry ~= nil then entry.Rating else RankingConfig.InitialRating)
		end
		teams[teamIndex] = participants
		teamRatings[teamIndex] = Elo.teamRating(ratings)
	end

	local draw = result.WinnerTeam == nil
	for teamIndex, participants in ipairs(teams) do
		local opponentRating = teamRatings[TEAMS_PER_MATCH + 1 - teamIndex]
		local won = result.WinnerTeam == teamIndex
		local score = if draw then 0.5 elseif won then 1 else 0
		for _, participant in ipairs(participants) do
			local entry = participant.Entry
			local player = participant.Player
			if entry == nil or player == nil then
				continue
			end
			local before = entry.Rating
			local kFactor = Elo.kFactor(entry.Matches, RankingConfig.KFactorSchedule)
			local after = Elo.update(before, opponentRating, score, kFactor, kFactor, BOUNDS)
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
			}
			RankingService.RatingChanged:Fire(player, result.ModeId, before, after)
			log.info(
				"%s %s %d -> %d (k %d, opponent %.0f)",
				player.Name,
				result.ModeId,
				before,
				after,
				kFactor,
				opponentRating
			)
		end
	end
	return deltas
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
		if reward.Ryo > 0 then
			currency.add(player, reward.Ryo, SEASON_REWARD_REASON)
		end
		local cosmetic = reward.Cosmetic
		if cosmetic ~= nil and table.find(live.Cosmetics.Owned, cosmetic) == nil then
			table.insert(live.Cosmetics.Owned, cosmetic)
			dataService.push(player, COSMETICS_SECTION)
		end
		log.info("%s rewarded for season %s: tier %s, %d Ryo", player.Name, season, tier.Id, reward.Ryo)
	end)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function RankingService.Init(deps: Deps)
	dataService = deps.DataService
	currency = deps.Currency
	leaderboard = deps.Leaderboard
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
	log.info("started (season %s, rating %d..%d)", GameConfig.SeasonId, BOUNDS.Floor, BOUNDS.Ceiling)
end

return RankingService
