--!strict
-- Which cosmetic a paid Robux receipt of a given rarity must hand over. Pure: no Roblox global, no
-- require, so it is unit-tested under Lune (tests/ReceiptItem.spec.luau).
--
-- The Robux are debited when the player confirms the dialog, so this decision must not be able to come
-- back empty while anything of that rarity is still owed. The intent the player expressed is only a
-- preference: it lives in a single client-writable slot that another remote can overwrite and that
-- expires, so it is used when it still applies and ignored otherwise.
--
-- Order: the intended item, then the first item of today's rotation, then the first item of the whole
-- catalogue. `nil` means the player owns every sellable item of that rarity and the caller must settle
-- the transaction another way rather than refuse it.

local ReceiptItem = {}

export type Item = { Id: string, Rarity: string, Sellable: boolean }

-- True when `item` is one this receipt may deliver: right rarity, sellable, not already owned.
function ReceiptItem.deliverable(item: Item?, rarity: string, owned: { string }): boolean
	if item == nil or item.Rarity ~= rarity or not item.Sellable then
		return false
	end
	for _, ownedId in ipairs(owned) do
		if ownedId == item.Id then
			return false
		end
	end
	return true
end

-- `catalogue` is every cosmetic, `rotation` the ids offered today (in display order), `owned` what the
-- player already has and `intended` the id they picked before opening the dialog, if any.
function ReceiptItem.pick(
	catalogue: { Item },
	rotation: { string },
	owned: { string },
	rarity: string,
	intended: string?
): string?
	local byId: { [string]: Item } = {}
	for _, item in ipairs(catalogue) do
		byId[item.Id] = item
	end
	if intended ~= nil and ReceiptItem.deliverable(byId[intended], rarity, owned) then
		return intended
	end
	for _, id in ipairs(rotation) do
		if ReceiptItem.deliverable(byId[id], rarity, owned) then
			return id
		end
	end
	for _, item in ipairs(catalogue) do
		if ReceiptItem.deliverable(item, rarity, owned) then
			return item.Id
		end
	end
	return nil
end

return ReceiptItem
