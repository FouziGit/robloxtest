--!strict
-- Who won a best-of-N series, from the rounds won and an optional forfeit. Pure: no Roblox global, no
-- require, so it is unit-tested under Lune (tests/SeriesOutcome.spec.luau).
--
-- `scores` is indexed by team, 1..teams. A nil entry counts as zero, so a match that has not scored yet
-- needs no initialisation.

local SeriesOutcome = {}

local function scoreOf(scores: { number }, team: number): number
	return scores[team] or 0
end

-- The single team with the highest score, nil when two or more share it.
function SeriesOutcome.leader(scores: { number }, teams: number): number?
	local best: number? = nil
	local bestScore = -1
	local tied = false
	for team = 1, teams do
		local score = scoreOf(scores, team)
		if score > bestScore then
			best = team
			bestScore = score
			tied = false
		elseif score == bestScore then
			tied = true
		end
	end
	return if tied then nil else best
end

-- The single team that already reached `roundsToWin`, nil while the series is still open. Two teams at
-- the target at once cannot decide it, so that reads as open too.
function SeriesOutcome.decided(scores: { number }, teams: number, roundsToWin: number): number?
	local decided: number? = nil
	for team = 1, teams do
		if scoreOf(scores, team) >= roundsToWin then
			if decided ~= nil then
				return nil
			end
			decided = team
		end
	end
	return decided
end

-- The highest score held by a team other than `team`, for raising a forfeit winner just past it.
function SeriesOutcome.bestOther(scores: { number }, teams: number, team: number): number
	local best = 0
	for other = 1, teams do
		if other ~= team then
			best = math.max(best, scoreOf(scores, other))
		end
	end
	return best
end

-- The outcome of a finished series. A team that already reached `roundsToWin` won it on the field and
-- keeps the win whatever happened next, including walking out. Otherwise a forfeit winner takes it.
-- Otherwise the highest score decides, and an equal top score is a draw (nil).
--
-- The order matters: crediting a forfeit by raising the survivor's score to `roundsToWin` turned a 2-0
-- series abandoned between rounds into 2-2, which reads as a draw for both sides.
function SeriesOutcome.resolve(scores: { number }, teams: number, roundsToWin: number, forfeitWinner: number?): number?
	local onField = SeriesOutcome.decided(scores, teams, roundsToWin)
	if onField ~= nil then
		return onField
	end
	if forfeitWinner ~= nil then
		return forfeitWinner
	end
	return SeriesOutcome.leader(scores, teams)
end

return SeriesOutcome
