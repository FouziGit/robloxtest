--!strict
-- Old identifier -> new identifier, for every id a saved profile can contain. Pure: no Roblox global,
-- no require, so DataMigration and the tests can both load it.
--
-- The vocabulary of the first two versions was borrowed from an existing licence: "jutsu", "chakra" and
-- the five rank names came straight from it, which is a moderation risk, a DMCA risk, and an obstacle to
-- owning a brand. docs/ART_BIBLE.md replaces the whole lexicon. The names below are drawn from
-- manuscript and typography craft: every one is a real word for a mark, a stroke or a stage of a book,
-- which is what this game is now about.
--
-- A profile written before the rename holds the old strings in Unlocks.Jutsus, Unlocks.Elements,
-- Loadout.Slots and Rank.Modes. Without this table those players would lose every unlock they earned.

local LegacyNames = {}

-- The five schools. Each is a historical pigment, so the name IS the colour.
LegacyNames.Pigments = {
	Fire = "Cinnabar",
	Water = "Indigo",
	Earth = "Umber",
	Wind = "Verdigris",
	Lightning = "Orpiment",
} :: { [string]: string }

-- The twenty glyphs. Named for marks and printing techniques, so the roster reads as one craft rather
-- than as a list of elements: a serif is a spike, a blot is a falling mass of ink, pounce is the powder
-- thrown on a wet page, a colophon is the final mark of a manuscript.
LegacyNames.Glyphs = {
	Fireball = "Brand",
	WaterWave = "Wash",
	EarthSpikes = "Serif",
	WindGust = "Sweep",
	BoilingMist = "Bleed",
	MudWall = "Margin",
	EmberStorm = "Scorch",
	Earthquake = "Rupture",
	EmberStep = "Ligature",
	Meteor = "Blot",
	WaterPrison = "Binding",
	MudShot = "Stipple",
	StoneSkin = "Gilding",
	WindBlade = "Hairline",
	Cyclone = "Spiral",
	Sandstorm = "Pounce",
	LightningBolt = "Strike",
	LightningStep = "Caret",
	StaticField = "Watermark",
	Raijin = "Colophon",
} :: { [string]: string }

-- The five ranks, as the states a manuscript passes through.
LegacyNames.Ranks = {
	Genin = "Blank",
	Chunin = "Sketch",
	Jonin = "Script",
	Anbu = "Illumination",
	Kage = "Codex",
} :: { [string]: string }

-- Returns the current id for `old`, or `old` itself when it is already current or unknown. Unknown ids
-- are passed through rather than dropped: a profile that somehow holds one keeps it, and the validation
-- that runs afterwards decides what to do with it.
local function translate(map: { [string]: string }, old: string): string
	return map[old] or old
end

function LegacyNames.pigment(old: string): string
	return translate(LegacyNames.Pigments, old)
end

function LegacyNames.glyph(old: string): string
	return translate(LegacyNames.Glyphs, old)
end

function LegacyNames.rank(old: string): string
	return translate(LegacyNames.Ranks, old)
end

-- Rewrites a list of ids in place through `map`, keeping order and dropping nothing.
function LegacyNames.translateList(map: { [string]: string }, list: { string }): number
	local changed = 0
	for index, old in ipairs(list) do
		local fresh = translate(map, old)
		if fresh ~= old then
			list[index] = fresh
			changed += 1
		end
	end
	return changed
end

return LegacyNames
