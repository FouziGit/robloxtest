--!strict
local Harness = require("./harness")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local QuestLogic = require("../src/shared/Pure/QuestLogic")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

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

	-- The quests screen counts down to periodEndsAt: the second it returns has to be the one the key changes
	-- on, and not one second earlier, or the board says "resets in 0m" over a set that stays.
	it("ends a period exactly where its key changes", function()
		local samples = { 0, 1, 86399, 86400, 86401, 3 * 86400, 4 * 86400 - 1, 4 * 86400, 20725 * 86400 + 43210 }
		for week = 0, 13 do
			table.insert(samples, 2960 * 7 * 86400 + week * 86400 + week * 3607)
		end
		for _, period in ipairs({ "Daily", "Weekly" } :: { QuestLogic.Period }) do
			local span = if period == "Daily" then 86400 else 7 * 86400
			for _, now in ipairs(samples) do
				local ends = QuestLogic.periodEndsAt(period, now)
				local key = QuestLogic.periodKey(period, now)
				expect(ends).toBeGreaterThan(now)
				expect(ends - now).toBeLessThanOrEqual(span)
				expect(QuestLogic.periodKey(period, ends - 1)).toBe(key)
				expect(QuestLogic.periodKey(period, ends)).never.toBe(key)
			end
		end
		-- 1970-01-01 was a Thursday: its week ends at the Monday that opens week 1, and its day at midnight.
		expect(QuestLogic.periodEndsAt("Weekly", 0)).toBe(4 * 86400)
		expect(QuestLogic.periodEndsAt("Daily", 86400 * 10 + 5)).toBe(86400 * 11)
		-- At a boundary the period that just began is the one counted down.
		expect(QuestLogic.periodEndsAt("Daily", 86400)).toBe(2 * 86400)
		expect(QuestLogic.periodEndsAt("Weekly", 4 * 86400)).toBe(11 * 86400)
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
			{ Id = "A", Period = "Daily", Event = "GlyphCast", Target = 3, NameKey = "quest.castGlyphs" },
			{ Id = "B", Period = "Daily", Event = "MatchWin", Target = 1, NameKey = "quest.winMatches" },
		}
		local set = newSet("D1")
		expect(QuestLogic.applyEvent(set, quests, "GlyphCast", 2)).toEqual({})
		expect(QuestLogic.applyEvent(set, quests, "GlyphCast", 5)).toEqual({ "A" })
		expect(set.Progress.A).toBe(3)
		expect(QuestLogic.applyEvent(set, quests, "GlyphCast", 1)).toEqual({})
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

-- A deploy that grows the pool must not redraw a period already under way: players who had claimed
-- today's quests were handed new ones to claim again. A set keeps the pool revision it was drawn from.
describe("QuestLogic pool revisions", function()
	-- Every revision's pool, in pool order. A revision is only ever appended here: removing or moving
	-- an entry would change the draw of sets already stored.
	local LAUNCH = {
		"DailyCastGlyphs",
		"DailyHitGlyphs",
		"DailyDummies",
		"DailyWin",
		"DailyPlay",
		"DailyDamage",
		"DailyDash",
		"DailyMelee",
		"DailyChain",
		"DailyCancel",
		"WeeklyWins",
		"WeeklyKills",
		"WeeklyBoss",
		"WeeklyCasts",
		"WeeklyDamage",
	}
	local FORGERS = table.clone(LAUNCH)
	table.insert(FORGERS, 11, "DailyForgers")
	local PINNED = { LAUNCH, FORGERS }

	local function idsOf(quests: { QuestConfig.QuestDef }): { string }
		local ids = {}
		for _, def in ipairs(quests) do
			table.insert(ids, def.Id)
		end
		return ids
	end

	-- The pool as it stood at `revision`, rebuilt from the pinned ids rather than from `Since`, and
	-- without any `Since`: a plain pool, drawn the way every pool was before revisions existed.
	local function poolAt(revision: number): { QuestConfig.QuestDef }
		local byId = {}
		for _, def in ipairs(QuestConfig.Pool) do
			local plain = table.clone(def)
			plain.Since = nil
			byId[def.Id] = plain
		end
		local pool = {}
		for _, id in ipairs(PINNED[revision]) do
			table.insert(pool, byId[id])
		end
		return pool
	end

	-- The first day from D20000 whose draw differs between `revision` - 1 and `revision`.
	local function dayRedrawnBy(revision: number): number
		for day = 20000, 20400 do
			local before = QuestLogic.select(QuestConfig.Pool, "Daily", 3, QuestLogic.setKey("D" .. day, revision - 1))
			local after = QuestLogic.select(QuestConfig.Pool, "Daily", 3, QuestLogic.setKey("D" .. day, revision))
			if table.concat(idsOf(before), ",") ~= table.concat(idsOf(after), ",") then
				return day
			end
		end
		error("no day in D20000..D20400 is redrawn by revision " .. revision .. ": this test would prove nothing")
	end

	it("pins each revision's pool", function()
		expect(#PINNED).toBe(QuestConfig.PoolRevision)
		for revision = 1, QuestConfig.PoolRevision do
			local ids = {}
			for _, def in ipairs(QuestConfig.Pool) do
				if (def.Since or 1) <= revision then
					table.insert(ids, def.Id)
				end
			end
			expect(ids).toEqual(PINNED[revision])
		end
		for _, def in ipairs(QuestConfig.Pool) do
			if def.Since ~= nil then
				expect(def.Since).toBeGreaterThanOrEqual(2)
				expect(def.Since).toBeLessThanOrEqual(QuestConfig.PoolRevision)
				expect(def.Since).toBe(math.floor(def.Since))
			end
		end
	end)

	it("names the revision in the key from the second pool on", function()
		expect(QuestLogic.setKey("D20725", 1)).toBe("D20725")
		expect(QuestLogic.setKey("D20725", 2)).toBe("D20725@2")
		expect(QuestLogic.setKey("W2960", 3)).toBe("W2960@3")
	end)

	it("draws every key of a revision from that revision's pool alone", function()
		for revision = 1, QuestConfig.PoolRevision do
			local pool = poolAt(revision)
			for day = 20000, 20400 do
				local key = QuestLogic.setKey("D" .. day, revision)
				expect(idsOf(QuestLogic.select(QuestConfig.Pool, "Daily", 3, key))).toEqual(
					idsOf(QuestLogic.select(pool, "Daily", 3, "D" .. day))
				)
			end
			for week = 2900, 2960 do
				local key = QuestLogic.setKey("W" .. week, revision)
				expect(idsOf(QuestLogic.select(QuestConfig.Pool, "Weekly", 3, key))).toEqual(
					idsOf(QuestLogic.select(pool, "Weekly", 3, "W" .. week))
				)
			end
		end
	end)

	it("keeps a set drawn before the pool grew until its period ends", function()
		local day = dayRedrawnBy(QuestConfig.PoolRevision)
		local stored = "D" .. day
		local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, stored)
		local set = newSet(stored)
		for _, def in ipairs(drawn) do
			set.Progress[def.Id] = def.Target
			set.Claimed[def.Id] = true
		end

		-- The deploy: the live key now carries the grown pool's revision, on the same day.
		local live = QuestLogic.setKey(stored, QuestConfig.PoolRevision)
		expect(QuestLogic.ensurePeriod(set, live)).toBe(false)
		expect(set.PeriodKey).toBe(stored)
		local kept = QuestLogic.select(QuestConfig.Pool, "Daily", 3, set.PeriodKey)
		expect(idsOf(kept)).toEqual(idsOf(drawn))
		-- The quests the grown pool would have drawn today are not in the set, so none can be claimed.
		local keptIds = idsOf(kept)
		local newcomers = 0
		for _, def in ipairs(QuestLogic.select(QuestConfig.Pool, "Daily", 3, live)) do
			if not table.find(keptIds, def.Id) then
				newcomers += 1
			end
		end
		expect(newcomers).toBeGreaterThan(0)
		for _, def in ipairs(kept) do
			expect(QuestLogic.canClaim(set, def)).toBe(false)
		end

		-- The next day is drawn from the grown pool.
		local tomorrow = QuestLogic.setKey("D" .. (day + 1), QuestConfig.PoolRevision)
		expect(QuestLogic.ensurePeriod(set, tomorrow)).toBe(true)
		expect(set.PeriodKey).toBe(tomorrow)
		expect(set.Claimed).toEqual({})
		expect(QuestLogic.ensurePeriod(set, tomorrow)).toBe(false)
	end)

	-- The server is where the rule holds or not: drawn from the live key, a set kept from before the deploy
	-- gets the grown pool's quests, and the claims start over. Read as text, since Lune cannot run a service.
	it("has QuestService draw every set from the key it stores", function()
		local source = (fs.readFile("src/server/Services/QuestService.luau"):gsub("%-%-[^\n]*", ""))
		local function body(header: string): string
			local start = source:find(header, 1, true)
			if start == nil then
				error(("QuestService has no %s: this gate would check nothing"):format(header))
			end
			local finish = source:find("\nend\n", start, true)
			return (source:sub(start, finish or #source):gsub("%s+", " "))
		end
		local ensure = body("local function ensureSet(")
		expect(ensure).toContain("QuestLogic.setKey(QuestLogic.periodKey(period, now), QuestConfig.PoolRevision)")
		expect(ensure).toContain("if QuestLogic.ensurePeriod(set, setKey) then")
		expect(ensure).toContain("return set, questsFor(period, set.PeriodKey)")
		expect(body("local function questsFor(")).toContain(
			"QuestLogic.select(QuestConfig.Pool, period, PERIOD_DEFS[period].Count, setKey)"
		)
		-- One draw, one caller of it: no other path reaches the quests by the live key.
		local _, draws = source:gsub("QuestLogic%.select%(", "")
		local _, uses = source:gsub("questsFor%(", "")
		expect(draws).toBe(1)
		expect(uses).toBe(2)
	end)

	it("has the quests screen draw a keyless set at the revision the server will store", function()
		local source = (fs.readFile("src/ui/screens/QuestsScreen.luau"):gsub("%-%-[^\n]*", ""))
		local start = source:find("local function activeQuests(", 1, true)
		if start == nil then
			error("QuestsScreen has no activeQuests: this gate would check nothing")
		end
		local finish = source:find("\n\tend\n", start, true)
		local active = (source:sub(start, finish or #source):gsub("%s+", " "))
		expect(active).toContain("QuestLogic.setKey(QuestLogic.periodKey(typed, os.time()), QuestConfig.PoolRevision)")
		local _, bare = active:gsub("else QuestLogic%.periodKey%(", "")
		expect(bare).toBe(0)
	end)
end)
