--!strict
-- DailyScreen: the login streak (D-147), in the yellow Daily chapter. A calendar of the streak's seven days in
-- one row, the seventh twice as wide and dressed as a legendary: the days already claimed stamped with a check,
-- today's in the primary yellow, breathing, with a "!", tomorrow's faded and named in a line under the row,
-- the ones after that locked. One Claim in the footer. While today is still unclaimed and the streak is worth
-- keeping, a line says so -- in the tone of what can still be won, since nothing is lost yet.
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
type Day = {
	Index: number,
	Sticker: Sticker.Sticker,
	Scale: UIScale,
	Veil: Frame,
	Lock: Frame,
	Mark: Frame,
	Check: Seal.Seal,
	Badge: Badge.Badge,
	State: DayState?,
}
type Destroyable = { Destroy: (self: any) -> () }

local DailyScreen = {}

local CHAPTER = "Daily"
local STREAK_LENGTH = #DailyConfig.Streak
local STREAK_SIZE = 26
local LINE_SIZE = 16
-- The calendar: seven cards, the last twice as wide, and what each holds.
local CALENDAR_HEIGHT = 170
local DAY_PADDING = 10
local DAY_LABEL_SIZE = 14
local AMOUNT_SIZE = 16
local COIN_SIZE = 20
local CHECK_SEAL = 40
local LOCK_SIZE = 22
local LEGENDARY_RIM = 3
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

-- A reward line on a day card: an icon, then the amount in the number face.
local function amountRow(parent: Instance, order: number, text: string, icon: Frame?)
	local row = blank("Amount", parent)
	row.Size = UDim2.new(1, 0, 0, COIN_SIZE)
	row.LayoutOrder = order
	local layout = list(row, Enum.FillDirection.Horizontal, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	if icon ~= nil then
		icon.LayoutOrder = 1
		icon.Parent = row
	end
	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = Theme.Fonts.Numeric
	label.TextSize = AMOUNT_SIZE
	label.TextColor3 = Theme.Colors.Text
	label.Text = text
	label.LayoutOrder = 2
	label.Parent = row
end

function DailyScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local days: { Day } = {}
	-- A claim sent and not yet seen in the profile.
	local waiting = false
	local stopBreath: (() -> ())? = nil

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

	local pill = FoliosPill.new({ Parent = panel.Right })
	own(trove, pill)

	panel:SetHeaderHeight(Theme.Sizes.PaddingSmall * 2 + STREAK_SIZE + 6)
	local streakLine = textLabel("Streak", Theme.Fonts.Title, STREAK_SIZE, 1, panel.Header)
	streakLine.TextWrapped = false
	streakLine.TextTruncate = Enum.TextTruncate.AtEnd

	-- The Claim button carries the touch minimum, which follows the viewport, so the panel measures the
	-- footer from the same live height on every scale change.
	panel:SetFooterHeight(function()
		return Theme.Sizes.PaddingSmall + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight) + Theme.Sizes.Padding
	end)
	local footerLayout = list(panel.Footer, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	----------------------------------------------------------------
	-- The calendar
	----------------------------------------------------------------

	-- The content never scrolls: the calendar and its two lines stand in its window.
	local content = panel.Content
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.CanvasSize = UDim2.fromScale(1, 1)
	local column = blank("Streak", content)
	column.Size = UDim2.fromScale(1, 1)
	list(column, Enum.FillDirection.Vertical, Theme.Sizes.Gap)

	-- The profile is not here yet: a row where the calendar will be, breathing.
	local loading = ListRow.new({ Left = "", Variant = "Skeleton", LayoutOrder = 0, Parent = column })
	own(trove, loading)

	local calendar = blank("Calendar", column)
	calendar.Size = UDim2.new(1, 0, 0, CALENDAR_HEIGHT)
	calendar.LayoutOrder = 1
	list(calendar, Enum.FillDirection.Horizontal, Theme.Sizes.Gap)
	-- Six days share six eighths of the row, the seventh takes two: the gaps come off each in proportion.
	local gaps = Theme.Sizes.Gap * (STREAK_LENGTH - 1)
	local unit = 1 / (STREAK_LENGTH + 1)

	for index, reward in ipairs(DailyConfig.Streak) do
		local last = index == STREAK_LENGTH
		local share = if last then 2 else 1
		local sticker = Sticker.new({
			Kind = "Card",
			Fill = Theme.Colors.PanelRaised,
			Size = UDim2.new(unit * share, -gaps * unit * share, 1, 0),
			LayoutOrder = index,
			Parent = calendar,
			Name = "Day" .. tostring(index),
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

		local dayLabel = textLabel("Day", Theme.Fonts.Label, DAY_LABEL_SIZE, 1, body)
		dayLabel.TextWrapped = false
		dayLabel.TextXAlignment = Enum.TextXAlignment.Center
		dayLabel.Text = t("daily.day", { day = index })
		amountRow(body, 2, t("reward.xp", { xp = reward.Xp }))
		amountRow(body, 3, t("reward.folios", { amount = reward.Folios }), Icon.new("Coin", COIN_SIZE))

		-- The seventh is the week's prize: a legendary's rim and ribbon, with its shimmer.
		if last then
			local rim = blank("Rim", face)
			rim.Size = UDim2.fromScale(1, 1)
			rim.ZIndex = 6
			Theme.corner(rim, UDim.new(0, Theme.Sizes.CornerCard))
			Theme.stroke(rim, "Primary", LEGENDARY_RIM)
			local ribbon = RarityRibbon.new("Legendary", t(Theme.rarity("Legendary").WordKey), face)
			ribbon.Instance.AnchorPoint = Vector2.new(1, 0)
			ribbon.Instance.Position = UDim2.new(1, -Theme.Sizes.PaddingSmall, 0, -Theme.Sizes.PaddingSmall * 1.5)
			own(trove, ribbon)
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

		days[index] = {
			Index = index,
			Sticker = sticker,
			Scale = scale,
			Veil = veil,
			Lock = lock,
			Mark = mark,
			Check = check,
			Badge = badge,
			State = nil,
		}
	end

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

	local function paint(day: Day, state: DayState)
		if day.State == state then
			return
		end
		day.State = state
		local seventh = day.Index == STREAK_LENGTH
		local fill = if state == "Today"
			then Theme.Colors.Primary
			elseif state == "Past" then Theme.Colors.Chalk
			elseif seventh then Theme.Colors.Primary
			elseif state == "Later" then Theme.Colors.Chalk
			else Theme.Colors.PanelRaised
		day.Sticker:SetFill(fill)
		day.Veil.Visible = state == "Tomorrow"
		day.Lock.Visible = state == "Later"
		day.Mark.Visible = state == "Past"
		day.Badge:Set(if state == "Today" then "!" else nil)
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
		local evaluation = DailyStreak.evaluate(daily, DailyStreak.dayIndex(os.time()))
		-- Today's streak day: the one a claim would grant while it can, the one granted once it has.
		local streak = if evaluation.CanClaim then evaluation.NextStreak else daily.Streak
		local current = DailyStreak.rewardIndex(streak, STREAK_LENGTH)
		local tomorrow = current % STREAK_LENGTH + 1
		streakLine.Text = t("daily.streak", { day = streak })

		local todayCard: Day? = nil
		for _, day in ipairs(days) do
			local state: DayState
			if day.Index < current then
				state = "Past"
			elseif day.Index == current then
				state = if evaluation.CanClaim then "Today" else "Past"
			elseif day.Index == tomorrow then
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

		local next = DailyConfig.Streak[tomorrow]
		tomorrowLine.Text = t("daily.tomorrow", { reward = t("quest.reward", { xp = next.Xp, folios = next.Folios }) })
		-- Only a streak worth keeping, and only while it is still whole: a broken one has nothing to lose.
		local atRisk = evaluation.CanClaim and not evaluation.Broken and daily.Streak >= AT_RISK_STREAK
		atRiskLine.Text = if atRisk then t("daily.atRisk", { streak = daily.Streak }) else ""

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
