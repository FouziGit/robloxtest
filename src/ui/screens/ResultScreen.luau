--!strict
-- ResultScreen: the end-of-match summary. MenuController opens it on MatchEnded; the outcome itself is
-- read from MatchController, which kept the last payload the server sent. Shows the result, the score,
-- the rewards, the rating line, the new rank when the tier changed and the first win of the day, then
-- closes itself after the mode's ResultSeconds or as soon as the player presses the button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Button = require(script.Parent.Parent.components.Button)
local MatchConfig = require(Shared.Config.MatchConfig)
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
	-- Last MatchEnded payload: the server decided every number rendered here.
	MatchController: { getLastOutcome: () -> Types.MatchOutcome? },
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
local STATUS_HEIGHT = Theme.Sizes.TextSmall + Theme.Sizes.PaddingSmall
local HEADER_HEIGHT = Theme.Sizes.PaddingSmall * 2 + STATUS_HEIGHT
local FALLBACK_RESULT_SECONDS = MatchConfig.Modes[MatchConfig.ModeOrder[1]].ResultSeconds

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
	label.Font = Theme.Fonts.Bold
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
	-- The footer buttons carry the touch minimum, so the band reserves the height they really take.
	panel:SetFooterHeight(
		Theme.Sizes.PaddingSmall + Theme.Sizes.Padding + Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
	)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, STATUS_HEIGHT)
	status.Font = Theme.Fonts.Body
	status.TextSize = Theme.Sizes.TextSmall
	status.TextColor3 = Theme.Colors.TextMuted
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.Text = t("match.returning")
	status.Parent = panel.Header

	local scoreLine = makeLine("Score", 1, Theme.Sizes.TextHero, Theme.Colors.Accent, panel.Content)
	local rewardLine = makeLine("Rewards", 2, Theme.Sizes.TextLarge, Theme.Colors.Text, panel.Content)
	local ratingLine = makeLine("Rating", 3, Theme.Sizes.TextLarge, Theme.Colors.Info, panel.Content)
	local rankLine = makeLine("RankUp", 4, Theme.Sizes.TextLarge, Theme.Colors.Accent, panel.Content)
	local firstWinLine = makeLine("FirstWin", 5, Theme.Sizes.TextBody, Theme.Colors.Success, panel.Content)

	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Parent = panel.Footer

	local okButton = Button.new({
		Text = t("common.ok"),
		Variant = "Primary",
		Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.ButtonHeight),
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

	local function render(outcome: Types.MatchOutcome)
		panel:SetTitle(t(titleKey(outcome)))
		local ours, theirs = scoreSides(outcome)
		scoreLine.Text = t("match.score", { ours = ours, theirs = theirs })
		rewardLine.Text = t("match.rewards", { xp = outcome.Xp, ryo = outcome.Ryo })

		local ranked = outcome.RankKeyAfter ~= ""
		ratingLine.Visible = ranked
		rankLine.Visible = ranked and outcome.RankKeyAfter ~= outcome.RankKeyBefore
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
