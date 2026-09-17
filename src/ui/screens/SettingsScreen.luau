--!strict
-- SettingsScreen: keyboard / gamepad rebinding and audio settings. Keybinds are edited on a local
-- pending copy per kind and sent with Save; the Settings push that follows confirms them. Audio
-- values are sent automatically after a short debounce. Refreshes from ClientData on Open and on
-- Settings changes, without overwriting unsaved local edits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local InputConfig = require(Shared.Config.InputConfig)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Slider = require(script.Parent.Parent.components.Slider)
local Tabs = require(script.Parent.Parent.components.Tabs)
local Theme = require(script.Parent.Parent.Theme)
local Toggle = require(script.Parent.Parent.components.Toggle)
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
	OnClose: () -> (),
	OnNavigate: (id: string) -> (),
}

export type Screen = {
	Instance: ScreenGui,
	Visible: boolean,
	Open: (self: Screen) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
}

type ActionId = InputConfig.ActionId
type BindKind = "Keyboard" | "Gamepad"
type TabId = "Keyboard" | "Gamepad" | "Audio"
type KeybindMap = Types.KeybindMap
type AudioState = { MusicVolume: number, SfxVolume: number, CameraShake: boolean }
type Destroyable = { Destroy: (self: any) -> () }

local SettingsScreen = {}

local DISPLAY_ORDER = 10
local OVERLAY_TRANSPARENCY = 0.45
local AUDIO_DEBOUNCE_SECONDS = 0.5
local VOLUME_STEP = 0.05
local KEY_BUTTON_WIDTH = 150
local FOOTER_BUTTON_WIDTH = 140
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + Theme.Sizes.RowHeight + Theme.Sizes.Gap + STATUS_HEIGHT
local FOOTER_HEIGHT = Theme.Sizes.PaddingSmall + Theme.Sizes.Padding + Theme.Sizes.ButtonHeight
local AUDIO_ROW_HEIGHT = Theme.Sizes.RowHeight + Theme.Sizes.PaddingSmall

-- Config maps are keyed by the ActionId literal union; the screen works with plain string keys.
local function stringMap(map: { [ActionId]: string }): { [string]: string }
	return (map :: any) :: { [string]: string }
end

local DEFAULTS: { [string]: { [string]: string } } = {
	Keyboard = stringMap(InputConfig.DefaultKeyboard),
	Gamepad = stringMap(InputConfig.DefaultGamepad),
}
local ALLOWED: { [string]: { [string]: boolean } } = {
	Keyboard = InputConfig.AllowedKeyboard,
	Gamepad = InputConfig.AllowedGamepad,
}
local ACTION_NAME_KEYS = stringMap(InputConfig.ActionNameKeys)
local REBINDABLE: { [string]: boolean } = {}
for _, action in ipairs(InputConfig.Rebindable) do
	REBINDABLE[action] = true
end

-- Dimmed backdrop that also swallows clicks so the world under the menu is not interacted with.
local function makeOverlay(parent: Instance): Frame
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = Theme.Colors.Overlay
	overlay.BackgroundTransparency = OVERLAY_TRANSPARENCY
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Active = true
	overlay.Parent = parent
	return overlay
end

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

function SettingsScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local pageTrove = trove:Extend()
	local t = deps.Localize.t
	local screen: Screen

	-- Keybind state
	local pending: { [string]: KeybindMap } = { Keyboard = {}, Gamepad = {} }
	local dirty: { [string]: boolean } = { Keyboard = false, Gamepad = false }
	local saving = false
	local capturing: string? = nil
	local currentTab: TabId = "Keyboard"
	local keyButtons: { [string]: Button.Button } = {}

	-- Audio state (neutral fallback until the profile is loaded; syncAudio overwrites it)
	local audio: AudioState = { MusicVolume = 1, SfxVolume = 1, CameraShake = true }
	local audioTimer: thread? = nil
	local audioInFlight = false
	local musicSlider: Slider.Slider? = nil
	local sfxSlider: Slider.Slider? = nil
	local shakeToggle: Toggle.Toggle? = nil

	local root = ScreenRoot.new({ Name = "SettingsScreen", DisplayOrder = DISPLAY_ORDER })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("settings.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	status.Font = Theme.Fonts.Body
	status.TextSize = Theme.Sizes.TextSmall
	status.TextColor3 = Theme.Colors.TextMuted
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = ""
	status.LayoutOrder = 2
	status.Parent = panel.Header

	local function setStatus(text: string)
		status.Text = text
	end

	local function actionName(action: string): string
		local key: string? = ACTION_NAME_KEYS[action]
		if key == nil then
			return action
		end
		return t(key)
	end

	----------------------------------------------------------------
	-- Keybinds
	----------------------------------------------------------------

	-- Rebuilds the pending copy of `kind` from the profile (defaults fill any missing action).
	local function syncPending(kind: BindKind)
		local map: KeybindMap = {}
		local defaults = DEFAULTS[kind]
		local data = deps.ClientData.get()
		local stored: KeybindMap? = nil
		if data ~= nil then
			stored = if kind == "Keyboard" then data.Settings.Keyboard else data.Settings.Gamepad
		end
		for _, action in ipairs(InputConfig.Actions) do
			local key: string? = if stored ~= nil then stored[action] else nil
			map[action] = if key ~= nil then key else defaults[action]
		end
		pending[kind] = map
		dirty[kind] = false
	end

	local function refreshKeyLabels(kind: BindKind)
		if currentTab ~= kind then
			return
		end
		local map = pending[kind]
		for action, button in pairs(keyButtons) do
			button:SetText(map[action])
		end
	end

	-- (true, kind) on a keybind tab; (false, "Keyboard") on the Audio tab. Two values rather than an
	-- optional so callers get a plain BindKind without relying on nil refinement of a literal union.
	local function currentBindKind(): (boolean, BindKind)
		if currentTab == "Gamepad" then
			return true, "Gamepad"
		end
		return currentTab == "Keyboard", "Keyboard"
	end

	local function finishCapture(kind: BindKind, action: string, keyName: string?)
		capturing = nil
		local highlighted: Button.Button? = keyButtons[action]
		if highlighted ~= nil then
			highlighted:SetVariant("Secondary")
		end
		if keyName == nil then
			setStatus(t("settings.captureCancelled"))
			return
		end
		if ALLOWED[kind][keyName] ~= true then
			setStatus(t("settings.keyNotAllowed", { key = keyName }))
			return
		end
		local map = pending[kind]
		local previous = map[action]
		if previous == keyName then
			setStatus(t("settings.bound", { action = actionName(action), key = keyName }))
			return
		end
		local holder: string? = nil
		for other, key in pairs(map) do
			if key == keyName and other ~= action then
				holder = other
				break
			end
		end
		if holder ~= nil then
			if REBINDABLE[holder] ~= true then
				setStatus(t("settings.duplicate", { key = keyName }))
				return
			end
			map[holder] = previous
			map[action] = keyName
			dirty[kind] = true
			refreshKeyLabels(kind)
			setStatus(t("settings.swapped", { a = actionName(action), b = actionName(holder) }))
			return
		end
		map[action] = keyName
		dirty[kind] = true
		refreshKeyLabels(kind)
		setStatus(t("settings.bound", { action = actionName(action), key = keyName }))
	end

	local function beginCapture(kind: BindKind, action: string)
		if capturing ~= nil or saving then
			return
		end
		capturing = action
		local button: Button.Button? = keyButtons[action]
		if button ~= nil then
			button:SetVariant("Primary")
		end
		deps.SoundController.play("UiClick")
		setStatus(t("settings.pressKey", { action = actionName(action) }))
		deps.InputController.captureNext(kind, function(keyName: string?)
			if capturing ~= action then
				return -- the screen was closed or reopened meanwhile
			end
			finishCapture(kind, action, keyName)
		end)
	end

	local function save()
		local isBind, kind: BindKind = currentBindKind()
		if not isBind or capturing ~= nil or saving then
			return
		end
		saving = true
		deps.SoundController.play("UiClick")
		setStatus(t("settings.saving"))
		deps.RemoteClient.fire("UpdateKeybinds", kind, table.clone(pending[kind]))
	end

	local function reset()
		local isBind, kind: BindKind = currentBindKind()
		if not isBind or capturing ~= nil or saving then
			return
		end
		local map = pending[kind]
		local defaults = DEFAULTS[kind]
		for _, action in ipairs(InputConfig.Rebindable) do
			map[action] = defaults[action]
		end
		dirty[kind] = true
		deps.SoundController.play("UiClick")
		refreshKeyLabels(kind)
		setStatus(t("settings.resetPending"))
	end

	----------------------------------------------------------------
	-- Audio
	----------------------------------------------------------------

	local function syncAudio()
		local data = deps.ClientData.get()
		if data == nil then
			return
		end
		audio.MusicVolume = data.Settings.MusicVolume
		audio.SfxVolume = data.Settings.SfxVolume
		audio.CameraShake = data.Settings.CameraShake
		local music = musicSlider
		if music ~= nil then
			music:SetValue(audio.MusicVolume)
		end
		local sfx = sfxSlider
		if sfx ~= nil then
			sfx:SetValue(audio.SfxVolume)
		end
		local shake = shakeToggle
		if shake ~= nil then
			shake:SetValue(audio.CameraShake)
		end
	end

	local function sendAudio()
		if deps.ClientData.get() == nil then
			return
		end
		audioInFlight = true
		deps.RemoteClient.fire("UpdateSettings", {
			MusicVolume = audio.MusicVolume,
			SfxVolume = audio.SfxVolume,
			CameraShake = audio.CameraShake,
		})
	end

	local function cancelAudioTimer()
		local timer = audioTimer
		if timer ~= nil then
			task.cancel(timer)
			audioTimer = nil
		end
	end

	local function scheduleAudio()
		cancelAudioTimer()
		audioTimer = task.delay(AUDIO_DEBOUNCE_SECONDS, function()
			audioTimer = nil
			sendAudio()
		end)
	end

	-- Sends unsent audio changes right away (used when the screen closes).
	local function flushAudio()
		if audioTimer == nil then
			return
		end
		cancelAudioTimer()
		sendAudio()
	end

	trove:Add(cancelAudioTimer)

	----------------------------------------------------------------
	-- Footer (Save / Reset, keybind tabs only)
	----------------------------------------------------------------

	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	footerLayout.Parent = panel.Footer

	local resetButton = Button.new({
		Text = t("common.reset"),
		Variant = "Secondary",
		Size = UDim2.fromOffset(FOOTER_BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
		LayoutOrder = 1,
		Parent = panel.Footer,
		OnClick = reset,
	})
	own(trove, resetButton)

	local saveButton = Button.new({
		Text = t("common.save"),
		Variant = "Primary",
		Size = UDim2.fromOffset(FOOTER_BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
		LayoutOrder = 2,
		Parent = panel.Footer,
		OnClick = save,
	})
	own(trove, saveButton)

	local function setFooterVisible(visible: boolean)
		panel:SetFooterHeight(if visible then FOOTER_HEIGHT else 0)
		resetButton.Instance.Visible = visible
		saveButton.Instance.Visible = visible
	end

	----------------------------------------------------------------
	-- Pages
	----------------------------------------------------------------

	local function buildBindPage(kind: BindKind)
		local map = pending[kind]
		for index, action in ipairs(InputConfig.Rebindable) do
			local button = Button.new({
				Text = map[action],
				Variant = "Secondary",
				Size = UDim2.fromOffset(KEY_BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
				OnClick = function()
					beginCapture(kind, action)
				end,
			})
			own(pageTrove, button)
			keyButtons[action] = button
			local row = ListRow.new({
				Left = actionName(action),
				Right = button.Instance,
				LayoutOrder = index,
				Parent = panel.Content,
			})
			own(pageTrove, row)
		end
		setFooterVisible(true)
		setStatus(t("settings.hint"))
	end

	local function buildAudioPage()
		local music = Slider.new({
			Min = 0,
			Max = 1,
			Step = VOLUME_STEP,
			Value = audio.MusicVolume,
			OnChange = function(value: number)
				audio.MusicVolume = value
				scheduleAudio()
			end,
		})
		own(pageTrove, music)
		local musicRow = ListRow.new({
			Left = t("settings.music"),
			Right = music.Instance,
			Height = AUDIO_ROW_HEIGHT,
			LayoutOrder = 1,
			Parent = panel.Content,
		})
		own(pageTrove, musicRow)

		local sfx = Slider.new({
			Min = 0,
			Max = 1,
			Step = VOLUME_STEP,
			Value = audio.SfxVolume,
			OnChange = function(value: number)
				audio.SfxVolume = value
				scheduleAudio()
			end,
		})
		own(pageTrove, sfx)
		local sfxRow = ListRow.new({
			Left = t("settings.sfx"),
			Right = sfx.Instance,
			Height = AUDIO_ROW_HEIGHT,
			LayoutOrder = 2,
			Parent = panel.Content,
		})
		own(pageTrove, sfxRow)

		local shake = Toggle.new({
			Value = audio.CameraShake,
			OnChange = function(value: boolean)
				audio.CameraShake = value
				scheduleAudio()
			end,
		})
		own(pageTrove, shake)
		local shakeRow = ListRow.new({
			Left = t("settings.cameraShake"),
			Right = shake.Instance,
			Height = AUDIO_ROW_HEIGHT,
			LayoutOrder = 3,
			Parent = panel.Content,
		})
		own(pageTrove, shakeRow)

		musicSlider = music
		sfxSlider = sfx
		shakeToggle = shake
		pageTrove:Add(function()
			musicSlider = nil
			sfxSlider = nil
			shakeToggle = nil
		end)
		setFooterVisible(false)
		setStatus("")
	end

	local function showTab(id: TabId)
		pageTrove:Clean()
		keyButtons = {}
		currentTab = id
		panel.Content.CanvasPosition = Vector2.zero
		if id == "Audio" then
			buildAudioPage()
		else
			buildBindPage(id)
		end
	end

	local tabs = Tabs.new({
		Items = {
			{ Id = "Keyboard", Text = t("settings.tab.keyboard") },
			{ Id = "Gamepad", Text = t("settings.tab.gamepad") },
			{ Id = "Audio", Text = t("settings.tab.audio") },
		},
		Selected = currentTab,
		OnSelect = function(id: string)
			deps.SoundController.play("UiClick")
			showTab(id :: TabId)
		end,
		LayoutOrder = 1,
		Parent = panel.Header,
	})
	own(trove, tabs)

	----------------------------------------------------------------
	-- Profile sync
	----------------------------------------------------------------

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section ~= "*" and section ~= "Settings" then
			return
		end
		if saving then
			saving = false
			syncPending("Keyboard")
			syncPending("Gamepad")
			local isBind, kind: BindKind = currentBindKind()
			if isBind then
				refreshKeyLabels(kind)
			end
			setStatus(t("settings.saved"))
		else
			-- Unsaved local edits win over the push; clean copies follow the profile.
			if not dirty.Keyboard then
				syncPending("Keyboard")
				refreshKeyLabels("Keyboard")
			end
			if not dirty.Gamepad then
				syncPending("Gamepad")
				refreshKeyLabels("Gamepad")
			end
		end
		-- Do not fight a drag in progress: the debounced send will push the latest values.
		if audioTimer == nil then
			syncAudio()
			if audioInFlight then
				audioInFlight = false
				setStatus(t("settings.saved"))
			end
		end
	end)

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		saving = false
		audioInFlight = false
		capturing = nil
		syncPending("Keyboard")
		syncPending("Gamepad")
		syncAudio()
		showTab(currentTab)
		root.Instance.Enabled = true
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if capturing ~= nil then
			capturing = nil
			deps.InputController.cancelCapture()
		end
		if not self.Visible then
			return
		end
		self.Visible = false
		capturing = nil
		flushAudio()
		root.Instance.Enabled = false
		deps.SoundController.play("UiClose")
	end

	local function destroy(self: Screen)
		self.Visible = false
		capturing = nil
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
