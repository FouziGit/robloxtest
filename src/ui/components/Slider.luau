--!strict
-- Slider: horizontal value slider with a draggable knob (D-147): an inkwell track in a thin ink outline, a
-- vivid fill, a knob of sheet in the ink outline that swells while held, and -- when the caller gives a
-- format -- the value written beside it ("80 %"). Mouse and touch drags start on the track (InputBegan)
-- and keep tracking through UserInputService so the drag survives leaving the track. With a gamepad, D-pad
-- left / right nudge the value while the slider is selected, and the knob springs to it. OnChange fires on
-- every user-driven change, OnRelease once the player lets go (a preview of the volume); SetValue is silent.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Min: number,
	Max: number,
	Value: number,
	Step: number?,
	OnChange: (value: number) -> (),
	-- Once a drag ends, and after each D-pad nudge.
	OnRelease: ((value: number) -> ())?,
	-- The readout beside the track, in the player's language (common.percent). Absent: no readout.
	Format: ((value: number) -> string)?,
	-- The fill; the ink bar's blue by default.
	Color: Color3?,
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
local BAR_HEIGHT = 12
local KNOB_SIZE = 28
local HELD_SCALE = 1.2
local GAMEPAD_STEPS = 20 -- D-pad nudges per full range when no Step is given: 5 % each
local READOUT_WIDTH = 60

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
	track.SelectionImageObject = trove:Add(Theme.focusRing())
	-- Keep gamepad selection on the slider so D-pad presses adjust the value instead of moving away.
	track.NextSelectionLeft = track
	track.NextSelectionRight = track
	trove:Add(track)

	-- The whole track is the drag area, so the touch minimum belongs to it: the knob is only an indicator.
	Theme.minPixelSize(track, Theme.MinTouchTarget)

	-- Bar inset by half a knob on each side so the knob never overflows the hit area, and short of the
	-- readout when there is one.
	local format = props.Format
	local readoutWidth = if format ~= nil then READOUT_WIDTH else 0
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, KNOB_SIZE / 2, 0.5, 0)
	bar.Size = UDim2.new(1, -KNOB_SIZE - readoutWidth, 0, BAR_HEIGHT)
	bar.BackgroundColor3 = Theme.Colors.Well
	bar.BorderSizePixel = 0
	Theme.corner(bar, Theme.Pill)
	Theme.stroke(bar, "Accent", Theme.Sizes.StrokeThin)
	bar.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = props.Color or Theme.Colors.InfoFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Theme.corner(fill, Theme.Pill)
	fill.Parent = bar

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BackgroundColor3 = Theme.Colors.PanelRaised
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	Theme.corner(knob, Theme.Pill)
	Theme.stroke(knob, "Accent", Theme.Sizes.Stroke)
	knob.Parent = bar
	local held = Instance.new("UIScale")
	held.Parent = knob
	trove:Add(function()
		Motion.cancel(fill)
		Motion.cancel(knob)
		Motion.cancel(held)
	end)

	local readout: TextLabel? = nil
	if format ~= nil then
		local label = Instance.new("TextLabel")
		label.Name = "Readout"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(1, 0.5)
		label.Position = UDim2.fromScale(1, 0.5)
		label.Size = UDim2.new(0, READOUT_WIDTH, 1, 0)
		label.FontFace = Theme.Fonts.Numeric
		label.TextSize = Theme.Sizes.NumSmall
		label.TextColor3 = Theme.Colors.Text
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.Parent = track
		readout = label
	end

	local function alpha(): number
		if range <= 0 then
			return 0
		end
		return (value - min) / range
	end

	-- Written directly under a finger, which must not lag; sprung on a D-pad nudge.
	local function render(animate: boolean?)
		local a = alpha()
		if animate then
			Motion.to(fill, { Size = UDim2.fromScale(a, 1) }, "UiSnappy")
			Motion.to(knob, { Position = UDim2.fromScale(a, 0.5) }, "UiSnappy")
		else
			Motion.set(fill, { Size = UDim2.fromScale(a, 1) })
			Motion.set(knob, { Position = UDim2.fromScale(a, 0.5) })
		end
		local label = readout
		if label ~= nil and format ~= nil then
			label.Text = format(value)
		end
	end

	local function release()
		local onRelease = props.OnRelease
		if onRelease ~= nil then
			onRelease(value)
		end
	end

	local function snap(raw: number): number
		local clamped = math.clamp(raw, min, max)
		local step = props.Step
		if step ~= nil and step > 0 then
			clamped = math.clamp(min + math.round((clamped - min) / step) * step, min, max)
		end
		return clamped
	end

	local function apply(raw: number, notify: boolean, animate: boolean?): boolean
		local snapped = snap(raw)
		if snapped == value then
			return false
		end
		value = snapped
		render(animate)
		if notify then
			props.OnChange(value)
		end
		return true
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
		Motion.to(held, { Scale = HELD_SCALE }, "UiSnappy")
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
			Motion.to(held, { Scale = 1 }, "UiPop")
			release()
		end
	end)

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if GuiService.SelectedObject ~= track then
			return
		end
		local step = props.Step or range / GAMEPAD_STEPS
		local moved = false
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			moved = apply(value - step, true, true)
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			moved = apply(value + step, true, true)
		end
		if moved then
			release()
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
