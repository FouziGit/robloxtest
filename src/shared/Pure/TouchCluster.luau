--!strict
-- TouchCluster: where the touch discs stand, and which of them can still pay for a glyph (D-147). Pure: no
-- Roblox global, no require. InputController measures the screen and the engine's jump button, hands them
-- in as numbers, and draws what comes back; tests/TouchCluster.spec.luau runs the layout on real phone
-- sizes.
--
-- The layout (InputConfig.Touch): the Menu disc in the top-right corner, the kit in a row left of the jump
-- button, the pigment ring above and left of it. Every centre stays inside the safe area and clear of the
-- jump button, and two discs are never closer than their two radii plus the gap. That spacing is per pair
-- rather than one step for all: the Melee disc is drawn bigger (Touch.SizeScale), and a single step sized
-- for it would push the whole kit row about 38 points toward the middle of a phone, eating the room the
-- combat dock has between the thumbs.

export type Point = { X: number, Y: number }
export type Rect = { Min: Point, Max: Point }
-- InputConfig.TouchPlacement, with its anchor as a plain string.
export type Placement = { Anchor: string, Angle: number?, Step: number? }
export type Config = {
	ButtonSize: number,
	MinButtonSize: number,
	Gap: number,
	Margin: number,
	Positions: { [string]: Placement },
	SizeScale: { [string]: number }?,
}
export type Disc = { Centre: Point, Diameter: number }
-- A glyph as the discs see it: the pigments of its recipe, and its ink.
export type Recipe = { Combo: { string }, Cost: number }

local TouchCluster = {}

local CLUSTER = "Cluster"
local JUMP_ROW = "JumpRow"
local TOP_RIGHT = "TopRight"
-- Resolved in this order, so the first placed keeps its spot: the corner, the row, then the ring.
local ANCHOR_PRIORITY: { [string]: number } = { TopRight = 1, JumpRow = 2, Cluster = 3 }
local LAST_PRIORITY = 4
-- Relaxation passes per disc, so a clamped placement still keeps its distances.
local SEPARATION_PASSES = 4
local EPSILON = 0.001

local function point(x: number, y: number): Point
	return { X = x, Y = y }
end

local function shrink(rect: Rect, x: number, y: number): Rect
	local minX, minY = rect.Min.X + x, rect.Min.Y + y
	local maxX, maxY = rect.Max.X - x, rect.Max.Y - y
	return { Min = point(minX, minY), Max = point(math.max(minX, maxX), math.max(minY, maxY)) }
end

local function clamp(at: Point, bounds: Rect): Point
	return point(math.clamp(at.X, bounds.Min.X, bounds.Max.X), math.clamp(at.Y, bounds.Min.Y, bounds.Max.Y))
end

-- A disc's diameter before its own scale: the design size at `scale`, never under the smallest reliable touch
-- target (the discs sit under no UIScale, so nothing else floors them).
function TouchCluster.baseDiameter(config: Config, scale: number): number
	return math.max(config.ButtonSize * scale, config.MinButtonSize)
end

-- The diameter of `action`'s disc: the base, times its own scale (Touch.SizeScale; 1 for most).
function TouchCluster.diameter(config: Config, action: string, scale: number): number
	local sizes = config.SizeScale
	local own = if sizes ~= nil then sizes[action] else nil
	return TouchCluster.baseDiameter(config, scale) * (own or 1)
end

local function rank(placement: Placement): number
	local anchor = ANCHOR_PRIORITY[placement.Anchor] or LAST_PRIORITY
	local detail = placement.Step or 0
	if placement.Anchor == CLUSTER then
		detail = if placement.Angle == nil then 0 else 1 + placement.Angle / 360
	end
	return anchor * 10 + detail
end

-- The actions that have a place, in the order they are placed.
local function placementOrder(config: Config, actions: { string }): { string }
	local order: { string } = {}
	for _, action in ipairs(actions) do
		if config.Positions[action] ~= nil then
			table.insert(order, action)
		end
	end
	table.sort(order, function(left: string, right: string): boolean
		local leftRank, rightRank = rank(config.Positions[left]), rank(config.Positions[right])
		if leftRank == rightRank then
			return left < right
		end
		return leftRank < rightRank
	end)
	return order
end

local function ringOffset(placement: Placement, step: number): Point
	local angle = placement.Angle
	if angle == nil then
		return point(0, 0)
	end
	local radians = math.rad(angle)
	return point(math.cos(radians) * step, -math.sin(radians) * step)
end

type Placed = { Centre: Point, Radius: number }

-- Pushes a disc of `radius` at `at` away from every disc placed before it, to their radii plus the gap.
local function pushNeighbours(at: Point, radius: number, placed: { Placed }, gap: number, bounds: Rect): Point
	local result = at
	for _, other in ipairs(placed) do
		local need = radius + other.Radius + gap
		local dx, dy = result.X - other.Centre.X, result.Y - other.Centre.Y
		local distance = math.sqrt(dx * dx + dy * dy)
		if distance < need - EPSILON then
			local ux, uy = -1, 0
			if distance > EPSILON then
				ux, uy = dx / distance, dy / distance
			end
			result = clamp(point(other.Centre.X + ux * need, other.Centre.Y + uy * need), bounds)
		end
	end
	return result
end

-- Lifts a point above the jump button when it fell inside the button plus `clearance`.
local function clearJump(at: Point, jump: Rect, clearance: number, bounds: Rect): Point
	local outside = at.X < jump.Min.X - clearance + EPSILON
		or at.X > jump.Max.X + clearance - EPSILON
		or at.Y < jump.Min.Y - clearance + EPSILON
		or at.Y > jump.Max.Y + clearance - EPSILON
	if outside then
		return at
	end
	return clamp(point(at.X, jump.Min.Y - clearance), bounds)
end

-- The kit row's centres along X, by action: the first step one radius and a gap left of the jump button, and
-- each next one its own radius, the previous one's and a gap further. A step left out keeps its room.
local function rowCentres(config: Config, order: { string }, jumpLeft: number, scale: number): { [string]: number }
	local gap = config.Gap * scale
	local base = TouchCluster.baseDiameter(config, scale)
	local row: { string } = {}
	for _, action in ipairs(order) do
		if config.Positions[action].Anchor == JUMP_ROW then
			table.insert(row, action)
		end
	end
	local centres: { [string]: number } = {}
	local x, lastRadius, lastStep = jumpLeft, 0, 0
	for index, action in ipairs(row) do
		local radius = TouchCluster.diameter(config, action, scale) / 2
		local step = config.Positions[action].Step or 1
		local skipped = math.max(0, step - lastStep - 1) * (base + gap)
		x -= (if index == 1 then 0 else lastRadius) + radius + gap + skipped
		centres[action] = x
		lastRadius, lastStep = radius, step
	end
	return centres
end

-- Every disc of `actions` that has a place: its centre, in the space `screen` and `jump` are measured in, and
-- its diameter. `screen` is the area under the top bar, `jump` the engine's jump button (or the corner kept
-- for it while the engine has not built it), `scale` the interface's (Theme.scaleFor).
function TouchCluster.layout(
	config: Config,
	actions: { string },
	screen: Rect,
	jump: Rect,
	scale: number
): { [string]: Disc }
	local gap = config.Gap * scale
	local margin = config.Margin * scale
	local order = placementOrder(config, actions)

	-- The ring is as wide as its biggest disc, and stands clear of the row's biggest.
	local ringRadius, rowRadius = 0, 0
	for _, action in ipairs(order) do
		local radius = TouchCluster.diameter(config, action, scale) / 2
		local anchor = config.Positions[action].Anchor
		if anchor == CLUSTER then
			ringRadius = math.max(ringRadius, radius)
		elseif anchor == JUMP_ROW then
			rowRadius = math.max(rowRadius, radius)
		end
	end
	local ringStep = ringRadius * 2 + gap
	local extentX, extentY = 0, 0
	for _, action in ipairs(order) do
		local placement = config.Positions[action]
		if placement.Anchor == CLUSTER then
			local offset = ringOffset(placement, ringStep)
			extentX, extentY = math.max(extentX, math.abs(offset.X)), math.max(extentY, math.abs(offset.Y))
		end
	end

	local rowY = jump.Min.Y + (jump.Max.Y - jump.Min.Y) * 0.5
	local rowX = rowCentres(config, order, jump.Min.X, scale)
	local ringBounds = shrink(shrink(screen, margin + ringRadius, margin + ringRadius), extentX, extentY)
	local ringCentre = point(
		math.max(ringBounds.Min.X, math.min(ringBounds.Max.X, jump.Max.X - extentX)),
		math.max(
			ringBounds.Min.Y,
			math.min(
				ringBounds.Max.Y,
				rowY - (ringRadius + rowRadius + gap) - extentY,
				jump.Min.Y - (ringRadius + gap) - extentY
			)
		)
	)

	local discs: { [string]: Disc } = {}
	local placed: { Placed } = {}
	for _, action in ipairs(order) do
		local placement = config.Positions[action]
		local diameter = TouchCluster.diameter(config, action, scale)
		local radius = diameter / 2
		local bounds = shrink(screen, margin + radius, margin + radius)
		local offset = ringOffset(placement, ringStep)
		local at = point(ringCentre.X + offset.X, ringCentre.Y + offset.Y)
		if placement.Anchor == TOP_RIGHT then
			at = point(bounds.Max.X, bounds.Min.Y)
		elseif placement.Anchor == JUMP_ROW then
			at = point(rowX[action], rowY)
		end
		at = clamp(at, bounds)
		for _ = 1, SEPARATION_PASSES do
			local moved = clearJump(pushNeighbours(at, radius, placed, gap, bounds), jump, radius + gap, bounds)
			local dx, dy = moved.X - at.X, moved.Y - at.Y
			local settled = math.sqrt(dx * dx + dy * dy) < EPSILON
			at = moved
			if settled then
				break
			end
		end
		discs[action] = { Centre = at, Diameter = diameter }
		table.insert(placed, { Centre = at, Radius = radius })
	end
	return discs
end

-- The combat dock's span on a touch screen (D-147), between the thumbs. Centred, and as wide as the room from
-- the middle to the nearest disc allows on both sides, never wider than `limits.Widest`; where the discs reach
-- too near the middle for `limits.Narrowest`, as on a small phone, it keeps that width and slides left until its
-- right edge clears them. `nearest` (the left edge of the nearest disc), `centre` and `limits.Clearance` are
-- screen pixels; the width and the offset of the dock's centre from `centre` come back in design units.
function TouchCluster.dockSpan(
	nearest: number,
	centre: number,
	scale: number,
	limits: { Clearance: number, Widest: number, Narrowest: number }
): (number, number)
	local room = (nearest - limits.Clearance - centre) / scale
	if 2 * room >= limits.Narrowest then
		return math.min(limits.Widest, 2 * room), 0
	end
	return limits.Narrowest, room - limits.Narrowest / 2
end

-- The pigments that still lead to a glyph the ink can pay for: those in the recipe of at least one equipped
-- glyph that costs no more than `ink`. A disc whose pigment is not in it can cast nothing right now, whatever
-- the sequence. Written into `into`, cleared first, so a push five times a second allocates nothing.
function TouchCluster.affordable(recipes: { Recipe }, ink: number, into: { [string]: boolean }): { [string]: boolean }
	table.clear(into)
	for _, recipe in ipairs(recipes) do
		if recipe.Cost <= ink then
			for _, pigment in ipairs(recipe.Combo) do
				into[pigment] = true
			end
		end
	end
	return into
end

return TouchCluster
