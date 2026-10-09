--!strict
-- The Battleground's page (D-131, D-282), held to what its config claims: 700 studs, every part on it and within the
-- part budget, nothing solid in the camp, on an arrival or on top of another solid, no corridor narrower than 16
-- studs, every arrival apart from every other and from the Forgers' spawns, a waypoint graph that is whole -- the
-- crater and the book's valley included -- and whose paths are clear and shortest, and a page that stands out of
-- the hub's sight and out of its packets' reach.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/server/Pure/BattlegroundLayout")
local BotConfig = require("../src/shared/Config/BotConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Gate = require("./gate")
local Harness = require("./harness")
local LightingConfig = require("../src/shared/Config/LightingConfig")
local PortalConfig = require("../src/shared/Config/PortalConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MAP = BattlegroundConfig.Map
local DRESSING: BattlegroundLayout.Dressing = {
	FloorName = BattlegroundConfig.Anchors.Floor,
	KillZoneName = BattlegroundConfig.Anchors.KillZone,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}
local LAYOUT = BattlegroundLayout.build(MAP, DRESSING, BotConfig.Path.RadiusStuds)
-- Every solid part that stands in a Forger's way (not the floor, not the dais), as its print.
local OBSTACLES: { BattlegroundLayout.Print } = {}
for _, box in ipairs(LAYOUT.Boxes) do
	if box.Solid and box.Role ~= "Floor" and box.Role ~= "Dais" then
		table.insert(OBSTACLES, BattlegroundLayout.printOf(box))
	end
end
-- The engine's default gravity, which the place keeps (tests/LockOn.spec.luau).
local GRAVITY = 196.2
local EPSILON = 1e-6
local HUB = "src/server/Services/HubService.luau"
-- What World/PortalGate builds of the gate home: two discs, two posts, the lintel, the panel, the sign, the seal.
local GATE_PARTS = 8
-- The narrowest way between two pieces on the ground (D-282).
local CORRIDOR_STUDS = 16

-- The print's four corners on the ground.
local function corners(print: BattlegroundLayout.Print): { BattlegroundLayout.Point }
	local out: { BattlegroundLayout.Point } = {}
	for _, sign in ipairs({ { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }) do
		local lx, lz = sign[1] * print.HalfX, sign[2] * print.HalfZ
		table.insert(
			out,
			{ X = print.X + lx * print.Cos + lz * print.Sin, Z = print.Z - lx * print.Sin + lz * print.Cos }
		)
	end
	return out
end

local function overlaps(a: BattlegroundLayout.Box, b: BattlegroundLayout.Box): boolean
	for _, axis in ipairs({ { "X", "SizeX" }, { "Y", "SizeY" }, { "Z", "SizeZ" } }) do
		local centre, size = axis[1], axis[2]
		local gap = math.abs((a :: any)[centre] - (b :: any)[centre])
		if gap >= ((a :: any)[size] + (b :: any)[size]) / 2 - EPSILON then
			return false
		end
	end
	return true
end

local function blocked(x: number, z: number): boolean
	for _, print in ipairs(LAYOUT.Blocked) do
		if BattlegroundLayout.inPrint(print, x, z) then
			return true
		end
	end
	return false
end

local function distance(a: BattlegroundLayout.Point, b: BattlegroundLayout.Point): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

-- The distance from p to the segment a -> b.
local function toSegment(p: BattlegroundLayout.Point, a: BattlegroundLayout.Point, b: BattlegroundLayout.Point): number
	local dx, dz = b.X - a.X, b.Z - a.Z
	local t = math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / (dx * dx + dz * dz), 0, 1)
	return distance(p, { X = a.X + t * dx, Z = a.Z + t * dz })
end

-- The gap between two prints on the ground: 0 when they touch or overlap, else the shortest distance between them.
local function gap(a: BattlegroundLayout.Print, b: BattlegroundLayout.Print): number
	local ca, cb = corners(a), corners(b)
	for _, corner in ipairs(ca) do
		if BattlegroundLayout.inPrint(b, corner.X, corner.Z) then
			return 0
		end
	end
	for _, corner in ipairs(cb) do
		if BattlegroundLayout.inPrint(a, corner.X, corner.Z) then
			return 0
		end
	end
	local shortest = math.huge
	for index = 1, 4 do
		local a1, a2 = ca[index], ca[index % 4 + 1]
		local b1, b2 = cb[index], cb[index % 4 + 1]
		for _, corner in ipairs(cb) do
			shortest = math.min(shortest, toSegment(corner, a1, a2))
		end
		for _, corner in ipairs(ca) do
			shortest = math.min(shortest, toSegment(corner, b1, b2))
		end
	end
	return shortest
end

-- A number from HubService, which needs an engine to require.
local function hubNumber(name: string): number
	local value = string.match(fs.readFile(HUB), "\nlocal " .. name .. " = (%d+)\n")
	if value == nil then
		error(("%s has no numeric %s: this gate would check nothing"):format(HUB, name))
	end
	return tonumber(value) :: number
end

-- The shortest walk over the graph by Dijkstra, independent of the A* under test.
local function shortest(from: number, to: number): number
	local best: { [number]: number } = { [from] = 0 }
	local done: { [number]: boolean } = {}
	while true do
		local current, currentCost = nil, math.huge
		for index, cost in pairs(best) do
			if not done[index] and cost < currentCost then
				current, currentCost = index, cost
			end
		end
		if current == nil then
			return math.huge
		end
		if current == to then
			return currentCost
		end
		done[current] = true
		for _, neighbour in ipairs(LAYOUT.Edges[current]) do
			local cost = currentCost + distance(LAYOUT.Nodes[current], LAYOUT.Nodes[neighbour])
			if best[neighbour] == nil or cost < best[neighbour] then
				best[neighbour] = cost
			end
		end
	end
end

-- The arrivals in the camp, and the others.
local function arrivals(): ({ BattlegroundLayout.Point }, { BattlegroundLayout.Point })
	local camp, edge = {}, {}
	for _, arrival in ipairs(LAYOUT.Arrivals) do
		table.insert(if BattlegroundLayout.inRect(LAYOUT.Camp, arrival.X, arrival.Z) then camp else edge, arrival)
	end
	return camp, edge
end

describe("the Battleground's parts", function()
	it("make a 700-stud page, every one of them on it, the whole map within the part budget", function()
		expect(MAP.Size).toBe(700)
		local half = MAP.Size / 2
		local top = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Role ~= "KillZone" then
				for _, corner in ipairs(corners(BattlegroundLayout.printOf(box))) do
					if math.abs(corner.X) > half + EPSILON or math.abs(corner.Z) > half + EPSILON then
						error(("%s leaves the page"):format(box.Name))
					end
				end
				expect(box.Y - box.SizeY / 2).toBeGreaterThanOrEqual(-MAP.FloorThickness - EPSILON)
				top = math.max(top, box.Y + box.SizeY / 2)
			end
		end
		local parts = #LAYOUT.Boxes + #LAYOUT.Arrivals + #LAYOUT.BotSpawns + GATE_PARTS
		expect(parts).toBeLessThanOrEqual(MAP.PartBudget)
		-- The highest landing is the cliffs' 60 studs.
		expect(top).toBe(60)
		for _, tear in ipairs(MAP.Deckle.Tears) do
			expect(tear).toBeGreaterThanOrEqual(0)
			expect(tear).toBeLessThan(MAP.Deckle.BandStuds)
		end
	end)

	it("draw everything flat on a rung of the ladder, sunk into the floor", function()
		local rungs = {
			Rule = WorldConfig.Ladder.Rule,
			CampLine = WorldConfig.Ladder.Rule,
			Camp = WorldConfig.Ladder.Training,
			Bed = WorldConfig.Ladder.Training,
		}
		local count = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			local rung = rungs[box.Role]
			if rung ~= nil then
				count += 1
				expect(box.Y + box.SizeY / 2).toBeCloseTo(rung, 9)
				expect(box.Y - box.SizeY / 2).toBeLessThan(0)
				expect(box.Solid).toBe(false)
			end
			-- Ink drawn on a raised top touches nothing either.
			if box.Role == "Trim" then
				expect(box.Solid).toBe(false)
			end
		end
		expect(count).toBeGreaterThan(30)
	end)

	it("never put one unturned solid inside another", function()
		local solids: { BattlegroundLayout.Box } = {}
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Solid and box.Yaw == 0 then
				table.insert(solids, box)
			end
		end
		for first = 1, #solids do
			for second = first + 1, #solids do
				if overlaps(solids[first], solids[second]) then
					error(("%s overlaps %s"):format(solids[first].Name, solids[second].Name))
				end
			end
		end
	end)

	it("leave no corridor narrower than 16 studs between two pieces on the ground", function()
		-- Pieces that touch are one mass (a ring, a stack, an arch); a corridor is the way between two masses.
		local obstacles = OBSTACLES
		expect(#obstacles).toBeGreaterThan(50)
		local gaps: { { number } } = {}
		local mass: { number } = {}
		for first = 1, #obstacles do
			gaps[first] = {}
			for second = 1, #obstacles do
				gaps[first][second] = if first == second then 0 else gap(obstacles[first], obstacles[second])
			end
		end
		for start = 1, #obstacles do
			if mass[start] == nil then
				mass[start] = start
				local queue = { start }
				while #queue > 0 do
					local current = table.remove(queue) :: number
					for other = 1, #obstacles do
						if mass[other] == nil and gaps[current][other] <= EPSILON then
							mass[other] = start
							table.insert(queue, other)
						end
					end
				end
			end
		end
		for first = 1, #obstacles do
			for second = first + 1, #obstacles do
				local apart = gaps[first][second]
				if mass[first] ~= mass[second] and apart < CORRIDOR_STUDS then
					local a, b = obstacles[first], obstacles[second]
					error(
						("a %.1f-stud corridor between the pieces at (%d, %d) and (%d, %d)"):format(
							apart,
							a.X,
							a.Z,
							b.X,
							b.Z
						)
					)
				end
			end
		end
	end)

	it("leave the camp free of anything solid", function()
		local camp = BattlegroundLayout.inflate(LAYOUT.Camp, 0)
		for _, obstacle in ipairs(OBSTACLES) do
			for _, corner in ipairs(corners(obstacle)) do
				expect(BattlegroundLayout.inRect(camp, corner.X, corner.Z)).toBe(false)
			end
		end
	end)

	it("are each painted a role the world has", function()
		for _, box in ipairs(LAYOUT.Boxes) do
			local role = (WorldConfig.Battleground :: any)[box.Role]
			if type(role) ~= "string" or WorldConfig.Colors[role] == nil then
				error(("%s is drawn as %s, which WorldConfig.Battleground does not paint"):format(box.Name, box.Role))
			end
		end
	end)

	it("hold a member jumping off the highest landing on the page", function()
		local movement = GameConfig.Movement
		local reach = (movement.JumpPower ^ 2 + movement.DoubleJumpVelocity ^ 2) / (2 * GRAVITY)
		local highest = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Solid then
				highest = math.max(highest, box.Y + box.SizeY / 2)
			end
		end
		expect(BattlegroundConfig.BoundsHeightStuds).toBeGreaterThan(
			highest + BattlegroundConfig.StandingRootStuds + reach
		)
		-- The low walls on the dais hide a Forger's quarry, standing on the dais or not.
		expect(MAP.CoverHeight).toBeGreaterThan(BattlegroundConfig.StandingRootStuds + BotConfig.Reach.SightHeightStuds)
	end)
end)

-- The solid parts whose names start with `prefix`: the bounds of their prints on the ground, their highest top, and
-- how many there are.
local function landmark(prefix: string): (BattlegroundLayout.Rect, number, number)
	local bounds = { MinX = math.huge, MaxX = -math.huge, MinZ = math.huge, MaxZ = -math.huge }
	local top, count = 0, 0
	for _, box in ipairs(LAYOUT.Boxes) do
		if box.Solid and string.sub(box.Name, 1, #prefix) == prefix then
			count += 1
			top = math.max(top, box.Y + box.SizeY / 2)
			for _, corner in ipairs(corners(BattlegroundLayout.printOf(box))) do
				bounds.MinX = math.min(bounds.MinX, corner.X)
				bounds.MaxX = math.max(bounds.MaxX, corner.X)
				bounds.MinZ = math.min(bounds.MinZ, corner.Z)
				bounds.MaxZ = math.max(bounds.MaxZ, corner.Z)
			end
		end
	end
	return bounds, top, count
end

local function named(name: string): BattlegroundLayout.Box
	for _, box in ipairs(LAYOUT.Boxes) do
		if box.Name == name then
			return box
		end
	end
	error(("the page has no part called %s"):format(name))
end

-- The tallest step a body climbs walking: the old dais's one stud, which the Forgers walked onto.
local STEP_STUDS = 1

describe("the landmarks, at the references' proportions (D-282)", function()
	it("raise the central place 6 to 8 studs over about 200, a flight of steps down each of its four sides", function()
		local dais = named("Dais")
		expect(dais.SizeX).toBeGreaterThanOrEqual(190)
		expect(dais.SizeX).toBeLessThanOrEqual(210)
		local height = dais.Y + dais.SizeY / 2
		expect(height).toBeGreaterThanOrEqual(6)
		expect(height).toBeLessThanOrEqual(8)
		expect(BattlegroundLayout.groundAt(LAYOUT, 0, 0)).toBe(height)
		-- From the centre out along each axis, the ground comes down a step at a time to the floor.
		for _, way in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local last = height
			for out = 0, dais.SizeX / 2 + 40, 0.25 do
				local here = BattlegroundLayout.groundAt(LAYOUT, way[1] * out, way[2] * out)
				expect(here).toBeLessThanOrEqual(last + EPSILON)
				expect(last - here).toBeLessThanOrEqual(STEP_STUDS + EPSILON)
				last = here
			end
			expect(last).toBe(0)
		end
		-- Anywhere else round it, the side drops sheer.
		local corner = dais.SizeX / 2 - 10
		expect(BattlegroundLayout.groundAt(LAYOUT, corner, -dais.SizeX / 2 + 0.5)).toBe(height)
		expect(BattlegroundLayout.groundAt(LAYOUT, corner, -dais.SizeX / 2 - 0.5)).toBe(0)
	end)

	it("let a Forger onto the place only up its steps, from anywhere on the page", function()
		local reach = named("Dais").SizeX / 2 + 40
		local raised = 0
		for index, node in ipairs(LAYOUT.Nodes) do
			if math.abs(node.X) <= reach and math.abs(node.Z) <= reach then
				if BattlegroundLayout.groundAt(LAYOUT, node.X, node.Z) > 0 then
					raised += 1
				end
				for _, neighbour in ipairs(LAYOUT.Edges[index]) do
					local other = LAYOUT.Nodes[neighbour]
					local last = BattlegroundLayout.groundAt(LAYOUT, node.X, node.Z)
					for sample = 1, 100 do
						local t = sample / 100
						local here = BattlegroundLayout.groundAt(
							LAYOUT,
							node.X + (other.X - node.X) * t,
							node.Z + (other.Z - node.Z) * t
						)
						if math.abs(here - last) > STEP_STUDS + EPSILON then
							error(
								("the walk from (%d, %d) to (%d, %d) climbs a sheer side"):format(
									node.X,
									node.Z,
									other.X,
									other.Z
								)
							)
						end
						last = here
					end
				end
			end
		end
		expect(raised).toBeGreaterThan(50)
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			local from = BattlegroundLayout.nearestNode(LAYOUT, spawn.X, spawn.Z) :: number
			expect(BattlegroundLayout.path(LAYOUT, from, BattlegroundLayout.nearestNode(LAYOUT, 0, 0) :: number)).never.toBe(
				nil
			)
		end
	end)

	it("keep the place's sheer sides 16 studs from anything standing on the floor", function()
		local raised: { BattlegroundLayout.Print } = {}
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Role == "Dais" then
				table.insert(raised, BattlegroundLayout.printOf(box))
			end
		end
		expect(#raised).toBeGreaterThan(4)
		for _, obstacle in ipairs(OBSTACLES) do
			local onIt = BattlegroundLayout.groundAt(LAYOUT, obstacle.X, obstacle.Z) > 0
			if not onIt then
				for _, ground in ipairs(raised) do
					expect(gap(obstacle, ground)).toBeGreaterThanOrEqual(CORRIDOR_STUDS)
				end
			end
		end
	end)

	it("open a book of about 200 by 140 north-west, two curved page hills either side of a walkable valley", function()
		local bounds, top = landmark("OpenBook")
		expect(bounds.MaxX - bounds.MinX).toBeGreaterThanOrEqual(180)
		expect(bounds.MaxZ - bounds.MinZ).toBeGreaterThanOrEqual(120)
		expect(top).toBeGreaterThanOrEqual(15)
		expect((bounds.MinX + bounds.MaxX) / 2).toBeLessThan(-100)
		expect((bounds.MinZ + bounds.MaxZ) / 2).toBeLessThan(-100)
		-- Each hill curves: several slopes, not three blocky steps.
		for _, half in ipairs({ "OpenBookWest", "OpenBookEast" }) do
			local slopes = 0
			for _, box in ipairs(LAYOUT.Boxes) do
				if box.Shape == "Wedge" and string.sub(box.Name, 1, #half) == half then
					slopes += 1
				end
			end
			expect(slopes).toBeGreaterThanOrEqual(4)
		end
		local book = MAP.Books[1]
		expect(BattlegroundLayout.segmentClear(LAYOUT, book.X, bounds.MinZ - 5, book.X, bounds.MaxZ + 5)).toBe(true)
	end)

	it("lean the quill north, about 200 long, a staircase up its shaft to 60 studs or more", function()
		local bounds, top, steps = landmark("QuillStep")
		expect(steps).toBeGreaterThanOrEqual(20)
		local whole, wholeTop = landmark("Quill")
		expect(math.max(whole.MaxX - whole.MinX, whole.MaxZ - whole.MinZ)).toBeGreaterThanOrEqual(180)
		expect(top).toBeGreaterThanOrEqual(60)
		expect(wholeTop).toBeLessThanOrEqual(70)
		expect(bounds.MaxZ).toBeLessThan(-100)
		local last = 0
		for step = 1, steps do
			local box = named("QuillStep" .. step)
			local rise = box.Y + box.SizeY / 2 - last
			expect(rise).toBeGreaterThan(0)
			expect(rise).toBeLessThanOrEqual(2)
			last += rise
		end
	end)

	it("pile the folio cliffs in the north-east corner, tier on tier up to 60 studs", function()
		local bounds, top = landmark("Folio")
		expect(bounds.MaxX - bounds.MinX).toBeGreaterThanOrEqual(180)
		expect(bounds.MaxZ - bounds.MinZ).toBeGreaterThanOrEqual(180)
		expect(bounds.MaxX).toBeGreaterThanOrEqual(MAP.Size / 2 - 20)
		expect(bounds.MinZ).toBeLessThanOrEqual(-MAP.Size / 2 + 20)
		expect(top).toBe(60)
		local tiers: { [number]: boolean } = {}
		for _, box in ipairs(LAYOUT.Boxes) do
			if string.sub(box.Name, 1, 5) == "Folio" and box.Shape == "Block" and box.Yaw == 0 then
				tiers[box.Y + box.SizeY / 2] = true
			end
		end
		for _, tier in ipairs({ 15, 30, 45, 60 }) do
			expect(tiers[tier]).toBe(true)
		end
	end)

	it("ring the crater with a raised, breached rim about 140 across, its floor the page's own", function()
		local bounds, top = landmark("CraterRim")
		expect(bounds.MaxX - bounds.MinX).toBeGreaterThanOrEqual(130)
		expect(bounds.MaxZ - bounds.MinZ).toBeGreaterThanOrEqual(130)
		expect(top).toBeGreaterThanOrEqual(6)
		expect(top).toBeLessThanOrEqual(8)
		expect(BattlegroundLayout.groundAt(LAYOUT, MAP.Crater.X, MAP.Crater.Z)).toBe(0)
	end)

	it("raise the scriptorium's arcade, three arches or more under one beam about 30 high, among its desks", function()
		local _, top, piers = landmark("ArcadePier")
		expect(piers).toBeGreaterThanOrEqual(4)
		local _, beamTop = landmark("ArcadeBeam")
		expect(beamTop).toBeGreaterThanOrEqual(28)
		expect(top).toBeLessThan(beamTop)
		local _, _, desks = landmark("Desk")
		expect(desks).toBeGreaterThanOrEqual(6)
	end)

	it(
		"scatter seals 20 to 40 across, some stacked, and run a ruled bed 60 wide from the cliffs to the south edge",
		function()
			local stacked, seals = 0, 0
			for _, piece in ipairs(MAP.Pieces) do
				if string.sub(piece.Name, 1, 4) == "Seal" then
					seals += 1
					expect(piece.Size[1]).toBeGreaterThanOrEqual(20)
					expect(piece.Size[1]).toBeLessThanOrEqual(40)
					if piece.Base > 0 then
						stacked += 1
					end
				end
			end
			expect(seals).toBeGreaterThanOrEqual(8)
			expect(stacked).toBeGreaterThanOrEqual(2)
			local bed = MAP.Bed
			expect(bed.Width).toBeGreaterThanOrEqual(55)
			local cliffs = landmark("Folio")
			local first, last = bed.Points[1], bed.Points[#bed.Points]
			expect(BattlegroundLayout.inRect(BattlegroundLayout.inflate(cliffs, 1), first.X, first.Z)).toBe(true)
			expect(last.Z).toBeGreaterThanOrEqual(MAP.Size / 2 - 30)
			-- The bridge crosses it east of the place.
			local bridge = named("BridgeDeck")
			expect(bridge.X).toBeGreaterThan(named("Dais").SizeX / 2)
			expect(bridge.SizeX).toBeGreaterThan(bed.Width)
		end
	)
end)

describe("the arrivals", function()
	it("are six in the camp with the return gate, and twelve round the edge", function()
		local camp, edge = arrivals()
		expect(#camp).toBe(6)
		expect(#edge).toBe(12)
		expect(BattlegroundLayout.inRect(LAYOUT.Camp, LAYOUT.ReturnGate.X, LAYOUT.ReturnGate.Z)).toBe(true)
	end)

	it("stand 80 studs apart round the edge, 60 from every Forger's spawn, on nothing solid", function()
		local camp, edge = arrivals()
		for index, arrival in ipairs(edge) do
			for other = index + 1, #edge do
				expect(distance(arrival, edge[other])).toBeGreaterThanOrEqual(MAP.ArrivalSpacingStuds)
			end
			for _, inCamp in ipairs(camp) do
				expect(distance(arrival, inCamp)).toBeGreaterThanOrEqual(MAP.ArrivalSpacingStuds)
			end
		end
		for _, arrival in ipairs(LAYOUT.Arrivals) do
			for _, spawn in ipairs(LAYOUT.BotSpawns) do
				expect(distance(arrival, spawn)).toBeGreaterThanOrEqual(MAP.MinSpawnDistanceStuds)
			end
			for _, obstacle in ipairs(OBSTACLES) do
				expect(
					BattlegroundLayout.inPrint(
						BattlegroundLayout.grow(obstacle, LAYOUT.PathRadius),
						arrival.X,
						arrival.Z
					)
				).toBe(false)
			end
			expect(BattlegroundLayout.inRect(LAYOUT.Bounds, arrival.X, arrival.Z)).toBe(true)
		end
	end)

	it("land nobody in the circle that sends them home", function()
		for _, arrival in ipairs(LAYOUT.Arrivals) do
			expect(distance(arrival, LAYOUT.ReturnGate)).toBeGreaterThanOrEqual(PortalConfig.ZoneRadiusStuds + 2)
		end
	end)
end)

describe("the camp", function()
	it("holds the whole return gate, its back flush on the camp's west edge", function()
		-- The gate faces east, into the page.
		local westmost = math.huge
		for _, corner in ipairs(Gate.corners(LAYOUT.ReturnGate.X, LAYOUT.ReturnGate.Z, 1, 0)) do
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, corner[1], corner[2])).toBe(true)
			westmost = math.min(westmost, corner[1])
		end
		expect(westmost).toBeCloseTo(LAYOUT.Camp.MinX, 9)
	end)

	it("lets a Forger walk straight up to the edge a goal is pushed onto, and not a hair past it", function()
		local x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, LAYOUT.Camp.MinZ + 2)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z - 15, x, z)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z - 15, x, z + 0.1)).toBe(false)
		x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, 0)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x + 15, z, x, z)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x + 15, z, x - 0.1, z)).toBe(false)
	end)

	it("pushes a goal out across its open edges and keeps every goal inside the roam", function()
		local radius = LAYOUT.PathRadius
		local x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, 0)
		expect(x).toBe(LAYOUT.Camp.MaxX + radius)
		expect(z).toBe(0)
		x, z = BattlegroundLayout.clampGoal(LAYOUT, -315, LAYOUT.Camp.MinZ + 2)
		expect(x).toBe(-315)
		expect(z).toBe(LAYOUT.Camp.MinZ - radius)
		-- Behind the camp, toward the torn edge: brought into the roam first, then out of the camp eastward.
		x, z = BattlegroundLayout.clampGoal(LAYOUT, LAYOUT.Camp.MinX + 1, 0)
		expect(x).toBe(LAYOUT.Camp.MaxX + radius)
		expect(z).toBe(0)
		-- A goal on the torn edge is brought back to the roam's border.
		x, z = BattlegroundLayout.clampGoal(LAYOUT, 345, -348)
		expect(x).toBe(LAYOUT.Roam.MaxX)
		expect(z).toBe(LAYOUT.Roam.MinZ)
		-- A goal inside the roam and outside the camp is left where it is.
		x, z = BattlegroundLayout.clampGoal(LAYOUT, 10, -20)
		expect(x).toBe(10)
		expect(z).toBe(-20)
	end)
end)

describe("the Forgers' ground", function()
	it("spawns them in the roam, clear of every obstacle and of the camp", function()
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			expect(blocked(spawn.X, spawn.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Roam, spawn.X, spawn.Z)).toBe(true)
		end
	end)

	it("lays no waypoint in the camp or an obstacle, nor past the roam", function()
		expect(#LAYOUT.Nodes).toBeGreaterThan(800)
		for _, node in ipairs(LAYOUT.Nodes) do
			expect(blocked(node.X, node.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, node.X, node.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Roam, node.X, node.Z)).toBe(true)
		end
	end)

	it("joins every waypoint to every other, the crater's floor and the book's valley included", function()
		local seen: { [number]: boolean } = { [1] = true }
		local queue = { 1 }
		local count = 1
		while #queue > 0 do
			local current = table.remove(queue, 1) :: number
			for _, neighbour in ipairs(LAYOUT.Edges[current]) do
				if not seen[neighbour] then
					seen[neighbour] = true
					count += 1
					table.insert(queue, neighbour)
				end
			end
		end
		expect(count).toBe(#LAYOUT.Nodes)
		-- Each enclosed ground has a waypoint of its own, walked to straight from its middle.
		for _, inside in ipairs({ { X = MAP.Crater.X, Z = MAP.Crater.Z }, { X = MAP.Books[1].X, Z = MAP.Books[1].Z } }) do
			local node = LAYOUT.Nodes[BattlegroundLayout.nearestNode(LAYOUT, inside.X, inside.Z) :: number]
			expect(distance(node, inside)).toBeLessThan(MAP.Grid.StepStuds)
			expect(BattlegroundLayout.segmentClear(LAYOUT, inside.X, inside.Z, node.X, node.Z)).toBe(true)
		end
	end)

	it("finds the shortest path, every leg of it a clear straight walk", function()
		local ends: { number } = {
			BattlegroundLayout.nearestNode(LAYOUT, MAP.Crater.X, MAP.Crater.Z) :: number,
			BattlegroundLayout.nearestNode(LAYOUT, LAYOUT.Camp.MaxX + 5, 0) :: number,
			BattlegroundLayout.nearestNode(LAYOUT, 250, 150) :: number,
			#LAYOUT.Nodes,
		}
		for _, from in ipairs(ends) do
			for _, to in ipairs(ends) do
				local route = BattlegroundLayout.path(LAYOUT, from, to)
				if route == nil then
					error(("no path from node %d to node %d"):format(from, to))
				end
				expect(route[1]).toBe(from)
				expect(route[#route]).toBe(to)
				local length = 0
				for index = 2, #route do
					local a, b = LAYOUT.Nodes[route[index - 1]], LAYOUT.Nodes[route[index]]
					expect(BattlegroundLayout.segmentClear(LAYOUT, a.X, a.Z, b.X, b.Z)).toBe(true)
					length += distance(a, b)
				end
				expect(length).toBeCloseTo(shortest(from, to), 6)
			end
		end
		-- Always the same path for the same ends, from a page built again.
		local again = BattlegroundLayout.build(MAP, DRESSING, BotConfig.Path.RadiusStuds)
		expect(BattlegroundLayout.path(again, ends[1], ends[3])).toEqual(
			BattlegroundLayout.path(LAYOUT, ends[1], ends[3])
		)
	end)

	it("heads first for a waypoint it can walk to straight", function()
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			local node = LAYOUT.Nodes[BattlegroundLayout.nearestNode(LAYOUT, spawn.X, spawn.Z) :: number]
			expect(BattlegroundLayout.segmentClear(LAYOUT, spawn.X, spawn.Z, node.X, node.Z)).toBe(true)
		end
		-- Just south of the north wall on the dais, the nearest waypoint lies past its end, the way there cut by
		-- the wall: the Forger takes the nearest one it can reach instead of walking into it.
		local x, z = 5, -60 + 1 + LAYOUT.PathRadius + 0.3
		local nearest, nearestDistance = 0, math.huge
		for index, node in ipairs(LAYOUT.Nodes) do
			local apart = distance(node, { X = x, Z = z })
			if apart < nearestDistance then
				nearest, nearestDistance = index, apart
			end
		end
		local behind = LAYOUT.Nodes[nearest]
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z, behind.X, behind.Z)).toBe(false)
		local chosen = BattlegroundLayout.nearestNode(LAYOUT, x, z) :: number
		expect(chosen ~= nearest).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z, LAYOUT.Nodes[chosen].X, LAYOUT.Nodes[chosen].Z)).toBe(true)
	end)

	it("breaks a tie between two equal walks toward the lower node, so every Forger takes the same one", function()
		-- A square with no diagonals: 1 -> 2 -> 4 and 1 -> 3 -> 4 are the same length.
		local square = {
			Nodes = { { X = 0, Z = 0 }, { X = 10, Z = 0 }, { X = 0, Z = 10 }, { X = 10, Z = 10 } },
			Edges = { { 2, 3 }, { 1, 4 }, { 1, 4 }, { 2, 3 } },
		}
		expect(BattlegroundLayout.path(square :: any, 1, 4)).toEqual({ 1, 2, 4 })
		expect(BattlegroundLayout.path(square :: any, 4, 1)).toEqual({ 4, 2, 1 })
	end)

	it("is blocked across the quill's turned stem and by the camp, and open beside the stem and down a lane", function()
		local quill = MAP.Quill
		local yaw = math.rad(quill.Yaw)
		-- Along the stem, and across it; halfway up its flight.
		local ax, az = math.sin(yaw), math.cos(yaw)
		local cx, cz = math.cos(yaw), -math.sin(yaw)
		local up = quill.Steps * quill.Tread / 2
		local mx, mz = quill.X + ax * up, quill.Z + az * up
		expect(BattlegroundLayout.segmentClear(LAYOUT, mx - cx * 20, mz - cz * 20, mx + cx * 20, mz + cz * 20)).toBe(
			false
		)
		-- Twenty studs off its axis, alongside: inside the stem's square bounds, outside the stem.
		local sx, sz = mx + cx * 20, mz + cz * 20
		expect(BattlegroundLayout.segmentClear(LAYOUT, sx - ax * 50, sz - az * 50, sx + ax * 50, sz + az * 50)).toBe(
			true
		)
		expect(BattlegroundLayout.segmentClear(LAYOUT, -320, -40, -320, 40)).toBe(false)
		expect(BattlegroundLayout.segmentClear(LAYOUT, -30, -40, -30, 40)).toBe(true)
	end)
end)

describe("the Battleground's names", function()
	it("names every part a reader finds by name once, in the map and in the Workspace", function()
		local anchors = BattlegroundConfig.Anchors
		local prefixes = { anchors.Arrival, anchors.BotSpawn }
		local seen: { [string]: boolean } = {}
		local function claim(name: string)
			if seen[name] then
				error(("two parts of the Battleground are called %s"):format(name))
			end
			for _, prefix in ipairs(prefixes) do
				if string.sub(name, 1, #prefix) == prefix then
					error(("%s reads as one of the markers %s*"):format(name, prefix))
				end
			end
			seen[name] = true
		end
		for _, box in ipairs(LAYOUT.Boxes) do
			claim(box.Name)
		end
		-- The return gate stands inside the map, its seal and its sign inside the gate.
		claim(PortalConfig.Anchors.ReturnGate)
		claim(PortalConfig.Anchors.Seal)
		claim(PortalConfig.Anchors.Sign)
		expect(seen[anchors.Floor]).toBe(true)
		expect(seen[anchors.KillZone]).toBe(true)
		expect(string.sub(anchors.Arrival, 1, #anchors.BotSpawn) ~= anchors.BotSpawn).toBe(true)
		expect(string.sub(anchors.BotSpawn, 1, #anchors.Arrival) ~= anchors.Arrival).toBe(true)
		-- Each folder a service rebuilds at Start destroys whatever already bears its name.
		local workspace = { anchors.Map, BotConfig.FolderName, WorldConfig.HubAnchors.Folder }
		for first = 1, #workspace do
			for second = first + 1, #workspace do
				expect(workspace[first] ~= workspace[second]).toBe(true)
			end
		end
	end)
end)

describe("the Battleground's place in the world", function()
	it("stands out of the hub's sight and out of its packets' reach", function()
		-- The hub's outer edge: the platform and its kerb. The arenas stacked above x = z = 0 are narrower.
		local hubEdge = hubNumber("PLATFORM_SIZE_STUDS") / 2 + hubNumber("PLATFORM_EDGE_WIDTH_STUDS")
		local origin = MAP.Origin
		local toCentre = math.sqrt(origin[1] ^ 2 + origin[3] ^ 2)
		local apart = toCentre - MAP.Size / 2 - hubEdge
		expect(apart).toBeGreaterThanOrEqual(GameConfig.Vfx.BroadcastRadiusStuds)
		expect(apart).toBeGreaterThanOrEqual(LightingConfig.Lighting.Numbers.FogEnd)
		expect(origin[2]).toBe(0)
	end)

	it("kills below the floor well above the engine's own cutoff, under the whole page", function()
		expect(MAP.KillZoneDepth).toBeLessThan(-MAP.FloorThickness)
		expect(MAP.KillZoneDepth).toBeGreaterThan(-500)
		expect(MAP.KillZoneSpread).toBeGreaterThan(1)
		-- A Forger thrown through the floor is caught by its fall check first, with no credit.
		expect(BotConfig.FallMarginStuds).toBeLessThan(-MAP.KillZoneDepth)
	end)
end)
