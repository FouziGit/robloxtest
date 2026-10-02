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
-- Loadout.Slots and Cosmetics. Without this table those players would lose every unlock they earned
-- and every cosmetic they were rewarded, which is the one loss no apology repairs.
--
-- Every key below is an OLD identifier and must stay spelled the old way forever. A sweep that renames
-- them to match the rest of the codebase turns this file into an identity map and quietly wipes the
-- profiles it exists to save.

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

-- Cosmetics a profile can own. Two reasons an id is here. Ten named a rank or a character of the old
-- licence, so they carry the same risk as the rest of the lexicon. Eight were named after the spell they
-- reskin, and that spell no longer exists under that name: CosmeticConfig points a skin at its glyph
-- through Target, so SkinFireballAzure would have been a skin for nothing.
--
-- The replacements stay inside the craft. A headband is the band sewn at the head of a book's spine, a
-- frisket is the mask a printer cuts to keep ink off part of a sheet, a palimpsest is a page scraped
-- clean and written over, and a stylus is what a scribe holds. The three chakra auras become ink auras,
-- which is the same object under the name this game uses for it.
LegacyNames.Cosmetics = {
	GeninHeadband = "BlankHeadband",
	SteelKatana = "SteelStylus",
	MistCape = "PalimpsestCape",
	AnbuMask = "FrisketMask",
	BlueChakraAura = "BlueInkAura",
	ClanKimono = "ScriptoriumRobe",
	VioletChakraAura = "VioletInkAura",
	SageCloak = "ScribeCloak",
	GoldenChakraAura = "GoldenInkAura",
	HokageCloak = "CodexCloak",
	TitleKage = "TitleCodex",
	AuraHokage = "AuraCodex",
	TitleJonin = "TitleScript",
	TitleAnbu = "TitleIllumination",
	TitleKageSeason = "TitleCodexSeason",
	SkinFireballAzure = "SkinBrandAzure",
	SkinFireballEmerald = "SkinBrandEmerald",
	SkinEarthquakeMagma = "SkinRuptureMagma",
	SkinEarthquakeCrystal = "SkinRuptureCrystal",
	SkinWaterWaveJade = "SkinWashJade",
	SkinEarthSpikesObsidian = "SkinSerifObsidian",
	SkinWindGustSilver = "SkinSweepSilver",
	SkinEmberStormAzure = "SkinScorchAzure",
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

function LegacyNames.cosmetic(old: string): string
	return translate(LegacyNames.Cosmetics, old)
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
