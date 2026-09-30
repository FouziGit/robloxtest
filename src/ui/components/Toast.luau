--!strict
-- Toast: the lane of short messages (D-147). Each one is a sticker card of the sheet on its hard ink shadow,
-- led by a medallion that says what kind of message it is before its words do: an i for information, a tick
-- for a success, a ! for a real failure (a refused purchase, a failed claim), the Folio coin for a reward. A
-- celebration -- a level, a pass tier, a finished quest, the first win of the day -- is the primary yellow
-- itself, its medallion on a splat, under a seal that turns once.
--
-- The lane depends on the device and never enters the middle of the screen. With a pointer it runs down the
-- right edge from a third of the height: the engine's player list is a CoreGui drawn over every ScreenGui in
-- the top-right corner, and a message under it could not be read. On a touch device, where that list is
-- hidden, it hangs from the top-right corner under the Menu disc (SetTop). A message slides in from the edge
-- as it fades in, and leaves the way it came: nothing appears, nothing vanishes (docs/ART_BIBLE.md rule 3).
--
-- Which message shows and for how long is ToastQueue's: a few at once, the oldest Info dropped first from a
-- full queue, and the value kinds held back while the player fights (rule 11: Hold).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Icon = require(script.Parent.Icon)
local Motion = require(script.Parent.Parent.Motion)
local Splat = require(script.Parent.Splat)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local ToastQueue = require(Shared:WaitForChild("Pure"):WaitForChild("ToastQueue"))
local Trove = require(Packages.Trove)

export type Kind = "Info" | "Success" | "Error" | "Reward" | "Celebrate"
export type Lane = "Pointer" | "Touch"

type TroveObject = typeof(Trove.new())

export type Props = {
	Parent: GuiObject,
	Name: string?,
	-- Where the lane runs: down the right edge (a mouse or a gamepad), or from the top-right corner (touch).
	Lane: Lane?,
}

export type Toast = {
	Instance: Frame,
	-- `amount`, when given, is drawn in a chip beside the words: the Folios a reward paid, written as the words
	-- are, in the player's language ("+4 000", reward.folios).
	Show: (self: Toast, text: string, kind: Kind, amount: string?) -> (),
	-- The kinds set in `kinds` wait in the queue from now on; Hold({}) lets them all through, in order.
	Hold: (self: Toast, kinds: { [string]: boolean }) -> (),
	SetMaxVisible: (self: Toast, count: number) -> (),
	-- Nothing new shows while paused (a boss's warning is up); what waits shows in order afterwards.
	Pause: (self: Toast, paused: boolean) -> (),
	-- Touch lane: how far below the top of its safe area the first message hangs, in design units.
	SetTop: (self: Toast, top: number) -> (),
	-- Moves the lane, its messages and its queue with it: a touch laptop touched, or typed on again.
	SetLane: (self: Toast, lane: Lane) -> (),
	-- In a fight (a match or an arena), a message that shows from now on wears no value colour (rule 11).
	SetFight: (self: Toast, fighting: boolean) -> (),
	Destroy: (self: Toast) -> (),
}

local Toast = {}

local MAX_PENDING = 8 -- older waiting messages are dropped beyond this (ToastQueue.push)
-- The lane: never wider than this, and never more than this share of the screen's width.
local LANE_MAX_WIDTH = 380
local POINTER_SHARE = 0.26
local TOUCH_SHARE = 0.3
local EDGE = 16
-- A pointer lane starts under the engine's player list.
local POINTER_TOP = 0.34
-- How far off the edge a message starts and ends.
local SLIDE = 40
local ELEVATION = 4
local PADDING_Y = 12
local PADDING_X = 16
local MEDALLION = 36
local TEXT_SIZE = 18
local CHIP_WIDTH = 72
local CHIP_HEIGHT = 32
local CHIP_TEXT = 18
-- The celebration: one line of the title face on the primary yellow, its medallion on a splat and a seal.
local CELEBRATE_WIDTH = 420
local CELEBRATE_HEIGHT = 72
local CELEBRATE_TEXT = 26
local CELEBRATE_SPLAT = 64
local SEAL_SCALE = 1.4
local MIN_SCALED_TEXT = 14

-- The medallion of each kind: its fill and its sign. A reward's is the Folio coin itself.
local FILLS: { [string]: Color3 } = {
	Info = Theme.Colors.InfoFill,
	Success = Theme.Colors.SuccessFill,
	Error = Theme.Colors.DangerFill,
	Celebrate = Theme.Colors.PanelRaised,
}
local SIGNS: { [string]: string } = {
	Info = "i",
	Success = Theme.Glyphs.Check,
	Error = "!",
	Celebrate = Theme.Glyphs.Check,
}
-- In a fight a success is a tick of ink on the sheet: the green is a value colour, which no fight shows
-- (docs/ART_BIBLE.md rule 11), and next to the cyan of a takedown pop it read as a second "us". The spec's
-- toast section asks for the green everywhere; its colour rules win (D-163).
local FIGHT_FILLS: { [string]: Color3 } = {
	Success = Theme.Colors.PanelRaised,
}

local function textLabel(name: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	return label
end

local function medallion(kind: string, fighting: boolean): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Medallion"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(MEDALLION, MEDALLION)
	holder.LayoutOrder = 1
	if kind == "Reward" then
		Icon.new("Coin", MEDALLION).Parent = holder
		return holder
	end
	local fill = (if fighting then FIGHT_FILLS[kind] else nil) or FILLS[kind] or FILLS.Info
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = fill
	disc.Size = UDim2.fromScale(1, 1)
	disc.ZIndex = 3
	Theme.corner(disc, Theme.Pill)
	-- A vivid disc on the sheet is detached by its outline, not by its colour (rule 11).
	Theme.stroke(disc, "Accent", Theme.Sizes.StrokeThin)
	local sign = textLabel(
		"Sign",
		if kind == "Success" or kind == "Celebrate" then Theme.Fonts.Bold else Theme.Fonts.Title,
		TEXT_SIZE,
		Theme.inkOn(fill)
	)
	sign.Size = UDim2.fromScale(1, 1)
	sign.Text = SIGNS[kind] or SIGNS.Info
	sign.ZIndex = 3
	sign.Parent = disc
	disc.Parent = holder
	return holder
end

-- The Folios a reward paid, beside its words, as the caller wrote them.
local function amountChip(amount: string): Frame
	local chip = Instance.new("Frame")
	chip.Name = "Amount"
	chip.BorderSizePixel = 0
	chip.BackgroundColor3 = Theme.Colors.Primary
	chip.Size = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT)
	chip.LayoutOrder = 3
	Theme.corner(chip, Theme.Pill)
	Theme.stroke(chip, "Accent", Theme.Sizes.StrokeThin)
	local label = textLabel("Value", Theme.Fonts.Numeric, CHIP_TEXT, Theme.Colors.Text)
	label.Size = UDim2.fromScale(1, 1)
	label.Text = amount
	label.Parent = chip
	return chip
end

-- The celebration's medallion stands on a splat of green and inside a seal that turns once as it arrives.
local function celebrateBacking(holder: Frame, trove: TroveObject)
	Splat.new({
		Size = UDim2.fromOffset(CELEBRATE_SPLAT, CELEBRATE_SPLAT),
		Tint = Theme.Colors.SuccessFill,
		Rotation = Splat.rotation(1),
		ZIndex = 1,
		Name = "Splat",
		Parent = holder,
	})
	local id = Theme.texture("SealRing")
	if id == "" then
		return
	end
	local ring = Instance.new("ImageLabel")
	ring.Name = "Seal"
	ring.BackgroundTransparency = 1
	ring.Image = id
	ring.ImageColor3 = Theme.Colors.Accent
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(SEAL_SCALE, SEAL_SCALE)
	ring.ZIndex = 2
	ring.Parent = holder
	trove:Add(function()
		Motion.cancel(ring)
	end)
	Motion.to(ring, { Rotation = 360 }, "Ui")
end

-- The card of one message, and the group it fades in: the slot takes its place in the lane at `order`, the
-- group slides inside it. Built in the lane, so a celebration's splat counts against the lane's own budget.
local function buildItem(
	entry: ToastQueue.Entry,
	order: number,
	lane: Frame,
	trove: TroveObject,
	fighting: boolean
): CanvasGroup
	local kind = entry.Kind
	local celebrate = kind == "Celebrate"

	local slot = Instance.new("Frame")
	slot.Name = kind
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.LayoutOrder = order
	trove:Add(slot)

	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Position = UDim2.fromOffset(SLIDE, 0)
	group.Parent = slot

	-- The group hosts its card (Sticker's Host, D-170): a message's group is as tall as its words, and a
	-- card filling it from a frame of its own was measured against the screen and ran down the whole lane.
	local card = Sticker.new({
		Kind = "Card",
		Fill = if celebrate then Theme.Colors.Primary else Theme.Colors.PanelRaised,
		Corner = UDim.new(0, Theme.Sizes.CornerCard),
		Elevation = ELEVATION,
		Host = group,
	})
	trove:Add(function()
		card:Destroy()
	end)

	-- The content rides above the card; its padding keeps it off the card's hard shadow.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.ZIndex = 2
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PADDING_Y)
	padding.PaddingBottom = UDim.new(0, PADDING_Y + ELEVATION)
	padding.PaddingLeft = UDim.new(0, PADDING_X)
	padding.PaddingRight = UDim.new(0, PADDING_X)
	padding.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, PADDING_Y)
	layout.Parent = body

	local icon = medallion(kind, fighting)
	icon.Parent = body

	local reserved = MEDALLION + PADDING_Y
	local amount = entry.Amount
	if amount ~= nil and not celebrate then
		amountChip(amount).Parent = body
		reserved += CHIP_WIDTH + PADDING_Y
	end

	local words: TextLabel
	if celebrate then
		-- A fixed card: its one line is scaled to fit rather than wrapped out of it.
		slot.Size = UDim2.fromOffset(CELEBRATE_WIDTH, CELEBRATE_HEIGHT)
		group.Size = UDim2.fromScale(1, 1)
		body.Size = UDim2.fromScale(1, 1)
		words = textLabel("Text", Theme.Fonts.Title, CELEBRATE_TEXT, Theme.Colors.Text)
		words.Size = UDim2.new(1, -reserved, 1, 0)
		words.TextScaled = true
		local cap = Instance.new("UITextSizeConstraint")
		cap.MinTextSize = MIN_SCALED_TEXT
		cap.MaxTextSize = CELEBRATE_TEXT
		cap.Parent = words
	else
		-- As tall as its words: the slot and the group follow the body, and the card fills them.
		slot.Size = UDim2.fromScale(1, 0)
		slot.AutomaticSize = Enum.AutomaticSize.Y
		group.Size = UDim2.fromScale(1, 0)
		group.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.fromScale(1, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		words = textLabel("Text", Theme.Fonts.Bold, TEXT_SIZE, Theme.Colors.Text)
		words.Size = UDim2.new(1, -reserved, 0, 0)
		words.AutomaticSize = Enum.AutomaticSize.Y
		words.TextWrapped = true
	end
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.LayoutOrder = 2
	words.Text = entry.Text
	words.Parent = body
	body.Parent = group
	slot.Parent = lane
	if celebrate then
		celebrateBacking(icon, trove)
	end
	return group
end

function Toast.new(props: Props): Toast
	local trove = Trove.new()
	local queue = ToastQueue.new(Theme.Timing.Toast.MaxVisibleHub, MAX_PENDING)
	local sequence = 0
	local destroyed = false
	local fighting = false
	local touch = false

	local container = Instance.new("Frame")
	container.Name = props.Name or "Toasts"
	container.AnchorPoint = Vector2.new(1, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	trove:Add(container)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(LANE_MAX_WIDTH, math.huge)
	sizeConstraint.Parent = container

	-- Messages stack downward, and hug the edge: a celebration is wider than the lane and grows inward.
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = container

	local pump: () -> ()

	local function present(entry: ToastQueue.Entry)
		sequence += 1
		local itemTrove = trove:Extend()
		local group = buildItem(entry, sequence, container, itemTrove, fighting)

		local function release()
			if destroyed then
				return
			end
			trove:Remove(itemTrove)
			ToastQueue.finish(queue)
			pump()
		end

		itemTrove:Add(function()
			Motion.cancel(group)
		end)
		Motion.to(group, { Position = UDim2.new() }, "UiPop")
		Motion.to(group, { GroupTransparency = 0 }, "Ui")

		local seconds = ToastQueue.duration(entry.Text, entry.Kind, Theme.Timing.Toast)
		itemTrove:Add(task.delay(seconds, function()
			-- The place is freed once the message has left, not on a timer guessed to match its exit.
			Motion.to(group, { Position = UDim2.fromOffset(SLIDE, 0), GroupTransparency = 1 }, "UiExit", release)
		end))
	end

	pump = function()
		while not destroyed do
			local entry = ToastQueue.take(queue)
			if entry == nil then
				return
			end
			present(entry)
		end
	end

	container.Parent = props.Parent

	local function show(_self: Toast, text: string, kind: Kind, amount: string?)
		if destroyed then
			return
		end
		if ToastQueue.push(queue, { Text = text, Kind = kind, Amount = amount }) then
			pump()
		end
	end

	local function hold(_self: Toast, kinds: { [string]: boolean })
		ToastQueue.hold(queue, kinds)
		pump()
	end

	local function setMaxVisible(_self: Toast, count: number)
		ToastQueue.setMaxVisible(queue, count)
		pump()
	end

	local function pause(_self: Toast, paused: boolean)
		ToastQueue.pause(queue, paused)
		pump()
	end

	local function setTop(_self: Toast, top: number)
		if touch then
			container.Position = UDim2.new(1, -EDGE, 0, top)
		end
	end

	local function setLane(_self: Toast, lane: Lane)
		touch = lane == "Touch"
		container.Position = if touch
			then UDim2.new(1, -EDGE, 0, Theme.Sizes.Padding)
			else UDim2.new(1, -EDGE, POINTER_TOP, 0)
		container.Size = UDim2.fromScale(if touch then TOUCH_SHARE else POINTER_SHARE, 0)
	end

	local function setFight(_self: Toast, next: boolean)
		fighting = next
	end

	local function destroy(_self: Toast)
		destroyed = true
		trove:Destroy()
	end

	local object: Toast = {
		Instance = container,
		Show = show,
		Hold = hold,
		SetMaxVisible = setMaxVisible,
		Pause = pause,
		SetTop = setTop,
		SetLane = setLane,
		SetFight = setFight,
		Destroy = destroy,
	}
	setLane(object, props.Lane or "Pointer")
	return object
end

return Toast
