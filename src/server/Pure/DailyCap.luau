--!strict
-- A daily allowance kept in the profile: the Folios the Forgers pay (BotConfig.Credit.DailyFolioCap) and the
-- practice fights against the Erasure that pay at all (WorldBossConfig.Practice.RewardsPerDay). Pure module:
-- no require, no Roblox global.
--
-- The count lives in the profile beside the day it belongs to (Types.DailyData), never in a server's memory:
-- an in-memory cap is escaped by switching server. A count from any other day than today is a count of zero.

local DailyCap = {}

-- Takes up to `want` from today's allowance. `day` and `used` are what the profile holds, `today` the current
-- day index (DailyStreak.dayIndex). Returns what was granted -- all of `want`, the part of it still under the
-- cap, or nothing -- and today's new count. The caller writes back `today` and that count.
function DailyCap.take(day: number, used: number, today: number, cap: number, want: number): (number, number)
	local already = if day == today then math.max(used, 0) else 0
	local room = math.max(cap - already, 0)
	local granted = math.min(math.max(want, 0), room)
	return granted, already + granted
end

return DailyCap
