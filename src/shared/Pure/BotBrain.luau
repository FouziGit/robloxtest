--!strict
-- What a Forger decides (D-131): whom it chases, where it walks, when it swings or throws, when it gives up,
-- and who is paid when it falls. Pure module: no require, no Roblox global. The shapes of BotConfig it reads
-- are re-declared here, every number comes through the caller, and nothing is random, so the same memory
-- and the same perception always give the same decision (tests/BotBrain.spec.luau).
--
-- The service perceives, this module decides, and the service applies. Every attack is a wind-up the server
-- times and announces (the ForgerTell effect) on an aim frozen for that step, then a resolve on that frozen
-- aim; the service re-checks every target before it deals a point of damage. Positions are on the ground
-- plane of the Battleground's local frame (BattlegroundLayout), heights only for reach.

export type Point = { X: number, Z: number }

-- BotConfig's MeleeDef, BoltDef and TierDef, field for field. Every field, not only the ones read here: a
-- nested table's type is matched exactly, so a TierDef whose Melee lacked one of BotConfig's fields would
-- refuse the tiers BotConfig ships.
export type MeleeDef = {
	Damage: { number },
	Range: number,
	HalfWidth: number,
	HalfHeight: number,
	WindupSeconds: number,
	ChainGapSeconds: number,
	FinisherGapSeconds: number,
	ChainSlackStuds: number,
	RecoverySeconds: number,
	FinisherKnockback: number,
	FinisherLift: number,
	FinisherStunSeconds: number,
	FinisherBreaksGuard: boolean,
	FinisherRagdoll: boolean,
}
export type BoltDef = {
	Damage: number,
	Range: number,
	MinRange: number,
	HitRadius: number,
	HalfHeight: number,
	SpawnOffset: number,
	WindupSeconds: number,
	CooldownSeconds: number,
	KnockbackSpeed: number,
}
export type TierDef = {
	Role: "Melee" | "Ranged",
	Health: number,
	WalkSpeed: number,
	Scale: number,
	AggroRadius: number,
	LoseSightSeconds: number,
	AggroMemorySeconds: number,
	CommitSeconds: number,
	SwitchMarginStuds: number,
	KeepRange: { number },
	StaggerImmune: boolean,
	Melee: MeleeDef,
	Bolt: BoltDef?,
	RewardKey: string?,
}

export type Targeting = {
	MaxEngagedPerTarget: number,
	MaxAttackersPerTarget: number,
	LoadPenaltyStuds: number,
	RetaliationStuds: number,
	FlankStuds: number,
	CircleStuds: number,
	StrafeStuds: number,
	StrafeSeconds: number,
	StrafePhaseSeconds: number,
	HomeRadiusStuds: number,
	MeleeStartInsetStuds: number,
	TargetRestSeconds: number,
	PostFinisherRestSeconds: number,
}
export type Reach = { UnreachableHeightStuds: number, UnreachableSeconds: number, IgnoreSeconds: number }
export type Stagger = {
	HitSeconds: number,
	KnockbackSeconds: number,
	MaxPerWindow: number,
	WindowSeconds: number,
	ImmuneSeconds: number,
}
-- BotConfig's Targeting, Reach and Stagger, its shortest tells, and CombatConfig.Hit.StunMaxSeconds.
export type Rules = {
	Targeting: Targeting,
	Reach: Reach,
	Stagger: Stagger,
	ArrivalGraceSeconds: number,
	MinWindupSeconds: number,
	MinChainGapSeconds: number,
	StunMaxSeconds: number,
}

-- A player as one Forger sees them. Load: how many OTHER Forgers chase them right now.
export type Target = {
	UserId: number,
	X: number,
	Y: number,
	Z: number,
	Visible: boolean,
	InCamp: boolean,
	Down: boolean,
	ArrivedAt: number,
	Load: number,
}
-- What one Forger knows this think. Index: its slot. X, Y, Z: its root. Home: its spawn point. Center: the
-- page's centre, which it faces while idle. RankFor[userId]: its rank among the Forgers on that player by
-- distance (engagedRank). TokenFreeFor[userId]: whether a melee chain may start on that player (tokenFree).
export type Perception = {
	Now: number,
	Index: number,
	X: number,
	Y: number,
	Z: number,
	HomeX: number,
	HomeZ: number,
	CenterX: number,
	CenterZ: number,
	Targets: { Target },
	RankFor: { [number]: number },
	TokenFreeFor: { [number]: boolean },
}

export type AttackKind = "Melee" | "Bolt"
-- A wind-up in progress: which step of the chain, when it resolves, and the aim it was shown on.
export type Attack = {
	Kind: AttackKind,
	Step: number,
	ResolveAt: number,
	AimX: number,
	AimZ: number,
	TargetUserId: number,
}
export type Memory = {
	Mode: "Idle" | "Engage" | "Return",
	TargetUserId: number?,
	TargetSince: number,
	LastSeenAt: number,
	LastHitBy: number?,
	LastHitAt: number,
	Attack: Attack?,
	RecoverUntil: number,
	BoltReadyAt: number,
	StaggerUntil: number,
	StaggerTimes: { number },
	ImmuneUntil: number,
	UnreachableSince: number?,
	IgnoreUntil: { [number]: number },
}
-- A wind-up that came due: the service resolves it on this aim. Final: the last step of a melee chain.
export type Resolve = {
	Kind: AttackKind,
	Step: number,
	AimX: number,
	AimZ: number,
	Final: boolean,
	TargetUserId: number,
}
-- One think's orders. Goal: where to walk. Stand: stop where it is. Face: the point to face. Start: a new
-- wind-up; Continue: the next step of a chain (each gets its clip and its tell). Resolve: a wind-up to land.
-- Ended: a melee chain that stopped short of its finisher. Heal: back home with nobody to chase.
export type Decision = {
	Goal: Point?,
	Stand: boolean,
	FaceX: number?,
	FaceZ: number?,
	Start: Attack?,
	Continue: Attack?,
	Resolve: Resolve?,
	Ended: { TargetUserId: number }?,
	Heal: boolean,
}
export type StaggerSource = "Hit" | "Knockback" | "Control"
-- One source's slow on a Forger (addSlow): the factor of its pace, and until when.
export type Slow = { Factor: number, Until: number }

local BotBrain = {}

local function newDecision(): Decision
	return {
		Goal = nil,
		Stand = false,
		FaceX = nil,
		FaceZ = nil,
		Start = nil,
		Continue = nil,
		Resolve = nil,
		Ended = nil,
		Heal = false,
	}
end

local function distanceBetween(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
end

-- The unit vector along (dx, dz). A target standing exactly on the Forger has no direction; any unit vector
-- then does, because the melee box contains its own origin whatever way it faces.
local function unit(dx: number, dz: number): (number, number)
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= 0 then
		return 1, 0
	end
	return dx / length, dz / length
end

local function find(perception: Perception, userId: number): Target?
	for _, target in ipairs(perception.Targets) do
		if target.UserId == userId then
			return target
		end
	end
	return nil
end

-- Stands still, facing (x, z).
local function face(decision: Decision, x: number, z: number)
	decision.Stand = true
	decision.FaceX = x
	decision.FaceZ = z
end

function BotBrain.newMemory(): Memory
	return {
		Mode = "Idle",
		TargetUserId = nil,
		TargetSince = 0,
		LastSeenAt = 0,
		LastHitBy = nil,
		LastHitAt = 0,
		Attack = nil,
		RecoverUntil = 0,
		BoltReadyAt = 0,
		StaggerUntil = 0,
		StaggerTimes = {},
		ImmuneUntil = 0,
		UnreachableSince = nil,
		IgnoreUntil = {},
	}
end

----------------------------------------------------------------
-- Targets
----------------------------------------------------------------

-- Everything a target must be except standing: past the arrival grace, not ignored, and never inside the
-- camp -- not even the one who just hit it from there, so the camp cannot be farmed; that hit earns nothing
-- either (creditHit).
local function eligible(rules: Rules, memory: Memory, target: Target, now: number): boolean
	if target.InCamp or now - target.ArrivedAt < rules.ArrivalGraceSeconds then
		return false
	end
	local ignoredUntil = memory.IgnoreUntil[target.UserId]
	return ignoredUntil == nil or ignoredUntil <= now
end

-- Whether a Forger may chase, or hit, this player at all: eligible, and standing -- a player a finisher
-- knocked down is never hit again before they are up.
function BotBrain.isValidTarget(rules: Rules, memory: Memory, target: Target, now: number): boolean
	return not target.Down and eligible(rules, memory, target, now)
end

-- The current target when it is down but otherwise still a target. The Forger waits over them rather than
-- giving them up: a Forger with nobody to chase walks home and heals there, and a finisher landed beside its
-- home would otherwise hand it a full heal in the middle of every fight.
local function downedTarget(rules: Rules, memory: Memory, perception: Perception): Target?
	local userId = memory.TargetUserId
	local target = if userId ~= nil then find(perception, userId) else nil
	if target ~= nil and target.Down and eligible(rules, memory, target, perception.Now) then
		return target
	end
	return nil
end

-- Lower is better: the distance, plus LoadPenaltyStuds per other Forger already on them, minus
-- RetaliationStuds for whoever hit this one within its AggroMemorySeconds.
function BotBrain.score(tier: TierDef, rules: Rules, memory: Memory, perception: Perception, target: Target): number
	local value = distanceBetween(perception.X, perception.Z, target.X, target.Z)
		+ rules.Targeting.LoadPenaltyStuds * target.Load
	if memory.LastHitBy == target.UserId and perception.Now - memory.LastHitAt <= tier.AggroMemorySeconds then
		value -= rules.Targeting.RetaliationStuds
	end
	return value
end

-- A valid player is worth considering when the Forger sees them within its aggro radius, when they hit it
-- recently, or when they are its current target and were seen within LoseSightSeconds.
local function isCandidate(tier: TierDef, memory: Memory, perception: Perception, target: Target): boolean
	local now = perception.Now
	local distance = distanceBetween(perception.X, perception.Z, target.X, target.Z)
	if target.Visible and distance <= tier.AggroRadius then
		return true
	end
	if memory.LastHitBy == target.UserId and now - memory.LastHitAt <= tier.AggroMemorySeconds then
		return true
	end
	return memory.TargetUserId == target.UserId and now - memory.LastSeenAt <= tier.LoseSightSeconds
end

-- Picks the target and records it. The best score wins, ties to the lowest UserId; a player
-- MaxAttackersPerTarget others already chase is skipped while a less crowded candidate exists; and the
-- current target is kept while the Forger is committed to it (CommitSeconds) or while nobody beats it by
-- SwitchMarginStuds. nil when there is nobody to chase.
function BotBrain.selectTarget(tier: TierDef, rules: Rules, memory: Memory, perception: Perception): Target?
	local now = perception.Now
	local current = if memory.TargetUserId ~= nil then find(perception, memory.TargetUserId) else nil
	if current ~= nil and current.Visible then
		memory.LastSeenAt = now
	end
	local maxAttackers = rules.Targeting.MaxAttackersPerTarget
	local candidates: { Target } = {}
	local roomy = false
	for _, target in ipairs(perception.Targets) do
		if BotBrain.isValidTarget(rules, memory, target, now) and isCandidate(tier, memory, perception, target) then
			table.insert(candidates, target)
			roomy = roomy or target.Load < maxAttackers
		end
	end
	local best: Target?, bestScore = nil, math.huge
	local currentScore: number? = nil
	for _, target in ipairs(candidates) do
		if not (roomy and target.Load >= maxAttackers) then
			local value = BotBrain.score(tier, rules, memory, perception, target)
			if target.UserId == memory.TargetUserId then
				currentScore = value
			end
			if best == nil or value < bestScore or (value == bestScore and target.UserId < best.UserId) then
				best, bestScore = target, value
			end
		end
	end
	if best == nil then
		memory.TargetUserId = nil
		memory.UnreachableSince = nil
		return nil
	end
	memory.Mode = "Engage"
	if current ~= nil and currentScore ~= nil then
		local committed = now - memory.TargetSince < tier.CommitSeconds
		if committed or bestScore > currentScore - tier.SwitchMarginStuds then
			return current
		end
	end
	memory.TargetUserId = best.UserId
	memory.TargetSince = now
	memory.LastSeenAt = now
	memory.UnreachableSince = nil
	return best
end

-- Whether a body `dy` studs above a root (below it, negative) is out of a Forger's reach: more than
-- UnreachableHeightStuds either way. Hovering over the Forgers and sinking under the floor are one escape.
function BotBrain.outOfReach(rules: Rules, dy: number): boolean
	return math.abs(dy) > rules.Reach.UnreachableHeightStuds
end

-- Whether the target is still worth chasing: one held out of reach of the Forger's root for UnreachableSeconds
-- -- hovering over it or sunk under it, whatever its role -- is ignored for IgnoreSeconds.
local function stillReachable(rules: Rules, memory: Memory, perception: Perception, target: Target): boolean
	local now = perception.Now
	local reach = rules.Reach
	if not BotBrain.outOfReach(rules, target.Y - perception.Y) then
		memory.UnreachableSince = nil
		return true
	end
	local since = memory.UnreachableSince
	if since == nil then
		memory.UnreachableSince = now
		return true
	end
	if now - since < reach.UnreachableSeconds then
		return true
	end
	for userId, untilTime in pairs(memory.IgnoreUntil) do
		if untilTime <= now then
			memory.IgnoreUntil[userId] = nil
		end
	end
	memory.IgnoreUntil[target.UserId] = now + reach.IgnoreSeconds
	memory.UnreachableSince = nil
	memory.TargetUserId = nil
	return false
end

----------------------------------------------------------------
-- Attacks
----------------------------------------------------------------

-- A wind-up that came due resolves on its frozen aim. A melee step that is not the finisher goes on to the
-- next while its target is still valid within Range + ChainSlackStuds, re-aimed at them for that step's own
-- tell; otherwise the chain ends and the Forger recovers.
local function continueAttack(tier: TierDef, rules: Rules, memory: Memory, perception: Perception, decision: Decision)
	local attack = memory.Attack :: Attack
	local now = perception.Now
	decision.Stand = true
	if now < attack.ResolveAt then
		decision.FaceX, decision.FaceZ = perception.X + attack.AimX, perception.Z + attack.AimZ
		return
	end
	local melee = tier.Melee
	local steps = #melee.Damage
	local final = attack.Kind == "Melee" and attack.Step >= steps
	decision.Resolve = {
		Kind = attack.Kind,
		Step = attack.Step,
		AimX = attack.AimX,
		AimZ = attack.AimZ,
		Final = final,
		TargetUserId = attack.TargetUserId,
	}
	memory.Attack = nil
	if attack.Kind == "Bolt" then
		return
	end
	if not final then
		local target = find(perception, attack.TargetUserId)
		if
			target ~= nil
			and BotBrain.isValidTarget(rules, memory, target, now)
			and distanceBetween(perception.X, perception.Z, target.X, target.Z)
				<= melee.Range + melee.ChainSlackStuds
		then
			local nextStep = attack.Step + 1
			local gap = if nextStep >= steps then melee.FinisherGapSeconds else melee.ChainGapSeconds
			attack.Step = nextStep
			attack.ResolveAt = now + math.max(gap, rules.MinChainGapSeconds)
			attack.AimX, attack.AimZ = unit(target.X - perception.X, target.Z - perception.Z)
			memory.Attack = attack
			decision.Continue = attack
			decision.FaceX, decision.FaceZ = perception.X + attack.AimX, perception.Z + attack.AimZ
			return
		end
		decision.Ended = { TargetUserId = attack.TargetUserId }
	end
	memory.RecoverUntil = now + melee.RecoverySeconds
end

-- A melee chain may start when the target stands MeleeStartInsetStuds inside the swing's reach, nobody else is
-- already swinging at them and they are not resting (TokenFreeFor), and -- for a brawler -- the Forger is
-- among the first MaxEngagedPerTarget on them.
local function canSwing(tier: TierDef, rules: Rules, perception: Perception, target: Target): boolean
	local targeting = rules.Targeting
	local distance = distanceBetween(perception.X, perception.Z, target.X, target.Z)
	if distance > tier.Melee.Range - targeting.MeleeStartInsetStuds then
		return false
	end
	if perception.TokenFreeFor[target.UserId] ~= true then
		return false
	end
	local rank = perception.RankFor[target.UserId] or 1
	return tier.Role ~= "Melee" or rank <= targeting.MaxEngagedPerTarget
end

-- Starts a bolt (visible, inside [MinRange, Range], off cooldown) or else a melee chain, and freezes its aim.
-- Nothing starts while the Forger recovers from its last chain: a bolt thrown the moment a chain ends would
-- be a fourth hit with no rest before it. Returns whether a wind-up started.
local function startAttack(
	tier: TierDef,
	rules: Rules,
	memory: Memory,
	perception: Perception,
	target: Target,
	decision: Decision
): boolean
	local now = perception.Now
	if now < memory.RecoverUntil then
		return false
	end
	local dx, dz = target.X - perception.X, target.Z - perception.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local aimX, aimZ = unit(dx, dz)
	local bolt = tier.Bolt
	local attack: Attack
	if
		bolt ~= nil
		and now >= memory.BoltReadyAt
		and target.Visible
		and distance >= bolt.MinRange
		and distance <= bolt.Range
	then
		local windup = math.max(bolt.WindupSeconds, rules.MinWindupSeconds)
		attack = {
			Kind = "Bolt",
			Step = 1,
			ResolveAt = now + windup,
			AimX = aimX,
			AimZ = aimZ,
			TargetUserId = target.UserId,
		}
		memory.BoltReadyAt = now + windup + bolt.CooldownSeconds
	elseif canSwing(tier, rules, perception, target) then
		local windup = math.max(tier.Melee.WindupSeconds, rules.MinWindupSeconds)
		attack = {
			Kind = "Melee",
			Step = 1,
			ResolveAt = now + windup,
			AimX = aimX,
			AimZ = aimZ,
			TargetUserId = target.UserId,
		}
	else
		return false
	end
	memory.Attack = attack
	decision.Start = attack
	face(decision, perception.X + aimX, perception.Z + aimZ)
	return true
end

----------------------------------------------------------------
-- Movement
----------------------------------------------------------------

-- Which way a strafe runs right now: it flips every StrafeSeconds, phased by the Forger's slot so a ring of
-- them never turns as one. Deterministic, never random.
local function strafeSide(rules: Rules, perception: Perception): number
	local targeting = rules.Targeting
	local phase = (perception.Now + perception.Index * targeting.StrafePhaseSeconds) / targeting.StrafeSeconds
	return if math.floor(phase) % 2 == 0 then 1 else -1
end

-- A point `radial` studs from the target on the Forger's side of it, pushed `lateral` studs sideways.
local function around(perception: Perception, target: Target, radial: number, lateral: number): Point
	local awayX, awayZ = unit(perception.X - target.X, perception.Z - target.Z)
	return {
		X = target.X + awayX * radial - awayZ * lateral,
		Z = target.Z + awayZ * radial + awayX * lateral,
	}
end

-- A brawler: the first on a target closes to its KeepRange's far edge and stands there; the next ones take
-- a flank either side (FlankStuds, the side by rank parity); the rest strafe on a circle of CircleStuds,
-- out of reach, waiting for a place.
local function brawlerGoal(tier: TierDef, rules: Rules, perception: Perception, target: Target, decision: Decision)
	local targeting = rules.Targeting
	local rank = perception.RankFor[target.UserId] or 1
	local standoff = tier.KeepRange[2]
	if rank > targeting.MaxEngagedPerTarget then
		decision.Goal =
			around(perception, target, targeting.CircleStuds, targeting.StrafeStuds * strafeSide(rules, perception))
	elseif rank > 1 then
		local side = if rank % 2 == 0 then 1 else -1
		decision.Goal = around(perception, target, standoff, targeting.FlankStuds * side)
	elseif distanceBetween(perception.X, perception.Z, target.X, target.Z) <= standoff then
		face(decision, target.X, target.Z)
	else
		decision.Goal = around(perception, target, standoff, 0)
	end
end

-- A caster keeps inside its KeepRange band: it closes on a target it cannot see, backs off inside the band's
-- near edge, closes beyond its far edge, and strafes StrafeStuds sideways inside it.
local function casterGoal(tier: TierDef, rules: Rules, perception: Perception, target: Target, decision: Decision)
	local distance = distanceBetween(perception.X, perception.Z, target.X, target.Z)
	local band = tier.KeepRange
	if not target.Visible then
		decision.Goal = { X = target.X, Z = target.Z }
	elseif distance < band[1] then
		decision.Goal = around(perception, target, band[1], 0)
	elseif distance > band[2] then
		decision.Goal = around(perception, target, band[2], 0)
	else
		decision.Goal =
			around(perception, target, distance, rules.Targeting.StrafeStuds * strafeSide(rules, perception))
	end
end

-- Nobody to chase: walk home, and once there heal once and face the page's centre.
local function goHome(rules: Rules, memory: Memory, perception: Perception, decision: Decision)
	local away = distanceBetween(perception.X, perception.Z, perception.HomeX, perception.HomeZ)
	if away > rules.Targeting.HomeRadiusStuds then
		memory.Mode = "Return"
		decision.Goal = { X = perception.HomeX, Z = perception.HomeZ }
		return
	end
	if memory.Mode ~= "Idle" then
		decision.Heal = true
		memory.Mode = "Idle"
	end
	face(decision, perception.CenterX, perception.CenterZ)
end

----------------------------------------------------------------
-- The think
----------------------------------------------------------------

-- One think: staggered, it stands; with a wind-up pending, it waits for it and resolves it; over a target it
-- knocked down, it waits for them to rise; otherwise it picks a target, starts an attack if it can, and moves.
function BotBrain.decide(tier: TierDef, rules: Rules, memory: Memory, perception: Perception): Decision
	local decision = newDecision()
	if perception.Now < memory.StaggerUntil then
		decision.Stand = true
		return decision
	end
	if memory.Attack ~= nil then
		continueAttack(tier, rules, memory, perception, decision)
		return decision
	end
	local downed = downedTarget(rules, memory, perception)
	if downed ~= nil then
		face(decision, downed.X, downed.Z)
		return decision
	end
	local target = BotBrain.selectTarget(tier, rules, memory, perception)
	if target ~= nil and not stillReachable(rules, memory, perception, target) then
		-- The one just ignored is no longer valid: pick again, and start the new one's own clock.
		target = BotBrain.selectTarget(tier, rules, memory, perception)
		if target ~= nil then
			stillReachable(rules, memory, perception, target)
		end
	end
	if target == nil then
		goHome(rules, memory, perception, decision)
		return decision
	end
	if startAttack(tier, rules, memory, perception, target, decision) then
		return decision
	end
	if tier.Role == "Melee" then
		brawlerGoal(tier, rules, perception, target, decision)
	else
		casterGoal(tier, rules, perception, target, decision)
	end
	return decision
end

-- A player hit this Forger: remembered for retaliation.
function BotBrain.noteHit(memory: Memory, userId: number, now: number)
	memory.LastHitBy = userId
	memory.LastHitAt = now
end

-- Staggers the Forger, which stands still and loses any wind-up it had. A glyph's stun ("Control") holds
-- every tier for its length, capped at StunMaxSeconds; a knockback staggers every tier too, heavy ones
-- included; a hit staggers only a tier that is not StaggerImmune, at most MaxPerWindow times per
-- WindowSeconds -- the next hit inside the window grants ImmuneSeconds of poise instead. Returns whether
-- it applied, and the wind-up it cancelled so the service can rest that wind-up's target.
function BotBrain.stagger(
	tier: TierDef,
	rules: Rules,
	memory: Memory,
	now: number,
	source: StaggerSource,
	seconds: number?
): (boolean, Attack?)
	local config = rules.Stagger
	local untilTime: number
	if source == "Control" then
		local stun = math.min(seconds or 0, rules.StunMaxSeconds)
		if stun <= 0 then
			return false, nil
		end
		untilTime = now + stun
	elseif source == "Knockback" then
		untilTime = now + config.KnockbackSeconds
	else
		if tier.StaggerImmune or now < memory.ImmuneUntil then
			return false, nil
		end
		local times = memory.StaggerTimes
		local kept = 0
		for index = 1, #times do
			if now - times[index] < config.WindowSeconds then
				kept += 1
				times[kept] = times[index]
			end
		end
		for index = #times, kept + 1, -1 do
			times[index] = nil
		end
		if kept >= config.MaxPerWindow then
			memory.ImmuneUntil = now + config.ImmuneSeconds
			table.clear(times)
			return false, nil
		end
		table.insert(times, now)
		untilTime = now + config.HitSeconds
	end
	memory.StaggerUntil = math.max(memory.StaggerUntil, untilTime)
	local cancelled = memory.Attack
	memory.Attack = nil
	return true, cancelled
end

----------------------------------------------------------------
-- Slows
----------------------------------------------------------------

-- Slows a Forger's pace to `factor` for `seconds` under the source `key` (a glyph id), as MovementService slows
-- a player: the same key again keeps its strongest factor and its latest end, and two keys never merge -- a
-- root ends on its own time, whatever weaker slow came after it.
function BotBrain.addSlow(slows: { [string]: Slow }, key: string, factor: number, seconds: number, now: number)
	local untilTime = now + seconds
	local existing = slows[key]
	if existing ~= nil and existing.Until > now then
		existing.Factor = math.min(existing.Factor, factor)
		existing.Until = math.max(existing.Until, untilTime)
	else
		slows[key] = { Factor = factor, Until = untilTime }
	end
end

-- The factor of its pace a Forger walks at now: the strongest slow still running, 1 with none. Every slow that
-- has run out is forgotten.
function BotBrain.slowFactor(slows: { [string]: Slow }, now: number): number
	local factor = 1
	for key, slow in pairs(slows) do
		if slow.Until <= now then
			slows[key] = nil
		else
			factor = math.min(factor, slow.Factor)
		end
	end
	return factor
end

-- Whether a melee chain may start on this player: no Forger has a melee wind-up pending on them (`pending`:
-- every Forger's pending attack), and their rest after the last chain is over. One chain at a time per player.
function BotBrain.tokenFree(pending: { Attack }, restUntil: number, targetUserId: number, now: number): boolean
	if now < restUntil then
		return false
	end
	for _, attack in ipairs(pending) do
		if attack.Kind == "Melee" and attack.TargetUserId == targetUserId then
			return false
		end
	end
	return true
end

-- When a player's rest ends after a chain: TargetRestSeconds; after a finisher, long enough for its stun to
-- end and PostFinisherRestSeconds more, if that is longer.
function BotBrain.restAfter(rules: Rules, now: number, finisher: boolean, stunApplied: number): number
	local targeting = rules.Targeting
	if not finisher then
		return now + targeting.TargetRestSeconds
	end
	local stun = math.min(math.max(stunApplied, 0), rules.StunMaxSeconds)
	return now + math.max(targeting.TargetRestSeconds, stun + targeting.PostFinisherRestSeconds)
end

-- Every rest a finisher earns (user id -> its end): its target's, landed on them or not, and one for each player
-- it held (`held`: user id -> how long), bystanders in its box included, each after their own hold. A finisher
-- that knocks two players down rests both, or another Forger starts a chain on the second as they rise.
function BotBrain.finisherRests(
	rules: Rules,
	now: number,
	targetUserId: number,
	held: { [number]: number }
): { [number]: number }
	local rests = { [targetUserId] = BotBrain.restAfter(rules, now, true, 0) }
	for userId, seconds in pairs(held) do
		rests[userId] = BotBrain.restAfter(rules, now, true, seconds)
	end
	return rests
end

-- A Forger's rank among those on one player: 1 plus how many others are closer, ties to the lower slot.
function BotBrain.engagedRank(
	selfIndex: number,
	selfDistance: number,
	others: { { Index: number, Distance: number } }
): number
	local rank = 1
	for _, other in ipairs(others) do
		if other.Distance < selfDistance or (other.Distance == selfDistance and other.Index < selfIndex) then
			rank += 1
		end
	end
	return rank
end

-- How to play an attack clip so its impact frame, `impact` seconds into the clip at speed 1, lands at the end
-- of a wind-up `window` seconds long: the speed, held within [minSpeed, maxSpeed], and the delay before the
-- clip starts. A clip with no impact frame plays as it is, at once.
function BotBrain.clipTiming(window: number, impact: number, minSpeed: number, maxSpeed: number): (number, number)
	if impact <= 0 then
		return 1, 0
	end
	local speed = math.clamp(impact / math.max(window, 0), minSpeed, maxSpeed)
	return speed, math.max(window - impact / speed, 0)
end

-- Whether a body at (dx, dy, dz) from the Forger's root is inside the melee box aimed along (aimX, aimZ): from
-- 0 to Range ahead, HalfWidth either side, HalfHeight above or below.
function BotBrain.inMeleeBox(dx: number, dy: number, dz: number, aimX: number, aimZ: number, melee: MeleeDef): boolean
	local forward = dx * aimX + dz * aimZ
	local side = math.abs(-dx * aimZ + dz * aimX)
	return forward >= 0 and forward <= melee.Range and side <= melee.HalfWidth and math.abs(dy) <= melee.HalfHeight
end

-- The distance from (px, pz) to the segment a -> b.
function BotBrain.segmentDistance(ax: number, az: number, bx: number, bz: number, px: number, pz: number): number
	local dx, dz = bx - ax, bz - az
	local lengthSquared = dx * dx + dz * dz
	local t = if lengthSquared > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / lengthSquared, 0, 1) else 0
	return distanceBetween(ax + dx * t, az + dz * t, px, pz)
end

-- The spawn point furthest from its nearest player, ties to the lower index; `preferred` with nobody there.
function BotBrain.pickSpawn(spawns: { Point }, players: { Point }, preferred: number): number
	if #players == 0 then
		return preferred
	end
	local best, bestDistance = preferred, -1
	for index, spawn in ipairs(spawns) do
		local nearest = math.huge
		for _, player in ipairs(players) do
			nearest = math.min(nearest, (player.X - spawn.X) ^ 2 + (player.Z - spawn.Z) ^ 2)
		end
		if nearest > bestDistance then
			best, bestDistance = index, nearest
		end
	end
	return best
end

-- How many Forgers the page holds for `active` members: `base` for one, `perExtra` more for each other one,
-- never fewer than one nor more than `maximum`. None at all while nobody is active: an idle page holds nobody.
function BotBrain.population(active: number, base: number, perExtra: number, maximum: number): number
	if active <= 0 then
		return 0
	end
	return math.clamp(base + perExtra * (active - 1), 1, maximum)
end

-- How long a slot whose Forger fell waits before it is filled again: `baseSeconds` for one active member,
-- `stepSeconds` less for each other one, never under `minSeconds`. A crowded page refills faster.
function BotBrain.respawnSeconds(active: number, baseSeconds: number, stepSeconds: number, minSeconds: number): number
	return math.max(minSeconds, baseSeconds - stepSeconds * math.max(active - 1, 0))
end

-- Whether a kill is paid to this player: not from the camp, not while every Forger ignores them, and not
-- after UnreachableSeconds out of reach of the floor (outOfReach), over it or sunk under it -- the three
-- places a Forger cannot answer from.
function BotBrain.creditable(
	inCamp: boolean,
	ignoredUntil: number,
	offFloorSince: number?,
	now: number,
	rules: Rules
): boolean
	if inCamp or ignoredUntil > now then
		return false
	end
	return offFloorSince == nil or now - offFloorSince < rules.Reach.UnreachableSeconds
end

-- What one player's hit on a Forger counts for. From outside the camp, its points go to their share of the kill
-- (`ledger`). From inside it, nothing: no share, and every point goes back to the Forger (the refund returned)
-- -- a Forger never answers anyone in the camp, so nothing done from there may soften it for a finisher outside.
function BotBrain.creditHit(ledger: { [number]: number }, userId: number, applied: number, fromCamp: boolean): number
	if fromCamp then
		return applied
	end
	ledger[userId] = (ledger[userId] or 0) + applied
	return 0
end

-- Who a kill pays: the killer, and everyone whose damage reached `share` of the Forger's health. Each once,
-- in UserId order.
function BotBrain.creditedUsers(
	killerUserId: number,
	ledger: { [number]: number },
	maxHealth: number,
	share: number
): { number }
	local users = { killerUserId }
	local threshold = share * maxHealth
	for userId, dealt in pairs(ledger) do
		if userId ~= killerUserId and dealt >= threshold then
			table.insert(users, userId)
		end
	end
	table.sort(users)
	return users
end

return BotBrain
