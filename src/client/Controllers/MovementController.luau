--!strict
-- MovementController: client-side movement the server cannot simulate. Double jump (edge-latched jump
-- input, GameConfig.Movement), and the server-approved MovementCommand payloads: dash and knockback
-- (LinearVelocity on the owned root, since characters are client-simulated) and stun (movement input
-- sink). WalkSpeed and JumpPower are server-owned and never written here.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Trove = require(Packages.Trove)

local log = Log.new("MovementController")

type Deps = { RemoteClient: any }
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

-- Drives the root at `velocity` for `duration` with a LinearVelocity, replacing any mover in progress.
local function pushVelocity(part: BasePart, velocity: Vector3, duration: number)
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
	mover.VectorVelocity = velocity
	mover.Parent = part
	commandTrove:Add(mover)

	task.delay(math.min(duration, MAX_COMMAND_SECONDS), function()
		if activeMover == commandTrove then
			stopMover()
		end
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
		pushVelocity(currentRoot, direction.Unit * (payload.Distance / payload.Duration), payload.Duration)
	elseif kind == "Knockback" then
		local velocity = payload.Velocity
		if typeof(velocity) ~= "Vector3" or not isPositive(payload.Duration) then
			warnMalformed("Knockback velocity/duration")
			return
		end
		currentRoot.AssemblyLinearVelocity = velocity
		pushVelocity(currentRoot, velocity, payload.Duration)
	else
		warnMalformed("unknown kind " .. kind)
	end
end

function MovementController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
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
