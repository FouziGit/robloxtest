--!strict
-- VfxBroadcaster: the only server-side path for visual effects. The server never builds visuals; it
-- broadcasts small packets ({Id, Origin, Direction, Caster, Targets, Params}) and each client renders
-- them through VfxLibrary. Packets go over the unreliable `Vfx` remote unless `reliable` is set
-- (walls, zones, kill effects) and only reach players near the origin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Players whose character root is farther than this from the packet origin never see it.
-- GameConfig carries no visual-culling distance yet (see docs/ARCHITECTURE.md: "GameConfig distance").
local BROADCAST_RADIUS_STUDS = GameConfig.Vfx.BroadcastRadiusStuds
local BROADCAST_RADIUS_SQUARED = BROADCAST_RADIUS_STUDS * BROADCAST_RADIUS_STUDS
local ROOT_PART_NAME = "HumanoidRootPart"

local VfxBroadcaster = {}

local registry: Registry

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

-- True when the player has no character (spectating / loading) or is within the broadcast radius.
local function shouldReceive(player: Player, origin: Vector3): boolean
	local character: Model? = player.Character
	if character == nil then
		return true
	end
	local root: Instance? = character:FindFirstChild(ROOT_PART_NAME)
	if root == nil or not root:IsA("BasePart") then
		return true
	end
	local offset = root.Position - origin
	return offset:Dot(offset) <= BROADCAST_RADIUS_SQUARED
end

-- Sends the packet to every player near `packet.Origin` (players without a character always receive it).
function VfxBroadcaster.emit(packet: Packet, reliable: boolean?)
	if not isValid(packet, "emit") then
		return
	end
	local name = remoteName(reliable)
	for _, player in ipairs(Players:GetPlayers()) do
		if shouldReceive(player, packet.Origin) then
			registry.fire(name, player, packet)
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
	log.info("started (radius %d studs)", BROADCAST_RADIUS_STUDS)
end

return VfxBroadcaster
