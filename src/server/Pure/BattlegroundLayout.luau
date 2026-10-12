--!strict
-- The Battleground's geometry (D-131, D-282), derived from BattlegroundConfig.Map: every part the map builder makes,
-- the points players land on and Forgers appear at, the ground prints a Forger walks around, and the waypoint graph
-- it finds its way on. Pure module: no require, no Roblox global. The shapes it takes are re-declared here, and
-- every number arrives through the caller, so tests/BattlegroundLayout.spec.luau holds the page to its claims --
-- every part on it, no narrow corridor, every path clear -- without an engine.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A part turned by Yaw degrees is turned
-- about +y as the engine turns it (CFrame.Angles(0, rad(Yaw), 0)): its own +x points along (cos, -sin) and its own
-- +z along (sin, cos). A part tipped by Pitch degrees is then turned about its own x, round its centre
-- (* CFrame.Angles(rad(Pitch), 0, 0)): a positive Pitch raises its own -z end. Everything a Forger decides happens on
-- the ground plane (x, z); heights only matter to the parts.

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
	Pitch: number?,
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
export type Book = {
	Name: string,
	X: number,
	Z: number,
	PageWidth: number,
	Length: number,
	Valley: number,
	Profile: { number },
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
	Dais: { Size: number, Height: number, Stairs: { Width: number, Rise: number, Tread: number } },
	CoverHeight: number,
	Covers: { Cover },
	Pieces: { Piece },
	Books: { Book },
	Quill: {
		X: number,
		Z: number,
		Yaw: number,
		Width: number,
		RailStuds: number,
		Steps: number,
		Rise: number,
		Tread: number,
		Landing: number,
		TipLength: number,
	},
	Crater: {
		X: number,
		Z: number,
		OuterRadius: number,
		RimStuds: number,
		Height: number,
		Segments: number,
		BreachSegments: number,
	},
	Arcade: {
		X: number,
		Z: number,
		Yaw: number,
		Arches: number,
		Pier: number,
		Opening: number,
		Thickness: number,
		Height: number,
		Beam: number,
		Corbel: { Width: number, Height: number },
	},
	Bed: { Points: { Point }, Width: number, BankStuds: number, Lines: number },
	Marks: { Mark },
	BotSpawns: { Point },
	Grid: { StepStuds: number, MarginStuds: number },
	Skin: {
		Out: number,
		Top: number,
		Seal: { Diameter: number, Height: number },
		BlotStuds: number,
		Wall: { Length: number, Thickness: number },
	},
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
	-- Tipped about its own x after its Yaw, nil for level.
	Pitch: number?,
	Solid: boolean,
	Transparency: number,
}

-- A landmark's skin (D-283): the meshes tools/meshes/page/ draws over its boxes, as one placement -- a pivot in the
-- local frame, a turn about the vertical and a scale per axis of the meshes' own studs. Boxes are the solids it hides
-- (they still collide), Marks the ink drawn on the page it replaces; each mesh is a MeshConfig key, Tone its colour
-- (WorldConfig.Battleground.Skin<Tone>).
export type SkinMesh = { Mesh: string, Tone: string }
export type Skin = {
	Name: string,
	Boxes: { string },
	Marks: { string },
	Meshes: { SkinMesh },
	X: number,
	Y: number,
	Z: number,
	Yaw: number,
	Scale: { number },
}

-- A part's print on the ground, or one grown by the path radius: its centre, its half extents along its own axes,
-- and the cosine and sine of its turn.
export type Print = { X: number, Z: number, HalfX: number, HalfZ: number, Cos: number, Sin: number }
-- Ground a body walks on above the floor: a print and the height of its top.
export type Ground = { Print: Print, Top: number }

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
	-- The obstacles, the camp and the raised place's sheer sides, each grown by PathRadius: where no waypoint lies
	-- and no straight walk crosses.
	Blocked: { Print },
	-- The raised place and its steps (BattlegroundLayout.groundAt).
	Ground: { Ground },
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
	-- A tipped part reaches further along its own z than it is long: its height leans out over the ground too.
	local pitch = math.rad(box.Pitch or 0)
	return {
		X = box.X,
		Z = box.Z,
		HalfX = box.SizeX / 2,
		HalfZ = box.SizeZ / 2 * math.cos(pitch) + box.SizeY / 2 * math.abs(math.sin(pitch)),
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

-- The ruled bed: a band Width wide along each leg of Points, its banks and Lines ink lines along it, and a disc
-- at each bend that rounds it off.
local function addBed(boxes: { Box }, map: MapDef, dressing: Dressing)
	local bed = map.Bed
	local gap = bed.Width / (bed.Lines + 1)
	for leg = 1, #bed.Points - 1 do
		local a, b = bed.Points[leg], bed.Points[leg + 1]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local length = math.sqrt(dx * dx + dz * dz)
		-- Turned so that its own x runs along the leg, its own z across it.
		local yaw = math.deg(math.atan2(-dz, dx))
		local acrossX, acrossZ = -dz / length, dx / length
		local mx, mz = (a.X + b.X) / 2, (a.Z + b.Z) / 2
		table.insert(
			boxes,
			drawn("Bed" .. leg, "Bed", "Block", mx, mz, length, bed.Width, dressing.CampTop, yaw, dressing)
		)
		for line = 0, bed.Lines + 1 do
			local bank = line == 0 or line == bed.Lines + 1
			local name = if bank then "BedBank" .. leg .. "_" .. line else "BedLine" .. leg .. "_" .. line
			local width = if bank then bed.BankStuds else map.RuleWidthStuds
			local off = -bed.Width / 2 + gap * line
			local x, z = mx + acrossX * off, mz + acrossZ * off
			table.insert(boxes, drawn(name, "Rule", "Block", x, z, length, width, dressing.RuleTop, yaw, dressing))
		end
	end
	for bend = 2, #bed.Points - 1 do
		local point = bed.Points[bend]
		table.insert(
			boxes,
			drawn(
				"BedBend" .. bend,
				"Bed",
				"Cylinder",
				point.X,
				point.Z,
				bed.Width,
				bed.Width,
				dressing.CampTop,
				0,
				dressing
			)
		)
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
	addBed(boxes, map, dressing)
	for _, mark in ipairs(map.Marks) do
		local top = mark.Base + dressing.RuleTop
		local role = if mark.Base == 0 then "Rule" else "Trim"
		table.insert(
			boxes,
			drawn(mark.Name, role, mark.Shape, mark.X, mark.Z, mark.SizeX, mark.SizeZ, top, mark.Yaw or 0, dressing)
		)
	end
end

-- The dais's four sides, each facing (X, Z) away from the centre.
local SIDES = {
	{ Name = "North", X = 0, Z = -1 },
	{ Name = "South", X = 0, Z = 1 },
	{ Name = "West", X = -1, Z = 0 },
	{ Name = "East", X = 1, Z = 0 },
}

-- The point `out` studs from the centre toward a side and `along` it.
local function onSide(side: { X: number, Z: number }, along: number, out: number): (number, number)
	return side.X * out + side.Z * along, side.Z * out + side.X * along
end

-- How many steps each flight has under the dais's own top.
local function stepCount(map: MapDef): number
	return math.round(map.Dais.Height / map.Dais.Stairs.Rise) - 1
end

-- The central place: the dais, a flight of steps down the middle of each side (the highest against the dais), its
-- ink edge drawn on its top, and the low walls standing on it.
local function addPlace(boxes: { Box }, map: MapDef, dressing: Dressing)
	local dais = map.Dais
	local stairs = dais.Stairs
	local half, width = dais.Size / 2, map.RuleWidthStuds
	table.insert(boxes, standing("Dais", "Dais", "Block", 0, 0, 0, { dais.Size, dais.Height, dais.Size }, 0))
	local steps = stepCount(map)
	for _, side in ipairs(SIDES) do
		for step = 1, steps do
			local x, z = onSide(side, 0, half + (steps - step + 0.5) * stairs.Tread)
			local sizeX = if side.X == 0 then stairs.Width else stairs.Tread
			local sizeZ = if side.X == 0 then stairs.Tread else stairs.Width
			local size = { sizeX, step * stairs.Rise, sizeZ }
			table.insert(boxes, standing("Stair" .. side.Name .. step, "Dais", "Block", x, z, 0, size, 0))
		end
	end
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

-- An open book: each half-page a hill from its outer edge to the spine through Profile, one stretch of the curve
-- per pair of heights -- a block as high as its lower end and a wedge on it up to its higher end -- and the valley
-- left open down the spine.
local function addBook(boxes: { Box }, book: Book)
	local run = book.PageWidth / (#book.Profile - 1)
	for _, half in ipairs({ { Name = "West", Sign = -1, Spine = 90 }, { Name = "East", Sign = 1, Spine = -90 } }) do
		for index = 1, #book.Profile - 1 do
			local outer, inner = book.Profile[index], book.Profile[index + 1]
			local x = book.X + half.Sign * (book.Valley / 2 + book.PageWidth - (index - 0.5) * run)
			local name = book.Name .. half.Name .. index
			local low = math.min(outer, inner)
			table.insert(
				boxes,
				standing(name .. "Base", "Landmark", "Block", x, book.Z, 0, { run, low, book.Length }, 0)
			)
			if inner ~= outer then
				-- Turned to rise toward the spine, or away from it where the page curls down into the valley.
				local yaw = if inner > outer then half.Spine else half.Spine + 180
				local size = { book.Length, math.abs(inner - outer), run }
				table.insert(boxes, standing(name .. "Slope", "Landmark", "Wedge", x, book.Z, low, size, yaw))
			end
		end
	end
end

-- The fallen quill: a flight of steps up its shaft from its foot along its yaw, a rail sloping as high on either
-- side, the landing at the top and the bevelled tip back down to the floor.
local function addQuill(boxes: { Box }, map: MapDef)
	local quill = map.Quill
	local yaw = math.rad(quill.Yaw)
	local function at(along: number, across: number): (number, number)
		return quill.X + math.sin(yaw) * along + math.cos(yaw) * across,
			quill.Z + math.cos(yaw) * along - math.sin(yaw) * across
	end
	local flight = quill.Steps * quill.Tread
	local top = quill.Steps * quill.Rise
	local stair = quill.Width - 2 * quill.RailStuds
	for step = 1, quill.Steps do
		local x, z = at((step - 0.5) * quill.Tread, 0)
		local size = { stair, step * quill.Rise, quill.Tread }
		table.insert(boxes, standing("QuillStep" .. step, "Landmark", "Block", x, z, 0, size, quill.Yaw))
	end
	for index, sign in ipairs({ -1, 1 }) do
		local x, z = at(flight / 2, sign * (stair + quill.RailStuds) / 2)
		local size = { quill.RailStuds, top, flight }
		table.insert(boxes, standing("QuillRail" .. index, "Landmark", "Wedge", x, z, 0, size, quill.Yaw))
	end
	local x, z = at(flight + quill.Landing / 2, 0)
	table.insert(
		boxes,
		standing("QuillLanding", "Landmark", "Block", x, z, 0, { quill.Width, top, quill.Landing }, quill.Yaw)
	)
	x, z = at(flight + quill.Landing + quill.TipLength / 2, 0)
	local tip = { quill.Width, top, quill.TipLength }
	table.insert(boxes, standing("QuillTip", "Landmark", "Wedge", x, z, 0, tip, quill.Yaw + 180))
end

-- The scriptorium's arcade: its piers along its yaw, one beam over them all, and a corbel in each upper corner of
-- every opening.
local function addArcade(boxes: { Box }, map: MapDef)
	local arcade = map.Arcade
	local yaw = math.rad(arcade.Yaw)
	local function at(along: number): (number, number)
		return arcade.X + math.cos(yaw) * along, arcade.Z - math.sin(yaw) * along
	end
	local bay = arcade.Pier + arcade.Opening
	local length = arcade.Arches * bay + arcade.Pier
	local pierHeight = arcade.Height - arcade.Beam
	for pier = 0, arcade.Arches do
		local x, z = at(-length / 2 + arcade.Pier / 2 + pier * bay)
		local size = { arcade.Pier, pierHeight, arcade.Thickness }
		table.insert(boxes, standing("ArcadePier" .. pier, "Landmark", "Block", x, z, 0, size, arcade.Yaw))
	end
	local x, z = at(0)
	local beam = { length, arcade.Beam, arcade.Thickness }
	table.insert(boxes, standing("ArcadeBeam", "Landmark", "Block", x, z, pierHeight, beam, arcade.Yaw))
	local corbel = arcade.Corbel
	for arch = 1, arcade.Arches do
		local opening = -length / 2 + arch * arcade.Pier + (arch - 1) * arcade.Opening
		for index, along in ipairs({ opening + corbel.Width / 2, opening + arcade.Opening - corbel.Width / 2 }) do
			x, z = at(along)
			local size = { corbel.Width, corbel.Height, arcade.Thickness }
			local base = pierHeight - corbel.Height
			table.insert(
				boxes,
				standing("ArcadeCorbel" .. arch .. "_" .. index, "Landmark", "Block", x, z, base, size, arcade.Yaw)
			)
		end
	end
end

-- The landmarks: the listed pieces, the books, the quill, the arcade and the crater's rim (a ring of blocks, each
-- turned along the ring, minus the four breaches).
local function addLandmarks(boxes: { Box }, map: MapDef)
	for _, piece in ipairs(map.Pieces) do
		local box =
			standing(piece.Name, "Landmark", piece.Shape, piece.X, piece.Z, piece.Base, piece.Size, piece.Yaw or 0)
		box.Pitch = piece.Pitch
		table.insert(boxes, box)
	end
	for _, book in ipairs(map.Books) do
		addBook(boxes, book)
	end
	addQuill(boxes, map)
	addArcade(boxes, map)
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

-- The raised place's sheer sides, as lines on the ground: its edge either side of each flight, and both sides of
-- every flight. Grown by the path radius, they leave a Forger the steps as its only way up or down.
local function ledges(map: MapDef): { Print }
	local half = map.Dais.Size / 2
	local span = map.Dais.Stairs.Width / 2
	local foot = half + stepCount(map) * map.Dais.Stairs.Tread
	local out: { Print } = {}
	for _, side in ipairs(SIDES) do
		for _, line in ipairs({
			{ -half, half, -span, half },
			{ span, half, half, half },
			{ -span, half, -span, foot },
			{ span, half, span, foot },
		}) do
			local ax, az = onSide(side, line[1], line[2])
			local bx, bz = onSide(side, line[3], line[4])
			local rect =
				{ MinX = math.min(ax, bx), MaxX = math.max(ax, bx), MinZ = math.min(az, bz), MaxZ = math.max(az, bz) }
			table.insert(out, rectPrint(rect))
		end
	end
	return out
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
		Blocked = { rectPrint(BattlegroundLayout.inflate(map.Camp, pathRadius)) },
		Ground = {},
		Nodes = {},
		Edges = {},
		PathRadius = pathRadius,
	}
	for _, box in ipairs(boxes) do
		if box.Solid and not GROUND[box.Role] then
			table.insert(layout.Blocked, BattlegroundLayout.grow(BattlegroundLayout.printOf(box), pathRadius))
		elseif box.Solid and box.Role ~= "Floor" then
			table.insert(layout.Ground, { Print = BattlegroundLayout.printOf(box), Top = box.Y + box.SizeY / 2 })
		end
	end
	for _, ledge in ipairs(ledges(map)) do
		table.insert(layout.Blocked, BattlegroundLayout.grow(ledge, pathRadius))
	end
	addGraph(layout, map)
	return layout
end

-- The height of the ground a body at (x, z) stands on: the top of the raised place or of the step under it, else
-- the floor's 0. What is high elsewhere -- a landmark -- is not ground: a Forger never stands on it.
function BattlegroundLayout.groundAt(layout: Layout, x: number, z: number): number
	local top = 0
	for _, ground in ipairs(layout.Ground) do
		if ground.Top > top and BattlegroundLayout.inPrint(ground.Print, x, z) then
			top = ground.Top
		end
	end
	return top
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

local FULL = { "Top", "Side", "Cover", "Ink" }
-- The torn edge's variants (tools/meshes/page/edge.py), one per tab in turn.
local EDGES = { "A", "B", "C" }

local function meshesOf(kind: string, tones: { string }): { SkinMesh }
	local out: { SkinMesh } = {}
	for _, tone in ipairs(tones) do
		table.insert(out, { Mesh = "Page" .. kind .. tone, Tone = tone })
	end
	return out
end

-- Where every landmark's skin goes, derived from the layout by the rule tools/meshes/page/ draws each mesh by: a
-- landmark drawn whole at layout size sits on its own centre on the floor; a kind drawn once (a seal, a desk, a wall)
-- sits on each box's base, scaled so its faces land Skin.Out outside the box's and its top Skin.Top over it, from
-- the size the mesh was drawn at -- Map.Skin's, or the first box of the kind's.
function BattlegroundLayout.skins(layout: Layout, map: MapDef): { Skin }
	local skin = map.Skin
	local boxes: { [string]: Box } = {}
	local names: { string } = {}
	for _, box in ipairs(layout.Boxes) do
		boxes[box.Name] = box
		table.insert(names, box.Name)
	end
	table.sort(names)
	local function chosen(keep: (string, Box) -> boolean): { string }
		local out: { string } = {}
		for _, name in ipairs(names) do
			if keep(name, boxes[name]) then
				table.insert(out, name)
			end
		end
		return out
	end
	local function prefixed(prefix: string): { string }
		return chosen(function(name)
			return string.sub(name, 1, #prefix) == prefix
		end)
	end
	local out: { Skin } = {}
	local function add(
		name: string,
		kind: string,
		tones: { string },
		covered: { string },
		marks: { string },
		x: number,
		y: number,
		z: number,
		yaw: number,
		scale: { number }
	)
		table.insert(out, {
			Name = name,
			Boxes = covered,
			Marks = marks,
			Meshes = meshesOf(kind, tones),
			X = x,
			Y = y,
			Z = z,
			Yaw = yaw,
			Scale = scale,
		})
	end
	local function base(box: Box): number
		return box.Y - box.SizeY / 2
	end
	-- Each box of a kind drawn once, at the size of `reference` (x, y, z studs), on its base and at its turn.
	local function scaled(kind: string, tones: { string }, kept: { string }, reference: { number })
		for _, name in ipairs(kept) do
			local box = boxes[name]
			add(name, kind, tones, { name }, {}, box.X, base(box), box.Z, box.Yaw, {
				(box.SizeX / 2 + skin.Out) / (reference[1] / 2 + skin.Out),
				(box.SizeY + skin.Top) / (reference[2] + skin.Top),
				(box.SizeZ / 2 + skin.Out) / (reference[3] / 2 + skin.Out),
			})
		end
	end
	local function sizeOf(name: string): { number }
		local box = boxes[name]
		return { box.SizeX, box.SizeY, box.SizeZ }
	end
	local ONE = { 1, 1, 1 }

	for _, book in ipairs(map.Books) do
		local halves = chosen(function(name)
			return string.sub(name, 1, #book.Name + 4) == book.Name .. "West"
				or string.sub(name, 1, #book.Name + 4) == book.Name .. "East"
		end)
		add(book.Name, book.Name, FULL, halves, { book.Name .. "Spine" }, book.X, 0, book.Z, 0, ONE)
	end

	local quill = map.Quill
	add("FallenQuill", "Quill", FULL, prefixed("Quill"), {}, quill.X, 0, quill.Z, quill.Yaw, ONE)

	-- The cliffs in two skins over one pivot: the rock and its boulders, and the books stacked and leaning on it.
	local rock = boxes.FolioRock
	local cliffs = chosen(function(name)
		return string.sub(name, 1, 5) == "Folio"
			and string.sub(name, 1, 10) ~= "FolioLoose"
			and string.sub(name, 1, 9) ~= "FolioRock"
	end)
	add("FolioRock", "FolioRock", { "Top", "Side", "Ink" }, prefixed("FolioRock"), {}, rock.X, 0, rock.Z, 0, ONE)
	add("FolioCliffs", "Folio", FULL, cliffs, {}, rock.X, 0, rock.Z, 0, ONE)
	local loose = prefixed("FolioLoose")
	scaled("LooseBook", { "Top", "Cover", "Ink" }, loose, sizeOf(loose[1]))

	-- The rim is drawn as one arc of kept blocks; a quarter turn of -90 degrees puts it on the next.
	local crater = map.Crater
	local quarter = crater.Segments // 4
	for q = 0, 3 do
		local arc = chosen(function(name)
			local index = tonumber(string.match(name, "^CraterRim(%d+)$"))
			return index ~= nil and index // quarter == q
		end)
		add("CraterArc" .. q, "CraterArc", FULL, arc, {}, crater.X, 0, crater.Z, -90 * q, ONE)
	end
	add("CraterPool", "CraterPool", { "Cover", "Ink" }, {}, {}, crater.X, 0, crater.Z, 0, ONE)

	local seal = { skin.Seal.Diameter, skin.Seal.Height, skin.Seal.Diameter }
	local function isSeal(name: string, stacked: boolean): boolean
		return string.sub(name, 1, 4) == "Seal" and (string.sub(name, -3) == "Top") == stacked
	end
	scaled(
		"Seal",
		FULL,
		chosen(function(name)
			return isSeal(name, false)
		end),
		seal
	)
	scaled(
		"SealStacked",
		FULL,
		chosen(function(name)
			return isSeal(name, true)
		end),
		seal
	)
	for _, name in ipairs(prefixed("Blot")) do
		local blot = boxes[name]
		local size = blot.SizeX / skin.BlotStuds
		add(name, "Blot", { "Ink" }, {}, { name }, blot.X, 0, blot.Z, 0, { size, 1, size })
	end

	local arcade = map.Arcade
	add("Arcade", "Arcade", FULL, prefixed("Arcade"), {}, arcade.X, 0, arcade.Z, arcade.Yaw, ONE)
	local function desks(shape: Shape): { string }
		return chosen(function(name, box)
			return string.sub(name, 1, 4) == "Desk" and string.sub(name, 1, 9) ~= "DeskStump" and box.Shape == shape
		end)
	end
	local desk, tipped, stumps = desks("Block"), desks("Wedge"), prefixed("DeskStump")
	scaled("Desk", FULL, desk, sizeOf(desk[1]))
	scaled("Tipped", FULL, tipped, sizeOf(tipped[1]))
	scaled("Stump", { "Top", "Side", "Ink" }, stumps, sizeOf(stumps[1]))

	local deck = boxes.BridgeDeck
	add(
		"StitchBridge",
		"Bridge",
		{ "Top", "Cover", "Ink" },
		prefixed("Bridge"),
		prefixed("Stitch"),
		deck.X,
		0,
		deck.Z,
		0,
		ONE
	)

	-- The torn edge: every tab of the deckle keeps its box (the page's floor, drawn) under a torn lip and the paper's
	-- cliff, a kind drawn once in EDGES variants for a tab torn 0 in -- the whole band -- and taken in turn, so no two
	-- tabs side by side look alike. Its pivot is on the band's inner edge, turned to face out, its depth scaled to
	-- the tab's so the cliff stands Skin.Out outside it.
	local band = map.Deckle.BandStuds
	local inner = map.Size / 2 - band
	for _, name in ipairs(prefixed("Deckle")) do
		local tab = boxes[name]
		local x, z, yaw, along, depth = tab.X, -inner, 0, tab.SizeX, tab.SizeZ
		if tab.Z > inner then
			z, yaw = inner, 180
		elseif tab.X < -inner then
			x, z, yaw, along, depth = -inner, tab.Z, 90, tab.SizeZ, tab.SizeX
		elseif tab.X > inner then
			x, z, yaw, along, depth = inner, tab.Z, -90, tab.SizeZ, tab.SizeX
		end
		local variant = EDGES[tonumber(string.sub(name, 7)) :: number % #EDGES + 1]
		add(name, "Edge" .. variant, { "Body", "Side", "Ink" }, {}, {}, x, 0, z, yaw, {
			(along / 2 + skin.Out) / (map.Deckle.SlotStuds / 2 + skin.Out),
			1,
			(depth + skin.Out) / (band + skin.Out),
		})
	end

	local stairs = prefixed("Stair")
	table.insert(stairs, 1, "Dais")
	add("Dais", "Dais", { "Top", "Side", "Body", "Ink" }, stairs, prefixed("DaisEdge"), 0, 0, 0, 0, ONE)
	-- One wall drawn along x; a wall running along z is turned a quarter.
	local walls = chosen(function(name)
		return string.sub(name, 1, 5) == "Cover" or string.sub(name, 1, 7) == "Parapet"
	end)
	for _, name in ipairs(walls) do
		local wall = boxes[name]
		local alongZ = wall.SizeZ > wall.SizeX
		local length = if alongZ then wall.SizeZ else wall.SizeX
		local thickness = if alongZ then wall.SizeX else wall.SizeZ
		add(
			name,
			"Wall",
			{ "Top", "Side", "Ink" },
			{ name },
			{},
			wall.X,
			base(wall),
			wall.Z,
			if alongZ then 90 else 0,
			{
				(length / 2 + skin.Out) / (skin.Wall.Length / 2 + skin.Out),
				1,
				(thickness / 2 + skin.Out) / (skin.Wall.Thickness / 2 + skin.Out),
			}
		)
	end
	return out
end

return BattlegroundLayout
