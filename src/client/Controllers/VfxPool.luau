--!strict
-- VfxPool: the instances half of the VFX pool. It owns the Parts, emitters, trails, lights and
-- attachments the renderers draw with, and asks Pure/PoolPolicy what to do with every borrow and every
-- release. Everything that can be decided without an engine lives there; what is left here is the engine.
--
-- Why at all: VfxLibrary builds its instances per effect and destroys them through the effect's trove a
-- few seconds later. In a six-player fight that is hundreds of creations and destructions a minute, and it
-- is what makes a Roblox client hitch a couple of minutes into a session -- not the particles, the churn.
-- docs/JUICE_PLAN.md phase 3: nothing created or destroyed in a loop, one pool per class, reset on borrow,
-- returned through the effect's Trove.
--
-- Reset on BORROW, never on release. An instance handed back with a leftover Color, Size, Transparency or
-- CFrame, an emitter with a leftover Rate, a Trail still Enabled: that is the pooling bug everybody writes
-- once, and it surfaces as one effect wearing the previous effect's colour, which is exactly the failure
-- docs/ART_BIBLE.md rule 2 cannot survive -- a player names the school by colour alone, from behind, at
-- thirty studs. Resetting on the way out means a borrowed instance is blank whatever the last renderer did
-- to it, and whatever crashed halfway through the last effect.
--
-- The reset lists are the union of what this layer writes, not every property of every class: a property
-- nothing ever writes cannot be dirty. A renderer that starts writing a new one adds it here.
--
-- Borrowed with acquire and handed back with release. There was a lease wrapper here that tied a borrow
-- to an effect's Trove; it was removed because nothing used it. VfxTimeline schedules its layers on one
-- Heartbeat and releases each layer's instances when that layer ends, which is a lifetime a Trove does
-- not describe, so the wrapper was an API with no caller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local PoolPolicy = require(Shared.Pure.PoolPolicy)

local log = Log.new("VfxPool")

type PolicyType = typeof(PoolPolicy.new({}))

local VfxPool = {}

-- Parked instances live here rather than under a nil parent: a folder can be opened in the explorer and
-- counted, which is what the phase 9 promise of "a duel leaves no instance behind" is checked against.
-- Out of Workspace, so a parked emitter cannot emit and a parked part cannot render whatever its
-- properties say -- nothing under ReplicatedStorage is drawn or simulated.
local FOLDER_NAME = "VellumVfxPool"

-- Vellum, from docs/ART_BIBLE.md. The blank a borrow hands out has to read as decor rather than as a
-- school: rule 1 says only a glyph is saturated, so the one colour a forgotten pigment may show is the
-- world's own.
local BLANK_COLOR = Color3.fromRGB(232, 224, 206)
local BLANK_COLOR_SEQUENCE = ColorSequence.new(BLANK_COLOR)
local OPAQUE_SEQUENCE = NumberSequence.new(0)
local UNIT_SEQUENCE = NumberSequence.new(1)
local UNIT_RANGE = NumberRange.new(1, 1)
local ZERO_RANGE = NumberRange.new(0, 0)
-- Far below every arena. A borrowed part rests here until its renderer places it, so a renderer that
-- parents before it positions cannot flash a blank through the middle of the fight.
local BLANK_CFRAME = CFrame.new(0, -500, 0)

local player = Players.LocalPlayer

local policy: PolicyType? = nil
local folder: Folder? = nil
-- className -> parked instances, most recently parked last: the stack PoolPolicy's borrow index points
-- into.
local parked: { [string]: { Instance } } = {}
-- Every instance currently out, and what it is. This is the record that lets a release be refused instead
-- of silently accepted.
local owned: { [Instance]: string } = {}

local capacityWarned: { [string]: boolean } = {}
local unknownWarned: { [string]: boolean } = {}
local unownedWarned = false

local function ensureFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

----------------------------------------------------------------
-- Per-class construction and reset
----------------------------------------------------------------

local function resetPart(part: Part)
	part.Name = "Part"
	-- A visual is never physics and never a query result. These are the values every renderer sets on
	-- every part it builds, so they are the baseline rather than the engine's defaults: a pooled part must
	-- not fall, collide or answer a raycast in the frame between the borrow and the renderer's first write.
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = Enum.PartType.Block
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0
	part.Color = BLANK_COLOR
	part.Transparency = 0
	part.Size = Vector3.one
	part.CFrame = BLANK_CFRAME
end

local function resetEmitter(emitter: ParticleEmitter)
	emitter.Name = "ParticleEmitter"
	-- Enabled true and Rate zero: a borrowed emitter emits nothing until its renderer sets a rate, which
	-- is exactly what a fresh one does for a renderer that only sets Rate, and it cannot spray a frame of
	-- the previous effect's particles on the way to being configured.
	emitter.Enabled = true
	emitter.Rate = 0
	emitter.Texture = ""
	emitter.Color = BLANK_COLOR_SEQUENCE
	emitter.Transparency = OPAQUE_SEQUENCE
	emitter.Size = UNIT_SEQUENCE
	emitter.Squash = OPAQUE_SEQUENCE
	emitter.Lifetime = UNIT_RANGE
	emitter.Speed = ZERO_RANGE
	emitter.Rotation = ZERO_RANGE
	emitter.RotSpeed = ZERO_RANGE
	emitter.SpreadAngle = Vector2.zero
	emitter.Acceleration = Vector3.zero
	emitter.Drag = 0
	emitter.VelocityInheritance = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Shape = Enum.ParticleEmitterShape.Box
	-- A leftover flipbook layout slices a plain texture into frames, which reads as a broken effect
	-- rather than as a wrong one. Layout None is what makes the flipbook properties moot.
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	emitter.LightEmission = 0
	emitter.LightInfluence = 0
	emitter.Brightness = 1
	emitter.ZOffset = 0
	emitter.LockedToPart = false
	emitter.TimeScale = 1
end

local function resetTrail(trail: Trail)
	trail.Name = "Trail"
	trail.Enabled = true
	-- Dropped, not kept: the attachments a trail ran between are pooled too and go back separately, and a
	-- trail still holding them would draw across the next effect that borrows them.
	trail.Attachment0 = nil
	trail.Attachment1 = nil
	trail.Color = BLANK_COLOR_SEQUENCE
	trail.Transparency = OPAQUE_SEQUENCE
	trail.WidthScale = UNIT_SEQUENCE
	trail.Lifetime = 1
	trail.FaceCamera = false
	trail.LightEmission = 0
	trail.LightInfluence = 0
	trail.Brightness = 1
	trail.Texture = ""
	trail.TextureLength = 1
	trail.TextureMode = Enum.TextureMode.Stretch
end

local function resetLight(light: PointLight)
	light.Name = "PointLight"
	light.Enabled = true
	light.Brightness = 1
	light.Color = BLANK_COLOR
	light.Range = 8
	-- Shadows are the expensive half of a dynamic light and no effect has asked for them. A leftover
	-- true would cost a renderer that never opted in.
	light.Shadows = false
end

local function resetDecal(decal: Decal)
	decal.Name = "Decal"
	decal.Texture = ""
	decal.Face = Enum.NormalId.Front
	decal.Color3 = BLANK_COLOR
	decal.Transparency = 0
	decal.LocalTransparencyModifier = 0
	decal.ZIndex = 0
end

local function resetBeam(beam: Beam)
	beam.Name = "Beam"
	beam.Enabled = true
	-- Dropped for the same reason a trail's are: the attachments go back to the pool separately, and a
	-- beam still holding them would draw across whatever borrows them next.
	beam.Attachment0 = nil
	beam.Attachment1 = nil
	beam.Color = BLANK_COLOR_SEQUENCE
	beam.Transparency = OPAQUE_SEQUENCE
	beam.Width0 = 1
	beam.Width1 = 1
	-- CurveSize is what bends a beam into a drawn stroke rather than a straight laser. A leftover curve
	-- from the previous effect is the most visible dirty-instance bug this class has.
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Segments = 10
	beam.FaceCamera = false
	beam.LightEmission = 0
	beam.LightInfluence = 0
	beam.Brightness = 1
	beam.Texture = ""
	beam.TextureLength = 1
	beam.TextureSpeed = 1
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.ZOffset = 0
end

local function resetAttachment(attachment: Attachment)
	attachment.Name = "Attachment"
	attachment.CFrame = CFrame.identity
	attachment.Visible = false
end

-- Parked instances are already out of the rendered tree, so these are the second lock: the day somebody
-- parents the pool folder into Workspace to count what is inside, nothing in there emits or draws.
local function mutePart(part: Part)
	part.Transparency = 1
end

local function muteEmitter(emitter: ParticleEmitter)
	emitter.Enabled = false
	emitter.Rate = 0
end

local function muteTrail(trail: Trail)
	trail.Enabled = false
end

local function muteLight(light: PointLight)
	light.Enabled = false
end

local function muteAttachment(attachment: Attachment)
	attachment.Visible = false
end

local function muteDecal(decal: Decal)
	decal.Transparency = 1
end

local function muteBeam(beam: Beam)
	beam.Enabled = false
end

type ClassOps = {
	create: () -> Instance,
	reset: (Instance) -> (),
	mute: (Instance) -> (),
}

-- The classes the VFX layer builds per effect. A class that is not here cannot be pooled, because the
-- pool has no complete reset for it, and acquiring one is refused rather than guessed at.
local CLASSES: { [string]: ClassOps } = {
	Part = {
		create = function(): Instance
			return Instance.new("Part")
		end,
		reset = function(instance: Instance)
			resetPart(instance :: Part)
		end,
		mute = function(instance: Instance)
			mutePart(instance :: Part)
		end,
	},
	ParticleEmitter = {
		create = function(): Instance
			return Instance.new("ParticleEmitter")
		end,
		reset = function(instance: Instance)
			resetEmitter(instance :: ParticleEmitter)
		end,
		mute = function(instance: Instance)
			muteEmitter(instance :: ParticleEmitter)
		end,
	},
	Trail = {
		create = function(): Instance
			return Instance.new("Trail")
		end,
		reset = function(instance: Instance)
			resetTrail(instance :: Trail)
		end,
		mute = function(instance: Instance)
			muteTrail(instance :: Trail)
		end,
	},
	PointLight = {
		create = function(): Instance
			return Instance.new("PointLight")
		end,
		reset = function(instance: Instance)
			resetLight(instance :: PointLight)
		end,
		mute = function(instance: Instance)
			muteLight(instance :: PointLight)
		end,
	},
	Decal = {
		create = function(): Instance
			return Instance.new("Decal")
		end,
		reset = function(instance: Instance)
			resetDecal(instance :: Decal)
		end,
		mute = function(instance: Instance)
			muteDecal(instance :: Decal)
		end,
	},
	Beam = {
		create = function(): Instance
			return Instance.new("Beam")
		end,
		reset = function(instance: Instance)
			resetBeam(instance :: Beam)
		end,
		mute = function(instance: Instance)
			muteBeam(instance :: Beam)
		end,
	},
	Attachment = {
		create = function(): Instance
			return Instance.new("Attachment")
		end,
		reset = function(instance: Instance)
			resetAttachment(instance :: Attachment)
		end,
		mute = function(instance: Instance)
			muteAttachment(instance :: Attachment)
		end,
	},
}

----------------------------------------------------------------
-- Borrow and release
----------------------------------------------------------------

local function getPolicy(): PolicyType
	local existing = policy
	if existing ~= nil then
		return existing
	end
	local created = PoolPolicy.new(PoolPolicy.Limits)
	policy = created
	return created
end

local function stackOf(className: string): { Instance }
	local existing = parked[className]
	if existing ~= nil then
		return existing
	end
	local created: { Instance } = {}
	parked[className] = created
	return created
end

-- Drops parked entries the pool no longer holds, so the policy's parked count and the stack agree before
-- a borrow reads an index out of it. They diverge when something outside the pool destroys a parked
-- instance, or when the folder is rebuilt and takes its children with it.
local function prune(className: string, stack: { Instance }, home: Folder)
	while #stack > 0 do
		local top = stack[#stack]
		if top.Parent == home then
			break
		end
		stack[#stack] = nil
		getPolicy():drop(className)
	end
end

-- Borrows one instance of `className`, blank, parented to the pool folder until the caller parents it
-- somewhere. nil when the class is not poolable or the class is at its live ceiling, and a caller that
-- gets nil skips that layer -- docs/ART_BIBLE.md rule 8: an effect we cannot afford is an effect we do
-- not play.
function VfxPool.acquire(className: string): Instance?
	local ops = CLASSES[className]
	if ops == nil then
		if not unknownWarned[className] then
			unknownWarned[className] = true
			log.warn("%s is not a pooled class: nothing was borrowed", className)
		end
		return nil
	end

	local home = ensureFolder()
	local stack = stackOf(className)
	prune(className, stack, home)

	local decision, index = getPolicy():borrow(className)
	if decision == "Refuse" then
		if not capacityWarned[className] then
			capacityWarned[className] = true
			local state = getPolicy():report()[className]
			local live = if state ~= nil then state.Live else 0
			log.warn(
				"%s pool is at its live ceiling (%d out): borrows are refused while it stays there and effects drop a layer; warned once",
				className,
				live
			)
		end
		return nil
	end

	local instance: Instance? = nil
	if decision == "Reuse" then
		instance = table.remove(stack, index)
		if instance == nil then
			-- The index the policy pointed at is empty although prune just agreed the counts matched.
			-- The borrow is live either way, so building one here keeps the instances and the accounting
			-- together; only the Created total is short, and this line is what matters.
			log.warn("%s parked stack and pool accounting diverged: built a replacement", className)
		end
	end
	local borrowed = instance or ops.create()

	-- A leftover child is leftover state, and the effect that left it there is gone. Anything the pool
	-- still has out is spared: a live borrowed instance may legitimately be parented to this one.
	for _, child in ipairs(borrowed:GetChildren()) do
		if owned[child] == nil then
			child:Destroy()
		end
	end

	ops.reset(borrowed)
	borrowed.Parent = home
	owned[borrowed] = className
	return borrowed
end

-- Hands one instance back. False when the pool did not have it out, in which case nothing is parked:
-- accepting a stranger, or the same instance twice, is what puts one instance in the parked set twice and
-- then draws two effects with it.
function VfxPool.release(instance: Instance): boolean
	local className = owned[instance]
	if className == nil then
		-- Parked or destroyed means it already came back -- which is what every effect trove that outlives
		-- a respawn reclaim does -- and is not worth a line. Anything else is a caller bug.
		local home = folder
		local returned = instance.Parent == nil or (home ~= nil and instance.Parent == home)
		if not returned and not unownedWarned then
			unownedWarned = true
			log.warn("released %s, which the pool never handed out; warned once", instance.ClassName)
		end
		return false
	end

	owned[instance] = nil
	local decision = getPolicy():release(className)
	local home = ensureFolder()
	if decision ~= "Park" or instance.Parent == nil then
		if decision == "Park" then
			-- Counted as parked, but there is nothing left to park: somebody destroyed or unparented it
			-- while it was out.
			getPolicy():drop(className)
		end
		instance:Destroy()
		return true
	end

	local ops = CLASSES[className]
	if ops ~= nil then
		ops.mute(instance)
	end
	instance.Parent = home
	table.insert(stackOf(className), instance)
	return true
end

function VfxPool.stats(): { [string]: PoolPolicy.ClassState }
	return getPolicy():report()
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

-- Everything out comes back when the local character goes away, the way Feel drops its shakes and its
-- flashes: an effect trove whose lifetime has not elapsed yet would otherwise hold its instances into the
-- next life, and a leak that only appears after a respawn is the hardest kind to find.
local function reclaimAll()
	local outstanding: { Instance } = {}
	for instance in pairs(owned) do
		table.insert(outstanding, instance)
	end
	for _, instance in ipairs(outstanding) do
		VfxPool.release(instance)
	end
	local remaining = getPolicy():outstanding()
	if remaining > 0 then
		log.warn("%d instance(s) still counted as out after reclaiming everything: the accounting drifted", remaining)
	end
end

-- Nothing is built at load time: a client that requires this module and never renders an effect plants no
-- folder in the data model. Init is also where a class the pool can build but the policy has no ceiling
-- for is caught, because the only symptom at runtime would be effects quietly missing a layer.
function VfxPool.Init()
	getPolicy()
	ensureFolder()
	for className in pairs(CLASSES) do
		if PoolPolicy.Limits[className] == nil then
			log.warn("no pool ceiling for %s: every borrow of it is refused", className)
		end
	end
end

function VfxPool.Start()
	player.CharacterRemoving:Connect(reclaimAll)
	log.info("started")
end

return VfxPool
