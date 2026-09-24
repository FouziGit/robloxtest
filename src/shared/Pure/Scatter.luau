--!strict
-- Scatter: where a scrap of paper thrown off a blast is, t seconds after it was thrown (D-114). Pure: no
-- Roblox global, no require, tested under Lune (tests/Scatter.spec.luau).
--
-- Closed form rather than stepped, so a dropped frame costs nothing and every client draws the same
-- flight from the same seed. A sheet of paper is not a stone: drag pulls its thrown speed toward a slow
-- terminal fall, and once it has stopped rising it rocks from side to side as it comes down.

local Scatter = {}

-- One scrap: its thrown velocity (studs/s), how hard the air slows it (1/s), the speed it settles into
-- falling (studs/s), how far and how fast it rocks after its apex, where in the rock it starts, and how
-- fast it tumbles (rad/s).
export type Piece = {
	VX: number,
	VY: number,
	VZ: number,
	Drag: number,
	Fall: number,
	Rock: number,
	RockRate: number,
	Phase: number,
	Tumble: number,
}

-- The rock eases in over this long after the apex: a scrap does not start swinging on one frame.
local ROCK_EASE_SECONDS = 0.2

-- Seconds until the scrap stops rising (0 when it was thrown downward).
function Scatter.apex(piece: Piece): number
	if piece.VY <= 0 then
		return 0
	end
	return math.log((piece.VY + piece.Fall) / piece.Fall) / piece.Drag
end

-- How far a thrown speed has carried a scrap after `t` seconds of drag: it approaches 1/Drag.
local function carried(piece: Piece, t: number): number
	return (1 - math.exp(-piece.Drag * t)) / piece.Drag
end

-- The scrap's offset from where it was thrown, `t` seconds later.
function Scatter.offset(piece: Piece, t: number): (number, number, number)
	local settle = carried(piece, t)
	local x = piece.VX * settle
	local z = piece.VZ * settle
	local y = -piece.Fall * t + (piece.VY + piece.Fall) * settle
	local apex = Scatter.apex(piece)
	if t > apex then
		-- Across its own flight, never along it: a sheet rocks side to side.
		local flat = math.sqrt(piece.VX * piece.VX + piece.VZ * piece.VZ)
		local sideX, sideZ = 1, 0
		if flat > 1e-6 then
			sideX, sideZ = -piece.VZ / flat, piece.VX / flat
		end
		local swing = math.min((t - apex) / ROCK_EASE_SECONDS, 1)
			* piece.Rock
			* math.sin(piece.RockRate * (t - apex) + piece.Phase)
		x += sideX * swing
		z += sideZ * swing
	end
	return x, y, z
end

-- How far the scrap has tumbled after `t` seconds: fast while the throw carries it, then slowly for as
-- long as it keeps falling.
function Scatter.tumble(piece: Piece, t: number): number
	return piece.Tumble * (carried(piece, t) + 0.3 * t)
end

-- The first moment after its apex the scrap is `depth` studs below where it was thrown (a floor under
-- the blast, depth > 0), found by bisection -- or nil when it is still above it after `within` seconds.
function Scatter.landing(piece: Piece, depth: number, within: number): number?
	local low = Scatter.apex(piece)
	local _, lowY = Scatter.offset(piece, low)
	if lowY <= -depth then
		return low
	end
	local _, endY = Scatter.offset(piece, within)
	if endY > -depth then
		return nil
	end
	local high = within
	for _ = 1, 40 do
		local middle = (low + high) / 2
		local _, y = Scatter.offset(piece, middle)
		if y > -depth then
			low = middle
		else
			high = middle
		end
	end
	return high
end

return Scatter
