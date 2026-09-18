--!strict
-- Team3v3: ranked three-on-three in a single round (MatchConfig.Modes.Team3v3.RoundsToWin = 1), so the
-- whole DurationSeconds budget is that round. A team wins by wiping every opponent out, or on the timer
-- by the number of teammates still alive and then by the health they have left; a perfect tie is a draw.
-- A team only forfeits once every one of its members has left the server: three players means the round
-- survives a disconnect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameModes = require(script.Parent)
local MatchConfig = require(Shared.Config.MatchConfig)

local DEF = MatchConfig.Modes.Team3v3

local Team3v3 = {}

Team3v3.Id = DEF.Id

function Team3v3.CanStart(userIds: { number }): boolean
	return GameModes.rosterOk(userIds, DEF.TeamSize * DEF.Teams)
end

function Team3v3.Start(match: GameModes.Match)
	match.MaxRounds = GameModes.maxRounds(match.Def)
	match.RoundSeconds = match.Def.DurationSeconds
end

function Team3v3.RoundVerdict(match: GameModes.Match, now: number): GameModes.Verdict?
	local forfeit = GameModes.forfeitVerdict(match)
	if forfeit ~= nil then
		return forfeit
	end
	if match.Phase ~= "Playing" then
		return nil
	end
	local wipe = GameModes.eliminationVerdict(match)
	if wipe ~= nil then
		return wipe
	end
	if now >= match.RoundEndsAt then
		-- Survivors first, total health as the tie-break.
		return GameModes.timeoutVerdict(match)
	end
	return nil
end

function Team3v3.OnPlayerLeft(match: GameModes.Match, player: Player)
	GameModes.markLeft(match, player)
end

function Team3v3.End(match: GameModes.Match): GameModes.Result
	return GameModes.result(match, GameModes.outcome(match))
end

-- Conformance: the registry hands this table out as a GameModes.GameMode.
local mode: GameModes.GameMode = Team3v3
return mode
