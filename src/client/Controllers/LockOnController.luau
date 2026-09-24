--!strict
-- LockOnController: locks onto one opponent (D-115). The LockOn action (the wheel's click, the right
-- stick's, a disc on touch) takes the opponent nearest the camera's aim, within reach and in sight, and
-- pressed again lets go. While locked the camera looks at them (Feel.lockOn) and the character faces
-- them, so a punch, a glyph or a dash with no direction goes at them: the server already aims every one
-- of those along the character's facing, so the lock needs no remote and trusts the client with nothing
-- new. Movement stays the player's own -- a sideways dash while locked is a sideways dodge.
--
-- What a lock can take is what the player can hurt: in a match, the other team's living players; in the
-- hub, the training proofs; in the World Boss arena, the boss. It lets go when the target dies, leaves,
-- goes out of reach or stops being an opponent, when the local character dies or is eliminated, and when
-- a menu opens (the key that would let go is unbound behind it). A target knocked down is kept: the fall
-- after a finisher is the moment to stay on them. It is not taken, though, while it lies there.
--
-- One loop, on PreSimulation: the facing is written just before physics steps, so the server's next
-- look at the character already faces the target.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local LockMarker = require(UI.components.LockMarker)
local LockOnConfig = require(Shared.Config.LockOnConfig)
local LockOnMath = require(Shared.Pure.LockOnMath)
local Log = require(Shared.Util.Log)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)

local log = Log.new("LockOnController")

type Deps = { Feel: any, InputController: any, MatchController: any }
type Kind = "Player" | "Proof" | "Boss"
type Lock = { Model: Model, Humanoid: Humanoid, Root: BasePart, Kind: Kind }

local ACTION = "LockOn"
local ROOT_PART_NAME = "HumanoidRootPart"
local RAGDOLL = CombatConfig.Status.RagdollAttribute

local LockOnController = {}

local feel: any
local inputController: any
local matchController: any

local player = Players.LocalPlayer
local current: Lock? = nil
local marker: LockMarker.LockMarker? = nil

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true

local function localBody(): (Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild(ROOT_PART_NAME)
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

-- A lock on `model` as `kind`, or nil when it is not a living body in the world.
local function lockOf(model: Instance?, kind: Kind): Lock?
	if model == nil or not model:IsA("Model") or model == player.Character then
		return nil
	end
	if not model:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild(ROOT_PART_NAME)
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return { Model = model, Humanoid = humanoid, Root = root, Kind = kind }
end

-- Every opponent this client may lock right now. In a match, the other teams' living players -- and
-- nothing at all for a local player who is out and watching a teammate, or before the snapshot has
-- said which team is theirs. Outside one, the proofs and the boss: the hub has no fight between players.
local function opponents(): { Lock }
	local out: { Lock } = {}
	local match = matchController.getMatch()
	if match ~= nil then
		local mine = match.Teams[match.LocalTeam]
		if match.LocalTeam < 1 or mine == nil then
			return out
		end
		for _, member in ipairs(mine) do
			if member.UserId == player.UserId and not member.Alive then
				return out
			end
		end
		for team, members in pairs(match.Teams) do
			if team ~= match.LocalTeam then
				for _, member in ipairs(members) do
					local other = if member.Alive then Players:GetPlayerByUserId(member.UserId) else nil
					local lock = lockOf(if other ~= nil then other.Character else nil, "Player")
					if lock ~= nil then
						table.insert(out, lock)
					end
				end
			end
		end
		return out
	end
	for _, model in ipairs(CollectionService:GetTagged(GameConfig.Enemy.Tag)) do
		local lock = lockOf(model, "Proof")
		if lock ~= nil then
			table.insert(out, lock)
		end
	end
	for _, model in ipairs(CollectionService:GetTagged(WorldBossConfig.Boss.Tag)) do
		local lock = lockOf(model, "Boss")
		if lock ~= nil then
			table.insert(out, lock)
		end
	end
	return out
end

-- Whether nothing but bodies stands between the camera and `lock`: a wall hides a target from a lock as
-- it hides it from the eye. A body does not -- a teammate in the way, or a proof in front of the one you
-- aim at, is not a reason to lock someone else -- so every character and every opponent (`bodies`) is
-- left out of the ray.
local function inSight(from: Vector3, lock: Lock, bodies: { Instance }): boolean
	sightParams.FilterDescendantsInstances = bodies
	return Workspace:Raycast(from, lock.Root.Position - from, sightParams) == nil
end

-- The opponent the camera is looking at: inside the cone around its aim, within reach of the character,
-- in sight, and not lying on the floor; the one nearest the aim first (LockOnMath.order).
local function acquire(): Lock?
	local _, root = localBody()
	local camera = Workspace.CurrentCamera
	if root == nil or camera == nil then
		return nil
	end
	local eye = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local standing: { Lock } = {}
	local candidates: { LockOnMath.Candidate } = {}
	local bodies: { Instance } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character ~= nil then
			table.insert(bodies, other.Character)
		end
	end
	for _, lock in ipairs(opponents()) do
		table.insert(bodies, lock.Model)
		if lock.Model:GetAttribute(RAGDOLL) == nil then
			local toward = lock.Root.Position - eye
			table.insert(standing, lock)
			table.insert(candidates, {
				Angle = LockOnMath.angle(look.X, look.Y, look.Z, toward.X, toward.Y, toward.Z),
				Distance = (lock.Root.Position - root.Position).Magnitude,
			})
		end
	end
	for _, index in ipairs(LockOnMath.order(candidates, LockOnConfig.AcquireStuds, LockOnConfig.ConeDegrees)) do
		if inSight(eye, standing[index], bodies) then
			return standing[index]
		end
	end
	return nil
end

-- Studs above its root the mark floats over `lock`: over the top of its body, whatever its height.
local function liftOf(lock: Lock): number
	local frame, size = lock.Model:GetBoundingBox()
	return frame.Position.Y + size.Y / 2 - lock.Root.Position.Y + LockOnConfig.Marker.LiftStuds
end

-- Turns the local character to face the target across the floor. Not while it is knocked down or
-- getting up: the server loosened its joints for the fall and a written frame would fight it (D-113).
local function face(lock: Lock)
	local humanoid, root = localBody()
	local character = player.Character
	if humanoid == nil or root == nil or character == nil or character:GetAttribute(RAGDOLL) ~= nil then
		return
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.GettingUp then
		return
	end
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end
	local position = root.Position
	local target = lock.Root.Position
	local x, z = LockOnMath.facing(position.X, position.Z, target.X, target.Z, LockOnConfig.FacingMinStuds)
	if x ~= nil and z ~= nil then
		root.CFrame = CFrame.lookAlong(position, Vector3.new(x, 0, z))
	end
end

local function release()
	if current == nil then
		return
	end
	current = nil
	feel.lockOn(nil)
	if marker ~= nil then
		marker:Hide()
	end
	-- The engine turns the character toward where it walks again. A respawned Humanoid starts with it on.
	local humanoid = localBody()
	if humanoid ~= nil then
		humanoid.AutoRotate = true
	end
end

local function engage(lock: Lock)
	current = lock
	feel.lockOn(lock.Root)
	if marker ~= nil then
		marker:Show(lock.Root, liftOf(lock))
	end
	-- Faced at once: the first punch after the press must already go at them.
	face(lock)
end

local function toggle()
	if current ~= nil then
		release()
		return
	end
	local lock = acquire()
	if lock ~= nil then
		engage(lock)
	end
end

-- Whether `lock` is still one the player may hold: alive, in the world, in reach, and still an opponent.
local function holds(lock: Lock): boolean
	local _, root = localBody()
	if root == nil or lock.Humanoid.Health <= 0 or lock.Root.Parent == nil then
		return false
	end
	if not lock.Model:IsDescendantOf(Workspace) then
		return false
	end
	if (lock.Root.Position - root.Position).Magnitude > LockOnConfig.BreakStuds then
		return false
	end
	if lock.Kind == "Player" then
		return Players:GetPlayerFromCharacter(lock.Model) ~= nil
	elseif lock.Kind == "Proof" then
		return CollectionService:HasTag(lock.Model, GameConfig.Enemy.Tag)
	end
	return CollectionService:HasTag(lock.Model, WorldBossConfig.Boss.Tag)
end

-- A new snapshot can make the target a teammate's, a corpse's or nobody's, and the local player a
-- spectator: the lock holds only an opponent the snapshot still lists.
local function onMatchChanged()
	local lock = current
	if lock == nil then
		return
	end
	for _, opponent in ipairs(opponents()) do
		if opponent.Model == lock.Model then
			return
		end
	end
	release()
end

local function step()
	local lock = current
	if lock == nil then
		return
	end
	if not holds(lock) then
		release()
		return
	end
	face(lock)
end

function LockOnController.isLocked(): boolean
	return current ~= nil
end

function LockOnController.Init(deps: Deps)
	feel = deps.Feel
	inputController = deps.InputController
	matchController = deps.MatchController
end

function LockOnController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	marker = LockMarker.new(playerGui, LockOnConfig.Marker.SizePx)
	inputController.Action:Connect(function(actionId: string, began: boolean)
		if actionId == ACTION and began then
			toggle()
		end
	end)
	inputController.SuspendedChanged:Connect(function(suspended: boolean)
		if suspended then
			release()
		end
	end)
	matchController.MatchChanged:Connect(onMatchChanged)
	player.CharacterRemoving:Connect(release)
	RunService.PreSimulation:Connect(step)
	log.info("started")
end

return LockOnController
