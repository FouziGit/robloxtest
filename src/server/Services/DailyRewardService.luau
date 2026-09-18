--!strict
-- DailyRewardService: the single writer of ProfileData.Daily. Login streak (DailyConfig.Streak), first
-- win of the day and the Roblox Premium daily bonus, all decided from Pure/DailyStreak.
--
-- Nothing is auto-claimed: the streak is evaluated when the profile loads and the section is
-- replicated so the client can offer the claim; only ClaimDaily pays it. The Premium bonus is the one
-- exception, because the player does nothing to earn it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DailyConfig = require(Shared.Config.DailyConfig)
local DailyStreak = require(Shared.Pure.DailyStreak)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("DailyRewardService")

type ProfileData = Types.ProfileData
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
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> number }
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> number }
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
}

local STREAK_LENGTH = #DailyConfig.Streak
local FIRST_WIN_XP = ProgressionConfig.XP.FirstWinOfDay
local FIRST_WIN_RYO = ProgressionConfig.Ryo.FirstWinOfDay
local PREMIUM_BONUS = DailyConfig.PremiumBonus

local DailyRewardService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi
local currency: CurrencyApi

-- Claims today's streak reward. The section is replicated on every path, including a refusal, so the
-- client never stays pending. Returns true when a reward was granted.
function DailyRewardService.claim(player: Player): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("claim skipped for %s: profile not loaded", player.Name)
		return false
	end
	local streak = DailyStreak.claim(data.Daily, DailyStreak.dayIndex(os.time()))
	dataService.push(player, "Daily")
	if streak == 0 then
		log.warn("claim refused for %s: already claimed today", player.Name)
		return false
	end
	local reward = DailyConfig.Streak[DailyStreak.rewardIndex(streak, STREAK_LENGTH)]
	if reward == nil then
		log.error("no streak entry for day %d (%d entries)", streak, STREAK_LENGTH)
		return false
	end
	local ryo = currency.add(player, reward.Ryo, "DailyStreak")
	local xp = progression.addXp(player, reward.Xp, "DailyStreak")
	notify.send(player, "daily.claimed", { day = streak, xp = xp, ryo = ryo }, "Success", "Claim")
	log.info("%s claimed day %d (+%d XP, +%d Ryo)", player.Name, streak, xp, ryo)
	return true
end

-- First win of the day bonus (ProgressionConfig.*.FirstWinOfDay), once per day and per player. Called
-- by MatchService when a player wins. Returns true when the bonus was granted.
function DailyRewardService.markFirstWin(player: Player): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("markFirstWin skipped for %s: profile not loaded", player.Name)
		return false
	end
	if not DailyStreak.markFirstWin(data.Daily, DailyStreak.dayIndex(os.time())) then
		return false
	end
	dataService.push(player, "Daily")
	local xp = progression.addXp(player, FIRST_WIN_XP, "FirstWinOfDay")
	local ryo = currency.add(player, FIRST_WIN_RYO, "FirstWinOfDay")
	notify.send(player, "daily.firstWin", { xp = xp, ryo = ryo }, "Success", "Claim")
	log.info("%s took the first win of the day (+%d XP, +%d Ryo)", player.Name, xp, ryo)
	return true
end

-- Roblox Premium bonus (DailyConfig.PremiumBonus), once per day. Returns true when it was granted.
function DailyRewardService.grantPremiumBonus(player: Player): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("grantPremiumBonus skipped for %s: profile not loaded", player.Name)
		return false
	end
	if not DailyStreak.markPremiumBonus(data.Daily, DailyStreak.dayIndex(os.time())) then
		return false
	end
	dataService.push(player, "Daily")
	local ryo = currency.add(player, PREMIUM_BONUS.Ryo, "PremiumBonus")
	local xp = progression.addXp(player, PREMIUM_BONUS.Xp, "PremiumBonus")
	notify.send(player, "daily.premium", { xp = xp, ryo = ryo }, "Success", "Claim")
	log.info("%s took the Premium bonus (+%d XP, +%d Ryo)", player.Name, xp, ryo)
	return true
end

local function onProfileLoaded(player: Player, data: ProfileData)
	local evaluation = DailyStreak.evaluate(data.Daily, DailyStreak.dayIndex(os.time()))
	-- Replicated as is: the client offers the claim, the server decides nothing on its own here.
	dataService.push(player, "Daily")
	if evaluation.Broken then
		notify.send(player, "daily.broken", nil, "Info")
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		DailyRewardService.grantPremiumBonus(player)
	end
end

function DailyRewardService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
	currency = deps.Currency
end

function DailyRewardService.Start()
	dataService.ProfileLoaded:Connect(onProfileLoaded)
	registry.on("ClaimDaily", function(player: Player)
		DailyRewardService.claim(player)
	end)
	log.info("started (%d streak days)", STREAK_LENGTH)
end

return DailyRewardService
