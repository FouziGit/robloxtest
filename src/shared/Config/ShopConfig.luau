--!strict
-- Cosmetic shop: Ryo prices by rarity, daily rotation, Robux equivalents. Pure data.

local ShopConfig = {}

ShopConfig.PriceRyo = { Common = 600, Rare = 1800, Epic = 4000, Legendary = 8000 } :: { [string]: number }

-- Developer product key (MonetizationConfig.Products) that buys one item of the rarity with Robux.
ShopConfig.RobuxProduct = {
	Common = "CosmeticCommon",
	Rare = "CosmeticRare",
	Epic = "CosmeticEpic",
	Legendary = "CosmeticLegendary",
} :: { [string]: string }

-- Items shown per day, by rarity (deterministic per day, see ShopRotation).
ShopConfig.Rotation = { Common = 2, Rare = 2, Epic = 1, Legendary = 1 } :: { [string]: number }
ShopConfig.RarityOrder = { "Legendary", "Epic", "Rare", "Common" } :: { string }

-- Seconds a Robux purchase intent for a specific item stays valid.
ShopConfig.PurchaseIntentSeconds = 600

return ShopConfig
