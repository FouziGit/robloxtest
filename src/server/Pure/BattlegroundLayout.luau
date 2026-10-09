--!strict
-- The Battleground's geometry (D-131, D-282), derived from BattlegroundConfig.Map: every part the map builder makes,
-- the points players land on and Forgers appear at, the ground prints a Forger walks around, and the waypoint graph
-- it finds its way on. Pure module: no require, no Roblox global. The shapes it takes are re-declared here, and
-- every number arrives through the caller, so tests/BattlegroundLayout.spec.luau holds the page to its claims --
-- every part on it, no narrow corridor, every path clear -- without an engine.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A part turned by Yaw degrees is turned
-- about +y as the engine turns it (CFrame.Angles(0, rad(Yaw), 0)): its own +x points along (cos, -sin) and its own
-- +z along (sin, cos). Everything a Forger decides happens on the ground plane (x, z); heights only matter to the
-- parts.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Shape = "Block" | "Wedge" | "Cylinder"
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }
export type Piece = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	Size: { number },
	Yaw: number?,
}
export type Mark = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	SizeX: number,
	SizeZ: number,
	Yaw: number?,
}

-- The fields of BattlegroundConfig.Map this module reads.
export type MapDef = {
	Size: number,
	FloorThickness: number,
	KillZoneDepth: number,
	KillZoneSpread: number,
	KillZoneThickness: number,
	Deckle: { BandStuds: number, SlotStuds: number, Tears: { number } },
	RuleSpacingStuds: number,
	RuleWidthStuds: number,
	MarginX: number,
	Camp: Rect,
	ReturnGate: Point,
	Arrivals: { Point },
	Dais: { Size: number, Height: number },
	CoverHeight: number,
	Covers: { Cover },
	Pieces: { Piece },
	Plume: { X: number, Z: number, Yaw: number, Length: number, TipLength: number, Width: number, Height: number },
	Crater: {
		X: number,
		Z: number,
		OuterRadius: number,
		RimStuds: number,
		Height: number,
		Segments: number,
		BreachSegments: number,
	},
	Bed: { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Lines: number },
	Marks: { Mark },
	BotSpawns: { Point },
	Grid: { StepStuds: number, MarginStuds: number },
}

-- What the page is dressed with, from outside BattlegroundConfig.Map: the names its readers find the floor and the
-- kill plane by (BattlegroundConfig.Anchors), the ladder's rungs and the flat slabs' thickness (WorldConfig), and
-- the camp's wash (WorldConfig.Battleground).
export type Dressing = {
	FloorName: string,
	KillZoneName: string,
	FlatThickness: number,
	RuleTop: number,
	CampTop: number,
	CampTransparency: number,
}

-- One part: its centre, size and turn in the local frame. Role is a key of WorldConfig.Battleground, the colour the
-- builder paints it. A solid part collides and blocks sight; the rest is drawn on the page.
export type Box = {
	Name: string,
	Role: string,
	Shape: Shape,
	X: number,
	Y: number,
	Z: number,
	SizeX: number,
	SizeY: number,
	SizeZ: number,
	Yaw: number,
	Solid: boolean,
	Transparency: number,
}

-- A part's print on the ground, or one grown by the path radius: its centre, its half extents along its own axes,
-- and the cosine and sine of its turn.
export type Print = { X: number, Z: number, HalfX: number, HalfZ: number, Cos: number, Sin: number }

export type Layout = {
	Boxes: { Box },
	Arrivals: { Point },
	BotSpawns: { Point },
	ReturnGate: Point,
	Camp: Rect,
	-- The page's square, torn edge included.
	Bounds: Rect,
	-- The square the waypoints cover: a Forger's goal is never past it.
	Roam: Rect,
	-- Every solid part that stands in a Forger's way (not the floor, not the dais), as its print.
	Obstacles: { Print },
	-- The obstacles and the camp, each grown by PathRadius: where no waypoint lies and no straight walk crosses.
	Blocked: { Print },
	Nodes: { Point },
	-- Edges[i]: the nodes a Forger can walk to straight from node i.
	Edges: { { number } },
	PathRadius: number,
}

local BattlegroundLayout = {}

local SQRT2 = math.sqrt(2)
-- Below this a segment has no extent along an axis, and only its position on that axis decides a hit.
local EPSILON = 1e-9
-- The solid parts a body walks on rather than around.
local GROUND = { Floor = true, Dais = true }

function BattlegroundLayout.inRect(rect: Rect, x: number, z: number): boolean
	return x >= rect.MinX and x <= rect.MaxX and z >= rect.MinZ and z <= rect.MaxZ
end

function BattlegroundLayout.inflate(rect: Rect, by: number): Rect
	return { MinX = rect.MinX - by, MaxX = rect.MaxX + by, MinZ = rect.MinZ - by, MaxZ = rect.MaxZ + by }
end

----------------------------------------------------------------
-- Prints
----------------------------------------------------------------

function BattlegroundLayout.printOf(box: Box): Print
	local yaw = math.rad(box.Yaw)
	return {
		X = box.X,
		Z = box.Z,
		HalfX = box.SizeX / 2,
		HalfZ = box.SizeZ / 2,
		Cos = math.cos(yaw),
		Sin = math.sin(yaw),
	}
end

function BattlegroundLayout.grow(print: Print, by: number): Print
	return {
		X = print.X,
		Z = print.Z,
		HalfX = print.HalfX + by,
		HalfZ = print.HalfZ + by,
		Cos = print.Cos,
		Sin = print.Sin,
	}
end

local function rectPrint(rect: Rect): Print
	return {
		X = (rect.MinX + rect.MaxX) / 2,
		Z = (rect.MinZ + rect.MaxZ) / 2,
		HalfX = (rect.MaxX - rect.MinX) / 2,
		HalfZ = (rect.MaxZ - rect.MinZ) / 2,
		Cos = 1,
		Sin = 0,
	}
end

-- A ground point in the print's own axes.
local function toPrint(print: Print, x: number, z: number): (number, number)
	local dx, dz = x - print.X, z - print.Z
	return dx * print.Cos - dz * print.Sin, dx * print.Sin + dz * print.Cos
end

function BattlegroundLayout.inPrint(print: Print, x: number, z: number): boolean
	local lx, lz = toPrint(print, x, z)
	return math.abs(lx) <= print.HalfX and math.abs(lz) <= print.HalfZ
end

-- The print's four corners on the ground.
function BattlegroundLayout.corners(print: Print): { Point }
	local out: { Point } = {}
	for _, sign in ipairs({ { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }) do
		local lx, lz = sign[1] * print.HalfX, sign[2] * print.HalfZ
		table.insert(
			out,
			{ X = print.X + lx * print.Cos + lz * print.Sin, Z = print.Z - lx * print.Sin + lz * print.Cos }
		)
	end
	return out
end

----------------------------------------------------------------
-- Boxes
----------------------------------------------------------------

-- A solid part standing with its underside `base` studs above the floor.
local function standing(
	name: string,
	role: string,
	shape: Shape,
	x: number,
	z: number,
	base: number,
	size: { number },
	yaw: number
): Box
	return {
		Name = name,
		Role = role,
		Shape = shape,
		X = x,
		Y = base + size[2] / 2,
		Z = z,
		SizeX = size[1],
		SizeY = size[2],
		SizeZ = size[3],
		Yaw = yaw,
		Solid = true,
		Transparency = 0,
	}
end

-- A slab drawn flat, sunk into whatever it lies on, its top face at `top`.
local function drawn(
	name: string,
	role: string,
	shape: Shape,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	top: number,
	yaw: number,
	dressing: Dressing
): Box
	return {
		Name = name,
		Role = role,
		Shape = shape,
		X = x,
		Y = top - dressing.FlatThickness / 2,
		Z = z,
		SizeX = sizeX,
		SizeY = dressing.FlatThickness,
		SizeZ = sizeZ,
		Yaw = yaw,
		Solid = false,
		Transparency = 0,
	}
end

local function flat(name: string, role: string, rect: Rect, top: number, dressing: Dressing): Box
	return drawn(
		name,
		role,
		"Block",
		(rect.MinX + rect.MaxX) / 2,
		(rect.MinZ + rect.MaxZ) / 2,
		rect.MaxX - rect.MinX,
		rect.MaxZ - rect.MinZ,
		top,
		0,
		dressing
	)
end

-- A piece of the floor, its top face at y = 0.
local function slab(name: string, x: number, z: number, sizeX: number, sizeZ: number, map: MapDef): Box
	return standing(name, "Floor", "Block", x, z, -map.FloorThickness, { sizeX, map.FloorThickness, sizeZ }, 0)
end

-- The floor inside the band, and the band cut in tabs, each torn in from the edge by the next of Tears: north and
-- south run the page's full width, west and east fit between them, so no two tabs overlap.
local function addFloor(boxes: { Box }, map: MapDef, dressing: Dressing)
	local deckle = map.Deckle
	local half, band, slot = map.Size / 2, deckle.BandStuds, deckle.SlotStuds
	table.insert(boxes, slab(dressing.FloorName, 0, 0, map.Size - 2 * band, map.Size - 2 * band, map))
	local count = 0
	local function tab(sideways: boolean, along: number, sign: number)
		local tear = deckle.Tears[count % #deckle.Tears + 1]
		count += 1
		local across = sign * (half - (band + tear) / 2)
		local depth = band - tear
		if sideways then
			table.insert(boxes, slab("Deckle" .. count, across, along, depth, slot, map))
		else
			table.insert(boxes, slab("Deckle" .. count, along, across, slot, depth, map))
		end
	end
	for along = -half + slot / 2, half, slot do
		tab(false, along, -1)
		tab(false, along, 1)
	end
	for along = -half + band + slot / 2, half - band, slot do
		tab(true, along, -1)
		tab(true, along, 1)
	end
end

-- The ruling (a line along x every RuleSpacingStuds, the margin along z), the camp's wash and the ink line at its
-- edge, the ruled bed and its lines: all flat on the floor.
local function addDrawing(boxes: { Box }, map: MapDef, dressing: Dressing)
	local inner = map.Size / 2 - map.Deckle.BandStuds
	local width = map.RuleWidthStuds
	local count = 0
	for z = -inner + map.RuleSpacingStuds, inner - map.RuleSpacingStuds / 2, map.RuleSpacingStuds do
		count += 1
		local line = { MinX = -inner, MaxX = inner, MinZ = z - width / 2, MaxZ = z + width / 2 }
		table.insert(boxes, flat("Rule" .. count, "Rule", line, dressing.RuleTop, dressing))
	end
	local margin = { MinX = map.MarginX - width / 2, MaxX = map.MarginX + width / 2, MinZ = -inner, MaxZ = inner }
	table.insert(boxes, flat("Margin", "Rule", margin, dressing.RuleTop, dressing))
	local camp = map.Camp
	local wash = flat("Camp", "Camp", camp, dressing.CampTop, dressing)
	wash.Transparency = dressing.CampTransparency
	table.insert(boxes, wash)
	local edge = { MinX = camp.MaxX - width / 2, MaxX = camp.MaxX + width / 2, MinZ = camp.MinZ, MaxZ = camp.MaxZ }
	table.insert(boxes, flat("CampLine", "CampLine", edge, dressing.RuleTop, dressing))
	local bed = map.Bed
	table.insert(
		boxes,
		flat(
			"Bed",
			"Bed",
			{ MinX = bed.MinX, MaxX = bed.MaxX, MinZ = bed.MinZ, MaxZ = bed.MaxZ },
			dressing.CampTop,
			dressing
		)
	)
	local gap = (bed.MaxX - bed.MinX) / (bed.Lines + 1)
	for line = 1, bed.Lines do
		local x = bed.MinX + gap * line
		local rect = { MinX = x - width / 2, MaxX = x + width / 2, MinZ = bed.MinZ, MaxZ = bed.MaxZ }
		table.insert(boxes, flat("BedLine" .. line, "Rule", rect, dressing.RuleTop, dressing))
	end
	for _, mark in ipairs(map.Marks) do
		local top = mark.Base + dressing.RuleTop
		local role = if mark.Base == 0 then "Rule" else "Trim"
		table.insert(
			boxes,
			drawn(mark.Name, role, mark.Shape, mark.X, mark.Z, mark.SizeX, mark.SizeZ, top, mark.Yaw or 0, dressing)
		)
	end
end

-- The central place: the dais, its ink edge drawn on its top, and the low walls standing on it.
local function addPlace(boxes: { Box }, map: MapDef, dressing: Dressing)
	local dais = map.Dais
	local half, width = dais.Size / 2, map.RuleWidthStuds
	table.insert(boxes, standing("Dais", "Dais", "Block", 0, 0, 0, { dais.Size, dais.Height, dais.Size }, 0))
	local top = dais.Height + dressing.RuleTop
	for _, edge in ipairs({
		{ Name = "DaisEdgeNorth", Rect = { MinX = -half, MaxX = half, MinZ = -half, MaxZ = -half + width } },
		{ Name = "DaisEdgeSouth", Rect = { MinX = -half, MaxX = half, MinZ = half - width, MaxZ = half } },
		{ Name = "DaisEdgeWest", Rect = { MinX = -half, MaxX = -half + width, MinZ = -half, MaxZ = half } },
		{ Name = "DaisEdgeEast", Rect = { MinX = half - width, MaxX = half, MinZ = -half, MaxZ = half } },
	}) do
		table.insert(boxes, flat(edge.Name, "Trim", edge.Rect, top, dressing))
	end
	for _, cover in ipairs(map.Covers) do
		local size = { cover.SizeX, map.CoverHeight, cover.SizeZ }
		table.insert(boxes, standing(cover.Name, "Cover", "Block", cover.X, cover.Z, dais.Height, size, 0))
	end
end

-- The landmarks: the listed pieces, the quill (a rising stem and its bevelled tip, end to end along its yaw) and the
-- crater's rim (a ring of blocks, each turned along the ring, minus the four breaches).
local function addLandmarks(boxes: { Box }, map: MapDef)
	for _, piece in ipairs(map.Pieces) do
		table.insert(
			boxes,
			standing(piece.Name, "Landmark", piece.Shape, piece.X, piece.Z, piece.Base, piece.Size, piece.Yaw or 0)
		)
	end
	local plume = map.Plume
	local yaw = math.rad(plume.Yaw)
	local dx, dz = math.sin(yaw), math.cos(yaw)
	local stem = plume.Length - plume.TipLength
	local stemAt = -plume.Length / 2 + stem / 2
	local tipAt = plume.Length / 2 - plume.TipLength / 2
	local stemSize = { plume.Width, plume.Height, stem }
	local tipSize = { plume.Width, plume.Height, plume.TipLength }
	table.insert(
		boxes,
		standing("PlumeStem", "Landmark", "Wedge", plume.X + dx * stemAt, plume.Z + dz * stemAt, 0, stemSize, plume.Yaw)
	)
	table.insert(
		boxes,
		standing(
			"PlumeTip",
			"Landmark",
			"Wedge",
			plume.X + dx * tipAt,
			plume.Z + dz * tipAt,
			0,
			tipSize,
			plume.Yaw + 180
		)
	)
	local crater = map.Crater
	local step = 360 / crater.Segments
	local quarter = crater.Segments / 4
	local middle = crater.OuterRadius - crater.RimStuds / 2
	local length = 2 * crater.OuterRadius * math.sin(math.rad(step / 2))
	for index = 0, crater.Segments - 1 do
		local fromAxis = index % quarter
		local breach = fromAxis < crater.BreachSegments / 2 or fromAxis >= quarter - crater.BreachSegments / 2
		if not breach then
			local angle = (index + 0.5) * step
			local x = crater.X + math.cos(math.rad(angle)) * middle
			local z = crater.Z + math.sin(math.rad(angle)) * middle
			local size = { crater.RimStuds, crater.Height, length }
			table.insert(boxes, standing("CraterRim" .. index, "Landmark", "Block", x, z, 0, size, -angle))
		end
	end
end

local function killZone(map: MapDef, dressing: Dressing): Box
	local span = map.Size * map.KillZoneSpread
	return {
		Name = dressing.KillZoneName,
		Role = "KillZone",
		Shape = "Block",
		X = 0,
		Y = map.KillZoneDepth,
		Z = 0,
		SizeX = span,
		SizeY = map.KillZoneThickness,
		SizeZ = span,
		Yaw = 0,
		Solid = false,
		Transparency = 1,
	}
end

----------------------------------------------------------------
-- Straight lines
----------------------------------------------------------------

-- Narrows [enter, leave], the share of a segment that lies inside one axis's open slab (low, high). A segment that
-- misses the slab comes back with enter >= leave.
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

-- Whether the segment a -> b passes through the print's interior (the slab test, in the print's own axes). One that
-- only touches its edge or a corner does not: the prints are already grown by the path radius, and a goal pushed
-- out of the camp lands exactly on the grown camp's edge (clampGoal), where a Forger must still be able to walk.
-- Called for every waypoint and every print, so it allocates nothing.
local function segmentMeets(print: Print, ax: number, az: number, bx: number, bz: number): boolean
	local alx, alz = toPrint(print, ax, az)
	local blx, blz = toPrint(print, bx, bz)
	local enter, leave = clip(alx, blx - alx, -print.HalfX, print.HalfX, 0, 1)
	if enter >= leave then
		return false
	end
	enter, leave = clip(alz, blz - alz, -print.HalfZ, print.HalfZ, enter, leave)
	return enter < leave
end

-- Whether a Forger can walk straight from a to b: the segment crosses no obstacle and not the camp, both grown by
-- the Forger's path radius.
function BattlegroundLayout.segmentClear(layout: Layout, ax: number, az: number, bx: number, bz: number): boolean
	for _, print in ipairs(layout.Blocked) do
		if segmentMeets(print, ax, az, bx, bz) then
			return false
		end
	end
	return true
end

----------------------------------------------------------------
-- Waypoints
----------------------------------------------------------------

local function blocked(prints: { Print }, x: number, z: number): boolean
	for _, print in ipairs(prints) do
		if BattlegroundLayout.inPrint(print, x, z) then
			return true
		end
	end
	return false
end

-- A node every StepStuds inside Size / 2 - MarginStuds, row by row, minus those in a blocked print; each joined to
-- its eight neighbours when the straight walk between them is clear.
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
	addFloor(boxes, map, dressing)
	addDrawing(boxes, map, dressing)
	addPlace(boxes, map, dressing)
	addLandmarks(boxes, map)
	table.insert(boxes, killZone(map, dressing))

	local half = map.Size / 2
	local roam = half - map.Grid.MarginStuds
	local layout: Layout = {
		Boxes = boxes,
		Arrivals = map.Arrivals,
		BotSpawns = map.BotSpawns,
		ReturnGate = map.ReturnGate,
		Camp = map.Camp,
		Bounds = { MinX = -half, MaxX = half, MinZ = -half, MaxZ = half },
		Roam = { MinX = -roam, MaxX = roam, MinZ = -roam, MaxZ = roam },
		Obstacles = {},
		Blocked = { rectPrint(BattlegroundLayout.inflate(map.Camp, pathRadius)) },
		Nodes = {},
		Edges = {},
		PathRadius = pathRadius,
	}
	for _, box in ipairs(boxes) do
		if box.Solid and not GROUND[box.Role] then
			local print = BattlegroundLayout.printOf(box)
			table.insert(layout.Obstacles, print)
			table.insert(layout.Blocked, BattlegroundLayout.grow(print, pathRadius))
		end
	end
	addGraph(layout, map)
	return layout
end

-- The node a Forger at (x, z) should head for first: the nearest one it can walk to straight, or the nearest of all
-- when none can be reached straight. Ties go to the lower index. nil only for a graph with no node.
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

-- The shortest walk from node `from` to node `to` over the graph (A*), both ends included; nil when `to` cannot be
-- reached.
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

-- Where a Forger chasing (x, z) walks to: the point brought inside the roam, then, inside the camp grown by the
-- path radius, pushed out across its nearest edge that stays in the roam. A Forger never walks into the camp nor
-- toward the torn edge, whatever it chases.
function BattlegroundLayout.clampGoal(layout: Layout, x: number, z: number): (number, number)
	local roam = layout.Roam
	x = math.clamp(x, roam.MinX, roam.MaxX)
	z = math.clamp(z, roam.MinZ, roam.MaxZ)
	local camp = BattlegroundLayout.inflate(layout.Camp, layout.PathRadius)
	if not BattlegroundLayout.inRect(camp, x, z) then
		return x, z
	end
	local bestX, bestZ, bestShift = x, z, math.huge
	for _, exit in ipairs({ { camp.MaxX, z }, { camp.MinX, z }, { x, camp.MinZ }, { x, camp.MaxZ } }) do
		local ex, ez = exit[1], exit[2]
		local shift = math.abs(ex - x) + math.abs(ez - z)
		if shift < bestShift and BattlegroundLayout.inRect(roam, ex, ez) then
			bestX, bestZ, bestShift = ex, ez, shift
		end
	end
	return bestX, bestZ
end

return BattlegroundLayout
