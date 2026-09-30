--!strict
-- Rewards: what a fallen Forger pays (D-131). The killer and everyone whose damage reached
-- BotConfig.Credit.AssistShare of its health are paid -- if they are members, and not from where a Forger
-- cannot answer: the camp, a place it has given up reaching, or UnreachableSeconds off the floor. Nothing dealt
-- from the camp counts toward a share at all (BotBrain.creditHit).
--
-- XP is never capped. Folios stop at DailyFolioCap a day, counted in the PROFILE (Daily.ForgerDay and
-- ForgerFolios, DailyCap.take): a count kept in a server's memory is escaped by joining another server. Past
-- the cap a kill pays XP alone, and the player is told once per day and per session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlegroundLayout = require(Shared.Pure.BattlegroundLayout)
local BotBrain = require(Shared.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Bots = require(script.Parent.Bots)
local Context = require(script.Parent.Context)
local DailyCap = require(Shared.Pure.DailyCap)
local DailyStreak = require(Shared.Pure.DailyStreak)
local Map = require(script.Parent.Map)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Roster = require(script.Parent.Roster)

type Bot = Bots.Bot

local CREDIT = BotConfig.Credit
local XP = (ProgressionConfig.XP :: any) :: { [string]: number }
local FOLIOS = (ProgressionConfig.Folios :: any) :: { [string]: number }

local Rewards = {}

local deps: Context.Deps
local handle: Map.Handle
-- Player -> the day they were last told the Forgers pay no more Folios.
local capToldOn: { [Player]: number } = {}

-- Takes today's Folios for one kill from the profile's allowance and writes the count back. Returns what may
-- be paid, before VIP (CurrencyService applies it); nil with no profile loaded, which is no cap reached.
local function takeFolios(player: Player, key: string, today: number): number?
	local data = deps.DataService.get(player)
	if data == nil then
		return nil
	end
	local daily = data.Daily
	local granted, used = DailyCap.take(daily.ForgerDay, daily.ForgerFolios, today, CREDIT.DailyFolioCap, FOLIOS[key])
	if daily.ForgerDay ~= today or daily.ForgerFolios ~= used then
		daily.ForgerDay = today
		daily.ForgerFolios = used
		deps.DataService.push(player, "Daily")
	end
	return granted
end

local function countKill(player: Player)
	local data = deps.DataService.get(player)
	if data == nil then
		return
	end
	data.Stats.Kills += 1
	deps.DataService.push(player, "Stats")
end

local function payOne(player: Player, member: Roster.Member, key: string, killer: boolean)
	local xp = deps.Progression.addXp(player, XP[key], key)
	local today = DailyStreak.dayIndex(os.time())
	local folios = takeFolios(player, key, today)
	if folios ~= nil and folios >= 1 then
		deps.Currency.add(player, folios, key)
	elseif folios ~= nil and capToldOn[player] ~= today then
		capToldOn[player] = today
		deps.Notify.send(player, "battleground.folioCap", nil, "Info")
	end
	-- Only the killer's own tally counts a kill, as a training proof's does (EnemyService).
	if killer then
		countKill(player)
	end
	deps.Quest.report(player, "BotKill", 1)
	deps.Notify.send(player, "hud.killReward", { xp = xp }, "Success", "Kill")
	member.Defeated += 1
	Roster.pushSnapshot(member)
end

-- Pays the Forger's kill to its killer and its assists, each once. A kill with no player behind it (0) pays
-- nobody, whoever had hurt the Forger before: the page's own deaths are not a reward. Nor does a tier with no
-- RewardKey: a spar's Duelist, whose duel pays through its result.
function Rewards.pay(bot: Bot, killerUserId: number, now: number)
	local key = bot.Def.RewardKey
	if killerUserId == 0 or key == nil then
		return
	end
	for _, userId in
		ipairs(BotBrain.creditedUsers(killerUserId, bot.Ledger, bot.Humanoid.MaxHealth, CREDIT.AssistShare))
	do
		local player = Players:GetPlayerByUserId(userId)
		local member = if player ~= nil then Roster.get(player) else nil
		local point = if player ~= nil then Context.targetPoint(deps.Combat, player) else nil
		if player ~= nil and member ~= nil and point ~= nil then
			local x, _, z = Context.toLocal(point)
			local inCamp = BattlegroundLayout.inRect(handle.Layout.Camp, x, z)
			local ignoredUntil = bot.Memory.IgnoreUntil[userId] or 0
			if BotBrain.creditable(inCamp, ignoredUntil, member.OffFloorSince, now, Context.Rules) then
				payOne(player, member, key, userId == killerUserId)
			end
		end
	end
end

function Rewards.forget(player: Player)
	capToldOn[player] = nil
end

function Rewards.Init(injected: Context.Deps, map: Map.Handle)
	deps = injected
	handle = map
end

return Rewards
