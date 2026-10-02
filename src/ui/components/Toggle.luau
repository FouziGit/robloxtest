--!strict
-- Toggle: an on/off switch drawn as a pill with a sliding knob inside a RowHeight-tall TextButton, so mouse,
-- touch and gamepad (Activated) all work (D-147). Off is chalk with its word on the right; on is the green
-- of what went well, with its word on the left, and the knob of sheet springs across with a pop. The word
-- is the caller's ("Off" / "Non"): colour is never the only cue. OnChange fires on user toggles; SetValue
-- is silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Value: boolean,
	OnChange: (value: boolean) -> (),
	-- The words in the pill, in the player's language (common.on / common.off). Absent: no word.
	OnText: string?,
	OffText: string?,
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
local PILL_WIDTH = 64
local PILL_HEIGHT = 34
local KNOB_SIZE = 26
local KNOB_INSET = (PILL_HEIGHT - KNOB_SIZE) / 2
local WORD_SIZE = 14
local HOVER_SHADE = 0.06

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
	button.SelectionImageObject = trove:Add(Theme.focusRing())
	trove:Add(button)

	-- The pill is decoration; the whole button is the target, so it carries the touch minimum.
	Theme.minPixelSize(button, Theme.MinTouchTarget)

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromOffset(PILL_WIDTH, PILL_HEIGHT)
	pill.BorderSizePixel = 0
	Theme.corner(pill, Theme.Pill)
	Theme.stroke(pill, "Accent", Theme.Sizes.StrokeThin)
	pill.Parent = button

	-- The word sits on the side the knob has left.
	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.BackgroundTransparency = 1
	word.AnchorPoint = Vector2.new(0, 0.5)
	word.Size = UDim2.new(1, -(KNOB_SIZE + KNOB_INSET * 2), 1, 0)
	word.FontFace = Theme.Fonts.Label
	word.TextSize = WORD_SIZE
	word.Parent = pill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BackgroundColor3 = Theme.Colors.PanelRaised
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	Theme.corner(knob, Theme.Pill)
	Theme.stroke(knob, "Accent", Theme.Sizes.StrokeThin)
	knob.Parent = pill

	local function render(animate: boolean)
		local pillColor = if value then Theme.Colors.SuccessFill else Theme.Colors.Chalk
		if hovered then
			pillColor = Theme.shade(pillColor, HOVER_SHADE)
		end
		local knobOffset = KNOB_INSET + KNOB_SIZE / 2
		local knobPosition = if value then UDim2.new(1, -knobOffset, 0.5, 0) else UDim2.new(0, knobOffset, 0.5, 0)
		word.Text = (if value then props.OnText else props.OffText) or ""
		word.TextColor3 = if value then Theme.Colors.Text else Theme.Colors.TextMuted
		word.Position = if value then UDim2.new(0, KNOB_INSET, 0.5, 0) else UDim2.new(0, KNOB_SIZE + KNOB_INSET, 0.5, 0)
		if animate then
			Motion.to(pill, { BackgroundColor3 = pillColor }, "UiSnappy")
			Motion.to(knob, { Position = knobPosition }, "UiPop")
		else
			Motion.set(pill, { BackgroundColor3 = pillColor })
			Motion.set(knob, { Position = knobPosition })
		end
	end
	trove:Add(function()
		Motion.cancel(pill)
		Motion.cancel(knob)
	end)

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
