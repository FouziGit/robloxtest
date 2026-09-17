--!strict
-- BattlepassScreen: season progress (tier + XP bar) and the 50-tier reward list with Free / Premium
-- cells. Rows are built once, on the first Open; cell states (claim / claimed / locked / premium
-- required) refresh from ClientData on Open and on every Battlepass change. Claims go through the
-- ClaimBattlepassReward remote; the server answers with a profile push and a Notify toast.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local Button = require(script.Parent.Parent.components.Button)
local GameConfig = require(Shared.Config.GameConfig)
local Panel = require(script.Parent.Parent.components.Panel)
local ProgressBar = require(script.Parent.Parent.components.ProgressBar)
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

type Track = "Free" | "Premium"
type Reward = BattlepassConfig.Reward
type SeasonData = Types.BattlepassSeasonData
type Cell = { Track: Track, HasReward: boolean, Button: Button.Button }
type Row = { Highlight: UIStroke, Free: Cell, Premium: Cell }
type Destroyable = { Destroy: (self: any) -> () }

local BattlepassScreen = {}

local DISPLAY_ORDER = 10
local OVERLAY_TRANSPARENCY = 0.45
local SEASON = GameConfig.SeasonId
local MAX_TIER = BattlepassConfig.MaxTier
local TIER_COLUMN_WIDTH = Theme.Sizes.RowHeight
local REWARD_LABEL_HEIGHT = Theme.Sizes.TextLarge
local ROW_HEIGHT = Theme.Sizes.PaddingSmall * 2
	+ REWARD_LABEL_HEIGHT
	+ Theme.Sizes.PaddingSmall
	+ Theme.Sizes.ButtonHeight
local ROW_PITCH = ROW_HEIGHT + Theme.Sizes.Gap
local COLUMN_HEADER_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local BAR_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2
	+ Theme.Sizes.TextLarge
	+ Theme.Sizes.Gap
	+ BAR_HEIGHT
	+ Theme.Sizes.Gap
	+ COLUMN_HEADER_HEIGHT
local HIGHLIGHT_THICKNESS = 2

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

local function horizontalLayout(parent: Instance)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = parent
end

local function flexFill(parent: Instance)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = parent
end

local function sidePadding(parent: Instance)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingSmall)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingSmall)
	padding.Parent = parent
end

-- Fixed-width column holding the tier number (rows) or nothing (column headers).
local function tierColumn(parent: Instance, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Tier"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0, TIER_COLUMN_WIDTH, 1, 0)
	label.Font = Theme.Fonts.Title
	label.TextSize = Theme.Sizes.TextLarge
	label.TextColor3 = Theme.Colors.TextMuted
	label.Text = text
	label.LayoutOrder = 1
	label.Parent = parent
	return label
end

local function columnHeader(parent: Instance, text: string, color: Color3, layoutOrder: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Column"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.Font = Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextSmall
	label.TextColor3 = color
	label.Text = text
	label.LayoutOrder = layoutOrder
	label.Parent = parent
	flexFill(label)
	return label
end

function BattlepassScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local rows: { Row } = {}
	local pendingScrollTier: number? = nil

	local root = ScreenRoot.new({ Name = "BattlepassScreen", DisplayOrder = DISPLAY_ORDER })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("battlepass.title", { season = SEASON }),
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)

	----------------------------------------------------------------
	-- Header: tier, XP bar, column titles
	----------------------------------------------------------------

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Vertical
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	headerLayout.Parent = panel.Header

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "TierLabel"
	tierLabel.BackgroundTransparency = 1
	tierLabel.Size = UDim2.new(1, 0, 0, Theme.Sizes.TextLarge)
	tierLabel.Font = Theme.Fonts.Bold
	tierLabel.TextSize = Theme.Sizes.TextLarge
	tierLabel.TextColor3 = Theme.Colors.Text
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.TextTruncate = Enum.TextTruncate.AtEnd
	tierLabel.Text = ""
	tierLabel.LayoutOrder = 1
	tierLabel.Parent = panel.Header

	local xpBar = ProgressBar.new({
		Color = Theme.Colors.Accent,
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		LayoutOrder = 2,
		Parent = panel.Header,
	})
	own(trove, xpBar)

	local columns = Instance.new("Frame")
	columns.Name = "Columns"
	columns.BackgroundTransparency = 1
	columns.Size = UDim2.new(1, 0, 0, COLUMN_HEADER_HEIGHT)
	columns.LayoutOrder = 3
	columns.Parent = panel.Header
	sidePadding(columns)
	horizontalLayout(columns)
	tierColumn(columns, "")
	columnHeader(columns, t("battlepass.free"), Theme.Colors.TextMuted, 2)
	columnHeader(columns, t("battlepass.premium"), Theme.Colors.Premium, 3)

	----------------------------------------------------------------
	-- Rows
	----------------------------------------------------------------

	local function rewardText(reward: Reward?): string
		if reward == nil then
			return t("battlepass.reward.none")
		end
		if reward.Kind == "Ryo" then
			return t("battlepass.reward.ryo", { amount = reward.Amount })
		elseif reward.Kind == "Cosmetic" then
			return t("battlepass.reward.cosmetic", { name = t("cosmetic." .. reward.Id) })
		end
		return t("battlepass.reward.xpBoost", { minutes = reward.Minutes })
	end

	local function claim(tier: number, track: Track)
		deps.SoundController.play("UiClick")
		deps.RemoteClient.fire("ClaimBattlepassReward", tier, track)
	end

	local function buildCell(parent: Frame, tier: number, track: Track, reward: Reward?, layoutOrder: number): Cell
		local cell = Instance.new("Frame")
		cell.Name = track
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromScale(0, 1)
		cell.LayoutOrder = layoutOrder
		flexFill(cell)

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
		layout.Parent = cell

		local label = Instance.new("TextLabel")
		label.Name = "Reward"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, REWARD_LABEL_HEIGHT)
		label.Font = Theme.Fonts.Body
		label.TextSize = Theme.Sizes.TextSmall
		label.TextColor3 = if track == "Premium" then Theme.Colors.Premium else Theme.Colors.Text
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = rewardText(reward)
		label.LayoutOrder = 1
		label.Parent = cell

		local button = Button.new({
			Text = "",
			Variant = "Secondary",
			Disabled = true,
			Size = UDim2.new(1, 0, 0, Theme.Sizes.ButtonHeight),
			LayoutOrder = 2,
			Parent = cell,
			OnClick = function()
				claim(tier, track)
			end,
		})
		own(trove, button)

		cell.Parent = parent
		return { Track = track, HasReward = reward ~= nil, Button = button }
	end

	local function buildRows()
		for tier = 1, MAX_TIER do
			local tierDef = BattlepassConfig.getTier(SEASON, tier)

			local row = Instance.new("Frame")
			row.Name = "Tier" .. tostring(tier)
			row.BackgroundColor3 = Theme.Colors.PanelRaised
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.LayoutOrder = tier
			sidePadding(row)
			horizontalLayout(row)

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
			corner.Parent = row

			local highlight = Instance.new("UIStroke")
			highlight.Color = Theme.Colors.Accent
			highlight.Thickness = HIGHLIGHT_THICKNESS
			highlight.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			highlight.Enabled = false
			highlight.Parent = row

			tierColumn(row, tostring(tier))
			local freeReward: Reward? = if tierDef ~= nil then tierDef.Free else nil
			local premiumReward: Reward? = if tierDef ~= nil then tierDef.Premium else nil
			local free = buildCell(row, tier, "Free", freeReward, 2)
			local premium = buildCell(row, tier, "Premium", premiumReward, 3)

			row.Parent = panel.Content
			rows[tier] = { Highlight = highlight, Free = free, Premium = premium }
		end
	end

	local function updateCell(cell: Cell, tier: number, season: SeasonData?)
		local button = cell.Button
		if not cell.HasReward then
			button.Instance.Visible = false
			return
		end
		local claimedMap: { [string]: boolean }? = if season == nil
			then nil
			elseif cell.Track == "Premium" then season.ClaimedPremium
			else season.ClaimedFree
		local claimed = claimedMap ~= nil and claimedMap[tostring(tier)] == true
		if claimed then
			button:SetText(t("battlepass.claimed"))
			button:SetVariant("Secondary")
			button:SetDisabled(true)
		elseif cell.Track == "Premium" and (season == nil or not season.Premium) then
			button:SetText(t("battlepass.premiumRequired"))
			button:SetVariant("Secondary")
			button:SetDisabled(true)
		elseif season == nil or tier > season.Tier then
			button:SetText(t("common.locked"))
			button:SetVariant("Secondary")
			button:SetDisabled(true)
		else
			button:SetText(t("battlepass.claim"))
			button:SetVariant("Primary")
			button:SetDisabled(false)
		end
	end

	----------------------------------------------------------------
	-- Refresh
	----------------------------------------------------------------

	local function currentSeason(): SeasonData?
		local data = deps.ClientData.get()
		if data == nil then
			return nil
		end
		return data.Battlepass[SEASON]
	end

	local function refresh()
		local season = currentSeason()
		local tier = if season ~= nil then season.Tier else 1
		local xp = if season ~= nil then season.XP else 0

		tierLabel.Text = t("battlepass.tier", { tier = tier, max = MAX_TIER })
		if tier >= MAX_TIER then
			xpBar:SetProgress(1)
			xpBar:SetLabel(t("battlepass.completed"))
		else
			local needed = BattlepassConfig.xpForTier(tier)
			xpBar:SetProgress(if needed > 0 then xp / needed else 0)
			xpBar:SetLabel(t("battlepass.xp", { xp = xp, needed = needed }))
		end

		for index, row in ipairs(rows) do
			updateCell(row.Free, index, season)
			updateCell(row.Premium, index, season)
			row.Highlight.Enabled = index == tier
		end
	end

	-- Scrolls so the current tier sits near the top (one row of context above it). The canvas only
	-- has a size once the layout has run, so the request is kept until AbsoluteCanvasSize is known.
	local function applyPendingScroll()
		local tier = pendingScrollTier
		if tier == nil or panel.Content.AbsoluteCanvasSize.Y <= 0 then
			return
		end
		pendingScrollTier = nil
		local y = math.max(0, (tier - 2) * ROW_PITCH * root:GetScale())
		panel.Content.CanvasPosition = Vector2.new(0, y)
	end

	trove:Connect(panel.Content:GetPropertyChangedSignal("AbsoluteCanvasSize"), applyPendingScroll)

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section == "*" or section == "Battlepass" then
			refresh()
		end
	end)

	refresh()

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen)
		if self.Visible then
			return
		end
		self.Visible = true
		if #rows == 0 then
			buildRows()
		end
		refresh()
		local season = currentSeason()
		pendingScrollTier = if season ~= nil then season.Tier else 1
		root.Instance.Enabled = true
		applyPendingScroll()
		panel:FocusForGamepad()
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		pendingScrollTier = nil
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

return BattlepassScreen
