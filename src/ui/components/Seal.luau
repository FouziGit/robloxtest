--!strict
-- Seal: a wax seal pressed on the page -- a level, a rank, a grade, a tier, the "claimed" stamp (D-147). A
-- flat disc of `Fill` in its ink outline, as every sticker wears one (a thinner one on a seal smaller than a
-- thumb), with its text in the title, the number or the illuminated face, in the ink that reads on the fill:
-- charcoal on a light fill, the sheet on a dark one. A seal that is worth more wears a crisp rim around its
-- outline -- a ring of `Rim`, then a ring of ink, as the board draws a rank -- and gold leaf shimmers. `Stamp`
-- presses it in: down from a size and a half, with the overshoot of a hand that lets go, its rims and its
-- letter with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Shimmer = require(script.Parent.Shimmer)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

-- Title and Numeric scale their text into the disc; Initial sets one illuminated letter at the board's size.
export type Face = "Title" | "Numeric" | "Initial"

export type Props = {
	Text: string,
	Fill: Color3,
	Rim: Color3?,
	-- The text's colour; the ink that reads on the fill unless told otherwise.
	Ink: Color3?,
	-- Diameter, in design units.
	Size: number,
	Face: Face?,
	Stamp: boolean?,
	-- Gold leaf: a sweep of light across the disc (Shimmer).
	Shimmer: boolean?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Seal = {
	Instance: Frame,
	SetText: (self: Seal, text: string) -> (),
	SetFill: (self: Seal, fill: Color3, rim: Color3?, ink: Color3?) -> (),
	SetShimmer: (self: Seal, on: boolean) -> (),
	Stamp: (self: Seal) -> (),
	Destroy: (self: Seal) -> (),
}

local Seal = {}

local STAMP_FROM = 1.5
local TEXT_SCALE = 0.62
-- Under this diameter the outline is the thin one: at a thumb's size a 3-unit ring ate the fill.
local THIN_BELOW = 32
-- The board's rank seal: 58 across, its letter 24.
local INITIAL_RATIO = 24 / 58
-- Each ring of a rim is a stroke this thick, outside the last.
local RIM = Theme.Sizes.Stroke
local SHINE_Z = 3

-- The ink that reads on `fill`: charcoal, or the sheet where charcoal does not read (the board's palette:
-- the sheet on Tyrian and on the ink plate, where the page's vellum would be the other choice).
local function inkFor(fill: Color3): Color3
	local ink = Theme.inkOn(fill)
	if ink == Theme.Colors.TextInverse then
		return Theme.Colors.PanelRaised
	end
	return ink
end

-- A transparent ring centred on `disc`, `grow` units wider than it, its stroke of `color` on its inside.
local function ring(disc: Frame, name: string, grow: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, grow, 1, grow)
	Theme.corner(frame, Theme.Pill)
	Theme.stroke(frame, color, RIM)
	frame.Parent = disc
	return frame
end

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
	-- As drawn: Theme.stroke floors a thin line on a phone.
	local thickness = Theme.stroke(
		disc,
		"Accent",
		if props.Size < THIN_BELOW then Theme.Sizes.StrokeThin else Theme.Sizes.Stroke
	).Thickness
	trove:Add(disc)
	local scale = Instance.new("UIScale")
	scale.Parent = disc
	trove:Add(function()
		Motion.cancel(scale)
	end)

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	if props.Face == "Initial" then
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Theme.Fonts.Initial
		label.TextSize = math.round(props.Size * INITIAL_RATIO)
	else
		label.Size = UDim2.fromScale(TEXT_SCALE, TEXT_SCALE)
		label.FontFace = if props.Face == "Numeric" then Theme.Fonts.Numeric else Theme.Fonts.Title
		label.TextScaled = true
	end
	label.TextColor3 = props.Ink or inkFor(fill)
	label.Text = props.Text
	label.Parent = disc

	-- The rim: a ring of its colour around the outline, then a ring of ink around that.
	local rims: { Frame } = {}
	local function setRim(rim: Color3?)
		for _, frame in ipairs(rims) do
			frame:Destroy()
		end
		table.clear(rims)
		if rim ~= nil then
			table.insert(rims, ring(disc, "Rim", RIM * 2, rim))
			table.insert(rims, ring(disc, "RimInk", RIM * 4, Theme.Colors.Accent))
		end
	end
	setRim(props.Rim)

	local shimmer: Shimmer.Shimmer? = nil
	local function setShimmer(_self: Seal?, on: boolean)
		local current = shimmer
		if on == (current ~= nil) then
			return
		end
		if current ~= nil then
			shimmer = nil
			current:Destroy()
			return
		end
		shimmer = Shimmer.new(disc, Theme.Pill, SHINE_Z, thickness)
	end
	trove:Add(function()
		setShimmer(nil, false)
	end)
	setShimmer(nil, props.Shimmer == true)

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

	local function setFill(_self: Seal, next: Color3, rim: Color3?, ink: Color3?)
		fill = next
		disc.BackgroundColor3 = fill
		label.TextColor3 = ink or inkFor(fill)
		setRim(rim)
	end

	local function destroy(_self: Seal)
		trove:Destroy()
	end

	local object: Seal = {
		Instance = disc,
		SetText = setText,
		SetFill = setFill,
		SetShimmer = setShimmer,
		Stamp = stamp,
		Destroy = destroy,
	}
	return object
end

return Seal
