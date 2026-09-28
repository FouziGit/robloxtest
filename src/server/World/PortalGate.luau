--!strict
-- PortalGate: builds one portal gate (D-130) -- an ink gateway over a chalk seal on an ink rim -- as a Model
-- under `parent`. Stateless: every place that has a gate calls `build` with where it stands (the hub's two,
-- the Return gate in the Erasure's arena template, the Return gate in the Battleground's camp), and
-- PortalService finds each one by its seal.
--
-- The zone is the invisible Seal part at the gate's foot. It carries PortalConfig.SealTag and names the gate's
-- destination in PortalConfig.SealAttribute, and it is exactly as wide as the chalk disc a player sees, so the
-- circle IS the zone the server measures. A tag survives Clone(), so a gate built into an arena template
-- arrives with every copy of the arena.
--
-- No word is written on it: the gate carries a neutral emblem, and each client names it in its own language.
--
-- Geometry (WorldConfig.Portal), in the space of `base` -- a point on the floor's top face whose LookVector
-- points to where players come from, so +Z is behind the gate -- with R the zone's radius: the seal is 2R
-- across and the rim shows SealRimStuds around it; the posts stand behind the circle, their inner faces
-- OpeningStuds apart and their front faces on its back edge; the lintel spans the posts' outer faces on top
-- of them; the panel hangs in front of the lintel. tests/gate.luau reads the same numbers to place the three
-- gates.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Draw = require(script.Parent.Draw)
local Palette = require(Shared.Util.Palette)
local PortalConfig = require(Shared.Config.PortalConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

local PORTAL = WorldConfig.Portal
local LADDER = WorldConfig.Ladder
local RADIUS = PortalConfig.ZoneRadiusStuds
local POST_SIZE = Palette.vector(PORTAL.PostStuds)
local PANEL_SIZE = Palette.vector(PORTAL.PanelStuds)
local SEAL_THICKNESS_STUDS = WorldConfig.FlatThicknessStuds

local PortalGate = {}

-- Builds the gate named `name` at `base`, leading to `portalId`, and parents it to `parent` last, so its seal
-- is complete -- tag, destination, place -- before anything watching the tag can see it.
function PortalGate.build(parent: Instance, name: string, base: CFrame, portalId: PortalConfig.PortalId)
	local model = Instance.new("Model")
	model.Name = name
	local frame = Palette.world(PORTAL.Frame)
	local function add(part: BasePart)
		part.Parent = model
	end

	-- The circle a player sees is exactly the zone: 2R across, on its rim.
	local ground = base.Position
	local rimDiameter = 2 * (RADIUS + PORTAL.SealRimStuds)
	add(Draw.flatDisc("SealRim", rimDiameter, ground, LADDER.SealRim, Palette.world(PORTAL.SealRim)))
	add(Draw.flatDisc("SealDisc", 2 * RADIUS, ground, LADDER.Seal, Palette.world(PORTAL.Seal)))

	-- Solid, as a wall is: a post stops a body and a shot.
	local postX = PORTAL.OpeningStuds / 2 + POST_SIZE.X / 2
	local postZ = RADIUS + POST_SIZE.Z / 2
	for index, side in ipairs({ -1, 1 }) do
		add(Draw.part("Post" .. index, POST_SIZE, base * CFrame.new(postX * side, POST_SIZE.Y / 2, postZ), frame))
	end
	local lintel = PORTAL.LintelStuds
	local lintelSize = Vector3.new(PORTAL.OpeningStuds + 2 * POST_SIZE.X, lintel, lintel)
	add(Draw.part("Lintel", lintelSize, base * CFrame.new(0, POST_SIZE.Y + lintel / 2, RADIUS + lintel / 2), frame))

	-- The emblem faces the way players come from: the panel's Front face is the base's.
	local panelAt = base * CFrame.new(0, POST_SIZE.Y - PANEL_SIZE.Y / 2, RADIUS - PANEL_SIZE.Z / 2)
	local panel = Draw.part(WorldConfig.HubAnchors.Panel, PANEL_SIZE, panelAt, frame)
	Draw.emblem(panel, Palette.world(PORTAL.Emblem), PORTAL.Emblems[portalId])
	add(panel)

	-- The zone itself: flat on the floor, invisible, and nothing to the physics.
	local sealSize = Vector3.new(2 * RADIUS, SEAL_THICKNESS_STUDS, 2 * RADIUS)
	local sealAt = base * CFrame.new(0, SEAL_THICKNESS_STUDS / 2, 0)
	local seal = Draw.part(PortalConfig.Anchors.Seal, sealSize, sealAt, Palette.world(PORTAL.Seal))
	seal.Transparency = 1
	seal.CanCollide = false
	seal.CanQuery = false
	seal.CanTouch = false
	seal:SetAttribute(PortalConfig.SealAttribute, portalId)
	CollectionService:AddTag(seal, PortalConfig.SealTag)
	add(seal)

	model.PrimaryPart = seal
	model.Parent = parent
end

return PortalGate
