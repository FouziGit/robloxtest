--!strict
-- DailyRewardService: the single writer of ProfileData.Daily. The login calendar (DailyConfig.Calendar) and its
-- Signets, first win of the day and the Roblox Premium daily bonus, all decided from Pure/DailyStreak.
--
-- Nothing is auto-claimed: the streak is evaluated when the profile loads and the section is
-- replicated so the client can offer the claim; only ClaimDaily pays it. The Premium bonus is the one
-- exception, because the player does nothing to earn it: it is paid when the profile loads, and when a
-- player becomes Premium during the session (PlayerMembershipChanged), once per UTC day either way.
--
-- A calendar day that ends a week gives its cosmetic through CosmeticService, and, when the profile owns it
-- already (a second month), DailyConfig.OwnedCosmeticFolios instead: a grant is never paid twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CosmeticConfig = require(Shared.Config.CosmeticConfig)
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
-- Idempotent: false when the cosmetic is owned already (or cannot be given), which the calendar pays in Folios.
type CosmeticApi = { grant: (player: Player, cosmeticId: string) -> boolean }
-- The single writer of ProfileData.Boosts (D-30): it extends a live boost instead of shortening it.
type BattlepassApi = { grantXpBoost: (player: Player, minutes: number) -> boolean }
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	Battlepass: BattlepassApi,
	Cosmetic: CosmeticApi,
}

local CALENDAR = DailyConfig.Calendar
local CALENDAR_LENGTH = #CALENDAR
local FIRST_WIN_XP = ProgressionConfig.XP.FirstWinOfDay
local FIRST_WIN_FOLIOS = ProgressionConfig.Folios.FirstWinOfDay
local PREMIUM_BONUS = DailyConfig.PremiumBonus
local OWNED_COSMETIC_FOLIOS = DailyConfig.OwnedCosmeticFolios

local DailyRewardService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi
local currency: CurrencyApi
local battlepass: BattlepassApi
local cosmetic: CosmeticApi

-- The cosmetic a calendar day ends its week on, given now. Returns its NameKey when it was, nil when the day has
-- none or the profile owns it already -- the day then pays OwnedCosmeticFolios more.
local function grantCosmetic(player: Player, day: DailyConfig.CalendarDay): string?
	local cosmeticId = day.Cosmetic
	if cosmeticId == nil then
		return nil
	end
	if not cosmetic.grant(player, cosmeticId) then
		return nil
	end
	local item = CosmeticConfig.ById[cosmeticId]
	return if item ~= nil then item.NameKey else nil
end

-- Claims today's calendar day. The section is replicated on every path, including a refusal, so the client never
-- stays pending. Returns true when a reward was granted.
function DailyRewardService.claim(player: Player): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("claim skipped for %s: profile not loaded", player.Name)
		return false
	end
	local daily = data.Daily
	local evaluation = DailyStreak.claim(daily, DailyStreak.dayIndex(os.time()), CALENDAR_LENGTH)
	local day = CALENDAR[daily.CalendarDay]
	-- The Signet the day slips in, into a book that is not full: it is written with the claim.
	local signet = evaluation.CanClaim
		and day ~= nil
		and day.Signet == true
		and DailyStreak.addSignet(daily, DailyConfig.MaxSignets)
	dataService.push(player, "Daily")
	if not evaluation.CanClaim then
		log.warn("claim refused for %s: already claimed today", player.Name)
		return false
	end
	if day == nil then
		log.error("no calendar entry for day %d (%d days)", daily.CalendarDay, CALENDAR_LENGTH)
		return false
	end
	local granted = grantCosmetic(player, day)
	local owned = day.Cosmetic ~= nil and granted == nil
	local folios = currency.add(player, day.Folios + (if owned then OWNED_COSMETIC_FOLIOS else 0), "DailyStreak")
	local xp = progression.addXp(player, day.Xp, "DailyStreak")
	notify.send(player, "daily.claimed", { day = daily.CalendarDay, xp = xp, folios = folios }, "Success", "Claim")
	if granted ~= nil then
		notify.send(player, "daily.cosmetic", { name = granted }, "Success")
	end
	if evaluation.SignetsUsed > 0 then
		notify.send(player, "daily.signetUsed", nil, "Success")
	end
	if signet then
		notify.send(player, "daily.signetEarned", nil, "Info")
	end
	log.info(
		"%s claimed day %d, streak %d (+%d XP, +%d Folios%s, %d Signet(s) spent, %d held)",
		player.Name,
		daily.CalendarDay,
		daily.Streak,
		xp,
		folios,
		if granted ~= nil then ", " .. tostring(day.Cosmetic) else "",
		evaluation.SignetsUsed,
		daily.Signets
	)
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
	local folios = currency.add(player, FIRST_WIN_FOLIOS, "FirstWinOfDay")
	notify.send(player, "daily.firstWin", { xp = xp, folios = folios }, "Success", "Claim")
	log.info("%s took the first win of the day (+%d XP, +%d Folios)", player.Name, xp, folios)
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
	local folios = currency.add(player, PREMIUM_BONUS.Folios, "PremiumBonus")
	local minutes = PREMIUM_BONUS.BoostMinutes
	log.succeeded("grantXpBoost", battlepass.grantXpBoost, player, minutes)
	notify.send(player, "daily.premium", { folios = folios, minutes = minutes }, "Success", "Claim")
	log.info("%s took the Premium bonus (+%d Folios, %d min XP boost)", player.Name, folios, minutes)
	return true
end

local function isPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

local function onProfileLoaded(player: Player, data: ProfileData)
	local evaluation = DailyStreak.evaluate(data.Daily, DailyStreak.dayIndex(os.time()), CALENDAR_LENGTH)
	-- Replicated as is: the client offers the claim, the server decides nothing on its own here.
	dataService.push(player, "Daily")
	if evaluation.Broken then
		notify.send(player, "daily.broken", nil, "Info")
	elseif evaluation.SignetsUsed > 0 then
		-- Nothing is spent yet: the claim spends the Signet, and today's claim is what keeps the streak.
		notify.send(player, "daily.signetSaves", nil, "Info")
	end
	if isPremium(player) then
		DailyRewardService.grantPremiumBonus(player)
	end
end

-- A player who subscribes during the session gets today's bonus at once, not at the next join. Before the
-- profile has loaded there is nothing to pay into, and onProfileLoaded pays it then.
local function onMembershipChanged(player: Player)
	if isPremium(player) and dataService.get(player) ~= nil then
		DailyRewardService.grantPremiumBonus(player)
	end
end

function DailyRewardService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
	currency = deps.Currency
	battlepass = deps.Battlepass
	cosmetic = deps.Cosmetic
end

function DailyRewardService.Start()
	dataService.ProfileLoaded:Connect(onProfileLoaded)
	Players.PlayerMembershipChanged:Connect(onMembershipChanged)
	registry.on("ClaimDaily", function(player: Player)
		DailyRewardService.claim(player)
	end)
	log.info("started (%d calendar days, %d Signets at most)", CALENDAR_LENGTH, DailyConfig.MaxSignets)
end

return DailyRewardService
