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
end)
