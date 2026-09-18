--!strict
-- Shared types, constants and Workspace queries of the WorldBossService folder. Every submodule
-- receives the same injected Deps table and keeps no state here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local MatchConfig = require(Shared.Config.MatchConfig)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)

-- Mirrors ArenaService.Arena: acquire() validates the spawn pads and the kill zone before handing one
-- over, so both are guaranteed here. The Boss arena carries its player ring in Spawns[1].
export type Arena = {
	Instance: Model,
	Id: string,
	SlotIndex: number,
	Spawns: { { BasePart } },
	KillZone: BasePart,
}

export type ProfileData = Types.ProfileData
export type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
export type NotifyKind = "Info" | "Success" | "Error"
export type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
	sendAll: (key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
export type Registry = {
	fire: (name: string, player: Player, ...any) -> (),
	fireAll: (name: string, ...any) -> (),
}
export type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
export type Policy = (source: Player?, targetModel: Model) -> boolean
export type CombatApi = {
	ApplyDamage: (
		source: Player?,
		targetModel: Model,
		amount: number,
		kind: string,
		tags: { string }
	) -> DamageResult,
	knockback: (targetModel: Model, velocity: Vector3, duration: number) -> (),
	-- Called after the encounter teleports a participant, so the position CombatService trusts follows.
	resyncPosition: (player: Player) -> (),
	-- Returns the policy it replaced, so a temporary owner can hand the slot back (see init.takePolicy).
	setPolicy: (fn: Policy) -> Policy?,
	-- One damage application, with who dealt it and to what. Boss contribution is attributed from this
	-- and never by reading an attribute back from a Humanoid event (see Encounter.recordDamage).
	Damaged: {
		Connect: (
			self: any,
			fn: (sourceUserId: number, targetModel: Model, applied: number, kind: string) -> ()
		) -> any,
	},
}
export type MovementApi = { applyStun: (player: Player, seconds: number) -> () }
export type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> number }
export type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> number }
export type HubApi = { teleportToHub: (player: Player) -> () }
export type ArenaApi = { acquire: (arenaId: string) -> Arena?, release: (arena: Arena) -> () }
export type MatchApi = { isInMatch: (player: Player) -> boolean }
export type QuestApi = { report: (player: Player, event: string, amount: number) -> () }
export type VfxPacket = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}
export type VfxApi = { emit: (packet: VfxPacket, reliable: boolean?) -> () }
export type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Combat: CombatApi,
	Movement: MovementApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	Hub: HubApi,
	Arena: ArenaApi,
	Match: MatchApi,
	Vfx: VfxApi,
	-- QuestService owns the "BossParticipation" / "BossKill" events of QuestConfig and is pushed to, the
	-- way every other gameplay owner reports to it. Optional so a bootstrap without it still runs the
	-- event (Start warns once): the fight never depends on the quest log.
	Quest: QuestApi?,
}
export type TroveType = typeof(Trove.new())

-- The live boss: one anchored body part carrying the Humanoid (it is stepped by CFrame, never
-- simulated), plus what the fight has to remember between two ticks.
export type Boss = {
	Arena: Arena,
	Model: Model,
	Humanoid: Humanoid,
	Body: BasePart,
	Center: Vector3, -- middle of the arena: what "still in the fight" is measured from
	GroundY: number, -- top of the arena floor, so the clients paint the telegraphs on it
	Facing: Vector3,
	LastHealth: number,
	ContactNextAt: { [number]: number }, -- user id -> os.clock of its next contact tick
}

local Context = {}

Context.ArenaId = "Boss" -- the MatchConfig.Arenas entry ArenaService builds the event arena from
-- Names ArenaService builds into the Boss arena (docs/GAME_DESIGN.md §8).
Context.FloorName = "Floor"
Context.BossSpawnName = "BossSpawn"
Context.RootPartName = "HumanoidRootPart"
-- Participants are dropped this far above their pad so they never start clipped into it.
Context.SpawnClearanceStuds = 4
-- How far from the arena centre a participant still counts as fighting: the arena is that wide, and a
-- participant who dies respawns at the hub SpawnLocation, hundreds of studs below the arena slot.
Context.ArenaReachStuds = MatchConfig.Arenas.Boss.Size
-- WorldBossConfig.Boss.ContactDamage is per second: one tick per participant and per second.
Context.ContactIntervalSeconds = 1
Context.ContactTags = { "BossContact" }
Context.BodyColor = Color3.fromRGB(78, 58, 92)
Context.SpawnVfxId = "BossSpawn"
Context.DefeatVfxId = "BossDefeated"
Context.Epsilon = 1e-3

-- Root of a player's live character, or nil while dead, unloaded or gone.
function Context.liveRoot(player: Player): BasePart?
	if player.Parent ~= Players then
		return nil
	end
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root: Instance? = character:FindFirstChild(Context.RootPartName)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The participants of `userIds` still in the server, in spawn order.
function Context.livePlayers(userIds: { number }): { Player }
	local result: { Player } = {}
	for _, userId in ipairs(userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil and player.Parent == Players then
			table.insert(result, player)
		end
	end
	return result
end

-- Everyone the event may pull in: in the server, alive, and not already in a match — MatchService owns
-- its participants and the boss never empties a running arena.
function Context.eligiblePlayers(match: MatchApi): { Player }
	local result: { Player } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not match.isInMatch(player) and Context.liveRoot(player) ~= nil then
			table.insert(result, player)
		end
	end
	return result
end

-- Participants still standing in the arena. A participant who dies respawns at the hub SpawnLocation,
-- so the boss must never take the whole world into account: it would walk out of its own arena.
function Context.arenaRoots(userIds: { number }, center: Vector3): { BasePart }
	local roots: { BasePart } = {}
	for _, player in ipairs(Context.livePlayers(userIds)) do
		local root = Context.liveRoot(player)
		if root ~= nil and (root.Position - center).Magnitude <= Context.ArenaReachStuds then
			table.insert(roots, root)
		end
	end
	return roots
end

-- The nearest of them inside WorldBossConfig.Boss.AggroRadius, or nil when nobody is close enough: the
-- boss then holds its ground and keeps swinging instead of chasing across the arena.
function Context.nearestRoot(roots: { BasePart }, origin: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = WorldBossConfig.Boss.AggroRadius
	for _, root in ipairs(roots) do
		local distance = (root.Position - origin).Magnitude
		if distance <= bestDistance then
			bestDistance = distance
			best = root
		end
	end
	return best
end

-- Closest ancestor Model owning a live Humanoid (accessories and tools nest parts under it).
local function modelOf(part: BasePart): Model?
	local ancestor: Instance? = part.Parent
	while ancestor ~= nil do
		if ancestor:IsA("Model") then
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil and humanoid.Health > 0 then
				return ancestor :: Model
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
end

-- Distinct live characters whose parts overlap the sphere, the boss itself excluded.
function Context.humanoidsInRadius(origin: Vector3, radius: number, exclude: Model): { Model }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { exclude }
	local seen: { [Model]: boolean } = {}
	local models: { Model } = {}
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(origin, radius, params)) do
		local model = modelOf(part)
		if model ~= nil and not seen[model] then
			seen[model] = true
			table.insert(models, model)
		end
	end
	return models
end

return Context
