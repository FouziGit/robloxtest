--!strict
-- SoundController: SFX (2D or 3D) and looping music from SoundConfig, scaled by the player's volume
-- settings. Temporary sounds are removed on Ended with a Debris safety net; music lives for the session.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local SoundConfig = require(Shared.Config.SoundConfig)

local log = Log.new("SoundController")

local SFX_LIFETIME_SECONDS = 6 -- safety net when Ended never fires (invalid asset id)
local EMITTER_FOLDER_NAME = "ClientSfx"
local EMITTER_SIZE = Vector3.one * 0.2
local ROLLOFF_MIN_STUDS = 10
local ROLLOFF_MAX_STUDS = 150
local HUB_MUSIC_ID = "Hub"

type Deps = { ClientData: any }

local SoundController = {}

local clientData: any
local emitterFolder: Folder? = nil
local music: Sound? = nil
local musicId: string? = nil
local musicEntry: SoundConfig.SoundEntry? = nil

local function sfxVolume(): number
	local data = clientData.get()
	if data == nil then
		return 1
	end
	return data.Settings.SfxVolume
end

local function musicVolume(): number
	local data = clientData.get()
	if data == nil then
		return 1
	end
	return data.Settings.MusicVolume
end

local function build(entry: SoundConfig.SoundEntry, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = entry.Id
	sound.Volume = entry.Volume * volume
	sound.PlaybackSpeed = entry.Speed
	return sound
end

local function getEmitterFolder(): Folder
	local existing = emitterFolder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = EMITTER_FOLDER_NAME
	folder.Parent = Workspace
	emitterFolder = folder
	return folder
end

-- Plays a one-shot SFX. With `position` the sound is 3D (short-lived anchored emitter part), otherwise 2D.
function SoundController.play(sfxId: string, position: Vector3?)
	local entry = SoundConfig.Sfx[sfxId]
	if entry == nil then
		log.warn("unknown sfx %s", tostring(sfxId))
		return
	end
	if entry.Id == "" then
		return
	end

	local sound = build(entry, sfxVolume())
	sound.Name = sfxId

	local holder: Instance
	if position ~= nil then
		local emitter = Instance.new("Part")
		emitter.Name = sfxId
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.CastShadow = false
		emitter.Transparency = 1
		emitter.Size = EMITTER_SIZE
		emitter.CFrame = CFrame.new(position)
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = ROLLOFF_MIN_STUDS
		sound.RollOffMaxDistance = ROLLOFF_MAX_STUDS
		sound.Parent = emitter
		emitter.Parent = getEmitterFolder()
		holder = emitter
	else
		sound.Parent = SoundService
		holder = sound
	end

	Debris:AddItem(holder, SFX_LIFETIME_SECONDS)
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
end

-- Switches the looping music track. An entry with an empty Id means silence.
function SoundController.music(id: string)
	local entry = SoundConfig.Music[id]
	if entry == nil then
		log.warn("unknown music %s", tostring(id))
		return
	end
	if musicId == id then
		return
	end

	local current = music
	if current ~= nil then
		current:Destroy()
		music = nil
	end
	musicId = id
	musicEntry = entry
	if entry.Id == "" then
		return
	end

	local sound = build(entry, musicVolume())
	sound.Name = "Music_" .. id
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()
	music = sound
end

local function applyVolumes()
	local current = music
	local entry = musicEntry
	if current ~= nil and entry ~= nil then
		current.Volume = entry.Volume * musicVolume()
	end
end

function SoundController.Init(deps: Deps)
	clientData = deps.ClientData
end

function SoundController.Start()
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Settings" then
			applyVolumes()
		end
	end)
	SoundController.music(HUB_MUSIC_ID)
	log.info("started")
end

return SoundController
