--!strict
-- The interface's palette and typography, as pure data, so that a test can hold them to
-- docs/ART_BIBLE.md and to a contrast ratio without an engine.
--
-- VELLUM: the world is a page and the power is ink. So the interface is a PAGE -- vellum panels, charcoal
-- text -- and not the dark grey card with a gold accent that docs/ART_BIBLE.md names as the Roblox
-- default theme and replaces. The only saturated things on it are pigments, and a pigment on the
-- interface means what it means in the world: a school. Red still means danger to you (rule 7), and it
-- is Cinnabar's red, which is also what a Cinnabar glyph is; the two do not conflict, because a Cinnabar
-- glyph IS a danger to you.
--
-- Colours are {r, g, b} in 0..255. A font is an Enum.Font name and an Enum.FontWeight name;
-- src/ui/Theme.luau turns both into engine values and is the only place that does.

local ThemeConfig = {}

export type Rgb = { number }
export type FontDef = { Font: string, Weight: string }

-- docs/ART_BIBLE.md: Vélin #E8E0CE, Charbon #17150F. The five pigments live in PigmentConfig. The two
-- hexes are written ONCE, here, and the roles below point at them: a role that repeated the literal could
-- drift from the bible while the test that holds the bible's hex still passed.
local VELLUM: Rgb = { 232, 224, 206 }
local CHARCOAL: Rgb = { 23, 21, 15 }

ThemeConfig.Vellum = VELLUM
ThemeConfig.Charcoal = CHARCOAL

ThemeConfig.Colors = {
	-- The page.
	Panel = VELLUM,
	-- A second sheet laid on the first: the same paper, in shadow.
	PanelRaised = { 216, 206, 184 },
	Border = { 168, 156, 132 },
	-- Ink.
	Text = CHARCOAL,
	TextMuted = { 92, 86, 74 },
	-- Vellum on ink: the text of a charcoal button.
	TextInverse = VELLUM,
	-- The accent of a page is its ink. A primary action is charcoal on vellum, not gold.
	Accent = CHARCOAL,
	-- Verdigris as ink: what displaces, and here what went well. The pigment itself (#4FA88C) is too
	-- light to read as text on the page; soaked into it, it is this -- dark enough to clear 4.5 on the
	-- shaded sheet as well as on the page, which is where the battle pass and the loadout set it.
	Success = { 26, 88, 70 },
	-- Cinnabar, exact: danger to you.
	Danger = { 217, 58, 34 },
	-- Indigo, exact: what contains, and here what informs.
	Info = { 46, 74, 140 },
	-- The inkwell. Ink is Indigo on the page.
	Ink = { 46, 74, 140 },
	-- Health is the ink still on the page: charcoal. What was just lost is the bar's ghost, in Cinnabar.
	Health = CHARCOAL,
	Overlay = { 0, 0, 0 },
	-- Orpiment as ink: what is gilded. The pigment itself (#E8C022) is unreadable as text on vellum, and
	-- so was a lighter gold than this: the battle pass sets it at thirteen pixels.
	Premium = { 104, 82, 8 },
	-- The stroke around a floating number, so it reads over any floor.
	Outline = CHARCOAL,
} :: { [string]: Rgb }

-- docs/ART_BIBLE.md: "une romane à empattements pour les titres, une grotesque condensée pour les
-- chiffres", and Gotham and RobotoMono, the engine's defaults, replaced. Merriweather is the roman, set
-- for words at every size -- a page is set in one face -- and Oswald the condensed grotesque, which is
-- what makes a number read as a number rather than as a word.
ThemeConfig.Fonts = {
	Title = { Font = "Merriweather", Weight = "Bold" },
	Body = { Font = "Merriweather", Weight = "Regular" },
	Bold = { Font = "Merriweather", Weight = "Bold" },
	Numeric = { Font = "Oswald", Weight = "Medium" },
} :: { [string]: FontDef }

-- WCAG relative luminance of an sRGB colour, the number a contrast ratio is made of.
local function channel(value: number): number
	local c = value / 255
	if c <= 0.03928 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

function ThemeConfig.luminance(rgb: Rgb): number
	return 0.2126 * channel(rgb[1]) + 0.7152 * channel(rgb[2]) + 0.0722 * channel(rgb[3])
end

-- Contrast ratio between two colours, 1 to 21. Body text wants 4.5, large text and accents 3.
function ThemeConfig.contrast(a: Rgb, b: Rgb): number
	local la = ThemeConfig.luminance(a)
	local lb = ThemeConfig.luminance(b)
	local high = math.max(la, lb)
	local low = math.min(la, lb)
	return (high + 0.05) / (low + 0.05)
end

-- The ink that reads on `background`: charcoal on a light pigment (Orpiment, Verdigris), vellum on a
-- dark one (Indigo, Umber). Decided by contrast, not by a luminance threshold someone guessed.
function ThemeConfig.inkOn(background: Rgb): Rgb
	local text = ThemeConfig.Colors.Text
	local inverse = ThemeConfig.Colors.TextInverse
	if ThemeConfig.contrast(background, text) >= ThemeConfig.contrast(background, inverse) then
		return text
	end
	return inverse
end

return ThemeConfig
