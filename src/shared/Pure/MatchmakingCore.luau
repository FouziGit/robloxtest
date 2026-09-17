--!strict
-- In-server matchmaking queue with a rating window that widens while waiting.
-- Pure module: no requires, no Roblox globals. Deterministic given the same inputs.

export type Entry = { UserId: number, Rating: number, JoinedAt: number }
export type Queue = { Mode: string, Entries: { Entry }, ById: { [number]: Entry } }
export type Config = { BaseWindow: number, WindowGrowthPerSecond: number, MaxWindow: number, MaxQueueSeconds: number }
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
	local copy: Entry = { UserId = entry.UserId, Rating = entry.Rating, JoinedAt = entry.JoinedAt }
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

-- Accepted rating difference for an entry that has waited since JoinedAt.
function MatchmakingCore.window(entry: Entry, now: number, config: Config): number
	local waited = math.max(0, now - entry.JoinedAt)
	return math.min(config.MaxWindow, config.BaseWindow + waited * config.WindowGrowthPerSecond)
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

-- Forms as many matches as possible. The longest-waiting player anchors each match; candidates are
-- the entries within the wider of the two windows, closest ratings first. Matched entries are removed.
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
		for index = 1, needed - 1 do
			table.insert(members, candidates[index])
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
