--!strict
-- MovementService: owns Humanoid movement stats. Applies GameConfig.Movement on spawn, runs the
-- slow / stun status timers on one Heartbeat accumulator (no per-player loops) and relays
-- server-approved movement commands to the owning client. Every part of a player's body joins the
-- players' collision group, which does not collide with itself, and a body whose client took its
-- Humanoid away is replaced.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)
local StunClock = require(Shared.Pure.StunClock)
local Trove = require(Packages.Trove)

local log = Log.new("MovementService")

-- Payload of the MovementCommand remote (see Shared/Remotes). A stun is told twice: when it begins or grows (the
-- seconds left) and, when the server lets go of it before its time, when it ends.
export type Command =
	{ Kind: "Dash", Direction: Vector3, Distance: number, Duration: number }
	| { Kind: "Knockback", Velocity: Vector3, Duration: number }
	| { Kind: "Stun", Seconds: number }
	| { Kind: "StunEnd" }

type Registry = { fire: (name: string, player: Player, ...any) -> () }
type AntiCheatApi = {
	strike: (
		player: Player,
		source: string,
		reason: string,
		kind: ("Schema" | "RateLimit" | "Origin" | "Movement")?
	) -> (),
}
type Deps = { Registry: Registry, AntiCheat: AntiCheatApi }
type TroveType = typeof(Trove.new())

-- One live slow source (guard, a glyph id). Sources never merge: see recomputeSlow.
type SlowEntry = { Factor: number, Until: number }

-- A joint loosened by a fall, with what it was before.
type Joint = { Joint: AnimationConstraint, Kinematic: boolean, MaxTorque: number }
-- A body that is down (MovementService.ragdoll): Until ends the limp phase, then the rise. RiseFrom is
-- when the rise began, for the joints' strength coming back over it.
type Fall = { Character: Model, Joints: { Joint }, Rising: boolean, Until: number, RiseFrom: number }
-- A body whose live Humanoid its client took out of it: the seconds it has been away, summed over every time it
-- left and came back, and since when it is away now (nil while it is back).
type Lost = { Character: Model, Away: number, Since: number? }

type State = {
	Trove: TroveType, -- player lifetime
	CharacterTrove: TroveType?, -- current character
	Humanoid: Humanoid?, -- nil while dead or without character
	Slows: { [string]: SlowEntry }, -- keyed by source, empty when no slow is active
	SlowFactor: number, -- minimum factor over the live entries, 1 when none
	SlowUntil: number, -- latest os.clock expiry over the live entries, 0 when none
	Stun: StunClock.Clock, -- the stun, dated on os.clock: when it began, when it ends, when the last one ended
	Fall: Fall?, -- nil unless the body is down
	Lost: Lost?, -- nil unless the live Humanoid has left the body, since it became the player's
}

local SLOW_ATTRIBUTE = CombatConfig.Status.SlowAttribute
local STUN_ATTRIBUTE = CombatConfig.Status.StunAttribute
local RAGDOLL_ATTRIBUTE = CombatConfig.Status.RagdollAttribute
-- The joint that carries the whole body on the root part: loosened, the torso would drop through the root
-- and the character would lose the part every other system reads its position from.
local ROOT_JOINT = "Root"
local TICK_SECONDS = 1 / GameConfig.Server.TickRate
local HUMANOID_WAIT_SECONDS = 10
local CHARACTER_GROUP = GameConfig.Movement.CharacterCollisionGroup

local MovementService = {}

-- A body whose Humanoid never came back is about to be replaced (player: Player): the places that keep a player take
-- it as a death there, before the new body arrives (the Battleground's camp takes it back, D-216).
MovementService.BodyLost = Signal.new()

local registry: Registry
local antiCheat: AntiCheatApi
local states: { [Player]: State } = {}
local accumulator = 0

local function isFinitePositive(value: number): boolean
	return value == value and value ~= math.huge and value > 0
end

-- Recomputes the effective slow from the live keyed entries: strongest factor wins, latest expiry
-- is kept, expired entries are dropped so the table never grows past the active sources.
local function recomputeSlow(state: State, now: number)
	local factor = 1
	local expiry = 0
	for key, entry in pairs(state.Slows) do
		if entry.Until <= now then
			state.Slows[key] = nil
		else
			factor = math.min(factor, entry.Factor)
			expiry = math.max(expiry, entry.Until)
		end
	end
	state.SlowFactor = factor
	state.SlowUntil = expiry
end

-- Writes WalkSpeed / JumpPower from the status state. Stun wins over slow.
local function applyStats(state: State, now: number)
	local humanoid = state.Humanoid
	if humanoid == nil then
		return
	end
	if StunClock.running(state.Stun, now) then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		return
	end
	local factor = if state.SlowUntil > now then state.SlowFactor else 1
	humanoid.WalkSpeed = GameConfig.Movement.WalkSpeed * factor
	humanoid.JumpPower = GameConfig.Movement.JumpPower
end

-- An Avatar Joint Upgrade rig is a ragdoll already: its joints are AnimationConstraints the animation drives
-- kinematically, over BallSocketConstraints with anatomical limits. Loosening every one but the root
-- (not kinematic, no torque) leaves a body hanging in its sockets. It is done HERE: a joint changed on the
-- victim's client never leaves that client, and every other player saw a rigid body tip over like a plank
-- (found by review, D-112). A Motor6D rig has nothing to loosen and keeps only the stun.
local function loosenJoints(character: Model): { Joint }
	local joints: { Joint } = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("AnimationConstraint") and descendant.Name ~= ROOT_JOINT then
			table.insert(joints, {
				Joint = descendant,
				Kinematic = descendant.IsKinematic,
				MaxTorque = descendant.MaxTorque,
			})
			descendant.IsKinematic = false
			descendant.MaxTorque = 0
		end
	end
	return joints
end

-- The rise: each joint gets its strength back while it is still physical, so a limb is PULLED to its pose
-- rather than put there in one frame -- restored rigid at once, a shoulder turned 115 degrees in a single
-- step (art bible rule 3, measured by review). And back gradually, on the square of the rise's progress:
-- all of it in one write, a knee still straightened 106 degrees in one frame; ramped, the worst joint
-- moved 42 (measured live).
local function strengthenJoints(fall: Fall, progress: number)
	local strength = math.clamp(progress, 0, 1) ^ 2
	for _, saved in ipairs(fall.Joints) do
		if saved.Joint.Parent ~= nil then
			saved.Joint.MaxTorque = saved.MaxTorque * strength
		end
	end
end

local function restoreJoints(fall: Fall)
	for _, saved in ipairs(fall.Joints) do
		if saved.Joint.Parent ~= nil then
			saved.Joint.MaxTorque = saved.MaxTorque
			saved.Joint.IsKinematic = saved.Kinematic
		end
	end
	fall.Character:SetAttribute(RAGDOLL_ATTRIBUTE, nil)
end

-- Advances a fall: limp, then rising, then over. The rise is counted from when it was due, not from the
-- tick that noticed: a late tick shortens it by at most a tick instead of stretching the lock past the
-- 0.55 s the finisher was tuned to (review). The stun is renewed to the rise's end all the same.
local function stepFall(player: Player, state: State, fall: Fall, now: number)
	if fall.Until > now then
		if fall.Rising then
			strengthenJoints(fall, (now - fall.RiseFrom) / CombatConfig.Hit.RagdollRiseSeconds)
		end
		return
	end
	if fall.Rising then
		restoreJoints(fall)
		state.Fall = nil
		return
	end
	fall.Rising = true
	fall.RiseFrom = fall.Until
	fall.Until += CombatConfig.Hit.RagdollRiseSeconds
	strengthenJoints(fall, (now - fall.RiseFrom) / CombatConfig.Hit.RagdollRiseSeconds)
	fall.Character:SetAttribute(RAGDOLL_ATTRIBUTE, CombatConfig.Status.RagdollRising)
	if fall.Until > now then
		MovementService.applyStun(player, fall.Until - now)
	end
end

-- A body that dies while it is down stays down: its joints put back rigid, a corpse's limbs jumped to the
-- standing pose in one step (review). Its next character is a new rig.
local function dropFall(state: State)
	local fall = state.Fall
	if fall ~= nil then
		state.Fall = nil
		fall.Character:SetAttribute(RAGDOLL_ATTRIBUTE, nil)
	end
end

local function clearStatuses(state: State)
	local fall = state.Fall
	if fall ~= nil then
		state.Fall = nil
		restoreJoints(fall)
	end
	state.Slows = {}
	state.SlowFactor = 1
	state.SlowUntil = 0
	state.Stun = StunClock.new()
	local humanoid = state.Humanoid
	if humanoid ~= nil then
		humanoid:SetAttribute(SLOW_ATTRIBUTE, nil)
		humanoid:SetAttribute(STUN_ATTRIBUTE, nil)
	end
end

local function releaseCharacter(state: State)
	local characterTrove = state.CharacterTrove
	state.CharacterTrove = nil
	if characterTrove ~= nil then
		characterTrove:Destroy()
	end
	clearStatuses(state)
	state.Humanoid = nil
	state.Lost = nil
end

-- A part of a player's body joins the players' collision group (D-215). Two bodies no longer push each other, so
-- no player can fling another, ram them off a ledge or pop them up off a shared pad; the world, the Forgers and the
-- Erasure, all Default, still collide with them as before.
local function joinGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = CHARACTER_GROUP
	end
end

-- Every part of `character`, now and whatever it is given later (an accessory that loads late, a tool), for as long
-- as it is the player's body.
local function groupCharacter(character: Model, characterTrove: TroveType)
	for _, descendant in ipairs(character:GetDescendants()) do
		joinGroup(descendant)
	end
	characterTrove:Connect(character.DescendantAdded, joinGroup)
end

local function findHumanoid(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		return humanoid
	end
	local waited = character:WaitForChild("Humanoid", HUMANOID_WAIT_SECONDS)
	if waited ~= nil and waited:IsA("Humanoid") then
		return waited
	end
	return nil
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if state == nil then
		return
	end
	releaseCharacter(state)
	local characterTrove = Trove.new()
	state.CharacterTrove = characterTrove
	groupCharacter(character, characterTrove)

	local humanoid = findHumanoid(character)
	if humanoid == nil then
		log.warn("no Humanoid found for %s", player.Name)
		return
	end
	-- findHumanoid may have yielded: only bind if this is still the live character.
	if states[player] ~= state or state.CharacterTrove ~= characterTrove then
		return
	end

	state.Humanoid = humanoid
	humanoid.UseJumpPower = true
	clearStatuses(state)
	applyStats(state, os.clock())

	characterTrove:Connect(humanoid.Died, function()
		dropFall(state)
		clearStatuses(state)
		state.Humanoid = nil
	end)
	-- Same guard as CombatService: a Humanoid the owning client detached from its character must not
	-- keep receiving WalkSpeed / JumpPower and status writes through the cached reference. A live one that
	-- leaves is timed away (respawnLost); given back, the body is held as before, and its time away is kept:
	-- a client that took it out and put it back over and over would otherwise never be replaced. Given back once
	-- that time has run out, it came back too late: it stays away, and the next tick replaces the body, where a
	-- Humanoid returned between the half second and that tick was taken back with no strike.
	local function onHumanoidDetached()
		if states[player] ~= state or state.CharacterTrove ~= characterTrove then
			return
		end
		local now = os.clock()
		local lost = state.Lost
		if humanoid.Parent == character then
			if lost ~= nil and lost.Character == character and lost.Since ~= nil then
				if lost.Away + now - lost.Since >= GameConfig.Spawn.HumanoidReturnSeconds then
					return
				end
				lost.Away += now - lost.Since
				lost.Since = nil
				state.Humanoid = humanoid
				applyStats(state, now)
			end
			return
		end
		local alive = state.Humanoid == humanoid
		clearStatuses(state)
		state.Humanoid = nil
		if not alive then
			return
		end
		if lost ~= nil and lost.Character == character then
			lost.Since = now
		else
			state.Lost = { Character = character, Away = 0, Since = now }
		end
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
		Trove = trove,
		CharacterTrove = nil,
		Humanoid = nil,
		Slows = {},
		SlowFactor = 1,
		SlowUntil = 0,
		Stun = StunClock.new(),
		Fall = nil,
		Lost = nil,
	}
	states[player] = state
	trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, character)
	end)
	trove:Connect(player.CharacterRemoving, function()
		releaseCharacter(state)
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
	releaseCharacter(state)
	state.Trove:Destroy()
end

-- A body whose Humanoid its client took away for GameConfig.Spawn.HumanoidReturnSeconds, at once or a little at a
-- time (D-216): with no Humanoid nothing can hurt it, and it stood invulnerable in the hub or the Erasure's arena. One
-- Schema strike, the places that keep a player told (BodyLost), and a new body from the engine: at the hub, which is
-- where a participant of the Erasure's fight goes back to, or in the Battleground's camp, which takes a member's new
-- body back as it does after a death there. A body already replaced, or a player gone, is left alone.
local function respawnLost(player: Player, character: Model)
	if player.Parent ~= Players or player.Character ~= character then
		return
	end
	antiCheat.strike(player, "Humanoid", "the Humanoid left the character and did not come back", "Schema")
	if player.Parent ~= Players then
		return
	end
	MovementService.BodyLost:Fire(player)
	task.spawn(function()
		log.try("LoadCharacterAsync " .. player.Name, function()
			player:LoadCharacterAsync()
		end)
	end)
end

-- Expires slows, stuns and falls for every tracked character, `GameConfig.Server.TickRate` times per
-- second, and replaces a body whose Humanoid did not come back.
local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local now = os.clock()
	for player, state in pairs(states) do
		local lost = state.Lost
		local since = if lost ~= nil then lost.Since else nil
		if lost ~= nil and since ~= nil and lost.Away + now - since >= GameConfig.Spawn.HumanoidReturnSeconds then
			state.Lost = nil
			respawnLost(player, lost.Character)
		end
		local humanoid = state.Humanoid
		if humanoid == nil then
			continue
		end
		local changed = false
		if state.SlowUntil > 0 then
			local previousFactor = state.SlowFactor
			local previousUntil = state.SlowUntil
			recomputeSlow(state, now)
			if state.SlowFactor ~= previousFactor or state.SlowUntil ~= previousUntil then
				if state.SlowUntil > 0 then
					humanoid:SetAttribute(SLOW_ATTRIBUTE, state.SlowUntil)
				else
					humanoid:SetAttribute(SLOW_ATTRIBUTE, nil)
				end
				changed = true
			end
		end
		if StunClock.expire(state.Stun, now) then
			humanoid:SetAttribute(STUN_ATTRIBUTE, nil)
			changed = true
		end
		if changed then
			applyStats(state, now)
		end
		local fall = state.Fall
		if fall ~= nil then
			stepFall(player, state, fall, now)
		end
	end
end

-- Multiplies WalkSpeed by `factor` (0..1) for `seconds`, under the source `key` ("Block", a glyph
-- id). Re-applying the same key keeps its strongest factor and latest expiry; different keys stay
-- independent so clearing one (guard release) never cleanses another (a glyph slow).
function MovementService.applySlow(player: Player, key: string, factor: number, seconds: number)
	if type(key) ~= "string" or key == "" then
		log.warn("applySlow rejected for %s: invalid key %s", player.Name, tostring(key))
		return
	end
	if factor ~= factor or factor < 0 or factor > 1 or not isFinitePositive(seconds) then
		log.warn("applySlow rejected for %s: factor %s, seconds %s", player.Name, tostring(factor), tostring(seconds))
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	local humanoid = state.Humanoid
	if humanoid == nil then
		return
	end
	local now = os.clock()
	local expiry = now + seconds
	local existing = state.Slows[key]
	if existing ~= nil and existing.Until > now then
		existing.Factor = math.min(existing.Factor, factor)
		existing.Until = math.max(existing.Until, expiry)
	else
		state.Slows[key] = { Factor = factor, Until = expiry }
	end
	recomputeSlow(state, now)
	humanoid:SetAttribute(SLOW_ATTRIBUTE, state.SlowUntil)
	applyStats(state, now)
end

-- Ends the slow of one source immediately (guard release), or every slow when `key` is nil
-- (cleanse effects). Slows from other sources keep running.
function MovementService.clearSlow(player: Player, key: string?)
	local state = states[player]
	if state == nil then
		return
	end
	if key == nil then
		state.Slows = {}
	else
		state.Slows[key] = nil
	end
	local now = os.clock()
	recomputeSlow(state, now)
	local humanoid = state.Humanoid
	if humanoid ~= nil then
		if state.SlowUntil > now then
			humanoid:SetAttribute(SLOW_ATTRIBUTE, state.SlowUntil)
		else
			humanoid:SetAttribute(SLOW_ATTRIBUTE, nil)
		end
	end
	applyStats(state, now)
end

-- Freezes the character for `seconds` (capped by CombatConfig.Hit.StunMaxSeconds, never shortened
-- when already stunned) and tells the owning client to lock its input for the remaining time. A combat hold:
-- a melee hit, a guard break, a fall, a Forger's or the Erasure's blow. A glyph asks applyGlyphStun.
function MovementService.applyStun(player: Player, seconds: number)
	if not isFinitePositive(seconds) then
		log.warn("applyStun rejected for %s: seconds %s", player.Name, tostring(seconds))
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	local humanoid = state.Humanoid
	if humanoid == nil then
		return
	end
	local now = os.clock()
	local left = StunClock.hold(state.Stun, now, math.min(seconds, CombatConfig.Hit.StunMaxSeconds))
	humanoid:SetAttribute(STUN_ATTRIBUTE, state.Stun.Until)
	applyStats(state, now)
	MovementService.command(player, { Kind = "Stun", Seconds = left })
end

-- A glyph's stun (GlyphEffects): it lands only where StunClock admits it -- no stun running, and
-- CombatConfig.Hit.StunGraceSeconds since the last one ended -- and then holds as applyStun does. Returns whether
-- it landed. A chain of glyphs used to extend one stun into the next and hold a player for as long as three
-- casters could keep casting (D-213).
function MovementService.applyGlyphStun(player: Player, seconds: number): boolean
	if not isFinitePositive(seconds) then
		log.warn("applyGlyphStun rejected for %s: seconds %s", player.Name, tostring(seconds))
		return false
	end
	local state = states[player]
	if state == nil or state.Humanoid == nil then
		return false
	end
	if not StunClock.admits(state.Stun, os.clock(), CombatConfig.Hit.StunGraceSeconds) then
		return false
	end
	MovementService.applyStun(player, seconds)
	return true
end

-- Freezes the character for `seconds` without the CombatConfig.Hit.StunMaxSeconds cap that protects
-- combat stuns. Reserved for scripted pauses the server fully controls (match countdown, round reset,
-- boss intro): a combat effect must always go through applyStun.
function MovementService.applyFreeze(player: Player, seconds: number)
	if not isFinitePositive(seconds) then
		log.warn("applyFreeze rejected for %s: seconds %s", player.Name, tostring(seconds))
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	local humanoid = state.Humanoid
	if humanoid == nil then
		return
	end
	local now = os.clock()
	local left = StunClock.hold(state.Stun, now, seconds)
	humanoid:SetAttribute(STUN_ATTRIBUTE, state.Stun.Until)
	applyStats(state, now)
	MovementService.command(player, { Kind = "Stun", Seconds = left })
end

-- Ends a stun or a freeze now, and tells the owning client it has ended. The result screen's freeze lasts as long
-- as the screen, and a player who asks for another duel from that screen is let go before it
-- (MatchService.releaseFromResult): without this they would walk into the next match still frozen. The end is a
-- message of its own, which the client applies at once: `Seconds = 0` was dropped as malformed, so the input stayed
-- locked until the screen's own end, and the attribute left at 0 (not nil) kept the double jump off until the next
-- stun (D-139).
function MovementService.clearStun(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	local now = os.clock()
	StunClock.clear(state.Stun, now)
	local humanoid = state.Humanoid
	if humanoid ~= nil then
		humanoid:SetAttribute(STUN_ATTRIBUTE, nil)
	end
	applyStats(state, now)
	MovementService.command(player, { Kind = "StunEnd" })
end

-- Lets the player's body go limp for `seconds`, then stand back up over CombatConfig.Hit.RagdollRiseSeconds,
-- and keeps the player stunned until it has. The phase is the character's RagdollAttribute: the owning
-- client puts its Humanoid in Physics and back (it alone simulates the body), and every client's Posture
-- stands aside. A body already down is left as it is: it is untouchable (D-113), so nothing that knocks a
-- body down can reach it, and loosening it twice would record loose joints as its own.
function MovementService.ragdoll(player: Player, seconds: number)
	if not isFinitePositive(seconds) then
		log.warn("ragdoll rejected for %s: seconds %s", player.Name, tostring(seconds))
		return
	end
	local state = states[player]
	if state == nil then
		return
	end
	local humanoid = state.Humanoid
	if humanoid == nil then
		return
	end
	local parent = humanoid.Parent
	if parent == nil or not parent:IsA("Model") then
		return
	end
	local character = parent :: Model
	local rise = CombatConfig.Hit.RagdollRiseSeconds
	local limp = math.min(seconds, CombatConfig.Hit.StunMaxSeconds - rise)
	if state.Fall ~= nil then
		return
	end
	local joints = loosenJoints(character)
	if #joints == 0 then
		return
	end
	state.Fall = { Character = character, Joints = joints, Rising = false, Until = os.clock() + limp, RiseFrom = 0 }
	character:SetAttribute(RAGDOLL_ATTRIBUTE, CombatConfig.Status.RagdollLimp)
	MovementService.applyStun(player, limp + rise)
end

-- True while the player's body is down, limp or getting up. CombatService refuses it every hit. It ends
-- when the rise ends, on the clock and not on the tick that restores the joints: the stun ends at that
-- same instant, and for up to a tick a player could act while nobody could touch them (measured live).
function MovementService.isDown(player: Player): boolean
	local state = states[player]
	local fall = if state ~= nil then state.Fall else nil
	return fall ~= nil and not (fall.Rising and fall.Until <= os.clock())
end

function MovementService.isStunned(player: Player): boolean
	local state = states[player]
	return state ~= nil and StunClock.running(state.Stun, os.clock())
end

-- When the running stun began and when it ends, on os.clock; 0, 0 when none runs. The movement audit reads it to
-- see a body walk through a stun it had been told of (Security/MovementAudit).
function MovementService.stunDates(player: Player): (number, number)
	local state = states[player]
	if state == nil or not StunClock.running(state.Stun, os.clock()) then
		return 0, 0
	end
	return state.Stun.StartedAt, state.Stun.Until
end

-- Sends a server-approved movement to the owning client (characters are client-simulated).
function MovementService.command(player: Player, payload: Command)
	if player.Parent ~= Players then
		return
	end
	registry.fire("MovementCommand", player, payload)
end

function MovementService.Init(deps: Deps)
	registry = deps.Registry
	antiCheat = deps.AntiCheat
end

-- The players' group, which does not collide with itself and collides with everything else. Before any body joins
-- it: a part in a group nobody registered collides as Default.
local function registerGroup()
	if not PhysicsService:IsCollisionGroupRegistered(CHARACTER_GROUP) then
		PhysicsService:RegisterCollisionGroup(CHARACTER_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(CHARACTER_GROUP, CHARACTER_GROUP, false)
end

function MovementService.Start()
	log.try("register the " .. CHARACTER_GROUP .. " collision group", registerGroup)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (walk %d, jump %d)", GameConfig.Movement.WalkSpeed, GameConfig.Movement.JumpPower)
end

return MovementService
