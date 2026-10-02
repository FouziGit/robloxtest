--!strict
-- StunClock: when a player's stun began and when it ends, dated on the server's clock, and the grace that keeps a
-- glyph from chaining one stun into the next (D-213). Pure: no Roblox global, no require, so it is unit-tested
-- under Lune (tests/Stun.spec.luau). MovementService keeps one per player and does the Roblox parts: the Humanoid,
-- the attribute and the command that tells the owning client.
--
-- Two kinds of hold go through it. A combat hold (a melee hit, a guard break, a fall, a Forger's or the Erasure's
-- blow) and a scripted freeze run to at least their own end: never shortened, extended by a longer one. A glyph's
-- stun asks first (`admits`): never while a stun runs, which it would only have extended, and never within the
-- grace after the last one ended, so the target always gets that long back between two glyph stuns. The longest
-- a chain of glyphs holds anybody without a break is then its longest glyph's own stun.

local StunClock = {}

export type Clock = {
	-- When the running stun began; 0 when none runs.
	StartedAt: number,
	-- When it ends; 0 when none runs.
	Until: number,
	-- When the last stun ended, on its own date rather than on the tick that noticed; -math.huge before the first.
	EndedAt: number,
}

function StunClock.new(): Clock
	return { StartedAt = 0, Until = 0, EndedAt = -math.huge }
end

-- Whether a stun runs at `now`.
function StunClock.running(clock: Clock, now: number): boolean
	return clock.Until > now
end

-- Ends a stun whose time is up, dated when it was due. True when this call ended one: the caller tells the body.
function StunClock.expire(clock: Clock, now: number): boolean
	if clock.Until <= 0 or clock.Until > now then
		return false
	end
	clock.EndedAt = clock.Until
	clock.StartedAt = 0
	clock.Until = 0
	return true
end

-- Holds the body until at least `now + seconds`: a stun already running is never shortened and keeps its start; a
-- new one is dated from `now`. Returns the seconds left, which the owning client is told.
function StunClock.hold(clock: Clock, now: number, seconds: number): number
	StunClock.expire(clock, now)
	if clock.Until <= 0 then
		clock.StartedAt = now
	end
	clock.Until = math.max(clock.Until, now + seconds)
	return clock.Until - now
end

-- Whether a glyph's stun may land at `now`: no stun running, and `grace` seconds since the last one ended.
function StunClock.admits(clock: Clock, now: number, grace: number): boolean
	StunClock.expire(clock, now)
	return clock.Until <= 0 and now >= clock.EndedAt + grace
end

-- Ends the stun now (a freeze the server lets go of early). True when one was running.
function StunClock.clear(clock: Clock, now: number): boolean
	StunClock.expire(clock, now)
	if clock.Until <= 0 then
		return false
	end
	clock.EndedAt = now
	clock.StartedAt = 0
	clock.Until = 0
	return true
end

return StunClock
