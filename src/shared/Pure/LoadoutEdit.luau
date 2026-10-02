--!strict
-- The loadout as the loadout screen edits it (D-147): what a tap on a glyph does to the list, what each
-- socket of the bar holds, and which of its four faces a glyph card shows. Pure module: no requires, no
-- Roblox globals. The server still validates every list it is sent (LoadoutService); this is what the
-- screen proposes and draws in the meantime.

export type Outcome = "Equipped" | "Unequipped" | "Full"
export type SocketKind = "Filled" | "Empty" | "Locked"
export type Socket = { Kind: SocketKind, Id: string? }
export type CardState = "Available" | "Equipped" | "Full" | "Locked"

local LoadoutEdit = {}

-- The list after a tap on `id`: an equipped glyph comes off, any other goes on at the end while a slot of
-- the `limit` is free. A full loadout is returned unchanged, as a copy. The list given is never modified.
function LoadoutEdit.toggle(slots: { string }, id: string, limit: number): ({ string }, Outcome)
	local updated: { string } = {}
	local removed = false
	for _, slot in ipairs(slots) do
		if slot == id then
			removed = true
		else
			table.insert(updated, slot)
		end
	end
	if removed then
		return updated, "Unequipped"
	end
	if #updated >= limit then
		return updated, "Full"
	end
	table.insert(updated, id)
	return updated, "Equipped"
end

-- The socket bar: `shown` sockets at least, or as many as the player may fill when that is more (an
-- account that holds the whole roster). The equipped glyphs fill the first ones in their order, the
-- rest of the budget is empty, and what lies past the budget is locked: what the pass would open.
function LoadoutEdit.sockets(slots: { string }, limit: number, shown: number): { Socket }
	local sockets: { Socket } = {}
	for index = 1, math.max(shown, limit) do
		if index > limit then
			table.insert(sockets, { Kind = "Locked" })
		elseif slots[index] ~= nil then
			table.insert(sockets, { Kind = "Filled", Id = slots[index] })
		else
			table.insert(sockets, { Kind = "Empty" })
		end
	end
	return sockets
end

-- The face of a glyph's card: locked before anything else (a locked glyph cannot be equipped, whatever
-- the list says), then equipped, then full when every slot is taken, and otherwise free to equip.
function LoadoutEdit.cardState(unlocked: boolean, equipped: boolean, full: boolean): CardState
	if not unlocked then
		return "Locked"
	elseif equipped then
		return "Equipped"
	elseif full then
		return "Full"
	end
	return "Available"
end

return LoadoutEdit
