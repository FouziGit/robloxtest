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
	-- A practice duel against a Duelist Forger while the player waits in the 1v1 queue (E10-S6, SparService, and
	-- MatchConfig.Spar below). It has no queue of its own and no arena: it is offered from the queue's card and
	-- fought in a pit beside the Battleground. Unranked, the rounds of the ranked duel, a shorter count first.
	Spar1v1 = {
		Id = "Spar1v1",
		NameKey = "mode.spar1v1",
		TeamSize = 1,
		Teams = 2,
		Ranked = false,
		DurationSeconds = 180,
		RoundsToWin = 2,
		CountdownSeconds = 3,
		ResultSeconds = 6,
		-- Not a MatchConfig.Arenas entry: a spar is fought in one of the Battleground's pits, never an arena.
		ArenaId = "Pit",
	},
} :: { [string]: ModeDef }

MatchConfig.ModeOrder = { "Duel1v1", "Team3v3" } :: { string }

MatchConfig.Spar = {
	-- The queue it is offered from, and after how long waiting there with nobody else in it.
	QueueModeId = "Duel1v1",
	OfferAfterSeconds = 20,
	-- The Forger it is fought against (BotConfig.Tiers), and the user id that stands for it in a snapshot.
	TierId = "Duelist",
	ForgerUserId = 0,
	-- Spars paid a day, counted in the profile (Daily.SparDay / SparPaid, DailyCap), each at this share of what
	-- the ranked duel pays for the same result (ProgressionConfig.XP / Folios MatchWin, MatchLoss, MatchDraw). A
	-- spar past the day's allowance pays nothing, and is still fought.
	PaidPerDay = 3,
	RewardFactor = 0.5,
	-- How often the offer is looked at for every player in the queue.
	OfferTickSeconds = 1,
}

-- The queue a mode is played from: its own, or the one a spar is offered in. nil for a mode no queue leads to.
function MatchConfig.queueOf(modeId: string): string?
	if table.find(MatchConfig.ModeOrder, modeId) ~= nil then
		return modeId
	end
	if modeId == MatchConfig.Modes.Spar1v1.Id then
		return MatchConfig.Spar.QueueModeId
	end
	return nil
end

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
