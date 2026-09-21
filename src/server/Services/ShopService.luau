--!strict
-- ShopService: today's cosmetic rotation and its two payment paths. The rotation is deterministic
-- (Pure/ShopRotation, seeded by the UTC day key), recomputed when the day key changes on a single
-- Heartbeat accumulator, and replicated as a Types.ShopSnapshot with ownership resolved for each
-- receiver (ShopChanged) on join, on every rotation and on every ownership change.
--
-- Folios purchases are settled here: the server checks the rotation, the Sellable flag, ownership and the
-- price from ShopConfig, then debits through CurrencyService and grants through CosmeticService. The
-- client only ever names a cosmetic id.
--
-- The Robux path needs to know which item the player picked, because the developer products are
-- generic per rarity (MonetizationConfig.Products.Cosmetic*). ShopService records that choice as a
-- purchase intent, valid ShopConfig.PurchaseIntentSeconds, and MonetizationService consumes it when
-- the receipt arrives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local ReceiptItem = require(Shared.Pure.ReceiptItem)
local ShopConfig = require(Shared.Config.ShopConfig)
local ShopRotation = require(Shared.Pure.ShopRotation)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("ShopService")

type ProfileData = Types.ProfileData
type ShopEntry = Types.ShopEntry
type ShopSnapshot = Types.ShopSnapshot
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type CurrencyApi = {
	get: (player: Player) -> number,
	trySpend: (player: Player, amount: number, reason: string) -> boolean,
}
type GrantedSignal = { Connect: (self: GrantedSignal, fn: (player: Player, cosmeticId: string) -> ()) -> any }
type CosmeticApi = {
	grant: (player: Player, cosmeticId: string) -> boolean,
	Granted: GrantedSignal?,
}
type AnalyticsApi = {
	economy: (
		player: Player,
		flowType: string,
		currency: string,
		amount: number,
		endingBalance: number,
		category: string,
		itemSku: string?
	) -> (),
}
type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	fire: (name: string, player: Player, ...any) -> (),
}
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Currency: CurrencyApi,
	Cosmetic: CosmeticApi,
	Analytics: AnalyticsApi,
}

-- One recorded Robux choice: which item, and when it was picked (os.clock).
type Intent = { CosmeticId: string, At: number }

-- The day key changes once a day; scanning it every few seconds makes the switch invisible to players
-- without a per-player loop.
local ROTATION_SCAN_SECONDS = 5
-- Roblox transaction type name reported to analytics for a soft-currency shop purchase.
local TRANSACTION_SHOP = "Shop"
local SFX_SUCCESS = "Claim"
local SFX_ERROR = "Error"

local ShopService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local currency: CurrencyApi
local cosmetic: CosmeticApi
local analytics: AnalyticsApi

local trove = Trove.new()
local dayKey = ""
local rotation: { string } = {}
local intents: { [Player]: Intent } = {}
local scanAccumulator = 0

----------------------------------------------------------------
-- Rotation
----------------------------------------------------------------

local function selectRotation(key: string): { string }
	return ShopRotation.select(
		(CosmeticConfig.Items :: any) :: { ShopRotation.Item },
		key,
		ShopConfig.Rotation,
		ShopConfig.RarityOrder
	)
end

-- Rebuilds the rotation for `now` when the day changed. Returns true when it changed.
local function refreshRotation(now: number): boolean
	local key = ShopRotation.dayKey(now)
	if key == dayKey then
		return false
	end
	dayKey = key
	rotation = selectRotation(key)
	log.info("rotation %s: %s", dayKey, table.concat(rotation, ", "))
	return true
end

local function isInRotation(cosmeticId: string): boolean
	return table.find(rotation, cosmeticId) ~= nil
end

----------------------------------------------------------------
-- Snapshot
----------------------------------------------------------------

-- Today's rotation with ownership and prices resolved for `data`. Entries whose rarity has no price or
-- no Robux product are skipped and reported: a rotation must never offer something unbuyable.
local function entriesFor(data: ProfileData): { ShopEntry }
	local entries: { ShopEntry } = {}
	for _, cosmeticId in ipairs(rotation) do
		local item = CosmeticConfig.ById[cosmeticId]
		if item == nil then
			log.error("rotation holds unknown cosmetic %s", cosmeticId)
			continue
		end
		local price = ShopConfig.PriceFolios[item.Rarity]
		local productKey = ShopConfig.RobuxProduct[item.Rarity]
		if price == nil or productKey == nil then
			log.error("rarity %s has no price or no Robux product (%s)", item.Rarity, cosmeticId)
			continue
		end
		-- Slot and Rarity widen to plain strings: the wire format (Types.ShopEntry) is not typed by the
		-- catalog's unions, so the client can render an entry it does not know yet.
		table.insert(entries, {
			CosmeticId = item.Id,
			NameKey = item.NameKey,
			Slot = item.Slot :: string,
			Rarity = item.Rarity :: string,
			PriceFolios = price,
			ProductKey = productKey,
			Owned = table.find(data.Cosmetics.Owned, item.Id) ~= nil,
		})
	end
	return entries
end

-- Today's rotation for `player`, or nil while the profile is not loaded.
function ShopService.getSnapshot(player: Player): ShopSnapshot?
	local data = dataService.get(player)
	if data == nil then
		return nil
	end
	return { DayKey = dayKey, Entries = entriesFor(data) }
end

-- Replicates the rotation to `player` (ownership resolved). Called on join, on rotation, after every
-- purchase and whenever CosmeticService grants something.
function ShopService.refresh(player: Player)
	if player.Parent ~= Players then
		return
	end
	local snapshot = ShopService.getSnapshot(player)
	if snapshot == nil then
		return
	end
	registry.fire("ShopChanged", player, snapshot)
end

local function refreshAll()
	for _, player in ipairs(Players:GetPlayers()) do
		ShopService.refresh(player)
	end
end

----------------------------------------------------------------
-- Purchase intent (Robux path)
----------------------------------------------------------------

-- Records which rotation item `player` wants to buy with Robux and returns the developer product key
-- that sells that rarity. On refusal returns nil plus the Strings key explaining why.
function ShopService.setPurchaseIntent(player: Player, cosmeticId: string): (string?, string?)
	local data = dataService.get(player)
	if data == nil then
		return nil, "purchase.failed"
	end
	local item = CosmeticConfig.ById[cosmeticId]
	if item == nil or not item.Sellable or not isInRotation(cosmeticId) then
		return nil, "purchase.unavailable"
	end
	if table.find(data.Cosmetics.Owned, cosmeticId) ~= nil then
		return nil, "purchase.alreadyOwned"
	end
	local productKey = ShopConfig.RobuxProduct[item.Rarity]
	if productKey == nil then
		log.error("rarity %s has no Robux product (%s)", item.Rarity, cosmeticId)
		return nil, "purchase.unavailable"
	end
	intents[player] = { CosmeticId = cosmeticId, At = os.clock() }
	return productKey, nil
end

-- The live intent of `player` without consuming it (nil when there is none or it expired).
function ShopService.getPurchaseIntent(player: Player): string?
	local intent = intents[player]
	if intent == nil then
		return nil
	end
	if os.clock() - intent.At > ShopConfig.PurchaseIntentSeconds then
		intents[player] = nil
		return nil
	end
	return intent.CosmeticId
end

-- Drops the live intent, but only when it is exactly `cosmeticId`. A receipt must never discard the
-- intent of another purchase the player has in flight: the two remotes that set an intent are
-- client-reachable, so the slot can already hold a different item by the time a receipt lands.
function ShopService.clearPurchaseIntent(player: Player, cosmeticId: string)
	local intent = intents[player]
	if intent ~= nil and intent.CosmeticId == cosmeticId then
		intents[player] = nil
	end
end

-- The cosmetic a Robux receipt of `rarity` must grant, or nil when the player already owns every
-- sellable item of that rarity. Preference order: the live intent when it names an item of the right
-- rarity, then today's rotation, then any sellable item of that rarity.
--
-- The Robux are debited when the player confirms the dialog, so a receipt must always have something
-- to deliver: the intent slot is a single client-writable slot that can be overwritten or expire
-- before the receipt arrives, and reading it as the only source would leave a paid purchase
-- undeliverable forever (Roblox re-delivers the receipt until it is granted).
function ShopService.resolveReceiptItem(player: Player, rarity: string): string?
	local data = dataService.get(player)
	if data == nil then
		return nil
	end
	return ReceiptItem.pick(
		(CosmeticConfig.Items :: any) :: { ReceiptItem.Item },
		rotation,
		data.Cosmetics.Owned,
		rarity,
		ShopService.getPurchaseIntent(player)
	)
end

----------------------------------------------------------------
-- Folios purchase
----------------------------------------------------------------

local function onBuyCosmetic(player: Player, cosmeticId: string)
	local data = dataService.get(player)
	if data == nil then
		log.warn("BuyCosmetic rejected for %s: profile not loaded", player.Name)
		notify.send(player, "purchase.failed", nil, "Error", SFX_ERROR)
		return
	end
	local item = CosmeticConfig.ById[cosmeticId]
	if item == nil or not item.Sellable or not isInRotation(cosmeticId) then
		log.warn("BuyCosmetic rejected for %s: %s is not in today's rotation", player.Name, cosmeticId)
		notify.send(player, "purchase.unavailable", nil, "Error", SFX_ERROR)
		ShopService.refresh(player)
		return
	end
	if table.find(data.Cosmetics.Owned, cosmeticId) ~= nil then
		notify.send(player, "purchase.alreadyOwned", nil, "Info")
		ShopService.refresh(player)
		return
	end
	local price = ShopConfig.PriceFolios[item.Rarity]
	if price == nil then
		log.error("rarity %s has no Folios price (%s)", item.Rarity, cosmeticId)
		notify.send(player, "purchase.unavailable", nil, "Error", SFX_ERROR)
		return
	end

	if not currency.trySpend(player, price, TRANSACTION_SHOP .. ":" .. cosmeticId) then
		-- Not affordable: remember the choice so the explicit "buy with Robux" button can complete it.
		ShopService.setPurchaseIntent(player, cosmeticId)
		notify.send(player, "shop.notEnoughFolios", nil, "Error", SFX_ERROR)
		ShopService.refresh(player)
		return
	end

	-- Debit first, then deliver: the balance is authoritative and a failed grant is a bug in
	-- CosmeticService, reported here with its context rather than paid back at the VIP rate.
	if not log.succeeded("cosmetic grant " .. cosmeticId, cosmetic.grant, player, cosmeticId) then
		notify.send(player, "purchase.failed", nil, "Error", SFX_ERROR)
		ShopService.refresh(player)
		return
	end
	intents[player] = nil
	notify.send(player, "shop.purchased", { name = item.NameKey }, "Success", SFX_SUCCESS)
	analytics.economy(player, "Sink", GameConfig.Currency.Id, price, currency.get(player), TRANSACTION_SHOP, cosmeticId)
	log.info("%s bought %s for %d Folios", player.Name, cosmeticId, price)
	ShopService.refresh(player)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

local function onHeartbeat(deltaTime: number)
	scanAccumulator += deltaTime
	if scanAccumulator < ROTATION_SCAN_SECONDS then
		return
	end
	scanAccumulator = 0
	if refreshRotation(os.time()) then
		refreshAll()
	end
end

local function onPlayerRemoving(player: Player)
	intents[player] = nil
end

function ShopService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	currency = deps.Currency
	cosmetic = deps.Cosmetic
	analytics = deps.Analytics
	refreshRotation(os.time())
end

function ShopService.Start()
	registry.on("BuyCosmetic", onBuyCosmetic)
	dataService.ProfileLoaded:Connect(function(player: Player)
		ShopService.refresh(player)
	end)
	if cosmetic.Granted ~= nil then
		trove:Add(cosmetic.Granted:Connect(function(player: Player)
			ShopService.refresh(player)
		end))
	else
		log.info("CosmeticService exposes no Granted signal: ownership refreshes on join, rotation and purchases")
	end
	trove:Add(Players.PlayerRemoving:Connect(onPlayerRemoving))
	trove:Add(RunService.Heartbeat:Connect(onHeartbeat))
	log.info("started (%d items in rotation %s)", #rotation, dayKey)
end

return ShopService
