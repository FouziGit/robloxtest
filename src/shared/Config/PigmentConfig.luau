--!strict
-- Pigments (mantras). Pure data: no requires, no Roblox globals, so it loads under Lune.
-- Pigment ids are persisted in profiles and used as combo keys: never rename them.

export type PigmentId = "Cinnabar" | "Indigo" | "Umber" | "Verdigris" | "Orpiment"
export type Rgb = { number }

local PigmentConfig = {}

-- Display / iteration order.
PigmentConfig.Order = { "Cinnabar", "Indigo", "Umber", "Verdigris", "Orpiment" } :: { PigmentId }

-- Unlocked for every new profile.
PigmentConfig.Base = { "Cinnabar", "Indigo", "Umber", "Verdigris" } :: { PigmentId }

-- Unlocked by grind or game pass (see MonetizationConfig / ProgressionConfig).
PigmentConfig.Unlockable = { "Orpiment" } :: { PigmentId }

-- The five pigments, as RGB 0-255 (the UI converts to Color3). These are the exact values argued in
-- docs/ART_BIBLE.md, and they are the game's whole colour language: a school IS its pigment, so a
-- player has to be able to name the school from the colour alone, from behind, at thirty studs.
--
-- What they replace was the default elemental wheel -- orange, blue, brown, pale green, yellow -- which
-- is the palette every other game of this genre ships, and the first reason a screenshot of this one
-- was interchangeable with any other.
--
-- They are dark and saturated on purpose. The world is cream and unsaturated (rule 1: nothing in the
-- scenery is ever saturated), so a mark reads as ink on a page rather than as a glow in a dark room,
-- which is the inversion the direction is built on. tests/Config.spec.luau holds every pair apart by a
-- perceptual distance, because two schools nobody can tell apart is a gameplay defect, not a taste one.
PigmentConfig.Colors = {
	Cinnabar = { 217, 58, 34 }, -- #D93A22, mercury red
	Indigo = { 46, 74, 140 }, -- #2E4A8C, vat blue
	Umber = { 107, 74, 47 }, -- #6B4A2F, burnt earth
	Verdigris = { 79, 168, 140 }, -- #4FA88C, copper green
	Orpiment = { 232, 192, 34 }, -- #E8C022, arsenic yellow
} :: { [PigmentId]: Rgb }

-- Sigil shown on combo chips / touch buttons. Pictographs, not initials: an initial is the initial of
-- one language, and "I" for Indigo is "I" for nothing in French, where the pigment is read Indigo but
-- sits beside Terre d'Ombre and Vert-de-gris. These labels never go through Strings.t, so a shape is
-- the only thing that survives both locales. One distinct shape per pigment, so colour is not the
-- only cue for a player who cannot separate the five hues.
PigmentConfig.Sigils = {
	Cinnabar = "▲",
	Indigo = "≈",
	Umber = "■",
	Verdigris = "»",
	Orpiment = "✦",
} :: { [PigmentId]: string }

-- Strings keys for localized names.
PigmentConfig.NameKeys = {
	Cinnabar = "pigment.cinnabar",
	Indigo = "pigment.indigo",
	Umber = "pigment.umber",
	Verdigris = "pigment.verdigris",
	Orpiment = "pigment.orpiment",
} :: { [PigmentId]: string }

local lookup: { [string]: boolean } = {}
for _, id in ipairs(PigmentConfig.Order) do
	lookup[id] = true
end

function PigmentConfig.isPigment(value: any): boolean
	return type(value) == "string" and lookup[value] == true
end

return PigmentConfig
