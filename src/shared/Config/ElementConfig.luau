--!strict
-- Elements (mantras). Pure data: no requires, no Roblox globals, so it loads under Lune.
-- Element ids are persisted in profiles and used as combo keys: never rename them.

export type ElementId = "Fire" | "Water" | "Earth" | "Wind" | "Lightning"
export type Rgb = { number }

local ElementConfig = {}

-- Display / iteration order.
ElementConfig.Order = { "Fire", "Water", "Earth", "Wind", "Lightning" } :: { ElementId }

-- Unlocked for every new profile.
ElementConfig.Base = { "Fire", "Water", "Earth", "Wind" } :: { ElementId }

-- Unlocked by grind or game pass (see MonetizationConfig / ProgressionConfig).
ElementConfig.Unlockable = { "Lightning" } :: { ElementId }

-- Colors as RGB 0-255 (UI converts to Color3).
ElementConfig.Colors = {
	Fire = { 235, 90, 40 },
	Water = { 60, 140, 235 },
	Earth = { 150, 105, 60 },
	Wind = { 170, 220, 190 },
	Lightning = { 240, 220, 80 },
} :: { [ElementId]: Rgb }

-- Single-letter glyph shown on combo chips / touch buttons (locale independent).
ElementConfig.Glyphs = {
	Fire = "F",
	Water = "W",
	Earth = "E",
	Wind = "A",
	Lightning = "L",
} :: { [ElementId]: string }

-- Strings keys for localized names.
ElementConfig.NameKeys = {
	Fire = "element.fire",
	Water = "element.water",
	Earth = "element.earth",
	Wind = "element.wind",
	Lightning = "element.lightning",
} :: { [ElementId]: string }

local lookup: { [string]: boolean } = {}
for _, id in ipairs(ElementConfig.Order) do
	lookup[id] = true
end

function ElementConfig.isElement(value: any): boolean
	return type(value) == "string" and lookup[value] == true
end

return ElementConfig
