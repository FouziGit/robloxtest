--!strict
-- Attacks: a Forger's blows (D-131). Every one is a wind-up the SERVER times and announces for its whole
-- length (the ForgerTell effect, on the reliable remote), on an aim frozen when it began, then a resolve on that
-- same aim -- a swing's box or a bolt's line -- through CombatService.ApplyDamage with no source, like the
-- Erasure's blows.
--
-- Damage with no source passes every PvP rule, the hub's included (MatchService.allowDamage): so before any
-- point of it, the target is asked again whether it is still a member, still standing on the page by the
-- position the server trusts, and still a target at all (BotBrain.isValidTarget). `strikeable` is that gate,
-- and no blow reaches ApplyDamage without it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local AnimationConfig = require(Shared.Config.AnimationConfig)
local BattlegroundLayout = require(Shared.Pure.BattlegroundLayout)
local BotBrain = require(Shared.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Bots = require(script.Parent.Bots)
local CombatConfig = require(Shared.Config.CombatConfig)
local Context = require(script.Parent.Context)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Map = require(script.Parent.Map)
local Roster = require(script.Parent.Roster)

-- The hold a resolve's finisher put on each player it held (user id -> seconds): each rests after their own
-- (BotBrain.finisherRests), bystanders in the box as much as its target.
export type Outcome = { Held: { [number]: number } }

type Bot = Bots.Bot
type Member = Roster.Member

local HIT = CombatConfig.Hit
local REACH = BotConfig.Reach
local CLIP_SPEED = BotConfig.ClipSpeed
local MELEE_CHAIN = AnimationConfig.Actions.Melee
local CAST_CLIP = AnimationConfig.Actions.Cast[1]
-- A finisher that breaks guard carries the players' own finisher tag: CombatConfig.Block.BrokenBy reads it,
-- and the Hit packet earns the finisher's impact frame from it. Every other step is tagged as the Forgers'.
local FINISHER_TAG = "MeleeFinisher"
local MELEE_TAG_PREFIX = "BotMelee"
local BOLT_TAGS = { "BotBolt" }
-- A bolt is ink of the Strike's school, drawn by the Strike's own renderer.
local STRIKE = GlyphConfig.ById.Strike
-- How long a ragdolled player stays down, as MovementService.ragdoll holds them: limp, capped so the rise
-- still fits under the longest stun, then the rise.
local RAGDOLL_HOLD_SECONDS = math.min(HIT.RagdollSeconds, HIT.StunMaxSeconds - HIT.RagdollRiseSeconds)
	+ HIT.RagdollRiseSeconds

local Attacks = {}

local deps: Context.Deps
local handle: Map.Handle

----------------------------------------------------------------
-- Wind-up
----------------------------------------------------------------

-- Announces one step of an attack for its whole `window` and schedules its clip so the blow in it lands on
-- the resolve (BotBrain.clipTiming). The tell is the floor that will be hit, measured from the Forger along the
-- frozen aim: how far (Range) and how wide (Width), exactly as the resolve below judges it -- a swing's box, or
-- a bolt's line from the muzzle, whose reach and width both carry the target's own radius. The client paints
-- that rectangle in ink (VfxLibrary.ForgerTell), and tests/ForgerTell.spec.luau holds the two to each other.
function Attacks.windup(bot: Bot, attack: BotBrain.Attack, window: number, now: number)
	local range, width, clipName
	local bolt = bot.Def.Bolt
	if attack.Kind == "Bolt" and bolt ~= nil then
		range = bolt.SpawnOffset + bolt.Range + REACH.TargetRadiusStuds
		width = 2 * (bolt.HitRadius + REACH.TargetRadiusStuds)
		clipName = CAST_CLIP
	else
		local melee = bot.Def.Melee
		local final = attack.Step >= #melee.Damage
		-- The finisher always plays the chain's last clip, the overhead smash, however short the tier's chain.
		local index = if final then #MELEE_CHAIN else math.min(attack.Step, #MELEE_CHAIN)
		range, width, clipName = melee.Range, 2 * melee.HalfWidth, MELEE_CHAIN[index]
	end
	local root = bot.Root.Position
	deps.Vfx.emit({
		Id = Context.TellVfxId,
		Origin = Vector3.new(root.X, handle.FloorY, root.Z),
		Direction = Vector3.new(attack.AimX, 0, attack.AimZ),
		Params = {
			Seconds = window,
			Range = range,
			Width = width,
			-- The body whose hand flashes at the end of the tell.
			Actor = bot.Model,
			-- Whose tell it is, for a retraction (Attacks.retract): a slot holds one Forger, and a Forger one tell.
			Forger = bot.Slot,
		},
	}, true)
	local clip: AnimationConfig.Clip? = AnimationConfig.Clips[clipName]
	local track: AnimationTrack? = bot.Tracks[clipName]
	if clip == nil or track == nil then
		bot.PendingClip = nil
		return
	end
	local speed, delay = BotBrain.clipTiming(window, clip.Impact, CLIP_SPEED.Min, CLIP_SPEED.Max)
	bot.PendingClip = clipName
	bot.ClipAt = now + delay
	bot.ClipSpeed = speed
end

-- Takes back the tell of a wind-up that will never land -- cut by a stagger, or its Forger dead -- on every
-- client that drew it, on the same reliable remote so it arrives after the tell: a warning still painted once
-- the server has dropped its blow sends players dodging nothing.
function Attacks.retract(bot: Bot)
	local root = bot.Root.Position
	deps.Vfx.emit({
		Id = Context.TellVfxId,
		Origin = Vector3.new(root.X, handle.FloorY, root.Z),
		Params = { Cancel = true, Forger = bot.Slot },
	}, true)
end

----------------------------------------------------------------
-- The gate in front of every blow
----------------------------------------------------------------

-- The character to hit and the point to measure it at, or nil when `member` may not be hit by this Forger now:
-- no longer in the roster, not standing on the page by the position the server trusts, or no longer a target
-- (down, in the camp, too fresh, ignored). The point is where a Forger sees them (Context.targetPoint).
local function strikeable(bot: Bot, member: Member, now: number): (Model?, Vector3?)
	local player = member.Player
	if Roster.get(player) ~= member then
		return nil, nil
	end
	local trusted = deps.Combat.trustedPosition(player)
	if trusted == nil or not Context.insideBounds(handle.Layout, trusted) then
		return nil, nil
	end
	local point = Context.targetPoint(deps.Combat, player)
	local character = player.Character
	if point == nil or character == nil then
		return nil, nil
	end
	local x, y, z = Context.toLocal(point)
	local target: BotBrain.Target = {
		UserId = member.UserId,
		X = x,
		Y = y,
		Z = z,
		Visible = true,
		InCamp = BattlegroundLayout.inRect(handle.Layout.Camp, x, z),
		Down = deps.Movement.isDown(player),
		ArrivedAt = member.ArrivedAt,
		Load = 0,
	}
	if not BotBrain.isValidTarget(Context.Rules, bot.Memory, target, now) then
		return nil, nil
	end
	return character, point
end

----------------------------------------------------------------
-- Resolve
----------------------------------------------------------------

-- The end of a chain, on a player it landed on: thrown along the aim and lifted, held for the finisher's stun,
-- and, for the tiers whose finisher does, knocked down like a player's finisher knocks down. Returns how long
-- the player is now held.
local function finish(melee: BotConfig.MeleeDef, player: Player, character: Model, aim: Vector3): number
	deps.Combat.knockback(
		character,
		aim * melee.FinisherKnockback + Vector3.yAxis * melee.FinisherLift,
		HIT.KnockbackDurationSeconds
	)
	local held = 0
	if melee.FinisherStunSeconds > 0 then
		held = math.min(melee.FinisherStunSeconds, HIT.StunMaxSeconds)
		deps.Movement.applyStun(player, held)
	end
	if melee.FinisherRagdoll then
		deps.Movement.ragdoll(player, HIT.RagdollSeconds)
		held = math.max(held, RAGDOLL_HOLD_SECONDS)
	end
	return held
end

-- A swing: every member standing in the box along the frozen aim takes it, each once.
local function resolveMelee(bot: Bot, resolve: BotBrain.Resolve, members: { Member }, now: number, outcome: Outcome)
	local melee = bot.Def.Melee
	local origin = bot.Root.Position
	local aim = Vector3.new(resolve.AimX, 0, resolve.AimZ)
	local tags =
		{ if resolve.Final and melee.FinisherBreaksGuard then FINISHER_TAG else MELEE_TAG_PREFIX .. resolve.Step }
	local damage = melee.Damage[math.min(resolve.Step, #melee.Damage)]
	for _, member in ipairs(members) do
		local character, point = strikeable(bot, member, now)
		if character ~= nil and point ~= nil then
			local offset = point - origin
			if BotBrain.inMeleeBox(offset.X, offset.Y, offset.Z, resolve.AimX, resolve.AimZ, melee) then
				local result = deps.Combat.ApplyDamage(nil, character, damage, "Melee", tags)
				if result.Applied > 0 then
					if resolve.Final then
						local held = finish(melee, member.Player, character, aim)
						if held > 0 then
							outcome.Held[member.UserId] = held
						end
					elseif not result.Blocked then
						-- A blocked step holds nobody: with the stun, a guard-breaking finisher behind a blocked
						-- step would be a combo no guard could leave.
						deps.Movement.applyStun(member.Player, BotConfig.MeleeHitStunSeconds)
					end
				end
			end
		end
	end
	-- The players' own stroke, heavier on the finisher, with no caster: nobody's hit-stop, nobody's camera.
	deps.Vfx.emit({
		Id = Context.MeleeVfxId,
		Origin = origin,
		Direction = aim,
		Params = { Index = if resolve.Final then #CombatConfig.Melee.Damage else resolve.Step },
	})
end

-- A bolt: one ray from the Forger's eyes along the frozen aim, stopped by the page and by glyph walls; the
-- nearest member along it, within HitRadius of the line and not past where it stopped, takes it.
local function resolveBolt(
	bot: Bot,
	bolt: BotConfig.BoltDef,
	resolve: BotBrain.Resolve,
	members: { Member },
	now: number
)
	local aim = Vector3.new(resolve.AimX, 0, resolve.AimZ)
	local eyes = bot.Root.Position + Vector3.yAxis * REACH.SightHeightStuds
	local start = eyes + aim * bolt.SpawnOffset
	local hit = Workspace:Raycast(start, aim * bolt.Range, handle.SightParams)
	local stop = if hit ~= nil then hit.Position else start + aim * bolt.Range
	local reach = (stop - start).Magnitude
	local bestCharacter: Model?, bestPoint: Vector3?, bestAlong = nil, nil, math.huge
	for _, member in ipairs(members) do
		local character, point = strikeable(bot, member, now)
		if character ~= nil and point ~= nil then
			local along = (point - start):Dot(aim)
			local aside = BotBrain.segmentDistance(start.X, start.Z, stop.X, stop.Z, point.X, point.Z)
			local rise = math.abs(point.Y - bot.Root.Position.Y)
			if
				along >= 0
				and along <= reach + REACH.TargetRadiusStuds
				and aside <= bolt.HitRadius + REACH.TargetRadiusStuds
				and rise <= bolt.HalfHeight
				and along < bestAlong
			then
				bestCharacter, bestPoint, bestAlong = character, point, along
			end
		end
	end
	local targets: { Vector3 } = {}
	if bestCharacter ~= nil and bestPoint ~= nil then
		local result = deps.Combat.ApplyDamage(nil, bestCharacter, bolt.Damage, "Glyph", BOLT_TAGS, STRIKE.Pigment)
		if result.Applied > 0 then
			deps.Combat.knockback(bestCharacter, aim * bolt.KnockbackSpeed, HIT.KnockbackDurationSeconds)
			table.insert(targets, bestPoint)
		end
	end
	-- Drawn from the Forger's eyes, where the ray left: the renderer adds SpawnOffset along the aim itself.
	deps.Vfx.emit({
		Id = STRIKE.VfxId,
		Origin = eyes,
		Direction = aim,
		Targets = targets,
		Params = { SpawnOffset = bolt.SpawnOffset, Range = reach },
	})
end

-- Lands the wind-up that came due on the frozen aim it was shown on, against `members`.
function Attacks.resolve(bot: Bot, resolve: BotBrain.Resolve, members: { Member }, now: number): Outcome
	local outcome: Outcome = { Held = {} }
	local bolt = bot.Def.Bolt
	if resolve.Kind == "Bolt" then
		if bolt ~= nil then
			resolveBolt(bot, bolt, resolve, members, now)
		end
	else
		resolveMelee(bot, resolve, members, now, outcome)
	end
	return outcome
end

function Attacks.Init(injected: Context.Deps, map: Map.Handle)
	deps = injected
	handle = map
end

return Attacks
