--!strict
-- Button: themed TextButton (Primary / Secondary / Danger) with hover, pressed, disabled and gamepad
-- selection states. Default height is Theme.Sizes.RowHeight, and Theme.minPixelSize keeps the rendered
-- button at Theme.MinTouchTarget real pixels even where the ScreenRoot UIScale shrinks the layout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Variant = "Primary" | "Secondary" | "Danger"

export type Props = {
	Text: string,
	Variant: Variant?,
	OnClick: (() -> ())?,
	Disabled: boolean?,
	Size: UDim2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Button = {
	Instance: TextButton,
	SetText: (self: Button, text: string) -> (),
	SetDisabled: (self: Button, disabled: boolean) -> (),
	SetVariant: (self: Button, variant: Variant) -> (),
	IsDisabled: (self: Button) -> boolean,
	Destroy: (self: Button) -> (),
}

type Palette = { Background: Color3, Text: Color3, Stroke: Color3? }

local Button = {}

local DISABLED_TRANSPARENCY = 0.55
local HOVER_SHADE = 0.08
local PRESSED_SHADE = -0.1
-- A press squashes the button and the spring brings it back: the overshoot is the click.
local PRESSED_SCALE = 0.96
local SELECTION_THICKNESS = 3

local function paletteFor(variant: Variant): Palette
	if variant == "Primary" then
		return { Background = Theme.Colors.Accent, Text = Theme.Colors.TextInverse }
	elseif variant == "Danger" then
		return { Background = Theme.Colors.Danger, Text = Theme.Colors.Text }
	end
	return { Background = Theme.Colors.PanelRaised, Text = Theme.Colors.Text, Stroke = Theme.Colors.Border }
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

function Button.new(props: Props): Button
	local trove = Trove.new()
	local palette = paletteFor(props.Variant or "Secondary")
	local disabled = props.Disabled == true
	local hovered = false
	local pressed = false

	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.AutoButtonColor = false
	button.BackgroundColor3 = palette.Background
	button.BorderSizePixel = 0
	button.FontFace = Theme.Fonts.Bold
	button.TextSize = Theme.Sizes.TextBody
	button.TextColor3 = palette.Text
	button.Text = props.Text
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.Size = props.Size or UDim2.new(1, 0, 0, Theme.Sizes.RowHeight)
	button.LayoutOrder = props.LayoutOrder or 0
	button.Selectable = not disabled
	button.SelectionImageObject = trove:Add(makeSelectionImage())
	trove:Add(button)
	trove:Add(function()
		Motion.cancel(button)
	end)

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = button

	Theme.minPixelSize(button, Theme.MinTouchTarget)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Sizes.CornerRadiusSmall)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
	padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
	padding.Parent = button

	local function refresh()
		local background = palette.Background
		local transparency = 0
		if disabled then
			transparency = DISABLED_TRANSPARENCY
		elseif pressed then
			background = Theme.shade(palette.Background, PRESSED_SHADE)
		elseif hovered then
			background = Theme.shade(palette.Background, HOVER_SHADE)
		end
		button.TextColor3 = palette.Text
		local strokeColor = palette.Stroke
		stroke.Color = strokeColor or palette.Background
		stroke.Transparency = if strokeColor ~= nil then transparency else 1
		Motion.to(button, {
			BackgroundColor3 = background,
			BackgroundTransparency = transparency,
			TextTransparency = transparency,
		}, "UiSnappy")
		Motion.to(scale, { Scale = if pressed then PRESSED_SCALE else 1 }, "UiSnappy")
	end

	trove:Connect(button.MouseEnter, function()
		hovered = true
		refresh()
	end)
	trove:Connect(button.MouseLeave, function()
		hovered = false
		pressed = false
		refresh()
	end)
	trove:Connect(button.MouseButton1Down, function()
		pressed = true
		refresh()
	end)
	trove:Connect(button.MouseButton1Up, function()
		pressed = false
		refresh()
	end)
	trove:Connect(button.SelectionGained, function()
		hovered = true
		refresh()
	end)
	trove:Connect(button.SelectionLost, function()
		hovered = false
		pressed = false
		refresh()
	end)
	trove:Connect(button.Activated, function()
		if disabled then
			return
		end
		local onClick = props.OnClick
		if onClick ~= nil then
			onClick()
		end
	end)

	refresh()
	button.Parent = props.Parent

	local function setText(_self: Button, text: string)
		button.Text = text
	end

	local function setDisabled(_self: Button, value: boolean)
		disabled = value
		button.Selectable = not value
		refresh()
	end

	local function setVariant(_self: Button, variant: Variant)
		palette = paletteFor(variant)
		refresh()
	end

	local function isDisabled(_self: Button): boolean
		return disabled
	end

	local function destroy(_self: Button)
		trove:Destroy()
	end

	local object: Button = {
		Instance = button,
		SetText = setText,
		SetDisabled = setDisabled,
		SetVariant = setVariant,
		IsDisabled = isDisabled,
		Destroy = destroy,
	}
	return object
end

return Button
