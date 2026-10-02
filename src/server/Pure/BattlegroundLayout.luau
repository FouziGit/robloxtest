--!strict
-- The Battleground's geometry (D-131), derived from BattlegroundConfig.Map: every box the map builder turns
-- into a part, the points players land on and Forgers appear at, the rectangles a Forger walks around, and
-- the waypoint graph it finds its way on. Pure module: no require, no Roblox global. The shapes it takes are
-- re-declared here, and every number arrives through the caller, so tests/BattlegroundLayout.spec.luau holds
-- the page to its claims -- nothing solid in the camp, nothing a perch, every path clear -- without an engine.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. Everything a Forger decides happens
-- on the ground plane (x, z); heights only matter to the boxes.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }

-- The fields of BattlegroundConfig.Map this module reads.
export type MapDef = {
	Size: number,
	WallHeight: number,
	WallThickness: number,
	FloorThickness: number,
	KillZoneDepth: number,
	KillZoneSpread: number,
	KillZoneThickness: number,
	RuleInsetStuds: number,
	RuleWidthStuds: number,
	Camp: Rect,
	ReturnGate: Point,
	Arrivals: { Point },
	Pillars: { Radius: number, Count: number, AngleOffsetDegrees: number, Size: { number } },
	Stele: { Size: { number } },
	CoverHeight: number,
	Covers: { Cover },
	BotSpawns: { Point },
	Grid: { StepStuds: number, MarginStuds: number },
}

-- What the page is dressed with, from outside BattlegroundConfig.Map: the names its readers find the floor
-- and the kill plane by (BattlegroundConfig.Anchors), the wall rule every arena draws (WorldConfig.Arena),
-- the ladder's rungs and the flat slabs' thickness (WorldConfig), and the camp's wash (WorldConfig.Battleground).
export type Dressing = {
	FloorName: string,
	KillZoneName: string,
	WallRuleStuds: number,
	WallRuleProudStuds: number,
	FlatThickness: number,
	RuleTop: number,
	CampTop: number,
	CampTransparency: number,
}

-- One part: its centre and size in the local frame. Role is a key of WorldConfig.Battleground, the colour
-- the builder paints it. A solid box collides and blocks sight; the rest is decoration.
export type Box = {
	Name: string,
	Role: string,
	X: number,
	Y: number,
	Z: number,
	SizeX: number,
	SizeY: number,
	SizeZ: number,
	Solid: boolean,
	Transparency: number,
}

export type Layout = {
	Boxes: { Box },
	Arrivals: { Point },
	BotSpawns: { Point },
	ReturnGate: Point,
	Camp: Rect,
	-- The floor's rectangle, inside the walls.
	Bounds: Rect,
	-- Every solid box that stands on the floor (not the floor, not a wall), as its footprint.
	Obstacles: { Rect },
	-- The obstacles and the camp, each grown by PathRadius: where no waypoint lies and no straight walk crosses.
	Blocked: { Rect },
	Nodes: { Point },
	-- Edges[i]: the nodes a Forger can walk to straight from node i.
	Edges: { { number } },
	PathRadius: number,
}

local BattlegroundLayout = {}

local SQRT2 = math.sqrt(2)
-- Below this a segment has no extent along an axis, and only its position on that axis decides a hit.
local EPSILON = 1e-9

function BattlegroundLayout.inRect(rect: Rect, x: number, z: number): boolean
	return x >= rect.MinX and x <= rect.MaxX and z >= rect.MinZ and z <= rect.MaxZ
end

function BattlegroundLayout.inflate(rect: Rect, by: number): Rect
	return { MinX = rect.MinX - by, MaxX = rect.MaxX + by, MinZ = rect.MinZ - by, MaxZ = rect.MaxZ + by }
end

local function footprint(box: Box): Rect
	return {
		MinX = box.X - box.SizeX / 2,
		MaxX = box.X + box.SizeX / 2,
		MinZ = box.Z - box.SizeZ / 2,
		MaxZ = box.Z + box.SizeZ / 2,
	}
end

----------------------------------------------------------------
-- Boxes
----------------------------------------------------------------

-- A solid box standing on the floor.
local function standing(name: string, role: string, x: number, z: number, size: { number }): Box
	return {
		Name = name,
		Role = role,
		X = x,
		Y = size[2] / 2,
		Z = z,
		SizeX = size[1],
		SizeY = size[2],
		SizeZ = size[3],
		Solid = true,
		Transparency = 0,
	}
end

-- A slab drawn flat over `rect`, sunk into the floor with its top face at `top`.
local function flat(name: string, role: string, rect: Rect, top: number, dressing: Dressing): Box
	return {
		Name = name,
		Role = role,
		X = (rect.MinX + rect.MaxX) / 2,
		Y = top - dressing.FlatThickness / 2,
		Z = (rect.MinZ + rect.MaxZ) / 2,
		SizeX = rect.MaxX - rect.MinX,
		SizeY = dressing.FlatThickness,
		SizeZ = rect.MaxZ - rect.MinZ,
		Solid = false,
		Transparency = 0,
	}
end

-- The ink rule along the top of a standing box, as on an arena wall: a hair wider on each widened axis and
-- raised by as much, because a face coplanar with the box's own flickers.
local function rule(under: Box, role: string, widen: { X: boolean, Z: boolean }, dressing: Dressing): Box
	local proud = dressing.WallRuleProudStuds
	local height = dressing.WallRuleStuds
	return {
		Name = under.Name .. "Rule",
		Role = role,
		X = under.X,
		Y = under.Y + under.SizeY / 2 - height / 2 + proud,
		Z = under.Z,
		SizeX = under.SizeX + if widen.X then proud else 0,
		SizeY = height,
		SizeZ = under.SizeZ + if widen.Z then proud else 0,
		Solid = false,
		Transparency = 0,
	}
end

-- The floor, its four walls and their rules. The north and south walls run the full outer length and the
-- west and east ones fit between them, so no two solids share a corner.
local function addEnclosure(boxes: { Box }, map: MapDef, dressing: Dressing)
	local size, thickness, height = map.Size, map.WallThickness, map.WallHeight
	table.insert(boxes, {
		Name = dressing.FloorName,
		Role = "Floor",
		X = 0,
		Y = -map.FloorThickness / 2,
		Z = 0,
		SizeX = size,
		SizeY = map.FloorThickness,
		SizeZ = size,
		Solid = true,
		Transparency = 0,
	})
	local offset = size / 2 + thickness / 2
	local along = { size + thickness * 2, height, thickness }
	local across = { thickness, height, size }
	local walls = {
		standing("WallNorth", "Wall", 0, -offset, along),
		standing("WallSouth", "Wall", 0, offset, along),
		standing("WallWest", "Wall", -offset, 0, across),
		standing("WallEast", "Wall", offset, 0, across),
	}
	for _, wall in ipairs(walls) do
		table.insert(boxes, wall)
		local thinX = wall.SizeX < wall.SizeZ
		table.insert(boxes, rule(wall, "WallRule", { X = thinX, Z = not thinX }, dressing))
	end
end

-- The ruling of the page, the camp's wash and the ink line at its edge: all flat.
local function addDrawing(boxes: { Box }, map: MapDef, dressing: Dressing)
	local half = map.Size / 2 - map.RuleInsetStuds
	local width = map.RuleWidthStuds
	local reach = half + width / 2
	local lines = {
		{
			Name = "RuleNorth",
			Rect = { MinX = -reach, MaxX = reach, MinZ = -half - width / 2, MaxZ = -half + width / 2 },
		},
		{
			Name = "RuleSouth",
			Rect = { MinX = -reach, MaxX = reach, MinZ = half - width / 2, MaxZ = half + width / 2 },
		},
		{
			Name = "RuleWest",
			Rect = { MinX = -half - width / 2, MaxX = -half + width / 2, MinZ = -reach, MaxZ = reach },
		},
		{ Name = "RuleEast", Rect = { MinX = half - width / 2, MaxX = half + width / 2, MinZ = -reach, MaxZ = reach } },
	}
	for _, line in ipairs(lines) do
		table.insert(boxes, flat(line.Name, "Rule", line.Rect, dressing.RuleTop, dressing))
	end
	local camp = map.Camp
	local wash = flat("Camp", "Camp", camp, dressing.CampTop, dressing)
	wash.Transparency = dressing.CampTransparency
	table.insert(boxes, wash)
	local edge = { MinX = camp.MaxX - width / 2, MaxX = camp.MaxX + width / 2, MinZ = camp.MinZ, MaxZ = camp.MaxZ }
	table.insert(boxes, flat("CampLine", "CampLine", edge, dressing.RuleTop, dressing))
end

-- The pillars on their ring, the stele at the centre (each capped by a rule) and the cover.
local function addFurniture(boxes: { Box }, map: MapDef, dressing: Dressing)
	local pillars = map.Pillars
	local both = { X = true, Z = true }
	for index = 1, pillars.Count do
		local angle = math.rad(pillars.AngleOffsetDegrees + (index - 1) * 360 / pillars.Count)
		local pillar = standing(
			"Pillar" .. index,
			"Pillar",
			math.cos(angle) * pillars.Radius,
			math.sin(angle) * pillars.Radius,
			pillars.Size
		)
		table.insert(boxes, pillar)
		table.insert(boxes, rule(pillar, "PillarRule", both, dressing))
	end
	local stele = standing("Stele", "Stele", 0, 0, map.Stele.Size)
	table.insert(boxes, stele)
	table.insert(boxes, rule(stele, "SteleRule", both, dressing))
	for _, cover in ipairs(map.Covers) do
		table.insert(
			boxes,
			standing(cover.Name, "Cover", cover.X, cover.Z, { cover.SizeX, map.CoverHeight, cover.SizeZ })
		)
	end
end

local function killZone(map: MapDef, dressing: Dressing): Box
	local span = map.Size * map.KillZoneSpread
	return {
		Name = dressing.KillZoneName,
		Role = "KillZone",
		X = 0,
		Y = map.KillZoneDepth,
		Z = 0,
		SizeX = span,
		SizeY = map.KillZoneThickness,
		SizeZ = span,
		Solid = false,
		Transparency = 1,
	}
end

----------------------------------------------------------------
-- Straight lines
----------------------------------------------------------------

-- Narrows [enter, leave], the share of a segment that lies inside one axis's open slab (low, high). A
-- segment that misses the slab comes back with enter >= leave.
local function clip(
	from: number,
	delta: number,
	low: number,
	high: number,
	enter: number,
	leave: number
): (number, number)
	if math.abs(delta) < EPSILON then
		if from <= low or from >= high then
			return 1, 0
		end
		return enter, leave
	end
	local t1, t2 = (low - from) / delta, (high - from) / delta
	return math.max(enter, math.min(t1, t2)), math.min(leave, math.max(t1, t2))
end

-- Whether the segment a -> b passes through the rectangle's interior (the slab test). One that only touches
-- its edge or a corner does not: the rectangles are already grown by the path radius, and a goal pushed out
-- of the camp lands exactly on the grown camp's edge (clampOutOfCamp), where a Forger must still be able to
-- walk. Called for every waypoint and every rectangle, so it allocates nothing.
local function segmentMeets(rect: Rect, ax: number, az: number, bx: number, bz: number): boolean
	local enter, leave = clip(ax, bx - ax, rect.MinX, rect.MaxX, 0, 1)
	if enter >= leave then
		return false
	end
	enter, leave = clip(az, bz - az, rect.MinZ, rect.MaxZ, enter, leave)
	return enter < leave
end

-- Whether a Forger can walk straight from a to b: the segment crosses no obstacle and not the camp, both
-- grown by the Forger's path radius.
function BattlegroundLayout.segmentClear(layout: Layout, ax: number, az: number, bx: number, bz: number): boolean
	for _, rect in ipairs(layout.Blocked) do
		if segmentMeets(rect, ax, az, bx, bz) then
			return false
		end
	end
	return true
end

----------------------------------------------------------------
-- Waypoints
----------------------------------------------------------------

local function blocked(rects: { Rect }, x: number, z: number): boolean
	for _, rect in ipairs(rects) do
		if BattlegroundLayout.inRect(rect, x, z) then
			return true
		end
	end
	return false
end

-- A node every StepStuds inside Size / 2 - MarginStuds, row by row, minus those in a blocked rectangle; each
-- joined to its eight neighbours when the straight walk between them is clear.
local function addGraph(layout: Layout, map: MapDef)
	local step = map.Grid.StepStuds
	local limit = map.Size / 2 - map.Grid.MarginStuds
	local count = math.floor(2 * limit / step) + 1
	local at: { [number]: { [number]: number } } = {}
	for row = 1, count do
		at[row] = {}
		for column = 1, count do
			local x, z = -limit + (column - 1) * step, -limit + (row - 1) * step
			if not blocked(layout.Blocked, x, z) then
				table.insert(layout.Nodes, { X = x, Z = z })
				at[row][column] = #layout.Nodes
			end
		end
	end
	for row = 1, count do
		for column = 1, count do
			local index = at[row][column]
			if index ~= nil then
				local node = layout.Nodes[index]
				local edges: { number } = {}
				for dRow = -1, 1 do
					for dColumn = -1, 1 do
						local neighbour = if at[row + dRow] ~= nil then at[row + dRow][column + dColumn] else nil
						if neighbour ~= nil and neighbour ~= index then
							local other = layout.Nodes[neighbour]
							if BattlegroundLayout.segmentClear(layout, node.X, node.Z, other.X, other.Z) then
								table.insert(edges, neighbour)
							end
						end
					end
				end
				layout.Edges[index] = edges
			end
		end
	end
end

function BattlegroundLayout.build(map: MapDef, dressing: Dressing, pathRadius: number): Layout
	local boxes: { Box } = {}
	addEnclosure(boxes, map, dressing)
	addDrawing(boxes, map, dressing)
	addFurniture(boxes, map, dressing)
	table.insert(boxes, killZone(map, dressing))

	local half = map.Size / 2
	local layout: Layout = {
		Boxes = boxes,
		Arrivals = map.Arrivals,
		BotSpawns = map.BotSpawns,
		ReturnGate = map.ReturnGate,
		Camp = map.Camp,
		Bounds = { MinX = -half, MaxX = half, MinZ = -half, MaxZ = half },
		Obstacles = {},
		Blocked = { BattlegroundLayout.inflate(map.Camp, pathRadius) },
		Nodes = {},
		Edges = {},
		PathRadius = pathRadius,
	}
	for _, box in ipairs(boxes) do
		if box.Solid and box.Role ~= "Floor" and box.Role ~= "Wall" then
			local rect = footprint(box)
			table.insert(layout.Obstacles, rect)
			table.insert(layout.Blocked, BattlegroundLayout.inflate(rect, pathRadius))
		end
	end
	addGraph(layout, map)
	return layout
end

-- The node a Forger at (x, z) should head for first: the nearest one it can walk to straight, or the nearest
-- of all when none can be reached straight. Ties go to the lower index. nil only for a graph with no node.
function BattlegroundLayout.nearestNode(layout: Layout, x: number, z: number): number?
	local best: number?, bestDistance = nil, math.huge
	local fallback: number?, fallbackDistance = nil, math.huge
	for index, node in ipairs(layout.Nodes) do
		local distance = (node.X - x) ^ 2 + (node.Z - z) ^ 2
		if distance < fallbackDistance then
			fallback, fallbackDistance = index, distance
		end
		if distance < bestDistance and BattlegroundLayout.segmentClear(layout, x, z, node.X, node.Z) then
			best, bestDistance = index, distance
		end
	end
	return best or fallback
end

-- The octile distance: exact on an eight-way grid with nothing in the way, never more than the real path.
local function octile(a: Point, b: Point): number
	local dx, dz = math.abs(a.X - b.X), math.abs(a.Z - b.Z)
	return math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)
end

-- The open node with the lowest estimate; ties to the lower index, so the same graph always gives the same path.
local function cheapest(open: { [number]: boolean }, estimate: { [number]: number }): number
	local best, bestScore = math.huge, math.huge
	for index in pairs(open) do
		local score = estimate[index]
		if score < bestScore or (score == bestScore and index < best) then
			best, bestScore = index, score
		end
	end
	return best
end

-- The shortest walk from node `from` to node `to` over the graph (A*), both ends included; nil when `to`
-- cannot be reached.
function BattlegroundLayout.path(layout: Layout, from: number, to: number): { number }?
	local nodes = layout.Nodes
	local goal = nodes[to]
	if nodes[from] == nil or goal == nil then
		return nil
	end
	local walked: { [number]: number } = { [from] = 0 }
	local estimate: { [number]: number } = { [from] = octile(nodes[from], goal) }
	local cameFrom: { [number]: number } = {}
	local open: { [number]: boolean } = { [from] = true }
	local openCount = 1
	while openCount > 0 do
		local current = cheapest(open, estimate)
		if current == to then
			local route = { to }
			while cameFrom[route[1]] ~= nil do
				table.insert(route, 1, cameFrom[route[1]])
			end
			return route
		end
		open[current] = nil
		openCount -= 1
		local here = nodes[current]
		for _, neighbour in ipairs(layout.Edges[current]) do
			local there = nodes[neighbour]
			local cost = walked[current] + math.sqrt((there.X - here.X) ^ 2 + (there.Z - here.Z) ^ 2)
			if walked[neighbour] == nil or cost < walked[neighbour] then
				walked[neighbour] = cost
				estimate[neighbour] = cost + octile(there, goal)
				cameFrom[neighbour] = current
				if not open[neighbour] then
					open[neighbour] = true
					openCount += 1
				end
			end
		end
	end
	return nil
end

-- A goal inside the camp (grown by the path radius) pushed out across its nearest edge that is not against a
-- wall; any other point is returned as it is. A Forger never walks into the camp, whatever it chases.
function BattlegroundLayout.clampOutOfCamp(layout: Layout, x: number, z: number): (number, number)
	local camp = BattlegroundLayout.inflate(layout.Camp, layout.PathRadius)
	if not BattlegroundLayout.inRect(camp, x, z) then
		return x, z
	end
	local bestX, bestZ, bestShift = x, z, math.huge
	for _, exit in ipairs({ { camp.MaxX, z }, { camp.MinX, z }, { x, camp.MinZ }, { x, camp.MaxZ } }) do
		local ex, ez = exit[1], exit[2]
		local shift = math.abs(ex - x) + math.abs(ez - z)
		if shift < bestShift and BattlegroundLayout.inRect(layout.Bounds, ex, ez) then
			bestX, bestZ, bestShift = ex, ez, shift
		end
	end
	return bestX, bestZ
end

return BattlegroundLayout
