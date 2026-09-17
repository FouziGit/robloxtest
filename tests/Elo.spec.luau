--!strict
local Elo = require("../src/shared/Pure/Elo")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local schedule = { { MaxMatches = 10, K = 40 }, { MaxMatches = 30, K = 24 }, { MaxMatches = nil, K = 16 } }
local bounds = { Floor = 100, Ceiling = 4000 }

describe("Elo", function()
	it("expected score is symmetric and 0.5 for equal ratings", function()
		expect(Elo.expected(1000, 1000)).toBeCloseTo(0.5, 6)
		expect(Elo.expected(1200, 1000) + Elo.expected(1000, 1200)).toBeCloseTo(1, 6)
		expect(Elo.expected(1400, 1000)).toBeGreaterThan(0.9)
	end)

	it("K factor decreases with experience", function()
		expect(Elo.kFactor(0, schedule)).toBe(40)
		expect(Elo.kFactor(9, schedule)).toBe(40)
		expect(Elo.kFactor(10, schedule)).toBe(24)
		expect(Elo.kFactor(29, schedule)).toBe(24)
		expect(Elo.kFactor(30, schedule)).toBe(16)
		expect(Elo.kFactor(1000, schedule)).toBe(16)
	end)

	it("is zero-sum for equal K and equal ratings", function()
		local a, b, da, db = Elo.update(1000, 1000, 1, 40, 40, bounds)
		expect(da).toBe(20)
		expect(db).toBe(-20)
		expect(a).toBe(1020)
		expect(b).toBe(980)
	end)

	it("rewards upsets more than expected wins", function()
		local _, _, underdogGain = Elo.update(1000, 1400, 1, 40, 40, bounds)
		local _, _, favoriteGain = Elo.update(1400, 1000, 1, 40, 40, bounds)
		expect(underdogGain).toBeGreaterThan(favoriteGain)
		expect(underdogGain).toBeGreaterThan(30)
		expect(favoriteGain).toBeLessThan(5)
	end)

	it("handles draws and keeps integers", function()
		local a, b, da, db = Elo.update(1200, 1000, 0.5, 40, 40, bounds)
		expect(da).toBeLessThan(0)
		expect(db).toBeGreaterThan(0)
		expect(a % 1).toBe(0)
		expect(b % 1).toBe(0)
	end)

	it("respects the floor and ceiling", function()
		-- equal ratings: a loss costs 20 points, clamped to the floor
		local a = Elo.update(105, 105, 0, 40, 40, bounds)
		expect(a).toBe(100)
		-- a win against an equal opponent gains 20 points, clamped to the ceiling
		local top = Elo.update(3995, 3995, 1, 40, 40, bounds)
		expect(top).toBe(4000)
		-- a hopeless loss (rounded delta 0) never moves the rating
		local unchanged = Elo.update(105, 2000, 0, 40, 40, bounds)
		expect(unchanged).toBe(105)
	end)

	it("computes team ratings", function()
		expect(Elo.teamRating({ 1000, 1200, 1400 })).toBe(1200)
		expect(Elo.teamRating({})).toBe(0)
	end)
end)
