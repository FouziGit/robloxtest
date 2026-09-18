--!strict
local Harness = require("./harness")
local SeriesOutcome = require("../src/shared/Pure/SeriesOutcome")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("SeriesOutcome", function()
	it("names the single leader and calls an equal top score a draw", function()
		expect(SeriesOutcome.leader({ 2, 1 }, 2)).toBe(1)
		expect(SeriesOutcome.leader({ 1, 2 }, 2)).toBe(2)
		expect(SeriesOutcome.leader({ 1, 1 }, 2)).toBeNil()
		expect(SeriesOutcome.leader({ 0, 0 }, 2)).toBeNil()
		expect(SeriesOutcome.leader({ 2, 1, 2 }, 3)).toBeNil()
		expect(SeriesOutcome.leader({ 2, 2, 3 }, 3)).toBe(3)
	end)

	it("treats a missing score as zero", function()
		expect(SeriesOutcome.leader({ 1 }, 2)).toBe(1)
		expect(SeriesOutcome.bestOther({ 1 }, 2, 1)).toBe(0)
		expect(SeriesOutcome.decided({}, 2, 2)).toBeNil()
	end)

	it("reports a series decided on rounds", function()
		expect(SeriesOutcome.decided({ 2, 0 }, 2, 2)).toBe(1)
		expect(SeriesOutcome.decided({ 1, 1 }, 2, 2)).toBeNil()
		expect(SeriesOutcome.decided({ 3, 0 }, 2, 2)).toBe(1)
		-- Both at the target at once cannot decide it.
		expect(SeriesOutcome.decided({ 2, 2 }, 2, 2)).toBeNil()
	end)

	it("returns the highest other score", function()
		expect(SeriesOutcome.bestOther({ 0, 1, 3 }, 3, 1)).toBe(3)
		expect(SeriesOutcome.bestOther({ 5, 1, 3 }, 3, 1)).toBe(3)
		expect(SeriesOutcome.bestOther({ 5 }, 1, 1)).toBe(0)
	end)

	it("keeps the win of a series already decided, even when that team then forfeits", function()
		-- The regression: team 1 had won 2-0 and left during the gap between rounds. Crediting the
		-- survivor used to tie it at 2-2 and pay both sides a draw.
		expect(SeriesOutcome.resolve({ 2, 0 }, 2, 2, 2)).toBe(1)
		expect(SeriesOutcome.resolve({ 0, 2 }, 2, 2, 1)).toBe(2)
	end)

	it("gives an undecided series to the forfeit winner", function()
		expect(SeriesOutcome.resolve({ 1, 0 }, 2, 2, 2)).toBe(2)
		expect(SeriesOutcome.resolve({ 0, 0 }, 2, 2, 1)).toBe(1)
		expect(SeriesOutcome.resolve({ 1, 1 }, 2, 2, 1)).toBe(1)
	end)

	it("falls back to the score when nobody forfeited", function()
		expect(SeriesOutcome.resolve({ 1, 0 }, 2, 2, nil)).toBe(1)
		expect(SeriesOutcome.resolve({ 1, 1 }, 2, 2, nil)).toBeNil()
	end)

	it("agrees with the score MatchService writes for a forfeit", function()
		-- MatchService raises the survivor to bestOther + 1 so the printed score matches the verdict.
		local scores = { 1, 0 }
		local winner = 2
		scores[winner] = math.max(scores[winner], SeriesOutcome.bestOther(scores, 2, winner) + 1)
		expect(scores[2]).toBe(2)
		expect(SeriesOutcome.resolve(scores, 2, 2, winner)).toBe(winner)
		expect(SeriesOutcome.leader(scores, 2)).toBe(winner)
	end)
end)
