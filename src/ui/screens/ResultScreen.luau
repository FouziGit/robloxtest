--!strict
-- ResultScreen: the end-of-match summary, composed as the card a player screenshots: the outcome in the
-- roman, the score in the condensed grotesque at display size over a rule of ink, then the rewards, the
-- rating and the rank. MenuController opens it on MatchEnded; the outcome itself is
-- read from MatchController, which kept the last payload the server sent. Shows the result, the score,
-- the rewards, the rating line, the new rank when the tier changed and the first win of the day, then
-- closes itself after the mode's ResultSeconds or as soon as the player presses the button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local MatchConfig = require(Shared.Config.MatchConfig)
local Motion = require(script.Parent.Parent.Motion)
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
	-- Last MatchEnded payload: the server decided every number rendered here. joinQueue is the one-click
	-- loop: the server keeps the wish while this screen is still up and honours it the moment the match
	-- lets the player go (docs/JUICE_PLAN.md phase 8, item 2).
	MatchController: { getLastOutcome: () -> Types.MatchOutcome?, joinQueue: (modeId: string) -> () },
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

local ResultScreen = {}

local OVERLAY_TRANSPARENCY = 0.55
local PANEL_SIZE = Vector2.new(Theme.Sizes.PanelWidth, Theme.Sizes.PanelHeight)
local BUTTON_WIDTH = 150
-- Seconds the bar spends filling the level that was completed before it starts the next one.
local LEVEL_FILL_SECONDS = 0.45
local STATUS_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + STATUS_HEIGHT
local FALLBACK_RESULT_SECONDS = MatchConfig.Modes[MatchConfig.ModeOrder[1]].ResultSeconds
-- The rule of ink under the score.
local RULE_WIDTH = 160
local RULE_HEIGHT = 2
-- A new rank is stamped: it lands from larger than itself.
local STAMP_SCALE = 1.5

-- Dimmed backdrop that also swallows clicks so the world under the screen is not interacted with.
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

-- Centered summary line. Hidden lines are skipped by the content layout, so an outcome without a rating
-- or a rank change leaves no hole.
local function makeLine(name: string, order: number, textSize: number, color: Color3, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize + Theme.Sizes.PaddingSmall)
	label.LayoutOrder = order
	label.FontFace = Theme.Fonts.Bold
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

local function titleKey(outcome: Types.MatchOutcome): string
	if outcome.Draw then
		return "match.draw"
	end
	return if outcome.Won then "match.victory" else "match.defeat"
end

-- MatchOutcome carries no local team, but with two teams the result already says which side of the score
-- is ours: the winner holds the higher score, a draw holds two equal ones.
local function scoreSides(outcome: Types.MatchOutcome): (number, number)
	local high = 0
	local low = 0
	for index, score in ipairs(outcome.Scores) do
		if index == 1 then
			high = score
			low = score
		else
			high = math.max(high, score)
			low = math.min(low, score)
		end
	end
	if outcome.Draw or outcome.Won then
		return high, low
	end
	return low, high
end

local function resultSeconds(modeId: string): number
	local def = MatchConfig.Modes[modeId]
	if def == nil then
		return FALLBACK_RESULT_SECONDS
	end
	return math.max(1, def.ResultSeconds)
end

function ResultScreen.new(deps: Deps): Screen
	local trove = Trove.new()
	local t = deps.Localize.t
	local screen: Screen
	local autoClose: thread? = nil
	-- Bumped whenever the card is rendered or closed, so a level-up still filling cannot write to a card
	-- that has moved on.
	local generation = 0

	local root = ScreenRoot.new({ Name = "ResultScreen", DisplayOrder = Theme.Layers.Result })
	own(trove, root)
	root.Instance.Enabled = false

	local overlay = makeOverlay(root.Content)

	local panel = Panel.new({
		Title = t("match.draw"), -- replaced by the outcome on every Open
		Size = PANEL_SIZE,
		Closable = true,
		OnClose = function()
			screen:Close()
			deps.OnClose()
		end,
		Parent = overlay,
	})
	own(trove, panel)
	panel:SetHeaderHeight(HEADER_HEIGHT)
	-- The footer buttons carry the touch minimum, which follows the viewport, so the panel measures the band
	-- from the same live height on every scale change.
	panel:SetFooterHeight(function()
		return Theme.Sizes.PaddingSmall + Theme.Sizes.Padding + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
	end)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	status.FontFace = Theme.Fonts.Body
	status.TextSize = Theme.Sizes.TextSmall
	status.TextColor3 = Theme.Colors.TextMuted
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = t("match.returning")
	status.Parent = panel.Header

	local scoreLine = makeLine("Score", 1, Theme.Sizes.TextDisplay, Theme.Colors.Accent, panel.Content)
	scoreLine.FontFace = Theme.Fonts.Numeric

	-- The rule of ink under the score, centred: a full-width row holding the bar, because a fixed-width
	-- frame inside the content's list layout is aligned by the layout and sat flush left.
	local ruleRow = Instance.new("Frame")
	ruleRow.Name = "Rule"
	ruleRow.BackgroundTransparency = 1
	ruleRow.Size = UDim2.new(1, 0, 0, RULE_HEIGHT + Theme.Sizes.PaddingSmall)
	ruleRow.LayoutOrder = 2
	ruleRow.Parent = panel.Content

	local rule = Instance.new("Frame")
	rule.Name = "Bar"
	rule.AnchorPoint = Vector2.new(0.5, 0.5)
	rule.Position = UDim2.fromScale(0.5, 0.5)
	rule.BackgroundColor3 = Theme.Colors.Accent
	rule.BorderSizePixel = 0
	rule.Size = UDim2.fromOffset(RULE_WIDTH, RULE_HEIGHT)
	rule.Parent = ruleRow

	-- What the player did with their glyphs, and the letter cut from it (Pure/Execution).
	local gradeLine = makeLine("Grade", 3, Theme.Sizes.TextTitle, Theme.Colors.Text, panel.Content)
	gradeLine.FontFace = Theme.Fonts.Title
	local executionLine = makeLine("Execution", 4, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, panel.Content)

	local rewardLine = makeLine("Rewards", 5, Theme.Sizes.TextLarge, Theme.Colors.Text, panel.Content)

	-- The level, filling from where the player stood before this match: the progression is watched
	-- happening rather than read (docs/JUICE_PLAN.md phase 8, item 3).
	local levelBar = ProgressBar.new({
		Name = "Level",
		Color = Theme.Colors.Accent,
		LayoutOrder = 6,
		Parent = panel.Content,
	})
	own(trove, levelBar)
	local nextLine = makeLine("NextUnlock", 7, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, panel.Content)

	local ratingLine = makeLine("Rating", 8, Theme.Sizes.TextLarge, Theme.Colors.Info, panel.Content)
	ratingLine.FontFace = Theme.Fonts.Numeric

	-- The rank is stamped, and it is stamped inside a row of its own fixed height: a UIScale on a child of
	-- a list layout makes the layout measure the scaled size, so the lines under it were pushed down and
	-- snapped back for as long as the spring ran.
	local rankRow = Instance.new("Frame")
	rankRow.Name = "RankUp"
	rankRow.BackgroundTransparency = 1
	rankRow.Size = UDim2.new(1, 0, 0, Theme.Sizes.TextTitle + Theme.Sizes.PaddingSmall)
	rankRow.LayoutOrder = 9
	rankRow.Parent = panel.Content

	local rankLine = makeLine("Rank", 1, Theme.Sizes.TextTitle, Theme.Colors.Accent, rankRow)
	rankLine.AnchorPoint = Vector2.new(0.5, 0.5)
	rankLine.Position = UDim2.fromScale(0.5, 0.5)
	rankLine.FontFace = Theme.Fonts.Title
	local rankScale = Instance.new("UIScale")
	rankScale.Name = "Scale"
	rankScale.Parent = rankLine

	local firstWinLine = makeLine("FirstWin", 10, Theme.Sizes.TextBody, Theme.Colors.Success, panel.Content)

	trove:Add(function()
		Motion.cancel(overlay)
		Motion.cancel(rankScale)
	end)

	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Padding = UDim.new(0, Theme.Sizes.Gap)
	footerLayout.Parent = panel.Footer

	-- The loop: one click from the result back into the queue, without a hub to cross.
	local againButton = Button.new({
		Name = "Again",
		Text = t("match.again"),
		Variant = "Primary",
		Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
		LayoutOrder = 1,
		Parent = panel.Footer,
		OnClick = function()
			local outcome = deps.MatchController.getLastOutcome()
			if outcome ~= nil then
				deps.MatchController.joinQueue(outcome.ModeId)
			end
			screen:Close()
			deps.OnClose()
		end,
	})
	own(trove, againButton)

	local okButton = Button.new({
		Text = t("common.ok"),
		Variant = "Secondary",
		Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
		LayoutOrder = 2,
		Parent = panel.Footer,
		OnClick = function()
			screen:Close()
			deps.OnClose()
		end,
	})
	own(trove, okButton)

	local function cancelAutoClose()
		local timer = autoClose
		if timer ~= nil then
			task.cancel(timer)
			autoClose = nil
		end
	end
	trove:Add(cancelAutoClose)

	-- The level bar, at a level and an XP inside it. `immediate` writes it with no motion: where the
	-- animation starts from.
	local function showLevel(level: number, xp: number, immediate: boolean?)
		if level >= ProgressionConfig.MaxLevel then
			levelBar:SetProgress(1, immediate)
			levelBar:SetLabel(t("match.levelMax", { level = level }))
			return
		end
		local needed = ProgressionConfig.xpForLevel(level)
		levelBar:SetProgress(if needed > 0 then xp / needed else 0, immediate)
		levelBar:SetLabel(t("match.level", { level = level, xp = xp, needed = needed }))
	end

	-- Walks the XP this match paid back off the profile and plays it forward again. A level gained fills
	-- the old bar to the end first, so the level-up is seen rather than inferred from a number.
	local function showProgress(outcome: Types.MatchOutcome)
		local data = deps.ClientData.get()
		if data == nil then
			return
		end
		local progression = data.Progression
		local levelAfter, xpAfter = progression.Level, progression.XP
		local levelBefore, xpBefore = ProgressionConfig.rewind(levelAfter, xpAfter, outcome.Xp)
		generation += 1
		local mine = generation
		showLevel(levelBefore, xpBefore, true)
		if levelBefore >= levelAfter then
			showLevel(levelAfter, xpAfter)
		else
			levelBar:SetProgress(1)
			task.delay(LEVEL_FILL_SECONDS, function()
				if generation ~= mine or not screen.Visible then
					return
				end
				showLevel(levelAfter, 0, true)
				showLevel(levelAfter, xpAfter)
			end)
		end

		local unlock = GlyphConfig.nextUnlock(levelAfter, ProgressionConfig.OrpimentUnlockLevel)
		nextLine.Visible = unlock ~= nil
		if unlock ~= nil then
			nextLine.Text = t("match.nextUnlock", { name = t(unlock.NameKey), level = unlock.Level })
		end
	end

	local function render(outcome: Types.MatchOutcome)
		panel:SetTitle(t(titleKey(outcome)))
		local ours, theirs = scoreSides(outcome)
		scoreLine.Text = t("match.score", { ours = ours, theirs = theirs })
		gradeLine.Text = t("match.grade", { grade = t(outcome.Grade) })
		executionLine.Text = t("match.execution", {
			hits = outcome.Hits,
			casts = outcome.Casts,
			damage = outcome.DamageDealt,
		})
		rewardLine.Text = t("match.rewards", { xp = outcome.Xp, folios = outcome.Folios })
		againButton:SetDisabled(MatchConfig.Modes[outcome.ModeId] == nil)
		showProgress(outcome)

		local ranked = outcome.RankKeyAfter ~= ""
		ratingLine.Visible = ranked
		rankRow.Visible = ranked and outcome.RankKeyAfter ~= outcome.RankKeyBefore
		if ranked then
			local rank = t(outcome.RankKeyAfter)
			local delta = outcome.RatingAfter - outcome.RatingBefore
			local key = if delta >= 0 then "match.ratingUp" else "match.ratingDown"
			ratingLine.Text = t(key, { rank = rank, rating = outcome.RatingAfter, delta = delta })
			ratingLine.TextColor3 = if delta >= 0 then Theme.Colors.Success else Theme.Colors.Danger
			rankLine.Text = t("match.rankUp", { rank = rank })
		end

		firstWinLine.Visible = outcome.FirstWinOfDay
		firstWinLine.Text = t("match.firstWin")
	end

	-- The XP this match paid can land after MatchEnded -- they are two pushes -- so the card re-reads the
	-- profile while it is open instead of trusting the order the two arrive in. showProgress bumps the
	-- generation, so a level-up still filling from the stale numbers is dropped.
	trove:Connect(deps.ClientData.Changed, function(section: string)
		local outcome = deps.MatchController.getLastOutcome()
		if screen.Visible and outcome ~= nil and (section == "*" or section == "Progression") then
			showProgress(outcome)
		end
	end)

	local function open(self: Screen)
		if self.Visible then
			return
		end
		local outcome = deps.MatchController.getLastOutcome()
		if outcome == nil then
			-- Nothing to show (no match played yet). Handing control back is deferred so MenuController
			-- finishes its open first and does not leave gameplay input suspended behind a hidden screen.
			task.defer(deps.OnClose)
			return
		end
		self.Visible = true
		render(outcome)
		panel.Content.CanvasPosition = Vector2.zero
		-- The world dims as the card lands (the card's own entrance is ScreenRoot's), and a new rank is
		-- stamped on it once it has.
		Motion.set(overlay, { BackgroundTransparency = 1 })
		Motion.to(overlay, { BackgroundTransparency = OVERLAY_TRANSPARENCY }, "Ui")
		if rankRow.Visible then
			Motion.set(rankScale, { Scale = STAMP_SCALE })
			Motion.to(rankScale, { Scale = 1 }, "UiSnappy")
		end
		root.Instance.Enabled = true
		panel:FocusForGamepad(okButton.Instance)
		deps.SoundController.play("UiOpen")
		cancelAutoClose()
		autoClose = task.delay(resultSeconds(outcome.ModeId), function()
			autoClose = nil
			if not screen.Visible then
				return
			end
			screen:Close()
			deps.OnClose()
		end)
	end

	local function close(self: Screen)
		cancelAutoClose()
		if not self.Visible then
			return
		end
		self.Visible = false
		generation += 1
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

return ResultScreen
