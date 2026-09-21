--!strict
-- The execution grade: what the result card stamps on a duel. It is the one number in the game that
-- judges the player rather than the outcome, so it is held to being unfoolable -- a win cannot buy an S,
-- and a player who never cast anything cannot be graded well for surviving.
local Execution = require("../src/shared/Pure/Execution")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("accuracy", function()
	it("is the share of casts that landed", function()
		expect(Execution.accuracy(10, 5)).toBeCloseTo(0.5, 6)
		expect(Execution.accuracy(12, 12)).toBe(1)
	end)

	it("is nothing when nothing was cast, and never more than everything", function()
		-- A player who cast nothing has not been accurate: a zero here is what keeps a duel won by walking
		-- away from being graded on the two melee hits it took.
		expect(Execution.accuracy(0, 0)).toBe(0)
		expect(Execution.accuracy(0, 5)).toBe(0)
		expect(Execution.accuracy(9, 40)).toBe(1)
	end)

	it("counts a small handful of casts against the floor, not against itself", function()
		-- Without the floor the best play was to cast ONCE and land it: a single landed glyph scored a
		-- perfect accuracy, so the player who threw fourteen and landed them graded below the player who
		-- threw one. The denominator is MinCasts until the player has really cast that many.
		local floor = Execution.MinCasts
		expect(floor).toBeGreaterThanOrEqual(4)
		expect(Execution.accuracy(1, 1)).toBeCloseTo(1 / floor, 6)
		expect(Execution.accuracy(floor, floor)).toBe(1)
		-- And the one-cast duel can no longer reach the top grade on a won trade.
		expect(Execution.grade(1, 1, 100, 40, true)).never.toBe("grade.steady")
		expect(Execution.grade(14, 14, 100, 40, true)).toBe("grade.steady")
	end)
end)

describe("efficiency", function()
	it("is the share of the damage exchanged that the player dealt", function()
		expect(Execution.efficiency(300, 100)).toBeCloseTo(0.75, 6)
		expect(Execution.efficiency(100, 300)).toBeCloseTo(0.25, 6)
		expect(Execution.efficiency(200, 200)).toBeCloseTo(0.5, 6)
	end)

	it("is even when nothing was exchanged", function()
		expect(Execution.efficiency(0, 0)).toBe(0.5)
	end)
end)

describe("the grade", function()
	it("weighs accuracy above the trade, and both above the win", function()
		expect(Execution.AccuracyWeight).toBeGreaterThan(Execution.EfficiencyWeight)
		expect(Execution.AccuracyWeight + Execution.EfficiencyWeight).toBeCloseTo(1, 6)
		expect(Execution.WinBonus).toBeLessThan(Execution.EfficiencyWeight)
	end)

	it("stays inside 0 and 1 whatever it is fed", function()
		local cases = {
			{ 0, 0, 0, 0 },
			{ 1, 0, 0, 5000 },
			{ 40, 40, 5000, 0 },
			{ 3, 9, 100, 100 },
		}
		for _, case in ipairs(cases) do
			for _, won in ipairs({ true, false }) do
				local score = Execution.score(case[1], case[2], case[3], case[4], won)
				expect(score).toBeGreaterThanOrEqual(0)
				expect(score).toBeLessThanOrEqual(1)
			end
		end
	end)

	it("rises with hits and with damage dealt", function()
		expect(Execution.score(10, 8, 300, 100, false)).toBeGreaterThan(Execution.score(10, 4, 300, 100, false))
		expect(Execution.score(10, 8, 400, 100, false)).toBeGreaterThan(Execution.score(10, 8, 300, 200, false))
	end)

	it("gives S to a duel played well and C to one played badly", function()
		expect(Execution.grade(12, 11, 420, 90, true)).toBe("grade.steady")
		expect(Execution.grade(12, 2, 80, 400, false)).toBe("grade.shaky")
	end)

	it("cannot be bought with the win alone", function()
		-- The bonus is there so a won duel with poor numbers is still better than a lost one with the same
		-- numbers. It must not be enough to reach the top grade on its own, or the grade says "you won",
		-- which the title of the card already says.
		local thresholds = Execution.Thresholds
		expect(Execution.WinBonus).toBeLessThan(thresholds.Steady - thresholds.Clean)
		-- An average trade, nothing cast, and a win: the floor grade.
		expect(Execution.grade(0, 0, 200, 200, true)).toBe("grade.shaky")
		-- The same duel won and lost differs by the bonus, never by more.
		local won = Execution.score(10, 6, 300, 200, true)
		local lost = Execution.score(10, 6, 300, 200, false)
		expect(won - lost).toBeCloseTo(Execution.WinBonus, 6)
	end)

	it("hands out every grade it declares, in order, and each one is a real key", function()
		local thresholds = Execution.Thresholds
		expect(thresholds.Steady).toBeGreaterThan(thresholds.Clean)
		expect(thresholds.Clean).toBeGreaterThan(thresholds.Unsure)
		expect(thresholds.Unsure).toBeGreaterThan(0)

		local seen: { [string]: boolean } = {}
		-- Accuracy alone spans the scale, which is the point: the grade is mostly what the player hit.
		for hits = 0, 10 do
			seen[Execution.grade(10, hits, 200, 200, false)] = true
		end
		for _, key in ipairs({ "grade.steady", "grade.clean", "grade.unsure", "grade.shaky" }) do
			if not seen[key] then
				error(("no execution reachable by accuracy alone is graded %s"):format(key))
			end
			expect(Strings.has(key)).toBe(true)
		end
	end)
end)
