--!strict
-- Admission: the hub's gate into the Erasure's arena (D-130, D-132). With a fight in the slot, a player joins
-- it or walks back into it (BossPractice.entryVerdict); with none, they may open a practice
-- (BossPractice.startVerdict), which WorldBossService then opens. The verdicts are BossPractice's; this module
-- carries them out on the slot, and keeps the one record that outlives a fight: when each player may open a
-- practice again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Audience = require(script.Parent.Audience)
local BossPractice = require(Shared.Pure.BossPractice)
local Context = require(script.Parent.Context)
local Encounter = require(script.Parent.Encounter)
local Log = require(Shared.Util.Log)
local Rewards = require(script.Parent.Rewards)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldBossMode = require(script.Parent.Parent.Parent.GameModes.WorldBossMode)

local log = Log.new("WorldBoss.Admission")

type Boss = Context.Boss
type State = WorldBossMode.State

local SCHEDULE = WorldBossConfig.Schedule
local PRACTICE = WorldBossConfig.Practice
-- The least health of a boss still standing: a practice's growth never leaves it below that.
local STANDING_HEALTH = 1

local Admission = {}

local deps: Context.Deps
local slot: Context.Slot
-- User id -> when they may open a practice again. Pruned of expired entries on every request to open one.
local startCooldownUntil: { [number]: number } = {}

----------------------------------------------------------------
-- Opening a practice
----------------------------------------------------------------

-- Why `player` may not open a practice now, as a Strings key and its params, or nil when they may: they
-- opened one too recently, or the event is due before it would end and could run (BossPractice.startVerdict).
function Admission.startRefusal(player: Player, now: number): (string?, { [string]: any }?)
	for userId, untilAt in pairs(startCooldownUntil) do
		if untilAt <= now then
			startCooldownUntil[userId] = nil
		end
	end
	local verdict, seconds = BossPractice.startVerdict({
		Now = now,
		NextEventAt = slot.NextEventAt,
		Eligible = #Context.eligiblePlayers(deps.Match),
		MinPlayers = SCHEDULE.MinPlayers,
		FightSeconds = PRACTICE.FightSeconds,
		CleanupSeconds = PRACTICE.CleanupSeconds,
		CooldownUntil = startCooldownUntil[player.UserId] or 0,
	})
	if verdict == "Cooldown" then
		return "boss.portal.cooldown", { seconds = seconds }
	elseif verdict == "EventSoon" then
		return "boss.portal.eventSoon", { seconds = seconds }
	end
	return nil, nil
end

-- The practice `player` asked for has opened: they are its starter, and wait StartCooldownSeconds to open
-- another. Recorded only once it has opened, so a refused opening never costs anybody a cooldown.
function Admission.opened(player: Player, now: number)
	slot.Starter = player.UserId
	slot.StartedAt = now
	startCooldownUntil[player.UserId] = now + PRACTICE.StartCooldownSeconds
end

-- The practice in the slot closed with nobody in it: whoever opened it waits before opening another, longer
-- if they walked out of it through a gate and it emptied early (BossPractice.startPenalty), so the gate cannot
-- be held by opening a practice and walking out. A starter a ranked match took, who died, or who left the
-- server did not walk out: none of them can reopen it on a loop, and a disconnect is not a choice.
function Admission.closedEmpty(now: number)
	local starter = slot.Starter
	if starter == nil then
		return
	end
	startCooldownUntil[starter] = now
		+ BossPractice.startPenalty(
			slot.Departed[starter] == "Gate",
			slot.StartedAt,
			now,
			PRACTICE.EarlyEmptySeconds,
			PRACTICE.EarlyEmptyCooldownSeconds,
			PRACTICE.StartCooldownSeconds
		)
end

----------------------------------------------------------------
-- Joining a fight in progress
----------------------------------------------------------------

-- A practice growing by `added` for one more player: the boss's humanoid, the health its hits are credited
-- against and the rules state rise together, so the damage already dealt stays dealt and the shares still add
-- up. The humanoid's health is raised after its maximum, and held within [STANDING_HEALTH, MaxHealth].
local function grow(live: Boss, current: State, added: number)
	if added <= 0 then
		return
	end
	WorldBossMode.grow(current, added)
	live.Humanoid.MaxHealth += added
	live.Humanoid.Health = math.clamp(live.Humanoid.Health + added, STANDING_HEALTH, live.Humanoid.MaxHealth)
	live.LastHealth += added
end

-- A hit on the boss by `userId` has just been recorded (the fight's Damaged handler). A practice joiner's first
-- one while the fight is on grows the Erasure for them, if it still stands (BossPractice.growthOnHit): the gate
-- only booked it. Once per joiner and per fight, returns included.
function Admission.struck(userId: number)
	local live, current = slot.Boss, slot.State
	if live == nil or current == nil or current.Phase ~= "Fighting" or not slot.GrowthOwed[userId] then
		return
	end
	slot.GrowthOwed[userId] = nil
	grow(
		live,
		current,
		BossPractice.growthOnHit(live.Humanoid.Health, current.MaxHealth, PRACTICE.HealthPerJoiner, PRACTICE.HealthCap)
	)
end

-- Brings `player` into the fight in progress. A newcomer ("Join") becomes a participant: the event's
-- participation quest is theirs the moment they are added, and a practice books its growth for them, paid by
-- their first hit (Admission.struck). A participant walking back in ("Rejoin") spends one of their returns.
-- Either way they are engaged again, dropped on their own pad and shown the fight.
local function admit(player: Player, verdict: BossPractice.EntryVerdict, now: number): boolean
	local live, current = slot.Boss, slot.State
	if live == nil or current == nil then
		return false
	end
	local userId = player.UserId
	if verdict == "Join" and table.find(slot.Participants, userId) == nil then
		table.insert(slot.Participants, userId)
		if slot.Kind == "Event" then
			Rewards.reportQuest(deps, player, "BossParticipation")
		else
			slot.GrowthOwed[userId] = true
		end
	elseif verdict == "Rejoin" then
		slot.Reentries[userId] = (slot.Reentries[userId] or 0) + 1
	end
	slot.Departed[userId] = nil
	local pad = table.find(slot.Participants, userId) or #slot.Participants
	local character = Encounter.placeOne(live.Arena, player, pad, live.Center)
	if character ~= nil then
		slot.Placed[userId] = { Character = character, At = now }
	end
	deps.Notify.send(player, "boss.started", nil, "Info")
	Audience.push(now)
	log.info("%s: %s %s (%d participant(s))", slot.Kind, player.Name, verdict, #slot.Participants)
	return true
end

-- The gate while a fight holds the slot: in, or the Strings key of why not and its params. A boss already
-- brought down closes the gate at once, before the fight's next tick records it (BossPractice.gatePhase).
function Admission.join(player: Player, now: number): (boolean, string?, { [string]: any }?)
	local current = slot.State
	if current == nil then
		return false, nil
	end
	local userId = player.UserId
	local live = slot.Boss
	local verdict = BossPractice.entryVerdict(
		BossPractice.gatePhase(current.Phase, if live ~= nil then live.Humanoid.Health else nil),
		table.find(slot.Participants, userId) ~= nil,
		slot.Reentries[userId] or 0,
		PRACTICE.MaxReentries,
		slot.Kind == "Practice"
	)
	if verdict == "Join" or verdict == "Rejoin" then
		return admit(player, verdict, now)
	elseif verdict == "Announced" then
		return false, "boss.portal.announced", { seconds = math.max(0, math.ceil(slot.PhaseEndsAt - now)) }
	elseif verdict == "Closing" then
		return false, "boss.portal.closing"
	end
	return false, "boss.portal.noReentry"
end

function Admission.Init(injected: Context.Deps, shared: Context.Slot)
	deps = injected
	slot = shared
end

return Admission
