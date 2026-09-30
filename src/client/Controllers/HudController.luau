--!strict
-- HudController: the always-on overlay, and the one place that orchestrates it. It builds the HUD's pieces,
-- places them, feeds them the data they draw and routes every server message. The pieces are components of
-- src/ui (D-147):
--   MetaCluster   the level, its XP, the Folios, the claims waiting and the queue, in the hub only
--   CombatDock    the player's own health and ink, on an ink plate at the bottom centre, between the thumbs
--   Hotbar        the equipped glyphs and their cooldowns, over the dock (the keys that cast them with a
--                 pointer, pips inside the dock on touch)
--   ComboRow      the sequence being pressed, the chain counter and the onboarding's ghost chips, above it
--   ScoreBand     the match, at the top-centre while a snapshot is held
--   Banner        the match's centre splashes (found, the count, the fight, a round) and the takedown pop
--   SpectatePlate who an eliminated player watches, in the dock's place (SpectateController)
-- and what stays here: the quick bar (bottom-right: Play, Shop and Leaderboard one click away, and the Menu
-- button beside the key that opens it, badged with what waits to be claimed; in a fight only the Menu, a small
-- word-only pill beside its key, D-179), on touch the Play sticker left of
-- the Menu disc, the top-centre column the bands stack in (HudController.topStack), and the toast lane. Every
-- visible text goes through Localize; server Notify payloads carry Strings keys, never text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Banner = require(UI.components.Banner)
local Button = require(UI.components.Button)
local Claims = require(UI.Claims)
local CombatDock = require(UI.components.CombatDock)
local ComboRow = require(UI.components.ComboRow)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Hotbar = require(UI.components.Hotbar)
local Icon = require(UI.components.Icon)
local InputConfig = require(Shared.Config.InputConfig)
local Keycap = require(UI.components.Keycap)
local Log = require(Shared.Util.Log)
local MatchSplash = require(Shared.Pure.MatchSplash)
local MetaCluster = require(UI.components.MetaCluster)
local Motion = require(UI.Motion)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local QualityConfig = require(Shared.Config.QualityConfig)
local ScoreBand = require(UI.components.ScoreBand)
local ScreenRoot = require(UI.components.ScreenRoot)
local Signal = require(Packages.Signal)
local SpectatePlate = require(UI.components.SpectatePlate)
local Theme = require(UI.Theme)
local ThemeConfig = require(Shared.Config.ThemeConfig)
local Toast = require(UI.components.Toast)
local TouchCluster = require(Shared.Pure.TouchCluster)
local Types = require(Shared.Types)
local UiPrefs = require(UI.UiPrefs)

local log = Log.new("HudController")

export type ToastKind = Toast.Kind

type CombatState = CombatDock.State & Hotbar.State

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
	TravelController: any,
}

local DISPLAY_ORDER = Theme.Layers.Hud
local HUD = ThemeConfig.Hud
-- The bottom stack, from the top: the combo row, with a pointer the air over the hotbar and the hotbar, then the
-- dock.
local COMBO_ORDER = 1
local LIFT_ORDER = 2
local HOTBAR_ORDER = 3
local DOCK_ORDER = 4
-- On touch the dock keeps this far off the nearest disc, in real pixels, and stays between these widths.
local DOCK_DISC_CLEARANCE = 12
local DOCK_SPAN = { Clearance = DOCK_DISC_CLEARANCE, Widest = HUD.DockWidthTouchMax, Narrowest = HUD.DockWidthTouchMin }
local MENU_ACTION: InputConfig.ActionId = "Menu"
local MENU_NAME_KEY = "action.menu"
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
-- The words of the amount's chip: the sentence's own Folios, grouped the same way (Strings.Quantities).
local REWARD_CHIP_KEY = "reward.folios"
-- A refused cast is said under the chips, where the player's eyes already are, never as a toast (D-147). A
-- cooldown also flashes the glyph's slot on the hotbar.
local INLINE_KEYS: { [string]: boolean } = {
	["hud.cast.cooldown"] = true,
	["hud.cast.notEnoughInk"] = true,
	["hud.cast.locked"] = true,
	["hud.cast.notEquipped"] = true,
	["hud.cast.failed"] = true,
	["hud.combo.noMatch"] = true,
	["hud.combo.dissipated"] = true,
}
local COOLDOWN_KEY = "hud.cast.cooldown"
-- A chain's refund is ink: the ink bar says it, and the counter over the chips says the chain.
local CHAIN_KEY = "hud.cast.chain"
-- The next pigments are hinted after one press or two: one step ahead, never the whole tree.
local HINT_MIN_PRESSES = 1
local HINT_MAX_PRESSES = 2
-- The names the sequence's hints and the onboarding's go by on the touch discs (InputController.setHints).
local SEQUENCE_HINTS = "Sequence"
local ONBOARDING_HINTS = "Onboarding"
-- The daily reward opens by itself, once a session (offerDaily).
local DAILY_SCREEN = "Daily"
-- The rounds the centre splash already says (Banner, from the snapshots): the same words again as a toast
-- would only be the same news twice. The player's own takedown pops at the centre too, and its toast keeps
-- the XP it paid.
local SPLASH_KEYS: { [string]: boolean } = { ["match.roundWon"] = true, ["match.roundLost"] = true }
local TAKEDOWN_KEY = "hud.playerKill"
-- A fight shows no value colour (docs/ART_BIBLE.md rule 11): its rewards and celebrations wait for the hub.
local FIGHT_HELD: { [string]: boolean } = { Reward = true, Celebrate = true }
-- The places a portal takes a player to fight in (PortalConfig.Zones); the rest of the page is the hub.
local ARENA_ZONES: { [string]: boolean } = { Battleground = true, WorldBoss = true }
local ERASURE_ZONE = "WorldBoss"
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
-- way to the menu. It stands as a column in that corner, the Menu at the foot: a row of four words was 630
-- to 690 units wide and covered the right third of the dock's bars on any window narrower than about 1880
-- (a 1366 laptop lays out 1366 units wide), and a column a word wide stays clear of the bottom stack from the
-- narrowest window a pointer plays in (tests/HudFit.spec.luau).
local QUICK_SCREENS: { { Screen: string, NameKey: string, Variant: Button.Variant } } = {
	{ Screen = "Play", NameKey = "queue.title", Variant = "Primary" },
	{ Screen = "Shop", NameKey = "menu.shop", Variant = "Secondary" },
	{ Screen = "Leaderboard", NameKey = "leaderboard.title", Variant = "Secondary" },
}
-- Each shortcut's icon, before its word (D-147).
local QUICK_ICONS: { [string]: Icon.Name } = { Play = "Play", Shop = "Coin", Leaderboard = "Podium" }
-- On a phone the queue is one tap away too: a Play sticker left of the Menu disc, in the hub (D-147).
local PLAY_SCREEN = "Play"
local PLAY_STICKER_HEIGHT = 44
local PLAY_STICKER_GAP = 8
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
local hotbar: Hotbar.Hotbar
local bottomStack: Frame
local spectatePlate: SpectatePlate.SpectatePlate
-- The dock's own scale, which carries it out while its player watches and back with their next life.
local dockScale: UIScale
local spectateToken = 0
local scoreBand: ScoreBand.ScoreBand
local banner: Banner.Banner
-- The match snapshot before the latest, which the splashes are told apart from.
local lastMatch: Types.MatchSnapshot? = nil
local quickBar: Frame
-- The Menu button and its key cap, side by side at the foot of the quick bar.
local menuRow: Frame
local quickButtons: { Button.Button } = {}
local menuButton: Button.Button
-- The Menu in a fight: the board's small pill, its word alone (the hub's button carries its icon and its badge).
local menuPill: Button.Button
-- The key that opens the menu, drawn beside the Menu button for the device in use.
local menuKey: Keycap.Keycap? = nil
local menuKeyDevice: Keycap.Device? = nil
local playSticker: Button.Button? = nil
-- Whether a wait for the day's turn is already pending: one at a time, however often the claims are counted.
local dayTurnPending = false
-- The equipped glyphs as the touch discs weigh them, and the pigments the ink can pay for (touch only).
local equipped: { TouchCluster.Recipe }? = nil
local payable: { [string]: boolean } = {}
-- The keys the hotbar draws, which the onboarding's ghosts stand under too.
local hotbarKeys: ComboRow.Keys? = nil
local dailyOffered = false
local toast: Toast.Toast
local toastRoot: ScreenRoot.ScreenRoot
local topStack: Frame
local notifyWarned = false
local hintSource: string? = nil -- "Keyboard" | "Gamepad" | "Touch", from the last input type
local menuController: any
local inputController: any
local qualityController: any
local travelController: any
local inMatch = false
-- In the Battleground or the World Boss's arena (setPlace): a fight, like a match. Which of the two: an arena
-- the server lets the player out of without a portal is left only if it is the one they are in (leftPlace).
local inArena = false
local arenaZone: string? = nil
local queued = false

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
	topStack.Position = UDim2.new(0.5, 0, 0, HUD.TopPad)
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

-- A button as wide as its label, hugging the right edge whatever the language. The button plays its own click.
-- Given no icon it is the fight's compact pill: its word alone, as short as a touch target.
local function quickButton(
	nameKey: string,
	variant: Button.Variant,
	order: number,
	icon: Icon.Name?,
	parent: Instance,
	onClick: () -> ()
): Button.Button
	local compact = icon == nil
	local button = Button.new({
		Name = nameKey,
		Text = "",
		Variant = variant,
		Icon = icon,
		Compact = compact,
		Size = UDim2.fromOffset(0, if compact then Theme.MinTouchTarget else Theme.Sizes.ButtonHeight),
		LayoutOrder = order,
		Parent = parent,
		OnClick = onClick,
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
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = quickBar
	quickBar.Parent = parent

	for index, entry in ipairs(QUICK_SCREENS) do
		table.insert(
			quickButtons,
			quickButton(entry.NameKey, entry.Variant, index, QUICK_ICONS[entry.Screen], quickBar, function()
				menuController.open(entry.Screen)
			end)
		)
	end
	menuRow = Instance.new("Frame")
	menuRow.Name = "MenuRow"
	menuRow.BackgroundTransparency = 1
	menuRow.LayoutOrder = #QUICK_SCREENS + 1
	menuRow.Size = UDim2.fromOffset(0, Theme.Sizes.ButtonHeight)
	menuRow.AutomaticSize = Enum.AutomaticSize.XY
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	rowLayout.Parent = menuRow
	menuRow.Parent = quickBar
	-- The key cap stands before the Menu button (refreshMenuKey): the hub's, or in a fight the pill (refreshHub).
	menuButton = quickButton(MENU_NAME_KEY, "Secondary", 2, "Burger", menuRow, function()
		menuController.toggle()
	end)
	menuPill = quickButton(MENU_NAME_KEY, "Secondary", 3, nil, menuRow, function()
		menuController.toggle()
	end)
	menuPill.Instance.Visible = false
end

-- The touch Play sticker, placed once the discs are (placePlaySticker).
local function buildPlaySticker(parent: Instance)
	local sticker = Button.new({
		Name = "PlaySticker",
		Text = localize.t("queue.title"),
		Variant = "Primary",
		Icon = "Play",
		Size = UDim2.fromOffset(0, PLAY_STICKER_HEIGHT),
		Parent = parent,
		OnClick = function()
			menuController.open(PLAY_SCREEN)
		end,
	})
	sticker.Instance.AnchorPoint = Vector2.new(1, 0.5)
	sticker.Instance.Selectable = false
	sticker.Instance.Visible = false
	playSticker = sticker
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
	if not touch then
		-- With a pointer the combo row stands clear of the hotbar's keys (the board's): the list's gap on each
		-- side of this makes HUD.ComboLift more than the one gap it had. On touch the dock's own pips are there.
		local lift = Instance.new("Frame")
		lift.Name = "ComboLift"
		lift.BackgroundTransparency = 1
		lift.Size = UDim2.fromOffset(0, HUD.ComboLift - HUD.ChipRowGap)
		lift.LayoutOrder = LIFT_ORDER
		lift.Parent = bottomStack
	end
	combatDock = CombatDock.new({
		Parent = bottomStack,
		Screen = root.Instance,
		LayoutOrder = DOCK_ORDER,
		Width = if touch then HUD.DockWidthTouchMax else HUD.DockWidthPointer,
		Pips = touch,
	})
	-- Where the dock was, while the player is out of the round and watching a teammate.
	spectatePlate = SpectatePlate.new({ Parent = bottomStack, Localize = localize, LayoutOrder = DOCK_ORDER })
	dockScale = Instance.new("UIScale")
	dockScale.Parent = combatDock.Instance
	-- On touch the discs already name the pigments: the hotbar is a row of pips inside the dock.
	hotbar = Hotbar.new({
		Parent = if touch then combatDock.PipRow or bottomStack else bottomStack,
		Mode = if touch then "Pips" else "Slots",
		Localize = localize,
		LayoutOrder = HOTBAR_ORDER,
	})
end

local function build()
	root = ScreenRoot.new({ Name = "Hud", DisplayOrder = DISPLAY_ORDER })
	local content = root.Content

	-- Bottom-left with a pointer, the engine's chat being top-left; top-left on touch, the thumbstick's corner
	-- being bottom-left.
	metaCluster = MetaCluster.new({
		Parent = content,
		Localize = localize,
		Corner = if Theme.touchOnly() then "Top" else "Bottom",
		OnOpen = function(screen: string, args: any?)
			menuController.open(screen, args)
		end,
		OnLeaveQueue = function()
			matchController.leaveQueue()
		end,
	})
	buildBottomStack(content, UserInputService.TouchEnabled)

	buildQuickBar(content)
	if UserInputService.TouchEnabled then
		buildPlaySticker(content)
	end

	buildTopStack(content)
	scoreBand = ScoreBand.new({ Parent = topStack, Localize = localize, LayoutOrder = MATCH_BAND_ORDER })
	banner = Banner.new({ Localize = localize })

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
	local top = toastRoot:ToContent(Vector2.new(menu.Min.X, menu.Max.Y)).Y
	toast:SetTop(math.max(Theme.Sizes.Padding, top + TOAST_UNDER_MENU))
end

-- On touch the dock is as wide as the gap between the thumbs allows, and never wider than its token: from the
-- centre of the screen to the nearest disc, less a clearance, on both sides (InputController.touchRects). On a
-- phone too small for that, the whole bottom stack slides left of the discs (TouchCluster.dockSpan).
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
	local width, offset = TouchCluster.dockSpan(nearest, centre, root:GetScale(), DOCK_SPAN)
	combatDock:SetWidth(width)
	bottomStack.Position = UDim2.new(0.5, offset, 1, -HUD.DockBottomPadTouch)
end

-- The player's own settings the interface follows (UiPrefs): "shakes and flashes", and the lowest graphics
-- tier, which draws no backdrop blots, shimmers or bursts.
local function refreshPrefs(data: Types.ProfileData?)
	if data ~= nil then
		UiPrefs.setShakes(data.Settings.CameraShake ~= false)
	end
	UiPrefs.setLowQuality(qualityController.get() == QualityConfig.Order[#QualityConfig.Order])
end

-- What waits to be claimed (Claims), as a badge on the Menu button: none in a fight, where the badge's yellow
-- would be a value colour (rule 11). A new day brings a new daily reward and new quests with no change to the
-- profile, so the count is made again when the day turns -- and as soon as the client has heard the servers'
-- clock, which it has not yet when the profile first arrives (Claims.nextCountIn). The claims are counted on
-- every queue snapshot, so only one wait for that turn is ever pending.
local function refreshClaims()
	local now = Workspace:GetServerTimeNow()
	local counts = Claims.count(clientData.get(), now)
	menuButton:SetBadge(if inMatch or inArena then nil else counts.Total)
	metaCluster:SetClaims(counts)
	if dayTurnPending then
		return
	end
	dayTurnPending = true
	task.delay(Claims.nextCountIn(now), function()
		dayTurnPending = false
		refreshClaims()
	end)
end

-- What only the hub shows (rule 11): the shortcuts and the Play sticker, both in the value yellow, and the
-- claims. The sticker also stands aside while the player queues, and until the discs are laid out.
local function refreshHub()
	local hub = not (inMatch or inArena)
	for _, button in ipairs(quickButtons) do
		button.Instance.Visible = hub
	end
	menuButton.Instance.Visible = hub
	menuPill.Instance.Visible = not hub
	local sticker = playSticker
	if sticker ~= nil then
		sticker.Instance.Visible = hub and not queued and inputController.touchRects()[MENU_ACTION] ~= nil
	end
	refreshClaims()
end

-- A match or an arena: fewer messages at once, none in a value colour (rule 11), and no level or Folios.
local function refreshFight()
	local fighting = inMatch or inArena
	toast:SetMaxVisible(if fighting then Theme.Timing.Toast.MaxVisibleMatch else Theme.Timing.Toast.MaxVisibleHub)
	toast:Hold(if fighting then FIGHT_HELD else {})
	toast:SetFight(fighting)
	metaCluster:SetVisible(not (inMatch or inArena))
	refreshHub()
end

-- The Play sticker, left of the Menu disc and level with it, in the HUD's design units.
local function placePlaySticker()
	local sticker = playSticker
	local menu = inputController.touchRects()[MENU_ACTION]
	if sticker == nil or menu == nil then
		return
	end
	local at = root:ToContent(Vector2.new(menu.Min.X, (menu.Min.Y + menu.Max.Y) / 2))
	sticker.Instance.Position = UDim2.fromOffset(at.X - PLAY_STICKER_GAP, at.Y)
	refreshHub()
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

-- The HUD's own safe-area frame, for a controller that places something of its own over the fight: the boss's
-- warning (BossController). Nil when the HUD never built.
function HudController.overlay(): Frame?
	return if root ~= nil then root.Content else nil
end

-- A boss attack is telegraphed (BossController), or has landed: while its warning is up, the toasts hold their
-- turn, so nothing new crosses the eye's way to it.
function HudController.setWarning(active: boolean)
	if toast ~= nil then
		toast:Pause(active)
		banner:Suppress(active)
	end
end

-- An eliminated player watches `name` (SpectateController): the dock leaves on the exit spring and the plate
-- saying who pops into its place, its discs calling `onCycle`; with nil, the plate leaves and the dock comes
-- back. The two never stand in the stack together.
function HudController.showSpectating(name: string?, onCycle: ((step: number) -> ())?)
	spectateToken += 1
	local token = spectateToken
	if name ~= nil and onCycle ~= nil then
		Motion.to(dockScale, { Scale = 0 }, "UiExit", function()
			if token == spectateToken then
				combatDock.Instance.Visible = false
				spectatePlate:Show(name, onCycle)
			end
		end)
		return
	end
	spectatePlate:Hide(function()
		if token == spectateToken then
			combatDock.Instance.Visible = true
			Motion.to(dockScale, { Scale = 1 }, "UiPop")
		end
	end)
end

-- Shows `pigments` as ghost chips, or clears them with nil (OnboardingController): with a pointer each under
-- the key that presses it, and on touch the discs that press them breathe.
function HudController.showGhostSequence(pigments: { string }?)
	comboRow:ShowGhosts(pigments, if hintSource == "Touch" then nil else hotbarKeys)
	inputController.setHints(ONBOARDING_HINTS, pigments or {})
end

-- One accepted cast, with the chain length the server counted for it.
local function onLocalCast(glyphId: string, chain: number)
	local def = GlyphConfig.byId(glyphId)
	comboRow:Cast(chain, if def ~= nil then def.Pigment else nil)
end

-- The sequence as it grows: its chips, and the pigments that go on from it after a press or two -- faint
-- chips after the live ones, and on touch the discs that go on breathing, where the thumb is.
local function onSequence(sequence: { string })
	comboRow:SetSequence(sequence)
	local hinted = #sequence >= HINT_MIN_PRESSES and #sequence <= HINT_MAX_PRESSES
	local nexts = if hinted then comboController.continuations(sequence) else {}
	comboRow:SetContinuations(nexts)
	inputController.setHints(SEQUENCE_HINTS, nexts)
end

-- The glyph the sequence already is, while the controller waits for more: named over the chips, and its cost
-- marked on the ink bar.
local function onPreview(glyphId: string?, windowSeconds: number?)
	comboRow:SetPreview(glyphId, windowSeconds)
	local def = if glyphId ~= nil then GlyphConfig.byId(glyphId) else nil
	combatDock:SetCost(if def ~= nil then def.Cost else nil)
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

-- The key that opens the menu, the player's own on the device in use, as a cap beside the Menu button (a
-- pad's button by the name players know it by: Keycap.label). A cap is rebuilt only when the device changes,
-- since a pad's cap is round.
local function refreshMenuKey(source: string, data: Types.ProfileData)
	local device: Keycap.Device = if source == "Gamepad" then "Gamepad" else "Keyboard"
	local saved = if device == "Gamepad" then data.Settings.Gamepad else data.Settings.Keyboard
	local defaults = if device == "Gamepad" then InputConfig.DefaultGamepad else InputConfig.DefaultKeyboard
	local key = saved[MENU_ACTION] or defaults[MENU_ACTION]
	local current = menuKey
	if current ~= nil and menuKeyDevice == device then
		current:SetKey(key)
		return
	end
	if current ~= nil then
		current:Destroy()
	end
	menuKeyDevice = device
	menuKey = Keycap.new({
		Key = key,
		Device = device,
		Localize = localize,
		LayoutOrder = 1,
		Parent = menuRow,
		Name = "MenuKey",
	})
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
		button.Instance.Visible = not (inMatch or inArena)
	end
	menuButton:SetText(localize.t(MENU_NAME_KEY))
	menuPill:SetText(localize.t(MENU_NAME_KEY))
	refreshMenuKey(source, data)
	quickBar.Visible = true
end

local function refreshCombat(state: CombatState)
	combatDock:SetState(state)
	hotbar:SetState(state)
	local recipes = equipped
	if recipes ~= nil then
		inputController.setAffordable(TouchCluster.affordable(recipes, state.Ink, payable))
	end
	if state.Health <= 0 then
		-- A caster who fell has no chain any more.
		comboRow:FadeStreak()
	end
end

-- Where the player now is: the arena `zone` (an ARENA_ZONES key), a fight like a match, or the hub (nil).
local function place(zone: string?)
	arenaZone = zone
	local arena = zone ~= nil
	if arena == inArena then
		return
	end
	inArena = arena
	if toast ~= nil then
		refreshFight()
	end
end

local function refreshMatch(snapshot: Types.MatchSnapshot?)
	local active = snapshot ~= nil
	if active and not inMatch then
		-- A match takes the player out of any arena (it ends a Battleground membership, and the Erasure lets
		-- a participant go), and the server sends them to the hub when it is over: never back to the arena.
		place(nil)
	end
	if active ~= inMatch then
		inMatch = active
		refreshFight()
	end
	scoreBand:Set(snapshot)
	-- MatchSplash reads a snapshot's plain fields; the phase's literal union is a string to it.
	for _, splash in ipairs(MatchSplash.between(lastMatch :: any, snapshot :: any)) do
		banner:Show(splash.Kind, splash.Digit)
	end
	if snapshot == nil and lastMatch ~= nil then
		banner:Clear()
	end
	lastMatch = snapshot
end

-- The keys the hotbar draws under each glyph: the player's own for each pigment, on the device in use.
local function refreshHotbarKeys(data: Types.ProfileData)
	local gamepad = hintSource == "Gamepad"
	local saved = if gamepad then data.Settings.Gamepad else data.Settings.Keyboard
	-- The config maps are keyed by the ActionId union; the pigments are plain strings here.
	local defaults: { [string]: string } = (
		if gamepad then InputConfig.DefaultGamepad else InputConfig.DefaultKeyboard
	) :: any
	local keys: { [string]: string } = {}
	for _, pigment in ipairs(PigmentConfig.Order) do
		keys[pigment] = saved[pigment] or defaults[pigment]
	end
	hotbar:SetKeys(if gamepad then "Gamepad" else "Keyboard", keys)
	hotbarKeys = { Device = if gamepad then "Gamepad" else "Keyboard", Keys = keys }
end

-- Once a session, a moment after the HUD first sees the profile, the daily reward opens by itself if it waits
-- and nothing else has the player: no fight, no queue, no screen open (D-147). A player who was busy then
-- finds it on its claim seal.
local function offerDaily()
	if dailyOffered then
		return
	end
	dailyOffered = true
	task.delay(Theme.Timing.DailyAutoOpenDelaySeconds, function()
		local waiting = Claims.count(clientData.get(), Workspace:GetServerTimeNow()).Daily > 0
		if waiting and not (inMatch or inArena or queued) and not menuController.isOpen() then
			menuController.open(DAILY_SCREEN)
		end
	end)
end

-- The equipped glyphs as the touch discs weigh them: which pigments lead to one, and at what ink.
local function recipesOf(slots: { string }): { TouchCluster.Recipe }
	local recipes: { TouchCluster.Recipe } = {}
	for _, id in ipairs(slots) do
		local def = GlyphConfig.byId(id)
		if def ~= nil then
			table.insert(recipes, { Combo = def.Combo, Cost = def.Cost })
		end
	end
	return recipes
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
		refreshHotbarKeys(data)
		refreshPrefs(data)
	end
	if section == "*" or section == "Loadout" then
		hotbar:SetLoadout(data.Loadout.Slots)
		equipped = recipesOf(data.Loadout.Slots)
		refreshCombat(combatController.getState())
	end
	if section == "*" or section == "Daily" or section == "Quests" or section == "Battlepass" then
		refreshClaims()
	end
	if section == "*" or section == "Stats" or section == "Daily" then
		metaCluster:SetChecklist({
			Cast = data.Stats.GlyphsCast > 0,
			Match = data.Stats.MatchesPlayed > 0,
			Daily = data.Daily.LastClaimDay > 0,
		})
	end
	offerDaily()
end

-- The Folios a reward names, for its chip: `folios` in most rewards, `amount` in the pass's and the season's,
-- written as the message writes them ("+4 000" in French, "+4,000" in English), never "+4000" beside them.
local function amountOf(params: { [string]: any }?): string?
	if params == nil then
		return nil
	end
	local amount = params.folios or params.amount
	if type(amount) ~= "number" or amount <= 0 then
		return nil
	end
	return localize.t(REWARD_CHIP_KEY, { amount = math.floor(amount + 0.5) })
end

-- Every message goes out through here: a refused cast under the chips, a chain's refund on the ink bar, a
-- celebration or a reward by its key, anything else as its kind. `raw` is the payload's own params, before
-- their keys became words: the cooldown's glyph is found by its name key.
local function show(key: string, params: { [string]: any }?, kind: ToastKind, raw: { [string]: any }?)
	local text = localize.t(key, params)
	if key == TAKEDOWN_KEY then
		banner:Pop()
	end
	local name = if raw ~= nil then raw.name else nil
	local ink = if raw ~= nil then raw.ink else nil
	if INLINE_KEYS[key] then
		comboRow:Refuse(text)
		if key == COOLDOWN_KEY and type(name) == "string" then
			hotbar:Refuse(name)
		end
	elseif key == CHAIN_KEY then
		if type(ink) == "number" then
			combatDock:GainInk(ink)
		end
	elseif SPLASH_KEYS[key] then
		return
	elseif CELEBRATE_KEYS[key] then
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
	show(payload.Key, localize.resolveParams(params), kind, params)
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
	show(key, params, kind or "Info", params)
end

-- Where a portal just took the player (TravelController, once it has fired Travelled): the Battleground and
-- the World Boss's arena are fights, like a match; anywhere else is the hub.
function HudController.setPlace(zoneId: string)
	local arena = ARENA_ZONES[zoneId] == true
	place(if arena then zoneId else nil)
end

-- Whether the player fights, as TravelController hears it (FightChanged). The one way into an arena that no
-- Travelled says is the scheduled Erasure: as it turns from announced to fighting, WorldBossService puts everybody
-- alive and in no match on its pads. The HUD stayed the hub's through that whole fight -- level, Folios,
-- shortcuts, and every reward shown in the value colours. The ways out are the HUD's own already: the fight's end
-- and a death there (leftPlace), a portal home (setPlace), a match (refreshMatch).
local function onFightChanged(fighting: boolean)
	if fighting and arenaZone == nil then
		place(ERASURE_ZONE)
	end
end

-- The server let the player out of the arena `zoneId` without a portal, so no Travelled says so: the
-- Battleground's membership ended (BattlegroundChanged nil), the Erasure's fight ended and sent everyone in it
-- home (BossChanged nil), or a body that died in the Erasure's arena came back at the hub's spawn. The hub
-- again -- unless a portal has since put them in the other arena. Without it the hub stayed in fight mode
-- until the next portal: no level, no Folios, no shortcuts, and every reward held.
function HudController.leftPlace(zoneId: string)
	if arenaZone == zoneId then
		place(nil)
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
	travelController = deps.TravelController
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
	comboController.SequenceChanged:Connect(onSequence)
	comboController.PreviewChanged:Connect(onPreview)
	comboController.SequenceBroken:Connect(function()
		comboRow:FadeStreak()
	end)
	vfxController.LocalCast:Connect(onLocalCast)
	combatController.StateChanged:Connect(refreshCombat)
	refreshCombat(combatController.getState())
	matchController.MatchChanged:Connect(refreshMatch)
	refreshMatch(matchController.getMatch())
	-- A participant who dies in the Erasure's arena comes back at the hub's spawn (WorldBossService); a
	-- Battleground member is taken back to the camp instead, and told otherwise when they are not.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		HudController.leftPlace(ERASURE_ZONE)
	end)
	travelController.FightChanged:Connect(onFightChanged)
	remoteClient.on("Notify", onNotify)
	inputController.TouchLayoutChanged:Connect(placeToasts)
	placeToasts()
	if UserInputService.TouchEnabled then
		inputController.TouchLayoutChanged:Connect(fitDock)
		fitDock()
		inputController.TouchLayoutChanged:Connect(placePlaySticker)
		placePlaySticker()
	end
	local function onQueue(snapshot: Types.QueueSnapshot)
		queued = snapshot.Queued
		metaCluster:SetQueue(snapshot)
		refreshHub()
	end
	matchController.QueueChanged:Connect(onQueue)
	onQueue(matchController.getQueue())
	qualityController.Changed:Connect(function()
		refreshPrefs(clientData.get())
	end)
	refreshPrefs(clientData.get())
	log.info("started")
end

return HudController
