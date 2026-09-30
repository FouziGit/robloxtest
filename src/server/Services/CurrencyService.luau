--!strict
-- CurrencyService: the only writer of Currency.Folios. Amounts are positive integers and the balance
-- never goes negative. Mirrors the balance into the leaderstats "Folios" value when it exists. A developer
-- account spends without paying when DeveloperConfig.UnlimitedFolios is on (D-129).
--
-- Every Folio it credits or debits is reported here, once, to AnalyticsService, with the reason it was handed
-- (which AnalyticsConfig files under a transaction type and an item): no caller reports a movement of its own.
-- A movement that did not happen -- a refusal, a developer's waived spend -- reports nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeveloperConfig = require(script.Parent.Parent.Config.DeveloperConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("CurrencyService")

-- Pass key in ProfileData.Passes granting the Folios multiplier (see MonetizationConfig.Passes).
local VIP_PASS_KEY = "Vip"

type ProfileData = Types.ProfileData
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type AnalyticsApi = {
	economy: (
		player: Player,
		flowType: "Source" | "Sink",
		currency: string,
		amount: number,
		endingBalance: number,
		reason: string
	) -> (),
}
type Deps = { DataService: DataApi, Analytics: AnalyticsApi }

local LEADERSTATS_FOLDER = "leaderstats"
local LEADERSTAT_FOLIOS = "Folios"
local CURRENCY_ID = GameConfig.Currency.Id

local CurrencyService = {}

local dataService: DataApi
local analytics: AnalyticsApi

local function isPositiveInteger(value: number): boolean
	return value == value and value ~= math.huge and value == math.floor(value) and value > 0
end

-- The movement just written, to the Economy dashboards. Telemetry never undoes a movement: a report that
-- throws is warned about, and the balance stands.
local function report(player: Player, flowType: "Source" | "Sink", amount: number, balance: number, reason: string)
	log.try("economy event " .. reason, analytics.economy, player, flowType, CURRENCY_ID, amount, balance, reason)
end

local function syncLeaderstat(player: Player, value: number)
	local folder = player:FindFirstChild(LEADERSTATS_FOLDER)
	if folder == nil then
		return
	end
	local stat = folder:FindFirstChild(LEADERSTAT_FOLIOS)
	if stat ~= nil and stat:IsA("IntValue") then
		stat.Value = value
	end
end

-- Returns the Folios actually credited (base amount times the VIP multiplier), or 0 when nothing was
-- granted, so callers can report the real figure to the player.
function CurrencyService.add(player: Player, amount: number, reason: string): number
	if not isPositiveInteger(amount) then
		log.warn("add rejected for %s (%s): invalid amount %s", player.Name, reason, tostring(amount))
		return 0
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("add skipped for %s (%s): profile not loaded", player.Name, reason)
		return 0
	end
	if data.Passes[VIP_PASS_KEY] == true then
		amount = math.max(1, math.floor(amount * ProgressionConfig.VipFolioMultiplier))
	end
	data.Currency.Folios += amount
	syncLeaderstat(player, data.Currency.Folios)
	dataService.push(player, "Currency")
	log.info("%s +%d Folios (%s) -> %d", player.Name, amount, reason, data.Currency.Folios)
	report(player, "Source", amount, data.Currency.Folios, reason)
	return amount
end

-- True when `player` spends without paying: a developer account while DeveloperConfig.UnlimitedFolios is on
-- (D-129). ShopService marks what such a purchase bought, so it leaves with the list.
function CurrencyService.waives(player: Player): boolean
	return DeveloperConfig.UnlimitedFolios and DeveloperConfig.isDeveloper(player.UserId, player.Name)
end

-- Debits `amount` when the balance covers it. Returns false (and changes nothing) otherwise.
function CurrencyService.trySpend(player: Player, amount: number, reason: string): boolean
	if not isPositiveInteger(amount) then
		log.warn("spend rejected for %s (%s): invalid amount %s", player.Name, reason, tostring(amount))
		return false
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("spend skipped for %s (%s): profile not loaded", player.Name, reason)
		return false
	end
	-- The purchase goes through and the balance is untouched: nothing is debited, nothing is credited.
	if CurrencyService.waives(player) then
		log.info("%s paid nothing for %s (developer: %d Folios waived)", player.Name, reason, amount)
		return true
	end
	if data.Currency.Folios < amount then
		return false
	end
	data.Currency.Folios -= amount
	syncLeaderstat(player, data.Currency.Folios)
	dataService.push(player, "Currency")
	log.info("%s -%d Folios (%s) -> %d", player.Name, amount, reason, data.Currency.Folios)
	report(player, "Sink", amount, data.Currency.Folios, reason)
	return true
end

-- Pays back what trySpend(`amount`) took, when what it paid for could not be delivered. Exactly that: never
-- the VIP multiplier `add` applies, which would turn a failed purchase into a profit, and nothing for a
-- developer, whose trySpend took nothing. Returns the Folios credited.
function CurrencyService.refund(player: Player, amount: number, reason: string): number
	if not isPositiveInteger(amount) then
		log.warn("refund rejected for %s (%s): invalid amount %s", player.Name, reason, tostring(amount))
		return 0
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("refund skipped for %s (%s): profile not loaded", player.Name, reason)
		return 0
	end
	if CurrencyService.waives(player) then
		log.info("%s is refunded nothing for %s (developer: the %d Folios were waived)", player.Name, reason, amount)
		return 0
	end
	data.Currency.Folios += amount
	syncLeaderstat(player, data.Currency.Folios)
	dataService.push(player, "Currency")
	log.info("%s +%d Folios refunded (%s) -> %d", player.Name, amount, reason, data.Currency.Folios)
	report(player, "Source", amount, data.Currency.Folios, reason)
	return amount
end

function CurrencyService.Init(deps: Deps)
	dataService = deps.DataService
	analytics = deps.Analytics
end

function CurrencyService.Start()
	log.info("started")
end

return CurrencyService
