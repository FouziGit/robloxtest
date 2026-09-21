--!strict
-- The execution grade of a duel: what a player did with their glyphs, in one letter the result card
-- can stamp. docs/JUICE_PLAN.md phase 8, item 4 ("feedback de maîtrise: note d'exécution de fin de duel").
--
-- Pure, so the letter a player is shown is the letter the test computed. The inputs are what the server
-- counted for that player over the match -- casts, casts that hit, damage dealt, damage taken -- and
-- nothing the client claims.
--
-- Accuracy is what the game calls skill (docs/GAME_DESIGN.md pillar 1: "le combo est le skill"): a
-- glyph that lands is a sequence that was right AND aimed. Efficiency is the trade: damage dealt against
-- damage taken. The win adds a little, because a won duel with poor numbers is still a won duel, but it
-- cannot make an S on its own.

local Execution = {}

-- A hand, not a letter. S / A / B / C is the rank card of every arcade game ever shipped and says nothing
-- about this one; a duel graded by the steadiness of the hand that drew it needs no legend, and it is the
-- same vocabulary as the ranks (docs/ART_BIBLE.md: the states of a manuscript).
export type Grade = "grade.steady" | "grade.clean" | "grade.unsure" | "grade.shaky"

-- Weights and thresholds. Accuracy weighs more than the trade because a player controls it directly.
Execution.AccuracyWeight = 0.6
Execution.EfficiencyWeight = 0.4
Execution.WinBonus = 0.05
Execution.Thresholds = { Steady = 0.8, Clean = 0.6, Unsure = 0.4 }
-- The denominator never falls below this. A ratio with no floor made the best play "cast once and land
-- it": one landed glyph scored a perfect accuracy, so a player who threw fourteen and landed them was
-- graded BELOW a player who threw one. Six is a low bar for a duel of two or three minutes -- pillar 1 of
-- docs/GAME_DESIGN.md is that the sequence is the skill, so the grade has to reward volume AND precision.
Execution.MinCasts = 6

-- 0..1: the share of casts that hit at least one target, over at least MinCasts of them.
function Execution.accuracy(casts: number, hits: number): number
	if casts <= 0 then
		return 0
	end
	return math.clamp(hits / math.max(casts, Execution.MinCasts), 0, 1)
end

-- 0..1: the share of the damage exchanged that the player dealt. Nothing exchanged is a half.
function Execution.efficiency(dealt: number, taken: number): number
	local total = dealt + taken
	if total <= 0 then
		return 0.5
	end
	return math.clamp(dealt / total, 0, 1)
end

-- The score the grade is cut from, 0..1.
function Execution.score(casts: number, hits: number, dealt: number, taken: number, won: boolean): number
	local score = Execution.AccuracyWeight * Execution.accuracy(casts, hits)
		+ Execution.EfficiencyWeight * Execution.efficiency(dealt, taken)
	if won then
		score += Execution.WinBonus
	end
	return math.clamp(score, 0, 1)
end

-- The Strings key of the grade.
function Execution.grade(casts: number, hits: number, dealt: number, taken: number, won: boolean): Grade
	local score = Execution.score(casts, hits, dealt, taken, won)
	if score >= Execution.Thresholds.Steady then
		return "grade.steady"
	elseif score >= Execution.Thresholds.Clean then
		return "grade.clean"
	elseif score >= Execution.Thresholds.Unsure then
		return "grade.unsure"
	end
	return "grade.shaky"
end

return Execution
