--!strict
-- CircleButton: a pressable disc of the sheet with a sign on it, for a button too small for a word (D-147) --
-- the meta cluster's "+" and "×", the spectate plate's previous and next. It sits on a chalk lip, lifts under
-- the pointer and sinks when pressed like every sticker you press, plays its own click, and its hit area is
-- floored at a thumb's whatever the scale. Out of a gamepad's way unless it says otherwise; then its focus is
-- the double ring, the fight's one where it stands in a fight (no value colour, docs/ART_BIBLE.md rule 11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiSound = require(script.Parent.Parent.UiSound)

export type Props = {
	Sign: string,
	-- Diameter, in design units.
	Size: number,
	OnClick: () -> (),
	-- A gamepad may select it, with this focus ring.
	Focus: Theme.FocusKind?,
	-- Turns the sign: a "►" turned half a turn points back.
	SignRotation: number?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type CircleButton = {
	Instance: TextButton,
	Destroy: (self: CircleButton) -> (),
}

local CircleButton = {}

local ELEVATION = 3
-- The sign fills this much of the disc.
local SIGN_SHARE = 0.5

function CircleButton.new(props: Props): CircleButton
	local trove = Trove.new()

	local button = Instance.new("TextButton")
	button.Name = props.Name or "CircleButton"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.LayoutOrder = props.LayoutOrder or 0
	button.Size = UDim2.fromOffset(props.Size, props.Size)
	button.Selectable = props.Focus ~= nil
	if props.Focus ~= nil then
		button.SelectionImageObject = trove:Add(Theme.focusRing(props.Focus, Theme.Pill))
	end
	trove:Add(button)
	Theme.minPixelSize(button, Theme.MinTouchTarget)

	-- The disc keeps its own size in the middle of the hit area, which a phone's floor makes larger than it:
	-- filling that area, it grew past the pill it sits in.
	local face = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Corner = Theme.Pill,
		Elevation = ELEVATION,
		Stroke = Theme.Sizes.StrokeThin,
		Size = UDim2.fromOffset(props.Size, props.Size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = button,
		Name = "Face",
	})
	trove:Add(function()
		face:Destroy()
	end)
	local sign = Instance.new("TextLabel")
	sign.Name = "Sign"
	sign.BackgroundTransparency = 1
	sign.Size = UDim2.fromScale(1, 1)
	sign.ZIndex = 3
	sign.FontFace = Theme.Fonts.Bold
	sign.TextSize = math.floor(props.Size * SIGN_SHARE)
	sign.TextColor3 = Theme.Colors.Text
	sign.Rotation = props.SignRotation or 0
	sign.Text = props.Sign
	sign.Parent = face.Face

	trove:Connect(button.MouseEnter, function()
		face:SetState("Hover")
	end)
	trove:Connect(button.MouseLeave, function()
		face:SetState("Idle")
	end)
	trove:Connect(button.MouseButton1Down, function()
		face:SetState("Pressed")
	end)
	trove:Connect(button.MouseButton1Up, function()
		face:SetState("Idle")
	end)
	trove:Connect(button.Activated, function()
		UiSound.play("UiClick")
		props.OnClick()
	end)

	button.Parent = props.Parent

	local function destroy(_self: CircleButton)
		trove:Destroy()
	end

	return { Instance = button, Destroy = destroy }
end

return CircleButton
