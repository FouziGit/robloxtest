--!strict
-- Sticker: the base of every card, button, tile, toast and plate of the colourful interface (D-147). A
-- flat face in one colour, an ink outline (docs/ART_BIBLE.md rule 11: the outline is what detaches a vivid
-- shape from the page), and under it either a coloured lip -- what you press -- or a hard ink shadow --
-- what you read. Players learn the difference: a lip goes down when pressed, a shadow never moves.
--
--   Pressable  a face on its lip; SetState moves the face (hover lifts it, a press sinks it onto the lip)
--   Card       a face on a hard ink shadow; never moves
--   Plate      an ink face with no base and no outline, for the HUD: translucent by the player's own
--              background-transparency setting (UiPrefs), opaque for a player who asked for opaque
--
-- Callers parent their content to `Face`, so it rides the face when it moves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)
local UiPrefs = require(script.Parent.Parent.UiPrefs)

export type Kind = "Card" | "Pressable" | "Plate"
export type State = "Idle" | "Hover" | "Pressed" | "Disabled"

export type Props = {
	Kind: Kind,
	Fill: Color3,
	-- Pressable only: the colour under the face (Theme.lip). Defaults to the Secondary lip.
	Lip: Color3?,
	Corner: UDim?,
	-- How far the face stands off its base, in design units (§2.4 of the redesign: 5 for a button or a
	-- card, 6 for a tile, 4 for a disc or a toast, 0 for a plate).
	Elevation: number?,
	Gloss: boolean?,
	-- The ink outline; true unless the kind is Plate (rule 11).
	Outline: boolean?,
	-- The outline's design thickness: Theme.Sizes.Stroke, or StrokeThin for a row, a chip or a keycap.
	Stroke: number?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Sticker = {
	Instance: Frame,
	Face: Frame,
	Base: Frame?,
	SetFill: (self: Sticker, fill: Color3) -> (),
	SetState: (self: Sticker, state: State) -> (),
	Destroy: (self: Sticker) -> (),
}

local Sticker = {}

-- The face of a plate lets this much of the world through, times the player's own setting.
local PLATE_TRANSPARENCY = 0.08
-- How much lighter a hovered face is, and darker a pressed one.
local HOVER_SHADE = 0.06
local PRESSED_SHADE = -0.06
-- How far a hovered face rises off its lip.
local HOVER_LIFT = 2
-- The face of the gloss covers this much of the face, from its top.
local GLOSS_HEIGHT = 0.45

local function defaultElevation(kind: Kind): number
	if kind == "Plate" then
		return 0
	end
	return 5
end

local function defaultCorner(kind: Kind): UDim
	if kind == "Pressable" then
		return Theme.Pill
	end
	return UDim.new(0, Theme.Sizes.CornerCard)
end

function Sticker.new(props: Props): Sticker
	local trove = Trove.new()
	local kind: Kind = props.Kind
	local fill = props.Fill
	local elevation = props.Elevation or defaultElevation(kind)
	local corner = props.Corner or defaultCorner(kind)
	local outline = if props.Outline ~= nil then props.Outline else kind ~= "Plate"
	local strokeThickness = props.Stroke or Theme.Sizes.Stroke
	local state: State = "Idle"

	local root = Instance.new("Frame")
	root.Name = props.Name or "Sticker"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.Size = props.Size or UDim2.fromScale(1, 1)
	root.Position = props.Position or UDim2.new()
	root.AnchorPoint = props.AnchorPoint or Vector2.zero
	root.LayoutOrder = props.LayoutOrder or 0
	trove:Add(root)

	local base: Frame? = nil
	if kind ~= "Plate" then
		local frame = Instance.new("Frame")
		frame.Name = "Base"
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Position = UDim2.fromOffset(0, elevation)
		frame.Size = UDim2.new(1, 0, 1, -elevation)
		frame.BackgroundColor3 = if kind == "Pressable" then props.Lip or Theme.lip("Secondary") else Theme.Colors.Plate
		Theme.corner(frame, corner)
		Theme.stroke(frame, "Accent", strokeThickness)
		frame.Parent = root
		base = frame
	end

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.ZIndex = 2
	face.Position = UDim2.new()
	face.Size = UDim2.new(1, 0, 1, -elevation)
	face.BackgroundColor3 = fill
	Theme.corner(face, corner)
	if outline then
		Theme.stroke(face, "Accent", strokeThickness)
	end
	face.Parent = root
	trove:Add(function()
		Motion.cancel(face)
	end)

	if props.Gloss == true then
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.BorderSizePixel = 0
		gloss.BackgroundColor3 = Theme.Colors.PanelRaised
		gloss.Size = UDim2.fromScale(1, GLOSS_HEIGHT)
		Theme.corner(gloss, corner)
		Theme.gradient("Gloss").Parent = gloss
		gloss.Parent = face
	end

	if kind == "Plate" then
		local function applyTransparency()
			face.BackgroundTransparency = PLATE_TRANSPARENCY * UiPrefs.transparency()
		end
		applyTransparency()
		local following = UiPrefs.Changed:Connect(applyTransparency)
		trove:Add(function()
			following:Disconnect()
		end)
	end

	local function render(animate: boolean)
		if kind ~= "Pressable" then
			face.BackgroundColor3 = fill
			return
		end
		local y = 0
		local color = fill
		local preset: Motion.Preset = "UiSnappy"
		if state == "Hover" then
			y = -HOVER_LIFT
			color = Theme.shade(fill, HOVER_SHADE)
		elseif state == "Pressed" then
			y = elevation - 1
			color = Theme.shade(fill, PRESSED_SHADE)
		elseif state == "Disabled" then
			-- It sits on its lip: no depth left to press.
			y = elevation - 1
			color = Theme.Colors.Chalk
		else
			-- Back from anywhere with the overshoot: a released button springs up, and that is the click.
			preset = "UiPop"
		end
		local goals = { Position = UDim2.fromOffset(0, y), BackgroundColor3 = color }
		if animate then
			Motion.to(face, goals, preset)
		else
			Motion.set(face, goals)
		end
	end

	render(false)
	root.Parent = props.Parent

	local function setFill(_self: Sticker, next: Color3)
		fill = next
		render(false)
	end

	local function setState(_self: Sticker, next: State)
		if state == next then
			return
		end
		state = next
		render(true)
	end

	local function destroy(_self: Sticker)
		trove:Destroy()
	end

	local object: Sticker = {
		Instance = root,
		Face = face,
		Base = base,
		SetFill = setFill,
		SetState = setState,
		Destroy = destroy,
	}
	return object
end

return Sticker
