--!strict
-- The Flyleaf's geometry (E16-S2), derived from FlyleafConfig.Map: every box the map builder turns into a part,
-- the six seals members arrive on, and the gate home. Pure module: no require, no Roblox global. The shapes it
-- takes are re-declared here and every number arrives through the caller, so tests/Flyleaf.spec.luau holds the
-- page to its claims -- every seal on the floor, clear of the cover and of the circle home -- without an engine.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }

-- The fields of FlyleafConfig.Map this module reads.
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
	ReturnGate: Point,
	SealRadiusStuds: number,
	SealCount: number,
	CoverHeight: number,
	Covers: { Cover },
}

-- What the page is dressed with from outside FlyleafConfig.Map: the names its readers find the floor and the
-- kill plane by, the wall rule every arena draws (WorldConfig.Arena), the ladder's rule rung and the flat slabs'
-- thickness (WorldConfig).
export type Dressing = {
	FloorName: string,
	KillZoneName: string,
	WallRuleStuds: number,
	WallRuleProudStuds: number,
	FlatThickness: number,
	RuleTop: number,
}

-- One part: its centre and size in the local frame. Role is a key of WorldConfig.Flyleaf, the colour the builder
-- paints it. A solid box collides; the rest is drawn on the page and touches nothing.
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
}

export type Layout = {
	Boxes: { Box },
	Seals: { Point },
	ReturnGate: Point,
	-- The floor's rectangle, inside the walls.
	Bounds: Rect,
	-- Every solid box standing on the floor (not the floor, not a wall), as its footprint.
	Obstacles: { Rect },
}

local FlyleafLayout = {}

function FlyleafLayout.inRect(rect: Rect, x: number, z: number): boolean
	return x >= rect.MinX and x <= rect.MaxX and z >= rect.MinZ and z <= rect.MaxZ
end

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
	}
end

-- The ink rule along the top of a standing box, a hair wider and higher than it: coplanar faces flicker.
local function rule(under: Box, dressing: Dressing): Box
	local proud = dressing.WallRuleProudStuds
	local height = dressing.WallRuleStuds
	return {
		Name = under.Name .. "Rule",
		Role = "Rule",
		X = under.X,
		Y = under.Y + under.SizeY / 2 - height / 2 + proud,
		Z = under.Z,
		SizeX = under.SizeX + proud,
		SizeY = height,
		SizeZ = under.SizeZ + proud,
		Solid = false,
	}
end

local function flat(name: string, rect: Rect, dressing: Dressing): Box
	return {
		Name = name,
		Role = "Rule",
		X = (rect.MinX + rect.MaxX) / 2,
		Y = dressing.RuleTop - dressing.FlatThickness / 2,
		Z = (rect.MinZ + rect.MaxZ) / 2,
		SizeX = rect.MaxX - rect.MinX,
		SizeY = dressing.FlatThickness,
		SizeZ = rect.MaxZ - rect.MinZ,
		Solid = false,
	}
end

-- The floor and its four walls, each capped by a rule. North and south run the full outer length and west and east
-- fit between them, so no two solids share a corner.
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
	})
	local offset = size / 2 + thickness / 2
	local along = { size + thickness * 2, height, thickness }
	local across = { thickness, height, size }
	for _, wall in ipairs({
		standing("WallNorth", "Wall", 0, -offset, along),
		standing("WallSouth", "Wall", 0, offset, along),
		standing("WallWest", "Wall", -offset, 0, across),
		standing("WallEast", "Wall", offset, 0, across),
	}) do
		table.insert(boxes, wall)
		table.insert(boxes, rule(wall, dressing))
	end
end

-- The ruling of the page, as on the hub: four ink lines, inset from the walls.
local function addRuling(boxes: { Box }, map: MapDef, dressing: Dressing)
	local half = map.Size / 2 - map.RuleInsetStuds
	local width = map.RuleWidthStuds
	local reach = half + width / 2
	table.insert(
		boxes,
		flat("RuleNorth", { MinX = -reach, MaxX = reach, MinZ = -half - width / 2, MaxZ = -half + width / 2 }, dressing)
	)
	table.insert(
		boxes,
		flat("RuleSouth", { MinX = -reach, MaxX = reach, MinZ = half - width / 2, MaxZ = half + width / 2 }, dressing)
	)
	table.insert(
		boxes,
		flat("RuleWest", { MinX = -half - width / 2, MaxX = -half + width / 2, MinZ = -reach, MaxZ = reach }, dressing)
	)
	table.insert(
		boxes,
		flat("RuleEast", { MinX = half - width / 2, MaxX = half + width / 2, MinZ = -reach, MaxZ = reach }, dressing)
	)
end

-- The seals: SealCount points on a ring of SealRadiusStuds, the first due east, then a turn apart.
function FlyleafLayout.seals(map: MapDef): { Point }
	local points: { Point } = {}
	for index = 1, map.SealCount do
		local angle = (index - 1) * 2 * math.pi / map.SealCount
		table.insert(points, { X = math.cos(angle) * map.SealRadiusStuds, Z = math.sin(angle) * map.SealRadiusStuds })
	end
	return points
end

function FlyleafLayout.build(map: MapDef, dressing: Dressing): Layout
	local boxes: { Box } = {}
	addEnclosure(boxes, map, dressing)
	addRuling(boxes, map, dressing)
	local obstacles: { Rect } = {}
	for _, cover in ipairs(map.Covers) do
		local box = standing(cover.Name, "Cover", cover.X, cover.Z, { cover.SizeX, map.CoverHeight, cover.SizeZ })
		table.insert(boxes, box)
		table.insert(boxes, rule(box, dressing))
		table.insert(obstacles, {
			MinX = box.X - box.SizeX / 2,
			MaxX = box.X + box.SizeX / 2,
			MinZ = box.Z - box.SizeZ / 2,
			MaxZ = box.Z + box.SizeZ / 2,
		})
	end
	local span = map.Size * map.KillZoneSpread
	table.insert(boxes, {
		Name = dressing.KillZoneName,
		Role = "KillZone",
		X = 0,
		Y = map.KillZoneDepth,
		Z = 0,
		SizeX = span,
		SizeY = map.KillZoneThickness,
		SizeZ = span,
		Solid = false,
	})
	local half = map.Size / 2
	return {
		Boxes = boxes,
		Seals = FlyleafLayout.seals(map),
		ReturnGate = map.ReturnGate,
		Bounds = { MinX = -half, MaxX = half, MinZ = -half, MaxZ = half },
		Obstacles = obstacles,
	}
end

return FlyleafLayout
