--!strict
-- HudController: the always-on overlay, and the one place that orchestrates it. It builds the HUD's pieces,
-- places them, feeds them the data they draw and routes every server message. The pieces are components of
-- src/ui (D-147):
--   MetaCluster   the level, its XP and the Folios (top-left), in the hub only
--   CombatDock    the player's own health and ink, on an ink plate at the bottom centre, between the thumbs
--   ComboRow      the sequence being pressed, the chain counter and the onboarding's ghost chips, above it
--   ScoreBand     the match, at the top-centre while a snapshot is held
-- and what stays here: the quick bar (bottom-right: Play, Shop and Leaderboard one click away, and the Menu
-- button naming its key), the top-centre column the bands stack in (HudController.topStack), and the toast
-- lane. Every visible text goes through Localize; server Notify payloads carry Strings keys, never text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Button = require(UI.components.Button)
local CombatDock = require(UI.components.CombatDock)
local ComboRow = require(UI.components.ComboRow)
local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local MetaCluster = require(UI.components.MetaCluster)
local QualityConfig = require(Shared.Config.QualityConfig)
local ScoreBand = require(UI.components.ScoreBand)
local ScreenRoot = require(UI.components.ScreenRoot)
local Signal = require(Packages.Signal)
local Theme = require(UI.Theme)
local ThemeConfig = require(Shared.Config.ThemeConfig)
local Toast = require(UI.components.Toast)
local Types = require(Shared.Types)
local UiPrefs = require(UI.UiPrefs)

local log = Log.new("HudController")

export type ToastKind = Toast.Kind

type CombatState = CombatDock.State

type Deps = {
	Localize: any,
	ClientData: any,
	RemoteClient: any,
	SoundController: any,
	ComboController: any,
	CombatController: any,
	MatchController: any,
	MenuController: any,
	VfxController: any,
	InputController: any,
	QualityController: any,
}

local DISPLAY_ORDER = Theme.Layers.Hud
local HUD = ThemeConfig.Hud
-- The bottom stack, from the top: the combo row, then the dock.
local COMBO_ORDER = 1
local DOCK_ORDER = 3
-- On touch the dock keeps this far off the nearest disc, in real pixels.
local DOCK_DISC_CLEARANCE = 12
local MENU_ACTION: InputConfig.ActionId = "Menu"
local GAMEPAD_PREFIX = "Gamepad"
-- The kinds a server message may name. The HUD adds two of its own, by key: a celebration and a reward.
local TOAST_KINDS: { [string]: boolean } = { Info = true, Success = true, Error = true }
-- The moments worth the primary yellow and a splat: a level, a pass tier, a finished quest, the first win of
-- the day (D-147).
local CELEBRATE_KEYS: { [string]: boolean } = {
	["hud.levelUp"] = true,
	["hud.tierUp"] = true,
	["quest.completed"] = true,
	["daily.firstWin"] = true,
}
-- Folios paid out: the coin leads the message, and the amount stands beside it (its `folios` or `amount`).
local REWARD_KEYS: { [string]: boolean } = {
	["daily.claimed"] = true,
	["daily.premium"] = true,
	["quest.reward"] = true,
	["battlepass.reward.folio"] = true,
	["season.rewardGranted"] = true,
}
-- A fight shows no value colour (docs/ART_BIBLE.md rule 11): its rewards and celebrations wait for the hub.
local FIGHT_HELD: { [string]: boolean } = { Reward = true, Celebrate = true }
-- The places a portal takes a player to fight in (PortalConfig.Zones); the rest of the page is the hub.
local ARENA_ZONES: { [string]: boolean } = { Battleground = true, WorldBoss = true }
-- Below the Menu disc, on a touch screen: the gap between the disc and the first message.
local TOAST_UNDER_MENU = 8
-- The quick bar (D-128). The screens a player comes to the hub for were reachable only through the M key,
-- which a small muted "M = Menu" in a corner was the only sign of: a developer testing the game could not
-- find the queue, the shop or the leaderboard. Each is one click away now, and the Menu button names its
-- key. Bottom-right, the one corner nothing else draws in: the top-right is the engine's player list, a
-- CoreGui drawn over every ScreenGui that takes the clicks on its rows, and the top centre is the toasts'
-- and the match and boss bands'. Hidden on a touch-only device, which has its Menu disc, and the three
-- shortcuts are hidden in a match, where queueing and shopping mean nothing. A pointer affordance: its
-- buttons are not gamepad-selectable -- the engine's navigation would carry a selection out of an open
-- panel into them, under its overlay, and leave it there when the panel closed; Select is the gamepad's
-- way to the menu.
local QUICK_SCREENS: { { Screen: string, NameKey: string, Variant: Button.Variant } } = {
	{ Screen = "Play", NameKey = "queue.title", Variant = "Primary" },
	{ Screen = "Shop", NameKey = "menu.shop", Variant = "Secondary" },
	{ Screen = "Leaderboard", NameKey = "leaderboard.title", Variant = "Secondary" },
}
local MENU_KEYS: { [string]: string } = { Keyboard = "hud.hint.keyboard", Gamepad = "hud.hint.gamepad" }
-- Order inside the top-centre column (see buildTopStack): the match band this module draws, and the three bands
-- other controllers draw there, each reading its place through HudController.topStack -- the portal circle the
-- player stands in first, because it is about to move them; the boss after the match; the place they are in
-- last, since it says nothing new until they leave it (TravelController, BossController).
local MATCH_BAND_ORDER = 1
local BAND_ORDERS: { [string]: number } = { Portal = 0, Boss = 2, Place = 3 }

local HudController = {}

-- Every server message, (key, params, kind), fired before the HUD shows anything of it: a screen that waits
-- for one listens here instead of reading a toast (the Play screen and queue.timedOut, D-147).
HudController.Notified = Signal.new()

local localize: any
local clientData: any
local remoteClient: any
local soundController: any
local comboController: any
local vfxController: any
local combatController: any
local matchController: any

local root: ScreenRoot.ScreenRoot
local metaCluster: MetaCluster.MetaCluster
local combatDock: CombatDock.CombatDock
local comboRow: ComboRow.ComboRow
local bottomStack: Frame
local scoreBand: ScoreBand.ScoreBand
local quickBar: Frame
local quickButtons: { Button.Button } = {}
local menuButton: Button.Button
local toast: Toast.Toast
local toastRoot: ScreenRoot.ScreenRoot
local topStack: Frame
local notifyWarned = false
local hintSource: string? = nil -- "Keyboard" | "Gamepad" | "Touch", from the last input type
local menuController: any
local inputController: any
local qualityController: any
local inMatch = false
-- In the Battleground or the World Boss's arena (setPlace): a fight, like a match.
local inArena = false

-- The one top-centre column. The match band, the World Boss band and the toast queue all used to
-- declare the same anchor and the same position, so they drew on top of each other: a round-won toast
-- hid the score and the countdown digit in every ranked match, and during an event the wider boss band
-- covered the match band outright. They are now children of this frame with a vertical layout, so
-- whatever is showing stacks instead of overlapping. A UIListLayout allocates nothing for an invisible
-- child, so a hidden band costs no gap.
--
-- LayoutOrder is deliberate: persistent state first (match, then boss), transient messages last, so a
-- toast can never push the information the player needs off its place. The portal circle a player stands in
-- goes above them all and the place they are in below (MATCH_BAND_ORDER, BAND_ORDERS).
local function buildTopStack(parent: Instance)
	topStack = Instance.new("Frame")
	topStack.Name = "TopStack"
	topStack.BackgroundTransparency = 1
	topStack.AnchorPoint = Vector2.new(0.5, 0)
	topStack.Position = UDim2.new(0.5, 0, 0, Theme.Sizes.Padding)
	topStack.Size = UDim2.fromOffset(0, 0)
	topStack.AutomaticSize = Enum.AutomaticSize.XY
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = topStack
	-- Bounded and clipped. The column is as tall as its visible children, and a player can legitimately
	-- hold a match snapshot and a World Boss snapshot at once: the server pushes BossChanged to everyone
	-- on the server, not only to the participants. Without a ceiling the two bands could reach down into
	-- the combat dock, which sits bottom-centre in the same column of screen.
	local ceiling = Instance.new("UISizeConstraint")
	ceiling.MaxSize = Vector2.new(math.huge, HUD.TopStackMaxHeight)
	ceiling.Parent = topStack
	topStack.ClipsDescendants = true
	topStack.Parent = parent
end

-- A button as wide as its label: the bar reads right to left from the corner, whatever the language.
local function quickButton(nameKey: string, variant: Button.Variant, order: number, onClick: () -> ()): Button.Button
	local button = Button.new({
		Name = nameKey,
		Text = "",
		Variant = variant,
		Size = UDim2.fromOffset(0, Theme.Sizes.ButtonHeight),
		LayoutOrder = order,
		Parent = quickBar,
		OnClick = function()
			soundController.play("UiClick")
			onClick()
		end,
	})
	button.Instance.AutomaticSize = Enum.AutomaticSize.X
	button.Instance.Selectable = false
	return button
end

local function buildQuickBar(parent: Instance)
	local pad = Theme.Sizes.Padding
	quickBar = Instance.new("Frame")
	quickBar.Name = "QuickBar"
	quickBar.BackgroundTransparency = 1
	quickBar.AnchorPoint = Vector2.new(1, 1)
	quickBar.Position = UDim2.new(1, -pad, 1, -pad)
	quickBar.Size = UDim2.fromOffset(0, Theme.Sizes.ButtonHeight)
	quickBar.AutomaticSize = Enum.AutomaticSize.XY
	quickBar.Visible = false -- refreshQuickBar shows it for the device in use
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = quickBar
	quickBar.Parent = parent

	for index, entry in ipairs(QUICK_SCREENS) do
		table.insert(
			quickButtons,
			quickButton(entry.NameKey, entry.Variant, index, function()
				menuController.open(entry.Screen)
			end)
		)
	end
	menuButton = quickButton("Menu", "Secondary", #QUICK_SCREENS + 1, function()
		menuController.toggle()
	end)
end

-- The bottom centre, between the thumbs: the combo row over the dock, off the bottom edge. The bottom-left
-- corner is the engine thumbstick's on touch, and the bottom-right the discs' or the quick bar's.
local function buildBottomStack(parent: Instance, touch: boolean)
	bottomStack = Instance.new("Frame")
	bottomStack.Name = "BottomStack"
	bottomStack.BackgroundTransparency = 1
	bottomStack.AnchorPoint = Vector2.new(0.5, 1)
	bottomStack.Position = UDim2.new(0.5, 0, 1, -(if touch then HUD.DockBottomPadTouch else HUD.DockBottomPad))
	bottomStack.Size = UDim2.new()
	bottomStack.AutomaticSize = Enum.AutomaticSize.XY
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, HUD.ChipRowGap)
	layout.Parent = bottomStack
	bottomStack.Parent = parent

	comboRow = ComboRow.new({ Parent = bottomStack, Localize = localize, LayoutOrder = COMBO_ORDER })
	combatDock = CombatDock.new({
		Parent = bottomStack,
		Screen = root.Instance,
		LayoutOrder = DOCK_ORDER,
		Width = if touch then HUD.DockWidthTouchMax else HUD.DockWidthPointer,
	})
end

local function build()
	root = ScreenRoot.new({ Name = "Hud", DisplayOrder = DISPLAY_ORDER })
	local content = root.Content

	metaCluster = MetaCluster.new({ Parent = content, Localize = localize })
	buildBottomStack(content, UserInputService.TouchEnabled)

	buildQuickBar(content)

	buildTopStack(content)
	scoreBand = ScoreBand.new({ Parent = topStack, Localize = localize, LayoutOrder = MATCH_BAND_ORDER })

	-- The toast queue gets its own ScreenGui on Theme.Layers.Toast, ABOVE every menu screen. It is the
	-- only surface a server message has, and screens now sit deterministically above the HUD, so leaving
	-- it inside the HUD made every server message unreadable while a panel was open: the panel covered it
	-- and the panel's dim overlay covered the rest. A player refused a purchase saw nothing at all.
	--
	-- It also stops the column from growing down over the bars: the column holds the two bands only, so
	-- their combined height is bounded by the match and boss layouts rather than by how many messages
	-- happen to be on screen. The messages follow the player's own text size, as the menus do.
	toastRoot = ScreenRoot.new({ Name = "Toasts", DisplayOrder = Theme.Layers.Toast, TextScalable = true })
	toast = Toast.new({
		Name = "Toasts",
		Parent = toastRoot.Content,
		Lane = if Theme.touchOnly() then "Touch" else "Pointer",
	})
end

-- On a touch screen the lane hangs under the Menu disc, which InputController lays out in screen pixels:
-- turned into the design units of the toasts' own safe area.
local function placeToasts()
	local menu = inputController.touchRects()[MENU_ACTION]
	if menu == nil then
		return
	end
	local safeArea = toastRoot.Content
	local top = (menu.Max.Y - safeArea.AbsolutePosition.Y) / toastRoot:GetScale()
	toast:SetTop(math.max(Theme.Sizes.Padding, top + TOAST_UNDER_MENU))
end

-- On touch the dock is as wide as the gap between the thumbs allows, and never wider than its token: from the
-- centre of the screen to the nearest disc, less a clearance, on both sides (InputController.touchRects).
local function fitDock()
	local nearest = math.huge
	for _, rect in pairs(inputController.touchRects()) do
		nearest = math.min(nearest, rect.Min.X)
	end
	if nearest == math.huge then
		return
	end
	local safeArea = root.Content
	local centre = safeArea.AbsolutePosition.X + safeArea.AbsoluteSize.X / 2
	local free = 2 * (nearest - DOCK_DISC_CLEARANCE - centre)
	if free > 0 then
		combatDock:SetWidth(math.min(HUD.DockWidthTouchMax, free / root:GetScale()))
	end
end

-- The player's own settings the interface follows (UiPrefs): "shakes and flashes", and the lowest graphics
-- tier, which draws no backdrop blots, shimmers or bursts.
local function refreshPrefs(data: Types.ProfileData?)
	if data ~= nil then
		UiPrefs.setShakes(data.Settings.CameraShake ~= false)
	end
	UiPrefs.setLowQuality(qualityController.get() == QualityConfig.Order[#QualityConfig.Order])
end

-- A match or an arena: fewer messages at once, none in a value colour (rule 11), and no level or Folios.
local function refreshFight()
	local fighting = inMatch or inArena
	toast:SetMaxVisible(if fighting then Theme.Timing.Toast.MaxVisibleMatch else Theme.Timing.Toast.MaxVisibleHub)
	toast:Hold(if fighting then FIGHT_HELD else {})
	metaCluster:SetVisible(not (inMatch or inArena))
end

-- The top-centre column the bands share, plus the LayoutOrder the band `band` must use: the boss's by default,
-- the portal circle's and the place's for TravelController. They parent their bands here instead of opening a
-- second ScreenGui at the same DisplayOrder, which had no defined draw order against this one.
--
-- At most three stack outside a match -- a portal band and a place band are about 50 units each and the boss
-- band 118 with its warning up -- which with the column's two gaps stays under HUD.TopStackMaxHeight. In a match
-- the portal and the place bands are never up: no circle moves a player in a match (PortalService), and a match
-- ends a Battleground membership (BattlegroundService's roster).
function HudController.topStack(band: ("Boss" | "Place" | "Portal")?): (Frame?, number)
	return topStack, BAND_ORDERS[band or "Boss"]
end

-- Shows `pigments` as ghost chips, or clears them with nil (OnboardingController).
function HudController.showGhostSequence(pigments: { string }?)
	comboRow:ShowGhosts(pigments)
end

-- One accepted cast, with the chain length the server counted for it.
local function onLocalCast(_glyphId: string, chain: number)
	comboRow:Cast(chain)
end

-- Touch players read the on-screen Menu button, so the hint only targets keyboard and gamepad.
local function sourceFor(inputType: Enum.UserInputType): string
	if string.sub(inputType.Name, 1, #GAMEPAD_PREFIX) == GAMEPAD_PREFIX then
		return "Gamepad"
	end
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	return "Keyboard"
end

-- The Menu button names the key that opens the menu. On a gamepad that is an Enum.KeyCode name, which
-- reads as code ("ButtonSelect"), so the button's own name is shown instead.
local function menuKeyText(source: string, data: Types.ProfileData): string
	if source == "Gamepad" then
		return localize.t("hud.key.select")
	end
	local saved = data.Settings.Keyboard
	return saved[MENU_ACTION] or InputConfig.DefaultKeyboard[MENU_ACTION]
end

local function refreshQuickBar(data: Types.ProfileData)
	local source = sourceFor(UserInputService:GetLastInputType())
	hintSource = source
	if source == "Touch" then
		quickBar.Visible = false
		return
	end
	for index, entry in ipairs(QUICK_SCREENS) do
		local button = quickButtons[index]
		button:SetText(localize.t(entry.NameKey))
		button.Instance.Visible = not inMatch
	end
	menuButton:SetText(localize.t(MENU_KEYS[source], { menu = menuKeyText(source, data) }))
	quickBar.Visible = true
end

local function refreshCombat(state: CombatState)
	combatDock:SetState(state)
	if state.Health <= 0 then
		-- A caster who fell has no chain any more.
		comboRow:FadeStreak()
	end
end

local function refreshMatch(snapshot: Types.MatchSnapshot?)
	local active = snapshot ~= nil
	if active ~= inMatch then
		inMatch = active
		for _, button in ipairs(quickButtons) do
			button.Instance.Visible = not active
		end
		refreshFight()
	end
	scoreBand:Set(snapshot)
end

local function refreshProfile(section: string)
	local data: Types.ProfileData? = clientData.get()
	if data == nil then
		return
	end
	if section == "*" or section == "Progression" then
		metaCluster:SetProgression(data.Progression)
	end
	if section == "*" or section == "Currency" then
		metaCluster:SetCurrency(data.Currency)
	end
	if section == "*" or section == "Settings" then
		refreshQuickBar(data)
		refreshPrefs(data)
	end
end

-- The Folios a reward names, for its chip: `folios` in most rewards, `amount` in the pass's and the season's.
local function amountOf(params: { [string]: any }?): number?
	if params == nil then
		return nil
	end
	local amount = params.folios or params.amount
	return if type(amount) == "number" and amount > 0 then amount else nil
end

-- Every message goes out through here: a celebration or a reward by its key, anything else as its kind.
local function show(key: string, params: { [string]: any }?, kind: ToastKind)
	local text = localize.t(key, params)
	if CELEBRATE_KEYS[key] then
		toast:Show(text, "Celebrate")
	elseif REWARD_KEYS[key] then
		toast:Show(text, "Reward", amountOf(params))
	else
		toast:Show(text, kind)
	end
end

local function onNotify(payload: any)
	if type(payload) ~= "table" or type(payload.Key) ~= "string" then
		if not notifyWarned then
			notifyWarned = true
			log.warn("malformed Notify payload dropped (%s)", typeof(payload))
		end
		return
	end
	local params = if type(payload.Params) == "table" then payload.Params else nil
	local kind: ToastKind = if TOAST_KINDS[payload.Kind] then payload.Kind else "Info"
	HudController.Notified:Fire(payload.Key, params, kind)
	if toast == nil then
		-- Same reason as showLocalToast: a HUD that never built must not turn every server message into
		-- an error on the remote handler.
		return
	end
	show(payload.Key, localize.resolveParams(params), kind)
	if type(payload.Sfx) == "string" then
		soundController.play(payload.Sfx)
	end
end

-- Client-originated feedback (combo resets, capture hints…): `key` is a Strings key.
--
-- Tolerates a HUD that never built. A message is worth losing; raising here is not, because the callers
-- are input handlers that fire several times a second, so one failed build turned into a wall of errors
-- that buried the one line naming the real cause.
function HudController.showLocalToast(key: string, params: { [string]: any }?, kind: ToastKind?)
	if toast == nil then
		return
	end
	show(key, params, kind or "Info")
end

-- Where a portal just took the player (TravelController, once it has fired Travelled): the Battleground and
-- the World Boss's arena are fights, like a match; anywhere else is the hub.
function HudController.setPlace(zoneId: string)
	local arena = ARENA_ZONES[zoneId] == true
	if arena == inArena then
		return
	end
	inArena = arena
	if toast ~= nil then
		refreshFight()
	end
end

function HudController.Init(deps: Deps)
	localize = deps.Localize
	clientData = deps.ClientData
	remoteClient = deps.RemoteClient
	soundController = deps.SoundController
	comboController = deps.ComboController
	vfxController = deps.VfxController
	combatController = deps.CombatController
	matchController = deps.MatchController
	menuController = deps.MenuController
	inputController = deps.InputController
	qualityController = deps.QualityController
	build()
end

function HudController.Start()
	clientData.Changed:Connect(refreshProfile)
	refreshProfile("*")
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if sourceFor(inputType) ~= hintSource then
			refreshProfile("Settings")
		end
	end)
	comboController.SequenceChanged:Connect(function(sequence: { string })
		comboRow:SetSequence(sequence)
	end)
	comboController.SequenceBroken:Connect(function()
		comboRow:FadeStreak()
	end)
	vfxController.LocalCast:Connect(onLocalCast)
	combatController.StateChanged:Connect(refreshCombat)
	refreshCombat(combatController.getState())
	matchController.MatchChanged:Connect(refreshMatch)
	refreshMatch(matchController.getMatch())
	remoteClient.on("Notify", onNotify)
	inputController.TouchLayoutChanged:Connect(placeToasts)
	placeToasts()
	if UserInputService.TouchEnabled then
		inputController.TouchLayoutChanged:Connect(fitDock)
		fitDock()
	end
	qualityController.Changed:Connect(function()
		refreshPrefs(clientData.get())
	end)
	refreshPrefs(clientData.get())
	log.info("started")
end

return HudController
