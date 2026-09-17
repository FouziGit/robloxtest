--!strict
-- CombatController: relays the combat kit inputs (melee, dash, block hold) to the server through
-- `CombatAction` and mirrors the server's `CombatState` snapshots for the HUD. Every number here is
-- server-authored; the client only displays it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)

local log = Log.new("CombatController")

export type State = {
	Chakra: number,
	MaxChakra: number,
	Health: number,
	MaxHealth: number,
	InCombat: boolean,
	Blocking: boolean,
	Cooldowns: { [string]: number },
}

type Deps = { RemoteClient: any, InputController: any }
type Mapping = { Began: string?, Ended: string? }

local ACTIONS: { [string]: Mapping } = {
	Melee = { Began = "Melee" },
	Dash = { Began = "Dash" },
	Block = { Began = "BlockStart", Ended = "BlockEnd" },
}
local BLOCK_ACTION = "Block"
local NUMBER_FIELDS = { "Chakra", "MaxChakra", "Health", "MaxHealth" }
local BOOLEAN_FIELDS = { "InCombat", "Blocking" }

local CombatController = {}

CombatController.StateChanged = Signal.new() -- (state: State)

local remoteClient: any
local inputController: any

local state: State = {
	Chakra = CombatConfig.Chakra.Max * CombatConfig.Chakra.StartFraction,
	MaxChakra = CombatConfig.Chakra.Max,
	Health = CombatConfig.Health.Max,
	MaxHealth = CombatConfig.Health.Max,
	InCombat = false,
	Blocking = false,
	Cooldowns = {},
}
local blockHeld = false
local malformedWarned = false

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function send(command: string)
	remoteClient.fire("CombatAction", command)
end

local function onAction(actionId: string, began: boolean)
	local mapping = ACTIONS[actionId]
	if mapping == nil then
		return
	end
	if actionId == BLOCK_ACTION then
		if blockHeld == began then
			return
		end
		blockHeld = began
	end
	local command = if began then mapping.Began else mapping.Ended
	if command ~= nil then
		send(command)
	end
end

-- Menus unbind the actions without an End event: release the guard so it never sticks.
local function onSuspended(value: boolean)
	if value and blockHeld then
		blockHeld = false
		send("BlockEnd")
	end
end

local function onCombatState(payload: any)
	if type(payload) ~= "table" then
		if not malformedWarned then
			malformedWarned = true
			log.warn("malformed CombatState dropped (%s)", typeof(payload))
		end
		return
	end
	for _, field in ipairs(NUMBER_FIELDS) do
		if isFinite(payload[field]) then
			(state :: any)[field] = payload[field]
		end
	end
	for _, field in ipairs(BOOLEAN_FIELDS) do
		if type(payload[field]) == "boolean" then
			(state :: any)[field] = payload[field]
		end
	end
	state.Cooldowns = if type(payload.Cooldowns) == "table" then payload.Cooldowns else {}
	CombatController.StateChanged:Fire(state)
end

function CombatController.getState(): State
	return state
end

function CombatController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	inputController = deps.InputController
end

function CombatController.Start()
	inputController.Action:Connect(onAction)
	inputController.SuspendedChanged:Connect(onSuspended)
	remoteClient.on("CombatState", onCombatState)
	log.info("started")
end

return CombatController
