--!strict
local ComboResolver = require("../src/shared/Pure/ComboResolver")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local recipes = {
	{ Id = "Brand", Combo = { "Cinnabar", "Cinnabar" } },
	{ Id = "Scorch", Combo = { "Cinnabar", "Cinnabar", "Verdigris" } },
	{ Id = "Sweep", Combo = { "Verdigris", "Verdigris" } },
	{ Id = "Bleed", Combo = { "Indigo", "Cinnabar" } },
	{ Id = "Margin", Combo = { "Indigo", "Indigo", "Umber" } },
	{ Id = "Blot", Combo = { "Cinnabar", "Umber", "Cinnabar", "Cinnabar" } },
}

describe("ComboResolver", function()
	local resolver = ComboResolver.new(recipes, 4)

	it("casts immediately when no longer recipe can follow", function()
		local sequence, decision = ComboResolver.push(resolver, {}, "Verdigris")
		expect(decision).toEqual({ Action = "Wait", Castable = false })
		sequence, decision = ComboResolver.push(resolver, sequence, "Verdigris")
		expect(decision).toEqual({ Action = "Cast", GlyphId = "Sweep" })
		expect(sequence).toHaveLength(0)
	end)

	it("waits when the sequence is both a recipe and a prefix", function()
		local sequence, decision = ComboResolver.push(resolver, { "Cinnabar" }, "Cinnabar")
		expect(decision).toEqual({ Action = "Wait", Castable = true })
		expect(sequence).toEqual({ "Cinnabar", "Cinnabar" })
	end)

	it("resolves the pending recipe on timeout, dissipates otherwise", function()
		expect(ComboResolver.timeout(resolver, { "Cinnabar", "Cinnabar" })).toEqual({
			Action = "Cast",
			GlyphId = "Brand",
		})
		expect(ComboResolver.timeout(resolver, { "Cinnabar" })).toEqual({ Action = "Reset", Reason = "Dissipated" })
		expect(ComboResolver.timeout(resolver, {})).toEqual({ Action = "Reset", Reason = "Empty" })
	end)

	it("extends a pending recipe into a longer one", function()
		local sequence, decision = ComboResolver.push(resolver, { "Cinnabar", "Cinnabar" }, "Verdigris")
		expect(decision).toEqual({ Action = "Cast", GlyphId = "Scorch" })
		expect(sequence).toHaveLength(0)
	end)

	it("resets dead sequences immediately", function()
		local sequence, decision = ComboResolver.push(resolver, { "Verdigris" }, "Cinnabar")
		expect(decision).toEqual({ Action = "Reset", Reason = "NoMatch" })
		expect(sequence).toHaveLength(0)
	end)

	it("handles four-press recipes and the max length", function()
		local sequence = {}
		local decision
		for _, pigment in ipairs({ "Cinnabar", "Umber", "Cinnabar" }) do
			sequence, decision = ComboResolver.push(resolver, sequence, pigment)
			expect(decision.Action).toBe("Wait")
		end
		sequence, decision = ComboResolver.push(resolver, sequence, "Cinnabar")
		expect(decision).toEqual({ Action = "Cast", GlyphId = "Blot" })

		local short = ComboResolver.new(
			{ { Id = "Long", Combo = { "Cinnabar", "Cinnabar", "Cinnabar", "Cinnabar", "Cinnabar" } } },
			4
		)
		local pending = { "Cinnabar", "Cinnabar", "Cinnabar", "Cinnabar" }
		local _, tooLong = ComboResolver.push(short, pending, "Cinnabar")
		expect(tooLong).toEqual({ Action = "Reset", Reason = "TooLong" })
	end)

	it("says where a sequence can go next: one step, only toward a recipe", function()
		-- Nothing pressed: every first pigment, once each, in the order the recipes come.
		expect(ComboResolver.continuations(resolver, {})).toEqual({ "Cinnabar", "Verdigris", "Indigo" })
		-- After Cinnabar: exactly the next pigments of the recipes that start with it.
		expect(ComboResolver.continuations(resolver, { "Cinnabar" })).toEqual({ "Cinnabar", "Umber" })
		expect(ComboResolver.continuations(resolver, { "Cinnabar", "Cinnabar" })).toEqual({ "Verdigris" })
		expect(ComboResolver.continuations(resolver, { "Indigo" })).toEqual({ "Cinnabar", "Indigo" })
		-- A whole recipe that nothing extends, and a sequence no recipe starts with, lead nowhere.
		expect(ComboResolver.continuations(resolver, { "Verdigris", "Verdigris" })).toEqual({})
		expect(ComboResolver.continuations(resolver, { "Umber" })).toEqual({})
		expect(ComboResolver.continuations(resolver, { "Cinnabar", "Umber", "Cinnabar", "Cinnabar" })).toEqual({})
		-- Each call hands out its own list.
		local first = ComboResolver.continuations(resolver, {})
		table.clear(first)
		expect(#ComboResolver.continuations(resolver, {})).toBe(3)
	end)

	it("hints only pigments that a push then waits on or casts", function()
		for _, prefix in ipairs({ {}, { "Cinnabar" }, { "Indigo" }, { "Cinnabar", "Umber" } }) do
			for _, pigment in ipairs(ComboResolver.continuations(resolver, prefix)) do
				local _, decision = ComboResolver.push(resolver, prefix, pigment)
				expect(decision.Action ~= "Reset").toBe(true)
			end
		end
	end)

	it("reports duplicate recipes and keeps the first", function()
		local dup = ComboResolver.new({
			{ Id = "A", Combo = { "Cinnabar", "Cinnabar" } },
			{ Id = "B", Combo = { "Cinnabar", "Cinnabar" } },
		}, 4)
		expect(dup.duplicates).toEqual({ "Cinnabar-Cinnabar" })
		expect(ComboResolver.resolve(dup, { "Cinnabar", "Cinnabar" })).toBe("A")
	end)

	it("resolves exact sequences for server validation", function()
		expect(ComboResolver.resolve(resolver, { "Indigo", "Indigo", "Umber" })).toBe("Margin")
		expect(ComboResolver.resolve(resolver, { "Indigo", "Indigo" })).toBeNil()
		expect(ComboResolver.resolve(resolver, {})).toBeNil()
		expect(ComboResolver.resolve(resolver, { "Cinnabar", "Cinnabar", "Cinnabar", "Cinnabar", "Cinnabar" })).toBeNil()
	end)
end)
