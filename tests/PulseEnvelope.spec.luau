--!strict
-- The pulse envelope, driven by the real spring and the real PageFlash profile. The first test is the
-- defect a player found by punching a training dummy: the page bleached and never came back.
local Harness = require("./harness")
local LightingConfig = require("../src/shared/Config/LightingConfig")
local PulseEnvelope = require("../src/shared/Pure/PulseEnvelope")
local Spring = require("../src/shared/Pure/Spring")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local FRAME = 1 / 60
local PROFILE = LightingConfig.Pulses.PageFlash
local EPSILON = LightingConfig.Envelope.SettleEpsilon
-- Everything a pulse needs to be gone, with generous slack for the spring's tail.
local LIFETIME = (PROFILE.AttackSeconds + PROFILE.HoldSeconds + PROFILE.ReleaseSeconds) * 4

-- The same conversion WorldLighting uses: a critically damped spring covering `seconds`.
local function shape(spring: any, seconds: number)
	local frequency = LightingConfig.Envelope.Settle / math.max(seconds, LightingConfig.Envelope.MinPhaseSeconds)
	spring.Tension = frequency * frequency
	spring.Friction = Spring.criticalFriction(spring.Tension)
end

local function pulse(strength: number): PulseEnvelope.Envelope
	return PulseEnvelope.new(Spring.new(0, 1, 1) :: any, shape, PROFILE, strength, EPSILON)
end

-- Runs a pulse until it reports itself gone, and returns how long that took and its highest weight.
local function runOut(envelope: PulseEnvelope.Envelope, limit: number): (number?, number)
	local elapsed, peak = 0, 0
	while elapsed < limit do
		local done = PulseEnvelope.step(envelope, FRAME)
		elapsed += FRAME
		peak = math.max(peak, envelope.Weight.Position)
		if done then
			return elapsed, peak
		end
	end
	return nil, peak
end

describe("a pulse asked for at less than full strength", function()
	it("releases, instead of staying on the page forever", function()
		-- 0.906 is the strength measured in the live session: a punch on a dummy a few studs away.
		local finished, peak = runOut(pulse(0.906), LIFETIME)
		if finished == nil then
			error(("a 0.906 pulse was still live after %.2f s: the page stays bleached"):format(LIFETIME))
		end
		-- And it reached the strength it was asked for, not the full profile.
		expect(peak).toBeGreaterThan(0.906 - EPSILON)
		expect(peak).toBeLessThanOrEqual(0.906 + EPSILON)
	end)

	it("releases at every strength, from a hint to the full page", function()
		for _, strength in ipairs({ 0.05, 0.3, 0.5, 0.75, 0.97, 0.98, 1 }) do
			local finished, peak = runOut(pulse(strength), LIFETIME)
			if finished == nil then
				error(("a %.2f pulse never released"):format(strength))
			end
			expect(peak).toBeLessThanOrEqual(strength + EPSILON)
		end
	end)
end)

describe("a pulse asked for again", function()
	it("comes back to rest after a whole combo of hits, all short of full strength", function()
		-- Four hits a quarter of a second apart, then nothing: the page must be clean again once the
		-- last one has had its release.
		local envelope = pulse(0.906)
		local elapsed = 0
		local nextHit = 0.25
		local hits = 1
		while hits < 4 do
			PulseEnvelope.step(envelope, FRAME)
			elapsed += FRAME
			if elapsed >= nextHit then
				PulseEnvelope.rearm(envelope, 0.906)
				hits += 1
				nextHit += 0.25
			end
		end
		local finished = runOut(envelope, LIFETIME)
		expect(finished).never.toBe(nil)
	end)

	it("is never pulled down by a weaker request, in any phase", function()
		local envelope = pulse(0.9)
		PulseEnvelope.step(envelope, FRAME)
		PulseEnvelope.rearm(envelope, 0.2)
		expect(envelope.Weight.Goal).toBeCloseTo(0.9, 6)
		-- Run it into its release: asked again, weaker than where it stands, it keeps on releasing
		-- instead of turning back into an attack toward a lower goal. Bounded, because a pulse that never
		-- reaches its release is the very defect this file is about and must fail here, not hang.
		local elapsed = 0
		while envelope.Phase ~= "Release" do
			PulseEnvelope.step(envelope, FRAME)
			elapsed += FRAME
			if elapsed > LIFETIME then
				error("a 0.9 pulse never reached its release: the page stays bleached")
			end
		end
		PulseEnvelope.rearm(envelope, 0.2)
		expect(envelope.Phase).toBe("Release")
		expect(envelope.Weight.Goal).toBe(0)
	end)

	it("keeps fading, instead of dropping in one frame, when a weaker hit lands during its release", function()
		-- Found by review: a near flash fading from 0.83 was cut to 0.10 in a single frame by a far hit,
		-- and a fight with hits at every distance flickered.
		local envelope = pulse(1)
		local guard = 0
		while envelope.Phase ~= "Release" do
			PulseEnvelope.step(envelope, FRAME)
			guard += FRAME
			if guard > LIFETIME then
				error("a full pulse never reached its release")
			end
		end
		PulseEnvelope.step(envelope, FRAME)
		local before = envelope.Weight.Position
		PulseEnvelope.rearm(envelope, 0.1)
		PulseEnvelope.step(envelope, FRAME)
		local after = envelope.Weight.Position
		-- One frame of a 0.16 s release takes off a fraction of the weight, never most of it.
		expect(before - after).toBeLessThan(before * 0.5)
		expect(after).toBeGreaterThan(0.1 + EPSILON)
		expect(runOut(envelope, LIFETIME)).never.toBe(nil)
	end)

	it("still flashes again when a hit lands on a pulse that has faded below it", function()
		local envelope = pulse(0.5)
		while envelope.Weight.Position > 0.2 or envelope.Phase ~= "Release" do
			PulseEnvelope.step(envelope, FRAME)
		end
		PulseEnvelope.rearm(envelope, 0.8)
		local finished, peak = runOut(envelope, LIFETIME)
		expect(finished).never.toBe(nil)
		expect(peak).toBeGreaterThan(0.8 - EPSILON)
	end)

	it("rises when the new request is stronger", function()
		local envelope = pulse(0.4)
		PulseEnvelope.step(envelope, FRAME)
		PulseEnvelope.rearm(envelope, 0.95)
		expect(envelope.Weight.Goal).toBeCloseTo(0.95, 6)
	end)
end)

describe("a frame that does not advance", function()
	it("never freezes a pulse in its hold", function()
		local envelope = pulse(1)
		while envelope.Phase ~= "Hold" do
			PulseEnvelope.step(envelope, FRAME)
		end
		PulseEnvelope.step(envelope, 0 / 0)
		PulseEnvelope.step(envelope, -1)
		PulseEnvelope.step(envelope, 0)
		expect(envelope.HoldRemaining == envelope.HoldRemaining).toBe(true)
		expect(runOut(envelope, LIFETIME)).never.toBe(nil)
	end)
end)

describe("WorldLighting", function()
	it("drives its pulses through this envelope and nowhere else", function()
		local code = (fs.readFile("src/client/Controllers/WorldLighting.luau"):gsub("%-%-[^\n]*", ""))
		expect(code:find("PulseEnvelope.step", 1, true)).never.toBe(nil)
		expect(code:find("PulseEnvelope.rearm", 1, true)).never.toBe(nil)
		-- The comparison that kept a weaker pulse alive forever must not come back inline.
		expect(code:find("1 - epsilon", 1, true)).toBe(nil)
	end)
end)
