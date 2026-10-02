--!strict
-- Teleport: the one way the server moves a player's body somewhere else (E6-S7, D-221). A match pad, the hub, the
-- Erasure's ring and the Battleground's camp all put a body down through here, and nothing else in the server
-- asks a client to stream the world in.
--
-- Where the place streams (Workspace.StreamingEnabled), a client only holds the world around its body: a body
-- dropped on a pad 900 studs up, or in the camp 1500 studs out, can land where its client has no floor yet. So a
-- trip that can wait asks the client for the world around its destination first (`travel`, at most
-- PortalConfig.StreamTimeoutSeconds), and puts the body down only once it has it, if the trip still stands. A
-- move that cannot wait -- a round's end, where the arena is released right after, or the Erasure's opening pull,
-- in the tick -- puts it down at once (`place`), and the engine's integrity mode holds a body whose floor has not
-- arrived instead of letting it fall. While the place does not stream, nothing waits and both are the same move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local PortalConfig = require(Shared.Config.PortalConfig)

local log = Log.new("Teleport")

-- What a teleport needs of CombatService: the position it trusts, re-anchored on the destination.
export type Combat = { resyncPosition: (player: Player, position: Vector3?) -> () }

local Teleport = {}

-- Asks `player`'s client for the world around `position` and waits until it has it, at most
-- PortalConfig.StreamTimeoutSeconds. Returns at once when the place does not stream.
function Teleport.streamAround(player: Player, position: Vector3)
	if not Workspace.StreamingEnabled then
		return
	end
	log.try("RequestStreamAroundAsync for " .. player.Name, function()
		player:RequestStreamAroundAsync(position, PortalConfig.StreamTimeoutSeconds)
	end)
end

-- The same request, in a thread of its own: returns at once. For a caller that knows several destinations ahead
-- of the moves, so their streams overlap instead of queueing behind one another.
function Teleport.prestream(player: Player, position: Vector3)
	if Workspace.StreamingEnabled then
		task.spawn(Teleport.streamAround, player, position)
	end
end

-- Puts `character` down at `target` now: pivoted, its momentum cleared so a knockback or a fall never carries over,
-- and the position CombatService trusts re-anchored on `target` itself. Re-reading the body instead would anchor
-- trust on whatever its client replicates next, which is where it stood before the move.
function Teleport.place(combat: Combat, player: Player, character: Model, target: CFrame)
	character:PivotTo(target)
	local root = character.PrimaryPart
	if root ~= nil then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	combat.resyncPosition(player, target.Position)
end

-- The world around `target` streamed in first, then the body put down there. Yields while it streams. False, with
-- nothing moved, when by then the player has left, the body is not theirs any more, or `stillWanted` says the
-- trip is off.
function Teleport.travel(
	combat: Combat,
	player: Player,
	character: Model,
	target: CFrame,
	stillWanted: (() -> boolean)?
): boolean
	Teleport.streamAround(player, target.Position)
	if player.Parent ~= Players or player.Character ~= character or character.Parent == nil then
		return false
	end
	if stillWanted ~= nil and not stillWanted() then
		return false
	end
	Teleport.place(combat, player, character, target)
	return true
end

return Teleport
