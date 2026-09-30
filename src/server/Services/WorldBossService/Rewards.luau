--!strict
-- Rewards: what a fight against the Erasure pays when the boss goes down (docs/GAME_DESIGN.md §7). Every
-- participant who removed at least WorldBossConfig.Rewards.MinShareToReward of its health is paid by that
-- share, with the kill bonus on top above KillBonusShare. The credited amounts come back from the services
-- (VIP and boost multipliers), so the toast never promises more than what was granted.
--
-- The scheduled event pays in full, counts a boss kill and advances the "BossKill" quest. A practice (D-132)
-- pays WorldBossConfig.Practice.RewardFactor of that and nothing else, and only under two caps, both kept in the
-- PROFILE because anything kept in a server's memory is escaped by joining another server: RewardsPerDay
-- (Daily.PracticeDay and PracticePaid, DailyCap.take), and one paid practice per RewardGapSeconds
-- (Daily.PracticeLastPaidAt, an os.time stamp), so a practice cannot be farmed back to back either (D-222). A
-- player refused by either is told why. Only a pay worth Practice.MinPaidFolios is charged to them: a share the
-- factor rounds to no Folio is paid its XP alone, free of both caps (BossPractice.charged).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BossPractice = require(script.Parent.Parent.Parent.Pure.BossPractice)
local Context = require(script.Parent.Context)
local DailyCap = require(script.Parent.Parent.Parent.Pure.DailyCap)
local DailyStreak = require(Shared.Pure.DailyStreak)
local Log = require(Shared.Util.Log)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldBossMode = require(script.Parent.Parent.Parent.GameModes.WorldBossMode)

local log = Log.new("WorldBoss.Rewards")

type Deps = Context.Deps

-- One fight's pay: who took part (user ids, in ring order), what they did (the rules state) and which kind of
-- fight it was.
export type PayContext = {
	Deps: Deps,
	State: WorldBossMode.State,
	Participants: { number },
	Kind: Context.Kind,
}

local PRACTICE = WorldBossConfig.Practice
local SECONDS_PER_MINUTE = 60
-- ProgressionService.addXp and CurrencyService.add refuse anything below one whole point (and warn): a line
-- a practice's factor rounded to nothing is simply not credited.
local MIN_AMOUNT = 1

local Rewards = {}

-- One quest event of QuestConfig ("BossParticipation" when a player is pulled into or joins the event,
-- "BossKill" when the boss goes down under them). A quest log that blew up never costs a reward.
function Rewards.reportQuest(deps: Deps, player: Player, event: string)
	local quest = deps.Quest
	if quest == nil then
		return
	end
	log.try("Quest.report " .. event, quest.report, player, event, 1)
end

local function bumpBossKills(deps: Deps, player: Player)
	local data = deps.DataService.get(player)
	if data == nil then
		return
	end
	data.Stats.BossKills += 1
	deps.DataService.push(player, "Stats")
end

-- Credits `reward` under the event's reasons and returns the XP and Folios the services actually granted.
local function credit(deps: Deps, player: Player, reward: WorldBossMode.Reward): (number, number)
	local xp, folios = 0, 0
	if reward.Xp >= MIN_AMOUNT then
		xp += deps.Progression.addXp(player, reward.Xp, "BossParticipation")
	end
	if reward.Folios >= MIN_AMOUNT then
		folios += deps.Currency.add(player, reward.Folios, "BossParticipation")
	end
	if reward.BonusXp >= MIN_AMOUNT then
		xp += deps.Progression.addXp(player, reward.BonusXp, "BossKillBonus")
		if reward.BonusFolios >= MIN_AMOUNT then
			folios += deps.Currency.add(player, reward.BonusFolios, "BossKillBonus")
		end
		deps.Notify.send(player, "boss.killBonus", nil, "Success")
	end
	return xp, folios
end

local function payEvent(ctx: PayContext): number
	local deps = ctx.Deps
	local paid = 0
	for _, player in ipairs(Context.livePlayers(ctx.Participants)) do
		local reward = WorldBossMode.rewardFor(WorldBossMode.shareOf(ctx.State, player.UserId))
		if reward ~= nil then
			local xp, folios = credit(deps, player, reward)
			bumpBossKills(deps, player)
			Rewards.reportQuest(deps, player, "BossKill")
			deps.Notify.send(player, "boss.reward", { xp = xp, folios = folios }, "Success", "Claim")
			paid += 1
		end
	end
	return paid
end

-- Whether a practice may pay `player` today, charging both caps in the profile when it may: one of the day's
-- paid practices, and the gap, which starts now. The gap is asked first, so a practice it refuses never spends
-- one of the day's paid practices.
local function practiceAllowed(ctx: PayContext, player: Player, today: number): boolean
	local deps = ctx.Deps
	local data = deps.DataService.get(player)
	if data == nil then
		log.warn("practice reward skipped for %s: profile not loaded", player.Name)
		return false
	end
	local daily = data.Daily
	local now = os.time()
	local last = daily.PracticeLastPaidAt
	if now - last < PRACTICE.RewardGapSeconds then
		local minutes = math.ceil((last + PRACTICE.RewardGapSeconds - now) / SECONDS_PER_MINUTE)
		deps.Notify.send(player, "boss.practice.noReward", { minutes = minutes }, "Info")
		return false
	end
	local granted, used = DailyCap.take(daily.PracticeDay, daily.PracticePaid, today, PRACTICE.RewardsPerDay, 1)
	local changed = daily.PracticeDay ~= today or daily.PracticePaid ~= used
	daily.PracticeDay = today
	daily.PracticePaid = used
	if granted >= 1 then
		daily.PracticeLastPaidAt = now
		changed = true
	end
	if changed then
		deps.DataService.push(player, "Daily")
	end
	if granted < 1 then
		deps.Notify.send(player, "boss.practice.dailyDone", nil, "Info")
		return false
	end
	return true
end

-- What a practice pays `player`, or nil for nothing. The reward is worked out first: only one worth
-- Practice.MinPaidFolios is a paid practice, which takes one of the day's allowance and starts the gap
-- (practiceAllowed) or is refused. Anything less -- a late joiner's sliver of a share -- is paid its XP alone
-- and charged nothing, so tagging along never spends the paid practices meant for a fight of their own.
local function practicePay(ctx: PayContext, player: Player, today: number): WorldBossMode.Reward?
	local share = WorldBossMode.shareOf(ctx.State, player.UserId)
	local reward = WorldBossMode.rewardFor(share, PRACTICE.RewardFactor)
	if reward == nil then
		return nil
	end
	if not BossPractice.charged(reward.Folios + reward.BonusFolios, PRACTICE.MinPaidFolios) then
		return { Xp = reward.Xp, Folios = 0, BonusXp = reward.BonusXp, BonusFolios = 0 }
	end
	if not practiceAllowed(ctx, player, today) then
		return nil
	end
	return reward
end

-- A practice: the event's reward scaled by RewardFactor, under both caps. No boss kill is counted and no
-- "BossKill" quest advances: both are the event's, and a practice opened at will must not farm them.
local function payPractice(ctx: PayContext): number
	local deps = ctx.Deps
	local today = DailyStreak.dayIndex(os.time())
	local paid = 0
	for _, player in ipairs(Context.livePlayers(ctx.Participants)) do
		local reward = practicePay(ctx, player, today)
		if reward ~= nil then
			local xp, folios = credit(deps, player, reward)
			deps.Notify.send(player, "boss.reward", { xp = xp, folios = folios }, "Success", "Claim")
			paid += 1
		end
	end
	return paid
end

-- Pays every participant of the fight that just went down, by the rules of its kind.
function Rewards.pay(ctx: PayContext)
	local paid = if ctx.Kind == "Practice" then payPractice(ctx) else payEvent(ctx)
	log.info("%s: %d participant(s) rewarded for %d damage", ctx.Kind, paid, math.floor(ctx.State.TotalDamage + 0.5))
end

return Rewards
