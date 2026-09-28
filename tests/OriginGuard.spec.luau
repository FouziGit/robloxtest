--!strict
local CombatConfig = require("../src/shared/Config/CombatConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MovementGuardConfig = require("../src/server/Config/MovementGuardConfig")
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
local RATE = GameConfig.Server.TickRate
local TICK = 1 / RATE
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
		expect(CONFIG.OriginToleranceStuds < CombatConfig.Melee.Range).toBe(true)
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

	it("treats a NaN sample as still rather than plausible", function()
		expect(verdict(0 / 0, TICK, 0)).toBe("Still")
	end)
end)

describe("OriginGuard.follow", function()
	local bySpeed = CONFIG.MaxSpeedStudsPerSecond * TICK

	it("leaves a still body's anchor, clock, allowance and tolerance alone", function()
		for _, spent in ipairs({ false, true }) do
			local result, left, advance, stillSpent = OriginGuard.follow(0, TICK, DASH_STUDS, true, spent, CONFIG)
			expect(result).toBe("Still")
			expect(left).toBe(DASH_STUDS)
			expect(advance).toBe(0)
			expect(stillSpent).toBe(spent)
		end
	end)

	it("follows an accepted body all the way and gives the tolerance back", function()
		local result, left, advance, spent = OriginGuard.follow(WALK * TICK, TICK, 0, false, true, CONFIG)
		expect(result).toBe("Accepted")
		expect(left).toBe(0)
		expect(advance).toBe(WALK * TICK)
		expect(spent).toBe(false)
	end)

	it("resolves one action inside the tolerance where the client says, then chases", function()
		local inside = bySpeed + CONFIG.OriginToleranceStuds
		local result, left, advance, spent = OriginGuard.follow(inside, TICK, 0, true, false, CONFIG)
		expect(result).toBe("Tolerated")
		expect(left).toBe(0)
		expect(advance).toBe(bySpeed)
		expect(spent).toBe(true)
		-- The next action inside it, before the anchor has caught up, is resolved from the anchor instead.
		result, _, advance, spent = OriginGuard.follow(inside, TICK, 0, true, true, CONFIG)
		expect(result).toBe("Chasing")
		expect(advance).toBe(bySpeed)
		expect(spent).toBe(true)
	end)

	it("lets only an action spend the tolerance", function()
		-- The per-tick sampling runs twenty times a second: had it been allowed to spend the tolerance, no
		-- action would ever find it unspent.
		local inside = bySpeed + CONFIG.OriginToleranceStuds
		local result, _, advance, spent = OriginGuard.follow(inside, TICK, 0, false, false, CONFIG)
		expect(result).toBe("Chasing")
		expect(advance).toBe(bySpeed)
		expect(spent).toBe(false)
		result = OriginGuard.follow(inside, TICK, 0, true, spent, CONFIG)
		expect(result).toBe("Tolerated")
	end)

	it("chases past the tolerance by the whole budget, allowance included, and refuses", function()
		for _, action in ipairs({ false, true }) do
			local result, left, advance, spent = OriginGuard.follow(80, TICK, 5, action, false, CONFIG)
			expect(result).toBe("Refused")
			expect(left).toBe(0)
			expect(advance).toBe(bySpeed + 5)
			expect(spent).toBe(false)
		end
	end)
end)

-- CombatService.trustedCFrame on one horizontal axis: the anchor, its clock, the tolerance, the converging
-- flag and the violations, driven through OriginGuard.follow the way the service drives it. The service
-- itself needs an engine; tests/MovementGates.spec.luau holds its source to this shape.
type Anchor = {
	X: number,
	At: number,
	Spent: boolean,
	Converging: boolean,
	Violations: { number },
	Refusals: number,
	Strikes: number,
}

local function newAnchor(): Anchor
	return { X = 0, At = 0, Spent = false, Converging = false, Violations = {}, Refusals = 0, Strikes = 0 }
end

-- Judges the observation `seen` at `now`; returns the verdict and where the action, if any, is resolved.
local function judgeAt(anchor: Anchor, seen: number, now: number, action: boolean): (OriginGuard.Verdict, number)
	local elapsed = now - anchor.At
	local result, _, advance, spent =
		OriginGuard.follow(math.abs(seen - anchor.X), elapsed, 0, action, anchor.Spent, CONFIG)
	anchor.Spent = spent
	if result == "Accepted" then
		anchor.Converging = false
		anchor.X, anchor.At = seen, now
		return result, seen
	end
	if result == "Still" then
		return result, seen
	end
	if elapsed >= MovementGuardConfig.StallSeconds then
		anchor.Converging = true
	end
	anchor.X += math.sign(seen - anchor.X) * advance
	anchor.At = now
	if result == "Tolerated" then
		return result, seen
	end
	if result == "Refused" and action and not anchor.Converging then
		anchor.Refusals += 1
		local cutoff = now - GameConfig.Latency.ViolationWindowSeconds
		while #anchor.Violations > 0 and anchor.Violations[1] < cutoff do
			table.remove(anchor.Violations, 1)
		end
		table.insert(anchor.Violations, now)
		if #anchor.Violations >= GameConfig.Latency.ViolationsBeforeStrike then
			table.clear(anchor.Violations)
			anchor.Strikes += 1
		end
	end
	return result, anchor.X
end

describe("the trusted anchor, chasing", function()
	it("makes a held spoof cost real time before it is believed", function()
		-- The point of the ceiling: a 90-stud offset has to be held, with every action but one clamped
		-- meanwhile. No single sample believes it, whatever time has passed, because the window is capped.
		local offset = 90
		expect(verdict(offset, TICK, 0)).toBe("Refused")
		expect(verdict(offset, CONFIG.MaxBudgetSeconds, 0)).toBe("Refused")
		-- The anchor chases at the ceiling, so the offset is believed on the 45th tick, 2.25 s after it
		-- appeared (GameConfig.Latency), and not one tick sooner.
		local anchor = newAnchor()
		local believedOn: number?, honoured = nil, 0
		for tick = 1, 100 do
			local now = tick * TICK
			local _, at = judgeAt(anchor, offset, now - TICK / 2, true)
			if at == offset then
				honoured += 1
			end
			if judgeAt(anchor, offset, now, false) == "Accepted" then
				believedOn = tick
				break
			end
		end
		expect(believedOn).toBe(45)
		expect(honoured).toBeLessThanOrEqual(1)
	end)

	-- A walker at WalkSpeed, sampled every tick, whose uplink delivers nothing from 1 s to 1 + `stall` s.
	-- Returns the samples refused once it catches up, how long after the last of them came, and the gap left
	-- 10 s later. `frozen` keeps the anchor and its clock where they last believed the body, as they did
	-- before the chase.
	local function converge(stall: number, frozen: boolean): (number, number, number)
		local anchor = newAnchor()
		local seen, refused, lastRefused = 0, 0, 0
		for tick = 1, math.round((1 + stall + 10) * RATE) do
			local now = tick * TICK
			if tick < RATE or tick > RATE * (1 + stall) then
				seen = WALK * now
			end
			local x, at = anchor.X, anchor.At
			local result = judgeAt(anchor, seen, now, false)
			if frozen and result ~= "Accepted" then
				anchor.X, anchor.At = x, at
			end
			if now > 1 + stall and result == "Refused" then
				refused += 1
				lastRefused = now - (1 + stall)
			end
		end
		return refused, lastRefused, math.abs(seen - anchor.X)
	end

	it("catches up with an honest walker after an uplink stall", function()
		-- Stall -> refused samples after it, and when the last came. Frozen, the anchor never caught up from
		-- 1.2 s on: every sample for the next ten seconds was refused and the gap only grew.
		local expected = {
			{ 1.2, 0, 0 },
			{ 2, 7, 0.35 },
			{ 3, 20, 1.0 },
			{ 5, 47, 2.35 },
			{ 8, 87, 4.35 },
		}
		for _, row in ipairs(expected) do
			local refused, last, gap = converge(row[1], false)
			expect(refused).toBe(row[2])
			expect(last).toBeCloseTo(row[3], 6)
			expect(gap).toBe(0)
		end
		local refused, _, gap = converge(1.2, true)
		expect(refused).toBe(193)
		expect(gap).toBeGreaterThan(170)
	end)

	it("never strikes an M1 player who comes back from a stall", function()
		-- A walker swinging at the combo's full cadence for a minute after an uplink stall, sampled 20 times
		-- a second with 50 ms of one-way latency, simulated at 240 Hz. Before the chase this was 112 to 126
		-- violations and 37 to 42 strikes: the kick is at 25. Now a few swings are clamped while the anchor
		-- converges, and none of them counts.
		local melee = CombatConfig.Melee
		local swing = (3 * melee.HitIntervalSeconds + melee.FinisherCooldownSeconds) / #melee.Damage
		local STEPS = 240
		local LATENCY = 0.05
		local STALL_AT = 5
		local expected = { { 1.2, 0 }, { 2, 1 }, { 3, 3 }, { 5, 5 }, { 8, 10 } }
		for _, row in ipairs(expected) do
			local stall = row[1]
			local anchor = newAnchor()
			local seen, clamped, nextSwing = 0, 0, 0.2
			local packets: { { number } } = {}
			for step = 1, (STALL_AT + 60) * STEPS do
				local now = step / STEPS
				local tick = step // (STEPS / RATE)
				local onTick = step % (STEPS / RATE) == 0
				if onTick and (tick < STALL_AT * RATE or tick > RATE * (STALL_AT + stall)) then
					table.insert(packets, { now + LATENCY, WALK * now })
				end
				while #packets > 0 and packets[1][1] <= now + 1e-9 do
					seen = table.remove(packets, 1)[2]
				end
				if onTick then
					judgeAt(anchor, seen, now, false)
				end
				if now >= nextSwing then
					nextSwing += swing
					local _, at = judgeAt(anchor, seen, now, true)
					if math.abs(at - seen) > 1 then
						clamped += 1
					end
				end
			end
			expect(anchor.Refusals).toBe(0)
			expect(anchor.Strikes).toBe(0)
			expect(clamped).toBeLessThanOrEqual(row[2])
		end
	end)
end)

describe("OriginGuard.budget", function()
	it("reports the studs a character is entitled to, capped", function()
		expect(OriginGuard.budget(TICK, 0, CONFIG)).toBe(CONFIG.MaxSpeedStudsPerSecond * TICK)
		expect(OriginGuard.budget(100, 0, CONFIG)).toBe(CONFIG.MaxSpeedStudsPerSecond * CONFIG.MaxBudgetSeconds)
		expect(OriginGuard.budget(0, 5, CONFIG)).toBe(5)
	end)
end)

-- The way a body faces, which the server aims every swing and glyph with (D-113). Measured live: after a
-- finisher the server still saw the victim's root tilted to 0.41 up when its stun ended, and a swing aimed
-- with that root went into the ground.
describe("OriginGuard.facing", function()
	local function facing(look: { number }, up: { number }): (number, number)
		return OriginGuard.facing(look[1], look[2], look[3], up[1], up[3])
	end
	local function near(a: number, b: number)
		expect(math.abs(a - b) < 1e-6).toBe(true)
	end

	it("is the look itself for a body standing up", function()
		local x, z = facing({ 0.6, 0, -0.8 }, { 0, 1, 0 })
		near(x, 0.6)
		near(z, -0.8)
	end)

	-- Facing an arbitrary horizontal direction, never an axis: the degenerate fallback is (0, -1), and a
	-- case facing -Z would pass by coincidence.
	local AIM = 0.7
	local FX, FZ = math.cos(AIM), math.sin(AIM)

	it("keeps pointing forward as the body tips over backwards, down to lying on its back", function()
		for _, degrees in ipairs({ 30, 60, 78, 80, 89, 90 }) do
			local t = math.rad(degrees)
			local c, s = math.cos(t), math.sin(t)
			local x, z = facing({ c * FX, s, c * FZ }, { -s * FX, c, -s * FZ })
			near(x, FX)
			near(z, FZ)
		end
	end)

	it("keeps pointing forward as the body falls on its face", function()
		for _, degrees in ipairs({ 30, 60, 85, 90 }) do
			local t = math.rad(degrees)
			local c, s = math.cos(t), math.sin(t)
			local x, z = facing({ c * FX, -s, c * FZ }, { s * FX, c, s * FZ })
			near(x, FX)
			near(z, FZ)
		end
	end)

	it("always returns a horizontal unit, even from a degenerate frame", function()
		local x, z = facing({ 0, 1, 0 }, { 0, 1, 0 })
		near(x * x + z * z, 1)
		x, z = facing({ 3, -2, 4 }, { 0, 1, 0 })
		near(x, 0.6)
		near(z, 0.8)
	end)
end)
