--!strict
-- ParticleBudget: how many particles a client has alive, and how many more it may ask for (art bible rule 8: the
-- density of particles is capped, and falls with the graphics setting). Each quality tier has a budget of live
-- particles (QualityConfig, Particles); every emitter asks before it emits, and gets what fits.
--
-- A ledger counts the particles asked for and forgets them when the last of them can have died: each batch is
-- counted for the longest life its emitter gives (the top of its Lifetime), rounded up to the ledger's step, so
-- the count is never under what is really alive. It is swept on demand, not per particle: a batch is one entry
-- per step of death, so a flow that emits a particle every frame costs a handful of entries, never one each.
--
-- Three ways to ask, one per kind of emitter the renderers have (VfxTimeline, CosmeticController, VfxLibrary):
--   grant    a burst, or a frame's worth of a flow the renderer emits itself: whole particles, at most what was
--            asked and what is left;
--   rate     an emitter the engine runs at a Rate for a while: the highest rate whose particles alive at once
--            (held: the rate times their longest life, and one) fit what is left -- the renderer then reserves
--            that many for as long as the emitter can have any alive;
--   room     what is left; wornRoom, what is left for what bodies wear, which never takes more than its share.
--
-- Pure: no Roblox global, no require, tested under Lune (tests/ParticleBudget.spec.luau).

local ParticleBudget = {}

export type Ledger = {
	-- Particles counted alive.
	Live: number,
	-- Seconds a death is rounded up to.
	Step: number,
	-- How many of them die at the end of each step, keyed by the step's index (its end is Index * Step).
	Deaths: { [number]: number },
}

function ParticleBudget.ledger(step: number): Ledger
	return { Live = 0, Step = math.max(step, 1e-3), Deaths = {} }
end

-- Forgets every batch dead by `now`.
function ParticleBudget.sweep(ledger: Ledger, now: number)
	local deaths = ledger.Deaths
	for index, count in pairs(deaths) do
		if index * ledger.Step <= now then
			ledger.Live -= count
			deaths[index] = nil
		end
	end
	-- Whole particles only ever enter, but a reserved rate is a fraction: never let rounding leave a ghost.
	if next(deaths) == nil then
		ledger.Live = 0
	end
end

-- Counts `count` particles as alive from `now` until `now + seconds`, rounded up to the step.
function ParticleBudget.count(ledger: Ledger, now: number, count: number, seconds: number)
	if count <= 0 or count ~= count then
		return
	end
	local index = math.ceil((now + math.max(seconds, 0)) / ledger.Step)
	-- A death already past (a zero life on a step boundary) is the next step's: counted, then swept.
	index = math.max(index, math.floor(now / ledger.Step) + 1)
	ledger.Deaths[index] = (ledger.Deaths[index] or 0) + count
	ledger.Live += count
end

-- What is left of `budget` with `live` particles alive: never negative.
function ParticleBudget.room(budget: number, live: number): number
	return math.max(budget - live, 0)
end

-- What is left for what bodies wear (auras, trails): never more than the budget's `share` less what they already
-- keep alive (`worn`), nor more than is left of the whole. The effects may use every particle the worn looks do
-- not; the worn looks never take the fight's colour away from the glyphs.
function ParticleBudget.wornRoom(budget: number, share: number, live: number, worn: number): number
	return math.min(ParticleBudget.room(budget, live), math.max(budget * share - worn, 0))
end

-- Of `wanted` particles, how many fit in `room`: whole ones, never more than asked, never fewer than none.
function ParticleBudget.grant(wanted: number, room: number): number
	if wanted ~= wanted or room ~= room then
		return 0
	end
	return math.max(math.min(math.floor(wanted), math.floor(room)), 0)
end

-- The most particles an emitter the engine runs at `rate` keeps alive at once, each living up to `lifetime`: one
-- is born every 1 / rate seconds, so a life holds rate × lifetime of them, and one more on its boundary.
function ParticleBudget.held(rate: number, lifetime: number): number
	if rate ~= rate or rate <= 0 then
		return 0
	end
	return math.floor(rate * math.max(lifetime, 0)) + 1
end

-- The rate, at most `rate`, an engine-run emitter whose particles live up to `lifetime` may run at so that what
-- it keeps alive at once (held) fits in `room`; nothing when not even one fits.
function ParticleBudget.rate(rate: number, lifetime: number, room: number): number
	if rate ~= rate or rate <= 0 or room ~= room or room < 1 then
		return 0
	end
	if lifetime <= 0 then
		return rate
	end
	return math.min(rate, (room - 1) / lifetime)
end

return ParticleBudget
