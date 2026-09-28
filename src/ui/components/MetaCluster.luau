--!strict
-- MetaCluster: what the player owns and where they stand, in the hub (D-147): their level and its XP, and
-- their Folios. HudController places it, feeds it the profile, and hides it in a fight -- a match or an arena --
-- which shows no value colour (docs/ART_BIBLE.md rule 11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local ProgressBar = require(script.Parent.ProgressBar)
local ProgressionConfig = require(Shared:WaitForChild("Config"):WaitForChild("ProgressionConfig"))
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared:WaitForChild("Types"))

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	Parent: Instance,
	Localize: Localizer,
}

export type MetaCluster = {
	Instance: Frame,
	SetProgression: (self: MetaCluster, progression: Types.ProgressionData) -> (),
	SetCurrency: (self: MetaCluster, currency: Types.CurrencyData) -> (),
	SetVisible: (self: MetaCluster, visible: boolean) -> (),
	Destroy: (self: MetaCluster) -> (),
}

local MetaCluster = {}

local WIDTH = 300
local ROW_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall

local function makeLabel(name: string, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	label.LayoutOrder = order
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeColor3 = Theme.Colors.TextInverse
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

function MetaCluster.new(props: Props): MetaCluster
	local trove = Trove.new()
	local localize = props.Localize
	local pad = Theme.Sizes.Padding

	local column = Instance.new("Frame")
	column.Name = "TopLeft"
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromOffset(pad, pad)
	column.Size = UDim2.fromOffset(WIDTH, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	trove:Add(column)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = column

	local levelTitle = makeLabel("LevelTitle", 1, column)
	local levelBar =
		ProgressBar.new({ Name = "LevelBar", Color = Theme.Colors.Accent, LayoutOrder = 2, Parent = column })
	trove:Add(function()
		levelBar:Destroy()
	end)
	local folioLabel = makeLabel("Folios", 3, column)

	column.Parent = props.Parent

	local function setProgression(_self: MetaCluster, progression: Types.ProgressionData)
		local level = progression.Level
		levelTitle.Text = localize.t("level.title", { level = level })
		if level >= ProgressionConfig.MaxLevel then
			levelBar:SetProgress(1)
			levelBar:SetLabel(localize.t("level.max"))
			return
		end
		local needed = ProgressionConfig.xpForLevel(level)
		local xp = math.floor(progression.XP)
		levelBar:SetProgress(if needed > 0 then xp / needed else 0)
		levelBar:SetLabel(localize.t("level.xp", { xp = xp, needed = needed }))
	end

	local function setCurrency(_self: MetaCluster, currency: Types.CurrencyData)
		folioLabel.Text = localize.t("hud.currency", {
			amount = math.floor(currency.Folios),
			currency = localize.t(GameConfig.Currency.NameKey),
		})
	end

	local function setVisible(_self: MetaCluster, visible: boolean)
		column.Visible = visible
	end

	local function destroy(_self: MetaCluster)
		trove:Destroy()
	end

	local object: MetaCluster = {
		Instance = column,
		SetProgression = setProgression,
		SetCurrency = setCurrency,
		SetVisible = setVisible,
		Destroy = destroy,
	}
	return object
end

return MetaCluster
