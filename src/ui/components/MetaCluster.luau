--!strict
-- MetaCluster: what the player owns and what waits for them, in the hub (D-147). A column of four rows:
--
--   Level    their level on a seal of the primary yellow, and its XP on a bar over an ink strip
--   Folios   an ink pill: the coin, the count (counted up when it grows), and a "+" to the shop's Folios
--   Claims   a seal per kind of claim waiting -- the daily reward, quests, pass tiers -- each badged with how
--            many, shown only while there is one, and opening its screen
--   Queue    while the player queues: searching, for how long, and a cross to leave; the pill opens Play
--   Steps    a new player's first three: cast a glyph, play a match, claim the daily reward -- ticked as they
--            happen, stamped and folded away once all three are done
--
-- HudController places it (the bottom-left with a pointer, the engine's chat being top-left; the top-left on
-- touch, the thumbstick's corner being bottom-left), feeds it the profile and the counts, and hides it in a
-- fight -- a match or an arena -- which shows no value colour (docs/ART_BIBLE.md rule 11). It requires no
-- controller: what it opens and the queue it leaves are the HUD's callbacks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local Badge = require(script.Parent.Badge)
local Icon = require(script.Parent.Icon)
local Motion = require(script.Parent.Parent.Motion)
local ProgressBar = require(script.Parent.ProgressBar)
local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))
local Seal = require(script.Parent.Seal)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ThemeConfig = require(Config:WaitForChild("ThemeConfig"))
local Trove = require(Packages.Trove)
local Types = require(Shared:WaitForChild("Types"))
local UiSound = require(script.Parent.Parent.UiSound)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }
export type Corner = "Top" | "Bottom"
-- What waits to be claimed, by kind (Claimables.count).
export type Claims = { Daily: number, Quests: number, Pass: number }
-- The first steps done, from the profile: a glyph cast, a match played, a daily reward claimed.
export type Checklist = { Cast: boolean, Match: boolean, Daily: boolean }

export type Props = {
	Parent: Instance,
	Localize: Localizer,
	Corner: Corner,
	-- Opens a screen (MenuController.open), with its arguments.
	OnOpen: (screen: string, args: any?) -> (),
	OnLeaveQueue: () -> (),
}

export type MetaCluster = {
	Instance: Frame,
	SetProgression: (self: MetaCluster, progression: Types.ProgressionData) -> (),
	SetCurrency: (self: MetaCluster, currency: Types.CurrencyData) -> (),
	SetClaims: (self: MetaCluster, claims: Claims) -> (),
	SetQueue: (self: MetaCluster, queue: Types.QueueSnapshot) -> (),
	SetChecklist: (self: MetaCluster, done: Checklist) -> (),
	SetVisible: (self: MetaCluster, visible: boolean) -> (),
	Destroy: (self: MetaCluster) -> (),
}

type TroveObject = typeof(Trove.new())

local MetaCluster = {}

local HUD = ThemeConfig.Hud
local GAP = Theme.Sizes.PaddingSmall
-- The level: its seal, and how much a level gained punches it.
local LEVEL_SEAL = 56
local LEVEL_PUNCH = 1.25
local XP_BAR_WIDTH = 200
local XP_BAR_HEIGHT = 12
local XP_TEXT = 14
-- The pills: the Folios and the queue.
local PILL_HEIGHT = 40
local COIN = 26
local CIRCLE = 32
local FOLIOS_TAB = "Folios"
-- The claims: a seal per kind, in its chapter's colour, with its screen's icon.
local CLAIM_SEAL = 36
local CLAIM_ICON = 20
type ClaimKind = { Kind: string, Screen: string, Fill: string, Icon: Icon.Name }
local CLAIMS: { ClaimKind } = {
	{ Kind = "Daily", Screen = "Daily", Fill = "Primary", Icon = "Calendar" },
	{ Kind = "Quests", Screen = "Quests", Fill = "InfoFill", Icon = "Scroll" },
	{ Kind = "Pass", Screen = "Battlepass", Fill = "Epic", Icon = "Pass" },
}
-- The queue: three dots in a wave on one loop, the wait counted each second.
local DOT = 10
local DOT_FILLS: { string } = { "Ally", "PanelRaised", "Ally" }
local QUEUE_TEXT = 16
local PLAY_SCREEN = "Play"
local SECOND = 1
-- The first steps: a sheet card, a box per step (chalk, then the claimed green with a tick), the screen each
-- one leads to, and how long the stamp shows before the card folds.
local STEPS_WIDTH = 280
local STEPS_TITLE = 20
local STEP_HEIGHT = 26
local STEP_BOX = 20
local STEP_TEXT = 16
local STEPS_SEAL = 36
local STAMP_SECONDS = 1
type Step = { Kind: string, Key: string, Screen: string? }
local STEPS: { Step } = {
	{ Kind = "Cast", Key = "hud.checklist.cast" },
	{ Kind = "Match", Key = "hud.checklist.match", Screen = "Play" },
	{ Kind = "Daily", Key = "hud.checklist.daily", Screen = "Daily" },
}

local function textLabel(name: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = ""
	return label
end

local function horizontal(parent: Instance, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
end

-- A pressable sheet disc with a sign on it (the pill's "+" and "✕"): a button too small for a word, its hit
-- area floored at a thumb's.
local function circleButton(
	name: string,
	sign: string,
	order: number,
	onClick: () -> (),
	trove: TroveObject
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Selectable = false
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(CIRCLE, CIRCLE)
	Theme.minPixelSize(button, Theme.MinTouchTarget)
	local face = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Corner = Theme.Pill,
		Elevation = 3,
		Stroke = Theme.Sizes.StrokeThin,
		Parent = button,
		Name = "Face",
	})
	trove:Add(function()
		face:Destroy()
	end)
	local label = textLabel("Sign", Theme.Fonts.Bold, Theme.Sizes.TextBody, Theme.Colors.Text)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.Text = sign
	label.Parent = face.Face
	trove:Connect(button.MouseEnter, function()
		face:SetState("Hover")
	end)
	trove:Connect(button.MouseLeave, function()
		face:SetState("Idle")
	end)
	trove:Connect(button.MouseButton1Down, function()
		face:SetState("Pressed")
	end)
	trove:Connect(button.MouseButton1Up, function()
		face:SetState("Idle")
	end)
	trove:Connect(button.Activated, function()
		UiSound.play("UiClick")
		onClick()
	end)
	return button
end

-- An ink pill, as wide as what it holds, laid out left to right.
local function inkPill(name: string, order: number, parent: Instance, trove: TroveObject): Frame
	local pill = Instance.new("Frame")
	pill.Name = name
	pill.BackgroundTransparency = 1
	pill.LayoutOrder = order
	pill.Size = UDim2.fromOffset(0, PILL_HEIGHT)
	pill.AutomaticSize = Enum.AutomaticSize.X
	local plate = Sticker.new({ Kind = "Plate", Fill = Theme.Colors.Plate, Corner = Theme.Pill, Parent = pill })
	trove:Add(function()
		plate:Destroy()
	end)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromScale(0, 1)
	row.ZIndex = 3
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, GAP)
	padding.PaddingRight = UDim.new(0, (PILL_HEIGHT - CIRCLE) / 2)
	padding.Parent = row
	horizontal(row, GAP)
	row.Parent = pill
	pill.Parent = parent
	return pill
end

function MetaCluster.new(props: Props): MetaCluster
	local trove = Trove.new()
	local localize = props.Localize
	local pad = Theme.Sizes.Padding
	local bottom = props.Corner == "Bottom"

	local column = Instance.new("Frame")
	column.Name = "MetaCluster"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0, if bottom then 1 else 0)
	column.Position = if bottom then UDim2.new(0, pad, 1, -pad) else UDim2.fromOffset(pad, pad)
	column.Size = UDim2.fromOffset(HUD.MetaWidth, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	trove:Add(column)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = column

	-- The level: a seal of the primary yellow, and its XP beside it on an ink strip.
	local levelRow = Instance.new("Frame")
	levelRow.Name = "Level"
	levelRow.BackgroundTransparency = 1
	levelRow.LayoutOrder = 1
	levelRow.Size = UDim2.new(1, 0, 0, LEVEL_SEAL)
	horizontal(levelRow, GAP)
	levelRow.Parent = column
	local sealHolder = Instance.new("Frame")
	sealHolder.Name = "Seal"
	sealHolder.BackgroundTransparency = 1
	sealHolder.Size = UDim2.fromOffset(LEVEL_SEAL, LEVEL_SEAL)
	sealHolder.LayoutOrder = 1
	sealHolder.Parent = levelRow
	local sealScale = Instance.new("UIScale")
	sealScale.Parent = sealHolder
	trove:Add(function()
		Motion.cancel(sealScale)
	end)
	local levelSeal =
		Seal.new({ Text = "", Fill = Theme.Colors.Primary, Size = LEVEL_SEAL, Face = "Numeric", Parent = sealHolder })
	trove:Add(function()
		levelSeal:Destroy()
	end)
	local strip = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Size = UDim2.new(1, -(LEVEL_SEAL + GAP), 1, 0),
		LayoutOrder = 2,
		Parent = levelRow,
		Name = "Xp",
	})
	trove:Add(function()
		strip:Destroy()
	end)
	local xpText = textLabel("Value", Theme.Fonts.Numeric, XP_TEXT, Theme.Colors.TextInverse)
	xpText.Position = UDim2.fromOffset(pad, GAP)
	xpText.Size = UDim2.new(1, -pad * 2, 0, XP_TEXT)
	xpText.TextXAlignment = Enum.TextXAlignment.Left
	xpText.ZIndex = 3
	xpText.Parent = strip.Face
	local xpBar = ProgressBar.new({
		Name = "Bar",
		Color = Theme.Colors.Primary,
		OnPlate = true,
		Height = XP_BAR_HEIGHT,
		Size = UDim2.fromOffset(XP_BAR_WIDTH, XP_BAR_HEIGHT),
		Parent = strip.Face,
	})
	xpBar.Instance.AnchorPoint = Vector2.new(0, 1)
	xpBar.Instance.Position = UDim2.new(0, pad, 1, -GAP * 1.5)
	xpBar.Instance.ZIndex = 3
	trove:Add(function()
		xpBar:Destroy()
	end)

	-- The Folios: the coin, the count, and the way to more.
	local folios = inkPill("Folios", 2, column, trove)
	local foliosRow = folios:FindFirstChild("Row") :: Frame
	local coin = Icon.new("Coin", COIN)
	coin.LayoutOrder = 1
	coin.Parent = foliosRow
	local count = textLabel("Count", Theme.Fonts.Numeric, Theme.Sizes.Num, Theme.Colors.Primary)
	count.AutomaticSize = Enum.AutomaticSize.X
	count.Size = UDim2.fromScale(0, 1)
	count.LayoutOrder = 2
	count.Parent = foliosRow
	circleButton("More", Theme.Glyphs.Plus, 3, function()
		props.OnOpen("Shop", { Tab = FOLIOS_TAB })
	end, trove).Parent =
		foliosRow

	-- The claims: a seal per kind, each opening its screen.
	local claimsRow = Instance.new("Frame")
	claimsRow.Name = "Claims"
	claimsRow.BackgroundTransparency = 1
	claimsRow.LayoutOrder = 3
	claimsRow.Size = UDim2.fromOffset(0, CLAIM_SEAL)
	claimsRow.AutomaticSize = Enum.AutomaticSize.X
	claimsRow.Visible = false
	horizontal(claimsRow, GAP)
	claimsRow.Parent = column
	type ClaimSeal = { Button: TextButton, Badge: Badge.Badge }
	local claimSeals: { [string]: ClaimSeal } = {}
	for index, claim in ipairs(CLAIMS) do
		local button = Instance.new("TextButton")
		button.Name = claim.Kind
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Selectable = false
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(CLAIM_SEAL, CLAIM_SEAL)
		button.Visible = false
		Theme.minPixelSize(button, Theme.MinTouchTarget)
		local fill = Theme.color(claim.Fill)
		local seal = Seal.new({ Text = "", Fill = fill, Size = CLAIM_SEAL, Parent = button })
		trove:Add(function()
			seal:Destroy()
		end)
		local icon = Icon.new(claim.Icon, CLAIM_ICON, Theme.inkOn(fill))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4
		icon.Parent = seal.Instance
		-- On the primary yellow the badge is the sheet: a yellow blot on a yellow seal says nothing.
		local badge = Badge.new(nil, button, if fill == Theme.Colors.Primary then Theme.Colors.PanelRaised else nil)
		trove:Add(function()
			badge:Destroy()
		end)
		trove:Connect(button.Activated, function()
			UiSound.play("UiClick")
			props.OnOpen(claim.Screen)
		end)
		button.Parent = claimsRow
		claimSeals[claim.Kind] = { Button = button, Badge = badge }
	end

	-- The queue: the dots in a wave, the wait, the cross that leaves; the pill itself opens Play.
	local queue = inkPill("Queue", 4, column, trove)
	queue.Visible = false
	local queueScale = Instance.new("UIScale")
	queueScale.Parent = queue
	trove:Add(function()
		Motion.cancel(queueScale)
	end)
	local queueRow = queue:FindFirstChild("Row") :: Frame
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.LayoutOrder = 1
	dots.Size = UDim2.fromOffset(DOT * 3 + GAP / 2 * 2, DOT)
	horizontal(dots, GAP / 2)
	dots.Parent = queueRow
	local dotFrames: { Frame } = {}
	for index, role in ipairs(DOT_FILLS) do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. index
		dot.BorderSizePixel = 0
		dot.LayoutOrder = index
		dot.Size = UDim2.fromOffset(DOT, DOT)
		dot.BackgroundColor3 = Theme.color(role)
		Theme.corner(dot, Theme.Pill)
		dot.Parent = dots
		dotFrames[index] = dot
	end
	-- One loop for the three: a wave value going back and forth, each dot brightest at its own place in it.
	local wave = Instance.new("NumberValue")
	wave.Name = "Wave"
	wave.Parent = queue
	trove:Connect(wave.Changed, function(value: number)
		for index, dot in ipairs(dotFrames) do
			local place = (index - 1) / (#dotFrames - 1)
			dot.BackgroundTransparency = math.clamp(math.abs(value - place) * 1.5, 0, 0.8)
		end
	end)
	local searching = textLabel("Text", Theme.Fonts.Bold, QUEUE_TEXT, Theme.Colors.TextInverse)
	searching.AutomaticSize = Enum.AutomaticSize.X
	searching.Size = UDim2.fromScale(0, 1)
	searching.LayoutOrder = 2
	searching.Parent = queueRow
	circleButton("Leave", Theme.Glyphs.Close, 3, props.OnLeaveQueue, trove).Parent = queueRow
	local opener = Instance.new("TextButton")
	opener.Name = "Open"
	opener.AutoButtonColor = false
	opener.BackgroundTransparency = 1
	opener.Text = ""
	opener.Selectable = false
	opener.Size = UDim2.fromScale(1, 1)
	opener.ZIndex = 2
	opener.Parent = queue
	trove:Connect(opener.Activated, function()
		UiSound.play("UiClick")
		props.OnOpen(PLAY_SCREEN)
	end)

	-- The first steps, under the rest.
	local steps = Instance.new("Frame")
	steps.Name = "Steps"
	steps.BackgroundTransparency = 1
	steps.LayoutOrder = 5
	steps.Size = UDim2.fromOffset(STEPS_WIDTH, 0)
	steps.AutomaticSize = Enum.AutomaticSize.Y
	steps.Visible = false
	steps.Parent = column
	local stepsScale = Instance.new("UIScale")
	stepsScale.Parent = steps
	trove:Add(function()
		Motion.cancel(stepsScale)
	end)
	local card = Sticker.new({ Kind = "Card", Fill = Theme.Colors.PanelRaised, Parent = steps, Name = "Card" })
	trove:Add(function()
		card:Destroy()
	end)
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.ZIndex = 3
	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingSmall + 4)
	listPadding.PaddingLeft = UDim.new(0, pad)
	listPadding.PaddingRight = UDim.new(0, pad)
	-- Past the card's shadow, which the list stands over.
	listPadding.PaddingBottom = UDim.new(0, pad + 5)
	listPadding.Parent = list
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list
	list.Parent = steps
	local stepsTitle = textLabel("Title", Theme.Fonts.Title, STEPS_TITLE, Theme.Colors.Text)
	stepsTitle.Size = UDim2.new(1, 0, 0, STEPS_TITLE + 6)
	stepsTitle.TextXAlignment = Enum.TextXAlignment.Left
	stepsTitle.Text = localize.t("hud.checklist.title")
	stepsTitle.Parent = list
	type StepRow = { Box: Frame, Tick: TextLabel }
	local stepRows: { [string]: StepRow } = {}
	for index, step in ipairs(STEPS) do
		local row = Instance.new("TextButton")
		row.Name = step.Kind
		row.AutoButtonColor = false
		row.BackgroundTransparency = 1
		row.Text = ""
		row.Selectable = false
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, STEP_HEIGHT)
		horizontal(row, GAP)
		local box = Instance.new("Frame")
		box.Name = "Box"
		box.BorderSizePixel = 0
		box.BackgroundColor3 = Theme.Colors.Chalk
		box.Size = UDim2.fromOffset(STEP_BOX, STEP_BOX)
		box.LayoutOrder = 1
		Theme.corner(box, Theme.Sizes.CornerKeycap)
		Theme.stroke(box, "Accent", Theme.Sizes.StrokeThin)
		box.Parent = row
		local tick = textLabel("Tick", Theme.Fonts.Bold, STEP_TEXT, Theme.Colors.Text)
		tick.Size = UDim2.fromScale(1, 1)
		tick.Text = Theme.Glyphs.Check
		tick.Visible = false
		tick.Parent = box
		local words = textLabel("Text", Theme.Fonts.Body, STEP_TEXT, Theme.Colors.Text)
		words.AutomaticSize = Enum.AutomaticSize.X
		words.Size = UDim2.fromScale(0, 1)
		words.LayoutOrder = 2
		words.Text = localize.t(step.Key)
		words.Parent = row
		local screen = step.Screen
		if screen ~= nil then
			trove:Connect(row.Activated, function()
				UiSound.play("UiClick")
				props.OnOpen(screen)
			end)
		end
		row.Parent = list
		stepRows[step.Kind] = { Box = box, Tick = tick }
	end

	column.Parent = props.Parent

	local shownLevel: number? = nil
	local shownFolios: number? = nil
	local queued = false
	local waitedBase, waitedAt = 0, 0
	local queueToken = 0
	local stopWave: (() -> ())? = nil

	local function setProgression(_self: MetaCluster, progression: Types.ProgressionData)
		local level = progression.Level
		levelSeal:SetText(tostring(level))
		if shownLevel ~= nil and level > shownLevel then
			Motion.punch(sealScale, LEVEL_PUNCH)
		end
		shownLevel = level
		if level >= ProgressionConfig.MaxLevel then
			xpBar:SetProgress(1)
			xpText.Text = localize.t("level.max")
			return
		end
		local needed = ProgressionConfig.xpForLevel(level)
		local xp = math.floor(progression.XP)
		xpBar:SetProgress(if needed > 0 then xp / needed else 0)
		xpText.Text = localize.t("level.xp", { xp = xp, needed = needed })
	end

	local function setCurrency(_self: MetaCluster, currency: Types.CurrencyData)
		local amount = math.floor(currency.Folios)
		local from = shownFolios
		shownFolios = amount
		if from == nil or amount <= from then
			count.Text = tostring(amount)
			return
		end
		Motion.countTo(count, from, amount, tostring)
	end

	local function setClaims(_self: MetaCluster, claims: Claims)
		local any = false
		for _, claim in ipairs(CLAIMS) do
			local waiting = (claims :: any)[claim.Kind] :: number
			local seal = claimSeals[claim.Kind]
			seal.Button.Visible = waiting > 0
			seal.Badge:Set(if waiting > 0 then waiting else nil)
			any = any or waiting > 0
		end
		claimsRow.Visible = any
	end

	-- The wait, counted here each second between the server's snapshots.
	local function tick(token: number)
		if token ~= queueToken or not queued then
			return
		end
		local waited = waitedBase + math.floor(os.clock() - waitedAt)
		searching.Text = localize.t("queue.searching", { waited = waited })
		task.delay(SECOND, tick, token)
	end

	local function setQueue(_self: MetaCluster, snapshot: Types.QueueSnapshot)
		local was = queued
		queued = snapshot.Queued
		queueToken += 1
		if queued then
			waitedBase, waitedAt = snapshot.WaitedSeconds, os.clock()
			tick(queueToken)
			if not was then
				queue.Visible = true
				Motion.set(queueScale, { Scale = 0 })
				Motion.to(queueScale, { Scale = 1 }, "UiPop")
				stopWave = Motion.loop(wave, { Value = 0 }, { Value = 1 }, "Ui")
			end
			return
		end
		if was then
			local stop = stopWave
			stopWave = nil
			if stop ~= nil then
				stop()
			end
			Motion.to(queueScale, { Scale = 0 }, "UiExit", function()
				if not queued then
					queue.Visible = false
				end
			end)
		end
	end

	-- Nil before the profile first says: a player with all three done never sees the card at all.
	local allDone: boolean? = nil
	local function setChecklist(_self: MetaCluster, done: Checklist)
		for kind, row in pairs(stepRows) do
			local ticked = (done :: any)[kind] == true
			row.Box.BackgroundColor3 = if ticked then Theme.Colors.SuccessFill else Theme.Colors.Chalk
			row.Tick.Visible = ticked
		end
		local all = done.Cast and done.Match and done.Daily
		local before = allDone
		allDone = all
		if before == nil then
			steps.Visible = not all
			return
		end
		if all and not before then
			-- Done: the card is stamped, then folds away.
			Seal.new({
				Text = Theme.Glyphs.Check,
				Fill = Theme.Colors.SuccessFill,
				Size = STEPS_SEAL,
				Stamp = true,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -GAP, 0, GAP),
				Parent = card.Face,
			})
			task.delay(STAMP_SECONDS, function()
				Motion.to(stepsScale, { Scale = 0 }, "UiExit", function()
					if allDone then
						steps.Visible = false
					end
				end)
			end)
		end
	end

	local function setVisible(_self: MetaCluster, visible: boolean)
		column.Visible = visible
	end

	local function destroy(_self: MetaCluster)
		queueToken += 1
		local stop = stopWave
		stopWave = nil
		if stop ~= nil then
			stop()
		end
		Motion.cancel(wave)
		trove:Destroy()
	end

	local object: MetaCluster = {
		Instance = column,
		SetProgression = setProgression,
		SetCurrency = setCurrency,
		SetClaims = setClaims,
		SetQueue = setQueue,
		SetChecklist = setChecklist,
		SetVisible = setVisible,
		Destroy = destroy,
	}
	return object
end

return MetaCluster
