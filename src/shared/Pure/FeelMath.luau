--!strict
-- The arithmetic behind the game feel, separated from the engine so it can be tested rather than
-- trusted. Pure: no require, no Roblox global. Every function takes its numbers from FeelConfig as an
-- argument instead of requiring it, which is what keeps the purity rule and lets a test drive each
-- curve with its own fixtures.

local FeelMath = {}

export type HitStopConfig = {
	MinSeconds: number,
	MaxSeconds: number,
	MinDamage: number,
	MaxDamage: number,
}

local function clamp01(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

FeelMath.clamp01 = clamp01

-- Where `damage` sits between the lightest and heaviest hit in the game, as 0 to 1. Everything else
-- that scales with impact reads this rather than the raw number, so one edit to FeelConfig moves the
-- hit-stop, the shake and the damage number together.
function FeelMath.severity(damage: number, config: HitStopConfig): number
	local span = config.MaxDamage - config.MinDamage
	if span <= 0 then
		return 1
	end
	return clamp01((damage - config.MinDamage) / span)
end

-- How long the world stops for a hit of `damage`. Monotonic and clamped to the configured window at
-- both ends, so a 1-damage tick still registers and a 500-damage boss slam still hands control back.
function FeelMath.hitStopSeconds(damage: number, config: HitStopConfig): number
	local t = FeelMath.severity(damage, config)
	return config.MinSeconds + (config.MaxSeconds - config.MinSeconds) * t
end

-- Two hit-stops overlapping resolve to the longer one, never to their sum. Three quick hits adding up
-- to 270 ms read as a freeze and a dropped input, not as impact.
function FeelMath.mergeHitStop(remaining: number, incoming: number): number
	return math.max(remaining, incoming)
end

-- How much of an effect survives `distance` studs away. 1 at the impact, 0 at the radius and beyond,
-- squared in between so the drop is gentle where the player is looking and steep out at the edge.
function FeelMath.falloff(distance: number, radiusStuds: number): number
	if radiusStuds <= 0 then
		return 0
	end
	local near = 1 - clamp01(distance / radiusStuds)
	return near * near
end

-- Speed along an impulse (knockback, dash) at `alpha` of its duration, as a multiple of the flat speed
-- the caller would otherwise have used.
--
-- The curve starts fast and decays, which is how a body that was struck actually moves. The (1 + e)
-- factor is not decoration: the integral of (1 + e) * (1 - a)^e over a from 0 to 1 is exactly 1, so the
-- total distance travelled is identical to holding the flat speed for the whole duration. Without it,
-- making knockback feel better would quietly change how far it throws people, and that is balance.
function FeelMath.impulseSpeed(alpha: number, exponent: number): number
	local a = clamp01(alpha)
	local e = math.max(exponent, 0)
	return (1 + e) * (1 - a) ^ e
end

-- Linear interpolation, clamped: used wherever a value has to stay inside its two ends whatever the
-- caller passes.
function FeelMath.lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * clamp01(alpha)
end

-- Opacity of a floating number at `alpha` of its life: fully opaque while it is being read, then out.
-- Fading from the first frame is why most damage numbers look weak.
function FeelMath.holdThenFade(alpha: number, holdFraction: number): number
	local a = clamp01(alpha)
	local hold = clamp01(holdFraction)
	if a <= hold then
		return 1
	end
	if hold >= 1 then
		return 1
	end
	return 1 - (a - hold) / (1 - hold)
end

-- How far a drawn effect has faded at `elapsed` of its life (0 to 1), given how far its own ease has
-- carried it (`shaped`). Ink dries: it lands dark, stays, and goes at the end -- a quarter sine, slow
-- then fast. A layer's ease is how fast it spreads, and it used to be how fast it faded too: a Wash stain
-- that spreads in a flash (Exponential Out) and is authored to last 2.4 s was 73 % transparent a third of
-- a second in, measured in a live client. A fade therefore never runs ahead of drying; a layer whose
-- author asked for an even slower one keeps it.
function FeelMath.inkFade(elapsed: number, shaped: number): number
	local drying = 1 - math.cos(clamp01(elapsed) * math.pi / 2)
	return math.min(clamp01(shaped), drying)
end

-- How far a drawn layer's transparency has travelled from `from` toward `to`. A layer that fades OUT
-- follows inkFade. One that darkens -- a warning gathering -- keeps its own ease (`shaped`), because its
-- author chose that curve to say when the danger arrives; so does one whose author tied the fade to its
-- size (`withSize`), a print that lightens as it spreads.
function FeelMath.layerFade(from: number, to: number, elapsed: number, shaped: number, withSize: boolean): number
	if withSize or to <= from then
		return shaped
	end
	return FeelMath.inkFade(elapsed, shaped)
end

return FeelMath
