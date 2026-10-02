--!strict
-- Shared types, constants and Workspace queries of the WorldBossService folder. Every submodule
-- receives the same injected Deps table and keeps no state here; the fight itself is the Slot record,
-- which WorldBossService creates and hands to the submodules that read or change it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local MatchConfig = require(Shared.Config.MatchConfig)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldBossMode = require(script.Parent.Parent.Parent.GameModes.WorldBossMode)

-- Mirrors ArenaService.Arena: acquire() validates the spawn pads and the kill zone before handing one
-- over, so both are guaranteed here. The Boss arena carries its player ring in Spawns[1].
export type Arena = {
	Instance: Model,
	Id: string,
	SlotIndex: number,
	Spawns: { { BasePart } },
	KillZone: BasePart,
}

-- Which fight holds the one encounter slot: the scheduled event, or a practice one player opened from the
-- hub's gate (D-132). There is never more than one fight, so the kind is a property of the slot.
export type Kind = "Event" | "Practice"

-- How a participant was let go (Audience.release): through a gate, or taken by a ranked match. Only a walk-out
-- through a gate costs the player who opened a practice its early-empty penalty (Admission.closedEmpty).
export type Release = "Gate" | "Match"

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
-- What the fight tells CombatService about the Boss zone (ZoneConfig): who it holds. Nobody there hurts another.
export type ZoneClaim = { Holds: (player: Player) -> boolean }
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
	resyncPosition: (player: Player, position: Vector3?) -> (),
	-- The Boss zone (E16-S1): the players the fight engaged never hurt each other, event or practice.
	claimZone: (zone: "Boss", claim: ZoneClaim) -> (),
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
export type AnalyticsApi = {
	fields: (first: string | number, second: (string | number)?, third: (string | number)?) -> { [string]: string },
	custom: (player: Player, eventName: string, value: number?, fields: { [string]: string }?) -> (),
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
	-- How each fight ended, for the dashboards (BossEnded, AnalyticsConfig.Events).
	Analytics: AnalyticsApi,
}
export type TroveType = typeof(Trove.new())

-- The live boss: one anchored body part carrying the Humanoid (it is stepped by CFrame, never
-- simulated), plus what the fight has to remember between two ticks.
export type Boss = {
	Arena: Arena,
	Model: Model,
	Humanoid: Humanoid,
	Body: BasePart, -- the contact hull, drawn invisible; the figure inside it is built from WorldConfig
	Band: BasePart, -- the ink band across the face, whose height says the phase
	Center: Vector3, -- middle of the arena: what "still in the fight" is measured from
	GroundY: number, -- top of the arena floor, so the clients paint the telegraphs on it
	FallY: number, -- underside of the arena floor: a participant's root under it fell off the page (K2, D-214)
	Facing: Vector3,
	LastHealth: number,
	ContactNextAt: { [number]: number }, -- user id -> os.clock of its next contact tick
}

-- The body the fight put on a pad of its ring, and when: the one body its fall rule judges (K2, D-214).
export type Placement = { Character: Model, At: number }

-- The one encounter slot and the fight it holds (D-132). WorldBossService creates the record once and hands
-- the same table to every submodule that reads or changes the fight: its fields are reassigned as fights open
-- and close, the table never is, so no submodule can hold a stale copy of the fight.
export type Slot = {
	Kind: Kind,
	State: WorldBossMode.State?, -- non-nil from the announce (or a practice's opening) to the end of the cleanup
	Boss: Boss?, -- non-nil from the spawn to the end of the cleanup
	Trove: TroveType?, -- what the fight owns: the arena, the boss model, its health connection
	Participants: { number }, -- user ids, in ring-spawn order
	Departed: { [number]: Release }, -- participants let go since, and how (a gate, or a practice's by a match)
	Reentries: { [number]: number }, -- times each participant walked back in through the hub's gate
	GrowthOwed: { [number]: true }, -- practice joiners it has not grown for yet: their first hit does (Admission)
	Placed: { [number]: Placement }, -- user id -> the body the fight last placed, until it falls or the fight ends
	Starter: number?, -- who opened the practice in the slot, and when (BossPractice.startPenalty)
	StartedAt: number,
	EmptySince: number?, -- when a practice's arena last emptied, while it waits for a returner
	PhaseEndsAt: number,
	NextEventAt: number, -- when the scheduled event is next announced
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
Context.SpawnVfxId = "BossSpawn"
-- Played at the boss when it enters a new phase: the band widening is what the world sees.
Context.PhaseVfxId = "BossPhase"
Context.DefeatVfxId = "BossDefeated"
Context.Epsilon = 1e-3

-- An empty slot, the event's, with nothing scheduled yet.
function Context.newSlot(): Slot
	return {
		Kind = "Event",
		State = nil,
		Boss = nil,
		Trove = nil,
		Participants = {},
		Departed = {},
		Reentries = {},
		GrowthOwed = {},
		Placed = {},
		Starter = nil,
		StartedAt = 0,
		EmptySince = nil,
		PhaseEndsAt = 0,
		NextEventAt = 0,
	}
end

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

-- The root of `player`'s live character while it stands in the arena around `center`, nil otherwise.
local function rootInArena(player: Player, center: Vector3): BasePart?
	local root = Context.liveRoot(player)
	if root ~= nil and (root.Position - center).Magnitude <= Context.ArenaReachStuds then
		return root
	end
	return nil
end

-- Whether `player` is alive and standing in the arena around `center`: what the end of a fight asks before it
-- sends anybody back to the hub, so a participant who has since gone to a ranked match, the Battleground or
-- the hub is left where they are.
function Context.inArena(player: Player, center: Vector3): boolean
	return rootInArena(player, center) ~= nil
end

-- Participants still standing in the arena. A participant who dies respawns at the hub SpawnLocation,
-- so the boss must never take the whole world into account: it would walk out of its own arena.
function Context.arenaRoots(userIds: { number }, center: Vector3): { BasePart }
	local roots: { BasePart } = {}
	for _, player in ipairs(Context.livePlayers(userIds)) do
		local root = rootInArena(player, center)
		if root ~= nil then
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
