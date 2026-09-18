--!strict
-- Duel1v1: ranked one-on-one, best of MatchConfig.Modes.Duel1v1.RoundsToWin (two rounds out of three).
-- A round ends the moment a duelist is down; on the timer the one with the most health left takes it
-- and an exact tie scores a draw round. The mode's DurationSeconds is the budget of the whole series,
-- so it is split across the rounds instead of restarting at every round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameModes = require(script.Parent)
local MatchConfig = require(Shared.Config.MatchConfig)

local DEF = MatchConfig.Modes.Duel1v1

local Duel1v1 = {}

Duel1v1.Id = DEF.Id

function Duel1v1.CanStart(userIds: { number }): boolean
	return GameModes.rosterOk(userIds, DEF.TeamSize * DEF.Teams)
end

function Duel1v1.Start(match: GameModes.Match)
	match.MaxRounds = GameModes.maxRounds(match.Def)
	match.RoundSeconds = match.Def.DurationSeconds / match.MaxRounds
end

function Duel1v1.RoundVerdict(match: GameModes.Match, now: number): GameModes.Verdict?
	-- A duelist who leaves has nobody to cover for them: their side forfeits the match, in any phase.
	local forfeit = GameModes.forfeitVerdict(match)
	if forfeit ~= nil then
		return forfeit
	end
	if match.Phase ~= "Playing" then
		return nil
	end
	local knockout = GameModes.eliminationVerdict(match)
	if knockout ~= nil then
		return knockout
	end
	if now >= match.RoundEndsAt then
		-- Both duelists are still standing, so the round goes to the one with the most health left.
		return GameModes.timeoutVerdict(match)
	end
	return nil
end

function Duel1v1.OnPlayerLeft(match: GameModes.Match, player: Player)
	GameModes.markLeft(match, player)
end

function Duel1v1.End(match: GameModes.Match): GameModes.Result
	return GameModes.result(match, GameModes.outcome(match))
end

-- Conformance: the registry hands this table out as a GameModes.GameMode.
local mode: GameModes.GameMode = Duel1v1
return mode
