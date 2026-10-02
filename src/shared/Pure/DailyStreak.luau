--!strict
-- The login calendar (E15-S1): a streak of consecutive days, a calendar of DailyConfig.Calendar's days it walks
-- through, and the Signets that keep it through a day missed. First win of the day and the Premium daily bonus
-- are counted here too. Pure module: no require, no Roblox global.
--
-- The streak counts the days claimed in a row; the calendar day is the last one of the calendar claimed, and the
-- next claim takes the one after it, back to the first once the last is taken. A day missed breaks both, unless
-- the profile holds a Signet for it: one Signet keeps the streak through one missed day, and a gap wider than the
-- Signets held breaks it and spends none.

export type DailyData = {
	LastClaimDay: number,
	Streak: number,
	CalendarDay: number,
	Signets: number,
	FirstWinDay: number,
	PremiumBonusDay: number,
}
-- What claiming today would do: whether it can, the streak and the calendar day it leaves, whether a streak that
-- was going is lost, and the Signets it spends to keep it.
export type Evaluation = {
	CanClaim: boolean,
	NextStreak: number,
	NextDay: number,
	Broken: boolean,
	SignetsUsed: number,
}

local DailyStreak = {}

local SECONDS_PER_DAY = 86400

function DailyStreak.dayIndex(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

-- Whether the profile has a streak going at all: one claimed day at least.
local function going(daily: DailyData): boolean
	return daily.Streak > 0 and daily.LastClaimDay > 0
end

-- The days missed between the last claim and `today`, neither counted.
local function missedDays(daily: DailyData, today: number): number
	return today - daily.LastClaimDay - 1
end

-- What claiming today would do, on a calendar of `length` days. A last claim dated today or after -- after, on a
-- server whose clock stands behind the one that wrote it -- is a claim already taken: claiming again would pay a
-- day twice and read the streak as broken.
function DailyStreak.evaluate(daily: DailyData, today: number, length: number): Evaluation
	if daily.LastClaimDay >= today then
		return {
			CanClaim = false,
			NextStreak = daily.Streak,
			NextDay = daily.CalendarDay,
			Broken = false,
			SignetsUsed = 0,
		}
	end
	if not going(daily) then
		return { CanClaim = true, NextStreak = 1, NextDay = 1, Broken = false, SignetsUsed = 0 }
	end
	local missed = missedDays(daily, today)
	if missed > math.max(daily.Signets, 0) then
		return { CanClaim = true, NextStreak = 1, NextDay = 1, Broken = true, SignetsUsed = 0 }
	end
	return {
		CanClaim = true,
		NextStreak = daily.Streak + 1,
		NextDay = math.max(daily.CalendarDay, 0) % math.max(length, 1) + 1,
		Broken = false,
		SignetsUsed = missed,
	}
end

-- Claims today's calendar day: writes the streak, the day and the Signets spent. Returns the evaluation it
-- applied; nothing was written when it cannot claim.
function DailyStreak.claim(daily: DailyData, today: number, length: number): Evaluation
	local evaluation = DailyStreak.evaluate(daily, today, length)
	if not evaluation.CanClaim then
		return evaluation
	end
	daily.LastClaimDay = today
	daily.Streak = evaluation.NextStreak
	daily.CalendarDay = evaluation.NextDay
	daily.Signets -= evaluation.SignetsUsed
	return evaluation
end

-- Slips one Signet into the book, never past `max`. Returns whether one was added.
function DailyStreak.addSignet(daily: DailyData, max: number): boolean
	if daily.Signets >= max then
		return false
	end
	daily.Signets = math.max(daily.Signets, 0) + 1
	return true
end

-- The streak as it stands today: the one kept, or 0 once the days missed are more than the Signets can cover.
function DailyStreak.standing(daily: DailyData, today: number): number
	if not going(daily) or missedDays(daily, today) > math.max(daily.Signets, 0) then
		return 0
	end
	return daily.Streak
end

-- Which week of the calendar `day` falls in, weeks of `week` days: 1 for the first.
function DailyStreak.weekOf(day: number, week: number): number
	return math.floor((math.max(day, 1) - 1) / week) + 1
end

function DailyStreak.firstWinAvailable(daily: DailyData, today: number): boolean
	return daily.FirstWinDay ~= today
end

function DailyStreak.markFirstWin(daily: DailyData, today: number): boolean
	if not DailyStreak.firstWinAvailable(daily, today) then
		return false
	end
	daily.FirstWinDay = today
	return true
end

function DailyStreak.premiumBonusAvailable(daily: DailyData, today: number): boolean
	return daily.PremiumBonusDay ~= today
end

function DailyStreak.markPremiumBonus(daily: DailyData, today: number): boolean
	if not DailyStreak.premiumBonusAvailable(daily, today) then
		return false
	end
	daily.PremiumBonusDay = today
	return true
end

return DailyStreak
