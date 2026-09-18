--!strict
-- Encounter: the boss as it exists in the world. It builds the anchored Humanoid model at the centre of
-- the Boss arena, drops the participants on the ring pads, and steps the fight once per server tick —
-- the walk towards the nearest participant, the contact damage, the telegraph of the next attack and
-- the hit it resolves. The rules behind each of those come from GameModes/WorldBossMode.
--
-- It never decides that the event is over: `step` reports what the tick found and WorldBossService owns
-- the schedule, the outcomes and the rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CombatConfig = require(Shared.Config.CombatConfig)
local Context = require(script.Parent.Context)
local Log = require(Shared.Util.Log)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldBossMode = require(script.Parent.Parent.Parent.GameModes.WorldBossMode)

local log = Log.new("WorldBoss.Encounter")

-- What one tick of the fight found: the boss is still up, it went down, or there is nobody left in the
-- arena to fight it.
export type Outcome = "Fighting" | "Defeated" | "Empty"

type Deps = Context.Deps
type Arena = Context.Arena
type Boss = Context.Boss

local BOSS = WorldBossConfig.Boss

local Encounter = {}

local deps: Deps

----------------------------------------------------------------
-- Building the arena side of the event
----------------------------------------------------------------

-- Top of the arena floor: the boss stands on it whatever altitude the arena slot sits at.
local function groundY(arena: Arena, fallback: number): number
	local floor = arena.Instance:FindFirstChild(Context.FloorName, true)
	if floor ~= nil and floor:IsA("BasePart") then
		return floor.Position.Y + floor.Size.Y / 2
	end
	return fallback
end

-- Centre of the arena: the BossSpawn marker, or the average of the player pads when it is missing.
local function centerOf(arena: Arena): Vector3
	local marker = arena.Instance:FindFirstChild(Context.BossSpawnName, true)
	if marker ~= nil and marker:IsA("BasePart") then
		return marker.Position
	end
	local total = Vector3.zero
	local count = 0
	for _, pads in ipairs(arena.Spawns) do
		for _, pad in ipairs(pads) do
			total += pad.Position
			count += 1
		end
	end
	if count == 0 then
		log.warn("arena %s has no spawn pad to centre the boss on", arena.Id)
		return Vector3.zero
	end
	return total / count
end

-- One anchored body part carrying the Humanoid: the boss is stepped by CFrame, never simulated, and
-- every visual beyond the block comes from VfxLibrary. No nameplate — the server cannot localize one,
-- so the HUD names and bars the boss from BossChanged.
local function buildBody(position: Vector3, facing: Vector3, health: number): (Model, Humanoid, BasePart)
	local model = Instance.new("Model")
	model.Name = BOSS.Name

	local body = Instance.new("Part")
	body.Name = Context.RootPartName
	body.Size = WorldBossMode.bodySize()
	body.Anchored = true
	body.Material = Enum.Material.Slate
	body.Color = Context.BodyColor
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = CFrame.lookAt(position, position + facing)
	body.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.DisplayName = ""
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	model.PrimaryPart = body
	return model, humanoid, body
end

-- Spawns the boss with `health` in `arena` and returns it, parented and ready to be ticked. The caller
-- owns the Trove that destroys the model and releases the arena.
function Encounter.build(arena: Arena, health: number): Boss
	local center = centerOf(arena)
	local size = WorldBossMode.bodySize()
	local floorY = groundY(arena, center.Y)
	local position = Vector3.new(center.X, floorY + size.Y / 2, center.Z)
	local facing = Vector3.new(0, 0, -1)
	local model, humanoid, body = buildBody(position, facing, health)
	model.Parent = arena.Instance
	return {
		Arena = arena,
		Model = model,
		Humanoid = humanoid,
		Body = body,
		Center = position,
		GroundY = floorY,
		Facing = facing,
		LastHealth = humanoid.Health,
		ContactNextAt = {},
	}
end

-- Drops every participant on its own pad of the arena ring, facing the boss.
function Encounter.place(arena: Arena, userIds: { number }, center: Vector3)
	local pads = arena.Spawns[1]
	if pads == nil or #pads == 0 then
		log.warn("arena %s has no player pad: participants stay where they are", arena.Id)
		return
	end
	for index, userId in ipairs(userIds) do
		local player = Players:GetPlayerByUserId(userId)
		local character = if player ~= nil then player.Character else nil
		if character ~= nil then
			local pad = pads[((index - 1) % #pads) + 1]
			local position = pad.Position + Vector3.new(0, Context.SpawnClearanceStuds, 0)
			character:PivotTo(CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
			local root = character.PrimaryPart
			if root ~= nil then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			-- The destination, passed explicitly: trust must follow a server-authored teleport and anchor on
			-- the pad the server chose, or the first hit this player lands on the boss is built back where
			-- they stood.
			deps.Combat.resyncPosition(player, position)
		end
	end
end

----------------------------------------------------------------
-- Attacks
----------------------------------------------------------------

-- Starts the warning of the next attack, if one is off cooldown: the clients draw the area it will
-- cover from the packet (so it goes over the reliable remote) and the HUD names it from the snapshot's
-- TelegraphKey. Returns whether an attack started.
local function startAttack(boss: Boss, state: WorldBossMode.State, now: number): boolean
	local attack = WorldBossMode.selectAttack(state, now)
	if attack == nil then
		return false
	end
	local seconds = WorldBossMode.beginAttack(state, attack, now)
	deps.Vfx.emit({
		Id = attack.VfxId,
		Origin = boss.Body.Position,
		Direction = boss.Facing,
		Params = {
			Shape = attack.Shape,
			Radius = attack.Radius,
			Range = attack.Range,
			Telegraph = seconds,
			Ground = boss.GroundY,
		},
	}, true)
	return true
end

-- The telegraph is over: everything standing in the shape takes the hit, through the single damage path
-- and with no source, so the attack lands whatever the PvP policy is. Knockback and stun only follow
-- damage that actually landed, so a guard that soaked it all stops them too.
local function resolveAttack(boss: Boss, state: WorldBossMode.State)
	local attack = state.Attack
	if attack == nil then
		return
	end
	WorldBossMode.endAttack(state)
	local origin = boss.Body.Position
	local facing = boss.Facing
	local tags = { "Boss" .. attack.Id }
	for _, model in ipairs(Context.humanoidsInRadius(origin, WorldBossMode.reachOf(attack), boss.Model)) do
		local position = model:GetPivot().Position
		if WorldBossMode.isInShape(attack, origin, facing, position) then
			local result = deps.Combat.ApplyDamage(nil, model, attack.Damage, "Boss", tags)
			if result.Applied > 0 then
				if attack.Knockback > 0 then
					deps.Combat.knockback(
						model,
						WorldBossMode.knockbackVelocity(attack, origin, facing, position),
						CombatConfig.Hit.KnockbackDurationSeconds
					)
				end
				local player = Players:GetPlayerFromCharacter(model)
				if attack.StunSeconds > 0 and player ~= nil then
					deps.Movement.applyStun(player, math.min(attack.StunSeconds, CombatConfig.Hit.StunMaxSeconds))
				end
			end
		end
	end
end

-- WorldBossConfig.Boss.ContactDamage for standing inside the boss, once per second and per participant.
local function applyContactDamage(boss: Boss, userIds: { number }, now: number)
	local origin = boss.Body.Position
	for _, player in ipairs(Context.livePlayers(userIds)) do
		local root = Context.liveRoot(player)
		local character = player.Character
		if root ~= nil and character ~= nil and WorldBossMode.insideBody(origin, root.Position) then
			if now >= (boss.ContactNextAt[player.UserId] or 0) then
				boss.ContactNextAt[player.UserId] = now + Context.ContactIntervalSeconds
				deps.Combat.ApplyDamage(nil, character, BOSS.ContactDamage, "Boss", Context.ContactTags)
			end
		end
	end
end

----------------------------------------------------------------
-- One tick of the fight
----------------------------------------------------------------

-- Walks the boss `deltaSeconds` towards the nearest participant in aggro range and turns it to face
-- them. Out of range it holds its ground and keeps the direction it already had.
local function walk(boss: Boss, state: WorldBossMode.State, roots: { BasePart }, deltaSeconds: number)
	local origin = boss.Body.Position
	local target = Context.nearestRoot(roots, origin)
	if target == nil then
		return
	end
	local destination = target.Position
	local position = WorldBossMode.stepToward(origin, destination, WorldBossMode.moveSpeed(state), deltaSeconds)
	local offset = Vector3.new(destination.X - position.X, 0, destination.Z - position.Z)
	if offset.Magnitude > Context.Epsilon then
		boss.Facing = offset.Unit
	end
	boss.Body.CFrame = CFrame.lookAt(position, position + boss.Facing)
end

-- One tick: death first, then the phase, the walk, the contact damage and the attack rotation. The
-- second return value asks for an immediate BossChanged push (a phase change, a telegraph, a hit).
function Encounter.step(
	boss: Boss,
	state: WorldBossMode.State,
	userIds: { number },
	now: number,
	deltaSeconds: number
): (Outcome, boolean)
	if boss.Humanoid.Health <= 0 then
		return "Defeated", true
	end
	local roots = Context.arenaRoots(userIds, boss.Center)
	if #roots == 0 then
		return "Empty", true
	end

	local dirty = WorldBossMode.setHealth(state, boss.Humanoid.Health)
	if dirty then
		log.info("phase %d at %d / %d health", state.PhaseIndex, math.floor(state.Health), state.MaxHealth)
	end
	state.Participants = #roots
	walk(boss, state, roots, deltaSeconds)
	applyContactDamage(boss, userIds, now)

	if state.Attack == nil then
		dirty = startAttack(boss, state, now) or dirty
	elseif now >= state.ResolveAt then
		resolveAttack(boss, state)
		dirty = true
	end
	return "Fighting", dirty
end

-- One damage application against the boss, attributed to the player CombatService says dealt it.
--
-- Driven by CombatService.Damaged rather than by Humanoid.HealthChanged plus a last-attacker
-- attribute: several players land a hit inside one resumption cycle, and a shared attribute slot
-- credits every one of those hits to whoever wrote it last, so a player timing cheap fast casts to
-- land last absorbed the whole frame's damage from everybody else.
--
-- The overkill of the killing blow never counts: the credit is clamped to the health still left, so
-- the shares always add up to exactly the health the boss lost and WorldBossMode.shareOf stays a
-- fraction of the real total.
function Encounter.recordDamage(boss: Boss, state: WorldBossMode.State, sourceUserId: number, applied: number)
	local credited = math.min(applied, boss.LastHealth)
	if credited <= 0 then
		return
	end
	boss.LastHealth -= credited
	WorldBossMode.recordDamage(state, sourceUserId, credited)
end

function Encounter.Init(injected: Deps)
	deps = injected
end

return Encounter
