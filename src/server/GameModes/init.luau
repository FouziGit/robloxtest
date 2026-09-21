--!strict
-- GameMode contract, shared win-condition helpers and the mode registry.
--
-- A mode owns its rules and nothing else: it reads and writes the match table it is handed and never
-- touches a service, an Instance or a remote. MatchService stays the only owner of arenas, teleports,
-- replication and rewards, so adding a mode is a rules file, not a second lifecycle.
--
-- The registry resolves a mode on first use: the mode modules require this one back for the contract,
-- so requiring them at the top level here would be a cyclic require.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local MatchConfig = require(Shared.Config.MatchConfig)
local SeriesOutcome = require(Shared.Pure.SeriesOutcome)
local Types = require(Shared.Types)

local GameModes = {}

export type ModeDef = MatchConfig.ModeDef
export type Result = Types.MatchResult

-- One player of a live match. `Present` drops when they leave the server, `Alive` when they lose the
-- current round; both are false for the rest of the match once a player is gone.
export type Participant = {
	UserId: number,
	Player: Player,
	Name: string, -- DisplayName resolved once at match start (never a Strings key)
	Team: number,
	Slot: number, -- index inside the team, used as the spawn slot
	Present: boolean,
	-- Let go early, while the match was still on its result screen, because they asked for another duel
	-- (MatchService.releaseFromResult). The wind-up must not move them again.
	Released: boolean,
	Alive: boolean,
	Health: number,
	MaxHealth: number,
}

export type TeamStats = { Present: number, Alive: number, Health: number }

-- "Elimination" and "Timeout" close a round, "Forfeit" closes the whole match at once.
export type VerdictReason = "Elimination" | "Timeout" | "Forfeit"
-- WinnerTeam = nil means a draw (draw round, or an abandoned match nobody won).
export type Verdict = { WinnerTeam: number?, Reason: VerdictReason }

export type Match = {
	Id: string,
	ModeId: Types.MatchModeId,
	Def: ModeDef,
	Phase: Types.MatchPhase,
	Round: number,
	MaxRounds: number, -- set by the mode in Start
	RoundSeconds: number, -- set by the mode in Start
	Scores: { number }, -- team index -> rounds won
	Teams: { { number } }, -- team index -> user ids
	Participants: { Participant },
	StartedAt: number, -- os.clock stamps
	RoundEndsAt: number,
	EndedAt: number, -- 0 until MatchService enters the Result phase
	-- Set by MatchService when a team wins because the other one walked out. It decides the outcome on
	-- its own: the rounds already played do not, because a forfeit can arrive on a series the LEAVER was
	-- winning and comparing scores would then read as a tie.
	ForfeitWinner: number?,
}

export type GameMode = {
	Id: string,
	-- Checked before an arena is acquired: a mode refuses a roster it cannot run.
	CanStart: (userIds: { number }) -> boolean,
	-- Fills the round plan (MaxRounds, RoundSeconds) from the mode definition.
	Start: (match: Match) -> (),
	-- nil while the round must keep running.
	RoundVerdict: (match: Match, now: number) -> Verdict?,
	-- A leaver is out of the match and dead for the current round.
	OnPlayerLeft: (match: Match, player: Player) -> (),
	End: (match: Match) -> Result,
}

local loaders: { [string]: () -> GameMode } = {
	Duel1v1 = function(): GameMode
		return require(script.Duel1v1) :: GameMode
	end,
	Team3v3 = function(): GameMode
		return require(script.Team3v3) :: GameMode
	end,
}
local loaded: { [string]: GameMode } = {}

-- The mode implementing `modeId`, or nil when none is registered.
function GameModes.get(modeId: string): GameMode?
	local cached = loaded[modeId]
	if cached ~= nil then
		return cached
	end
	local loader = loaders[modeId]
	if loader == nil then
		return nil
	end
	local mode = loader()
	loaded[modeId] = mode
	return mode
end

-- Rounds a best-of-`RoundsToWin` series can take: 1 round for a single-round mode, 3 for two wins.
function GameModes.maxRounds(def: ModeDef): number
	return (def.RoundsToWin - 1) * def.Teams + 1
end

-- Exactly `expected` distinct user ids.
function GameModes.rosterOk(userIds: { number }, expected: number): boolean
	if #userIds ~= expected then
		return false
	end
	local seen: { [number]: boolean } = {}
	for _, userId in ipairs(userIds) do
		if seen[userId] then
			return false
		end
		seen[userId] = true
	end
	return true
end

-- Living members and their remaining health. Eliminated players count for nothing, so a timeout is
-- decided by what is still standing.
function GameModes.teamStats(match: Match, team: number): TeamStats
	local stats: TeamStats = { Present = 0, Alive = 0, Health = 0 }
	for _, participant in ipairs(match.Participants) do
		if participant.Team == team then
			if participant.Present then
				stats.Present += 1
			end
			if participant.Alive then
				stats.Alive += 1
				stats.Health += participant.Health
			end
		end
	end
	return stats
end

-- A team with nobody left forfeits. nil while every team still has a member; a verdict without a
-- winner when every team is empty (the match is over and nobody won it).
function GameModes.forfeitVerdict(match: Match): Verdict?
	local survivors: { number } = {}
	local empty = false
	for team = 1, match.Def.Teams do
		if GameModes.teamStats(match, team).Present > 0 then
			table.insert(survivors, team)
		else
			empty = true
		end
	end
	if not empty then
		return nil
	end
	return { WinnerTeam = if #survivors == 1 then survivors[1] else nil, Reason = "Forfeit" }
end

-- Round over by elimination: nil while every team has a living member, otherwise the single team that
-- still stands (nil winner when the last members fell together).
function GameModes.eliminationVerdict(match: Match): Verdict?
	local standing: { number } = {}
	local wiped = false
	for team = 1, match.Def.Teams do
		if GameModes.teamStats(match, team).Alive > 0 then
			table.insert(standing, team)
		else
			wiped = true
		end
	end
	if not wiped then
		return nil
	end
	return { WinnerTeam = if #standing == 1 then standing[1] else nil, Reason = "Elimination" }
end

-- Round over on the timer: most living members, then most remaining health, an exact tie is a draw.
function GameModes.timeoutVerdict(match: Match): Verdict
	local best: number? = nil
	local bestAlive = -1
	local bestHealth = -1
	local tied = false
	for team = 1, match.Def.Teams do
		local stats = GameModes.teamStats(match, team)
		if stats.Alive > bestAlive or (stats.Alive == bestAlive and stats.Health > bestHealth) then
			best = team
			bestAlive = stats.Alive
			bestHealth = stats.Health
			tied = false
		elseif stats.Alive == bestAlive and stats.Health == bestHealth then
			tied = true
		end
	end
	return { WinnerTeam = if tied then nil else best, Reason = "Timeout" }
end

-- The outcome of a finished match. Pure/SeriesOutcome owns the rule; every mode's End goes through this
-- so no mode can forget the forfeit case.
function GameModes.outcome(match: Match): number?
	return SeriesOutcome.resolve(match.Scores, match.Def.Teams, match.Def.RoundsToWin, match.ForfeitWinner)
end

-- The single team that has already won the series on rounds, nil while it is still open.
function GameModes.decidedWinner(match: Match): number?
	return SeriesOutcome.decided(match.Scores, match.Def.Teams, match.Def.RoundsToWin)
end

-- The highest score held by a team other than `team`, for raising a forfeit winner just past it.
function GameModes.bestOtherScore(match: Match, team: number): number
	return SeriesOutcome.bestOther(match.Scores, match.Def.Teams, team)
end

-- The team with the single highest score, nil on a tie.
function GameModes.scoreWinner(match: Match): number?
	return SeriesOutcome.leader(match.Scores, match.Def.Teams)
end

-- Marks a leaver: out of the match, and dead for the current round.
function GameModes.markLeft(match: Match, player: Player)
	for _, participant in ipairs(match.Participants) do
		if participant.UserId == player.UserId then
			participant.Present = false
			participant.Alive = false
			participant.Health = 0
		end
	end
end

-- The participant carrying `userId`, or nil.
function GameModes.participantOf(match: Match, userId: number): Participant?
	for _, participant in ipairs(match.Participants) do
		if participant.UserId == userId then
			return participant
		end
	end
	return nil
end

-- Participants that are still in the match (a disconnect drops out of this count).
function GameModes.presentCount(match: Match): number
	local count = 0
	for _, participant in ipairs(match.Participants) do
		if participant.Present then
			count += 1
		end
	end
	return count
end

-- True once a team has won the series: no further round is worth playing.
function GameModes.isDecided(match: Match): boolean
	for _, score in ipairs(match.Scores) do
		if score >= match.Def.RoundsToWin then
			return true
		end
	end
	return false
end

-- Wire snapshot of the match (MatchChanged). LocalTeam is filled in per receiver by MatchService.
function GameModes.snapshot(match: Match, secondsLeft: number): Types.MatchSnapshot
	local teams: { { Types.MatchPlayerSnapshot } } = {}
	for team = 1, match.Def.Teams do
		teams[team] = {}
	end
	for _, participant in ipairs(match.Participants) do
		local list = teams[participant.Team]
		if list ~= nil then
			table.insert(list, {
				UserId = participant.UserId,
				Name = participant.Name,
				Team = participant.Team,
				Alive = participant.Alive,
				Health = participant.Health,
				MaxHealth = participant.MaxHealth,
			})
		end
	end
	return {
		MatchId = match.Id,
		ModeId = match.ModeId,
		Phase = match.Phase,
		SecondsLeft = secondsLeft,
		Round = match.Round,
		RoundsToWin = match.Def.RoundsToWin,
		Scores = table.clone(match.Scores),
		Teams = teams,
		LocalTeam = 0,
	}
end

-- Result handed to MatchService (rewards) and RankingService (Elo).
function GameModes.result(match: Match, winnerTeam: number?): Result
	local endedAt = if match.EndedAt > 0 then match.EndedAt else match.StartedAt
	return {
		MatchId = match.Id,
		ModeId = match.ModeId,
		WinnerTeam = winnerTeam,
		Teams = match.Teams,
		DurationSeconds = math.max(0, endedAt - match.StartedAt),
	}
end

return GameModes
