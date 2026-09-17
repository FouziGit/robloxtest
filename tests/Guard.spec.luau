--!strict
local Guard = require("../src/shared/Util/Guard")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("Guard", function()
	it("accepts and rejects primitives", function()
		expect((Guard.check(Guard.string(), "abc"))).toBe(true)
		expect((Guard.check(Guard.string(), 12))).toBe(false)
		expect((Guard.check(Guard.string({ max = 2 }), "abc"))).toBe(false)
		expect((Guard.check(Guard.number(), 1.5))).toBe(true)
		expect((Guard.check(Guard.number(), 0 / 0))).toBe(false)
		expect((Guard.check(Guard.number(), math.huge))).toBe(false)
		expect((Guard.check(Guard.number({ integer = true }), 1.5))).toBe(false)
		expect((Guard.check(Guard.number({ min = 1, max = 50 }), 51))).toBe(false)
		expect((Guard.check(Guard.boolean(), false))).toBe(true)
		expect((Guard.check(Guard.boolean(), "false"))).toBe(false)
		expect((Guard.check(Guard.literal("x"), "x"))).toBe(true)
		expect((Guard.check(Guard.literal("x"), "y"))).toBe(false)
		expect((Guard.check(Guard.oneOf({ "a", "b" }), "b"))).toBe(true)
		expect((Guard.check(Guard.oneOf({ "a", "b" }), "c"))).toBe(false)
	end)

	it("validates arrays strictly", function()
		local schema = Guard.array(Guard.oneOf({ "Fire", "Water" }), { maxLength = 3 })
		expect((Guard.check(schema, { "Fire", "Water" }))).toBe(true)
		expect((Guard.check(schema, { "Fire", "Lava" }))).toBe(false)
		expect((Guard.check(schema, { "Fire", "Fire", "Fire", "Fire" }))).toBe(false)
		expect((Guard.check(schema, { [1] = "Fire", [3] = "Water" }))).toBe(false)
		expect((Guard.check(schema, { Fire = true }))).toBe(false)
		expect((Guard.check(schema, "Fire"))).toBe(false)
	end)

	it("enforces array minLength", function()
		-- Same options CastJutsu uses: a combo sequence shorter than the shortest recipe is refused.
		local schema = Guard.array(Guard.oneOf({ "Fire", "Water" }), { minLength = 2, maxLength = 4 })
		expect((Guard.check(schema, {}))).toBe(false)
		expect((Guard.check(schema, { "Fire" }))).toBe(false)
		expect((Guard.check(schema, { "Fire", "Water" }))).toBe(true)
		expect((Guard.check(schema, { "Fire", "Water", "Fire", "Water" }))).toBe(true)
		expect((Guard.check(schema, { "Fire", "Water", "Fire", "Water", "Fire" }))).toBe(false)
		-- No minLength means no lower bound: the previous behaviour is untouched.
		expect((Guard.check(Guard.array(Guard.string()), {}))).toBe(true)
		local ok, reason = Guard.check(schema, { "Fire" })
		expect(ok).toBe(false)
		expect(reason).toContain("too short")
	end)

	it("rejects unknown keys in strict tables and allows optional fields", function()
		local schema =
			Guard.strict({ Volume = Guard.number({ min = 0, max = 1 }), Name = Guard.optional(Guard.string()) })
		expect((Guard.check(schema, { Volume = 0.5 }))).toBe(true)
		expect((Guard.check(schema, { Volume = 0.5, Name = "x" }))).toBe(true)
		expect((Guard.check(schema, { Volume = 0.5, Extra = 1 }))).toBe(false)
		expect((Guard.check(schema, {}))).toBe(false)
		local ok, reason = Guard.check(schema, { Volume = 2 })
		expect(ok).toBe(false)
		expect(reason).toContain("Volume")
	end)

	it("validates maps with string keys", function()
		local schema = Guard.map(Guard.string({ max = 4 }), { maxLength = 2 })
		expect((Guard.check(schema, { Fire = "J", Water = "K" }))).toBe(true)
		expect((Guard.check(schema, { Fire = "J", Water = "K", Earth = "L" }))).toBe(false)
		expect((Guard.check(schema, { [1] = "J" }))).toBe(false)
		expect((Guard.check(schema, { Fire = 5 }))).toBe(false)
	end)

	it("never throws on garbage", function()
		expect(function()
			Guard.check(
				Guard.array(Guard.string()),
				setmetatable({}, {
					__index = function()
						error("boom")
					end,
				})
			)
		end).never.toThrow()
	end)
end)
