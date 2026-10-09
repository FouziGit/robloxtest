--!strict
-- Roster: who is in the Battleground (D-131). A player becomes a member through the service's `enter` (and
-- again through the camp after a death inside), and stays one only while every tick agrees: still in the
-- server, in no match, not taken by the Erasure's event, and standing on the page by the position the server
-- TRUSTS. Whoever fails is let go, and told so (BattlegroundChanged nil). So every way out another service
-- takes -- a match that starts, the event pulling them in, a teleport home -- ends the membership on its own,
-- with no hook in any of those services. Every admission -- through the gate or back from a death -- puts the
-- arrival bubble on the member (CombatService.protect, D-282).
--
-- Each tick also keeps what the Forgers and the rewards read off a member: how long they have been out of
-- reach of the floor, when they last stood outside the camp, and the camp's heal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BattlegroundLayout = require(script.Parent.Parent.Parent.Pure.BattlegroundLayout)
local BotBrain = require(script.Parent.Parent.Parent.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Context = require(script.Parent.Context)
local Map = require(script.Parent.Map)
local Teleport = require(script.Parent.Parent.Parent.World.Teleport)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

export type Member = {
	Player: Player,
	UserId: number,
	ArrivedAt: number,
	-- Where the server put them: the anchor trust is re-set to while the new body has none yet.
	Landing: Vector3,
	-- Forgers they helped defeat since they came in, deaths inside included.
	Defeated: number,
	-- Since when their root has been out of reach of standing height (BotBrain.outOfReach): hung over the floor
	-- or sunk under it. nil on the ground.
	OffFloorSince: number?,
	OutsideCampAt: number,
	-- The current body's connections.
	Trove: Context.TroveType,
}

-- A member who died inside: when, and what they had defeated, until their next body comes back to the camp.
type Pending = { At: number, Defeated: number }

local CAMP = BotConfig.Camp

local Roster = {}

local deps: Context.Deps
local handle: Map.Handle
local standing: () -> number
local members: { [Player]: Member } = {}
local memberCount = 0
local pendingRespawn: { [number]: Pending } = {}
local playerTroves: { [Player]: Context.TroveType } = {}
local nextArrival = 0

local function tell(player: Player, snapshot: Types.BattlegroundSnapshot?)
	if player.Parent == Players then
		deps.Registry.fire(Context.SnapshotRemote, player, snapshot)
	end
end

function Roster.get(player: Player): Member?
	return members[player]
end

-- Every member, in user id order.
function Roster.list(): { Member }
	local list: { Member } = {}
	for _, member in pairs(members) do
		table.insert(list, member)
	end
	table.sort(list, function(a: Member, b: Member): boolean
		return a.UserId < b.UserId
	end)
	return list
end

function Roster.pushSnapshot(member: Member)
	tell(member.Player, { Standing = standing(), Defeated = member.Defeated })
end

function Roster.pushAll()
	for _, member in pairs(members) do
		Roster.pushSnapshot(member)
	end
end

-- The next landing, taken in turn, so two players arriving together never stand in one another.
function Roster.nextLanding(): Vector3
	nextArrival = nextArrival % #handle.Arrivals + 1
	return handle.Arrivals[nextArrival].Position
end

-- Puts the character down on `landing` now, facing into the page (Teleport.place): its velocity cleared, and the
-- position CombatService trusts re-anchored on that point. Without the resync the move reads as a 1500-stud
-- teleport and the player acts from the hub for half a minute. Every caller has had the camp streamed in around
-- `landing` first (Teleport.streamAround) and asked again what that wait may have changed.
function Roster.place(player: Player, character: Model, landing: Vector3)
	local center = Context.Origin
	Teleport.place(deps.Combat, player, character, CFrame.lookAt(landing, Vector3.new(center.X, landing.Y, center.Z)))
end

-- Lets go of a member now and tells them. Nothing for a player who is not one.
function Roster.drop(player: Player)
	local member = members[player]
	if member == nil then
		return
	end
	members[player] = nil
	memberCount -= 1
	member.Trove:Destroy()
	tell(player, nil)
end

-- A member's body died. With RespawnInside the membership waits for the next body, which the camp takes back
-- (onCharacterAdded); no nil is sent, so the band does not flicker through the death.
local function onDied(member: Member)
	local player = member.Player
	if members[player] ~= member then
		return
	end
	if not BattlegroundConfig.RespawnInside then
		Roster.drop(player)
		return
	end
	pendingRespawn[member.UserId] = { At = os.clock(), Defeated = member.Defeated }
	members[player] = nil
	memberCount -= 1
	member.Trove:Destroy()
end

-- A member whose body MovementService is replacing because its client took the Humanoid away (BodyLost, D-216):
-- a death inside, so the camp takes the new body back. Nothing for a player who is not a member.
function Roster.lost(player: Player)
	local member = members[player]
	if member ~= nil then
		onDied(member)
	end
end

-- Makes `player` a member standing on `landing`, bound to this `character` (replacing any membership they
-- had), and returns the member. The caller has placed the character and pushes the snapshot.
function Roster.admit(player: Player, character: Model, landing: Vector3, now: number, defeated: number): Member
	local previous = members[player]
	if previous ~= nil then
		previous.Trove:Destroy()
	else
		memberCount += 1
	end
	pendingRespawn[player.UserId] = nil
	local member: Member = {
		Player = player,
		UserId = player.UserId,
		ArrivedAt = now,
		Landing = landing,
		Defeated = defeated,
		OffFloorSince = nil,
		-- Arriving counts as activity: the page fills for a newcomer before they step out of the camp.
		OutsideCampAt = now,
		Trove = Trove.new(),
	}
	members[player] = member
	deps.Combat.protect(player, BattlegroundConfig.ArrivalProtectionSeconds)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		member.Trove:Connect(humanoid.Died, function()
			onDied(member)
		end)
	end
	return member
end

-- Whether there is a place for `player`: they already hold one, or the page is not full.
function Roster.hasRoom(player: Player): boolean
	return members[player] ~= nil or memberCount < BattlegroundConfig.MaxMembers
end

-- Runs deferred from CharacterAdded, after the new body has had RootWaitSeconds to bring its root. Everything
-- is asked again here, after the wait: MatchService.start marks a participant BEFORE prepareRound loads their
-- character, so a respawn racing the start of a match belongs to the match, and a body that was replaced in
-- the meantime belongs to no one.
local function redirect(player: Player, character: Model, defeated: number)
	character:WaitForChild(Context.RootPartName, Context.RootWaitSeconds)
	-- The new body stands on the hub, 1500 studs away: the camp streams in around its landing first.
	local landing = Roster.nextLanding()
	Teleport.streamAround(player, landing)
	if
		player.Character ~= character
		or deps.Match.isInMatch(player)
		or deps.WorldBoss.isEngaged(player)
		or Context.liveRoot(player) == nil
		or not Roster.hasRoom(player)
	then
		tell(player, nil)
		return
	end
	Roster.place(player, character, landing)
	Roster.pushSnapshot(Roster.admit(player, character, landing, os.clock(), defeated))
end

-- A member who died inside comes back to the camp, if the new body arrives within the respawn time plus
-- RespawnRedirectGraceSeconds and nothing else claimed them meanwhile. Anything else ends the membership.
local function onCharacterAdded(player: Player, character: Model)
	local pending = pendingRespawn[player.UserId]
	if pending == nil then
		return
	end
	pendingRespawn[player.UserId] = nil
	local late = os.clock() - pending.At > Players.RespawnTime + BattlegroundConfig.RespawnRedirectGraceSeconds
	if late or deps.Match.isInMatch(player) or deps.WorldBoss.isEngaged(player) then
		tell(player, nil)
		return
	end
	task.defer(redirect, player, character, pending.Defeated)
end

function Roster.track(player: Player)
	if playerTroves[player] ~= nil then
		return
	end
	local trove = Trove.new()
	playerTroves[player] = trove
	trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, character)
	end)
end

-- Lets go of a player another fight takes before it loads their next body -- a practice duel's pit
-- (BattlegroundService.openPit), as MatchService.start marks a participant first: their membership, and a death
-- inside still waiting for its body, which would otherwise send the fight's new body back to the camp.
function Roster.release(player: Player)
	Roster.drop(player)
	pendingRespawn[player.UserId] = nil
end

-- A player leaving the server: their membership, a death inside still waiting for its body, their connections.
function Roster.forget(player: Player)
	Roster.release(player)
	local trove = playerTroves[player]
	playerTroves[player] = nil
	if trove ~= nil then
		trove:Destroy()
	end
end

----------------------------------------------------------------
-- Tick
----------------------------------------------------------------

-- Whether a member is still one. The position is the one the server trusts, never the raw root: right after a
-- teleport the client still replicates where it was, and must not be dropped for it. A new body with no
-- SpawnLocation to start from has no trusted position at all; within the arrival grace the anchor is set back on
-- the landing.
local function stays(member: Member, now: number): boolean
	local player = member.Player
	if player.Parent ~= Players or deps.Match.isInMatch(player) or deps.WorldBoss.isEngaged(player) then
		return false
	end
	local trusted = deps.Combat.trustedPosition(player)
	if trusted ~= nil then
		return Context.insideBounds(handle.Layout, trusted)
	end
	if now - member.ArrivedAt < BotConfig.ArrivalGraceSeconds then
		deps.Combat.resyncPosition(player, member.Landing)
		return true
	end
	return false
end

-- What a member's body tells the page this tick: how long it has been out of reach of the floor, above or
-- below, whether it stood outside the camp, and, inside it, the heal.
local function observe(member: Member, now: number, dt: number)
	local point = Context.targetPoint(deps.Combat, member.Player)
	if point == nil then
		return
	end
	local standingRoot = handle.FloorY + BattlegroundConfig.StandingRootStuds
	if BotBrain.outOfReach(Context.Rules, point.Y - standingRoot) then
		member.OffFloorSince = member.OffFloorSince or now
	else
		member.OffFloorSince = nil
	end
	local x, _, z = Context.toLocal(point)
	if BattlegroundLayout.inRect(handle.Layout.Camp, x, z) then
		deps.Combat.heal(member.Player, CAMP.RegenPerSecond * dt, CAMP.QuietSeconds)
	else
		member.OutsideCampAt = now
	end
end

function Roster.step(now: number, dt: number)
	for _, member in ipairs(Roster.list()) do
		if stays(member, now) then
			observe(member, now, dt)
		else
			Roster.drop(member.Player)
		end
	end
end

-- Members who stood outside the camp within ActiveWindowSeconds: the ones the page fills for.
function Roster.activeCount(now: number): number
	local count = 0
	for _, member in pairs(members) do
		if now - member.OutsideCampAt < BotConfig.ActiveWindowSeconds then
			count += 1
		end
	end
	return count
end

function Roster.Init(injected: Context.Deps, map: Map.Handle, standingCount: () -> number)
	deps = injected
	handle = map
	standing = standingCount
end

return Roster
