--!strict
-- Keycap: a key or a pad button drawn as the thing the player presses (D-147) -- a small sheet cap on a
-- chalk lip, the key's name in the number face. The hotbar, the settings, the glyph cards and the hub's
-- prompts all name keys this way, so a player learns one picture for "press this". An optional strip of a
-- pigment along its bottom ties the key to its school: "J" on a Cinnabar strip.
--
-- What it says (Keycap.label): a letter, a digit or F1 to F8 as itself; the D-pad as arrows, in the only
-- face that has them; anything else as its `key.*` word, in the player's language ("Maj", "Clic gauche").

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

-- What the cap of `keyName` says.
function Keycap.label(keyName: string, localize: Localizer): string
	local arrow = ARROWS[keyName]
	if arrow ~= nil then
		return arrow
	end
	local digit = DIGITS[keyName]
	if digit ~= nil then
		return digit
	end
	if #keyName == 1 or string.match(keyName, "^F%d+$") ~= nil then
		return keyName
	end
	return localize.t("key." .. keyName)
end

function Keycap.new(props: Props): Keycap
	local trove = Trove.new()
	local height = props.Size or Theme.Sizes.Keycap
	local corner = if props.Device == "Gamepad" then Theme.Pill else UDim.new(0, Theme.Sizes.CornerKeycap)

	local sticker = Sticker.new({
		Kind = "Pressable",
		Fill = Theme.Colors.PanelRaised,
		Lip = Theme.lip("Secondary"),
		Corner = corner,
		Elevation = ELEVATION,
		Stroke = Theme.Sizes.StrokeThin,
		Size = UDim2.fromOffset(0, height + ELEVATION),
		LayoutOrder = props.LayoutOrder,
		Name = props.Name or "Keycap",
	})
	trove:Add(function()
		sticker:Destroy()
	end)
	local root = sticker.Instance
	-- A word widens the cap; a letter keeps it square.
	root.AutomaticSize = Enum.AutomaticSize.X

	-- Invisible, and the only child the automatic width reads: the face and its lip fill whatever it asks.
	local measure = Instance.new("TextLabel")
	measure.Name = "Measure"
	measure.BackgroundTransparency = 1
	measure.TextTransparency = 1
	measure.AutomaticSize = Enum.AutomaticSize.X
	measure.Size = UDim2.fromOffset(height, height)
	measure.FontFace = Theme.Fonts.Numeric
	measure.TextSize = TEXT_SIZE
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, PADDING)
	padding.PaddingRight = UDim.new(0, PADDING)
	padding.Parent = measure
	measure.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Key"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextSize = TEXT_SIZE
	label.TextColor3 = Theme.Colors.Text
	label.Parent = sticker.Face

	local pigment = props.Pigment
	if pigment ~= nil then
		local strip = Instance.new("Frame")
		strip.Name = "Pigment"
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = Theme.pigmentColor(pigment)
		strip.AnchorPoint = Vector2.new(0.5, 1)
		strip.Position = UDim2.new(0.5, 0, 1, -Theme.Sizes.StrokeThin)
		strip.Size = UDim2.new(1, -Theme.Sizes.CornerKeycap * 2, 0, STRIP_HEIGHT)
		strip.Parent = sticker.Face
	end

	local function setKey(_self: Keycap?, key: string)
		local text = Keycap.label(key, props.Localize)
		local font = if ARROWS[key] ~= nil then Theme.Fonts.Symbol else Theme.Fonts.Numeric
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
