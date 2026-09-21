--!strict
-- SoundController: every sound the client plays, from SoundConfig, through two SoundGroups.
--
-- Two groups because the plan asks for one thing that only a group can do: ducking. A heavy impact
-- pulls the music down for a moment and lets it back up, and that is a volume on the Music group, not on
-- a Sound -- the loop keeps playing at its own volume, the group is what dips. The player's two sliders
-- are group volumes too, so a change applies to every sound already in the air.
--
-- Pitch wanders. Every effect entry carries a Vary, and each play lands somewhere inside Speed +/- Vary,
-- so two casts of the same glyph are never the same sound. Five percent is the number from
-- docs/JUICE_PLAN.md and it is deliberately small: enough to stop the ear noticing a repeat, not enough
-- to change what the sound is.
--
-- A sound whose file has not been uploaded is not played, and the list of them is said once at startup.
-- There is no fallback. What was here before was the engine's own ping at nine speeds.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local SoundConfig = require(Shared.Config.SoundConfig)

local log = Log.new("SoundController")

-- Safety net when Ended never fires (an id that does not resolve). The longest effect is under three
-- seconds; a boss warning stretched to a two-second window is the longest anything is asked to fit.
local SFX_LIFETIME_SECONDS = 6
local EMITTER_FOLDER_NAME = "ClientSfx"
local EMITTER_SIZE = Vector3.one * 0.2
local ROLLOFF_MIN_STUDS = 10
local ROLLOFF_MAX_STUDS = 150
local HUB_MUSIC_ID = "Hub"
-- A fitted sound is stretched by PlaybackSpeed. Past these the pitch is a different sound: a warning
-- asked to fit a tenth of a second would be a chirp, and one asked to fit ten seconds a groan.
local FIT_SPEED_MIN = 0.5
local FIT_SPEED_MAX = 4
-- Ducking: how far the music drops under a heavy impact, how long the dip is held before it starts
-- back, and the curve it comes back on. The drop is immediate and the return is eased, because a dip
-- that returns as fast as it fell reads as a glitch in the music rather than as the impact having weight.
local DUCK_VOLUME = 0.35
local DUCK_HOLD_SECONDS = 0.04
local DUCK_OUT_STYLE = Enum.EasingStyle.Quad
local DUCK_OUT_DIRECTION = Enum.EasingDirection.Out

-- Who is asking for music, highest first. A ranked match and the Erasure can overlap on one server,
-- and a duelist must not lose the match loop because a boss was announced in the hub: the loop that
-- plays is the highest source that has asked for one, and the hub is what plays when nobody has.
local MUSIC_SOURCES = { "Match", "Boss" }

export type PlayOptions = {
	-- Multiplies the entry's speed, on top of the wander: the sequence's notes climb a scale with it.
	Pitch: number?,
	-- Seconds the sound has to last. The speed is set so the file ends exactly then, within the clamps.
	Fit: number?,
	-- A part to play from instead of a fixed point: the sound moves with it. A projectile's tail heard
	-- from the launch point is a tail that stayed behind.
	Anchor: BasePart?,
}

type Deps = { ClientData: any }

local SoundController = {}

local clientData: any
local emitterFolder: Folder? = nil
local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local music: Sound? = nil
local musicId: string? = nil
local musicWanted: { [string]: string? } = {}
local duckUntil = 0
local duckTween: Tween? = nil
local random = Random.new()

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

-- The speed a play lands at: the entry's, wandered by its Vary, multiplied by the caller's pitch, or
-- replaced outright by whatever makes the file fit a window.
local function speedFor(entry: SoundConfig.SoundEntry, options: PlayOptions?): number
	local fit = if options ~= nil then options.Fit else nil
	if fit ~= nil and fit > 0 and entry.Seconds > 0 then
		return math.clamp(entry.Seconds / fit, FIT_SPEED_MIN, FIT_SPEED_MAX)
	end
	local speed = 1
	if entry.Vary > 0 then
		speed *= 1 + random:NextNumber(-entry.Vary, entry.Vary)
	end
	local pitch = if options ~= nil then options.Pitch else nil
	if pitch ~= nil and pitch > 0 then
		speed *= pitch
	end
	return speed
end

-- Plays a one-shot effect. With `position` the sound is 3D, on a short-lived anchored emitter part;
-- without, it is 2D. Unknown keys warn -- a typo in a timeline is worth hearing about -- and an entry
-- with no id yet is silently not played, because that was already said once at startup.
function SoundController.play(sfxId: string, position: Vector3?, options: PlayOptions?)
	local entry = SoundConfig.Sfx[sfxId]
	if entry == nil then
		log.warn("unknown sfx %s", tostring(sfxId))
		return
	end
	if entry.Id == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = sfxId
	sound.SoundId = entry.Id
	sound.Volume = entry.Volume
	sound.PlaybackSpeed = speedFor(entry, options)
	sound.SoundGroup = sfxGroup

	local holder: Instance
	local anchor = if options ~= nil then options.Anchor else nil
	if anchor ~= nil and anchor.Parent ~= nil then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = ROLLOFF_MIN_STUDS
		sound.RollOffMaxDistance = ROLLOFF_MAX_STUDS
		sound.Parent = anchor
		holder = sound
	elseif position ~= nil then
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

-- Starts (or restarts) the return from a dip, toward whatever the player's music volume is now, over
-- what is left of the duck. One place builds the tween, so a slider moved mid-duck and a second impact
-- mid-duck both end at the right volume.
local function releaseDuck()
	local tween = duckTween
	if tween ~= nil then
		tween:Cancel()
	end
	local remaining = duckUntil - os.clock()
	if remaining <= 0 then
		duckTween = nil
		musicGroup.Volume = musicVolume()
		return
	end
	local release = TweenService:Create(
		musicGroup,
		TweenInfo.new(remaining, DUCK_OUT_STYLE, DUCK_OUT_DIRECTION, 0, false, DUCK_HOLD_SECONDS),
		{ Volume = musicVolume() }
	)
	duckTween = release
	release:Play()
end

-- Pulls the music down for `seconds` and eases it back. Every heavy impact dips, even one landing in the
-- tail of a longer duck; overlapping ducks extend the return rather than stacking depth.
function SoundController.duck(seconds: number)
	if seconds <= 0 then
		return
	end
	duckUntil = math.max(duckUntil, os.clock() + DUCK_HOLD_SECONDS + seconds)
	musicGroup.Volume = musicVolume() * DUCK_VOLUME
	releaseDuck()
end

-- Plays the loop `id`, replacing whatever plays. An entry with no id yet means silence, said once at
-- startup. Not public: a caller says what it WANTS through SoundController.wantMusic, and the highest
-- source decides.
local function switchMusic(id: string)
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
	if entry.Id == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. id
	sound.SoundId = entry.Id
	sound.Volume = entry.Volume
	sound.Looped = true
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	sound:Play()
	music = sound
end

-- What plays: the highest source that wants a loop, or the hub. Match outranks Boss, because a player
-- in a ranked match is in the match; everyone else hears the event.
local function resolveMusic()
	for _, source in ipairs(MUSIC_SOURCES) do
		-- Typed optional explicitly: Luau reads a table index as non-optional, and the nil guard below
		-- would otherwise be dead to the analyser.
		local wanted: string? = musicWanted[source]
		if wanted ~= nil then
			switchMusic(wanted)
			return
		end
	end
	switchMusic(HUB_MUSIC_ID)
end

-- `source` (Match or Boss) asks for loop `id`, or withdraws with nil. Two systems can want music at once
-- and neither has to know about the other.
function SoundController.wantMusic(source: string, id: string?)
	musicWanted[source] = id
	resolveMusic()
end

local function applyVolumes()
	sfxGroup.Volume = sfxVolume()
	if os.clock() < duckUntil then
		-- Mid-duck: rebuild the return toward the new volume instead of snapping the music up under the
		-- impact, or leaving the old target in the tween.
		releaseDuck()
	else
		musicGroup.Volume = musicVolume()
	end
end

function SoundController.Init(deps: Deps)
	clientData = deps.ClientData
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "Sfx"
	sfxGroup.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Parent = SoundService
end

function SoundController.Start()
	applyVolumes()
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Settings" then
			applyVolumes()
		end
	end)
	local missing = SoundConfig.missing()
	if #missing > 0 then
		log.warn(
			"%d sound(s) not uploaded yet, they are silent until they are (docs/STUDIO_SETUP.md §8): %s",
			#missing,
			table.concat(missing, ", ")
		)
	end
	resolveMusic()
	log.info("started")
end

return SoundController
