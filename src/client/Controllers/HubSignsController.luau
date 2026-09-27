--!strict
-- HubSignsController: the hub's words, drawn by each client in its own language (D-128). HubService builds
-- the hub on the server with emblems and no text, because a SurfaceGui on a shared part reads the same for
-- every viewer. So what the hub says is added here, on the parts the server built:
--   * each leaderboard board's title in its band, and its empty state while the ladder has no row --
--     the boards used to stand as blank cream panels, and a blank panel says nothing, not "no one yet";
--   * the queue terminal's and the shop kiosk's names above them, and a prompt at each that opens the
--     Play or the Shop screen -- they looked like the way in to a match or the shop and did nothing.
-- Everything is built into this player's PlayerGui (a SurfaceGui or BillboardGui adorned to the server's
-- part, and a prompt that only this client has), and rebuilt when the server rebuilds the hub.
--
-- A prompt is live only when its key is free: not while a screen is open (the key would swap screens, and
-- abort a rebind capture waiting for that very key), and not while the player has bound that key to an
-- action (InputConfig.HubPrompt is a rebindable key: E cast a glyph and opened the shop at once).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local RankingConfig = require(Shared.Config.RankingConfig)
local Theme = require(UI.Theme)
local Trove = require(Packages.Trove)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("HubSignsController")

type Deps = { Localize: any, MenuController: any, InputController: any, ClientData: any }

local ANCHORS = WorldConfig.HubAnchors
local BOARD = WorldConfig.HubBoard
-- How long a sign waits for the part it words: the hub replicates with the world, well inside this.
local ANCHOR_WAIT_SECONDS = 30
-- Drawn above the server's SurfaceGui on the same face.
local SIGN_Z_OFFSET = 1
-- A name above a pedestal: a plate the size of a line of title text, standing over the emblem, read at
-- any distance on the hub (its size is in screen pixels, so it does not shrink with distance).
local PLATE_SIZE = UDim2.fromOffset(280, 52)
local PLATE_STUDS_ABOVE = 5
local PLATE_MAX_DISTANCE = 160
local PLATE_STROKE = 2
-- The prompt at a pedestal: close enough that it is the one the player walks up to.
local PROMPT_DISTANCE_STUDS = 12

local HubSignsController = {}

local localize: any
local menuController: any
local inputController: any
local clientData: any
local signs = Trove.new()
local gui: Folder? = nil
local prompts: { ProximityPrompt } = {}

-- Whether the player bound one of the prompt's keys to an action.
local function promptKeyTaken(): boolean
	local data = clientData.get()
	if data == nil then
		return false
	end
	for _, key in pairs(data.Settings.Keyboard) do
		if key == InputConfig.HubPrompt.Keyboard then
			return true
		end
	end
	for _, button in pairs(data.Settings.Gamepad) do
		if button == InputConfig.HubPrompt.Gamepad then
			return true
		end
	end
	return false
end

local function refreshPrompts()
	local live = not inputController.isSuspended() and not promptKeyTaken()
	for _, prompt in ipairs(prompts) do
		prompt.Enabled = live
	end
end

local function playerGui(): Instance
	local player = Players.LocalPlayer
	return player:WaitForChild("PlayerGui")
end

local function textLabel(name: string, text: string, textSize: number, color: Color3, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Title
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = text
	label.Parent = parent
	return label
end

-- A board's title in its band, and its empty state over the row container, shown while the server has
-- written no row into it.
local function wordBoard(folder: Instance, boardId: string, trove: typeof(Trove.new()))
	local model = folder:WaitForChild(ANCHORS.BoardPrefix .. boardId, ANCHOR_WAIT_SECONDS)
	local panel = if model ~= nil then model:WaitForChild(ANCHORS.Panel, ANCHOR_WAIT_SECONDS) else nil
	if panel == nil or not panel:IsA("BasePart") then
		log.warn("board %s has no %s to word", boardId, ANCHORS.Panel)
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "BoardWords_" .. boardId
	surface.Adornee = panel
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = BOARD.PixelsPerStud
	surface.LightInfluence = 0
	surface.ZOffset = SIGN_Z_OFFSET
	surface.ResetOnSpawn = false
	trove:Add(surface)

	local title = textLabel(
		"Title",
		localize.t("hub.board.title", { board = localize.t("leaderboard.board." .. boardId) }),
		BOARD.TitlePixels,
		Theme.Colors.TextInverse,
		surface
	)
	title.Size = UDim2.fromScale(1, BOARD.TitleBand)

	local empty = textLabel("Empty", localize.t("leaderboard.empty"), BOARD.TextPixels, Theme.Colors.TextMuted, surface)
	empty.Position = UDim2.fromScale(0, BOARD.TitleBand)
	empty.Size = UDim2.fromScale(1, 1 - BOARD.TitleBand)
	surface.Parent = gui

	local server = panel:WaitForChild(ANCHORS.BoardGui, ANCHOR_WAIT_SECONDS)
	local background = if server ~= nil then server:FindFirstChildWhichIsA("Frame") else nil
	local entries = if background ~= nil then background:WaitForChild(ANCHORS.Entries, ANCHOR_WAIT_SECONDS) else nil
	if entries == nil then
		log.warn("board %s has no %s: its empty state stays up", boardId, ANCHORS.Entries)
		return
	end
	-- The container also holds its padding and list layout: a row is a Frame.
	local function refresh()
		empty.Visible = entries:FindFirstChildWhichIsA("Frame") == nil
	end
	trove:Connect(entries.ChildAdded, refresh)
	trove:Connect(entries.ChildRemoved, refresh)
	refresh()
end

-- A pedestal's name above it, and the prompt that opens its screen.
local function wordPedestal(
	folder: Instance,
	anchor: string,
	nameKey: string,
	actionKey: string,
	screen: string,
	trove: typeof(Trove.new())
)
	local model = folder:WaitForChild(anchor, ANCHOR_WAIT_SECONDS)
	local panel = if model ~= nil then model:WaitForChild(ANCHORS.Panel, ANCHOR_WAIT_SECONDS) else nil
	if panel == nil or not panel:IsA("BasePart") then
		log.warn("%s has no %s to word", anchor, ANCHORS.Panel)
		return
	end
	local name = localize.t(nameKey)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign_" .. anchor
	billboard.Adornee = panel
	billboard.Size = PLATE_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, PLATE_STUDS_ABOVE, 0)
	billboard.MaxDistance = PLATE_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	trove:Add(billboard)

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Theme.Colors.Panel
	plate.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Text
	stroke.Thickness = PLATE_STROKE
	stroke.Parent = plate
	plate.Parent = billboard
	local label = textLabel("Name", name, Theme.Sizes.TextTitle, Theme.Colors.Text, plate)
	label.Size = UDim2.fromScale(1, 1)
	billboard.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open_" .. screen
	prompt.ActionText = localize.t(actionKey)
	prompt.ObjectText = name
	prompt.KeyboardKeyCode = (Enum.KeyCode :: any)[InputConfig.HubPrompt.Keyboard]
	prompt.GamepadKeyCode = (Enum.KeyCode :: any)[InputConfig.HubPrompt.Gamepad]
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE_STUDS
	prompt.RequiresLineOfSight = false
	trove:Add(prompt)
	trove:Connect(prompt.Triggered, function()
		if not menuController.isOpen() then
			menuController.open(screen)
		end
	end)
	table.insert(prompts, prompt)
	trove:Add(function()
		local index = table.find(prompts, prompt)
		if index ~= nil then
			table.remove(prompts, index)
		end
	end)
	prompt.Parent = panel
	refreshPrompts()
end

-- Words the hub `folder` the server just built, replacing whatever worded the previous one.
local function wordHub(folder: Instance)
	signs:Clean()
	local trove = signs:Extend()
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		trove:Add(task.spawn(wordBoard, folder, boardId, trove))
	end
	trove:Add(task.spawn(wordPedestal, folder, ANCHORS.Queue, "hub.queue.name", "queue.title", "Play", trove))
	trove:Add(task.spawn(wordPedestal, folder, ANCHORS.Shop, "shop.title", "hub.prompt.open", "Shop", trove))
end

function HubSignsController.Init(deps: Deps)
	localize = deps.Localize
	menuController = deps.MenuController
	inputController = deps.InputController
	clientData = deps.ClientData
end

function HubSignsController.Start()
	local folder = Instance.new("Folder")
	folder.Name = "HubSigns"
	folder.Parent = playerGui()
	gui = folder

	inputController.SuspendedChanged:Connect(refreshPrompts)
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Settings" then
			refreshPrompts()
		end
	end)

	-- HubService rebuilds its folder on a re-run (a Rojo re-sync in Studio): the new one is worded afresh.
	Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == ANCHORS.Folder then
			wordHub(child)
		end
	end)
	local existing = Workspace:FindFirstChild(ANCHORS.Folder)
	if existing ~= nil then
		wordHub(existing)
	end
	log.info("started")
end

return HubSignsController
