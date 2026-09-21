--!strict
-- VfxController: receives Vfx / VfxReliable packets, validates them and renders each one through
-- VfxLibrary inside a fresh Trove destroyed after a fixed lifetime.
--
-- It no longer owns any camera work. Camera shake, hit-stop, field of view, hit flashes and damage
-- numbers all belong to Feel now, so there is exactly one owner of the camera and one place the numbers
-- live (Config/FeelConfig). What is left here is what this module was always for: deciding whether a
-- packet is trustworthy and handing it to the right renderer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)
local VfxConfig = require(Shared.Config.VfxConfig)
-- WaitForChild: a sibling module may not have been copied into PlayerScripts yet.
local VfxLibrary = require(script.Parent:WaitForChild("VfxLibrary"))

local log = Log.new("VfxController")

type Deps = { RemoteClient: any, ClientData: any, SoundController: any, Feel: any, VfxTimeline: any }

-- Every packet trove is destroyed after this delay (VfxLibrary effects fit inside it).
local TROVE_LIFETIME_SECONDS = GameConfig.Vfx.LifetimeSeconds
local FALLBACK_COLOR = Color3.fromRGB(255, 245, 220)

local VfxController = {}

-- Fired when the Cast packet of the LOCAL player arrives: the one moment the client knows the server
-- accepted a sequence, with the length of the chain the server counted (GlyphService). The HUD's chain
-- counter reads it instead of the client's own resolution, which counted casts the server then refused
-- for a cooldown or for ink and left the player looking at a number they had not earned.
VfxController.LocalCast = Signal.new() -- (glyphId: string, chain: number)
local CAST_ID = "Cast"

local remoteClient: any
local soundController: any
local feel: any
local timeline: any

local unknownIds: { [string]: boolean } = {}
local malformedWarned = false

local function localCharacter(): Model?
	return Players.LocalPlayer.Character
end

local function pigmentColor(pigment: string): Color3
	local rgb = PigmentConfig.Colors[pigment :: any]
	if rgb == nil then
		return FALLBACK_COLOR
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- The character of a player by user id, for effects that adorn the person rather than a point in space.
-- nil for user id 0, which is how the server writes "a training dummy or an enemy, with nobody behind
-- it", and nil for a player who has left or has not respawned.
local function characterOf(userId: number): Model?
	if userId == 0 then
		return nil
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil then
		return nil
	end
	return target.Character
end

local api: VfxLibrary.Api = {
	Sound = nil :: any,
	PigmentColor = pigmentColor,
	LocalCharacter = localCharacter,
	Feel = nil :: any,
	Timeline = nil :: any,
	LocalUserId = Players.LocalPlayer.UserId,
	CharacterOf = characterOf,
}

local function warnMalformed(reason: string)
	if malformedWarned then
		return
	end
	malformedWarned = true
	log.warn("malformed vfx packet dropped (%s); further malformed packets are dropped silently", reason)
end

local function isValid(packet: any): boolean
	if type(packet) ~= "table" then
		warnMalformed("packet is " .. typeof(packet))
		return false
	end
	if type(packet.Id) ~= "string" then
		warnMalformed("Id is " .. typeof(packet.Id))
		return false
	end
	if typeof(packet.Origin) ~= "Vector3" then
		warnMalformed("Origin is " .. typeof(packet.Origin))
		return false
	end
	if packet.Direction ~= nil and typeof(packet.Direction) ~= "Vector3" then
		warnMalformed("Direction is " .. typeof(packet.Direction))
		return false
	end
	if packet.Caster ~= nil and type(packet.Caster) ~= "number" then
		warnMalformed("Caster is " .. typeof(packet.Caster))
		return false
	end
	if packet.Targets ~= nil and type(packet.Targets) ~= "table" then
		warnMalformed("Targets is " .. typeof(packet.Targets))
		return false
	end
	if packet.Params ~= nil and type(packet.Params) ~= "table" then
		warnMalformed("Params is " .. typeof(packet.Params))
		return false
	end
	return true
end

local function onPacket(packet: any)
	if not isValid(packet) then
		return
	end
	local typed = packet :: VfxLibrary.Packet
	local effect = VfxLibrary[typed.Id]
	if effect == nil then
		if not unknownIds[typed.Id] then
			unknownIds[typed.Id] = true
			log.warn("unknown vfx id %s", typed.Id)
		end
		return
	end

	if typed.Id == CAST_ID and typed.Caster == api.LocalUserId then
		local params = typed.Params
		local glyphId = if type(params) == "table" and type(params.GlyphId) == "string" then params.GlyphId else ""
		local chain = if type(params) == "table" and type(params.Chain) == "number" then params.Chain else 1
		VfxController.LocalCast:Fire(glyphId, math.max(1, math.floor(chain)))
	end

	local trove = Trove.new()
	task.delay(TROVE_LIFETIME_SECONDS, function()
		trove:Destroy()
	end)
	if not log.try("vfx " .. typed.Id, effect, typed, trove, api) then
		trove:Destroy()
	end
end

function VfxController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	soundController = deps.SoundController
	feel = deps.Feel
	timeline = deps.VfxTimeline
	api.Sound = soundController
	api.Feel = feel
	api.Timeline = timeline
end

-- Every declared effect id must have a renderer: a missing one would silently drop its packets.
-- tests/EffectCoverage.spec.luau fails the build for the same thing, so this only catches a renderer
-- removed at runtime, which should never happen and is worth a line in the log if it does.
local function auditRenderers()
	local missing: { string } = {}
	for _, id in ipairs(VfxConfig.Ids) do
		if VfxLibrary[id] == nil then
			table.insert(missing, id)
		end
	end
	if #missing > 0 then
		log.warn("no renderer for %d declared effect id(s): %s", #missing, table.concat(missing, ", "))
	end
end

function VfxController.Start()
	auditRenderers()
	remoteClient.on("Vfx", onPacket)
	remoteClient.on("VfxReliable", onPacket)
	log.info("started")
end

return VfxController
