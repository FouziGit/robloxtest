--!strict
-- ListRow: a card in a list (D-147) -- the sheet, a thin ink outline, a tab of colour down its left edge
-- saying what it is (a pigment, a rarity, a status), a leading slot, a title and its line, and a right slot.
-- No shadow: a list of fifty shadows is fifty frames more and a page that looks stacked, not listed.
--
--   Item       the card (the default)
--   Highlight  the card ringed in the primary yellow, with a ♦ tag: this tier, today, you
--   Header     no card: a title in the poster face with a brush swash of the chapter under its baseline,
--              and the right slot for a countdown
--   Empty      no card: a grey blot and a line of lore, and the right slot for a button (Retry)
--   Skeleton   chalk blocks where the words will be, breathing until the data arrives
--
-- The left slot is the title (a word, or any GuiObject that fills the rest of the row) and the right slot
-- is sized by its content, as before: `ListRow.new({ Left, Right, Height, LayoutOrder, Parent })` works
-- unchanged. A GuiObject handed to a slot is only re-parented: the caller keeps ownership, but it is
-- destroyed with the row like any descendant. Rows never render below Theme.MinTouchTarget.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Breath = require(script.Parent.Parent.Breath)
local Splat = require(script.Parent.Splat)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Content = string | GuiObject
export type Variant = "Item" | "Highlight" | "Header" | "Empty" | "Skeleton"

export type Props = {
	Left: Content,
	Right: Content?,
	Height: number?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
	Variant: Variant?,
	-- The tab down the left edge: a pigment, a rarity, a status.
	Tint: Color3?,
	-- The line under the title.
	Subtitle: string?,
	-- The leading slot, 40 square: an icon, a pigment chip, a seal.
	Leading: GuiObject?,
	-- The screen whose chapter colours a Header's swash (a ThemeConfig.Chapters key).
	Chapter: string?,
}

export type ListRow = {
	Instance: Frame,
	SetLeft: (self: ListRow, content: Content) -> (),
	SetRight: (self: ListRow, content: Content?) -> (),
	SetTint: (self: ListRow, tint: Color3?) -> (),
	Destroy: (self: ListRow) -> (),
}

type Slot = {
	Frame: Frame,
	Label: TextLabel?, -- label owned by the row
	Object: GuiObject?, -- object owned by the caller
}

local ListRow = {}

local TAB_WIDTH = 6
local TAB_INSET = 4
local LEADING_SIZE = 40
local SUBTITLE_SIZE = 16
local HEADER_SIZE = 24
local SWASH_HEIGHT = 12
local COUNTDOWN_SIZE = 18
local EMPTY_BLOT = 72
local EMPTY_TEXT_SIZE = 18
local HIGHLIGHT_STROKE = 4
local TAG_SIZE = 20
local SKELETON_LOW = 0.2
local SKELETON_HIGH = 0.5
local SKELETON_HOLD = 0.2

local function makeSlot(name: string, alignment: Enum.HorizontalAlignment, layoutOrder: number): Slot
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(0, 1)
	frame.LayoutOrder = layoutOrder

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = alignment
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	return { Frame = frame, Label = nil, Object = nil }
end

local function makeLabel(slot: Slot, text: string, isLeft: boolean, variant: Variant): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	if isLeft and variant == "Empty" then
		label.FontFace = Theme.Fonts.Lore
		label.TextSize = EMPTY_TEXT_SIZE
		label.TextColor3 = Theme.Colors.TextMuted
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.fromScale(1, 0)
		label.TextWrapped = true
		label.Text = text
		label.Parent = slot.Frame
		return label
	elseif isLeft then
		label.FontFace = if variant == "Header" then Theme.Fonts.Title else Theme.Fonts.Bold
		label.TextSize = if variant == "Header" then HEADER_SIZE else Theme.Sizes.TextButton
		label.TextColor3 = Theme.Colors.Text
		label.Size = UDim2.fromScale(1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
	else
		label.FontFace = if variant == "Header" then Theme.Fonts.Numeric else Theme.Fonts.Bold
		label.TextSize = if variant == "Header" then COUNTDOWN_SIZE else Theme.Sizes.TextBody
		label.TextColor3 = Theme.Colors.TextMuted
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.TextXAlignment = Enum.TextXAlignment.Right
	end
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.Parent = slot.Frame
	return label
end

local function clearSlot(slot: Slot)
	local label = slot.Label
	if label ~= nil then
		label:Destroy()
		slot.Label = nil
	end
	local object = slot.Object
	if object ~= nil then
		object.Parent = nil
		slot.Object = nil
	end
end

local function fillSlot(slot: Slot, content: Content?, isLeft: boolean, variant: Variant)
	clearSlot(slot)
	if content == nil then
		return
	end
	if type(content) == "string" then
		slot.Label = makeLabel(slot, content, isLeft, variant)
	else
		local object = content :: GuiObject
		object.Parent = slot.Frame
		slot.Object = object
	end
end

-- A chalk block standing in for a word that has not arrived.
local function block(parent: Instance, width: number, height: number, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Block"
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Theme.Colors.Chalk
	frame.BackgroundTransparency = SKELETON_LOW
	frame.Size = UDim2.new(width, 0, 0, height)
	frame.LayoutOrder = order
	Theme.corner(frame, Theme.Pill)
	frame.Parent = parent
	return frame
end

function ListRow.new(props: Props): ListRow
	local trove = Trove.new()
	local variant: Variant = props.Variant or "Item"
	local carded = variant == "Item" or variant == "Highlight" or variant == "Skeleton"

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "ListRow"
	frame.BackgroundColor3 = Theme.Colors.PanelRaised
	frame.BackgroundTransparency = if carded then 0 else 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, props.Height or Theme.Sizes.RowHeight)
	frame.LayoutOrder = props.LayoutOrder or 0
	trove:Add(frame)

	Theme.minPixelSize(frame, Theme.MinTouchTarget)

	local right = makeSlot("Right", Enum.HorizontalAlignment.Right, 4)
	right.Frame.AutomaticSize = Enum.AutomaticSize.X
	local empty = variant == "Empty"
	if empty then
		frame.AutomaticSize = Enum.AutomaticSize.Y
	end

	-- The card's outline lies on a frame of its own, over the card: a screen that rings a row with its own
	-- stroke (the Daily's today) sets it on the row itself, and one frame carries one stroke.
	if carded then
		Theme.corner(frame, UDim.new(0, Theme.Sizes.CornerCard))
		local edge = Instance.new("Frame")
		edge.Name = "Edge"
		edge.BackgroundTransparency = 1
		edge.Size = UDim2.fromScale(1, 1)
		edge.ZIndex = 3
		Theme.corner(edge, UDim.new(0, Theme.Sizes.CornerCard))
		Theme.stroke(edge, "Accent", Theme.Sizes.StrokeThin)
		edge.Parent = frame
	end

	local tab = Instance.new("Frame")
	tab.Name = "Tab"
	tab.BorderSizePixel = 0
	tab.Position = UDim2.fromOffset(TAB_INSET, TAB_INSET)
	tab.Size = UDim2.new(0, TAB_WIDTH, 1, -TAB_INSET * 2)
	tab.Visible = false
	Theme.corner(tab, Theme.Pill)
	tab.Parent = frame

	-- What is laid out in a row: the leading slot, the title and its line, the right slot.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 2
	body.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding + (if carded then TAB_INSET + TAB_WIDTH else 0))
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = body

	if empty then
		-- Nothing to list: a grey blot, a line of lore under it, and the right slot's button under that.
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.fromScale(1, 0)
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local blot = Instance.new("Frame")
		blot.Name = "Blot"
		blot.BackgroundTransparency = 1
		blot.Size = UDim2.fromOffset(EMPTY_BLOT, EMPTY_BLOT)
		blot.LayoutOrder = 0
		blot.Parent = body
		Splat.new({
			Size = UDim2.fromScale(1, 1),
			Tint = Theme.Colors.Chalk,
			Rotation = Splat.rotation(1),
			Parent = blot,
		})
		right.Frame.AutomaticSize = Enum.AutomaticSize.XY
		right.Frame.Size = UDim2.new()
	end

	local leading = props.Leading
	if leading ~= nil then
		local slot = Instance.new("Frame")
		slot.Name = "Leading"
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromOffset(LEADING_SIZE, LEADING_SIZE)
		slot.LayoutOrder = 1
		slot.Parent = body
		leading.Parent = slot
	end

	-- The title and its line, filling what the leading and right slots leave.
	local texts = Instance.new("Frame")
	texts.Name = "Texts"
	texts.BackgroundTransparency = 1
	texts.Size = UDim2.fromScale(0, 1)
	texts.LayoutOrder = 2
	texts.Parent = body
	if empty then
		texts.AutomaticSize = Enum.AutomaticSize.Y
		texts.Size = UDim2.fromScale(1, 0)
	else
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = texts
	end
	local textsLayout = Instance.new("UIListLayout")
	textsLayout.FillDirection = Enum.FillDirection.Vertical
	textsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	textsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	textsLayout.Padding = UDim.new(0, 2)
	textsLayout.Parent = texts

	-- The title fills the row, as the left slot always did (a caller's own frame is sized to it), unless a
	-- line goes under it.
	local left = makeSlot("Left", Enum.HorizontalAlignment.Left, 1)
	left.Frame.Size = if props.Subtitle ~= nil
		then UDim2.new(1, 0, 0, Theme.Sizes.TextButton + 6)
		else UDim2.fromScale(1, 1)
	if empty then
		left.Frame.AutomaticSize = Enum.AutomaticSize.Y
		left.Frame.Size = UDim2.fromScale(1, 0)
	end
	left.Frame.Parent = texts
	right.Frame.Parent = body

	local subtitle = props.Subtitle
	if subtitle ~= nil and variant ~= "Skeleton" then
		local line = Instance.new("TextLabel")
		line.Name = "Subtitle"
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, SUBTITLE_SIZE + 4)
		line.FontFace = Theme.Fonts.Body
		line.TextSize = SUBTITLE_SIZE
		line.TextColor3 = Theme.Colors.TextMuted
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextTruncate = Enum.TextTruncate.AtEnd
		line.Text = subtitle
		line.LayoutOrder = 2
		line.Parent = texts
	end

	if variant == "Skeleton" then
		-- The words are not here yet: two chalk blocks where they will be, on the shared breath.
		local title = block(texts, 0.6, 14, 1)
		local line = block(texts, 0.4, 10, 2)
		left.Frame.Visible = false
		if not UiPrefs.reducedMotion() then
			local reader = Breath.join("Skeleton", SKELETON_LOW, SKELETON_HIGH, SKELETON_HOLD)
			local following = reader.Value.Changed:Connect(function(value: number)
				title.BackgroundTransparency = value
				line.BackgroundTransparency = value
			end)
			local function stop()
				following:Disconnect()
				reader.Leave()
			end
			trove:Add(stop)
			frame.Destroying:Once(stop)
		end
	elseif variant == "Header" then
		-- The swash sits under the baseline, never behind a letter: decoration only.
		local swash: GuiObject
		local id = Theme.texture("BrushStroke")
		local color = if props.Chapter ~= nil then Theme.chapter(props.Chapter).Band else Theme.Colors.Primary
		if id ~= "" then
			local image = Instance.new("ImageLabel")
			image.Image = id
			image.ImageColor3 = color
			image.BackgroundTransparency = 1
			image.ScaleType = Enum.ScaleType.Stretch
			swash = image
		else
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = color
			Theme.corner(bar, Theme.Pill)
			swash = bar
		end
		swash.Name = "Swash"
		swash.BorderSizePixel = 0
		swash.AnchorPoint = Vector2.new(0, 1)
		swash.Position = UDim2.new(0, 0, 1, SWASH_HEIGHT / 2)
		swash.Size = UDim2.new(0.5, 0, 0, SWASH_HEIGHT)
		swash.ZIndex = 0
		swash.Parent = left.Frame
	elseif variant == "Highlight" then
		-- A second ring, in the primary yellow, inside the ink one; and a ♦ tag on the corner.
		local ring = Instance.new("Frame")
		ring.Name = "Highlight"
		ring.BackgroundTransparency = 1
		ring.Size = UDim2.fromScale(1, 1)
		ring.ZIndex = 4
		Theme.corner(ring, UDim.new(0, Theme.Sizes.CornerCard))
		Theme.stroke(ring, "Primary", HIGHLIGHT_STROKE)
		ring.Parent = frame
		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.BorderSizePixel = 0
		tag.BackgroundColor3 = Theme.Colors.Primary
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Position = UDim2.fromOffset(TAB_INSET, TAB_INSET)
		tag.Size = UDim2.fromOffset(TAG_SIZE, TAG_SIZE)
		tag.ZIndex = 5
		tag.FontFace = Theme.Fonts.Label
		tag.TextSize = Theme.Sizes.TextLabel - 3
		tag.TextColor3 = Theme.Colors.Text
		tag.Text = Theme.Glyphs.Pip
		Theme.corner(tag, Theme.Pill)
		Theme.stroke(tag, "Accent", Theme.Sizes.StrokeThin)
		tag.Parent = frame
	end

	fillSlot(left, props.Left, true, variant)
	fillSlot(right, props.Right, false, variant)

	local function setTint(_self: ListRow?, tint: Color3?)
		tab.Visible = carded and tint ~= nil
		if tint ~= nil then
			tab.BackgroundColor3 = tint
		end
	end
	setTint(nil, props.Tint)

	frame.Parent = props.Parent

	local function setLeft(_self: ListRow, content: Content)
		fillSlot(left, content, true, variant)
	end

	local function setRight(_self: ListRow, content: Content?)
		fillSlot(right, content, false, variant)
	end

	local function destroy(_self: ListRow)
		trove:Destroy()
	end

	local object: ListRow = {
		Instance = frame,
		SetLeft = setLeft,
		SetRight = setRight,
		SetTint = setTint,
		Destroy = destroy,
	}
	return object
end

return ListRow
