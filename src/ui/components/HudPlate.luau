--!strict
-- HudPlate: an ink plate of the HUD, as tall as what it holds (D-147). The match, the boss, the portal circle
-- and the place each draw their band on one, in the top-centre column, and the boss's warning stands on one:
-- ink against the cream world (13.89), vellum and the pigments on the ink. A plate lets the world through by
-- the player's own background-transparency setting (Sticker's Plate kind).
--
-- Callers fill `Content`, which stacks its children down the middle; `Scale` is the plate's own, for the
-- entrance that grows it into place (docs/ART_BIBLE.md rule 3: nothing appears).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Props = {
	Name: string,
	Width: number,
	-- A fixed height; absent, the plate is as tall as its content.
	Height: number?,
	Padding: number?,
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

function HudPlate.new(props: Props): HudPlate
	local trove = Trove.new()
	local padding = props.Padding or PADDING
	local fixed = props.Height

	local frame = Instance.new("Frame")
	frame.Name = props.Name
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = props.LayoutOrder or 0
	frame.Position = props.Position or UDim2.new()
	frame.AnchorPoint = props.AnchorPoint or Vector2.zero
	frame.Size = UDim2.fromOffset(props.Width, fixed or 0)
	frame.AutomaticSize = if fixed ~= nil then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
	frame.Visible = false
	trove:Add(frame)

	local plate = Sticker.new({
		Kind = "Plate",
		Fill = Theme.Colors.Plate,
		Corner = props.Corner or UDim.new(0, Theme.Sizes.CornerCard),
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
		Name = "Plate",
	})
	trove:Add(function()
		plate:Destroy()
	end)

	-- The content decides the height; the plate, sized to the frame, fills whatever it asks for.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	if fixed ~= nil then
		content.Size = UDim2.fromScale(1, 1)
	else
		content.Size = UDim2.fromScale(1, 0)
		content.AutomaticSize = Enum.AutomaticSize.Y
	end
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0, padding)
	inset.PaddingBottom = UDim.new(0, padding)
	inset.PaddingLeft = UDim.new(0, padding)
	inset.PaddingRight = UDim.new(0, padding)
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
