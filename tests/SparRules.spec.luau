--!strict
-- The rules of the practice duel against a Forger (E10-S6, src/server/Pure/SparRules): when it is offered, when the
-- matchmaker may take its player, who takes a round, and what it pays, with the shipped numbers of
-- MatchConfig.Spar.
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local SparRules = require("../src/server/Pure/SparRules")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SPAR = MatchConfig.Spar
local RULES: SparRules.OfferRules = { QueueModeId = SPAR.QueueModeId, OfferAfterSeconds = SPAR.OfferAfterSeconds }

-- A player alone in the 1v1 queue for `waited` seconds, nothing else holding them.
local function alone(waited: number): SparRules.OfferInput
	return {
		QueuedFor = SPAR.QueueModeId,
		WaitedSeconds = waited,
		Others = 0,
		Sparring = false,
		InMatch = false,
		EventLive = false,
		Engaged = false,
	}
end

local function side(alive: boolean, health: number, maxHealth: number): SparRules.Side
	return { Alive = alive, Health = health, MaxHealth = maxHealth }
end

describe("the practice duel's offer", function()
	it("comes after twenty seconds alone in the 1v1 queue, and not a second before", function()
		expect(SPAR.OfferAfterSeconds).toBe(20)
		expect(SPAR.QueueModeId).toBe("Duel1v1")
		expect(SparRules.offered(alone(19.9), RULES)).toBe(false)
		expect(SparRules.offered(alone(20), RULES)).toBe(true)
		expect(SparRules.offered(alone(200), RULES)).toBe(true)
	end)

	it("never comes with somebody else in the queue, in another queue, or out of every queue", function()
		local crowded = alone(60)
		crowded.Others = 1
		expect(SparRules.offered(crowded, RULES)).toBe(false)
		local team = alone(60)
		team.QueuedFor = "Team3v3"
		expect(SparRules.offered(team, RULES)).toBe(false)
		local none = alone(60)
		none.QueuedFor = nil
		expect(SparRules.offered(none, RULES)).toBe(false)
	end)

	it("never comes to a player a spar, a match or the Erasure already holds", function()
		for _, field in ipairs({ "Sparring", "InMatch", "EventLive", "Engaged" }) do
			local held = alone(60) :: any
			held[field] = true
			if SparRules.offered(held, RULES) then
				error(("a spar is offered to a player who is %s"):format(field))
			end
		end
	end)
end)

describe("the practice duel's breaks", function()
	it("let the matchmaker take the player at every one, and never during a round", function()
		expect(SparRules.pairable("Playing")).toBe(false)
		for _, phase in ipairs({ "Countdown", "RoundOver", "Result" }) do
			expect(SparRules.pairable(phase)).toBe(true)
		end
	end)
end)

describe("a round of the practice duel", function()
	it("goes to whoever is still standing, and is a draw when both fall", function()
		expect(SparRules.roundVerdict(side(true, 40, 100), side(false, 0, 160), false)).toBe("Player")
		expect(SparRules.roundVerdict(side(false, 0, 100), side(true, 10, 160), false)).toBe("Forger")
		expect(SparRules.roundVerdict(side(false, 0, 100), side(false, 0, 160), false)).toBe("Draw")
		expect(SparRules.roundVerdict(side(true, 40, 100), side(true, 10, 160), false)).toBeNil()
	end)

	it("goes on the timer to the bigger share of health left, not the bigger number", function()
		-- 60 of 100 is more than 90 of 160.
		expect(SparRules.roundVerdict(side(true, 60, 100), side(true, 90, 160), true)).toBe("Player")
		expect(SparRules.roundVerdict(side(true, 50, 100), side(true, 120, 160), true)).toBe("Forger")
		expect(SparRules.roundVerdict(side(true, 50, 100), side(true, 80, 160), true)).toBe("Draw")
	end)
end)

describe("what a practice duel pays", function()
	it("is decided by its rounds", function()
		expect(SparRules.outcome({ 2, 0 })).toBe("Win")
		expect(SparRules.outcome({ 1, 2 })).toBe("Loss")
		expect(SparRules.outcome({ 1, 1 })).toBe("Draw")
	end)

	it("is half what the ranked duel pays, three times a day", function()
		expect(SPAR.RewardFactor).toBe(0.5)
		expect(SPAR.PaidPerDay).toBe(3)
		expect(SparRules.scaled(ProgressionConfig.XP.MatchWin, SPAR.RewardFactor)).toBe(175)
		expect(SparRules.scaled(ProgressionConfig.Folios.MatchWin, SPAR.RewardFactor)).toBe(30)
		expect(SparRules.scaled(ProgressionConfig.Folios.MatchLoss, SPAR.RewardFactor)).toBe(10)
		expect(SparRules.scaled(100, 0)).toBe(0)
		expect(SparRules.paidLeft(0, 3)).toBe(3)
		expect(SparRules.paidLeft(2, 3)).toBe(1)
		expect(SparRules.paidLeft(5, 3)).toBe(0)
	end)
end)

return nil
