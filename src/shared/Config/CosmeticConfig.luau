--!strict
-- Cosmetic catalog. Pure data. Cosmetics never affect gameplay; VfxLibrary reads the visual params.
-- Slots: Aura | Trail | KillEffect | Title | Skin (Skin applies to one jutsu id via Target).

export type Slot = "Aura" | "Trail" | "KillEffect" | "Title" | "Skin"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type CosmeticDef = {
	Id: string,
	Slot: Slot,
	Rarity: Rarity,
	NameKey: string,
	Sellable: boolean, -- false = reward only (battle pass, season, pack)
	Target: string?, -- jutsu id for skins
	Visual: { [string]: number }, -- colors as R/G/B components or numeric parameters
}

local CosmeticConfig = {}

local function rgb(prefix: string, r: number, g: number, b: number): { [string]: number }
	return { [prefix .. "R"] = r, [prefix .. "G"] = g, [prefix .. "B"] = b }
end

CosmeticConfig.Items = {
	-- Battle pass free track
	{
		Id = "GeninHeadband",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.GeninHeadband",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "SteelKatana",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.SteelKatana",
		Sellable = false,
		Visual = rgb("Color", 200, 200, 210),
	},
	{
		Id = "MistCape",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.MistCape",
		Sellable = false,
		Visual = rgb("Color", 180, 200, 220),
	},
	{ Id = "AnbuMask", Slot = "Title", Rarity = "Rare", NameKey = "cosmetic.AnbuMask", Sellable = false, Visual = {} },
	{
		Id = "BlueChakraAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.BlueChakraAura",
		Sellable = false,
		Visual = rgb("Color", 80, 160, 255),
	},
	{
		Id = "ClanKimono",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.ClanKimono",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "VioletChakraAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.VioletChakraAura",
		Sellable = false,
		Visual = rgb("Color", 170, 90, 255),
	},
	{
		Id = "SageCloak",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.SageCloak",
		Sellable = false,
		Visual = rgb("Color", 230, 150, 60),
	},
	{
		Id = "GoldenChakraAura",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.GoldenChakraAura",
		Sellable = false,
		Visual = rgb("Color", 255, 215, 90),
	},
	{
		Id = "HokageCloak",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.HokageCloak",
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
		Id = "SkinFireballAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinFireballAzure",
		Sellable = false,
		Target = "Fireball",
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
		Id = "SkinEarthquakeMagma",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinEarthquakeMagma",
		Sellable = false,
		Target = "Earthquake",
		Visual = rgb("Color", 255, 90, 20),
	},
	{
		Id = "KillEffectLightning",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectLightning",
		Sellable = false,
		Visual = rgb("Color", 255, 240, 120),
	},
	{
		Id = "TitleKage",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleKage",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "AuraHokage",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraHokage",
		Sellable = false,
		Visual = rgb("Color", 255, 180, 60),
	},
	-- Season rewards
	{
		Id = "TitleJonin",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleJonin",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "TitleAnbu",
		Slot = "Title",
		Rarity = "Epic",
		NameKey = "cosmetic.TitleAnbu",
		Sellable = false,
		Visual = {},
	},
	{
		Id = "TitleKageSeason",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleKageSeason",
		Sellable = false,
		Visual = {},
	},
	-- Skin pack (game pass)
	{
		Id = "SkinWaterWaveJade",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinWaterWaveJade",
		Sellable = false,
		Target = "WaterWave",
		Visual = rgb("Color", 60, 220, 160),
	},
	{
		Id = "SkinEarthSpikesObsidian",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinEarthSpikesObsidian",
		Sellable = false,
		Target = "EarthSpikes",
		Visual = rgb("Color", 40, 30, 50),
	},
	{
		Id = "SkinWindGustSilver",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinWindGustSilver",
		Sellable = false,
		Target = "WindGust",
		Visual = rgb("Color", 220, 225, 235),
	},
	-- Shop catalog (Ryo or Robux)
	{
		Id = "TrailLeaf",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailLeaf",
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
		Id = "SkinFireballEmerald",
		Slot = "Skin",
		Rarity = "Rare",
		NameKey = "cosmetic.SkinFireballEmerald",
		Sellable = true,
		Target = "Fireball",
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
		Id = "SkinEmberStormAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinEmberStormAzure",
		Sellable = true,
		Target = "EmberStorm",
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
		Id = "SkinEarthquakeCrystal",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinEarthquakeCrystal",
		Sellable = true,
		Target = "Earthquake",
		Visual = rgb("Color", 150, 230, 255),
	},
} :: { CosmeticDef }

CosmeticConfig.ById = {} :: { [string]: CosmeticDef }
for _, item in ipairs(CosmeticConfig.Items) do
	CosmeticConfig.ById[item.Id] = item
end

CosmeticConfig.Slots = { "Aura", "Trail", "KillEffect", "Title", "Skin" } :: { Slot }

-- Equipped slot key for a cosmetic (skins are per jutsu).
function CosmeticConfig.slotKey(item: CosmeticDef): string
	if item.Slot == "Skin" then
		return "Skin:" .. tostring(item.Target)
	end
	return item.Slot
end

return CosmeticConfig
