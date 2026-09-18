--!strict
-- Shared types, constants and helpers of the MonetizationService folder. Every submodule receives the
-- same injected Deps table and keeps no state here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Types = require(Shared.Types)

export type PurchaseKind = "Pass" | "Product" | "Cosmetic"
-- Reasons another service may ask for a contextual prompt (docs/ECONOMY.md §5).
export type PromptReason = "CloseLoss" | "PassTierLocked" | "LightningDeath" | "LoadoutFull"

export type ProfileData = Types.ProfileData
export type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
export type ReleaseSignal = { Connect: (self: ReleaseSignal, fn: (player: Player) -> ()) -> any }
export type DataApi = {
	get: (player: Player) -> ProfileData?,
	waitFor: (player: Player, timeout: number?) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	recordReceipt: (player: Player, purchaseId: string) -> boolean,
	saveNow: (player: Player) -> (),
	isActive: (player: Player) -> boolean,
	ProfileLoaded: ProfileSignal,
	ProfileReleased: ReleaseSignal,
}
export type NotifyKind = "Info" | "Success" | "Error"
export type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
export type CurrencyApi = {
	get: (player: Player) -> number,
	add: (player: Player, amount: number, reason: string) -> number,
}
export type BattlepassApi = {
	addXp: (player: Player, amount: number) -> (),
	isPremium: (player: Player) -> boolean,
	setPremium: (player: Player, value: boolean) -> (),
	-- The single writer of ProfileData.Boosts: it extends a live boost instead of shortening it.
	grantXpBoost: (player: Player, minutes: number) -> boolean,
}
export type ProgressionApi = { getLevel: (player: Player) -> number }
-- The single writer of ProfileData.Loadout and ProfileData.Unlocks: pass effects go through it.
export type LoadoutApi = {
	grantElement: (player: Player, elementId: string) -> boolean,
	setExtraSlots: (player: Player, count: number) -> boolean,
}
export type CosmeticApi = { grant: (player: Player, cosmeticId: string) -> boolean }
export type ShopApi = {
	setPurchaseIntent: (player: Player, cosmeticId: string) -> (string?, string?),
	getPurchaseIntent: (player: Player) -> string?,
	resolveReceiptItem: (player: Player, rarity: string) -> string?,
	clearPurchaseIntent: (player: Player, cosmeticId: string) -> (),
	refresh: (player: Player) -> (),
}
export type MatchApi = { isInMatch: (player: Player) -> boolean }
export type AnalyticsApi = {
	economy: (
		player: Player,
		flowType: string,
		currency: string,
		amount: number,
		endingBalance: number,
		category: string,
		itemSku: string?
	) -> (),
	custom: (player: Player, eventName: string, value: number?, fields: { [string]: any }?) -> (),
}
export type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
export type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Currency: CurrencyApi,
	Battlepass: BattlepassApi,
	Progression: ProgressionApi,
	Loadout: LoadoutApi,
	Cosmetic: CosmeticApi,
	Shop: ShopApi,
	Match: MatchApi,
	Analytics: AnalyticsApi,
}

local Context = {}

-- Sfx ids (SoundConfig.Sfx) attached to purchase feedback.
Context.SfxSuccess = "Claim"
Context.SfxError = "Error"
Context.SfxTierUp = "TierUp"
-- Roblox analytics transaction type name for a Robux purchase.
Context.TransactionIap = "IAP"
-- Analytics event names: Creator Dashboard dimensions, never shown to a player.
Context.EventPromptShown = "PromptShown"
Context.EventPromptAccepted = "PromptAccepted"
Context.EventPromptDeclined = "PromptDeclined"
Context.EventProductPurchased = "ProductPurchased"
Context.EventPassPurchased = "PassPurchased"

function Context.seasonOf(data: ProfileData): Types.BattlepassSeasonData?
	return data.Battlepass[GameConfig.SeasonId]
end

function Context.atMaxTier(data: ProfileData): boolean
	local season = Context.seasonOf(data)
	return season ~= nil and season.Tier >= BattlepassConfig.MaxTier
end

return Context
