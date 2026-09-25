--!strict
-- VfxLab (client): look at a glyph's effect frame by frame, in Studio only (D-118).
--
-- Never part of the published game: it lives in tools/vfxlab/, outside default.project.json, and is put in a
-- place only by tools/vfxlab/vfxlab.project.json (or injected into an open Studio place); and it returns
-- at once anywhere but Studio. It drives the real game: the real CastGlyph remote, the real packets, the
-- real renderers. What it adds is time: effect time (VfxClock) slowed and stopped at an exact instant, the
-- server's packets held until effect time reaches the moment they would have arrived at, the local body's
-- animation held with it, the quality tier pinned, and three cameras.
--
-- Driven through a BindableFunction, ReplicatedStorage.VfxLab, so the Studio MCP (or the command bar) can
-- call it: VfxLab:Invoke(command, args). Commands:
--   aim     { dummy = 1..6, distance = studs }   stand facing a training dummy
--   shoot   { glyph = "Brand", moment = "depart" | "travel" | "cast" | "impact" | ..., offset = s? }
--           casts the glyph and stops effect time at the moment; returns what it measured
--   view    { name = "game" | "side" | "impact" }   moves the camera while stopped
--   resume  {}                                   lets time run again and gives the camera back
--   status  {}                                   what is live, and the current times
-- Moments: "cast" (the Cast packet), "depart" (the glyph acts: its Anticipation + Cast), "travel" (0.1 s
-- after departing), "impact" (its burst or first hit), "impact+0.1", "impact+0.3", "end" (1.2 s after the
-- impact); `offset` adds seconds to any of them.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local VfxTimelineConfig = require(Shared.Config.VfxTimelineConfig)

local scripts = script.Parent
local controllers = scripts:WaitForChild("Controllers")
local RemoteClient = require(scripts:WaitForChild("RemoteClient"))
local VfxClock = require(controllers:WaitForChild("VfxClock"))
local VfxController = require(controllers:WaitForChild("VfxController"))

local player = Players.LocalPlayer

local TIME_ATTRIBUTE = VfxClock.LabAttribute
local QUALITY_ATTRIBUTE = "VfxLabQuality"
-- Effect-time seconds before a target at which the clock slows, so a Studio frame of up to a fifteenth of
-- a second real time is under a hundredth of effect time when it lands.
local APPROACH = 0.15
local SLOW = 0.1
local TIMEOUT = 12
local END_AFTER = 1.2

type Times = { Cast: number?, Glyph: number?, Impact: number?, ImpactPoint: Vector3? }

local times: Times = {}
local watching: string? = nil
local target: number? = nil
local stoppedAt: number? = nil
local cameraName: string? = nil
local heldTracks: { [AnimationTrack]: number } = {}
local aimed: { Caster: Vector3, Dummy: Vector3 }? = nil

local function root(): BasePart?
	local character = player.Character
	local part = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if part ~= nil and part:IsA("BasePart") then part else nil
end

local function dummies(): { Model }
	local out = {}
	for _, model in ipairs(CollectionService:GetTagged(GameConfig.Enemy.Tag)) do
		if model:IsA("Model") and model:IsDescendantOf(Workspace) then
			table.insert(out, model)
		end
	end
	table.sort(out, function(a: Model, b: Model)
		local pa, pb = a:GetPivot().Position, b:GetPivot().Position
		return math.atan2(pa.Z, pa.X) < math.atan2(pb.Z, pb.X)
	end)
	return out
end

-- When the glyph acts after its packet: its timeline's Anticipation and Cast.
local function releaseOf(glyphId: string): number
	local def = GlyphConfig.byId(glyphId)
	local timeline = if def ~= nil then VfxTimelineConfig.Timelines[def.VfxId] else nil
	local seconds = 0
	for _, phase in ipairs(if timeline ~= nil then timeline.Phases else {}) do
		if phase.Name == "Anticipation" or phase.Name == "Cast" then
			seconds += phase.Duration
		end
	end
	return seconds
end

-- The animation of the local body runs on effect time too, while the lab runs.
local function scaleAnimation(scale: number)
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator == nil then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if heldTracks[track] == nil then
			heldTracks[track] = track.Speed
		end
		track:AdjustSpeed(heldTracks[track] * scale)
	end
end

local function releaseAnimation()
	for track, speed in pairs(heldTracks) do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
	table.clear(heldTracks)
end

local function setScale(scale: number?)
	ReplicatedStorage:SetAttribute(TIME_ATTRIBUTE, scale)
	if scale ~= nil then
		scaleAnimation(scale)
	end
end

local function targetFor(moment: string, offset: number): number?
	local cast, glyph, impact = times.Cast, times.Glyph, times.Impact
	if moment == "cast" then
		return if cast ~= nil then cast + offset else nil
	elseif moment == "depart" or moment == "travel" then
		if glyph == nil or watching == nil then
			return nil
		end
		return glyph + releaseOf(watching) + (if moment == "travel" then 0.1 else 0) + offset
	elseif impact == nil then
		return nil
	elseif moment == "impact" then
		return impact + offset
	elseif moment == "impact+0.1" then
		return impact + 0.1 + offset
	elseif moment == "impact+0.3" then
		return impact + 0.3 + offset
	elseif moment == "end" then
		return impact + END_AFTER + offset
	end
	return nil
end

-- The three cameras, written after everything else each frame while the lab holds the view.
local function cameraFor(name: string): CFrame?
	local here = aimed
	if name == "game" or here == nil then
		return nil
	end
	local caster, dummy = here.Caster, here.Dummy
	local along = (dummy - caster) * Vector3.new(1, 0, 1)
	local forward = if along.Magnitude > 1e-3 then along.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	if name == "side" then
		-- Square to the throw, far enough to hold the caster and the dummy both.
		local middle = (caster + dummy) / 2
		local span = (dummy - caster).Magnitude
		return CFrame.lookAt(middle + right * (span * 0.75 + 4) + Vector3.new(0, 2, 0), middle)
	end
	-- Close on the impact, from the thrower's side and a little above: where the burst is judged.
	local point = times.ImpactPoint or dummy
	return CFrame.lookAt(point - forward * 7 + right * 4 + Vector3.new(0, 3, 0), point + Vector3.new(0, 0.5, 0))
end

RunService:BindToRenderStep("VfxLabCamera", Enum.RenderPriority.Last.Value, function()
	local name = cameraName
	local camera = Workspace.CurrentCamera
	if name == nil or camera == nil then
		return
	end
	local frame = cameraFor(name)
	if frame ~= nil then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = frame
	end
end)

RunService:BindToRenderStep("VfxLabClock", Enum.RenderPriority.First.Value, function()
	local goal = target
	if goal == nil or stoppedAt ~= nil then
		return
	end
	-- A clip started while time is slowed (the cast's own animation, played on the Cast packet) is slowed
	-- with it.
	local scale = ReplicatedStorage:GetAttribute(TIME_ATTRIBUTE)
	if type(scale) == "number" and scale ~= 1 then
		scaleAnimation(scale)
	end
	local now = VfxClock.now()
	if now >= goal then
		setScale(0)
		stoppedAt = VfxClock.now()
	elseif goal - now <= APPROACH and ReplicatedStorage:GetAttribute(TIME_ATTRIBUTE) ~= SLOW then
		setScale(SLOW)
	end
end)

VfxController.Acted:Connect(function(id: string, caster: number, params: { [string]: any }?)
	local glyph = watching
	if glyph == nil or caster ~= player.UserId then
		return
	end
	local now = VfxClock.now()
	if id == "Cast" and times.Cast == nil then
		times.Cast = now
	elseif id == glyph and times.Glyph == nil then
		times.Glyph = now
	elseif (id == "Explosion" or id == "Hit") and times.Impact == nil then
		times.Impact = now
		local victim = if type(params) == "table" then params.Victim else nil
		if typeof(victim) == "Instance" and victim:IsA("Model") then
			times.ImpactPoint = victim:GetPivot().Position
		end
	end
end)

local function aim(args: { [string]: any }): { [string]: any }
	local list = dummies()
	local index = math.clamp(math.floor(tonumber(args.dummy) or 1), 1, math.max(#list, 1))
	local dummy: Model? = list[index]
	local body = root()
	if dummy == nil or body == nil then
		return { ok = false, why = "no dummy or no character" }
	end
	local distance = tonumber(args.distance) or 16
	local at = dummy:GetPivot().Position
	local centre = Vector3.new(0, at.Y, 0)
	local inward = (centre - at) * Vector3.new(1, 0, 1)
	local direction = if inward.Magnitude > 1e-3 then inward.Unit else Vector3.new(-1, 0, 0)
	local stand = Vector3.new(at.X, body.Position.Y, at.Z) + direction * distance
	body.AssemblyLinearVelocity = Vector3.zero
	body.CFrame = CFrame.lookAt(stand, Vector3.new(at.X, body.Position.Y, at.Z))
	aimed = { Caster = stand, Dummy = at }
	-- The game's own camera, put where a player throwing at the dummy has it: behind, a little above, at
	-- the default zoom. It stays the game's camera; only its starting place is set.
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
		-- The body faces the dummy, back along `direction`: behind it is further along `direction`.
		camera.CFrame = CFrame.lookAt(stand + direction * 11 + Vector3.new(0, 5, 0), stand - direction * 6)
	end
	return { ok = true, dummy = index, caster = tostring(stand), target = tostring(at) }
end

local function shoot(args: { [string]: any }): { [string]: any }
	local glyphId = tostring(args.glyph or "")
	local def = GlyphConfig.byId(glyphId)
	if def == nil then
		return { ok = false, why = "no glyph " .. glyphId }
	end
	local moment = tostring(args.moment or "depart")
	local offset = tonumber(args.offset) or 0
	ReplicatedStorage:SetAttribute(QUALITY_ATTRIBUTE, args.quality or "High")
	-- A fresh epoch: time runs at real speed until the approach of the moment.
	setScale(nil)
	releaseAnimation()
	cameraName = nil
	times = {}
	stoppedAt = nil
	target = nil
	watching = glyphId
	setScale(1)
	RemoteClient.fire("CastGlyph", def.Combo)
	local started = os.clock()
	while stoppedAt == nil and os.clock() - started < TIMEOUT do
		if target == nil then
			target = targetFor(moment, offset)
		end
		task.wait()
	end
	return {
		ok = stoppedAt ~= nil,
		glyph = glyphId,
		moment = moment,
		cast = times.Cast,
		glyphAt = if times.Glyph ~= nil and times.Cast ~= nil then times.Glyph - times.Cast else nil,
		impactAt = if times.Impact ~= nil and times.Cast ~= nil then times.Impact - times.Cast else nil,
		stoppedAt = if stoppedAt ~= nil and times.Cast ~= nil then stoppedAt - times.Cast else nil,
		target = if target ~= nil and times.Cast ~= nil then target - times.Cast else nil,
		why = if stoppedAt == nil then "the moment never came (refused cast, cooldown, or no impact)" else nil,
	}
end

local function resume(): { [string]: any }
	cameraName = nil
	target = nil
	stoppedAt = nil
	watching = nil
	setScale(nil)
	releaseAnimation()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
	end
	return { ok = true }
end

local bindable = ReplicatedStorage:FindFirstChild("VfxLab") or Instance.new("BindableFunction")
bindable.Name = "VfxLab"
bindable.Parent = ReplicatedStorage;
(bindable :: BindableFunction).OnInvoke = function(command: string, args: { [string]: any }?)
	local given: { [string]: any } = args or {}
	if command == "aim" then
		return aim(given)
	elseif command == "shoot" then
		return shoot(given)
	elseif command == "view" then
		cameraName = tostring(given.name or "game")
		return { ok = true, view = cameraName }
	elseif command == "resume" then
		return resume()
	elseif command == "status" then
		return {
			scale = ReplicatedStorage:GetAttribute(TIME_ATTRIBUTE),
			quality = ReplicatedStorage:GetAttribute(QUALITY_ATTRIBUTE),
			now = VfxClock.now(),
			dummies = #dummies(),
		}
	end
	return { ok = false, why = "unknown command " .. tostring(command) }
end

player.CharacterRemoving:Connect(resume)
