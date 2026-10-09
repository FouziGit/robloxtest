--!strict
-- Map: builds Workspace.Battleground (D-131, D-282) from BattlegroundLayout, once, at Start, and hands the rest of
-- the service what it measures against -- the layout, the landing and spawn markers, the kill plane and the
-- sight rays' filter. A few hundred static parts (BattlegroundConfig.Map.PartBudget), never released.
--
-- The camp holds the way out: a Return gate (World/PortalGate, D-130) whose circle PortalService watches like
-- any other, so a member who came in through the hub's gate always has a way back, dead or alive.
--
-- Every colour is a role of WorldConfig.Battleground and every part is what its box says: a solid collides and
-- blocks sight, everything else is drawn on the page and touches nothing. The markers are plain invisible
-- parts, never SpawnLocations: HubSpawn must stay the only SpawnLocation in the world (ArenaService).
--
-- The solids -- the floor and its torn edge, the dais, the cover and the landmarks -- also carry
-- MovementGuardConfig.BarrierTag: the geometry no body may pass through, which is all the movement audit casts
-- its noclip ray against. The kill plane, the ink drawn on the page and the camp touch nothing and are left out.
-- A box is a block, a wedge or a cylinder, turned by its Yaw about the vertical; a cylinder's axis is the engine's
-- x, so it is laid on its side to stand on its flat face.
--
-- The landmarks are drawn as ink volumes (D-283): BattlegroundLayout.skins places the meshes tools/meshes/page/
-- generated over their boxes, each a part that touches nothing, and the boxes it covers go invisible but still
-- collide. A skin waits for every one of its meshes to be uploaded and resolved (MeshConfig); until then its boxes
-- and marks stay drawn as they are.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BattlegroundLayout = require(script.Parent.Parent.Parent.Pure.BattlegroundLayout)
local BotConfig = require(Shared.Config.BotConfig)
local Context = require(script.Parent.Context)
local Log = require(Shared.Util.Log)
local MeshConfig = require(Shared.Config.MeshConfig)
local MovementGuardConfig = require(script.Parent.Parent.Parent.Config.MovementGuardConfig)
local Palette = require(Shared.Util.Palette)
local PortalConfig = require(Shared.Config.PortalConfig)
local PortalGate = require(script.Parent.Parent.Parent.World.PortalGate)
local WorldConfig = require(Shared.Config.WorldConfig)

export type Handle = {
	Instance: Model,
	Origin: Vector3,
	FloorY: number,
	Layout: BattlegroundLayout.Layout,
	-- Arrivals[i] is the marker named Anchors.Arrival .. i, BotSpawns[i] the one named Anchors.BotSpawn .. i.
	Arrivals: { BasePart },
	BotSpawns: { BasePart },
	KillZone: BasePart,
	-- The page and every glyph wall, and nothing else: what a Forger's sight and its bolts stop on. One cached
	-- set of parameters, kept current as walls rise and fall.
	SightParams: RaycastParams,
}

local ANCHORS = BattlegroundConfig.Anchors
local MAP = BattlegroundConfig.Map
-- Role -> colour name. Every Role a box carries is a key of WorldConfig.Battleground
-- (tests/BattlegroundLayout.spec.luau), which also holds the camp's transparency, a number.
local ROLES = (WorldConfig.Battleground :: any) :: { [string]: string }
local MARKER_ROLE = "Marker"
local KILL_ZONE_ROLE = "KillZone"
-- As ArenaService's: a marker stands where a character's root goes, so PivotTo(marker.CFrame) stands it up.
local MARKER_STUDS = Vector3.new(2, 1, 2)
local COLLISION_TAG = WorldConfig.Glyphs.CollisionTag
-- Lays a cylinder's axis (the engine's x) along the vertical.
local CYLINDER_UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local DRESSING: BattlegroundLayout.Dressing = {
	FloorName = ANCHORS.Floor,
	KillZoneName = ANCHORS.KillZone,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}

local log = Log.new("BattlegroundService")

local Map = {}

local function newPart(
	name: string,
	shape: BattlegroundLayout.Shape,
	size: Vector3,
	cframe: CFrame,
	role: string
): BasePart
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		end
		part = block
	end
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = Palette.world(ROLES[role])
	part.Material = Palette.material()
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- One box of the layout. A solid collides and can be hit by a query; the rest -- the ruling, the camp's wash, the
-- bed, the ink marks -- is drawn on the page and is nothing to the physics.
local function buildBox(box: BattlegroundLayout.Box, parent: Model): BasePart
	local frame = CFrame.new(Context.toWorld(box.X, box.Y, box.Z)) * CFrame.Angles(0, math.rad(box.Yaw), 0)
	local size = Vector3.new(box.SizeX, box.SizeY, box.SizeZ)
	if box.Shape == "Cylinder" then
		frame *= CYLINDER_UPRIGHT
		size = Vector3.new(box.SizeY, box.SizeX, box.SizeZ)
	end
	local part = newPart(box.Name, box.Shape, size, frame, box.Role)
	part.Transparency = box.Transparency
	part.CanCollide = box.Solid
	part.CanQuery = box.Solid
	part.CanTouch = false
	if box.Solid then
		CollectionService:AddTag(part, MovementGuardConfig.BarrierTag)
	end
	part.Parent = parent
	return part
end

-- A SpecialMesh's Scale on one axis: the placed size over the imported one. A flat mesh (a single quad of top) was
-- imported with no extent on one axis, and there the skin's own scale is all there is.
local function stretch(studs: number, imported: number, scale: number): number
	return if imported > 0 then studs / imported else scale
end

-- One mesh of a landmark's skin: a SpecialMesh scaled from the size the importer gave it (Native) to its placed
-- size, on a part centred on its placed bounds (the importer recentres a mesh on them), nothing to the physics.
local function buildSkinPart(
	name: string,
	mesh: MeshConfig.Mesh,
	tone: string,
	pivot: CFrame,
	scale: Vector3,
	parent: Model
)
	local native = mesh.Native :: { number }
	local min = Vector3.new(mesh.Min[1], mesh.Min[2], mesh.Min[3])
	local max = Vector3.new(mesh.Max[1], mesh.Max[2], mesh.Max[3])
	local size = (max - min) * scale
	local part = newPart(name, "Block", size, pivot * CFrame.new((min + max) / 2 * scale), "Skin" .. tone)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local special = Instance.new("SpecialMesh")
	special.MeshType = Enum.MeshType.FileMesh
	special.MeshId = mesh.Id
	special.Scale = Vector3.new(
		stretch(size.X, native[1], scale.X),
		stretch(size.Y, native[2], scale.Y),
		stretch(size.Z, native[3], scale.Z)
	)
	special.Parent = part
	part.Parent = parent
end

-- A landmark's skin, once every one of its meshes is uploaded and resolved: its parts, then its boxes and marks
-- hidden (a box still collides). Otherwise nothing changes, and the meshes it waits for are noted in `missing`.
local function buildSkin(
	skin: BattlegroundLayout.Skin,
	parts: { [string]: BasePart },
	parent: Model,
	missing: { [string]: boolean }
)
	local ready = true
	for _, piece in ipairs(skin.Meshes) do
		local mesh = MeshConfig.get(piece.Mesh)
		if mesh == nil or mesh.Id == "" or mesh.Native == nil then
			missing[piece.Mesh] = true
			ready = false
		end
	end
	if not ready then
		return
	end
	local pivot = CFrame.new(Context.toWorld(skin.X, skin.Y, skin.Z)) * CFrame.Angles(0, math.rad(skin.Yaw), 0)
	local scale = Vector3.new(skin.Scale[1], skin.Scale[2], skin.Scale[3])
	for _, piece in ipairs(skin.Meshes) do
		local mesh = MeshConfig.get(piece.Mesh) :: MeshConfig.Mesh
		buildSkinPart("Skin" .. skin.Name .. piece.Tone, mesh, piece.Tone, pivot, scale, parent)
	end
	for _, name in ipairs(skin.Boxes) do
		parts[name].Transparency = 1
	end
	for _, name in ipairs(skin.Marks) do
		parts[name].Transparency = 1
	end
end

-- An invisible marker standing where a character's root goes, turned toward `face` (a world point).
local function buildMarker(name: string, point: BattlegroundLayout.Point, face: Vector3, parent: Model): BasePart
	local position = Context.toWorld(point.X, BattlegroundConfig.StandingRootStuds, point.Z)
	local frame = CFrame.lookAt(position, Vector3.new(face.X, position.Y, face.Z))
	local marker = newPart(name, "Block", MARKER_STUDS, frame, MARKER_ROLE)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Parent = parent
	return marker
end

-- Keeps the sight filter on the page and on every glyph wall standing anywhere: a wall a player raises in the
-- Battleground hides them from a Forger exactly as it stops a player's shot.
local function watchSight(params: RaycastParams, model: Model, trove: Context.TroveType)
	local function refresh()
		local include: { Instance } = CollectionService:GetTagged(COLLISION_TAG)
		table.insert(include, model)
		params.FilterDescendantsInstances = include
	end
	refresh()
	trove:Connect(CollectionService:GetInstanceAddedSignal(COLLISION_TAG), refresh)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(COLLISION_TAG), refresh)
end

-- Builds the page, replacing any previous one, and returns its handle. `trove` owns what outlives the call:
-- the connections that keep the sight filter current.
function Map.build(trove: Context.TroveType): Handle
	local previous = Workspace:FindFirstChild(ANCHORS.Map)
	if previous ~= nil then
		previous:Destroy()
	end
	local layout = BattlegroundLayout.build(MAP, DRESSING, BotConfig.Path.RadiusStuds)
	local model = Instance.new("Model")
	model.Name = ANCHORS.Map

	local killZone: BasePart? = nil
	local parts: { [string]: BasePart } = {}
	for _, box in ipairs(layout.Boxes) do
		local part = buildBox(box, model)
		parts[box.Name] = part
		if box.Name == ANCHORS.Floor then
			model.PrimaryPart = part
		elseif box.Role == KILL_ZONE_ROLE then
			-- As an arena's: invisible, felt by whatever falls into it, and never in anybody's way.
			part.CanTouch = true
			killZone = part
		end
	end
	assert(killZone ~= nil, "BattlegroundLayout built no kill zone")

	local missing: { [string]: boolean } = {}
	for _, skin in ipairs(BattlegroundLayout.skins(layout, MAP)) do
		buildSkin(skin, parts, model, missing)
	end
	local waiting: { string } = {}
	for key in pairs(missing) do
		table.insert(waiting, key)
	end
	if #waiting > 0 then
		table.sort(waiting)
		log.warn(
			"%d landmark meshes are not uploaded or resolved, so their boxes stay drawn: %s",
			#waiting,
			table.concat(waiting, ", ")
		)
	end

	local arrivals: { BasePart } = {}
	for index, point in ipairs(layout.Arrivals) do
		-- Facing the page's centre, the way a player walks out of the camp or in from the edge.
		table.insert(arrivals, buildMarker(ANCHORS.Arrival .. index, point, Context.Origin, model))
	end
	local spawns: { BasePart } = {}
	for index, point in ipairs(layout.BotSpawns) do
		table.insert(spawns, buildMarker(ANCHORS.BotSpawn .. index, point, Context.Origin, model))
	end
	-- Facing east, the way its players come from the page; its back posts end on the camp's west edge.
	local gate = Context.toWorld(layout.ReturnGate.X, 0, layout.ReturnGate.Z)
	PortalGate.build(model, PortalConfig.Anchors.ReturnGate, CFrame.lookAt(gate, gate + Vector3.xAxis), "Return")

	local sight = RaycastParams.new()
	sight.FilterType = Enum.RaycastFilterType.Include
	sight.IgnoreWater = true
	watchSight(sight, model, trove)

	model.Parent = Workspace
	return {
		Instance = model,
		Origin = Context.Origin,
		FloorY = Context.FloorY,
		Layout = layout,
		Arrivals = arrivals,
		BotSpawns = spawns,
		KillZone = killZone,
		SightParams = sight,
	}
end

return Map
