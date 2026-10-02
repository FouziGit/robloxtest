--!strict
-- A binding map as the Settings screen edits it (D-147): what a captured key does to it, what Reset does,
-- and whether a profile push is the map that was sent. Pure module: no requires, no Roblox globals. The
-- server still validates every map it is sent (SettingsService.validateKeybinds); the screen saves each
-- change as it is made, so these are the rules it saves by.

export type Map = { [string]: string }
export type Result = "Cancelled" | "NotAllowed" | "Same" | "Duplicate" | "Swapped" | "Bound"

local Rebind = {}

-- The map after `action` is given `key` (nil: the capture was cancelled), how it went, and the other
-- action involved. A key already bound elsewhere swaps with that action when it may move, and is refused
-- when it may not (the Menu key). The map given is never modified.
function Rebind.apply(
	map: Map,
	action: string,
	key: string?,
	allowed: { [string]: boolean },
	rebindable: { [string]: boolean }
): (Result, Map, string?)
	local updated = table.clone(map)
	if key == nil then
		return "Cancelled", updated, nil
	end
	if allowed[key] ~= true then
		return "NotAllowed", updated, nil
	end
	local previous = map[action]
	if previous == key then
		return "Same", updated, nil
	end
	local holder: string? = nil
	for other, bound in pairs(map) do
		if bound == key and other ~= action then
			holder = other
			break
		end
	end
	if holder ~= nil then
		if rebindable[holder] ~= true then
			return "Duplicate", updated, holder
		end
		updated[holder] = previous
		updated[action] = key
		return "Swapped", updated, holder
	end
	updated[action] = key
	return "Bound", updated, nil
end

-- Every action of `rebindable` back to its default; the others keep what they have.
function Rebind.reset(map: Map, defaults: Map, rebindable: { string }): Map
	local updated = table.clone(map)
	for _, action in ipairs(rebindable) do
		updated[action] = defaults[action]
	end
	return updated
end

-- Whether `a` and `b` bind each of `actions` to the same key: the push that confirms what was sent.
function Rebind.same(a: Map, b: Map, actions: { string }): boolean
	for _, action in ipairs(actions) do
		if a[action] ~= b[action] then
			return false
		end
	end
	return true
end

return Rebind
