--!strict
-- MovementService: owns Humanoid movement stats. Applies GameConfig.Movement on spawn, runs the
-- slow / stun status timers on one Heartbeat accumulator (no per-player loops) and relays
-- server-approved movement commands to the owning client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Trove = require(Packages.Trove)

local log = Log.new("MovementService")

-- Payload of the MovementCommand remote (see Shared/Remotes).
export type Command =
	{ Kind: "Dash", Direction: Vector3, Distance: number, Duration: number }
	| { Kind: "Knockback", Velocity: Vector3, Duration: number }
	| { Kind: "Stun", Seconds: number }

type Registry = { fire: (name: string, player: Player, ...any) -> () }
type Deps = { Registry: Registry }
type TroveType = typeof(Trove.new())

type State = {
	Trove: TroveType, -- player lifetime
	CharacterTrove: TroveType?, -- current character
	Humanoid: Humanoid?, -- nil while dead or without character
	SlowFactor: number, -- 1 when no slow is active
	SlowUntil: number, -- os.clock expiry, 0 when inactive
	StunUntil: number, -- os.clock expiry, 0 when inactive
}

local SLOW_ATTRIBUTE = CombatConfig.Status.SlowAttribute
local STUN_ATTRIBUTE = CombatConfig.Status.StunAttribute
local TICK_SECONDS = 1 / GameConfig.Server.TickRate
local HUMANOID_WAIT_SECONDS = 10

local MovementService = {}

local registry: Registry
local states: { [Player]: State } = {}
local accumulator = 0

local function isFinitePositive(value: number): boolean
	return value == value and value ~= math.huge and value > 0
end

-- Writes WalkSpeed / JumpPower from the status state. Stun wins over slow.
local function applyStats(state: State, now: number)
	local humanoid = state.Humanoid
	if humanoid == nil then
		return
	end
	if state.StunUntil > now then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		return
	end
	local factor = if state.SlowUntil > now then state.SlowFactor else 1
	humanoid.WalkSpeed = GameConfig.Movement.WalkSpeed * factor
	humanoid.JumpPower = GameConfig.Movement.JumpPower
end

local function clearStatuses(state: State)
	state.SlowFactor = 1
	state.SlowUntil = 0
	state.StunUntil = 0
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
		clearStatuses(state)
		state.Humanoid = nil
	end)
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
		SlowFactor = 1,
		SlowUntil = 0,
		StunUntil = 0,
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

-- Expires slows and stuns for every tracked character, `GameConfig.Server.TickRate` times per second.
local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local now = os.clock()
	for _, state in pairs(states) do
		local humanoid = state.Humanoid
		if humanoid == nil then
			continue
		end
		local changed = false
		if state.SlowUntil > 0 and state.SlowUntil <= now then
			state.SlowUntil = 0
			state.SlowFactor = 1
			humanoid:SetAttribute(SLOW_ATTRIBUTE, nil)
			changed = true
		end
		if state.StunUntil > 0 and state.StunUntil <= now then
			state.StunUntil = 0
			humanoid:SetAttribute(STUN_ATTRIBUTE, nil)
			changed = true
		end
		if changed then
			applyStats(state, now)
		end
	end
end

-- Multiplies WalkSpeed by `factor` (0..1) for `seconds`. Slows never stack: the strongest factor
-- is kept and the expiry extended.
function MovementService.applySlow(player: Player, factor: number, seconds: number)
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
	if state.SlowUntil > now then
		state.SlowFactor = math.min(state.SlowFactor, factor)
		state.SlowUntil = math.max(state.SlowUntil, expiry)
	else
		state.SlowFactor = factor
		state.SlowUntil = expiry
	end
	humanoid:SetAttribute(SLOW_ATTRIBUTE, state.SlowUntil)
	applyStats(state, now)
end

-- Ends any active slow immediately (guard release, cleanse effects).
function MovementService.clearSlow(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	state.SlowUntil = 0
	state.SlowFactor = 1
	local humanoid = state.Humanoid
	if humanoid ~= nil then
		humanoid:SetAttribute(SLOW_ATTRIBUTE, nil)
	end
	applyStats(state, os.clock())
end

-- Freezes the character for `seconds` (capped by CombatConfig.Hit.StunMaxSeconds, never shortened
-- when already stunned) and tells the owning client to lock its input for the remaining time.
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
	local capped = math.min(seconds, CombatConfig.Hit.StunMaxSeconds)
	state.StunUntil = math.max(state.StunUntil, now + capped)
	humanoid:SetAttribute(STUN_ATTRIBUTE, state.StunUntil)
	applyStats(state, now)
	MovementService.command(player, { Kind = "Stun", Seconds = state.StunUntil - now })
end

function MovementService.isStunned(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.StunUntil > os.clock()
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
end

function MovementService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (walk %d, jump %d)", GameConfig.Movement.WalkSpeed, GameConfig.Movement.JumpPower)
end

return MovementService
