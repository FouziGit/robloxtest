--!strict
-- GlyphEffects: server-side hit detection for every glyph, keyed by GlyphConfig `Effect` id.
-- Effects build NO visual effects: they detect targets (spatial queries, stepped raycasts, collision
-- parts for walls), deal damage through CombatService.ApplyDamage only, and broadcast Vfx packets that
-- each client renders, under the glyph's own `VfxId` and carrying its `Pigment`. The one look set here
-- is the Margin slab's own colour and its rise and sink: a thing that blocks must be seen by everyone it
-- blocks, on every quality tier, so its geometry carries it (WorldConfig.Glyphs, D-108 and D-110).
-- Timed effects step inline in the caller's thread (the remote handler runs in its own thread) and stop
-- early when the caster dies, leaves, raises guard or is stunned.
-- Every effect returns the number of distinct models it damaged.
--
-- The helper section owns every shape the roster needs: spheres and boxes of live humanoids, a
-- stepped projectile (straight or arcing under a gravity), a hitscan beam that only walls stop, a
-- ticking zone, a chain search and the raycast-validated teleport destination of Caret. An
-- effect adds geometry, never a new query or a magic number: all tuning comes from `Def.Params`.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CombatConfig = require(Shared.Config.CombatConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Palette = require(Shared.Util.Palette)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

export type GlyphDef = GlyphConfig.GlyphDef
export type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
export type CombatApi = {
	ApplyDamage: (
		source: Player?,
		targetModel: Model,
		amount: number,
		kind: string,
		tags: { string },
		pigment: string?
	) -> DamageResult,
	knockback: (targetModel: Model, velocity: Vector3, duration: number) -> (),
	applyStoneSkin: (player: Player) -> boolean,
	grantIFrames: (player: Player, seconds: number) -> (),
	isBlocking: (player: Player) -> boolean,
	isStunned: (player: Player) -> boolean,
	-- Called after an effect teleports its caster, with the position the SERVER chose. Passing nothing
	-- would re-anchor trust on whatever the client replicated, which is the value none of this believes.
	resyncPosition: (player: Player, position: Vector3?) -> (),
	-- Issues a movement command and grants the travel it covers in one call. Every displacement an effect
	-- asks for goes through this, never through Movement.command, or the travel budget is not told.
	grantMovement: (
		player: Player,
		command: { Kind: "Dash", Direction: Vector3, Distance: number, Duration: number }
	) -> (),
	-- The caster origin the server is willing to believe, re-validated at call time. An effect that keeps
	-- damaging around the caster must follow this, not the raw root.
	trustedOrigin: (player: Player) -> CFrame?,
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
-- No `command` here on purpose: an effect that displaces its caster goes through
-- CombatApi.grantMovement, which issues the command AND grants the travel it covers. Exposing the raw
-- command again would let a future effect forget the second half.
export type MovementApi = {
	applySlow: (player: Player, key: string, factor: number, seconds: number) -> (),
	applyStun: (player: Player, seconds: number) -> (),
}
export type Context = {
	Caster: Player,
	Def: GlyphDef,
	Origin: CFrame,
	Direction: Vector3,
	Combat: CombatApi,
	Vfx: VfxApi,
	Movement: MovementApi,
}
export type Effect = (ctx: Context) -> number

-- Tracks the models damaged across the steps of one cast. `MaxHits` = how often one model may be
-- damaged by this cast: 1 for a wave or a spike line, `math.huge` for a zone that ticks every
-- interval, a small cap for the Ligature trail. `Tags` is built once: tags[1] is the i-frame key
-- CombatService keys its hit memory on, tags[2] lets CombatConfig.Block.BrokenBy see an ultimate.
type Tracker = { MaxHits: number, Hits: { [Model]: number }, Count: number, Tags: { string } }
-- One candidate of a distance ranking (hitscan beam, chain arc, projectile proximity scan).
type Ranked = { Model: Model, Distance: number }
-- Where a stepped projectile stopped, and the live model it stopped on (nil = geometry, fuse, range).
type ProjectileStop = { Point: Vector3, Model: Model? }

-- Server collision geometry (walls) carries this tag so spatial queries skip it.
local COLLISION_TAG = WorldConfig.Glyphs.CollisionTag
local ROOT_PART_NAME = "HumanoidRootPart"
local WALL_NAME = WorldConfig.Glyphs.WallName
-- A projectile fuse is clamped so a synchronous effect never pins the remote handler for long.
local MAX_PROJECTILE_SECONDS = 1.5
-- Longest simulated step: a frame hitch must not teleport a projectile through targets.
local MAX_STEP_SECONDS = 0.1
local WAVE_STEP_SECONDS = 0.05
-- A hitscan beam is re-cast at most this many times to skip the characters standing in it; the cap
-- keeps the loop bounded when a crowd fills the whole line.
local MAX_HITSCAN_CASTS = 8
-- Blast push (horizontal, away from the blast) and lift applied to players caught in an explosion.
local BRAND_PUSH = 40
local BRAND_LIFT = 20
local WAVE_LIFT = 10
-- Humanoid roots float about this high above the floor (HipHeight + half the root height).
local ROOT_FLOOR_OFFSET = 3
local KNOCKBACK_DURATION = CombatConfig.Hit.KnockbackDurationSeconds
-- Self buff of the Gilding glyph: CombatService reads the attribute in ApplyDamage.
local STONE_SKIN = CombatConfig.Status.Gilding
local EPSILON = 1e-3

local GlyphEffects = {}

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

-- Root of the caster while the cast may still deal damage: in the game with a live character, not
-- guarding and not stunned. GlyphService applies the same rule once at cast time; timed effects
-- re-check it on every step so raising guard, dashing into a stun or being stunned stops waves,
-- spike lines and zones instead of letting them tick under guard.
local function casterRoot(ctx: Context): BasePart?
	local root = liveRoot(ctx.Caster)
	if root == nil then
		return nil
	end
	if ctx.Combat.isBlocking(ctx.Caster) or ctx.Combat.isStunned(ctx.Caster) then
		return nil
	end
	return root
end

local function casterAlive(ctx: Context): boolean
	return casterRoot(ctx) ~= nil
end

-- Closest ancestor Model owning a Humanoid, alive or not (player characters, NPC dummies).
local function characterOf(part: BasePart): (Model?, Humanoid?)
	local ancestor: Instance? = part.Parent
	while ancestor ~= nil do
		if ancestor:IsA("Model") then
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				return ancestor :: Model, humanoid
			end
		end
		ancestor = ancestor.Parent
	end
	return nil, nil
end

-- Closest ancestor Model with a live Humanoid (accessories and tools nest parts under it).
local function modelOf(part: BasePart): Model?
	local model, humanoid = characterOf(part)
	if model == nil or humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return model
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

-- Distinct models with a live Humanoid among the parts of a spatial query.
local function distinctModels(parts: { BasePart }): { Model }
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

-- Distinct models with a live Humanoid whose parts overlap the sphere (caster and walls excluded).
local function humanoidsInRadius(position: Vector3, radius: number, excludeCharacter: Model?): { Model }
	return distinctModels(Workspace:GetPartBoundsInRadius(position, radius, overlapParams(excludeCharacter)))
end

-- Same, for an oriented box: beams use it to sweep the whole line in one query.
local function humanoidsInBox(box: CFrame, size: Vector3, excludeCharacter: Model?): { Model }
	return distinctModels(Workspace:GetPartBoundsInBox(box, size, overlapParams(excludeCharacter)))
end

-- The `count` models closest to `position`, nearest first.
local function nearestModels(models: { Model }, position: Vector3, count: number): { Model }
	local ranked: { Ranked } = {}
	for _, model in ipairs(models) do
		table.insert(ranked, { Model = model, Distance = (model:GetPivot().Position - position).Magnitude })
	end
	table.sort(ranked, function(left: Ranked, right: Ranked): boolean
		return left.Distance < right.Distance
	end)
	local result: { Model } = {}
	for index = 1, math.min(count, #ranked) do
		table.insert(result, ranked[index].Model)
	end
	return result
end

-- The single model closest to `position`, or nil when nothing is in range.
local function nearestModel(models: { Model }, position: Vector3): Model?
	local ranked = nearestModels(models, position, 1)
	if #ranked == 0 then
		return nil
	end
	return ranked[1]
end

local function newTracker(def: GlyphDef, maxHits: number): Tracker
	return { MaxHits = maxHits, Hits = {}, Count = 0, Tags = { def.Id, def.Archetype } }
end

-- Damages one model through the single damage path, honouring the per-cast hit cap. Returns whether
-- damage landed: blocked-to-zero, spawn-protected and i-framed targets did not take any.
local function damageModel(ctx: Context, tracker: Tracker, model: Model): boolean
	local hits = tracker.Hits[model]
	if hits ~= nil and hits >= tracker.MaxHits then
		return false
	end
	local result = ctx.Combat.ApplyDamage(ctx.Caster, model, ctx.Def.Damage, "Glyph", tracker.Tags, ctx.Def.Pigment)
	if result.Applied <= 0 then
		return false
	end
	if hits == nil then
		tracker.Count += 1
	end
	tracker.Hits[model] = (hits or 0) + 1
	return true
end

-- Damages every live model within `radius` of `center` and returns the models actually damaged in
-- this call (blocked-to-zero, protected and i-framed targets are not).
local function damageArea(ctx: Context, tracker: Tracker, center: Vector3, radius: number): { Model }
	local damaged: { Model } = {}
	for _, model in ipairs(humanoidsInRadius(center, radius, ctx.Caster.Character)) do
		if damageModel(ctx, tracker, model) then
			table.insert(damaged, model)
		end
	end
	return damaged
end

local function horizontal(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < EPSILON then
		return -Vector3.zAxis
	end
	return flat.Unit
end

local function excludeParams(character: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	return params
end

-- Steps a projectile in the caller's thread: `velocity` studs/s, `gravity` studs/s² pulling it down
-- (0 = straight line). It stops on the first obstruction a ray finds — a Margin and the terrain
-- included, which is how Umber blocks projectiles —, on the first live model within `hitRadius`
-- (0 = no proximity scan: the blast of an exploding projectile finds its own targets), once
-- `maxDistance` of path has been travelled or when the fuse burns out. Returns nil as soon as the
-- cast stops qualifying (caster dead, guarding or stunned) so nothing lands afterwards.
local function stepProjectile(
	ctx: Context,
	start: Vector3,
	velocity: Vector3,
	gravity: number,
	fuse: number,
	maxDistance: number,
	hitRadius: number
): ProjectileStop?
	local character = ctx.Caster.Character
	local rayParams = excludeParams(character)
	local position = start
	local travelled = 0
	local elapsed = 0
	while true do
		local dt = math.min(task.wait(), MAX_STEP_SECONDS)
		if not casterAlive(ctx) then
			return nil
		end
		elapsed += dt
		if gravity ~= 0 then
			velocity -= Vector3.yAxis * (gravity * dt)
		end
		local step = velocity * dt
		local ray = Workspace:Raycast(position, step, rayParams)
		if ray ~= nil then
			return { Point = ray.Position, Model = modelOf(ray.Instance) }
		end
		position += step
		travelled += step.Magnitude
		if hitRadius > 0 then
			local nearest = nearestModel(humanoidsInRadius(position, hitRadius, character), position)
			if nearest ~= nil then
				return { Point = position, Model = nearest }
			end
		end
		if elapsed >= fuse or travelled >= maxDistance then
			return { Point = position, Model = nil }
		end
	end
end

-- First obstruction of a beam, ignoring characters: the ray is re-cast past every model it crosses
-- so a crowd never shortens the beam, and only walls, terrain and props stop it.
local function geometryStop(start: Vector3, direction: Vector3, range: number, character: Model?): Vector3
	local rayParams = excludeParams(character)
	local filter: { Instance } = rayParams.FilterDescendantsInstances
	for _ = 1, MAX_HITSCAN_CASTS do
		local ray = Workspace:Raycast(start, direction * range, rayParams)
		if ray == nil then
			break
		end
		local model = characterOf(ray.Instance)
		if model == nil then
			return ray.Position
		end
		table.insert(filter, model)
		rayParams.FilterDescendantsInstances = filter
	end
	return start + direction * range
end

-- Hitscan: the models within `radius` of the beam between the caster and the first obstruction,
-- nearest first, plus that stop point (the length the client draws).
local function hitscan(
	ctx: Context,
	start: Vector3,
	direction: Vector3,
	range: number,
	radius: number
): ({ Model }, Vector3)
	local character = ctx.Caster.Character
	local stop = geometryStop(start, direction, range, character)
	local span = stop - start
	local length = span.Magnitude
	if length < EPSILON then
		return {}, stop
	end
	local box = CFrame.lookAt(start + span / 2, stop)
	local models = humanoidsInBox(box, Vector3.new(radius * 2, radius * 2, length), character)
	return nearestModels(models, start, #models), stop
end

-- Ticks a zone `ticks` times every `interval` seconds: each tick damages every live model within
-- `radius` of the fixed `center` and hands the models it damaged to `onHit` (slow, stun, pull).
local function tickZone(
	ctx: Context,
	center: Vector3,
	radius: number,
	ticks: number,
	interval: number,
	onHit: ((Model) -> ())?
): number
	local tracker = newTracker(ctx.Def, math.huge)
	for tick = 1, ticks do
		if tick > 1 then
			task.wait(interval)
			if not casterAlive(ctx) then
				break
			end
		end
		for _, model in ipairs(damageArea(ctx, tracker, center, radius)) do
			if onHit ~= nil then
				onHit(model)
			end
		end
	end
	return tracker.Count
end

-- Detonation shared by the exploding projectiles: one "Explosion" packet, one damage pass, and a
-- push away from the blast for everything it hurt.
local function explode(ctx: Context, point: Vector3, radius: number, push: number, lift: number): number
	ctx.Vfx.emit({ Id = "Explosion", Origin = point, Params = { Radius = radius, Pigment = ctx.Def.Pigment } })
	local tracker = newTracker(ctx.Def, 1)
	for _, model in ipairs(damageArea(ctx, tracker, point, radius)) do
		local offset = model:GetPivot().Position - point
		local away = if Vector3.new(offset.X, 0, offset.Z).Magnitude > EPSILON
			then horizontal(offset)
			else horizontal(ctx.Direction)
		ctx.Combat.knockback(model, away * push + Vector3.yAxis * lift, KNOCKBACK_DURATION)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Brand: stepped projectile that explodes on contact, fuse or max range
----------------------------------------------------------------

function GlyphEffects.Brand(ctx: Context): number
	local params = ctx.Def.Params
	local fuse = math.min(params.Fuse, MAX_PROJECTILE_SECONDS)
	local direction = ctx.Direction
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = { Speed = params.Speed, Fuse = fuse, SpawnOffset = params.SpawnOffset, Pigment = ctx.Def.Pigment },
	})

	local stop = stepProjectile(
		ctx,
		ctx.Origin.Position + direction * params.SpawnOffset,
		direction * params.Speed,
		0,
		fuse,
		ctx.Def.Range,
		0
	)
	if stop == nil then
		return 0
	end
	return explode(ctx, stop.Point, params.BlastRadius, BRAND_PUSH, BRAND_LIFT)
end

----------------------------------------------------------------
-- Wash: a front that sweeps from the caster to max range, hitting each target once
----------------------------------------------------------------

function GlyphEffects.Wash(ctx: Context): number
	local params = ctx.Def.Params
	local origin = ctx.Origin.Position
	local direction = ctx.Direction
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = origin,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			TravelTime = params.TravelTime,
			Range = ctx.Def.Range,
			SpawnOffset = params.SpawnOffset,
			HitRadius = params.HitRadius,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	local tracker = newTracker(ctx.Def, 1)
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
-- Serif: a line of spikes erupting one after the other, each target hit once, players stunned
----------------------------------------------------------------

function GlyphEffects.Serif(ctx: Context): number
	local params = ctx.Def.Params
	local origin = ctx.Origin.Position
	local direction = ctx.Direction
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = origin,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Count = params.Count,
			Spacing = params.Spacing,
			StartOffset = params.StartOffset,
			StepDelay = params.StepDelay,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	local tracker = newTracker(ctx.Def, 1)
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
-- Sweep: instant burst in front of the caster that shoves targets away
----------------------------------------------------------------

function GlyphEffects.Sweep(ctx: Context): number
	local params = ctx.Def.Params
	local direction = ctx.Direction
	local center = ctx.Origin.Position + direction * params.Offset
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = params.Radius, Offset = params.Offset, Pigment = ctx.Def.Pigment },
	})

	local tracker = newTracker(ctx.Def, 1)
	local push = direction * params.Push + Vector3.yAxis * params.Lift
	for _, model in ipairs(damageArea(ctx, tracker, center, params.Radius)) do
		ctx.Combat.knockback(model, push, KNOCKBACK_DURATION)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Bleed: fixed zone that burns and slows on every tick
----------------------------------------------------------------

function GlyphEffects.Bleed(ctx: Context): number
	local params = ctx.Def.Params
	local center = ctx.Origin.Position + ctx.Direction * params.Offset
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = center,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Radius = params.Radius,
			Duration = params.Ticks * params.TickInterval,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	return tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval, function(model: Model)
		local player = playerOf(model)
		if player ~= nil then
			ctx.Movement.applySlow(player, ctx.Def.Id, params.SlowFactor, params.SlowDuration)
		end
	end)
end

----------------------------------------------------------------
-- Margin: a collision wall in front of the caster, drawn by its own slab (clients add the ink)
----------------------------------------------------------------

-- Live walls per caster. Their only bound used to be arithmetic: the wall lasts Params.Duration (6 s) and
-- the glyph recharges in Cooldown (10 s), so one could exist at a time. Nothing stated that, and anything
-- that shortens the cooldown turns a solid 14 by 9 stud slab into something the caster can
-- stack until the hub is a maze. The cap makes the invariant explicit and independent of the cooldown.
local MAX_WALLS_PER_CASTER = 2
local wallsByCaster: { [Player]: { BasePart } } = {}

local function retireOldestWall(caster: Player, wall: BasePart)
	local live = wallsByCaster[caster]
	if live == nil then
		live = {}
		wallsByCaster[caster] = live
	end
	-- Drop the ones Debris already collected before counting.
	for index = #live, 1, -1 do
		if live[index].Parent == nil then
			table.remove(live, index)
		end
	end
	while #live >= MAX_WALLS_PER_CASTER do
		local oldest = table.remove(live, 1)
		if oldest ~= nil then
			oldest:Destroy()
		end
	end
	table.insert(live, wall)
end

-- The table is released here rather than by a service, so nothing has to remember to call it. The walls
-- themselves belong to Debris and expire on their own.
Players.PlayerRemoving:Connect(function(player: Player)
	wallsByCaster[player] = nil
end)

function GlyphEffects.Margin(ctx: Context): number
	local params = ctx.Def.Params
	local base = ctx.Origin * CFrame.new(0, 0, -params.Offset)
	local floorY = ctx.Origin.Position.Y - ROOT_FLOOR_OFFSET

	-- Standing, and sunk: the slab's two places. It rises out of the page with its collision and goes
	-- back into it before Debris takes it, so what blocks is always exactly what is drawn.
	local standing = CFrame.new(base.Position.X, floorY + params.Height / 2, base.Position.Z) * base.Rotation
	local sunk = standing * CFrame.new(0, -params.Height, 0)
	local wall = Instance.new("Part")
	wall.Name = WALL_NAME
	wall.Size = Vector3.new(params.Width, params.Height, params.Thickness)
	wall.CFrame = sunk
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = true
	wall.CanTouch = false
	wall.CastShadow = false
	-- The slab carries the look (WorldConfig.Glyphs, D-110): a wall of its glyph's own pigment, solid, on
	-- every quality tier, because the thing that blocks must be seen by everyone it blocks. Paled toward
	-- the page, like dry earth, so the client's ink -- the full pigment, ruled on the floor and painted
	-- on the faces -- reads darker on it instead of vanishing into a wall of the same colour. The shade is
	-- CosmeticConfig's measured one: the school stays readable at it.
	local look = WorldConfig.Glyphs
	local colors = (PigmentConfig.Colors :: any) :: { [string]: { number } }
	local pigment = colors[ctx.Def.Pigment] or colors.Umber
	wall.Color =
		Palette.rgb(CosmeticConfig.shade(pigment, look.WallShade, WorldConfig.Colors.Ink, WorldConfig.Colors.Page))
	wall.Material = Palette.material()
	CollectionService:AddTag(wall, COLLISION_TAG)
	wall.Parent = Workspace
	Debris:AddItem(wall, params.Duration)
	retireOldestWall(ctx.Caster, wall)
	TweenService:Create(
		wall,
		TweenInfo.new(look.WallRiseSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = standing }
	):Play()
	task.delay(math.max(0, params.Duration - look.WallSinkSeconds), function()
		if wall.Parent ~= nil then
			TweenService:Create(
				wall,
				TweenInfo.new(look.WallSinkSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = sunk }
			):Play()
		end
	end)

	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = standing.Position,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Width = params.Width,
			Height = params.Height,
			Thickness = params.Thickness,
			Duration = params.Duration,
			Pigment = ctx.Def.Pigment,
		},
	}, true)
	return 0
end

----------------------------------------------------------------
-- Scorch: zone that follows the caster and burns on every tick
----------------------------------------------------------------

function GlyphEffects.Scorch(ctx: Context): number
	local params = ctx.Def.Params
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Radius = params.Radius,
			Duration = params.Ticks * params.TickInterval,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	local tracker = newTracker(ctx.Def, math.huge)
	for tick = 1, params.Ticks do
		if tick > 1 then
			task.wait(params.TickInterval)
		end
		-- Re-validated every tick. Reading the raw root here made the validated origin decorative: a
		-- client could move itself onto a different victim between ticks and the zone followed.
		local centre = ctx.Combat.trustedOrigin(ctx.Caster)
		if centre == nil then
			break
		end
		damageArea(ctx, tracker, centre.Position, params.Radius)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Rupture: instant shockwave around the caster that launches and stuns
----------------------------------------------------------------

function GlyphEffects.Rupture(ctx: Context): number
	local params = ctx.Def.Params
	local origin = ctx.Origin.Position
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = origin,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = params.Radius, Pigment = ctx.Def.Pigment },
	})

	local tracker = newTracker(ctx.Def, 1)
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

----------------------------------------------------------------
-- Ligature: forward dash that leaves a line of burning pools behind it
----------------------------------------------------------------

function GlyphEffects.Ligature(ctx: Context): number
	local params = ctx.Def.Params
	local direction = horizontal(ctx.Direction)
	local start = ctx.Origin.Position
	-- Pools are laid along the dash path at cast time: the trail stays where the caster ran, and the
	-- client renders the very same points.
	local trail: { Vector3 } = {}
	for index = 1, params.TrailSegments do
		table.insert(trail, start + direction * ((index - 1) * params.TrailSpacing))
	end
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = start,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Range = ctx.Def.Range,
			DashDuration = params.DashDuration,
			TrailSegments = params.TrailSegments,
			TrailSpacing = params.TrailSpacing,
			TrailRadius = params.TrailRadius,
			Duration = params.Ticks * params.TickInterval,
			Pigment = ctx.Def.Pigment,
		},
	}, true)
	-- The character is client-simulated: the dash itself is a server-approved movement command, issued
	-- through grantMovement so its distance joins the caster's travel budget. Going straight to
	-- Movement.command made this glyph's own gap-close look like a teleport, and the melee it exists to
	-- set up was clamped back to where the dash started.
	ctx.Combat.grantMovement(ctx.Caster, {
		Kind = "Dash",
		Direction = direction,
		Distance = ctx.Def.Range,
		Duration = params.DashDuration,
	})

	local tracker = newTracker(ctx.Def, params.MaxHitsPerTarget)
	for tick = 1, params.Ticks do
		if tick > 1 then
			task.wait(params.TickInterval)
			if not casterAlive(ctx) then
				break
			end
		end
		for _, point in ipairs(trail) do
			damageArea(ctx, tracker, point, params.TrailRadius)
		end
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Blot: heavy arcing projectile, detonates in a wide blast and breaks guards (Ultimate)
----------------------------------------------------------------

function GlyphEffects.Blot(ctx: Context): number
	local params = ctx.Def.Params
	local direction = horizontal(ctx.Direction)
	local fuse = math.min(params.Fuse, MAX_PROJECTILE_SECONDS)
	-- Bell arc: rising at `rise` under `gravity`, the meteor peaks at ArcHeight after half the fuse
	-- and is back at cast height when the fuse burns out. The client re-simulates from these two.
	local rise = 4 * params.ArcHeight / fuse
	local gravity = 2 * rise / fuse
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Speed = params.Speed,
			ArcHeight = params.ArcHeight,
			Fuse = fuse,
			SpawnOffset = params.SpawnOffset,
			BlastRadius = params.BlastRadius,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	local stop = stepProjectile(
		ctx,
		ctx.Origin.Position + direction * params.SpawnOffset,
		direction * params.Speed + Vector3.yAxis * rise,
		gravity,
		fuse,
		ctx.Def.Range,
		0
	)
	if stop == nil then
		return 0
	end
	return explode(ctx, stop.Point, params.BlastRadius, params.Knockback, params.Lift)
end

----------------------------------------------------------------
-- Binding: roots the closest target in front of the caster
----------------------------------------------------------------

function GlyphEffects.Binding(ctx: Context): number
	local params = ctx.Def.Params
	local center = ctx.Origin.Position + ctx.Direction * params.Offset
	local targets =
		nearestModels(humanoidsInRadius(center, params.HitRadius, ctx.Caster.Character), center, params.MaxTargets)

	local tracker = newTracker(ctx.Def, 1)
	local points: { Vector3 } = {}
	for _, model in ipairs(targets) do
		if damageModel(ctx, tracker, model) then
			table.insert(points, model:GetPivot().Position)
			local player = playerOf(model)
			if player ~= nil then
				-- Root, not stun: WalkSpeed pinned at zero leaves the victim able to fight back.
				ctx.Movement.applySlow(player, ctx.Def.Id, params.RootSlowFactor, params.RootDuration)
			end
		end
	end
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = center,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Targets = points,
		-- Origin is already the centre of the grab, so the packet carries no Offset: the renderer
		-- falls back to Origin itself when the prison caught nobody.
		Params = { Radius = params.HitRadius, RootDuration = params.RootDuration, Pigment = ctx.Def.Pigment },
	}, true)
	return tracker.Count
end

----------------------------------------------------------------
-- Stipple: fast direct-hit projectile that slows what it hits
----------------------------------------------------------------

function GlyphEffects.Stipple(ctx: Context): number
	local params = ctx.Def.Params
	local direction = ctx.Direction
	local fuse = math.min(params.Fuse, MAX_PROJECTILE_SECONDS)
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Speed = params.Speed,
			Fuse = fuse,
			SpawnOffset = params.SpawnOffset,
			HitRadius = params.HitRadius,
			Pigment = ctx.Def.Pigment,
		},
	})

	local stop = stepProjectile(
		ctx,
		ctx.Origin.Position + direction * params.SpawnOffset,
		direction * params.Speed,
		0,
		fuse,
		ctx.Def.Range,
		params.HitRadius
	)
	if stop == nil then
		return 0
	end
	local target = stop.Model
	if target == nil then
		return 0
	end
	local tracker = newTracker(ctx.Def, 1)
	if not damageModel(ctx, tracker, target) then
		return 0
	end
	local player = playerOf(target)
	if player ~= nil then
		ctx.Movement.applySlow(player, ctx.Def.Id, params.SlowFactor, params.SlowDuration)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Gilding: self buff, damage reduction and knockback immunity read by CombatService
----------------------------------------------------------------

function GlyphEffects.Gilding(ctx: Context): number
	local root = casterRoot(ctx)
	if root == nil then
		return 0
	end
	-- CombatService owns the status: it writes the attribute that ApplyDamage and knockback read, and
	-- refuses when the caster has no live Humanoid — nothing to render then.
	if not ctx.Combat.applyStoneSkin(ctx.Caster) then
		return 0
	end

	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = root.Position,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = { Radius = ctx.Def.Range, Duration = STONE_SKIN.DurationSeconds, Pigment = ctx.Def.Pigment },
	}, true)
	return 0
end

----------------------------------------------------------------
-- Hairline: fast direct-hit projectile; being Verdigris, it marks its target Fanned through ApplyDamage
----------------------------------------------------------------

function GlyphEffects.Hairline(ctx: Context): number
	local params = ctx.Def.Params
	local direction = ctx.Direction
	local fuse = math.min(params.Fuse, MAX_PROJECTILE_SECONDS)
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Speed = params.Speed,
			Fuse = fuse,
			SpawnOffset = params.SpawnOffset,
			Pigment = ctx.Def.Pigment,
		},
	})

	local stop = stepProjectile(
		ctx,
		ctx.Origin.Position + direction * params.SpawnOffset,
		direction * params.Speed,
		0,
		fuse,
		ctx.Def.Range,
		params.HitRadius
	)
	if stop == nil then
		return 0
	end
	local target = stop.Model
	if target == nil then
		return 0
	end
	local tracker = newTracker(ctx.Def, 1)
	if damageModel(ctx, tracker, target) then
		ctx.Combat.knockback(target, direction * params.Knockback, KNOCKBACK_DURATION)
	end
	return tracker.Count
end

----------------------------------------------------------------
-- Spiral: zone that drags everything it damages toward its centre on every tick
----------------------------------------------------------------

function GlyphEffects.Spiral(ctx: Context): number
	local params = ctx.Def.Params
	local center = ctx.Origin.Position + ctx.Direction * params.Offset
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = center,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Radius = params.Radius,
			Duration = params.Ticks * params.TickInterval,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	return tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval, function(model: Model)
		local offset = center - model:GetPivot().Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= params.PullMinDistance then
			return
		end
		-- Never drag a target past the eye of the storm: one pull covers its distance at most.
		local speed = math.min(params.PullSpeed, flat.Magnitude / KNOCKBACK_DURATION)
		ctx.Combat.knockback(model, flat.Unit * speed, KNOCKBACK_DURATION)
	end)
end

----------------------------------------------------------------
-- Pounce: wide zone that slows everything inside on every tick
----------------------------------------------------------------

function GlyphEffects.Pounce(ctx: Context): number
	local params = ctx.Def.Params
	local center = ctx.Origin.Position + ctx.Direction * params.Offset
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = center,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Radius = params.Radius,
			Duration = params.Ticks * params.TickInterval,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	return tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval, function(model: Model)
		local player = playerOf(model)
		if player ~= nil then
			ctx.Movement.applySlow(player, ctx.Def.Id, params.SlowFactor, params.SlowDuration)
		end
	end)
end

----------------------------------------------------------------
-- Strike: hitscan beam, no travel time
----------------------------------------------------------------

function GlyphEffects.Strike(ctx: Context): number
	local params = ctx.Def.Params
	local direction = horizontal(ctx.Direction)
	local start = ctx.Origin.Position + direction * params.SpawnOffset
	local candidates, stop = hitscan(ctx, start, direction, ctx.Def.Range, params.HitRadius)

	local tracker = newTracker(ctx.Def, 1)
	local points: { Vector3 } = {}
	for _, model in ipairs(candidates) do
		if #points >= params.MaxTargets then
			break
		end
		if damageModel(ctx, tracker, model) then
			table.insert(points, model:GetPivot().Position)
			ctx.Combat.knockback(model, direction * params.Knockback, KNOCKBACK_DURATION)
		end
	end
	-- Origin is the caster, not the muzzle: the renderer offsets by SpawnOffset itself, and Range is
	-- the beam length from there (the point the server validated is in Targets).
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Targets = points,
		Params = {
			SpawnOffset = params.SpawnOffset,
			Range = (stop - start).Magnitude,
			Pigment = ctx.Def.Pigment,
		},
	})
	return tracker.Count
end

----------------------------------------------------------------
-- Caret: teleport forward, to a destination the server validates
----------------------------------------------------------------

-- A destination is valid when there is ground within `snap` studs under it and nothing overlaps the
-- clearance sphere around the landing point. Returns the landing position, or nil when the spot is
-- inside geometry, occupied by another character or hanging over the void. The downward ray keeps
-- the terrain (that is the ground it looks for), the clearance sphere drops it: Terrain is one part
-- whose bounds span the whole map, so every landing would read as blocked.
local function landingPosition(candidate: Vector3, clearance: number, snap: number, character: Model): Vector3?
	local down = Workspace:Raycast(candidate, -Vector3.yAxis * (snap + ROOT_FLOOR_OFFSET), excludeParams(character))
	if down == nil then
		return nil
	end
	local landing = Vector3.new(candidate.X, down.Position.Y + ROOT_FLOOR_OFFSET, candidate.Z)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, Workspace.Terrain }
	if #Workspace:GetPartBoundsInRadius(landing, clearance, params) > 0 then
		return nil
	end
	return landing
end

function GlyphEffects.Caret(ctx: Context): number
	local params = ctx.Def.Params
	local root = casterRoot(ctx)
	local character: Model? = ctx.Caster.Character
	if root == nil or character == nil then
		return 0
	end
	local direction = horizontal(ctx.Direction)
	-- The VALIDATED origin, never root.Position: the step is computed from it and then re-anchors trust on
	-- where it landed, so reading the raw root here would have let a client teleport itself anywhere and
	-- have the server certify the result.
	local start = ctx.Origin.Position
	-- Never through a wall: the reach stops WallBackoffStuds short of the first obstruction.
	local blocker = Workspace:Raycast(start, direction * ctx.Def.Range, excludeParams(character))
	local reach = if blocker ~= nil
		then math.max((blocker.Position - start).Magnitude - params.WallBackoffStuds, 0)
		else ctx.Def.Range
	-- Never off the arena: candidates walk back toward the caster until one lands on solid ground.
	local destination: Vector3? = nil
	local distance = reach
	while distance > 0 and destination == nil do
		destination =
			landingPosition(start + direction * distance, params.ClearanceRadius, params.GroundSnapStuds, character)
		distance -= params.ClearanceRadius
	end
	if destination == nil then
		return 0
	end

	local landing = destination
	ctx.Combat.grantIFrames(ctx.Caster, params.IFrameSeconds)
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = start,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Targets = { landing },
		Params = {
			Range = (landing - start).Magnitude,
			IFrameSeconds = params.IFrameSeconds,
			Pigment = ctx.Def.Pigment,
		},
	}, true)
	character:PivotTo(CFrame.new(landing) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	-- The destination the server chose, passed explicitly: the caster must be able to attack from where
	-- they landed, and trust must anchor on that point rather than on whatever the client now reports.
	ctx.Combat.resyncPosition(ctx.Caster, landing)
	return 0
end

----------------------------------------------------------------
-- Watermark: zone that micro-stuns on every tick
----------------------------------------------------------------

function GlyphEffects.Watermark(ctx: Context): number
	local params = ctx.Def.Params
	local center = ctx.Origin.Position + ctx.Direction * params.Offset
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = center,
		Direction = ctx.Direction,
		Caster = ctx.Caster.UserId,
		Params = {
			Radius = params.Radius,
			Duration = params.Ticks * params.TickInterval,
			Pigment = ctx.Def.Pigment,
		},
	}, true)

	return tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval, function(model: Model)
		local player = playerOf(model)
		if player ~= nil then
			ctx.Movement.applyStun(player, params.StunSeconds)
		end
	end)
end

----------------------------------------------------------------
-- Colophon: hitscan that arcs from target to target, stunning every link (Ultimate)
----------------------------------------------------------------

-- Closest live model within `radius` of the previous link that this cast has not arced to yet.
local function nextLink(ctx: Context, from: Vector3, radius: number, struck: { [Model]: boolean }): Model?
	local candidates: { Model } = {}
	for _, model in ipairs(humanoidsInRadius(from, radius, ctx.Caster.Character)) do
		if not struck[model] then
			table.insert(candidates, model)
		end
	end
	return nearestModel(candidates, from)
end

function GlyphEffects.Colophon(ctx: Context): number
	local params = ctx.Def.Params
	local direction = horizontal(ctx.Direction)
	local start = ctx.Origin.Position + direction * params.SpawnOffset
	local candidates, stop = hitscan(ctx, start, direction, ctx.Def.Range, params.HitRadius)

	local tracker = newTracker(ctx.Def, 1)
	local struck: { [Model]: boolean } = {}
	local points: { Vector3 } = {}
	local previous = start
	local target = nearestModel(candidates, start)
	while target ~= nil and #points < params.ChainCount do
		local link = target
		struck[link] = true
		local position = link:GetPivot().Position
		table.insert(points, position)
		if damageModel(ctx, tracker, link) then
			local player = playerOf(link)
			if player ~= nil then
				ctx.Movement.applyStun(player, params.StunSeconds)
			end
			ctx.Combat.knockback(link, horizontal(position - previous) * params.Knockback, KNOCKBACK_DURATION)
		end
		previous = position
		target = nextLink(ctx, position, params.ChainRadius, struck)
	end
	-- The chain path is authoritative: Targets carries one point per link, in the order the arcs fired.
	ctx.Vfx.emit({
		Id = ctx.Def.VfxId,
		Origin = ctx.Origin.Position,
		Direction = direction,
		Caster = ctx.Caster.UserId,
		Targets = points,
		Params = {
			SpawnOffset = params.SpawnOffset,
			Range = (stop - start).Magnitude,
			Pigment = ctx.Def.Pigment,
		},
	}, true)
	return tracker.Count
end

return GlyphEffects
