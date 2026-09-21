--!strict
-- CurrencyService: the only writer of Currency.Folios. Amounts are positive integers and the balance
-- never goes negative. Mirrors the balance into the leaderstats "Folios" value when it exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

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
type Deps = { DataService: DataApi }

local LEADERSTATS_FOLDER = "leaderstats"
local LEADERSTAT_FOLIOS = "Folios"

local CurrencyService = {}

local dataService: DataApi

local function isPositiveInteger(value: number): boolean
	return value == value and value ~= math.huge and value == math.floor(value) and value > 0
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

-- Current balance, 0 while the profile is not loaded.
function CurrencyService.get(player: Player): number
	local data = dataService.get(player)
	if data == nil then
		return 0
	end
	return data.Currency.Folios
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
	return amount
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
	if data.Currency.Folios < amount then
		return false
	end
	data.Currency.Folios -= amount
	syncLeaderstat(player, data.Currency.Folios)
	dataService.push(player, "Currency")
	log.info("%s -%d Folios (%s) -> %d", player.Name, amount, reason, data.Currency.Folios)
	return true
end

function CurrencyService.Init(deps: Deps)
	dataService = deps.DataService
end

function CurrencyService.Start()
	log.info("started")
end

return CurrencyService
