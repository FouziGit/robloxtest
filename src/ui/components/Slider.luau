--!strict
-- Slider: horizontal value slider with a draggable knob. Mouse and touch drags start on the track
-- (InputBegan) and keep tracking through UserInputService so the drag survives leaving the track.
-- With a gamepad, D-pad left / right nudge the value while the slider is selected. OnChange fires on
-- every user-driven change; SetValue is silent.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Min: number,
	Max: number,
	Value: number,
	Step: number?,
	OnChange: (value: number) -> (),
	Size: UDim2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Slider = {
	Instance: Frame,
	SetValue: (self: Slider, value: number) -> (),
	GetValue: (self: Slider) -> number,
	Destroy: (self: Slider) -> (),
}

local Slider = {}

local DEFAULT_WIDTH = 200
local BAR_HEIGHT = Theme.Sizes.PaddingSmall
local KNOB_SIZE = Theme.Sizes.ButtonHeight / 2
local GAMEPAD_STEPS = 10 -- D-pad nudges per full range when no Step is given
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

function Slider.new(props: Props): Slider
	local trove = Trove.new()
	local min = math.min(props.Min, props.Max)
	local max = math.max(props.Min, props.Max)
	local range = max - min
	local value = math.clamp(props.Value, min, max)
	local activeInput: InputObject? = nil

	-- Hit area (transparent, taller than the bar so fingers land easily).
	local track = Instance.new("Frame")
	track.Name = props.Name or "Slider"
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.Active = true
	track.Selectable = true
	track.Size = props.Size or UDim2.fromOffset(DEFAULT_WIDTH, Theme.Sizes.ButtonHeight)
	track.LayoutOrder = props.LayoutOrder or 0
	track.SelectionImageObject = trove:Add(makeSelectionImage())
	-- Keep gamepad selection on the slider so D-pad presses adjust the value instead of moving away.
	track.NextSelectionLeft = track
	track.NextSelectionRight = track
	trove:Add(track)

	-- The whole track is the drag area, so the touch minimum belongs to it: the knob is only an indicator.
	Theme.minPixelSize(track, Theme.MinTouchTarget)

	-- Bar inset by half a knob on each side so the knob never overflows the hit area.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, KNOB_SIZE / 2, 0.5, 0)
	bar.Size = UDim2.new(1, -KNOB_SIZE, 0, BAR_HEIGHT)
	bar.BackgroundColor3 = Theme.Colors.Border
	bar.BorderSizePixel = 0
	bar.Parent = track
	roundCorners(bar)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	roundCorners(fill)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BackgroundColor3 = Theme.Colors.Text
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = bar
	roundCorners(knob)

	local function alpha(): number
		if range <= 0 then
			return 0
		end
		return (value - min) / range
	end

	local function render()
		local a = alpha()
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
	end

	local function snap(raw: number): number
		local clamped = math.clamp(raw, min, max)
		local step = props.Step
		if step ~= nil and step > 0 then
			clamped = math.clamp(min + math.round((clamped - min) / step) * step, min, max)
		end
		return clamped
	end

	local function apply(raw: number, notify: boolean)
		local snapped = snap(raw)
		if snapped == value then
			return
		end
		value = snapped
		render()
		if notify then
			props.OnChange(value)
		end
	end

	local function valueFromX(x: number): number
		local width = bar.AbsoluteSize.X
		if width <= 0 then
			return value
		end
		local a = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
		return min + a * range
	end

	local function isPointer(inputType: Enum.UserInputType): boolean
		return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
	end

	trove:Connect(track.InputBegan, function(input: InputObject)
		if not isPointer(input.UserInputType) then
			return
		end
		activeInput = input
		apply(valueFromX(input.Position.X), true)
	end)

	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		local active = activeInput
		if active == nil then
			return
		end
		local isMouseDrag = active.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		if input == active or isMouseDrag then
			apply(valueFromX(input.Position.X), true)
		end
	end)

	trove:Connect(UserInputService.InputEnded, function(input: InputObject)
		local active = activeInput
		if active == nil then
			return
		end
		local isMouseRelease = active.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if input == active or isMouseRelease then
			activeInput = nil
		end
	end)

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if GuiService.SelectedObject ~= track then
			return
		end
		local step = props.Step or range / GAMEPAD_STEPS
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			apply(value - step, true)
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			apply(value + step, true)
		end
	end)

	render()
	track.Parent = props.Parent

	local function setValue(_self: Slider, next: number)
		apply(next, false)
	end

	local function getValue(_self: Slider): number
		return value
	end

	local function destroy(_self: Slider)
		trove:Destroy()
	end

	local object: Slider = {
		Instance = track,
		SetValue = setValue,
		GetValue = getValue,
		Destroy = destroy,
	}
	return object
end

return Slider
