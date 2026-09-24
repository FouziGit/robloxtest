--!strict
-- VfxBroadcaster: the only server-side path for visual effects. The server never builds visuals; it
-- broadcasts small packets ({Id, Origin, Direction, Caster, Targets, Params}) and each client renders
-- them through VfxLibrary. Packets go over the unreliable `Vfx` remote unless `reliable` is set
-- (walls, zones, kill effects) and only reach players near the origin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)

local log = Log.new("VfxBroadcaster")

export type Packet = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}

type Registry = { fire: (name: string, player: Player, ...any) -> () }
type Deps = { Registry: Registry }

-- One recipient of the current frame. Position is nil for a player without a character (spectating or
-- still loading), who receives every packet.
type Recipient = { Player: Player, Position: Vector3? }

-- Players whose character root is farther than this from the packet origin never see it; the radius is
-- the scene scale (see GameConfig.Vfx).
local BROADCAST_RADIUS_STUDS = GameConfig.Vfx.BroadcastRadiusStuds
local BROADCAST_RADIUS_SQUARED = BROADCAST_RADIUS_STUDS * BROADCAST_RADIUS_STUDS
local ROOT_PART_NAME = "HumanoidRootPart"

local VfxBroadcaster = {}

local registry: Registry

-- Recipients resolved once per frame: a busy frame broadcasts many packets, and resolving Character
-- plus HumanoidRootPart per packet per player multiplies that walk by the packet count.
local recipients: { Recipient } = {}
local recipientsStale = true

local function isValid(packet: Packet, context: string): boolean
	if type(packet) ~= "table" then
		log.warn("%s rejected: packet is %s", context, typeof(packet))
		return false
	end
	if type(packet.Id) ~= "string" or packet.Id == "" then
		log.warn("%s rejected: Id is %s", context, typeof(packet.Id))
		return false
	end
	if typeof(packet.Origin) ~= "Vector3" then
		log.warn("%s (%s) rejected: Origin is %s", context, packet.Id, typeof(packet.Origin))
		return false
	end
	return true
end

local function remoteName(reliable: boolean?): string
	return if reliable == true then "VfxReliable" else "Vfx"
end

local function rootPositionOf(player: Player): Vector3?
	local character: Model? = player.Character
	if character == nil then
		return nil
	end
	local root: Instance? = character:FindFirstChild(ROOT_PART_NAME)
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function refreshRecipients()
	table.clear(recipients)
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(recipients, { Player = player, Position = rootPositionOf(player) })
	end
	recipientsStale = false
end

-- True when the recipient has no character (spectating / loading) or is within the broadcast radius.
local function shouldReceive(position: Vector3?, origin: Vector3): boolean
	if position == nil then
		return true
	end
	local offset = position - origin
	return offset:Dot(offset) <= BROADCAST_RADIUS_SQUARED
end

-- Sends the packet to every player near `packet.Origin` (players without a character always receive it),
-- and near `alsoNear` too when given: a thrown thing's burst goes to everyone who saw it thrown, or a
-- player behind the thrower drew the flight and never its landing (D-114, found by review).
function VfxBroadcaster.emit(packet: Packet, reliable: boolean?, alsoNear: Vector3?)
	if not isValid(packet, "emit") then
		return
	end
	if recipientsStale then
		refreshRecipients()
	end
	local name = remoteName(reliable)
	for _, recipient in ipairs(recipients) do
		local near = shouldReceive(recipient.Position, packet.Origin)
			or (alsoNear ~= nil and shouldReceive(recipient.Position, alsoNear))
		if near then
			registry.fire(name, recipient.Player, packet)
		end
	end
end

-- Sends the packet to one player regardless of distance (personal feedback: hits on self, kills).
function VfxBroadcaster.emitTo(player: Player, packet: Packet, reliable: boolean?)
	if not isValid(packet, "emitTo") then
		return
	end
	if player.Parent ~= Players then
		return
	end
	registry.fire(remoteName(reliable), player, packet)
end

function VfxBroadcaster.Init(deps: Deps)
	registry = deps.Registry
end

function VfxBroadcaster.Start()
	-- Marking the snapshot stale once per frame is enough whichever order this runs in relative to the
	-- services that emit: either way a frame rebuilds it exactly once, on its first packet.
	RunService.Heartbeat:Connect(function()
		recipientsStale = true
	end)
	log.info("started (radius %d studs)", BROADCAST_RADIUS_STUDS)
end

return VfxBroadcaster
