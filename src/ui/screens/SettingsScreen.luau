--!strict
-- SettingsScreen: the player's settings, on the ink band of the Settings chapter (D-147). Five tabs:
-- Keyboard and Gamepad (only while that hardware is attached, so a capture is never started where no key
-- can end it; the strip is rebuilt whenever the hardware set changes), Audio, Graphics and Accessibility.
--
-- The binding pages are SettingsBindings': each change is saved as it is made, and Reset asks first. Audio
-- and Accessibility are SettingsValues', which sends everything UpdateSettings carries; the Graphics page,
-- the four quality tiers, is drawn here and reaches its tier through it.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local Panel = require(script.Parent.Parent.components.Panel)
local QualityConfig = require(Shared.Config.QualityConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local SettingsBindings = require(script.Parent.SettingsBindings)
local SettingsValues = require(script.Parent.SettingsValues)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: {
		captureNext: (kind: string, callback: (keyName: string?) -> ()) -> (),
		cancelCapture: () -> (),
	},
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- Every message of the server: how a refused binding is heard.
	HudController: { Notified: any }?,
	OnClose: () -> (),
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

type TabId = "Keyboard" | "Gamepad" | "Audio" | "Graphics" | "Accessibility"
type Destroyable = { Destroy: (self: any) -> () }

local SettingsScreen = {}

local CHAPTER = "Settings"
-- Four tiers side by side: wide enough that each label fits without truncating on a phone.
local QUALITY_STRIP_WIDTH = 320
local TABS_HEIGHT = 48
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

-- Tab shown first: a rebinding page needs the matching hardware to capture a key, so a touch-only
-- phone (no keyboard, no gamepad) opens on the only page it can use.
local function initialTab(): TabId
	if UserInputService.KeyboardEnabled then
		return "Keyboard"
	elseif UserInputService.GamepadEnabled then
		return "Gamepad"
	end
	return "Audio"
end

function SettingsScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local pageTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen
	local currentTab: TabId = initialTab()

	local root = ScreenRoot.new({
		Name = "SettingsScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("settings.title"),
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
	-- The tab strip and the footer button carry the touch minimum, which follows the viewport, so both bands
	-- are measured by the panel on every scale change instead of once here.
	panel:SetHeaderHeight(function()
		return Theme.Sizes.PaddingSmall * 2 + Theme.touchTargetHeight(TABS_HEIGHT) + Theme.Sizes.Gap + STATUS_HEIGHT
	end)
	local function footerHeight(): number
		return Theme.Sizes.PaddingSmall + Theme.Sizes.Padding + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
	end

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	status.FontFace = Theme.Fonts.Body
	status.TextSize = Theme.Sizes.TextBody
	status.TextColor3 = Theme.Colors.TextMuted
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = ""
	status.LayoutOrder = 2
	status.Parent = panel.Header

	local function setStatus(text: string)
		status.Text = text
	end

	local bindings = SettingsBindings.new({
		Localize = deps.Localize,
		ClientData = deps.ClientData,
		RemoteClient = deps.RemoteClient,
		InputController = deps.InputController,
		Notified = if deps.HudController ~= nil then deps.HudController.Notified else nil,
		Content = panel.Content,
		Card = panel.Instance,
		SetStatus = setStatus,
	})
	own(trove, bindings)

	local values = SettingsValues.new({
		Localize = deps.Localize,
		ClientData = deps.ClientData,
		RemoteClient = deps.RemoteClient,
		Content = panel.Content,
	})
	own(trove, values)

	----------------------------------------------------------------
	-- Footer (Reset, binding pages only)
	----------------------------------------------------------------

	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Parent = panel.Footer

	-- A question first: the confirm is the one red button of the menus (SettingsBindings.AskReset).
	local resetButton = Button.new({
		Name = "Reset",
		Text = t("common.reset"),
		Variant = "Secondary",
		LayoutOrder = 1,
		Parent = panel.Footer,
		OnClick = function()
			bindings:AskReset()
		end,
	})
	own(trove, resetButton)

	local function setFooterVisible(visible: boolean)
		panel:SetFooterHeight(if visible then footerHeight else 0)
		resetButton.Instance.Visible = visible
	end

	----------------------------------------------------------------
	-- Pages
	----------------------------------------------------------------

	-- The graphics page: the four tiers of Config/QualityConfig, and a line saying that the game lowers
	-- the setting by itself when the frame rate falls. The chosen tier is a ceiling, so the strip shows
	-- what the player asked for and never what the frame rate has currently forced -- a strip that moved
	-- on its own would read as the game overriding the choice rather than protecting it.
	local function buildGraphicsPage()
		local items: { Tabs.Item } = {}
		for _, name in ipairs(QualityConfig.Order) do
			local tier = QualityConfig.tier(name)
			table.insert(items, { Id = name, Text = t(tier.NameKey) })
		end
		local strip = Tabs.new({
			Name = "Quality",
			Items = items,
			Selected = values:Quality(),
			Chapter = CHAPTER,
			Size = UDim2.fromOffset(QUALITY_STRIP_WIDTH, TABS_HEIGHT),
			OnSelect = function(id: string)
				deps.SoundController.play("UiClick")
				values:SetQuality(id)
			end,
		})
		own(pageTrove, strip)
		values:FollowQuality(pageTrove, strip)
		values:Row(pageTrove, t("settings.quality"), strip.Instance, 1)

		local hint = Instance.new("TextLabel")
		hint.Name = "QualityHint"
		hint.BackgroundTransparency = 1
		hint.Size = UDim2.new(1, 0, 0, Theme.Sizes.TextSmall * 3)
		hint.LayoutOrder = 2
		hint.FontFace = Theme.Fonts.Body
		hint.TextSize = Theme.Sizes.TextSmall
		hint.TextColor3 = Theme.Colors.TextMuted
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.TextWrapped = true
		hint.Text = t("settings.qualityHint")
		hint.Parent = panel.Content
		pageTrove:Add(hint)
	end

	local function showTab(id: TabId)
		bindings:Leave()
		pageTrove:Clean()
		currentTab = id
		panel.Content.CanvasPosition = Vector2.zero
		-- Reset, and the line of hints, belong to the binding pages.
		local binding = id == "Keyboard" or id == "Gamepad"
		setFooterVisible(binding)
		setStatus("")
		if id == "Audio" then
			values:BuildAudio(pageTrove)
		elseif id == "Graphics" then
			buildGraphicsPage()
		elseif id == "Accessibility" then
			values:BuildAccessibility(pageTrove)
		else
			bindings:Build(id, pageTrove)
		end
	end

	-- A rebinding page can only be finished with the matching hardware: a capture unbinds every on-screen
	-- touch control and waits for a key no touch-only device can send, which would leave the player with
	-- no HUD and a half-finished capture. The page is therefore not offered at all without the hardware,
	-- which also matches what initialTab already opens on. The screen is built once and kept for the whole
	-- session, so a pad plugged in later must still get its page: the strip is rebuilt on every change.
	local tabsTrove = trove:Extend()
	local tabs: Tabs.Tabs? = nil
	local hasKeyboard = false
	local hasGamepad = false

	local function tabExists(id: TabId): boolean
		if id == "Keyboard" then
			return hasKeyboard
		elseif id == "Gamepad" then
			return hasGamepad
		end
		return true
	end

	local function buildTabs()
		hasKeyboard = UserInputService.KeyboardEnabled
		hasGamepad = UserInputService.GamepadEnabled
		local items: { Tabs.Item } = {}
		if hasKeyboard then
			table.insert(items, { Id = "Keyboard", Text = t("settings.tab.keyboard") })
		end
		if hasGamepad then
			table.insert(items, { Id = "Gamepad", Text = t("settings.tab.gamepad") })
		end
		table.insert(items, { Id = "Audio", Text = t("settings.tab.audio") })
		table.insert(items, { Id = "Graphics", Text = t("settings.tab.graphics") })
		table.insert(items, { Id = "Accessibility", Text = t("settings.tab.accessibility") })

		-- The open page may be the one that just disappeared: fall back to the default for the new hardware.
		if not tabExists(currentTab) then
			showTab(initialTab())
		end

		tabsTrove:Clean()
		local strip = Tabs.new({
			Items = items,
			Selected = currentTab,
			Chapter = CHAPTER,
			-- Tabs make no sound of their own (a Button does): the click is the screen's.
			OnSelect = function(id: string)
				deps.SoundController.play("UiClick")
				showTab(id :: TabId)
			end,
			LayoutOrder = 1,
			Parent = panel.Header,
		})
		own(tabsTrove, strip)
		tabs = strip
	end

	-- The first tab is where a pad starts.
	local function focusTabs()
		local strip = tabs
		local first = if strip ~= nil then strip.Instance:FindFirstChildWhichIsA("TextButton", true) else nil
		panel:FocusForGamepad(first)
	end

	-- Neither KeyboardEnabled nor GamepadEnabled has a change signal of its own: a pad raises
	-- GamepadConnected / GamepadDisconnected, and a keyboard that appears later shows up as an input type.
	local function syncTabsToHardware()
		if UserInputService.KeyboardEnabled == hasKeyboard and UserInputService.GamepadEnabled == hasGamepad then
			return
		end
		buildTabs()
		-- The strip that was just destroyed may have held the gamepad selection, leaving the D-pad dead.
		if screen.Visible and GuiService.SelectedObject == nil then
			focusTabs()
		end
	end

	buildTabs()
	trove:Connect(UserInputService.GamepadConnected, syncTabsToHardware)
	trove:Connect(UserInputService.GamepadDisconnected, syncTabsToHardware)
	trove:Connect(UserInputService.LastInputTypeChanged, syncTabsToHardware)

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		bindings:Open()
		values:Open()
		showTab(currentTab)
		root:PlayEnter()
		focusTabs()
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		bindings:Leave()
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
	return screen
end

return SettingsScreen
