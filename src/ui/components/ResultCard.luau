--!strict
-- ResultCard: the card of the Result takeover (D-147), the best lines first, since the old card buried them
-- below the fold. The score -- ours in our cyan, theirs in ink -- beside the seal of the hand that drew the
-- match; the grade in words; the new rank stamped in its colour, or else the rating and how it moved; what
-- the match paid, counted up from nothing while coins fly into the Folios; the level bar filling from where
-- the player stood before; the first win of the day; and, folded on a phone, the details.
--
-- The card only draws what the server decided (MatchOutcome and the profile). The level bar is replayed
-- from the XP the match paid, which can land after the outcome -- they are two pushes -- so ShowProgress is
-- called again whenever the profile's progression moves, and a replay still running is dropped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local Button = require(script.Parent.Button)
local GlyphConfig = require(Config:WaitForChild("GlyphConfig"))
local Icon = require(script.Parent.Icon)
local LeaderboardView = require(Shared:WaitForChild("Pure"):WaitForChild("LeaderboardView"))
local Motion = require(script.Parent.Parent.Motion)
local ProgressBar = require(script.Parent.ProgressBar)
local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))
local RankingConfig = require(Config:WaitForChild("RankingConfig"))
local Seal = require(script.Parent.Seal)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared:WaitForChild("Types"))
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type ResultCard = {
	-- The rows, in a scrolling list the card's owner sizes and places.
	Instance: ScrollingFrame,
	Render: (self: ResultCard, outcome: Types.MatchOutcome) -> (),
	-- The level bar, replayed from before the match to the profile's progression now.
	ShowProgress: (self: ResultCard, outcome: Types.MatchOutcome, data: Types.ProfileData?) -> (),
	-- What moves once the card has landed: the counts, the coins, the rank's stamp.
	Celebrate: (self: ResultCard, outcome: Types.MatchOutcome) -> (),
	-- The card has moved on: a replay or a flight still running is dropped.
	Stop: (self: ResultCard) -> (),
	Destroy: (self: ResultCard) -> (),
}

local ResultCard = {}

-- The seal of the hand that drew the match (Execution.Grade): its colour, and as many pips as it is steady.
-- The grade is a word, not a letter, so the seal says it with colour and count; the line under says it.
local GRADE_SEALS: { [string]: { Fill: Color3, Pips: number } } = {
	["grade.steady"] = { Fill = Theme.Colors.Primary, Pips = 4 },
	["grade.clean"] = { Fill = Theme.Colors.SuccessFill, Pips = 3 },
	["grade.unsure"] = { Fill = Theme.Colors.InfoFill, Pips = 2 },
	["grade.shaky"] = { Fill = Theme.Colors.Chalk, Pips = 1 },
}
local ROW_GAP = Theme.Sizes.Gap
local SCORE_HEIGHT = 72
local SCORE_PADDING = 18
local GRADE_SEAL = 56
local RANK_SEAL = 48
-- The rank is stamped in a row of its own fixed height: a UIScale on a child of a list layout makes the
-- layout measure the scaled size, and the lines under it were pushed down and snapped back.
local RANK_ROW = 64
local RATING_SIZE = 36
local CHIP_HEIGHT = 44
local CHIP_ICON = 26
local COIN_SIZE = 28
local COINS = 6
local COIN_STEP_SECONDS = 0.03
local CHIP_PUNCH = 1.15
local BAR_HEIGHT = 18
-- Seconds the bar spends filling the level that was completed before it starts the next one.
local LEVEL_FILL_SECONDS = 0.45

local function label(name: string, font: Font, size: number, color: Color3, order: number, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, size + Theme.Sizes.PaddingSmall)
	text.LayoutOrder = order
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Text = ""
	text.Parent = parent
	return text
end

-- A row of things side by side, centred.
local function row(name: string, height: number, order: number, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

-- A pill of `fill` in the ink outline every vivid shape on the page wears, holding a number.
local function pill(name: string, fill: Color3, height: number, textSize: number, order: number, parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = fill
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, height)
	frame.LayoutOrder = order
	Theme.corner(frame, Theme.Pill)
	Theme.stroke(frame, "Accent", Theme.Sizes.Stroke)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, SCORE_PADDING)
	padding.PaddingRight = UDim.new(0, SCORE_PADDING)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
	layout.Parent = frame
	local number = label("Value", Theme.Fonts.Numeric, textSize, Theme.inkOn(fill), 2, frame)
	number.AutomaticSize = Enum.AutomaticSize.X
	number.Size = UDim2.fromScale(0, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	frame.Parent = parent
	return frame, number, scale
end

function ResultCard.new(localize: Localizer, parent: Instance): ResultCard
	local trove = Trove.new()
	local t = localize.t
	-- Bumped whenever the card is rendered again or stopped, so a replay or a flight cannot write to a
	-- card that has moved on.
	local generation = 0

	local content = Instance.new("ScrollingFrame")
	content.Name = "Rows"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ScrollBarThickness = Theme.Sizes.PaddingSmall
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Selectable = false
	trove:Add(content)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingTop = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = content

	-- 1. The score, and the seal of the hand.
	local scoreRow = row("Score", SCORE_HEIGHT, 1, content)
	local _, ours = pill("Ours", Theme.Colors.Ally, SCORE_HEIGHT, Theme.Sizes.NumScore, 1, scoreRow)
	local dash = label("Dash", Theme.Fonts.Numeric, Theme.Sizes.NumScore, Theme.Colors.Text, 2, scoreRow)
	dash.AutomaticSize = Enum.AutomaticSize.X
	dash.Size = UDim2.fromScale(0, 1)
	dash.Text = Theme.Glyphs.Minus
	local _, theirs = pill("Theirs", Theme.Colors.Plate, SCORE_HEIGHT, Theme.Sizes.NumScore, 3, scoreRow)
	local gradeSeal = Seal.new({
		Text = "",
		Fill = Theme.Colors.Chalk,
		Size = GRADE_SEAL,
		LayoutOrder = 4,
		Name = "Grade",
		Parent = scoreRow,
	})
	trove:Add(function()
		gradeSeal:Destroy()
	end)
	local gradeLine = label("Grade", Theme.Fonts.Body, Theme.Sizes.TextBody, Theme.Colors.TextMuted, 2, content)

	-- 2. The new rank, stamped; or the rating and how it moved.
	local rankRow = row("RankUp", RANK_ROW, 3, content)
	local rankSeal =
		Seal.new({ Text = "", Fill = Theme.Colors.Chalk, Size = RANK_SEAL, LayoutOrder = 1, Parent = rankRow })
	trove:Add(function()
		rankSeal:Destroy()
	end)
	local rankLine = label("Rank", Theme.Fonts.Title, Theme.Sizes.TextTitle, Theme.Colors.Text, 2, rankRow)
	rankLine.AutomaticSize = Enum.AutomaticSize.X
	rankLine.Size = UDim2.fromScale(0, 1)
	local ratingLine = label("Rating", Theme.Fonts.Numeric, RATING_SIZE, Theme.Colors.Success, 4, content)

	-- 3. What the match paid.
	local rewards = row("Rewards", CHIP_HEIGHT, 5, content)
	local _, xpText, xpScale = pill("Xp", Theme.Colors.Primary, CHIP_HEIGHT, Theme.Sizes.Num, 1, rewards)
	local folios, foliosText, foliosScale =
		pill("Folios", Theme.Colors.PanelRaised, CHIP_HEIGHT, Theme.Sizes.Num, 2, rewards)
	local coin = Icon.new("Coin", CHIP_ICON)
	coin.LayoutOrder = 1
	coin.Parent = folios
	trove:Add(function()
		Motion.cancel(xpScale)
		Motion.cancel(foliosScale)
	end)

	-- 4. The level, filling from where the player stood before this match.
	local levelBar = ProgressBar.new({
		Name = "Level",
		Color = Theme.Colors.Primary,
		Height = BAR_HEIGHT,
		LayoutOrder = 6,
		Parent = content,
	})
	trove:Add(function()
		levelBar:Destroy()
	end)
	local levelLine = label("Level", Theme.Fonts.Bold, Theme.Sizes.TextBody, Theme.Colors.Text, 7, content)
	local nextLine = label("NextUnlock", Theme.Fonts.Body, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, 8, content)

	-- 5. The first win of the day, on a green ribbon.
	local firstWinRow = row("FirstWin", CHIP_HEIGHT, 9, content)
	local _, firstWin = pill("Ribbon", Theme.Colors.SuccessFill, CHIP_HEIGHT, Theme.Sizes.TextBody, 1, firstWinRow)
	firstWin.FontFace = Theme.Fonts.Bold
	firstWin.Text = t("match.firstWin")

	-- 6. The details, folded on a phone where the card has no room to spare, and the toggle that unfolds them
	-- there. With a pointer they are open, and nothing folds them: a toggle there could only hide a line, and its
	-- row was what the card lacked to hold its rows without scrolling (seen in Studio at 886 high).
	local details = Instance.new("Frame")
	details.Name = "Details"
	details.BackgroundTransparency = 1
	details.AutomaticSize = Enum.AutomaticSize.Y
	details.Size = UDim2.fromScale(1, 0)
	details.LayoutOrder = 11
	local detailsLayout = Instance.new("UIListLayout")
	detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	detailsLayout.Parent = details
	details.Parent = content
	local executionLine =
		label("Execution", Theme.Fonts.Body, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, 1, details)
	local bestChainLine =
		label("BestChain", Theme.Fonts.Body, Theme.Sizes.TextSmall, Theme.Colors.TextMuted, 2, details)
	details.Visible = not Theme.touchOnly()
	local detailsToggle = Button.new({
		Name = "DetailsToggle",
		Text = t("result.details"),
		Variant = "Ghost",
		LayoutOrder = 10,
		Parent = content,
		OnClick = function()
			details.Visible = not details.Visible
		end,
	})
	detailsToggle.Instance.Visible = not details.Visible
	trove:Add(function()
		detailsToggle:Destroy()
	end)

	local function showLevel(level: number, xp: number, immediate: boolean?)
		if level >= ProgressionConfig.MaxLevel then
			levelBar:SetProgress(1, immediate)
			levelLine.Text = t("match.levelMax", { level = level })
			return
		end
		local needed = ProgressionConfig.xpForLevel(level)
		levelBar:SetProgress(if needed > 0 then xp / needed else 0, immediate)
		levelLine.Text = t("match.level", { level = level, xp = xp, needed = needed })
	end

	-- Walks the XP this match paid back off the profile and plays it forward again. A level gained fills
	-- the old bar to the end first, so the level-up is seen rather than inferred from a number.
	local function showProgress(_self: ResultCard, outcome: Types.MatchOutcome, data: Types.ProfileData?)
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
				if generation ~= mine then
					return
				end
				showLevel(levelAfter, 0, true)
				showLevel(levelAfter, xpAfter)
			end)
		end

		local best = data.Stats.BestChain
		bestChainLine.Visible = best >= 2
		bestChainLine.Text = t("match.bestChain", { count = best })

		local unlock = GlyphConfig.nextUnlock(levelAfter, ProgressionConfig.OrpimentUnlockLevel)
		nextLine.Visible = unlock ~= nil
		if unlock ~= nil then
			nextLine.Text = t("match.nextUnlock", { name = t(unlock.NameKey), level = unlock.Level })
		end
	end

	local function render(_self: ResultCard, outcome: Types.MatchOutcome)
		generation += 1
		content.CanvasPosition = Vector2.zero
		local high, low = 0, 0
		for index, score in ipairs(outcome.Scores) do
			high = if index == 1 then score else math.max(high, score)
			low = if index == 1 then score else math.min(low, score)
		end
		-- MatchOutcome carries no local team, but with two teams the result says which side is ours: the
		-- winner holds the higher score, a draw holds two equal ones.
		local mine = if outcome.Draw or outcome.Won then high else low
		ours.Text = tostring(mine)
		theirs.Text = tostring(if outcome.Draw or outcome.Won then low else high)
		local grade = GRADE_SEALS[outcome.Grade] or GRADE_SEALS["grade.shaky"]
		gradeSeal:SetFill(grade.Fill)
		gradeSeal:SetText(string.rep(Theme.Glyphs.Pip, grade.Pips))
		gradeLine.Text = t("match.grade", { grade = t(outcome.Grade) })
		executionLine.Text = t("match.execution", {
			hits = outcome.Hits,
			casts = outcome.Casts,
			damage = outcome.DamageDealt,
		})
		xpText.Text = t("reward.xp", { xp = 0 })
		foliosText.Text = t("reward.folios", { amount = 0 })

		local ranked = outcome.RankKeyAfter ~= ""
		local rankedUp = ranked and outcome.RankKeyAfter ~= outcome.RankKeyBefore
		rankRow.Visible = rankedUp
		ratingLine.Visible = ranked and not rankedUp
		if ranked then
			local rankName = t(outcome.RankKeyAfter)
			local delta = outcome.RatingAfter - outcome.RatingBefore
			local key = if delta >= 0 then "match.ratingUp" else "match.ratingDown"
			ratingLine.Text = t(key, { rank = rankName, rating = outcome.RatingAfter, delta = delta })
			-- Up in the green of what went well; down in Cinnabar, at the large size it may be read at.
			ratingLine.TextColor3 = if delta >= 0 then Theme.Colors.Success else Theme.Colors.Danger
			local rank = Theme.rank(
				LeaderboardView.tierId(outcome.RankKeyAfter, RankingConfig.Tiers) or RankingConfig.Tiers[1].Id
			)
			rankSeal:SetFill(rank.Fill, rank.Rim)
			rankLine.Text = t("match.rankUp", { rank = rankName })
		end
		firstWinRow.Visible = outcome.FirstWinOfDay
	end

	-- Coins fly from the top of the card into the Folios chip, which punches as the last one lands.
	local function flyCoins(mine: number)
		local holder = content.Parent
		if holder == nil or not holder:IsA("GuiObject") then
			return
		end
		local size = holder.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local centre = folios.AbsolutePosition + folios.AbsoluteSize / 2 - holder.AbsolutePosition
		local target = UDim2.fromScale(centre.X / size.X, centre.Y / size.Y)
		for index = 1, COINS do
			task.delay((index - 1) * COIN_STEP_SECONDS, function()
				if generation ~= mine then
					return
				end
				local flying = Icon.new("Coin", COIN_SIZE)
				flying.Name = "Flying"
				flying.AnchorPoint = Vector2.new(0.5, 0.5)
				flying.Position = UDim2.fromScale(0.5, 0)
				flying.ZIndex = 10
				flying.Parent = holder
				Motion.to(flying, { Position = target }, "UiSnappy", function()
					flying:Destroy()
					if index == COINS and generation == mine then
						Motion.punch(foliosScale, CHIP_PUNCH)
					end
				end)
			end)
		end
	end

	local function celebrate(_self: ResultCard, outcome: Types.MatchOutcome)
		local mine = generation
		Motion.countTo(xpText, 0, outcome.Xp, function(value: number): string
			return t("reward.xp", { xp = value })
		end)
		Motion.countTo(foliosText, 0, outcome.Folios, function(value: number): string
			return t("reward.folios", { amount = value })
		end)
		if outcome.Folios > 0 and not UiPrefs.reducedMotion() then
			flyCoins(mine)
		else
			Motion.punch(foliosScale, CHIP_PUNCH)
		end
		-- A new rank is stamped: it lands from larger than itself (D-85).
		if rankRow.Visible then
			rankSeal:Stamp()
		end
	end

	local function stop(_self: ResultCard)
		generation += 1
	end

	content.Parent = parent

	local function destroy(_self: ResultCard)
		generation += 1
		trove:Destroy()
	end

	return {
		Instance = content,
		Render = render,
		ShowProgress = showProgress,
		Celebrate = celebrate,
		Stop = stop,
		Destroy = destroy,
	}
end

return ResultCard
