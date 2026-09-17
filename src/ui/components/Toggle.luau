--!strict
-- Toggle: on/off switch drawn as a pill with a sliding knob inside a RowHeight-tall TextButton, so
-- mouse, touch and gamepad (Activated) all work. OnChange fires on user toggles; SetValue is silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Value: boolean,
	OnChange: (value: boolean) -> (),
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Toggle = {
	Instance: TextButton,
	SetValue: (self: Toggle, value: boolean) -> (),
	GetValue: (self: Toggle) -> boolean,
	Destroy: (self: Toggle) -> (),
}

local Toggle = {}

local BUTTON_WIDTH = Theme.Sizes.TouchButton
local PILL_WIDTH = 52
local PILL_HEIGHT = 28
local KNOB_INSET = 3
local KNOB_SIZE = PILL_HEIGHT - KNOB_INSET * 2
local HOVER_SHADE = 0.08
local SELECTION_THICKNESS = 3

local function roundCorners(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
end

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

function Toggle.new(props: Props): Toggle
	local trove = Trove.new()
	local value = props.Value
	local hovered = false

	local button = Instance.new("TextButton")
	button.Name = props.Name or "Toggle"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.Size = UDim2.fromOffset(BUTTON_WIDTH, Theme.Sizes.RowHeight)
	button.LayoutOrder = props.LayoutOrder or 0
	button.SelectionImageObject = trove:Add(makeSelectionImage())
	trove:Add(button)

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromOffset(PILL_WIDTH, PILL_HEIGHT)
	pill.BorderSizePixel = 0
	pill.Parent = button
	roundCorners(pill)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BorderSizePixel = 0
	knob.Parent = pill
	roundCorners(knob)

	local function render(animate: boolean)
		local pillColor = if value then Theme.Colors.Accent else Theme.Colors.Border
		if hovered then
			pillColor = Theme.shade(pillColor, HOVER_SHADE)
		end
		local knobColor = if value then Theme.Colors.Text else Theme.Colors.TextMuted
		local knobOffset = KNOB_INSET + KNOB_SIZE / 2
		local knobPosition = if value then UDim2.new(1, -knobOffset, 0.5, 0) else UDim2.new(0, knobOffset, 0.5, 0)
		if animate then
			TweenService:Create(pill, TweenInfo.new(Theme.Animation.Fast), { BackgroundColor3 = pillColor }):Play()
			TweenService:Create(
				knob,
				TweenInfo.new(Theme.Animation.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = knobPosition, BackgroundColor3 = knobColor }
			):Play()
		else
			pill.BackgroundColor3 = pillColor
			knob.Position = knobPosition
			knob.BackgroundColor3 = knobColor
		end
	end

	trove:Connect(button.MouseEnter, function()
		hovered = true
		render(true)
	end)
	trove:Connect(button.MouseLeave, function()
		hovered = false
		render(true)
	end)
	trove:Connect(button.SelectionGained, function()
		hovered = true
		render(true)
	end)
	trove:Connect(button.SelectionLost, function()
		hovered = false
		render(true)
	end)
	trove:Connect(button.Activated, function()
		value = not value
		render(true)
		props.OnChange(value)
	end)

	render(false)
	button.Parent = props.Parent

	local function setValue(_self: Toggle, next: boolean)
		if next == value then
			return
		end
		value = next
		render(true)
	end

	local function getValue(_self: Toggle): boolean
		return value
	end

	local function destroy(_self: Toggle)
		trove:Destroy()
	end

	local object: Toggle = {
		Instance = button,
		SetValue = setValue,
		GetValue = getValue,
		Destroy = destroy,
	}
	return object
end

return Toggle
