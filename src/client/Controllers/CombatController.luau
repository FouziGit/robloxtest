--!strict
-- CombatController: relays the combat kit inputs (melee, dash, block hold) to the server through
-- `CombatAction` and mirrors the server's `CombatState` snapshots for the HUD. Every number here is
-- server-authored; the client only displays it.
--
-- Sends are throttled to the server's own acceptance intervals (see SEND_INTERVAL) so a legitimate
-- player mashing the combat keys never overflows the `CombatAction` token bucket. This is a courtesy
-- to the rate limiter only: the server re-checks every cooldown and never trusts this timing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local CombatConfig = require(Shared.Config.CombatConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)

local log = Log.new("CombatController")
local player = Players.LocalPlayer

export type State = {
	Ink: number,
	MaxInk: number,
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
-- Minimum delay between two identical sends, mirroring the interval the server itself accepts
-- (CombatService.onMelee / onDash). Anything faster is guaranteed to be rejected server-side and only
-- drains the shared CombatAction token bucket, so it is dropped here instead. Block needs no entry:
-- it is a hold, coalesced through `blockHeld` below.
local SEND_INTERVAL: { [string]: number } = {
	Melee = CombatConfig.Melee.HitIntervalSeconds,
	Dash = CombatConfig.Dash.CooldownSeconds,
}
local NUMBER_FIELDS = { "Ink", "MaxInk", "Health", "MaxHealth" }
local BOOLEAN_FIELDS = { "InCombat", "Blocking" }

local CombatController = {}

CombatController.StateChanged = Signal.new() -- (state: State)

local remoteClient: any
local inputController: any

local state: State = {
	Ink = CombatConfig.Ink.Max * CombatConfig.Ink.StartFraction,
	MaxInk = CombatConfig.Ink.Max,
	Health = CombatConfig.Health.Max,
	MaxHealth = CombatConfig.Health.Max,
	InCombat = false,
	Blocking = false,
	Cooldowns = {},
}
local blockHeld = false
local malformedWarned = false
local lastSentAt: { [string]: number } = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Throttled by SEND_INTERVAL: a repeat inside the server's own acceptance window is dropped locally.
local function send(command: string)
	local interval = SEND_INTERVAL[command]
	if interval ~= nil then
		local now = os.clock()
		local last = lastSentAt[command]
		if last ~= nil and now - last < interval then
			return
		end
		lastSentAt[command] = now
	end
	remoteClient.fire("CombatAction", command)
end

local function onAction(actionId: string, began: boolean)
	local mapping = ACTIONS[actionId]
	if mapping == nil then
		return
	end
	local command = if began then mapping.Began else mapping.Ended
	if command == nil then
		return
	end
	if actionId == BLOCK_ACTION then
		-- The guard is a hold: only a real state change is worth a packet, so BlockStart is never sent
		-- twice in a row and a release without a matching press sends nothing.
		if blockHeld == began then
			return
		end
		blockHeld = began
	end
	send(command)
end

-- A respawn clears the server's own cooldowns (CombatService.resetState), so the local throttle must
-- not keep holding back inputs recorded during the previous life.
local function onCharacterAdded()
	table.clear(lastSentAt)
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
	player.CharacterAdded:Connect(onCharacterAdded)
	remoteClient.on("CombatState", onCombatState)
	log.info("started")
end

return CombatController
