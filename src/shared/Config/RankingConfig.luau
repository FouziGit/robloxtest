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
	{ Id = "Blank", NameKey = "rank.blank", Min = 0 },
	{ Id = "Sketch", NameKey = "rank.sketch", Min = 1100 },
	{ Id = "Script", NameKey = "rank.script", Min = 1300 },
	{ Id = "Illumination", NameKey = "rank.illumination", Min = 1500 },
	{ Id = "Codex", NameKey = "rank.codex", Min = 1700 },
} :: { Tier }

-- Ranked modes (keys of ProfileData.Rank.Modes).
RankingConfig.Modes = { "Duel1v1", "Team3v3" } :: { string }

-- The same two players, again and again in one UTC day (E4-S3, D-XXXfarm). Their first FullMatchesPerDay ranked
-- matches of the day count in full; from the next one on, the pair's ratings no longer move and each of them earns
-- RepeatRewardScale of a match's XP and Folios. Counted in each profile (Rank.Opponents, Pure/OpponentLedger), so a
-- new server does not start the count over. In a 3v3, a participant is held to the rule by any opponent they have
-- met that often today. Five is a long evening of rematches between friends; the sixth is a farm.
RankingConfig.Opponents = {
	FullMatchesPerDay = 5,
	RepeatRewardScale = 0.25,
}

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

-- End-of-season rewards by tier reached (Folios + cosmetic title id).
RankingConfig.SeasonRewards = {
	Blank = { Folios = 200 },
	Sketch = { Folios = 500 },
	Script = { Folios = 1000, Cosmetic = "TitleScript" },
	Illumination = { Folios = 2000, Cosmetic = "TitleIllumination" },
	Codex = { Folios = 4000, Cosmetic = "TitleCodexSeason" },
} :: { [string]: { Folios: number, Cosmetic: string? } }

return RankingConfig
