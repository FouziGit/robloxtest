--!strict
-- GlyphService: validates every CastGlyph request (profile, alive, not stunned / guarding, real
-- recipe, unlocked, equipped, cooldown, ink), then runs the server effect from GlyphEffects with
-- the caster's HumanoidRootPart as origin. Hits feed XP and stats. The single owner of glyph cooldowns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ComboResolver = require(Shared.Pure.ComboResolver)
local DeveloperConfig = require(script.Parent.Parent.Config.DeveloperConfig)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
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
	-- Cast origin the server is willing to believe, corrected back to the last plausible position when
	-- the client claims an implausible one.
	trustedOrigin: (player: Player) -> CFrame?,
	-- Called after an effect teleports its caster (Caret), so the trusted position follows.
	resyncPosition: (player: Player) -> (),
	isBlocking: (player: Player) -> boolean,
	isStunned: (player: Player) -> boolean,
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
type VfxApi = { emit: (packet: VfxPacket, reliable: boolean?) -> () }
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
}
type Effect = (ctx: EffectContext) -> number
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type QuestApi = { report: (player: Player, event: string, amount: number) -> () }
-- Read only to decide whether free casting applies. A developer testing the roster must not carry
-- no-cost casting into a ranked match or a World Boss, where it takes real rating and real rewards from
-- other players.
type MatchApi = { isInMatch: (player: Player) -> boolean }
type WorldBossApi = { isLive: () -> boolean }
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
}

-- XP is granted per target hit, capped so multi-hit zones do not out-earn kills.
local MAX_REWARDED_HITS = 3
local ROOT_PART_NAME = "HumanoidRootPart"

local GlyphService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local combat: CombatApi
local effects: { [string]: Effect }
local vfx: VfxApi
local movement: MovementApi
local progression: ProgressionApi
local quest: QuestApi
local match: MatchApi
local worldBoss: WorldBossApi

local resolver = ComboResolver.new(GlyphConfig.recipes(), GameConfig.Combo.MaxLength)
-- Per player: glyph id -> os.clock timestamp at which it can be cast again.
local cooldowns: { [Player]: { [string]: number } } = {}

-- A developer account testing the roster in the hub: no ink, and cooldowns collapsed to
-- DeveloperConfig.MinRecastSeconds.
--
-- Deliberately refused inside a ranked match and during a World Boss event. Both pay out to other
-- players: a free-casting account would take real Elo from a real opponent and write it to the live
-- seasonal ladder, and would swallow a share of a boss payout that is divided between participants. The
-- hub is where the roster is meant to be tried, and the hub pays nobody.
--
-- The CastGlyph token bucket still applies: it is flood protection against an untrusted client, not an
-- economy rule, so a developer is throttled to its refill rate like everybody else. That bounds the real
-- pace at a few casts a second, well below anything the effects were written against.
local function freeCasting(player: Player): boolean
	if not DeveloperConfig.FreeCasting then
		return false
	end
	if not DeveloperConfig.isDeveloper(player.UserId, player.Name) then
		return false
	end
	return not match.isInMatch(player) and not worldBoss.isLive()
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
	if table.find(data.Unlocks.Glyphs, glyphId) == nil then
		notify.send(player, "hud.cast.locked", { name = def.NameKey }, "Error")
		return nil
	end
	if table.find(data.Loadout.Slots, glyphId) == nil then
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

-- Runs the effect in the handler thread (timed effects yield inline). Returns distinct models hit.
local function runEffect(player: Player, def: GlyphDef, effect: Effect, origin: CFrame, direction: Vector3): number
	local hits = 0
	local ctx: EffectContext = {
		Caster = player,
		Def = def,
		Origin = origin,
		Direction = direction,
		Combat = combat,
		Vfx = vfx,
		Movement = movement,
	}
	xpcall(function()
		hits = effect(ctx)
	end, function(err: any)
		log.error("effect %s failed for %s: %s", def.Effect, player.Name, tostring(err))
		notify.send(player, "hud.cast.failed", { name = def.NameKey }, "Error")
	end)
	return hits
end

local function recordCast(player: Player, hits: number)
	-- Timed effects yield: the profile may have been released meanwhile.
	local data = dataService.get(player)
	if data == nil then
		return
	end
	data.Stats.GlyphsCast += 1
	quest.report(player, "GlyphCast", 1)
	if hits > 0 then
		data.Stats.GlyphsHit += hits
		quest.report(player, "GlyphHit", hits)
		progression.addXp(player, ProgressionConfig.XP.GlyphHit * math.min(hits, MAX_REWARDED_HITS), "GlyphHit")
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
	if combat.isStunned(player) or combat.isBlocking(player) then
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
	vfx.emit({
		Id = "Cast",
		Origin = origin.Position,
		Direction = direction,
		Caster = player.UserId,
		Params = { GlyphId = def.Id, Pigment = def.Pigment },
	})
	-- Confirmed before the effect runs: zones and projectiles yield for seconds.
	notify.send(player, "hud.cast.success", { name = def.NameKey }, "Info")

	local hits = runEffect(player, def, effect, origin, direction)
	recordCast(player, hits)
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
	movement = deps.Movement
	progression = deps.Progression
	quest = deps.Quest
	match = deps.Match
	worldBoss = deps.WorldBoss
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
	end)
	registry.on("CastGlyph", onCastGlyph)
	log.info("started (%d glyphs)", #GlyphConfig.Glyphs)
end

return GlyphService
