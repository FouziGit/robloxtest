--!strict
-- TouchButton: round on-screen button for touch controls (one per ContextActionService action).
-- Purely visual: a colored disc with a glyph label. The InputController owns the input handling and
-- calls SetPressed to reflect the touch state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Label: string,
	Color: Color3,
	Size: number, -- px at UIScale 1
	Position: UDim2,
	Parent: Instance?,
	Name: string?,
}

export type TouchButton = {
	Instance: Frame,
	SetPressed: (self: TouchButton, pressed: boolean) -> (),
	Destroy: (self: TouchButton) -> (),
}

local TouchButton = {}

local IDLE_TRANSPARENCY = 0.35
local PRESSED_TRANSPARENCY = 0.05
local PRESSED_SCALE = 0.9
local STROKE_THICKNESS = 2
local STROKE_TRANSPARENCY = 0.5

function TouchButton.new(props: Props): TouchButton
	local trove = Trove.new()
	local pressed = false

	local frame = Instance.new("Frame")
	frame.Name = props.Name or "TouchButton"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = props.Position
	frame.Size = UDim2.fromOffset(props.Size, props.Size)
	frame.BackgroundColor3 = props.Color
	frame.BackgroundTransparency = IDLE_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Active = true
	trove:Add(frame)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Text
	stroke.Thickness = STROKE_THICKNESS
	stroke.Transparency = STROKE_TRANSPARENCY
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Fonts.Title
	label.TextSize = Theme.Sizes.TextTitle
	label.TextColor3 = Theme.Colors.Text
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = props.Label
	label.Parent = frame

	local function render()
		TweenService:Create(frame, TweenInfo.new(Theme.Animation.Fast), {
			BackgroundTransparency = if pressed then PRESSED_TRANSPARENCY else IDLE_TRANSPARENCY,
		}):Play()
		TweenService:Create(scale, TweenInfo.new(Theme.Animation.Fast), {
			Scale = if pressed then PRESSED_SCALE else 1,
		}):Play()
	end

	frame.Parent = props.Parent

	local function setPressed(_self: TouchButton, value: boolean)
		if value == pressed then
			return
		end
		pressed = value
		render()
	end

	local function destroy(_self: TouchButton)
		trove:Destroy()
	end

	local object: TouchButton = {
		Instance = frame,
		SetPressed = setPressed,
		Destroy = destroy,
	}
	return object
end

return TouchButton
