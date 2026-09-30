--!strict
-- CombatService: the ONLY damage path of the game. Owns per-player combat state (ink, guard,
-- dash / melee timers, spawn protection, per-glyph hit memory), the M1 / dash / block handlers and
-- the single gameplay Heartbeat (regen, timers, CombatState replication at STATE_REPLICATION_HZ, and the
-- movement audit, Security/MovementAudit, stepped once per tick).
-- Every hit, from melee, glyphs, bosses or the environment, goes through ApplyDamage so PvP policy,
-- spawn protection, i-frames and guard rules apply everywhere.
-- It also owns the combat statuses of docs/GAME_DESIGN.md §6 (Fanned, Conductive, Gilding): they
-- live as Humanoid attributes named by CombatConfig.Status, carry their own expiry and are read back
-- inside ApplyDamage / knockback, so no status needs a ticker and clients can render them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ChannelHold = require(Shared.Pure.ChannelHold)
local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MovementAudit = require(script.Parent.Parent.Security.MovementAudit)
local MovementGuard = require(Shared.Pure.MovementGuard)
local MovementGuardConfig = require(script.Parent.Parent.Config.MovementGuardConfig)
local OriginGuard = require(Shared.Pure.OriginGuard)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("CombatService")

export type DamageKind = Types.DamageKind
export type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
export type CombatState = { Ink: number, MaxInk: number, InCombat: boolean, Blocking: boolean, Stunned: boolean }
export type Policy = (source: Player?, targetModel: Model) -> boolean
export type Action = "Melee" | "Dash" | "BlockStart" | "BlockEnd"
-- A glyph's hold on a body that is not a player's (controlNpc): a stun, or a slow by a factor.
export type ControlKind = "Stun" | "Slow"

type ProfileData = Types.ProfileData
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type MovementCommand =
	{ Kind: "Dash", Direction: Vector3, Distance: number, Duration: number }
	| { Kind: "Knockback", Velocity: Vector3, Duration: number }
	| { Kind: "Stun", Seconds: number }
type AntiCheatApi = {
	strike: (
		player: Player,
		source: string,
		reason: string,
		kind: ("Schema" | "RateLimit" | "Origin" | "Movement")?
	) -> (),
}
type MovementApi = {
	applySlow: (player: Player, key: string, factor: number, seconds: number) -> (),
	clearSlow: (player: Player, key: string?) -> (),
	applyStun: (player: Player, seconds: number) -> (),
	ragdoll: (player: Player, seconds: number) -> (),
	isStunned: (player: Player) -> boolean,
	isDown: (player: Player) -> boolean,
	command: (player: Player, payload: MovementCommand) -> (),
}
type VfxPacket = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}
type VfxApi = { emit: (packet: VfxPacket, reliable: boolean?) -> () }
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> () }
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> () }
type GlyphApi = { getCooldowns: (player: Player) -> { [string]: number } }
type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	fire: (name: string, player: Player, ...any) -> (),
	lastInbound: (player: Player) -> number,
}
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Movement: MovementApi,
	Vfx: VfxApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	AntiCheat: AntiCheatApi,
	Glyph: GlyphApi?, -- wired after Combat in the bootstrap table: read in Start, never in Init
	Cosmetic: CosmeticApi,
}
type TroveType = typeof(Trove.new())
type CosmeticApi = { skinShade: (player: Player, glyphId: string) -> number }
-- One pigment interaction of docs/GAME_DESIGN.md §6, as CombatConfig.Status declares it: damage of
-- AppliedByPigment writes the mark, damage of AmplifiesPigment is multiplied while it lasts.
type PigmentMark = {
	Attribute: string,
	AppliedByPigment: string,
	AmplifiesPigment: string,
	DurationSeconds: number,
	DamageMultiplier: number,
	NameKey: string,
}

type State = {
	Player: Player,
	Trove: TroveType, -- player lifetime
	CharacterTrove: TroveType?, -- current character
	Character: Model?,
	Humanoid: Humanoid?, -- nil while dead or without character
	Ink: number,
	InCombatUntil: number, -- os.clock timestamps below
	LastDamageTakenAt: number,
	Blocking: boolean,
	BlockStartedAt: number,
	BlockCooldownUntil: number,
	DashCooldownUntil: number,
	IFramesUntil: number,
	-- The hold a charged glyph or a rush keeps on its caster, on os.clock, and whose hold it is (D-142).
	Channel: ChannelHold.Hold,
	MeleeIndex: number,
	MeleeLastHitAt: number,
	MeleeCooldownUntil: number,
	SpawnProtectedUntil: number,
	KillCredited: boolean, -- this character's death was already credited (ApplyDamage or onDied)
	HitMemory: { [string]: { [Model]: number } }, -- tag -> target model -> i-frame expiry
	-- Last root position the server was willing to believe, and when. Characters are simulated by the
	-- owning client, so the replicated CFrame is whatever that client last sent: every hitbox and every
	-- cast origin is measured against this instead of trusting it outright (see trustedCFrame).
	TrustedPosition: Vector3?,
	TrustedAt: number,
	-- os.clock of each implausible origin on an ACTION, pruned to GameConfig.Latency
	-- .ViolationWindowSeconds. A list rather than a counter: a client that returns to a legal position
	-- between two swings would reset a counter every time and never be struck.
	OriginViolations: { number },
	-- Studs the travel budget still allows because the SERVER moved this character (dash, knockback, a
	-- glyph dash), until TravelAllowanceUntil. Consumed as it is spent, never re-granted per sample:
	-- without it every legitimate dash looked like a teleport, and re-granting it turned the ceiling into
	-- a multiple of itself.
	TravelAllowanceStuds: number,
	TravelAllowanceUntil: number,
	-- The round-trip tolerance has been used by an action since the anchor last caught up (OriginGuard
	-- .follow). Only an action sets it; an Accepted sample clears it.
	ToleranceSpent: boolean,
	-- The anchor fell behind across a stall (a non-Accepted verdict after MovementGuardConfig.StallSeconds
	-- of silence) and is chasing until this os.clock: as long as closing that gap on a body walking away
	-- could take (OriginGuard.convergeSeconds). A refused action counts no violation meanwhile: the gap is the
	-- connection's, and the action is already resolved from the anchor. Cleared by an Accepted sample.
	ConvergingUntil: number,
	-- The body the last server teleport (resyncPosition with a position) moved. With deferred signals a new body's
	-- CharacterAdded can run after the teleport that placed it, and must not put the anchors back on the spawn.
	TeleportCharacter: Model?,
	-- When the server last pivoted this body (a teleport, or the movement audit pulling it back): until the pivot
	-- has settled, the client may still replicate where it stood before, and the anchor is held (settling).
	TeleportAt: number,
}

local TICK_SECONDS = 1 / GameConfig.Server.TickRate
-- CombatState snapshots per second (unreliable remote; the HUD tweens between them).
local STATE_REPLICATION_HZ = GameConfig.Server.CombatStateHz
local TICKS_PER_REPLICATION = math.max(1, math.floor(GameConfig.Server.TickRate / STATE_REPLICATION_HZ))
-- Hub safe zone: the dummy ring plus a margin. Players inside cannot be damaged by other players.
local SAFE_ZONE_MARGIN_STUDS = GameConfig.Spawn.SafeZoneMarginStuds
local SAFE_ZONE_RADIUS_STUDS = GameConfig.Enemy.DummyRingRadius + SAFE_ZONE_MARGIN_STUDS
-- Vertical extent of the M1 hitbox (covers crouching / jumping targets in front of the attacker).
local MELEE_HITBOX_HEIGHT = CombatConfig.Melee.HitboxHeight
-- Read by EnemyService on death to credit the killer.
local LAST_ATTACKER_ATTRIBUTE = "LastAttackerUserId"
local ROOT_PART_NAME = "HumanoidRootPart"
local HUMANOID_WAIT_SECONDS = 10
-- The MicroProfiler label the movement audit's share of the tick is read under.
local AUDIT_PROFILE_LABEL = "MovementAudit"
local BLOCK_ATTRIBUTE = CombatConfig.Status.BlockAttribute
-- Slow source key of the guard, so releasing the guard never cleanses a glyph slow.
local BLOCK_SLOW_KEY = "Block"

local brokenBy = (CombatConfig.Block.BrokenBy :: any) :: { [string]: boolean }

local STONE_SKIN = CombatConfig.Status.Gilding
-- Pigment marks indexed by the pigment that writes them and by the pigment they amplify, so
-- ApplyDamage stays two table lookups instead of a chain of pigment tests.
local PIGMENT_MARKS: { PigmentMark } = { CombatConfig.Status.Fanned, CombatConfig.Status.Conductive }
local MARK_BY_SOURCE_PIGMENT: { [string]: PigmentMark } = {}
local MARK_BY_AMPLIFIED_PIGMENT: { [string]: PigmentMark } = {}
-- Every status attribute this service owns, wiped when a character is bound so nothing survives a
-- respawn (the guard attribute is not here: releaseBlock owns it).
local STATUS_ATTRIBUTES: { string } = { STONE_SKIN.Attribute }
for _, mark in ipairs(PIGMENT_MARKS) do
	MARK_BY_SOURCE_PIGMENT[mark.AppliedByPigment] = mark
	MARK_BY_AMPLIFIED_PIGMENT[mark.AmplifiesPigment] = mark
	table.insert(STATUS_ATTRIBUTES, mark.Attribute)
end

local CombatService = {}

CombatService.Killed = Signal.new() -- (sourceUserId: number, victimModel: Model)
-- Fired once per damage application that actually removed health, after every guard, i-frame and
-- policy check, carrying who dealt it and to what. QuestService turns it into the DamageDealt and
-- MeleeHit quest events and WorldBossService attributes boss contribution from it; nothing else may
-- count damage, so a single application can never be credited twice.
--
-- Consumers must attribute from this payload and not by reading an attribute back from a Humanoid
-- event: several players hit the boss in one resumption cycle, so a shared "last attacker" slot
-- credits them all to whoever wrote it last.
CombatService.Damaged = Signal.new() -- (sourceUserId: number, targetModel: Model, applied: number, kind: DamageKind)
-- Fired once per dash the server actually granted (ink spent, cooldown armed). `cancelled` is true when
-- the dash cut a finisher's recovery short (CombatConfig.Dash.CancelCost).
CombatService.Dashed = Signal.new() -- (player: Player, cancelled: boolean)
-- A knockback approved for a body no player owns (knockback). A player's character is moved by its own
-- client through a MovementCommand; nothing moves a server-owned body unless its owner listens here --
-- the Battleground's Forgers do (D-131). Anchored bodies (the training proofs, the Erasure) have no
-- listener and stay where they are.
CombatService.Shoved = Signal.new() -- (targetModel: Model, velocity: Vector3, duration: number)
-- A glyph's stun or slow on a body no player owns (controlNpc): players are held through MovementService,
-- which only knows players, so the owner of any other body listens here. Its last argument is the glyph's
-- id: two glyphs' slows stay apart, as MovementService keeps a player's.
-- (targetModel: Model, kind: ControlKind, seconds: number, factor: number, key: string)
CombatService.Controlled = Signal.new()

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local movement: MovementApi
local antiCheat: AntiCheatApi
local vfx: VfxApi
local progression: ProgressionApi
local currency: CurrencyApi
local cosmetic: CosmeticApi
local glyph: GlyphApi? = nil
local deps: Deps

local states: { [Player]: State } = {}
local policy: Policy
local accumulator = 0
local ticksSinceReplication = 0
-- os.clock of the previous tick, so regeneration integrates over the time that really passed. 0 until
-- the first tick, which then regenerates nothing.
local lastTickAt = 0
local cachedSpawn: SpawnLocation? = nil

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function isFiniteNonNegative(value: number): boolean
	return value == value and value ~= math.huge and value >= 0
end

local function stateOf(player: Player?): State?
	if player == nil then
		return nil
	end
	return states[player]
end

local function rootOf(model: Model): BasePart?
	local root: Instance? = model:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- World position of a target for hit VFX: root part when present, model pivot otherwise.
local function positionOf(model: Model): Vector3
	local root = rootOf(model)
	if root ~= nil then
		return root.Position
	end
	return model:GetPivot().Position
end

-- Closest ancestor Model that owns a Humanoid (accessories and tools nest parts under it).
local function modelOf(part: BasePart): Model?
	local ancestor: Instance? = part.Parent
	while ancestor ~= nil do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") ~= nil then
			return ancestor :: Model
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function findHumanoid(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		return humanoid
	end
	local waited: Instance? = character:WaitForChild("Humanoid", HUMANOID_WAIT_SECONDS)
	if waited ~= nil and waited:IsA("Humanoid") then
		return waited
	end
	return nil
end

-- The hub SpawnLocation (centre of the safe zone), re-resolved when the cached one leaves the world.
local function findSpawn(): SpawnLocation?
	local cached = cachedSpawn
	if cached ~= nil and cached:IsDescendantOf(Workspace) then
		return cached
	end
	local found: Instance? = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if found ~= nil and found:IsA("SpawnLocation") then
		cachedSpawn = found
		return found
	end
	cachedSpawn = nil
	return nil
end

local function isSpawnProtected(state: State?, character: Model?, now: number): boolean
	if state ~= nil and now < state.SpawnProtectedUntil then
		return true
	end
	if character ~= nil and character:FindFirstChildOfClass("ForceField") ~= nil then
		return true
	end
	return false
end

local function breaksGuard(kind: string, tags: { string }): boolean
	if brokenBy[kind] == true then
		return true
	end
	for _, tag in ipairs(tags) do
		if brokenBy[tag] == true then
			return true
		end
	end
	return false
end

-- A status attribute holds the os.clock timestamp at which it stops applying. Statuses have no
-- ticker: they are checked lazily here and an expired one is cleared on read, so a client never sees
-- a stale mark and a refresh only pushes the timestamp (never stacks).
local function isStatusActive(humanoid: Humanoid, attribute: string, now: number): boolean
	local value = humanoid:GetAttribute(attribute)
	if value == nil then
		return false
	end
	if typeof(value) == "number" and now < (value :: number) then
		return true
	end
	humanoid:SetAttribute(attribute, nil)
	return false
end

local function setStatus(humanoid: Humanoid, attribute: string, durationSeconds: number, now: number)
	humanoid:SetAttribute(attribute, now + durationSeconds)
end

local function clearStatuses(humanoid: Humanoid)
	for _, attribute in ipairs(STATUS_ATTRIBUTES) do
		humanoid:SetAttribute(attribute, nil)
	end
end

local function markInCombat(state: State, now: number)
	state.InCombatUntil = now + CombatConfig.Ink.InCombatSeconds
end

-- Drops expired i-frame entries so the memory never grows past the targets hit in the last window.
local function pruneHitMemory(memory: { [Model]: number }, now: number)
	for model, expiry in pairs(memory) do
		if expiry <= now then
			memory[model] = nil
		end
	end
end

local LATENCY = GameConfig.Latency
-- Pure/OriginGuard owns the arithmetic and is unit-tested; this is the shipped configuration it judges
-- against. The epsilon is here rather than in GameConfig because it is a property of Roblox character
-- jitter, not a balance value: a resting character still moves by a fraction of a stud.
local GUARD: OriginGuard.Config = {
	MaxSpeedStudsPerSecond = LATENCY.MaxSpeedStudsPerSecond,
	OriginToleranceStuds = LATENCY.OriginToleranceStuds,
	MaxBudgetSeconds = LATENCY.MaxBudgetSeconds,
	StillEpsilonStuds = 0.05,
}

-- Pure/MovementGuard's configuration, handed to MovementAudit: MovementGuardConfig, which only the server reads,
-- plus what it does not hold -- the engine's gravity, the jump velocities, the speed ceiling and its window, the
-- stillness epsilon above and the tick. tests/MovementGates.spec.luau checks that nothing the judge reads is left
-- out.
local function auditConfig(): MovementGuard.Config
	local config = table.clone(MovementGuardConfig) :: any
	config.Gravity = Workspace.Gravity
	config.JumpVelocity = GameConfig.Movement.JumpPower
	config.DoubleJumpVelocity = GameConfig.Movement.DoubleJumpVelocity
	config.MaxSpeedStudsPerSecond = LATENCY.MaxSpeedStudsPerSecond
	config.MaxBudgetSeconds = LATENCY.MaxBudgetSeconds
	config.StillEpsilonStuds = GUARD.StillEpsilonStuds
	config.TickSeconds = TICK_SECONDS
	return config :: MovementGuard.Config
end

local AUDIT = auditConfig()

-- The CFrame a hitbox or a cast origin is built from.
--
-- Roblox simulates a player's character on the owning client, so `root.CFrame` is whatever that client
-- last replicated: read straight, it let a tampered client set its root to the opponent's position, fire
-- a melee, and teleport back, landing a full combo from anywhere in the arena with no travel and no
-- counterplay. The same trick placed a cast origin wherever the client liked.
--
-- So the position is measured, not trusted: it is accepted when the character could plausibly have
-- travelled there from the last accepted position at GameConfig.Latency.MaxSpeedStudsPerSecond, plus
-- OriginToleranceStuds of slack for the round trip. An implausible one is not rejected outright, which
-- would punish a bad connection: the action still happens, anchored at the last position the server did
-- believe, so a teleported attacker swings at empty air. Only a sustained stream of them strikes.
--
-- An implausible sample does not freeze the anchor: it chases the observation at the speed ceiling, so a
-- body that fell behind catches up and nobody stays stuck. Server-authored teleports go through
-- resyncPosition instead.
-- Grants `studs` of extra travel for `seconds`, because the server itself set this character moving.
-- Called by every server-authored displacement the client applies (dash, knockback, a glyph dash): the
-- character is simulated by the owning client, so the move arrives as one jump in the replicated
-- position. Overlapping grants add up, capped at MovementGuardConfig.MaxAllowanceStuds, and share the later
-- deadline, which the round trip `rtt` stretches by MovementGuard.grace: the client plays the move that much
-- later. No mover overshoot here: it would lend every action after a dash a few free studs.
local function allowTravel(state: State, studs: number, seconds: number, now: number, rtt: number)
	local deadline = now + seconds + MovementGuard.grace(rtt, AUDIT)
	if now >= state.TravelAllowanceUntil then
		state.TravelAllowanceStuds = 0
	end
	state.TravelAllowanceStuds = math.min(state.TravelAllowanceStuds + math.max(0, studs), AUDIT.MaxAllowanceStuds)
	state.TravelAllowanceUntil = math.max(state.TravelAllowanceUntil, deadline)
end

-- Studs of server-granted travel still unspent, 0 once the window has closed.
local function liveAllowance(state: State, now: number): number
	return if now < state.TravelAllowanceUntil then state.TravelAllowanceStuds else 0
end

-- Records an implausible ACTION origin and strikes once the window holds enough of them.
local function countViolation(state: State, now: number, travelled: number, budget: number)
	local times = state.OriginViolations
	local cutoff = now - LATENCY.ViolationWindowSeconds
	while #times > 0 and times[1] < cutoff do
		table.remove(times, 1)
	end
	table.insert(times, now)
	if #times < LATENCY.ViolationsBeforeStrike then
		return
	end
	table.clear(times)
	antiCheat.strike(
		state.Player,
		"Origin",
		string.format("%.0f horizontal studs against a budget of %.0f", travelled, budget),
		"Origin"
	)
end

-- The same place, turned to face the way the body faces, upright (OriginGuard.facing).
local function upright(frame: CFrame): CFrame
	local look, up = frame.LookVector, frame.UpVector
	local x, z = OriginGuard.facing(look.X, look.Y, look.Z, up.X, up.Z)
	return CFrame.lookAlong(frame.Position, Vector3.new(x, 0, z))
end

-- Every coordinate a number and within MovementGuardConfig.MaxCoordinateStuds: NaN fails every comparison,
-- so it is caught by the same test as a coordinate flung out of the world.
local function isSanePosition(position: Vector3): boolean
	local limit = MovementGuardConfig.MaxCoordinateStuds
	return math.abs(position.X) <= limit and math.abs(position.Y) <= limit and math.abs(position.Z) <= limit
end

-- Whether the server pivoted this body so recently that what the client replicates may still be where it stood
-- before the pivot reached it: MovementGuard.settle of the round trip the audit reads, which the audit waits out
-- too. The first test only spares reading the round trip on every tick.
local function settling(state: State, now: number): boolean
	local since = now - state.TeleportAt
	return since < AUDIT.SettleMaxSeconds and since < MovementGuard.settle(MovementAudit.rtt(state.Player), AUDIT)
end

-- `strikeOnFailure` is true only for an action the player chose (a melee, a cast). The per-tick sampling
-- passes false: it moves the anchor, and must neither strike, nor absolve, nor spend the tolerance.
--
-- The verdicts (OriginGuard.follow):
--  * within the speed ceiling plus any unspent server-granted allowance -> honest movement: the anchor
--    follows, and the allowance is reduced by the part of the travel that needed it;
--  * beyond that but within OriginToleranceStuds, on the first action since the anchor last caught up ->
--    the action is resolved where the client says it is, to absorb the round trip, once;
--  * beyond that -> the action is resolved from the anchor, and only a Refused one (past the tolerance)
--    counts as a violation, unless the anchor is converging after a stall.
-- In every case but the first, the anchor advances toward the observation by what the ceiling allows, so a
-- body that fell behind is caught up with rather than refused forever, and a held spoof is believed only
-- after it has cost the time it would have taken to walk there.
--
-- Except while a server pivot settles: the observation that does not fit is where the body stood before the
-- pivot, which the stream still carries. Chased, it pulled the anchor two studs a tick back toward the hub
-- after a portal -- out of the Battleground's bounds at 0.4 s of round trip -- and a Caret's landing ten studs
-- behind the first swing. It is held instead, whole: no advance, no allowance or tolerance spent, not even
-- the height, and an action is resolved from the destination without counting a violation. Its clock restarts,
-- or the budget grown through the wait would accept a short teleport's stale sample late (a Caret's after
-- 0.45 s).
--
-- Only HORIZONTAL travel is measured. Vertical speed is gravity-driven and unbounded, so a fall would
-- fail every check, while the exploit being bounded is repositioning onto a target. The anchor's height
-- follows every observation it judges, so a clamped origin still sits at the player's real altitude; a held
-- one is the height the body had before the pivot, and is left out.
--
-- A position that is not a number, or is beyond MovementGuardConfig.MaxCoordinateStuds, is never stored:
-- the action is resolved from the anchor, and a later honest sample is still judged against it.
--
-- Upright, always: every swing and every glyph is aimed with this frame, and a root tilted by a fall
-- aimed them into the ground or the sky (D-113).
local function trustedCFrame(state: State, root: BasePart, now: number, strikeOnFailure: boolean): CFrame
	local observed = upright(root.CFrame)
	local position = observed.Position
	local trusted = state.TrustedPosition
	if not isSanePosition(position) then
		return if trusted ~= nil then CFrame.new(trusted) else observed
	end
	if trusted == nil then
		state.TrustedPosition = position
		state.TrustedAt = now
		return observed
	end
	local elapsed = now - state.TrustedAt
	local allowance = liveAllowance(state, now)
	local delta = position - trusted
	local flatDelta = Vector3.new(delta.X, 0, delta.Z)
	local travelled = flatDelta.Magnitude
	local verdict, allowanceLeft, advance, toleranceSpent =
		OriginGuard.follow(travelled, elapsed, allowance, strikeOnFailure, state.ToleranceSpent, GUARD)
	if verdict ~= "Still" and verdict ~= "Accepted" and settling(state, now) then
		state.TrustedAt = now
		return CFrame.new(trusted) * (observed - position)
	end
	state.TravelAllowanceStuds = allowanceLeft
	state.ToleranceSpent = toleranceSpent
	if verdict == "Accepted" then
		state.ConvergingUntil = -math.huge
		state.TrustedPosition = position
		state.TrustedAt = now
		return observed
	end
	if verdict == "Still" then
		-- Nothing moved: the clock is left alone so the budget keeps growing through a stall. The altitude
		-- still follows, so a falling player is not measured against where they jumped from.
		state.TrustedPosition = Vector3.new(trusted.X, position.Y, trusted.Z)
		return observed
	end
	if elapsed >= MovementGuardConfig.StallSeconds then
		-- Converging for as long as the chase could need to close what is left on a body that keeps walking away
		-- at the pace the audit forgives a stall at, and no longer.
		state.ConvergingUntil = now
			+ OriginGuard.convergeSeconds(
				travelled - advance,
				MovementGuardConfig.StallSpeedStudsPerSecond,
				MovementGuardConfig.StallCapSeconds,
				GUARD
			)
	end
	-- Chase: `advance` never reaches the observation here (it would have been Accepted), so the flat delta
	-- is long enough to have a direction.
	local chased = trusted + flatDelta.Unit * advance
	local anchor = Vector3.new(chased.X, position.Y, chased.Z)
	state.TrustedPosition = anchor
	state.TrustedAt = now
	if verdict == "Tolerated" then
		return observed
	end
	if verdict == "Refused" and strikeOnFailure and now >= state.ConvergingUntil then
		countViolation(state, now, travelled, OriginGuard.budget(elapsed, allowance, GUARD))
	end
	-- Rotation is the player's aim and costs nothing to honour; only the position is corrected. The local
	-- anchor is used rather than state.TrustedPosition, which the field's own type says may be nil: it is
	-- not, a few lines above, but relying on that is how a later edit turns a type error into a crash.
	return CFrame.new(anchor) * (observed - position)
end

-- The live root of `player`, resolved through Players rather than the state's cached Character: with
-- deferred signals the cached one can lag a respawn by a resumption cycle, and a caller that then read
-- "no state" would fall back to the unvalidated client position.
local function playerRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

-- Where the engine puts a new body: the root of `character` standing on the hub's SpawnLocation, at its own
-- standing height (MovementAudit.standingHeight), a default body's for a player who has none yet. nil with no
-- SpawnLocation.
local function spawnPoint(character: Model?): Vector3?
	local spawn = findSpawn()
	if spawn == nil then
		return nil
	end
	local stand = if character ~= nil
		then MovementAudit.standingHeight(character)
		else MovementGuardConfig.DefaultStandHeightStuds
	return spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + stand, 0)
end

-- Puts OriginGuard's anchor on `position` with a clean slate: no allowance, the tolerance whole, nothing
-- converging, no pivot settling, and the origin violations cleared if `clearViolations`. nil leaves no anchor,
-- and the next sample is taken as it comes. A server pivot starts its settle after this.
local function anchorOn(state: State, position: Vector3?, now: number, clearViolations: boolean)
	state.TrustedPosition = position
	state.TrustedAt = now
	state.TravelAllowanceStuds = 0
	state.TravelAllowanceUntil = 0
	state.ToleranceSpent = false
	state.ConvergingUntil = -math.huge
	state.TeleportAt = -math.huge
	if clearViolations then
		table.clear(state.OriginViolations)
	end
end

-- Re-anchors the trust sample on a position the SERVER chose. Every server-authored reposition (match
-- spawn, hub return, boss arena placement, a portal's trip, the Battleground's camp, a teleporting glyph)
-- must call this right after its PivotTo, or the player's next hitbox would be built where they used to
-- stand and miss, and the movement audit would read the move as a teleport.
--
-- A teleport MUST pass `position`. Re-reading the character would anchor trust on whatever the client
-- last replicated, which is the one value this path exists not to believe: a glyph that moves the caster
-- relative to a spoofed root would otherwise have the server bless the spoof. With a position both guards
-- move there: OriginGuard's anchor, held there while the pivot settles, and MovementAudit, which then waits
-- for the body to arrive. Called with nil (no caller does today), only OriginGuard re-arms on the current
-- root: the audit never adopts a position the client chose.
function CombatService.resyncPosition(player: Player, position: Vector3?)
	local state = states[player]
	if state == nil then
		return
	end
	local now = os.clock()
	if position == nil then
		local root = playerRoot(player)
		anchorOn(state, if root ~= nil then root.Position else nil, now, true)
		return
	end
	anchorOn(state, position, now, true)
	state.TeleportAt = now
	state.TeleportCharacter = player.Character
	MovementAudit.teleported(player, position)
end

-- The movement audit pulled `player`'s body back to `position`: OriginGuard starts there too, and holds there
-- while the pivot settles. The origin violations stay: a correction absolves nothing.
local function reanchor(player: Player, position: Vector3)
	local state = states[player]
	if state ~= nil then
		local now = os.clock()
		anchorOn(state, position, now, false)
		state.TeleportAt = now
	end
end

-- Issues a server-authored movement command AND grants the travel it covers. The single door for every
-- displacement the client applies, so no caller can set a character moving without the travel budget
-- being told: a glyph dash that forgot to would make an honest player's follow-up melee whiff.
--
-- A knockback's vertical share is lift, never horizontal travel: OriginGuard is given only the flat distance, and
-- the movement audit the two apart, each stretched by the round trip the audit reads.
function CombatService.grantMovement(player: Player, command: MovementCommand)
	local state = states[player]
	if state ~= nil then
		local now = os.clock()
		local rtt = MovementAudit.rtt(player)
		if command.Kind == "Dash" then
			allowTravel(state, command.Distance, command.Duration, now, rtt)
			MovementAudit.grant(player, command.Distance, 0, command.Duration)
		elseif command.Kind == "Knockback" then
			local velocity = command.Velocity
			local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude * command.Duration
			local lift = math.max(0, velocity.Y) * command.Duration
			allowTravel(state, flat, command.Duration, now, rtt)
			MovementAudit.grant(player, flat, lift, command.Duration)
		end
	end
	movement.command(player, command)
end

-- The origin an attack is built from, validated. nil when the caster has no live character: a caller must
-- then refuse the action, never fall back to the client's own value.
function CombatService.trustedOrigin(player: Player): CFrame?
	local state = states[player]
	local root = playerRoot(player)
	if state == nil or root == nil then
		return nil
	end
	return trustedCFrame(state, root, os.clock(), true)
end

-- The same origin, for a loop the SERVER runs on its own clock: a charge's release, the Scorch's ticks, the pull of a
-- Stitch, the strokes of the Hatching. Judged and chased exactly as trustedOrigin judges it, so the zone and the
-- strokes follow the same anchor, but as the per-tick sampling is: no violation counted, no tolerance spent. The
-- player chose the cast, which trustedOrigin judged; they did not choose when the server's loop asks again, and
-- three ticks after a network freeze were three violations -- a strike -- that no action of theirs had made. nil
-- when the caster has no live character: the loop then stops, never falls back to the client's word.
function CombatService.currentOrigin(player: Player): CFrame?
	local state = states[player]
	local root = playerRoot(player)
	if state == nil or root == nil then
		return nil
	end
	return trustedCFrame(state, root, os.clock(), false)
end

-- Where the server last believed `player` stood: the anchor the per-tick sampling keeps, read as it is. Never
-- judged here and never counted as an action, so reading it can neither move the anchor nor strike anyone --
-- which is what a watcher that asks every tick needs (the Battleground's roster, and anything else that must
-- know where a player is without taking the client's word for it). Right after a respawn it is the SpawnLocation
-- the engine put the new body on; nil only when there is none, until the next tick samples the new body.
function CombatService.trustedPosition(player: Player): Vector3?
	local state = states[player]
	if state == nil then
		return nil
	end
	return state.TrustedPosition
end

-- Heals a live player by `amount`, but only once they have taken no damage for `quietSeconds`, and never past
-- their MaxHealth. Returns what was healed. A place that heals (the Battleground's camp) goes through this so
-- it can never heal somebody in the middle of taking hits, and never a dead body.
function CombatService.heal(player: Player, amount: number, quietSeconds: number): number
	if not isFiniteNonNegative(amount) or not isFiniteNonNegative(quietSeconds) then
		log.warn("heal rejected for %s: amount %s, quiet %s", player.Name, tostring(amount), tostring(quietSeconds))
		return 0
	end
	local state = states[player]
	if state == nil then
		return 0
	end
	local humanoid = state.Humanoid
	if humanoid == nil or humanoid.Parent ~= state.Character or humanoid.Health <= 0 then
		return 0
	end
	if os.clock() - state.LastDamageTakenAt < quietSeconds then
		return 0
	end
	local healed = math.min(amount, humanoid.MaxHealth - humanoid.Health)
	if healed <= 0 then
		return 0
	end
	humanoid.Health += healed
	return healed
end

-- A glyph's stun (factor 0) or slow (0 <= factor <= 1) on a body that is not a player's, for `seconds`, under
-- the source `key` (the glyph's id, as MovementService.applySlow takes it): fires Controlled for whoever owns
-- that body. A player's character is refused, because players are held through MovementService, and a second
-- path would let the two disagree about how long somebody is held.
function CombatService.controlNpc(targetModel: Model, kind: ControlKind, seconds: number, factor: number, key: string)
	if Players:GetPlayerFromCharacter(targetModel) ~= nil then
		log.warn("controlNpc rejected: %s is a player's character", targetModel.Name)
		return
	end
	if seconds ~= seconds or seconds <= 0 or seconds == math.huge or not (factor >= 0 and factor <= 1) then
		log.warn("controlNpc rejected (%s): seconds %s, factor %s", kind, tostring(seconds), tostring(factor))
		return
	end
	if type(key) ~= "string" or key == "" then
		log.warn("controlNpc rejected (%s): invalid key %s", kind, tostring(key))
		return
	end
	CombatService.Controlled:Fire(targetModel, kind, seconds, factor, key)
end

-- Guard drop (manual release, auto-release, guard break, death): starts the block cooldown.
local function releaseBlock(state: State, now: number)
	state.Blocking = false
	movement.clearSlow(state.Player, BLOCK_SLOW_KEY)
	state.BlockCooldownUntil = now + CombatConfig.Block.CooldownSeconds
	local humanoid = state.Humanoid
	if humanoid ~= nil then
		humanoid:SetAttribute(BLOCK_ATTRIBUTE, nil)
	end
end

local function isInSafeZone(spawn: SpawnLocation, model: Model): boolean
	return (model:GetPivot().Position - spawn.Position).Magnitude <= SAFE_ZONE_RADIUS_STUDS
end

-- Default PvP policy: NPCs are always valid targets; players only outside spawn protection and the
-- hub safe zone. The safe zone is symmetric: standing inside it protects from PvP damage AND
-- forbids dealing it, so the zone can never be used as a one-way firing position. A source without
-- a character (NPC, environment) is not zone-tested. Match / boss modes replace it through setPolicy.
local function defaultPolicy(source: Player?, targetModel: Model): boolean
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	if targetPlayer == nil then
		return true
	end
	local now = os.clock()
	if isSpawnProtected(states[targetPlayer], targetModel, now) then
		return false
	end
	local sourceCharacter: Model? = if source ~= nil then source.Character else nil
	if source ~= nil and isSpawnProtected(states[source], sourceCharacter, now) then
		return false
	end
	local spawn = findSpawn()
	if spawn == nil then
		return true
	end
	if isInSafeZone(spawn, targetModel) then
		return false
	end
	return sourceCharacter == nil or not isInSafeZone(spawn, sourceCharacter)
end

policy = defaultPolicy

----------------------------------------------------------------
-- Character lifecycle
----------------------------------------------------------------

-- Defined in the damage section below; the Died handler reaches the same crediting path for deaths
-- that never went through ApplyDamage.
local onKill: (source: Player?, targetPlayer: Player?, targetModel: Model) -> ()

local function releaseCharacter(state: State, now: number)
	if state.Blocking then
		releaseBlock(state, now)
	end
	local characterTrove = state.CharacterTrove
	state.CharacterTrove = nil
	if characterTrove ~= nil then
		characterTrove:Destroy()
	end
	state.Humanoid = nil
	state.Character = nil
end

-- A fresh slate for a new body (`character`), or for a player who has none yet. The anchors start where the
-- engine spawns bodies, the SpawnLocation, rather than on the new body's first report -- unless a server teleport
-- of this very body already ran (deferred signals can deliver CharacterAdded after it): it set them on the point
-- the server chose.
local function resetState(state: State, now: number, character: Model?)
	state.Ink = CombatConfig.Ink.Max * CombatConfig.Ink.StartFraction
	state.InCombatUntil = 0
	state.LastDamageTakenAt = 0
	state.Blocking = false
	state.BlockStartedAt = 0
	state.BlockCooldownUntil = 0
	state.DashCooldownUntil = 0
	state.IFramesUntil = 0
	ChannelHold.breaks(state.Channel)
	state.MeleeIndex = 0
	state.MeleeLastHitAt = 0
	state.MeleeCooldownUntil = 0
	state.SpawnProtectedUntil = now + GameConfig.Spawn.ProtectionSeconds
	state.KillCredited = false
	state.HitMemory = {}
	if character ~= nil and state.TeleportCharacter == character then
		return
	end
	anchorOn(state, spawnPoint(character), now, true)
	if character ~= nil then
		MovementAudit.spawned(state.Player, character)
	end
end

-- Credits a death that did not come from ApplyDamage (Reset Character, fall, environment) to the
-- last attacker while the fight is still fresh, so leaving the fight is never a free escape. The
-- attribute is cleared afterwards so a later unrelated death cannot re-credit the same attacker.
--
-- "Fresh" holds for both branches. It used to gate only the death with no recorded attacker, so an
-- attacker recorded at the end of a match was credited whenever the survivor next died: the winner of a
-- duel, teleported back to the hub on the same character, pressed Reset minutes later and handed the
-- loser a kill, its XP and Folios -- and, once kill effects were drawn, the loser's finisher at the
-- winner's feet in the hub (D-109, found by review).
local function creditDeath(state: State, character: Model, now: number)
	local attribute = character:GetAttribute(LAST_ATTACKER_ATTRIBUTE)
	local attackerId: number? = if typeof(attribute) == "number" then attribute :: number else nil
	local inCombat = state.LastDamageTakenAt > 0 and now - state.LastDamageTakenAt < CombatConfig.Ink.InCombatSeconds
	if not inCombat then
		character:SetAttribute(LAST_ATTACKER_ATTRIBUTE, nil)
		return
	end
	local attacker: Player? = nil
	if attackerId ~= nil then
		attacker = Players:GetPlayerByUserId(attackerId)
	end
	character:SetAttribute(LAST_ATTACKER_ATTRIBUTE, nil)
	state.KillCredited = true
	onKill(attacker, state.Player, character)
end

local function onDied(state: State)
	local now = os.clock()
	if state.Blocking then
		releaseBlock(state, now)
	end
	state.Humanoid = nil
	local character = state.Character
	if character ~= nil and not state.KillCredited then
		creditDeath(state, character, now)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if state == nil then
		return
	end
	local now = os.clock()
	releaseCharacter(state, now)
	resetState(state, now, character)
	local characterTrove = Trove.new()
	state.CharacterTrove = characterTrove
	state.Character = character

	local humanoid = findHumanoid(character)
	if humanoid == nil then
		log.warn("no Humanoid found for %s", player.Name)
		return
	end
	-- findHumanoid may have yielded: only bind if this is still the live character.
	if states[player] ~= state or state.CharacterTrove ~= characterTrove then
		return
	end
	humanoid.MaxHealth = CombatConfig.Health.Max
	humanoid.Health = CombatConfig.Health.Max
	-- Completes the resetState above: the statuses live on the Humanoid, which only exists here (a
	-- respawned character brings a fresh one, a re-bound character must not keep its old marks).
	clearStatuses(humanoid)
	state.Humanoid = humanoid
	characterTrove:Connect(humanoid.Died, function()
		onDied(state)
	end)
	-- A client can delete or reparent the Humanoid inside its own character and the deletion
	-- replicates. Without this, the cached reference would keep authorising melee / dash / block
	-- while every incoming ApplyDamage and area query skips a model that has no Humanoid. Dropping
	-- the reference makes liveCharacter reject every action until the next respawn.
	local function onHumanoidDetached()
		if states[player] ~= state or state.CharacterTrove ~= characterTrove then
			return
		end
		if humanoid.Parent == character then
			return
		end
		local detachedAt = os.clock()
		if state.Blocking then
			releaseBlock(state, detachedAt)
		end
		state.Humanoid = nil
		log.warn("Humanoid left the character of %s: combat actions rejected until respawn", player.Name)
	end
	characterTrove:Connect(humanoid.AncestryChanged, onHumanoidDetached)
	characterTrove:Connect(humanoid.Destroying, onHumanoidDetached)
end

local function onPlayerAdded(player: Player)
	if states[player] ~= nil then
		return
	end
	local trove = Trove.new()
	local state: State = {
		Player = player,
		Trove = trove,
		CharacterTrove = nil,
		Character = nil,
		Humanoid = nil,
		Ink = 0,
		InCombatUntil = 0,
		LastDamageTakenAt = 0,
		Blocking = false,
		BlockStartedAt = 0,
		BlockCooldownUntil = 0,
		DashCooldownUntil = 0,
		IFramesUntil = 0,
		Channel = ChannelHold.new(),
		MeleeIndex = 0,
		MeleeLastHitAt = 0,
		MeleeCooldownUntil = 0,
		SpawnProtectedUntil = 0,
		KillCredited = false,
		HitMemory = {},
		TrustedPosition = nil,
		TrustedAt = 0,
		OriginViolations = {},
		TravelAllowanceStuds = 0,
		TravelAllowanceUntil = 0,
		ToleranceSpent = false,
		ConvergingUntil = -math.huge,
		TeleportCharacter = nil,
		TeleportAt = -math.huge,
	}
	resetState(state, os.clock())
	states[player] = state
	MovementAudit.add(player)
	trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, character)
	end)
	trove:Connect(player.CharacterRemoving, function()
		releaseCharacter(state, os.clock())
	end)
	local character = player.Character
	if character ~= nil then
		onCharacterAdded(player, character)
	end
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	states[player] = nil
	MovementAudit.remove(player)
	releaseCharacter(state, os.clock())
	state.Trove:Destroy()
end

----------------------------------------------------------------
-- Damage
----------------------------------------------------------------

function onKill(source: Player?, targetPlayer: Player?, targetModel: Model)
	if targetPlayer ~= nil then
		local victimData = dataService.get(targetPlayer)
		if victimData ~= nil then
			victimData.Stats.Deaths += 1
			dataService.push(targetPlayer, "Stats")
		end
		if source ~= nil then
			local xp = ProgressionConfig.XP.PlayerKill
			progression.addXp(source, xp, "PlayerKill")
			currency.add(source, ProgressionConfig.Folios.PlayerKill, "PlayerKill")
			local sourceData = dataService.get(source)
			if sourceData ~= nil then
				sourceData.Stats.Kills += 1
				dataService.push(source, "Stats")
			end
			notify.send(source, "hud.playerKill", { name = targetPlayer.DisplayName, xp = xp }, "Success", "Kill")
		end
	end
	CombatService.Killed:Fire(if source ~= nil then source.UserId else 0, targetModel)
end

-- Pigment interaction (docs/GAME_DESIGN.md §6): a mark left by another pigment amplifies this hit
-- once, by the multiplier CombatConfig.Status declares. Returns the damage and the mark that did it,
-- so the Hit packet can show the bonus (flat and visible, never a hidden multiplier).
local function amplifyByMark(humanoid: Humanoid, damage: number, pigment: string?, now: number): (number, PigmentMark?)
	if pigment == nil then
		return damage, nil
	end
	local mark = MARK_BY_AMPLIFIED_PIGMENT[pigment]
	if mark == nil or not isStatusActive(humanoid, mark.Attribute, now) then
		return damage, nil
	end
	return damage * mark.DamageMultiplier, mark
end

-- Verdigris marks its targets Fanned, Indigo marks them Conductive: only a hit that landed marks, and a
-- second hit of the same pigment refreshes the expiry instead of stacking.
local function markTarget(humanoid: Humanoid, pigment: string?, now: number)
	if pigment == nil then
		return
	end
	local mark = MARK_BY_SOURCE_PIGMENT[pigment]
	if mark ~= nil then
		setStatus(humanoid, mark.Attribute, mark.DurationSeconds, now)
	end
end

-- Guard rules for a blocking player target. Takes the damage left by the pigment and Gilding
-- steps. Returns the damage that goes through and whether the guard absorbed part of it.
local function applyGuard(
	targetPlayer: Player,
	targetState: State,
	damage: number,
	kind: string,
	tags: { string },
	origin: Vector3,
	now: number
): (number, boolean)
	if breaksGuard(kind, tags) then
		releaseBlock(targetState, now)
		movement.applyStun(targetPlayer, CombatConfig.Block.BreakStunSeconds)
		-- Target, like the Hit packet: the body that is thrown open is the target's, and without
		-- naming it the clients could only guess which of the two characters to pose.
		vfx.emit({ Id = "GuardBreak", Origin = origin, Params = { Target = targetPlayer.UserId } })
		return damage, false
	end
	vfx.emit({ Id = "BlockHit", Origin = origin })
	return damage * (1 - CombatConfig.Block.DamageReduction), true
end

-- Everything a hit is turned away for before it is scaled, in one place: what ApplyDamage refuses and what
-- canDamage answers (a glyph that commits to a body before it strikes it, D-143). Read-only: the per-source
-- hit memory stays in ApplyDamage, because only a hit that is going to land may write it.
local function refuses(source: Player?, targetModel: Model, now: number): boolean
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return true
	end
	local sourceCharacter: Model? = if source ~= nil then source.Character else nil
	if sourceCharacter ~= nil and sourceCharacter == targetModel then
		return true
	end
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local targetState = stateOf(targetPlayer)
	if isSpawnProtected(stateOf(source), sourceCharacter, now) or isSpawnProtected(targetState, targetModel, now) then
		return true
	end
	-- A body on the ground is untouchable until it stands (D-113): it cannot act either, and a knockdown
	-- that could be hit would be a guaranteed follow-up. Every knockback, stun and slow rides on damage
	-- applied, so this refuses them too; GlyphEffects does not even pick such a body as a target.
	if targetPlayer ~= nil and movement.isDown(targetPlayer) then
		return true
	end
	if targetState ~= nil and now < targetState.IFramesUntil then
		return true
	end
	return not policy(source, targetModel)
end

-- Whether a hit from `source` on `targetModel` would be let through right now: the safe zone, a match's PvP
-- rule, spawn protection, i-frames and a body on the ground, exactly as ApplyDamage judges them. For an effect
-- that has to choose its body before it strikes (the Dagger moves its caster first).
function CombatService.canDamage(source: Player, targetModel: Model): boolean
	return not refuses(source, targetModel, os.clock())
end

-- `pigment` (glyph pigment, nil for melee / environment) colours the Hit packet clients render and
-- drives the pigment interactions: it writes the mark of its own pigment on the target and reads
-- the mark that amplifies it (docs/GAME_DESIGN.md §6).
function CombatService.ApplyDamage(
	source: Player?,
	targetModel: Model,
	amount: number,
	kind: DamageKind,
	tags: { string },
	pigment: string?
): DamageResult
	local result: DamageResult = { Applied = 0, Killed = false, Blocked = false }
	if not isFiniteNonNegative(amount) then
		log.warn("ApplyDamage rejected (%s): invalid amount %s", kind, tostring(amount))
		return result
	end
	local now = os.clock()
	if refuses(source, targetModel, now) then
		return result
	end
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return result
	end
	local sourceCharacter: Model? = if source ~= nil then source.Character else nil
	local sourceState = stateOf(source)
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local targetState = stateOf(targetPlayer)

	-- Per-source i-frames: one glyph instance (tags[1]) cannot hit the same target twice in a window.
	local memory: { [Model]: number }? = nil
	local tag: string? = tags[1]
	if sourceState ~= nil and tag ~= nil then
		local existing = sourceState.HitMemory[tag]
		if existing == nil then
			existing = {}
			sourceState.HitMemory[tag] = existing
		end
		pruneHitMemory(existing, now)
		if existing[targetModel] ~= nil then
			return result
		end
		memory = existing
	end

	local origin = positionOf(targetModel)
	-- Pigment mark, then Gilding, then the guard: each step scales what the previous one left, so
	-- a guarded Fanned Cinnabar hit is amplified once and reduced once by each, and rounding happens once.
	local damage, amplifier = amplifyByMark(humanoid, amount, pigment, now)
	if isStatusActive(humanoid, STONE_SKIN.Attribute, now) then
		damage *= 1 - STONE_SKIN.DamageReduction
	end
	if targetPlayer ~= nil and targetState ~= nil and targetState.Blocking then
		damage, result.Blocked = applyGuard(targetPlayer, targetState, damage, kind, tags, origin, now)
	end
	local applied = math.floor(damage + 0.5)
	if applied <= 0 then
		return result
	end

	-- Claimed before TakeDamage: Humanoid.Died may run before this call returns and must not credit
	-- the same kill a second time.
	if targetState ~= nil then
		targetState.KillCredited = applied >= humanoid.Health
	end
	-- Before TakeDamage, never after: Humanoid.Died and HealthChanged can run inside that call, and
	-- every consumer of this attribute reads it from one of those events. Written late, EnemyService
	-- credited a dummy kill to the previous attacker (or to nobody on a one-shot) and CombatService's
	-- own last-attacker fallback named the wrong player.
	if source ~= nil then
		targetModel:SetAttribute(LAST_ATTACKER_ATTRIBUTE, source.UserId)
	end
	humanoid:TakeDamage(applied)
	result.Applied = applied
	if source ~= nil then
		CombatService.Damaged:Fire(source.UserId, targetModel, applied, kind)
	end
	markTarget(humanoid, pigment, now)
	if sourceState ~= nil then
		markInCombat(sourceState, now)
	end
	if targetState ~= nil then
		markInCombat(targetState, now)
		targetState.LastDamageTakenAt = now
	end
	local hitParams: { [string]: any } = { Amount = applied, Kind = kind }
	if pigment ~= nil then
		hitParams.Pigment = pigment
	end
	-- The end of a melee chain: the client reads it for the impact frame a finisher earns (D-112), whatever
	-- its damage -- fourteen is a light hit and a heavy moment.
	if kind == "Melee" and tags[1] == "MeleeFinisher" then
		hitParams.Finisher = true
	end
	-- A skinned glyph lands in its skin: the ring, the burn and the number of its hit are part of the
	-- cast. Glyph damage carries its glyph id as tags[1] (GlyphEffects' tracker).
	if kind == "Glyph" and source ~= nil and tags[1] ~= nil then
		local shade = cosmetic.skinShade(source, tags[1])
		if shade ~= 0 then
			hitParams.Shade = shade
		end
	end
	-- Who dealt it and who took it. Without these the client could only guess from the impact position,
	-- and it guessed badly: every player standing near a hit got the hit-stop and the camera shake meant
	-- for the two people actually in it. Target is 0 for a training dummy or an enemy, which has no
	-- player behind it; the client treats that as "not me" and it is right.
	hitParams.Target = if targetPlayer ~= nil then targetPlayer.UserId else 0
	-- The body itself, for the outline and the ink print (D-112): a dummy or the boss has no user id to
	-- find it by, and the training hub never showed either.
	hitParams.Victim = targetModel
	if amplifier ~= nil then
		-- Floating text of the interaction (Strings "hud.status.bonus" takes {status} and {percent}).
		hitParams.StatusKey = amplifier.NameKey
		hitParams.StatusPercent = math.floor((amplifier.DamageMultiplier - 1) * 100 + 0.5)
	end
	-- Horizontal unit vector from whoever dealt the hit toward whoever took it. The client needs it to
	-- throw sparks the way the blow travelled and to lean the camera with the impact instead of shaking
	-- it symmetrically; docs/JUICE_AUDIT.md lists its absence as the reason every hit reads the same.
	-- nil when there is no attacker position to measure from (an environmental hit, a hit on itself),
	-- and the client falls back to a direction-free impact rather than inventing one.
	local hitDirection: Vector3? = nil
	if sourceCharacter ~= nil then
		local flat = origin - positionOf(sourceCharacter)
		flat = Vector3.new(flat.X, 0, flat.Z)
		if flat.Magnitude > 1e-3 then
			hitDirection = flat.Unit
		end
	end
	vfx.emit({
		Id = "Hit",
		Origin = origin,
		Caster = if source ~= nil then source.UserId else nil,
		Direction = hitDirection,
		Params = hitParams,
	})
	if memory ~= nil then
		memory[targetModel] = now + CombatConfig.Hit.IFrameSeconds
	end
	if humanoid.Health <= 0 then
		result.Killed = true
		if targetState ~= nil then
			targetState.KillCredited = true
		end
		onKill(source, targetPlayer, targetModel)
	end
	return result
end

-- Server-approved knockback, applied by the owning client (characters are client-simulated).
-- Any other body is announced on Shoved for whoever moves it: the Forgers are thrown by their service, the
-- anchored dummies and the Erasure have no listener and ignore it. A Gilding target keeps its ground: "la
-- Terre bloque" of docs/GAME_DESIGN.md §6 makes the buff stop knockback as well as damage.
function CombatService.knockback(targetModel: Model, velocity: Vector3, duration: number)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player == nil then
		CombatService.Shoved:Fire(targetModel, velocity, duration)
		return
	end
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if
		humanoid ~= nil
		and STONE_SKIN.KnockbackImmune
		and isStatusActive(humanoid, STONE_SKIN.Attribute, os.clock())
	then
		return
	end
	-- Through grantMovement so the distance it can carry them joins their travel budget: a knockback the
	-- client replicates in one jump must not read as a teleport.
	CombatService.grantMovement(player, { Kind = "Knockback", Velocity = velocity, Duration = duration })
end

-- Grants the Gilding buff (CombatConfig.Status.Gilding) to a live caster for its configured
-- duration: every incoming hit loses DamageReduction and knockback stops applying until it expires.
-- Re-casting refreshes the expiry instead of stacking. Returns false when the caster has no live
-- Humanoid, so the glyph effect can skip its own rendering.
-- Grants an invulnerability window (mobility glyphs). Never shortens one already running: two
-- overlapping sources leave the later expiry in place.
function CombatService.grantIFrames(player: Player, seconds: number)
	if seconds ~= seconds or seconds <= 0 or seconds == math.huge then
		log.warn("grantIFrames rejected for %s: seconds %s", player.Name, tostring(seconds))
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	state.IFramesUntil = math.max(state.IFramesUntil, os.clock() + seconds)
end

-- A charged glyph or a rush holds its caster for `seconds`: no M1 and no other glyph meanwhile, and a dash
-- breaks it (D-142). Returns the hold's number, which the effect keeping it asks about (holdsChannel) and ends
-- it with (endChannel); nil when there is nothing to hold, which no hold is ever read as.
function CombatService.channel(player: Player, seconds: number): number?
	if seconds ~= seconds or seconds < 0 or seconds == math.huge then
		log.warn("channel rejected for %s: seconds %s", player.Name, tostring(seconds))
		return nil
	end
	local state = states[player]
	if state == nil then
		return nil
	end
	return ChannelHold.open(state.Channel, os.clock(), seconds)
end

-- Whether the hold numbered `token` is still the one `player` is kept in: no dash broke it and no later cast
-- opened another. Its effect asks this, never isChanneling, which would read a later glyph's hold as its own.
function CombatService.holdsChannel(player: Player, token: number?): boolean
	local state = states[player]
	return state ~= nil and token ~= nil and ChannelHold.owns(state.Channel, token)
end

-- Ends the hold numbered `token`, and nothing a later cast opened.
function CombatService.endChannel(player: Player, token: number?)
	local state = states[player]
	if state ~= nil and token ~= nil then
		ChannelHold.close(state.Channel, token)
	end
end

function CombatService.applyStoneSkin(player: Player): boolean
	local state = states[player]
	if state == nil then
		return false
	end
	local humanoid = state.Humanoid
	if humanoid == nil or humanoid.Parent ~= state.Character or humanoid.Health <= 0 then
		return false
	end
	setStatus(humanoid, STONE_SKIN.Attribute, STONE_SKIN.DurationSeconds, os.clock())
	return true
end

----------------------------------------------------------------
-- Combat actions (M1 / dash / block)
----------------------------------------------------------------

-- Live humanoid and root of the player's current character, or nil when dead / not spawned. A
-- Humanoid detached from its character is not live: ApplyDamage and the area queries ignore a model
-- without one, so its owner must not act either.
local function liveCharacter(state: State): (Model?, Humanoid?, BasePart?)
	local character = state.Character
	local humanoid = state.Humanoid
	if character == nil or humanoid == nil or humanoid.Parent ~= character or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	local root = rootOf(character)
	if root == nil then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function meleeTargets(character: Model, rootCFrame: CFrame): { Model }
	local melee = CombatConfig.Melee
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local parts = Workspace:GetPartBoundsInBox(
		rootCFrame * CFrame.new(0, 0, -melee.Range / 2),
		Vector3.new(melee.Width * 2, MELEE_HITBOX_HEIGHT, melee.Range),
		params
	)
	local seen: { [Model]: boolean } = {}
	local models: { Model } = {}
	for _, part in ipairs(parts) do
		local model = modelOf(part)
		if model ~= nil and not seen[model] then
			seen[model] = true
			table.insert(models, model)
		end
	end
	return models
end

local function onMelee(player: Player, state: State, now: number)
	local character, _humanoid, root = liveCharacter(state)
	if character == nil or root == nil then
		return
	end
	if movement.isStunned(player) or state.Blocking or ChannelHold.refuses(state.Channel, now) then
		return
	end
	local melee = CombatConfig.Melee
	if now - state.MeleeLastHitAt < melee.HitIntervalSeconds or now < state.MeleeCooldownUntil then
		return
	end
	if now - state.MeleeLastHitAt > melee.ComboWindowSeconds then
		state.MeleeIndex = 0
	end
	state.MeleeIndex += 1
	state.MeleeLastHitAt = now
	local index = math.clamp(state.MeleeIndex, 1, #melee.Damage)
	local damage = melee.Damage[index]
	local isFinisher = index >= #melee.Damage
	local tags = if isFinisher then { "MeleeFinisher" } else { "Melee" .. tostring(index) }
	-- Validated, never the raw client CFrame: a tampered client set its root on the opponent and swung.
	local rootCFrame = trustedCFrame(state, root, now, true)

	for _, model in ipairs(meleeTargets(character, rootCFrame)) do
		local result = CombatService.ApplyDamage(player, model, damage, "Melee", tags)
		if result.Applied > 0 and not isFinisher then
			local hitPlayer = Players:GetPlayerFromCharacter(model)
			if hitPlayer ~= nil then
				movement.applyStun(hitPlayer, melee.HitStunSeconds)
			end
		end
		if isFinisher and result.Applied > 0 then
			CombatService.knockback(
				model,
				rootCFrame.LookVector * melee.FinisherKnockback + Vector3.yAxis * melee.FinisherLift,
				CombatConfig.Hit.KnockbackDurationSeconds
			)
			local targetPlayer = Players:GetPlayerFromCharacter(model)
			if targetPlayer ~= nil then
				movement.applyStun(targetPlayer, melee.FinisherStunSeconds)
				-- After the knockback: the body is thrown, then goes limp, and its stun lasts until it is up.
				movement.ragdoll(targetPlayer, CombatConfig.Hit.RagdollSeconds)
			end
		end
	end

	if isFinisher then
		state.MeleeIndex = 0
		state.MeleeCooldownUntil = now + melee.FinisherCooldownSeconds
	end
	markInCombat(state, now)
	vfx.emit({
		Id = "Melee",
		-- The validated position, not the raw root: emitting the raw one drew the swing where the client
		-- claimed to be and chose the packet's recipients around that point instead of the real one.
		Origin = rootCFrame.Position,
		Direction = rootCFrame.LookVector,
		Caster = player.UserId,
		Params = { Index = index },
	})
end

-- Horizontal unit vector of the dash: current movement input, else the facing direction.
local function dashDirection(humanoid: Humanoid, root: BasePart): Vector3
	local direction = humanoid.MoveDirection
	if direction.Magnitude <= 0.1 then
		direction = root.CFrame.LookVector
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return -Vector3.zAxis
	end
	return flat.Unit
end

local function onDash(player: Player, state: State, now: number)
	local _character, humanoid, root = liveCharacter(state)
	if humanoid == nil or root == nil then
		return
	end
	if movement.isStunned(player) or now < state.DashCooldownUntil then
		return
	end
	local dash = CombatConfig.Dash
	-- Inside the finisher's recovery a dash can also CUT that recovery, for the extra ink -- and only if
	-- the player can pay for it. Charging every dash in the window and refusing the ones under 25 took the
	-- escape away exactly when it was needed: a player between 10 and 24 ink who had just thrown a
	-- finisher could not dash at all, for a second and a fifth, with no message. The cancel is the
	-- affordable extra, never a toll on the dash itself.
	local cancelling = now < state.MeleeCooldownUntil and state.Ink >= dash.Cost + dash.CancelCost
	local cost = if cancelling then dash.Cost + dash.CancelCost else dash.Cost
	if not CombatService.trySpendInk(player, cost) then
		return
	end
	if cancelling then
		state.MeleeCooldownUntil = now
	end
	-- I-frames are granted on the server decision alone, independently of the client actually applying
	-- the Dash MovementCommand: characters are client-simulated, so the displacement is not observable
	-- here (docs/DECISIONS.md D-13). The cost and the cooldown are what bound the ability.
	state.IFramesUntil = now + dash.IFrameSeconds
	state.DashCooldownUntil = now + dash.CooldownSeconds
	ChannelHold.breaks(state.Channel) -- a dash is the way out of a charge or a rush (D-142)
	local direction = dashDirection(humanoid, root)
	CombatService.grantMovement(player, {
		Kind = "Dash",
		Direction = direction,
		Distance = dash.Distance,
		Duration = dash.DurationSeconds,
	})
	vfx.emit({
		Id = "Dash",
		Origin = root.Position,
		Direction = direction,
		Caster = player.UserId,
		Params = { Distance = dash.Distance, Duration = dash.DurationSeconds },
	})
	CombatService.Dashed:Fire(player, cancelling)
end

local function onBlockStart(player: Player, state: State, now: number)
	local _character, humanoid, root = liveCharacter(state)
	if humanoid == nil or root == nil then
		return
	end
	if movement.isStunned(player) or now < state.BlockCooldownUntil or state.Blocking then
		return
	end
	state.Blocking = true
	state.BlockStartedAt = now
	movement.applySlow(
		player,
		BLOCK_SLOW_KEY,
		CombatConfig.Block.WalkSpeedFactor,
		CombatConfig.Block.SlowRefreshSeconds
	)
	humanoid:SetAttribute(BLOCK_ATTRIBUTE, true)
	vfx.emit({ Id = "BlockStart", Origin = root.Position, Caster = player.UserId })
end

local function onCombatAction(player: Player, action: Action)
	local state = states[player]
	if state == nil then
		return
	end
	local now = os.clock()
	if action == "Melee" then
		onMelee(player, state, now)
	elseif action == "Dash" then
		onDash(player, state, now)
	elseif action == "BlockStart" then
		onBlockStart(player, state, now)
	elseif action == "BlockEnd" then
		if state.Blocking then
			releaseBlock(state, now)
		end
	end
end

----------------------------------------------------------------
-- Heartbeat: regen, timers, replication
----------------------------------------------------------------

local function cooldownsFor(player: Player): { [string]: number }
	local api = glyph
	if api == nil then
		return {}
	end
	return api.getCooldowns(player)
end

local function replicateState(player: Player, state: State, inCombat: boolean)
	if player.Parent ~= Players then
		return
	end
	local humanoid = state.Humanoid
	registry.fire("CombatState", player, {
		Ink = state.Ink,
		MaxInk = CombatConfig.Ink.Max,
		Health = if humanoid ~= nil then humanoid.Health else 0,
		MaxHealth = if humanoid ~= nil then humanoid.MaxHealth else CombatConfig.Health.Max,
		InCombat = inCombat,
		Blocking = state.Blocking,
		Cooldowns = cooldownsFor(player),
	})
end

-- `elapsed` is the wall-clock time since the previous tick, never the nominal tick length: the
-- accumulator fires at most once per frame and drops the remainder, so below TickRate frames per second
-- a fixed step silently paid out less ink and health per second than the config promises. Rates are
-- per second and integrating over the real interval makes them frame-rate independent.
local function tickPlayer(player: Player, state: State, now: number, elapsed: number, replicate: boolean)
	local ink = CombatConfig.Ink
	local inCombat = now < state.InCombatUntil
	if state.Ink < ink.Max then
		local rate = if inCombat then ink.RegenInCombat else ink.RegenOutOfCombat
		state.Ink = math.min(ink.Max, state.Ink + rate * elapsed)
	end

	-- Sampled every tick, so the plausibility envelope an action is measured against stays tight
	-- (TickRate studs of travel, not a whole idle period's worth).
	local sampleRoot = if state.Character ~= nil then state.Character:FindFirstChild("HumanoidRootPart") else nil
	if sampleRoot ~= nil and sampleRoot:IsA("BasePart") then
		trustedCFrame(state, sampleRoot, now, false)
	end

	-- Entries expire after CombatConfig.Hit.IFrameSeconds but were only ever swept when the same glyph
	-- tag damaged something again, so a tag nobody casts twice kept strong references to the character
	-- Models it hit, and through them their parts, long after they were destroyed.
	for _, memory in pairs(state.HitMemory) do
		pruneHitMemory(memory, now)
	end

	local humanoid = state.Humanoid
	local alive = false
	if humanoid ~= nil and humanoid.Health > 0 then
		alive = true
		local health = CombatConfig.Health
		if humanoid.Health < humanoid.MaxHealth and now - state.LastDamageTakenAt >= health.RegenDelaySeconds then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + health.RegenPerSecond * elapsed)
		end
	end

	if state.Blocking then
		-- The stance is paid for by the tick, over the real interval, like every other rate in here. It
		-- ends when the player lets go, when they die, or when the ink runs out -- never on a timer.
		local block = CombatConfig.Block
		state.Ink = math.max(0, state.Ink - block.InkPerSecond * elapsed)
		if not alive or state.Ink <= 0 then
			releaseBlock(state, now)
		else
			-- Re-armed every tick so the slow can never outlive the guard, whatever ends it.
			movement.applySlow(player, BLOCK_SLOW_KEY, block.WalkSpeedFactor, block.SlowRefreshSeconds)
		end
	end

	if replicate then
		replicateState(player, state, inCombat)
	end
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	ticksSinceReplication += 1
	local replicate = ticksSinceReplication >= TICKS_PER_REPLICATION
	if replicate then
		ticksSinceReplication = 0
	end
	local now = os.clock()
	local elapsed = if lastTickAt > 0 then now - lastTickAt else 0
	lastTickAt = now
	for player, state in pairs(states) do
		tickPlayer(player, state, now, elapsed, replicate)
	end
	-- Once per tick, after every player's own: a tick that came late is a server hitch, which excuses what it
	-- makes a body look like. Under its own MicroProfiler label, so its cost can be read apart.
	debug.profilebegin(AUDIT_PROFILE_LABEL)
	log.try("MovementAudit.step", MovementAudit.step, now, elapsed > MovementGuardConfig.HitchSeconds)
	debug.profileend()
end

----------------------------------------------------------------
-- Public state API
----------------------------------------------------------------

function CombatService.getState(player: Player): CombatState
	local state = states[player]
	if state == nil then
		return { Ink = 0, MaxInk = CombatConfig.Ink.Max, InCombat = false, Blocking = false, Stunned = false }
	end
	return {
		Ink = state.Ink,
		MaxInk = CombatConfig.Ink.Max,
		InCombat = os.clock() < state.InCombatUntil,
		Blocking = state.Blocking,
		Stunned = movement.isStunned(player),
	}
end

-- Debits `cost` ink when available. Returns false (and changes nothing) otherwise.
function CombatService.trySpendInk(player: Player, cost: number): boolean
	if not isFiniteNonNegative(cost) then
		log.warn("trySpendInk rejected for %s: invalid cost %s", player.Name, tostring(cost))
		return false
	end
	local state = states[player]
	if state == nil or state.Ink < cost then
		return false
	end
	state.Ink -= cost
	return true
end

-- Gives ink back, never past the maximum: the chain refund (GlyphService). Refuses a bad amount the
-- way trySpendInk does.
function CombatService.addInk(player: Player, amount: number)
	if not isFiniteNonNegative(amount) then
		log.warn("addInk rejected for %s: invalid amount %s", player.Name, tostring(amount))
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	state.Ink = math.min(CombatConfig.Ink.Max, state.Ink + amount)
end

function CombatService.isBlocking(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Blocking
end

function CombatService.isStunned(player: Player): boolean
	return movement.isStunned(player)
end

-- Whether `player` is kept in a hold now, whoever opened it: what refuses every other glyph (GlyphService).
function CombatService.isChanneling(player: Player): boolean
	local state = states[player]
	return state ~= nil and ChannelHold.refuses(state.Channel, os.clock())
end

-- Replaces the PvP policy (match / boss modes). The policy runs after spawn protection and i-frames.
-- Installs the PvP rule and returns the one it replaced, so a temporary owner (a World Boss event)
-- can hand it back. There is a single slot: two owners at once must coordinate, never interleave.
function CombatService.setPolicy(fn: Policy): Policy?
	if type(fn) ~= "function" then
		log.warn("setPolicy rejected: expected function, got %s", typeof(fn))
		return nil
	end
	local previous = policy
	policy = fn
	return previous
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CombatService.Init(injected: Deps)
	deps = injected
	registry = injected.Registry
	dataService = injected.DataService
	notify = injected.Notify
	movement = injected.Movement
	antiCheat = injected.AntiCheat
	vfx = injected.Vfx
	progression = injected.Progression
	currency = injected.Currency
	cosmetic = injected.Cosmetic
	MovementAudit.init({
		AntiCheat = antiCheat,
		Movement = movement,
		Registry = registry,
		Reanchor = reanchor,
		SpawnPoint = spawnPoint,
	}, AUDIT)
end

function CombatService.Start()
	glyph = deps.Glyph
	if glyph == nil then
		log.warn("Glyph dependency missing: CombatState replicates without cooldowns")
	end
	MovementAudit.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	registry.on("CombatAction", onCombatAction)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info(
		"started (tick %d Hz, state %d Hz, safe zone %d studs)",
		GameConfig.Server.TickRate,
		STATE_REPLICATION_HZ,
		SAFE_ZONE_RADIUS_STUDS
	)
end

return CombatService
