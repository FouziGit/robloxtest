--!strict
-- MatchSplash: which centre splash a match snapshot calls for (D-147). Pure module: no require, no Roblox
-- global, tested under Lune (tests/MatchSplash.spec.luau). The HUD compares each MatchChanged snapshot with
-- the one before it and hands what this returns to the Banner.
--
--   MatchFound   the first snapshot of a match
--   Countdown    each new whole second of a round's countdown, with its digit
--   Fight        the countdown over: the round is on
--   RoundWon     a round is over and our score is higher than the snapshot before said
--   RoundLost    a round is over and theirs is
--
-- A round is told by its score, not by the phase changing: a score is only ever counted once, and the
-- snapshot that opens the phase may still carry the old one.
--
-- A snapshot is only what this reads of Types.MatchSnapshot.

export type Snapshot = {
	MatchId: string,
	Phase: string,
	SecondsLeft: number,
	Scores: { number },
	LocalTeam: number,
}

-- One fighter as the announcement names them (E10-S7): their name, their level, and their rank's Strings key, ""
-- for a player still in the quick duel.
export type Fighter = { Name: string, Level: number, RankKey: string }
export type Roster = { Teams: { { Fighter } }, LocalTeam: number }

export type Kind = "MatchFound" | "Countdown" | "Fight" | "RoundWon" | "RoundLost"
export type Splash = { Kind: Kind, Digit: number? }

local MatchSplash = {}

local COUNTDOWN = "Countdown"
local PLAYING = "Playing"
local ROUND_OVER = "RoundOver"

-- Our score and the best of theirs.
local function scores(snapshot: Snapshot): (number, number)
	local ours, theirs = 0, 0
	for index, score in ipairs(snapshot.Scores) do
		if index == snapshot.LocalTeam then
			ours = score
		else
			theirs = math.max(theirs, score)
		end
	end
	return ours, theirs
end

-- The splashes `current` calls for, coming after `previous` (nil before the first snapshot, or after a match),
-- in the order they are to show.
function MatchSplash.between(previous: Snapshot?, current: Snapshot?): { Splash }
	local splashes: { Splash } = {}
	if current == nil then
		return splashes
	end
	local before = if previous ~= nil and previous.MatchId == current.MatchId then previous else nil
	if before == nil then
		table.insert(splashes, { Kind = "MatchFound" })
	end
	if current.Phase == COUNTDOWN then
		local digit = math.ceil(current.SecondsLeft)
		local shown = if before ~= nil and before.Phase == COUNTDOWN then math.ceil(before.SecondsLeft) else nil
		if digit > 0 and digit ~= shown then
			table.insert(splashes, { Kind = "Countdown", Digit = digit })
		end
	elseif current.Phase == PLAYING then
		if before ~= nil and before.Phase == COUNTDOWN then
			table.insert(splashes, { Kind = "Fight" })
		end
	elseif current.Phase == ROUND_OVER and before ~= nil then
		local ours, theirs = scores(current)
		local oursBefore, theirsBefore = scores(before)
		if ours > oursBefore then
			table.insert(splashes, { Kind = "RoundWon" })
		elseif theirs > theirsBefore then
			table.insert(splashes, { Kind = "RoundLost" })
		end
	end
	return splashes
end

-- The fighters the local player faces, team by team, in the order the snapshot lists them: who the match's
-- announcement names, with their level and their rank. None before the snapshot says which team is ours.
function MatchSplash.opponents(roster: Roster): { Fighter }
	local found: { Fighter } = {}
	if roster.LocalTeam < 1 then
		return found
	end
	for team, fighters in ipairs(roster.Teams) do
		if team ~= roster.LocalTeam then
			for _, fighter in ipairs(fighters) do
				table.insert(found, fighter)
			end
		end
	end
	return found
end

return MatchSplash
