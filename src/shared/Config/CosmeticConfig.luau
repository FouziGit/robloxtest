--!strict
-- Cosmetic catalog. Pure data. Cosmetics never affect gameplay.
-- Slots: Aura | Trail | KillEffect | Title | Skin (Skin applies to one glyph id via Target).
--
-- Every look obeys docs/ART_BIBLE.md, and that is a constraint on what a cosmetic may BE, not a style:
--   * rule 1, every saturated colour on screen belongs to a glyph -- so an aura, a trail or a kill effect
--     is drawn in the page's own inks (Tones below), never in a colour a player would read as a school;
--   * rule 2, a glyph is one pigment -- so a skin is a SHADE of its glyph's pigment (darker toward ink,
--     paler toward the page), never another hue: a blue Brand would be read as Indigo from thirty studs;
--   * rule 7, white means invulnerable -- so no tone is chalk-white.
-- Rarity is carried by craft: how many styles are layered and how they move, not by colour.
-- Ids are storage keys (profiles, passes, rewards) and keep their historical names; what a player sees
-- is the NameKey and the Look (docs/DECISIONS.md D-109).

export type Slot = "Aura" | "Trail" | "KillEffect" | "Title" | "Skin"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type Tone = "Ink" | "Graphite" | "Wash"
-- Styles are named in AuraStyles and TrailStyles below; CosmeticController owns what each one looks like.
export type Look = {
	Styles: { string }?, -- Aura, Trail: layered, most visible first
	Tone: Tone?, -- Aura, Trail
	Timeline: string?, -- KillEffect: a VfxTimelineConfig timeline
	TextKey: string?, -- Title: the words shown above the head
	Shade: number?, -- Skin: -1 toward ink .. +1 toward the page, inside PigmentConfig.ShadeRange
}
export type CosmeticDef = {
	Id: string,
	Slot: Slot,
	Rarity: Rarity,
	NameKey: string,
	Sellable: boolean, -- false = reward only (battle pass, season, pack)
	Target: string?, -- glyph id for skins
	Look: Look,
}

local CosmeticConfig = {}

CosmeticConfig.Items = {
	-- Battle pass free track
	{
		Id = "BlankHeadband",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.BlankHeadband",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.BlankHeadband" },
	},
	{
		Id = "SteelStylus",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.SteelStylus",
		Sellable = false,
		Look = { Styles = { "Hairline" }, Tone = "Graphite" },
	},
	{
		Id = "PalimpsestCape",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.PalimpsestCape",
		Sellable = false,
		Look = { Styles = { "Pages" }, Tone = "Wash" },
	},
	{
		Id = "FrisketMask",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.FrisketMask",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.FrisketMask" },
	},
	{
		Id = "BlueInkAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.BlueInkAura",
		Sellable = false,
		Look = { Styles = { "Drips", "Motes" }, Tone = "Ink" },
	},
	{
		Id = "ScriptoriumRobe",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.ScriptoriumRobe",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.ScriptoriumRobe" },
	},
	{
		Id = "VioletInkAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.VioletInkAura",
		Sellable = false,
		Look = { Styles = { "Wisps", "Motes" }, Tone = "Graphite" },
	},
	{
		Id = "ScribeCloak",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.ScribeCloak",
		Sellable = false,
		Look = { Styles = { "Stroke" }, Tone = "Ink" },
	},
	{
		Id = "GoldenInkAura",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.GoldenInkAura",
		Sellable = false,
		Look = { Styles = { "Orbit", "Motes" }, Tone = "Ink" },
	},
	{
		Id = "CodexCloak",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.CodexCloak",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.CodexCloak" },
	},
	-- Battle pass premium track
	{
		Id = "TrailEmber",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.TrailEmber",
		Sellable = false,
		Look = { Styles = { "Stroke", "Soot" }, Tone = "Ink" },
	},
	{
		Id = "AuraCrimson",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.AuraCrimson",
		Sellable = false,
		Look = { Styles = { "Wisps" }, Tone = "Ink" },
	},
	{
		Id = "KillEffectShatter",
		Slot = "KillEffect",
		Rarity = "Epic",
		NameKey = "cosmetic.KillEffectShatter",
		Sellable = false,
		Look = { Timeline = "KillTear" },
	},
	{
		Id = "TitleShadow",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleShadow",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleShadow" },
	},
	{
		Id = "SkinBrandAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinBrandAzure",
		Sellable = false,
		Target = "Brand",
		Look = { Shade = -0.25 },
	},
	{
		Id = "TrailStorm",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.TrailStorm",
		Sellable = false,
		Look = { Styles = { "Scrawl" }, Tone = "Graphite" },
	},
	{
		Id = "SkinRuptureMagma",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinRuptureMagma",
		Sellable = false,
		Target = "Rupture",
		Look = { Shade = -0.25 },
	},
	{
		Id = "KillEffectRedaction",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectRedaction",
		Sellable = false,
		Look = { Timeline = "KillRedaction" },
	},
	{
		Id = "TitleCodex",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleCodex",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleCodex" },
	},
	{
		Id = "AuraCodex",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraCodex",
		Sellable = false,
		Look = { Styles = { "Orbit", "Pages" }, Tone = "Ink" },
	},
	-- Season rewards
	{
		Id = "TitleScript",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleScript",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleScript" },
	},
	{
		Id = "TitleIllumination",
		Slot = "Title",
		Rarity = "Epic",
		NameKey = "cosmetic.TitleIllumination",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleIllumination" },
	},
	{
		Id = "TitleCodexSeason",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleCodexSeason",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleCodexSeason" },
	},
	-- Skin pack (game pass)
	{
		Id = "SkinWashJade",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinWashJade",
		Sellable = false,
		Target = "Wash",
		Look = { Shade = -0.25 },
	},
	{
		Id = "SkinSerifObsidian",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinSerifObsidian",
		Sellable = false,
		Target = "Serif",
		Look = { Shade = -0.25 },
	},
	{
		Id = "SkinSweepSilver",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinSweepSilver",
		Sellable = false,
		Target = "Sweep",
		Look = { Shade = 0.2 },
	},
	-- VIP game pass: the aura docs/ECONOMY.md and the pass description promise (MonetizationConfig.VipCosmetics).
	{
		Id = "VipAura",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.VipAura",
		Sellable = false,
		Look = { Styles = { "Orbit", "Wisps", "Motes" }, Tone = "Ink" },
	},
	-- Shop catalog (Folios or Robux)
	{
		Id = "TrailFolio",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailFolio",
		Sellable = true,
		Look = { Styles = { "Scraps" }, Tone = "Wash" },
	},
	{
		Id = "TrailSand",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailSand",
		Sellable = true,
		Look = { Styles = { "Dust" }, Tone = "Wash" },
	},
	{
		Id = "TitleRookie",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.TitleRookie",
		Sellable = true,
		Look = { TextKey = "cosmetic.title.TitleRookie" },
	},
	{
		Id = "TitleWanderer",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.TitleWanderer",
		Sellable = true,
		Look = { TextKey = "cosmetic.title.TitleWanderer" },
	},
	{
		Id = "AuraFrost",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.AuraFrost",
		Sellable = true,
		Look = { Styles = { "Motes" }, Tone = "Graphite" },
	},
	{
		Id = "AuraEmber",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.AuraEmber",
		Sellable = true,
		Look = { Styles = { "Soot" }, Tone = "Ink" },
	},
	{
		Id = "TrailViolet",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.TrailViolet",
		Sellable = true,
		Look = { Styles = { "Stroke", "Hairline" }, Tone = "Ink" },
	},
	{
		Id = "SkinBrandEmerald",
		Slot = "Skin",
		Rarity = "Rare",
		NameKey = "cosmetic.SkinBrandEmerald",
		Sellable = true,
		Target = "Brand",
		Look = { Shade = 0.2 },
	},
	{
		Id = "KillEffectPetals",
		Slot = "KillEffect",
		Rarity = "Epic",
		NameKey = "cosmetic.KillEffectPetals",
		Sellable = true,
		Look = { Timeline = "KillScraps", Tone = "Wash" },
	},
	{
		Id = "AuraStorm",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.AuraStorm",
		Sellable = true,
		Look = { Styles = { "Orbit" }, Tone = "Graphite" },
	},
	{
		Id = "SkinScorchAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinScorchAzure",
		Sellable = true,
		Target = "Scorch",
		Look = { Shade = -0.25 },
	},
	{
		Id = "AuraVoid",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraVoid",
		Sellable = true,
		Look = { Styles = { "Wisps", "Drips" }, Tone = "Ink" },
	},
	{
		Id = "KillEffectSupernova",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectSupernova",
		Sellable = true,
		Look = { Timeline = "KillOverexposure" },
	},
	{
		Id = "SkinRuptureCrystal",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinRuptureCrystal",
		Sellable = true,
		Target = "Rupture",
		Look = { Shade = 0.2 },
	},
} :: { CosmeticDef }

-- The page's inks, as RGB 0-255. Tints, never colours (tests/Cosmetics.spec.luau measures them), and
-- none of them white. Ink is WorldConfig.Colors.Ink; Graphite and Wash are the two greys between it and
-- the page, dark enough to be read on vellum.
CosmeticConfig.Tones = {
	Ink = { 23, 21, 15 },
	Graphite = { 74, 70, 63 },
	Wash = { 128, 120, 104 },
} :: { [string]: { number } }

-- What an aura or a trail may be made of. CosmeticController draws each one; tests/Cosmetics.spec.luau
-- holds the two lists, the catalogue and the renderer to each other.
CosmeticConfig.AuraStyles = { "Motes", "Wisps", "Drips", "Pages", "Soot", "Orbit" }
CosmeticConfig.TrailStyles = { "Stroke", "Hairline", "Scrawl", "Soot", "Scraps", "Dust" }

-- A skin's Look.Shade moves its glyph's pigment toward ink or page, inside PigmentConfig.ShadeRange: the
-- measured range in which every school stays its own (PigmentConfig.shade).

CosmeticConfig.ById = {} :: { [string]: CosmeticDef }
for _, item in ipairs(CosmeticConfig.Items) do
	CosmeticConfig.ById[item.Id] = item
end

CosmeticConfig.Slots = { "Aura", "Trail", "KillEffect", "Title", "Skin" } :: { Slot }

-- Equipped slot key for a cosmetic (skins are per glyph).
function CosmeticConfig.slotKey(item: CosmeticDef): string
	if item.Slot == "Skin" then
		return "Skin:" .. tostring(item.Target)
	end
	return item.Slot
end

return CosmeticConfig
