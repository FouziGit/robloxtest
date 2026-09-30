--!strict
-- Practice against the Erasure, and joining any fight through the hub's gate (D-132). A practice shares the
-- event's one encounter slot, so each rule here is one way a single player could otherwise take the event
-- away from a whole server, or farm it.
local BossPractice = require("../src/server/Pure/BossPractice")
local Harness = require("./harness")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PRACTICE = WorldBossConfig.Practice
local SCHEDULE = WorldBossConfig.Schedule

local function input(overrides: { [string]: number }?): BossPractice.StartInput
	local base: BossPractice.StartInput = {
		Now = 1000,
		NextEventAt = 1000 + SCHEDULE.IntervalSeconds,
		Eligible = SCHEDULE.MinPlayers,
		MinPlayers = SCHEDULE.MinPlayers,
		FightSeconds = PRACTICE.FightSeconds,
		CleanupSeconds = PRACTICE.CleanupSeconds,
		CooldownUntil = 0,
	}
	for key, value in pairs(overrides or {}) do
		(base :: any)[key] = value
	end
	return base
end

describe("BossPractice.startVerdict", function()
	it("starts when nothing stands in the way", function()
		local verdict, seconds = BossPractice.startVerdict(input())
		expect(verdict).toBe("Start")
		expect(seconds).toBe(0)
	end)

	it("makes the player who opened the last one wait, and says how long", function()
		local verdict, seconds = BossPractice.startVerdict(input({ CooldownUntil = 1012.2 }))
		expect(verdict).toBe("Cooldown")
		expect(seconds).toBe(13)
		-- Over the moment it ends.
		expect((BossPractice.startVerdict(input({ CooldownUntil = 1000 })))).toBe("Start")
	end)

	it("refuses when the event is due before the practice would end, and could run", function()
		local holds = PRACTICE.FightSeconds + PRACTICE.CleanupSeconds
		local verdict, seconds = BossPractice.startVerdict(input({ NextEventAt = 1000 + holds - 1 }))
		expect(verdict).toBe("EventSoon")
		expect(seconds).toBe(holds - 1)
		-- Due exactly when the slot is free again: the event is not delayed, so the practice may run.
		expect((BossPractice.startVerdict(input({ NextEventAt = 1000 + holds })))).toBe("Start")
		-- Overdue, still waiting for players: nothing to count down.
		local overdue, left = BossPractice.startVerdict(input({ NextEventAt = 900 }))
		expect(overdue).toBe("EventSoon")
		expect(left).toBe(0)
	end)

	it("lets a practice run where the event could not have run anyway", function()
		local verdict = BossPractice.startVerdict(input({ NextEventAt = 1010, Eligible = SCHEDULE.MinPlayers - 1 }))
		expect(verdict).toBe("Start")
	end)
end)

describe("BossPractice.entryVerdict", function()
	it("turns the gate away while a fight is announced or closing", function()
		for _, practice in ipairs({ false, true }) do
			expect(BossPractice.entryVerdict("Announced", false, 0, PRACTICE.MaxReentries, practice)).toBe("Announced")
			expect(BossPractice.entryVerdict("Defeated", true, 0, PRACTICE.MaxReentries, practice)).toBe("Closing")
			expect(BossPractice.entryVerdict("Expired", false, 0, PRACTICE.MaxReentries, practice)).toBe("Closing")
		end
	end)

	it("joins a newcomer to a fight in progress, event or practice", function()
		expect(BossPractice.entryVerdict("Fighting", false, 0, PRACTICE.MaxReentries, false)).toBe("Join")
		expect(BossPractice.entryVerdict("Fighting", false, 0, PRACTICE.MaxReentries, true)).toBe("Join")
	end)

	it("caps a practice's returns and leaves the event's uncapped", function()
		local cap = PRACTICE.MaxReentries
		expect(BossPractice.entryVerdict("Fighting", true, cap - 1, cap, true)).toBe("Rejoin")
		expect(BossPractice.entryVerdict("Fighting", true, cap, cap, true)).toBe("NoReentry")
		expect(BossPractice.entryVerdict("Fighting", true, cap + 50, cap, false)).toBe("Rejoin")
	end)
end)

describe("BossPractice.gatePhase", function()
	-- The killing blow lands between two of the fight's ticks: until the next one records it, the phase still
	-- reads Fighting, and the gate let a player into a fight already won.
	it("closes the gate on a boss already down, whatever phase its next tick has yet to record", function()
		expect(BossPractice.gatePhase("Fighting", 0)).toBe("Defeated")
		expect(BossPractice.gatePhase("Fighting", -12)).toBe("Defeated")
		for _, practice in ipairs({ false, true }) do
			local phase = BossPractice.gatePhase("Fighting", 0)
			expect(BossPractice.entryVerdict(phase, false, 0, PRACTICE.MaxReentries, practice)).toBe("Closing")
			expect(BossPractice.entryVerdict(phase, true, 0, PRACTICE.MaxReentries, practice)).toBe("Closing")
		end
	end)

	it("reads the fight's own phase while the boss stands, or before it spawns", function()
		expect(BossPractice.gatePhase("Fighting", 1)).toBe("Fighting")
		expect(BossPractice.gatePhase("Fighting", nil)).toBe("Fighting")
		expect(BossPractice.gatePhase("Announced", nil)).toBe("Announced")
		expect(BossPractice.gatePhase("Expired", 900)).toBe("Expired")
		expect(BossPractice.entryVerdict(BossPractice.gatePhase("Fighting", 1), false, 0, PRACTICE.MaxReentries, true)).toBe(
			"Join"
		)
	end)
end)

describe("BossPractice health, rewards and grace", function()
	it("grows the Erasure per joiner and stops at the cap", function()
		local health = PRACTICE.Health
		local joins = 0
		while true do
			local added = BossPractice.grownHealth(health, PRACTICE.HealthPerJoiner, PRACTICE.HealthCap)
			if added == 0 then
				break
			end
			expect(added).toBeLessThanOrEqual(PRACTICE.HealthPerJoiner)
			health += added
			joins += 1
			expect(joins).toBeLessThan(100)
		end
		expect(health).toBe(PRACTICE.HealthCap)
		-- Past the cap (an event's health), a practice never takes any away.
		expect(BossPractice.grownHealth(PRACTICE.HealthCap + 500, PRACTICE.HealthPerJoiner, PRACTICE.HealthCap)).toBe(0)
	end)

	-- A joiner used to grow the Erasure on the way in, and could walk straight back out: someone else's solo
	-- practice stayed HealthPerJoiner stronger for good. The first hit pays the growth, if the boss still stands.
	it("grows a practice on a joiner's first hit, and never a boss that hit brought down", function()
		local perJoiner, cap = PRACTICE.HealthPerJoiner, PRACTICE.HealthCap
		expect(BossPractice.growthOnHit(PRACTICE.Health - 40, PRACTICE.Health, perJoiner, cap)).toBe(perJoiner)
		expect(BossPractice.growthOnHit(1, PRACTICE.Health, perJoiner, cap)).toBe(perJoiner)
		-- The killing blow: the fight ends, nothing grows back.
		expect(BossPractice.growthOnHit(0, PRACTICE.Health, perJoiner, cap)).toBe(0)
		expect(BossPractice.growthOnHit(-30, PRACTICE.Health, perJoiner, cap)).toBe(0)
		-- Still under the cap.
		expect(BossPractice.growthOnHit(500, cap - 100, perJoiner, cap)).toBe(100)
		expect(BossPractice.growthOnHit(500, cap, perJoiner, cap)).toBe(0)
	end)

	it("rounds a scaled reward to the nearest point, and pays nothing at no factor", function()
		expect(BossPractice.scaled(150, 0.25)).toBe(38)
		expect(BossPractice.scaled(80, 0.25)).toBe(20)
		expect(BossPractice.scaled(3, 0.1)).toBe(0)
		expect(BossPractice.scaled(600, 0)).toBe(0)
		expect(BossPractice.scaled(600, -1)).toBe(0)
		-- The shipped factor on the shipped bonus: a solo top share still sees a kill bonus.
		expect(BossPractice.scaled(ProgressionConfig.Folios.BossKillBonus, PRACTICE.RewardFactor)).toBeGreaterThanOrEqual(
			1
		)
	end)

	-- A late joiner's sliver of a share (1 XP, 0 Folios) used to spend one of the day's paid practices and the
	-- server's gap. Both sides of the floor: a pay under it is never charged, a pay at it always is.
	it("charges a paid practice only for a pay worth one", function()
		local floor = PRACTICE.MinPaidFolios
		-- At 1 or more, a pay the factor rounds to no Folio is free, and no Folio is ever paid outside the caps.
		expect(floor).toBeGreaterThanOrEqual(1)
		expect(BossPractice.charged(0, floor)).toBe(false)
		expect(BossPractice.charged(floor - 1, floor)).toBe(false)
		expect(BossPractice.charged(floor, floor)).toBe(true)
		expect(BossPractice.charged(floor + 40, floor)).toBe(true)
		-- The practice the caps exist for: a solo top share, bonus included, is charged.
		local folios = ProgressionConfig.Folios
		local solo = BossPractice.scaled(folios.BossParticipation, PRACTICE.RewardFactor)
			+ BossPractice.scaled(folios.BossKillBonus, PRACTICE.RewardFactor)
		expect(BossPractice.charged(solo, floor)).toBe(true)
	end)

	it("keeps an empty practice only while someone may come back, for the grace", function()
		local grace = PRACTICE.EmptyGraceSeconds
		expect(BossPractice.keepAlive(true, false, nil, 50, grace)).toBe(true)
		expect(BossPractice.keepAlive(false, false, 40, 41, grace)).toBe(false)
		expect(BossPractice.keepAlive(false, true, nil, 41, grace)).toBe(true)
		expect(BossPractice.keepAlive(false, true, 40, 40 + grace - 0.1, grace)).toBe(true)
		expect(BossPractice.keepAlive(false, true, 40, 40 + grace, grace)).toBe(false)
	end)

	it("penalises only a practice left empty early", function()
		local early, penalty, base =
			PRACTICE.EarlyEmptySeconds, PRACTICE.EarlyEmptyCooldownSeconds, PRACTICE.StartCooldownSeconds
		expect(BossPractice.startPenalty(true, 100, 100 + early - 1, early, penalty, base)).toBe(penalty)
		expect(BossPractice.startPenalty(true, 100, 100 + early, early, penalty, base)).toBe(base)
		expect(BossPractice.startPenalty(false, 100, 101, early, penalty, base)).toBe(base)
	end)

	-- A starter a ranked match took, or who died and did not make it back within the grace, was charged the
	-- walk-out's penalty. Only walking out through a gate is holding the gate.
	it("penalises the starter who walked out early, and nobody a match or a death took", function()
		local early, penalty, base =
			PRACTICE.EarlyEmptySeconds, PRACTICE.EarlyEmptyCooldownSeconds, PRACTICE.StartCooldownSeconds
		local walkedOut, takenAway = true, false
		expect(BossPractice.startPenalty(walkedOut, 100, 100 + 1, early, penalty, base)).toBe(penalty)
		expect(BossPractice.startPenalty(takenAway, 100, 100 + 1, early, penalty, base)).toBe(base)
		expect(BossPractice.startPenalty(takenAway, 100, 100 + early - 1, early, penalty, base)).toBe(base)
		expect(penalty).toBeGreaterThan(base)
	end)
end)
