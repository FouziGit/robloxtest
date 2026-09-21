--!strict
-- Cosmetic catalog. Pure data. Cosmetics never affect gameplay; VfxLibrary reads the visual params.
-- Slots: Aura | Trail | KillEffect | Title | Skin (Skin applies to one glyph id via Target).

export type Slot = "Aura" | "Trail" | "KillEffect" | "Title" | "Skin"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type CosmeticDef = {
	Id: string,
	Slot: Slot,
	Rarity: Rarity,
	NameKey: string,
	Sellable: boolean, -- false = reward only (battle pass, season, pack)
	Target: string?, -- glyph id for skins
	Visual: { [string]: number }, -- colors as R/G/B components or numeric parameters
}

local CosmeticConfig = {}

local function rgb(prefix: string, r: number, g: number, b: number): { [string]: number }
	return { [prefix .. "R"] = r, [prefix .. "G"] = g, [prefix .. "B"] = b }
end

CosmeticConfig.Items = {
	-- Battle pass free track
	{
		Id = "BlankHeadband",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.BlankHeadband",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "SteelStylus",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.SteelStylus",
		Sellable = false,
		Visual = rgb("Color", 200, 200, 210),
	},
	{
		Id = "PalimpsestCape",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.PalimpsestCape",
		Sellable = false,
		Visual = rgb("Color", 180, 200, 220),
	},
	{
		Id = "FrisketMask",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.FrisketMask",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "BlueInkAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.BlueInkAura",
		Sellable = false,
		Visual = rgb("Color", 80, 160, 255),
	},
	{
		Id = "ScriptoriumRobe",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.ScriptoriumRobe",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "VioletInkAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.VioletInkAura",
		Sellable = false,
		Visual = rgb("Color", 170, 90, 255),
	},
	{
		Id = "ScribeCloak",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.ScribeCloak",
		Sellable = false,
		Visual = rgb("Color", 230, 150, 60),
	},
	{
		Id = "GoldenInkAura",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.GoldenInkAura",
		Sellable = false,
		Visual = rgb("Color", 255, 215, 90),
	},
	{
		Id = "CodexCloak",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.CodexCloak",
		Sellable = false,
		Visual = {},
	},
	-- Battle pass premium track
	{
		Id = "TrailEmber",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.TrailEmber",
		Sellable = false,
		Visual = rgb("Color", 255, 120, 40),
	},
	{
		Id = "AuraCrimson",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.AuraCrimson",
		Sellable = false,
		Visual = rgb("Color", 220, 40, 60),
	},
	{
		Id = "KillEffectShatter",
		Slot = "KillEffect",
		Rarity = "Epic",
		NameKey = "cosmetic.KillEffectShatter",
		Sellable = false,
		Visual = rgb("Color", 200, 230, 255),
	},
	{
		Id = "TitleShadow",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleShadow",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "SkinBrandAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinBrandAzure",
		Sellable = false,
		Target = "Brand",
		Visual = rgb("Color", 60, 140, 255),
	},
	{
		Id = "TrailStorm",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.TrailStorm",
		Sellable = false,
		Visual = rgb("Color", 120, 200, 255),
	},
	{
		Id = "SkinRuptureMagma",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinRuptureMagma",
		Sellable = false,
		Target = "Rupture",
		Visual = rgb("Color", 255, 90, 20),
	},
	{
		Id = "KillEffectRedaction",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectRedaction",
		Sellable = false,
		Visual = rgb("Color", 255, 240, 120),
	},
	{
		Id = "TitleCodex",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleCodex",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "AuraCodex",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraCodex",
		Sellable = false,
		Visual = rgb("Color", 255, 180, 60),
	},
	-- Season rewards
	{
		Id = "TitleScript",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleScript",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "TitleIllumination",
		Slot = "Title",
		Rarity = "Epic",
		NameKey = "cosmetic.TitleIllumination",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "TitleCodexSeason",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleCodexSeason",
		Sellable = false,
		Visual = {},
	},
	-- Skin pack (game pass)
	{
		Id = "SkinWashJade",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinWashJade",
		Sellable = false,
		Target = "Wash",
		Visual = rgb("Color", 60, 220, 160),
	},
	{
		Id = "SkinSerifObsidian",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinSerifObsidian",
		Sellable = false,
		Target = "Serif",
		Visual = rgb("Color", 40, 30, 50),
	},
	{
		Id = "SkinSweepSilver",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinSweepSilver",
		Sellable = false,
		Target = "Sweep",
		Visual = rgb("Color", 220, 225, 235),
	},
	-- Shop catalog (Folios or Robux)
	{
		Id = "TrailFolio",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailFolio",
		Sellable = true,
		Visual = rgb("Color", 110, 200, 90),
	},
	{
		Id = "TrailSand",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailSand",
		Sellable = true,
		Visual = rgb("Color", 225, 200, 140),
	},
	{
		Id = "TitleRookie",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.TitleRookie",
		Sellable = true,
		Visual = {},
	},
	{
		Id = "TitleWanderer",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.TitleWanderer",
		Sellable = true,
		Visual = {},
	},
	{
		Id = "AuraFrost",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.AuraFrost",
		Sellable = true,
		Visual = rgb("Color", 170, 220, 255),
	},
	{
		Id = "AuraEmber",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.AuraEmber",
		Sellable = true,
		Visual = rgb("Color", 255, 140, 60),
	},
	{
		Id = "TrailViolet",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.TrailViolet",
		Sellable = true,
		Visual = rgb("Color", 180, 100, 255),
	},
	{
		Id = "SkinBrandEmerald",
		Slot = "Skin",
		Rarity = "Rare",
		NameKey = "cosmetic.SkinBrandEmerald",
		Sellable = true,
		Target = "Brand",
		Visual = rgb("Color", 60, 200, 120),
	},
	{
		Id = "KillEffectPetals",
		Slot = "KillEffect",
		Rarity = "Epic",
		NameKey = "cosmetic.KillEffectPetals",
		Sellable = true,
		Visual = rgb("Color", 255, 170, 200),
	},
	{
		Id = "AuraStorm",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.AuraStorm",
		Sellable = true,
		Visual = rgb("Color", 90, 150, 255),
	},
	{
		Id = "SkinScorchAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinScorchAzure",
		Sellable = true,
		Target = "Scorch",
		Visual = rgb("Color", 60, 140, 255),
	},
	{
		Id = "AuraVoid",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraVoid",
		Sellable = true,
		Visual = rgb("Color", 40, 20, 60),
	},
	{
		Id = "KillEffectSupernova",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectSupernova",
		Sellable = true,
		Visual = rgb("Color", 255, 230, 150),
	},
	{
		Id = "SkinRuptureCrystal",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinRuptureCrystal",
		Sellable = true,
		Target = "Rupture",
		Visual = rgb("Color", 150, 230, 255),
	},
} :: { CosmeticDef }

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
