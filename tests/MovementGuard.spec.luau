--!strict
-- Pure/MovementGuard's rules one at a time, on the shipped numbers: the judge's config as tests/movementsim.luau
-- builds it from MovementGuardConfig and GameConfig. The scenario suite (tests/MovementScenarios.spec.luau)
-- proves the guard on whole motions; these cases pin what a whole motion cannot: the margins, caps, windows and
-- bookkeeping whose mutation leaves every scenario passing. Each was broken on purpose once to watch it fail.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MovementGuard = require("../src/shared/Pure/MovementGuard")
local Sim = require("./movementsim")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CONFIG = Sim.config
local RATE = GameConfig.Server.TickRate
local WALK = GameConfig.Movement.WalkSpeed
-- An R15 body's standing root height, on ground whose top is at 0 unless a case says otherwise.
local STAND = 3
-- How far the speed ceiling lets a body travel in one tick.
local STEP = CONFIG.MaxSpeedStudsPerSecond / RATE
local TICK = 1 / RATE

-- Server tick k, in seconds: exact multiples, so a latch that ends on a tick ends exactly there.
local function at(k: number): number
	return k / RATE
end

local function sample(now: number, x: number, y: number, z: number, fields: { [string]: any }?): MovementGuard.Sample
	local made: MovementGuard.Sample = {
		At = now,
		X = x,
		Y = y,
		Z = z,
		Supported = true,
		StandHeight = STAND,
		Down = false,
		Contact = false,
		WalkSpeed = WALK,
		Rtt = 0,
		LastInboundAt = -math.huge,
		Hitch = false,
		Crossing = nil,
		SupportTops = nil,
	}
	for key, value in pairs(fields or {}) do
		(made :: any)[key] = value
	end
	return made
end

local function observe(
	track: MovementGuard.Track,
	now: number,
	x: number,
	y: number,
	z: number,
	fields: { [string]: any }?
): MovementGuard.Verdict
	return MovementGuard.observe(track, sample(now, x, y, z, fields), CONFIG)
end

-- A body the server spawned at (x, y, z) at time 0.
local function spawnedAt(x: number, y: number, z: number): MovementGuard.Track
	local track = MovementGuard.newTrack(CONFIG)
	MovementGuard.spawned(track, x, y, z, 0, CONFIG)
	return track
end

-- A floor top at `top` the ray from the last judged sample went down through.
local function floorCrossing(top: number): MovementGuard.Crossing
	return {
		HitY = top,
		Top = top,
		Floor = true,
		PassThrough = true,
		PlaneX = 0,
		PlaneY = top,
		PlaneZ = 0,
		NormalX = 0,
		NormalY = 1,
		NormalZ = 0,
	}
end

describe("MovementGuard: shipped numbers", function()
	it("reaches 12.74 studs with a jump and a double jump at its apex", function()
		expect(math.abs(MovementGuard.maxRise(CONFIG) - 12.74) <= 0.01).toBe(true)
	end)

	it("grants the round trip plus the overhead, clamped", function()
		-- clamp(round trip + 0.35, 0.5, 1.5): GetNetworkPing leaves out frame and send time, so a 0.5 s round
		-- trip needs 0.85 s of grace.
		expect(MovementGuard.grace(0.5, CONFIG)).toBeCloseTo(0.85, 6)
		expect(MovementGuard.grace(0, CONFIG)).toBeCloseTo(0.5, 6)
		expect(MovementGuard.grace(-1, CONFIG)).toBeCloseTo(0.5, 6)
		expect(MovementGuard.grace(1.4, CONFIG)).toBeCloseTo(1.5, 6)
		-- An unreadable round trip is the worst allowed, never none.
		expect(MovementGuard.grace(0 / 0, CONFIG)).toBeCloseTo(1.5, 6)
	end)

	it("waits a round trip and an overhead, clamped, for a pivot to settle", function()
		-- clamp(round trip + 0.1, 0.2, 1.0): how long the stream may still carry a body where it stood before a
		-- pivot. The judge ignores those samples, and CombatService holds OriginGuard's anchor through them.
		expect(MovementGuard.settle(0.5, CONFIG)).toBeCloseTo(0.6, 6)
		expect(MovementGuard.settle(0, CONFIG)).toBeCloseTo(0.2, 6)
		expect(MovementGuard.settle(1.4, CONFIG)).toBeCloseTo(1.0, 6)
		expect(MovementGuard.settle(0 / 0, CONFIG)).toBeCloseTo(1.0, 6)
	end)

	it("pays the client mover's overshoot on every grant", function()
		-- The lift overshoot is the peak of the impulse curve, (1 + e)(1 - a)^e at a = 0: an upper bound at
		-- any frame rate. The horizontal one covers the x1.39 a mover overshoots by at 15 fps.
		expect(CONFIG.LiftOvershoot).toBeCloseTo(1 + FeelConfig.Impulse.KnockbackExponent, 6)
		expect(CONFIG.HorizontalOvershoot >= 1.39).toBe(true)
		local track = spawnedAt(0, STAND, 0)
		MovementGuard.grant(track, 22, 15, 0.25, 0, 0, CONFIG)
		expect(track.Allowance).toBeCloseTo(22 * CONFIG.HorizontalOvershoot, 6)
		expect(track.Lift).toBeCloseTo(15 * CONFIG.LiftOvershoot, 6)
	end)

	it("caps what a stream of grants can bank, above what an honest juggle needs", function()
		-- Finisher, Sweep, Rupture and the boss's Fury, 0.3 s apart: 48.75 flat and 34 lift studs.
		local juggle = spawnedAt(0, STAND, 0)
		for i, grant in ipairs({ { 45, 18 }, { 70, 30 }, { 0, 60 }, { 80, 28 } }) do
			MovementGuard.grant(juggle, grant[1] * 0.25, grant[2] * 0.25, 0.25, 0.3 * i, 0.3, CONFIG)
		end
		-- About 73 and 99 studs once overshot: under the caps of 100 and 120, so never clipped.
		expect(juggle.Allowance).toBeCloseTo(48.75 * CONFIG.HorizontalOvershoot, 6)
		expect(juggle.Lift).toBeCloseTo(34 * CONFIG.LiftOvershoot, 6)
		expect(juggle.Allowance < 100).toBe(true)
		expect(juggle.Lift < 120).toBe(true)

		-- Ten Fury-sized grants in a row never bank more than 100 flat and 120 lift studs.
		local stream = spawnedAt(0, STAND, 0)
		for i = 1, 10 do
			MovementGuard.grant(stream, 20, 15, 0.25, 0.1 * i, 0.3, CONFIG)
			expect(stream.Allowance <= 100).toBe(true)
			expect(stream.Lift <= 120).toBe(true)
		end
		expect(stream.Allowance).toBe(100)
		expect(stream.Lift).toBe(120)
	end)
end)

describe("MovementGuard: horizontal", function()
	it("does not flag a body the engine spawned on the corner of the hub pad", function()
		-- The server re-bases on the SpawnLocation's point; the engine puts the body anywhere on the 12 x 12
		-- pad, 8.5 studs from it at the corners, and the first sample comes a tick later.
		local track = spawnedAt(0, STAND, 0)
		local v = observe(track, at(1), 6, STAND, 6)
		expect(v.Action).toBe("None")
	end)

	it("takes a sample as a correction target only once the anchor has nearly caught up", function()
		-- One tick after the spawn the body shows up further than the ceiling allows, by more than the clean
		-- gap but under the slack: not flagged, not believed either.
		local track = spawnedAt(0, STAND, 0)
		local offset = STEP + (CONFIG.CleanGapStuds + CONFIG.TeleportSlackStuds) / 2
		expect(observe(track, at(1), offset, STAND, 0).Action).toBe("None")
		expect(track.Gap > CONFIG.CleanGapStuds).toBe(true)
		local _, newest = MovementGuard.safePoint(track, 1, false)
		expect(newest).toBe(0)
		-- Walking on, the anchor closes on it, and from then on the samples are believed.
		local caughtUp = false
		for k = 2, 12 do
			local x = offset + 0.5 * (k - 1)
			expect(observe(track, at(k), x, STAND, 0).Action).toBe("None")
			local _, latest = MovementGuard.safePoint(track, 1, false)
			if track.Gap <= CONFIG.CleanGapStuds then
				caughtUp = true
				expect(latest).toBe(x)
			else
				expect(latest).toBe(0)
			end
		end
		expect(caughtUp).toBe(true)
	end)

	it("holds a slow against the body only once the client could have learned it", function()
		-- Just inside the walking ceiling at WalkSpeed 16. The server slows the body to 8 at 3 s; the client
		-- learns it a round trip later, so the ceiling stays 16 for the round trip and half a second after it.
		local speed = WALK * CONFIG.SustainedFactor + CONFIG.SustainedSlackStudsPerSecond - 1
		local rtt = 0.2
		local slowAt = 3
		local learnedBy = slowAt + rtt + 0.5
		local track = spawnedAt(0, STAND, 0)
		local firstFlag = math.huge
		for k = 1, 6 * RATE do
			local now = at(k)
			local walkSpeed = if now < slowAt then WALK else WALK / 2
			local v = observe(track, now, speed * now, STAND, 0, { Rtt = rtt, WalkSpeed = walkSpeed })
			if v.Kind == "Speed" then
				firstFlag = math.min(firstFlag, now)
			end
		end
		expect(firstFlag > learnedBy).toBe(true)
		-- And it is held against it after that: the case is not clean by accident.
		expect(firstFlag < math.huge).toBe(true)
	end)
end)

describe("MovementGuard: grants", function()
	it("covers nothing and excuses nothing until the displacement it pays for shows", function()
		local track = spawnedAt(0, STAND, 0)
		for k = 1, RATE do
			observe(track, at(k), 0, STAND, 0)
		end
		MovementGuard.grant(track, 22, 0, 0.22, at(RATE), 0.1, CONFIG)
		-- Walking while the dash is awaited: its allowance is there, but it hides no segment from H2.
		for k = RATE + 1, RATE + 10 do
			observe(track, at(k), WALK * (k - RATE) * TICK, STAND, 0)
		end
		expect(track.Awaiting).toBe(true)
		expect(track.GrantCoverUntil < at(RATE)).toBe(true)
		expect(track.ActiveUntil <= at(RATE + 10)).toBe(true)
		-- The dash shows: from this sample on it covers the body, its whole duration and the activation grace.
		local x = WALK * 10 * TICK + 5
		observe(track, at(RATE + 11), x, STAND, 0)
		expect(track.Awaiting).toBe(false)
		expect(track.GrantCoverUntil).toBe(at(RATE + 11))
		expect(track.ActiveUntil).toBeCloseTo(at(RATE + 11) + 0.22 + CONFIG.ActivationGraceSeconds, 6)
	end)
end)

describe("MovementGuard: vertical", function()
	it("times the hang from the end of a grant's window, not from the last high point", function()
		-- Walks off a ledge (ground top 100), dashes and chains a Ligature in the air -- their movers hold it
		-- level for their whole duration -- then falls. Timed from the ledge alone, the hover reads as floating.
		local g = CONFIG.Gravity
		local track = spawnedAt(0, 103, 0)
		local x = 0
		local hoverY = 103 - 0.5 * g * 0.2 ^ 2
		for k = 1, 52 do
			local now = at(k)
			if k == 24 then
				MovementGuard.grant(track, 22, 0, 0.22, now, 0.1, CONFIG)
			elseif k == 28 then
				MovementGuard.grant(track, 20, 0, 0.25, now, 0.1, CONFIG)
			end
			local y
			if k <= 20 then
				y = 103
			elseif k < 24 then
				y = 103 - 0.5 * g * (now - 1) ^ 2
			elseif k <= 33 then
				y = hoverY
				x += if k >= 29 then 4 elseif k >= 25 then 5.5 else 0
			else
				y = hoverY - 0.5 * g * (now - 1.65) ^ 2
			end
			local v = observe(track, now, x, y, 0, { Supported = k <= 20, Rtt = 0.1 })
			expect(v.Action).toBe("None")
		end
	end)

	it("lets one unexplained rise through, then times the hang from where the climb began", function()
		-- A gentle climb (the exploit critic's A): 2 studs off the ground, then 0.3 more every 0.55 s, never
		-- supported. The first rise spends the one ascent token a jump between two probes may need; every
		-- later rise is unexplained and must not restart the hang clock, or the climb is only caught at the
		-- altitude ceiling some twenty seconds on.
		local track = spawnedAt(0, STAND, 0)
		local caught: MovementGuard.Verdict? = nil
		local caughtAt = math.huge
		for k = 1, 30 * RATE do
			local now = at(k)
			local climbing = now > 2
			local y = if climbing then STAND + 2 + 0.3 * math.floor((now - 2) / 0.55) else STAND
			local v = observe(track, now, 0.8 * k, y, 0, { Supported = not climbing })
			if v.Action ~= "None" then
				caught, caughtAt = v, now
				break
			end
		end
		expect(caught).never.toBeNil()
		local v = caught :: MovementGuard.Verdict
		expect(v.Kind).toBe("Flight")
		expect(v.Rule).toBe("hang")
		expect(caughtAt < 2 + 3).toBe(true)
	end)

	it("excuses a floor crossing only after a real fall", function()
		-- Walking on a floor at 500 and 21 studs below it one tick later: fast enough to tunnel, but from the
		-- floor itself no physics step carries a body through.
		local track = spawnedAt(0, 503, 0)
		for k = 1, 19 do
			observe(track, at(k), 0.5 * k, 503, 0)
		end
		local v = observe(track, at(20), 0.5 * 20, 482, 0, { Supported = false, Crossing = floorCrossing(500) })
		expect(v.Action).toBe("Watch")
		expect(v.Kind).toBe("Noclip")
		expect(v.Rule).toBe("floor")

		-- Walking off the boss arena at 900 and falling through the same floor is the tunnel a real fall can
		-- make.
		local g = CONFIG.Gravity
		local faller = spawnedAt(0, 903, 0)
		local lastY = 903
		local crossed = false
		for k = 1, 80 do
			local now = at(k)
			local y = if k <= 20 then 903 else 903 - 0.5 * g * (now - 1) ^ 2
			local through = lastY >= 500 and y < 499
			local v2 = observe(faller, now, 0, y, 0, {
				Supported = k <= 20,
				Crossing = if through then floorCrossing(500) else nil,
			})
			expect(v2.Action).toBe("None")
			lastY = y
			if through then
				crossed = true
				break
			end
		end
		expect(crossed).toBe(true)
	end)

	it("ends a flight incident when the confirm probe finds ground", function()
		-- The support probe missed a ledge the body stands on, 18.5 studs up: the altitude rule flags it and,
		-- once confirmed, asks for a correction. MovementAudit's confirm probe finds the ledge instead.
		local ledge = 18.5 + STAND
		local function flaggedOnLedge(track: MovementGuard.Track): number
			for k = 20, 40 do
				local v = observe(track, at(k), 0, ledge, 0, { Supported = false })
				expect(v.Kind).toBe("Flight")
				if v.Action == "Correct" then
					return at(k)
				end
			end
			error("the altitude rule never asked for a correction", 0)
		end
		local track = spawnedAt(0, STAND, 0)
		MovementGuard.groundFound(track, ledge, flaggedOnLedge(track))
		expect(track.Episodes.Flight.Count).toBe(0)
		expect(track.GroundY).toBe(ledge)
		-- Standing there is fine from now on.
		for k = 41, 120 do
			expect(observe(track, at(k), 0, ledge, 0, { Supported = false }).Action).toBe("None")
		end
		-- Without the probe's finding the same body keeps being flagged.
		local unprobed = spawnedAt(0, STAND, 0)
		flaggedOnLedge(unprobed)
		local flags = 0
		for k = 41, 120 do
			if observe(unprobed, at(k), 0, ledge, 0, { Supported = false }).Action ~= "None" then
				flags += 1
			end
		end
		expect(flags > 0).toBe(true)
	end)
end)

describe("MovementGuard: server teleports", function()
	it("keeps a live grant across a teleport", function()
		-- The client's mover keeps pushing after a server pivot: a Caret mid-dash still carries the dash.
		local track = spawnedAt(0, STAND, 0)
		MovementGuard.grant(track, 22, 15, 0.22, at(1), 0.2, CONFIG)
		local allowance, lift, windowEnd = track.Allowance, track.Lift, track.WindowEnd
		local fromX, fromY, fromZ = MovementGuard.heard(track)
		MovementGuard.teleported(track, 55, STAND, 0, at(2), fromX, fromY, fromZ, STAND, CONFIG)
		expect(track.Allowance).toBe(allowance)
		expect(track.Lift).toBe(lift)
		expect(track.WindowEnd).toBe(windowEnd)
		expect(track.Awaiting).toBe(true)
	end)

	it("ignores a stale sample from before the teleport just after arrival, and judges it after that", function()
		local track = spawnedAt(0, STAND, 0)
		for k = 1, 19 do
			observe(track, at(k), 0, STAND, 0)
		end
		local fromX, fromY, fromZ = MovementGuard.heard(track)
		MovementGuard.teleported(track, 100, STAND, 0, at(20), fromX, fromY, fromZ, STAND, CONFIG)
		-- The stream still carries the old place until the pivot lands, then the body arrives.
		for k = 20, 24 do
			expect(observe(track, at(k), 0, STAND, 0).Action).toBe("None")
		end
		expect(observe(track, at(25), 100, STAND, 0).Action).toBe("None")
		expect(track.Pending).toBe(false)
		-- A late packet from before the pivot: neither judged nor believed.
		expect(observe(track, at(26), 0, STAND, 0).Action).toBe("None")
		local lastX = MovementGuard.rayOrigin(track)
		expect(lastX).toBe(100)
		-- Once the return window is over, the same sample is a teleport.
		local k = 27
		while at(k) <= at(25) + CONFIG.ReturnWindowSeconds do
			expect(observe(track, at(k), 100, STAND, 0).Action).toBe("None")
			k += 1
		end
		local v = observe(track, at(k), 0, STAND, 0)
		expect(v.Action).toBe("Watch")
		expect(v.Kind).toBe("Teleport")
	end)

	it("measures altitude from the ground found under the destination, or keeps the old ground with none", function()
		-- A pad 900 studs above the hub: the root is dropped 4.5 studs over its standing height.
		local floor, root = 900 + STAND, 900 + STAND + 4.5
		local track = spawnedAt(0, STAND, 0)
		MovementGuard.teleported(track, 0, root, 0, at(1), 0, STAND, 0, floor, CONFIG)
		expect(track.GroundY).toBe(floor)
		expect(track.TokenUsed).toBe(false)
		local ok, _, y = MovementGuard.safePoint(track, 1, true)
		expect(ok).toBe(true)
		expect(y).toBe(root)
		-- Nothing found under it: the altitude rule keeps its old ground, and the point is no ground to fall back to.
		local lost = spawnedAt(0, STAND, 0)
		MovementGuard.teleported(lost, 50, root, 0, at(1), 0, STAND, 0, nil, CONFIG)
		expect(lost.GroundY).toBe(STAND)
		local _, x = MovementGuard.safePoint(lost, 1, true)
		expect(x).toBe(0)
	end)

	it("excuses a return near where a server teleport took the body from, never one a correction armed", function()
		local track = spawnedAt(0, STAND, 0)
		MovementGuard.teleported(track, 100, STAND, 0, at(1), 0, STAND, 0, STAND, CONFIG)
		expect(track.LeftX).toBe(0)
		expect(track.LeftAt).toBe(at(1))
		-- Pulled back from 60, where the client had put the body: the stale samples from there are still known
		-- (From), but a return there is no packet from before a server teleport.
		MovementGuard.corrected(track, 95, STAND, 0, at(40), 60, STAND, 0, STAND, CONFIG)
		expect(track.FromX).toBe(60)
		expect(track.Pending).toBe(true)
		expect(track.LeftX).toBe(0)
		expect(track.LeftAt).toBe(at(1))
	end)

	it("scans for a landing on the sample that shows a pending teleport arrived", function()
		-- Its settle can last a second, in which the body landed on the pad and jumped again: without the scan,
		-- a hop on arrival read as a hang.
		local track = spawnedAt(0, STAND, 0)
		MovementGuard.teleported(track, 0, 900 + STAND + 4.5, 0, at(1), 0, STAND, 0, 900 + STAND, CONFIG)
		expect(track.Pending).toBe(true)
		local midHop = sample(at(1 + RATE), 0, 900 + STAND + 7, 0, { Supported = false })
		expect(MovementGuard.preview(track, midHop, CONFIG)).toBe(true)
	end)
end)

describe("MovementGuard: a teleport the client refuses", function()
	local DEST = 100

	-- Teleports the body to `dest` at `from`'s tick, then keeps replicating it at x = `stay` with validated
	-- remotes arriving; returns the first Repivot and the tick it came on.
	local function refused(
		track: MovementGuard.Track,
		fromTick: number,
		stay: number,
		dest: number
	): (MovementGuard.Verdict, number)
		local x, y, z = MovementGuard.heard(track)
		MovementGuard.teleported(track, dest, STAND, 0, at(fromTick), x, y, z, STAND, CONFIG)
		for k = fromTick + 1, fromTick + 10 * RATE do
			local v = observe(track, at(k), stay, STAND, 0, { LastInboundAt = at(k) - TICK })
			if v.Action == "Repivot" then
				return v, k
			end
		end
		error("the teleport was never sent again", 0)
	end

	local function refusedTwice(track: MovementGuard.Track, fromTick: number): number
		local _, first = refused(track, fromTick, 0, DEST)
		local k = first
		repeat
			k += 1
		until observe(track, at(k), 0, STAND, 0, { LastInboundAt = at(k) - TICK }).Action == "Repivot"
		return k
	end

	it("sends it again, and calls the third refusal resisting", function()
		local track = spawnedAt(0, STAND, 0)
		local second = refusedTwice(track, RATE)
		expect(track.Refusals).toBe(2)
		local k = second
		local v
		repeat
			k += 1
			v = observe(track, at(k), 0, STAND, 0, { LastInboundAt = at(k) - TICK })
		until v.Action == "Repivot"
		expect(v.Kind).toBe("Resist")
		expect(v.Strikeable).toBe(true)
	end)

	it("forgets the refusals once the body arrives", function()
		local track = spawnedAt(0, STAND, 0)
		local k = refusedTwice(track, RATE)
		repeat
			k += 1
			observe(track, at(k), DEST, STAND, 0)
		until not track.Pending
		local v = refused(track, k, DEST, DEST + 200)
		expect(v.Kind).toBeNil()
		expect(v.Rule).toBe("timeout")
	end)

	it("remembers refusals across a respawn for RefusalWindowSeconds, and no longer", function()
		local track = spawnedAt(0, STAND, 0)
		local k = refusedTwice(track, RATE)
		MovementGuard.spawned(track, 0, STAND, 0, at(k + 1), CONFIG)
		local v, last = refused(track, k + 2, 0, DEST)
		expect(v.Kind).toBe("Resist")
		MovementGuard.spawned(track, 0, STAND, 0, at(last + 1), CONFIG)
		local later = last + (CONFIG.RefusalWindowSeconds + 1) * RATE
		v = refused(track, later, 0, DEST)
		expect(v.Kind).toBeNil()
		expect(v.Rule).toBe("timeout")
	end)
end)

describe("MovementGuard: confirmation and exemptions", function()
	-- Walks at 10 studs per second along x and, at tick `jumpAt`, jumps 100 studs sideways and walks on from
	-- there. Returns the verdict of the tick after the jump, the one that confirms it.
	local function jumpAside(jumpAt: number, contactAt: number?): MovementGuard.Verdict
		local track = spawnedAt(0, STAND, 0)
		local confirmed = nil
		for k = 1, jumpAt + 1 do
			local z = if k >= jumpAt then 100 else 0
			local v = observe(track, at(k), 0.5 * k, STAND, z, { Contact = k == contactAt })
			if k == jumpAt then
				expect(v.Action).toBe("Watch")
			end
			confirmed = v
		end
		return confirmed :: MovementGuard.Verdict
	end

	it("corrects a teleport right after a spawn without striking it", function()
		local inGrace = jumpAside(2)
		expect(inGrace.Action).toBe("Correct")
		expect(inGrace.Strikeable).toBe(false)
		local after = jumpAside(2 * RATE)
		expect(after.Action).toBe("Correct")
		expect(after.Strikeable).toBe(true)
	end)

	it("keeps an episode's exemption when its confirming sample is not exempt", function()
		-- Touched at 2 s, the contact exempts until 3 s; the first flag lands inside it, the second exactly
		-- where it ends. The episode is one incident, and the contact explains it.
		local latch = math.max(CONFIG.ContactLatchSeconds, CONFIG.ContactRttMarginSeconds)
		local touchedAt = 2 * RATE
		local lastExempt = touchedAt + latch * RATE - 1
		local v = jumpAside(lastExempt, touchedAt)
		expect(v.Action).toBe("Correct")
		expect(v.Strikeable).toBe(false)
		-- Without the touch, the same jump is struck.
		expect(jumpAside(lastExempt).Strikeable).toBe(true)
	end)

	it("confirms two flags inside the window even with a clean sample between them", function()
		-- One packet in two replicated 100 studs aside.
		local track = spawnedAt(0, STAND, 0)
		for k = 1, 39 do
			observe(track, at(k), 0.5 * k, STAND, 0)
		end
		expect(observe(track, at(40), 0.5 * 40 + 100, STAND, 0).Action).toBe("Watch")
		expect(observe(track, at(41), 0.5 * 41, STAND, 0).Action).toBe("None")
		local v = observe(track, at(42), 0.5 * 42 + 100, STAND, 0)
		expect(v.Action).toBe("Correct")
		expect(v.Kind).toBe("Teleport")
	end)
end)

describe("MovementGuard: corrections", function()
	it("keeps counting broken samples across the correction they cause", function()
		-- A client that keeps sending NaN is corrected on every one after the first, not watched afresh
		-- after each pivot.
		local track = spawnedAt(0, STAND, 0)
		for k = 1, RATE do
			observe(track, at(k), 0.5 * k, STAND, 0)
		end
		expect(observe(track, at(RATE + 1), 0 / 0, STAND, 0).Action).toBe("Watch")
		local v = observe(track, at(RATE + 2), 0 / 0, STAND, 0)
		expect(v.Action).toBe("Correct")
		expect(v.Strikeable).toBe(true)
		local x, y, z = MovementGuard.heard(track)
		MovementGuard.corrected(track, v.X, v.Y, v.Z, at(RATE + 2), x, y, z, v.Y, CONFIG)
		local again = observe(track, at(RATE + 3), math.huge, STAND, 0)
		expect(again.Action).toBe("Correct")
		expect(again.Strikeable).toBe(true)
	end)

	it("sends a flight back to the ground it left, and a speed hack back to where it began", function()
		-- Walks, jumps -- the points on the way up are believed, but in the air -- and pops to 40 studs.
		local g = CONFIG.Gravity
		local jumper = spawnedAt(0, STAND, 0)
		for k = 1, RATE do
			observe(jumper, at(k), 0.5 * k, STAND, 0)
		end
		local flight: MovementGuard.Verdict? = nil
		for k = RATE + 1, 3 * RATE do
			local t = at(k) - 1
			local y = if k <= RATE + 5 then STAND + 50 * t - 0.5 * g * t * t else 40
			local v = observe(jumper, at(k), 0.5 * k, y, 0, { Supported = false })
			if v.Action == "Correct" then
				flight = v
				break
			end
		end
		local _, _, airY = MovementGuard.safePoint(jumper, 1, false)
		expect(airY > STAND).toBe(true)
		local v = flight :: MovementGuard.Verdict
		expect(v.Kind).toBe("Flight")
		expect(v.X).toBe(0.5 * RATE)
		expect(v.Y).toBe(STAND)

		-- 25 studs per second from the spawn: under the ceiling each tick, over the walking pace for long.
		local runner = spawnedAt(0, STAND, 0)
		local speed: MovementGuard.Verdict? = nil
		for k = 1, 10 * RATE do
			local sv = observe(runner, at(k), 25 * at(k), STAND, 0)
			if sv.Action == "Correct" then
				speed = sv
				break
			end
		end
		local sv = speed :: MovementGuard.Verdict
		expect(sv.Kind).toBe("Speed")
		local _, newest = MovementGuard.safePoint(runner, 1, false)
		expect(newest > 50).toBe(true)
		expect(sv.X).toBe(0)
	end)

	it("sends a flight to the newest point instead once its ground is too old", function()
		-- Stands still on its spawn for longer than GroundMaxAgeSeconds, so the spawn is its only ground
		-- point, then jumps and pops.
		local g = CONFIG.Gravity
		local track = spawnedAt(0, STAND, 0)
		local still = math.ceil(CONFIG.GroundMaxAgeSeconds * RATE) + RATE
		for k = 1, still do
			observe(track, at(k), 0, STAND, 0)
		end
		local flight: MovementGuard.Verdict? = nil
		for k = still + 1, still + 2 * RATE do
			local t = at(k - still)
			local y = if k <= still + 5 then STAND + 50 * t - 0.5 * g * t * t else 40
			local v = observe(track, at(k), 0, y, 0, { Supported = false })
			if v.Action == "Correct" then
				flight = v
				break
			end
		end
		local v = flight :: MovementGuard.Verdict
		expect(v.Kind).toBe("Flight")
		expect(v.Y > STAND).toBe(true)
	end)
end)

describe("MovementGuard: a new body", function()
	it("forgets the old body's points and contact", function()
		-- Touched just before dying, with a round trip that latches the touch for two seconds; the new body
		-- teleports once its spawn grace is over, still inside that latch.
		local track = spawnedAt(0, STAND, 0)
		local touchedAt = 2 * RATE
		for k = 1, touchedAt do
			observe(track, at(k), 0.5 * k, STAND, 0, { Contact = k == touchedAt, Rtt = 1.5 })
		end
		expect(track.ContactUntil > at(touchedAt) + CONFIG.SpawnGraceSeconds + 2 * TICK).toBe(true)
		MovementGuard.spawned(track, 50, STAND, 0, at(touchedAt + 1), CONFIG)
		local ok = MovementGuard.safePoint(track, 2, false)
		expect(ok).toBe(false)
		local jumpAt = touchedAt + 1 + CONFIG.SpawnGraceSeconds * RATE + 1
		local v
		for k = touchedAt + 2, jumpAt + 1 do
			v = observe(track, at(k), 50 + 0.5 * (k - touchedAt), STAND, if k >= jumpAt then 100 else 0, { Rtt = 1.5 })
		end
		expect(v.Action).toBe("Correct")
		expect(v.Strikeable).toBe(true)
	end)
end)

describe("MovementGuard: the round trip it reads", function()
	it("is capped, so a lagging client cannot stretch its own exemptions", function()
		local track = spawnedAt(0, STAND, 0)
		observe(track, at(1), 0.5, STAND, 0, { Contact = true, Rtt = 60 })
		expect(track.ContactUntil).toBeCloseTo(at(1) + CONFIG.MaxRttSeconds + CONFIG.ContactRttMarginSeconds, 6)
	end)
end)

describe("MovementGuard.touching", function()
	local RADIUS = 6

	local function touching(positions: { { number } }, moves: { { number } }, flagged: { boolean }): { boolean }
		local xs, ys, zs, dxs, dys, dzs = {}, {}, {}, {}, {}, {}
		for i, p in ipairs(positions) do
			xs[i], ys[i], zs[i] = p[1], p[2], p[3]
			dxs[i], dys[i], dzs[i] = moves[i][1], moves[i][2], moves[i][3]
		end
		return MovementGuard.touching(xs, ys, zs, dxs, dys, dzs, flagged, RADIUS, CONFIG)
	end

	local STILL = { 0, 0, 0 }

	it("pairs roots within the radius in 3D, and only those", function()
		-- The fourth is 5 studs from the second (4 up, 3 across) and 7.1 from the first.
		local result = touching({ { 0, 3, 0 }, { 5, 3, 0 }, { 30, 3, 0 }, { 5, 7, 3 } }, {
			STILL,
			STILL,
			STILL,
			STILL,
		}, { false, false, false, false })
		expect(result).toEqual({ true, true, false, true })
		-- 3D: a body 7 studs straight overhead is not touching.
		expect(touching({ { 0, 3, 0 }, { 0, 10, 0 } }, { STILL, STILL }, { false, false })).toEqual({ false, false })
	end)

	it("keeps a fling victim's exemption", function()
		-- The flinger spins in place and was flagged; its victim is thrown 30 studs away from it.
		local result = touching({ { 0, 3, 0 }, { 4, 3, 0 } }, { STILL, { 30, 5, 0 } }, { true, true })
		expect(result).toEqual({ true, true })
	end)

	it("voids the contact of bodies flagged while moving together", function()
		local together = { 20, 0, 1 }
		-- Two cheaters teleporting side by side lose it both ways.
		expect(touching({ { 0, 3, 0 }, { 3, 3, 0 } }, { together, together }, { true, true })).toEqual({ false, false })
		-- Only the flagged one's partner loses it: a clean body is not exempted by a flagged one.
		expect(touching({ { 0, 3, 0 }, { 3, 3, 0 } }, { together, together }, { false, true })).toEqual({
			false,
			true,
		})
		-- Carried together by something honest -- nobody flagged -- both keep it.
		expect(touching({ { 0, 3, 0 }, { 3, 3, 0 } }, { together, together }, { false, false })).toEqual({ true, true })
		-- Moving apart, or together but within the teleport slack, is not moving together.
		local apart = { -20, 0, 1 }
		expect(touching({ { 0, 3, 0 }, { 3, 3, 0 } }, { together, apart }, { true, true })).toEqual({ true, true })
		local short = { CONFIG.TeleportSlackStuds, 0, 0 }
		expect(touching({ { 0, 3, 0 }, { 3, 3, 0 } }, { short, short }, { true, true })).toEqual({ true, true })
	end)
end)

-- The geometry MovementAudit turns a barrier ray's hit into, in the barrier's own space: the shipped half width
-- (1) and floor sink (1).
describe("MovementGuard: barrier geometry", function()
	-- A wall 2 thick on x, 20 long on z, 10 high; a floor slab 40 by 40, 4 thick.
	local WALL = { 1, 5, 10 }
	local SLAB = { 20, 2, 20 }

	local function through(floor: boolean, a: { number }, b: { number }, half: { number }): boolean
		return MovementGuard.passesThrough(floor, a[1], a[2], a[3], b[1], b[2], b[3], half[1], half[2], half[3], CONFIG)
	end

	it("measures a turned box's top from its centre", function()
		-- Upright: half its own height.
		expect(MovementGuard.halfHeight(0, 1, 0, 4, 10, 6)).toBeCloseTo(5, 6)
		-- Lying on its side, turned a quarter about z: its x size stands up.
		expect(MovementGuard.halfHeight(1, 0, 0, 4, 10, 6)).toBeCloseTo(2, 6)
		-- Tipped 45 degrees about z, either way: both x and y climb.
		local tilt = math.sqrt(0.5)
		expect(MovementGuard.halfHeight(tilt, tilt, 0, 4, 10, 6)).toBeCloseTo(7 * tilt, 6)
		expect(MovementGuard.halfHeight(-tilt, tilt, 0, 4, 10, 6)).toBeCloseTo(7 * tilt, 6)
	end)

	it("reads a step from one side of a wall to the other as going through it", function()
		expect(through(false, { -3, 0, 0 }, { 3, 0, 2 }, WALL)).toBe(true)
		expect(through(false, { 3, 0, 0 }, { -3, 0, 0 }, WALL)).toBe(true)
		-- The thinner horizontal axis decides which way is across: the same wall turned a quarter.
		expect(through(false, { 0, 0, -3 }, { 0, 0, 3 }, { 10, 5, 1 })).toBe(true)
	end)

	it("does not read a chord that cuts the end of a wall as a crossing", function()
		-- Crossing the middle 9.5 studs along a wall 10 long from its centre: inside the end, but not by a body's
		-- half width.
		expect(through(false, { -3, 0, 9.5 }, { 3, 0, 9.5 }, WALL)).toBe(false)
		-- 8.5 along: a whole half width inside the end.
		expect(through(false, { -3, 0, 8.5 }, { 3, 0, 8.5 }, WALL)).toBe(true)
		-- Measured where the step crosses the middle, not at either end: from 12 to 4 crosses at 8.
		expect(through(false, { -3, 0, 12 }, { 3, 0, 4 }, WALL)).toBe(true)
		expect(through(false, { -3, 0, 14 }, { 3, 0, 8 }, WALL)).toBe(false)
	end)

	it("does not read a step that starts inside a wall, or stays on one side, as a crossing", function()
		-- Out of it by the far face, or into it: the step never went from one side to the other.
		expect(through(false, { 0.5, 0, 0 }, { -3, 0, 0 }, WALL)).toBe(false)
		expect(through(false, { -3, 0, 0 }, { 0.5, 0, 0 }, WALL)).toBe(false)
		expect(through(false, { 0.5, 0, 0 }, { 3, 0, 0 }, WALL)).toBe(false)
		expect(through(false, { -3, 0, 0 }, { -0.5, 0, 0 }, WALL)).toBe(false)
		expect(through(false, { -3, 0, 0 }, { -1.5, 0, 0 }, WALL)).toBe(false)
	end)

	it("reads a drop from above a floor to under it as going through it, well inside its footprint", function()
		-- From over the top (2) to more than the floor sink under it.
		expect(through(true, { 0, 5, 0 }, { 3, 0.9, -4 }, SLAB)).toBe(true)
		-- Not sunk past the floor sink: a body resting in the floor's surface.
		expect(through(true, { 0, 5, 0 }, { 3, 1.1, -4 }, SLAB)).toBe(false)
		-- Not from above it.
		expect(through(true, { 0, 1.9, 0 }, { 3, -3, -4 }, SLAB)).toBe(false)
		-- Landing within a body's half width of an edge: a fall past it, not through it.
		expect(through(true, { 0, 5, 0 }, { 19.5, -3, 0 }, SLAB)).toBe(false)
		expect(through(true, { 0, 5, 0 }, { 0, -3, -19.5 }, SLAB)).toBe(false)
		expect(through(true, { 0, 5, 0 }, { 18.5, -3, -18.5 }, SLAB)).toBe(true)
	end)
end)
