--!strict
-- WorldBossService: the recurring server-wide event of docs/GAME_DESIGN.md §7. Every
-- WorldBossConfig.Schedule.IntervalSeconds it warns the server, spawns the boss in the Boss arena,
-- pulls in the players who are not in a match, runs the fight for at most FightSeconds and pays
-- everybody by the share of the boss health they personally removed.
--
-- This module owns the event lifecycle: the schedule, the announce, the arena, the PvP policy, the
-- BossChanged replication, the rewards and the return to the hub. The boss in the world (its model, its
-- walk, its telegraphs, its hits) is Encounter, and the rules it follows (phases, attack rotation,
-- telegraph windows, hit shapes, knockback, reward split) are GameModes/WorldBossMode — the way a match
-- keeps its rules in its mode.
--
-- One Heartbeat accumulator drives all of it, so nothing spawns a thread per player and no timer can
-- outlive the event. Everything the event owns (boss model, arena, health connection) hangs from one
-- Trove, so a victory, a timeout, an empty arena and a failed spawn all release it the same way.
--
-- The boss damages players through CombatService.ApplyDamage with no source, which is how
-- server-authored damage keeps landing while PvP is switched off for the duration (see `bossPolicy`).
-- Players damage it through the ordinary glyph and melee path, and their contribution is read back from
-- the LastAttackerUserId attribute CombatService writes on every hit it applies. The quest log is pushed
-- to, never polled (QuestService.report), like every other gameplay owner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Context = require(script.Context)
local Encounter = require(script.Encounter)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local Trove = require(Packages.Trove)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldBossMode = require(script.Parent.Parent.GameModes.WorldBossMode)

local log = Log.new("WorldBossService")

export type Arena = Context.Arena

type Deps = Context.Deps
type Boss = Context.Boss
type Policy = Context.Policy
type State = WorldBossMode.State

local SCHEDULE = WorldBossConfig.Schedule
local TICK_SECONDS = 1 / GameConfig.Server.TickRate
-- BossChanged is pushed at the rate match snapshots use: the HUD tweens between them the same way.
local TICKS_PER_SNAPSHOT = math.max(1, math.floor(GameConfig.Server.TickRate / MatchConfig.SnapshotHz))

local WorldBossService = {}

local deps: Deps
local state: State? = nil -- non-nil from the announce to the end of the cleanup
local boss: Boss? = nil -- non-nil from the spawn to the end of the cleanup
local eventTrove: Context.TroveType? = nil
local participants: { number } = {} -- user ids, in ring-spawn order
local restorePolicy: Policy? = nil
local phaseEndsAt = 0
local nextEventAt = 0
local accumulator = 0
local ticks = 0

----------------------------------------------------------------
-- PvP policy
----------------------------------------------------------------

-- Damage rule while the event is live. It NARROWS the rule it borrowed, it does not replace it: any
-- pair where either side is in a match is decided by the borrowed rule, so a duel or a 3v3 that was
-- already running when the boss spawned keeps its participant PvP. Everything else follows the event
-- rule of docs/GAME_DESIGN.md §7 — server-authored damage carries no source so the boss, its attacks
-- and the environment still land, players still hit the boss and the training dummies, and no player
-- can damage another one.
--
-- Replacing the rule outright made every live match undamageable for the whole event: nobody could be
-- eliminated, so each round ran to its timer and resolved as a draw, and a ranked series was scored on
-- a fight that was physically impossible to play. Roughly a third of every event cycle was exposed.
local function bossPolicy(source: Player?, targetModel: Model): boolean
	if source == nil then
		return true
	end
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local borrowed = restorePolicy
	if
		borrowed ~= nil
		and (deps.Match.isInMatch(source) or (targetPlayer ~= nil and deps.Match.isInMatch(targetPlayer)))
	then
		return borrowed(source, targetModel)
	end
	return targetPlayer == nil
end

-- CombatService keeps a single policy slot and MatchService owns it from its Start, so the event borrows
-- the slot instead of stacking on it: setPolicy hands back the policy it replaced, bossPolicy defers to
-- it for anything a live match governs, and the cleanup puts it back. A build where nothing comes back
-- is logged rather than guessed — the event would otherwise restore a rule it never read, and
-- bossPolicy would have nothing to defer to.
local function takePolicy()
	local replaced = deps.Combat.setPolicy(bossPolicy)
	restorePolicy = replaced
	if replaced == nil then
		log.warn("Combat.setPolicy returned no previous policy: PvP stays off until an owner installs one")
	end
end

local function releasePolicy()
	local previous = restorePolicy
	restorePolicy = nil
	if previous ~= nil then
		deps.Combat.setPolicy(previous)
	end
end

----------------------------------------------------------------
-- Replication
----------------------------------------------------------------

-- BossChanged goes to the whole server (the event is server-wide) with the damage share resolved per
-- receiver: one table, one field rewritten per player, FireClient serializes it on the spot.
local function pushSnapshot(now: number)
	local current = state
	if current == nil then
		return
	end
	local snapshot = WorldBossMode.snapshot(current, phaseEndsAt - now, 0)
	for _, player in ipairs(Players:GetPlayers()) do
		snapshot.MyShare = WorldBossMode.shareOf(current, player.UserId)
		deps.Registry.fire("BossChanged", player, snapshot)
	end
end

----------------------------------------------------------------
-- End of the event
----------------------------------------------------------------

-- Last step of every path out of an event, including the ones that never spawned a boss: the PvP policy
-- goes back, the Trove destroys the boss and releases the arena, the HUD is cleared and the next event
-- is scheduled. Safe to call from any phase, and twice.
local function reset(now: number)
	releasePolicy()
	local trove = eventTrove
	eventTrove = nil
	if trove ~= nil then
		trove:Destroy()
	end
	boss = nil
	state = nil
	participants = {}
	phaseEndsAt = 0
	nextEventAt = now + SCHEDULE.IntervalSeconds
	deps.Registry.fireAll("BossChanged", nil)
end

local function finish(now: number)
	for _, player in ipairs(Context.livePlayers(participants)) do
		log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player)
	end
	reset(now)
	log.info("event closed, next one in %ds", SCHEDULE.IntervalSeconds)
end

----------------------------------------------------------------
-- Rewards
----------------------------------------------------------------

-- One quest event of QuestConfig ("BossParticipation" when a player is pulled into the fight,
-- "BossKill" when the boss goes down under them). A quest log that blew up never costs a reward.
local function reportQuest(player: Player, event: string)
	local quest = deps.Quest
	if quest == nil then
		return
	end
	log.try("Quest.report " .. event, quest.report, player, event, 1)
end

local function bumpBossKills(player: Player)
	local data = deps.DataService.get(player)
	if data == nil then
		return
	end
	data.Stats.BossKills += 1
	deps.DataService.push(player, "Stats")
end

-- Pays every participant that removed at least WorldBossConfig.Rewards.MinShareToReward of the boss
-- health, with the kill bonus on top above KillBonusShare. The credited amounts come back from the
-- services (VIP and boost multipliers), so the toast never promises more than what was granted.
local function rewardParticipants(current: State)
	local paid = 0
	for _, player in ipairs(Context.livePlayers(participants)) do
		local share = WorldBossMode.shareOf(current, player.UserId)
		local reward = WorldBossMode.rewardFor(share)
		if reward ~= nil then
			local xp = deps.Progression.addXp(player, reward.Xp, "BossParticipation")
			local ryo = deps.Currency.add(player, reward.Ryo, "BossParticipation")
			if reward.BonusXp > 0 then
				xp += deps.Progression.addXp(player, reward.BonusXp, "BossKillBonus")
				ryo += deps.Currency.add(player, reward.BonusRyo, "BossKillBonus")
				deps.Notify.send(player, "boss.killBonus", nil, "Success")
			end
			bumpBossKills(player)
			reportQuest(player, "BossKill")
			deps.Notify.send(player, "boss.reward", { xp = xp, ryo = ryo }, "Success", "Claim")
			paid += 1
		end
	end
	log.info("%d participant(s) rewarded for %d damage", paid, math.floor(current.TotalDamage + 0.5))
end

local function defeat(live: Boss, current: State, now: number)
	current.Phase = "Defeated"
	WorldBossMode.setHealth(current, 0)
	WorldBossMode.endAttack(current)
	phaseEndsAt = now + SCHEDULE.CleanupSeconds
	deps.Notify.sendAll("boss.defeated", nil, "Success", "MatchWin")
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
	log.try("rewardParticipants", rewardParticipants, current)
	pushSnapshot(now)
end

local function expire(current: State, now: number)
	current.Phase = "Expired"
	WorldBossMode.endAttack(current)
	phaseEndsAt = now + SCHEDULE.CleanupSeconds
	deps.Notify.sendAll("boss.expired", nil, "Info")
	pushSnapshot(now)
	log.info("boss escaped with %d / %d health", math.floor(current.Health + 0.5), current.MaxHealth)
end

----------------------------------------------------------------
-- Announce and spawn
----------------------------------------------------------------

local function announce(now: number)
	local eligible = Context.eligiblePlayers(deps.Match)
	if #eligible < SCHEDULE.MinPlayers then
		nextEventAt = now + SCHEDULE.IntervalSeconds
		log.info("event skipped: %d player(s) available, %d needed", #eligible, SCHEDULE.MinPlayers)
		return
	end
	state = WorldBossMode.newState(#eligible, now)
	phaseEndsAt = now + SCHEDULE.AnnounceSeconds
	deps.Notify.sendAll("boss.announced", { seconds = SCHEDULE.AnnounceSeconds }, "Info")
	pushSnapshot(now)
	log.info("boss announced to %d player(s), spawning in %ds", #eligible, SCHEDULE.AnnounceSeconds)
end

local function spawnBoss(now: number)
	local eligible = Context.eligiblePlayers(deps.Match)
	if #eligible < SCHEDULE.MinPlayers then
		log.info("event cancelled: %d player(s) left when the boss was due", #eligible)
		reset(now)
		return
	end
	local arena = deps.Arena.acquire(Context.ArenaId)
	if arena == nil then
		log.warn("event cancelled: no free %s arena", Context.ArenaId)
		reset(now)
		return
	end
	-- The arena is tracked before anything else can fail, so every path out of here releases it.
	local trove = Trove.new()
	trove:Add(function()
		log.try("Arena.release " .. arena.Id, deps.Arena.release, arena)
	end)
	eventTrove = trove

	participants = {}
	for _, player in ipairs(eligible) do
		table.insert(participants, player.UserId)
		-- Taking part is being pulled in, so the quest credit does not depend on how the fight ends.
		reportQuest(player, "BossParticipation")
	end
	local fresh = WorldBossMode.newState(#participants, now)
	fresh.Phase = "Fighting"
	state = fresh
	phaseEndsAt = now + SCHEDULE.FightSeconds

	local live = Encounter.build(arena, fresh.MaxHealth)
	trove:Add(live.Model)
	-- Connected then added, rather than through trove:Connect: Trove accepts a signal whose Connect takes
	-- a variadic handler, and Context.Damaged deliberately declares the four argument types instead, so
	-- that a handler with the wrong shape is a type error here rather than a nil at runtime. The
	-- connection is still owned by the trove and still released with the encounter.
	trove:Add(deps.Combat.Damaged:Connect(function(sourceUserId: number, targetModel: Model, applied: number)
		local current = state
		if current ~= nil and boss == live and targetModel == live.Model then
			Encounter.recordDamage(live, current, sourceUserId, applied)
		end
	end))
	boss = live

	takePolicy()
	Encounter.place(arena, participants, live.Center)
	deps.Notify.sendAll("boss.started", nil, "Info")
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
	pushSnapshot(now)
	log.info(
		"boss spawned on arena %s slot %d: %d health, %d participant(s), %ds to kill it",
		arena.Id,
		arena.SlotIndex,
		fresh.MaxHealth,
		#participants,
		SCHEDULE.FightSeconds
	)
end

----------------------------------------------------------------
-- Tick
----------------------------------------------------------------

local function tickFight(live: Boss, current: State, now: number)
	if now >= phaseEndsAt then
		expire(current, now)
		return
	end
	local ok, outcome, dirty = pcall(Encounter.step, live, current, participants, now, TICK_SECONDS)
	if not ok then
		log.warn("fight tick failed: %s", tostring(outcome))
		-- A tick that blew up must not leave the boss stepping until the timer: close the event.
		expire(current, now)
	elseif outcome == "Defeated" then
		defeat(live, current, now)
	elseif outcome == "Empty" then
		log.info("no participant left in the arena")
		expire(current, now)
	elseif dirty == true then
		pushSnapshot(now)
	end
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local now = os.clock()
	local current = state
	if current == nil then
		if now >= nextEventAt then
			log.try("announce", announce, now)
		end
		return
	end

	if current.Phase == "Announced" then
		if now >= phaseEndsAt and not log.try("spawnBoss", spawnBoss, now) then
			-- A spawn that blew up must not be retried on every tick: drop it and schedule the next event.
			reset(now)
		end
	elseif current.Phase == "Fighting" then
		local live = boss
		if live == nil or live.Model.Parent == nil then
			log.warn("the boss model is gone: the event ends without a winner")
			expire(current, now)
		else
			tickFight(live, current, now)
		end
	elseif now >= phaseEndsAt then
		log.try("finish", finish, now)
		return
	end

	ticks += 1
	if ticks % TICKS_PER_SNAPSHOT == 0 then
		pushSnapshot(now)
	end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- True from the announce until the arena is released: PvP is off and players are being pulled into the
-- boss arena, which other services may want to know before they move somebody somewhere else.
function WorldBossService.isLive(): boolean
	return state ~= nil
end

function WorldBossService.Init(injected: Deps)
	deps = injected
	Encounter.Init(injected)
end

function WorldBossService.Start()
	if deps.Quest == nil then
		log.warn("Quest dependency missing: boss fights will not advance the World Boss quests")
	end
	nextEventAt = os.clock() + SCHEDULE.IntervalSeconds
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info(
		"%s started (every %ds, %ds warning, %ds fight, %d players minimum)",
		WorldBossMode.Id,
		SCHEDULE.IntervalSeconds,
		SCHEDULE.AnnounceSeconds,
		SCHEDULE.FightSeconds,
		SCHEDULE.MinPlayers
	)
end

return WorldBossService
