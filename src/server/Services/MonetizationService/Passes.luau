--!strict
-- Game pass ownership and effects. Ownership is read with UserOwnsGamePassAsync (pcall + retries) and
-- cached in ProfileData.Passes. The cache follows Roblox's definite answers both ways (PassCache, D-211): each
-- pass that has an id is asked about again on every join, and again when a purchase dialog closes without a
-- sale, which is how Roblox closes it on a pass the player already owns. An owned pass enters the cache, and
-- one Roblox says is not owned leaves it: a refund, a pass deleted from the inventory, a Studio test purchase.
-- A check that fails leaves the previous answer untouched, so an outage never takes a pass away.
--
-- Effects are idempotent: they run on every profile load of a cached pass and right after a purchase. What a
-- pass gives while it is held follows the cache: the VIP multipliers read it, the chat tag mirrors it, and the
-- extra loadout slots go back to none when it leaves. What a pass handed over once (its cosmetics, the
-- Orpiment pigment) stays owned, as a delivered purchase does.
--
-- In Studio a test purchase grants nothing unless StudioConfig.PersistTestPurchases says so (Sandbox).
--
-- The chat tag the VIP pass sells (D-209) is decided here: the cache's Vip entry is mirrored onto the Player
-- as ChatConfig.VipAttribute, which only the server can set for every client to see, and each client draws
-- the tag from it (ChatController).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChatConfig = require(Shared.Config.ChatConfig)
local Context = require(script.Parent.Context)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Log = require(Shared.Util.Log)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local PassCache = require(Shared.Pure.PassCache)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Sandbox = require(script.Parent.Sandbox)

local log = Log.new("MonetizationService")

type Deps = Context.Deps

-- Pass keys of MonetizationConfig.Passes whose effect is applied here. Vip's XP and Folios bonuses are read
-- by CurrencyService and ProgressionService themselves; its exclusive aura is granted here.
local PASS_LIGHTNING = "Orpiment"
local PASS_VIP = "Vip"
local PASS_LOADOUT_SLOTS = "LoadoutSlots"
local PASS_SKIN_PACK = "SkinPack"
-- The Orpiment pass grants the Orpiment pigment (PigmentConfig.Unlockable).
local ORPIMENT_PIGMENT = "Orpiment"
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

-- The VIP chat tag follows the cache: set while it holds Vip, cleared otherwise.
local function mirrorVip(player: Player, data: Context.ProfileData)
	player:SetAttribute(ChatConfig.VipAttribute, if data.Passes[PASS_VIP] == true then true else nil)
end

-- Applies what an owned pass grants.
function Passes.apply(player: Player, passKey: string)
	-- Every effect below writes through the service that owns the section, and each of those warns on a
	-- missing profile: bail out first so a sync racing a leaving player stays quiet.
	if deps.DataService.get(player) == nil then
		return
	end
	if passKey == PASS_LIGHTNING then
		log.try("grantPigment " .. ORPIMENT_PIGMENT, deps.Loadout.grantPigment, player, ORPIMENT_PIGMENT)
	elseif passKey == PASS_LOADOUT_SLOTS then
		log.try("setExtraSlots", deps.Loadout.setExtraSlots, player, ProgressionConfig.Loadout.PassExtraSlots)
	elseif passKey == PASS_SKIN_PACK or passKey == PASS_VIP then
		local list = if passKey == PASS_VIP
			then MonetizationConfig.VipCosmetics
			else MonetizationConfig.SkinPackCosmetics
		for _, cosmeticId in ipairs(list) do
			if CosmeticConfig.ById[cosmeticId] == nil then
				log.error("%s pass holds unknown cosmetic %s", passKey, cosmeticId)
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
	mirrorVip(player, data)
	Passes.apply(player, passKey)
	return changed
end

-- Takes back what a pass that left the cache gave only while it was held.
local function withdraw(player: Player, passKey: string)
	if passKey == PASS_LOADOUT_SLOTS then
		log.try("setExtraSlots", deps.Loadout.setExtraSlots, player, 0)
	end
end

-- Brings the cache in line with Roblox's definite `answers`, then applies every pass it holds. `held` is the
-- cache as it stood when the questions were asked: a pass bought while Roblox was being asked arrived after
-- the answer, and must not be taken out by it. Returns the passes that entered the cache.
local function settle(
	player: Player,
	data: Context.ProfileData,
	answers: { [string]: boolean },
	held: { [string]: boolean }
): { string }
	local added, removed = PassCache.reconcile(data.Passes, answers, held)
	if #added > 0 or #removed > 0 then
		deps.DataService.push(player, "Passes")
	end
	for _, passKey in ipairs(removed) do
		log.info("%s no longer owns pass %s: it leaves the cache", player.Name, passKey)
		withdraw(player, passKey)
	end
	mirrorVip(player, data)
	for _, passKey in ipairs(Passes.Keys) do
		if data.Passes[passKey] == true then
			Passes.apply(player, passKey)
		end
	end
	return added
end

-- Asks Roblox about every pass that has an id, then settles the cache and applies what it holds. Yields (web
-- calls), so the profile is re-read after each check and the sync stops as soon as the player is gone.
function Passes.sync(player: Player)
	-- The tag from what the cache already holds, before any web call: an owner is tagged from their first
	-- message.
	local cached = deps.DataService.get(player)
	if cached == nil then
		return
	end
	mirrorVip(player, cached)
	local held = table.clone(cached.Passes)

	local answers: { [string]: boolean } = {}
	for _, passKey in ipairs(Passes.Keys) do
		local pass = MonetizationConfig.Passes[passKey]
		if pass.Id ~= 0 then
			local owned = ownsPass(player, pass.Id)
			if deps.DataService.get(player) == nil then
				return
			end
			if owned ~= nil then
				answers[passKey] = owned
			end
		end
	end

	local data = deps.DataService.get(player)
	if data == nil then
		return
	end
	settle(player, data, answers, held)
end

-- A dialog Roblox closed without a sale. It closes that way on a pass the player already owns, which the
-- cache misses when the check at join failed: ask again, and settle on a definite answer. Yields.
local function recheck(player: Player, passKey: string, pass: MonetizationConfig.PassDef)
	local before = deps.DataService.get(player)
	if before == nil then
		return
	end
	local held = table.clone(before.Passes)
	local owned = ownsPass(player, pass.Id)
	local data = deps.DataService.get(player)
	if data == nil or owned == nil then
		return
	end
	local added = settle(player, data, { [passKey] = owned }, held)
	if table.find(added, passKey) ~= nil then
		deps.Notify.send(player, "purchase.passGranted", { name = pass.NameKey }, "Success", Context.SfxSuccess)
		log.info("%s already owned pass %s: it enters the cache", player.Name, passKey)
	end
end

-- A pass dialog closed. A sale is cached, applied, told to the player and saved right away; a dialog closed
-- without one is asked about again. In a Studio sandbox neither touches the cache: a sale grants nothing, and
-- the recheck is skipped too, since Roblox may keep answering "owned" after a test sale for the rest of the
-- session.
function Passes.onPurchaseFinished(player: Player, gamePassId: number, wasPurchased: boolean)
	local passKey, pass = MonetizationConfig.passByAssetId(gamePassId)
	if passKey == nil or pass == nil then
		return
	end
	if not wasPurchased then
		deps.Analytics.custom(player, "PromptDeclined", nil, deps.Analytics.fields("Pass", passKey))
		if not Sandbox.active() then
			task.spawn(function()
				log.try("pass recheck " .. passKey, recheck, player, passKey, pass)
			end)
		end
		return
	end
	if Sandbox.active() then
		Sandbox.acknowledge(player, "pass " .. passKey, pass.NameKey)
		return
	end
	deps.Analytics.custom(player, "PromptAccepted", nil, deps.Analytics.fields("Pass", passKey))
	Passes.cache(player, passKey)
	deps.Notify.send(player, "purchase.passGranted", { name = pass.NameKey }, "Success", Context.SfxSuccess)
	deps.Analytics.custom(player, "PassPurchased", pass.PriceRobux, deps.Analytics.fields(passKey))
	log.info("%s owns pass %s", player.Name, passKey)
	task.spawn(function()
		log.try("saveNow " .. player.Name, deps.DataService.saveNow, player)
	end)
end

function Passes.Init(injected: Deps)
	deps = injected
end

return Passes
