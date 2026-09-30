--!strict
-- The login calendar and its Signets (E15-S1), first win of the day, Premium bonus. Pure data.

-- One day of the calendar: what claiming it pays, the cosmetic it gives on the last day of a week (never sold:
-- CosmeticConfig marks each one Sellable = false), and whether it slips a Signet into the book.
export type CalendarDay = { Folios: number, Xp: number, Cosmetic: string?, Signet: boolean? }
export type PremiumBonus = { Folios: number, BoostMinutes: number }

local DailyConfig = {}

-- Twenty-eight days, four weeks of seven, claimed one a day; the day after the last is the first again, and a day
-- missed with no Signet to cover it starts over from the first (Pure/DailyStreak). Each week pays the old seven-day
-- streak's rising row a little higher than the week before, and ends on a cosmetic; the third day of each slips a
-- Signet in. A month is about 4,450 Folios and 8,000 XP (docs/ECONOMY.md §2).
DailyConfig.Calendar = {
	{ Folios = 50, Xp = 100 },
	{ Folios = 75, Xp = 150 },
	{ Folios = 100, Xp = 200, Signet = true },
	{ Folios = 125, Xp = 250 },
	{ Folios = 150, Xp = 300 },
	{ Folios = 200, Xp = 400 },
	{ Folios = 150, Xp = 600, Cosmetic = "TitleFaithfulHand" },
	{ Folios = 75, Xp = 100 },
	{ Folios = 100, Xp = 150 },
	{ Folios = 125, Xp = 200, Signet = true },
	{ Folios = 150, Xp = 250 },
	{ Folios = 175, Xp = 300 },
	{ Folios = 225, Xp = 400 },
	{ Folios = 175, Xp = 600, Cosmetic = "TrailRibbon" },
	{ Folios = 100, Xp = 100 },
	{ Folios = 125, Xp = 150 },
	{ Folios = 150, Xp = 200, Signet = true },
	{ Folios = 175, Xp = 250 },
	{ Folios = 200, Xp = 300 },
	{ Folios = 250, Xp = 400 },
	{ Folios = 200, Xp = 600, Cosmetic = "TitleKeeperOfDays" },
	{ Folios = 125, Xp = 100 },
	{ Folios = 150, Xp = 150 },
	{ Folios = 175, Xp = 200, Signet = true },
	{ Folios = 200, Xp = 250 },
	{ Folios = 225, Xp = 300 },
	{ Folios = 275, Xp = 400 },
	{ Folios = 225, Xp = 600, Cosmetic = "AuraSignet" },
} :: { CalendarDay }

-- The calendar's weeks, for the screen that shows one at a time.
DailyConfig.WeekLength = 7

-- The Signets a profile holds at most. One keeps the streak through one missed day; a gap wider than the Signets
-- held breaks it and spends none. Never sold, only earned on the calendar's Signet days.
DailyConfig.MaxSignets = 2

-- What a day whose cosmetic is already owned pays instead, on top of its own Folios: the second month of the
-- calendar, or a cosmetic the grant could not give.
DailyConfig.OwnedCosmeticFolios = 300

-- Bonus for Roblox Premium members, once per UTC day: Folios and a timed double-XP boost (docs/ECONOMY.md §6).
DailyConfig.PremiumBonus = { Folios = 150, BoostMinutes = 30 } :: PremiumBonus

return DailyConfig
