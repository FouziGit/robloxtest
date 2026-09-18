--!strict
-- Opening a Roblox purchase dialog. The client names a catalog entry (a pass key, a product key, or a
-- cosmetic id of today's rotation) and the server resolves the asset id: no id ever crosses the wire.
--
-- Cosmetic developer products are generic per rarity, so naming a cosmetic first records the shop
-- purchase intent (ShopService) that the receipt will consume.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Context = require(script.Parent.Context)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Log = require(Shared.Util.Log)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)

local log = Log.new("MonetizationService")

type Deps = Context.Deps

local Purchases = {}

local deps: Deps

local function refuse(player: Player, key: string, reason: string)
	log.warn("purchase refused for %s: %s", player.Name, reason)
	deps.Notify.send(player, key, nil, "Error", Context.SfxError)
end

local function promptPass(player: Player, passKey: string)
	local pass = MonetizationConfig.Passes[passKey]
	if pass == nil then
		refuse(player, "purchase.unavailable", "unknown pass key " .. passKey)
		return
	end
	if pass.Id == 0 then
		refuse(player, "purchase.unavailable", "pass " .. passKey .. " has no id yet")
		return
	end
	local data = deps.DataService.get(player)
	if data ~= nil and data.Passes[passKey] == true then
		deps.Notify.send(player, "purchase.alreadyOwned", nil, "Info")
		return
	end
	local opened = log.try("PromptGamePassPurchase " .. passKey, function()
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
	if not opened then
		deps.Notify.send(player, "purchase.failed", nil, "Error", Context.SfxError)
		return
	end
	deps.Notify.send(player, "purchase.prompt", nil, "Info")
end

-- Resolves a developer product key from what the client named. A cosmetic id records the shop intent
-- first. Returns nil plus the Strings key of the refusal.
local function resolveProductKey(player: Player, key: string): (string?, string?)
	if MonetizationConfig.Products[key] ~= nil then
		return key, nil
	end
	if CosmeticConfig.ById[key] == nil then
		return nil, "purchase.unavailable"
	end
	local productKey, reason = deps.Shop.setPurchaseIntent(player, key)
	if productKey == nil then
		return nil, reason or "purchase.unavailable"
	end
	return productKey, nil
end

local function promptProduct(player: Player, key: string)
	local productKey, refusal = resolveProductKey(player, key)
	if productKey == nil then
		refuse(player, refusal or "purchase.unavailable", "entry " .. key .. " is not purchasable")
		return
	end
	local product = MonetizationConfig.Products[productKey]
	if product == nil then
		refuse(player, "purchase.unavailable", "unknown product key " .. productKey)
		return
	end
	if product.Id == 0 then
		refuse(player, "purchase.unavailable", "product " .. productKey .. " has no id yet")
		return
	end
	local data = deps.DataService.get(player)
	if data == nil then
		refuse(player, "purchase.failed", "profile not loaded")
		return
	end
	-- A rarity product alone says nothing about which item to grant: the player must have picked one.
	if product.Kind == "Cosmetic" and deps.Shop.getPurchaseIntent(player) == nil then
		refuse(player, "purchase.unavailable", "no cosmetic picked for " .. productKey)
		return
	end
	if product.Kind == "PremiumPass" and deps.Battlepass.isPremium(player) then
		deps.Notify.send(player, "purchase.alreadyOwned", nil, "Info")
		return
	end
	if product.Kind == "TierSkip" and Context.atMaxTier(data) then
		refuse(player, "purchase.unavailable", "battle pass already at max tier")
		return
	end
	local opened = log.try("PromptProductPurchase " .. productKey, function()
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
	if not opened then
		deps.Notify.send(player, "purchase.failed", nil, "Error", Context.SfxError)
		return
	end
	deps.Notify.send(player, "purchase.prompt", nil, "Info")
end

-- Opens the Roblox purchase dialog for a catalog entry.
function Purchases.prompt(player: Player, kind: Context.PurchaseKind, key: string)
	if kind == "Pass" then
		promptPass(player, key)
	elseif kind == "Cosmetic" then
		-- The shop validates the item (in today's rotation, sellable, not owned), records which one the
		-- player wants and answers with the product that sells that rarity.
		local productKey, reasonKey = deps.Shop.setPurchaseIntent(player, key)
		if productKey == nil then
			deps.Notify.send(player, reasonKey or "purchase.unavailable", nil, "Error")
			return
		end
		promptProduct(player, productKey)
	else
		promptProduct(player, key)
	end
end

-- A product dialog closed: the grant itself happens in the receipt, this only records the outcome.
function Purchases.onPurchaseFinished(userId: number, productId: number, wasPurchased: boolean)
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end
	local productKey = MonetizationConfig.productByAssetId(productId)
	if productKey == nil then
		return
	end
	local event = if wasPurchased then Context.EventPromptAccepted else Context.EventPromptDeclined
	deps.Analytics.custom(player, event, nil, { product = productKey })
end

function Purchases.Init(injected: Deps)
	deps = injected
end

return Purchases
