--!strict
local ComboResolver = require("../src/shared/Pure/ComboResolver")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local recipes = {
	{ Id = "Fireball", Combo = { "Fire", "Fire" } },
	{ Id = "EmberStorm", Combo = { "Fire", "Fire", "Wind" } },
	{ Id = "WindGust", Combo = { "Wind", "Wind" } },
	{ Id = "BoilingMist", Combo = { "Water", "Fire" } },
	{ Id = "MudWall", Combo = { "Water", "Water", "Earth" } },
	{ Id = "Meteor", Combo = { "Fire", "Earth", "Fire", "Fire" } },
}

describe("ComboResolver", function()
	local resolver = ComboResolver.new(recipes, 4)

	it("casts immediately when no longer recipe can follow", function()
		local sequence, decision = ComboResolver.push(resolver, {}, "Wind")
		expect(decision).toEqual({ Action = "Wait", Castable = false })
		sequence, decision = ComboResolver.push(resolver, sequence, "Wind")
		expect(decision).toEqual({ Action = "Cast", JutsuId = "WindGust" })
		expect(sequence).toHaveLength(0)
	end)

	it("waits when the sequence is both a recipe and a prefix", function()
		local sequence, decision = ComboResolver.push(resolver, { "Fire" }, "Fire")
		expect(decision).toEqual({ Action = "Wait", Castable = true })
		expect(sequence).toEqual({ "Fire", "Fire" })
	end)

	it("resolves the pending recipe on timeout, dissipates otherwise", function()
		expect(ComboResolver.timeout(resolver, { "Fire", "Fire" })).toEqual({ Action = "Cast", JutsuId = "Fireball" })
		expect(ComboResolver.timeout(resolver, { "Fire" })).toEqual({ Action = "Reset", Reason = "Dissipated" })
		expect(ComboResolver.timeout(resolver, {})).toEqual({ Action = "Reset", Reason = "Empty" })
	end)

	it("extends a pending recipe into a longer one", function()
		local sequence, decision = ComboResolver.push(resolver, { "Fire", "Fire" }, "Wind")
		expect(decision).toEqual({ Action = "Cast", JutsuId = "EmberStorm" })
		expect(sequence).toHaveLength(0)
	end)

	it("resets dead sequences immediately", function()
		local sequence, decision = ComboResolver.push(resolver, { "Wind" }, "Fire")
		expect(decision).toEqual({ Action = "Reset", Reason = "NoMatch" })
		expect(sequence).toHaveLength(0)
	end)

	it("handles four-press recipes and the max length", function()
		local sequence = {}
		local decision
		for _, element in ipairs({ "Fire", "Earth", "Fire" }) do
			sequence, decision = ComboResolver.push(resolver, sequence, element)
			expect(decision.Action).toBe("Wait")
		end
		sequence, decision = ComboResolver.push(resolver, sequence, "Fire")
		expect(decision).toEqual({ Action = "Cast", JutsuId = "Meteor" })

		local short = ComboResolver.new({ { Id = "Long", Combo = { "Fire", "Fire", "Fire", "Fire", "Fire" } } }, 4)
		local pending = { "Fire", "Fire", "Fire", "Fire" }
		local _, tooLong = ComboResolver.push(short, pending, "Fire")
		expect(tooLong).toEqual({ Action = "Reset", Reason = "TooLong" })
	end)

	it("reports duplicate recipes and keeps the first", function()
		local dup = ComboResolver.new({
			{ Id = "A", Combo = { "Fire", "Fire" } },
			{ Id = "B", Combo = { "Fire", "Fire" } },
		}, 4)
		expect(dup.duplicates).toEqual({ "Fire-Fire" })
		expect(ComboResolver.resolve(dup, { "Fire", "Fire" })).toBe("A")
	end)

	it("resolves exact sequences for server validation", function()
		expect(ComboResolver.resolve(resolver, { "Water", "Water", "Earth" })).toBe("MudWall")
		expect(ComboResolver.resolve(resolver, { "Water", "Water" })).toBeNil()
		expect(ComboResolver.resolve(resolver, {})).toBeNil()
		expect(ComboResolver.resolve(resolver, { "Fire", "Fire", "Fire", "Fire", "Fire" })).toBeNil()
	end)
end)
