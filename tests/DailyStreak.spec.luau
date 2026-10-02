--!strict
-- The login calendar (E15-S1): a streak of days claimed in a row, walked through the 28 days of
-- DailyConfig.Calendar, and the Signets that keep it through a missed day. The rules are Pure/DailyStreak's and are
-- run here; what the calendar pays and gives is DailyConfig's and is held here too.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DailyConfig = require("../src/shared/Config/DailyConfig")
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local LENGTH = #DailyConfig.Calendar
local MAX = DailyConfig.MaxSignets

local function fresh(): DailyStreak.DailyData
	return { LastClaimDay = 0, Streak = 0, CalendarDay = 0, Signets = 0, FirstWinDay = 0, PremiumBonusDay = 0 }
end

-- A profile that claimed day `calendarDay` of the calendar on `lastDay`, `streak` days in a row, holding `signets`.
local function claimedOn(lastDay: number, streak: number, calendarDay: number, signets: number): DailyStreak.DailyData
	local daily = fresh()
	daily.LastClaimDay = lastDay
	daily.Streak = streak
	daily.CalendarDay = calendarDay
	daily.Signets = signets
	return daily
end

describe("the login calendar", function()
	it("starts on its first day, walks one day per claim and refuses a second claim the same day", function()
		local daily = fresh()
		expect(DailyStreak.evaluate(daily, 100, LENGTH)).toEqual({
			CanClaim = true,
			NextStreak = 1,
			NextDay = 1,
			Broken = false,
			SignetsUsed = 0,
		})
		expect(DailyStreak.claim(daily, 100, LENGTH).NextDay).toBe(1)
		expect(DailyStreak.claim(daily, 100, LENGTH).CanClaim).toBe(false)
		expect(daily.CalendarDay).toBe(1)
		expect(DailyStreak.claim(daily, 101, LENGTH).NextDay).toBe(2)
		expect(DailyStreak.claim(daily, 102, LENGTH).NextDay).toBe(3)
		expect(daily.Streak).toBe(3)
		expect(daily.LastClaimDay).toBe(102)
	end)

	it("keeps the streak through a missed day with a Signet, and spends it", function()
		local daily = claimedOn(100, 5, 5, 1)
		local evaluation = DailyStreak.evaluate(daily, 102, LENGTH)
		expect(evaluation).toEqual({ CanClaim = true, NextStreak = 6, NextDay = 6, Broken = false, SignetsUsed = 1 })
		DailyStreak.claim(daily, 102, LENGTH)
		expect(daily.Streak).toBe(6)
		expect(daily.CalendarDay).toBe(6)
		expect(daily.Signets).toBe(0)
		expect(daily.LastClaimDay).toBe(102)
	end)

	it("starts over from the first day without a Signet", function()
		local daily = claimedOn(100, 5, 5, 0)
		expect(DailyStreak.evaluate(daily, 102, LENGTH)).toEqual({
			CanClaim = true,
			NextStreak = 1,
			NextDay = 1,
			Broken = true,
			SignetsUsed = 0,
		})
		DailyStreak.claim(daily, 102, LENGTH)
		expect(daily.Streak).toBe(1)
		expect(daily.CalendarDay).toBe(1)
	end)

	it("covers one missed day per Signet, and spends none on a gap wider than the Signets held", function()
		local two = claimedOn(100, 9, 9, 2)
		DailyStreak.claim(two, 103, LENGTH)
		expect(two.Streak).toBe(10)
		expect(two.CalendarDay).toBe(10)
		expect(two.Signets).toBe(0)
		local short = claimedOn(100, 9, 9, 1)
		local evaluation = DailyStreak.claim(short, 103, LENGTH)
		expect(evaluation.Broken).toBe(true)
		expect(short.Streak).toBe(1)
		expect(short.CalendarDay).toBe(1)
		-- Kept for a day it can save.
		expect(short.Signets).toBe(1)
	end)

	it("gives its 28th day once, and takes the first again the day after", function()
		local daily = fresh()
		local days: { number } = {}
		for offset = 0, LENGTH - 1 do
			table.insert(days, DailyStreak.claim(daily, 1000 + offset, LENGTH).NextDay)
		end
		expect(days[LENGTH]).toBe(LENGTH)
		local lastSeen = 0
		for _, day in ipairs(days) do
			if day == LENGTH then
				lastSeen += 1
			end
		end
		expect(lastSeen).toBe(1)
		-- The same day again: nothing, and nothing written.
		local again = DailyStreak.claim(daily, 1000 + LENGTH - 1, LENGTH)
		expect(again.CanClaim).toBe(false)
		expect(daily.CalendarDay).toBe(LENGTH)
		-- The day after: the calendar's first day, the streak going on.
		local next = DailyStreak.claim(daily, 1000 + LENGTH, LENGTH)
		expect(next.NextDay).toBe(1)
		expect(daily.Streak).toBe(LENGTH + 1)
	end)

	it("refuses a claim dated before the last one, on a server whose clock stands behind", function()
		local daily = claimedOn(200, 4, 4, 1)
		local evaluation = DailyStreak.claim(daily, 199, LENGTH)
		expect(evaluation.CanClaim).toBe(false)
		expect(daily).toEqual(claimedOn(200, 4, 4, 1))
	end)

	it("holds no more Signets than the book takes", function()
		local daily = fresh()
		for _ = 1, MAX do
			expect(DailyStreak.addSignet(daily, MAX)).toBe(true)
		end
		expect(DailyStreak.addSignet(daily, MAX)).toBe(false)
		expect(daily.Signets).toBe(MAX)
	end)

	it("reads the streak as it stands today: kept, saved by a Signet, or gone", function()
		expect(DailyStreak.standing(claimedOn(100, 6, 6, 0), 100)).toBe(6)
		expect(DailyStreak.standing(claimedOn(100, 6, 6, 0), 101)).toBe(6)
		expect(DailyStreak.standing(claimedOn(100, 6, 6, 1), 102)).toBe(6)
		expect(DailyStreak.standing(claimedOn(100, 6, 6, 1), 103)).toBe(0)
		expect(DailyStreak.standing(claimedOn(100, 6, 6, 0), 102)).toBe(0)
		expect(DailyStreak.standing(fresh(), 100)).toBe(0)
	end)

	it("counts its weeks from the first day", function()
		expect(DailyStreak.weekOf(1, 7)).toBe(1)
		expect(DailyStreak.weekOf(7, 7)).toBe(1)
		expect(DailyStreak.weekOf(8, 7)).toBe(2)
		expect(DailyStreak.weekOf(28, 7)).toBe(4)
		expect(DailyStreak.weekOf(0, 7)).toBe(1)
	end)
end)

describe("what the calendar pays", function()
	it("runs four weeks, pays every day, and bounds the Signets", function()
		expect(LENGTH).toBe(28)
		expect(LENGTH % DailyConfig.WeekLength).toBe(0)
		for _, day in ipairs(DailyConfig.Calendar) do
			expect(day.Folios).toBeGreaterThan(0)
			expect(day.Xp).toBeGreaterThan(0)
		end
		expect(MAX).toBeGreaterThanOrEqual(1)
		expect(MAX).toBeLessThanOrEqual(3)
		expect(DailyConfig.OwnedCosmeticFolios).toBeGreaterThan(0)
		expect(DailyConfig.PremiumBonus.Folios).toBeGreaterThan(0)
	end)

	it("gives a cosmetic on days 7, 14, 21 and 28 alone, each one never sold and each its own", function()
		local seen: { [string]: boolean } = {}
		local days: { number } = {}
		for index, day in ipairs(DailyConfig.Calendar) do
			local cosmeticId = day.Cosmetic
			if cosmeticId ~= nil then
				table.insert(days, index)
				local item = CosmeticConfig.ById[cosmeticId]
				if item == nil then
					error(("day %d gives the unknown cosmetic %s"):format(index, cosmeticId))
				end
				expect(item.Sellable).toBe(false)
				expect(seen[cosmeticId]).toBeNil()
				seen[cosmeticId] = true
			end
		end
		expect(days).toEqual({ 7, 14, 21, 28 })
	end)

	it("slips a Signet in once a week, never on a cosmetic's day", function()
		local signetDays = 0
		for index, day in ipairs(DailyConfig.Calendar) do
			if day.Signet then
				signetDays += 1
				expect(day.Cosmetic).toBeNil()
				expect(index % DailyConfig.WeekLength).never.toBe(0)
			end
		end
		expect(signetDays).toBe(LENGTH / DailyConfig.WeekLength)
	end)
end)

describe("the other dailies", function()
	it("tracks first win and premium bonus per day", function()
		local daily = fresh()
		expect(DailyStreak.firstWinAvailable(daily, 50)).toBe(true)
		expect(DailyStreak.markFirstWin(daily, 50)).toBe(true)
		expect(DailyStreak.markFirstWin(daily, 50)).toBe(false)
		expect(DailyStreak.firstWinAvailable(daily, 51)).toBe(true)
		expect(DailyStreak.markPremiumBonus(daily, 50)).toBe(true)
		expect(DailyStreak.premiumBonusAvailable(daily, 50)).toBe(false)
	end)
end)

return nil
