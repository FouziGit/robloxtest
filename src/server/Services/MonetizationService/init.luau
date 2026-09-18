--!strict
-- MonetizationService: the only place in the game that talks to MarketplaceService. Game pass ownership
-- (Passes), contextual offers (Prompts), purchase dialogs (Purchases) and developer product receipts
-- (Receipts) live in this folder; this module wires them and owns the service lifecycle.
--
-- Asset ids live only in MonetizationConfig and are validated at startup: every id still at 0 is warned
-- once by name (the owner pastes it from the Creator Dashboard, see docs/STUDIO_SETUP.md) and only that
-- entry's purchases are refused, with Notify purchase.unavailable. Everything else keeps working, so the
-- game is fully playable before a single id exists.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Context = require(script.Context)
local Log = require(Shared.Util.Log)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Passes = require(script.Passes)
local Prompts = require(script.Prompts)
local Purchases = require(script.Purchases)
local Receipts = require(script.Receipts)
local Trove = require(Packages.Trove)

local log = Log.new("MonetizationService")

export type PurchaseKind = Context.PurchaseKind
export type PromptReason = Context.PromptReason

type Deps = Context.Deps

local MonetizationService = {}

local deps: Deps
local trove = Trove.new()

local productCount = 0
for _ in pairs(MonetizationConfig.Products) do
	productCount += 1
end

-- Offers the item of `reason` to `player` as a localized toast, when the guard-rails of
-- docs/ECONOMY.md §5 allow it. Returns true when the offer was shown.
function MonetizationService.maybePrompt(player: Player, reason: string): boolean
	return Prompts.maybePrompt(player, reason)
end

-- Opens the Roblox purchase dialog for a catalog entry. The client never sends an asset id: it names a
-- pass key, a product key or a cosmetic id of today's rotation.
function MonetizationService.promptPurchase(player: Player, kind: PurchaseKind, key: string)
	Purchases.prompt(player, kind, key)
end

local function onProfileLoaded(player: Player)
	task.spawn(function()
		log.try("pass sync " .. player.Name, Passes.sync, player)
	end)
end

function MonetizationService.Init(injected: Deps)
	deps = injected
	Passes.Init(deps)
	Prompts.Init(deps)
	Purchases.Init(deps)
	Receipts.Init(deps)
end

function MonetizationService.Start()
	local missing = MonetizationConfig.missingIds()
	for _, key in ipairs(missing) do
		log.warn(
			"missing id %s: paste it from the Creator Dashboard (docs/STUDIO_SETUP.md). Purchases of this entry are refused until then",
			key
		)
	end

	deps.Registry.on("PromptPurchase", function(player: Player, kind: PurchaseKind, key: string)
		Purchases.prompt(player, kind, key)
	end)

	MarketplaceService.ProcessReceipt = Receipts.process
	trove:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(Passes.onPurchaseFinished))
	trove:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(Purchases.onPurchaseFinished))

	deps.DataService.ProfileLoaded:Connect(onProfileLoaded)
	deps.DataService.ProfileReleased:Connect(Prompts.release)
	trove:Add(Players.PlayerRemoving:Connect(Prompts.release))
	for _, player in ipairs(Players:GetPlayers()) do
		if deps.DataService.get(player) ~= nil then
			onProfileLoaded(player)
		end
	end

	log.info("started (%d passes, %d products, %d missing ids)", #Passes.Keys, productCount, #missing)
end

return MonetizationService
