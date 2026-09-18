--!strict
-- DailyScreen: the login streak. One row per DailyConfig.Streak day with its reward, the day the
-- player is on highlighted, and a single Claim button in the footer. Whether today can be claimed is
-- derived from the profile's Daily section through the pure DailyStreak module (the same one the
-- server uses), so the button state matches the server decision; the claim itself goes through the
-- ClaimDaily remote and the server answers with a profile push and a Notify toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local DailyConfig = require(Shared.Config.DailyConfig)
local DailyStreak = require(Shared.Pure.DailyStreak)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Panel = require(script.Parent.Parent.components.Panel)
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

local DailyScreen = {}

local OVERLAY_TRANSPARENCY = 0.45
local STATUS_HEIGHT = Theme.Sizes.TextBody + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + STATUS_HEIGHT
local HIGHLIGHT_THICKNESS = 2
local STREAK_LENGTH = #DailyConfig.Streak

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

local function makeHighlight(parent: Instance): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Accent
	stroke.Thickness = HIGHLIGHT_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Enabled = false
	stroke.Parent = parent
	return stroke
end

function DailyScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local highlights: { UIStroke } = {}

	local root = ScreenRoot.new({ Name = "DailyScreen", DisplayOrder = Theme.Layers.Screen })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("daily.title"),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)
	-- The Claim button carries the touch minimum, so the footer reserves the height it really takes.
	panel:SetFooterHeight(
		Theme.Sizes.PaddingSmall + Theme.touchTargetHeight(Theme.Sizes.RowHeight) + Theme.Sizes.Padding
	)

	local streakLabel = Instance.new("TextLabel")
	streakLabel.Name = "Streak"
	streakLabel.BackgroundTransparency = 1
	streakLabel.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	streakLabel.Font = Theme.Fonts.Bold
	streakLabel.TextSize = Theme.Sizes.TextBody
	streakLabel.TextColor3 = Theme.Colors.Accent
	streakLabel.TextXAlignment = Enum.TextXAlignment.Left
	streakLabel.TextTruncate = Enum.TextTruncate.AtEnd
	streakLabel.Text = ""
	streakLabel.Parent = panel.Header

	for index, reward in ipairs(DailyConfig.Streak) do
		local row = ListRow.new({
			Left = t("daily.claimed", { day = index, xp = reward.Xp, ryo = reward.Ryo }),
			LayoutOrder = index,
			Name = "Day" .. tostring(index),
			Parent = panel.Content,
		})
		own(trove, row)
		highlights[index] = makeHighlight(row.Instance)
	end

	local claimButton = Button.new({
		Text = t("quest.claim"),
		Variant = "Secondary",
		Disabled = true,
		Parent = panel.Footer,
		OnClick = function()
			deps.SoundController.play("UiClick")
			deps.RemoteClient.fire("ClaimDaily")
		end,
	})
	own(trove, claimButton)

	-- The streak day shown and highlighted is today's: the one a claim would grant when the reward is
	-- still available, the one already granted otherwise.
	local function refresh()
		local data = deps.ClientData.get()
		if data == nil then
			streakLabel.Text = ""
			claimButton:SetText(t("quest.claim"))
			claimButton:SetVariant("Secondary")
			claimButton:SetDisabled(true)
			for _, highlight in ipairs(highlights) do
				highlight.Enabled = false
			end
			return
		end
		local daily = data.Daily
		local today = DailyStreak.dayIndex(os.time())
		local evaluation = DailyStreak.evaluate(daily, today)
		local day = if evaluation.CanClaim then evaluation.NextStreak else daily.Streak
		streakLabel.Text = t("daily.streak", { day = day })
		if evaluation.CanClaim then
			claimButton:SetText(t("quest.claim"))
			claimButton:SetVariant("Primary")
			claimButton:SetDisabled(false)
		else
			claimButton:SetText(t("quest.claimed"))
			claimButton:SetVariant("Secondary")
			claimButton:SetDisabled(true)
		end
		local current = DailyStreak.rewardIndex(day, STREAK_LENGTH)
		for index, highlight in ipairs(highlights) do
			highlight.Enabled = index == current
		end
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Daily" then
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
		-- A claimed day leaves the button disabled: the panel then focuses its close button.
		panel:FocusForGamepad(if claimButton:IsDisabled() then nil else claimButton.Instance)
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

return DailyScreen
