--!strict
-- Shared types, constants and helpers of the MonetizationService folder. Every submodule receives the
-- same injected Deps table and keeps no state here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Types = require(Shared.Types)

export type PurchaseKind = "Pass" | "Product" | "Cosmetic"

export type ProfileData = Types.ProfileData
export type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
export type DataApi = {
	get: (player: Player) -> ProfileData?,
	waitFor: (player: Player, timeout: number?) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	recordReceipt: (player: Player, purchaseId: string) -> boolean,
	-- Yields, and returns whether ProfileStore CONFIRMED the write. Never tell Roblox PurchaseGranted on
	-- a false: the Robux are already taken and the receipt would never be delivered again.
	saveNow: (player: Player) -> boolean,
	isActive: (player: Player) -> boolean,
	ProfileLoaded: ProfileSignal,
}
export type NotifyKind = "Info" | "Success" | "Error"
export type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
export type CurrencyApi = {
	add: (player: Player, amount: number, reason: string) -> number,
}
export type BattlepassApi = {
	addXp: (player: Player, amount: number) -> (),
	isPremium: (player: Player) -> boolean,
	setPremium: (player: Player, value: boolean) -> (),
	-- The single writer of ProfileData.Boosts: it extends a live boost instead of shortening it.
	grantXpBoost: (player: Player, minutes: number) -> boolean,
}
-- The single writer of ProfileData.Loadout and ProfileData.Unlocks: pass effects go through it.
export type LoadoutApi = {
	grantPigment: (player: Player, pigmentId: string) -> boolean,
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
export type AnalyticsApi = {
	-- CustomField01 to 03 of one event, as text (AnalyticsService.fields).
	fields: (first: string | number, second: (string | number)?, third: (string | number)?) -> { [string]: string },
	-- `eventName` is a name of AnalyticsConfig.Events, and `fields` what `fields` built for it.
	custom: (player: Player, eventName: string, value: number?, fields: { [string]: string }?) -> (),
}
export type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
export type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Currency: CurrencyApi,
	Battlepass: BattlepassApi,
	Loadout: LoadoutApi,
	Cosmetic: CosmeticApi,
	Shop: ShopApi,
	Analytics: AnalyticsApi,
}

local Context = {}

-- Sfx ids (SoundConfig.Sfx) attached to purchase feedback.
Context.SfxSuccess = "Claim"
Context.SfxError = "Error"
Context.SfxTierUp = "TierUp"

function Context.seasonOf(data: ProfileData): Types.BattlepassSeasonData?
	return data.Battlepass[GameConfig.SeasonId]
end

function Context.atMaxTier(data: ProfileData): boolean
	local season = Context.seasonOf(data)
	return season ~= nil and season.Tier >= BattlepassConfig.MaxTier
end

return Context
