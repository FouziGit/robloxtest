--!strict
-- Every way an instance pool fails is an accounting failure, and none of them is visible from the screen.
-- A borrow that creates where it should have reused looks exactly right and costs exactly what the pool
-- was built to avoid. A release that parks an instance twice hands it to two effects at once. A pool that
-- never discards grows every fight until the client it was meant to protect is the one that hitches.
--
-- So the policy is driven here through the sequences a real fight produces, with no engine anywhere near
-- it: borrow, release, reuse, overflow, double release, and the bound that says the thing cannot grow.
local Harness = require("./harness")
local PoolPolicy = require("../src/shared/Pure/PoolPolicy")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Small enough that a test reaches both ceilings in three lines. Parked below Live on purpose: that is the
-- shape the shipped rows have, and it is the shape that makes overflow reachable.
local LIMITS: { [string]: PoolPolicy.Limits } = {
	Part = { Live = 3, Parked = 2 },
	Trail = { Live = 2, Parked = 1 },
}

local function stateOf(policy: any, className: string): PoolPolicy.ClassState
	return policy:report()[className]
end

describe("PoolPolicy borrowing", function()
	it("creates when nothing is parked", function()
		local policy = PoolPolicy.new(LIMITS)
		local decision, index = policy:borrow("Part")
		expect(decision).toBe("Create")
		expect(index).toBe(0)

		local state = stateOf(policy, "Part")
		expect(state.Live).toBe(1)
		expect(state.Parked).toBe(0)
		expect(state.Created).toBe(1)
	end)

	it("parks what comes back, and reuses it instead of creating a second one", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		expect(policy:release("Part")).toBe("Park")
		expect(stateOf(policy, "Part").Parked).toBe(1)

		local decision = policy:borrow("Part")
		expect(decision).toBe("Reuse")
		-- The whole point: the second borrow cost nothing.
		expect(stateOf(policy, "Part").Created).toBe(1)
		expect(stateOf(policy, "Part").Parked).toBe(0)
	end)

	it("hands back the most recently parked entry", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		policy:borrow("Part")
		policy:release("Part")
		policy:release("Part")

		-- Last in, first out: the index is the top of the caller's stack, so a borrow is a pop and the
		-- warm instances stay at the top instead of every parked one rotating through every effect.
		local _, top = policy:borrow("Part")
		expect(top).toBe(2)
		local _, second = policy:borrow("Part")
		expect(second).toBe(1)
	end)

	it("refuses a borrow past the live ceiling instead of growing", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		policy:borrow("Part")
		policy:borrow("Part")

		local decision, index = policy:borrow("Part")
		expect(decision).toBe("Refuse")
		expect(index).toBe(0)
		local state = stateOf(policy, "Part")
		expect(state.Live).toBe(3)
		expect(state.Created).toBe(3)
		expect(state.Refused).toBe(1)
	end)

	it("refuses a class it has no ceiling for rather than inventing one", function()
		local policy = PoolPolicy.new(LIMITS)
		local decision = policy:borrow("Fire")
		expect(decision).toBe("Refuse")
		expect(policy:release("Fire")).toBe("Refuse")
		expect(policy:report().Fire).toBeNil()
	end)

	it("treats a malformed ceiling as zero rather than as a negative one", function()
		local policy = PoolPolicy.new({ Part = { Live = -5, Parked = -2 } })
		local decision = policy:borrow("Part")
		expect(decision).toBe("Refuse")
	end)
end)

describe("PoolPolicy releasing", function()
	it("discards instead of parking once the parked set is full", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		policy:borrow("Part")
		policy:borrow("Part")

		expect(policy:release("Part")).toBe("Park")
		expect(policy:release("Part")).toBe("Park")
		-- Parked is 2: the third one back is the one dropped, not an older parked one.
		expect(policy:release("Part")).toBe("Discard")

		local state = stateOf(policy, "Part")
		expect(state.Parked).toBe(2)
		expect(state.Live).toBe(0)
		expect(state.Discarded).toBe(1)
	end)

	it("refuses an instance it never had out, and does not let the count go negative", function()
		local policy = PoolPolicy.new(LIMITS)
		expect(policy:release("Part")).toBe("Refuse")

		local state = stateOf(policy, "Part")
		expect(state.Live).toBe(0)
		expect(state.Parked).toBe(0)
		expect(state.Unowned).toBe(1)
	end)

	it("refuses the same instance coming back twice", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		expect(policy:release("Part")).toBe("Park")
		-- Accepting this is what parks one instance twice and then draws two effects with it.
		expect(policy:release("Part")).toBe("Refuse")
		expect(stateOf(policy, "Part").Parked).toBe(1)
	end)

	it("drops a parked entry that is gone, and says so when there is none", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		policy:release("Part")

		expect(policy:drop("Part")).toBe(true)
		local state = stateOf(policy, "Part")
		expect(state.Parked).toBe(0)
		expect(state.Discarded).toBe(1)
		expect(policy:drop("Part")).toBe(false)
	end)
end)

describe("PoolPolicy accounting", function()
	it("keeps the high-water marks at the peak, not at the current count", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		policy:borrow("Part")
		policy:borrow("Part")
		policy:release("Part")
		policy:release("Part")
		policy:release("Part")

		local state = stateOf(policy, "Part")
		expect(state.Live).toBe(0)
		expect(state.PeakLive).toBe(3)
		-- Two parked and one discarded, so the parked peak is the cap and not the three that came back.
		expect(state.PeakParked).toBe(2)
	end)

	it("counts what is still out, across classes", function()
		local policy = PoolPolicy.new(LIMITS)
		expect(policy:outstanding()).toBe(0)
		policy:borrow("Part")
		policy:borrow("Trail")
		expect(policy:outstanding()).toBe(2)
		policy:release("Part")
		policy:release("Trail")
		-- This is the leak check a finished duel has to pass.
		expect(policy:outstanding()).toBe(0)
	end)

	it("hands out a copy of the accounting, not the accounting", function()
		local policy = PoolPolicy.new(LIMITS)
		policy:borrow("Part")
		local report = policy:report()
		report.Part.Live = 99
		expect(stateOf(policy, "Part").Live).toBe(1)
	end)

	it("never holds more of a class than its live ceiling, parked included", function()
		-- The bound that makes "the pool cannot grow" true rather than hoped for: because a borrow tests
		-- the ceiling before the parked set, everything the pool has ever built for a class is still
		-- either out or parked, and their sum stays under the ceiling whatever the fight does.
		local policy = PoolPolicy.new(LIMITS)
		local out = 0
		for step = 1, 200 do
			-- A fight is bursts of borrows with releases trailing behind, not one in one out.
			if step % 3 == 0 and out > 0 then
				policy:release("Part")
				out -= 1
			else
				local decision = policy:borrow("Part")
				if decision ~= "Refuse" then
					out += 1
				end
			end
			local state = stateOf(policy, "Part")
			expect(state.Live + state.Parked).toBeLessThanOrEqual(3)
			expect(state.Created).toBeLessThanOrEqual(3)
		end
		expect(stateOf(policy, "Part").Live).toBe(out)
	end)
end)

describe("PoolPolicy shipped ceilings", function()
	it("cover every class the VFX layer builds per effect", function()
		-- A class VfxPool can build but this table has no row for refuses every borrow of it, and the only
		-- symptom in game is effects quietly missing a layer.
		--
		-- The list is READ from VfxPool's source rather than copied here. A copied list cannot fail when
		-- VfxPool gains a class, which is the only failure this test exists to catch -- and it already
		-- happened once: Decal and Beam were added to the pool for the timeline runtime and the ceilings
		-- had to be noticed by hand. VfxPool itself cannot be required here, it is a controller full of
		-- Roblox globals, so the source is parsed the way tests/EffectCoverage.spec.luau parses its own.
		local source = fs.readFile("src/client/Controllers/VfxPool.luau")
		local table_ = string.match(source, "local CLASSES: { %[string%]: ClassOps } = (%b{})")
		if table_ == nil then
			error("could not find the CLASSES table in VfxPool.luau; this test is checking nothing")
		end
		local built: { string } = {}
		for className in string.gmatch(table_, "\n\t([%a][%w]*) = {") do
			table.insert(built, className)
		end
		expect(#built).toBeGreaterThanOrEqual(7)
		for _, className in ipairs(built) do
			if PoolPolicy.Limits[className] == nil then
				error(("VfxPool builds %s and PoolPolicy.Limits has no row for it"):format(className))
			end
		end
	end)

	it("are usable numbers", function()
		for className, limit in pairs(PoolPolicy.Limits) do
			-- A zero ceiling refuses everything, and a parked set larger than the ceiling can never fill:
			-- both are typos rather than decisions.
			expect(limit.Live > 0).toBe(true)
			expect(limit.Parked > 0).toBe(true)
			expect(limit.Parked <= limit.Live).toBe(true)
			expect(limit.Live).toBe(math.floor(limit.Live))
			expect(limit.Parked).toBe(math.floor(limit.Parked))
			-- An infinite ceiling is not a generous ceiling, it is the absence of one, and it looks like a
			-- number in a table full of numbers.
			expect(limit.Live < math.huge).toBe(true)
			expect(limit.Parked < math.huge).toBe(true)
			expect(#className > 0).toBe(true)
		end
	end)
end)
