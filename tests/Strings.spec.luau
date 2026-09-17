--!strict
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("Strings", function()
	it("has en and fr for every key", function()
		for key, entry in pairs(Strings.Table) do
			expect(type(entry.en)).toBe("string")
			expect(type(entry.fr)).toBe("string")
			expect(#entry.en).toBeGreaterThan(0)
			expect(#entry.fr).toBeGreaterThan(0)
			-- both locales must use the same placeholders
			local enParams: { [string]: boolean } = {}
			for name in string.gmatch(entry.en, "{(%w+)}") do
				enParams[name] = true
			end
			for name in string.gmatch(entry.fr, "{(%w+)}") do
				if not enParams[name] then
					error(("key %s: placeholder {%s} only in fr"):format(key, name))
				end
				enParams[name] = nil
			end
			if next(enParams) ~= nil then
				error(("key %s: placeholder only in en"):format(key))
			end
		end
	end)

	it("substitutes params and falls back to English", function()
		expect(Strings.t("hud.levelUp", { level = 7 })).toBe("Level 7 reached!")
		expect(Strings.t("hud.levelUp", { level = 7 }, "fr")).toBe("Niveau 7 atteint !")
		expect(Strings.t("hud.levelUp", { level = 7 }, "de")).toBe("Level 7 reached!")
		expect(Strings.t("hud.levelUp")).toBe("Level {level} reached!")
	end)

	it("marks missing keys visibly instead of throwing", function()
		expect(Strings.t("does.not.exist")).toBe("[does.not.exist]")
		expect(Strings.has("does.not.exist")).toBe(false)
		expect(Strings.has("common.ok")).toBe(true)
	end)

	it("lists keys sorted", function()
		local keys = Strings.keys()
		expect(#keys).toBeGreaterThan(50)
		for index = 2, #keys do
			expect(keys[index - 1] < keys[index]).toBe(true)
		end
	end)
end)
