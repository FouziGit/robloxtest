--!strict
-- Posture: the body does what the character is doing.
--
-- Before this controller the game had no animation of any kind -- a character landed a four-hit combo
-- with its arms hanging at its sides, guarded standing upright and dashed without leaning. Damage,
-- knockback, hit-stop and screen shake all worked, which made it worse: the numbers moved and the body
-- did not, so the game read as a spreadsheet with particles.
--
-- How it works, and why it needs no asset:
--   * A Roblox animation track writes Motor6D.Transform. This writes Motor6D.C0. They compose, so the
--     engine's own idle and walk keep running underneath and a swing is ADDED on top of them instead of
--     replacing them. There is no Animator here and no animation asset id, which is the point: the only
--     ids available to borrow belong to other studios (docs/ART_BIBLE.md).
--   * Angles are declared in Config/PostureConfig in PARENT space and converted here, once, per joint.
--     An R6 "Right Shoulder" and an R15 "RightShoulder" sit at different orientations, so applying a
--     raw rotation to either one gives two different poses; applying it about the joint's pivot in the
--     torso's space gives the same pose on both rigs.
--   * Every pose is a weight between 0 and 1 carried by the same spring the camera and the HUD use, and
--     the weights SUM. A player who dashes out of a finisher gets both, composed, rather than the
--     second cancelling the first.
--
-- WHAT THIS NEEDS, and it is not negotiable: a Motor6D rig. Verified in a running client -- a modern
-- Roblox avatar is no longer built from Motor6D at all. It is a physically driven rig of
-- AnimationConstraint plus BallSocketConstraint, with the same joint NAMES (RightShoulder, Waist, Neck)
-- and none of the joints. Neither attachment frame nor the constraint's own Transform moves a limb on
-- it, written once or written every frame after the character step; all three were measured against the
-- hand's position and all three moved it by under two tenths of a stud.
--
-- The fix is a universe setting, not code: Avatar Type set to R6 (docs/STUDIO_SETUP.md). An R6 rig has
-- exactly the six Motor6Ds Config/PostureConfig names, and R6 is what this genre uses anyway -- a
-- silhouette that reads at fighting distance. Until it is set, this controller says so once and poses
-- nothing, which is the honest behaviour: it never half-moves a body.
--
-- C0 is written on this client only: Motor6D.C0 does not replicate from a client. That is not a
-- limitation, it is the design -- every client runs this controller against the same replicated state
-- (the guard attribute) and the same broadcast packets, so everyone sees everyone's body move, and the
-- server spends nothing.
--
-- One Heartbeat for every character, like FootprintController: characters are read from Players each
-- frame, so a respawn or a leave costs nothing to track.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CombatConfig = require(Shared.Config.CombatConfig)
local Log = require(Shared.Util.Log)
local PostureConfig = require(Shared.Config.PostureConfig)
local Spring = require(Shared.Pure.Spring)

local log = Log.new("Posture")

type Deps = { VfxController: any }

type SpringHandle = typeof(Spring.new(0, 0, 0))

-- One pose currently playing on one character: its weight, and how far into its own envelope it is.
type Pulse = {
	PoseId: string,
	Weight: SpringHandle,
	Elapsed: number,
	Releasing: boolean,
}

-- Everything known about one character being posed.
type Entry = {
	Humanoid: Humanoid,
	-- Semantic joint name -> the Motor6D carrying it, and the C0 it had before this file touched it.
	Motors: { [string]: Motor6D },
	Originals: { [string]: CFrame },
	Pulses: { Pulse },
	Guard: SpringHandle,
	-- True while at least one joint is displaced, so a character standing still costs no CFrame writes.
	Displaced: boolean,
}

local GUARD_ATTRIBUTE = CombatConfig.Status.BlockAttribute
local ENVELOPE = PostureConfig.Envelope
local JOINTS = PostureConfig.JointOrder
local GUARD_ANGLES = PostureConfig.Guard.Angles
-- Below this the composed rotation is under a tenth of a degree and writing it is writing noise.
local EPSILON_DEGREES = 0.1
local RANGE_SQUARED = PostureConfig.RangeStuds * PostureConfig.RangeStuds

local Posture = {}

local entries: { [Model]: Entry } = {}
local vfxController: any
-- Rig types already reported as unposeable. Once each, never per character and never per frame: a
-- twelve-player server on the wrong avatar setting would otherwise print seven hundred lines a second.
local warnedRigs: { [string]: boolean } = {}

-- The critically damped spring that covers a declared phase, by the conversion PostureConfig.Envelope
-- states: within 2% of the goal after `seconds`.
local function springFor(seconds: number): (number, number)
	local safe = math.max(seconds, ENVELOPE.MinPhaseSeconds)
	local tension = (ENVELOPE.Settle / safe) ^ 2
	return tension, Spring.criticalFriction(tension)
end

local function retune(handle: SpringHandle, seconds: number)
	local tension, friction = springFor(seconds)
	handle.Tension = tension
	handle.Friction = friction
end

-- The Motor6D carrying a semantic joint, or nil when this rig has no such joint. Searched by name
-- across the character because the two rigs park the same joint under different parents.
local function findMotors(character: Model, humanoid: Humanoid): { [string]: Motor6D }?
	local rig = if humanoid.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15"
	local names = PostureConfig.Motors[rig]
	if names == nil then
		return nil
	end
	local found: { [string]: Motor6D } = {}
	local any = false
	for _, joint in ipairs(JOINTS) do
		local motorName = names[joint]
		if motorName ~= nil then
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("Motor6D") and descendant.Name == motorName then
					found[joint] = descendant
					any = true
					break
				end
			end
		end
	end
	if not any then
		return nil
	end
	return found
end

local function track(character: Model, humanoid: Humanoid): Entry?
	local motors = findMotors(character, humanoid)
	if motors == nil then
		local rig = humanoid.RigType.Name
		if not warnedRigs[rig] then
			warnedRigs[rig] = true
			log.warn(
				"%s characters carry no Motor6D on this client, so no body will move. "
					.. "Set the experience's Avatar Type to R6 (docs/STUDIO_SETUP.md)",
				rig
			)
		end
		return nil
	end
	local originals: { [string]: CFrame } = {}
	for joint, motor in pairs(motors) do
		originals[joint] = motor.C0
	end
	local rise, riseFriction = springFor(PostureConfig.Guard.RiseSeconds)
	local entry: Entry = {
		Humanoid = humanoid,
		Motors = motors,
		Originals = originals,
		Pulses = {},
		Guard = Spring.new(0, rise, riseFriction),
		Displaced = false,
	}
	entries[character] = entry
	return entry
end

-- Puts every joint back exactly as it was found. Called when a character stops being posed, so the
-- engine's own animation is never left standing on an offset this file forgot to take off.
local function restore(entry: Entry)
	for joint, motor in pairs(entry.Motors) do
		local original: CFrame? = entry.Originals[joint]
		if original ~= nil and motor.Parent ~= nil then
			motor.C0 = original
		end
	end
	entry.Displaced = false
end

local function forget(character: Model)
	local entry = entries[character]
	if entry == nil then
		return
	end
	if entry.Displaced then
		restore(entry)
	end
	entries[character] = nil
end

-- Starts a pose on a character, or restarts it if it is already playing: a second jab inside the first
-- one's release should swing again, not wait for the first to finish leaving.
local function play(character: Model, poseId: string)
	local def = PostureConfig.Poses[poseId]
	if def == nil then
		return
	end
	local entry = entries[character]
	if entry == nil then
		return
	end
	for _, pulse in ipairs(entry.Pulses) do
		if pulse.PoseId == poseId then
			pulse.Elapsed = 0
			pulse.Releasing = false
			retune(pulse.Weight, def.AttackSeconds)
			Spring.setGoal(pulse.Weight, 1)
			return
		end
	end
	local tension, friction = springFor(def.AttackSeconds)
	local weight = Spring.new(0, tension, friction)
	Spring.setGoal(weight, 1)
	table.insert(entry.Pulses, { PoseId = poseId, Weight = weight, Elapsed = 0, Releasing = false })
end

-- Advances one character's springs and writes its joints. Returns nothing: every decision here is
-- local to this entry.
local function step(entry: Entry, deltaTime: number)
	-- Pulses first, dropping the ones that have arrived back at rest.
	local index = #entry.Pulses
	while index >= 1 do
		local pulse = entry.Pulses[index]
		local def = PostureConfig.Poses[pulse.PoseId]
		pulse.Elapsed += deltaTime
		if def ~= nil then
			if not pulse.Releasing and pulse.Elapsed >= def.AttackSeconds + def.HoldSeconds then
				pulse.Releasing = true
				retune(pulse.Weight, def.ReleaseSeconds)
				Spring.setGoal(pulse.Weight, 0)
			end
			Spring.step(pulse.Weight, deltaTime)
			if pulse.Releasing and pulse.Weight.Position <= ENVELOPE.SettleEpsilon then
				table.remove(entry.Pulses, index)
			end
		else
			table.remove(entry.Pulses, index)
		end
		index -= 1
	end

	-- The guard, which is a state and not a pulse: it follows the attribute and nothing else can make
	-- it leave early.
	local guarding = entry.Humanoid:GetAttribute(GUARD_ATTRIBUTE) == true
	local guardGoal = if guarding then 1 else 0
	if entry.Guard.Goal ~= guardGoal then
		retune(entry.Guard, if guarding then PostureConfig.Guard.RiseSeconds else PostureConfig.Guard.FallSeconds)
		Spring.setGoal(entry.Guard, guardGoal)
	end
	Spring.step(entry.Guard, deltaTime)

	-- Compose every live weight into one rotation per joint.
	local guardWeight = entry.Guard.Position
	local displaced = false
	for _, joint in ipairs(JOINTS) do
		local motor: Motor6D? = entry.Motors[joint]
		local original: CFrame? = entry.Originals[joint]
		if motor ~= nil and original ~= nil and motor.Parent ~= nil then
			local x, y, z = 0, 0, 0
			for _, pulse in ipairs(entry.Pulses) do
				local def = PostureConfig.Poses[pulse.PoseId]
				local angles = if def ~= nil then def.Angles[joint] else nil
				if angles ~= nil then
					local weight = pulse.Weight.Position
					x += angles[1] * weight
					y += angles[2] * weight
					z += angles[3] * weight
				end
			end
			local guardAngles = GUARD_ANGLES[joint]
			if guardAngles ~= nil and guardWeight > 0 then
				x += guardAngles[1] * guardWeight
				y += guardAngles[2] * guardWeight
				z += guardAngles[3] * guardWeight
			end
			if math.abs(x) + math.abs(y) + math.abs(z) > EPSILON_DEGREES then
				displaced = true
				-- The pivot is kept and the rotation is applied in the PARENT's space, before the
				-- joint's own orientation. This is the line that makes one declared pose read the same
				-- on an R6 shoulder and an R15 one.
				local position = original.Position
				local rotation = original - position
				local offset = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
				motor.C0 = CFrame.new(position) * offset * rotation
			elseif entry.Displaced then
				motor.C0 = original
			end
		end
	end
	entry.Displaced = displaced
end

local function onHeartbeat(deltaTime: number)
	local camera = Workspace.CurrentCamera
	local origin = if camera ~= nil then camera.CFrame.Position else Vector3.zero

	local seen: { [Model]: boolean } = {}
	local budget = PostureConfig.MaxCharacters
	for _, player in ipairs(Players:GetPlayers()) do
		if budget <= 0 then
			break
		end
		local character = player.Character
		if character ~= nil then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart") then
				-- Squared, so the range test costs no square root per character per frame.
				local offset = root.Position - origin
				if offset:Dot(offset) <= RANGE_SQUARED then
					local entry: Entry? = entries[character]
					if entry == nil then
						entry = track(character, humanoid)
					end
					if entry ~= nil then
						seen[character] = true
						budget -= 1
						step(entry, deltaTime)
					end
				end
			end
		end
	end

	-- Anything tracked last frame and not this one has died, left, or walked out of range.
	for character in pairs(entries) do
		if not seen[character] then
			forget(character)
		end
	end
end

local function characterOf(userId: number): Model?
	if userId <= 0 then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	return if player ~= nil then player.Character else nil
end

-- The user id carried by a packet's Params.Target: who RECEIVED the thing. 0 for a training dummy or
-- an enemy, which has no player behind it and no posture here.
local function targetOf(params: { [string]: any }?): number
	if type(params) ~= "table" then
		return 0
	end
	local target = params.Target
	return if type(target) == "number" then target else 0
end

-- What the server broadcast, turned into a pose. Every packet read here already existed and already
-- named the character it is about: nothing was added to the wire for the body to move, except the
-- target of a guard break, which the Hit packet beside it already carried.
local function onAction(id: string, userId: number, params: { [string]: any }?)
	if id == "Melee" then
		local character = characterOf(userId)
		if character == nil then
			return
		end
		local chain = PostureConfig.MeleeChain
		local index = if type(params) == "table" and type(params.Index) == "number" then params.Index else 1
		local pose = chain[math.clamp(math.floor(index), 1, #chain)]
		if pose ~= nil then
			play(character, pose)
		end
	elseif id == "Dash" then
		local character = characterOf(userId)
		if character ~= nil then
			play(character, "Dash")
		end
	elseif id == "Cast" then
		local character = characterOf(userId)
		if character ~= nil then
			play(character, "Cast")
		end
	elseif id == "Hit" then
		-- The flinch is the TARGET's, never the attacker's. It plays on a guarded hit too: the guard
		-- pose is held by the attribute and the flinch adds to it, which is what a blow landing on a
		-- raised guard should look like.
		local character = characterOf(targetOf(params))
		if character ~= nil then
			play(character, "Flinch")
		end
	elseif id == "GuardBreak" then
		local character = characterOf(targetOf(params))
		if character ~= nil then
			play(character, "GuardBreak")
		end
	end
end

function Posture.Init(deps: Deps)
	vfxController = deps.VfxController
end

function Posture.Start()
	vfxController.Acted:Connect(onAction)
	RunService.Heartbeat:Connect(onHeartbeat)
	Players.PlayerRemoving:Connect(function(player: Player)
		local character = player.Character
		if character ~= nil then
			forget(character)
		end
	end)
	log.info("started")
end

return Posture
