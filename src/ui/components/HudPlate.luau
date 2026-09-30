--!strict
-- HudPlate: an ink plate of the HUD, as tall as what it holds (D-147). The match, the boss, the portal circle
-- and the place each draw their band on one, in the top-centre column, and the boss's warning stands on one:
-- ink against the cream world (13.89), vellum and the pigments on the ink. A plate lets the world through by
-- the player's own background-transparency setting (Sticker's Plate kind).
--
-- Callers fill `Content`, which stacks its children down the middle; `Scale` is the plate's own, for the
-- entrance that grows it into place (docs/ART_BIBLE.md rule 3: nothing appears). A plate given no width is as
-- wide as what it holds, like the board's score pill: then nothing in `Content` may take its width from the
-- plate by scale (Sticker's Host, D-170).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Name: string,
	-- A fixed width; absent, the plate is as wide as its content.
	Width: number?,
	-- A fixed height; absent, the plate is as tall as its content.
	Height: number?,
	Padding: number?,
	-- The inset at the plate's two ends, when it differs from the one over and under its content (Padding).
	PaddingX: number?,
	Gap: number?,
	Corner: UDim?,
	-- How the content stacks: down the middle (a band), or along a row (the boss's warning).
	Direction: ("Vertical" | "Horizontal")?,
	LayoutOrder: number?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Parent: Instance?,
}

export type HudPlate = {
	Instance: Frame,
	Content: Frame,
	Scale: UIScale,
	-- Shown or not; shown, it grows into place from `from`.
	Grow: (self: HudPlate, from: number) -> (),
	Destroy: (self: HudPlate) -> (),
}

local HudPlate = {}

local PADDING = 10

-- How a frame sizes itself: along each axis it is given no size on.
local function automatic(width: boolean, height: boolean): Enum.AutomaticSize
	if width and height then
		return Enum.AutomaticSize.XY
	elseif width then
		return Enum.AutomaticSize.X
	elseif height then
		return Enum.AutomaticSize.Y
	end
	return Enum.AutomaticSize.None
end

function HudPlate.new(props: Props): HudPlate
	local trove = Trove.new()
	local padding = props.Padding or PADDING
	local paddingX = props.PaddingX or padding
	local width = props.Width
	local fixed = props.Height

	local frame = Instance.new("Frame")
	frame.Name = props.Name
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = props.LayoutOrder or 0
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.Size = UDim2.fromOffset(width or 0, fixed or 0)
	frame.AutomaticSize = automatic(width == nil, fixed == nil)
	frame.Visible = false
	trove:Add(frame)

	-- The frame hosts its plate (Sticker's Host, D-170): the content decides the height, and the plate, the
	-- frame's own child, fills whatever it asks for.
	local plate = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = props.Corner or UDim.new(0, Theme.Sizes.CornerCard),
		Host = frame,
	})
	trove:Add(function()
		plate:Destroy()
	end)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Size = UDim2.fromScale(if width ~= nil then 1 else 0, if fixed ~= nil then 1 else 0)
	content.AutomaticSize = automatic(width == nil, fixed == nil)
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0, padding)
	inset.PaddingBottom = UDim.new(0, padding)
	inset.PaddingLeft = UDim.new(0, paddingX)
	inset.PaddingRight = UDim.new(0, paddingX)
	inset.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if props.Direction == "Horizontal"
		then Enum.FillDirection.Horizontal
		else Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, props.Gap or padding)
	layout.Parent = content
	content.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Name = "Entrance"
	scale.Parent = frame
	trove:Add(function()
		Motion.cancel(scale)
	end)

	frame.Parent = props.Parent

	local function grow(_self: HudPlate, from: number)
		if frame.Visible then
			return
		end
		frame.Visible = true
		Motion.set(scale, { Scale = from })
		Motion.to(scale, { Scale = 1 }, "UiSnappy")
	end

	local function destroy(_self: HudPlate)
		trove:Destroy()
	end

	local object: HudPlate = {
		Instance = frame,
		Content = content,
		Scale = scale,
		Grow = grow,
		Destroy = destroy,
	}
	return object
end

return HudPlate
