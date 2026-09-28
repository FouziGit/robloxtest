--!strict
-- MenuScreen: the hub menu (D-147), an ink chapter with the five-pigment stripe. A summary strip across the
-- top (the level seal and its bar, the Folios and the way to more of them, the settings, an invite), then the
-- whole menu as tiles above the fold of a phone: Play, the loudest, a yellow double tile on the left; the six
-- others in a grid of three by two, each in its own chapter's colour, and never two of one colour side by
-- side. A tile badges what waits on its screen (Claims, on the server's day, as the HUD counts it): the pass's
-- reached tiers, the quests done, a "!" on today's reward. Picking a tile stacks its screen on this one, so
-- Back returns here (MenuController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local Claims = require(script.Parent.Parent.Claims)
local FoliosPill = require(script.Parent.Parent.components.FoliosPill)
local Icon = require(script.Parent.Parent.components.Icon)
local Panel = require(script.Parent.Parent.components.Panel)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local ProgressBar = require(script.Parent.Parent.components.ProgressBar)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Seal = require(script.Parent.Parent.components.Seal)
local Splat = require(script.Parent.Parent.components.Splat)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- The menu is a panel, not a surface for messages: the one line it can need (an invite the platform
	-- refuses) goes through the HUD's own toast column.
	HudController: { showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> () },
	-- The queue, for the Play tile's line while the player waits in one.
	MatchController: { getQueue: () -> Types.QueueSnapshot, QueueChanged: any },
	OnClose: () -> (),
	OnNavigate: (id: string, args: any?) -> (),
	OnBack: () -> (),
	CanGoBack: () -> boolean,
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen, args: any?) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type Destroyable = { Destroy: (self: any) -> () }

local MenuScreen = {}

local CHAPTER = "Menu"
local SUMMARY_HEIGHT = 56
local ICON_BUTTON = 44
local SEAL_SIZE = 44
local XP_BAR_WIDTH = 200
local XP_BAR_HEIGHT = 12
local XP_TEXT_SIZE = 16
local PILL_HEIGHT = 44
-- The Play tile: its share of the deck's width, its word, its line, and the ► on a blot of the sheet.
local PLAY_SHARE = 0.4
local PLAY_TEXT_SIZE = 40
local PLAY_LINE_SIZE = 18
local PLAY_GLYPH_SIZE = 64
local PLAY_SPLAT_TRANSPARENCY = 0.2
-- The grid's three columns by two rows, and how tall two rows stand with a pointer: on a phone the tiles
-- share whatever the card has, so the whole menu stays above its fold.
local GRID_COLUMNS = 3
local POINTER_DECK_HEIGHT = Theme.Sizes.TileHeight * 2 + Theme.Sizes.Gap
-- The five-pigment stripe along the foot of an ink tile that holds the pigments (the Loadout).
local STRIPE_HEIGHT = 6
-- The Play tile's line counts the wait once a second while the screen is up.
local TICK_SECONDS = 1

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function textLabel(name: string, font: Font, size: number, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size + 4)
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent
	return label
end

local function row(name: string, parent: Instance, gap: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	return frame
end

function MenuScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen

	local root = ScreenRoot.new({
		Name = "MenuScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("menu.title"),
		Chapter = CHAPTER,
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		OnBack = deps.OnBack,
		ShowBack = deps.CanGoBack,
		Localize = deps.Localize,
		Parent = root.Content,
	})
	own(trove, panel)
	root:SetCard(panel)

	-- A tile opens its screen on top of this one: Back returns here.
	local function navigate(id: string, args: any?)
		deps.OnNavigate(id, args)
	end

	----------------------------------------------------------------
	-- Summary strip: level, Folios, settings, invite
	----------------------------------------------------------------

	-- Its buttons carry the touch minimum, which follows the viewport.
	panel:SetHeaderHeight(function()
		return Theme.Sizes.PaddingSmall * 2 + math.max(SUMMARY_HEIGHT, Theme.touchTargetHeight(ICON_BUTTON))
	end)
	local strip = row("Summary", panel.Header, Theme.Sizes.Gap)
	strip.Size = UDim2.fromScale(1, 1)

	local levelSeal = Seal.new({
		Text = "",
		Fill = Theme.Colors.Primary,
		Size = SEAL_SIZE,
		Face = "Numeric",
		LayoutOrder = 1,
		Parent = strip,
	})
	own(trove, levelSeal)

	local xpColumn = Instance.new("Frame")
	xpColumn.Name = "Level"
	xpColumn.BackgroundTransparency = 1
	xpColumn.Size = UDim2.fromOffset(XP_BAR_WIDTH, XP_TEXT_SIZE + 4 + XP_BAR_HEIGHT + 4)
	xpColumn.LayoutOrder = 2
	xpColumn.Parent = strip
	local xpLayout = Instance.new("UIListLayout")
	xpLayout.SortOrder = Enum.SortOrder.LayoutOrder
	xpLayout.Padding = UDim.new(0, 4)
	xpLayout.Parent = xpColumn
	local xpText = textLabel("Xp", Theme.Fonts.Numeric, XP_TEXT_SIZE, 1, xpColumn)
	local xpBar = ProgressBar.new({
		Color = Theme.Colors.Primary,
		Size = UDim2.fromOffset(XP_BAR_WIDTH, XP_BAR_HEIGHT),
		LayoutOrder = 2,
		Parent = xpColumn,
	})
	own(trove, xpBar)

	-- The Folios, and the way to buy more beside them.
	local pill = FoliosPill.new({ Height = PILL_HEIGHT, LayoutOrder = 3, Parent = strip })
	own(trove, pill)

	-- An icon on its own: as wide as it is tall, never the width of a word.
	local function iconButton(name: string, text: string, icon: Icon.Name?, order: number, onClick: () -> ())
		local button = Button.new({
			Name = name,
			Text = text,
			Icon = icon,
			Variant = "Secondary",
			Size = UDim2.fromOffset(ICON_BUTTON, ICON_BUTTON),
			LayoutOrder = order,
			Parent = strip,
			OnClick = onClick,
		})
		button.Instance.AutomaticSize = Enum.AutomaticSize.None
		own(trove, button)
		return button
	end

	iconButton("MoreFolios", Theme.Glyphs.Plus, nil, 4, function()
		navigate("Shop", { Tab = "Folios" })
	end)

	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.fromScale(0, 1)
	spacer.LayoutOrder = 5
	spacer.Parent = strip
	local spacerFlex = Instance.new("UIFlexItem")
	spacerFlex.FlexMode = Enum.UIFlexMode.Fill
	spacerFlex.Parent = spacer

	iconButton("Settings", "", "Sliders", 6, function()
		navigate("Settings")
	end)

	-- Sharing, which on Roblox is the platform's own invite prompt: the player picks who from their own
	-- friends list, inside the client's UI, and nothing about them ever reaches this game.
	-- CanSendGameInviteAsync yields and can throw (an unsupported device, a policy that forbids it), so it
	-- runs in its own thread behind a pcall and says so rather than doing nothing.
	iconButton("Invite", "", "Invite", 7, function()
		task.spawn(function()
			local ok, allowed = pcall(function()
				return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
			end)
			if not ok or allowed ~= true then
				deps.HudController.showLocalToast("menu.inviteUnavailable", nil, "Error")
				return
			end
			pcall(function()
				SocialService:PromptGameInvite(Players.LocalPlayer)
			end)
		end)
	end)

	----------------------------------------------------------------
	-- The tiles
	----------------------------------------------------------------

	-- The content never scrolls: its canvas is its window, and the deck fills it. With a pointer the two
	-- rows stand at the tile height; on a phone they share what the card has.
	local content = panel.Content
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.CanvasSize = UDim2.fromScale(1, 1)

	local deck = row("Deck", content, Theme.Sizes.Gap)
	deck.Size = UDim2.fromScale(1, 1)
	if not Theme.touchOnly() then
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = Vector2.new(math.huge, POINTER_DECK_HEIGHT)
		cap.Parent = deck
	end

	local playFrame = Instance.new("Frame")
	playFrame.Name = "PlayTile"
	playFrame.BackgroundTransparency = 1
	playFrame.Size = UDim2.new(PLAY_SHARE, -Theme.Sizes.Gap / 2, 1, 0)
	playFrame.LayoutOrder = 1
	playFrame.Parent = deck

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1 - PLAY_SHARE, -Theme.Sizes.Gap / 2, 1, 0)
	grid.LayoutOrder = 2
	grid.Parent = deck
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.FillDirectionMaxCells = GRID_COLUMNS
	gridLayout.CellPadding = UDim2.fromOffset(Theme.Sizes.Gap, Theme.Sizes.Gap)
	gridLayout.CellSize =
		UDim2.new(1 / GRID_COLUMNS, -Theme.Sizes.Gap * (GRID_COLUMNS - 1) / GRID_COLUMNS, 0.5, -Theme.Sizes.Gap / 2)
	gridLayout.Parent = grid

	-- The grid reads left to right, top to bottom, by LayoutOrder: Shop, Leaderboard, Pass over Quests,
	-- Daily, Loadout. Play (yellow) touches Shop (green) and Quests (blue); the yellow Daily sits between the
	-- blue and the ink; the two ink tiles stand on a diagonal. No two tiles of one colour touch.
	local playButton = Button.new({
		Text = t("queue.title"),
		Variant = "Tile",
		Chapter = "Play",
		LayoutOrder = 3,
		Sublabel = t("hub.queue.name"),
		Size = UDim2.fromScale(1, 1),
		Parent = playFrame,
		OnClick = function()
			navigate("Play")
		end,
	})
	own(trove, playButton)

	local shopButton = Button.new({
		Text = t("menu.shop"),
		Variant = "Tile",
		Chapter = "Shop",
		LayoutOrder = 4,
		Icon = "Coin",
		Parent = grid,
		OnClick = function()
			navigate("Shop")
		end,
	})
	own(trove, shopButton)

	local leaderboardButton = Button.new({
		Text = t("leaderboard.title"),
		Variant = "Tile",
		Chapter = "Leaderboard",
		LayoutOrder = 5,
		Icon = "Podium",
		Parent = grid,
		OnClick = function()
			navigate("Leaderboard")
		end,
	})
	own(trove, leaderboardButton)

	local battlepassButton = Button.new({
		Text = t("menu.battlepass"),
		Variant = "Tile",
		Chapter = "Battlepass",
		LayoutOrder = 6,
		Icon = "Pass",
		Parent = grid,
		OnClick = function()
			navigate("Battlepass")
		end,
	})
	own(trove, battlepassButton)

	local questsButton = Button.new({
		Text = t("menu.quests"),
		Variant = "Tile",
		Chapter = "Quests",
		LayoutOrder = 7,
		Icon = "Scroll",
		Parent = grid,
		OnClick = function()
			navigate("Quests")
		end,
	})
	own(trove, questsButton)

	local dailyButton = Button.new({
		Text = t("daily.title"),
		Variant = "Tile",
		Chapter = "Daily",
		LayoutOrder = 8,
		Icon = "Calendar",
		Parent = grid,
		OnClick = function()
			navigate("Daily")
		end,
	})
	own(trove, dailyButton)

	local loadoutButton = Button.new({
		Text = t("menu.loadout"),
		Variant = "Tile",
		Chapter = "Loadout",
		LayoutOrder = 9,
		Icon = "Deck",
		Parent = grid,
		OnClick = function()
			navigate("Loadout")
		end,
	})
	own(trove, loadoutButton)

	-- The Play tile: a ► on a blot of the sheet, its word at poster size, and its line under it.
	-- What a tile adds (the Play art, the stripe) goes on its face, so it rides the face when it is pressed.
	local playFace = playButton:Face()
	local playLine: TextLabel? = nil
	if playFace ~= nil then
		local art = Instance.new("Frame")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.42)
		art.Size = UDim2.fromOffset(PLAY_GLYPH_SIZE * 1.6, PLAY_GLYPH_SIZE * 1.6)
		art.ZIndex = 2
		art.Parent = playFace
		Splat.new({
			Size = UDim2.fromScale(1, 1),
			Tint = Theme.Colors.PanelRaised,
			Rotation = Splat.rotation(1),
			Transparency = PLAY_SPLAT_TRANSPARENCY,
			ZIndex = 2,
			Parent = art,
		})
		local glyph = Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromOffset(PLAY_GLYPH_SIZE, PLAY_GLYPH_SIZE)
		glyph.FontFace = Theme.Fonts.Bold
		glyph.TextSize = PLAY_GLYPH_SIZE
		glyph.TextColor3 = Theme.Colors.Text
		glyph.Text = Theme.Glyphs.Play
		glyph.ZIndex = 3
		glyph.Parent = art

		local words = playFace:FindFirstChild("Content")
		if words ~= nil and words:IsA("Frame") then
			-- The word and its line at the foot of the tile, the word as large as the tile allows.
			words.ZIndex = 4
			local layout = words:FindFirstChildOfClass("UIListLayout")
			if layout ~= nil then
				layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
			end
			local label = words:FindFirstChild("Label", true)
			local cap = if label ~= nil then label:FindFirstChildOfClass("UITextSizeConstraint") else nil
			if label ~= nil and label:IsA("TextLabel") and cap ~= nil then
				cap.MaxTextSize = PLAY_TEXT_SIZE
				label.Size = UDim2.new(1, 0, 0, PLAY_TEXT_SIZE + 6)
			end
			local line = words:FindFirstChild("Sublabel", true)
			if line ~= nil and line:IsA("TextLabel") then
				line.TextSize = PLAY_LINE_SIZE
				playLine = line
			end
		end
	end

	-- The Loadout tile holds the five pigments: their stripe along its foot, as on its chapter's band.
	local loadoutFace = loadoutButton:Face()
	if loadoutFace ~= nil then
		local stripe = row("Stripe", loadoutFace, 0)
		stripe.AnchorPoint = Vector2.new(0.5, 1)
		stripe.Position = UDim2.new(0.5, 0, 1, -Theme.Sizes.Stroke - Theme.Sizes.PaddingSmall)
		stripe.Size = UDim2.new(1, -Theme.Sizes.CornerTile * 2, 0, STRIPE_HEIGHT)
		stripe.ZIndex = 3
		for index, pigment in ipairs(PigmentConfig.Order) do
			local segment = Instance.new("Frame")
			segment.Name = pigment
			segment.BorderSizePixel = 0
			segment.BackgroundColor3 = Theme.pigmentColor(pigment)
			segment.Size = UDim2.fromScale(1 / #PigmentConfig.Order, 1)
			segment.LayoutOrder = index
			segment.ZIndex = 3
			segment.Parent = stripe
		end
	end

	-- The D-pad walks the grid on its own; from Play it goes into the grid's first column, and back.
	playButton.Instance.NextSelectionRight = shopButton.Instance
	shopButton.Instance.NextSelectionLeft = playButton.Instance
	questsButton.Instance.NextSelectionLeft = playButton.Instance

	----------------------------------------------------------------
	-- Refresh
	----------------------------------------------------------------

	-- The wait, counted locally from the server's last value, once a second while the screen is up.
	local waitedBase = 0
	local waitedAt = os.clock()
	local ticking = false

	local function refreshQueue()
		local line = playLine
		if line == nil then
			return
		end
		local queue = deps.MatchController.getQueue()
		if queue.Queued then
			local waited = math.max(0, math.floor(waitedBase + (os.clock() - waitedAt)))
			line.Text = t("queue.searching", { waited = waited })
		else
			line.Text = t("hub.queue.name")
		end
	end

	local function tick()
		if not screen.Visible or not deps.MatchController.getQueue().Queued then
			ticking = false
			return
		end
		refreshQueue()
		task.delay(TICK_SECONDS, tick)
	end

	local function syncTick()
		if ticking or not screen.Visible or not deps.MatchController.getQueue().Queued then
			return
		end
		ticking = true
		task.delay(TICK_SECONDS, tick)
	end

	local function refresh()
		local data = deps.ClientData.get()
		if data ~= nil then
			local level = data.Progression.Level
			levelSeal:SetText(tostring(level))
			if level >= ProgressionConfig.MaxLevel then
				xpBar:SetProgress(1)
				xpText.Text = t("level.max")
			else
				local needed = ProgressionConfig.xpForLevel(level)
				xpBar:SetProgress(if needed > 0 then data.Progression.XP / needed else 0)
				xpText.Text = t("level.xp", { xp = data.Progression.XP, needed = needed })
			end
			pill:Set(data.Currency.Folios, screen.Visible)
		end
		local counts = Claims.count(data, workspace:GetServerTimeNow())
		battlepassButton:SetBadge(if counts.Pass > 0 then counts.Pass else nil)
		questsButton:SetBadge(if counts.Quests > 0 then counts.Quests else nil)
		dailyButton:SetBadge(if counts.Daily > 0 then "!" else nil)
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if
			section == "*"
			or section == "Progression"
			or section == "Currency"
			or section == "Battlepass"
			or section == "Quests"
			or section == "Daily"
		then
			refresh()
		end
	end)

	trove:Connect(deps.MatchController.QueueChanged, function(queue: Types.QueueSnapshot)
		waitedBase = queue.WaitedSeconds
		waitedAt = os.clock()
		refreshQueue()
		syncTick()
	end)

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		refresh()
		local queue = deps.MatchController.getQueue()
		waitedBase = queue.WaitedSeconds
		waitedAt = os.clock()
		refreshQueue()
		syncTick()
		root:PlayEnter()
		panel:FocusForGamepad(playButton.Instance)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root:PlayExit()
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		trove:Destroy()
	end

	screen = {
		Instance = root.Instance,
		Visible = false,
		Open = open,
		Close = close,
		Destroy = destroy,
	}
	refresh()
	return screen
end

return MenuScreen
