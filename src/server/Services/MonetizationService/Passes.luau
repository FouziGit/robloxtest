--!strict
-- Game pass ownership and effects. Ownership is read with UserOwnsGamePassAsync (pcall + retries) and
-- cached in ProfileData.Passes. The cache is never written back to false: Roblox does not revoke a pass,
-- so a failed check leaves the previous answer untouched instead of taking a pass away.
--
-- Effects are idempotent: they run on every profile load of a cached pass and right after a purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Context = require(script.Parent.Context)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Log = require(Shared.Util.Log)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)

local log = Log.new("MonetizationService")

type Deps = Context.Deps

-- Pass keys of MonetizationConfig.Passes whose effect is applied here. Vip needs nothing: CurrencyService
-- and ProgressionService read Passes.Vip themselves.
local PASS_LIGHTNING = "Lightning"
local PASS_LOADOUT_SLOTS = "LoadoutSlots"
local PASS_SKIN_PACK = "SkinPack"
-- The Lightning pass grants the Lightning element (ElementConfig.Unlockable).
local LIGHTNING_ELEMENT = "Lightning"
-- UserOwnsGamePassAsync is a web call: retried with a growing backoff before giving up.
local OWNERSHIP_ATTEMPTS = 3
local OWNERSHIP_BACKOFF_SECONDS = 2

local Passes = {}

local deps: Deps

-- Pass keys in a stable order, so logs and effects never depend on hash order.
Passes.Keys = {} :: { string }
for key in pairs(MonetizationConfig.Passes) do
	table.insert(Passes.Keys, key)
end
table.sort(Passes.Keys)

-- True / false when the answer is known, nil when every attempt failed. Yields between attempts.
local function ownsPass(player: Player, passId: number): boolean?
	local backoff = OWNERSHIP_BACKOFF_SECONDS
	for attempt = 1, OWNERSHIP_ATTEMPTS do
		local ok, result = pcall(function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return result == true
		end
		if attempt == OWNERSHIP_ATTEMPTS then
			log.warn("ownership check of pass %d for %s failed: %s", passId, player.Name, tostring(result))
		else
			task.wait(backoff)
			backoff *= 2
		end
	end
	return nil
end

-- Applies what an owned pass grants.
function Passes.apply(player: Player, passKey: string)
	local data = deps.DataService.get(player)
	if data == nil then
		return
	end
	if passKey == PASS_LIGHTNING then
		log.try("grantElement " .. LIGHTNING_ELEMENT, deps.Loadout.grantElement, player, LIGHTNING_ELEMENT)
	elseif passKey == PASS_LOADOUT_SLOTS then
		if data.Loadout.ExtraSlots ~= ProgressionConfig.Loadout.PassExtraSlots then
			data.Loadout.ExtraSlots = ProgressionConfig.Loadout.PassExtraSlots
			deps.DataService.push(player, "Loadout")
		end
	elseif passKey == PASS_SKIN_PACK then
		for _, cosmeticId in ipairs(MonetizationConfig.SkinPackCosmetics) do
			if CosmeticConfig.ById[cosmeticId] == nil then
				log.error("SkinPackCosmetics holds unknown cosmetic %s", cosmeticId)
				continue
			end
			log.try("cosmetic grant " .. cosmeticId, deps.Cosmetic.grant, player, cosmeticId)
		end
	end
end

-- Caches `passKey` as owned and applies it. Returns true when the cache changed.
function Passes.cache(player: Player, passKey: string): boolean
	local data = deps.DataService.get(player)
	if data == nil then
		return false
	end
	local changed = data.Passes[passKey] ~= true
	if changed then
		data.Passes[passKey] = true
		deps.DataService.push(player, "Passes")
	end
	Passes.apply(player, passKey)
	return changed
end

-- Checks every pass that has an id, then applies the ones the player owns. Yields (web calls), so the
-- profile is re-read after each check and the sync stops as soon as the player is gone.
function Passes.sync(player: Player)
	local owned: { string } = {}
	for _, passKey in ipairs(Passes.Keys) do
		local pass = MonetizationConfig.Passes[passKey]
		local data = deps.DataService.get(player)
		if data == nil then
			return
		end
		local isOwned = data.Passes[passKey] == true
		if not isOwned and pass.Id ~= 0 then
			isOwned = ownsPass(player, pass.Id) == true
		end
		if isOwned then
			table.insert(owned, passKey)
		end
	end

	local data = deps.DataService.get(player)
	if data == nil then
		return
	end
	local changed = false
	for _, passKey in ipairs(owned) do
		if data.Passes[passKey] ~= true then
			data.Passes[passKey] = true
			changed = true
		end
	end
	if changed then
		deps.DataService.push(player, "Passes")
	end
	for _, passKey in ipairs(owned) do
		Passes.apply(player, passKey)
	end
end

-- A pass bought during the session: cache it, apply it, tell the player and save right away.
function Passes.onPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	local passKey, pass = MonetizationConfig.passByAssetId(gamePassId)
	if passKey == nil or pass == nil then
		return
	end
	if not wasPurchased then
		deps.Analytics.custom(player, Context.EventPromptDeclined, nil, { pass = passKey })
		return
	end
	deps.Analytics.custom(player, Context.EventPromptAccepted, nil, { pass = passKey })
	Passes.cache(player, passKey)
	deps.Notify.send(player, "purchase.passGranted", { name = pass.NameKey }, "Success", Context.SfxSuccess)
	deps.Analytics.custom(player, Context.EventPassPurchased, pass.PriceRobux, { pass = passKey })
	log.info("%s owns pass %s", player.Name, passKey)
	task.spawn(function()
		log.try("saveNow " .. player.Name, deps.DataService.saveNow, player)
	end)
end

function Passes.Init(injected: Deps)
	deps = injected
end

return Passes
