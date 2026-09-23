--!strict
-- The curves behind the feel. The one that matters most is impulseSpeed: it changes HOW a knockback
-- moves without changing HOW FAR it throws, and if that second half is wrong then a polish pass has
-- silently rebalanced the game.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local FeelMath = require("../src/shared/Pure/FeelMath")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local HIT_STOP = FeelConfig.HitStop

describe("FeelMath.hitStopSeconds", function()
	it("stays inside the window at both extremes", function()
		expect(FeelMath.hitStopSeconds(0, HIT_STOP)).toBe(HIT_STOP.MinSeconds)
		expect(FeelMath.hitStopSeconds(-50, HIT_STOP)).toBe(HIT_STOP.MinSeconds)
		expect(FeelMath.hitStopSeconds(10000, HIT_STOP)).toBe(HIT_STOP.MaxSeconds)
	end)

	it("rises with damage and never falls", function()
		local previous = 0
		for damage = 0, 60 do
			local seconds = FeelMath.hitStopSeconds(damage, HIT_STOP)
			expect(seconds >= previous).toBe(true)
			previous = seconds
		end
	end)

	it("puts a jab and an ultimate at opposite ends", function()
		local jab = FeelMath.hitStopSeconds(HIT_STOP.MinDamage, HIT_STOP)
		local ultimate = FeelMath.hitStopSeconds(HIT_STOP.MaxDamage, HIT_STOP)
		expect(ultimate > jab * 1.5).toBe(true)
	end)
end)

describe("FeelMath.mergeHitStop", function()
	it("takes the longer of two, never their sum", function()
		expect(FeelMath.mergeHitStop(0.05, 0.08)).toBe(0.08)
		expect(FeelMath.mergeHitStop(0.08, 0.05)).toBe(0.08)
		-- Five hits landing inside one stop must not hold the player for a quarter of a second.
		local remaining = 0
		for _ = 1, 5 do
			remaining = FeelMath.mergeHitStop(remaining, HIT_STOP.MaxSeconds)
		end
		expect(remaining).toBe(HIT_STOP.MaxSeconds)
	end)
end)

describe("FeelMath.falloff", function()
	it("is whole at the impact and nothing at the radius", function()
		expect(FeelMath.falloff(0, 70)).toBe(1)
		expect(FeelMath.falloff(70, 70)).toBe(0)
		expect(FeelMath.falloff(500, 70)).toBe(0)
	end)

	it("never rises with distance", function()
		local previous = math.huge
		for distance = 0, 80, 2 do
			local value = FeelMath.falloff(distance, 70)
			expect(value <= previous).toBe(true)
			previous = value
		end
	end)

	it("returns nothing rather than dividing by zero when the radius is zero", function()
		expect(FeelMath.falloff(0, 0)).toBe(0)
	end)
end)

describe("FeelMath.impulseSpeed", function()
	-- Integrates the curve over its own duration with the midpoint rule. If this is not 1, the curve
	-- moves a character a different distance than the server granted, and knockback range has changed.
	local function travelled(exponent: number, samples: number): number
		local total = 0
		local step = 1 / samples
		for index = 0, samples - 1 do
			total += FeelMath.impulseSpeed((index + 0.5) * step, exponent) * step
		end
		return total
	end

	it("covers exactly the distance a flat velocity would, for every exponent used", function()
		for _, exponent in ipairs({ 0, 0.5, FeelConfig.Impulse.DashExponent, FeelConfig.Impulse.KnockbackExponent, 4 }) do
			local distance = travelled(exponent, 20000)
			expect(math.abs(distance - 1) < 0.001).toBe(true)
		end
	end)

	it("starts faster than flat and ends at rest", function()
		local exponent = FeelConfig.Impulse.KnockbackExponent
		expect(FeelMath.impulseSpeed(0, exponent) > 1).toBe(true)
		expect(FeelMath.impulseSpeed(1, exponent)).toBe(0)
	end)

	it("decays without ever speeding back up", function()
		local exponent = FeelConfig.Impulse.KnockbackExponent
		local previous = math.huge
		for index = 0, 100 do
			local speed = FeelMath.impulseSpeed(index / 100, exponent)
			expect(speed <= previous).toBe(true)
			previous = speed
		end
	end)

	it("is flat at exponent zero, which is the behaviour it replaces", function()
		expect(FeelMath.impulseSpeed(0, 0)).toBe(1)
		expect(FeelMath.impulseSpeed(0.5, 0)).toBe(1)
		expect(FeelMath.impulseSpeed(0.999, 0)).toBe(1)
	end)

	it("clamps an alpha outside its own duration instead of reversing", function()
		local exponent = FeelConfig.Impulse.KnockbackExponent
		expect(FeelMath.impulseSpeed(2, exponent)).toBe(0)
		expect(FeelMath.impulseSpeed(-1, exponent)).toBe(FeelMath.impulseSpeed(0, exponent))
	end)
end)

describe("FeelMath.holdThenFade", function()
	it("holds, then fades to nothing", function()
		local hold = FeelConfig.DamageNumbers.HoldFraction
		expect(FeelMath.holdThenFade(0, hold)).toBe(1)
		expect(FeelMath.holdThenFade(hold, hold)).toBe(1)
		expect(FeelMath.holdThenFade(1, hold)).toBe(0)
		expect(FeelMath.holdThenFade(2, hold)).toBe(0)
	end)

	it("never fades before the number can be read", function()
		local hold = FeelConfig.DamageNumbers.HoldFraction
		expect(hold > 0.2).toBe(true)
		for index = 0, 40 do
			local alpha = (index / 40) * hold
			expect(FeelMath.holdThenFade(alpha, hold)).toBe(1)
		end
	end)
end)

describe("FeelMath.inkFade", function()
	-- Exponential Out, the ease the Wash stains give their size: 85 % spread a fifth of the way in.
	local function exponentialOut(t: number): number
		return if t >= 1 then 1 else 1 - 2 ^ (-10 * t)
	end

	it("keeps a stain that spreads in a flash on the page for most of its life", function()
		-- The defect measured in a live client: a Wash stain, 0.32 -> 1 over 2.4 s, spread on Exponential
		-- Out and faded on the same curve, was 73 % transparent a third of a second in.
		local elapsed = 0.32 / 2.4
		local fade = FeelMath.inkFade(elapsed, exponentialOut(elapsed))
		expect(0.32 + (1 - 0.32) * fade).toBeLessThan(0.4)
		-- Still readable (under 0.6) at the half of its life, where it used to be gone after an eighth.
		local half = FeelMath.inkFade(0.5, exponentialOut(0.5))
		expect(0.32 + (1 - 0.32) * half).toBeLessThan(0.6)
	end)

	it("never fades faster than ink dries, nor faster than the layer's own ease", function()
		for index = 0, 100 do
			local elapsed = index / 100
			local drying = 1 - math.cos(elapsed * math.pi / 2)
			for _, shaped in ipairs({ 0, elapsed * elapsed, elapsed, exponentialOut(elapsed), 1 }) do
				local fade = FeelMath.inkFade(elapsed, shaped)
				expect(fade).toBeLessThanOrEqual(drying + 1e-9)
				expect(fade).toBeLessThanOrEqual(shaped + 1e-9)
				expect(fade).toBeGreaterThanOrEqual(0)
			end
		end
	end)

	it("does fade: it dries on its own curve, continuously, whenever the layer's ease is ahead of it", function()
		-- Upper bounds alone let a law that holds and then pops pass; this pins the curve from below and
		-- forbids a jump between two frames of the shortest fading layer in the game (0.12 s).
		local frame = (1 / 60) / 0.12
		local previous = 0
		for index = 0, 100 do
			local elapsed = index / 100
			local drying = 1 - math.cos(elapsed * math.pi / 2)
			local fade = FeelMath.inkFade(elapsed, exponentialOut(elapsed))
			expect(fade).toBeGreaterThanOrEqual(math.min(drying, exponentialOut(elapsed)) - 1e-9)
			expect(fade).toBeGreaterThanOrEqual(previous - 1e-9)
			previous = fade
		end
		local steepest = 0
		local elapsed = 0
		while elapsed < 1 do
			local nextElapsed = math.min(elapsed + frame, 1)
			steepest = math.max(steepest, FeelMath.inkFade(nextElapsed, 1) - FeelMath.inkFade(elapsed, 1))
			elapsed = nextElapsed
		end
		expect(steepest).toBeLessThan(0.25)
	end)

	it("starts untouched, ends gone, and keeps an ease that overshoots inside the two", function()
		expect(FeelMath.inkFade(0, 0)).toBe(0)
		expect(FeelMath.inkFade(1, 1)).toBeCloseTo(1, 9)
		-- Back Out overshoots past one; Back In dips below zero first.
		expect(FeelMath.inkFade(0.6, 1.08)).toBeLessThanOrEqual(1)
		expect(FeelMath.inkFade(0.2, -0.05)).toBe(0)
		expect(FeelMath.inkFade(0 / 0, 0.5)).toBe(0)
	end)
end)

describe("FeelMath.layerFade", function()
	it("dries a fading layer, and leaves a darkening one or a gesture on its own ease", function()
		local elapsed, shaped = 0.2, 0.9
		local drying = FeelMath.inkFade(elapsed, shaped)
		expect(drying).toBeLessThan(shaped)
		-- Fading out: the ink's clock.
		expect(FeelMath.layerFade(0.3, 1, elapsed, shaped, false)).toBe(drying)
		-- Darkening -- a warning gathering -- or holding: the author's ease, untouched.
		expect(FeelMath.layerFade(1, 0.2, elapsed, shaped, false)).toBe(shaped)
		expect(FeelMath.layerFade(0.4, 0.4, elapsed, shaped, false)).toBe(shaped)
		-- A fade that is the gesture itself (VfxTimelineConfig.Layer.FadesWithSize).
		expect(FeelMath.layerFade(0.1, 1, elapsed, shaped, true)).toBe(shaped)
	end)
end)
