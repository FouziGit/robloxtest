--!strict
-- The Battleground's page (D-131), held to what its config claims: everything inside the walls, nothing solid
-- in the camp or on top of another solid, no perch out of every Forger's reach, a waypoint graph that is
-- whole and whose paths are clear and shortest, and a page that every packet fired on it reaches while the
-- hub is out of sight and out of reach.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/shared/Pure/BattlegroundLayout")
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
local ARENA = WorldConfig.Arena
local DRESSING: BattlegroundLayout.Dressing = {
	FloorName = BattlegroundConfig.Anchors.Floor,
	KillZoneName = BattlegroundConfig.Anchors.KillZone,
	WallRuleStuds = ARENA.WallRuleStuds,
	WallRuleProudStuds = ARENA.WallRuleProudStuds,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}
local LAYOUT = BattlegroundLayout.build(MAP, DRESSING, BotConfig.Path.RadiusStuds)
-- The engine's default gravity, which the place keeps (tests/LockOn.spec.luau).
local GRAVITY = 196.2
local EPSILON = 1e-6
local HUB = "src/server/Services/HubService.luau"

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

local function rectsOverlap(a: BattlegroundLayout.Rect, b: BattlegroundLayout.Rect): boolean
	return a.MinX < b.MaxX - EPSILON
		and b.MinX < a.MaxX - EPSILON
		and a.MinZ < b.MaxZ - EPSILON
		and b.MinZ < a.MaxZ - EPSILON
end

local function blocked(x: number, z: number): boolean
	for _, rect in ipairs(LAYOUT.Blocked) do
		if BattlegroundLayout.inRect(rect, x, z) then
			return true
		end
	end
	return false
end

local function distance(a: BattlegroundLayout.Point, b: BattlegroundLayout.Point): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
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

describe("the Battleground's boxes", function()
	it("stand inside the walls, from the floor's underside to the wall rules' tops", function()
		local reach = MAP.Size / 2 + MAP.WallThickness + ARENA.WallRuleProudStuds / 2
		local top = MAP.WallHeight + ARENA.WallRuleProudStuds
		expect(#LAYOUT.Boxes).toBeGreaterThan(30)
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Role ~= "KillZone" then
				local within = math.abs(box.X) + box.SizeX / 2 <= reach + EPSILON
					and math.abs(box.Z) + box.SizeZ / 2 <= reach + EPSILON
					and box.Y - box.SizeY / 2 >= -MAP.FloorThickness - EPSILON
					and box.Y + box.SizeY / 2 <= top + EPSILON
				if not within then
					error(("%s leaves the page"):format(box.Name))
				end
			end
		end
	end)

	it("draw everything flat on a rung of the ladder, sunk into the floor", function()
		local rungs =
			{ Rule = WorldConfig.Ladder.Rule, CampLine = WorldConfig.Ladder.Rule, Camp = WorldConfig.Ladder.Training }
		local count = 0
		for _, box in ipairs(LAYOUT.Boxes) do
			local rung = rungs[box.Role]
			if rung ~= nil then
				count += 1
				expect(box.Y + box.SizeY / 2).toBeCloseTo(rung, 9)
				expect(box.Y - box.SizeY / 2).toBeLessThan(0)
				expect(box.Solid).toBe(false)
			end
		end
		-- The four lines of the ruling, the camp's wash and its line.
		expect(count).toBe(6)
	end)

	it("never put one solid inside another", function()
		local solids: { BattlegroundLayout.Box } = {}
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Solid then
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

	it("leave the camp free of anything solid", function()
		expect(#LAYOUT.Obstacles).toBe(MAP.Pillars.Count + 1 + #MAP.Covers)
		for _, obstacle in ipairs(LAYOUT.Obstacles) do
			expect(rectsOverlap(obstacle, LAYOUT.Camp)).toBe(false)
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

	it("leave no perch out of a double jump's reach", function()
		local movement = GameConfig.Movement
		local reach = (movement.JumpPower ^ 2 + movement.DoubleJumpVelocity ^ 2) / (2 * GRAVITY)
		for _, box in ipairs(LAYOUT.Boxes) do
			if box.Solid and box.Role ~= "Floor" then
				if box.Y + box.SizeY / 2 <= reach then
					error(
						("%s is %.2f studs tall: a double jump (%.2f) stands on it"):format(box.Name, box.SizeY, reach)
					)
				end
			end
		end
		expect(MAP.CoverHeight).toBeGreaterThan(reach)
	end)
end)

describe("the camp", function()
	it("takes every arrival and the return gate", function()
		for _, arrival in ipairs(LAYOUT.Arrivals) do
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, arrival.X, arrival.Z)).toBe(true)
		end
		expect(BattlegroundLayout.inRect(LAYOUT.Camp, LAYOUT.ReturnGate.X, LAYOUT.ReturnGate.Z)).toBe(true)
	end)

	it("lands nobody in the circle that sends them home", function()
		for _, arrival in ipairs(LAYOUT.Arrivals) do
			expect(distance(arrival, LAYOUT.ReturnGate)).toBeGreaterThanOrEqual(PortalConfig.ZoneRadiusStuds + 2)
		end
	end)

	it("holds the whole return gate, its back flush on the west wall", function()
		-- The gate faces east, into the page.
		local corners = Gate.corners(LAYOUT.ReturnGate.X, LAYOUT.ReturnGate.Z, 1, 0)
		local westmost = math.huge
		for _, corner in ipairs(corners) do
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, corner[1], corner[2])).toBe(true)
			westmost = math.min(westmost, corner[1])
		end
		expect(westmost).toBeCloseTo(-MAP.Size / 2, 9)
	end)

	it("lets a Forger walk straight up to the edge a goal is pushed onto, and not a hair past it", function()
		local x, z = BattlegroundLayout.clampOutOfCamp(LAYOUT, -70, LAYOUT.Camp.MinZ + 2)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z - 15, x, z)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x, z - 15, x, z + 0.1)).toBe(false)
		x, z = BattlegroundLayout.clampOutOfCamp(LAYOUT, -70, 0)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x + 15, z, x, z)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, x + 15, z, x - 0.1, z)).toBe(false)
	end)

	it("is pushed out of across its open edges, never through a wall", function()
		local radius = LAYOUT.PathRadius
		local x, z = BattlegroundLayout.clampOutOfCamp(LAYOUT, -70, 0)
		expect(x).toBe(LAYOUT.Camp.MaxX + radius)
		expect(z).toBe(0)
		x, z = BattlegroundLayout.clampOutOfCamp(LAYOUT, -70, LAYOUT.Camp.MinZ + 2)
		expect(x).toBe(-70)
		expect(z).toBe(LAYOUT.Camp.MinZ - radius)
		-- Against the west wall the nearest edge is the wall: the goal goes to the nearest open one instead.
		x, z = BattlegroundLayout.clampOutOfCamp(LAYOUT, LAYOUT.Camp.MinX + 1, 0)
		expect(x).toBe(LAYOUT.Camp.MinX + 1)
		expect(z).toBe(LAYOUT.Camp.MinZ - radius)
		expect(BattlegroundLayout.inRect(LAYOUT.Bounds, x, z)).toBe(true)
		-- A goal outside the camp is left where it is.
		x, z = BattlegroundLayout.clampOutOfCamp(LAYOUT, 10, -20)
		expect(x).toBe(10)
		expect(z).toBe(-20)
	end)
end)

describe("the Forgers' ground", function()
	it("spawns them outside the camp, clear of every obstacle, far from every arrival", function()
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			expect(blocked(spawn.X, spawn.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Bounds, spawn.X, spawn.Z)).toBe(true)
			for _, arrival in ipairs(LAYOUT.Arrivals) do
				expect(distance(spawn, arrival)).toBeGreaterThanOrEqual(MAP.MinSpawnDistanceStuds)
			end
		end
	end)

	it("lays no waypoint in the camp or an obstacle", function()
		expect(#LAYOUT.Nodes).toBeGreaterThan(200)
		for _, node in ipairs(LAYOUT.Nodes) do
			expect(blocked(node.X, node.Z)).toBe(false)
			expect(BattlegroundLayout.inRect(LAYOUT.Camp, node.X, node.Z)).toBe(false)
		end
	end)

	it("joins every waypoint to every other", function()
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
	end)

	it("finds the shortest path, every leg of it a clear straight walk", function()
		local ends: { number } = {}
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			table.insert(ends, BattlegroundLayout.nearestNode(LAYOUT, spawn.X, spawn.Z) :: number)
		end
		table.insert(ends, BattlegroundLayout.nearestNode(LAYOUT, LAYOUT.Camp.MaxX + 5, 0) :: number)
		table.insert(ends, #LAYOUT.Nodes)
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
		-- Always the same path for the same ends.
		expect(BattlegroundLayout.path(LAYOUT, ends[1], ends[5])).toEqual(
			BattlegroundLayout.path(LAYOUT, ends[1], ends[5])
		)
	end)

	it("heads first for a waypoint it can walk to straight", function()
		for _, spawn in ipairs(LAYOUT.BotSpawns) do
			local node = LAYOUT.Nodes[BattlegroundLayout.nearestNode(LAYOUT, spawn.X, spawn.Z) :: number]
			expect(BattlegroundLayout.segmentClear(LAYOUT, spawn.X, spawn.Z, node.X, node.Z)).toBe(true)
		end
		-- Just past the end of a cover wall the nearest waypoint lies behind it: the Forger takes the nearest one
		-- it can reach instead of walking into the wall.
		local cover: BattlegroundConfig.Cover? = nil
		for _, each in ipairs(MAP.Covers) do
			if each.Name == "CoverEast" then
				cover = each
			end
		end
		assert(cover ~= nil, "CoverEast is gone: this case would check nothing")
		local x, z = cover.X + 1, cover.Z + cover.SizeZ / 2 + LAYOUT.PathRadius + 0.3
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

	it("is blocked by a pillar and by the camp, and open down a lane", function()
		local pillar = LAYOUT.Obstacles[1]
		local middleX, middleZ = (pillar.MinX + pillar.MaxX) / 2, (pillar.MinZ + pillar.MaxZ) / 2
		expect(BattlegroundLayout.segmentClear(LAYOUT, middleX - 10, middleZ, middleX + 10, middleZ)).toBe(false)
		expect(BattlegroundLayout.segmentClear(LAYOUT, -70, -40, -70, 40)).toBe(false)
		expect(BattlegroundLayout.segmentClear(LAYOUT, 20, -30, 20, 30)).toBe(true)
		expect(BattlegroundLayout.segmentClear(LAYOUT, -50, -40, -50, 40)).toBe(true)
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
	it("is reached everywhere by every packet fired on it", function()
		expect(math.sqrt(2) * MAP.Size).toBeLessThanOrEqual(GameConfig.Vfx.BroadcastRadiusStuds)
	end)

	it("stands out of the hub's sight and out of its packets' reach", function()
		-- The hub's outer edge: the platform and its kerb. The arenas stacked above x = z = 0 are narrower.
		local hubEdge = hubNumber("PLATFORM_SIZE_STUDS") / 2 + hubNumber("PLATFORM_EDGE_WIDTH_STUDS")
		local origin = MAP.Origin
		local toCentre = math.sqrt(origin[1] ^ 2 + origin[3] ^ 2)
		local gap = toCentre - MAP.Size / 2 - MAP.WallThickness - hubEdge
		expect(gap).toBeGreaterThanOrEqual(GameConfig.Vfx.BroadcastRadiusStuds)
		expect(gap).toBeGreaterThanOrEqual(LightingConfig.Lighting.Numbers.FogEnd)
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
