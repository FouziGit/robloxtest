--!strict
-- The pacing simulator (E10-S4): four players, sixty days, the real configs.
--
-- It plays each profile day after day through the rules the game ships -- the level curve, the pass's tier
-- cost and free track, the match, kill and quest rewards, the daily streak, the Forgers' and the Trials' daily
-- caps (TrialPay and DailyCap themselves), the quests each day and week really draws (QuestLogic, Solo floor
-- and free reroll included), the level road's milestones and the plates of the Ex-libris (ExLibris itself) and
-- the shop's real rotation -- and says how long things take: the minutes to
-- levels 5, 10, 20 and 40, the day the pass is finished, the Folios earned by day 7 and day 30, and the day the
-- catalogue a player can earn without Robux is complete.
--
-- What it cannot read from a config is how people play: how long a round lasts, how long the queue is, how
-- often a glyph lands. Those are `Pacing.Assumptions`, each with its reason, and nothing here was measured on a
-- live server. tests/Pacing.spec.luau holds the numbers that matter to their ceilings on every run of the gates.
--
--   lune run scripts/pacing -- --table   the summary docs/ECONOMY.md quotes
--   lune run scripts/pacing -- --csv     writes docs/economy/pacing.csv, one row per profile and day
--   lune run scripts/pacing -- --check   fails when that file is not what the configs give today

local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local BotConfig = require("../src/shared/Config/BotConfig")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DailyCap = require("../src/server/Pure/DailyCap")
local DailyConfig = require("../src/shared/Config/DailyConfig")
local DrillConfig = require("../src/shared/Config/DrillConfig")
local ExLibris = require("../src/shared/Pure/ExLibris")
local ExLibrisConfig = require("../src/shared/Config/ExLibrisConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local QuestLogic = require("../src/shared/Pure/QuestLogic")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local ShopRotation = require("../src/shared/Pure/ShopRotation")
local TrialPay = require("../src/server/Pure/TrialPay")
local fs = require("@lune/fs")
local process = require("@lune/process")

export type Activity = "Duel" | "Trials" | "Forgers"
export type Profile = { Id: string, Name: string, Minutes: { { Activity: Activity, Minutes: number } } }
export type Day = {
	Day: number,
	Minutes: number,
	Level: number,
	TotalXp: number,
	Tier: number,
	FoliosEarned: number,
	Folios: number,
	Owned: number,
}
export type Result = {
	Profile: Profile,
	MinutesToLevel: { [number]: number },
	PassDay: number?,
	FoliosByDay7: number,
	FoliosByDay30: number,
	CatalogueDay: number?,
	-- XP an hour of each activity paid, from that activity alone (no quest, streak or first win), and the
	-- Folios it paid over the whole run.
	XpPerHour: { [string]: number },
	ActivityFolios: { [string]: number },
	-- The pass XP each activity brought.
	ActivityPassXp: { [string]: number },
	-- The levels whose milestone was paid, in order, and the day each plate of the Ex-libris was earned.
	Milestones: { number },
	Plates: { [string]: number },
	Days: { Day },
}

local Pacing = {}

-- How people play, which no config says. Each is a guess to be replaced by a measurement (E8), and each is
-- here once.
Pacing.Assumptions = {
	Days = 60,
	-- A Monday, so the first week of quests is a whole one (QuestLogic.weekIndex).
	StartDay = 20731,
	-- A 1v1 between players of a level: the time in the queue at a small population, the portal there and
	-- back, and a round's fight (GAME_DESIGN §5 puts a kill at 12-15 s on a player who dodges badly; equals
	-- dodge). Matches go by fours, two won and two lost, one of each clean and one close (see DUELS).
	QueueSeconds = 45,
	TravelSeconds = 10,
	RoundFightSeconds = 50,
	-- Damage dealt in a round lost, as a share of a full health bar.
	LostRoundDamageShare = 0.6,
	LandShare = { Duel = 0.5, Trials = 1, Forgers = 0.7 },
	-- How much of a fight goes to M1 rather than moving, guarding and casting.
	MeleeShare = { Duel = 0.3, Trials = 1, Forgers = 0.5 },
	DashesPerMinute = 6,
	DashCancelsPerMinute = 1,
	-- Casts that follow the previous one inside the chain window. A player's best chain is taken as the longest
	-- whose expected count over their casts is one at least (a chain of k is k - 1 of these in a row).
	ChainShare = 0.2,
	-- A Forger fights back and walks: the share of a player's damage that reaches it, and the walk to the next.
	ForgerDamageShare = 0.6,
	ForgerApproachSeconds = 3,
}

Pacing.Profiles = {
	{
		Id = "Solo20",
		Name = "20 min/j seul",
		Minutes = { { Activity = "Trials", Minutes = 5 }, { Activity = "Forgers", Minutes = 15 } },
	},
	{ Id = "Pvp20", Name = "20 min/j en PvP", Minutes = { { Activity = "Duel", Minutes = 20 } } },
	{ Id = "Pvp60", Name = "60 min/j en PvP", Minutes = { { Activity = "Duel", Minutes = 60 } } },
	{ Id = "Farmer", Name = "fermier d'Épreuves", Minutes = { { Activity = "Trials", Minutes = 60 } } },
} :: { Profile }

Pacing.Levels = { 5, 10, 20, 40 }

local A = Pacing.Assumptions
local XP = (ProgressionConfig.XP :: any) :: { [string]: number }
local FOLIOS = (ProgressionConfig.Folios :: any) :: { [string]: number }
local PASS_EXCLUDED = ProgressionConfig.PassExcluded
local SEASON = BattlepassConfig.Seasons[GameConfig.SeasonId]
local DUEL = MatchConfig.Modes.Duel1v1
local DUEL_REWARDS = MatchConfig.Rewards.Duel1v1
local ENEMY = GameConfig.Enemy
local SECONDS_PER_DAY = 86400
-- The milestone each level pays when it is reached (HonoursService), and the kit's drills the Ex-libris reads.
local MILESTONES: { [number]: ProgressionConfig.Milestone } = {}
for _, milestone in ipairs(ProgressionConfig.Milestones) do
	MILESTONES[milestone.Level] = milestone
end
local KIT_IDS: { string } = {}
for _, kit in ipairs(DrillConfig.Kit) do
	table.insert(KIT_IDS, kit.Id)
end
local PERIODS: { QuestConfig.Period } = { "Daily", "Weekly" }
-- The events each activity produces, for the quests a profile can play and the ones it rerolls.
local PRODUCES: { [Activity]: { string } } = {
	Duel = {
		"MatchPlayed",
		"MatchWin",
		"PlayerKill",
		"GlyphCast",
		"GlyphHit",
		"DamageDealt",
		"Dash",
		"MeleeHit",
		"Chain",
		"DashCancel",
	},
	Trials = { "DummyKill", "GlyphCast", "GlyphHit", "DamageDealt", "Dash", "MeleeHit", "Chain", "DashCancel" },
	Forgers = { "BotKill", "GlyphCast", "GlyphHit", "DamageDealt", "Dash", "MeleeHit", "Chain", "DashCancel" },
}

----------------------------------------------------------------
-- Rates the configs give
----------------------------------------------------------------

-- The glyphs a new player has equipped: the default unlocks, as many as the base slots hold.
local function starterGlyphs(): { GlyphConfig.GlyphDef }
	local glyphs = {}
	for _, id in ipairs(GlyphConfig.defaultUnlocks()) do
		local def = GlyphConfig.byId(id)
		if def ~= nil and #glyphs < ProgressionConfig.Loadout.BaseSlots then
			table.insert(glyphs, def)
		end
	end
	return glyphs
end

-- Casts a second in a fight, as the ink in combat pays for them, and the damage a cast carries.
local function castRate(): (number, number)
	local cost, damage = 0, 0
	local glyphs = starterGlyphs()
	for _, def in ipairs(glyphs) do
		cost += def.Cost
		damage += def.Damage
	end
	return CombatConfig.Ink.RegenInCombat / (cost / #glyphs), damage / #glyphs
end

local CASTS_PER_SECOND, CAST_DAMAGE = castRate()

-- M1 damage and hits a second, a whole combo (its hits at the minimum interval, then the finisher's recovery)
-- at a time.
local function meleeDps(): (number, number)
	local total = 0
	for _, amount in ipairs(CombatConfig.Melee.Damage) do
		total += amount
	end
	local melee = CombatConfig.Melee
	local cycle = (#melee.Damage - 1) * melee.HitIntervalSeconds + melee.FinisherCooldownSeconds
	return total / cycle, #melee.Damage / cycle
end

local MELEE_DPS, MELEE_HITS_PER_SECOND = meleeDps()

-- The seconds a Trial proof takes to fell: its health at a player's whole damage, then the walk to the next
-- proof of the ring.
local function trialSeconds(): number
	local dps = MELEE_DPS * A.MeleeShare.Trials + CASTS_PER_SECOND * CAST_DAMAGE * A.LandShare.Trials
	local gap = 2 * ENEMY.DummyRingRadius * math.sin(math.pi / ENEMY.DummyCount)
	return ENEMY.DummyHealth / dps + gap / GameConfig.Movement.WalkSpeed
end

-- A lone player's Forgers, in the order their slots fill (BotConfig.Roster, BaseCount of them).
local function loneForgers(): { { Health: number, RewardKey: string } }
	local list = {}
	for slot = 1, BotConfig.BaseCount do
		local tier = (BotConfig.Tiers :: any)[BotConfig.Roster[slot]]
		table.insert(list, { Health = tier.Health, RewardKey = tier.RewardKey })
	end
	return list
end

local FORGERS = loneForgers()

-- A 1v1 from the queue to the hub: its rounds, each with its countdown and pause, then the result.
local function duelSeconds(rounds: number): number
	local perRound = DUEL.CountdownSeconds + A.RoundFightSeconds + MatchConfig.RoundOverSeconds
	return A.QueueSeconds + A.TravelSeconds + rounds * perRound + DUEL.ResultSeconds
end

----------------------------------------------------------------
-- One player
----------------------------------------------------------------

type Counts = { [string]: number }
type Periods<T> = { Daily: T, Weekly: T }
type Player = {
	Seconds: number,
	Level: number,
	LevelXp: number,
	TotalXp: number,
	Tier: number,
	PassXp: number,
	Folios: number,
	FoliosEarned: number,
	Owned: { [string]: boolean },
	ActivityXp: Counts,
	ActivityFolios: Counts,
	ActivityPassXp: Counts,
	ActivitySeconds: Counts,
	LevelAt: { [number]: number },
	PassDay: number?,
	Day: number,
	Daily: { ForgerDay: number, ForgerFolios: number, Trial: TrialPay.Ledger },
	Sets: Periods<QuestLogic.SetData>,
	Quests: Periods<{ QuestConfig.QuestDef }>,
	-- The events of the period so far, and the whole ones already handed to QuestLogic.applyEvent.
	Events: Periods<Counts>,
	Applied: Periods<Counts>,
	FirstWinDay: number,
	-- The lifetime measures the Ex-libris reads (Stats), the casts behind them, and what HonoursService paid.
	Casts: number,
	Stats: ExLibris.Stats,
	Milestones: { number },
	Plates: { [string]: number },
}

local function newPlayer(): Player
	local function set(): QuestLogic.SetData
		return { PeriodKey = "", Progress = {}, Claimed = {}, Swaps = {} }
	end
	return {
		Seconds = 0,
		Level = 1,
		LevelXp = 0,
		TotalXp = 0,
		Tier = 1,
		PassXp = 0,
		Folios = 0,
		FoliosEarned = 0,
		Owned = {},
		ActivityXp = {},
		ActivityFolios = {},
		ActivityPassXp = {},
		ActivitySeconds = {},
		LevelAt = {},
		PassDay = nil,
		Day = 0,
		Daily = { ForgerDay = 0, ForgerFolios = 0, Trial = { Day = 0, Kills = 0, Folios = 0 } },
		Sets = { Daily = set(), Weekly = set() },
		Quests = { Daily = {}, Weekly = {} },
		Events = { Daily = {}, Weekly = {} },
		Applied = { Daily = {}, Weekly = {} },
		FirstWinDay = 0,
		Casts = 0,
		Stats = { Kills = 0, MatchesPlayed = 0, GlyphsCast = 0, BestChain = 0, BossKills = 0 },
		Milestones = {},
		Plates = {},
	}
end

local function freeReward(player: Player, tier: number)
	local reward = SEASON.Tiers[tier].Free
	if reward == nil then
		return
	elseif reward.Kind == "Folios" then
		player.Folios += reward.Amount
		player.FoliosEarned += reward.Amount
	elseif reward.Kind == "Cosmetic" then
		player.Owned[reward.Id] = true
	end
end

local function grantFolios(player: Player, amount: number, activity: string?)
	player.Folios += amount
	player.FoliosEarned += amount
	if activity ~= nil then
		player.ActivityFolios[activity] = (player.ActivityFolios[activity] or 0) + amount
	end
end

-- XP from `reason`, as ProgressionService grants it: levels cascade, each reached level pays its milestone
-- (HonoursService, on LevelUp), and the pass takes it unless the source is one ProgressionConfig.PassExcluded
-- names. `activity` is the play it came from, for the hourly rates; a milestone is no activity's.
local function grantXp(player: Player, amount: number, reason: string, activity: string?)
	if amount <= 0 then
		return
	end
	player.TotalXp += amount
	if activity ~= nil then
		player.ActivityXp[activity] = (player.ActivityXp[activity] or 0) + amount
	end
	if player.Level < ProgressionConfig.MaxLevel then
		player.LevelXp += amount
		while
			player.Level < ProgressionConfig.MaxLevel
			and player.LevelXp >= ProgressionConfig.xpForLevel(player.Level)
		do
			player.LevelXp -= ProgressionConfig.xpForLevel(player.Level)
			player.Level += 1
			if table.find(Pacing.Levels, player.Level) ~= nil then
				player.LevelAt[player.Level] = player.Seconds / 60
			end
			local milestone = MILESTONES[player.Level]
			if milestone ~= nil then
				table.insert(player.Milestones, milestone.Level)
				grantFolios(player, milestone.Folios)
			end
		end
	end
	if PASS_EXCLUDED[reason] or player.Tier >= BattlepassConfig.MaxTier then
		return
	end
	local passXp = amount * ProgressionConfig.BattlepassXpMultiplier
	player.PassXp += passXp
	if activity ~= nil then
		player.ActivityPassXp[activity] = (player.ActivityPassXp[activity] or 0) + passXp
	end
	while player.Tier < BattlepassConfig.MaxTier and player.PassXp >= BattlepassConfig.xpForTier(player.Tier) do
		player.PassXp -= BattlepassConfig.xpForTier(player.Tier)
		player.Tier += 1
		freeReward(player, player.Tier)
	end
	if player.Tier >= BattlepassConfig.MaxTier and player.PassDay == nil then
		player.PassDay = player.Day
	end
end

-- The longest chain `casts` have likely reached: the longest whose expected count is one at least.
local function bestChain(casts: number): number
	local chain = if casts >= 1 then 1 else 0
	while chain < casts and casts * A.ChainShare ^ chain >= 1 do
		chain += 1
	end
	return chain
end

-- Every plate of the Ex-libris the lifetime measures now meet, granted once with its Folios (HonoursService,
-- ExLibris.due). No profile here fights the Erasure or does a drill: those measures stay at zero.
local function honours(player: Player)
	local facts = ExLibris.facts(player.Stats, {}, KIT_IDS)
	for _, plate in ipairs(ExLibrisConfig.Plates) do
		if ExLibris.due(plate, facts, player.Plates) then
			player.Plates[plate.Id] = player.Day
			grantFolios(player, plate.Folios)
		end
	end
end

-- `amount` of `event` against both periods; a quest whose count reaches its target is claimed on the spot.
local function report(player: Player, event: string, amount: number)
	for _, period in ipairs({ "Daily", "Weekly" } :: { QuestConfig.Period }) do
		local counts, applied = player.Events[period], player.Applied[period]
		counts[event] = (counts[event] or 0) + amount
		local whole = math.floor(counts[event])
		local set = player.Sets[period]
		local def = QuestConfig.Periods[period]
		QuestLogic.applyEvent(set, player.Quests[period], event, whole - (applied[event] or 0))
		applied[event] = whole
		for _, quest in ipairs(player.Quests[period]) do
			if QuestLogic.claim(set, quest) then
				grantXp(player, def.RewardXp, "Quest" .. period)
				grantFolios(player, def.RewardFolios)
			end
		end
	end
end

-- The share of a fight's events that happen in `seconds` of it.
local function fight(player: Player, activity: Activity, seconds: number, glyphXp: boolean)
	local casts = CASTS_PER_SECOND * seconds
	local landed = casts * A.LandShare[activity]
	player.Casts += casts
	player.Stats.GlyphsCast = math.floor(player.Casts)
	player.Stats.BestChain = bestChain(player.Casts)
	report(player, "GlyphCast", casts)
	report(player, "GlyphHit", landed)
	report(player, "Chain", casts * A.ChainShare)
	report(player, "MeleeHit", MELEE_HITS_PER_SECOND * A.MeleeShare[activity] * seconds)
	report(player, "Dash", A.DashesPerMinute * seconds / 60)
	report(player, "DashCancel", A.DashCancelsPerMinute * seconds / 60)
	-- A hit on a Trial proof pays no XP (GlyphService): the Trials pay by the kill.
	if glyphXp then
		grantXp(player, landed * XP.GlyphHit, "GlyphHit", activity)
	end
end

local function spend(player: Player, activity: Activity, seconds: number)
	player.Seconds += seconds
	player.ActivitySeconds[activity] = (player.ActivitySeconds[activity] or 0) + seconds
end

-- Four 1v1s between equals, in turn: a clean win, a close loss, a close win, a clean loss. Half the matches and
-- half the rounds won, whatever MatchConfig's RoundsToWin, and the day's first win comes with its first match.
local TO_WIN = DUEL.RoundsToWin
local DUELS = {
	{ Won = true, RoundsWon = TO_WIN, Rounds = TO_WIN },
	{ Won = false, RoundsWon = TO_WIN - 1, Rounds = 2 * TO_WIN - 1 },
	{ Won = true, RoundsWon = TO_WIN, Rounds = 2 * TO_WIN - 1 },
	{ Won = false, RoundsWon = 0, Rounds = TO_WIN },
}

-- One 1v1 of the day, the `index`th: its rounds, its kills and its result.
local function duel(player: Player, index: number): number
	local outcome = DUELS[(index - 1) % #DUELS + 1]
	local won, roundsWon, rounds = outcome.Won, outcome.RoundsWon, outcome.Rounds
	local seconds = duelSeconds(rounds)
	local fightSeconds = rounds * A.RoundFightSeconds
	spend(player, "Duel", seconds)
	fight(player, "Duel", fightSeconds, true)
	local health = CombatConfig.Health.Max
	report(player, "DamageDealt", health * (roundsWon + A.LostRoundDamageShare * (rounds - roundsWon)))
	player.Stats.MatchesPlayed += 1
	player.Stats.Kills += roundsWon
	for _ = 1, roundsWon do
		grantXp(player, XP.PlayerKill, "PlayerKill", "Duel")
		grantFolios(player, FOLIOS.PlayerKill, "Duel")
		report(player, "PlayerKill", 1)
	end
	local key = if won then "MatchWin" else "MatchLoss"
	grantXp(player, math.floor(XP[key] * DUEL_REWARDS.Xp + 0.5), key, "Duel")
	grantFolios(player, math.floor(FOLIOS[key] * DUEL_REWARDS.Folios + 0.5), "Duel")
	report(player, "MatchPlayed", 1)
	if won then
		report(player, "MatchWin", 1)
		if player.FirstWinDay ~= player.Day then
			player.FirstWinDay = player.Day
			grantXp(player, XP.FirstWinOfDay, "FirstWinOfDay")
			grantFolios(player, FOLIOS.FirstWinOfDay)
		end
	end
	return seconds
end

-- One Trial proof felled, paid by TrialPay on the day's ledger.
local function trial(player: Player, today: number): number
	local seconds = trialSeconds()
	spend(player, "Trials", seconds)
	fight(player, "Trials", seconds, false)
	report(player, "DamageDealt", ENEMY.DummyHealth)
	report(player, "DummyKill", 1)
	-- Counted whatever it pays (EnemyService).
	player.Stats.Kills += 1
	local pay = TrialPay.kill(player.Daily.Trial, today, ENEMY.Pay, XP.DummyKill, FOLIOS.DummyKill, DailyCap.take)
	player.Daily.Trial = pay.Ledger
	grantXp(player, pay.Xp, "DummyKill", "Trials")
	grantFolios(player, pay.Folios, "Trials")
	return seconds
end

-- One Forger felled, its Folios under BotConfig.Credit.DailyFolioCap.
local function forger(player: Player, today: number, index: number): number
	local target = FORGERS[(index - 1) % #FORGERS + 1]
	local dps = (MELEE_DPS * A.MeleeShare.Forgers + CASTS_PER_SECOND * CAST_DAMAGE * A.LandShare.Forgers)
		* A.ForgerDamageShare
	local seconds = target.Health / dps + A.ForgerApproachSeconds
	spend(player, "Forgers", seconds)
	fight(player, "Forgers", seconds, true)
	report(player, "DamageDealt", target.Health)
	report(player, "BotKill", 1)
	player.Stats.Kills += 1
	grantXp(player, XP[target.RewardKey], target.RewardKey, "Forgers")
	local daily = player.Daily
	local granted, used = DailyCap.take(
		daily.ForgerDay,
		daily.ForgerFolios,
		today,
		BotConfig.Credit.DailyFolioCap,
		FOLIOS[target.RewardKey]
	)
	daily.ForgerDay, daily.ForgerFolios = today, used
	grantFolios(player, granted, "Forgers")
	return seconds
end

----------------------------------------------------------------
-- Days
----------------------------------------------------------------

local function produces(profile: Profile): { [string]: boolean }
	local events = {}
	for _, entry in ipairs(profile.Minutes) do
		for _, event in ipairs(PRODUCES[entry.Activity]) do
			events[event] = true
		end
	end
	return events
end

-- The day's and the week's quests, drawn as QuestService draws them, and the day's free reroll spent on the
-- first daily quest this profile's play can never advance.
local function drawQuests(player: Player, profile: Profile, today: number)
	local unix = today * SECONDS_PER_DAY
	-- Indexed and annotated, as QuestService does: an `in` iteration widens the period literals to strings.
	for index = 1, #PERIODS do
		local period: QuestConfig.Period = PERIODS[index]
		local key = QuestLogic.setKey(QuestLogic.periodKey(period, unix), QuestConfig.PoolRevision)
		local set = player.Sets[period]
		if QuestLogic.ensurePeriod(set, key) then
			player.Events[period] = {}
			player.Applied[period] = {}
		end
	end
	local set = player.Sets.Daily
	local rules: QuestLogic.RerollRules = {
		Pool = QuestConfig.Pool,
		Count = QuestConfig.Periods.Daily.Count,
		Floor = QuestConfig.SoloFloor,
		Allowance = QuestConfig.Rerolls.Daily,
	}
	local playable = produces(profile)
	local drawn = QuestLogic.select(QuestConfig.Pool, "Daily", rules.Count, set.PeriodKey, rules.Floor)
	for _, quest in ipairs(QuestLogic.swapped(QuestConfig.Pool, drawn, set.Swaps)) do
		if not playable[quest.Event] then
			QuestLogic.reroll(rules, "Daily", set, quest.Id)
			break
		end
	end
	for index = 1, #PERIODS do
		local period: QuestConfig.Period = PERIODS[index]
		local periodSet = player.Sets[period]
		local count = QuestConfig.Periods[period].Count
		local base = QuestLogic.select(QuestConfig.Pool, period, count, periodSet.PeriodKey, QuestConfig.SoloFloor)
		player.Quests[period] = QuestLogic.swapped(QuestConfig.Pool, base, periodSet.Swaps)
	end
end

-- Everything a player can own without Robux: the shop's items and the free track's.
local function earnable(): { [string]: boolean }
	local items = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Sellable then
			items[item.Id] = true
		end
	end
	for _, tier in ipairs(SEASON.Tiers) do
		local reward = tier.Free
		if reward ~= nil and reward.Kind == "Cosmetic" then
			items[reward.Id] = true
		end
	end
	return items
end

local EARNABLE = earnable()

-- The day's rotation, bought cheapest first while the Folios last.
local function shop(player: Player, today: number)
	local offered = ShopRotation.select(
		(CosmeticConfig.Items :: any) :: { ShopRotation.Item },
		ShopRotation.dayKey(today * SECONDS_PER_DAY),
		ShopConfig.Rotation,
		ShopConfig.RarityOrder
	)
	local rarity: { [string]: string } = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		rarity[item.Id] = item.Rarity
	end
	table.sort(offered, function(a: string, b: string): boolean
		return ShopConfig.PriceFolios[rarity[a]] < ShopConfig.PriceFolios[rarity[b]]
	end)
	for _, id in ipairs(offered) do
		local price = ShopConfig.PriceFolios[rarity[id]]
		if not player.Owned[id] and player.Folios >= price then
			player.Folios -= price
			player.Owned[id] = true
		end
	end
end

local function ownedEarnable(player: Player): (number, boolean)
	local owned, all = 0, true
	for id in pairs(EARNABLE) do
		if player.Owned[id] then
			owned += 1
		else
			all = false
		end
	end
	return owned, all
end

local function playDay(player: Player, profile: Profile, day: number)
	local today = A.StartDay + day - 1
	player.Day = day
	local streak = DailyConfig.Streak[(day - 1) % #DailyConfig.Streak + 1]
	grantXp(player, streak.Xp, "DailyStreak")
	grantFolios(player, streak.Folios)
	drawQuests(player, profile, today)
	for _, entry in ipairs(profile.Minutes) do
		local budget = entry.Minutes * 60
		local used, index = 0, 0
		while used < budget do
			index += 1
			if entry.Activity == "Duel" then
				used += duel(player, index)
			elseif entry.Activity == "Trials" then
				used += trial(player, today)
			else
				used += forger(player, today, index)
			end
			honours(player)
		end
	end
	shop(player, today)
end

function Pacing.simulate(profile: Profile): Result
	local player = newPlayer()
	local days: { Day } = {}
	local foliosBy: { [number]: number } = {}
	local catalogueDay: number? = nil
	for day = 1, A.Days do
		playDay(player, profile, day)
		local owned, complete = ownedEarnable(player)
		if complete and catalogueDay == nil then
			catalogueDay = day
		end
		foliosBy[day] = player.FoliosEarned
		table.insert(days, {
			Day = day,
			Minutes = math.floor(player.Seconds / 60 + 0.5),
			Level = player.Level,
			TotalXp = math.floor(player.TotalXp + 0.5),
			Tier = player.Tier,
			FoliosEarned = math.floor(player.FoliosEarned + 0.5),
			Folios = math.floor(player.Folios + 0.5),
			Owned = owned,
		})
	end
	local perHour: { [string]: number } = {}
	for activity, seconds in pairs(player.ActivitySeconds) do
		perHour[activity] = (player.ActivityXp[activity] or 0) / (seconds / 3600)
	end
	return {
		Profile = profile,
		MinutesToLevel = player.LevelAt,
		PassDay = player.PassDay,
		FoliosByDay7 = math.floor(foliosBy[7] + 0.5),
		FoliosByDay30 = math.floor(foliosBy[30] + 0.5),
		CatalogueDay = catalogueDay,
		XpPerHour = perHour,
		ActivityFolios = player.ActivityFolios,
		ActivityPassXp = player.ActivityPassXp,
		Milestones = player.Milestones,
		Plates = player.Plates,
		Days = days,
	}
end

-- Every profile, in Pacing.Profiles order.
function Pacing.all(): { Result }
	local results = {}
	for _, profile in ipairs(Pacing.Profiles) do
		table.insert(results, Pacing.simulate(profile))
	end
	return results
end

-- The pass's whole cost, tier 1 to MaxTier.
function Pacing.passCost(): number
	local total = 0
	for tier = 1, BattlepassConfig.MaxTier - 1 do
		total += BattlepassConfig.xpForTier(tier)
	end
	return total
end

----------------------------------------------------------------
-- Output
----------------------------------------------------------------

local CSV_PATH = "docs/economy/pacing.csv"

local function cell(value: number?): string
	if value == nil then
		return "—"
	end
	return tostring(math.floor(value + 0.5))
end

function Pacing.csv(results: { Result }): string
	local lines = { "profil,jour,minutes,niveau,xp_totale,palier,folios_gagnes,folios_en_poche,objets_possedes" }
	for _, result in ipairs(results) do
		for _, day in ipairs(result.Days) do
			table.insert(
				lines,
				table.concat({
					result.Profile.Id,
					tostring(day.Day),
					tostring(day.Minutes),
					tostring(day.Level),
					tostring(day.TotalXp),
					tostring(day.Tier),
					tostring(day.FoliosEarned),
					tostring(day.Folios),
					tostring(day.Owned),
				}, ",")
			)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

local function summarize(results: { Result })
	local total = 0
	for _ in pairs(EARNABLE) do
		total += 1
	end
	print("| Profil | Niv. 5 | Niv. 10 | Niv. 20 | Niv. 40 | Pass fini | Folios J7 | Folios J30 | Catalogue complet |")
	print("|---|---|---|---|---|---|---|---|---|")
	for _, result in ipairs(results) do
		local levels = {}
		for _, level in ipairs(Pacing.Levels) do
			local minutes = result.MinutesToLevel[level]
			table.insert(levels, if minutes ~= nil then cell(minutes) .. " min" else "—")
		end
		print(
			("| %s | %s | J%s | %s | %s | %s |"):format(
				result.Profile.Name,
				table.concat(levels, " | "),
				cell(result.PassDay),
				cell(result.FoliosByDay7),
				cell(result.FoliosByDay30),
				if result.CatalogueDay ~= nil then "J" .. cell(result.CatalogueDay) else "après J" .. A.Days
			)
		)
	end
	print("")
	for _, result in ipairs(results) do
		for activity, rate in pairs(result.XpPerHour) do
			print(("XP/h %s (%s) : %s"):format(activity, result.Profile.Name, cell(rate)))
		end
	end
	print(("Coût du pass : %s XP ; %d objets gagnables sans Robux."):format(cell(Pacing.passCost()), total))
end

for _, argument in ipairs(process.args) do
	if argument == "--table" then
		summarize(Pacing.all())
	elseif argument == "--csv" then
		fs.writeFile(CSV_PATH, Pacing.csv(Pacing.all()))
		print("wrote " .. CSV_PATH)
	elseif argument == "--check" then
		local existing = if fs.isFile(CSV_PATH) then fs.readFile(CSV_PATH) else ""
		if existing ~= Pacing.csv(Pacing.all()) then
			print(CSV_PATH .. " is out of date: run `lune run scripts/pacing -- --csv`")
			process.exit(1)
		end
		print(CSV_PATH .. " up to date")
	end
end

return Pacing
