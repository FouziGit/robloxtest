--!strict
-- StunWatch: whether a body walked through a stun it had been told of (D-213). Pure: no Roblox global, no require,
-- so it is unit-tested under Lune (tests/Stun.spec.luau). Security/MovementAudit keeps one per player and logs what
-- it finds; it never moves anybody nor strikes for it.
--
-- MovementService dates every stun (Pure/StunClock). The owning client learns of it a one-way trip after it began,
-- stops its body, and the server sees the body stopped a round trip and a send after the start (`learnedAt`). From
-- then to the stun's end, a tick on which something else moves the body -- a push the server granted, a touch, a
-- fall -- is carried, and a step faster than a body can move on its own is not a walk (a server pivot, a correction,
-- the catch-up after a stall: other rules judge those); every other stud it covers, it walked. Once it has walked
-- past the slack, that stun is logged, once.

local StunWatch = {}

export type Watch = {
	-- The start of the stun being watched, 0 for none: another start is another stun.
	StartedAt: number,
	-- Whether the window has opened, and where the body stood on the last tick of it, and when.
	Open: boolean,
	FromX: number,
	FromZ: number,
	FromAt: number,
	-- Horizontal studs walked since the window opened, and whether this stun was already reported.
	Walked: number,
	Reported: boolean,
}

function StunWatch.new(): Watch
	return { StartedAt = 0, Open = false, FromX = 0, FromZ = 0, FromAt = 0, Walked = 0, Reported = false }
end

-- When the server can first expect to see a stun that began at `startedAt` obeyed: the round trip `rtt` and
-- `overhead` for a send and a frame. A round trip that is not a number never opens the window.
function StunWatch.learnedAt(startedAt: number, rtt: number, overhead: number): number
	if rtt ~= rtt then
		return math.huge
	end
	return startedAt + math.max(rtt, 0) + overhead
end

-- One audited tick of a body at (`x`, `z`). `startedAt` and `endsAt` date the running stun (0, 0 for none), `learned`
-- is StunWatch.learnedAt of it, `carried` says something else moves the body this tick, and `speed` is the fastest a
-- body moves on its own. Returns the studs walked on the tick they first pass `slack` in this stun, and nil on every
-- other tick.
function StunWatch.step(
	watch: Watch,
	now: number,
	startedAt: number,
	endsAt: number,
	learned: number,
	x: number,
	z: number,
	carried: boolean,
	slack: number,
	speed: number
): number?
	if startedAt ~= watch.StartedAt then
		watch.StartedAt = startedAt
		watch.Open = false
		watch.Walked = 0
		watch.Reported = false
	end
	if startedAt <= 0 or now < learned or now > endsAt then
		return nil
	end
	if not watch.Open then
		watch.Open = true
		watch.FromX, watch.FromZ, watch.FromAt = x, z, now
		return nil
	end
	local dx, dz = x - watch.FromX, z - watch.FromZ
	local step = math.sqrt(dx * dx + dz * dz)
	local elapsed = now - watch.FromAt
	watch.FromX, watch.FromZ, watch.FromAt = x, z, now
	if carried or step > speed * elapsed then
		return nil
	end
	watch.Walked += step
	if watch.Reported or watch.Walked <= slack then
		return nil
	end
	watch.Reported = true
	return watch.Walked
end

return StunWatch
