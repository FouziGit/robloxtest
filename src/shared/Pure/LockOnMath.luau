--!strict
-- LockOnMath: the arithmetic of a lock (D-115) -- which target a look picks, where the locked camera
-- looks, and which way the character faces. Pure: no Roblox global, no require, tested under Lune
-- (tests/LockOn.spec.luau). Vectors are passed as numbers.

local LockOnMath = {}

-- Degrees between a look (a unit vector) and the direction to a point `d` away, or nil for a point
-- at the eye itself.
function LockOnMath.angle(lx: number, ly: number, lz: number, dx: number, dy: number, dz: number): number?
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-6 then
		return nil
	end
	local cosine = math.clamp((lx * dx + ly * dy + lz * dz) / length, -1, 1)
	return math.deg(math.acos(cosine))
end

-- How well a target `angle` degrees off the look and `distance` studs away answers a lock, lower is
-- better; nil when it is out of reach or out of the cone. The angle decides; within half a degree, the
-- nearer.
function LockOnMath.rank(angle: number, distance: number, reach: number, cone: number): number?
	if distance > reach or angle > cone then
		return nil
	end
	return angle + 0.5 * distance / reach
end

-- Where a locked camera looks, as a unit vector, toward a point `d` from its pivot: straight at it
-- across the floor, and up or down at it tilted by `bias` degrees and held between `low` and `high`, so
-- a target overhead or underfoot never swings the camera into the sky or the floor. nil when the point
-- is straight above or below the pivot, where there is no direction to face.
function LockOnMath.look(
	dx: number,
	dy: number,
	dz: number,
	bias: number,
	low: number,
	high: number
): (number?, number?, number?)
	local flat = math.sqrt(dx * dx + dz * dz)
	if flat < 1e-3 then
		return nil, nil, nil
	end
	local pitch = math.rad(math.clamp(math.deg(math.atan2(dy, flat)) + bias, low, high))
	local across = math.cos(pitch)
	return dx / flat * across, math.sin(pitch), dz / flat * across
end

-- The way a character at (fx, fz) faces a target at (tx, tz), across the floor, as a unit (x, z); nil
-- when the two are closer than `minimum`, where the direction is noise.
function LockOnMath.facing(fx: number, fz: number, tx: number, tz: number, minimum: number): (number?, number?)
	local dx, dz = tx - fx, tz - fz
	local length = math.sqrt(dx * dx + dz * dz)
	if length < math.max(minimum, 1e-6) then
		return nil, nil
	end
	return dx / length, dz / length
end

-- The share of the way a camera turning at `rate` (per second) covers in `seconds`: the same turn
-- whatever the frame rate.
function LockOnMath.turnShare(rate: number, seconds: number): number
	return 1 - math.exp(-rate * math.max(seconds, 0))
end

-- The candidates a lock may take, best first, as indices into `candidates`: each within `reach` studs
-- and `cone` degrees of the aim (an Angle of nil is a point at the eye itself, never taken), ranked by
-- `rank`. Whether one is in sight is the caller's to ask, in this order, stopping at the first.
export type Candidate = { Angle: number?, Distance: number }
function LockOnMath.order(candidates: { Candidate }, reach: number, cone: number): { number }
	local ranked: { { Index: number, Score: number } } = {}
	for index, candidate in ipairs(candidates) do
		local angle = candidate.Angle
		local score = if angle ~= nil then LockOnMath.rank(angle, candidate.Distance, reach, cone) else nil
		if score ~= nil then
			table.insert(ranked, { Index = index, Score = score })
		end
	end
	table.sort(ranked, function(a, b)
		return a.Score < b.Score
	end)
	local out: { number } = {}
	for _, entry in ipairs(ranked) do
		table.insert(out, entry.Index)
	end
	return out
end

-- A difference in height as a locked camera takes it: none within `deadband` studs -- a jump, or a
-- double jump, is not a reason to swing the view -- and only what is beyond it past that.
function LockOnMath.lift(dy: number, deadband: number): number
	if math.abs(dy) <= deadband then
		return 0
	end
	return dy - math.sign(dy) * deadband
end

-- The yaw (radians about the vertical, 0 looking down -Z) and pitch of a unit look, and back.
function LockOnMath.yawPitch(x: number, y: number, z: number): (number, number)
	return math.atan2(-x, -z), math.asin(math.clamp(y, -1, 1))
end

function LockOnMath.fromYawPitch(yaw: number, pitch: number): (number, number, number)
	local across = math.cos(pitch)
	return -math.sin(yaw) * across, math.sin(pitch), -math.cos(yaw) * across
end

-- An angle turned `share` of the way toward another, the short way round.
function LockOnMath.turnAngle(from: number, to: number, share: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * share
end

return LockOnMath
