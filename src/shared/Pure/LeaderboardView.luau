--!strict
-- What the leaderboard screen draws of a board (D-147): the first three on the podium, second on the left,
-- first in the centre, third on the right; the rest as rows; where the local player stands in it; and the
-- tier of the illuminated rank ladder each row's seal wears. Pure module: no requires, no Roblox globals.
--
-- A row's tier is read from the rank key the server wrote on it, not recomputed from its number: a mode
-- board stores a rating, but the Global board stores the gains above the starting rating, and only the
-- server's key says which tier that is (LeaderboardService.boardRankKey).

export type Entry = { Rank: number, UserId: number, Name: string, Rating: number, RankKey: string }
export type Tier = { Id: string, NameKey: string, Min: number }

local LeaderboardView = {}

-- The podium holds this many, and shows them left to right in this order of their places.
LeaderboardView.PodiumSize = 3
LeaderboardView.PodiumOrder = { 2, 1, 3 }

local function finite(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.floor(value)
end

-- The entries of a board as the server sent them. Rows are server-authored, but a truncated entry is dropped
-- rather than rendered half empty, and a number that is not one is read as its floor.
function LeaderboardView.read(payload: any): { Entry }
	local entries: { Entry } = {}
	if type(payload) ~= "table" then
		return entries
	end
	for _, raw in ipairs(payload) do
		if type(raw) == "table" and type(raw.Name) == "string" then
			table.insert(entries, {
				Rank = math.max(1, finite(raw.Rank, #entries + 1)),
				UserId = math.max(0, finite(raw.UserId, 0)),
				Name = raw.Name,
				Rating = math.max(0, finite(raw.Rating, 0)),
				RankKey = if type(raw.RankKey) == "string" then raw.RankKey else "",
			})
		end
	end
	return entries
end

-- The podium (the first PodiumSize entries, in place order), the rows under it, and the index of the
-- player `userId` in the whole board, or nil when they are not listed.
function LeaderboardView.split(entries: { Entry }, userId: number): ({ Entry }, { Entry }, number?)
	local podium: { Entry } = {}
	local rows: { Entry } = {}
	local own: number? = nil
	for index, entry in ipairs(entries) do
		if index <= LeaderboardView.PodiumSize then
			table.insert(podium, entry)
		else
			table.insert(rows, entry)
		end
		if own == nil and entry.UserId == userId then
			own = index
		end
	end
	return podium, rows, own
end

-- The id of the tier whose name is `rankKey`, or nil for a key no tier has.
function LeaderboardView.tierId(rankKey: string, tiers: { Tier }): string?
	for _, tier in ipairs(tiers) do
		if tier.NameKey == rankKey then
			return tier.Id
		end
	end
	return nil
end

return LeaderboardView
