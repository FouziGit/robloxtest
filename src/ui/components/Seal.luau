--!strict
-- Seal: a wax seal pressed on the page -- a level, a rank, a grade, a tier, the "claimed" stamp (D-147). A
-- disc of `Fill`, ringed by the SealRing texture the casts draw in the air (tinted `Rim`, or ink), with
-- its text in the title or the number face, in the ink that reads on the fill. `Stamp` presses it in:
-- down from a size and a half, with the overshoot of a hand that lets go.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Face = "Title" | "Numeric"

export type Props = {
	Text: string,
	Fill: Color3,
	Rim: Color3?,
	-- Diameter, in design units.
	Size: number,
	Face: Face?,
	Stamp: boolean?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Seal = {
	Instance: Frame,
	SetText: (self: Seal, text: string) -> (),
	SetFill: (self: Seal, fill: Color3, rim: Color3?) -> (),
	Stamp: (self: Seal) -> (),
	Destroy: (self: Seal) -> (),
}

local Seal = {}

-- The ring's ink reaches 0.90 to 0.92 of its plane (AssetIds), so a plane 115 % of the disc puts the ring
-- just outside the wax.
local RING_SCALE = 1.15
local RING_TRANSPARENCY = 0.1
local STAMP_FROM = 1.5
local TEXT_SCALE = 0.62

function Seal.new(props: Props): Seal
	local trove = Trove.new()
	local fill = props.Fill

	local disc = Instance.new("Frame")
	disc.Name = props.Name or "Seal"
	disc.BorderSizePixel = 0
	disc.BackgroundColor3 = fill
	disc.Size = UDim2.fromOffset(props.Size, props.Size)
	disc.Position = props.Position or UDim2.new()
	disc.AnchorPoint = props.AnchorPoint or Vector2.zero
	disc.LayoutOrder = props.LayoutOrder or 0
	Theme.corner(disc, Theme.Pill)
	trove:Add(disc)
	local scale = Instance.new("UIScale")
	scale.Parent = disc
	trove:Add(function()
		Motion.cancel(scale)
	end)

	local ringColor = props.Rim or Theme.Colors.Accent
	local ring: GuiObject
	local id = Theme.texture("SealRing")
	if id ~= "" then
		local image = Instance.new("ImageLabel")
		image.Image = id
		image.ImageColor3 = ringColor
		image.ImageTransparency = RING_TRANSPARENCY
		image.BackgroundTransparency = 1
		ring = image
	else
		-- Not uploaded: the rim is a plain ring of ink.
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		Theme.corner(frame, Theme.Pill)
		Theme.stroke(frame, ringColor, Theme.Sizes.Stroke)
		ring = frame
	end
	ring.Name = "Ring"
	ring.BorderSizePixel = 0
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(RING_SCALE, RING_SCALE)
	ring.Parent = disc

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(TEXT_SCALE, TEXT_SCALE)
	label.FontFace = if props.Face == "Numeric" then Theme.Fonts.Numeric else Theme.Fonts.Title
	label.TextScaled = true
	label.TextColor3 = Theme.inkOn(fill)
	label.Text = props.Text
	label.Parent = disc

	local function recolour(rim: Color3?)
		disc.BackgroundColor3 = fill
		label.TextColor3 = Theme.inkOn(fill)
		local color = rim or Theme.Colors.Accent
		if ring:IsA("ImageLabel") then
			ring.ImageColor3 = color
		else
			local stroke = ring:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				stroke.Color = color
			end
		end
	end

	local function stamp(_self: Seal?)
		Motion.set(scale, { Scale = STAMP_FROM })
		Motion.to(scale, { Scale = 1 }, "UiPop")
	end

	disc.Parent = props.Parent
	if props.Stamp == true then
		stamp(nil)
	end

	local function setText(_self: Seal, text: string)
		label.Text = text
	end

	local function setFill(_self: Seal, next: Color3, rim: Color3?)
		fill = next
		recolour(rim)
	end

	local function destroy(_self: Seal)
		trove:Destroy()
	end

	local object: Seal = {
		Instance = disc,
		SetText = setText,
		SetFill = setFill,
		Stamp = stamp,
		Destroy = destroy,
	}
	return object
end

return Seal
