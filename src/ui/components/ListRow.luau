--!strict
-- ListRow: a raised row with a left slot (label or any GuiObject, fills the remaining width) and an
-- optional right slot (label or any GuiObject, sized by its content). Rows default to
-- Theme.Sizes.RowHeight so they stay comfortable touch targets. A GuiObject handed to a slot is only
-- re-parented: the caller keeps ownership, but it is destroyed with the row like any descendant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Content = string | GuiObject

export type Props = {
	Left: Content,
	Right: Content?,
	Height: number?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type ListRow = {
	Instance: Frame,
	SetLeft: (self: ListRow, content: Content) -> (),
	SetRight: (self: ListRow, content: Content?) -> (),
	Destroy: (self: ListRow) -> (),
}

type Slot = {
	Frame: Frame,
	Label: TextLabel?, -- label owned by the row
	Object: GuiObject?, -- object owned by the caller
}

local ListRow = {}

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

local function makeLabel(slot: Slot, text: string, isLeft: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = if isLeft then Theme.Fonts.Body else Theme.Fonts.Bold
	label.TextSize = Theme.Sizes.TextBody
	label.TextColor3 = if isLeft then Theme.Colors.Text else Theme.Colors.TextMuted
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	if isLeft then
		label.Size = UDim2.fromScale(1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
	else
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.TextXAlignment = Enum.TextXAlignment.Right
	end
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

local function fillSlot(slot: Slot, content: Content?, isLeft: boolean)
	clearSlot(slot)
	if content == nil then
		return
	end
	if type(content) == "string" then
		slot.Label = makeLabel(slot, content, isLeft)
	else
		local object = content :: GuiObject
		object.Parent = slot.Frame
		slot.Object = object
	end
end

function ListRow.new(props: Props): ListRow
	local trove = Trove.new()

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "ListRow"
	frame.BackgroundColor3 = Theme.Colors.PanelRaised
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, props.Height or Theme.Sizes.RowHeight)
	frame.LayoutOrder = props.LayoutOrder or 0
	trove:Add(frame)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Theme.Sizes.Gap)
	layout.Parent = frame

	local left = makeSlot("Left", Enum.HorizontalAlignment.Left, 1)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = left.Frame
	left.Frame.Parent = frame

	local right = makeSlot("Right", Enum.HorizontalAlignment.Right, 2)
	right.Frame.AutomaticSize = Enum.AutomaticSize.X
	right.Frame.Parent = frame

	fillSlot(left, props.Left, true)
	fillSlot(right, props.Right, false)

	frame.Parent = props.Parent

	local function setLeft(_self: ListRow, content: Content)
		fillSlot(left, content, true)
	end

	local function setRight(_self: ListRow, content: Content?)
		fillSlot(right, content, false)
	end

	local function destroy(_self: ListRow)
		trove:Destroy()
	end

	local object: ListRow = {
		Instance = frame,
		SetLeft = setLeft,
		SetRight = setRight,
		Destroy = destroy,
	}
	return object
end

return ListRow
