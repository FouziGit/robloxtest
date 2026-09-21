--!strict
-- Match modes, matchmaking windows, arena layout. Pure data.

export type ModeDef = {
	Id: string,
	NameKey: string,
	TeamSize: number,
	Teams: number,
	Ranked: boolean,
	DurationSeconds: number,
	RoundsToWin: number, -- 1 = single round, 2 = best of three
	CountdownSeconds: number,
	ResultSeconds: number,
	ArenaId: string,
}

local MatchConfig = {}

MatchConfig.Modes = {
	Duel1v1 = {
		Id = "Duel1v1",
		NameKey = "mode.duel1v1",
		TeamSize = 1,
		Teams = 2,
		Ranked = true,
		DurationSeconds = 180,
		RoundsToWin = 2,
		CountdownSeconds = 5,
		ResultSeconds = 8,
		ArenaId = "Duel",
	},
	Team3v3 = {
		Id = "Team3v3",
		NameKey = "mode.team3v3",
		TeamSize = 3,
		Teams = 2,
		Ranked = true,
		DurationSeconds = 300,
		RoundsToWin = 1,
		CountdownSeconds = 5,
		ResultSeconds = 8,
		ArenaId = "Team",
	},
} :: { [string]: ModeDef }

MatchConfig.ModeOrder = { "Duel1v1", "Team3v3" } :: { string }

-- Pause shown between two rounds of a multi-round mode, before the next countdown.
MatchConfig.RoundOverSeconds = 3
-- MatchChanged pushes per second to each participant.
MatchConfig.SnapshotHz = 4

MatchConfig.Matchmaking = {
	BaseWindow = 100, -- rating difference accepted immediately
	WindowGrowthPerSecond = 15, -- window widens while waiting
	MaxWindow = 800,
	TickSeconds = 2, -- how often the queue is scanned
	MaxQueueSeconds = 240, -- after this the player is dequeued and notified
}

MatchConfig.Rewards = {
	-- Multipliers applied to ProgressionConfig.XP / Folios match values per mode.
	Duel1v1 = { Xp = 1, Folios = 1 },
	Team3v3 = { Xp = 1.2, Folios = 1.2 },
}

-- Geometry of generated arenas (studs). Anchors are documented in docs/GAME_DESIGN.md §8.
MatchConfig.Arenas = {
	Duel = { Size = 80, WallHeight = 24, SpawnDistance = 30, KillZoneDepth = -40, Height = 500 },
	Team = { Size = 120, WallHeight = 24, SpawnDistance = 44, KillZoneDepth = -40, Height = 700 },
	Boss = { Size = 160, WallHeight = 30, SpawnDistance = 60, KillZoneDepth = -40, Height = 900 },
}

-- Vertical stacking of instantiated arenas so simultaneous matches never overlap.
MatchConfig.ArenaSpacingStuds = 400

return MatchConfig
