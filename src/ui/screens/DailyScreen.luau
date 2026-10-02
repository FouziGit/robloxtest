--!strict
-- DailyScreen: the login calendar (D-147, E15-S1), in the yellow Daily chapter. Its 28 days are shown a week at a
-- time: the week today falls in, seven cards in one row, the seventh twice as wide and dressed as the cosmetic it
-- gives -- its rarity's rim and ribbon, its name. The days already claimed stamped with a check, today's in the
-- primary yellow, breathing, with a "!", tomorrow's faded and named in a line under the row, the ones after that
-- locked; a day that slips a Signet into the book wears a bookmark in its corner. The header says which day of
-- the 28 this is and how long the streak runs, and shows the Signets held, a bookmark each. One Claim in the
-- footer. Under the row, a line says what a missed day would cost -- in the tone of what can still be won, since
-- nothing is lost yet -- or that a Signet is keeping the streak, or what a Signet is for.
--
-- Whether today can be claimed is derived from the profile's Daily section through the pure DailyStreak
-- module (the same one the server uses), so the button matches the server's decision. The claim goes through
-- ClaimDaily and waits for the profile to show it: then today's card is stamped, blots burst behind it and
-- the band's Folios count up; no answer at all says so.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Badge = require(script.Parent.Parent.components.Badge)
local Burst = require(script.Parent.Parent.components.Burst)
local Button = require(script.Parent.Parent.components.Button)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local DailyConfig = require(Shared.Config.DailyConfig)
local DailyStreak = require(Shared.Pure.DailyStreak)
local FoliosPill = require(script.Parent.Parent.components.FoliosPill)
local Icon = require(script.Parent.Parent.components.Icon)
local ListRow = require(script.Parent.Parent.components.ListRow)
local Motion = require(script.Parent.Parent.Motion)
local Panel = require(script.Parent.Parent.components.Panel)
local RarityRibbon = require(script.Parent.Parent.components.RarityRibbon)
local ScreenRoot = require(script.Parent.Parent.components.ScreenRoot)
local Seal = require(script.Parent.Parent.components.Seal)
local Sticker = require(script.Parent.Parent.components.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Deps = {
	Localize: { t: (key: string, params: { [string]: any }?) -> string },
	ClientData: { get: () -> Types.ProfileData?, Changed: any },
	RemoteClient: { fire: (name: string, ...any) -> () },
	InputController: { captureNext: (kind: string, callback: (keyName: string?) -> ()) -> () },
	SoundController: { play: (sfxId: string, position: Vector3?) -> () },
	-- A claim that never hears back says so on the HUD's toast column.
	HudController: { showLocalToast: (key: string, params: { [string]: any }?, kind: string?) -> () },
	OnClose: () -> (),
	OnNavigate: (id: string, args: any?) -> (),
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

type DayState = "Past" | "Today" | "Tomorrow" | "Later"
-- One card of the week's row: its slot in the week (1 to 7) and the calendar day it shows now.
type Day = {
	Slot: number,
	Number: number,
	Sticker: Sticker.Sticker,
	Scale: UIScale,
	Veil: Frame,
	Lock: Frame,
	Mark: Frame,
	Check: Seal.Seal,
	Badge: Badge.Badge,
	Word: TextLabel,
	Xp: TextLabel,
	Folios: TextLabel,
	-- The seventh card's: the cosmetic's name, and its rarity's rim.
	Prize: TextLabel?,
	Rim: UIStroke?,
	-- The bookmark of a day that slips a Signet in.
	Signet: Frame?,
	State: DayState?,
}
type Destroyable = { Destroy: (self: any) -> () }

local DailyScreen = {}

local CHAPTER = "Daily"
local CALENDAR = DailyConfig.Calendar
local CALENDAR_LENGTH = #CALENDAR
local WEEK = DailyConfig.WeekLength
local STREAK_SIZE = 26
local LINE_SIZE = 16
-- The calendar: seven cards, the last twice as wide, and what each holds. It is CALENDAR_HEIGHT tall where the
-- window has the room, and gives up height down to CALENDAR_MIN (what a card holds) where it has not.
local CALENDAR_HEIGHT = 170
local CALENDAR_MIN = 104
local DAY_PADDING = 10
local DAY_LABEL_SIZE = 14
local AMOUNT_SIZE = 16
local COIN_SIZE = 20
local CHECK_SEAL = 40
local LOCK_SIZE = 22
local PRIZE_RIM = 3
-- A Signet day's bookmark, in the card's bottom corner, and the header's, one per Signet the book holds.
local SIGNET_MARK = 16
local SIGNET_ICON = 20
local SIGNET_LABEL_SIZE = 14
-- A bookmark the book does not hold is drawn this faded.
local SIGNET_EMPTY = 0.7
-- The prize card's rim, and its ribbon just over it.
local RIM_Z = 6
-- Tomorrow's card is faded by a veil of the page.
local TOMORROW_VEIL = 0.4
-- Today's card breathes while it waits.
local TODAY_BREATH = 1.04
-- A claim's burst: three blots of the chapter's yellow and two of the green that says done.
local BURST_TINTS = {
	Theme.Colors.Primary,
	Theme.Colors.Primary,
	Theme.Colors.Primary,
	Theme.Colors.SuccessFill,
	Theme.Colors.SuccessFill,
}
-- The streak worth warning about: from two days on.
local AT_RISK_STREAK = 2

local function own(owner: typeof(Trove.new()), object: Destroyable)
	owner:Add(function()
		object:Destroy()
	end)
end

local function blank(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function list(frame: Frame, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = frame
	return layout
end

local function textLabel(name: string, font: Font, size: number, order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = Theme.Colors.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent
	return label
end

-- An amount on a day card, in the number face, sized by its text.
local function amountLabel(order: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = Theme.Fonts.Numeric
	label.TextSize = AMOUNT_SIZE
	label.TextColor3 = Theme.Colors.Text
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

-- A reward line on a day card: centred, one row tall, laid out left to right.
local function amountRow(parent: Instance, order: number): Frame
	local row = blank("Amount", parent)
	row.Size = UDim2.new(1, 0, 0, COIN_SIZE)
	row.LayoutOrder = order
	local layout = list(row, Enum.FillDirection.Horizontal, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return row
end

local function coin(order: number, parent: Instance)
	local icon = Icon.new("Coin", COIN_SIZE)
	icon.LayoutOrder = order
	icon.Parent = parent
end

-- The calendar day the card in `slot` shows while `current` is the day today stands on.
local function dayFor(current: number, slot: number): number
	return (DailyStreak.weekOf(current, WEEK) - 1) * WEEK + slot
end

function DailyScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local days: { Day } = {}
	-- A claim sent and not yet seen in the profile.
	local waiting = false
	local stopBreath: (() -> ())? = nil
	-- The prize card's ribbon, for the rarity it shows now.
	local ribbon: RarityRibbon.RarityRibbon? = nil
	local ribbonRarity: string? = nil

	local root = ScreenRoot.new({
		Name = "DailyScreen",
		DisplayOrder = Theme.Layers.Screen,
		Chapter = CHAPTER,
		TextScalable = true,
	})
	own(trove, root)
	root.Instance.Enabled = false

	local panel = Panel.new({
		Title = t("daily.title"),
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

	local pill = FoliosPill.new({ Localize = deps.Localize, Parent = panel.Right })
	own(trove, pill)

	----------------------------------------------------------------
	-- The header: the day of the calendar and the streak, the Signets held
	----------------------------------------------------------------

	panel:SetHeaderHeight(Theme.Sizes.PaddingSmall * 2 + STREAK_SIZE + 6)
	-- One row: the words take what the Signets leave them, and the Signets stand at its right end.
	local standing = blank("Standing", panel.Header)
	standing.Size = UDim2.new(1, 0, 0, STREAK_SIZE + 6)
	local standingLayout = list(standing, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)
	standingLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local streakLine = textLabel("Streak", Theme.Fonts.Title, STREAK_SIZE, 1, standing)
	streakLine.AutomaticSize = Enum.AutomaticSize.None
	streakLine.Size = UDim2.fromScale(0, 1)
	streakLine.TextWrapped = false
	streakLine.TextTruncate = Enum.TextTruncate.AtEnd
	local streakFill = Instance.new("UIFlexItem")
	streakFill.FlexMode = Enum.UIFlexMode.Fill
	streakFill.Parent = streakLine
	local signets = blank("Signets", standing)
	signets.LayoutOrder = 2
	signets.AutomaticSize = Enum.AutomaticSize.X
	signets.Size = UDim2.fromScale(0, 1)
	local signetsLayout = list(signets, Enum.FillDirection.Horizontal, 4)
	signetsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local signetsWord = Instance.new("TextLabel")
	signetsWord.Name = "Word"
	signetsWord.BackgroundTransparency = 1
	signetsWord.AutomaticSize = Enum.AutomaticSize.X
	signetsWord.Size = UDim2.fromScale(0, 1)
	signetsWord.FontFace = Theme.Fonts.Label
	signetsWord.TextSize = SIGNET_LABEL_SIZE
	signetsWord.TextColor3 = Theme.Colors.TextMuted
	signetsWord.Text = t("daily.signets")
	signetsWord.LayoutOrder = 0
	signetsWord.Parent = signets
	-- One bookmark per Signet the book can hold: in ink while held, faded while not.
	local held: { Frame } = {}
	for index = 1, DailyConfig.MaxSignets do
		local mark = Icon.new("Bookmark", SIGNET_ICON, Theme.Colors.Accent)
		mark.Name = "Signet" .. index
		mark.LayoutOrder = index
		mark.Parent = signets
		held[index] = mark
	end

	-- The Claim button carries the touch minimum, which follows the viewport, so the panel measures the
	-- footer from the same live height on every scale change.
	panel:SetFooterHeight(function()
		return Theme.Sizes.PaddingSmall + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight) + Theme.Sizes.Padding
	end)
	local footerLayout = list(panel.Footer, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	----------------------------------------------------------------
	-- The week's row
	----------------------------------------------------------------

	-- The content never scrolls: the row and its two lines stand in its window.
	panel:SetContentMode("Fill")
	local content = panel.Content
	local column = blank("Streak", content)
	column.Size = UDim2.fromScale(1, 1)
	list(column, Enum.FillDirection.Vertical, Theme.Sizes.Gap)

	-- The profile is not here yet: a row where the calendar will be, breathing.
	local loading = ListRow.new({ Left = "", Variant = "Skeleton", LayoutOrder = 0, Parent = column })
	own(trove, loading)

	-- The row takes what the two lines under it leave: the content does not scroll, and a fixed row pushed them
	-- out of a phone's window, the nudge first (tests/DailyFit.spec.luau).
	local calendar = blank("Calendar", column)
	calendar.Size = UDim2.fromScale(1, 0)
	calendar.LayoutOrder = 1
	local calendarFill = Instance.new("UIFlexItem")
	calendarFill.FlexMode = Enum.UIFlexMode.Fill
	calendarFill.Parent = calendar
	local calendarRange = Instance.new("UISizeConstraint")
	calendarRange.MinSize = Vector2.new(0, CALENDAR_MIN)
	calendarRange.MaxSize = Vector2.new(math.huge, CALENDAR_HEIGHT)
	calendarRange.Parent = calendar
	list(calendar, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)
	-- Six days share six eighths of the row, the seventh takes two: the gaps come off each in proportion.
	local gaps = Theme.Sizes.Gap * (WEEK - 1)
	local unit = 1 / (WEEK + 1)

	for slot = 1, WEEK do
		local last = slot == WEEK
		local share = if last then 2 else 1
		local sticker = Sticker.new({
			Kind = "Card",
			Fill = Theme.Colors.PanelRaised,
			-- A whole number of pixels, rounded up: a truncated share ran the row past the calendar's edge.
			Size = UDim2.new(unit * share, -math.ceil(gaps * unit * share), 1, 0),
			LayoutOrder = slot,
			Parent = calendar,
			Name = "Day" .. tostring(slot),
		})
		own(trove, sticker)
		local scale = Instance.new("UIScale")
		scale.Parent = sticker.Instance
		trove:Add(function()
			Motion.cancel(scale)
		end)
		local face = sticker.Face
		local body = blank("Body", face)
		body.Size = UDim2.fromScale(1, 1)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, DAY_PADDING)
		padding.PaddingBottom = UDim.new(0, DAY_PADDING)
		padding.PaddingLeft = UDim.new(0, DAY_PADDING / 2)
		padding.PaddingRight = UDim.new(0, DAY_PADDING / 2)
		padding.Parent = body
		local bodyLayout = list(body, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)
		bodyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

		-- The day's word from the card's left, in a box that ends where today's badge begins, as a tile's word
		-- stands clear of its badge: centred across the card, today's "!" covered its number (seen in Studio).
		local dayRow = blank("DayRow", body)
		dayRow.Size = UDim2.new(1, 0, 0, DAY_LABEL_SIZE + 6)
		dayRow.LayoutOrder = 1
		local dayLabel = textLabel("Day", Theme.Fonts.Label, DAY_LABEL_SIZE, 1, dayRow)
		dayLabel.AutomaticSize = Enum.AutomaticSize.None
		-- A whole padding in from the card's edge (half of it is the body's), up to the badge's corner.
		dayLabel.Position = UDim2.fromOffset(DAY_PADDING / 2, 0)
		dayLabel.Size = UDim2.new(1, -Badge.reach(), 1, 0)
		dayLabel.TextWrapped = false
		dayLabel.TextTruncate = Enum.TextTruncate.AtEnd
		dayLabel.TextXAlignment = Enum.TextXAlignment.Left

		local xp: TextLabel
		local folios: TextLabel
		local prize: TextLabel? = nil
		local rim: UIStroke? = nil
		local signet: Frame? = nil
		if last then
			-- The week's prize: the cosmetic's name, then its XP and Folios side by side on the wide card.
			local prizeLabel = textLabel("Prize", Theme.Fonts.Bold, AMOUNT_SIZE, 2, body)
			prizeLabel.AutomaticSize = Enum.AutomaticSize.None
			prizeLabel.Size = UDim2.new(1, 0, 0, COIN_SIZE)
			prizeLabel.TextWrapped = false
			prizeLabel.TextTruncate = Enum.TextTruncate.AtEnd
			prizeLabel.TextXAlignment = Enum.TextXAlignment.Center
			prize = prizeLabel
			local amounts = amountRow(body, 3)
			xp = amountLabel(1, amounts)
			coin(2, amounts)
			folios = amountLabel(3, amounts)
			-- Its rarity's rim, over which the ribbon lies (refresh dresses both for the week shown).
			local rimFrame = blank("Rim", face)
			rimFrame.Size = UDim2.fromScale(1, 1)
			rimFrame.ZIndex = RIM_Z
			Theme.corner(rimFrame, UDim.new(0, Theme.Sizes.CornerCard))
			rim = Theme.stroke(rimFrame, "Primary", PRIZE_RIM)
		else
			xp = amountLabel(1, amountRow(body, 2))
			local foliosRow = amountRow(body, 3)
			coin(1, foliosRow)
			folios = amountLabel(2, foliosRow)
			-- The bookmark of a Signet day, in the bottom corner the lock and the check leave free.
			local mark = Icon.new("Bookmark", SIGNET_MARK, Theme.Colors.Accent)
			mark.Name = "SignetMark"
			mark.AnchorPoint = Vector2.new(1, 1)
			mark.Position = UDim2.new(1, -DAY_PADDING / 2, 1, -DAY_PADDING / 2)
			mark.ZIndex = 5
			mark.Visible = false
			mark.Parent = face
			signet = mark
		end

		local veil = blank("Veil", face)
		veil.BackgroundColor3 = Theme.Colors.Panel
		veil.BackgroundTransparency = TOMORROW_VEIL
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = 4
		veil.Visible = false
		Theme.corner(veil, UDim.new(0, Theme.Sizes.CornerCard))
		local lock = Icon.new("Lock", LOCK_SIZE, Theme.Colors.TextMuted)
		lock.AnchorPoint = Vector2.new(0.5, 1)
		lock.Position = UDim2.new(0.5, 0, 1, -DAY_PADDING)
		lock.ZIndex = 5
		lock.Visible = false
		lock.Parent = face
		-- Claimed: a check seal pressed over the card, a little turned.
		local mark = blank("Claimed", face)
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.62)
		mark.Size = UDim2.fromOffset(CHECK_SEAL, CHECK_SEAL)
		mark.Rotation = -8
		mark.ZIndex = 5
		mark.Visible = false
		local check = Seal.new({
			Text = Theme.Glyphs.Check,
			Fill = Theme.Colors.SuccessFill,
			Size = CHECK_SEAL,
			Parent = mark,
		})
		own(trove, check)
		local badge = Badge.new(nil, sticker.Instance, Theme.Colors.PanelRaised)
		own(trove, badge)

		days[slot] = {
			Slot = slot,
			Number = 0,
			Sticker = sticker,
			Scale = scale,
			Veil = veil,
			Lock = lock,
			Mark = mark,
			Check = check,
			Badge = badge,
			Word = dayLabel,
			Xp = xp,
			Folios = folios,
			Prize = prize,
			Rim = rim,
			Signet = signet,
			State = nil,
		}
	end
	trove:Add(function()
		if ribbon ~= nil then
			ribbon:Destroy()
		end
	end)

	local tomorrowLine = textLabel("Tomorrow", Theme.Fonts.Bold, LINE_SIZE, 2, column)
	tomorrowLine.TextColor3 = Theme.Colors.TextMuted
	local atRiskLine = textLabel("AtRisk", Theme.Fonts.Body, LINE_SIZE, 3, column)
	atRiskLine.TextColor3 = Theme.Colors.Success

	----------------------------------------------------------------
	-- Claiming
	----------------------------------------------------------------

	-- The claim waits on the server, on the button; no answer in time is said, and the button is back.
	local claimButton: Button.Button
	claimButton = Button.new({
		Text = t("daily.claim"),
		Variant = "Primary",
		Wide = true,
		Parent = panel.Footer,
		OnClick = function()
			if waiting then
				return
			end
			waiting = true
			claimButton:SetPending(true)
			deps.RemoteClient.fire("ClaimDaily")
		end,
		OnTimeout = function()
			waiting = false
			deps.HudController.showLocalToast("common.pendingTimeout", nil, "Error")
		end,
	})
	own(trove, claimButton)

	-- Today's card breathes while it waits, on its own loop, only while the screen is up.
	local function setBreathing(day: Day?)
		local stop = stopBreath
		stopBreath = nil
		if stop ~= nil then
			stop()
		end
		if day ~= nil and screen.Visible then
			stopBreath = Motion.loop(
				day.Scale,
				{ Scale = 1 },
				{ Scale = TODAY_BREATH },
				"Ui",
				Theme.Timing.IdleBreathSeconds
			)
		end
	end
	trove:Add(function()
		setBreathing(nil)
	end)

	-- The prize card dressed for the cosmetic its week ends on: the name, the rim and the ribbon of its rarity.
	local function dressPrize(day: Day, entry: DailyConfig.CalendarDay)
		local item = if entry.Cosmetic ~= nil then CosmeticConfig.ById[entry.Cosmetic] else nil
		local prize, rim = day.Prize, day.Rim
		if prize == nil or rim == nil then
			return
		end
		prize.Text = if item ~= nil then t(item.NameKey) else ""
		local rarity = if item ~= nil then item.Rarity :: string else "Common"
		rim.Color = Theme.rarity(rarity).Fill
		if ribbonRarity == rarity then
			return
		end
		if ribbon ~= nil then
			ribbon:Destroy()
		end
		ribbonRarity = rarity
		-- Over the rim, whose outline would otherwise strike its word through, and standing on the card's top
		-- edge down to the padding the day's word starts under.
		local face = day.Sticker.Face
		local fresh = RarityRibbon.new(rarity, t(Theme.rarity(rarity).WordKey), face)
		fresh.Instance.AnchorPoint = Vector2.new(1, 1)
		fresh.Instance.Position = UDim2.new(1, -Theme.Sizes.PaddingSmall, 0, DAY_PADDING)
		fresh.Instance.ZIndex = RIM_Z + 1
		ribbon = fresh
	end

	-- The card of slot `day.Slot` showing calendar day `number`: its word, its amounts, its bookmark or its prize.
	local function show(day: Day, number: number)
		if day.Number == number then
			return
		end
		day.Number = number
		local entry = CALENDAR[number]
		if entry == nil then
			return
		end
		day.Word.Text = t("daily.day", { day = number })
		day.Xp.Text = t("reward.xp", { xp = entry.Xp })
		day.Folios.Text = t("reward.folios", { amount = entry.Folios })
		local signet = day.Signet
		if signet ~= nil then
			signet.Visible = entry.Signet == true
		end
		dressPrize(day, entry)
	end

	local function paint(day: Day, state: DayState)
		if day.State == state then
			return
		end
		day.State = state
		local prize = day.Slot == WEEK
		local fill = if state == "Today"
			then Theme.Colors.Primary
			elseif state == "Past" then Theme.Colors.Chalk
			elseif prize then Theme.Colors.Primary
			elseif state == "Later" then Theme.Colors.Chalk
			else Theme.Colors.PanelRaised
		day.Sticker:SetFill(fill)
		day.Veil.Visible = state == "Tomorrow"
		day.Lock.Visible = state == "Later"
		day.Mark.Visible = state == "Past"
		day.Badge:Set(if state == "Today" then "!" else nil)
	end

	-- What tomorrow brings: its cosmetic, or its XP and Folios, and its Signet.
	local function tomorrowText(number: number): string
		local entry = CALENDAR[number]
		local item = if entry.Cosmetic ~= nil then CosmeticConfig.ById[entry.Cosmetic] else nil
		local reward = if item ~= nil
			then t(item.NameKey)
			else t("quest.reward", { xp = entry.Xp, folios = entry.Folios })
		return t(if entry.Signet then "daily.tomorrow.signet" else "daily.tomorrow", { reward = reward })
	end

	local function refresh()
		local data = deps.ClientData.get()
		loading.Instance.Visible = data == nil
		calendar.Visible = data ~= nil
		if data == nil then
			streakLine.Text = ""
			tomorrowLine.Text = ""
			atRiskLine.Text = ""
			claimButton:SetDisabled(true)
			setBreathing(nil)
			return
		end
		pill:Set(data.Currency.Folios, screen.Visible)
		local daily = data.Daily
		-- The server's day, the one it grants a claim on: never the player's own clock.
		local today = DailyStreak.dayIndex(workspace:GetServerTimeNow())
		local evaluation = DailyStreak.evaluate(daily, today, CALENDAR_LENGTH)
		-- Today's calendar day: the one a claim would grant while it can, the one granted once it has.
		local current = if evaluation.CanClaim then evaluation.NextDay else math.max(daily.CalendarDay, 1)
		local tomorrow = current % CALENDAR_LENGTH + 1
		streakLine.Text = t("daily.calendar", {
			day = current,
			length = CALENDAR_LENGTH,
			streak = DailyStreak.standing(daily, today),
		})
		for index, mark in ipairs(held) do
			for _, child in ipairs(mark:GetDescendants()) do
				if child:IsA("GuiObject") then
					child.BackgroundTransparency = if index <= daily.Signets then 0 else SIGNET_EMPTY
				end
			end
		end

		local todayCard: Day? = nil
		for _, day in ipairs(days) do
			local number = dayFor(current, day.Slot)
			show(day, number)
			local state: DayState
			if number < current then
				state = "Past"
			elseif number == current then
				state = if evaluation.CanClaim then "Today" else "Past"
			elseif number == tomorrow then
				state = "Tomorrow"
			else
				state = "Later"
			end
			paint(day, state)
			if state == "Today" then
				todayCard = day
			end
		end
		setBreathing(todayCard)

		tomorrowLine.Text = tomorrowText(tomorrow)
		-- What a missed day would cost, only for a streak worth keeping and still whole; that a Signet keeps it
		-- when one does; and otherwise what a Signet is for, to whoever holds one.
		local atRisk = evaluation.CanClaim and not evaluation.Broken and daily.Streak >= AT_RISK_STREAK
		if evaluation.CanClaim and evaluation.SignetsUsed > 0 then
			atRiskLine.Text = t("daily.signetSaves")
		elseif atRisk then
			atRiskLine.Text = t("daily.atRisk", { streak = daily.Streak })
		elseif daily.Signets > 0 then
			atRiskLine.Text = t("daily.signetHint")
		else
			atRiskLine.Text = ""
		end

		if evaluation.CanClaim then
			claimButton:SetDisabled(false)
		else
			claimButton:SetDisabled(true, "Claimed", t("quest.claimed"))
		end
	end

	-- The claim is in the profile: today's card is stamped, the blots burst behind it.
	local function claimed(day: Day)
		claimButton:SetPending(false)
		claimButton:Flash("Success")
		day.Check:Stamp()
		Burst.play(day.Sticker.Instance, BURST_TINTS)
	end

	trove:Connect(deps.ClientData.Changed, function(section: string)
		if section ~= "*" and section ~= "Daily" and section ~= "Currency" then
			return
		end
		local before: Day? = nil
		for _, day in ipairs(days) do
			if day.State == "Today" then
				before = day
			end
		end
		refresh()
		if waiting and before ~= nil and before.State == "Past" then
			waiting = false
			claimed(before)
		end
	end)

	----------------------------------------------------------------
	-- Screen API
	----------------------------------------------------------------

	local function open(self: Screen, _args: any?)
		if self.Visible then
			return
		end
		self.Visible = true
		refresh()
		root:PlayEnter()
		-- A claimed day leaves the button disabled: the panel then focuses its close button.
		panel:FocusForGamepad(if claimButton:IsDisabled() then nil else claimButton.Instance)
		deps.SoundController.play("UiOpen")
	end

	local function close(self: Screen)
		if not self.Visible then
			return
		end
		self.Visible = false
		setBreathing(nil)
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
	refresh()
	return screen
end

return DailyScreen
