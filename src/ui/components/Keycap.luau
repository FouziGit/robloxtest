--!strict
-- Keycap: a key or a pad button drawn as the thing the player presses (D-147) -- a small sheet cap on a
-- chalk lip, the key's character in the number face or its word in the label face. The hotbar, the settings, the glyph cards and the hub's
-- prompts all name keys this way, so a player learns one picture for "press this". An optional strip of a
-- pigment along its foot, the width of the cap, ties the key to its school: "J" on a Cinnabar strip. The
-- hotbar's caps stand on no lip, as the board draws them: they are a legend under a slot, not buttons.
--
-- What it says (Keycap.label): a letter, a digit or F1 to F8 as itself, in the number face; the D-pad as
-- arrows, in the only face that has them; anything else as its `key.*` word, in the player's language ("Maj",
-- "Clic gauche"), in the label face that sets every word on a badge or a tag (spec 2.8: its 4.14 asks the
-- number face of the cap, which is right for the characters and wrong for a word).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local Sticker = require(script.Parent.Sticker)
local Theme = require(script.Parent.Parent.Theme)
local Trove = require(Packages.Trove)

export type Device = "Keyboard" | "Gamepad"
export type Localizer = { t: (key: string, params: { [string]: any }?) -> string }

export type Props = {
	-- An Enum.KeyCode (or UserInputType, for the mouse buttons) name.
	Key: string,
	Device: Device,
	Localize: Localizer,
	-- Height of the cap, in design units (Theme.Sizes.Keycap by default).
	Size: number?,
	-- A PigmentConfig id: the strip along the bottom.
	Pigment: string?,
	-- Whether the cap stands on its chalk lip; true unless told otherwise.
	Lip: boolean?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
}

export type Keycap = {
	Instance: Frame,
	SetKey: (self: Keycap, key: string) -> (),
	Destroy: (self: Keycap) -> (),
}

local Keycap = {}

local ARROWS: { [string]: string } = {
	DPadUp = "↑",
	DPadRight = "→",
	DPadDown = "↓",
	DPadLeft = "←",
}
local DIGITS: { [string]: string } = {
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}

local ELEVATION = 3
local TEXT_SIZE = 16
local PADDING = 6
local STRIP_HEIGHT = 4

-- A key is drawn as an arrow, as its own character (a digit, a letter, an F key), or as its word.
type Form = "Arrow" | "Character" | "Word"

local function formOf(keyName: string): Form
	if ARROWS[keyName] ~= nil then
		return "Arrow"
	elseif DIGITS[keyName] ~= nil or #keyName == 1 or string.match(keyName, "^F%d+$") ~= nil then
		return "Character"
	end
	return "Word"
end

-- What the cap of `keyName` says.
function Keycap.label(keyName: string, localize: Localizer): string
	local form = formOf(keyName)
	if form == "Arrow" then
		return ARROWS[keyName]
	elseif form == "Character" then
		return DIGITS[keyName] or keyName
	end
	return localize.t("key." .. keyName)
end

-- The face the cap of `keyName` is set in.
function Keycap.font(keyName: string): Font
	local form = formOf(keyName)
	if form == "Arrow" then
		return Theme.Fonts.Symbol
	elseif form == "Word" then
		return Theme.Fonts.Label
	end
	return Theme.Fonts.Numeric
end

function Keycap.new(props: Props): Keycap
	local trove = Trove.new()
	local height = props.Size or Theme.Sizes.Keycap
	local round = props.Device == "Gamepad"
	local corner = if round then Theme.Pill else UDim.new(0, Theme.Sizes.CornerKeycap)
	local elevation = if props.Lip == false then 0 else ELEVATION

	local sticker = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Lip = Theme.lip("Secondary"),
		Corner = corner,
		Elevation = elevation,
		Stroke = Theme.Sizes.StrokeThin,
		Size = UDim2.fromOffset(0, height + elevation),
		LayoutOrder = props.LayoutOrder,
		Name = props.Name or "Keycap",
	})
	trove:Add(function()
		sticker:Destroy()
	end)
	local root = sticker.Instance :: Frame
	-- A word widens the cap; a letter keeps it square.
	root.AutomaticSize = Enum.AutomaticSize.X

	-- Invisible, and what the automatic width is measured on: the face and its lip, the cap's own children,
	-- fill whatever it asks. Nothing under the face takes its width from the face, or the engine would
	-- measure it against the screen (D-170): the word is centred at its own width, and the pigment strip is
	-- the cap's child, not the face's.
	--
	-- A pigment strip takes the foot of the face: the word stands over it, set no taller than what it leaves.
	-- A hotbar's cap (19 units, D-172) sets it at 13; a word of 16 on the cap of 15 it was lost its foot under
	-- the strip.
	local pigment = props.Pigment
	local reserve = if pigment ~= nil then STRIP_HEIGHT + Theme.Sizes.StrokeThin else 0
	local textSize = math.min(TEXT_SIZE, height - reserve)
	local measure = Instance.new("TextLabel")
	measure.Name = "Measure"
	measure.BackgroundTransparency = 1
	measure.TextTransparency = 1
	measure.AutomaticSize = Enum.AutomaticSize.X
	measure.Size = UDim2.fromOffset(height, height)
	measure.TextSize = textSize
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = measure
	measure.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Key"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.new(0, 0, 1, -reserve)
	label.TextSize = textSize
	label.TextColor3 = Theme.Colors.Text
	label.Parent = sticker.Face

	if pigment ~= nil then
		-- The pigment runs the width of the face inside its outline, flush on the face's foot, rounded as the
		-- face's inner corner is. A pad's button is round: its strip keeps a corner's width off the curve.
		local inset = if round then Theme.Sizes.CornerKeycap else Theme.Sizes.StrokeThin
		local strip = Instance.new("Frame")
		strip.Name = "Pigment"
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = Theme.pigmentColor(pigment)
		strip.AnchorPoint = Vector2.new(0.5, 1)
		strip.Position = UDim2.new(0.5, 0, 1, -Theme.Sizes.StrokeThin - elevation)
		strip.Size = UDim2.new(1, -inset * 2, 0, STRIP_HEIGHT)
		Theme.corner(
			strip,
			if round then Theme.Pill else UDim.new(0, Theme.Sizes.CornerKeycap - Theme.Sizes.StrokeThin)
		)
		strip.ZIndex = 3
		strip.Parent = root
	end

	local function setKey(_self: Keycap?, key: string)
		local text = Keycap.label(key, props.Localize)
		local font = Keycap.font(key)
		label.FontFace = font
		label.Text = text
		measure.FontFace = font
		measure.Text = text
	end
	setKey(nil, props.Key)

	root.Parent = props.Parent

	local function destroy(_self: Keycap)
		trove:Destroy()
	end

	local object: Keycap = {
		Instance = root,
		SetKey = setKey,
		Destroy = destroy,
	}
	return object
end

return Keycap
