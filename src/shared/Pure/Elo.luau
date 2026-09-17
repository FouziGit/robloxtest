--!strict
-- Elo rating with a decreasing K-factor. Pure module: no requires, no Roblox globals.

export type KSchedule = { { MaxMatches: number?, K: number } }
export type Bounds = { Floor: number, Ceiling: number }

local Elo = {}

-- Expected score of `rating` against `opponent` (0..1).
function Elo.expected(rating: number, opponent: number): number
	return 1 / (1 + 10 ^ ((opponent - rating) / 400))
end

-- K for a player who has played `matches` ranked games.
function Elo.kFactor(matches: number, schedule: KSchedule): number
	for _, entry in ipairs(schedule) do
		if entry.MaxMatches == nil or matches < entry.MaxMatches then
			return entry.K
		end
	end
	return schedule[#schedule].K
end

local function clamp(value: number, bounds: Bounds): number
	return math.max(bounds.Floor, math.min(bounds.Ceiling, value))
end

-- Updates two ratings. `scoreA` is 1 (A won), 0.5 (draw) or 0 (B won).
-- Returns (newA, newB, deltaA, deltaB); deltas are integers so ratings stay integers.
function Elo.update(
	ratingA: number,
	ratingB: number,
	scoreA: number,
	kA: number,
	kB: number,
	bounds: Bounds
): (number, number, number, number)
	local expectedA = Elo.expected(ratingA, ratingB)
	local expectedB = 1 - expectedA
	local scoreB = 1 - scoreA
	local deltaA = math.floor(kA * (scoreA - expectedA) + 0.5)
	local deltaB = math.floor(kB * (scoreB - expectedB) + 0.5)
	local newA = clamp(ratingA + deltaA, bounds)
	local newB = clamp(ratingB + deltaB, bounds)
	return newA, newB, newA - ratingA, newB - ratingB
end

-- Team rating = mean of member ratings.
function Elo.teamRating(ratings: { number }): number
	if #ratings == 0 then
		return 0
	end
	local total = 0
	for _, rating in ipairs(ratings) do
		total += rating
	end
	return total / #ratings
end

return Elo
