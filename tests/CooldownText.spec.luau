--!strict
-- The seconds a cooling glyph shows (D-147, the board's "3,2"): tenths under ten, whole seconds from ten, both
-- rounded up so a glyph never reads ready early, in the locale's own mark.
local CooldownText = require("../src/shared/Pure/CooldownText")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function shown(remaining: number): (number, number?)
	return CooldownText.split(remaining)
end

describe("a cooldown's seconds", function()
	it("count in tenths under ten seconds, rounded up", function()
		local whole, tenth = shown(3.2)
		expect(whole).toBe(3)
		expect(tenth).toBe(2)
		whole, tenth = shown(3.21)
		expect(whole).toBe(3)
		expect(tenth).toBe(3)
		whole, tenth = shown(9.9)
		expect(whole).toBe(9)
		expect(tenth).toBe(9)
		-- The last moment still says something is left.
		whole, tenth = shown(0.04)
		expect(whole).toBe(0)
		expect(tenth).toBe(1)
		-- A float's noise past a tenth is the tenth.
		whole, tenth = shown(3.2 + 1e-9)
		expect(whole).toBe(3)
		expect(tenth).toBe(2)
	end)

	it("count in whole seconds from ten up, rounded up, and never read 10.0", function()
		local whole, tenth = shown(10)
		expect(whole).toBe(10)
		expect(tenth).toBeNil()
		whole, tenth = shown(12.3)
		expect(whole).toBe(13)
		expect(tenth).toBeNil()
		-- Under ten, but ten once rounded up: whole.
		whole, tenth = shown(9.95)
		expect(whole).toBe(10)
		expect(tenth).toBeNil()
		expect(CooldownText.TenthsBelow).toBe(10)
	end)

	it("write the tenth with each language's own mark", function()
		expect(Strings.t("hud.hotbar.seconds", { whole = 3, tenth = 2 }, "fr")).toBe("3,2")
		expect(Strings.t("hud.hotbar.seconds", { whole = 3, tenth = 2 }, "en")).toBe("3.2")
	end)
end)

return nil
