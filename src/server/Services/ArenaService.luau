--!strict
-- ArenaService: builds one arena template per MatchConfig.Arenas entry inside ServerStorage at Start
-- and hands live copies to MatchService. A template is built around the origin (floor centred on it)
-- so acquire() only has to pivot the clone onto a free slot of one global vertical stack; slots are
-- MatchConfig.ArenaSpacingStuds apart and the stack starts above the tallest configured arena, so two
-- live matches never share an altitude and never see each other. release() destroys the copy and
-- frees its slot; a second release on the same arena frees nothing.
--
-- Spawn markers are plain anchored Parts, never SpawnLocations: HubSpawn must stay the only
-- SpawnLocation in the world, because CombatService and EnemyService resolve the hub safe zone and
-- the dummy ring from the first SpawnLocation they find.
--
-- The kill zone is exposed, not armed: it is an environment kill, and CombatService.ApplyDamage needs
-- a source, so MatchService owns the reaction (eliminate the participant that falls into it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local Palette = require(Shared.Util.Palette)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("ArenaService")

-- No service is needed to build geometry; Init keeps the signature every service shares.
type Deps = { [string]: any }

-- Shape of a MatchConfig.Arenas entry (studs). KillZoneDepth is a negative offset from the floor.
type ArenaDef = {
	Size: number,
	WallHeight: number,
	SpawnDistance: number,
	KillZoneDepth: number,
	Height: number,
}

-- A live arena handed to MatchService. Spawns is indexed by team, then by member, in build order.
export type Arena = {
	Instance: Model,
	Id: string,
	SlotIndex: number,
	Spawns: { { BasePart } },
	KillZone: BasePart,
}

type Template = {
	Id: string,
	Model: Model,
	-- Names of the spawn markers, per team, so a clone is resolved without re-deriving the layout.
	SpawnNames: { { string } },
}

local TEMPLATES_FOLDER_NAME = "ArenaTemplates"
local LIVE_FOLDER_NAME = "Arenas"
local FLOOR_NAME = "Floor"
local KILL_ZONE_NAME = "KillZone"
local FLOOR_THICKNESS_STUDS = 4
local WALL_THICKNESS_STUDS = 2
-- Distance between two teammates' spawn markers.
local SPAWN_SPACING_STUDS = 8
local SPAWN_MARKER_SIZE_STUDS = Vector3.new(2, 1, 2)
-- A marker is placed where the character's root goes, so PivotTo(marker.CFrame) stands it upright.
local CHARACTER_PIVOT_STUDS = 3.5
-- The kill zone reaches well past the walls so a knockback that clears them still lands in it.
local KILL_ZONE_SPREAD = 3
local KILL_ZONE_THICKNESS_STUDS = 1
-- Two low central walls break the sight lines of a team arena (docs/GAME_DESIGN.md §8).
local COVER_WALL_HEIGHT_STUDS = 6
local COVER_WALL_THICKNESS_STUDS = 2
local COVER_WALL_LENGTH_FRACTION = 0.3
local COVER_WALL_OFFSET_FRACTION = 0.15
-- Arenas no mode references (the World Boss arena) spawn everyone on the perimeter ring.
local RING_MARGIN_STUDS = 10
local RING_SPAWN_CAP = 50
local BOSS_SPAWN_NAME = "BossSpawn"
-- Every colour is a role of WorldConfig.Arena (D-86): a page walled in bone, ruled in ink.
local ARENA = WorldConfig.Arena

local arenaDefs = (MatchConfig.Arenas :: any) :: { [string]: ArenaDef }

local ArenaService = {}

local templatesFolder: Folder
local liveFolder: Folder
local templates: { [string]: Template } = {}
-- slot index -> live arena. A hole is a free slot; slots are reused lowest-first.
local slots: { [number]: Arena } = {}
-- Altitude of slot 1: above the highest configured arena so every arena clears the hub and its own
-- configured height. Filled by Init from MatchConfig.
local baseAltitude = 0

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Palette.material()
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Teams and team size of the mode that plays on this arena; nil when no mode references it.
local function modeShapeFor(arenaId: string): (number?, number?)
	for _, mode in pairs(MatchConfig.Modes) do
		if mode.ArenaId == arenaId then
			return mode.Teams, mode.TeamSize
		end
	end
	return nil, nil
end

local function markerName(team: number, index: number, teamSize: number): string
	if teamSize <= 1 then
		return ("Spawn_Team%d"):format(team)
	end
	return ("Spawn_Team%d_%d"):format(team, index)
end

-- One team per radial direction at SpawnDistance / 2 from the centre, members spread sideways.
local function teamSpawnCFrames(def: ArenaDef, teams: number, teamSize: number, markerY: number): { { CFrame } }
	local result: { { CFrame } } = {}
	for team = 1, teams do
		local angle = (team - 1) * (2 * math.pi / teams)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local sideways = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local anchor = outward * (def.SpawnDistance / 2)
		local members: { CFrame } = {}
		for index = 1, teamSize do
			local slide = ((index - 1) - (teamSize - 1) / 2) * SPAWN_SPACING_STUDS
			local position = anchor + sideways * slide + Vector3.new(0, markerY, 0)
			members[index] = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
		end
		result[team] = members
	end
	return result
end

-- Perimeter ring used by the arenas no mode references: one marker per player slot of the server.
local function ringSpawnCFrames(def: ArenaDef, markerY: number): { CFrame }
	local count = math.clamp(Players.MaxPlayers, 2, RING_SPAWN_CAP)
	local radius = def.Size / 2 - RING_MARGIN_STUDS
	local members: { CFrame } = {}
	for index = 1, count do
		local angle = (index - 1) * (2 * math.pi / count)
		local position = Vector3.new(math.cos(angle) * radius, markerY, math.sin(angle) * radius)
		members[index] = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	end
	return members
end

local function buildWalls(def: ArenaDef, parent: Model, floorTop: number)
	local length = def.Size + WALL_THICKNESS_STUDS * 2
	local offset = def.Size / 2 + WALL_THICKNESS_STUDS / 2
	local centerY = floorTop + def.WallHeight / 2
	local along = Vector3.new(length, def.WallHeight, WALL_THICKNESS_STUDS)
	local across = Vector3.new(WALL_THICKNESS_STUDS, def.WallHeight, length)
	local walls = {
		{ Name = "WallNorth", Size = along, Position = Vector3.new(0, centerY, -offset) },
		{ Name = "WallSouth", Size = along, Position = Vector3.new(0, centerY, offset) },
		{ Name = "WallWest", Size = across, Position = Vector3.new(-offset, centerY, 0) },
		{ Name = "WallEast", Size = across, Position = Vector3.new(offset, centerY, 0) },
	}
	-- The ink rule along the top of each wall: the border of the sheet. A hair thicker than the wall,
	-- because a coplanar face flickers.
	local ruleHeight = ARENA.WallRuleStuds
	local proud = ARENA.WallRuleProudStuds
	for _, wall in ipairs(walls) do
		newPart(wall.Name, wall.Size, CFrame.new(wall.Position), Palette.world(ARENA.Wall)).Parent = parent
		local ruleSize = Vector3.new(
			wall.Size.X + if wall.Size.X < wall.Size.Z then proud else 0,
			ruleHeight,
			wall.Size.Z + if wall.Size.Z < wall.Size.X then proud else 0
		)
		-- Raised by `proud` as well as widened by it: at the same top height as the wall the two +Y faces
		-- are coplanar over the whole length of every wall, which is the flicker this is here to avoid.
		local ruleCenterY = floorTop + def.WallHeight - ruleHeight / 2 + proud
		local rulePosition = Vector3.new(wall.Position.X, ruleCenterY, wall.Position.Z)
		newPart(wall.Name .. "Rule", ruleSize, CFrame.new(rulePosition), Palette.world(ARENA.WallRule)).Parent = parent
	end
end

local function buildCoverWalls(def: ArenaDef, parent: Model, floorTop: number)
	local size = Vector3.new(COVER_WALL_THICKNESS_STUDS, COVER_WALL_HEIGHT_STUDS, def.Size * COVER_WALL_LENGTH_FRACTION)
	local offset = def.Size * COVER_WALL_OFFSET_FRACTION
	local centerY = floorTop + COVER_WALL_HEIGHT_STUDS / 2
	for index, sign in ipairs({ -1, 1 }) do
		local position = Vector3.new(offset * sign, centerY, offset * -sign)
		newPart("CoverWall" .. index, size, CFrame.new(position), Palette.world(ARENA.CoverWall)).Parent = parent
	end
end

local function buildKillZone(def: ArenaDef, parent: Model, floorTop: number): BasePart
	local span = def.Size * KILL_ZONE_SPREAD
	local part = newPart(
		KILL_ZONE_NAME,
		Vector3.new(span, KILL_ZONE_THICKNESS_STUDS, span),
		CFrame.new(0, floorTop + def.KillZoneDepth, 0),
		Palette.world(ARENA.Floor)
	)
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function buildMarker(name: string, cframe: CFrame, parent: Instance)
	local marker = newPart(name, SPAWN_MARKER_SIZE_STUDS, cframe, Palette.world(ARENA.Floor))
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Parent = parent
end

local function buildTemplate(arenaId: string, def: ArenaDef): Template
	local model = Instance.new("Model")
	model.Name = arenaId

	local floor = newPart(
		FLOOR_NAME,
		Vector3.new(def.Size, FLOOR_THICKNESS_STUDS, def.Size),
		CFrame.new(0, 0, 0),
		Palette.world(ARENA.Floor)
	)
	floor.Parent = model
	-- The floor is the pivot, so PivotTo(CFrame.new(0, altitude, 0)) places the whole arena.
	model.PrimaryPart = floor

	local floorTop = FLOOR_THICKNESS_STUDS / 2
	local markerY = floorTop + CHARACTER_PIVOT_STUDS
	buildWalls(def, model, floorTop)
	buildKillZone(def, model, floorTop)

	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = model

	local teams, teamSize = modeShapeFor(arenaId)
	local names: { { string } } = {}
	if teams ~= nil and teamSize ~= nil then
		for team, members in ipairs(teamSpawnCFrames(def, teams, teamSize, markerY)) do
			local teamNames: { string } = {}
			for index, cframe in ipairs(members) do
				local name = markerName(team, index, teamSize)
				buildMarker(name, cframe, spawnsFolder)
				teamNames[index] = name
			end
			names[team] = teamNames
		end
		if teamSize > 1 then
			buildCoverWalls(def, model, floorTop)
		end
	else
		-- World Boss layout (docs/GAME_DESIGN.md §8): everyone on the perimeter, boss in the centre.
		local ring = ringSpawnCFrames(def, markerY)
		local teamNames: { string } = {}
		for index, cframe in ipairs(ring) do
			local name = markerName(1, index, #ring)
			buildMarker(name, cframe, spawnsFolder)
			teamNames[index] = name
		end
		names[1] = teamNames
		buildMarker(BOSS_SPAWN_NAME, CFrame.new(0, markerY, 0), spawnsFolder)
	end

	-- Kept out of the world until a match asks for a copy.
	model.Parent = templatesFolder
	return { Id = arenaId, Model = model, SpawnNames = names }
end

local function rebuildFolder(parent: Instance, name: string): Folder
	local previous = parent:FindFirstChild(name)
	if previous ~= nil then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function findBasePart(root: Model, name: string): BasePart?
	local found = root:FindFirstChild(name, true)
	if found ~= nil and found:IsA("BasePart") then
		return found
	end
	return nil
end

local function altitudeFor(slotIndex: number): number
	return baseAltitude + (slotIndex - 1) * MatchConfig.ArenaSpacingStuds
end

local function freeSlotIndex(): number
	local index = 1
	while slots[index] ~= nil do
		index += 1
	end
	return index
end

-- Resolves the parts of a clone from the template's recorded names. Returns nil if anything is
-- missing, which can only mean the template was tampered with after Start.
local function resolveClone(template: Template, clone: Model): ({ { BasePart } }?, BasePart?)
	local spawns: { { BasePart } } = {}
	for team, teamNames in ipairs(template.SpawnNames) do
		local members: { BasePart } = {}
		for index, name in ipairs(teamNames) do
			local part = findBasePart(clone, name)
			if part == nil then
				return nil, nil
			end
			members[index] = part
		end
		spawns[team] = members
	end
	local killZone = findBasePart(clone, KILL_ZONE_NAME)
	if killZone == nil then
		return nil, nil
	end
	return spawns, killZone
end

function ArenaService.Init(_deps: Deps)
	local highest = 0
	for _, def in pairs(arenaDefs) do
		highest = math.max(highest, def.Height)
	end
	baseAltitude = highest
end

function ArenaService.Start()
	templatesFolder = rebuildFolder(ServerStorage, TEMPLATES_FOLDER_NAME)
	liveFolder = rebuildFolder(Workspace, LIVE_FOLDER_NAME)
	-- A rebuild invalidates every arena handed out before it.
	table.clear(templates)
	table.clear(slots)

	local count = 0
	for arenaId, def in pairs(arenaDefs) do
		templates[arenaId] = buildTemplate(arenaId, def)
		count += 1
	end
	log.info(
		"%d arena templates built, slots %d studs apart from altitude %d",
		count,
		MatchConfig.ArenaSpacingStuds,
		baseAltitude
	)
end

-- Clones the template of arenaId onto the lowest free slot and returns the live arena, or nil when
-- the id is unknown or the clone is unusable (both logged).
function ArenaService.acquire(arenaId: string): Arena?
	local template = templates[arenaId]
	if template == nil then
		log.warn("acquire failed: unknown arena id %s", arenaId)
		return nil
	end

	local slotIndex = freeSlotIndex()
	local clone = template.Model:Clone()
	clone.Name = ("%s_%d"):format(arenaId, slotIndex)
	clone:PivotTo(CFrame.new(0, altitudeFor(slotIndex), 0))

	local spawns, killZone = resolveClone(template, clone)
	if spawns == nil or killZone == nil then
		log.warn("acquire failed: arena %s template is missing a spawn marker or its kill zone", arenaId)
		clone:Destroy()
		return nil
	end

	clone.Parent = liveFolder
	local arena: Arena = {
		Instance = clone,
		Id = arenaId,
		SlotIndex = slotIndex,
		Spawns = spawns,
		KillZone = killZone,
	}
	slots[slotIndex] = arena
	return arena
end

-- Destroys the live arena and frees its slot. Idempotent: a slot is only freed while it still holds
-- this exact arena, so a double release can never release a slot another match has taken.
function ArenaService.release(arena: Arena)
	if slots[arena.SlotIndex] ~= arena then
		log.warn("release ignored: arena %s no longer holds slot %d", arena.Id, arena.SlotIndex)
		return
	end
	slots[arena.SlotIndex] = nil
	arena.Instance:Destroy()
end

return ArenaService
