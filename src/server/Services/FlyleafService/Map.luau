--!strict
-- Map: builds Workspace.Flyleaf (E16-S2) from Pure/FlyleafLayout, once, at Start, and hands the rest of the service
-- what it measures against -- the layout, where a body stands on each seal, and the kill plane, which it also judges.
-- About forty static parts, never released.
--
-- The page holds its way out: a Return gate (World/PortalGate, D-130) whose circle PortalService watches like any
-- other. Every colour is a role of WorldConfig.Flyleaf and every part is what its box says: a solid collides,
-- everything else is drawn on the page and touches nothing. The seals are chalk discs on ink rims, drawn like the
-- hub's spawn (World/Draw), never SpawnLocations: HubSpawn must stay the only one in the world (ArenaService).
--
-- The solids -- the floor, the walls and the cover -- carry MovementGuardConfig.BarrierTag: the geometry no body
-- may pass through, which is all the movement audit casts its noclip ray against.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local World = script.Parent.Parent.Parent.World

local Context = require(script.Parent.Context)
local Draw = require(World.Draw)
local FlyleafConfig = require(Shared.Config.FlyleafConfig)
local FlyleafLayout = require(script.Parent.Parent.Parent.Pure.FlyleafLayout)
local MovementGuardConfig = require(script.Parent.Parent.Parent.Config.MovementGuardConfig)
local Palette = require(Shared.Util.Palette)
local PortalConfig = require(Shared.Config.PortalConfig)
local PortalGate = require(World.PortalGate)
local WorldConfig = require(Shared.Config.WorldConfig)

export type Handle = {
	Instance: Model,
	Layout: FlyleafLayout.Layout,
	-- Standing[i]: where the root of a body standing on seal i goes, in the world.
	Standing: { Vector3 },
	KillZone: BasePart,
}

local ANCHORS = FlyleafConfig.Anchors
local MAP = FlyleafConfig.Map
local ROLES = (WorldConfig.Flyleaf :: any) :: { [string]: string }
local LADDER = WorldConfig.Ladder

local DRESSING: FlyleafLayout.Dressing = {
	FloorName = ANCHORS.Floor,
	KillZoneName = ANCHORS.KillZone,
	WallRuleStuds = WorldConfig.Arena.WallRuleStuds,
	WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = LADDER.Rule,
}

local Map = {}

local function buildBox(box: FlyleafLayout.Box, parent: Model): Part
	local part = Draw.part(
		box.Name,
		Vector3.new(box.SizeX, box.SizeY, box.SizeZ),
		CFrame.new(Context.toWorld(box.X, box.Y, box.Z)),
		Palette.world(ROLES[box.Role])
	)
	part.CanCollide = box.Solid
	part.CanQuery = box.Solid
	part.CanTouch = false
	if box.Solid then
		CollectionService:AddTag(part, MovementGuardConfig.BarrierTag)
	end
	part.Parent = parent
	return part
end

-- One seal: the chalk disc on its ink rim, drawn flat on the page like the hub's spawn.
local function buildSeal(index: number, point: FlyleafLayout.Point, parent: Model)
	local center = Context.toWorld(point.X, 0, point.Z)
	local diameter = MAP.SealDiameterStuds
	local rim = Draw.flatDisc(
		ANCHORS.Seal .. index .. "Rim",
		diameter + MAP.SealRimStuds * 2,
		center,
		LADDER.SealRim,
		Palette.world(ROLES.SealRim)
	)
	rim.Parent = parent
	local seal = Draw.flatDisc(ANCHORS.Seal .. index, diameter, center, LADDER.Seal, Palette.world(ROLES.Seal))
	seal.Parent = parent
end

-- Builds the page, replacing any previous one, and returns its handle.
function Map.build(): Handle
	local previous = Workspace:FindFirstChild(ANCHORS.Map)
	if previous ~= nil then
		previous:Destroy()
	end
	local layout = FlyleafLayout.build(MAP, DRESSING)
	local model = Instance.new("Model")
	model.Name = ANCHORS.Map

	local killZone: BasePart? = nil
	for _, box in ipairs(layout.Boxes) do
		local part = buildBox(box, model)
		if box.Name == ANCHORS.Floor then
			model.PrimaryPart = part
		elseif box.Role == "KillZone" then
			-- Invisible, felt by whatever falls into it, and never in anybody's way.
			part.Transparency = 1
			part.CanTouch = true
			killZone = part
		end
	end
	assert(killZone ~= nil, "FlyleafLayout built no kill zone")

	local standing: { Vector3 } = {}
	for index, point in ipairs(layout.Seals) do
		buildSeal(index, point, model)
		table.insert(standing, Context.toWorld(point.X, FlyleafConfig.StandingRootStuds, point.Z))
	end
	-- Facing south, the way its players come from the page; its back posts end on the north wall.
	local gate = Context.toWorld(layout.ReturnGate.X, 0, layout.ReturnGate.Z)
	PortalGate.build(model, PortalConfig.Anchors.ReturnGate, CFrame.lookAt(gate, gate + Vector3.zAxis), "Return")

	model.Parent = Workspace
	return { Instance = model, Layout = layout, Standing = standing, KillZone = killZone }
end

-- A player's body under the kill plane, inside its footprint: a death of the environment, credited to nobody (or to
-- the last attacker, by CombatService, while the fight is fresh). As the server sees it, every tick: Touched is the
-- owning client's word.
function Map.judgeFalls(handle: Handle)
	local plane = handle.KillZone
	local half = plane.Size / 2
	for _, player in ipairs(Players:GetPlayers()) do
		local root = Context.liveRoot(player)
		local character = player.Character
		if root ~= nil and character ~= nil then
			local offset = plane.CFrame:PointToObjectSpace(root.Position)
			if offset.Y < 0 and math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid ~= nil then
					humanoid.Health = 0
				end
			end
		end
	end
end

-- The kill plane as the client that owns the falling body reports it: Touched.
function Map.onKillZoneTouched(part: BasePart)
	local model = part:FindFirstAncestorOfClass("Model")
	local player = if model ~= nil then Players:GetPlayerFromCharacter(model) else nil
	local humanoid = if model ~= nil and player ~= nil then model:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

return Map
