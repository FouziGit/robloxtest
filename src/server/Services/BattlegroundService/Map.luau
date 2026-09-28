--!strict
-- Map: builds Workspace.Battleground (D-131) from BattlegroundLayout, once, at Start, and hands the rest of
-- the service what it measures against -- the layout, the landing and spawn markers, the kill plane and the
-- sight rays' filter. About sixty static parts, never released.
--
-- The camp holds the way out: a Return gate (World/PortalGate, D-130) whose circle PortalService watches like
-- any other, so a member who came in through the hub's gate always has a way back, dead or alive.
--
-- Every colour is a role of WorldConfig.Battleground and every part is what its box says: a solid collides and
-- blocks sight, everything else is drawn on the page and touches nothing. The markers are plain invisible
-- parts, never SpawnLocations: HubSpawn must stay the only SpawnLocation in the world (ArenaService).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BattlegroundLayout = require(Shared.Pure.BattlegroundLayout)
local BotConfig = require(Shared.Config.BotConfig)
local Context = require(script.Parent.Context)
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

local DRESSING: BattlegroundLayout.Dressing = {
	FloorName = ANCHORS.Floor,
	KillZoneName = ANCHORS.KillZone,
	WallRuleStuds = WorldConfig.Arena.WallRuleStuds,
	WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}

local Map = {}

local function newPart(name: string, size: Vector3, cframe: CFrame, role: string): Part
	local part = Instance.new("Part")
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

-- One box of the layout. A solid collides and can be hit by a query; the rest -- rules, the camp's wash, the
-- rule caps -- is drawn on the page and is nothing to the physics.
local function buildBox(box: BattlegroundLayout.Box, parent: Model): Part
	local part = newPart(
		box.Name,
		Vector3.new(box.SizeX, box.SizeY, box.SizeZ),
		CFrame.new(Context.toWorld(box.X, box.Y, box.Z)),
		box.Role
	)
	part.Transparency = box.Transparency
	part.CanCollide = box.Solid
	part.CanQuery = box.Solid
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- An invisible marker standing where a character's root goes, turned toward `face` (a world point).
local function buildMarker(name: string, point: BattlegroundLayout.Point, face: Vector3, parent: Model): Part
	local position = Context.toWorld(point.X, BattlegroundConfig.StandingRootStuds, point.Z)
	local marker =
		newPart(name, MARKER_STUDS, CFrame.lookAt(position, Vector3.new(face.X, position.Y, face.Z)), MARKER_ROLE)
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
	for _, box in ipairs(layout.Boxes) do
		local part = buildBox(box, model)
		if box.Name == ANCHORS.Floor then
			model.PrimaryPart = part
		elseif box.Role == KILL_ZONE_ROLE then
			-- As an arena's: invisible, felt by whatever falls into it, and never in anybody's way.
			part.CanTouch = true
			killZone = part
		end
	end
	assert(killZone ~= nil, "BattlegroundLayout built no kill zone")

	local arrivals: { BasePart } = {}
	for index, point in ipairs(layout.Arrivals) do
		-- Facing east, into the page, the way a player walks out of the camp.
		local ahead = Context.toWorld(point.X + 1, 0, point.Z)
		table.insert(arrivals, buildMarker(ANCHORS.Arrival .. index, point, ahead, model))
	end
	local spawns: { BasePart } = {}
	for index, point in ipairs(layout.BotSpawns) do
		table.insert(spawns, buildMarker(ANCHORS.BotSpawn .. index, point, Context.Origin, model))
	end
	-- Facing east, the way its players come from the page; its back posts end on the west wall.
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
