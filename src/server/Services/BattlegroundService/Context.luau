--!strict
-- Shared types, constants and helpers of the BattlegroundService folder (D-131). Every submodule receives the
-- same injected Deps table and keeps its own state; nothing here does.
--
-- The page lives in its own frame (BattlegroundConfig: x east, z south, y = 0 the floor's top face), and
-- BotBrain and BattlegroundLayout decide everything in it. The conversions between that frame and the world
-- are here, and so is the one rule for where a player is: the position the server trusts, never the raw one
-- a client replicates, for anything that decides whether they belong here or can be hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BattlegroundLayout = require(Shared.Pure.BattlegroundLayout)
local BotBrain = require(Shared.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Palette = require(Shared.Util.Palette)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type TroveType = typeof(Trove.new())
export type ProfileData = Types.ProfileData
export type NotifyKind = "Info" | "Success" | "Error"
export type DamageResult = { Applied: number, Killed: boolean, Blocked: boolean }
export type VfxPacket = {
	Id: string,
	Origin: Vector3,
	Direction: Vector3?,
	Caster: number?,
	Targets: { Vector3 }?,
	Params: { [string]: any }?,
}
-- Each signal's handler is declared with its arguments, the way WorldBossService's Context declares Damaged,
-- so a handler of the wrong shape is a type error here rather than a nil at runtime.
export type CombatApi = {
	-- The single damage path. Every Forger blow passes `nil` as the source: server-authored damage.
	ApplyDamage: (
		source: Player?,
		targetModel: Model,
		amount: number,
		kind: string,
		tags: { string },
		pigment: string?
	) -> DamageResult,
	knockback: (targetModel: Model, velocity: Vector3, duration: number) -> (),
	-- Called after the service places a player, with the position the SERVER chose.
	resyncPosition: (player: Player, position: Vector3?) -> (),
	-- Where the server last believed the player stood; nil right after a respawn. Never judged, never strikes.
	trustedPosition: (player: Player) -> Vector3?,
	heal: (player: Player, amount: number, quietSeconds: number) -> number,
	Damaged: {
		Connect: (
			self: any,
			fn: (sourceUserId: number, targetModel: Model, applied: number, kind: string) -> ()
		) -> any,
	},
	Killed: { Connect: (self: any, fn: (sourceUserId: number, victimModel: Model) -> ()) -> any },
	Shoved: { Connect: (self: any, fn: (targetModel: Model, velocity: Vector3, duration: number) -> ()) -> any },
	-- `key`: the glyph that holds it, so two slows never merge into one (BotBrain.addSlow).
	Controlled: {
		Connect: (
			self: any,
			fn: (targetModel: Model, kind: string, seconds: number, factor: number, key: string) -> ()
		) -> any,
	},
}
export type MovementApi = {
	applyStun: (player: Player, seconds: number) -> (),
	ragdoll: (player: Player, seconds: number) -> (),
	isDown: (player: Player) -> boolean,
}
export type Deps = {
	Registry: { fire: (name: string, player: Player, ...any) -> () },
	DataService: {
		get: (player: Player) -> ProfileData?,
		push: (player: Player, section: string) -> (),
	},
	Notify: {
		send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
	},
	Combat: CombatApi,
	Movement: MovementApi,
	-- Both return what was really credited (VIP and boosts included), so a toast never promises more.
	Progression: { addXp: (player: Player, amount: number, reason: string) -> number },
	Currency: { add: (player: Player, amount: number, reason: string) -> number },
	Match: { isInMatch: (player: Player) -> boolean },
	-- The Erasure's event pulls players in from anywhere, this page included: whoever it took is let go.
	WorldBoss: { isEngaged: (player: Player) -> boolean },
	Quest: { report: (player: Player, event: string, amount: number) -> () },
	Vfx: { emit: (packet: VfxPacket, reliable: boolean?) -> () },
}

local MAP = BattlegroundConfig.Map

local Context = {}

Context.RootPartName = "HumanoidRootPart"
-- The member's view of the page (Types.BattlegroundSnapshot), or nil once they leave it.
Context.SnapshotRemote = "BattlegroundChanged"
-- The ServerStorage folder the Forgers' bodies are cloned from, rebuilt at every Start.
Context.TemplatesFolderName = "ForgerTemplates"
-- The server's announcement of every wind-up, for its whole length (D-131): an ink wedge on the floor for a
-- swing, an ink line for a bolt. The blows themselves are the players' own melee stroke and the Strike beam.
Context.TellVfxId = "ForgerTell"
Context.MeleeVfxId = "Melee"
-- The names a Forger's walk and idle clips are loaded under, beside the action clips' own names.
Context.WalkTrack = "Walk"
Context.IdleTrack = "Idle"
-- A clip cross-fades in and out this fast: a chain of blows must not blur into one (as the players' Moves).
Context.FadeSeconds = 0.06
-- How long a respawned body is given to bring its root before the camp gives up on redirecting it.
Context.RootWaitSeconds = 5
-- Where the page is, in the world: its local origin, the centre of the floor's top face.
Context.Origin = Palette.vector(MAP.Origin)
Context.FloorY = Context.Origin.Y
-- The rules every Forger thinks by: BotConfig's, the minimum tells, and the longest stun the combat allows.
Context.Rules = {
	Targeting = BotConfig.Targeting,
	Reach = BotConfig.Reach,
	Stagger = BotConfig.Stagger,
	ArrivalGraceSeconds = BotConfig.ArrivalGraceSeconds,
	MinWindupSeconds = BotConfig.MinWindupSeconds,
	MinChainGapSeconds = BotConfig.MinChainGapSeconds,
	StunMaxSeconds = CombatConfig.Hit.StunMaxSeconds,
} :: BotBrain.Rules

-- A point of the page's frame, in the world.
function Context.toWorld(x: number, y: number, z: number): Vector3
	return Context.Origin + Vector3.new(x, y, z)
end

-- A world position, in the page's frame.
function Context.toLocal(position: Vector3): (number, number, number)
	local offset = position - Context.Origin
	return offset.X, offset.Y, offset.Z
end

-- Whether a world position is on the page: over the floor, between BoundsDepthStuds under it and
-- BoundsHeightStuds above it.
function Context.insideBounds(layout: BattlegroundLayout.Layout, position: Vector3): boolean
	local x, y, z = Context.toLocal(position)
	return BattlegroundLayout.inRect(layout.Bounds, x, z)
		and y >= -BattlegroundConfig.BoundsDepthStuds
		and y <= BattlegroundConfig.BoundsHeightStuds
end

-- Whether a world position stands in the camp, on the ground plane.
function Context.inCamp(layout: BattlegroundLayout.Layout, position: Vector3): boolean
	local x, _, z = Context.toLocal(position)
	return BattlegroundLayout.inRect(layout.Camp, x, z)
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
	local root = character:FindFirstChild(Context.RootPartName)
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Where a Forger sees, aims at and hits a player: their root, unless it has strayed horizontally from the
-- position the server trusts by more than the origin tolerance -- then the trusted spot, at the root's height.
-- A client that claims to stand somewhere else is judged where it really is, and cannot drag a swing or a
-- bolt onto empty ground; an honest one is judged where it is drawn.
function Context.targetPoint(combat: CombatApi, player: Player): Vector3?
	local root = Context.liveRoot(player)
	if root == nil then
		return nil
	end
	local raw = root.Position
	local trusted = combat.trustedPosition(player)
	if trusted == nil then
		return raw
	end
	local drift = Vector3.new(raw.X - trusted.X, 0, raw.Z - trusted.Z).Magnitude
	if drift <= GameConfig.Latency.OriginToleranceStuds then
		return raw
	end
	return Vector3.new(trusted.X, raw.Y, trusted.Z)
end

return Context
