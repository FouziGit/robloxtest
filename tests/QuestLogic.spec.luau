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
			-- A quest of one does not count it in the plural: "Win 1 matches" (seen in Studio).
			if def.Target == 1 then
				for _, words in pairs((Strings.Table :: any)[def.NameKey]) do
					if string.find(words, "{target}", 1, true) ~= nil then
						error(("%s counts its one in %q"):format(def.Id, words))
					end
				end
			end
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
	local SOLO_WEEK = table.clone(FORGERS)
	table.insert(SOLO_WEEK, "WeeklyForgers")
	table.insert(SOLO_WEEK, "WeeklyChains")
	table.insert(SOLO_WEEK, "WeeklyMelee")
	local PINNED = { LAUNCH, FORGERS, SOLO_WEEK }
	local FLOOR = QuestConfig.SoloFloor

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

	-- The first day from D20000 whose draw differs between `revision` - 1 and `revision`, drawn as the server
	-- draws (with the Solo floor).
	local function dayRedrawnBy(revision: number): number
		for day = 20000, 20400 do
			local before =
				QuestLogic.select(QuestConfig.Pool, "Daily", 3, QuestLogic.setKey("D" .. day, revision - 1), FLOOR)
			local after =
				QuestLogic.select(QuestConfig.Pool, "Daily", 3, QuestLogic.setKey("D" .. day, revision), FLOOR)
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

	-- Before the floor's revision a key draws what a plain pool drew before revisions (and the floor) existed;
	-- from it on, what that revision's pool alone draws under the same key and floor.
	it("draws every key of a revision from that revision's pool alone", function()
		for revision = 1, QuestConfig.PoolRevision do
			local pool = poolAt(revision)
			for day = 20000, 20400 do
				local key = QuestLogic.setKey("D" .. day, revision)
				local expected = if revision < FLOOR.Since
					then QuestLogic.select(pool, "Daily", 3, "D" .. day)
					else QuestLogic.select(pool, "Daily", 3, key, FLOOR)
				expect(idsOf(QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR))).toEqual(idsOf(expected))
			end
			for week = 2900, 2960 do
				local key = QuestLogic.setKey("W" .. week, revision)
				local expected = if revision < FLOOR.Since
					then QuestLogic.select(pool, "Weekly", 3, "W" .. week)
					else QuestLogic.select(pool, "Weekly", 3, key, FLOOR)
				expect(idsOf(QuestLogic.select(QuestConfig.Pool, "Weekly", 3, key, FLOOR))).toEqual(idsOf(expected))
			end
		end
	end)

	-- The draws of the first two revisions over a year of days and weeks, fingerprinted before the Solo floor
	-- existed: a floor that reached back into them would redraw quests already played, and claimed.
	it("keeps every draw of revisions 1 and 2 exactly as it was", function()
		local function fingerprint(text: string): number
			local value = 2166136261
			for index = 1, #text do
				value = (bit32.bxor(value, string.byte(text, index)) * 16777619) % 4294967296
			end
			return value
		end
		local PRINTS = {
			{ Daily = 2889474368, Weekly = 563148400 },
			{ Daily = 515310871, Weekly = 563148400 },
		}
		for revision, prints in ipairs(PRINTS) do
			local days, weeks = {}, {}
			for day = 20000, 20364 do
				local key = QuestLogic.setKey("D" .. day, revision)
				table.insert(
					days,
					table.concat(idsOf(QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR)), ",")
				)
			end
			for week = 2860, 2911 do
				local key = QuestLogic.setKey("W" .. week, revision)
				table.insert(
					weeks,
					table.concat(idsOf(QuestLogic.select(QuestConfig.Pool, "Weekly", 3, key, FLOOR)), ",")
				)
			end
			expect(fingerprint(table.concat(days, ","))).toBe(prints.Daily)
			expect(fingerprint(table.concat(weeks, ","))).toBe(prints.Weekly)
		end
	end)

	it("keeps a set drawn before the pool grew until its period ends", function()
		local day = dayRedrawnBy(QuestConfig.PoolRevision)
		local stored = "D" .. day
		local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, stored, FLOOR)
		local set = newSet(stored)
		for _, def in ipairs(drawn) do
			set.Progress[def.Id] = def.Target
			set.Claimed[def.Id] = true
		end

		-- The deploy: the live key now carries the grown pool's revision, on the same day.
		local live = QuestLogic.setKey(stored, QuestConfig.PoolRevision)
		expect(QuestLogic.ensurePeriod(set, live)).toBe(false)
		expect(set.PeriodKey).toBe(stored)
		local kept = QuestLogic.select(QuestConfig.Pool, "Daily", 3, set.PeriodKey, FLOOR)
		expect(idsOf(kept)).toEqual(idsOf(drawn))
		-- The quests the grown pool would have drawn today are not in the set, so none can be claimed.
		local keptIds = idsOf(kept)
		local newcomers = 0
		for _, def in ipairs(QuestLogic.select(QuestConfig.Pool, "Daily", 3, live, FLOOR)) do
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
		expect(ensure).toContain(
			"return set, QuestLogic.swapped(QuestConfig.Pool, questsFor(period, set.PeriodKey), set.Swaps)"
		)
		expect(body("local function questsFor(")).toContain(
			"QuestLogic.select(QuestConfig.Pool, period, PERIOD_DEFS[period].Count, setKey, QuestConfig.SoloFloor)"
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
		expect(active).toContain(
			"local drawn = QuestLogic.select(QuestConfig.Pool, typed, periodDef(period).Count, key, QuestConfig.SoloFloor)"
		)
		expect(active).toContain("return QuestLogic.swapped(QuestConfig.Pool, drawn, set.Swaps)")
	end)
end)

-- A player alone on a server could draw two quests that need others (a match, a player to defeat, the Erasure's
-- event) and finish one of three. From revision 3 each quest says what it needs, every draw holds at least two
-- a player alone can finish, and one free reroll a day swaps a daily quest for another of those (E10-S10).
describe("QuestLogic Solo quests and the free reroll", function()
	local FLOOR = QuestConfig.SoloFloor
	-- The quest events that cannot happen with nobody else on the server.
	local NEEDS_OTHERS =
		{ MatchWin = true, MatchPlayed = true, PlayerKill = true, BossParticipation = true, BossKill = true }

	local function soloCount(quests: { QuestConfig.QuestDef }): number
		local count = 0
		for _, def in ipairs(quests) do
			if def.Needs == "Solo" then
				count += 1
			end
		end
		return count
	end

	local function ids(quests: { QuestConfig.QuestDef }): { string }
		local list = {}
		for _, def in ipairs(quests) do
			table.insert(list, def.Id)
		end
		return list
	end

	local function rules(period: QuestConfig.Period): QuestLogic.RerollRules
		return {
			Pool = QuestConfig.Pool,
			Count = QuestConfig.Periods[period].Count,
			Floor = FLOOR,
			Allowance = QuestConfig.Rerolls[period],
		}
	end

	local function freshSet(key: string): QuestLogic.SetData
		return { PeriodKey = key, Progress = {}, Claimed = {}, Swaps = {} }
	end

	it("tags every quest Solo or Players, Players exactly where the event needs others", function()
		for _, def in ipairs(QuestConfig.Pool) do
			expect(def.Needs == "Solo" or def.Needs == "Players").toBe(true)
			expect(def.Needs == "Players").toBe(NEEDS_OTHERS[def.Event] == true)
		end
		expect(QuestConfig.PoolRevision).toBe(3)
		expect(FLOOR).toEqual({ Since = 3, Count = 2 })
		expect(QuestConfig.Rerolls).toEqual({ Daily = 1, Weekly = 0 })
	end)

	it("holds at least two Solo quests in every draw of revision 3, over 365 days and 52 weeks", function()
		local floored = 0
		for day = 20000, 20364 do
			local key = QuestLogic.setKey("D" .. day, 3)
			local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR)
			expect(#drawn).toBe(3)
			expect(soloCount(drawn)).toBeGreaterThanOrEqual(2)
			if soloCount(QuestLogic.select(QuestConfig.Pool, "Daily", 3, key)) < 2 then
				floored += 1
			end
		end
		for week = 2860, 2911 do
			local key = QuestLogic.setKey("W" .. week, 3)
			local drawn = QuestLogic.select(QuestConfig.Pool, "Weekly", 3, key, FLOOR)
			expect(#drawn).toBe(3)
			expect(soloCount(drawn)).toBeGreaterThanOrEqual(2)
			if soloCount(QuestLogic.select(QuestConfig.Pool, "Weekly", 3, key)) < 2 then
				floored += 1
			end
		end
		-- Without the floor some of these draws held fewer: the floor is what holds them.
		expect(floored).toBeGreaterThan(0)
	end)

	-- A short draw gives up its last Players quests and nothing else: the quests drawn first keep their slots.
	it("gives a short draw its Solo quests in the place of its last Players quests", function()
		local shortDraws = 0
		for _, period in ipairs({ "Daily", "Weekly" } :: { QuestConfig.Period }) do
			local first, last, letter = 20000, 20364, "D"
			if period == "Weekly" then
				first, last, letter = 2860, 2911, "W"
			end
			for index = first, last do
				local key = QuestLogic.setKey(letter .. index, 3)
				local plain = QuestLogic.select(QuestConfig.Pool, period, 3, key)
				local floored = QuestLogic.select(QuestConfig.Pool, period, 3, key, FLOOR)
				local missing = math.max(FLOOR.Count - soloCount(plain), 0)
				if missing > 0 then
					shortDraws += 1
				end
				for slot = #plain, 1, -1 do
					if missing > 0 and plain[slot].Needs == "Players" then
						missing -= 1
						expect(floored[slot].Needs).toBe("Solo")
					else
						expect(floored[slot].Id).toBe(plain[slot].Id)
					end
				end
			end
		end
		expect(shortDraws).toBeGreaterThan(10)
	end)

	it("leaves a draw that already holds its Solo quests as it would have been", function()
		local kept = 0
		for day = 20000, 20364 do
			local key = QuestLogic.setKey("D" .. day, 3)
			local plain = QuestLogic.select(QuestConfig.Pool, "Daily", 3, key)
			if soloCount(plain) >= 2 then
				kept += 1
				expect(ids(QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR))).toEqual(ids(plain))
			end
		end
		expect(kept).toBeGreaterThan(300)
	end)

	it("swaps a daily quest for a Solo one not drawn today, in its place, and forgets its progress", function()
		for day = 20000, 20364 do
			local key = QuestLogic.setKey("D" .. day, 3)
			local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR)
			for slot, sent in ipairs(drawn) do
				local set = freshSet(key)
				set.Progress[sent.Id] = sent.Target - 1
				local verdict, taken = QuestLogic.reroll(rules("Daily"), "Daily", set, sent.Id)
				expect(verdict).toBe("Rerolled")
				assert(taken ~= nil, "a reroll that says Rerolled drew nothing")
				expect(taken.Needs).toBe("Solo")
				expect(taken.Period).toBe("Daily")
				expect(table.find(ids(drawn), taken.Id)).toBeNil()
				expect(set.Swaps).toEqual({ [sent.Id] = taken.Id })
				expect(set.Progress[sent.Id]).toBeNil()
				local live = QuestLogic.swapped(QuestConfig.Pool, drawn, set.Swaps)
				expect(live[slot].Id).toBe(taken.Id)
				for other = 1, #drawn do
					if other ~= slot then
						expect(live[other].Id).toBe(drawn[other].Id)
					end
				end
				-- Another player sending the same quest away today draws the same one.
				local again = freshSet(key)
				local _, same = QuestLogic.reroll(rules("Daily"), "Daily", again, sent.Id)
				expect((same :: QuestConfig.QuestDef).Id).toBe(taken.Id)
			end
		end
	end)

	it("draws the replacement by the quest sent away, not by the day alone", function()
		local differ = 0
		for day = 20000, 20364 do
			local key = QuestLogic.setKey("D" .. day, 3)
			local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR)
			local taken: { [string]: boolean } = {}
			local kinds = 0
			for _, sent in ipairs(drawn) do
				local _, def = QuestLogic.reroll(rules("Daily"), "Daily", freshSet(key), sent.Id)
				local id = (def :: QuestConfig.QuestDef).Id
				if not taken[id] then
					taken[id] = true
					kinds += 1
				end
			end
			if kinds > 1 then
				differ += 1
			end
		end
		expect(differ).toBeGreaterThan(100)
	end)

	it("refuses a claimed, a completed, an absent quest, and a second reroll the same day", function()
		local key = QuestLogic.setKey("D20100", 3)
		local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR)

		local claimed = freshSet(key)
		claimed.Progress[drawn[1].Id] = drawn[1].Target
		claimed.Claimed[drawn[1].Id] = true
		expect((QuestLogic.reroll(rules("Daily"), "Daily", claimed, drawn[1].Id))).toBe("Claimed")
		expect(claimed.Swaps).toEqual({})

		local completed = freshSet(key)
		completed.Progress[drawn[2].Id] = drawn[2].Target
		expect((QuestLogic.reroll(rules("Daily"), "Daily", completed, drawn[2].Id))).toBe("Completed")
		expect(completed.Progress[drawn[2].Id]).toBe(drawn[2].Target)

		local absent = freshSet(key)
		local outsider = nil
		for _, def in ipairs(QuestConfig.Pool) do
			if def.Period == "Daily" and table.find(ids(drawn), def.Id) == nil then
				outsider = def
			end
		end
		assert(outsider ~= nil, "every daily quest is drawn: this case would check nothing")
		expect((QuestLogic.reroll(rules("Daily"), "Daily", absent, outsider.Id))).toBe("NotLive")
		expect((QuestLogic.reroll(rules("Daily"), "Daily", absent, "NoSuchQuest"))).toBe("NotLive")

		local spent = freshSet(key)
		local _, taken = QuestLogic.reroll(rules("Daily"), "Daily", spent, drawn[1].Id)
		expect(QuestLogic.rerollsLeft(spent, rules("Daily").Allowance)).toBe(0)
		expect((QuestLogic.reroll(rules("Daily"), "Daily", spent, drawn[2].Id))).toBe("Spent")
		-- Nor the quest the reroll brought in, which would swap the day's quests round and round.
		expect((QuestLogic.reroll(rules("Daily"), "Daily", spent, (taken :: QuestConfig.QuestDef).Id))).toBe("Spent")
		expect(spent.Swaps).toEqual({ [drawn[1].Id] = (taken :: QuestConfig.QuestDef).Id })

		-- With a reroll still left, the quest a reroll brought in stays: a slot is swapped once.
		local roomy: QuestLogic.RerollRules = table.clone(rules("Daily"))
		roomy.Allowance = 2
		local once = freshSet(key)
		local _, brought = QuestLogic.reroll(roomy, "Daily", once, drawn[3].Id)
		expect(QuestLogic.rerollsLeft(once, roomy.Allowance)).toBe(1)
		expect((QuestLogic.reroll(roomy, "Daily", once, (brought :: QuestConfig.QuestDef).Id))).toBe("Spent")
		expect((QuestLogic.reroll(roomy, "Daily", once, drawn[1].Id))).toBe("Rerolled")

		-- A weekly quest has no free reroll: QuestConfig.Rerolls.Weekly is none.
		local weekKey = QuestLogic.setKey("W2900", 3)
		local week = QuestLogic.select(QuestConfig.Pool, "Weekly", 3, weekKey, FLOOR)
		expect((QuestLogic.reroll(rules("Weekly"), "Weekly", freshSet(weekKey), week[1].Id))).toBe("Spent")
	end)

	it("never draws a quest this period already drew or sent away, and says so when none is left", function()
		local pool: { QuestConfig.QuestDef } = {
			{ Id = "A", Period = "Daily", Event = "Dash", Target = 1, NameKey = "quest.useDash", Needs = "Solo" },
			{ Id = "B", Period = "Daily", Event = "Chain", Target = 1, NameKey = "quest.chainCasts", Needs = "Solo" },
			{
				Id = "C",
				Period = "Daily",
				Event = "MatchWin",
				Target = 1,
				NameKey = "quest.winMatch",
				Needs = "Players",
			},
			{ Id = "D", Period = "Daily", Event = "MeleeHit", Target = 1, NameKey = "quest.landMelee", Needs = "Solo" },
			{
				Id = "E",
				Period = "Daily",
				Event = "MatchPlayed",
				Target = 1,
				NameKey = "quest.playMatches",
				Needs = "Players",
			},
		}
		local twice: QuestLogic.RerollRules = { Pool = pool, Count = 3, Floor = FLOOR, Allowance = 2 }
		for day = 20000, 20100 do
			local key = QuestLogic.setKey("D" .. day, 3)
			local drawn = QuestLogic.select(pool, "Daily", 3, key, FLOOR)
			local set = freshSet(key)
			local seen = {}
			for _, def in ipairs(drawn) do
				seen[def.Id] = true
			end
			-- The two Solo quests left out of a draw of three are at most one: the first reroll takes it, if any.
			local verdict, taken = QuestLogic.reroll(twice, "Daily", set, drawn[1].Id)
			if verdict == "Rerolled" then
				local id = (taken :: QuestConfig.QuestDef).Id
				expect(seen[id]).toBeNil()
				seen[id] = true
				local second = QuestLogic.reroll(twice, "Daily", set, drawn[2].Id)
				expect(second).toBe("NoCandidate")
			else
				expect(verdict).toBe("NoCandidate")
			end
			expect(QuestLogic.rerollsLeft(set, 2)).toBeGreaterThanOrEqual(1)
		end
	end)

	-- A swap is kept in the profile, and the pool it names may not be the one a server runs (a build rolled back
	-- mid-day): the quest drawn stays in its slot rather than leaving a hole in the list.
	it("plays the quest drawn in the place of a swap to a quest the pool does not have", function()
		local key = QuestLogic.setKey("D20100", 3)
		local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, key, FLOOR)
		local live = QuestLogic.swapped(QuestConfig.Pool, drawn, { [drawn[2].Id] = "NoSuchQuest" })
		expect(#live).toBe(#drawn)
		expect(ids(live)).toEqual(ids(drawn))
	end)

	it("clears the swaps with the rest of the set when the period turns", function()
		local set = freshSet("D20100@3")
		local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", 3, set.PeriodKey, FLOOR)
		QuestLogic.reroll(rules("Daily"), "Daily", set, drawn[1].Id)
		expect(next(set.Swaps)).never.toBeNil()
		expect(QuestLogic.ensurePeriod(set, "D20101@3")).toBe(true)
		expect(set.Swaps).toEqual({})
		expect(QuestLogic.rerollsLeft(set, QuestConfig.Rerolls.Daily)).toBe(1)
	end)
end)
