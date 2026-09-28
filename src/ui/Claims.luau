--!strict
-- Claims: what the player has waiting right now, counted over the day, the quest periods and the battle-pass
-- season running at `unixTime` (Claimables, D-147). Everything in the interface that badges a claim counts
-- through here -- the HUD's Menu button and claim seals, the daily reward that opens by itself -- so they
-- agree with each other and with the services that grant the claims. Callers pass the server's clock
-- (Workspace:GetServerTimeNow()): the day turns when the servers say it does, not when the player's own
-- clock does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Pure = Shared:WaitForChild("Pure")

local BattlepassConfig = require(Config:WaitForChild("BattlepassConfig"))
local Claimables = require(Pure:WaitForChild("Claimables"))
local DailyStreak = require(Pure:WaitForChild("DailyStreak"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local QuestLogic = require(Pure:WaitForChild("QuestLogic"))

local Claims = {}

local SECONDS_PER_DAY = 86400
-- Past the turn of the day by this much, so a count made on the stroke of midnight sees the new day.
local TURN_MARGIN_SECONDS = 1
-- The client hears the servers' clock a moment after it starts; until then GetServerTimeNow() is 0.
local CLOCK_RETRY_SECONDS = 0.5

-- A quest period as it runs at `unixTime`, drawing its quests as the Quests screen and the server do.
local function period(name: QuestLogic.Period, unixTime: number): Claimables.Period
	local count = QuestConfig.Periods[name].Count
	return {
		Live = QuestLogic.periodKey(name, unixTime),
		Select = function(setKey: string): { any }
			return QuestLogic.select(QuestConfig.Pool, name, count, setKey)
		end,
	}
end

-- The day, the two quest periods and the season running at `unixTime`.
function Claims.context(unixTime: number): Claimables.Context
	local season = BattlepassConfig.Seasons[GameConfig.SeasonId]
	return {
		Today = DailyStreak.dayIndex(unixTime),
		Periods = { Daily = period("Daily", unixTime), Weekly = period("Weekly", unixTime) },
		Season = GameConfig.SeasonId,
		Tiers = if season ~= nil then season.Tiers else {},
	}
end

-- Everything `profile` (a Types.ProfileData, or nil before it loads) has waiting at `unixTime`, by kind.
function Claims.count(profile: any, unixTime: number): Claimables.Counts
	return Claimables.count(profile, Claims.context(unixTime))
end

-- Seconds until what waits can change with no change to the profile: the next day's turn, as the servers count
-- days (UTC) -- a daily reward, and the quests of a new period, become claimable then; a week starts on a day's
-- turn too. Before the client has heard the servers' clock (`unixTime` 0), a moment: counted on day 0 there is
-- no daily reward, and the HUD, which counts as the profile arrives, showed none all session (seen in Studio).
function Claims.nextCountIn(unixTime: number): number
	if unixTime <= 0 then
		return CLOCK_RETRY_SECONDS
	end
	return SECONDS_PER_DAY - unixTime % SECONDS_PER_DAY + TURN_MARGIN_SECONDS
end

return Claims
