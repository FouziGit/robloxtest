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
		local schema = Guard.array(Guard.oneOf({ "Cinnabar", "Indigo" }), { maxLength = 3 })
		expect((Guard.check(schema, { "Cinnabar", "Indigo" }))).toBe(true)
		expect((Guard.check(schema, { "Cinnabar", "Lava" }))).toBe(false)
		expect((Guard.check(schema, { "Cinnabar", "Cinnabar", "Cinnabar", "Cinnabar" }))).toBe(false)
		expect((Guard.check(schema, { [1] = "Cinnabar", [3] = "Indigo" }))).toBe(false)
		expect((Guard.check(schema, { Cinnabar = true }))).toBe(false)
		expect((Guard.check(schema, "Cinnabar"))).toBe(false)
	end)

	it("enforces array minLength", function()
		-- Same options CastJutsu uses: a combo sequence shorter than the shortest recipe is refused.
		local schema = Guard.array(Guard.oneOf({ "Cinnabar", "Indigo" }), { minLength = 2, maxLength = 4 })
		expect((Guard.check(schema, {}))).toBe(false)
		expect((Guard.check(schema, { "Cinnabar" }))).toBe(false)
		expect((Guard.check(schema, { "Cinnabar", "Indigo" }))).toBe(true)
		expect((Guard.check(schema, { "Cinnabar", "Indigo", "Cinnabar", "Indigo" }))).toBe(true)
		expect((Guard.check(schema, { "Cinnabar", "Indigo", "Cinnabar", "Indigo", "Cinnabar" }))).toBe(false)
		-- No minLength means no lower bound: the previous behaviour is untouched.
		expect((Guard.check(Guard.array(Guard.string()), {}))).toBe(true)
		local ok, reason = Guard.check(schema, { "Cinnabar" })
		expect(ok).toBe(false)
		expect(reason).toContain("too short")
	end)

	it("rejects an over-long array before walking the rest of it", function()
		-- A tampered client can send far more entries than the schema declares, so the bound has to be
		-- hit while counting. The hole past the bound is the witness: a scan that counted every key
		-- first would report the hole instead of the length.
		local schema = Guard.array(Guard.string(), { maxLength = 4 })
		local flood: { [number]: string } = {}
		for index = 1, 10 do
			flood[index] = "x"
		end
		flood[20] = "x"
		local ok, reason = Guard.check(schema, flood)
		expect(ok).toBe(false)
		expect(reason).toContain("too long")
	end)

	it("rejects a flooded strict table on the first key outside the schema", function()
		-- Same bound, held by the schema itself: only the declared fields can pass, so the scan ends on
		-- the first key that is not one of them however many the payload carries.
		local schema = Guard.strict({ Volume = Guard.number() })
		local flood: { [string]: number } = { Volume = 0.5 }
		for index = 1, 500 do
			flood["k" .. index] = index
		end
		local ok, reason = Guard.check(schema, flood)
		expect(ok).toBe(false)
		expect(reason).toContain("unexpected key")
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
		expect((Guard.check(schema, { Cinnabar = "J", Indigo = "K" }))).toBe(true)
		expect((Guard.check(schema, { Cinnabar = "J", Indigo = "K", Umber = "L" }))).toBe(false)
		expect((Guard.check(schema, { [1] = "J" }))).toBe(false)
		expect((Guard.check(schema, { Cinnabar = 5 }))).toBe(false)
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
