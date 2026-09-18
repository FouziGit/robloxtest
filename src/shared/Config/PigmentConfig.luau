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

-- Colors as RGB 0-255 (UI converts to Color3).
PigmentConfig.Colors = {
	Cinnabar = { 235, 90, 40 },
	Indigo = { 60, 140, 235 },
	Umber = { 150, 105, 60 },
	Verdigris = { 170, 220, 190 },
	Orpiment = { 240, 220, 80 },
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
