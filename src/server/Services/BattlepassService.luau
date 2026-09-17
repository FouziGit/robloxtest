--!strict
-- BattlepassService: seasonal pass XP, tier cascade and reward claims. Pass XP mirrors player XP
-- (forwarded by ProgressionService). The single writer of Battlepass[season].

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlepassConfig = require(Shared.Config.BattlepassConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("BattlepassService")

export type Track = "Free" | "Premium"

type ProfileData = Types.ProfileData
type SeasonData = Types.BattlepassSeasonData
type Reward = BattlepassConfig.Reward
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> () }
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> () }
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Currency: CurrencyApi,
	Progression: ProgressionApi,
}

local SEASON = GameConfig.SeasonId
-- The profile schema has no timed-boost field, so an XpBoost reward is paid out immediately as the
-- XP of one match win per this many boost minutes.
local BOOST_MINUTES_PER_MATCH_WIN = 30

local BattlepassService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local currency: CurrencyApi
local progression: ProgressionApi

local function isPositiveInteger(value: number): boolean
	return value == value and value ~= math.huge and value == math.floor(value) and value > 0
end

-- Season record of the loaded profile (DataService guarantees the current season exists).
local function seasonOf(player: Player, data: ProfileData): SeasonData?
	local season = data.Battlepass[SEASON]
	if season == nil then
		log.error("season %s missing for %s", SEASON, player.Name)
	end
	return season
end

-- Converts XP into tiers. Terminates because Tier strictly increases towards MaxTier and every step
-- costs a positive amount. Notifies once per tier gained.
local function cascade(player: Player, season: SeasonData)
	local maxTier = BattlepassConfig.MaxTier
	while season.Tier < maxTier do
		local needed = BattlepassConfig.xpForTier(season.Tier)
		if needed <= 0 then
			log.error("xpForTier(%d) = %d, cascade stopped", season.Tier, needed)
			break
		end
		if season.XP < needed then
			break
		end
		season.XP -= needed
		season.Tier += 1
		notify.send(player, "hud.tierUp", { tier = season.Tier }, "Success", "TierUp")
	end
	if season.Tier >= maxTier then
		season.Tier = maxTier
		season.XP = 0
	end
end

function BattlepassService.addXp(player: Player, amount: number)
	if not isPositiveInteger(amount) then
		log.warn("addXp rejected for %s: invalid amount %s", player.Name, tostring(amount))
		return
	end
	local data = dataService.get(player)
	if data == nil then
		log.warn("addXp skipped for %s: profile not loaded", player.Name)
		return
	end
	local season = seasonOf(player, data)
	if season == nil then
		return
	end
	if season.Tier >= BattlepassConfig.MaxTier then
		return
	end
	local previousTier = season.Tier
	season.XP += amount
	cascade(player, season)
	dataService.push(player, "Battlepass")
	if season.Tier > previousTier then
		log.info("%s reached pass tier %d", player.Name, season.Tier)
	end
end

local function grant(player: Player, data: ProfileData, reward: Reward)
	if reward.Kind == "Ryo" then
		currency.add(player, reward.Amount, "Battlepass")
		notify.send(player, "battlepass.reward.ryo", { amount = reward.Amount }, "Success", "Claim")
	elseif reward.Kind == "Cosmetic" then
		if table.find(data.Cosmetics.Owned, reward.Id) == nil then
			table.insert(data.Cosmetics.Owned, reward.Id)
			dataService.push(player, "Cosmetics")
		end
		notify.send(player, "battlepass.reward.cosmetic", { name = "cosmetic." .. reward.Id }, "Success", "Claim")
	else
		local amount = math.floor(ProgressionConfig.XP.MatchWin * reward.Minutes / BOOST_MINUTES_PER_MATCH_WIN)
		progression.addXp(player, amount, "BattlepassBoost")
		notify.send(player, "battlepass.reward.xpBoost", { minutes = reward.Minutes }, "Success", "Claim")
	end
end

-- Claims the reward of `tier` on `track`. Returns true when a reward was granted; every refusal is
-- explained to the player through Notify.
function BattlepassService.claim(player: Player, tier: number, track: Track): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("claim skipped for %s: profile not loaded", player.Name)
		return false
	end
	local season = seasonOf(player, data)
	if season == nil then
		return false
	end
	local tierDef = BattlepassConfig.getTier(SEASON, tier)
	if tierDef == nil then
		log.warn("claim rejected for %s: tier %d not defined in season %s", player.Name, tier, SEASON)
		return false
	end

	if tier > season.Tier then
		notify.send(player, "battlepass.notReached", { tier = tier }, "Error")
		return false
	end
	if track == "Premium" and not season.Premium then
		notify.send(player, "battlepass.premiumRequired", nil, "Error")
		return false
	end
	local claimed = if track == "Premium" then season.ClaimedPremium else season.ClaimedFree
	local key = tostring(tier)
	if claimed[key] == true then
		notify.send(player, "battlepass.alreadyClaimed", nil, "Error")
		return false
	end
	local reward = if track == "Premium" then tierDef.Premium else tierDef.Free
	if reward == nil then
		log.warn("claim rejected for %s: tier %d has no %s reward", player.Name, tier, track)
		return false
	end

	-- Mark before granting so a re-entrant claim cannot pay twice.
	claimed[key] = true
	dataService.push(player, "Battlepass")
	grant(player, data, reward)
	log.info("%s claimed tier %d (%s): %s", player.Name, tier, track, reward.Kind)
	return true
end

function BattlepassService.isPremium(player: Player): boolean
	local data = dataService.get(player)
	if data == nil then
		return false
	end
	local season = data.Battlepass[SEASON]
	return season ~= nil and season.Premium == true
end

function BattlepassService.setPremium(player: Player, value: boolean)
	local data = dataService.get(player)
	if data == nil then
		log.warn("setPremium skipped for %s: profile not loaded", player.Name)
		return
	end
	local season = seasonOf(player, data)
	if season == nil then
		return
	end
	season.Premium = value
	dataService.push(player, "Battlepass")
	log.info("%s premium = %s", player.Name, tostring(value))
end

function BattlepassService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	currency = deps.Currency
	progression = deps.Progression
end

function BattlepassService.Start()
	registry.on("ClaimBattlepassReward", function(player: Player, tier: number, track: Track)
		BattlepassService.claim(player, tier, track)
	end)
	log.info("started (season %s, %d tiers)", SEASON, BattlepassConfig.MaxTier)
end

return BattlepassService
