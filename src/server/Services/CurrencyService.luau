--!strict
-- CurrencyService: the only writer of Currency.Ryo. Amounts are positive integers and the balance
-- never goes negative. Mirrors the balance into the leaderstats "Ryo" value when it exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)

local log = Log.new("CurrencyService")

type ProfileData = Types.ProfileData
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type Deps = { DataService: DataApi }

local LEADERSTATS_FOLDER = "leaderstats"
local LEADERSTAT_RYO = "Ryo"

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
	local stat = folder:FindFirstChild(LEADERSTAT_RYO)
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
	return data.Currency.Ryo
end

function CurrencyService.add(player: Player, amount: number, reason: string)
	if not isPositiveInteger(amount) then
		log.warn("add rejected for %s (%s): invalid amount %s", player.Name, reason, tostring(amount))
		return
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("add skipped for %s (%s): profile not loaded", player.Name, reason)
		return
	end
	data.Currency.Ryo += amount
	syncLeaderstat(player, data.Currency.Ryo)
	dataService.push(player, "Currency")
	log.info("%s +%d Ryo (%s) -> %d", player.Name, amount, reason, data.Currency.Ryo)
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
	if data.Currency.Ryo < amount then
		return false
	end
	data.Currency.Ryo -= amount
	syncLeaderstat(player, data.Currency.Ryo)
	dataService.push(player, "Currency")
	log.info("%s -%d Ryo (%s) -> %d", player.Name, amount, reason, data.Currency.Ryo)
	return true
end

function CurrencyService.Init(deps: Deps)
	dataService = deps.DataService
end

function CurrencyService.Start()
	log.info("started")
end

return CurrencyService
