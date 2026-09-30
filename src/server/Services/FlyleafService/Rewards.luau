--!strict
-- Rewards: what a kill on the Flyleaf pays (E16-S2). CombatService leaves this zone's kills to it
-- (ZoneConfig.Rules.Flyleaf, CombatPaysKills false) and says each one on Killed.
--
-- The killer is paid FlyleafConfig.Rewards: the XP always, the Folios out of a daily allowance counted in the
-- PROFILE (Daily.FlyleafDay and FlyleafFolios, DailyCap.take) -- a count kept in a server's memory is escaped by
-- joining another server. Nothing is paid for a victim the killer has already taken MaxPaidDeaths times within the
-- window (Pure/FlyleafRules.recordKill): two friends trading kills stop earning, and so does hunting one stranger.
-- Past the cap a kill pays XP alone, and the player is told once per day and per session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Context = require(script.Parent.Context)
local DailyCap = require(Shared.Pure.DailyCap)
local DailyStreak = require(Shared.Pure.DailyStreak)
local FlyleafConfig = require(Shared.Config.FlyleafConfig)
local FlyleafRules = require(script.Parent.Parent.Parent.Pure.FlyleafRules)

local REWARDS = FlyleafConfig.Rewards
local FARM = FlyleafConfig.Farm
-- The reason every credit of this page is logged under (analytics, the result of addXp and add).
local REASON = "FlyleafKill"

local Rewards = {}

local deps: Context.Deps
local ledger: FlyleafRules.Ledger = {}
-- Player -> the day they were last told the page pays no more Folios.
local capToldOn: { [Player]: number } = {}

-- Takes today's Folios for one kill from the profile's allowance and writes the count back. Returns what may be
-- paid, before VIP (CurrencyService applies it); nil with no profile loaded.
local function takeFolios(player: Player, today: number): number?
	local data = deps.DataService.get(player)
	if data == nil then
		return nil
	end
	local daily = data.Daily
	local granted, used =
		DailyCap.take(daily.FlyleafDay, daily.FlyleafFolios, today, REWARDS.DailyFolioCap, REWARDS.Folios)
	if daily.FlyleafDay ~= today or daily.FlyleafFolios ~= used then
		daily.FlyleafDay = today
		daily.FlyleafFolios = used
		deps.DataService.push(player, "Daily")
	end
	return granted
end

-- Pays `killer` for taking `victim` down at `now`, and says whether anything was paid.
function Rewards.pay(killer: Player, victim: Player, now: number): boolean
	if not FlyleafRules.recordKill(ledger, killer.UserId, victim.UserId, now, FARM) then
		deps.Notify.send(killer, "flyleaf.noPay", { name = victim.DisplayName }, "Info")
		return false
	end
	local xp = deps.Progression.addXp(killer, REWARDS.Xp, REASON)
	local today = DailyStreak.dayIndex(os.time())
	local folios = takeFolios(killer, today)
	if folios ~= nil and folios >= 1 then
		deps.Currency.add(killer, folios, REASON)
	elseif folios ~= nil and capToldOn[killer] ~= today then
		capToldOn[killer] = today
		deps.Notify.send(killer, "flyleaf.folioCap", nil, "Info")
	end
	deps.Notify.send(killer, "hud.playerKill", { name = victim.DisplayName, xp = xp }, "Success", "Kill")
	return true
end

-- What the ledger keeps stays bounded by the deaths of the last window. A player who left is not forgotten
-- sooner: rejoining must not wipe the deaths they took.
function Rewards.prune(now: number)
	FlyleafRules.prune(ledger, now, FARM)
end

function Rewards.forget(player: Player)
	capToldOn[player] = nil
end

function Rewards.Init(injected: Context.Deps)
	deps = injected
end

return Rewards
