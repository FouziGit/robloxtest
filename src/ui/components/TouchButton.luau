--!strict
-- TouchButton: round on-screen button for touch controls (one per ContextActionService action).
-- Purely visual: a colored disc with a glyph label. The InputController owns the input handling and
-- calls SetPressed to reflect the touch state. The label color is derived from the disc luminance, so
-- light pigment discs (Verdigris, Orpiment) keep a readable glyph over the 3D scene, and its size is derived
-- from the disc so a localized action name shrinks to fit instead of being cut off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Label: string,
	Color: Color3,
	Size: number, -- disc diameter in rendered px (these buttons sit under no UIScale)
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
local LABEL_STROKE_TRANSPARENCY = 0.35
-- Rec. 709 relative luminance above which a disc counts as light and takes the dark glyph.
local LIGHT_DISC_LUMINANCE = 0.55
-- Label size as a fraction of the disc diameter: half a disc is what a single glyph fills without
-- touching the ring. Localized words are longer than a glyph, so TextScaled shrinks them from there
-- down to LABEL_MIN_TEXT_SIZE instead of truncating.
local LABEL_TEXT_RATIO = 0.5
local LABEL_MIN_TEXT_SIZE = 10

-- Glyph color and its outline for a disc of `color`: the pair is always the light/dark contrast, so a
-- semi-transparent disc over a bright world stays legible.
local function labelColors(color: Color3): (Color3, Color3)
	local luminance = 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
	if luminance > LIGHT_DISC_LUMINANCE then
		return Theme.Colors.TextInverse, Theme.Colors.Text
	end
	return Theme.Colors.Text, Theme.Colors.TextInverse
end

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

	local textColor, outlineColor = labelColors(props.Color)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Fonts.Title
	label.TextColor3 = textColor
	label.TextStrokeColor3 = outlineColor
	label.TextStrokeTransparency = LABEL_STROKE_TRANSPARENCY
	label.TextScaled = true
	label.TextWrapped = false -- one line: a wrapped word inside a disc reads worse than a smaller one
	label.Text = props.Label
	label.Parent = frame

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize = LABEL_MIN_TEXT_SIZE
	textSize.MaxTextSize =
		math.clamp(math.floor(props.Size * LABEL_TEXT_RATIO), LABEL_MIN_TEXT_SIZE, Theme.Sizes.TextTitle)
	textSize.Parent = label

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
