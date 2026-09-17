--!strict
-- JutsuEffects: server-side hit detection for every jutsu, keyed by JutsuConfig `Effect` id.
-- Effects build NO visuals: they detect targets (spatial queries, stepped raycasts, invisible
-- collision parts for walls), deal damage through CombatService.ApplyDamage only, and broadcast Vfx
-- packets that each client renders. Timed effects step inline in the caller's thread (the remote
-- handler runs in its own thread) and stop early when the caster dies or leaves.
-- Every effect returns the number of distinct models it damaged.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CombatConfig = require(Shared.Config.CombatConfig)
local JutsuConfig = require(Shared.Config.JutsuConfig)

export type JutsuDef = JutsuConfig.JutsuDef
export type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
export type CombatApi = {
	ApplyDamage: (source: Player?, targetModel: Model, amount: number, kind: string, tags: { string }) -> DamageResult,
	knockback: (targetModel: Model, velocity: Vector3, duration: number) -> (),
}
export type VfxPacket = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}
export type VfxApi = { emit: (packet: VfxPacket, reliable: boolean?) -> () }
export type MovementApi = {
	applySlow: (player: Player, factor: number, seconds: number) -> (),
	applyStun: (player: Player, seconds: number) -> (),
}
export type Context = {
	Caster: Player,
	Def: JutsuDef,
	Origin: CFrame,
	Direction: Vector3,
	Combat: CombatApi,
	Vfx: VfxApi,
	Movement: MovementApi,
}
export type Effect = (ctx: Context) -> number

-- Tracks distinct damaged models across the steps of one cast. `Once` = a model is damaged at most
-- once per cast (waves, spikes); zones damage on every tick instead.
type Tracker = { Once: boolean, Seen: { [Model]: boolean }, Count: number }

-- Invisible server collision geometry (walls) carries this tag so spatial queries skip it.
local COLLISION_TAG = "JutsuCollision"
local ROOT_PART_NAME = "HumanoidRootPart"
local WALL_NAME = "MudWall"
-- A projectile fuse is clamped so a synchronous effect never pins the remote handler for long.
local MAX_PROJECTILE_SECONDS = 1.5
-- Longest simulated step: a frame hitch must not teleport a projectile through targets.
local MAX_STEP_SECONDS = 0.1
local WAVE_STEP_SECONDS = 0.05
-- Blast push (horizontal, away from the blast) and lift applied to players caught in an explosion.
local FIREBALL_PUSH = 40
local FIREBALL_LIFT = 20
local WAVE_LIFT = 10
-- Humanoid roots float about this high above the floor (HipHeight + half the root height).
local ROOT_FLOOR_OFFSET = 3
local KNOCKBACK_DURATION = CombatConfig.Hit.KnockbackDurationSeconds

local JutsuEffects = {}

----------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------

local function playerOf(model: Model): Player?
	return Players:GetPlayerFromCharacter(model)
end

-- Root of a player's live character, or nil when dead / gone.
local function liveRoot(player: Player): BasePart?
	if player.Parent ~= Players then
		return nil
	end
	local character: Model? = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root: Instance? = character:FindFirstChild(ROOT_PART_NAME)
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Timed effects stop when the caster is no longer in the game with a live character.
local function casterAlive(ctx: Context): boolean
	return liveRoot(ctx.Caster) ~= nil
end

-- Closest ancestor Model with a live Humanoid (accessories and tools nest parts under it).
local function modelOf(part: BasePart): Model?
	local ancestor: Instance? = part.Parent
	while ancestor ~= nil do
		if ancestor:IsA("Model") then
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				return if humanoid.Health > 0 then ancestor :: Model else nil
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function overlapParams(excludeCharacter: Model?): OverlapParams
	local filter: { Instance } = CollectionService:GetTagged(COLLISION_TAG)
	if excludeCharacter ~= nil then
		table.insert(filter, excludeCharacter)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	return params
end

-- Distinct models with a live Humanoid whose parts overlap the sphere (caster and walls excluded).
local function humanoidsInRadius(position: Vector3, radius: number, excludeCharacter: Model?): { Model }
	local parts = Workspace:GetPartBoundsInRadius(position, radius, overlapParams(excludeCharacter))
	local seen: { [Model]: boolean } = {}
	local models: { Model } = {}
	for _, part in ipairs(parts) do
		local model = modelOf(part)
		if model ~= nil and not seen[model] then
			seen[model] = true
			table.insert(models, model)
		end
	end
	return models
end

local function newTracker(once: boolean): Tracker
	return { Once = once, Seen = {}, Count = 0 }
end

-- tags[1] is the i-frame key (one cast cannot hit the same target twice in a window); the archetype
-- lets CombatConfig.Block.BrokenBy recognise ultimates.
local function tagsOf(def: JutsuDef): { string }
	return { def.Id, def.Archetype }
end

-- Damages every live model within `radius` of `center` and returns the models actually damaged in
-- this call (blocked-to-zero, protected and i-framed targets are not).
local function damageArea(ctx: Context, tracker: Tracker, center: Vector3, radius: number): { Model }
	local damaged: { Model } = {}
	local tags = tagsOf(ctx.Def)
	for _, model in ipairs(humanoidsInRadius(center, radius, ctx.Caster.Character)) do
		if tracker.Once and tracker.Seen[model] then
			continue
		end
		local result = ctx.Combat.ApplyDamage(ctx.Caster, model, ctx.Def.Damage, "Jutsu", tags)
		if result.Applied > 0 then
			if not tracker.Seen[model] then
				tracker.Seen[model] = true
				tracker.Count += 1
			end
			table.insert(damaged, model)
		end
	end
	return damaged
end

local function horizontal(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return -Vector3.zAxis
	end
	return flat.Unit
end

----------------------------------------------------------------
-- Fireball: stepped projectile that explodes on contact, fuse or max range
----------------------------------------------------------------

local function explode(ctx: Context, point: Vector3, radius: number): number
	ctx.Vfx.emit({ Id = "Explosion", Origin = point, Params = { Radius = radius } })
	local tracker = newTracker(true)
	for _, model in ipairs(damageArea(ctx, tracker, point, radius)) do
		local offset = model:GetPivot().Position - point
		local away = if Vector3.new(offset.X, 0, offset.Z).Magnitude > 1e-3
			then horizontal(offset)
			else horizontal(ctx.Direction)
		ctx.Combat.knockback(model, away * FIREBALL_PUSH + Vector3.yAxis * FIREBALL_LIFT, KNOCKBACK_DURATION)
	end
	return tracker.Count
end

function JutsuEffects.Fireball(ctx: Context): number
	local params = ctx.Def.Params
	local speed = params.Speed
	local fuse = math.min(params.Fuse, MAX_PROJECTILE_SECONDS)
	local spawnOffset = params.SpawnOffset
	local direction = ctx.Direction
	ctx.Vfx.emit({
		Id = "Fireball",
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = { Speed = speed, Fuse = fuse, SpawnOffset = spawnOffset },
	})

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local casterCharacter = ctx.Caster.Character
	rayParams.FilterDescendantsInstances = if casterCharacter ~= nil then { casterCharacter } else {}

	local position = ctx.Origin.Position + direction * spawnOffset
	local travelled = 0
	local elapsed = 0
	local stopPoint: Vector3? = nil
	while stopPoint == nil do
		local dt = math.min(task.wait(), MAX_STEP_SECONDS)
		if not casterAlive(ctx) then
			return 0
		end
		elapsed += dt
		local step = speed * dt
		local nextPosition = position + direction * step
		local ray = Workspace:Raycast(position, nextPosition - position, rayParams)
		if ray ~= nil then
			stopPoint = ray.Position
		else
			position = nextPosition
			travelled += step
			if elapsed >= fuse or travelled >= ctx.Def.Range then
				stopPoint = position
			end
		end
	end
	return explode(ctx, stopPoint :: Vector3, params.BlastRadius)
end

----------------------------------------------------------------
-- WaterWave: a front that sweeps from the caster to max range, hitting each target once
----------------------------------------------------------------

function JutsuEffects.WaterWave(ctx: Context): number
	local params = ctx.Def.Params
	local origin = ctx.Origin.Position
	local direction = ctx.Direction
	ctx.Vfx.emit({
		Id = "WaterWave",
		Origin = origin,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			TravelTime = params.TravelTime,
			Range = ctx.Def.Range,
			SpawnOffset = params.SpawnOffset,
			HitRadius = params.HitRadius,
		},
	}, true)

	local tracker = newTracker(true)
	local push = direction * params.Knockback + Vector3.yAxis * WAVE_LIFT
	local span = ctx.Def.Range - params.SpawnOffset
	local elapsed = 0
	while true do
		local progress = math.clamp(elapsed / params.TravelTime, 0, 1)
		local center = origin + direction * (params.SpawnOffset + span * progress)
		for _, model in ipairs(damageArea(ctx, tracker, center, params.HitRadius)) do
			ctx.Combat.knockback(model, push, KNOCKBACK_DURATION)
		end
		if progress >= 1 then
			break
		end
		elapsed += task.wait(WAVE_STEP_SECONDS)
		if not casterAlive(ctx) then
			break
		end
	end
	return tracker.Count
end

----------------------------------------------------------------
-- EarthSpikes: a line of spikes erupting one after the other, each target hit once, players stunned
----------------------------------------------------------------

function JutsuEffects.EarthSpikes(ctx: Context): number
	local params = ctx.Def.Params
	local origin = ctx.Origin.Position
	local direction = ctx.Direction
	ctx.Vfx.emit({
		Id = "EarthSpikes",
		Origin = origin,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Count = params.Count,
			Spacing = params.Spacing,
			StartOffset = params.StartOffset,
			StepDelay = params.StepDelay,
		},
	}, true)

	local tracker = newTracker(true)
	for index = 1, params.Count do
		if index > 1 then
			task.wait(params.StepDelay)
			if not casterAlive(ctx) then
				break
			end
		end
		local point = origin + direction * (params.StartOffset + (index - 1) * params.Spacing)
		for _, model in ipairs(damageArea(ctx, tracker, point, params.HitRadius)) do
			local player = playerOf(model)
			if player ~= nil then
				ctx.Movement.applyStun(player, params.Stun)
			end
		end
	end
	return tracker.Count
end

----------------------------------------------------------------
-- WindGust: instant burst in front of the caster that shoves targets away
----------------------------------------------------------------

function JutsuEffects.WindGust(ctx: Context): number
	local params = ctx.Def.Params
	local direction = ctx.Direction
	local center = ctx.Origin.Position + direction * params.Offset
	ctx.Vfx.emit({
		Id = "WindGust",
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = params.Radius, Offset = params.Offset },
	})

	local tracker = newTracker(true)
	local push = direction * params.Push + Vector3.yAxis * params.Lift
	for _, model in ipairs(damageArea(ctx, tracker, center, params.Radius)) do
		ctx.Combat.knockback(model, push, KNOCKBACK_DURATION)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- BoilingMist: fixed zone that burns and slows on every tick
----------------------------------------------------------------

function JutsuEffects.BoilingMist(ctx: Context): number
	local params = ctx.Def.Params
	local center = ctx.Origin.Position + ctx.Direction * params.Offset
	ctx.Vfx.emit({
		Id = "BoilingMist",
		Origin = center,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = params.Radius, Duration = params.Ticks * params.TickInterval },
	}, true)

	local tracker = newTracker(false)
	for tick = 1, params.Ticks do
		if tick > 1 then
			task.wait(params.TickInterval)
			if not casterAlive(ctx) then
				break
			end
		end
		for _, model in ipairs(damageArea(ctx, tracker, center, params.Radius)) do
			local player = playerOf(model)
			if player ~= nil then
				ctx.Movement.applySlow(player, params.SlowFactor, params.SlowDuration)
			end
		end
	end
	return tracker.Count
end

----------------------------------------------------------------
-- MudWall: invisible collision wall in front of the caster (clients render the visual)
----------------------------------------------------------------

function JutsuEffects.MudWall(ctx: Context): number
	local params = ctx.Def.Params
	local base = ctx.Origin * CFrame.new(0, 0, -params.Offset)
	local floorY = ctx.Origin.Position.Y - ROOT_FLOOR_OFFSET

	local wall = Instance.new("Part")
	wall.Name = WALL_NAME
	wall.Size = Vector3.new(params.Width, params.Height, params.Thickness)
	wall.CFrame = CFrame.new(base.Position.X, floorY + params.Height / 2, base.Position.Z) * base.Rotation
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = true
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Transparency = 1
	CollectionService:AddTag(wall, COLLISION_TAG)
	wall.Parent = Workspace
	Debris:AddItem(wall, params.Duration)

	ctx.Vfx.emit({
		Id = "MudWall",
		Origin = wall.Position,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Width = params.Width,
			Height = params.Height,
			Thickness = params.Thickness,
			Duration = params.Duration,
		},
	}, true)
	return 0
end

----------------------------------------------------------------
-- EmberStorm: zone that follows the caster and burns on every tick
----------------------------------------------------------------

function JutsuEffects.EmberStorm(ctx: Context): number
	local params = ctx.Def.Params
	ctx.Vfx.emit({
		Id = "EmberStorm",
		Origin = ctx.Origin.Position,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = params.Radius, Duration = params.Ticks * params.TickInterval },
	}, true)

	local tracker = newTracker(false)
	for tick = 1, params.Ticks do
		if tick > 1 then
			task.wait(params.TickInterval)
		end
		local root = liveRoot(ctx.Caster)
		if root == nil then
			break
		end
		damageArea(ctx, tracker, root.Position, params.Radius)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Earthquake: instant shockwave around the caster that launches and stuns
----------------------------------------------------------------

function JutsuEffects.Earthquake(ctx: Context): number
	local params = ctx.Def.Params
	local origin = ctx.Origin.Position
	ctx.Vfx.emit({
		Id = "Earthquake",
		Origin = origin,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = params.Radius },
	})

	local tracker = newTracker(true)
	local launch = Vector3.yAxis * params.Launch
	for _, model in ipairs(damageArea(ctx, tracker, origin, params.Radius)) do
		ctx.Combat.knockback(model, launch, KNOCKBACK_DURATION)
		local player = playerOf(model)
		if player ~= nil then
			ctx.Movement.applyStun(player, params.Stun)
		end
	end
	return tracker.Count
end

return JutsuEffects
