--!strict
-- Daily login streak, first win of the day, Premium bonus. Pure data.

export type StreakReward = { Folios: number, Xp: number }

local DailyConfig = {}

-- Reward for consecutive login days; day 8+ cycles back to entry 1 while the streak keeps counting.
DailyConfig.Streak = {
	{ Folios = 50, Xp = 100 },
	{ Folios = 75, Xp = 150 },
	{ Folios = 100, Xp = 200 },
	{ Folios = 125, Xp = 250 },
	{ Folios = 150, Xp = 300 },
	{ Folios = 200, Xp = 400 },
	{ Folios = 300, Xp = 600 },
} :: { StreakReward }

-- Bonus for Roblox Premium members, once per day.
DailyConfig.PremiumBonus = { Folios = 150, Xp = 300 }

return DailyConfig
