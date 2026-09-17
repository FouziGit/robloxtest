--!strict
local DailyConfig = require("../src/shared/Config/DailyConfig")
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function fresh()
	return { LastClaimDay = 0, Streak = 0, FirstWinDay = 0, PremiumBonusDay = 0 }
end

describe("DailyStreak", function()
	it("starts, continues and breaks streaks", function()
		local daily = fresh()
		expect(DailyStreak.evaluate(daily, 100)).toEqual({ CanClaim = true, NextStreak = 1, Broken = false })
		expect(DailyStreak.claim(daily, 100)).toBe(1)
		expect(DailyStreak.claim(daily, 100)).toBe(0)
		expect(DailyStreak.claim(daily, 101)).toBe(2)
		expect(DailyStreak.claim(daily, 102)).toBe(3)
		local evaluation = DailyStreak.evaluate(daily, 105)
		expect(evaluation).toEqual({ CanClaim = true, NextStreak = 1, Broken = true })
		expect(DailyStreak.claim(daily, 105)).toBe(1)
		expect(daily.Streak).toBe(1)
	end)

	it("cycles the reward table", function()
		local size = #DailyConfig.Streak
		expect(size).toBe(7)
		expect(DailyStreak.rewardIndex(1, size)).toBe(1)
		expect(DailyStreak.rewardIndex(7, size)).toBe(7)
		expect(DailyStreak.rewardIndex(8, size)).toBe(1)
		expect(DailyStreak.rewardIndex(0, size)).toBe(1)
		for _, reward in ipairs(DailyConfig.Streak) do
			expect(reward.Ryo).toBeGreaterThan(0)
			expect(reward.Xp).toBeGreaterThan(0)
		end
	end)

	it("tracks first win and premium bonus per day", function()
		local daily = fresh()
		expect(DailyStreak.firstWinAvailable(daily, 50)).toBe(true)
		expect(DailyStreak.markFirstWin(daily, 50)).toBe(true)
		expect(DailyStreak.markFirstWin(daily, 50)).toBe(false)
		expect(DailyStreak.firstWinAvailable(daily, 51)).toBe(true)
		expect(DailyStreak.markPremiumBonus(daily, 50)).toBe(true)
		expect(DailyStreak.premiumBonusAvailable(daily, 50)).toBe(false)
		expect(DailyConfig.PremiumBonus.Ryo).toBeGreaterThan(0)
	end)
end)
