--!strict
-- What a player has waiting to be collected right now (D-147): today's daily reward, the completed quests
-- of the running periods, the battle-pass tiers reached. Pure module: no requires, no Roblox globals; the
-- configs and the running period come in the context the client builds. A menu tile's badge, a claim seal
-- in the hub, the Menu's total and the daily reward that opens by itself all count here, so they agree with
-- each other and with what the server would grant (QuestService, BattlepassService, DailyRewardService).

-- `Swaps` are the set's rerolls (QuestLogic.reroll); a set that never rerolled may carry none.
export type QuestSet = {
	PeriodKey: string,
	Progress: { [string]: number },
	Claimed: { [string]: boolean },
	Swaps: { [string]: string }?,
}
-- The profile's season record exactly (Types.BattlepassSeasonData), so the profile's own is accepted.
export type Season = {
	XP: number,
	Tier: number,
	Premium: boolean,
	ClaimedFree: { [string]: boolean },
	ClaimedPremium: { [string]: boolean },
}
-- A pass tier: its reward on each track, when the track has one.
export type Tier = { Free: any?, Premium: any? }
-- One period of quests as it stands now.
export type Period = {
	-- The key of the period running now, without a pool revision (QuestLogic.periodKey).
	Live: string,
	-- The quests a set plays, from its key and its swaps: QuestLogic.select over QuestConfig.Pool at the
	-- period's count and floor, each rerolled quest in its replacement's place (QuestLogic.swapped), as they
	-- come (each with an Id and a Target; an array of a narrower record would not accept them).
	Select: (setKey: string, swaps: { [string]: string }?) -> { any },
}
export type Context = {
	-- Today, in days since the epoch (DailyStreak.dayIndex).
	Today: number,
	Periods: { Daily: Period, Weekly: Period },
	-- The running season (GameConfig.SeasonId) and its tiers (BattlepassConfig.Seasons[season].Tiers).
	Season: string,
	Tiers: { Tier },
}
export type Counts = { Daily: number, Quests: number, Pass: number, Total: number }

local Claimables = {}

-- A whole profile (`daily`, `count`) is a Types.ProfileData, or nil before it loads, and is typed loosely on
-- purpose: a pure module cannot require Types, and no narrower record accepts the profile's, whose nested
-- records are compared field for field. What is read from it goes through the typed functions below.

-- The period a set's key names, without the pool revision it was drawn at: "D20725@2" is "D20725"
-- (QuestLogic.setKey).
local function periodOf(setKey: string): string
	return string.match(setKey, "^(.-)@%d+$") or setKey
end

-- Whether today's daily reward is still to be claimed.
function Claimables.daily(profile: any, today: number): boolean
	return profile ~= nil and profile.Daily.LastClaimDay < today
end

-- The completed, unclaimed quests of `set`. A set of a period that has ended counts none: the server
-- resets it before anything in it can be claimed. Nor does a set never drawn, whose key is empty.
function Claimables.quests(set: QuestSet, period: Period): number
	if periodOf(set.PeriodKey) ~= period.Live then
		return 0
	end
	local count = 0
	for _, quest in ipairs(period.Select(set.PeriodKey, set.Swaps)) do
		if not set.Claimed[quest.Id] and (set.Progress[quest.Id] or 0) >= quest.Target then
			count += 1
		end
	end
	return count
end

-- The rewards waiting on the tiers `season` has reached: every free one not yet claimed, and the premium
-- ones only for a player who owns the premium pass.
function Claimables.pass(season: Season?, tiers: { Tier }): number
	if season == nil then
		return 0
	end
	local count = 0
	for tier = 1, math.min(season.Tier, #tiers) do
		local def = tiers[tier]
		local key = tostring(tier)
		if def.Free ~= nil and not season.ClaimedFree[key] then
			count += 1
		end
		if season.Premium and def.Premium ~= nil and not season.ClaimedPremium[key] then
			count += 1
		end
	end
	return count
end

-- Everything waiting, by kind, and in all. Nothing for a profile not loaded yet.
function Claimables.count(profile: any, context: Context): Counts
	if profile == nil then
		return { Daily = 0, Quests = 0, Pass = 0, Total = 0 }
	end
	local daily = if Claimables.daily(profile, context.Today) then 1 else 0
	local quests = Claimables.quests(profile.Quests.Daily, context.Periods.Daily)
		+ Claimables.quests(profile.Quests.Weekly, context.Periods.Weekly)
	local pass = Claimables.pass(profile.Battlepass[context.Season], context.Tiers)
	return { Daily = daily, Quests = quests, Pass = pass, Total = daily + quests + pass }
end

return Claimables
