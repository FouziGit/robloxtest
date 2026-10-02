--!strict
-- EffectClock: the time every drawn effect runs on, which is real time unless something asks otherwise.
-- Two things do. An impact holds it for a few hundredths of a second, so the burst, its sparks and its
-- flash stop dead together -- the freeze frame that sells a hit (D-118); inputs and the server never
-- stop. And the Studio VFX lab (tools/vfxlab/) slows it or stops it, to look at an effect frame by frame.
--
-- Read on demand from the real clock the caller passes: no loop of its own, and exact at any frame rate.
-- Pure: no Roblox global, no require, tested under Lune (tests/EffectClock.spec.luau).

local EffectClock = {}

export type State = {
	-- Effect time at RealBase, and how fast it runs from there.
	Base: number,
	RealBase: number,
	Scale: number,
	-- The real time span it is held still over (none: an empty span in the past).
	HoldFrom: number,
	HoldUntil: number,
}

function EffectClock.new(real: number): State
	return { Base = real, RealBase = real, Scale = 1, HoldFrom = -math.huge, HoldUntil = -math.huge }
end

-- Effect time at real time `real`: the real time since RealBase, less the part of it spent held, at Scale.
function EffectClock.read(state: State, real: number): number
	local held = math.max(math.min(real, state.HoldUntil) - math.max(state.RealBase, state.HoldFrom), 0)
	return state.Base + (real - state.RealBase - held) * state.Scale
end

-- How fast effect time is running at `real`: 0 while held.
function EffectClock.rate(state: State, real: number): number
	return if real >= state.HoldFrom and real < state.HoldUntil then 0 else state.Scale
end

local function rebase(state: State, real: number)
	state.Base = EffectClock.read(state, real)
	state.RealBase = real
end

-- Runs effect time at `scale` from now on (0 stops it, 1 is real time). Never negative: an effect is not
-- played backwards.
function EffectClock.rescale(state: State, real: number, scale: number)
	rebase(state, real)
	state.Scale = math.max(scale, 0)
end

-- Holds effect time still for `seconds`, starting `after` seconds from now (at once when absent): a burst
-- held on its first frame is held before it has drawn anything, a few hundredths later it is held at its
-- widest. Overlapping holds do not add up -- they merge, the later end wins -- and no hold outlasts
-- `longest`, so a burst of hits reads as impact, never as a stall.
function EffectClock.hold(state: State, real: number, seconds: number, longest: number, after: number?)
	if seconds <= 0 then
		return
	end
	rebase(state, real)
	local from = real + math.max(after or 0, 0)
	local untilAt = from + math.min(seconds, longest)
	if state.HoldUntil < real then
		state.HoldFrom = from
		state.HoldUntil = untilAt
	else
		state.HoldFrom = math.min(state.HoldFrom, from)
		state.HoldUntil = math.max(state.HoldUntil, untilAt)
	end
end

return EffectClock
