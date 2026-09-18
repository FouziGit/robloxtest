--!strict
-- HubService: builds the whole hub in code at Start (nothing is authored in Studio). One Workspace
-- folder holds the platform, the single SpawnLocation (HubSpawn), the training ring marker, the
-- QueueTerminal, one LeaderboardBoard_<boardId> per RankingConfig board and the ShopKiosk. The
-- folder is destroyed and rebuilt at Start so a Rojo re-sync or a re-run never leaves two hubs.
--
-- Signage rule: a SurfaceGui parented to a server-built part is byte-identical for every viewer, so
-- it cannot be localized. Every sign this service builds therefore carries a neutral emblem and no
-- text: the localized queue and shop UI belong to the client (MatchScreen / ShopScreen). The
-- leaderboard boards are the one legitimate exception — player names and ratings are not
-- localizable text — so they expose an empty row container that LeaderboardService fills.
--
-- Anchor names come from docs/GAME_DESIGN.md §8 and must survive any replacement by real assets:
-- HubSpawn, QueueTerminal, LeaderboardBoard_<boardId>, ShopKiosk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ui = ReplicatedStorage:WaitForChild("UI")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local RankingConfig = require(Shared.Config.RankingConfig)
local Theme = require(Ui.Theme)

local log = Log.new("HubService")

-- No service is needed to build geometry; Init keeps the signature every service shares.
-- CombatService is read for resyncPosition only, which runs long after every Init: HubService is the
-- first service the bootstrap starts, so it must never CALL into Combat during Init.
type CombatApi = { resyncPosition: (player: Player) -> () }
type Deps = { Combat: CombatApi }

type BoardLayout = { BoardId: string, PanelCFrame: CFrame }
type Layout = { Boards: { BoardLayout }, QueueCFrame: CFrame, ShopCFrame: CFrame }

local HUB_FOLDER_NAME = "Hub"
-- docs/GAME_DESIGN.md §8: 200×200 platform, spawn at the centre.
local PLATFORM_SIZE_STUDS = 200
local PLATFORM_THICKNESS_STUDS = 4
local PLATFORM_COLOR = Color3.fromRGB(58, 62, 72)
local PLATFORM_EDGE_COLOR = Color3.fromRGB(38, 40, 48)
local PLATFORM_EDGE_WIDTH_STUDS = 6
local PLATFORM_EDGE_HEIGHT_STUDS = 2
local SPAWN_SIZE_STUDS = Vector3.new(12, 1, 12)
local SPAWN_COLOR = Color3.fromRGB(96, 104, 124)
-- Same radius as CombatService's hub safe zone, so the marker shows exactly where PvP is disabled
-- and the EnemyService dummy ring (GameConfig.Enemy.DummyRingRadius) stands inside it.
local TRAINING_RADIUS_STUDS = GameConfig.Enemy.DummyRingRadius + GameConfig.Spawn.SafeZoneMarginStuds
local TRAINING_MARKER_THICKNESS_STUDS = 0.2
local TRAINING_MARKER_TRANSPARENCY = 0.4
-- Props stand clear of the dummy ring; boards sit a little further out so their panels never touch.
local PROP_RING_RADIUS_STUDS = TRAINING_RADIUS_STUDS + 16
local BOARD_RING_RADIUS_STUDS = TRAINING_RADIUS_STUDS + 24
local BOARD_PANEL_SIZE_STUDS = Vector3.new(24, 14, 1)
local BOARD_PANEL_GAP_STUDS = 6
local BOARD_LEG_HEIGHT_STUDS = 6
local BOARD_LEG_THICKNESS_STUDS = 1
local BOARD_LEG_INSET_STUDS = 2
local BOARD_PIXELS_PER_STUD = 48
local BOARD_ACCENT_HEIGHT_SCALE = 0.07
local BOARD_PADDING_PIXELS = 12
local BOARD_ROW_GAP_PIXELS = 4
local PEDESTAL_BASE_SIZE_STUDS = Vector3.new(7, 1, 7)
local PEDESTAL_COLUMN_SIZE_STUDS = Vector3.new(2.5, 4, 2.5)
local PEDESTAL_PANEL_SIZE_STUDS = Vector3.new(6, 4, 0.5)
local PEDESTAL_PANEL_TILT_DEGREES = 18
local PEDESTAL_COLOR = Color3.fromRGB(46, 48, 58)
local EMBLEM_PIXELS_PER_STUD = 64
local EMBLEM_STROKE_PIXELS = 6
-- Rotations (degrees) of the bars inside the emblem ring: a pair of crossed blades for the queue
-- terminal, an upright cross for the shop kiosk. Shapes only, never text.
local QUEUE_EMBLEM_BARS = { -28, 28 }
local SHOP_EMBLEM_BARS = { 0, 90 }
-- Returning players land on a small ring around the spawn so a whole team never stacks on one point.
local RETURN_SLOT_COUNT = 8
local RETURN_RADIUS_STUDS = 9
-- PivotTo places the character's root: half a character above the ground it should stand on.
local CHARACTER_PIVOT_STUDS = 3.5

local HubService = {}

local layout: Layout
local combat: CombatApi
local hubSpawn: SpawnLocation?
-- boardId -> the row container LeaderboardService fills (UIListLayout already installed).
local boardEntries: { [string]: Frame? } = {}
local returnSlot = 0

local function ringPosition(angle: number, radius: number, height: number): Vector3
	return Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

-- A prop faces the spawn: CFrame.lookAt points LookVector (-Z, the Front face) at the centre.
local function facingCenter(position: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

local function computeLayout(): Layout
	local boards: { BoardLayout } = {}
	local ids = RankingConfig.Leaderboard.Boards
	-- Angular step from the panel footprint so two boards can never overlap on the ring.
	local step = (BOARD_PANEL_SIZE_STUDS.X + BOARD_PANEL_GAP_STUDS) / BOARD_RING_RADIUS_STUDS
	local panelHeight = BOARD_LEG_HEIGHT_STUDS + BOARD_PANEL_SIZE_STUDS.Y / 2
	for index, boardId in ipairs(ids) do
		-- Centred on the far side of the platform (half a turn from the queue terminal).
		local angle = math.pi / 2 + (index - (#ids + 1) / 2) * step
		boards[index] = {
			BoardId = boardId,
			PanelCFrame = facingCenter(ringPosition(angle, BOARD_RING_RADIUS_STUDS, panelHeight)),
		}
	end
	return {
		Boards = boards,
		QueueCFrame = facingCenter(ringPosition(0, PROP_RING_RADIUS_STUDS, 0)),
		ShopCFrame = facingCenter(ringPosition(math.pi, PROP_RING_RADIUS_STUDS, 0)),
	}
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function buildPlatform(parent: Folder)
	local half = PLATFORM_SIZE_STUDS / 2
	local platform = newPart(
		"HubPlatform",
		Vector3.new(PLATFORM_SIZE_STUDS, PLATFORM_THICKNESS_STUDS, PLATFORM_SIZE_STUDS),
		CFrame.new(0, -PLATFORM_THICKNESS_STUDS / 2, 0),
		PLATFORM_COLOR
	)
	platform.Parent = parent

	-- A low kerb on all four sides: a visible edge that also stops a knockback from ending in a fall.
	local length = PLATFORM_SIZE_STUDS + PLATFORM_EDGE_WIDTH_STUDS * 2
	local offset = half + PLATFORM_EDGE_WIDTH_STUDS / 2
	local height = PLATFORM_EDGE_HEIGHT_STUDS / 2
	local sides = {
		{
			Name = "HubEdgeNorth",
			Size = Vector3.new(length, PLATFORM_EDGE_HEIGHT_STUDS, PLATFORM_EDGE_WIDTH_STUDS),
			Position = Vector3.new(0, height, -offset),
		},
		{
			Name = "HubEdgeSouth",
			Size = Vector3.new(length, PLATFORM_EDGE_HEIGHT_STUDS, PLATFORM_EDGE_WIDTH_STUDS),
			Position = Vector3.new(0, height, offset),
		},
		{
			Name = "HubEdgeWest",
			Size = Vector3.new(PLATFORM_EDGE_WIDTH_STUDS, PLATFORM_EDGE_HEIGHT_STUDS, length),
			Position = Vector3.new(-offset, height, 0),
		},
		{
			Name = "HubEdgeEast",
			Size = Vector3.new(PLATFORM_EDGE_WIDTH_STUDS, PLATFORM_EDGE_HEIGHT_STUDS, length),
			Position = Vector3.new(offset, height, 0),
		},
	}
	for _, side in ipairs(sides) do
		newPart(side.Name, side.Size, CFrame.new(side.Position), PLATFORM_EDGE_COLOR).Parent = parent
	end
end

local function buildSpawn(parent: Folder): SpawnLocation
	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = "HubSpawn"
	spawnPart.Size = SPAWN_SIZE_STUDS
	spawnPart.CFrame = CFrame.new(0, SPAWN_SIZE_STUDS.Y / 2, 0)
	spawnPart.Anchored = true
	spawnPart.Neutral = true
	spawnPart.AllowTeamChangeOnTouch = false
	spawnPart.Color = SPAWN_COLOR
	spawnPart.Material = Enum.Material.Metal
	spawnPart.TopSurface = Enum.SurfaceType.Smooth
	spawnPart.BottomSurface = Enum.SurfaceType.Smooth
	-- The engine ForceField lasts exactly as long as the protection CombatService enforces itself,
	-- so the visual and the rule can never disagree.
	spawnPart.Duration = GameConfig.Spawn.ProtectionSeconds
	spawnPart.Parent = parent
	return spawnPart
end

local function buildTrainingMarker(parent: Folder)
	local diameter = TRAINING_RADIUS_STUDS * 2
	-- A cylinder's flat faces are on its X axis, so the disc is rolled a quarter turn to lie flat.
	local marker = newPart(
		"TrainingArea",
		Vector3.new(TRAINING_MARKER_THICKNESS_STUDS, diameter, diameter),
		CFrame.new(0, TRAINING_MARKER_THICKNESS_STUDS / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Theme.Colors.AccentSoft
	)
	marker.Shape = Enum.PartType.Cylinder
	marker.Transparency = TRAINING_MARKER_TRANSPARENCY
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Parent = parent
end

-- Neutral emblem: a ring plus straight bars, no text, identical for every viewer.
local function buildEmblem(panel: BasePart, accent: Color3, bars: { number })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Emblem"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = EMBLEM_PIXELS_PER_STUD
	gui.LightInfluence = 0

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.Colors.Panel
	background.BorderSizePixel = 0
	background.Parent = gui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.8, 0.8)
	ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ring.BackgroundTransparency = 1
	ring.Parent = background

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = EMBLEM_STROKE_PIXELS
	stroke.Parent = ring

	for index, rotation in ipairs(bars) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. index
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.12, 0.6)
		bar.SizeConstraint = Enum.SizeConstraint.RelativeYY
		bar.Rotation = rotation
		bar.BackgroundColor3 = accent
		bar.BorderSizePixel = 0
		bar.Parent = ring
	end

	gui.Parent = panel
end

-- Pedestal = base + column + tilted emblem panel, grouped in a Model under the anchor name.
local function buildPedestal(parent: Folder, name: string, baseCFrame: CFrame, accent: Color3, bars: { number })
	local model = Instance.new("Model")
	model.Name = name

	local base = newPart(
		"Base",
		PEDESTAL_BASE_SIZE_STUDS,
		baseCFrame * CFrame.new(0, PEDESTAL_BASE_SIZE_STUDS.Y / 2, 0),
		PEDESTAL_COLOR
	)
	base.Parent = model

	local columnY = PEDESTAL_BASE_SIZE_STUDS.Y + PEDESTAL_COLUMN_SIZE_STUDS.Y / 2
	local column = newPart("Column", PEDESTAL_COLUMN_SIZE_STUDS, baseCFrame * CFrame.new(0, columnY, 0), PEDESTAL_COLOR)
	column.Parent = model

	local panelY = PEDESTAL_BASE_SIZE_STUDS.Y + PEDESTAL_COLUMN_SIZE_STUDS.Y + PEDESTAL_PANEL_SIZE_STUDS.Y / 2
	local panelCFrame = baseCFrame
		* CFrame.new(0, panelY, 0)
		* CFrame.Angles(math.rad(PEDESTAL_PANEL_TILT_DEGREES), 0, 0)
	local panel = newPart("Panel", PEDESTAL_PANEL_SIZE_STUDS, panelCFrame, PEDESTAL_COLOR)
	panel.Parent = model

	buildEmblem(panel, accent, bars)
	model.PrimaryPart = base
	model.Parent = parent
end

-- Empty row container: LeaderboardService adds one row per entry (LayoutOrder = rank).
local function buildBoardGui(panel: BasePart): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BOARD_PIXELS_PER_STUD
	gui.LightInfluence = 0

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Theme.Colors.Panel
	background.BorderSizePixel = 0
	background.ClipsDescendants = true
	background.Parent = gui

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.fromScale(1, BOARD_ACCENT_HEIGHT_SCALE)
	accent.BackgroundColor3 = Theme.Colors.Accent
	accent.BorderSizePixel = 0
	accent.Parent = background

	local entries = Instance.new("Frame")
	entries.Name = "Entries"
	entries.Position = UDim2.fromScale(0, BOARD_ACCENT_HEIGHT_SCALE)
	entries.Size = UDim2.fromScale(1, 1 - BOARD_ACCENT_HEIGHT_SCALE)
	entries.BackgroundTransparency = 1
	entries.Parent = background

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, BOARD_PADDING_PIXELS)
	padding.PaddingBottom = UDim.new(0, BOARD_PADDING_PIXELS)
	padding.PaddingLeft = UDim.new(0, BOARD_PADDING_PIXELS)
	padding.PaddingRight = UDim.new(0, BOARD_PADDING_PIXELS)
	padding.Parent = entries

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, BOARD_ROW_GAP_PIXELS)
	list.Parent = entries

	gui.Parent = panel
	return entries
end

local function buildBoard(parent: Folder, board: BoardLayout)
	local model = Instance.new("Model")
	model.Name = "LeaderboardBoard_" .. board.BoardId

	local panel = newPart("Panel", BOARD_PANEL_SIZE_STUDS, board.PanelCFrame, Theme.Colors.Background)
	panel.Parent = model

	local legOffsetX = BOARD_PANEL_SIZE_STUDS.X / 2 - BOARD_LEG_INSET_STUDS
	local legOffsetY = -BOARD_PANEL_SIZE_STUDS.Y / 2 - BOARD_LEG_HEIGHT_STUDS / 2
	for index, sign in ipairs({ -1, 1 }) do
		local leg = newPart(
			"Leg" .. index,
			Vector3.new(BOARD_LEG_THICKNESS_STUDS, BOARD_LEG_HEIGHT_STUDS, BOARD_LEG_THICKNESS_STUDS),
			board.PanelCFrame * CFrame.new(legOffsetX * sign, legOffsetY, 0),
			PEDESTAL_COLOR
		)
		leg.Parent = model
	end

	boardEntries[board.BoardId] = buildBoardGui(panel)
	model.PrimaryPart = panel
	model.Parent = parent
end

-- Any SpawnLocation outside this folder would steal the hub safe zone CombatService and EnemyService
-- resolve from the first SpawnLocation in the Workspace, so it is reported loudly.
local function warnOnForeignSpawns(folder: Folder)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(folder) then
			log.warn(
				"foreign SpawnLocation %s: the hub safe zone must be centred on HubSpawn only",
				descendant:GetFullName()
			)
		end
	end
end

function HubService.Init(deps: Deps)
	combat = deps.Combat
	layout = computeLayout()
end

function HubService.Start()
	local previous = Workspace:FindFirstChild(HUB_FOLDER_NAME)
	if previous ~= nil then
		previous:Destroy()
	end
	table.clear(boardEntries)

	local folder = Instance.new("Folder")
	folder.Name = HUB_FOLDER_NAME

	buildPlatform(folder)
	local spawnPart = buildSpawn(folder)
	buildTrainingMarker(folder)
	buildPedestal(folder, "QueueTerminal", layout.QueueCFrame, Theme.Colors.Info, QUEUE_EMBLEM_BARS)
	buildPedestal(folder, "ShopKiosk", layout.ShopCFrame, Theme.Colors.Accent, SHOP_EMBLEM_BARS)
	for _, board in ipairs(layout.Boards) do
		buildBoard(folder, board)
	end

	folder.Parent = Workspace
	hubSpawn = spawnPart
	warnOnForeignSpawns(folder)
	log.info("hub built: %d studs platform, %d leaderboard boards", PLATFORM_SIZE_STUDS, #layout.Boards)
end

-- The hub SpawnLocation. Built by Start, which Bootstrap runs before any player can join.
function HubService.getSpawn(): BasePart
	local spawnPart = hubSpawn
	assert(spawnPart ~= nil and spawnPart:IsDescendantOf(Workspace), "HubService.getSpawn called before Start")
	return spawnPart
end

-- Row container of a hub leaderboard board, for LeaderboardService to fill. nil for an unknown id.
function HubService.getLeaderboardEntries(boardId: string): Frame?
	local entries = boardEntries[boardId]
	if entries == nil or not entries:IsDescendantOf(Workspace) then
		return nil
	end
	return entries
end

-- Places the character back on the hub platform, facing the spawn, with its velocity cleared so a
-- knockback or a fall from an arena never carries over. Players land on consecutive ring slots so a
-- whole team returning at once does not stack on one point.
function HubService.teleportToHub(player: Player)
	local spawnPart = hubSpawn
	if spawnPart == nil or not spawnPart:IsDescendantOf(Workspace) then
		log.warn("teleportToHub for %s ignored: the hub is not built", player.Name)
		return
	end
	local character = player.Character
	if character == nil or character.Parent == nil then
		return
	end

	returnSlot = returnSlot % RETURN_SLOT_COUNT + 1
	local angle = (returnSlot - 1) * (2 * math.pi / RETURN_SLOT_COUNT)
	local offset = ringPosition(angle, RETURN_RADIUS_STUDS, spawnPart.Size.Y / 2 + CHARACTER_PIVOT_STUDS)
	character:PivotTo(facingCenter(spawnPart.Position + offset))

	local root = character.PrimaryPart
	if root ~= nil then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	-- The server moved this character, so the position CombatService trusts must follow it: otherwise the
	-- player's next hitbox is built back in the arena they just left (CombatService.trustedCFrame).
	combat.resyncPosition(player)
end

return HubService
