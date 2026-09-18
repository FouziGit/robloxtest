--!strict
-- MenuScreen: the hub menu. Shows the player's level (XP bar) and Ryo, and navigates to the other
-- screens. Hidden until Open(); refreshes from ClientData on Open and whenever a relevant section
-- changes. The close button hides the screen and notifies the controller through OnClose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
local ProgressBar = require(script.Parent.Parent.components.ProgressBar)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
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

type Destroyable = { Destroy: (self: any) -> () }

local MenuScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local SUMMARY_BAR_WIDTH = 220
local SUMMARY_BAR_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall

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

function MenuScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen

	local root = ScreenRoot.new({ Name = "MenuScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("menu.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)

	-- Summary rows
	local levelBar = ProgressBar.new({
		Color = Theme.Colors.Accent,
		Size = UDim2.fromOffset(SUMMARY_BAR_WIDTH, SUMMARY_BAR_HEIGHT),
	})
	own(trove, levelBar)
	local levelRow = ListRow.new({ Left = "", Right = levelBar.Instance, LayoutOrder = 1, Parent = panel.Content })
	own(trove, levelRow)
	local ryoRow = ListRow.new({ Left = t("currency.ryo"), Right = "", LayoutOrder = 2, Parent = panel.Content })
	own(trove, ryoRow)

	-- Navigation
	local function navigate(id: string)
		deps.SoundController.play("UiClick")
		deps.OnNavigate(id)
	end

	local playButton = Button.new({
		Text = t("queue.title"),
		Variant = "Primary",
		LayoutOrder = 3,
		Parent = panel.Content,
		OnClick = function()
			navigate("Play")
		end,
	})
	own(trove, playButton)

	local leaderboardButton = Button.new({
		Text = t("leaderboard.title"),
		Variant = "Secondary",
		LayoutOrder = 4,
		Parent = panel.Content,
		OnClick = function()
			navigate("Leaderboard")
		end,
	})
	own(trove, leaderboardButton)

	local settingsButton = Button.new({
		Text = t("menu.settings"),
		Variant = "Secondary",
		LayoutOrder = 5,
		Parent = panel.Content,
		OnClick = function()
			navigate("Settings")
		end,
	})
	own(trove, settingsButton)

	local battlepassButton = Button.new({
		Text = t("menu.battlepass"),
		Variant = "Secondary",
		LayoutOrder = 6,
		Parent = panel.Content,
		OnClick = function()
			navigate("Battlepass")
		end,
	})
	own(trove, battlepassButton)

	local questsButton = Button.new({
		Text = t("menu.quests"),
		Variant = "Secondary",
		LayoutOrder = 7,
		Parent = panel.Content,
		OnClick = function()
			navigate("Quests")
		end,
	})
	own(trove, questsButton)

	local dailyButton = Button.new({
		Text = t("daily.title"),
		Variant = "Secondary",
		LayoutOrder = 8,
		Parent = panel.Content,
		OnClick = function()
			navigate("Daily")
		end,
	})
	own(trove, dailyButton)

	local loadoutButton = Button.new({
		Text = t("menu.loadout"),
		Variant = "Secondary",
		LayoutOrder = 9,
		Parent = panel.Content,
		OnClick = function()
			navigate("Loadout")
		end,
	})
	own(trove, loadoutButton)

	local shopButton = Button.new({
		Text = t("menu.shop"),
		Variant = "Secondary",
		LayoutOrder = 10,
		Parent = panel.Content,
		OnClick = function()
			navigate("Shop")
		end,
	})
	own(trove, shopButton)

	local function refresh()
		local data = deps.ClientData.get()
		if data == nil then
			return
		end
		local level = data.Progression.Level
		levelRow:SetLeft(t("level.title", { level = level }))
		if level >= ProgressionConfig.MaxLevel then
			levelBar:SetProgress(1)
			levelBar:SetLabel(t("level.max"))
		else
			local needed = ProgressionConfig.xpForLevel(level)
			levelBar:SetProgress(if needed > 0 then data.Progression.XP / needed else 0)
			levelBar:SetLabel(t("level.xp", { xp = data.Progression.XP, needed = needed }))
		end
		ryoRow:SetRight(tostring(data.Currency.Ryo))
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Progression" or section == "Currency" then
			refresh()
		end
	end)

	refresh()

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		refresh()
		root.Instance.Enabled = true
		panel:FocusForGamepad(settingsButton.Instance)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		panel:ReleaseGamepadFocus()
		root.Instance.Enabled = false
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

return MenuScreen
