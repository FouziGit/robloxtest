--!strict
-- The quick duel for newcomers (E10-S7): a player's matches count for rank once they have reached level 10 and
-- played 5 matches, and the Play screen says which is missing and how far off it is (Pure/RankedGate).
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local RankedGate = require("../src/shared/Pure/RankedGate")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local RULES = MatchConfig.Newcomer

describe("RankedGate", function()
	it("keeps the first five matches unranked, whatever the level", function()
		for played = 0, 4 do
			local status = RankedGate.status(played, 30, RULES)
			expect(status.Ranked).toBe(false)
			expect(status.MatchesLeft).toBe(5 - played)
			expect(status.LevelsLeft).toBe(0)
		end
		expect(RankedGate.status(5, 30, RULES).Ranked).toBe(true)
	end)

	it("opens ranked at level 10, whatever the matches played", function()
		expect(RankedGate.status(40, 9, RULES)).toEqual({ Ranked = false, LevelsLeft = 1, MatchesLeft = 0 })
		expect(RankedGate.status(40, 1, RULES)).toEqual({ Ranked = false, LevelsLeft = 9, MatchesLeft = 0 })
		expect(RankedGate.status(40, 10, RULES)).toEqual({ Ranked = true, LevelsLeft = 0, MatchesLeft = 0 })
	end)

	it("says both when both are missing, and never counts below nothing", function()
		expect(RankedGate.status(2, 7, RULES)).toEqual({ Ranked = false, LevelsLeft = 3, MatchesLeft = 3 })
		expect(RankedGate.status(0, 1, RULES)).toEqual({ Ranked = false, LevelsLeft = 9, MatchesLeft = 5 })
		expect(RankedGate.status(99, 99, RULES)).toEqual({ Ranked = true, LevelsLeft = 0, MatchesLeft = 0 })
	end)
end)
