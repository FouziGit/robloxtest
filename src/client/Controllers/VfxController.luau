--!strict
-- VfxController: receives Vfx / VfxReliable packets, validates them and renders each one through
-- VfxLibrary inside a fresh Trove destroyed after a fixed lifetime. Owns the client-side juice the
-- effects call through `api`: camera shake (Humanoid.CameraOffset jitter, honouring Settings.CameraShake)
-- and hit-stop (a short FieldOfView pulse — WalkSpeed is server-owned and never touched).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local ElementConfig = require(Shared.Config.ElementConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Trove = require(Packages.Trove)
local VfxConfig = require(Shared.Config.VfxConfig)
local VfxLibrary = require(script.Parent.VfxLibrary)

local log = Log.new("VfxController")

type Deps = { RemoteClient: any, ClientData: any, SoundController: any }

-- Every packet trove is destroyed after this delay (VfxLibrary effects fit inside it).
local TROVE_LIFETIME_SECONDS = GameConfig.Vfx.LifetimeSeconds
local SHAKE_SECONDS = 0.25
local HIT_STOP_FOV_DELTA = 6
local HIT_STOP_RELEASE_FACTOR = 2 -- the FOV returns over twice the pulse duration
local FALLBACK_COLOR = Color3.fromRGB(255, 245, 220)

local VfxController = {}

local remoteClient: any
local clientData: any
local soundController: any

local unknownIds: { [string]: boolean } = {}
local malformedWarned = false

local shakeRemaining = 0
local shakeIntensity = 0
local shakeConnection: RBXScriptConnection? = nil
local hitStopActive = false

local function localCharacter(): Model?
	return Players.LocalPlayer.Character
end

local function localHumanoid(): Humanoid?
	local character = localCharacter()
	if character == nil then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function shakeEnabled(): boolean
	local data = clientData.get()
	if data == nil then
		return true
	end
	return data.Settings.CameraShake ~= false
end

local function stopShake()
	local connection = shakeConnection
	shakeConnection = nil
	if connection ~= nil then
		connection:Disconnect()
	end
	shakeRemaining = 0
	shakeIntensity = 0
	local humanoid = localHumanoid()
	if humanoid ~= nil then
		humanoid.CameraOffset = Vector3.zero
	end
end

local function stepShake(deltaTime: number)
	shakeRemaining -= deltaTime
	local humanoid = localHumanoid()
	if shakeRemaining <= 0 or humanoid == nil then
		stopShake()
		return
	end
	local strength = shakeIntensity * (shakeRemaining / SHAKE_SECONDS)
	humanoid.CameraOffset = Vector3.new((math.random() * 2 - 1) * strength, (math.random() * 2 - 1) * strength, 0)
end

-- Jitters the camera for SHAKE_SECONDS; a stronger shake replaces a weaker one in progress.
local function shake(intensity: number)
	if intensity <= 0 or not shakeEnabled() or localHumanoid() == nil then
		return
	end
	shakeIntensity = math.max(shakeIntensity, intensity)
	shakeRemaining = SHAKE_SECONDS
	if shakeConnection == nil then
		shakeConnection = RunService.RenderStepped:Connect(stepShake)
	end
end

-- Brief FieldOfView pulse. Never overlaps itself so the base FOV is always restored.
local function hitStop(seconds: number)
	if hitStopActive or seconds <= 0 then
		return
	end
	local camera: Camera? = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	hitStopActive = true
	local baseFov = camera.FieldOfView
	local pulseIn = TweenService:Create(
		camera,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov - HIT_STOP_FOV_DELTA }
	)
	pulseIn:Play()
	task.delay(seconds, function()
		local releaseSeconds = seconds * HIT_STOP_RELEASE_FACTOR
		TweenService:Create(
			camera,
			TweenInfo.new(releaseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = baseFov }
		):Play()
		task.delay(releaseSeconds, function()
			hitStopActive = false
		end)
	end)
end

local function elementColor(element: string): Color3
	local rgb = ElementConfig.Colors[element :: any]
	if rgb == nil then
		return FALLBACK_COLOR
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local api: VfxLibrary.Api = {
	Sound = nil :: any,
	Shake = shake,
	HitStop = hitStop,
	ElementColor = elementColor,
	LocalCharacter = localCharacter,
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
	clientData = deps.ClientData
	soundController = deps.SoundController
	api.Sound = soundController
end

-- Every declared effect id must have a renderer: a missing one would silently drop its packets.
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
	Players.LocalPlayer.CharacterRemoving:Connect(stopShake)
	log.info("started")
end

return VfxController
