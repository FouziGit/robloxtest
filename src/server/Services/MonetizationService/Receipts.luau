--!strict
-- Developer product receipts. Pure/ReceiptProcessor owns the idempotence decision; this module only
-- provides the side effects it asks for (find the product, read the profile, check and record the
-- purchase id, grant, save, log) and translates its verdict into an Enum.ProductPurchaseDecision.
--
-- Anything that cannot be granted returns NotProcessedYet, which makes a half-applied purchase
-- impossible. It is NOT free: the Robux are debited when the player confirms the dialog, and
-- NotProcessedYet only leaves the transaction pending, with Roblox re-delivering the receipt. A path
-- that can never succeed therefore loops for ever on a purchase the player already paid for, so every
-- refusal here must be a transient failure and never a permanent one. Two consequences enforced below.
-- What a receipt can no longer deliver is paid in Folios instead of refused (D-202): a cosmetic of a
-- rarity the player owns entirely, at its shop price (after ShopService.resolveReceiptItem found nothing);
-- a tier past the last one, which the pass may have reached while the dialog was open; a Premium Pass for a
-- player who already has the track (both at the product's CompensationFolios). And PurchaseGranted is
-- only returned once DataService.saveNow confirms the write.
--
-- A Studio test receipt is the one exception, and grants nothing: Roblox charged nothing for it, and its
-- grant would land in the player's real profile (Sandbox, D-211). It is acknowledged, so it is not delivered
-- again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local Context = require(script.Parent.Context)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local ReceiptProcessor = require(Shared.Pure.ReceiptProcessor)
local Sandbox = require(script.Parent.Sandbox)
local ShopConfig = require(Shared.Config.ShopConfig)

local log = Log.new("MonetizationService")

type Deps = Context.Deps
type ProfileData = Context.ProfileData

local Receipts = {}

local deps: Deps

-- XP to hand to BattlepassService so the pass advances exactly `tiers` tiers, plus the number of tiers
-- that fit below MaxTier. BattlepassService has no "skip tiers" entry point, and its cascade consumes
-- xpForTier(tier) per tier, so the exact sum of the crossed tiers' costs lands on the target tier and
-- keeps the partial XP the player already had (xpForTier grows with the tier, so nothing over-cascades).
local function tierSkipXp(data: ProfileData, tiers: number): (number, number)
	local season = Context.seasonOf(data)
	if season == nil then
		return 0, 0
	end
	local granted = math.min(tiers, BattlepassConfig.MaxTier - season.Tier)
	if granted <= 0 then
		return 0, 0
	end
	local xp = 0
	for step = 0, granted - 1 do
		xp += BattlepassConfig.xpForTier(season.Tier + step)
	end
	return xp, granted
end

local function grantFolios(player: Player, productKey: string, amount: number, nameKey: string): boolean
	if deps.Currency.add(player, amount, "Product:" .. productKey) <= 0 then
		return false
	end
	deps.Notify.send(player, "purchase.granted", { name = nameKey }, "Success", Context.SfxSuccess)
	return true
end

-- Pays `units` units of `productKey` that its receipt can no longer deliver, at the product's
-- CompensationFolios each (D-202). Returns the Folios credited, 0 when nothing could be paid.
local function compensate(player: Player, productKey: string, def: MonetizationConfig.ProductDef, units: number): number
	local rate = def.CompensationFolios
	if rate == nil or rate <= 0 then
		log.error("product %s has no CompensationFolios for %d undeliverable unit(s)", productKey, units)
		return 0
	end
	local credited = deps.Currency.add(player, rate * units, "Product:" .. productKey .. ":Compensation")
	if credited <= 0 then
		return 0
	end
	log.info("%s could not receive %d unit(s) of %s: paid %d Folios instead", player.Name, units, productKey, credited)
	return credited
end

-- Grants one cosmetic of the rarity the player paid for: the item they picked before opening the
-- dialog when it still applies, otherwise the first unowned item of that rarity (ShopService resolves
-- the preference order). The Robux are debited at confirmation, so this must never refuse: a refusal
-- returns NotProcessedYet and Roblox re-delivers the same receipt for ever.
--
-- When the player owns every sellable item of the rarity there is nothing left to hand over, so the
-- transaction is completed in Folios at that rarity's shop price instead of looping.
local function grantCosmetic(player: Player, rarity: string?): boolean
	local price = if rarity ~= nil then ShopConfig.PriceFolios[rarity] else nil
	if rarity == nil or price == nil then
		log.error("cosmetic product has no usable rarity: %s", tostring(rarity))
		return false
	end
	local cosmeticId = deps.Shop.resolveReceiptItem(player, rarity)
	if cosmeticId == nil then
		log.warn("%s owns every sellable %s item: paying %d Folios instead", player.Name, rarity, price)
		if deps.Currency.add(player, price, "Product:Cosmetic" .. rarity) <= 0 then
			return false
		end
		deps.Notify.send(player, "purchase.grantedFoliosInstead", { amount = price }, "Success", Context.SfxSuccess)
		return true
	end
	local item = CosmeticConfig.ById[cosmeticId]
	if item == nil then
		log.error("resolveReceiptItem returned the unknown cosmetic %s", cosmeticId)
		return false
	end
	if not log.succeeded("cosmetic grant " .. cosmeticId, deps.Cosmetic.grant, player, cosmeticId) then
		return false
	end
	deps.Shop.clearPurchaseIntent(player, cosmeticId)
	deps.Notify.send(player, "purchase.granted", { name = item.NameKey }, "Success", Context.SfxSuccess)
	deps.Shop.refresh(player)
	return true
end

-- Applies one product to a loaded profile. Returns false when nothing could be granted.
local function grantProduct(
	player: Player,
	data: ProfileData,
	productKey: string,
	product: ReceiptProcessor.ProductDef
): boolean
	local def = MonetizationConfig.Products[productKey]
	if def == nil then
		log.error("receipt for unknown product key %s", productKey)
		return false
	end

	local granted = false
	if product.Kind == "Folios" then
		local amount = product.Amount
		if amount == nil or amount <= 0 then
			log.error("product %s has no Folios amount", productKey)
			return false
		end
		granted = grantFolios(player, productKey, amount, def.NameKey)
	elseif product.Kind == "PremiumPass" then
		if deps.Battlepass.isPremium(player) then
			-- Purchases refuses the dialog to a Premium player, but a receipt can still land on one: a second
			-- dialog confirmed before the first receipt arrived, or a receipt delivered late. The track cannot
			-- be given twice, so the pass is paid in Folios (D-202).
			local credited = compensate(player, productKey, def, 1)
			if credited <= 0 then
				return false
			end
			deps.Notify.send(
				player,
				"purchase.premiumOwnedFolios",
				{ amount = credited },
				"Success",
				Context.SfxSuccess
			)
		else
			deps.Battlepass.setPremium(player, true)
			deps.Notify.send(player, "purchase.passGranted", { name = def.NameKey }, "Success", Context.SfxSuccess)
		end
		granted = true
	elseif product.Kind == "TierSkip" then
		local tiers = product.Amount
		if tiers == nil or tiers <= 0 then
			log.error("product %s has no tier amount", productKey)
			return false
		end
		-- The pass may have reached the last tier since the dialog opened (Purchases only refuses at the
		-- last tier when it opens), or sit fewer than `tiers` below it. Whatever does not fit is paid in
		-- Folios, and first: a refused credit then returns before any tier moved, so the retried receipt
		-- starts from the same pass and cannot grant a tier twice.
		local xp, tiersGranted = tierSkipXp(data, tiers)
		local owed = tiers - tiersGranted
		local credited = 0
		if owed > 0 then
			credited = compensate(player, productKey, def, owed)
			if credited <= 0 then
				return false
			end
		end
		if xp > 0 then
			deps.Battlepass.addXp(player, xp)
			deps.Notify.send(player, "purchase.tiersGranted", { tiers = tiersGranted }, "Success", Context.SfxTierUp)
		end
		if credited > 0 then
			deps.Notify.send(player, "purchase.tiersPastLast", { amount = credited }, "Success", Context.SfxSuccess)
		end
		granted = true
	elseif product.Kind == "XpBoost" then
		local minutes = product.Minutes
		if minutes == nil or minutes <= 0 then
			log.error("product %s has no boost duration", productKey)
			return false
		end
		-- BattlepassService is the single writer of Boosts (docs/DECISIONS.md D-26): it extends a live
		-- boost instead of shortening it, and applies ProgressionConfig.XpBoostMultiplier.
		if not deps.Battlepass.grantXpBoost(player, minutes) then
			log.error("grantXpBoost refused %d minute(s) for %s", minutes, player.Name)
			return false
		end
		deps.Notify.send(player, "purchase.boostActive", { minutes = minutes }, "Success", Context.SfxSuccess)
		granted = true
	elseif product.Kind == "Cosmetic" then
		granted = grantCosmetic(player, product.Rarity)
	else
		log.error("product %s has unknown kind %s", productKey, tostring(product.Kind))
		return false
	end

	if not granted then
		return false
	end
	local counts = data.Purchases.ProductCounts
	counts[productKey] = (counts[productKey] or 0) + 1
	deps.DataService.push(player, "Purchases")
	deps.Analytics.custom(player, "ProductPurchased", def.PriceRobux, deps.Analytics.fields(productKey))
	log.info("%s received %s", player.Name, productKey)
	return true
end

-- Side effects handed to the pure processor, bound to the player the receipt belongs to.
local function processorFor(player: Player): ReceiptProcessor.Deps
	return {
		findProduct = function(productId: number): (string?, ReceiptProcessor.ProductDef?)
			local productKey, product = MonetizationConfig.productByAssetId(productId)
			return productKey, (product :: any) :: ReceiptProcessor.ProductDef?
		end,
		getProfile = function(_userId: number): any?
			return deps.DataService.waitFor(player, GameConfig.Server.ProfileLoadTimeoutSeconds)
		end,
		isRecorded = function(data: any, purchaseId: string): boolean
			return table.find((data :: ProfileData).Purchases.Receipts, purchaseId) ~= nil
		end,
		record = function(_data: any, purchaseId: string)
			deps.DataService.recordReceipt(player, purchaseId)
		end,
		grant = function(
			data: any,
			productKey: string,
			product: ReceiptProcessor.ProductDef,
			_receipt: ReceiptProcessor.Receipt
		): boolean
			return grantProduct(player, data :: ProfileData, productKey, product)
		end,
		save = function(_userId: number): boolean
			if not deps.DataService.isActive(player) then
				return false
			end
			-- succeeded, not try: try returns pcall's ok, i.e. "the call did not throw", which is exactly
			-- the thing this path must never confuse with "the write landed".
			return log.succeeded("saveNow " .. player.Name, deps.DataService.saveNow, player)
		end,
		log = function(message: string)
			log.warn("receipt: %s", message)
		end,
	}
end

-- MarketplaceService.ProcessReceipt handler.
function Receipts.process(receiptInfo: { [string]: any })
	local userId = tonumber(receiptInfo.PlayerId)
	local productId = tonumber(receiptInfo.ProductId)
	local purchaseId = receiptInfo.PurchaseId
	if userId == nil or productId == nil or type(purchaseId) ~= "string" then
		log.error("malformed receipt dropped (player %s, product %s)", tostring(userId), tostring(productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		-- Bought offline or on another server: Roblox delivers the receipt again on the next join.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if Sandbox.active() then
		local productKey, product = MonetizationConfig.productByAssetId(productId)
		-- A product this game does not sell goes the normal way, which refuses it.
		if productKey ~= nil and product ~= nil then
			Sandbox.acknowledge(player, "product " .. productKey, product.NameKey)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local receipt: ReceiptProcessor.Receipt = { PlayerId = userId, PurchaseId = purchaseId, ProductId = productId }
	local ok, decision, detail = pcall(ReceiptProcessor.process, receipt, processorFor(player))
	if not ok then
		log.error("receipt %s failed for %s: %s", purchaseId, player.Name, tostring(decision))
		deps.Notify.send(player, "purchase.failed", nil, "Error", Context.SfxError)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if decision ~= "PurchaseGranted" then
		log.warn("receipt %s for %s not processed: %s", purchaseId, player.Name, tostring(detail))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Receipts.Init(injected: Deps)
	deps = injected
end

return Receipts
