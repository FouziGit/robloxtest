--!strict
-- Daily login streak, first win of the day and Premium daily bonus. Pure module.

export type DailyData = { LastClaimDay: number, Streak: number, FirstWinDay: number, PremiumBonusDay: number }
export type Evaluation = { CanClaim: boolean, NextStreak: number, Broken: boolean }

local DailyStreak = {}

local SECONDS_PER_DAY = 86400

function DailyStreak.dayIndex(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

-- What claiming today would do: keep the streak going, start over, or nothing (already claimed).
function DailyStreak.evaluate(daily: DailyData, today: number): Evaluation
	if daily.LastClaimDay == today then
		return { CanClaim = false, NextStreak = daily.Streak, Broken = false }
	end
	if daily.LastClaimDay == today - 1 then
		return { CanClaim = true, NextStreak = daily.Streak + 1, Broken = false }
	end
	return { CanClaim = true, NextStreak = 1, Broken = daily.Streak > 0 }
end

-- Claims today's reward. Returns the streak day granted (0 when nothing was claimable).
function DailyStreak.claim(daily: DailyData, today: number): number
	local evaluation = DailyStreak.evaluate(daily, today)
	if not evaluation.CanClaim then
		return 0
	end
	daily.LastClaimDay = today
	daily.Streak = evaluation.NextStreak
	return daily.Streak
end

-- Reward entry for a streak day; cycles through the table after its last entry.
function DailyStreak.rewardIndex(streak: number, tableSize: number): number
	if tableSize <= 0 or streak <= 0 then
		return 1
	end
	return ((streak - 1) % tableSize) + 1
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
