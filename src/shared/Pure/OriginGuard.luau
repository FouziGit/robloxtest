--!strict
-- Decides whether a character could plausibly be where its owning client says it is. Pure: no Roblox
-- global, no require, so it is unit-tested under Lune (tests/OriginGuard.spec.luau).
--
-- Roblox simulates a player's character on the owning client, so the replicated position is whatever that
-- client last sent. The server keeps the last position it was willing to believe, its timestamp, and any
-- travel a server-authored burst (a dash, a knockback) still entitles the character to; this module turns
-- the horizontal distance from that anchor into one of four verdicts. CombatService does the Roblox parts:
-- reading the root, measuring the distance, and acting on the verdict.
--
-- Only horizontal distance is judged. Vertical speed is gravity-driven and unbounded, while the exploit
-- being bounded is repositioning onto a target.

local OriginGuard = {}

export type Config = {
	-- Ceiling on UNASSISTED horizontal speed. Server-granted bursts are not measured against it: they add
	-- their own distance through `allowance`.
	MaxSpeedStudsPerSecond: number,
	-- Extra distance an ACTION may be resolved from, to absorb the client round trip. Never banked.
	OriginToleranceStuds: number,
	-- Cap on how much elapsed time the budget may accumulate.
	MaxBudgetSeconds: number,
	-- Below this, a sample carries no movement at all.
	StillEpsilonStuds: number,
}

-- "Still"      nothing moved: no anchor to update, and the clock must NOT be refreshed, or a stall would
--              hold the budget at one sample and then refuse the burst that catches up.
-- "Accepted"   plausible: the anchor follows, and the allowance is reduced by the part that needed it.
-- "Tolerated"  beyond plausible but inside the round-trip tolerance: the action is resolved where the
--              client says it is, and the anchor does NOT move, so the tolerance is worth one action
--              rather than a fresh helping every sample.
-- "Refused"    beyond that: resolve the action from the anchor instead, and count a violation.
export type Verdict = "Still" | "Accepted" | "Tolerated" | "Refused"

-- Returns the verdict and the allowance left afterwards. `travelled` is the horizontal distance from the
-- anchor, `elapsed` the seconds since the anchor was set, `allowance` the unspent server-granted studs.
function OriginGuard.judge(travelled: number, elapsed: number, allowance: number, config: Config): (Verdict, number)
	local unspent = math.max(0, allowance)
	if travelled ~= travelled or travelled <= config.StillEpsilonStuds then
		-- NaN counts as still: a broken sample must not move the anchor.
		return "Still", unspent
	end
	local window = math.clamp(elapsed, 0, config.MaxBudgetSeconds)
	local bySpeed = config.MaxSpeedStudsPerSecond * window
	local budget = bySpeed + unspent
	if travelled <= budget then
		local spent = math.max(0, travelled - bySpeed)
		return "Accepted", math.max(0, unspent - spent)
	end
	if travelled <= budget + config.OriginToleranceStuds then
		return "Tolerated", unspent
	end
	return "Refused", unspent
end

-- Studs the character is entitled to right now: the speed ceiling over the capped window, plus whatever
-- server-granted travel is unspent. Reported in the strike message so a log line can be read back.
function OriginGuard.budget(elapsed: number, allowance: number, config: Config): number
	local window = math.clamp(elapsed, 0, config.MaxBudgetSeconds)
	return config.MaxSpeedStudsPerSecond * window + math.max(0, allowance)
end

-- Below this much horizontal length, a look vector says nothing about which way a body faces.
local FLAT_LOOK_MIN = 0.2

-- The horizontal way a body faces, from its root's look vector and the horizontal part of its up vector,
-- as a unit (x, z). The look flattened -- for a standing body, which a Humanoid keeps upright, that is the look itself. A body lying
-- down looks at the sky or the floor: then its facing is where its head points (face down) or its feet
-- point (face up), which is what the look turns into as it tips. The server aims every swing and every
-- glyph with it: aimed with the tilted root, a player getting up swung into the ground (D-113, measured).
function OriginGuard.facing(lookX: number, lookY: number, lookZ: number, upX: number, upZ: number): (number, number)
	local x, z = lookX, lookZ
	local length = math.sqrt(x * x + z * z)
	if length < FLAT_LOOK_MIN then
		local sign = if lookY > 0 then -1 else 1
		x, z = upX * sign, upZ * sign
		length = math.sqrt(x * x + z * z)
	end
	if length < 1e-6 then
		return 0, -1
	end
	return x / length, z / length
end

return OriginGuard
