--!strict
-- A cache that keeps at most `capacity` entries and, when full, lets go of the one read or written longest ago.
-- Pure module (no require, no Roblox global), tested under Lune (tests/Caches.spec.luau).
--
-- Reads and writes are O(1): the entries form a list from the most recently used to the least, and the table
-- finds an entry's place in it.

export type Node<K, V> = { Key: K, Value: V, Newer: Node<K, V>?, Older: Node<K, V>? }
export type Cache<K, V> = {
	Capacity: number,
	Size: number,
	Nodes: { [K]: Node<K, V> },
	Newest: Node<K, V>?,
	Oldest: Node<K, V>?,
}

local Lru = {}

function Lru.new<K, V>(capacity: number): Cache<K, V>
	assert(capacity >= 1 and capacity % 1 == 0, "an LRU cache holds at least one entry")
	return { Capacity = capacity, Size = 0, Nodes = {}, Newest = nil, Oldest = nil }
end

local function unlink<K, V>(cache: Cache<K, V>, node: Node<K, V>)
	local newer, older = node.Newer, node.Older
	if newer ~= nil then
		newer.Older = older
	else
		cache.Newest = older
	end
	if older ~= nil then
		older.Newer = newer
	else
		cache.Oldest = newer
	end
	node.Newer = nil
	node.Older = nil
end

local function pushNewest<K, V>(cache: Cache<K, V>, node: Node<K, V>)
	local newest = cache.Newest
	node.Older = newest
	node.Newer = nil
	if newest ~= nil then
		newest.Newer = node
	else
		cache.Oldest = node
	end
	cache.Newest = node
end

-- The value under `key`, or nil; a hit becomes the most recently used entry.
function Lru.get<K, V>(cache: Cache<K, V>, key: K): V?
	local node = cache.Nodes[key]
	if node == nil then
		return nil
	end
	if cache.Newest ~= node then
		unlink(cache, node)
		pushNewest(cache, node)
	end
	return node.Value
end

-- Writes `value` under `key` as the most recently used entry, letting go of the least recently used one when the
-- cache is full.
function Lru.set<K, V>(cache: Cache<K, V>, key: K, value: V)
	local node = cache.Nodes[key]
	if node ~= nil then
		node.Value = value
		if cache.Newest ~= node then
			unlink(cache, node)
			pushNewest(cache, node)
		end
		return
	end
	if cache.Size >= cache.Capacity then
		local oldest = cache.Oldest
		if oldest ~= nil then
			unlink(cache, oldest)
			cache.Nodes[oldest.Key] = nil
			cache.Size -= 1
		end
	end
	local fresh: Node<K, V> = { Key = key, Value = value, Newer = nil, Older = nil }
	cache.Nodes[key] = fresh
	cache.Size += 1
	pushNewest(cache, fresh)
end

return Lru
