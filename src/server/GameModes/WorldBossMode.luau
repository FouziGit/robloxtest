--!strict
-- WorldBossMode: the rules of the World Boss event (docs/GAME_DESIGN.md §7), held the way Duel1v1 and
-- Team3v3 hold the rules of a match. WorldBossService owns the lifecycle (arena, boss model, teleports,
-- replication, rewards) and asks this module what the event should do: which phase the boss is in,
-- which attack it may start, how long it telegraphs, who that attack reaches, how hard it pushes and
-- what every participant earned. Nothing here touches an Instance, a remote or a service, so the rules
-- read (and break) on their own.
--
-- It deliberately does NOT implement the `GameModes.GameMode` interface of the registry beside it, and
-- the registry gets no WorldBoss loader: that contract is built around a `MatchConfig.ModeDef` (teams,
-- team size, rounds, round verdicts, Elo) and `MatchConfig.Modes` declares no WorldBoss entry — the
-- Boss arena is precisely the one ArenaService builds with a perimeter ring instead of team pads,
-- because no mode claims it. An event with one side, no rounds and no rating cannot answer CanStart,
-- RoundVerdict or End honestly, and a loader returning this table would hand MatchService a mode it
-- would try to run as a match. `Id` is kept so logs and snapshots name the event like a mode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BossPractice = require(Shared.Pure.BossPractice)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)

export type Attack = WorldBossConfig.AttackDef
export type Phase = Types.BossPhaseSnapshot

-- What one participant takes home. The bonus is kept apart from the base so the service can credit it
-- under its own reason (ProgressionConfig keys BossParticipation / BossKillBonus).
export type Reward = { Xp: number, Folios: number, BonusXp: number, BonusFolios: number }

-- Live rules state of one event. `Attack` is the attack being telegraphed (nil between attacks) and
-- `ResolveAt` the os.clock stamp its hit lands on. `Origin` and `Facing` are where the boss stood and
-- looked when the warning started: the packet that paints the floor and the test that deals the damage
-- both read THESE, never the live body, so the shape that hurts is the shape that was shown. The body
-- also stands still for the wind-up (Encounter.step), but that is the animation; this is the rule.
export type State = {
	Phase: Phase,
	PhaseIndex: number,
	Participants: number,
	MaxHealth: number,
	Health: number,
	TotalDamage: number,
	Damage: { [number]: number }, -- user id -> damage that user removed from the boss
	Cooldowns: { [string]: number }, -- attack id -> os.clock it may be started again
	Attack: Attack?,
	ResolveAt: number,
	Origin: Vector3,
	Facing: Vector3,
}

local XP = ProgressionConfig.XP
local FOLIOS = ProgressionConfig.Folios
local REWARDS = WorldBossConfig.Rewards
local BOSS = WorldBossConfig.Boss
-- WorldBossConfig stays free of Roblox globals and stores the body as {X, Y, Z}: build the vector once.
local BODY_SIZE = Vector3.new(BOSS.BodySize[1], BOSS.BodySize[2], BOSS.BodySize[3])
-- The body is square in plan; this is how close a target has to be to stand inside it. Derived in
-- WorldBossConfig, because the client's telegraph is held to the same number by a test and the two must
-- not be able to drift apart.
local CONTACT_RADIUS_STUDS = WorldBossConfig.contactRadius()
-- Share of the horizontal push sent upwards, so an attack throws its targets instead of sliding them
-- along the floor (the blasts of GlyphEffects are shaped the same way).
local KNOCKBACK_LIFT_FACTOR = 0.35
-- A share is never rounded down to nothing: the smallest rewarded share still pays one point before a
-- practice's factor, if any, scales it (rewardFor).
local MIN_REWARD = 1
local DEFAULT_FACING = Vector3.new(0, 0, -1)
local EPSILON = 1e-3

local WorldBossMode = {}

WorldBossMode.Id = "WorldBoss"

----------------------------------------------------------------
-- Geometry helpers (ground plane: a jump never dodges an attack)
----------------------------------------------------------------

local function flatOffset(origin: Vector3, target: Vector3): (Vector3, number)
	local offset = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	return offset, offset.Magnitude
end

local function flatUnit(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < EPSILON then
		return DEFAULT_FACING
	end
	return flat.Unit
end

function WorldBossMode.bodySize(): Vector3
	return BODY_SIZE
end

function WorldBossMode.contactRadius(): number
	return CONTACT_RADIUS_STUDS
end

----------------------------------------------------------------
-- Event state
----------------------------------------------------------------

-- Fresh state for a fight by `participants` players, with `maxHealth` when the caller sets it (a practice,
-- WorldBossConfig.Practice) and the event's WorldBossConfig.healthFor otherwise. Every attack starts on its
-- own cooldown, so the first minute already has the rhythm of the rest of the fight instead of a double opener.
function WorldBossMode.newState(participants: number, now: number, maxHealth: number?): State
	local health = maxHealth or WorldBossConfig.healthFor(participants)
	local cooldowns: { [string]: number } = {}
	for _, attack in ipairs(WorldBossConfig.Attacks) do
		cooldowns[attack.Id] = now + attack.CooldownSeconds
	end
	return {
		Phase = "Announced",
		PhaseIndex = 1,
		Participants = participants,
		MaxHealth = health,
		Health = health,
		TotalDamage = 0,
		Damage = {},
		Cooldowns = cooldowns,
		Attack = nil,
		ResolveAt = 0,
		Origin = Vector3.zero,
		Facing = DEFAULT_FACING,
	}
end

function WorldBossMode.phaseDef(index: number): { Threshold: number, AttackSpeed: number, MoveSpeed: number }
	local phases = WorldBossConfig.Phases
	return phases[math.clamp(index, 1, #phases)]
end

-- Records the boss health and answers whether the fight moved into another phase (worth a log and an
-- immediate snapshot: the phase changes how fast the boss moves and warns).
--
-- A phase is only ever entered, never left. In the event the health only falls, so this changes nothing
-- there; in a practice a joiner's first hit raises the health (`grow`), and the fraction climbing back over a
-- threshold must not hand the boss back its slower rhythm, or a practice could be reset to phase 1 by joining.
function WorldBossMode.setHealth(state: State, health: number): boolean
	state.Health = math.clamp(health, 0, state.MaxHealth)
	local fraction = if state.MaxHealth > 0 then state.Health / state.MaxHealth else 0
	local index = math.max(state.PhaseIndex, WorldBossConfig.phaseFor(fraction))
	if index == state.PhaseIndex then
		return false
	end
	state.PhaseIndex = index
	return true
end

-- A practice growing by `added` health for a player who joined it (BossPractice.growthOnHit): the maximum and
-- the health left both rise, so the damage already dealt stays dealt and the shares keep adding up to it.
function WorldBossMode.grow(state: State, added: number)
	if added <= 0 then
		return
	end
	state.MaxHealth += added
	state.Health += added
end

function WorldBossMode.moveSpeed(state: State): number
	return WorldBossMode.phaseDef(state.PhaseIndex).MoveSpeed
end

----------------------------------------------------------------
-- Contribution and rewards
----------------------------------------------------------------

-- Damage `userId` actually removed from the boss. Only damage that landed is recorded, so the shares
-- always add up to the health the boss lost.
function WorldBossMode.recordDamage(state: State, userId: number, amount: number)
	if amount <= 0 then
		return
	end
	state.Damage[userId] = (state.Damage[userId] or 0) + amount
	state.TotalDamage += amount
end

function WorldBossMode.shareOf(state: State, userId: number): number
	if state.TotalDamage <= 0 then
		return 0
	end
	return math.clamp((state.Damage[userId] or 0) / state.TotalDamage, 0, 1)
end

-- What a damage share is worth: nil under WorldBossConfig.Rewards.MinShareToReward (the player was
-- there but did nothing), the participation reward scaled by the share otherwise, plus the kill bonus
-- above KillBonusShare. docs/ECONOMY.md §2 quotes the numbers a top contributor takes home.
--
-- `factor` is the fraction of all that a practice pays (WorldBossConfig.Practice.RewardFactor); the event
-- passes none and pays in full. Each amount is scaled once, after the share, through BossPractice.scaled, so
-- a practice can round a small line down to nothing (the service credits no zero). A factor of zero or less
-- pays nothing at all.
function WorldBossMode.rewardFor(share: number, factor: number?): Reward?
	local scale = factor or 1
	if share < REWARDS.MinShareToReward or scale <= 0 then
		return nil
	end
	local bonus = share >= REWARDS.KillBonusShare
	return {
		Xp = BossPractice.scaled(math.max(MIN_REWARD, math.floor(XP.BossParticipation * share + 0.5)), scale),
		Folios = BossPractice.scaled(math.max(MIN_REWARD, math.floor(FOLIOS.BossParticipation * share + 0.5)), scale),
		BonusXp = if bonus then BossPractice.scaled(XP.BossKillBonus, scale) else 0,
		BonusFolios = if bonus then BossPractice.scaled(FOLIOS.BossKillBonus, scale) else 0,
	}
end

----------------------------------------------------------------
-- Attacks
----------------------------------------------------------------

-- The attack the boss starts next: unlocked by the current phase, off cooldown, and among those the
-- one that has been ready the longest, so the whole kit stays in rotation. No randomness — the same
-- fight state always picks the same attack, which is what makes the telegraphs learnable.
function WorldBossMode.selectAttack(state: State, now: number): Attack?
	local best: Attack? = nil
	local bestReadyAt = math.huge
	for _, attack in ipairs(WorldBossConfig.Attacks) do
		if attack.MinPhase <= state.PhaseIndex then
			local readyAt = state.Cooldowns[attack.Id] or 0
			if readyAt <= now and readyAt < bestReadyAt then
				best = attack
				bestReadyAt = readyAt
			end
		end
	end
	return best
end

-- Warning window of `attack` in the current phase: a later phase warns for less time (AttackSpeed).
function WorldBossMode.telegraphSeconds(state: State, attack: Attack): number
	return attack.TelegraphSeconds / WorldBossMode.phaseDef(state.PhaseIndex).AttackSpeed
end

-- Starts the telegraph and returns how long it lasts. The cooldown runs from the warning, not from the
-- hit, so a long telegraph never pushes the whole rotation back. `origin` and `facing` are frozen into
-- the state here: a warning painted at one origin and a hit resolved at another was the first thing the
-- telegraph test could not see, because it compares shapes and a walk is a translation.
function WorldBossMode.beginAttack(state: State, attack: Attack, now: number, origin: Vector3, facing: Vector3): number
	local seconds = WorldBossMode.telegraphSeconds(state, attack)
	state.Attack = attack
	state.ResolveAt = now + seconds
	state.Origin = origin
	state.Facing = facing
	state.Cooldowns[attack.Id] = now + attack.CooldownSeconds
	return seconds
end

function WorldBossMode.endAttack(state: State)
	state.Attack = nil
	state.ResolveAt = 0
end

-- Farthest an attack can reach, so the service queries humanoids once and filters with isInShape.
function WorldBossMode.reachOf(attack: Attack): number
	if attack.Shape == "Circle" then
		return attack.Radius
	end
	return math.max(attack.Radius, attack.Range)
end

-- True when `target` stands in the shape `attack` draws around the boss:
--   Circle: within Radius of the boss;
--   Cone: in front of it up to Range, inside a wedge that opens to Radius at that range and never
--         closes below the body itself (hugging the boss is not a dodge);
--   Ring: outside Radius — the safe centre — and within Range.
function WorldBossMode.isInShape(attack: Attack, origin: Vector3, facing: Vector3, target: Vector3): boolean
	local offset, distance = flatOffset(origin, target)
	if attack.Shape == "Circle" then
		return distance <= attack.Radius
	end
	if attack.Shape == "Ring" then
		return distance > attack.Radius and distance <= attack.Range
	end
	local look = flatUnit(facing)
	local forward = offset:Dot(look)
	if forward <= 0 or forward > attack.Range then
		return false
	end
	local halfWidth = math.max(attack.Radius * (forward / attack.Range), CONTACT_RADIUS_STUDS)
	return (offset - look * forward).Magnitude <= halfWidth
end

-- Push of an attack: away from the boss with some lift. A target standing exactly on the boss is
-- pushed along the way it faces.
function WorldBossMode.knockbackVelocity(attack: Attack, origin: Vector3, facing: Vector3, target: Vector3): Vector3
	local offset, distance = flatOffset(origin, target)
	local direction = if distance > EPSILON then offset / distance else flatUnit(facing)
	return direction * attack.Knockback + Vector3.new(0, attack.Knockback * KNOCKBACK_LIFT_FACTOR, 0)
end

----------------------------------------------------------------
-- Body: contact damage and walking
----------------------------------------------------------------

-- True while `target` stands inside the boss body (WorldBossConfig.Boss.ContactDamage applies).
function WorldBossMode.insideBody(origin: Vector3, target: Vector3): boolean
	local _, distance = flatOffset(origin, target)
	return distance <= CONTACT_RADIUS_STUDS and math.abs(target.Y - origin.Y) <= BODY_SIZE.Y / 2
end

-- Where the boss stands after walking at `speed` for `deltaSeconds` towards `target`: straight at it
-- on the ground plane, stopping as its body touches it (it is anchored, the service steps the CFrame).
function WorldBossMode.stepToward(origin: Vector3, target: Vector3, speed: number, deltaSeconds: number): Vector3
	local offset, distance = flatOffset(origin, target)
	if distance <= EPSILON then
		return origin
	end
	local travel = math.min(speed * deltaSeconds, distance - CONTACT_RADIUS_STUDS)
	if travel <= 0 then
		return origin
	end
	return origin + (offset / distance) * travel
end

----------------------------------------------------------------
-- Replication
----------------------------------------------------------------

-- Wire state of the fight (BossChanged). MyShare is filled per receiver by WorldBossService; `practice` says
-- the fight is a practice (D-132), which the HUD titles as such.
function WorldBossMode.snapshot(
	state: State,
	secondsLeft: number,
	myShare: number,
	practice: boolean
): Types.BossSnapshot
	local attack = state.Attack
	return {
		Phase = state.Phase,
		SecondsLeft = math.max(0, math.ceil(secondsLeft)),
		Health = math.floor(state.Health + 0.5),
		MaxHealth = state.MaxHealth,
		PhaseIndex = state.PhaseIndex,
		Participants = state.Participants,
		TelegraphKey = if attack ~= nil then attack.NameKey else nil,
		MyShare = myShare,
		Practice = practice,
	}
end

return WorldBossMode
