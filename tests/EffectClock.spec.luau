--!strict
-- The effect clock (D-118): real time unless an impact holds it or the Studio lab scales it. Held to its
-- outputs, because a clock that drifts, jumps or runs backwards shows up as an effect that stutters.
local EffectClock = require("../src/shared/Pure/EffectClock")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("the effect clock", function()
	it("runs with real time until asked otherwise", function()
		local clock = EffectClock.new(10)
		expect(EffectClock.read(clock, 10)).toBeCloseTo(10, 9)
		expect(EffectClock.read(clock, 12.5)).toBeCloseTo(12.5, 9)
		expect(EffectClock.rate(clock, 12.5)).toBe(1)
	end)

	it("holds still for exactly the hold, then carries on from where it stopped", function()
		local clock = EffectClock.new(0)
		EffectClock.hold(clock, 1, 0.08, 0.2)
		expect(EffectClock.read(clock, 1)).toBeCloseTo(1, 9)
		expect(EffectClock.read(clock, 1.05)).toBeCloseTo(1, 9)
		expect(EffectClock.rate(clock, 1.05)).toBe(0)
		expect(EffectClock.read(clock, 1.08)).toBeCloseTo(1, 9)
		expect(EffectClock.read(clock, 1.18)).toBeCloseTo(1.1, 9)
		expect(EffectClock.rate(clock, 1.18)).toBe(1)
	end)

	it("never stacks holds past the longest one, and ignores an empty one", function()
		local clock = EffectClock.new(0)
		EffectClock.hold(clock, 1, 0.08, 0.1)
		EffectClock.hold(clock, 1.04, 0.08, 0.1)
		-- The later end wins: held until 1.12, not 1.16.
		expect(EffectClock.read(clock, 1.12)).toBeCloseTo(1, 9)
		expect(EffectClock.read(clock, 1.22)).toBeCloseTo(1.1, 9)
		local capped = EffectClock.new(0)
		EffectClock.hold(capped, 2, 5, 0.1)
		expect(EffectClock.read(capped, 2.2)).toBeCloseTo(2.1, 9)
		local empty = EffectClock.new(0)
		EffectClock.hold(empty, 3, 0, 0.1)
		expect(EffectClock.read(empty, 3.5)).toBeCloseTo(3.5, 9)
	end)

	it("scales from the moment it is rescaled, never backwards, and a hold keeps the new scale", function()
		local clock = EffectClock.new(0)
		EffectClock.rescale(clock, 2, 0.1)
		expect(EffectClock.read(clock, 2)).toBeCloseTo(2, 9)
		expect(EffectClock.read(clock, 3)).toBeCloseTo(2.1, 9)
		EffectClock.rescale(clock, 3, 0)
		expect(EffectClock.read(clock, 9)).toBeCloseTo(2.1, 9)
		expect(EffectClock.rate(clock, 9)).toBe(0)
		EffectClock.rescale(clock, 9, -4)
		expect(EffectClock.read(clock, 10)).toBeCloseTo(2.1, 9)
		EffectClock.rescale(clock, 10, 0.5)
		EffectClock.hold(clock, 10, 0.1, 0.2)
		expect(EffectClock.read(clock, 10.1)).toBeCloseTo(2.1, 9)
		expect(EffectClock.read(clock, 10.3)).toBeCloseTo(2.2, 9)
	end)

	it("holds from a moment ahead when asked, and merges a hold asked for during another", function()
		local clock = EffectClock.new(0)
		EffectClock.hold(clock, 1, 0.05, 0.1, 0.04)
		-- Runs on until the hold begins, stands still through it, then carries on.
		expect(EffectClock.read(clock, 1.03)).toBeCloseTo(1.03, 9)
		expect(EffectClock.rate(clock, 1.03)).toBe(1)
		expect(EffectClock.read(clock, 1.04)).toBeCloseTo(1.04, 9)
		expect(EffectClock.read(clock, 1.07)).toBeCloseTo(1.04, 9)
		expect(EffectClock.rate(clock, 1.07)).toBe(0)
		expect(EffectClock.read(clock, 1.19)).toBeCloseTo(1.14, 9)
		-- A second hold asked for while the first is still to come merges with it.
		local merged = EffectClock.new(0)
		EffectClock.hold(merged, 2, 0.05, 0.1, 0.04)
		EffectClock.hold(merged, 2.02, 0.05, 0.1, 0.04)
		expect(EffectClock.read(merged, 2.04)).toBeCloseTo(2.04, 9)
		expect(EffectClock.read(merged, 2.11)).toBeCloseTo(2.04, 9)
		expect(EffectClock.read(merged, 2.21)).toBeCloseTo(2.14, 9)
		-- A hold asked for long after the last one is its own.
		EffectClock.hold(merged, 5, 0.05, 0.1, 0.04)
		expect(EffectClock.read(merged, 5.04)).toBeCloseTo(4.97, 9)
		expect(EffectClock.read(merged, 5.08)).toBeCloseTo(4.97, 9)
		expect(EffectClock.read(merged, 5.19)).toBeCloseTo(5.07, 9)
	end)

	it("never runs backwards, whatever order it is held and scaled in", function()
		local clock = EffectClock.new(0)
		local last = EffectClock.read(clock, 0)
		local real = 0
		for step = 1, 400 do
			real += 0.013
			if step % 37 == 0 then
				EffectClock.hold(clock, real, 0.07, 0.1, (step % 2) * 0.04)
			elseif step % 53 == 0 then
				EffectClock.rescale(clock, real, (step % 3) * 0.5)
			end
			local now = EffectClock.read(clock, real)
			if now < last - 1e-9 then
				error(("the effect clock went back from %.4f to %.4f at step %d"):format(last, now, step))
			end
			last = now
		end
	end)
end)
