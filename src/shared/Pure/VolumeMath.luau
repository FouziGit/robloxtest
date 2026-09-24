--!strict
-- VolumeMath: the arithmetic of a generated volume (D-114) -- where its pivot goes, how it turns, how a
-- landed drop splats, how a scrap of paper grows in and fades out, and the seed every client draws a
-- blast's volumes from. Pure: no Roblox global, no require, tested under Lune (tests/Volumes.spec.luau).
--
-- It lives apart from VfxVolumes so the numbers that make a volume stand on the floor, face the right
-- way and never pop are held to their outputs, not to the text of the lines that compute them.

local VolumeMath = {}

-- A scrap grows in from this share of its size over GROW_SECONDS (rule 3), and in its last FADE_SECONDS
-- it shrinks and fades on the ink's clock, having lain flat for the rest (rule 5: the trace that fades).
VolumeMath.GrowFrom = 0.3
VolumeMath.GrowSeconds = 0.06
VolumeMath.FadeSeconds = 0.3
-- How long a landed scrap takes to settle flat.
VolumeMath.SettleSeconds = 0.12

-- A landed drop splats: this much wider, and this much shorter along its flight, once it is done.
local SPLAT_WIDEN = 0.6
local SPLAT_FLATTEN = 0.9

local function clamp01(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- The SpecialMesh.Offset that puts a mesh's pivot back on its part, at scale (x, y, z). The importer
-- recentres a mesh on its bounds, so the part's centre is the bounds' centre; moving the mesh by the
-- centre's distance from the pivot puts the pivot where the part is: a crown stands ON the floor.
function VolumeMath.pivotOffset(
	min: { number },
	max: { number },
	pivot: { number },
	x: number,
	y: number,
	z: number
): (number, number, number)
	return ((min[1] + max[1]) / 2 - pivot[1]) * x,
		((min[2] + max[2]) / 2 - pivot[2]) * y,
		((min[3] + max[3]) / 2 - pivot[3]) * z
end

-- A turn of `angle` about a mesh's own axis, as the three angles CFrame.Angles takes. Only ever about
-- that axis: every normal of a volume points along it, so any other turn would light it another tone.
function VolumeMath.turn(axis: string, angle: number): (number, number, number)
	if axis == "X" then
		return angle, 0, 0
	elseif axis == "Z" then
		return 0, 0, angle
	end
	return 0, angle, 0
end

-- A facing laid flat on the floor, as a unit vector: a volume turns only about the vertical and never
-- tips. Straight up or down has no horizontal answer, so it faces the world's forward.
function VolumeMath.flatFacing(x: number, _y: number, z: number): (number, number, number)
	local length = math.sqrt(x * x + z * z)
	if length < 1e-3 then
		return 0, 0, -1
	end
	return x / length, 0, z / length
end

-- How far a landed drop has splatted, `since` seconds after it landed: fast then easing (rule 4), done
-- when its landing fade is.
function VolumeMath.splat(since: number, seconds: number): number
	local done = if seconds > 0 then clamp01(since / seconds) else 1
	return 1 - (1 - done) * (1 - done)
end

-- What a splat of `splat` does to a drop's scale: wider across, shorter along its flight (its Z).
function VolumeMath.splatScale(splat: number): (number, number)
	return 1 + SPLAT_WIDEN * splat, 1 - SPLAT_FLATTEN * splat
end

-- How much of its size a scrap has `t` seconds after it was thrown: grown in, fast then easing.
function VolumeMath.scrapGrow(t: number): number
	local grown = clamp01(t / VolumeMath.GrowSeconds)
	return VolumeMath.GrowFrom + (1 - VolumeMath.GrowFrom) * (1 - (1 - grown) * (1 - grown))
end

-- A scrap's transparency `t` seconds after it was thrown, when it lasts `lasts`: none until its last
-- FadeSeconds, then gone on the ink's clock -- a quarter sine, slow then fast (FeelMath.inkFade).
function VolumeMath.scrapFade(t: number, lasts: number): number
	local into = clamp01((t - (lasts - VolumeMath.FadeSeconds)) / VolumeMath.FadeSeconds)
	return 1 - math.cos(into * math.pi / 2)
end

-- How much of its size a dash's sketch keeps at `elapsed` of its life (0 to 1): all of it, then over the
-- last `share` of its life shrinking away to nothing, slow then fast -- a print never vanishes (rule 3).
function VolumeMath.sketchShrink(elapsed: number, share: number): number
	if share <= 0 then
		return if elapsed >= 1 then 0 else 1
	end
	local into = clamp01((elapsed - (1 - share)) / share)
	return 1 - into * into
end

-- What a dash's print waiting for its body does now (D-116): "Lay" once the body has covered `target`
-- studs of its path; "Drop" once it has been moving for `wait` seconds without getting there (a dash
-- stopped by a wall), or has not moved at all within `ceiling` of the print's time -- counted from the
-- moment it moved, not from the packet, because another screen sees a dasher move only a round trip
-- later; otherwise "Wait". `movedAt` is nil until the body has moved.
function VolumeMath.printDecision(
	travelled: number,
	target: number,
	now: number,
	at: number,
	movedAt: number?,
	wait: number,
	ceiling: number
): string
	if travelled >= target then
		return "Lay"
	end
	if movedAt ~= nil then
		return if now >= movedAt + wait then "Drop" else "Wait"
	end
	return if now >= at + ceiling then "Drop" else "Wait"
end

-- How far below where a scrap was thrown it lands, or nil when it has nowhere to land: no floor under
-- the blast, or a "floor" above it (the probe starts a stud up). A scrap with nowhere to land fades in
-- the air rather than lying flat on nothing.
function VolumeMath.scrapDepth(originY: number, floorY: number, found: boolean): number?
	if not found or floorY > originY + 1e-3 then
		return nil
	end
	return math.max(originY - floorY, 0)
end

-- A seed every client computes the same from what every client received: the point a play is drawn at
-- (a packet's Origin arrives as the same float on every screen), snapped to a sixteenth of a stud, and
-- a salt naming what inside the play it seeds. A client-side counter would give each screen its own
-- blast.
function VolumeMath.seed(x: number, y: number, z: number, salt: number): number
	local qx = math.floor(x * 16 + 0.5)
	local qy = math.floor(y * 16 + 0.5)
	local qz = math.floor(z * 16 + 0.5)
	return (qx * 73856093 + qy * 19349663 + qz * 83492791 + salt * 2654435761) % 2147483647
end

return VolumeMath
