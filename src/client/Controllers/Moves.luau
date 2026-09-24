--!strict
-- Moves: the local character plays real animation clips for what it does.
--
-- The clips are CC0 motion retargeted onto R15, and casts keyed by hand for their glyph
-- (Config/AnimationConfig, tools/animations/). They are played here through the character's own
-- Animator, and only on the LOCAL character: Roblox replicates an animation a client plays on its own
-- character to the server and to every other client, so each player's client animating its own body is
-- what makes everyone see everyone move. Playing another player's character from here would be seen by
-- nobody but this client.
--
-- An action with no uploaded clip is left to Posture's procedural pose, and an action WITH one is left
-- entirely to this file: both read AnimationConfig.clipFor (castClip for a cast, which a glyph may have
-- its own of), so the two never move the same body for the same action.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local AnimationConfig = require(Shared.Config.AnimationConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local Log = require(Shared.Util.Log)

local log = Log.new("Moves")

type Deps = { VfxController: any }

local Moves = {}

local player = Players.LocalPlayer
local vfxController: any
local animator: Animator? = nil
-- Loaded tracks by clip name, for the current character only; a respawn builds a new Animator.
local tracks: { [string]: AnimationTrack } = {}
-- The strike or cast currently playing, stopped when the next one starts: two of them at the same
-- priority would be blended into a pose that is neither.
local current: AnimationTrack? = nil
-- Clip ids that failed to load, reported once each.
local failed: { [string]: boolean } = {}

-- A cross-fade short enough that a chain of hits does not blur into one another.
local FADE_SECONDS = 0.06
-- The guard lowers a little slower than a strike leaves, so letting go reads as a choice.
local GUARD_FADE_SECONDS = 0.12
local GUARD_ATTRIBUTE = CombatConfig.Status.BlockAttribute

-- The guard attribute's connection on the current character.
local guardConnection: RBXScriptConnection? = nil

local function trackFor(name: string, clip: AnimationConfig.Clip): AnimationTrack?
	local existing: AnimationTrack? = tracks[name]
	if existing ~= nil then
		return existing
	end
	local target = animator
	if target == nil then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = clip.Id
	local ok, result = pcall(function()
		return target:LoadAnimation(animation)
	end)
	if not ok then
		if not failed[clip.Id] then
			failed[clip.Id] = true
			log.warn("could not load clip %s (%s): %s", name, clip.Id, tostring(result))
		end
		return nil
	end
	local track = result :: AnimationTrack
	track.Looped = clip.Looped
	local priority = (Enum.AnimationPriority :: any)[clip.Priority]
	if typeof(priority) == "EnumItem" then
		track.Priority = priority :: Enum.AnimationPriority
	end
	tracks[name] = track
	return track
end

local function nameOf(action: string, index: number?): string?
	local names = AnimationConfig.Actions[action]
	return if names ~= nil then names[index or 1] else nil
end

-- Plays `clip`. A blow -- a strike or a cast -- replaces the one before it; a flinch plays over it.
local function start(name: string, clip: AnimationConfig.Clip, blow: boolean)
	local track = trackFor(name, clip)
	if track == nil then
		return
	end
	if blow and current ~= nil and current ~= track then
		current:Stop(FADE_SECONDS)
	end
	track:Play(FADE_SECONDS, 1, clip.Speed)
	if clip.Impact > 0 then
		-- Start just before the blow: the damage is already applied, so the fist must arrive with it.
		track.TimePosition = math.max(0, clip.Impact - AnimationConfig.ImpactLeadSeconds)
	end
	if blow then
		current = track
	end
end

local function play(action: string, index: number?)
	local clip = AnimationConfig.clipFor(action, index)
	local name = nameOf(action, index)
	if clip == nil or name == nil then
		return
	end
	start(name, clip, action == "Melee")
end

-- A glyph's cast: its own clip when it has one, the generic cast otherwise (AnimationConfig.castClip).
local function cast(glyphId: string?)
	local name, clip = AnimationConfig.castClip(glyphId)
	if name == nil or clip == nil then
		return
	end
	start(name, clip, true)
end

-- The guard is a state, like in Posture: the loop runs exactly while the attribute is on.
local function setGuard(on: boolean)
	local clip = AnimationConfig.clipFor("Guard")
	local name = nameOf("Guard")
	if clip == nil or name == nil then
		return
	end
	local track = trackFor(name, clip)
	if track == nil then
		return
	end
	if on and not track.IsPlaying then
		if current ~= nil then
			current:Stop(FADE_SECONDS)
			current = nil
		end
		track:Play(FADE_SECONDS, 1, clip.Speed)
	elseif not on and track.IsPlaying then
		track:Stop(GUARD_FADE_SECONDS)
	end
end

local function targetOf(params: { [string]: any }?): number
	if type(params) ~= "table" then
		return 0
	end
	local target = params.Target
	return if type(target) == "number" then target else 0
end

local function glyphOf(params: { [string]: any }?): string?
	if type(params) ~= "table" then
		return nil
	end
	local glyphId = params.GlyphId
	return if type(glyphId) == "string" then glyphId else nil
end

local function onAction(id: string, userId: number, params: { [string]: any }?)
	-- What this player did...
	if userId == player.UserId then
		if id == "Melee" then
			local index = if type(params) == "table" and type(params.Index) == "number" then params.Index else 1
			play("Melee", math.max(1, math.floor(index)))
		elseif id == "Cast" then
			cast(glyphOf(params))
		end
	end
	-- ...and what was done TO them, which the packet names as its target.
	if targetOf(params) == player.UserId then
		if id == "Hit" then
			play("Flinch")
		elseif id == "GuardBreak" then
			setGuard(false)
			play("GuardBreak")
		end
	end
end

local function bind(character: Model)
	tracks = {}
	current = nil
	animator = nil
	if guardConnection ~= nil then
		guardConnection:Disconnect()
		guardConnection = nil
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	local found = humanoid:WaitForChild("Animator", 10)
	if found ~= nil and found:IsA("Animator") then
		animator = found
	end
	local typed = humanoid :: Humanoid
	guardConnection = typed:GetAttributeChangedSignal(GUARD_ATTRIBUTE):Connect(function()
		setGuard(typed:GetAttribute(GUARD_ATTRIBUTE) == true)
	end)
end

function Moves.Init(deps: Deps)
	vfxController = deps.VfxController
end

function Moves.Start()
	vfxController.Acted:Connect(onAction)
	player.CharacterAdded:Connect(bind)
	if player.Character ~= nil then
		task.spawn(bind, player.Character)
	end
	log.info("started")
end

return Moves
