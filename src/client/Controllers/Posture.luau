--!strict
-- Posture: the body does what the character is doing.
--
-- Before this controller the game had no animation of any kind -- a character landed a four-hit combo
-- with its arms hanging at its sides, guarded standing upright and dashed without leaning. Damage,
-- knockback, hit-stop and screen shake all worked, which made it worse: the numbers moved and the body
-- did not, so the game read as a spreadsheet with particles.
--
-- How it works, and why it needs no asset:
--   * Every joint the engine animates has a Transform that the Animator rewrites once per frame,
--     between RunService.PreAnimation and RunService.PreSimulation. This controller runs IN
--     PreSimulation, reads the pose the Animator just wrote, and multiplies an offset into it. The
--     engine's own idle and walk therefore keep running underneath and a swing is ADDED on top of them.
--     That is Roblox's documented pattern for procedural layers (the AnimationConstraint reference and
--     the Avatar Joint Upgrade migration notes), and it is the same on both joint classes below.
--   * The joint may be a Motor6D (R6, and R15 in experiences that opted out) or an AnimationConstraint
--     (R15 under the Avatar Joint Upgrade, the default for experiences since May 2026, with the opt-out
--     scheduled to disappear). They carry the same NAMES and neither can be posed through its frames:
--     an AnimationConstraint's C0 is a read-only alias that throws, and Roblox asks that rig attachments
--     never be moved, because retargeting depends on them.
--   * Angles are declared in Config/PostureConfig in PARENT space and converted here, per joint, by
--     conjugating with the rotation of the joint's parent-side frame (Motor6D.C0, or the constraint's
--     Attachment0). An R6 "Right Shoulder" and an R15 "RightShoulder" sit at orientations ninety
--     degrees apart, so a raw rotation gives two different poses; the conjugated one gives the same pose
--     on both.
--   * Every pose is a weight between 0 and 1 carried by the same spring the camera and the HUD use, and
--     the weights SUM. A player who dashes out of a finisher gets both, composed, rather than the
--     second cancelling the first.
--   * There is no Animator call and no animation asset id here, which is the point: the only ids
--     available to borrow belong to other studios (docs/ART_BIBLE.md).
--
-- What went wrong the first time, so it is not done again: this file used to write Motor6D.C0 from a
-- Heartbeat, and a live session showed a modern avatar has no Motor6D at all. The follow-up measurement
-- then wrote the constraint's Transform from a render-step binding -- a point in the frame where the
-- Animator's next write simply replaces it -- and concluded, wrongly, that the rig could not be posed.
-- The timing was the bug. tests/Posture.spec.luau now holds the controller to PreSimulation.
--
-- Transform does not replicate. That is not a limitation, it is the design: every client runs this
-- controller against the same replicated state (the guard attribute) and the same broadcast packets,
-- so everyone sees everyone's body move and the server spends nothing -- which is also what Roblox
-- recommends for procedural joints.
--
-- One PreSimulation connection for every character: characters are read from Players each frame, so a
-- respawn or a leave costs nothing to track.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local AnimationConfig = require(Shared.Config.AnimationConfig)
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

-- The two joint classes that carry a Transform the Animator rewrites every frame.
type JointInstance = Motor6D | AnimationConstraint

-- One posed joint.
type JointState = {
	Instance: JointInstance,
	-- Rotation of the joint's parent-side frame: what a parent-space angle is conjugated by.
	Frame: CFrame,
	-- The Transform the engine produced this frame, before the offset.
	Base: CFrame?,
	-- The Transform this file wrote last frame, or nil when it wrote nothing.
	Written: CFrame?,
}

-- Everything known about one character being posed.
type Entry = {
	Humanoid: Humanoid,
	-- Semantic joint name -> the joint carrying it.
	Joints: { [string]: JointState },
	Pulses: { Pulse },
	Guard: SpringHandle,
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
-- twelve-player server of an unknown rig would otherwise print seven hundred lines a second.
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

-- Writes a joint's Transform. One branch per class because the type checker cannot assign through a
-- union of two engine classes, even to a property both of them declare.
local function setTransform(instance: JointInstance, value: CFrame)
	if instance:IsA("Motor6D") then
		(instance :: Motor6D).Transform = value
	else
		(instance :: AnimationConstraint).Transform = value
	end
end

-- The parent-side frame of a joint: Motor6D.C0, or the constraint's Attachment0 (the attachment on the
-- parent part -- on a right shoulder, the one inside the torso). Rotation only: the offset turns the
-- limb about its pivot and never moves the pivot.
local function frameOf(instance: JointInstance): CFrame?
	if instance:IsA("Motor6D") then
		return (instance :: Motor6D).C0.Rotation
	end
	local attachment = (instance :: AnimationConstraint).Attachment0
	if attachment == nil then
		return nil
	end
	return attachment.CFrame.Rotation
end

-- The joints carrying each semantic joint on this rig, by name, whatever their class. Searched across
-- the character because the two rigs park the same joint under different parents.
local function findJoints(character: Model, humanoid: Humanoid): { [string]: JointState }?
	local rig = if humanoid.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15"
	local names = PostureConfig.JointNames[rig]
	if names == nil then
		return nil
	end
	local found: { [string]: JointState } = {}
	local any = false
	for _, joint in ipairs(JOINTS) do
		local jointName = names[joint]
		if jointName ~= nil then
			for _, descendant in ipairs(character:GetDescendants()) do
				if
					descendant.Name == jointName
					and (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint"))
				then
					local instance = descendant :: JointInstance
					local frame = frameOf(instance)
					if frame ~= nil then
						found[joint] = { Instance = instance, Frame = frame, Base = nil, Written = nil }
						any = true
					end
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
	local joints = findJoints(character, humanoid)
	if joints == nil then
		local rig = humanoid.RigType.Name
		if not warnedRigs[rig] then
			warnedRigs[rig] = true
			log.warn(
				"%s characters carry neither a Motor6D nor an AnimationConstraint under the joint names "
					.. "PostureConfig expects, so their bodies will not move",
				rig
			)
		end
		return nil
	end
	local rise, riseFriction = springFor(PostureConfig.Guard.RiseSeconds)
	local entry: Entry = {
		Humanoid = humanoid,
		Joints = joints,
		Pulses = {},
		Guard = Spring.new(0, rise, riseFriction),
	}
	entries[character] = entry
	return entry
end

-- Hands every joint back to the engine exactly as the engine last posed it. Called when a character
-- stops being posed, so no offset is left standing on a body this file no longer tracks. Where an
-- Animator is running this is overwritten on the next frame anyway; where none is, it is the only thing
-- that takes the offset off.
local function restore(entry: Entry)
	for _, state in pairs(entry.Joints) do
		if state.Written ~= nil and state.Instance.Parent ~= nil then
			setTransform(state.Instance, state.Base or CFrame.identity)
		end
		state.Written = nil
	end
end

local function forget(character: Model)
	local entry = entries[character]
	if entry == nil then
		return
	end
	restore(entry)
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
	-- A guard with a real clip is held by Moves on the guarding player's own client and replicated.
	local guarding = entry.Humanoid:GetAttribute(GUARD_ATTRIBUTE) == true and AnimationConfig.clipFor("Guard") == nil
	local guardGoal = if guarding then 1 else 0
	if entry.Guard.Goal ~= guardGoal then
		retune(entry.Guard, if guarding then PostureConfig.Guard.RiseSeconds else PostureConfig.Guard.FallSeconds)
		Spring.setGoal(entry.Guard, guardGoal)
	end
	Spring.step(entry.Guard, deltaTime)

	-- Compose every live weight into one rotation per joint, and multiply it into the pose the Animator
	-- has just written.
	local guardWeight = entry.Guard.Position
	for _, joint in ipairs(JOINTS) do
		local state = entry.Joints[joint]
		if state ~= nil and state.Instance.Parent ~= nil then
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

			local current = state.Instance.Transform
			-- The Animator rewrites Transform every frame it evaluates. If what is there is still exactly
			-- what this file wrote last frame, nothing rewrote it -- the evaluation was throttled, or the
			-- character has no Animator -- and multiplying again would compound the offset frame after
			-- frame into a spinning limb. Rebuild from the last pose the engine actually produced instead.
			local base = if state.Written ~= nil and current == state.Written then state.Base or current else current
			state.Base = base

			if math.abs(x) + math.abs(y) + math.abs(z) > EPSILON_DEGREES then
				-- A parent-space rotation about the pivot, carried into the joint's own frame by
				-- conjugation. This is the line that makes one declared pose read the same on every rig.
				local rotation = CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
				local written = state.Frame:Inverse() * rotation * state.Frame * base
				setTransform(state.Instance, written)
				state.Written = written
			elseif state.Written ~= nil then
				setTransform(state.Instance, base)
				state.Written = nil
			end
		end
	end
end

local function onPreSimulation(deltaTime: number)
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
		-- A hit with a real clip is animated by Moves on the attacker's own client and replicated to
		-- everyone; posing it here as well would move the same arm twice.
		if AnimationConfig.clipFor("Melee", math.max(1, math.floor(index))) ~= nil then
			return
		end
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
		if character ~= nil and AnimationConfig.clipFor("Cast") == nil then
			play(character, "Cast")
		end
	elseif id == "Hit" then
		-- The flinch is the TARGET's, never the attacker's. It plays on a guarded hit too: the guard
		-- pose is held by the attribute and the flinch adds to it, which is what a blow landing on a
		-- raised guard should look like.
		local character = characterOf(targetOf(params))
		if character ~= nil and AnimationConfig.clipFor("Flinch") == nil then
			play(character, "Flinch")
		end
	elseif id == "GuardBreak" then
		local character = characterOf(targetOf(params))
		if character ~= nil and AnimationConfig.clipFor("GuardBreak") == nil then
			play(character, "GuardBreak")
		end
	end
end

function Posture.Init(deps: Deps)
	vfxController = deps.VfxController
end

function Posture.Start()
	vfxController.Acted:Connect(onAction)
	-- PreSimulation and nothing else: it is the one point in the frame after the Animator has written
	-- this frame's pose and before the joints are solved. Heartbeat and the render step both come after
	-- the next Animator write has replaced anything written there.
	RunService.PreSimulation:Connect(onPreSimulation)
	Players.PlayerRemoving:Connect(function(player: Player)
		local character = player.Character
		if character ~= nil then
			forget(character)
		end
	end)
	log.info("started")
end

return Posture
