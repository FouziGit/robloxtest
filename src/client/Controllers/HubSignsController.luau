--!strict
-- HubSignsController: the hub's words, drawn by each client in its own language (D-128). HubService builds
-- the hub on the server with emblems and no text, because a SurfaceGui on a shared part reads the same for
-- every viewer. So what the hub says is added here, on the parts the server built:
--   * each leaderboard board's title in its band, and its empty state while the ladder has no row --
--     the boards used to stand as blank cream panels, and a blank panel says nothing, not "no one yet";
--   * the queue terminal's and the shop kiosk's names above them, and a prompt at each that opens the
--     Play or the Shop screen -- they looked like the way in to a match or the shop and did nothing;
--   * on every portal gate's sign (D-130, D-174), wherever it stands -- the hub's two, the Battleground's
--     camp, the Erasure's arena -- where its circle leads and what it asks: stay in it. No prompt and no
--     remote: the server moves whoever stands in the circle (PortalService), so there is nothing here to press.
-- Everything is built into this player's PlayerGui (a SurfaceGui or BillboardGui adorned to the server's
-- part, and a prompt that only this client has), and rebuilt when the server rebuilds the hub; a gate's
-- words come and go with its sign (PortalConfig.SignTag), which is how the arena copies and anything the
-- place streams in or out are worded without a list of them. When the player's language changes
-- (Localize.Changed), all of it is worded again in the new one.
--
-- A prompt is live only when its key is free: not while a screen is open (the key would swap screens, and
-- abort a rebind capture waiting for that very key), and not while the player has bound that key to an
-- action (InputConfig.HubPrompt is a rebindable key: E cast a glyph and opened the shop at once).
--
-- All of it is drawn in the world, so it stays unsaturated (docs/ART_BIBLE.md rule 1, D-147): ink plates
-- edged in the sheet, vellum and chalk words. The prompts are drawn here too (their style is Custom): an ink
-- pill with the key to press as a cap, what it does and what it opens; a tap on the pill presses it on touch.
-- Colour arrives with the screen the prompt opens.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local InputConfig = require(Shared.Config.InputConfig)
local Keycap = require(UI.components.Keycap)
local Log = require(Shared.Util.Log)
local Motion = require(UI.Motion)
local PortalConfig = require(Shared.Config.PortalConfig)
local RankingConfig = require(Shared.Config.RankingConfig)
local Sticker = require(UI.components.Sticker)
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
-- The name in the title face, as large as the plate lets it be up to this.
local NAME_MAX_TEXT = 30
-- A gate's words, on its sign (WorldConfig.Portal.SignStuds, D-174): two lines, its destination in the title
-- face and what the circle asks under it, each as large as its share of the sign lets it be. In the sign's own
-- pixels, this many to a stud: a word is never scaled past 100 of them, and a name's share of the sign is
-- about 97, so the name grows until the sign's width stops it.
local SIGN_PIXELS_PER_STUD = 30
local SIGN_NAME_SHARE = 0.6
-- The words keep this far off the sign's edges, and its edge of the sheet is this thick.
local SIGN_INSET_X = 15
local SIGN_INSET_Y = 9
local SIGN_EDGE = 5
-- The prompt at a pedestal: close enough that it is the one the player walks up to.
local PROMPT_DISTANCE_STUDS = 12
-- The prompt as it is drawn: an ink pill this many pixels, this far over the pedestal, the key on a cap.
local PROMPT_SIZE = UDim2.fromOffset(220, 48)
local PROMPT_STUDS_ABOVE = 3
local PROMPT_ACTION_TEXT = 18
local PROMPT_OBJECT_TEXT = 14
local PROMPT_FROM_SCALE = 0.8

local HubSignsController = {}

local localize: any
local menuController: any
local inputController: any
local clientData: any
local signs = Trove.new()
local gui: Folder? = nil
local prompts: { ProximityPrompt } = {}
-- The pill each of those prompts is drawn as while it shows.
local shownPrompts: { [ProximityPrompt]: BillboardGui } = {}
-- The words on each gate standing in the world, by its sign.
local gateSigns: { [BasePart]: typeof(Trove.new()) } = {}
-- The hub folder last worded, to word again in another language.
local hubFolder: Instance? = nil

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

-- `text` in `textSize`, or as large as its box lets it be when there is no size.
local function textLabel(name: string, text: string, textSize: number?, color: Color3, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = Theme.Fonts.Title
	if textSize ~= nil then
		label.TextSize = textSize
	else
		label.TextScaled = true
	end
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
	empty.FontFace = Theme.Fonts.Lore
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

-- Named after what it words: the model `part` belongs to.
local function signName(part: BasePart): string
	local owner = part.Parent
	return "Sign_" .. (if owner ~= nil then owner.Name else part.Name)
end

-- A plate of page edged in ink, `above` studs over `adornee` and facing whoever looks at it, with `name` in the
-- title face. The size of a line of title text in screen pixels, so it reads at any distance on the hub and does
-- not shrink with it.
local function namePlate(adornee: BasePart, name: string, above: number, trove: typeof(Trove.new())): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = signName(adornee)
	billboard.Adornee = adornee
	billboard.Size = PLATE_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, above, 0)
	billboard.MaxDistance = PLATE_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	trove:Add(billboard)

	-- Ink edged in the sheet: against the cream world the plate is the darkest thing there is.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Theme.Colors.Plate
	plate.BackgroundTransparency = 0
	plate.BorderSizePixel = 0
	Theme.corner(plate, Theme.Sizes.CornerCard)
	Theme.stroke(plate, "PanelRaised", Theme.Sizes.StrokeThin)
	-- The words keep off the plate's rounded ends: a scaled name ran into its corners and its outline.
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, Theme.Sizes.CornerCard)
	inset.PaddingRight = UDim.new(0, Theme.Sizes.CornerCard)
	inset.Parent = plate
	plate.Parent = billboard
	local label = textLabel("Name", name, NAME_MAX_TEXT, Theme.Colors.TextInverse, plate)
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = NAME_MAX_TEXT
	cap.Parent = label
	billboard.Parent = gui
	return billboard
end

-- `name` in the title face on the gate's `sign`, and under it `hint`, written on the face that looks where the
-- gate's players come from: ink edged in the sheet, as the pedestals' plates. Sized in the world with the sign,
-- not on the screen (D-174): screen-sized, the hub's two plates touched from the spawn and covered each other on
-- a phone. Only that face is written, so the back of one gate's sign never shows words over the other's.
local function writeSign(sign: BasePart, name: string, hint: string, trove: typeof(Trove.new())): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Name = signName(sign)
	surface.Adornee = sign
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = SIGN_PIXELS_PER_STUD
	surface.MaxDistance = PLATE_MAX_DISTANCE
	surface.LightInfluence = 0
	surface.ResetOnSpawn = false
	trove:Add(surface)

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Theme.Colors.Plate
	plate.BackgroundTransparency = 0
	plate.BorderSizePixel = 0
	Theme.stroke(plate, "PanelRaised", SIGN_EDGE)
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, SIGN_INSET_X)
	inset.PaddingRight = UDim.new(0, SIGN_INSET_X)
	inset.PaddingTop = UDim.new(0, SIGN_INSET_Y)
	inset.PaddingBottom = UDim.new(0, SIGN_INSET_Y)
	inset.Parent = plate
	plate.Parent = surface
	local label = textLabel("Name", name, nil, Theme.Colors.TextInverse, plate)
	label.Size = UDim2.fromScale(1, SIGN_NAME_SHARE)
	local line = textLabel("Hint", hint, nil, Theme.Colors.Chalk, plate)
	line.FontFace = Theme.Fonts.Body
	line.Position = UDim2.fromScale(0, SIGN_NAME_SHARE)
	line.Size = UDim2.fromScale(1, 1 - SIGN_NAME_SHARE)
	surface.Parent = gui
	return surface
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
	namePlate(panel, name, PLATE_STUDS_ABOVE, trove)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open_" .. screen
	prompt.ActionText = localize.t(actionKey)
	prompt.ObjectText = name
	prompt.KeyboardKeyCode = (Enum.KeyCode :: any)[InputConfig.HubPrompt.Keyboard]
	prompt.GamepadKeyCode = (Enum.KeyCode :: any)[InputConfig.HubPrompt.Gamepad]
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE_STUDS
	prompt.RequiresLineOfSight = false
	-- Drawn here, in ink (onPromptShown), not in the engine's grey.
	prompt.Style = Enum.ProximityPromptStyle.Custom
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

-- One of this controller's prompts, drawn while it shows: an ink pill over what it opens, with the key on a cap
-- for the device the player uses (none on touch), what it does and what it opens; a tap or a click on it
-- presses the prompt. It pops in and leaves the same way.
local function onPromptShown(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if table.find(prompts, prompt) == nil or shownPrompts[prompt] then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Prompt_" .. prompt.Name
	billboard.Adornee = prompt.Parent :: Instance
	billboard.Size = PROMPT_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, PROMPT_STUDS_ABOVE, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Active = true
	shownPrompts[prompt] = billboard
	local scale = Instance.new("UIScale")
	scale.Parent = billboard

	local pill = Sticker.new({ Kind = "Plate", Fill = Theme.Colors.Plate, Corner = Theme.Pill, Parent = billboard })
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = 3
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = row
	row.Parent = pill.Face
	if inputType ~= Enum.ProximityPromptInputType.Touch then
		local gamepad = inputType == Enum.ProximityPromptInputType.Gamepad
		Keycap.new({
			Key = if gamepad then InputConfig.HubPrompt.Gamepad else InputConfig.HubPrompt.Keyboard,
			Device = if gamepad then "Gamepad" else "Keyboard",
			Localize = localize,
			LayoutOrder = 1,
			Parent = row,
		})
	end
	local words = Instance.new("Frame")
	words.Name = "Words"
	words.BackgroundTransparency = 1
	words.AutomaticSize = Enum.AutomaticSize.X
	words.Size = UDim2.fromScale(0, 1)
	words.LayoutOrder = 2
	local stack = Instance.new("UIListLayout")
	stack.VerticalAlignment = Enum.VerticalAlignment.Center
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Parent = words
	words.Parent = row
	local action = textLabel("Action", prompt.ActionText, PROMPT_ACTION_TEXT, Theme.Colors.TextInverse, words)
	action.FontFace = Theme.Fonts.Bold
	action.AutomaticSize = Enum.AutomaticSize.XY
	action.TextWrapped = false
	action.LayoutOrder = 1
	local object = textLabel("Object", prompt.ObjectText, PROMPT_OBJECT_TEXT, Theme.Colors.Chalk, words)
	object.FontFace = Theme.Fonts.Label
	object.AutomaticSize = Enum.AutomaticSize.XY
	object.TextWrapped = false
	object.LayoutOrder = 2

	-- A custom prompt is pressed by hand on touch, and a click on the pill works with a mouse too.
	local press = Instance.new("TextButton")
	press.Name = "Press"
	press.BackgroundTransparency = 1
	press.Text = ""
	press.Size = UDim2.fromScale(1, 1)
	press.ZIndex = 5
	press.Parent = billboard
	press.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	press.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)

	billboard.Parent = gui
	Motion.set(scale, { Scale = PROMPT_FROM_SCALE })
	Motion.to(scale, { Scale = 1 }, "UiPop")
	-- A hub rebuilt under a shown prompt takes the prompt with it: its pill goes too.
	-- The pill's plate follows the player's transparency setting until it is destroyed itself: gone with the
	-- billboard, never left listening.
	local function dispose()
		pill:Destroy()
		billboard:Destroy()
	end
	-- The pedestal's prompt lives for the whole session: this show's listener goes with this show, or every
	-- walk up to the kiosk leaves one more behind, holding a pill already destroyed.
	local destroying = prompt.Destroying:Once(function()
		shownPrompts[prompt] = nil
		dispose()
	end)
	prompt.PromptHidden:Once(function()
		destroying:Disconnect()
		if shownPrompts[prompt] == billboard then
			shownPrompts[prompt] = nil
		end
		Motion.to(scale, { Scale = 0 }, "UiExit", dispose)
	end)
end

-- The words on the gate `sign` stands on: where its circle leads and how to go there, in this player's language.
-- A sign that names no destination this client knows is left unworded, and the log says so.
local function wordSign(sign: BasePart)
	local id = sign:GetAttribute(PortalConfig.SealAttribute)
	local zone = if type(id) == "string" then PortalConfig.Zones[id] else nil
	if zone == nil then
		log.warn(
			"%s is a sign that leads nowhere: %s is %s",
			sign:GetFullName(),
			PortalConfig.SealAttribute,
			tostring(id)
		)
		return
	end
	local trove = Trove.new()
	gateSigns[sign] = trove
	writeSign(sign, localize.t(zone.NameKey), localize.t(zone.HintKey), trove)
end

local function unwordSign(sign: BasePart)
	local trove = gateSigns[sign]
	if trove ~= nil then
		gateSigns[sign] = nil
		trove:Destroy()
	end
end

-- A tagged sign is worded while it stands in the Workspace, as PortalService only counts the seals there.
local function onSignAdded(instance: Instance)
	if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) and gateSigns[instance] == nil then
		wordSign(instance)
	end
end

local function onSignRemoved(instance: Instance)
	if instance:IsA("BasePart") then
		unwordSign(instance)
	end
end

-- Words the hub `folder` the server just built, replacing whatever worded the previous one.
local function wordHub(folder: Instance)
	hubFolder = folder
	signs:Clean()
	local trove = signs:Extend()
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		trove:Add(task.spawn(wordBoard, folder, boardId, trove))
	end
	trove:Add(task.spawn(wordPedestal, folder, ANCHORS.Queue, "hub.queue.name", "queue.title", "Play", trove))
	trove:Add(task.spawn(wordPedestal, folder, ANCHORS.Shop, "shop.title", "hub.prompt.open", "Shop", trove))
end

-- The player's language changed: the hub and every gate standing are worded again in it.
local function reword()
	local folder = hubFolder
	if folder ~= nil and folder.Parent ~= nil then
		wordHub(folder)
	end
	local standing: { BasePart } = {}
	for sign in pairs(gateSigns) do
		table.insert(standing, sign)
	end
	for _, sign in ipairs(standing) do
		unwordSign(sign)
		wordSign(sign)
	end
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
	ProximityPromptService.PromptShown:Connect(onPromptShown)
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

	CollectionService:GetInstanceAddedSignal(PortalConfig.SignTag):Connect(onSignAdded)
	CollectionService:GetInstanceRemovedSignal(PortalConfig.SignTag):Connect(onSignRemoved)
	for _, sign in ipairs(CollectionService:GetTagged(PortalConfig.SignTag)) do
		onSignAdded(sign)
	end
	localize.Changed:Connect(reword)
	log.info("started")
end

return HubSignsController
