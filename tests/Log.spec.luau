--!strict
-- Log.try and Log.succeeded answer different questions, and confusing them cost a refused cosmetic grant
-- and an unconfirmed profile save that both read as having worked. These tests pin the difference.
--
-- The failure cases genuinely call `warn`, so a few warning lines in the runner output are expected here
-- and prove the contract that an error is never swallowed.
local Harness = require("./harness")
local Log = require("../src/shared/Util/Log")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local log = Log.new("LogSpec")

describe("Log.try", function()
	it("reports only whether the call threw, and discards the result", function()
		expect(log.try("returns nothing", function() end)).toBe(true)
		-- The trap: a function reporting "I did not do it" still reads as true here.
		expect(log.try("returns false", function()
			return false
		end)).toBe(true)
		expect(log.try("returns nil", function()
			return nil
		end)).toBe(true)
		expect(log.try("throws", function()
			error("boom")
		end)).toBe(false)
	end)

	it("passes its arguments through", function()
		local seen: { any } = {}
		expect(log.try("args", function(a: number, b: string)
			seen = { a, b }
		end, 7, "x")).toBe(true)
		expect(seen[1]).toBe(7)
		expect(seen[2]).toBe("x")
	end)
end)

describe("Log.succeeded", function()
	it("is true only when the call neither threw nor returned a falsy result", function()
		expect(log.succeeded("returns true", function()
			return true
		end)).toBe(true)
		expect(log.succeeded("returns a value", function()
			return "granted"
		end)).toBe(true)
		expect(log.succeeded("returns false", function()
			return false
		end)).toBe(false)
		expect(log.succeeded("returns nil", function()
			return nil
		end)).toBe(false)
		expect(log.succeeded("returns nothing", function() end)).toBe(false)
		expect(log.succeeded("throws", function()
			error("boom")
		end)).toBe(false)
	end)

	it("passes its arguments through and reads only the first result", function()
		expect(log.succeeded("args", function(amount: number)
			return amount > 0, "ignored"
		end, 5)).toBe(true)
		expect(log.succeeded("args", function(amount: number)
			return amount > 0, "ignored"
		end, -1)).toBe(false)
	end)
end)

describe("Log formatting", function()
	it("never throws on a bad format string", function()
		-- A caller that passes the wrong number of arguments must still get a line, not an error.
		expect(log.try("bad format", function()
			log.info("%d and %d", 1)
		end)).toBe(true)
		expect(log.try("no args", function()
			log.info("plain message")
		end)).toBe(true)
	end)
end)
