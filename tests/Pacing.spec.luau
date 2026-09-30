--!strict
-- The pacing of the game held to its ceilings (E10-S4, E10-S5): scripts/pacing.luau plays four players for
-- sixty days through the real configs and the very rules the server runs (TrialPay, DailyCap, QuestLogic,
-- ShopRotation), and this gate fails the day a change to a reward, a cap or a cost breaks what the game promises.
--
-- - The safest thing in the game is not the best paid: an hour of Trials pays under 30 % of the XP of an hour of
--   duels, a day of them no more Folios than their cap, and no pass at all.
-- - A pass lasts a Volume: a player at 20 minutes a day finishes it between day 28 and day 42, one at an hour a
--   day not before day 15.
-- - The numbers docs/ECONOMY.md, docs/GAME_DESIGN.md and docs/economy/ quote are the ones the simulator gives.
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local Pacing = require("../scripts/pacing")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local RESULTS = Pacing.all()
local BY_ID: { [string]: Pacing.Result } = {}
for _, result in ipairs(RESULTS) do
	BY_ID[result.Profile.Id] = result
end

local function strip(path: string): string
	return (fs.readFile(path):gsub("%-%-[^\n]*", ""))
end

describe("the pacing of sixty days", function()
	it("plays the four profiles E10-S4 names, for sixty days", function()
		expect(#RESULTS).toBe(4)
		expect(BY_ID.Solo20.Profile.Minutes).toEqual({
			{ Activity = "Trials", Minutes = 5 },
			{ Activity = "Forgers", Minutes = 15 },
		})
		expect(BY_ID.Pvp20.Profile.Minutes).toEqual({ { Activity = "Duel", Minutes = 20 } })
		expect(BY_ID.Pvp60.Profile.Minutes).toEqual({ { Activity = "Duel", Minutes = 60 } })
		expect(BY_ID.Farmer.Profile.Minutes).toEqual({ { Activity = "Trials", Minutes = 60 } })
		for _, result in ipairs(RESULTS) do
			expect(#result.Days).toBe(60)
			local minutes = 0
			for _, entry in ipairs(result.Profile.Minutes) do
				minutes += entry.Minutes
			end
			-- Every day is played in full, and no day runs more than one fight over.
			local last = result.Days[60].Minutes
			expect(last).toBeGreaterThanOrEqual(60 * minutes)
			expect(last).toBeLessThan(60 * minutes + 60 * 5)
		end
	end)

	it("keeps an hour of Trials under 30 % of the XP of an hour of duels", function()
		local trials = BY_ID.Farmer.XpPerHour.Trials
		local duels = BY_ID.Pvp60.XpPerHour.Duel
		expect(duels).toBeGreaterThan(0)
		expect(trials).toBeGreaterThan(0)
		expect(trials / duels).toBeLessThan(0.3)
		-- Twenty minutes of duels pay at the rate an hour does: the rate is the activity's, not the session's.
		expect(math.abs(BY_ID.Pvp20.XpPerHour.Duel - duels) / duels).toBeLessThan(0.05)
	end)

	it("pays a day of Trials no more Folios than their cap, and no pass", function()
		local farmer = BY_ID.Farmer
		expect(farmer.ActivityFolios.Trials).toBe(60 * GameConfig.Enemy.Pay.DailyFolioCap)
		-- The farmer's pass moves on its streak and its quests alone, and never ends inside sixty days; a proof
		-- brings the pass nothing, a duel and a Forger do.
		expect(farmer.PassDay).toBeNil()
		expect(farmer.ActivityPassXp.Trials).toBeNil()
		expect(BY_ID.Solo20.ActivityPassXp.Trials).toBeNil()
		expect(BY_ID.Solo20.ActivityPassXp.Forgers).toBeGreaterThan(0)
		expect(BY_ID.Pvp20.ActivityPassXp.Duel).toBeGreaterThan(0)
		expect(farmer.Days[60].Tier).toBeLessThan(BattlepassConfig.MaxTier)
	end)

	it("finishes the pass between day 28 and day 42 at 20 minutes a day, and after day 14 at an hour", function()
		for _, id in ipairs({ "Solo20", "Pvp20" }) do
			local day = BY_ID[id].PassDay
			assert(day ~= nil, id .. " never finishes the pass")
			expect(day).toBeGreaterThanOrEqual(28)
			expect(day).toBeLessThanOrEqual(42)
		end
		local hour = BY_ID.Pvp60.PassDay
		assert(hour ~= nil, "an hour a day never finishes the pass")
		expect(hour).toBeGreaterThan(14)
	end)

	it("says every figure E10-S4 asks for", function()
		for _, result in ipairs(RESULTS) do
			for _, level in ipairs({ 5, 10, 20, 40 }) do
				expect(result.MinutesToLevel[level]).never.toBeNil()
			end
			expect(result.MinutesToLevel[5]).toBeLessThanOrEqual(result.MinutesToLevel[10])
			expect(result.MinutesToLevel[10]).toBeLessThanOrEqual(result.MinutesToLevel[20])
			expect(result.MinutesToLevel[20]).toBeLessThanOrEqual(result.MinutesToLevel[40])
			expect(result.FoliosByDay7).toBeGreaterThan(0)
			expect(result.FoliosByDay30).toBeGreaterThan(result.FoliosByDay7)
		end
		-- An hour a day of duels owns everything a player can earn without Robux before a player at 20 minutes.
		local hour, twenty = BY_ID.Pvp60.CatalogueDay, BY_ID.Pvp20.CatalogueDay
		assert(hour ~= nil, "an hour a day never completes the catalogue")
		expect(twenty == nil or (twenty :: number) > hour).toBe(true)
	end)
end)

describe("the simulator", function()
	it("reads the real configs and runs the rules the server runs", function()
		local script = strip("scripts/pacing.luau")
		for _, path in ipairs({
			"../src/shared/Config/BattlepassConfig",
			"../src/shared/Config/BotConfig",
			"../src/shared/Config/CombatConfig",
			"../src/shared/Config/CosmeticConfig",
			"../src/shared/Config/DailyConfig",
			"../src/shared/Config/GameConfig",
			"../src/shared/Config/GlyphConfig",
			"../src/shared/Config/MatchConfig",
			"../src/shared/Config/ProgressionConfig",
			"../src/shared/Config/QuestConfig",
			"../src/shared/Config/ShopConfig",
			"../src/server/Pure/DailyCap",
			"../src/shared/Pure/QuestLogic",
			"../src/shared/Pure/ShopRotation",
			"../src/server/Pure/TrialPay",
		}) do
			expect(script:find('require("' .. path .. '")', 1, true)).never.toBeNil()
		end
		for _, rule in ipairs({
			"TrialPay.kill(player.Daily.Trial, today, ENEMY.Pay, XP.DummyKill, FOLIOS.DummyKill, DailyCap.take)",
			"DailyCap.take(daily.ForgerDay, daily.ForgerFolios, today, BotConfig.Credit.DailyFolioCap, FOLIOS[target.RewardKey])",
			"if PASS_EXCLUDED[reason] or player.Tier >= BattlepassConfig.MaxTier then",
			"BattlepassConfig.xpForTier(player.Tier)",
			"ProgressionConfig.xpForLevel(player.Level)",
			'QuestLogic.reroll(rules, "Daily", set, quest.Id)',
			"QuestLogic.select(QuestConfig.Pool, period, count, periodSet.PeriodKey, QuestConfig.SoloFloor)",
		}) do
			-- Read without whitespace, so a call the formatter spread over lines still reads as one.
			if (script:gsub("%s+", "")):find((rule:gsub("%s+", "")), 1, true) == nil then
				error(("scripts/pacing.luau no longer runs %q"):format(rule))
			end
		end
	end)

	it("keeps docs/economy/pacing.csv what the configs give today", function()
		local path = "docs/economy/pacing.csv"
		expect(fs.isFile(path)).toBe(true)
		if fs.readFile(path) ~= Pacing.csv(RESULTS) then
			error(path .. " is out of date: run `lune run scripts/pacing -- --csv`")
		end
	end)
end)
