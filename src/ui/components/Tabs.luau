--!strict
-- Tabs: horizontal tab strip. Every tab is a TextButton sharing the width equally; the selected one is
-- filled with the accent color. `Select` switches tabs programmatically and fires OnSelect exactly like
-- a click would (nothing happens when the tab is already selected). The `Selected` prop only sets the
-- initial visual state, so screens build their first page explicitly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Item = { Id: string, Text: string }

export type Props = {
	Items: { Item },
	Selected: string?,
	OnSelect: (id: string) -> (),
	Size: UDim2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Tabs = {
	Instance: Frame,
	Select: (self: Tabs, id: string) -> (),
	GetSelected: (self: Tabs) -> string?,
	Destroy: (self: Tabs) -> (),
}

local Tabs = {}

local INSET = Theme.Sizes.PaddingSmall / 2
local HOVER_TRANSPARENCY = 0.8
local SELECTION_THICKNESS = 3

-- Gamepad selection highlight (replaces the engine's default blue box).
local function makeSelectionImage(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Selection"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Accent
	stroke.Thickness = SELECTION_THICKNESS
	stroke.Parent = frame

	return frame
end

function Tabs.new(props: Props): Tabs
	local trove = Trove.new()
	local selected: string? = props.Selected
	local buttons: { [string]: TextButton } = {}
	local hovered: { [string]: boolean } = {}

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "Tabs"
	frame.BackgroundColor3 = Theme.Colors.PanelRaised
	frame.BorderSizePixel = 0
	frame.Size = props.Size or UDim2.new(1, 0, 0, Theme.Sizes.RowHeight)
	frame.LayoutOrder = props.LayoutOrder or 0
	trove:Add(frame)

	-- The tabs fill the strip, so flooring the strip is enough to keep every tab tappable.
	Theme.minPixelSize(frame, Theme.MinTouchTarget)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, INSET)
	padding.PaddingBottom = UDim.new(0, INSET)
	padding.PaddingLeft = UDim.new(0, INSET)
	padding.PaddingRight = UDim.new(0, INSET)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, INSET)
	layout.Parent = frame

	local function refresh()
		for id, button in pairs(buttons) do
			local transparency = 1
			local textColor = Theme.Colors.TextMuted
			if id == selected then
				transparency = 0
				textColor = Theme.Colors.TextInverse
			elseif hovered[id] then
				transparency = HOVER_TRANSPARENCY
				textColor = Theme.Colors.Text
			end
			button.TextColor3 = textColor
			TweenService:Create(button, TweenInfo.new(Theme.Animation.Fast), {
				BackgroundTransparency = transparency,
			}):Play()
		end
	end

	local function selectTab(id: string)
		local button: TextButton? = buttons[id]
		if button == nil or selected == id then
			return
		end
		selected = id
		refresh()
		props.OnSelect(id)
	end

	local count = math.max(1, #props.Items)
	for index, item in ipairs(props.Items) do
		local button = Instance.new("TextButton")
		button.Name = item.Id
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.Colors.Accent
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Font = Theme.Fonts.Bold
		button.TextSize = Theme.Sizes.TextBody
		button.TextColor3 = Theme.Colors.TextMuted
		button.Text = item.Text
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.LayoutOrder = index
		-- Equal share of the width minus the gaps between tabs.
		button.Size = UDim2.new(1 / count, -INSET * (count - 1) / count, 1, 0)
		button.SelectionImageObject = trove:Add(makeSelectionImage())

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
		buttonCorner.Parent = button

		trove:Connect(button.MouseEnter, function()
			hovered[item.Id] = true
			refresh()
		end)
		trove:Connect(button.MouseLeave, function()
			hovered[item.Id] = false
			refresh()
		end)
		trove:Connect(button.SelectionGained, function()
			hovered[item.Id] = true
			refresh()
		end)
		trove:Connect(button.SelectionLost, function()
			hovered[item.Id] = false
			refresh()
		end)
		trove:Connect(button.Activated, function()
			selectTab(item.Id)
		end)

		button.Parent = frame
		buttons[item.Id] = button
	end

	refresh()
	frame.Parent = props.Parent

	local function selectMethod(_self: Tabs, id: string)
		selectTab(id)
	end

	local function getSelected(_self: Tabs): string?
		return selected
	end

	local function destroy(_self: Tabs)
		trove:Destroy()
	end

	local object: Tabs = {
		Instance = frame,
		Select = selectMethod,
		GetSelected = getSelected,
		Destroy = destroy,
	}
	return object
end

return Tabs
