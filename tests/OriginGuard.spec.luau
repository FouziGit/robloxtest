--!strict
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local OriginGuard = require("../src/shared/Pure/OriginGuard")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- The shipped numbers, so the cases below fail if a config change breaks a real scenario rather than
-- passing against a set of values nobody plays with.
local CONFIG: OriginGuard.Config = {
	MaxSpeedStudsPerSecond = GameConfig.Latency.MaxSpeedStudsPerSecond,
	OriginToleranceStuds = GameConfig.Latency.OriginToleranceStuds,
	MaxBudgetSeconds = GameConfig.Latency.MaxBudgetSeconds,
	StillEpsilonStuds = 0.05,
}
local TICK = 1 / GameConfig.Server.TickRate
local WALK = GameConfig.Movement.WalkSpeed
local DASH_STUDS = 22

local function verdict(travelled: number, elapsed: number, allowance: number): string
	local result = OriginGuard.judge(travelled, elapsed, allowance, CONFIG)
	return result
end

describe("OriginGuard shipped numbers", function()
	it("keeps the ceiling above unassisted movement and below a dash", function()
		-- The ceiling exists to bound walking, not the dash: a dash adds its own distance instead.
		expect(CONFIG.MaxSpeedStudsPerSecond > WALK).toBe(true)
		expect(CONFIG.MaxSpeedStudsPerSecond < DASH_STUDS / 0.22).toBe(true)
	end)

	it("keeps the tolerance under the melee reach", function()
		local melee = require("../src/shared/Config/CombatConfig").Melee.Range
		expect(CONFIG.OriginToleranceStuds < melee).toBe(true)
	end)
end)

describe("OriginGuard on honest movement", function()
	it("accepts a walking step and spends no allowance", function()
		local result, left = OriginGuard.judge(WALK * TICK, TICK, 0, CONFIG)
		expect(result).toBe("Accepted")
		expect(left).toBe(0)
	end)

	it("treats a sample with no movement as still, without touching the allowance", function()
		expect(verdict(0, TICK, 0)).toBe("Still")
		expect(verdict(CONFIG.StillEpsilonStuds, TICK, 0)).toBe("Still")
		local _, left = OriginGuard.judge(0, TICK, DASH_STUDS, CONFIG)
		expect(left).toBe(DASH_STUDS)
	end)

	it("covers the catch-up jump after a one-second uplink stall", function()
		-- The regression: the stall was judged still, so the clock was refreshed every sample and the
		-- budget never grew. Here the clock was left alone, so the burst fits.
		expect(verdict(WALK * 1, 1, 0)).toBe("Accepted")
	end)

	it("accepts a dash that arrives as one jump, and consumes what it used", function()
		local result, left = OriginGuard.judge(DASH_STUDS, TICK, DASH_STUDS, CONFIG)
		expect(result).toBe("Accepted")
		-- Only the part beyond the speed ceiling came out of the allowance.
		local bySpeed = CONFIG.MaxSpeedStudsPerSecond * TICK
		expect(left).toBe(DASH_STUDS - (DASH_STUDS - bySpeed))
	end)

	it("does not re-grant the same allowance on the next sample", function()
		-- The regression: the whole allowance was added to every sample in its window, so a 22-stud dash
		-- bought hundreds of studs of accepted travel.
		local _, afterFirst = OriginGuard.judge(DASH_STUDS, TICK, DASH_STUDS, CONFIG)
		expect(afterFirst < DASH_STUDS).toBe(true)
		expect(verdict(DASH_STUDS, TICK, afterFirst)).toBe("Refused")
	end)
end)

describe("OriginGuard on a spoofed position", function()
	it("tolerates one action inside the round-trip slack without moving the anchor", function()
		local bySpeed = CONFIG.MaxSpeedStudsPerSecond * TICK
		expect(verdict(bySpeed + CONFIG.OriginToleranceStuds, TICK, 0)).toBe("Tolerated")
		expect(verdict(bySpeed + CONFIG.OriginToleranceStuds + 0.1, TICK, 0)).toBe("Refused")
	end)

	it("refuses a jump across a duel arena", function()
		-- A duel arena is 80 studs across, 113 corner to corner.
		expect(verdict(80, TICK, 0)).toBe("Refused")
		expect(verdict(113, TICK, 0)).toBe("Refused")
	end)

	it("caps what standing still can bank", function()
		-- Ten seconds of not moving must not buy ten seconds of travel.
		local capped = CONFIG.MaxSpeedStudsPerSecond * CONFIG.MaxBudgetSeconds
		expect(verdict(capped, 10, 0)).toBe("Accepted")
		expect(verdict(capped + CONFIG.OriginToleranceStuds + 0.1, 10, 0)).toBe("Refused")
	end)

	it("makes a held spoof cost real time before it is believed", function()
		-- The point of the ceiling: a 90-stud offset has to be held, with every action refused meanwhile.
		local offset = 90
		expect(verdict(offset, TICK, 0)).toBe("Refused")
		local seconds = offset / CONFIG.MaxSpeedStudsPerSecond
		expect(seconds > 2).toBe(true)
		-- And even then only because the window is capped, so it takes several refused samples in a row.
		expect(verdict(offset, CONFIG.MaxBudgetSeconds, 0)).toBe("Refused")
	end)

	it("treats a NaN sample as still rather than plausible", function()
		expect(verdict(0 / 0, TICK, 0)).toBe("Still")
	end)
end)

describe("OriginGuard.budget", function()
	it("reports the studs a character is entitled to, capped", function()
		expect(OriginGuard.budget(TICK, 0, CONFIG)).toBe(CONFIG.MaxSpeedStudsPerSecond * TICK)
		expect(OriginGuard.budget(100, 0, CONFIG)).toBe(CONFIG.MaxSpeedStudsPerSecond * CONFIG.MaxBudgetSeconds)
		expect(OriginGuard.budget(0, 5, CONFIG)).toBe(5)
	end)
end)
