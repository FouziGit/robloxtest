--!strict
-- The day's ranked opponents of one profile (Pure/OpponentLedger, D-255): what a pair of accounts that meet
-- again and again is counted by. tests/RankedFarm.spec.luau plays the rule through the real services.
local Harness = require("./harness")
local OpponentLedger = require("../src/server/Pure/OpponentLedger")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local TODAY = 20500

describe("OpponentLedger", function()
	it("counts today's matches against one opponent, and nothing of another day", function()
		local ledger = { Day = TODAY, Counts = { ["102"] = 3 } }
		expect(OpponentLedger.count(ledger, TODAY, 102)).toBe(3)
		expect(OpponentLedger.count(ledger, TODAY, 103)).toBe(0)
		expect(OpponentLedger.count(ledger, TODAY + 1, 102)).toBe(0)
		expect(OpponentLedger.count({ Day = TODAY, Counts = { ["102"] = -4 } }, TODAY, 102)).toBe(0)
	end)

	it("adds one match against each opponent, and never writes into the ledger it was given", function()
		local ledger = { Day = TODAY, Counts = { ["102"] = 2 } }
		local next = OpponentLedger.record(ledger, TODAY, { 102, 103 })
		expect(next).toEqual({ Day = TODAY, Counts = { ["102"] = 3, ["103"] = 1 } })
		expect(ledger).toEqual({ Day = TODAY, Counts = { ["102"] = 2 } })
	end)

	it("starts a new day over, forgetting yesterday's opponents", function()
		local ledger = { Day = TODAY - 1, Counts = { ["102"] = 9, ["104"] = 2 } }
		expect(OpponentLedger.record(ledger, TODAY, { 102 })).toEqual({ Day = TODAY, Counts = { ["102"] = 1 } })
	end)

	it("keys a test account's negative id like any other", function()
		local ledger = OpponentLedger.record({ Day = 0, Counts = {} }, TODAY, { -2 })
		expect(OpponentLedger.count(ledger, TODAY, -2)).toBe(1)
	end)

	it("numbers a meeting past the higher of the two sides' counts", function()
		local mine = { Day = TODAY, Counts = { ["102"] = 2 } }
		local theirs = { Day = TODAY, Counts = { ["101"] = 5 } }
		expect(OpponentLedger.meeting(mine, theirs, TODAY, 101, 102)).toBe(6)
		expect(OpponentLedger.meeting(theirs, mine, TODAY, 102, 101)).toBe(6)
		-- A side whose profile is not here counts for nothing; the other still holds the pair.
		expect(OpponentLedger.meeting(mine, nil, TODAY, 101, 102)).toBe(3)
		expect(OpponentLedger.meeting({ Day = 0, Counts = {} }, theirs, TODAY, 101, 102)).toBe(6)
	end)

	it("calls a meeting a repeat only past the day's full matches", function()
		expect(OpponentLedger.isRepeat(5, 5)).toBe(false)
		expect(OpponentLedger.isRepeat(6, 5)).toBe(true)
		expect(OpponentLedger.isRepeat(1, 5)).toBe(false)
	end)
end)
