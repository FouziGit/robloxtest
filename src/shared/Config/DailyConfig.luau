--!strict
-- Daily login streak, first win of the day, Premium bonus. Pure data.

export type StreakReward = { Ryo: number, Xp: number }

local DailyConfig = {}

-- Reward for consecutive login days; day 8+ cycles back to entry 1 while the streak keeps counting.
DailyConfig.Streak = {
	{ Ryo = 50, Xp = 100 },
	{ Ryo = 75, Xp = 150 },
	{ Ryo = 100, Xp = 200 },
	{ Ryo = 125, Xp = 250 },
	{ Ryo = 150, Xp = 300 },
	{ Ryo = 200, Xp = 400 },
	{ Ryo = 300, Xp = 600 },
} :: { StreakReward }

-- Bonus for Roblox Premium members, once per day.
DailyConfig.PremiumBonus = { Ryo = 150, Xp = 300 }

return DailyConfig
