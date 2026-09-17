--!strict
local Harness = require("./harness")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local QuestLogic = require("../src/shared/Pure/QuestLogic")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function newSet(key: string)
	return { PeriodKey = key, Progress = {}, Claimed = {} }
end

describe("QuestLogic", function()
	it("computes day and week keys", function()
		expect(QuestLogic.dayIndex(0)).toBe(0)
		expect(QuestLogic.dayIndex(86399)).toBe(0)
		expect(QuestLogic.dayIndex(86400)).toBe(1)
		-- 1970-01-05 (Monday) starts week 1; 1970-01-04 (Sunday) is still week 0
		expect(QuestLogic.weekIndex(4 * 86400)).toBe(1)
		expect(QuestLogic.weekIndex(3 * 86400)).toBe(0)
		expect(QuestLogic.periodKey("Daily", 86400 * 10)).toBe("D10")
		expect(QuestLogic.periodKey("Weekly", 86400 * 10)).toBe("W1")
	end)

	it("selects deterministic distinct quests per period", function()
		local a = QuestLogic.select(QuestConfig.Pool, "Daily", 3, "D100")
		local b = QuestLogic.select(QuestConfig.Pool, "Daily", 3, "D100")
		local c = QuestLogic.select(QuestConfig.Pool, "Daily", 3, "D101")
		expect(a).toHaveLength(3)
		expect(a).toEqual(b)
		local seen = {}
		for _, def in ipairs(a) do
			expect(def.Period).toBe("Daily")
			expect(seen[def.Id]).toBeNil()
			seen[def.Id] = true
		end
		local same = true
		for index = 1, 3 do
			if a[index].Id ~= c[index].Id then
				same = false
			end
		end
		expect(same).toBe(false)
		expect(QuestLogic.select(QuestConfig.Pool, "Weekly", 99, "W1")).toHaveLength(5)
	end)

	it("resets when the period changes", function()
		local set = newSet("D1")
		set.Progress.X = 5
		set.Claimed.X = true
		expect(QuestLogic.ensurePeriod(set, "D1")).toBe(false)
		expect(QuestLogic.ensurePeriod(set, "D2")).toBe(true)
		expect(set.Progress).toEqual({})
		expect(set.Claimed).toEqual({})
	end)

	it("tracks progress, completion and claims", function()
		local quests = {
			{ Id = "A", Period = "Daily", Event = "JutsuCast", Target = 3, NameKey = "quest.castJutsus" },
			{ Id = "B", Period = "Daily", Event = "MatchWin", Target = 1, NameKey = "quest.winMatches" },
		}
		local set = newSet("D1")
		expect(QuestLogic.applyEvent(set, quests, "JutsuCast", 2)).toEqual({})
		expect(QuestLogic.applyEvent(set, quests, "JutsuCast", 5)).toEqual({ "A" })
		expect(set.Progress.A).toBe(3)
		expect(QuestLogic.applyEvent(set, quests, "JutsuCast", 1)).toEqual({})
		expect(QuestLogic.applyEvent(set, quests, "Nope", 1)).toEqual({})
		expect(QuestLogic.applyEvent(set, quests, "MatchWin", 0)).toEqual({})
		expect(QuestLogic.canClaim(set, quests[1])).toBe(true)
		expect(QuestLogic.canClaim(set, quests[2])).toBe(false)
		expect(QuestLogic.claim(set, quests[1])).toBe(true)
		expect(QuestLogic.claim(set, quests[1])).toBe(false)
		local status = QuestLogic.status(set, quests)
		expect(status[1]).toEqual({ Id = "A", Progress = 3, Target = 3, Claimed = true, Completed = true })
		expect(status[2]).toEqual({ Id = "B", Progress = 0, Target = 1, Claimed = false, Completed = false })
	end)

	it("has a valid pool", function()
		local ids = {}
		for _, def in ipairs(QuestConfig.Pool) do
			expect(ids[def.Id]).toBeNil()
			ids[def.Id] = true
			expect(def.Target).toBeGreaterThan(0)
			expect(Strings.has(def.NameKey)).toBe(true)
		end
		expect(#QuestLogic.select(QuestConfig.Pool, "Daily", QuestConfig.Periods.Daily.Count, "D1")).toBe(3)
		expect(#QuestLogic.select(QuestConfig.Pool, "Weekly", QuestConfig.Periods.Weekly.Count, "W1")).toBe(3)
	end)
end)
