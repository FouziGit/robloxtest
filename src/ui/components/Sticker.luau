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
--
-- A pressable's whole elevation shows its lip, and the ink rims it from outside (the board's `0 5px 0 0 lip,
-- 0 5px 0 3px ink`): an inner outline ate three of a button's five units of lip. A disabled one sinks onto a
-- chalk lip -- there is nothing under it to press -- and gets its colour back when it wakes.
--
-- A frame that sizes itself to its content (AutomaticSize) hosts its sticker (`Host`, D-170): the base, the
-- face and the gloss are then its own children, each sized by scale to it. The engine resolves a scale-sized
-- child of an automatically sized frame against the size its content gives it, but a scale-sized grandchild
-- against the nearest ancestor of a fixed size, and grows the frame to hold that: a sticker filling a button
-- from inside its own frame made the button as wide as the screen. So nothing under the face may take its
-- size from the face along an axis the host sizes itself on either; the gloss is the face's sibling, and
-- with it the face callers fill is a clear layer above it (`Face`), riding with the coloured one.

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
	-- Draw into this frame instead of a new one; Size, Position, AnchorPoint, LayoutOrder, Parent and Name are
	-- then the host's own, and Destroy leaves it standing.
	Host: GuiObject?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Sticker = {
	Instance: GuiObject,
	-- Where callers put content: the coloured face, or with a gloss the clear layer above both.
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
-- The gloss is light caught inside the ink, never over it. The board sets it inside the outline (`inset: 3px
-- 10px auto; height: 38%` on a pill, `.4cqw .8cqw` and 36% on a tile, each measured from inside the border):
-- this far under the outline and this far in from its ends, over this share of what the outline encloses; a
-- tile's under a corner this much tighter than its own.
local GLOSS_PILL_TOP = 3
local GLOSS_PILL_SIDE = 10
local GLOSS_PILL_HEIGHT = 0.38
local GLOSS_TILE_TOP = 4
local GLOSS_TILE_SIDE = 8
local GLOSS_TILE_HEIGHT = 0.36
local GLOSS_TILE_TIGHTEN = 4

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

	local host = props.Host
	local root: GuiObject
	if host ~= nil then
		root = host
	else
		local frame = Instance.new("Frame")
		frame.Name = props.Name or "Sticker"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = false
		frame.Size = props.Size or UDim2.fromScale(1, 1)
		frame.Position = props.Position or UDim2.new()
		frame.AnchorPoint = props.AnchorPoint or Vector2.zero
		frame.LayoutOrder = props.LayoutOrder or 0
		trove:Add(frame)
		root = frame
	end

	local lip = props.Lip or Theme.lip("Secondary")
	local base: Frame? = nil
	if kind ~= "Plate" then
		local frame = Instance.new("Frame")
		frame.Name = "Base"
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Position = UDim2.fromOffset(0, elevation)
		frame.Size = UDim2.new(1, 0, 1, -elevation)
		frame.BackgroundColor3 = if kind == "Pressable" then lip else Theme.Colors.Plate
		Theme.corner(frame, corner)
		if kind == "Pressable" then
			Theme.stroke(frame, "Accent", strokeThickness, "Border", "Outer")
		else
			Theme.stroke(frame, "Accent", strokeThickness)
		end
		frame.Parent = root
		trove:Add(frame)
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
	trove:Add(face)
	trove:Add(function()
		Motion.cancel(face)
	end)

	-- What rides with the face: the face, and with a gloss the gloss and the clear layer over it, each from
	-- where it rests on an idle face.
	local riders: { Frame } = { face }
	local rests: { [Frame]: UDim2 } = { [face] = UDim2.new() }
	local surface = face
	local shine: Frame? = nil
	if props.Gloss == true then
		local pill = corner == Theme.Pill
		local side = strokeThickness + (if pill then GLOSS_PILL_SIDE else GLOSS_TILE_SIDE)
		local drop = strokeThickness + (if pill then GLOSS_PILL_TOP else GLOSS_TILE_TOP)
		local share = if pill then GLOSS_PILL_HEIGHT else GLOSS_TILE_HEIGHT
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.BorderSizePixel = 0
		gloss.BackgroundColor3 = Theme.Colors.PanelRaised
		gloss.ZIndex = 3
		-- An offset is a whole number of units.
		gloss.Size = UDim2.new(1, -side * 2, share, -math.round(share * (elevation + strokeThickness * 2)))
		Theme.corner(gloss, if pill then corner else UDim.new(corner.Scale, corner.Offset - GLOSS_TILE_TIGHTEN))
		Theme.gradient("Gloss").Parent = gloss
		gloss.Parent = root
		trove:Add(gloss)
		local top = Instance.new("Frame")
		top.Name = "Top"
		top.BackgroundTransparency = 1
		top.BorderSizePixel = 0
		top.ZIndex = 4
		top.Size = face.Size
		top.Parent = root
		trove:Add(top)
		riders = { face, gloss, top }
		shine = gloss
		rests[gloss] = UDim2.fromOffset(side, drop)
		rests[top] = UDim2.new()
		surface = top
		trove:Add(function()
			Motion.cancel(gloss)
			Motion.cancel(top)
		end)
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
		local under = lip
		local preset: Motion.Preset = "UiSnappy"
		if state == "Hover" then
			y = -HOVER_LIFT
			color = Theme.shade(fill, HOVER_SHADE)
		elseif state == "Pressed" then
			y = elevation - 1
			color = Theme.shade(fill, PRESSED_SHADE)
		elseif state == "Disabled" then
			-- It sits on its lip: no depth left to press, and no light caught on a chalk that cannot be pressed
			-- (the board's disabled sticker is flat; seen in Studio, a disabled Buy kept its gloss).
			y = elevation - 1
			color = Theme.Colors.Chalk
			under = Theme.Colors.Chalk
		else
			-- Back from anywhere with the overshoot: a released button springs up, and that is the click.
			preset = "UiPop"
		end
		local currentBase = base
		if currentBase ~= nil then
			currentBase.BackgroundColor3 = under
		end
		local currentShine = shine
		if currentShine ~= nil then
			currentShine.Visible = state ~= "Disabled"
		end
		local position = UDim2.fromOffset(0, y)
		for _, rider in ipairs(riders) do
			local goals: { [string]: any } = { Position = rests[rider] + position }
			if rider == face then
				goals.BackgroundColor3 = color
			end
			if animate then
				Motion.to(rider, goals, preset)
			else
				Motion.set(rider, goals)
			end
		end
	end

	render(false)
	if host == nil then
		root.Parent = props.Parent
	end

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
		Face = surface,
		Base = base,
		SetFill = setFill,
		SetState = setState,
		Destroy = destroy,
	}
	return object
end

return Sticker
