--!strict
-- AuraMath: the arithmetic of what a body wears (D-148) -- how many particles an aura or a trail owes this
-- frame, how dense it may be on this screen, what colour each particle is over its life, and where each one
-- is born or each stroke runs round the body. CosmeticController draws with it and tests/Cosmetics.spec.luau
-- measures with it, so the colours, the budget and the dimming the tests hold are the ones on screen.
--
-- Pure: no Roblox global, no require, tested under Lune. Points are returned as numbers in the wearer's root
-- space: +Y up, +Z behind the body (a root looks down -Z).

local AuraMath = {}

export type Rgb = { number }

-- A driven flow: particles a second, and the share of one owed and not yet emitted.
export type Flow = { Rate: number, Carry: number }

-- The part of a CosmeticConfig.Place this module reads (the config's own type, restated: a pure module may
-- not require the config that describes it).
export type Place = {
	Kind: string,
	Radius: number?,
	Low: number?,
	High: number?,
	Lift: number?,
	Height: number?,
	Seconds: number?,
	Bob: number?,
	Depth: number?,
	Gap: number?,
}

-- What a colour ramp reads off an emission or a ribbon.
export type Ramp = { Dries: number?, Glint: number?, Flickers: number?, Heat: number? }

export type Stop = { Time: number, Rgb: Rgb }

local WHITE: Rgb = { 255, 255, 255 }

-- The shape of the two moving paths. An orbit rises and falls 1.7 times a turn, so its two strokes never
-- trace the same ellipse twice running; a scrawl swells and shrinks three times a turn and climbs 2.3 times,
-- the loops of a pen that never lifts.
local ORBIT_BOB_PER_TURN = 1.7
local SCRAWL_SWELL = 0.35
local SCRAWL_SWELLS_PER_TURN = 3
local SCRAWL_BOB_PER_TURN = 2.3

local function lerp(a: Rgb, b: Rgb, t: number): Rgb
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

-- How many particles `flow` owes after `dt` seconds, carrying the fraction to the next frame. A frame longer
-- than `maxStep` (a hitch, a tab brought back) owes only `maxStep`: a hitch must not come back as a burst.
function AuraMath.owed(flow: Flow, dt: number, maxStep: number): number
	local step = math.clamp(dt, 0, maxStep)
	flow.Carry += step * flow.Rate
	local count = math.floor(flow.Carry)
	flow.Carry -= count
	return count
end

-- The share of a flow this screen draws: the tier's particle scale, nothing of somebody else's on the floor
-- tier (rule 8), and the quieter share while the local player fights.
function AuraMath.density(
	particleScale: number,
	isLocal: boolean,
	floorTier: boolean,
	fighting: boolean,
	fightDensity: number
): number
	if floorTier and not isLocal then
		return 0
	end
	return particleScale * (if fighting then fightDensity else 1)
end

-- A transparency curve made fainter by `shift`, each point held under fully transparent.
function AuraMath.lifted(values: { number }, shift: number): { number }
	local out = table.create(#values)
	for index, value in ipairs(values) do
		out[index] = math.min(value + shift, 1)
	end
	return out
end

-- How much of its colour an emission adds as light: only its declared Glow, and never more than a fight
-- allows.
function AuraMath.glow(glow: number?, fighting: boolean, fightGlow: number): number
	local own = glow or 0
	return if fighting then math.min(own, fightGlow) else own
end

-- How many particles an emission keeps alive at once at the High tier: its rate times its longest life.
function AuraMath.live(emission: { Rate: number, Lifetime: { number } }): number
	return emission.Rate * emission.Lifetime[2]
end

-- The colour of a particle over its life, or of a ribbon along its length, as stops from 0 to 1.
--   * Heat: born pushed that share toward white, cooled into its tone by `hold` of its life (a core);
--   * Dries: held in its tone for `hold` of its life, then that share of the way to ink by its end (soot,
--     iron-gall, wet ink drying);
--   * Glint: flickers that share toward white `Flickers` times over its life (gold leaf, graphite).
function AuraMath.colors(rgb: Rgb, ramp: Ramp, ink: Rgb, hold: number): { Stop }
	local dries = ramp.Dries or 0
	local function base(t: number): Rgb
		if t <= hold or dries <= 0 then
			return rgb
		end
		return lerp(rgb, ink, dries * (t - hold) / (1 - hold))
	end
	local glint = ramp.Glint
	if glint ~= nil and glint > 0 then
		local steps = 2 * (ramp.Flickers or 1)
		local stops: { Stop } = {}
		for k = 0, steps do
			local t = k / steps
			local colour = base(t)
			table.insert(stops, { Time = t, Rgb = if k % 2 == 1 then lerp(colour, WHITE, glint) else colour })
		end
		return stops
	end
	local born = if (ramp.Heat or 0) > 0 then lerp(rgb, WHITE, ramp.Heat :: number) else rgb
	return { { Time = 0, Rgb = born }, { Time = hold, Rgb = rgb }, { Time = 1, Rgb = base(1) } }
end

-- Where stroke `stroke` of `count` is on a moving path at `now`. The strokes share the path, spaced evenly
-- round one turn of it:
--   * Orbit: a circle of Radius at Height, rising and falling by Bob, once every Seconds;
--   * Scrawl: the same circle swelling and shrinking, climbing by Bob, a loop that never closes;
--   * Behind: a point Depth behind the body at Height, each further stroke Gap lower, rising and falling by
--     Bob every Seconds when Seconds is given (a line scribbled as the body runs), still otherwise.
function AuraMath.path(place: Place, stroke: number, count: number, now: number): (number, number, number)
	local seconds = place.Seconds or 1
	local turn = 2 * math.pi * (now / seconds + (stroke - 1) / math.max(count, 1))
	local height = place.Height or 0
	local bob = place.Bob or 0
	if place.Kind == "Behind" then
		local wobble = if place.Seconds ~= nil then bob * math.sin(turn) else 0
		return 0, height - (stroke - 1) * (place.Gap or 0) + wobble, place.Depth or 0
	end
	local radius = place.Radius or 0
	if place.Kind == "Scrawl" then
		radius *= 1 + SCRAWL_SWELL * math.sin(SCRAWL_SWELLS_PER_TURN * turn)
		return radius * math.cos(turn), height + bob * math.sin(SCRAWL_BOB_PER_TURN * turn), radius * math.sin(turn)
	end
	return radius * math.cos(turn), height + bob * math.sin(ORBIT_BOB_PER_TURN * turn), radius * math.sin(turn)
end

-- Where one particle of an emission is born, from two uniform draws `u` and `v` in [0, 1), `side` (+1 or -1)
-- choosing a hand, and `floor` the height of the ground under the root (negative):
--   * Ring: anywhere on a cylinder of Radius round the body, between Low and High -- outside the body, which
--     would hide a particle born inside it for most of its life (D-109);
--   * Feet: anywhere on a disc of Radius at the floor, Lift above it;
--   * Floor: the floor under the body, Lift above it;
--   * Hands: beside the body at Radius, Height and Depth, on the `side` hand;
--   * Behind: Depth behind the body, anywhere between Low and High;
--   * Orbit, Scrawl: where the path is at `now`.
function AuraMath.point(
	place: Place,
	floor: number,
	now: number,
	u: number,
	v: number,
	side: number
): (number, number, number)
	local kind = place.Kind
	local radius = place.Radius or 0
	if kind == "Ring" then
		local angle = 2 * math.pi * u
		local low = place.Low or 0
		return radius * math.cos(angle), low + ((place.High or low) - low) * v, radius * math.sin(angle)
	elseif kind == "Feet" then
		local angle = 2 * math.pi * u
		local reach = radius * math.sqrt(v)
		return reach * math.cos(angle), floor + (place.Lift or 0), reach * math.sin(angle)
	elseif kind == "Floor" then
		return 0, floor + (place.Lift or 0), 0
	elseif kind == "Hands" then
		return side * radius, place.Height or 0, place.Depth or 0
	elseif kind == "Behind" then
		local low = place.Low or 0
		return 0, low + ((place.High or low) - low) * v, place.Depth or 0
	end
	return AuraMath.path(place, 1, 1, now)
end

return AuraMath
