--!strict
-- QuestCard: one quest on the quests board (D-147). A card of the list (ListRow) with a tab down its edge in
-- the colour of the quest's state -- the primary yellow while it waits to be claimed, chalk while it is
-- played, green once claimed -- its name over a bar of its progress with the count beside it, what it pays,
-- and only when there is something to do, its Claim button, in the Quests chapter's own blue.
--
-- A claim sent from the card waits, pending, for the profile push that marks the quest claimed; then the
-- seal is stamped and a burst of ink goes off behind it. The server decides; the card only shows what it
-- decided. Now and then the board asks every claimable card to wiggle, so a claim is found (Wiggle).
--
-- A card given OnSwap also carries a Swap button, the sheet's small pill, shown only while the quest is being
-- played and the board says a free reroll is left (SetSwappable). A swap that lands replaces the card; the
-- server decides that too (QuestLogic.reroll).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Button = require(script.Parent.Button)
local Icon = require(script.Parent.Icon)
local ListRow = require(script.Parent.ListRow)
local Motion = require(script.Parent.Parent.Motion)
local ProgressBar = require(script.Parent.ProgressBar)
local QuestBoard = require(Shared:WaitForChild("Pure"):WaitForChild("QuestBoard"))
local Seal = require(script.Parent.Seal)
local Splat = require(script.Parent.Splat)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Props = {
	-- The quest's name, what it pays, and the two words of its action, all worded by the caller.
	Title: string,
	Reward: string,
	ClaimText: string,
	ClaimedText: string,
	OnClaim: () -> (),
	-- The claim was never answered in time (Button's OnTimeout): the caller says so, as every claim does.
	OnTimeout: () -> (),
	-- The word of the Swap button and what it does; a card without OnSwap has no Swap button.
	SwapText: string?,
	OnSwap: (() -> ())?,
	Name: string?,
	Parent: Instance?,
}

export type QuestCard = {
	Instance: Frame,
	Button: Button.Button,
	-- The quest's state, the share of its target reached and the count that says it. `animate` springs the
	-- bar and celebrates a claim that has just landed; without it everything is written as it is.
	Set: (self: QuestCard, state: QuestBoard.State, fraction: number, count: string, animate: boolean) -> (),
	GetState: (self: QuestCard) -> QuestBoard.State?,
	IsPending: (self: QuestCard) -> boolean,
	-- One tilt of the Claim button, when it is there to be pressed.
	Wiggle: (self: QuestCard) -> (),
	-- Whether a free reroll is left for this quest's set: the Swap button shows while it is and the quest is
	-- being played.
	SetSwappable: (self: QuestCard, swappable: boolean) -> (),
	-- The Swap button, nil on a card given no OnSwap.
	SwapButton: Button.Button?,
	Destroy: (self: QuestCard) -> (),
}

local QuestCard = {}

-- The card: the name over the bar, with room beside the bar for the count it carries outside.
local HEIGHT = 84
local NAME_HEIGHT = Theme.Sizes.TextButton + Theme.Sizes.PaddingSmall
local BAR_HEIGHT = 14
local BAR_LABEL_ROOM = 120
local CHIP_HEIGHT = 36
local CHIP_ICON = 22
local CHIP_TEXT = 16
local SEAL_SIZE = 30
-- How far the Claim button tilts each way when it wiggles.
local WIGGLE_DEGREES = 2
-- The ink that goes off when the claim lands: its colours, how wide a blot starts and ends, where each one
-- lands around the seal, and how long before the blots go back to the screen's pool.
local BURST_TINTS = { Theme.Colors.Primary, Theme.Colors.SuccessFill, Theme.Colors.Primary }
local BURST_FROM = 24
local BURST_TO = 64
local BURST_OFFSETS = { Vector2.new(-26, -10), Vector2.new(24, -14), Vector2.new(2, 18) }
local BURST_TRANSPARENCY = 0.2
local BURST_SECONDS = 0.7

local TINTS: { [QuestBoard.State]: Color3 } = {
	Claimable = Theme.Colors.Primary,
	InProgress = Theme.Colors.Chalk,
	Claimed = Theme.Colors.SuccessFill,
}

local function textLabel(name: string, font: Font, size: number, color: Color3, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.LayoutOrder = order
	return label
end

local function row(parent: Instance, direction: Enum.FillDirection, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
end

-- A frame as wide as what it holds, laid out in a row.
local function strip(name: string, order: number, gap: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromScale(0, 1)
	frame.LayoutOrder = order
	row(frame, Enum.FillDirection.Horizontal, gap)
	return frame
end

-- Ink going off around `anchor`: the blots grow out of it and fade, then go back to the screen's pool.
-- Under reduced motion they only fade.
local function burst(anchor: GuiObject)
	for index, tint in ipairs(BURST_TINTS) do
		local offset = BURST_OFFSETS[index]
		local splat = Splat.new({
			Size = UDim2.fromOffset(BURST_FROM, BURST_FROM),
			Tint = tint,
			Rotation = Splat.rotation(index),
			Transparency = BURST_TRANSPARENCY,
			Position = UDim2.new(0.5, offset.X, 0.5, offset.Y),
			ZIndex = 1,
			Name = "Burst",
			Parent = anchor,
		})
		if splat ~= nil then
			if not UiPrefs.reducedMotion() then
				Motion.to(splat, { Size = UDim2.fromOffset(BURST_TO, BURST_TO) }, "UiPop")
			end
			Splat.fade(splat, 1, "Ui")
			task.delay(BURST_SECONDS, Splat.release, splat)
		end
	end
end

function QuestCard.new(props: Props): QuestCard
	local trove = Trove.new()
	local state: QuestBoard.State? = nil
	local pending = false

	-- Left: the name over the bar.
	local body = Instance.new("Frame")
	body.Name = "Quest"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	row(body, Enum.FillDirection.Vertical, Theme.Sizes.PaddingSmall)
	local title = textLabel("Title", Theme.Fonts.Bold, Theme.Sizes.TextButton, Theme.Colors.Text, 1)
	title.AutomaticSize = Enum.AutomaticSize.None
	title.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = props.Title
	title.Parent = body
	local bar = ProgressBar.new({
		Name = "Progress",
		Color = Theme.Colors.Primary,
		Size = UDim2.new(1, -BAR_LABEL_ROOM, 0, BAR_HEIGHT),
		LabelOutside = true,
		LayoutOrder = 2,
		Parent = body,
	})
	trove:Add(function()
		bar:Destroy()
	end)

	-- Right: what it pays, then the Claim button or the claimed seal.
	local actions = strip("Actions", 2, Theme.Sizes.Gap)

	local chip = strip("Reward", 1, Theme.Sizes.PaddingSmall)
	chip.BackgroundTransparency = 0
	chip.BackgroundColor3 = Theme.Colors.Panel
	chip.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	Theme.corner(chip, Theme.Pill)
	Theme.stroke(chip, "Accent", Theme.Sizes.StrokeThin)
	local chipPadding = Instance.new("UIPadding")
	chipPadding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingSmall)
	chipPadding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	chipPadding.Parent = chip
	Icon.new("Coin", CHIP_ICON).Parent = chip
	local reward = textLabel("Text", Theme.Fonts.Bold, CHIP_TEXT, Theme.Colors.Text, 2)
	reward.Text = props.Reward
	reward.Parent = chip
	chip.Parent = actions

	-- The claim is the Quests chapter's own button, in its blue with its lip and gloss (the board's « Réclamer »).
	local button: Button.Button
	button = Button.new({
		Name = "Claim",
		Text = props.ClaimText,
		Variant = "Owner",
		Chapter = "Quests",
		LayoutOrder = 2,
		Parent = actions,
		OnClick = function()
			pending = true
			button:SetPending(true)
			props.OnClaim()
		end,
		-- The server never answered: the button is back, and so is the wiggle; the board says so.
		OnTimeout = function()
			pending = false
			props.OnTimeout()
		end,
	})
	trove:Add(function()
		Motion.cancel(button.Instance)
		button:Destroy()
	end)
	button.Instance.Visible = false

	-- The swap: the sheet's small pill after what the quest pays, pending until the push that replaces the card.
	local swapButton: Button.Button? = nil
	local swappable = false
	local onSwap = props.OnSwap
	if onSwap ~= nil then
		local swap: Button.Button
		swap = Button.new({
			Name = "Swap",
			Text = props.SwapText or "",
			Variant = "Secondary",
			Compact = true,
			LayoutOrder = 4,
			Parent = actions,
			OnClick = function()
				swap:SetPending(true)
				onSwap()
			end,
			-- Unanswered, it is said as an unanswered claim is.
			OnTimeout = props.OnTimeout,
		})
		swap.Instance.Visible = false
		trove:Add(function()
			swap:Destroy()
		end)
		swapButton = swap
	end

	local claimed = strip("Claimed", 3, Theme.Sizes.PaddingSmall)
	claimed.Visible = false
	-- The seal sits over a holder of its own, outside the row's layout, where the burst can spread behind it.
	local holder = Instance.new("Frame")
	holder.Name = "SealHolder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(SEAL_SIZE, SEAL_SIZE)
	holder.LayoutOrder = 1
	holder.Parent = claimed
	local seal = Seal.new({
		Text = Theme.Glyphs.Check,
		Fill = Theme.Colors.SuccessFill,
		Size = SEAL_SIZE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = holder,
	})
	seal.Instance.ZIndex = 2
	trove:Add(function()
		seal:Destroy()
	end)
	local claimedText = textLabel("Text", Theme.Fonts.Bold, Theme.Sizes.TextBody, Theme.Colors.Success, 2)
	claimedText.Text = props.ClaimedText
	claimedText.Parent = claimed
	claimed.Parent = actions

	local card = ListRow.new({
		Left = body,
		Right = actions,
		Height = HEIGHT,
		Name = props.Name,
		Parent = props.Parent,
	})
	trove:Add(function()
		card:Destroy()
	end)

	-- The Swap button shows only on a quest being played, and only while a reroll is left.
	local function showSwap()
		local swap = swapButton
		if swap == nil then
			return
		end
		local shown = swappable and state == "InProgress"
		swap.Instance.Visible = shown
		if not shown then
			swap:SetPending(false)
		end
	end

	local function set(_self: QuestCard, next: QuestBoard.State, fraction: number, count: string, animate: boolean)
		local previous = state
		state = next
		card:SetTint(TINTS[next])
		bar:SetProgress(fraction, not animate or previous == nil)
		bar:SetLabel(count)
		button.Instance.Visible = next == "Claimable"
		claimed.Visible = next == "Claimed"
		if next ~= "Claimable" and pending then
			pending = false
			button:SetPending(false)
		end
		-- The claim has landed: the seal is stamped, and the ink goes off behind it.
		if animate and previous == "Claimable" and next == "Claimed" then
			seal:Stamp()
			burst(holder)
		end
		showSwap()
	end

	local function setSwappable(_self: QuestCard, value: boolean)
		swappable = value
		showSwap()
	end

	local function getState(_self: QuestCard): QuestBoard.State?
		return state
	end

	local function isPending(_self: QuestCard): boolean
		return pending
	end

	local function wiggle(_self: QuestCard)
		if state ~= "Claimable" or pending or UiPrefs.reducedMotion() then
			return
		end
		local target = button.Instance
		Motion.to(target, { Rotation = WIGGLE_DEGREES }, "UiSnappy", function()
			Motion.to(target, { Rotation = -WIGGLE_DEGREES }, "UiSnappy", function()
				Motion.to(target, { Rotation = 0 }, "UiPop")
			end)
		end)
	end

	local function destroy(_self: QuestCard)
		trove:Destroy()
	end

	local object: QuestCard = {
		Instance = card.Instance,
		Button = button,
		Set = set,
		GetState = getState,
		IsPending = isPending,
		Wiggle = wiggle,
		SetSwappable = setSwappable,
		SwapButton = swapButton,
		Destroy = destroy,
	}
	return object
end

return QuestCard
