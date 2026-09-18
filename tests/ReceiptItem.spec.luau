--!strict
local Harness = require("./harness")
local ReceiptItem = require("../src/shared/Pure/ReceiptItem")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CATALOGUE: { ReceiptItem.Item } = {
	{ Id = "CommonA", Rarity = "Common", Sellable = true },
	{ Id = "CommonB", Rarity = "Common", Sellable = true },
	{ Id = "RareA", Rarity = "Rare", Sellable = true },
	{ Id = "RareGift", Rarity = "Rare", Sellable = false },
	{ Id = "EpicA", Rarity = "Epic", Sellable = true },
}
local ROTATION = { "EpicA", "RareA", "CommonB" }

describe("ReceiptItem", function()
	it("honours the intended item when it still applies", function()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, {}, "Common", "CommonA")).toBe("CommonA")
	end)

	it("ignores an intent of the wrong rarity and falls back to the rotation", function()
		-- The exploit the fallback exists for: the intent slot was overwritten with a cheaper item
		-- while the dialog for the dearer rarity was open. The player paid for Epic, so they get Epic.
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, {}, "Epic", "CommonA")).toBe("EpicA")
	end)

	it("ignores an unknown or absent intent", function()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, {}, "Rare", "DoesNotExist")).toBe("RareA")
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, {}, "Rare", nil)).toBe("RareA")
	end)

	it("never returns an item the player already owns", function()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, { "CommonB" }, "Common", "CommonB")).toBe("CommonA")
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, { "CommonA", "CommonB" }, "Common", nil)).toBeNil()
	end)

	it("never returns an item that is not sellable", function()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, { "RareA" }, "Rare", "RareGift")).toBeNil()
		expect(ReceiptItem.deliverable({ Id = "RareGift", Rarity = "Rare", Sellable = false }, "Rare", {})).toBe(false)
	end)

	it("prefers the rotation over the rest of the catalogue", function()
		-- CommonB is in the rotation, CommonA is not, so an intent-less Common receipt takes CommonB.
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, {}, "Common", nil)).toBe("CommonB")
	end)

	it("reaches outside the rotation when the rotation is exhausted", function()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, { "CommonB" }, "Common", nil)).toBe("CommonA")
		expect(ReceiptItem.pick(CATALOGUE, {}, {}, "Common", nil)).toBe("CommonA")
	end)

	it("returns nil only when nothing of the rarity is left", function()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, {}, "Legendary", nil)).toBeNil()
		expect(ReceiptItem.pick(CATALOGUE, ROTATION, { "EpicA" }, "Epic", "EpicA")).toBeNil()
	end)
end)
