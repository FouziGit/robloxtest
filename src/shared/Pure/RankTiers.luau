--!strict
-- Rank tiers from a rating. Pure module: no requires, no Roblox globals.

export type Tier = { Id: string, NameKey: string, Min: number }

local RankTiers = {}

-- Highest tier whose Min <= rating (tiers must be sorted by ascending Min).
function RankTiers.tierFor(rating: number, tiers: { Tier }): Tier
	local current = tiers[1]
	for _, tier in ipairs(tiers) do
		if rating >= tier.Min then
			current = tier
		else
			break
		end
	end
	return current
end

-- The next tier above `rating`, or nil at the top.
function RankTiers.nextTier(rating: number, tiers: { Tier }): Tier?
	for _, tier in ipairs(tiers) do
		if rating < tier.Min then
			return tier
		end
	end
	return nil
end

-- Progress (0..1) from the current tier's Min to the next tier's Min; 1 at the top tier.
function RankTiers.progress(rating: number, tiers: { Tier }): number
	local current = RankTiers.tierFor(rating, tiers)
	local next = RankTiers.nextTier(rating, tiers)
	if next == nil then
		return 1
	end
	local span = next.Min - current.Min
	if span <= 0 then
		return 1
	end
	return math.clamp((rating - current.Min) / span, 0, 1)
end

-- Validates the tier list shape (ascending, unique ids). Returns (ok, reason?).
function RankTiers.validate(tiers: { Tier }): (boolean, string?)
	if #tiers == 0 then
		return false, "no tiers"
	end
	local seen: { [string]: boolean } = {}
	local previous = -math.huge
	for index, tier in ipairs(tiers) do
		if seen[tier.Id] then
			return false, "duplicate tier " .. tier.Id
		end
		seen[tier.Id] = true
		if tier.Min <= previous then
			return false, "tier " .. tostring(index) .. " is not ascending"
		end
		previous = tier.Min
	end
	if tiers[1].Min ~= 0 then
		return false, "first tier must start at 0"
	end
	return true, nil
end

return RankTiers
