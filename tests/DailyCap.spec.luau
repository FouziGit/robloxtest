--!strict
-- The daily allowances kept in the profile (D-131, D-132). A count that survived midnight, or one that could
-- be pushed past its cap by a single large grant, is a farm: the Forgers' Folios and the Erasure's practice
-- pay would have no ceiling at all.
local BotConfig = require("../src/shared/Config/BotConfig")
local DailyCap = require("../src/server/Pure/DailyCap")
local Harness = require("./harness")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local TODAY = 20000

describe("DailyCap.take", function()
	it("grants in full under the cap and counts it", function()
		local granted, used = DailyCap.take(TODAY, 10, TODAY, 150, 4)
		expect(granted).toBe(4)
		expect(used).toBe(14)
	end)

	it("starts a new day from nothing, whatever yesterday's count", function()
		local granted, used = DailyCap.take(TODAY - 1, 150, TODAY, 150, 4)
		expect(granted).toBe(4)
		expect(used).toBe(4)
		-- A day in the future (a clock that moved back) is not today either.
		local again = DailyCap.take(TODAY + 3, 150, TODAY, 150, 1)
		expect(again).toBe(1)
	end)

	it("grants only what is left under the cap, then nothing", function()
		local granted, used = DailyCap.take(TODAY, 148, TODAY, 150, 4)
		expect(granted).toBe(2)
		expect(used).toBe(150)
		local more, still = DailyCap.take(TODAY, used, TODAY, 150, 4)
		expect(more).toBe(0)
		expect(still).toBe(150)
	end)

	it("grants nothing on a count already past a cap that was lowered, and keeps that count", function()
		local granted, used = DailyCap.take(TODAY, 160, TODAY, 150, 4)
		expect(granted).toBe(0)
		expect(used).toBe(160)
	end)

	it("never grants a negative amount, nor counts a corrupt negative one", function()
		local granted, used = DailyCap.take(TODAY, 5, TODAY, 150, -3)
		expect(granted).toBe(0)
		expect(used).toBe(5)
		local fromBroken, counted = DailyCap.take(TODAY, -40, TODAY, 150, 4)
		expect(fromBroken).toBe(4)
		expect(counted).toBe(4)
	end)

	it("holds the shipped caps: a day of Forgers and a day of practices", function()
		-- Kill after kill at the richest Forger's pay, for a whole day on one profile.
		local cap = BotConfig.Credit.DailyFolioCap
		local richest = 0
		for _, tier in pairs(BotConfig.Tiers) do
			richest = math.max(richest, ProgressionConfig.Folios[tier.RewardKey])
		end
		local used, paid = 0, 0
		for _ = 1, 500 do
			local granted
			granted, used = DailyCap.take(TODAY, used, TODAY, cap, richest)
			paid += granted
		end
		expect(paid).toBe(cap)
		local practices = WorldBossConfig.Practice.RewardsPerDay
		local count, fights = 0, 0
		for _ = 1, practices + 5 do
			local granted
			granted, count = DailyCap.take(TODAY, count, TODAY, practices, 1)
			fights += granted
		end
		expect(fights).toBe(practices)
	end)
end)
