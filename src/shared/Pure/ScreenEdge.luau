--!strict
-- ScreenEdge: where a line from the middle of the screen toward something off it meets the screen's edge,
-- and which way it points (D-147). The lock's chevron stands there when the locked target is out of view,
-- turned toward it. Pure: no Roblox global, no require; tested under Lune (tests/LockMarker.spec.luau).
-- Screen axes: x to the right, y down, angles in degrees from the right, clockwise.

local ScreenEdge = {}

-- The point, relative to the centre of a rectangle `halfWidth` by `halfHeight` from its centre, where the ray
-- along (dx, dy) leaves it, and the ray's angle. Nil for no direction.
function ScreenEdge.toward(dx: number, dy: number, halfWidth: number, halfHeight: number): (number?, number?, number?)
	if dx == 0 and dy == 0 then
		return nil, nil, nil
	end
	local alongX = if dx ~= 0 then halfWidth / math.abs(dx) else math.huge
	local alongY = if dy ~= 0 then halfHeight / math.abs(dy) else math.huge
	local reach = math.min(alongX, alongY)
	return dx * reach, dy * reach, math.deg(math.atan2(dy, dx))
end

return ScreenEdge
