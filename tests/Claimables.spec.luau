--!strict
-- What a player has waiting (D-147), counted the way the server grants it. Every badge, claim seal and the
-- daily reward's own opening read Claimables, so a count that drifts from the server's rules shows a "!"
-- on something that cannot be claimed, or hides what can.
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local Claimables = require("../src/shared/Pure/Claimables")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local QuestLogic = require("../src/shared/Pure/QuestLogic")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- A fixed instant, and the day it falls on.
local NOW = 1790000000
local TODAY = QuestLogic.dayIndex(NOW)
local SEASON = GameConfig.SeasonId
local TIERS = BattlepassConfig.Seasons[SEASON].Tiers

local function period(name: QuestLogic.Period): Claimables.Period
	return {
		Live = QuestLogic.periodKey(name, NOW),
		Select = function(setKey: string): { any }
			return QuestLogic.select(QuestConfig.Pool, name, QuestConfig.Periods[name].Count, setKey)
		end,
	}
end

local CONTEXT: Claimables.Context = {
	Today = TODAY,
	Periods = { Daily = period("Daily"), Weekly = period("Weekly") },
	Season = SEASON,
	Tiers = TIERS,
}

local function emptySet(key: string): Claimables.QuestSet
	return { PeriodKey = key, Progress = {}, Claimed = {} }
end

local function liveKey(name: QuestLogic.Period): string
	return QuestLogic.setKey(QuestLogic.periodKey(name, NOW), QuestConfig.PoolRevision)
end

local function season(tier: number, premium: boolean): Claimables.Season
	return { XP = 0, Tier = tier, Premium = premium, ClaimedFree = {}, ClaimedPremium = {} }
end

local function profile(): any
	return {
		Daily = { LastClaimDay = TODAY },
		Quests = { Daily = emptySet(liveKey("Daily")), Weekly = emptySet(liveKey("Weekly")) },
		Battlepass = {},
	}
end

-- What the server would let this set's owner claim right now: QuestService.claim's own test.
local function serverQuests(set: Claimables.QuestSet, name: QuestLogic.Period): number
	local count = 0
	for _, def in ipairs(QuestLogic.select(QuestConfig.Pool, name, QuestConfig.Periods[name].Count, set.PeriodKey)) do
		if QuestLogic.canClaim(set :: any, def) then
			count += 1
		end
	end
	return count
end

describe("the daily reward", function()
	it("waits when it was last claimed before today, and only then", function()
		local p = profile()
		p.Daily.LastClaimDay = TODAY - 1
		expect(Claimables.daily(p, TODAY)).toBe(true)
		p.Daily.LastClaimDay = 0
		expect(Claimables.daily(p, TODAY)).toBe(true)
		p.Daily.LastClaimDay = TODAY
		expect(Claimables.daily(p, TODAY)).toBe(false)
		-- A server a day ahead of this clock has already paid today.
		p.Daily.LastClaimDay = TODAY + 1
		expect(Claimables.daily(p, TODAY)).toBe(false)
		expect(Claimables.daily(nil, TODAY)).toBe(false)
	end)
end)

describe("the quests", function()
	it("count the completed and unclaimed ones of the running set, as the server would", function()
		for _, name in ipairs({ "Daily", "Weekly" } :: { QuestLogic.Period }) do
			local set = emptySet(liveKey(name))
			local quests = CONTEXT.Periods[name].Select(set.PeriodKey)
			expect(#quests).toBe(QuestConfig.Periods[name].Count)
			expect(Claimables.quests(set, CONTEXT.Periods[name])).toBe(0)
			-- The first done, the second done and claimed, the third half done.
			set.Progress[quests[1].Id] = quests[1].Target
			set.Progress[quests[2].Id] = quests[2].Target
			set.Claimed[quests[2].Id] = true
			set.Progress[quests[3].Id] = math.max(0, quests[3].Target - 1)
			expect(Claimables.quests(set, CONTEXT.Periods[name])).toBe(1)
			expect(Claimables.quests(set, CONTEXT.Periods[name])).toBe(serverQuests(set, name))
			-- Progress on a quest that is not in the set counts nothing.
			set.Progress.NotInTheSet = 1000
			expect(Claimables.quests(set, CONTEXT.Periods[name])).toBe(1)
		end
	end)

	it("count none in a set of a period that has ended, or a set never drawn", function()
		local set = emptySet(QuestLogic.setKey(QuestLogic.periodKey("Daily", NOW - 86400), QuestConfig.PoolRevision))
		for _, quest in
			ipairs(QuestLogic.select(QuestConfig.Pool, "Daily", QuestConfig.Periods.Daily.Count, set.PeriodKey))
		do
			set.Progress[quest.Id] = quest.Target
		end
		expect(Claimables.quests(set, CONTEXT.Periods.Daily)).toBe(0)
		expect(Claimables.quests(emptySet(""), CONTEXT.Periods.Daily)).toBe(0)
	end)

	it("read a set drawn at any pool revision as its period's", function()
		for revision = 1, 3 do
			local set = emptySet(QuestLogic.setKey(QuestLogic.periodKey("Weekly", NOW), revision))
			local quests = CONTEXT.Periods.Weekly.Select(set.PeriodKey)
			set.Progress[quests[1].Id] = quests[1].Target
			expect(Claimables.quests(set, CONTEXT.Periods.Weekly)).toBe(1)
		end
	end)
end)

describe("the battle pass", function()
	it("counts the free rewards of the tiers reached and not yet claimed", function()
		local s = season(3, false)
		expect(Claimables.pass(s, TIERS)).toBe(3)
		s.ClaimedFree["2"] = true
		expect(Claimables.pass(s, TIERS)).toBe(2)
		expect(Claimables.pass(season(0, false), TIERS)).toBe(0)
		expect(Claimables.pass(nil, TIERS)).toBe(0)
	end)

	it("counts the premium track only for a player who owns it", function()
		local owner = season(3, true)
		expect(Claimables.pass(owner, TIERS)).toBe(6)
		owner.ClaimedPremium["1"] = true
		expect(Claimables.pass(owner, TIERS)).toBe(5)
		expect(Claimables.pass(season(3, false), TIERS)).toBe(3)
	end)

	it("counts no reward a tier does not have, and no tier past the last", function()
		local tiers: { Claimables.Tier } =
			{ { Free = { Kind = "Folios", Amount = 50 } }, { Premium = { Kind = "XpBoost", Minutes = 30 } } }
		expect(Claimables.pass(season(2, false), tiers)).toBe(1)
		expect(Claimables.pass(season(2, true), tiers)).toBe(2)
		local free = 0
		for _, def in ipairs(TIERS) do
			if def.Free ~= nil then
				free += 1
			end
		end
		expect(free).toBeGreaterThan(0)
		expect(Claimables.pass(season(BattlepassConfig.MaxTier + 5, false), TIERS)).toBe(free)
	end)
end)

describe("the totals", function()
	it("add up what is waiting, and nothing for a profile not loaded", function()
		local p = profile()
		p.Daily.LastClaimDay = TODAY - 3
		local quests = CONTEXT.Periods.Daily.Select(p.Quests.Daily.PeriodKey)
		p.Quests.Daily.Progress[quests[1].Id] = quests[1].Target
		local weekly = CONTEXT.Periods.Weekly.Select(p.Quests.Weekly.PeriodKey)
		p.Quests.Weekly.Progress[weekly[1].Id] = weekly[1].Target
		p.Quests.Weekly.Progress[weekly[2].Id] = weekly[2].Target
		p.Battlepass[SEASON] = season(2, true)
		local counts = Claimables.count(p, CONTEXT)
		expect(counts.Daily).toBe(1)
		expect(counts.Quests).toBe(3)
		expect(counts.Pass).toBe(4)
		expect(counts.Total).toBe(8)
		-- Another season's progress is not this one's.
		p.Battlepass = { Elsewhere = season(10, true) }
		expect(Claimables.count(p, CONTEXT).Pass).toBe(0)
		local none = Claimables.count(nil, CONTEXT)
		expect(none).toEqual({ Daily = 0, Quests = 0, Pass = 0, Total = 0 })
	end)
end)
