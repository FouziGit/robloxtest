--!strict
-- FlyleafService: the Flyleaf (« La Page de garde », E16-S2), a permanent page built in code at world X = -1500
-- where every member fights every other: no queue, no rank, light pay. A third gate of the hub leads in (D-130: a
-- circle the server sees a player stand in, no remote), a Return gate on the page leads home.
--
-- It owns the Flyleaf zone (CombatService.claimZone, ZoneConfig): two members hurt each other once both are out of
-- their protection, nobody else hurts a member and a member hurts nobody else. A member arrives, and comes back
-- RespawnSeconds after a death, on the seal furthest from every other member (Pure/FlyleafRules.farthestSeal),
-- protected for ProtectionSeconds -- the engine's ForceField shows it, the page's own clock decides it, since a
-- client can delete what its body wears. A kill is paid by Rewards; a run of ManiculeKills puts the Manicule on the
-- killer's body, which every client draws (ManiculeController).
--
-- A member stays one only while every tick agrees: still in the server, in no match, not taken by the Erasure's
-- event, on the same body, and standing on the page by the position the server TRUSTS. Whoever fails is let go and
-- told (FlyleafChanged nil), so every way out another service takes ends the membership with no hook in it. One
-- Heartbeat accumulator at FlyleafConfig.TickHz steps all of it; a respawn, which yields on LoadCharacterAsync and on
-- the world streaming in, runs in its own thread and asks everything again once it is back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Context = require(script.Context)
local FlyleafConfig = require(Shared.Config.FlyleafConfig)
local FlyleafRules = require(script.Parent.Parent.Pure.FlyleafRules)
local Log = require(Shared.Util.Log)
local Map = require(script.Map)
local PortalConfig = require(Shared.Config.PortalConfig)
local Rewards = require(script.Rewards)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("FlyleafService")

type Deps = Context.Deps
type TroveType = typeof(Trove.new())
type Member = {
	Player: Player,
	Character: Model,
	-- Where the server put them: the anchor trust is re-set to while the new body has none yet.
	Landing: Vector3,
	ArrivedAt: number,
	-- Until when nobody hurts them and they hurt nobody, and the ForceField that shows it until then.
	ProtectedUntil: number,
	Shield: ForceField?,
	-- Lives taken since they came in, deaths included, and since they last lost theirs.
	Kills: number,
	Streak: number,
	-- The current body's connections.
	Trove: TroveType,
}
-- A member who died, until their next body stands on a seal: when, what they had taken, and the run they lost.
type Pending = { At: number, Kills: number, Streak: number, Respawning: boolean }

local TICK_SECONDS = 1 / FlyleafConfig.TickHz

local FlyleafService = {}

local deps: Deps
local handle: Map.Handle? = nil
local members: { [Player]: Member } = {}
local memberCount = 0
local pending: { [Player]: Pending } = {}
-- The seal the next arrival on an empty page takes, in turn.
local turn = 0
local accumulator = 0

----------------------------------------------------------------
-- Members
----------------------------------------------------------------

local function tell(player: Player, snapshot: Types.FlyleafSnapshot?)
	if player.Parent == Players then
		deps.Registry.fire(Context.SnapshotRemote, player, snapshot)
	end
end

-- Everybody on the page: its members, and the fallen ones about to come back.
local function present(): number
	local count = memberCount
	for _ in pairs(pending) do
		count += 1
	end
	return count
end

local function pushSnapshot(member: Member)
	tell(member.Player, { Members = present(), Kills = member.Kills, Streak = member.Streak })
end

local function pushAll()
	for _, member in pairs(members) do
		pushSnapshot(member)
	end
end

-- Every member's word to every other member: who wears the Manicule, who took it off them.
local function tellMembers(key: string, params: { [string]: any })
	for player in pairs(members) do
		deps.Notify.send(player, key, params, "Info")
	end
end

local function unshield(member: Member)
	local shield = member.Shield
	member.Shield = nil
	if shield ~= nil then
		shield:Destroy()
	end
end

-- The seal `player` lands on: the one furthest from every other member standing on the page.
local function nextLanding(map: Map.Handle, player: Player): Vector3
	local others: { FlyleafRules.Point } = {}
	for other in pairs(members) do
		local trusted = if other ~= player then deps.Combat.trustedPosition(other) else nil
		if trusted ~= nil then
			local x, _, z = Context.toLocal(trusted)
			table.insert(others, { X = x, Z = z })
		end
	end
	turn += 1
	return map.Standing[FlyleafRules.farthestSeal(map.Layout.Seals, others, turn)]
end

-- Puts the character down on `landing`, facing the centre of the page, with its velocity cleared -- and re-anchors
-- the position CombatService trusts on that point, never on what the client says next.
local function place(player: Player, character: Model, landing: Vector3)
	local center = Context.Origin
	character:PivotTo(CFrame.lookAt(landing, Vector3.new(center.X, landing.Y, center.Z)))
	local root = character.PrimaryPart
	if root ~= nil then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	deps.Combat.resyncPosition(player, landing)
end

-- Lets go of a member now: their body loses the page's marks, and they are told. Nothing for a non-member.
local function drop(player: Player)
	local member = members[player]
	if member == nil then
		return
	end
	members[player] = nil
	memberCount -= 1
	member.Trove:Destroy()
	unshield(member)
	member.Character:SetAttribute(FlyleafConfig.MemberAttribute, nil)
	member.Character:SetAttribute(FlyleafConfig.ManiculeAttribute, nil)
	tell(player, nil)
	pushAll()
end

-- A member's body died: the membership waits for the next body, which the page puts back on a seal
-- RespawnSeconds later (respawn). No nil is sent, so the band does not flicker through the death.
local function onDied(member: Member)
	local player = member.Player
	if members[player] ~= member then
		return
	end
	members[player] = nil
	memberCount -= 1
	member.Trove:Destroy()
	unshield(member)
	pending[player] = { At = os.clock(), Kills = member.Kills, Streak = member.Streak, Respawning = false }
end

-- Makes `player` a member standing on `landing` on this `character`, protected from now, and tells everybody on
-- the page how many they are.
local function admit(player: Player, character: Model, landing: Vector3, kills: number)
	local now = os.clock()
	pending[player] = nil
	local member: Member = {
		Player = player,
		Character = character,
		Landing = landing,
		ArrivedAt = now,
		ProtectedUntil = now + FlyleafConfig.ProtectionSeconds,
		Shield = nil,
		Kills = kills,
		Streak = 0,
		Trove = Trove.new(),
	}
	members[player] = member
	memberCount += 1
	local shield = Instance.new("ForceField")
	shield.Visible = true
	shield.Parent = character
	member.Shield = shield
	character:SetAttribute(FlyleafConfig.MemberAttribute, true)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		member.Trove:Connect(humanoid.Died, function()
			onDied(member)
		end)
	end
	pushAll()
end

-- Whether there is a place for `player`: they already hold one (or are coming back from a death), or the page is
-- not full.
local function hasRoom(player: Player): boolean
	local count = memberCount
	for other in pairs(pending) do
		if other ~= player then
			count += 1
		end
	end
	return members[player] ~= nil or count < FlyleafConfig.MaxMembers
end

-- Waits, at most PortalConfig.StreamTimeoutSeconds, for the world around `landing` to stream in for `player`.
local function streamAround(player: Player, landing: Vector3)
	if Workspace.StreamingEnabled then
		log.try("RequestStreamAroundAsync", function()
			player:RequestStreamAroundAsync(landing, PortalConfig.StreamTimeoutSeconds)
		end)
	end
end

-- A fallen member who will not come back: they are told, and the others see one rival fewer.
local function abandon(player: Player)
	pending[player] = nil
	tell(player, nil)
	pushAll()
end

-- Anything that claimed `player` elsewhere while a trip or a respawn yielded.
local function claimedElsewhere(player: Player): boolean
	return player.Parent ~= Players or deps.Match.isInMatch(player) or deps.WorldBoss.isEngaged(player)
end

----------------------------------------------------------------
-- Respawn
----------------------------------------------------------------

-- A dead member's next body, RespawnSeconds after the death, on the seal furthest from the others. Runs in its own
-- thread, started by the tick that found nothing else claiming them: LoadCharacterAsync and the streaming both yield,
-- and everything is asked again after each.
local function respawn(map: Map.Handle, player: Player, entry: Pending)
	local loaded = log.try("LoadCharacterAsync " .. player.Name, function()
		player:LoadCharacterAsync()
	end)
	local character = player.Character
	if pending[player] ~= entry then
		return
	end
	if not loaded or character == nil or claimedElsewhere(player) then
		abandon(player)
		return
	end
	local landing = nextLanding(map, player)
	streamAround(player, landing)
	if pending[player] ~= entry then
		return
	end
	if claimedElsewhere(player) or player.Character ~= character or Context.liveRoot(player) == nil then
		abandon(player)
		return
	end
	place(player, character, landing)
	admit(player, character, landing, entry.Kills)
end

----------------------------------------------------------------
-- Tick
----------------------------------------------------------------

-- Whether a member is still one: see the header. Right after a placement the client may still replicate where it
-- was; the trusted position follows the server's own resync, and a new body with none yet is put back on its seal
-- within TrustGraceSeconds.
local function stays(member: Member, now: number): boolean
	local player = member.Player
	if claimedElsewhere(player) or player.Character ~= member.Character then
		return false
	end
	local map = handle
	local trusted = deps.Combat.trustedPosition(player)
	if map ~= nil and trusted ~= nil then
		return Context.insideBounds(map.Layout, trusted)
	end
	if now - member.ArrivedAt < FlyleafConfig.TrustGraceSeconds then
		deps.Combat.resyncPosition(player, member.Landing)
		return true
	end
	return false
end

local function tick(map: Map.Handle, now: number)
	Map.judgeFalls(map)
	for player, member in pairs(members) do
		if not stays(member, now) then
			drop(player)
		elseif member.Shield ~= nil and now >= member.ProtectedUntil then
			unshield(member)
		end
	end
	for player, entry in pairs(pending) do
		if claimedElsewhere(player) or now - entry.At >= FlyleafConfig.RespawnGiveUpSeconds then
			abandon(player)
		elseif not entry.Respawning and now - entry.At >= FlyleafConfig.RespawnSeconds then
			entry.Respawning = true
			task.spawn(function()
				log.try("respawn " .. player.Name, respawn, map, player, entry)
			end)
		end
	end
	Rewards.prune(now)
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local map = handle
	if map ~= nil then
		tick(map, os.clock())
	end
end

----------------------------------------------------------------
-- Zone and kills
----------------------------------------------------------------

-- The Flyleaf zone's rule: two members, both out of their protection.
local function pairAllowed(source: Player, target: Player): boolean
	local attacker, victim = members[source], members[target]
	local now = os.clock()
	return attacker ~= nil and victim ~= nil and now >= attacker.ProtectedUntil and now >= victim.ProtectedUntil
end

-- A member who took a life: counted, paid, and on a run of ManiculeKills, marked. A victim who wore the Manicule
-- loses it with their body, and everybody on the page hears who took it off them.
local function onKilled(sourceUserId: number, victimModel: Model)
	local victim = Players:GetPlayerFromCharacter(victimModel)
	local killer = Players:GetPlayerByUserId(sourceUserId)
	if victim == nil or killer == nil or victim == killer then
		return
	end
	local fallen = members[victim]
	local lost = pending[victim]
	if (fallen == nil or fallen.Character ~= victimModel) and lost == nil then
		return
	end
	local member = members[killer]
	local dead = pending[killer]
	if member == nil and dead == nil then
		return
	end
	local victimStreak = if fallen ~= nil then fallen.Streak elseif lost ~= nil then lost.Streak else 0
	log.try("Rewards.pay", Rewards.pay, killer, victim, os.clock())
	if FlyleafRules.wearsManicule(victimStreak, FlyleafConfig.ManiculeKills) then
		tellMembers("flyleaf.maniculeTaken", { name = killer.DisplayName, rival = victim.DisplayName })
	end
	if member == nil then
		if dead ~= nil then
			dead.Kills += 1
		end
		return
	end
	member.Kills += 1
	member.Streak += 1
	if member.Streak == FlyleafConfig.ManiculeKills then
		member.Character:SetAttribute(FlyleafConfig.ManiculeAttribute, true)
		tellMembers("flyleaf.manicule", { name = killer.DisplayName })
	end
	pushSnapshot(member)
end

local function onPlayerRemoving(player: Player)
	drop(player)
	if pending[player] ~= nil then
		abandon(player)
	end
	Rewards.forget(player)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Whether the page would take `player` now, or the Strings key it refuses with: it is not built, they are in a
-- match, or it is full. The hub's gate asks before it lets a player out of the Erasure's fight.
function FlyleafService.admits(player: Player): (boolean, string?)
	if handle == nil then
		return false, "portal.unavailable"
	end
	if deps.Match.isInMatch(player) then
		return false, "queue.inMatch"
	end
	if not hasRoom(player) then
		return false, "flyleaf.full"
	end
	return true, nil
end

-- Puts `player` on the seal furthest from every other member. Refuses with a Strings key the caller shows (or none,
-- silently): the page does not admit them, or they have no body to move. Everything that can change while the
-- world streams in around the landing is asked again after that wait.
function FlyleafService.enter(player: Player): (boolean, string?)
	local admitted, refusal = FlyleafService.admits(player)
	local map = handle
	if not admitted or map == nil then
		return false, refusal
	end
	local character = player.Character
	if character == nil or Context.liveRoot(player) == nil then
		return false, nil
	end
	local landing = nextLanding(map, player)
	streamAround(player, landing)
	if deps.Match.isInMatch(player) then
		return false, "queue.inMatch"
	end
	if not hasRoom(player) then
		return false, "flyleaf.full"
	end
	if deps.WorldBoss.isEngaged(player) or player.Character ~= character or Context.liveRoot(player) == nil then
		return false, nil
	end
	place(player, character, landing)
	local previous = members[player]
	if previous ~= nil then
		drop(player)
	end
	admit(player, character, landing, if previous ~= nil then previous.Kills else 0)
	deps.Notify.send(player, "flyleaf.entered", nil, "Info")
	return true
end

-- Lets `player` go now (a gate took them elsewhere), and a death inside waiting for its body with them.
function FlyleafService.leave(player: Player)
	drop(player)
	if pending[player] ~= nil then
		abandon(player)
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function FlyleafService.Init(injected: Deps)
	deps = injected
	Rewards.Init(injected)
end

function FlyleafService.Start()
	local map = Map.build()
	handle = map
	deps.Combat.claimZone("Flyleaf", {
		Holds = function(player: Player): boolean
			return members[player] ~= nil
		end,
		Pair = pairAllowed,
	})
	deps.Combat.Killed:Connect(onKilled)
	map.KillZone.Touched:Connect(Map.onKillZoneTouched)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info(
		"page built at x %d: %d studs, %d seals, up to %d members",
		Context.Origin.X,
		FlyleafConfig.Map.Size,
		#map.Standing,
		FlyleafConfig.MaxMembers
	)
end

return FlyleafService
