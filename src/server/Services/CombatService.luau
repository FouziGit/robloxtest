--!strict
-- CombatService: the ONLY damage path of the game. Owns per-player combat state (chakra, guard,
-- dash / melee timers, spawn protection, per-jutsu hit memory), the M1 / dash / block handlers and
-- the single gameplay Heartbeat (regen, timers, CombatState replication at STATE_REPLICATION_HZ).
-- Every hit, from melee, jutsus, bosses or the environment, goes through ApplyDamage so PvP policy,
-- spawn protection, i-frames and guard rules apply everywhere.
-- It also owns the combat statuses of docs/GAME_DESIGN.md §6 (Fanned, Conductive, StoneSkin): they
-- live as Humanoid attributes named by CombatConfig.Status, carry their own expiry and are read back
-- inside ApplyDamage / knockback, so no status needs a ticker and clients can render them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("CombatService")

export type DamageKind = Types.DamageKind
export type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
export type CombatState = { Chakra: number, MaxChakra: number, InCombat: boolean, Blocking: boolean, Stunned: boolean }
export type Policy = (source: Player?, targetModel: Model) -> boolean
export type Action = "Melee" | "Dash" | "BlockStart" | "BlockEnd"

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
type MovementApi = {
	applySlow: (player: Player, key: string, factor: number, seconds: number) -> (),
	clearSlow: (player: Player, key: string?) -> (),
	applyStun: (player: Player, seconds: number) -> (),
	isStunned: (player: Player) -> boolean,
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
type JutsuApi = { getCooldowns: (player: Player) -> { [string]: number } }
type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	fire: (name: string, player: Player, ...any) -> (),
}
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Movement: MovementApi,
	Vfx: VfxApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	Jutsu: JutsuApi?, -- wired after Combat in the bootstrap table: read in Start, never in Init
}
type TroveType = typeof(Trove.new())
-- One elemental interaction of docs/GAME_DESIGN.md §6, as CombatConfig.Status declares it: damage of
-- AppliedByElement writes the mark, damage of AmplifiesElement is multiplied while it lasts.
type ElementalMark = {
	Attribute: string,
	AppliedByElement: string,
	AmplifiesElement: string,
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
	Chakra: number,
	InCombatUntil: number, -- os.clock timestamps below
	LastDamageTakenAt: number,
	Blocking: boolean,
	BlockStartedAt: number,
	BlockCooldownUntil: number,
	DashCooldownUntil: number,
	IFramesUntil: number,
	MeleeIndex: number,
	MeleeLastHitAt: number,
	MeleeCooldownUntil: number,
	SpawnProtectedUntil: number,
	KillCredited: boolean, -- this character's death was already credited (ApplyDamage or onDied)
	HitMemory: { [string]: { [Model]: number } }, -- tag -> target model -> i-frame expiry
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
local BLOCK_ATTRIBUTE = CombatConfig.Status.BlockAttribute
-- Slow source key of the guard, so releasing the guard never cleanses a jutsu slow.
local BLOCK_SLOW_KEY = "Block"

local brokenBy = (CombatConfig.Block.BrokenBy :: any) :: { [string]: boolean }

local STONE_SKIN = CombatConfig.Status.StoneSkin
-- Elemental marks indexed by the element that writes them and by the element they amplify, so
-- ApplyDamage stays two table lookups instead of a chain of element tests.
local ELEMENTAL_MARKS: { ElementalMark } = { CombatConfig.Status.Fanned, CombatConfig.Status.Conductive }
local MARK_BY_SOURCE_ELEMENT: { [string]: ElementalMark } = {}
local MARK_BY_AMPLIFIED_ELEMENT: { [string]: ElementalMark } = {}
-- Every status attribute this service owns, wiped when a character is bound so nothing survives a
-- respawn (the guard attribute is not here: releaseBlock owns it).
local STATUS_ATTRIBUTES: { string } = { STONE_SKIN.Attribute }
for _, mark in ipairs(ELEMENTAL_MARKS) do
	MARK_BY_SOURCE_ELEMENT[mark.AppliedByElement] = mark
	MARK_BY_AMPLIFIED_ELEMENT[mark.AmplifiesElement] = mark
	table.insert(STATUS_ATTRIBUTES, mark.Attribute)
end

local CombatService = {}

CombatService.Killed = Signal.new() -- (sourceUserId: number, victimModel: Model)

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local movement: MovementApi
local vfx: VfxApi
local progression: ProgressionApi
local currency: CurrencyApi
local jutsu: JutsuApi? = nil
local deps: Deps

local states: { [Player]: State } = {}
local policy: Policy
local accumulator = 0
local ticksSinceReplication = 0
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
	state.InCombatUntil = now + CombatConfig.Chakra.InCombatSeconds
end

-- Drops expired i-frame entries so the memory never grows past the targets hit in the last window.
local function pruneHitMemory(memory: { [Model]: number }, now: number)
	for model, expiry in pairs(memory) do
		if expiry <= now then
			memory[model] = nil
		end
	end
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

local function resetState(state: State, now: number)
	state.Chakra = CombatConfig.Chakra.Max * CombatConfig.Chakra.StartFraction
	state.InCombatUntil = 0
	state.LastDamageTakenAt = 0
	state.Blocking = false
	state.BlockStartedAt = 0
	state.BlockCooldownUntil = 0
	state.DashCooldownUntil = 0
	state.IFramesUntil = 0
	state.MeleeIndex = 0
	state.MeleeLastHitAt = 0
	state.MeleeCooldownUntil = 0
	state.SpawnProtectedUntil = now + GameConfig.Spawn.ProtectionSeconds
	state.KillCredited = false
	state.HitMemory = {}
end

-- Credits a death that did not come from ApplyDamage (Reset Character, fall, environment) to the
-- last attacker while the fight is still fresh, so leaving the fight is never a free escape. The
-- attribute is cleared afterwards so a later unrelated death cannot re-credit the same attacker.
local function creditDeath(state: State, character: Model, now: number)
	local attribute = character:GetAttribute(LAST_ATTACKER_ATTRIBUTE)
	local attackerId: number? = if typeof(attribute) == "number" then attribute :: number else nil
	local inCombat = state.LastDamageTakenAt > 0 and now - state.LastDamageTakenAt < CombatConfig.Chakra.InCombatSeconds
	if attackerId == nil and not inCombat then
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
	resetState(state, now)
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
		Chakra = 0,
		InCombatUntil = 0,
		LastDamageTakenAt = 0,
		Blocking = false,
		BlockStartedAt = 0,
		BlockCooldownUntil = 0,
		DashCooldownUntil = 0,
		IFramesUntil = 0,
		MeleeIndex = 0,
		MeleeLastHitAt = 0,
		MeleeCooldownUntil = 0,
		SpawnProtectedUntil = 0,
		KillCredited = false,
		HitMemory = {},
	}
	resetState(state, os.clock())
	states[player] = state
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
			currency.add(source, ProgressionConfig.Ryo.PlayerKill, "PlayerKill")
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

-- Elemental interaction (docs/GAME_DESIGN.md §6): a mark left by another element amplifies this hit
-- once, by the multiplier CombatConfig.Status declares. Returns the damage and the mark that did it,
-- so the Hit packet can show the bonus (flat and visible, never a hidden multiplier).
local function amplifyByMark(
	humanoid: Humanoid,
	damage: number,
	element: string?,
	now: number
): (number, ElementalMark?)
	if element == nil then
		return damage, nil
	end
	local mark = MARK_BY_AMPLIFIED_ELEMENT[element]
	if mark == nil or not isStatusActive(humanoid, mark.Attribute, now) then
		return damage, nil
	end
	return damage * mark.DamageMultiplier, mark
end

-- Wind marks its targets Fanned, Water marks them Conductive: only a hit that landed marks, and a
-- second hit of the same element refreshes the expiry instead of stacking.
local function markTarget(humanoid: Humanoid, element: string?, now: number)
	if element == nil then
		return
	end
	local mark = MARK_BY_SOURCE_ELEMENT[element]
	if mark ~= nil then
		setStatus(humanoid, mark.Attribute, mark.DurationSeconds, now)
	end
end

-- Guard rules for a blocking player target. Takes the damage left by the elemental and StoneSkin
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
		vfx.emit({ Id = "GuardBreak", Origin = origin })
		return damage, false
	end
	vfx.emit({ Id = "BlockHit", Origin = origin })
	return damage * (1 - CombatConfig.Block.DamageReduction), true
end

-- `element` (jutsu element, nil for melee / environment) colours the Hit packet clients render and
-- drives the elemental interactions: it writes the mark of its own element on the target and reads
-- the mark that amplifies it (docs/GAME_DESIGN.md §6).
function CombatService.ApplyDamage(
	source: Player?,
	targetModel: Model,
	amount: number,
	kind: DamageKind,
	tags: { string },
	element: string?
): DamageResult
	local result: DamageResult = { Applied = 0, Killed = false, Blocked = false }
	if not isFiniteNonNegative(amount) then
		log.warn("ApplyDamage rejected (%s): invalid amount %s", kind, tostring(amount))
		return result
	end
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return result
	end
	local now = os.clock()
	local sourceCharacter: Model? = if source ~= nil then source.Character else nil
	if sourceCharacter ~= nil and sourceCharacter == targetModel then
		return result
	end
	local sourceState = stateOf(source)
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local targetState = stateOf(targetPlayer)

	if isSpawnProtected(sourceState, sourceCharacter, now) or isSpawnProtected(targetState, targetModel, now) then
		return result
	end

	-- Per-source i-frames: one jutsu instance (tags[1]) cannot hit the same target twice in a window.
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
	if targetState ~= nil and now < targetState.IFramesUntil then
		return result
	end
	if not policy(source, targetModel) then
		return result
	end

	local origin = positionOf(targetModel)
	-- Elemental mark, then StoneSkin, then the guard: each step scales what the previous one left, so
	-- a guarded Fanned Fire hit is amplified once and reduced once by each, and rounding happens once.
	local damage, amplifier = amplifyByMark(humanoid, amount, element, now)
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
	humanoid:TakeDamage(applied)
	result.Applied = applied
	markTarget(humanoid, element, now)
	if source ~= nil then
		targetModel:SetAttribute(LAST_ATTACKER_ATTRIBUTE, source.UserId)
	end
	if sourceState ~= nil then
		markInCombat(sourceState, now)
	end
	if targetState ~= nil then
		markInCombat(targetState, now)
		targetState.LastDamageTakenAt = now
	end
	local hitParams: { [string]: any } = { Amount = applied, Kind = kind }
	if element ~= nil then
		hitParams.Element = element
	end
	if amplifier ~= nil then
		-- Floating text of the interaction (Strings "hud.status.bonus" takes {status} and {percent}).
		hitParams.StatusKey = amplifier.NameKey
		hitParams.StatusPercent = math.floor((amplifier.DamageMultiplier - 1) * 100 + 0.5)
	end
	vfx.emit({ Id = "Hit", Origin = origin, Params = hitParams })
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
-- NPCs (anchored dummies, bosses) ignore it. A StoneSkin target keeps its ground: "la Terre bloque"
-- of docs/GAME_DESIGN.md §6 makes the buff stop knockback as well as damage.
function CombatService.knockback(targetModel: Model, velocity: Vector3, duration: number)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player == nil then
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
	movement.command(player, { Kind = "Knockback", Velocity = velocity, Duration = duration })
end

-- Grants the StoneSkin buff (CombatConfig.Status.StoneSkin) to a live caster for its configured
-- duration: every incoming hit loses DamageReduction and knockback stops applying until it expires.
-- Re-casting refreshes the expiry instead of stacking. Returns false when the caster has no live
-- Humanoid, so the jutsu effect can skip its own rendering.
-- Grants an invulnerability window (mobility jutsus). Never shortens one already running: two
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
	if movement.isStunned(player) or state.Blocking then
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
	local rootCFrame = root.CFrame

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
		Origin = root.Position,
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
	if not CombatService.trySpendChakra(player, dash.Cost) then
		return
	end
	-- I-frames are granted on the server decision alone, independently of the client actually
	-- applying the Dash MovementCommand (characters are client-simulated, so the displacement is not
	-- observable here). Phase 8 adds the displacement check: expected start position / direction /
	-- duration recorded when the command is sent, compared with the observed root afterwards.
	state.IFramesUntil = now + dash.IFrameSeconds
	state.DashCooldownUntil = now + dash.CooldownSeconds
	local direction = dashDirection(humanoid, root)
	movement.command(player, {
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
	movement.applySlow(player, BLOCK_SLOW_KEY, CombatConfig.Block.WalkSpeedFactor, CombatConfig.Block.MaxHoldSeconds)
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
	local api = jutsu
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
		Chakra = state.Chakra,
		MaxChakra = CombatConfig.Chakra.Max,
		Health = if humanoid ~= nil then humanoid.Health else 0,
		MaxHealth = if humanoid ~= nil then humanoid.MaxHealth else CombatConfig.Health.Max,
		InCombat = inCombat,
		Blocking = state.Blocking,
		Cooldowns = cooldownsFor(player),
	})
end

local function tickPlayer(player: Player, state: State, now: number, replicate: boolean)
	local chakra = CombatConfig.Chakra
	local inCombat = now < state.InCombatUntil
	if state.Chakra < chakra.Max then
		local rate = if inCombat then chakra.RegenInCombat else chakra.RegenOutOfCombat
		state.Chakra = math.min(chakra.Max, state.Chakra + rate * TICK_SECONDS)
	end

	local humanoid = state.Humanoid
	local alive = false
	if humanoid ~= nil and humanoid.Health > 0 then
		alive = true
		local health = CombatConfig.Health
		if humanoid.Health < humanoid.MaxHealth and now - state.LastDamageTakenAt >= health.RegenDelaySeconds then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + health.RegenPerSecond * TICK_SECONDS)
		end
	end

	if state.Blocking then
		if not alive or now - state.BlockStartedAt >= CombatConfig.Block.MaxHoldSeconds then
			releaseBlock(state, now)
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
	for player, state in pairs(states) do
		tickPlayer(player, state, now, replicate)
	end
end

----------------------------------------------------------------
-- Public state API
----------------------------------------------------------------

function CombatService.getState(player: Player): CombatState
	local state = states[player]
	if state == nil then
		return { Chakra = 0, MaxChakra = CombatConfig.Chakra.Max, InCombat = false, Blocking = false, Stunned = false }
	end
	return {
		Chakra = state.Chakra,
		MaxChakra = CombatConfig.Chakra.Max,
		InCombat = os.clock() < state.InCombatUntil,
		Blocking = state.Blocking,
		Stunned = movement.isStunned(player),
	}
end

-- Debits `cost` chakra when available. Returns false (and changes nothing) otherwise.
function CombatService.trySpendChakra(player: Player, cost: number): boolean
	if not isFiniteNonNegative(cost) then
		log.warn("trySpendChakra rejected for %s: invalid cost %s", player.Name, tostring(cost))
		return false
	end
	local state = states[player]
	if state == nil or state.Chakra < cost then
		return false
	end
	state.Chakra -= cost
	return true
end

function CombatService.isBlocking(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Blocking
end

function CombatService.isStunned(player: Player): boolean
	return movement.isStunned(player)
end

-- Replaces the PvP policy (match / boss modes). The policy runs after spawn protection and i-frames.
function CombatService.setPolicy(fn: Policy)
	if type(fn) ~= "function" then
		log.warn("setPolicy rejected: expected function, got %s", typeof(fn))
		return
	end
	policy = fn
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
	vfx = injected.Vfx
	progression = injected.Progression
	currency = injected.Currency
end

function CombatService.Start()
	jutsu = deps.Jutsu
	if jutsu == nil then
		log.warn("Jutsu dependency missing: CombatState replicates without cooldowns")
	end
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
