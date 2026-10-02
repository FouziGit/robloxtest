--!strict
-- FlyleafRules: what the Flyleaf decides (E16-S2) -- where a member lands, what a kill pays, who wears the
-- Manicule. Pure module: no require, no Roblox global, tested under Lune (tests/Flyleaf.spec.luau).

export type Point = { X: number, Z: number }
-- The deaths each victim took from each killer, as the times they happened: killer id -> victim id -> times.
export type Ledger = { [number]: { [number]: { number } } }
export type FarmRules = { MaxPaidDeaths: number, WindowSeconds: number }

local FlyleafRules = {}

-- Two squared distances this close are the same distance.
local TIE_STUDS2 = 1e-6

-- The seal a member lands on: the one whose nearest other member is furthest away, so nobody arrives in someone's
-- reach. With nobody else on the page, the seals are taken in turn from `turn` (1-based, wrapped), so two members
-- who arrive together never share one. Ties -- within TIE_STUDS2, what the arithmetic of equal distances leaves --
-- go to the lowest index.
function FlyleafRules.farthestSeal(seals: { Point }, others: { Point }, turn: number): number
	if #others == 0 then
		return (turn - 1) % #seals + 1
	end
	local best, bestDistance = 1, -math.huge
	for index, seal in ipairs(seals) do
		local nearest = math.huge
		for _, other in ipairs(others) do
			local dx, dz = seal.X - other.X, seal.Z - other.Z
			nearest = math.min(nearest, dx * dx + dz * dz)
		end
		if nearest > bestDistance + TIE_STUDS2 then
			best, bestDistance = index, nearest
		end
	end
	return best
end

-- Records a kill of `victimId` by `killerId` at `now` and says whether it pays: not when the victim had already
-- died to this killer MaxPaidDeaths times in the last WindowSeconds. Every death is recorded, paid or not, and what
-- has left the window is forgotten, so a pair that stops for WindowSeconds starts again from nothing.
function FlyleafRules.recordKill(
	ledger: Ledger,
	killerId: number,
	victimId: number,
	now: number,
	rules: FarmRules
): boolean
	local byVictim = ledger[killerId]
	if byVictim == nil then
		byVictim = {}
		ledger[killerId] = byVictim
	end
	local kept: { number } = {}
	for _, at in ipairs(byVictim[victimId] or {}) do
		if now - at < rules.WindowSeconds then
			table.insert(kept, at)
		end
	end
	local pays = #kept < rules.MaxPaidDeaths
	table.insert(kept, now)
	byVictim[victimId] = kept
	return pays
end

-- Forgets every pair whose latest death is older than WindowSeconds: what the ledger keeps stays bounded by the kills
-- of the last window. A player who leaves is not forgotten sooner, so leaving and rejoining the server resets nothing.
function FlyleafRules.prune(ledger: Ledger, now: number, rules: FarmRules)
	for killerId, byVictim in pairs(ledger) do
		for victimId, times in pairs(byVictim) do
			local latest = times[#times]
			if latest == nil or now - latest >= rules.WindowSeconds then
				byVictim[victimId] = nil
			end
		end
		if next(byVictim) == nil then
			ledger[killerId] = nil
		end
	end
end

-- Whether a member on a run of `streak` lives taken without losing theirs wears the Manicule.
function FlyleafRules.wearsManicule(streak: number, threshold: number): boolean
	return streak >= threshold
end

return FlyleafRules
