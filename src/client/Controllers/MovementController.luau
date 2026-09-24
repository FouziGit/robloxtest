--!strict
-- MovementController: client-side movement the server cannot simulate. Double jump (edge-latched jump
-- input, GameConfig.Movement), and the server-approved MovementCommand payloads: dash and knockback
-- (LinearVelocity on the owned root, since characters are client-simulated) and stun (movement input
-- sink). WalkSpeed and JumpPower are server-owned and never written here.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local FeelConfig = require(Shared.Config.FeelConfig)
local FeelMath = require(Shared.Pure.FeelMath)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Trove = require(Packages.Trove)

local log = Log.new("MovementController")

type Deps = { RemoteClient: any, Feel: any }
type TroveType = typeof(Trove.new())

local ROOT_PART_NAME = "HumanoidRootPart"
local CHARACTER_WAIT_SECONDS = 10
local STUN_ACTION = "MovementStun"
local STUN_PRIORITY = Enum.ContextActionPriority.High.Value + 1 -- above every control binding
local MOVEMENT_ACTIONS: { any } = {
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump,
}
local JUMP_RELEASE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true,
}
local MAX_COMMAND_SECONDS = 3 -- safety cap so a mover can never outlive a bad payload

local MovementController = {}

local remoteClient: any
local feel: any

local player = Players.LocalPlayer
local characterTrove = Trove.new()
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local activeMover: TroveType? = nil
local jumpCount = 0
local jumpLatched = false -- true until the jump input is released after a jump
local stunned = false
local stunGeneration = 0
local malformedWarned = false

local function isPositive(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value > 0
end

local function sinkMovement(_action: string, _state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function releaseStun()
	if not stunned then
		return
	end
	stunned = false
	ContextActionService:UnbindAction(STUN_ACTION)
end

local function applyStun(seconds: number)
	stunGeneration += 1
	local expected = stunGeneration
	if not stunned then
		stunned = true
		ContextActionService:BindActionAtPriority(
			STUN_ACTION,
			sinkMovement,
			false,
			STUN_PRIORITY,
			table.unpack(MOVEMENT_ACTIONS)
		)
	end
	task.delay(seconds, function()
		if expected == stunGeneration then
			releaseStun()
		end
	end)
end

local function stopMover()
	local mover = activeMover
	activeMover = nil
	if mover ~= nil then
		-- Remove both cleans the child trove and drops it from the character trove's object list.
		characterTrove:Remove(mover :: any)
	end
end

-- Drives the root along `velocity` for `duration` with a LinearVelocity, replacing any mover in
-- progress. The speed is not held flat: it follows FeelMath.impulseSpeed, which starts above the flat
-- speed and decays to nothing, the way a body that was struck actually moves.
--
-- That curve is normalised, so the distance travelled is exactly what the flat velocity would have
-- covered over the same duration. This matters more than it looks: knockback distance and dash range
-- are balance numbers the server granted, and a polish pass is not allowed to change them.
local function pushVelocity(part: BasePart, velocity: Vector3, duration: number, exponent: number)
	stopMover()
	local commandTrove = characterTrove:Extend()
	activeMover = commandTrove

	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementCommand"
	attachment.Parent = part
	commandTrove:Add(attachment)

	local mover = Instance.new("LinearVelocity")
	mover.Name = "MovementCommand"
	mover.Attachment0 = attachment
	mover.MaxForce = math.huge
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = velocity * FeelMath.impulseSpeed(0, exponent)
	mover.Parent = part
	commandTrove:Add(mover)

	local total = math.min(duration, MAX_COMMAND_SECONDS)
	local elapsed = 0
	local sinceStep = 0
	commandTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= total then
			if activeMover == commandTrove then
				stopMover()
			end
			return
		end
		-- The curve is re-evaluated at a fixed rate rather than every frame: between evaluations the
		-- constraint holds its value, so a 240 Hz client and a 30 Hz client travel the same path.
		sinceStep += deltaTime
		if sinceStep < FeelConfig.Impulse.StepSeconds then
			return
		end
		sinceStep = 0
		mover.VectorVelocity = velocity * FeelMath.impulseSpeed(elapsed / total, exponent)
	end)
end

local function releaseCharacter()
	characterTrove:Clean()
	activeMover = nil
	releaseStun()
	humanoid = nil
	root = nil
	jumpCount = 0
	jumpLatched = false
end

local function bindCharacter(character: Model)
	releaseCharacter()
	local foundHumanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", CHARACTER_WAIT_SECONDS)
	local foundRoot = character:FindFirstChild(ROOT_PART_NAME)
		or character:WaitForChild(ROOT_PART_NAME, CHARACTER_WAIT_SECONDS)
	-- WaitForChild may have yielded: only bind if this is still the live character.
	if player.Character ~= character then
		return
	end
	if
		foundHumanoid == nil
		or not foundHumanoid:IsA("Humanoid")
		or foundRoot == nil
		or not foundRoot:IsA("BasePart")
	then
		log.warn("character %s has no Humanoid / %s: movement extras disabled", character.Name, ROOT_PART_NAME)
		return
	end
	humanoid = foundHumanoid
	root = foundRoot

	-- A fall (D-112). The server loosens the joints and names the phase on the character; the state of a
	-- Humanoid is its simulating client's alone, so this client lets its body go and stands it back up.
	local function followFall()
		if foundHumanoid.Health <= 0 then
			return
		end
		local phase = character:GetAttribute(CombatConfig.Status.RagdollAttribute)
		if phase == CombatConfig.Status.RagdollLimp then
			foundHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
		elseif foundHumanoid:GetState() == Enum.HumanoidStateType.Physics then
			-- Rising, or the fall already over: a Humanoid never leaves Physics on its own, so a body this
			-- client let go stands back up whichever of the two it saw (review).
			foundHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	characterTrove:Connect(character:GetAttributeChangedSignal(CombatConfig.Status.RagdollAttribute), followFall)
	followFall()

	characterTrove:Connect(
		foundHumanoid.StateChanged,
		function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Jumping then
				jumpCount += 1
				jumpLatched = true
			elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				jumpCount = 0
			end
		end
	)
	characterTrove:Connect(foundHumanoid.Died, function()
		stopMover()
		releaseStun()
		humanoid = nil
		root = nil
	end)
end

local function onJumpRequest()
	local currentHumanoid = humanoid
	local currentRoot = root
	if currentHumanoid == nil or currentRoot == nil or stunned or jumpLatched then
		return
	end
	if jumpCount < 1 or jumpCount >= GameConfig.Movement.MaxJumps then
		return
	end
	if currentHumanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
		return
	end
	if currentHumanoid:GetAttribute(CombatConfig.Status.StunAttribute) ~= nil then
		return
	end
	jumpLatched = true
	local velocity = currentRoot.AssemblyLinearVelocity
	currentRoot.AssemblyLinearVelocity = Vector3.new(velocity.X, GameConfig.Movement.DoubleJumpVelocity, velocity.Z)
	currentHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

local function onInputEnded(input: InputObject, _processed: boolean)
	if JUMP_RELEASE_KEYS[input.KeyCode] or input.UserInputType == Enum.UserInputType.Touch then
		jumpLatched = false
	end
end

local function warnMalformed(reason: string)
	if malformedWarned then
		return
	end
	malformedWarned = true
	log.warn("malformed MovementCommand dropped (%s); further malformed commands are dropped silently", reason)
end

local function onCommand(payload: any)
	if type(payload) ~= "table" or type(payload.Kind) ~= "string" then
		warnMalformed("payload is " .. typeof(payload))
		return
	end
	local kind = payload.Kind
	if kind == "Stun" then
		if not isPositive(payload.Seconds) then
			warnMalformed("Stun.Seconds is " .. typeof(payload.Seconds))
			return
		end
		applyStun(math.min(payload.Seconds, CombatConfig.Hit.StunMaxSeconds))
		return
	end

	local currentRoot = root
	if currentRoot == nil or currentRoot.Parent == nil then
		return
	end
	if kind == "Dash" then
		local direction = payload.Direction
		if typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 then
			warnMalformed("Dash.Direction is " .. typeof(direction))
			return
		end
		if not isPositive(payload.Distance) or not isPositive(payload.Duration) then
			warnMalformed("Dash distance/duration")
			return
		end
		pushVelocity(
			currentRoot,
			direction.Unit * (payload.Distance / payload.Duration),
			payload.Duration,
			FeelConfig.Impulse.DashExponent
		)
		if feel ~= nil then
			feel.fovPunch(FeelConfig.Fov.DashImpulse)
			feel.shake("Dash")
			feel.haptic("Dash")
		end
	elseif kind == "Knockback" then
		local velocity = payload.Velocity
		if typeof(velocity) ~= "Vector3" or not isPositive(payload.Duration) then
			warnMalformed("Knockback velocity/duration")
			return
		end
		currentRoot.AssemblyLinearVelocity = velocity
		pushVelocity(currentRoot, velocity, payload.Duration, FeelConfig.Impulse.KnockbackExponent)
	else
		warnMalformed("unknown kind " .. kind)
	end
end

function MovementController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	feel = deps.Feel
end

-- True while a server-approved displacement is carrying the character. Feel reads it so hit-stop
-- never plants the feet in the middle of a dash the server already granted.
function MovementController.isDisplacing(): boolean
	return activeMover ~= nil
end

function MovementController.Start()
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(releaseCharacter)
	local character = player.Character
	if character ~= nil then
		task.spawn(bindCharacter, character)
	end
	UserInputService.JumpRequest:Connect(onJumpRequest)
	UserInputService.InputEnded:Connect(onInputEnded)
	remoteClient.on("MovementCommand", onCommand)
	log.info("started (max jumps %d)", GameConfig.Movement.MaxJumps)
end

return MovementController
