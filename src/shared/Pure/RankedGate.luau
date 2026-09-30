--!strict
-- RankedGate: whether a player's matches count for rank yet (E10-S7). A newcomer plays the quick duel, unranked,
-- until they have both reached MinLevel and played MinMatches matches; the Play screen says which is missing and how
-- far off it is, and the server decides from the same numbers. Pure module: no require, no Roblox global, tested
-- under Lune (tests/RankedGate.spec.luau).

export type Rules = { MinMatches: number, MinLevel: number }
-- Ranked, or what is still missing: the levels and the matches to go (0 when that one is done).
export type Status = { Ranked: boolean, LevelsLeft: number, MatchesLeft: number }

local RankedGate = {}

function RankedGate.status(matchesPlayed: number, level: number, rules: Rules): Status
	local levelsLeft = math.max(0, rules.MinLevel - math.floor(level))
	local matchesLeft = math.max(0, rules.MinMatches - math.floor(matchesPlayed))
	return { Ranked = levelsLeft == 0 and matchesLeft == 0, LevelsLeft = levelsLeft, MatchesLeft = matchesLeft }
end

return RankedGate
