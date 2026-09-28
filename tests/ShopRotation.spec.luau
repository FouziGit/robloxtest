--!strict
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local Harness = require("./harness")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local ShopRotation = require("../src/shared/Pure/ShopRotation")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("ShopRotation", function()
	it("is deterministic, distinct and respects rarity slots", function()
		local a = ShopRotation.select(CosmeticConfig.Items, "S100", ShopConfig.Rotation, ShopConfig.RarityOrder)
		local b = ShopRotation.select(CosmeticConfig.Items, "S100", ShopConfig.Rotation, ShopConfig.RarityOrder)
		expect(a).toEqual(b)
		local expected = 0
		for _, count in pairs(ShopConfig.Rotation) do
			expected += count
		end
		expect(a).toHaveLength(expected)
		local seen = {}
		local counts = {}
		for _, id in ipairs(a) do
			expect(seen[id]).toBeNil()
			seen[id] = true
			local item = CosmeticConfig.ById[id]
			expect(item.Sellable).toBe(true)
			counts[item.Rarity] = (counts[item.Rarity] or 0) + 1
		end
		for rarity, count in pairs(ShopConfig.Rotation) do
			expect(counts[rarity]).toBe(count)
		end
	end)

	it("changes between days", function()
		local differs = false
		local base = ShopRotation.select(CosmeticConfig.Items, "S1", ShopConfig.Rotation, ShopConfig.RarityOrder)
		for day = 2, 6 do
			local other =
				ShopRotation.select(CosmeticConfig.Items, "S" .. day, ShopConfig.Rotation, ShopConfig.RarityOrder)
			for index, id in ipairs(base) do
				if other[index] ~= id then
					differs = true
				end
			end
		end
		expect(differs).toBe(true)
		expect(ShopRotation.dayKey(86400 * 5 + 10)).toBe("S5")
	end)

	it("names the second the next rotation starts, and no second before it", function()
		-- Mid-day, a server clock's fraction of a second, and the very first second of a day.
		for _, now in ipairs({ 86400 * 5 + 10, 86400 * 20725 + 43200.75, 86400 * 7, 86400 * 7 - 1 }) do
			local nextAt = ShopRotation.nextRotationAt(now)
			expect(nextAt > now).toBe(true)
			expect(ShopRotation.dayKey(nextAt) ~= ShopRotation.dayKey(now)).toBe(true)
			expect(ShopRotation.dayKey(nextAt - 1)).toBe(ShopRotation.dayKey(now))
			-- A day at most: the countdown never promises more than the rotation lasts.
			expect(nextAt - now <= 86400).toBe(true)
		end
		expect(ShopRotation.nextRotationAt(86400 * 5 + 10)).toBe(86400 * 6)
		expect(ShopRotation.nextRotationAt(86400 * 7)).toBe(86400 * 8)
	end)
end)
