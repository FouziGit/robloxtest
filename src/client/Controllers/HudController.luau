--!strict
-- HudController: the always-on overlay. Level / XP bar and Ryo counter (top-left), health and chakra
-- bars (bottom-left), combo chips (bottom-center), server and local toasts, and the keyboard menu hint.
-- Every visible text goes through Localize; server Notify payloads carry Strings keys, never text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local ElementConfig = require(Shared.Config.ElementConfig)
local GameConfig = require(Shared.Config.GameConfig)
local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local ProgressBar = require(UI.components.ProgressBar)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local ScreenRoot = require(UI.components.ScreenRoot)
local Theme = require(UI.Theme)
local Toast = require(UI.components.Toast)
local Types = require(Shared.Types)

local log = Log.new("HudController")

export type ToastKind = "Info" | "Success" | "Error"

type CombatState = { Health: number, MaxHealth: number, Chakra: number, MaxChakra: number }

type Deps = {
	Localize: any,
	ClientData: any,
	RemoteClient: any,
	SoundController: any,
	ComboController: any,
	CombatController: any,
}

local DISPLAY_ORDER = 10
local COLUMN_WIDTH = 300
local ROW_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local CHIP_SIZE = 36
local COMBO_BOTTOM_MARGIN = 110 -- keeps the chips above the touch thumb cluster
local HINT_WIDTH = 220
local MENU_ACTION: InputConfig.ActionId = "Menu"
local TOAST_KINDS: { [string]: boolean } = { Info = true, Success = true, Error = true }

local HudController = {}

local localize: any
local clientData: any
local remoteClient: any
local soundController: any
local comboController: any
local combatController: any

local root: ScreenRoot.ScreenRoot
local levelTitle: TextLabel
local levelBar: ProgressBar.ProgressBar
local ryoLabel: TextLabel
local healthBar: ProgressBar.ProgressBar
local chakraBar: ProgressBar.ProgressBar
local comboRow: Frame
local hintLabel: TextLabel
local toast: Toast.Toast
local notifyWarned = false

local function makeColumn(name: string, anchor: Vector2, position: UDim2, parent: Instance): Frame
	local column = Instance.new("Frame")
	column.Name = name
	column.BackgroundTransparency = 1
	column.AnchorPoint = anchor
	column.Position = position
	column.Size = UDim2.fromOffset(COLUMN_WIDTH, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = column
	column.Parent = parent
	return column
end

local function makeLabel(name: string, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	label.LayoutOrder = order
	label.Font = Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

local function build()
	root = ScreenRoot.new({ Name = "Hud", DisplayOrder = DISPLAY_ORDER })
	local content = root.Content
	local pad = Theme.Sizes.Padding

	local topLeft = makeColumn("TopLeft", Vector2.zero, UDim2.fromOffset(pad, pad), content)
	levelTitle = makeLabel("LevelTitle", 1, topLeft)
	levelBar = ProgressBar.new({ Name = "LevelBar", Color = Theme.Colors.Accent, LayoutOrder = 2, Parent = topLeft })
	ryoLabel = makeLabel("Ryo", 3, topLeft)

	local bottomLeft = makeColumn("BottomLeft", Vector2.new(0, 1), UDim2.new(0, pad, 1, -pad), content)
	healthBar =
		ProgressBar.new({ Name = "HealthBar", Color = Theme.Colors.Health, LayoutOrder = 1, Parent = bottomLeft })
	chakraBar =
		ProgressBar.new({ Name = "ChakraBar", Color = Theme.Colors.Chakra, LayoutOrder = 2, Parent = bottomLeft })

	comboRow = Instance.new("Frame")
	comboRow.Name = "Combo"
	comboRow.BackgroundTransparency = 1
	comboRow.AnchorPoint = Vector2.new(0.5, 1)
	comboRow.Position = UDim2.new(0.5, 0, 1, -COMBO_BOTTOM_MARGIN)
	comboRow.Size = UDim2.fromOffset(0, CHIP_SIZE)
	comboRow.AutomaticSize = Enum.AutomaticSize.X
	local comboLayout = Instance.new("UIListLayout")
	comboLayout.FillDirection = Enum.FillDirection.Horizontal
	comboLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	comboLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	comboLayout.SortOrder = Enum.SortOrder.LayoutOrder
	comboLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	comboLayout.Parent = comboRow
	comboRow.Parent = content

	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.BackgroundTransparency = 1
	hintLabel.AnchorPoint = Vector2.new(1, 0)
	hintLabel.Position = UDim2.new(1, -pad, 0, pad)
	hintLabel.Size = UDim2.fromOffset(HINT_WIDTH, ROW_HEIGHT)
	hintLabel.Font = Theme.Fonts.Body
	hintLabel.TextSize = Theme.Sizes.TextSmall
	hintLabel.TextColor3 = Theme.Colors.TextMuted
	hintLabel.TextStrokeTransparency = 0.6
	hintLabel.TextXAlignment = Enum.TextXAlignment.Right
	hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
	hintLabel.Text = ""
	hintLabel.Visible = not UserInputService.TouchEnabled
	hintLabel.Parent = content

	toast = Toast.new({ Name = "Toasts", Parent = content })
end

local function makeChip(index: number, element: string): Frame
	local chip = Instance.new("Frame")
	chip.Name = "Chip" .. index
	chip.LayoutOrder = index
	chip.Size = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE)
	chip.BackgroundColor3 = Theme.elementColor(element)
	chip.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = chip
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Font = Theme.Fonts.Bold
	glyph.TextSize = Theme.Sizes.TextLarge
	glyph.TextColor3 = Theme.Colors.TextInverse
	glyph.Text = ElementConfig.Glyphs[element :: any] or ""
	glyph.Parent = chip
	return chip
end

local function refreshCombo(sequence: { string })
	for _, child in ipairs(comboRow:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, element in ipairs(sequence) do
		makeChip(index, element).Parent = comboRow
	end
end

local function refreshProgression(data: Types.ProfileData)
	local progression = data.Progression
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

local function refreshCurrency(data: Types.ProfileData)
	ryoLabel.Text = localize.t("hud.currency", {
		amount = math.floor(data.Currency.Ryo),
		currency = localize.t(GameConfig.Currency.NameKey),
	})
end

local function refreshHint(data: Types.ProfileData)
	local key = data.Settings.Keyboard[MENU_ACTION] or InputConfig.DefaultKeyboard[MENU_ACTION]
	hintLabel.Text = localize.t("hud.hint.keyboard", { menu = key })
end

local function refreshBar(bar: ProgressBar.ProgressBar, nameKey: string, current: number, max: number)
	bar:SetProgress(if max > 0 then current / max else 0)
	bar:SetLabel(localize.t("hud.bar", {
		name = localize.t(nameKey),
		current = math.floor(current + 0.5),
		max = math.floor(max + 0.5),
	}))
end

local function refreshCombat(state: CombatState)
	refreshBar(healthBar, "hud.health", state.Health, state.MaxHealth)
	refreshBar(chakraBar, "hud.chakra", state.Chakra, state.MaxChakra)
end

local function refreshProfile(section: string)
	local data: Types.ProfileData? = clientData.get()
	if data == nil then
		return
	end
	if section == "*" or section == "Progression" then
		refreshProgression(data)
	end
	if section == "*" or section == "Currency" then
		refreshCurrency(data)
	end
	if section == "*" or section == "Settings" then
		refreshHint(data)
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
	toast:Show(localize.t(payload.Key, localize.resolveParams(params)), kind)
	if type(payload.Sfx) == "string" then
		soundController.play(payload.Sfx)
	end
end

-- Client-originated feedback (combo resets, capture hints…): `key` is a Strings key.
function HudController.showLocalToast(key: string, params: { [string]: any }?, kind: ToastKind?)
	toast:Show(localize.t(key, params), kind or "Info")
end

function HudController.Init(deps: Deps)
	localize = deps.Localize
	clientData = deps.ClientData
	remoteClient = deps.RemoteClient
	soundController = deps.SoundController
	comboController = deps.ComboController
	combatController = deps.CombatController
	build()
end

function HudController.Start()
	clientData.Changed:Connect(refreshProfile)
	refreshProfile("*")
	comboController.SequenceChanged:Connect(refreshCombo)
	combatController.StateChanged:Connect(refreshCombat)
	refreshCombat(combatController.getState())
	remoteClient.on("Notify", onNotify)
	log.info("started")
end

return HudController
