--!strict
local Harness = require("./harness")
local RankTiers = require("../src/shared/Pure/RankTiers")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local tiers = {
	{ Id = "Blank", NameKey = "rank.blank", Min = 0 },
	{ Id = "Sketch", NameKey = "rank.sketch", Min = 1100 },
	{ Id = "Script", NameKey = "rank.script", Min = 1300 },
	{ Id = "Codex", NameKey = "rank.codex", Min = 1700 },
}

describe("RankTiers", function()
	it("maps ratings to tiers", function()
		expect(RankTiers.tierFor(0, tiers).Id).toBe("Blank")
		expect(RankTiers.tierFor(1099, tiers).Id).toBe("Blank")
		expect(RankTiers.tierFor(1100, tiers).Id).toBe("Sketch")
		expect(RankTiers.tierFor(1650, tiers).Id).toBe("Script")
		expect(RankTiers.tierFor(5000, tiers).Id).toBe("Codex")
		expect(RankTiers.tierFor(-50, tiers).Id).toBe("Blank")
	end)

	it("finds the next tier and progress", function()
		expect((RankTiers.nextTier(1000, tiers) :: any).Id).toBe("Sketch")
		expect(RankTiers.nextTier(1700, tiers)).toBeNil()
		expect(RankTiers.progress(1200, tiers)).toBeCloseTo(0.5, 6)
		expect(RankTiers.progress(1700, tiers)).toBe(1)
		expect(RankTiers.progress(0, tiers)).toBe(0)
	end)

	it("validates tier lists", function()
		expect((RankTiers.validate(tiers))).toBe(true)
		expect((RankTiers.validate({}))).toBe(false)
		expect((RankTiers.validate({ { Id = "A", NameKey = "x", Min = 10 } }))).toBe(false)
		expect((RankTiers.validate({ { Id = "A", NameKey = "x", Min = 0 }, { Id = "A", NameKey = "y", Min = 5 } }))).toBe(
			false
		)
		expect((RankTiers.validate({ { Id = "A", NameKey = "x", Min = 0 }, { Id = "B", NameKey = "y", Min = 0 } }))).toBe(
			false
		)
	end)
end)
