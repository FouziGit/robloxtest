--!strict
-- What RankingService remembers of a ranked roster while its match can still be scored, and nothing past it
-- (E9-S7, D-222). Pure module (no require, no Roblox global), tested under Lune (tests/Caches.spec.luau).
--
-- Two memories, both about players who may already have left:
--  * the last rating seen for a user id, per mode: a participant who disconnected has no profile any more, and the
--    opposing team must still be scored against the rating they actually had;
--  * the match whose forfeit was already debited for a user id (applyAbandon), so the result of that match skips
--    them and no second debit can ever land.
-- Both used to grow for the life of the server, one entry per ranked player it ever saw. They now hold only users
-- a live match holds: `hold` when a match starts, `release` when it ends however it ends, and a user no live match
-- holds any more is forgotten.

export type Memory = {
	Ratings: { [string]: { [number]: number } }, -- mode id -> user id -> last rating seen
	Settled: { [number]: string }, -- user id -> match whose forfeit is already debited
	Holders: { [number]: { [string]: true } }, -- user id -> the live matches holding them
}

local RatingMemory = {}

function RatingMemory.new(): Memory
	return { Ratings = {}, Settled = {}, Holders = {} }
end

-- `matchId` holds `userId` until it is released.
function RatingMemory.hold(memory: Memory, matchId: string, userId: number)
	local matches = memory.Holders[userId]
	if matches == nil then
		matches = {}
		memory.Holders[userId] = matches
	end
	matches[matchId] = true
end

-- `matchId` is over: whoever it held and no other live match holds is forgotten, and a forfeit debited for it that
-- no result will now come to consume goes with them.
function RatingMemory.release(memory: Memory, matchId: string)
	for userId, matches in pairs(memory.Holders) do
		if matches[matchId] then
			matches[matchId] = nil
			if memory.Settled[userId] == matchId then
				memory.Settled[userId] = nil
			end
			if next(matches) == nil then
				memory.Holders[userId] = nil
				for _, byUser in pairs(memory.Ratings) do
					byUser[userId] = nil
				end
			end
		end
	end
end

-- Remembers `rating` as the last one seen for `userId` in `modeId`, if a live match holds them.
function RatingMemory.remember(memory: Memory, modeId: string, userId: number, rating: number)
	if memory.Holders[userId] == nil then
		return
	end
	local byUser = memory.Ratings[modeId]
	if byUser == nil then
		byUser = {}
		memory.Ratings[modeId] = byUser
	end
	byUser[userId] = rating
end

-- The last rating seen for `userId` in `modeId`, or nil.
function RatingMemory.known(memory: Memory, modeId: string, userId: number): number?
	local byUser = memory.Ratings[modeId]
	return if byUser ~= nil then byUser[userId] else nil
end

-- The forfeit of `matchId` is debited for `userId`, if a live match holds them.
function RatingMemory.settle(memory: Memory, userId: number, matchId: string)
	if memory.Holders[userId] ~= nil then
		memory.Settled[userId] = matchId
	end
end

function RatingMemory.isSettled(memory: Memory, userId: number, matchId: string): boolean
	return memory.Settled[userId] == matchId
end

-- True, once, when the forfeit of `matchId` was already debited for `userId`: its result must skip them.
function RatingMemory.consume(memory: Memory, userId: number, matchId: string): boolean
	if memory.Settled[userId] ~= matchId then
		return false
	end
	memory.Settled[userId] = nil
	return true
end

return RatingMemory
