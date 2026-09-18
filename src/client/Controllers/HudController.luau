--!strict
-- HudController: the always-on overlay. Level / XP bar and Ryo counter (top-left), health and chakra
-- bars (bottom-left on mouse/gamepad, bottom-center above the combo row on touch so they never cover
-- the engine thumbstick), combo chips (bottom-center), server and local toasts, and the menu hint of
-- the device in use. Every visible text goes through Localize; server Notify payloads carry Strings
-- keys, never text.
--
-- While MatchController holds a match snapshot, a compact band is shown at the top-center: round, phase
-- timer (the countdown number while the round has not started), score and both team rosters with a
-- dead / alive marker. It disappears as soon as the snapshot is nil.

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
	MatchController: any,
}

local DISPLAY_ORDER = Theme.Layers.Hud
local COLUMN_WIDTH = 300
local ROW_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local CHIP_SIZE = 36
local COMBO_BOTTOM_MARGIN = 110 -- keeps the chips above the touch thumb cluster
-- On touch the bars sit above the combo row: the bottom-left corner belongs to the engine thumbstick.
local BARS_TOUCH_BOTTOM_MARGIN = COMBO_BOTTOM_MARGIN + CHIP_SIZE + Theme.Sizes.Gap
-- Ceiling on the top-centre column (see buildTopStack). Measured from the phone the layout targets: a
-- 375-unit viewport leaves 498.5 padded units at scale 0.68, and the bars start BARS_TOUCH_BOTTOM_MARGIN
-- above the bottom, so this is what is left above them with a gap to spare.
local TOP_STACK_MAX_HEIGHT = 240
local HINT_WIDTH = 220
local MENU_ACTION: InputConfig.ActionId = "Menu"
local GAMEPAD_PREFIX = "Gamepad"
local TOAST_KINDS: { [string]: boolean } = { Info = true, Success = true, Error = true }
local HINT_KEYS: { [string]: string } = { Keyboard = "hud.hint.keyboard", Gamepad = "hud.hint.gamepad" }
-- Match band (top-center, hidden outside a match).
local BAND_WIDTH = 360
-- Order inside the top-centre column (see buildTopStack). The boss band takes BOSS_BAND_ORDER, which
-- BossController reads through HudController.topStack.
local MATCH_BAND_ORDER = 1
local BOSS_BAND_ORDER = 2
local BAND_ROW_HEIGHT = Theme.Sizes.TextLarge + Theme.Sizes.PaddingSmall
local BAND_HERO_HEIGHT = Theme.Sizes.TextHero + Theme.Sizes.PaddingSmall
local ROSTER_COLUMN_WIDTH = (BAND_WIDTH - Theme.Sizes.Gap) / 2
local ROSTER_ROW_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local COUNTDOWN_PHASE = "Countdown"
-- Icon glyphs, locale independent (same convention as the panel close button).
local ALIVE_GLYPH = "●"
local DEAD_GLYPH = "✕"

local HudController = {}

local localize: any
local clientData: any
local remoteClient: any
local soundController: any
local comboController: any
local combatController: any
local matchController: any

local root: ScreenRoot.ScreenRoot
local levelTitle: TextLabel
local levelBar: ProgressBar.ProgressBar
local ryoLabel: TextLabel
local healthBar: ProgressBar.ProgressBar
local chakraBar: ProgressBar.ProgressBar
local comboRow: Frame
local hintLabel: TextLabel
local toast: Toast.Toast
local toastRoot: ScreenRoot.ScreenRoot
local topStack: Frame
local matchBand: Frame
local matchRoundLabel: TextLabel
local matchScoreLabel: TextLabel
local matchTimerLabel: TextLabel
local matchRoster: Frame
local rosterColumns: { Frame } = {}
local rosterLabels: { { TextLabel } } = {}
local notifyWarned = false
local hintSource: string? = nil -- "Keyboard" | "Gamepad" | "Touch", from the last input type

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

-- Centered line of the match band.
local function makeBandLabel(name: string, order: number, height: number, textSize: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.Font = Theme.Fonts.Bold
	label.TextSize = textSize
	label.TextColor3 = Theme.Colors.Text
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- The one top-centre column. The match band, the World Boss band and the toast queue all used to
-- declare the same anchor and the same position, so they drew on top of each other: a round-won toast
-- hid the score and the countdown digit in every ranked match, and during an event the wider boss band
-- covered the match band outright. They are now children of this frame with a vertical layout, so
-- whatever is showing stacks instead of overlapping. A UIListLayout allocates nothing for an invisible
-- child, so a hidden band costs no gap.
--
-- LayoutOrder is deliberate: persistent state first (match, then boss), transient messages last, so a
-- toast can never push the information the player needs off its place.
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
	-- the health and chakra bars, which on touch sit bottom-centre in the same column of screen.
	local ceiling = Instance.new("UISizeConstraint")
	ceiling.MaxSize = Vector2.new(math.huge, TOP_STACK_MAX_HEIGHT)
	ceiling.Parent = topStack
	topStack.ClipsDescendants = true
	topStack.Parent = parent
end

local function buildMatchBand(parent: Instance)
	matchBand = Instance.new("Frame")
	matchBand.Name = "Match"
	matchBand.BackgroundTransparency = 1
	matchBand.LayoutOrder = MATCH_BAND_ORDER
	matchBand.Size = UDim2.fromOffset(BAND_WIDTH, 0)
	matchBand.AutomaticSize = Enum.AutomaticSize.Y
	matchBand.Visible = false -- refreshMatch shows it while a snapshot is held
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = matchBand

	matchRoundLabel = makeBandLabel("Round", 1, ROSTER_ROW_HEIGHT, Theme.Sizes.TextSmall, matchBand)
	matchRoundLabel.TextColor3 = Theme.Colors.TextMuted
	matchScoreLabel = makeBandLabel("Score", 2, BAND_ROW_HEIGHT, Theme.Sizes.TextTitle, matchBand)
	matchScoreLabel.TextColor3 = Theme.Colors.Accent
	matchTimerLabel = makeBandLabel("Timer", 3, BAND_ROW_HEIGHT, Theme.Sizes.TextLarge, matchBand)

	matchRoster = Instance.new("Frame")
	matchRoster.Name = "Roster"
	matchRoster.BackgroundTransparency = 1
	matchRoster.Size = UDim2.fromScale(1, 0)
	matchRoster.AutomaticSize = Enum.AutomaticSize.Y
	matchRoster.LayoutOrder = 4
	local rosterLayout = Instance.new("UIListLayout")
	rosterLayout.FillDirection = Enum.FillDirection.Horizontal
	rosterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rosterLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rosterLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	rosterLayout.Parent = matchRoster
	matchRoster.Parent = matchBand

	matchBand.Parent = parent
end

local function build()
	root = ScreenRoot.new({ Name = "Hud", DisplayOrder = DISPLAY_ORDER })
	local content = root.Content
	local pad = Theme.Sizes.Padding

	local topLeft = makeColumn("TopLeft", Vector2.zero, UDim2.fromOffset(pad, pad), content)
	levelTitle = makeLabel("LevelTitle", 1, topLeft)
	levelBar = ProgressBar.new({ Name = "LevelBar", Color = Theme.Colors.Accent, LayoutOrder = 2, Parent = topLeft })
	ryoLabel = makeLabel("Ryo", 3, topLeft)

	local touch = UserInputService.TouchEnabled
	local barsAnchor = if touch then Vector2.new(0.5, 1) else Vector2.new(0, 1)
	local barsPosition = if touch then UDim2.new(0.5, 0, 1, -BARS_TOUCH_BOTTOM_MARGIN) else UDim2.new(0, pad, 1, -pad)
	local bars = makeColumn("Bars", barsAnchor, barsPosition, content)
	healthBar = ProgressBar.new({ Name = "HealthBar", Color = Theme.Colors.Health, LayoutOrder = 1, Parent = bars })
	chakraBar = ProgressBar.new({ Name = "ChakraBar", Color = Theme.Colors.Chakra, LayoutOrder = 2, Parent = bars })

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
	hintLabel.Visible = false -- refreshHint shows it for the device in use
	hintLabel.Parent = content

	buildTopStack(content)
	buildMatchBand(topStack)

	-- The toast queue gets its own ScreenGui on Theme.Layers.Toast, ABOVE every menu screen. It is the
	-- only surface a server message has, and screens now sit deterministically above the HUD, so leaving
	-- it inside the HUD made every server message unreadable while a panel was open: the panel covered it
	-- and the panel's dim overlay covered the rest. A player refused a purchase saw nothing at all.
	--
	-- It also stops the column from growing down over the bars: the column holds the two bands only, so
	-- their combined height is bounded by the match and boss layouts rather than by how many messages
	-- happen to be on screen.
	toastRoot = ScreenRoot.new({ Name = "Toasts", DisplayOrder = Theme.Layers.Toast })
	toast = Toast.new({ Name = "Toasts", Parent = toastRoot.Content })
end

-- The top-centre column the match band, the boss band and the toasts share, plus the LayoutOrder the
-- boss band must use. BossController parents its band here instead of opening a second ScreenGui at the
-- same DisplayOrder, which had no defined draw order against this one.
function HudController.topStack(): (Frame?, number)
	return topStack, BOSS_BAND_ORDER
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

local function refreshHint(data: Types.ProfileData)
	local source = sourceFor(UserInputService:GetLastInputType())
	hintSource = source
	if source == "Touch" then
		hintLabel.Visible = false
		return
	end
	local gamepad = source == "Gamepad"
	local saved = if gamepad then data.Settings.Gamepad else data.Settings.Keyboard
	local defaults = if gamepad then InputConfig.DefaultGamepad else InputConfig.DefaultKeyboard
	local key = saved[MENU_ACTION] or defaults[MENU_ACTION]
	hintLabel.Text = localize.t(HINT_KEYS[source], { menu = key })
	hintLabel.Visible = true
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

-- Roster instances are pooled: a match snapshot lands a few times per second, so nothing is rebuilt.
-- Visibility is the caller's business (an empty team hides its whole column).
local function rosterColumn(index: number): Frame
	local existing: Frame? = rosterColumns[index]
	if existing ~= nil then
		return existing
	end
	local column = Instance.new("Frame")
	column.Name = "Team" .. index
	column.BackgroundTransparency = 1
	column.Size = UDim2.fromOffset(ROSTER_COLUMN_WIDTH, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.LayoutOrder = index
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column
	column.Parent = matchRoster
	rosterColumns[index] = column
	rosterLabels[index] = {}
	return column
end

local function rosterLabel(teamIndex: number, slot: number): TextLabel
	local column = rosterColumn(teamIndex)
	local labels = rosterLabels[teamIndex]
	local existing: TextLabel? = labels[slot]
	if existing ~= nil then
		existing.Visible = true
		return existing
	end
	local label = Instance.new("TextLabel")
	label.Name = "Member" .. slot
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, ROSTER_ROW_HEIGHT)
	label.LayoutOrder = slot
	label.Font = Theme.Fonts.Body
	label.TextSize = Theme.Sizes.TextSmall
	label.TextStrokeTransparency = 0.6
	-- Teams read outwards from the middle of the band: odd teams on the left, even teams on the right.
	label.TextXAlignment = if teamIndex % 2 == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = column
	labels[slot] = label
	return label
end

local function refreshRoster(snapshot: Types.MatchSnapshot)
	for teamIndex, members in ipairs(snapshot.Teams) do
		local column = rosterColumn(teamIndex)
		column.Visible = #members > 0
		for slot, member in ipairs(members) do
			local label = rosterLabel(teamIndex, slot)
			label.Text = (if member.Alive then ALIVE_GLYPH else DEAD_GLYPH) .. " " .. member.Name
			if not member.Alive then
				label.TextColor3 = Theme.Colors.TextMuted
			elseif teamIndex == snapshot.LocalTeam then
				label.TextColor3 = Theme.Colors.Success
			else
				label.TextColor3 = Theme.Colors.Danger
			end
		end
		local labels = rosterLabels[teamIndex]
		for slot = #members + 1, #labels do
			labels[slot].Visible = false
		end
	end
	for index = #snapshot.Teams + 1, #rosterColumns do
		rosterColumns[index].Visible = false
	end
end

local function refreshMatch(snapshot: Types.MatchSnapshot?)
	if snapshot == nil then
		matchBand.Visible = false
		return
	end
	-- Best-of series: winning RoundsToWin rounds takes at most 2 * RoundsToWin - 1 rounds.
	local total = math.max(snapshot.Round, snapshot.RoundsToWin * 2 - 1)
	matchRoundLabel.Text = localize.t("match.round", { round = snapshot.Round, total = total })

	local ours = 0
	local theirs = 0
	for index, score in ipairs(snapshot.Scores) do
		if index == snapshot.LocalTeam then
			ours = score
		else
			theirs = math.max(theirs, score)
		end
	end
	matchScoreLabel.Text = localize.t("match.score", { ours = ours, theirs = theirs })

	local seconds = math.max(0, math.ceil(snapshot.SecondsLeft))
	if snapshot.Phase == COUNTDOWN_PHASE then
		matchTimerLabel.Size = UDim2.new(1, 0, 0, BAND_HERO_HEIGHT)
		matchTimerLabel.TextSize = Theme.Sizes.TextHero
		matchTimerLabel.Text = localize.t("match.countdown", { seconds = seconds })
	else
		matchTimerLabel.Size = UDim2.new(1, 0, 0, BAND_ROW_HEIGHT)
		matchTimerLabel.TextSize = Theme.Sizes.TextLarge
		matchTimerLabel.Text = localize.t("match.timeLeft", { seconds = seconds })
	end

	refreshRoster(snapshot)
	matchBand.Visible = true
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
	if toast == nil then
		-- Same reason as showLocalToast: a HUD that never built must not turn every server message into
		-- an error on the remote handler.
		return
	end
	toast:Show(localize.t(payload.Key, localize.resolveParams(params)), kind)
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
	toast:Show(localize.t(key, params), kind or "Info")
end

function HudController.Init(deps: Deps)
	localize = deps.Localize
	clientData = deps.ClientData
	remoteClient = deps.RemoteClient
	soundController = deps.SoundController
	comboController = deps.ComboController
	combatController = deps.CombatController
	matchController = deps.MatchController
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
	comboController.SequenceChanged:Connect(refreshCombo)
	combatController.StateChanged:Connect(refreshCombat)
	refreshCombat(combatController.getState())
	matchController.MatchChanged:Connect(refreshMatch)
	refreshMatch(matchController.getMatch())
	remoteClient.on("Notify", onNotify)
	log.info("started")
end

return HudController
