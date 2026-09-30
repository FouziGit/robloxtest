--!strict
-- WorldBossService: the Erasure of docs/GAME_DESIGN.md §7. Two kinds of fight hold its one encounter slot:
--
--   * the scheduled EVENT. Every WorldBossConfig.Schedule.IntervalSeconds it warns the server, spawns the boss
--     in the Boss arena, pulls in the players who are not in a match, runs the fight for at most FightSeconds
--     and pays everybody by the share of the boss health they personally removed;
--   * a PRACTICE (D-132), opened on demand by one player through the hub's gate (`enterFromPortal`): the same
--     Erasure, weaker, growing with each player who joins and strikes it, paying a fraction of the event a few
--     times a day.
--     It never pauses ranked matchmaking (`isLive` stays the event's), never borrows the PvP policy, never
--     moves the schedule, and only its own participants hear of it.
--
-- Either fight is joined in progress through the hub's gate, and left through a gate (`leave`); `isEngaged`
-- is what the other places that hold a player ask before they do.
--
-- This module owns the lifecycle: the schedule, the announce, the arena and the return to the hub. The slot
-- itself is one record (Context.Slot) every submodule shares. Who hears about the fight is Audience, the
-- hub's gate is Admission, the PvP rule the event borrows is Policy, the pay is Rewards, the boss in the
-- world (its model, its walk, its telegraphs, its hits) is Encounter, and the rules it follows (phases,
-- attack rotation, telegraph windows, hit shapes, knockback, reward split) are GameModes/WorldBossMode —
-- the way a match keeps its rules in its mode. What keeps a practice from taking the slot away from the
-- event is BossPractice's.
--
-- One Heartbeat accumulator drives all of it, so nothing spawns a thread per player and no timer can
-- outlive the fight. Everything a fight owns (boss model, arena, health connection) hangs from one Trove,
-- so a victory, a timeout, an empty arena and a failed spawn all release it the same way.
--
-- The boss damages players through CombatService.ApplyDamage with no source, which is how
-- server-authored damage keeps landing while PvP is switched off for the event (see Policy), and
-- under MatchService's own rule during a practice. Players damage it through the ordinary glyph and melee
-- path, and their contribution comes from CombatService.Damaged, one application at a time with who dealt
-- it (Encounter.recordDamage). The quest log is pushed to, never polled (QuestService.report), like every
-- other gameplay owner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Admission = require(script.Admission)
local Audience = require(script.Audience)
local BossPractice = require(Shared.Pure.BossPractice)
local Context = require(script.Context)
local Encounter = require(script.Encounter)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local MovementGuardConfig = require(script.Parent.Parent.Config.MovementGuardConfig)
local Policy = require(script.Policy)
local Rewards = require(script.Rewards)
local Trove = require(Packages.Trove)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldBossMode = require(script.Parent.Parent.GameModes.WorldBossMode)

local log = Log.new("WorldBossService")

export type Arena = Context.Arena

type Deps = Context.Deps
type Boss = Context.Boss
type State = WorldBossMode.State

local SCHEDULE = WorldBossConfig.Schedule
local PRACTICE = WorldBossConfig.Practice
local TICK_SECONDS = 1 / GameConfig.Server.TickRate
-- BossChanged is pushed at the rate match snapshots use: the HUD tweens between them the same way.
local TICKS_PER_SNAPSHOT = math.max(1, math.floor(GameConfig.Server.TickRate / MatchConfig.SnapshotHz))

local WorldBossService = {}

local deps: Deps
local slot: Context.Slot = Context.newSlot()
local accumulator = 0
local ticks = 0
-- User id -> when a practice last paid them: the server's RewardGapSeconds guard (Rewards), across fights.
local lastPaidAt: { [number]: number } = {}

----------------------------------------------------------------
-- End of the fight
----------------------------------------------------------------

-- Last step of every path out of a fight, including the ones that never spawned a boss: the PvP policy
-- goes back, the Trove destroys the boss and releases the arena, the HUD is cleared and the slot is the
-- event's again. Only the event moves the schedule: a practice closing, or failing to open, leaves the next
-- event where it was. Safe to call from any phase, and twice.
local function reset(now: number)
	Policy.release()
	local trove = slot.Trove
	slot.Trove = nil
	if trove ~= nil then
		trove:Destroy()
	end
	if slot.Kind == "Event" then
		slot.NextEventAt = now + SCHEDULE.IntervalSeconds
	end
	slot.Kind = "Event"
	slot.State = nil
	slot.Boss = nil
	slot.Participants = {}
	slot.Departed = {}
	slot.Reentries = {}
	slot.GrowthOwed = {}
	slot.Placed = {}
	slot.Starter = nil
	slot.EmptySince = nil
	slot.PhaseEndsAt = 0
	deps.Registry.fireAll("BossChanged", nil)
end

-- Sends back to the hub whoever still stands in the arena, and only them: a participant who has since gone
-- to a ranked match, the Battleground or the hub is where they chose to be, and a teleport would take them
-- out of it.
local function finish(now: number)
	local live = slot.Boss
	for _, player in ipairs(Context.livePlayers(slot.Participants)) do
		if live ~= nil and Context.inArena(player, live.Center) then
			log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player)
		end
	end
	if slot.Kind == "Event" then
		log.info("event closed, next one in %ds", SCHEDULE.IntervalSeconds)
	else
		log.info("practice closed, next event in %ds", math.max(0, math.ceil(slot.NextEventAt - now)))
	end
	reset(now)
end

-- The victory or timeout screen before the arena is released; a practice gives the slot back sooner.
local function cleanupSeconds(): number
	return if slot.Kind == "Practice" then PRACTICE.CleanupSeconds else SCHEDULE.CleanupSeconds
end

local function defeat(live: Boss, current: State, now: number)
	current.Phase = "Defeated"
	WorldBossMode.setHealth(current, 0)
	WorldBossMode.endAttack(current)
	slot.PhaseEndsAt = now + cleanupSeconds()
	-- No sound on the toast: the BossDefeated timeline is the sound of this, and the match's fanfare on
	-- top of it was two endings at once.
	Audience.tell("boss.defeated", nil, "Success")
	deps.Vfx.emit({
		Id = Context.DefeatVfxId,
		Origin = live.Body.Position,
		Direction = live.Facing,
		Params = {
			Height = WorldBossMode.bodySize().Y,
			Radius = WorldBossMode.contactRadius(),
			Ground = live.GroundY,
		},
	}, true)
	local pay: Rewards.PayContext = {
		Deps = deps,
		State = current,
		Participants = slot.Participants,
		Kind = slot.Kind,
		Now = now,
		LastPaidAt = lastPaidAt,
	}
	log.try("Rewards.pay", Rewards.pay, pay)
	Audience.push(now)
end

local function expire(current: State, now: number)
	current.Phase = "Expired"
	WorldBossMode.endAttack(current)
	slot.PhaseEndsAt = now + cleanupSeconds()
	Audience.tell("boss.expired", nil, "Info")
	Audience.push(now)
	log.info("%s: boss escaped with %d / %d health", slot.Kind, math.floor(current.Health + 0.5), current.MaxHealth)
end

----------------------------------------------------------------
-- Announce and open
----------------------------------------------------------------

local function announce(now: number)
	local eligible = Context.eligiblePlayers(deps.Match)
	if #eligible < SCHEDULE.MinPlayers then
		slot.NextEventAt = now + SCHEDULE.IntervalSeconds
		log.info("event skipped: %d player(s) available, %d needed", #eligible, SCHEDULE.MinPlayers)
		return
	end
	slot.State = WorldBossMode.newState(#eligible, now)
	slot.PhaseEndsAt = now + SCHEDULE.AnnounceSeconds
	deps.Notify.sendAll("boss.announced", { seconds = SCHEDULE.AnnounceSeconds }, "Info")
	Audience.push(now)
	log.info("boss announced to %d player(s), spawning in %ds", #eligible, SCHEDULE.AnnounceSeconds)
end

-- Opens a fight in the slot for `players`: acquires the arena, builds the boss with `health`, drops everybody
-- on the ring and tells them. The event and a practice both open through here; what differs (who is taken,
-- the quest, the PvP policy) is the caller's. False, holding nothing, when no Boss arena is free.
local function openFight(players: { Player }, health: number, seconds: number, now: number): boolean
	local arena = deps.Arena.acquire(Context.ArenaId)
	if arena == nil then
		return false
	end
	-- The arena is tracked before anything else can fail, so every path out of here releases it.
	local trove = Trove.new()
	trove:Add(function()
		log.try("Arena.release " .. arena.Id, deps.Arena.release, arena)
	end)
	slot.Trove = trove

	local participants: { number } = {}
	for _, player in ipairs(players) do
		table.insert(participants, player.UserId)
	end
	slot.Participants = participants
	local fresh = WorldBossMode.newState(#participants, now, health)
	fresh.Phase = "Fighting"
	slot.State = fresh
	slot.PhaseEndsAt = now + seconds

	local live = Encounter.build(arena, fresh.MaxHealth)
	trove:Add(live.Model)
	-- Connected then added, rather than through trove:Connect: Trove accepts a signal whose Connect takes
	-- a variadic handler, and Context.Damaged deliberately declares the four argument types instead, so
	-- that a handler with the wrong shape is a type error here rather than a nil at runtime. The
	-- connection is still owned by the trove and still released with the encounter. The hit is credited
	-- against the health it found, then a joiner's first one may grow a practice (Admission.struck).
	trove:Add(deps.Combat.Damaged:Connect(function(sourceUserId: number, targetModel: Model, applied: number)
		local current = slot.State
		if current ~= nil and slot.Boss == live and targetModel == live.Model then
			Encounter.recordDamage(live, current, sourceUserId, applied)
			Admission.struck(sourceUserId)
		end
	end))
	slot.Boss = live

	for userId, character in pairs(Encounter.place(arena, participants, live.Center)) do
		slot.Placed[userId] = { Character = character, At = now }
	end
	Audience.tell("boss.started", nil, "Info")
	deps.Vfx.emit({
		Id = Context.SpawnVfxId,
		Origin = live.Body.Position,
		Direction = live.Facing,
		Params = {
			Height = WorldBossMode.bodySize().Y,
			Radius = WorldBossMode.contactRadius(),
			Ground = live.GroundY,
		},
	}, true)
	Audience.push(now)
	log.info(
		"%s opened on arena %s slot %d: %d health, %d participant(s), %ds to kill it",
		slot.Kind,
		arena.Id,
		arena.SlotIndex,
		fresh.MaxHealth,
		#participants,
		seconds
	)
	return true
end

-- The scheduled event: everybody it may take, its PvP rule, and the participation quest for being pulled in,
-- so the quest credit does not depend on how the fight ends.
local function spawnBoss(now: number)
	local eligible = Context.eligiblePlayers(deps.Match)
	if #eligible < SCHEDULE.MinPlayers then
		log.info("event cancelled: %d player(s) left when the boss was due", #eligible)
		reset(now)
		return
	end
	Policy.take()
	if not openFight(eligible, WorldBossConfig.healthFor(#eligible), SCHEDULE.FightSeconds, now) then
		log.warn("event cancelled: no free %s arena", Context.ArenaId)
		reset(now)
		return
	end
	for _, player in ipairs(eligible) do
		Rewards.reportQuest(deps, player, "BossParticipation")
	end
end

----------------------------------------------------------------
-- Tick
----------------------------------------------------------------

-- The boss entering a new phase: the band widened on the body (Encounter.dress), and the world sees it
-- happen. Emitted once per phase, by the tick that crossed the threshold.
local function phaseChanged(live: Boss)
	deps.Vfx.emit({
		Id = Context.PhaseVfxId,
		Origin = live.Body.Position,
		Direction = live.Facing,
		Params = {
			Height = WorldBossMode.bodySize().Y,
			Radius = WorldBossMode.contactRadius(),
			Ground = live.GroundY,
		},
	}, true)
end

-- Nobody alive in the arena. The event closes at once, as it always has. A practice waits EmptyGraceSeconds
-- for whoever may still walk back in -- a participant who died, not one let go since or gone from the
-- server -- with the boss's pending blow dropped, so a returner never lands in a hit nobody warned them of.
local function closeEmpty(current: State, now: number)
	if slot.Kind == "Event" then
		log.info("no participant left in the arena")
		expire(current, now)
		return
	end
	WorldBossMode.endAttack(current)
	local since = slot.EmptySince or now
	slot.EmptySince = since
	if BossPractice.keepAlive(false, #Audience.recipients() > 0, since, now, PRACTICE.EmptyGraceSeconds) then
		return
	end
	log.info("practice left empty")
	expire(current, now)
	Admission.closedEmpty(now)
end

-- K2 (D-XXXc): the Erasure's arena stands in the same stack as the duels, and a participant who fell off its page
-- fell into whichever match was below. Whoever the fight placed and is still in it, whose root is under the arena's
-- floor within the reach of its kill zone, is taken back to the hub -- never killed. Only the body the fight placed,
-- once its pivot settled: a body just placed still replicates the hub, far under the arena, for a round trip (as
-- MatchService judges its falls, D-138). Judged here rather than by Touched, which the falling body's own client
-- reports; and once per placement, so a body the hub's gate places again is judged again.
local function judgeFalls(live: Boss, now: number)
	local plane = live.Arena.KillZone
	local half = plane.Size / 2
	for userId, placed in pairs(slot.Placed) do
		local player = Players:GetPlayerByUserId(userId)
		local root = if player ~= nil then Context.liveRoot(player) else nil
		if
			player ~= nil
			and root ~= nil
			and not slot.Departed[userId]
			and player.Character == placed.Character
			and now - placed.At >= MovementGuardConfig.SettleMaxSeconds
			and root.Position.Y < live.FallY
		then
			local offset = plane.CFrame:PointToObjectSpace(root.Position)
			if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then
				slot.Placed[userId] = nil
				log.info("%s: %s fell off the arena, back to the hub", slot.Kind, player.Name)
				log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player)
			end
		end
	end
end

local function tickFight(live: Boss, current: State, now: number)
	if now >= slot.PhaseEndsAt then
		expire(current, now)
		return
	end
	judgeFalls(live, now)
	Audience.releaseMatched()
	local phaseBefore = current.PhaseIndex
	local ok, outcome, dirty = pcall(Encounter.step, live, current, slot.Participants, now, TICK_SECONDS)
	if not ok then
		log.warn("fight tick failed: %s", tostring(outcome))
		-- A tick that blew up must not leave the boss stepping until the timer: close the fight.
		expire(current, now)
	elseif outcome == "Defeated" then
		defeat(live, current, now)
	elseif outcome == "Empty" then
		closeEmpty(current, now)
	else
		slot.EmptySince = nil
		if dirty == true then
			if current.PhaseIndex ~= phaseBefore then
				phaseChanged(live)
			end
			Audience.push(now)
		end
	end
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local now = os.clock()
	local current = slot.State
	if current == nil then
		if now >= slot.NextEventAt then
			log.try("announce", announce, now)
		end
		return
	end

	if current.Phase == "Announced" then
		if now >= slot.PhaseEndsAt and not log.try("spawnBoss", spawnBoss, now) then
			-- A spawn that blew up must not be retried on every tick: drop it and schedule the next event.
			reset(now)
		end
	elseif current.Phase == "Fighting" then
		local live = slot.Boss
		if live == nil or live.Model.Parent == nil then
			log.warn("the boss model is gone: the fight ends without a winner")
			expire(current, now)
		else
			tickFight(live, current, now)
		end
	elseif now >= slot.PhaseEndsAt then
		log.try("finish", finish, now)
		return
	elseif slot.Boss ~= nil then
		-- The victory or timeout screen: the page still stands, and a body can still fall off it.
		judgeFalls(slot.Boss, now)
	end

	ticks += 1
	if ticks % TICKS_PER_SNAPSHOT == 0 then
		Audience.push(now)
	end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- True while the scheduled EVENT holds the slot, from the announce until the arena is released: PvP is off,
-- players are being pulled into the boss arena and ranked matchmaking waits for it. A practice is never live
-- (D-132): one player practising must not freeze ranked for the whole server.
function WorldBossService.isLive(): boolean
	return slot.State ~= nil and slot.Kind == "Event"
end

-- True while `player` is one of the fight's participants, from the spawn until the arena is released, and
-- has not been let go since (a gate, or a practice's participant taken by a match). The event pulls in
-- players wherever they are, the Battleground included (D-131): a place that holds a player asks this so that
-- it lets go of whoever the fight took, rather than pulling them back out of the arena.
function WorldBossService.isEngaged(player: Player): boolean
	local userId = player.UserId
	return slot.State ~= nil and table.find(slot.Participants, userId) ~= nil and not slot.Departed[userId]
end

-- The hub's gate (D-130). With a fight in the slot, `player` joins it or walks back into it; with none, they
-- open a practice. Returns whether they were taken in, and otherwise the Strings key of the reason and its
-- params; no key when there is nothing to say (no live character).
function WorldBossService.enterFromPortal(player: Player): (boolean, string?, { [string]: any }?)
	if deps.Match.isInMatch(player) then
		return false, "queue.inMatch"
	end
	if Context.liveRoot(player) == nil then
		return false, nil
	end
	local now = os.clock()
	if slot.State ~= nil then
		return Admission.join(player, now)
	end
	local refusal, params = Admission.startRefusal(player, now)
	if refusal ~= nil then
		return false, refusal, params
	end
	-- Marked a practice before it opens, so the opening already speaks to its own participant only, and a
	-- failure leaves the schedule where it was. Never the event's PvP rule: a practice takes no policy.
	slot.Kind = "Practice"
	local opened = log.succeeded(
		"open a practice for " .. player.Name,
		openFight,
		{ player },
		PRACTICE.Health,
		PRACTICE.FightSeconds,
		now
	)
	if not opened then
		reset(now)
		return false, "boss.portal.busy"
	end
	Admission.opened(player, now)
	return true
end

-- A participant going out through a gate (the arena's Return gate, or the hub's gate to the Battleground).
-- Nothing for anybody else.
function WorldBossService.leave(player: Player)
	local userId = player.UserId
	if slot.State == nil or slot.Departed[userId] or table.find(slot.Participants, userId) == nil then
		return
	end
	Audience.release(player, "Gate")
end

function WorldBossService.Init(injected: Deps)
	deps = injected
	Encounter.Init(injected)
	Policy.Init(injected)
	Audience.Init(injected, slot)
	Admission.Init(injected, slot)
end

function WorldBossService.Start()
	if deps.Quest == nil then
		log.warn("Quest dependency missing: boss fights will not advance the World Boss quests")
	end
	slot.NextEventAt = os.clock() + SCHEDULE.IntervalSeconds
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info(
		"%s started (every %ds, %ds warning, %ds fight, %d players minimum; practice %ds)",
		WorldBossMode.Id,
		SCHEDULE.IntervalSeconds,
		SCHEDULE.AnnounceSeconds,
		SCHEDULE.FightSeconds,
		SCHEDULE.MinPlayers,
		PRACTICE.FightSeconds
	)
end

return WorldBossService
