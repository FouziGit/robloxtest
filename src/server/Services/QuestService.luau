--!strict
-- QuestService: the single writer of ProfileData.Quests. The active set of a period is selected
-- deterministically from QuestConfig.Pool for the current period key (QuestLogic.select), so every
-- player on every server shares the same daily / weekly quests and the client can rebuild the list
-- from the replicated section alone. A day or week rollover resets the set (QuestLogic.ensurePeriod).
--
-- This service never decides that a gameplay event happened: the services that own the gameplay call
-- `report(player, event, amount)` with the event strings QuestConfig documents. The only signal it
-- subscribes to is CombatService.Killed, which already tells who killed what.
--
-- Progress pushes are coalesced on one Heartbeat accumulator (a DamageDealt quest would otherwise
-- replicate the section on every hit); a completion, a claim and a period reset push immediately.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local QuestConfig = require(Shared.Config.QuestConfig)
local QuestLogic = require(Shared.Pure.QuestLogic)
local Types = require(Shared.Types)

local log = Log.new("QuestService")

export type Period = QuestConfig.Period
export type Status = QuestLogic.Status

type ProfileData = Types.ProfileData
type SetData = Types.QuestSetData
type QuestDef = QuestConfig.QuestDef
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type ReleasedSignal = { Connect: (self: ReleasedSignal, fn: (player: Player) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
	ProfileReleased: ReleasedSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> number }
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> number }
type KilledSignal = { Connect: (self: KilledSignal, fn: (sourceUserId: number, victimModel: Model) -> ()) -> any }
type DamagedSignal = {
	Connect: (
		self: DamagedSignal,
		fn: (sourceUserId: number, targetModel: Model, applied: number, kind: string) -> ()
	) -> any,
}
type DashedSignal = { Connect: (self: DashedSignal, fn: (player: Player) -> ()) -> any }
type CombatApi = { Killed: KilledSignal, Damaged: DamagedSignal, Dashed: DashedSignal }
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	Combat: CombatApi,
}

-- One period's live quests, cached until its period key changes.
type Selection = { PeriodKey: string, Quests: { QuestDef } }

local PERIOD_ORDER: { Period } = { "Daily", "Weekly" }
-- Keyed by period id so a Period value reads as a plain string key.
local PERIOD_DEFS = (QuestConfig.Periods :: any) :: { [string]: { Count: number, RewardXp: number, RewardRyo: number } }
local ENEMY_TAG = GameConfig.Enemy.Tag
-- Types.DamageKind value that makes a damage application a landed melee hit.
local MELEE_KIND: Types.DamageKind = "Melee"
-- Coalescing window of the progress pushes.
local PUSH_INTERVAL_SECONDS = 1

local QuestService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi
local currency: CurrencyApi
local combat: CombatApi

local selections: { [string]: Selection } = {}
-- Players whose Quests section changed since the last flush.
local pending: { [Player]: true } = {}
local accumulator = 0

local function isPositiveInteger(value: number): boolean
	return value == value and value ~= math.huge and value == math.floor(value) and value > 0
end

local function setFor(data: ProfileData, period: Period): SetData
	if period == "Daily" then
		return data.Quests.Daily
	end
	return data.Quests.Weekly
end

local function push(player: Player)
	pending[player] = nil
	dataService.push(player, "Quests")
end

-- Live quests of `period` for the period containing `now`. Deterministic, so the cache is shared by
-- every player and only rebuilt on a rollover.
local function selectionFor(period: Period, now: number): Selection
	local periodKey = QuestLogic.periodKey(period, now)
	local cached = selections[period]
	if cached ~= nil and cached.PeriodKey == periodKey then
		return cached
	end
	local selection: Selection = {
		PeriodKey = periodKey,
		Quests = QuestLogic.select(QuestConfig.Pool, period, PERIOD_DEFS[period].Count, periodKey),
	}
	selections[period] = selection
	log.info("%s set %s: %d quests", period, periodKey, #selection.Quests)
	return selection
end

-- Aligns the stored set with the live period and hands back both. A rollover clears the progress and
-- is replicated at once so the client never shows yesterday's quests.
local function ensureSet(player: Player, data: ProfileData, period: Period, now: number): (SetData, { QuestDef })
	local selection = selectionFor(period, now)
	local set = setFor(data, period)
	if QuestLogic.ensurePeriod(set, selection.PeriodKey) then
		push(player)
		log.info("%s: %s quests reset for %s", player.Name, period, selection.PeriodKey)
	end
	return set, selection.Quests
end

-- True when `event` can still advance one of the active quests. A read-only relevance test: it keeps
-- an irrelevant event from dirtying the section, while QuestLogic.applyEvent stays the only place
-- that decides what the progress becomes.
local function tracks(set: SetData, quests: { QuestDef }, event: string): boolean
	for _, def in ipairs(quests) do
		if def.Event == event and not set.Claimed[def.Id] and (set.Progress[def.Id] or 0) < def.Target then
			return true
		end
	end
	return false
end

local function findQuest(quests: { QuestDef }, questId: string): QuestDef?
	for _, def in ipairs(quests) do
		if def.Id == questId then
			return def
		end
	end
	return nil
end

-- Records `amount` of `event` against both periods. Called by the services that own the gameplay.
function QuestService.report(player: Player, event: string, amount: number)
	if not isPositiveInteger(amount) then
		log.warn("report rejected for %s (%s): invalid amount %s", player.Name, event, tostring(amount))
		return
	end
	local data = dataService.get(player)
	if data == nil then
		-- An event can reach a player whose profile is not loaded (or already released): nothing to record.
		return
	end
	local now = os.time()
	-- Indexed and annotated: an `in` iteration or a bare local widens the period literals to strings.
	for index = 1, #PERIOD_ORDER do
		local period: Period = PERIOD_ORDER[index]
		local set, quests = ensureSet(player, data, period, now)
		if tracks(set, quests, event) then
			local completed = QuestLogic.applyEvent(set, quests, event, amount)
			pending[player] = true
			for _, questId in ipairs(completed) do
				local def = findQuest(quests, questId)
				if def ~= nil then
					local params = { name = def.NameKey, target = def.Target }
					notify.send(player, "quest.completed", params, "Success", "Claim")
					log.info("%s completed %s", player.Name, def.Id)
				end
			end
			if #completed > 0 then
				push(player)
			end
		end
	end
end

-- Claims `questId` of `period`: it must belong to the live set, be completed and not already claimed.
-- The section is replicated on every path, including a refusal, so the client never stays pending.
function QuestService.claim(player: Player, period: Period, questId: string): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("claim skipped for %s: profile not loaded", player.Name)
		return false
	end
	local set, quests = ensureSet(player, data, period, os.time())
	local def = findQuest(quests, questId)
	if def == nil then
		log.warn("claim rejected for %s: %s is not in the live %s set", player.Name, questId, period)
		push(player)
		return false
	end
	if not QuestLogic.canClaim(set, def) then
		log.warn("claim rejected for %s: %s is not claimable", player.Name, questId)
		push(player)
		return false
	end
	-- Marked and replicated before granting, so a re-entrant claim cannot pay twice.
	QuestLogic.claim(set, def)
	push(player)

	local reward = PERIOD_DEFS[period]
	local xp = progression.addXp(player, reward.RewardXp, "Quest" .. period)
	local ryo = currency.add(player, reward.RewardRyo, "Quest" .. period)
	notify.send(player, "quest.reward", { xp = xp, ryo = ryo }, "Success", "Claim")
	log.info("%s claimed %s (%s): +%d XP, +%d Ryo", player.Name, questId, period, xp, ryo)
	return true
end

-- Status of the live quests of `period` (progress clamped to the target, claim state). Empty while the
-- profile is not loaded.
function QuestService.getActive(player: Player, period: Period): { Status }
	local data = dataService.get(player)
	if data == nil then
		return {}
	end
	local set, quests = ensureSet(player, data, period, os.time())
	return QuestLogic.status(set, quests)
end

-- Flushes the coalesced progress pushes.
local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < PUSH_INTERVAL_SECONDS then
		return
	end
	accumulator = math.min(accumulator - PUSH_INTERVAL_SECONDS, PUSH_INTERVAL_SECONDS)
	for player in pairs(pending) do
		pending[player] = nil
		dataService.push(player, "Quests")
	end
end

local function onProfileLoaded(player: Player, data: ProfileData)
	local now = os.time()
	for index = 1, #PERIOD_ORDER do
		ensureSet(player, data, PERIOD_ORDER[index], now)
	end
end

-- The gameplay events of QuestConfig that no service reports explicitly come from CombatService
-- signals: Killed (PlayerKill / DummyKill), Damaged (DamageDealt, and MeleeHit when the hit was a
-- melee) and Dashed (Dash). JutsuService, MatchService and WorldBossService call `report` directly for
-- the events they own. Every QuestConfig.Pool event has exactly one producer.
local function onKilled(sourceUserId: number, victimModel: Model)
	if sourceUserId == 0 then
		return
	end
	local source = Players:GetPlayerByUserId(sourceUserId)
	if source == nil then
		return
	end
	if Players:GetPlayerFromCharacter(victimModel) ~= nil then
		QuestService.report(source, "PlayerKill", 1)
	elseif CollectionService:HasTag(victimModel, ENEMY_TAG) then
		QuestService.report(source, "DummyKill", 1)
	end
end

-- One event per damage application that removed health, whatever the victim: the damage quests count
-- what the player dealt, and MeleeHit counts landed melee hits rather than swings.
local function onDamaged(sourceUserId: number, _targetModel: Model, applied: number, kind: string)
	if sourceUserId == 0 or applied <= 0 then
		return
	end
	local source = Players:GetPlayerByUserId(sourceUserId)
	if source == nil then
		return
	end
	QuestService.report(source, "DamageDealt", applied)
	if kind == MELEE_KIND then
		QuestService.report(source, "MeleeHit", 1)
	end
end

local function onDashed(player: Player)
	QuestService.report(player, "Dash", 1)
end

function QuestService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
	currency = deps.Currency
	combat = deps.Combat
end

function QuestService.Start()
	dataService.ProfileLoaded:Connect(onProfileLoaded)
	dataService.ProfileReleased:Connect(function(player: Player)
		pending[player] = nil
	end)
	combat.Killed:Connect(onKilled)
	combat.Damaged:Connect(onDamaged)
	combat.Dashed:Connect(onDashed)
	registry.on("ClaimQuest", function(player: Player, period: Period, questId: string)
		QuestService.claim(player, period, questId)
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (%d daily, %d weekly)", PERIOD_DEFS.Daily.Count, PERIOD_DEFS.Weekly.Count)
end

return QuestService
