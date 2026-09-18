--!strict
-- Elements (mantras). Pure data: no requires, no Roblox globals, so it loads under Lune.
-- Element ids are persisted in profiles and used as combo keys: never rename them.

export type ElementId = "Cinnabar" | "Indigo" | "Umber" | "Verdigris" | "Orpiment"
export type Rgb = { number }

local ElementConfig = {}

-- Display / iteration order.
ElementConfig.Order = { "Cinnabar", "Indigo", "Umber", "Verdigris", "Orpiment" } :: { ElementId }

-- Unlocked for every new profile.
ElementConfig.Base = { "Cinnabar", "Indigo", "Umber", "Verdigris" } :: { ElementId }

-- Unlocked by grind or game pass (see MonetizationConfig / ProgressionConfig).
ElementConfig.Unlockable = { "Orpiment" } :: { ElementId }

-- Colors as RGB 0-255 (UI converts to Color3).
ElementConfig.Colors = {
	Cinnabar = { 235, 90, 40 },
	Indigo = { 60, 140, 235 },
	Umber = { 150, 105, 60 },
	Verdigris = { 170, 220, 190 },
	Orpiment = { 240, 220, 80 },
} :: { [ElementId]: Rgb }

-- Glyph shown on combo chips / touch buttons. Pictographs, not initials: letters would have to be the
-- initials of one language ("W" for Water reads as Eau in French), and these labels never go through
-- Strings.t. One distinct shape per element so colour is not the only cue.
ElementConfig.Glyphs = {
	Cinnabar = "▲",
	Indigo = "≈",
	Umber = "■",
	Verdigris = "»",
	Orpiment = "✦",
} :: { [ElementId]: string }

-- Strings keys for localized names.
ElementConfig.NameKeys = {
	Cinnabar = "pigment.cinnabar",
	Indigo = "pigment.indigo",
	Umber = "pigment.umber",
	Verdigris = "pigment.verdigris",
	Orpiment = "pigment.orpiment",
} :: { [ElementId]: string }

local lookup: { [string]: boolean } = {}
for _, id in ipairs(ElementConfig.Order) do
	lookup[id] = true
end

function ElementConfig.isElement(value: any): boolean
	return type(value) == "string" and lookup[value] == true
end

return ElementConfig
