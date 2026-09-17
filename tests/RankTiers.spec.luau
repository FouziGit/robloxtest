--!strict
local Harness = require("./harness")
local RankTiers = require("../src/shared/Pure/RankTiers")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local tiers = {
	{ Id = "Genin", NameKey = "rank.genin", Min = 0 },
	{ Id = "Chunin", NameKey = "rank.chunin", Min = 1100 },
	{ Id = "Jonin", NameKey = "rank.jonin", Min = 1300 },
	{ Id = "Kage", NameKey = "rank.kage", Min = 1700 },
}

describe("RankTiers", function()
	it("maps ratings to tiers", function()
		expect(RankTiers.tierFor(0, tiers).Id).toBe("Genin")
		expect(RankTiers.tierFor(1099, tiers).Id).toBe("Genin")
		expect(RankTiers.tierFor(1100, tiers).Id).toBe("Chunin")
		expect(RankTiers.tierFor(1650, tiers).Id).toBe("Jonin")
		expect(RankTiers.tierFor(5000, tiers).Id).toBe("Kage")
		expect(RankTiers.tierFor(-50, tiers).Id).toBe("Genin")
	end)

	it("finds the next tier and progress", function()
		expect((RankTiers.nextTier(1000, tiers) :: any).Id).toBe("Chunin")
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
