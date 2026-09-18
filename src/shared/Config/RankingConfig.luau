--!strict
-- Ranked play: Elo parameters, rank tiers, leaderboards. Pure data.

export type Tier = { Id: string, NameKey: string, Min: number }

local RankingConfig = {}

RankingConfig.InitialRating = 1000
RankingConfig.RatingFloor = 100
RankingConfig.RatingCeiling = 4000

-- K-factor decreases with experience: first matches move the rating fast, veterans move slowly.
-- Entries are checked in order; the first whose MaxMatches is nil or > matches wins.
RankingConfig.KFactorSchedule = {
	{ MaxMatches = 10, K = 40 },
	{ MaxMatches = 30, K = 24 },
	{ MaxMatches = nil, K = 16 },
} :: { { MaxMatches: number?, K: number } }

-- Named tiers by rating (ascending Min). NameKey resolves through Strings.
RankingConfig.Tiers = {
	{ Id = "Genin", NameKey = "rank.genin", Min = 0 },
	{ Id = "Chunin", NameKey = "rank.chunin", Min = 1100 },
	{ Id = "Jonin", NameKey = "rank.jonin", Min = 1300 },
	{ Id = "Anbu", NameKey = "rank.anbu", Min = 1500 },
	{ Id = "Kage", NameKey = "rank.kage", Min = 1700 },
} :: { Tier }

-- Ranked modes (keys of ProfileData.Rank.Modes).
RankingConfig.Modes = { "Duel1v1", "Team3v3" } :: { string }

RankingConfig.Leaderboard = {
	RefreshSeconds = 60, -- OrderedDataStore refresh cadence (per board)
	TopCount = 50,
	-- Board ids: "Global" (sum of mode ratings above initial) plus one per mode.
	Boards = { "Global", "Duel1v1", "Team3v3" },
	-- DataStore write budget guard: a player's rating is written at most this often.
	MinWriteIntervalSeconds = 30,
	-- Roblox refuses a second SetAsync on the same OrderedDataStore key inside this window. The periodic
	-- scan never meets it because MinWriteIntervalSeconds is longer; the forced flush when a player leaves
	-- does, and waits it out rather than burning its retries on a throttled call.
	KeyCooldownSeconds = 6,
}

-- End-of-season rewards by tier reached (Ryo + cosmetic title id).
RankingConfig.SeasonRewards = {
	Genin = { Ryo = 200 },
	Chunin = { Ryo = 500 },
	Jonin = { Ryo = 1000, Cosmetic = "TitleJonin" },
	Anbu = { Ryo = 2000, Cosmetic = "TitleAnbu" },
	Kage = { Ryo = 4000, Cosmetic = "TitleKageSeason" },
} :: { [string]: { Ryo: number, Cosmetic: string? } }

return RankingConfig
