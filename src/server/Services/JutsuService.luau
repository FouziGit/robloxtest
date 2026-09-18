--!strict
-- JutsuService: validates every CastJutsu request (profile, alive, not stunned / guarding, real
-- recipe, unlocked, equipped, cooldown, chakra), then runs the server effect from JutsuEffects with
-- the caster's HumanoidRootPart as origin. Hits feed XP and stats. The single owner of jutsu cooldowns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ComboResolver = require(Shared.Pure.ComboResolver)
local GameConfig = require(Shared.Config.GameConfig)
local JutsuConfig = require(Shared.Config.JutsuConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("JutsuService")

export type JutsuDef = JutsuConfig.JutsuDef

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
		element: string?
	) -> DamageResult,
	knockback: (targetModel: Model, velocity: Vector3, duration: number) -> (),
	trySpendChakra: (player: Player, cost: number) -> boolean,
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
	Def: JutsuDef,
	Origin: CFrame,
	Direction: Vector3,
	Combat: CombatApi,
	Vfx: VfxApi,
	Movement: MovementApi,
}
type Effect = (ctx: EffectContext) -> number
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type QuestApi = { report: (player: Player, event: string, amount: number) -> () }
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
}

-- XP is granted per target hit, capped so multi-hit zones do not out-earn kills.
local MAX_REWARDED_HITS = 3
local ROOT_PART_NAME = "HumanoidRootPart"

local JutsuService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local combat: CombatApi
local effects: { [string]: Effect }
local vfx: VfxApi
local movement: MovementApi
local progression: ProgressionApi
local quest: QuestApi

local resolver = ComboResolver.new(JutsuConfig.recipes(), GameConfig.Combo.MaxLength)
-- Per player: jutsu id -> os.clock timestamp at which it can be cast again.
local cooldowns: { [Player]: { [string]: number } } = {}

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
local function resolveCast(player: Player, data: ProfileData, sequence: { string }, now: number): JutsuDef?
	local jutsuId = ComboResolver.resolve(resolver, sequence)
	if jutsuId == nil then
		notify.send(player, "hud.combo.noMatch", nil, "Error")
		return nil
	end
	local def = JutsuConfig.ById[jutsuId]
	if def == nil then
		log.error("recipe %s resolves to unknown jutsu %s", table.concat(sequence, "-"), jutsuId)
		return nil
	end
	if table.find(data.Unlocks.Jutsus, jutsuId) == nil then
		notify.send(player, "hud.cast.locked", { name = def.NameKey }, "Error")
		return nil
	end
	if table.find(data.Loadout.Slots, jutsuId) == nil then
		notify.send(player, "hud.cast.notEquipped", { name = def.NameKey }, "Error")
		return nil
	end
	local readyAt = cooldownsOf(player)[jutsuId]
	if readyAt ~= nil and readyAt > now then
		local seconds = string.format("%.1f", readyAt - now)
		notify.send(player, "hud.cast.cooldown", { name = def.NameKey, seconds = seconds }, "Error")
		return nil
	end
	return def
end

-- Runs the effect in the handler thread (timed effects yield inline). Returns distinct models hit.
local function runEffect(player: Player, def: JutsuDef, effect: Effect, origin: CFrame, direction: Vector3): number
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
	data.Stats.JutsusCast += 1
	quest.report(player, "JutsuCast", 1)
	if hits > 0 then
		data.Stats.JutsusHit += hits
		quest.report(player, "JutsuHit", hits)
		progression.addXp(player, ProgressionConfig.XP.JutsuHit * math.min(hits, MAX_REWARDED_HITS), "JutsuHit")
	end
	dataService.push(player, "Stats")
end

local function onCastJutsu(player: Player, sequence: { string })
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
	if not combat.trySpendChakra(player, def.Cost) then
		notify.send(player, "hud.cast.notEnoughChakra", nil, "Error", "Error")
		return
	end
	local effect = effects[def.Effect]
	if effect == nil then
		log.error("no effect %s for jutsu %s", def.Effect, def.Id)
		return
	end

	local origin = root.CFrame
	local direction = origin.LookVector
	cooldownsOf(player)[def.Id] = now + def.Cooldown
	vfx.emit({
		Id = "Cast",
		Origin = origin.Position,
		Direction = direction,
		Caster = player.UserId,
		Params = { JutsuId = def.Id, SfxId = def.SfxId, Element = def.Element },
	})
	-- Confirmed before the effect runs: zones and projectiles yield for seconds.
	notify.send(player, "hud.cast.success", { name = def.NameKey }, "Info")

	local hits = runEffect(player, def, effect, origin, direction)
	recordCast(player, hits)
end

-- Remaining cooldown per jutsu id, only entries still counting down. Expired entries are dropped.
function JutsuService.getCooldowns(player: Player): { [string]: number }
	local result: { [string]: number } = {}
	local map = cooldowns[player]
	if map == nil then
		return result
	end
	local now = os.clock()
	for jutsuId, readyAt in pairs(map) do
		local left = readyAt - now
		if left > 0 then
			result[jutsuId] = left
		else
			map[jutsuId] = nil
		end
	end
	return result
end

function JutsuService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	combat = deps.Combat
	effects = deps.Effects
	vfx = deps.Vfx
	movement = deps.Movement
	progression = deps.Progression
	quest = deps.Quest
end

function JutsuService.Start()
	if #resolver.duplicates > 0 then
		log.warn("duplicate recipes (first wins): %s", table.concat(resolver.duplicates, ", "))
	end
	for _, def in ipairs(JutsuConfig.Jutsus) do
		if effects[def.Effect] == nil then
			log.warn("jutsu %s has no effect %s", def.Id, def.Effect)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		cooldowns[player] = nil
	end)
	registry.on("CastJutsu", onCastJutsu)
	log.info("started (%d jutsus)", #JutsuConfig.Jutsus)
end

return JutsuService
