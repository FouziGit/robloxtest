--!strict
-- GlyphService: validates every CastGlyph request (profile, alive, not stunned / guarding, real
-- recipe, unlocked, equipped, cooldown, ink), then runs the server effect from GlyphEffects with
-- the caster's HumanoidRootPart as origin. Hits feed XP and stats. The single owner of glyph cooldowns.
-- A hit on a Trial proof counts for the stats and the quests but pays no XP: the Trials pay by the kill
-- (EnemyService, TrialPay).
--
-- It also runs the frame a glyph with a Hasten leaves at its cast point (the Cartouche, D-256): while its
-- caster stands inside, their other cooldowns run Hasten times as fast, stepped on this service's one Heartbeat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ComboResolver = require(Shared.Pure.ComboResolver)
local DeveloperConfig = require(script.Parent.Parent.Config.DeveloperConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Signal = require(Packages.Signal)
local Types = require(Shared.Types)

local log = Log.new("GlyphService")

export type GlyphDef = GlyphConfig.GlyphDef

type ProfileData = Types.ProfileData
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
type CombatApi = {
	ApplyDamage: (
		source: Player?,
		targetModel: Model,
		amount: number,
		kind: string,
		tags: { string },
		pigment: string?
	) -> DamageResult,
	knockback: (targetModel: Model, velocity: Vector3, duration: number) -> (),
	trySpendInk: (player: Player, cost: number) -> boolean,
	addInk: (player: Player, amount: number) -> (),
	-- Cast origin the server is willing to believe, corrected back to the last plausible position when
	-- the client claims an implausible one.
	trustedOrigin: (player: Player) -> CFrame?,
	-- Called after an effect teleports its caster (Caret), so the trusted position follows.
	resyncPosition: (player: Player, position: Vector3?) -> (),
	isBlocking: (player: Player) -> boolean,
	isStunned: (player: Player) -> boolean,
	-- A charged glyph or a rush holding its caster (D-142): no other glyph until it ends or a dash breaks it.
	isChanneling: (player: Player) -> boolean,
	-- Where the server last believed the player stood, read without judging it: what a frame asks every step.
	trustedPosition: (player: Player) -> Vector3?,
	grantIFrames: (player: Player, seconds: number) -> (),
	applyStoneSkin: (player: Player) -> boolean,
}
type VfxPacket = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}
type VfxApi = { emit: (packet: VfxPacket, reliable: boolean?, alsoNear: Vector3?) -> () }
type MovementCommand =
	{ Kind: "Dash", Direction: Vector3, Distance: number, Duration: number }
	| { Kind: "Knockback", Velocity: Vector3, Duration: number }
	| { Kind: "Stun", Seconds: number }
type MovementApi = {
	applySlow: (player: Player, key: string, factor: number, seconds: number) -> (),
	applyStun: (player: Player, seconds: number) -> (),
	command: (player: Player, payload: MovementCommand) -> (),
}
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> () }
type EffectContext = {
	Caster: Player,
	Def: GlyphDef,
	Origin: CFrame,
	Direction: Vector3,
	Combat: CombatApi,
	Vfx: VfxApi,
	Movement: MovementApi,
	Landed: { [Model]: boolean }?,
}
type Effect = (ctx: EffectContext) -> number
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type QuestApi = { report: (player: Player, event: string, amount: number) -> () }
-- Read only to decide whether the developer perks apply. A developer testing the roster must not carry
-- no-cost casting or the whole roster into a ranked match or a World Boss, where they take real rating and
-- real rewards from other players.
type MatchApi = { isInMatch: (player: Player) -> boolean }
-- isLive is the scheduled event only; a practice's participants are refused through isEngaged (D-132).
type WorldBossApi = { isLive: () -> boolean, isEngaged: (player: Player) -> boolean }
-- The Battleground pays for every Forger (D-131): a member standing on its page is refused free casting too.
type BattlegroundApi = { isInside: (player: Player) -> boolean }
-- The glyphs a profile holds, and the loadout it could equip, with the developer list set aside.
type LoadoutApi = { fielded: (data: ProfileData) -> ({ string }, { string }) }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Combat: CombatApi,
	Effects: { [string]: Effect },
	Vfx: VfxApi,
	Movement: MovementApi,
	Progression: ProgressionApi,
	Quest: QuestApi,
	Match: MatchApi,
	WorldBoss: WorldBossApi,
	Battleground: BattlegroundApi,
	Loadout: LoadoutApi,
	-- The skin a caster wears on a glyph, written into the packets of that cast (D-109).
	Cosmetic: { skinShade: (player: Player, glyphId: string) -> number },
}

-- XP is granted per target hit, capped so multi-hit zones do not out-earn kills.
local MAX_REWARDED_HITS = 3
local ROOT_PART_NAME = "HumanoidRootPart"
local TICK_SECONDS = 1 / GameConfig.Server.TickRate

-- A frame that hastens its caster's cooldowns (openFrame): the glyph that laid it, whose own cooldown it leaves
-- alone, where and how wide it is, how fast the rest run inside it, when it ends and when it was last stepped.
type Frame = {
	GlyphId: string,
	Center: Vector3,
	Radius: number,
	Rate: number,
	EndsAt: number,
	SteppedAt: number,
}

local GlyphService = {}

-- Fired the moment a cast is ACCEPTED, before its effect runs: the glyph and the length of the chain it
-- belongs to. MatchService counts a duel's casts from it, and it has to be this side of the effect --
-- a zone that is still ticking when the match ends would otherwise never be counted at all.
GlyphService.Cast = Signal.new() -- (player: Player, glyphId: string, chain: number)
-- Fired after the effect resolved, with how many targets it hit.
GlyphService.CastLanded = Signal.new() -- (player: Player, glyphId: string, hits: number)

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local combat: CombatApi
local effects: { [string]: Effect }
local vfx: VfxApi
local cosmetic: { skinShade: (player: Player, glyphId: string) -> number }
local movement: MovementApi
local progression: ProgressionApi
local quest: QuestApi
local match: MatchApi
local worldBoss: WorldBossApi
local battleground: BattlegroundApi
local loadout: LoadoutApi

local resolver = ComboResolver.new(GlyphConfig.recipes(), GameConfig.Combo.MaxLength)
-- Per player: glyph id -> os.clock timestamp at which it can be cast again.
local cooldowns: { [Player]: { [string]: number } } = {}
-- os.clock of each player's last accepted cast, and how many casts that chain is now long: two inside
-- GameConfig.Combo.ChainWindowSeconds are a chain of two, and every cast from the second on is refunded
-- ChainInkRefund. Measured here, on casts the server ACCEPTED, which is the only timing of a sequence the
-- server can trust -- and therefore the only count the HUD may show and the profile may keep.
local lastCastAt: { [Player]: number } = {}
local chainLength: { [Player]: number } = {}
-- The frame each player stands to gain from, one at a time: a new one replaces the last.
local frames: { [Player]: Frame } = {}
local accumulator = 0

-- A developer account in the hub, where its perks reach (DeveloperConfig): free casting, the whole roster and
-- every slot.
--
-- Deliberately refused inside a ranked match, during a World Boss event, in a practice against the Erasure
-- and on the Battleground's page. All of them pay out: a perked account would take real Elo from a real
-- opponent and write it to the live seasonal ladder, would swallow a share of a boss payout that is divided
-- between participants, and would farm a practice's pay or the Forgers' XP and Folios at no cost. The hub is
-- where the roster is meant to be tried.
local function developerPerks(player: Player): boolean
	if not DeveloperConfig.isDeveloper(player.UserId, player.Name) then
		return false
	end
	return not match.isInMatch(player)
		and not worldBoss.isLive()
		and not worldBoss.isEngaged(player)
		and not battleground.isInside(player)
end

-- A developer testing the roster in the hub: no ink, and cooldowns collapsed to
-- DeveloperConfig.MinRecastSeconds.
--
-- The CastGlyph token bucket still applies: it is flood protection against an untrusted client, not an
-- economy rule, so a developer is throttled to its refill rate like everybody else. That bounds the real
-- pace at a few casts a second, well below anything the effects were written against.
local function freeCasting(player: Player): boolean
	return DeveloperConfig.FreeCasting and developerPerks(player)
end

-- The unlocks and the loadout a cast is checked against. A developer's profile holds the whole roster in as
-- many slots (DeveloperConfig.UnlimitedSlots), and that is a perk of the hub like free casting: anywhere else
-- a developer fights with what a player with the same level, passes and slots would hold (docs/QA.md R6).
local function fielded(player: Player, data: ProfileData): ({ string }, { string })
	if DeveloperConfig.isDeveloper(player.UserId, player.Name) and not developerPerks(player) then
		return loadout.fielded(data)
	end
	return data.Unlocks.Glyphs, data.Loadout.Slots
end

local function cooldownsOf(player: Player): { [string]: number }
	local map = cooldowns[player]
	if map == nil then
		map = {}
		cooldowns[player] = map
	end
	return map
end

-- Live root of the player's character, or nil when dead / not spawned.
local function liveRoot(player: Player): BasePart?
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

-- A glyph whose Params carry a Hasten frames the ground at `center` for Ticks x TickInterval, the life of its ticks
-- (D-256). Laid when the cast is accepted, from the origin the server validated, as the effect's zone is.
local function openFrame(player: Player, def: GlyphDef, center: Vector3, now: number)
	local params = def.Params
	local rate = params.Hasten
	if rate == nil then
		return
	end
	frames[player] = {
		GlyphId = def.Id,
		Center = center,
		Radius = params.Radius,
		Rate = rate,
		EndsAt = now + params.Ticks * params.TickInterval,
		SteppedAt = now,
	}
end

-- Takes `seconds x (Rate - 1)` off every cooldown of `player` still counting, but the frame's own glyph's: they run
-- Rate times as fast for those seconds.
local function hasten(player: Player, frame: Frame, seconds: number, now: number)
	local map = cooldowns[player]
	if map == nil then
		return
	end
	local saved = seconds * (frame.Rate - 1)
	for glyphId, readyAt in pairs(map) do
		if glyphId ~= frame.GlyphId and readyAt > now then
			map[glyphId] = readyAt - saved
		end
	end
end

-- Steps every frame to `now`. The time since the last step counts only while its caster stands inside it, by the
-- position the server believes; and a frame ends for good, before it hastens anything more, on the first step its
-- caster is dead, stunned or guarding -- what stops its ticks (GlyphEffects.casterAlive), which read it only once a
-- tick: the hastening never outlives the zone. Bounded by construction: no frame outlasts its EndsAt, so none
-- saves more than (Rate - 1) x Ticks x TickInterval on a cooldown.
local function stepFrames(now: number)
	for player, frame in pairs(frames) do
		local span = math.min(now, frame.EndsAt) - frame.SteppedAt
		frame.SteppedAt = now
		if liveRoot(player) == nil or combat.isStunned(player) or combat.isBlocking(player) then
			frames[player] = nil
			continue
		end
		local position = combat.trustedPosition(player)
		if position ~= nil and (position - frame.Center).Magnitude <= frame.Radius then
			hasten(player, frame, span, now)
		end
		if now >= frame.EndsAt then
			frames[player] = nil
		end
	end
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	if next(frames) ~= nil then
		stepFrames(os.clock())
	end
end

-- Validates the request and returns the definition to cast, or nil after notifying the player.
local function resolveCast(player: Player, data: ProfileData, sequence: { string }, now: number): GlyphDef?
	local glyphId = ComboResolver.resolve(resolver, sequence)
	if glyphId == nil then
		notify.send(player, "hud.combo.noMatch", nil, "Error")
		return nil
	end
	local def = GlyphConfig.ById[glyphId]
	if def == nil then
		log.error("recipe %s resolves to unknown glyph %s", table.concat(sequence, "-"), glyphId)
		return nil
	end
	local unlocked, slots = fielded(player, data)
	if table.find(unlocked, glyphId) == nil then
		notify.send(player, "hud.cast.locked", { name = def.NameKey }, "Error")
		return nil
	end
	if table.find(slots, glyphId) == nil then
		notify.send(player, "hud.cast.notEquipped", { name = def.NameKey }, "Error")
		return nil
	end
	local readyAt = cooldownsOf(player)[glyphId]
	if readyAt ~= nil and readyAt > now then
		local seconds = string.format("%.1f", readyAt - now)
		notify.send(player, "hud.cast.cooldown", { name = def.NameKey, seconds = seconds }, "Error")
		return nil
	end
	return def
end

-- The broadcaster, with the caster's skin shade written into every packet the effect sends: its own
-- visual and whatever it detonates (Brand's Explosion), so a skinned cast is skinned end to end.
local function shadedVfx(shade: number): VfxApi
	if shade == 0 then
		return vfx
	end
	return {
		emit = function(packet: VfxPacket, reliable: boolean?, alsoNear: Vector3?)
			local params: { [string]: any } = table.clone(packet.Params or {})
			if params.Shade == nil then
				params.Shade = shade
			end
			packet.Params = params
			vfx.emit(packet, reliable, alsoNear)
		end,
	}
end

-- Runs the effect in the handler thread (timed effects yield inline). Returns distinct models hit, and how
-- many of them pay XP: every one but a model that was a Trial proof when the cast struck it (Context.Landed).
local function runEffect(
	player: Player,
	def: GlyphDef,
	effect: Effect,
	origin: CFrame,
	direction: Vector3,
	shade: number
): (number, number)
	local hits = 0
	local landed: { [Model]: boolean } = {}
	local ctx: EffectContext = {
		Caster = player,
		Def = def,
		Origin = origin,
		Direction = direction,
		Combat = combat,
		Vfx = shadedVfx(shade),
		Movement = movement,
		Landed = landed,
	}
	xpcall(function()
		hits = effect(ctx)
	end, function(err: any)
		log.error("effect %s failed for %s: %s", def.Effect, player.Name, tostring(err))
		notify.send(player, "hud.cast.failed", { name = def.NameKey }, "Error")
	end)
	local paying = 0
	for _, proof in pairs(landed) do
		if not proof then
			paying += 1
		end
	end
	return hits, paying
end

local function recordCast(player: Player, glyphId: string, hits: number, paying: number, chain: number)
	GlyphService.CastLanded:Fire(player, glyphId, hits)
	-- Timed effects yield: the profile may have been released meanwhile.
	local data = dataService.get(player)
	if data == nil then
		return
	end
	data.Stats.GlyphsCast += 1
	if chain > data.Stats.BestChain then
		data.Stats.BestChain = chain
	end
	quest.report(player, "GlyphCast", 1)
	if hits > 0 then
		data.Stats.GlyphsHit += hits
		quest.report(player, "GlyphHit", hits)
	end
	if paying > 0 then
		progression.addXp(player, ProgressionConfig.XP.GlyphHit * math.min(paying, MAX_REWARDED_HITS), "GlyphHit")
	end
	dataService.push(player, "Stats")
end

local function onCastGlyph(player: Player, sequence: { string })
	local data = dataService.get(player)
	if data == nil then
		return
	end
	local root = liveRoot(player)
	if root == nil then
		return
	end
	if combat.isStunned(player) or combat.isBlocking(player) or combat.isChanneling(player) then
		return
	end
	local now = os.clock()
	local def = resolveCast(player, data, sequence, now)
	if def == nil then
		return
	end
	local effect = effects[def.Effect]
	if effect == nil then
		log.error("no effect %s for glyph %s", def.Effect, def.Id)
		return
	end

	-- CombatService validates the origin against the position the server last believed: the character is
	-- simulated by the owning client, so root.CFrame alone let a cast be placed anywhere on the map.
	--
	-- Resolved and failed closed BEFORE the ink is spent. Falling back to root.CFrame would restore
	-- exactly the hole this closes whenever the validator declines to answer, and refusing after the debit
	-- would take the ink for a cast that never happened. It declines only when there is no live
	-- character, in which case there is nothing to cast from anyway.
	local origin = combat.trustedOrigin(player)
	if origin == nil then
		return
	end
	if not freeCasting(player) and not combat.trySpendInk(player, def.Cost) then
		notify.send(player, "hud.cast.notEnoughInk", nil, "Error", "Error")
		return
	end
	local direction = origin.LookVector
	-- A floor, not zero, under free casting. Every damage cap, hit tracker and duration in GlyphEffects is
	-- per cast, so two live casts of the same glyph double their damage, stack their stuns and pile up
	-- their world geometry. The floor is longer than the longest zone tick, so a cast always ends before
	-- its successor starts.
	local cooldown = if freeCasting(player) then DeveloperConfig.MinRecastSeconds else def.Cooldown
	cooldownsOf(player)[def.Id] = now + cooldown
	-- Never under free casting: its cooldowns are already that floor, and a frame would halve it.
	if not freeCasting(player) then
		openFrame(player, def, origin.Position, now)
	end
	local previous = lastCastAt[player]
	local chain = 1
	if previous ~= nil and now - previous <= GameConfig.Combo.ChainWindowSeconds then
		chain = (chainLength[player] or 1) + 1
	end
	chainLength[player] = chain
	lastCastAt[player] = now
	GlyphService.Cast:Fire(player, def.Id, chain)
	-- Reliable, unlike every other effect packet: this one is also the only confirmation the CLIENT gets
	-- that the server accepted a cast, and the HUD counts the chain from it (VfxController.LocalCast). A
	-- dropped packet on the unreliable channel took the counter to zero in the middle of a chain.
	local shade = cosmetic.skinShade(player, def.Id)
	vfx.emit({
		Id = "Cast",
		Origin = origin.Position,
		Direction = direction,
		Caster = player.UserId,
		Params = { GlyphId = def.Id, Pigment = def.Pigment, Chain = chain, Shade = shade },
	}, true)
	-- Confirmed before the effect runs: zones and projectiles yield for seconds.
	-- Only a chain says anything. A line per cast filled the toast column for the whole of every fight --
	-- one a second, three visible, two and a half seconds each -- so the messages that matter (a refused
	-- purchase, a claimed quest) queued behind a stream of the player's own glyph names. What confirms an
	-- ordinary cast is the cast: its effect, its sound and the ink leaving the bar.
	if chain > 1 then
		if not freeCasting(player) then
			combat.addInk(player, GameConfig.Combo.ChainInkRefund)
		end
		quest.report(player, "Chain", 1)
		notify.send(
			player,
			"hud.cast.chain",
			{ name = def.NameKey, count = chain, ink = GameConfig.Combo.ChainInkRefund },
			"Info"
		)
	end

	local hits, paying = runEffect(player, def, effect, origin, direction, shade)
	recordCast(player, def.Id, hits, paying, chain)
end

-- Forgets every cooldown of `player`, and the frame hastening them. MatchService calls it on every round's fresh
-- character and when a match lets them go, so nothing a round cost carries into the next one or out of the match
-- (D-20). Only the
-- server's match flow calls it: never a respawn or a portal, which a player can trigger as often as they like.
function GlyphService.resetCooldowns(player: Player)
	cooldowns[player] = nil
	frames[player] = nil
end

-- Remaining cooldown per glyph id, only entries still counting down. Expired entries are dropped.
function GlyphService.getCooldowns(player: Player): { [string]: number }
	local result: { [string]: number } = {}
	local map = cooldowns[player]
	if map == nil then
		return result
	end
	local now = os.clock()
	for glyphId, readyAt in pairs(map) do
		local left = readyAt - now
		if left > 0 then
			result[glyphId] = left
		else
			map[glyphId] = nil
		end
	end
	return result
end

function GlyphService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	combat = deps.Combat
	effects = deps.Effects
	vfx = deps.Vfx
	cosmetic = deps.Cosmetic
	movement = deps.Movement
	progression = deps.Progression
	quest = deps.Quest
	match = deps.Match
	worldBoss = deps.WorldBoss
	battleground = deps.Battleground
	loadout = deps.Loadout
end

function GlyphService.Start()
	if #resolver.duplicates > 0 then
		log.warn("duplicate recipes (first wins): %s", table.concat(resolver.duplicates, ", "))
	end
	for _, def in ipairs(GlyphConfig.Glyphs) do
		if effects[def.Effect] == nil then
			log.warn("glyph %s has no effect %s", def.Id, def.Effect)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		cooldowns[player] = nil
		lastCastAt[player] = nil
		chainLength[player] = nil
		frames[player] = nil
	end)
	registry.on("CastGlyph", onCastGlyph)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (%d glyphs)", #GlyphConfig.Glyphs)
end

return GlyphService
