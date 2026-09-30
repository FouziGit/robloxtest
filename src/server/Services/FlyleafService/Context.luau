--!strict
-- Shared types and helpers of the FlyleafService folder (E16-S2). Every submodule receives the same injected Deps
-- table and keeps its own state; nothing here does.
--
-- The page lives in its own frame (FlyleafConfig: x east, z south, y = 0 the floor's top face). The one rule for
-- where a member is: the position the server trusts, never the raw one a client replicates, for anything that
-- decides whether they belong here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local FlyleafConfig = require(Shared.Config.FlyleafConfig)
local FlyleafLayout = require(script.Parent.Parent.Parent.Pure.FlyleafLayout)
local Palette = require(Shared.Util.Palette)
local Types = require(Shared.Types)

export type NotifyKind = "Info" | "Success" | "Error"
export type ZoneClaim = {
	Holds: (player: Player) -> boolean,
	Pair: ((source: Player, target: Player) -> boolean)?,
}
export type Deps = {
	Registry: { fire: (name: string, player: Player, ...any) -> () },
	DataService: {
		get: (player: Player) -> Types.ProfileData?,
		push: (player: Player, section: string) -> (),
	},
	Notify: {
		send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
	},
	Combat: {
		claimZone: (zone: "Flyleaf", claim: ZoneClaim) -> (),
		-- Called after the service places a player (World/Teleport), with the position the SERVER chose.
		resyncPosition: (player: Player, position: Vector3?) -> (),
		-- Where the server last believed the player stood. Never judged, never strikes.
		trustedPosition: (player: Player) -> Vector3?,
		Killed: { Connect: (self: any, fn: (sourceUserId: number, victimModel: Model) -> ()) -> any },
	},
	-- Both return what was really credited (VIP and boosts included), so a toast never promises more.
	Progression: { addXp: (player: Player, amount: number, reason: string) -> number },
	Currency: { add: (player: Player, amount: number, reason: string) -> number },
	Match: { isInMatch: (player: Player) -> boolean },
	-- The Erasure's event pulls players in from anywhere, this page included: whoever it took is let go.
	WorldBoss: { isEngaged: (player: Player) -> boolean },
}

local MAP = FlyleafConfig.Map

local Context = {}

Context.RootPartName = "HumanoidRootPart"
-- The member's view of the page (Types.FlyleafSnapshot), or nil once they leave it.
Context.SnapshotRemote = "FlyleafChanged"
-- Where the page is, in the world: its local origin, the centre of the floor's top face.
Context.Origin = Palette.vector(MAP.Origin)

-- A point of the page's frame, in the world.
function Context.toWorld(x: number, y: number, z: number): Vector3
	return Context.Origin + Vector3.new(x, y, z)
end

-- A world position, in the page's frame.
function Context.toLocal(position: Vector3): (number, number, number)
	local offset = position - Context.Origin
	return offset.X, offset.Y, offset.Z
end

-- Whether a world position is on the page: over the floor, between BoundsDepthStuds under it and BoundsHeightStuds
-- above it.
function Context.insideBounds(layout: FlyleafLayout.Layout, position: Vector3): boolean
	local x, y, z = Context.toLocal(position)
	return FlyleafLayout.inRect(layout.Bounds, x, z)
		and y >= -FlyleafConfig.BoundsDepthStuds
		and y <= FlyleafConfig.BoundsHeightStuds
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

return Context
