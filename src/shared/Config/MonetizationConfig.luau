--!strict
-- Every Roblox asset id lives here and only here. Fill the Id fields from the Creator Dashboard
-- (see docs/STUDIO_SETUP.md). MonetizationService validates this table at startup and warns for
-- each Id left at 0. Prices are informational (the Dashboard is the source of truth).

export type PassDef = { Id: number, PriceRobux: number, NameKey: string, DescKey: string }
export type ProductKind = "Ryo" | "PremiumPass" | "TierSkip" | "XpBoost" | "Cosmetic"
export type ProductDef = {
	Id: number,
	PriceRobux: number,
	Kind: ProductKind,
	Amount: number?, -- Ryo amount / tiers
	Minutes: number?, -- XpBoost
	Rarity: string?, -- Cosmetic
	NameKey: string,
	DescKey: string,
}

local MonetizationConfig = {}

MonetizationConfig.Passes = {
	Vip = { Id = 0, PriceRobux = 399, NameKey = "pass.vip", DescKey = "pass.vip.desc" },
	LoadoutSlots = { Id = 0, PriceRobux = 199, NameKey = "pass.loadoutSlots", DescKey = "pass.loadoutSlots.desc" },
	Lightning = { Id = 0, PriceRobux = 299, NameKey = "pass.lightning", DescKey = "pass.lightning.desc" },
	SkinPack = { Id = 0, PriceRobux = 249, NameKey = "pass.skinPack", DescKey = "pass.skinPack.desc" },
} :: { [string]: PassDef }

-- Cosmetics granted by the SkinPack pass.
MonetizationConfig.SkinPackCosmetics = {
	"SkinFireballAzure",
	"SkinWaterWaveJade",
	"SkinEarthSpikesObsidian",
	"SkinWindGustSilver",
} :: { string }

MonetizationConfig.Products = {
	RyoSmall = {
		Id = 0,
		PriceRobux = 99,
		Kind = "Ryo",
		Amount = 1000,
		NameKey = "product.ryoSmall",
		DescKey = "product.ryo.desc",
	},
	RyoMedium = {
		Id = 0,
		PriceRobux = 299,
		Kind = "Ryo",
		Amount = 3500,
		NameKey = "product.ryoMedium",
		DescKey = "product.ryo.desc",
	},
	RyoLarge = {
		Id = 0,
		PriceRobux = 599,
		Kind = "Ryo",
		Amount = 8000,
		NameKey = "product.ryoLarge",
		DescKey = "product.ryo.desc",
	},
	PremiumPass = {
		Id = 0,
		PriceRobux = 349,
		Kind = "PremiumPass",
		NameKey = "product.premiumPass",
		DescKey = "product.premiumPass.desc",
	},
	TierSkip5 = {
		Id = 0,
		PriceRobux = 149,
		Kind = "TierSkip",
		Amount = 5,
		NameKey = "product.tierSkip5",
		DescKey = "product.tierSkip5.desc",
	},
	XpBoost1h = {
		Id = 0,
		PriceRobux = 79,
		Kind = "XpBoost",
		Minutes = 60,
		NameKey = "product.xpBoost1h",
		DescKey = "product.xpBoost1h.desc",
	},
	CosmeticCommon = {
		Id = 0,
		PriceRobux = 49,
		Kind = "Cosmetic",
		Rarity = "Common",
		NameKey = "product.cosmetic",
		DescKey = "product.cosmetic.desc",
	},
	CosmeticRare = {
		Id = 0,
		PriceRobux = 149,
		Kind = "Cosmetic",
		Rarity = "Rare",
		NameKey = "product.cosmetic",
		DescKey = "product.cosmetic.desc",
	},
	CosmeticEpic = {
		Id = 0,
		PriceRobux = 349,
		Kind = "Cosmetic",
		Rarity = "Epic",
		NameKey = "product.cosmetic",
		DescKey = "product.cosmetic.desc",
	},
	CosmeticLegendary = {
		Id = 0,
		PriceRobux = 699,
		Kind = "Cosmetic",
		Rarity = "Legendary",
		NameKey = "product.cosmetic",
		DescKey = "product.cosmetic.desc",
	},
} :: { [string]: ProductDef }

-- Contextual prompt rules (see docs/ECONOMY.md §5).
MonetizationConfig.Prompts = {
	FirstSessionGraceSeconds = 180, -- never prompt during the first 3 minutes of the first session
	MinIntervalSeconds = 300, -- at most one prompt every 5 minutes
	CloseLossHealthFraction = 0.15, -- "close loss" threshold for the XP boost prompt
	CloseLossCooldownSeconds = 1800,
	LightningDeathMinLevel = 10,
	LightningDeathPerSession = 1,
}

-- Keys whose Id is still 0.
function MonetizationConfig.missingIds(): { string }
	local missing = {}
	for key, pass in pairs(MonetizationConfig.Passes) do
		if pass.Id == 0 then
			table.insert(missing, "Passes." .. key)
		end
	end
	for key, product in pairs(MonetizationConfig.Products) do
		if product.Id == 0 then
			table.insert(missing, "Products." .. key)
		end
	end
	table.sort(missing)
	return missing
end

function MonetizationConfig.productByAssetId(assetId: number): (string?, ProductDef?)
	if assetId == 0 then
		return nil, nil
	end
	for key, product in pairs(MonetizationConfig.Products) do
		if product.Id == assetId then
			return key, product
		end
	end
	return nil, nil
end

function MonetizationConfig.passByAssetId(assetId: number): (string?, PassDef?)
	if assetId == 0 then
		return nil, nil
	end
	for key, pass in pairs(MonetizationConfig.Passes) do
		if pass.Id == assetId then
			return key, pass
		end
	end
	return nil, nil
end

return MonetizationConfig
