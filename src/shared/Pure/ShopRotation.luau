--!strict
-- Deterministic daily shop rotation. Pure module: no requires, no Roblox globals.

export type Item = { Id: string, Rarity: string, Sellable: boolean }

local ShopRotation = {}

local function hash(text: string): number
	local value = 2166136261
	for index = 1, #text do
		value = (bit32.bxor(value, string.byte(text, index)) * 16777619) % 4294967296
	end
	return value
end

local function nextRandom(state: number): number
	state = bit32.bxor(state, bit32.lshift(state, 13) % 4294967296)
	state = bit32.bxor(state, bit32.rshift(state, 17))
	state = bit32.bxor(state, bit32.lshift(state, 5) % 4294967296)
	return state
end

-- Picks `slots[rarity]` sellable items per rarity for `dayKey`, in `rarityOrder`. Same inputs → same output.
function ShopRotation.select(
	catalog: { Item },
	dayKey: string,
	slots: { [string]: number },
	rarityOrder: { string }
): { string }
	local selected: { string } = {}
	for _, rarity in ipairs(rarityOrder) do
		local count = slots[rarity] or 0
		local candidates = {}
		for _, item in ipairs(catalog) do
			if item.Sellable and item.Rarity == rarity then
				table.insert(candidates, item.Id)
			end
		end
		table.sort(candidates)
		local state = hash(dayKey .. ":" .. rarity)
		local picked = 0
		while picked < count and #candidates > 0 do
			state = nextRandom(state)
			local index = (state % #candidates) + 1
			table.insert(selected, candidates[index])
			table.remove(candidates, index)
			picked += 1
		end
	end
	return selected
end

function ShopRotation.dayKey(unixTime: number): string
	return "S" .. tostring(math.floor(unixTime / 86400))
end

return ShopRotation
