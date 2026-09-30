--!strict
-- In-server matchmaking queue with a rating window that widens while waiting.
-- Pure module: no requires, no Roblox globals. Deterministic given the same inputs.
--
-- A newcomer (E10-S7, Pure/RankedGate) is held to NewcomerMaxWindow for the first NewcomerSeconds of their wait:
-- their own window stops there, and nobody's wider window pairs them further -- every member of a match stands
-- within the cap of every newcomer in it. Past those seconds they are paired like anybody.

export type Entry = { UserId: number, Rating: number, JoinedAt: number, Newcomer: boolean? }
export type Queue = { Mode: string, Entries: { Entry }, ById: { [number]: Entry } }
export type Config = {
	BaseWindow: number,
	WindowGrowthPerSecond: number,
	MaxWindow: number,
	MaxQueueSeconds: number,
	NewcomerMaxWindow: number?,
	NewcomerSeconds: number?,
}
export type Match = { Teams: { { number } }, AverageRating: number }

local MatchmakingCore = {}

function MatchmakingCore.newQueue(mode: string): Queue
	return { Mode = mode, Entries = {}, ById = {} }
end

function MatchmakingCore.size(queue: Queue): number
	return #queue.Entries
end

function MatchmakingCore.contains(queue: Queue, userId: number): boolean
	return queue.ById[userId] ~= nil
end

-- Returns false if the player is already queued.
function MatchmakingCore.enqueue(queue: Queue, entry: Entry): boolean
	if queue.ById[entry.UserId] ~= nil then
		return false
	end
	local copy: Entry =
		{ UserId = entry.UserId, Rating = entry.Rating, JoinedAt = entry.JoinedAt, Newcomer = entry.Newcomer }
	table.insert(queue.Entries, copy)
	queue.ById[entry.UserId] = copy
	return true
end

function MatchmakingCore.dequeue(queue: Queue, userId: number): boolean
	local entry = queue.ById[userId]
	if entry == nil then
		return false
	end
	queue.ById[userId] = nil
	local index = table.find(queue.Entries, entry)
	if index ~= nil then
		table.remove(queue.Entries, index)
	end
	return true
end

-- The widest rating difference anybody may be paired with `entry` at: NewcomerMaxWindow while a newcomer is in
-- their first NewcomerSeconds, and no limit otherwise.
function MatchmakingCore.cap(entry: Entry, now: number, config: Config): number
	local limit, seconds = config.NewcomerMaxWindow, config.NewcomerSeconds
	if entry.Newcomer ~= true or limit == nil or seconds == nil or now - entry.JoinedAt >= seconds then
		return math.huge
	end
	return limit
end

-- Accepted rating difference for an entry that has waited since JoinedAt.
function MatchmakingCore.window(entry: Entry, now: number, config: Config): number
	local waited = math.max(0, now - entry.JoinedAt)
	local widened = math.min(config.MaxWindow, config.BaseWindow + waited * config.WindowGrowthPerSecond)
	return math.min(widened, MatchmakingCore.cap(entry, now, config))
end

-- Removes and returns the user ids that waited longer than MaxQueueSeconds.
function MatchmakingCore.expire(queue: Queue, now: number, config: Config): { number }
	local expired = {}
	for index = #queue.Entries, 1, -1 do
		local entry = queue.Entries[index]
		if now - entry.JoinedAt > config.MaxQueueSeconds then
			table.insert(expired, entry.UserId)
			queue.ById[entry.UserId] = nil
			table.remove(queue.Entries, index)
		end
	end
	table.sort(expired)
	return expired
end

-- Greedy balance: strongest players are dealt to the team with the lowest total that still has room.
function MatchmakingCore.balanceTeams(entries: { Entry }, teams: number, teamSize: number): { { number } }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		if a.Rating ~= b.Rating then
			return a.Rating > b.Rating
		end
		return a.UserId < b.UserId
	end)
	local result: { { number } } = {}
	local totals: { number } = {}
	for team = 1, teams do
		result[team] = {}
		totals[team] = 0
	end
	for _, entry in ipairs(sorted) do
		local best = 0
		for team = 1, teams do
			if #result[team] < teamSize and (best == 0 or totals[team] < totals[best]) then
				best = team
			end
		end
		if best == 0 then
			break
		end
		table.insert(result[best], entry.UserId)
		totals[best] += entry.Rating
	end
	return result
end

local function byWaitThenId(a: Entry, b: Entry): boolean
	if a.JoinedAt ~= b.JoinedAt then
		return a.JoinedAt < b.JoinedAt
	end
	return a.UserId < b.UserId
end

-- Whether `entry` may join `members`: every pair it would make stays within the cap of either side (a newcomer's).
local function fits(entry: Entry, members: { Entry }, now: number, config: Config): boolean
	local own = MatchmakingCore.cap(entry, now, config)
	for _, member in ipairs(members) do
		local limit = math.min(own, MatchmakingCore.cap(member, now, config))
		if math.abs(entry.Rating - member.Rating) > limit then
			return false
		end
	end
	return true
end

-- Forms as many matches as possible. The longest-waiting player anchors each match; candidates are
-- the entries within the wider of the two windows, closest ratings first, each taken only if it stands within
-- every newcomer's cap among those already taken. Matched entries are removed.
function MatchmakingCore.findMatches(
	queue: Queue,
	teamSize: number,
	teams: number,
	now: number,
	config: Config
): { Match }
	local needed = teamSize * teams
	local matches: { Match } = {}
	if needed < 2 then
		return matches
	end

	local waiting = table.clone(queue.Entries)
	table.sort(waiting, byWaitThenId)
	local taken: { [number]: boolean } = {}

	for _, anchor in ipairs(waiting) do
		if taken[anchor.UserId] then
			continue
		end
		local anchorWindow = MatchmakingCore.window(anchor, now, config)
		local candidates: { Entry } = {}
		for _, other in ipairs(waiting) do
			if other ~= anchor and not taken[other.UserId] then
				local allowed = math.max(anchorWindow, MatchmakingCore.window(other, now, config))
				if math.abs(other.Rating - anchor.Rating) <= allowed then
					table.insert(candidates, other)
				end
			end
		end
		if #candidates + 1 < needed then
			continue
		end
		table.sort(candidates, function(a, b)
			local da = math.abs(a.Rating - anchor.Rating)
			local db = math.abs(b.Rating - anchor.Rating)
			if da ~= db then
				return da < db
			end
			return byWaitThenId(a, b)
		end)
		local members: { Entry } = { anchor }
		for _, candidate in ipairs(candidates) do
			if #members == needed then
				break
			end
			if fits(candidate, members, now, config) then
				table.insert(members, candidate)
			end
		end
		if #members < needed then
			continue
		end
		local total = 0
		for _, member in ipairs(members) do
			taken[member.UserId] = true
			total += member.Rating
		end
		table.insert(matches, {
			Teams = MatchmakingCore.balanceTeams(members, teams, teamSize),
			AverageRating = total / needed,
		})
	end

	for userId in pairs(taken) do
		MatchmakingCore.dequeue(queue, userId)
	end
	return matches
end

return MatchmakingCore
