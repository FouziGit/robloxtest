--!strict
-- PortalService: the portals (D-130). A portal is a circle a player STANDS in -- the chalk seal at the foot of
-- a gate (World/PortalGate) -- not a button. Ten times a second the server looks at where it trusts each
-- player stands (CombatService.trustedPosition), and whoever has stayed in one circle for its DwellSeconds is
-- moved: into the Battleground, into the Erasure's fight, or back to the hub.
--
-- No client-to-server remote exists for travelling, and none may (tests/Portal.spec.luau): the client never
-- asks to be moved, so there is nothing to forge, rate-limit or count against it, and a circle works the same
-- on a keyboard, a gamepad and a touch screen whatever key the player rebound. The client is only told -- the
-- band that fills while its player stands in a circle (PortalChanged), and where a trip took them (Travelled).
--
-- The circles are found by their seals' tag, and only while they stand in the Workspace: the Erasure's arena
-- template keeps a Return gate in ServerStorage, built around the world's origin, and its seal -- lying at the
-- height of the hub's own floor -- must never open a circle there.
-- A circle re-arms only once its player has stepped out of it, so a refusal is said once, not every dwell.
-- After a trip the player's circles stay shut for CooldownSeconds: no ping-pong between two gates, and no
-- chaining the arrival's invulnerability into a player nobody can hit.
--
-- One Heartbeat accumulator at PortalConfig.CheckHz steps every player. A trip runs in its own thread, because
-- entering the Battleground waits for the world around the landing to stream in; the player is not watched
-- until it is over.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local PortalConfig = require(Shared.Config.PortalConfig)
local Types = require(Shared.Types)

local log = Log.new("PortalService")

type PortalId = PortalConfig.PortalId
type NotifyKind = "Info" | "Success" | "Error"
type Deps = {
	Registry: { fire: (name: string, player: Player, ...any) -> () },
	Notify: {
		send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
	},
	-- Read, never judged: trustedOrigin counts violations, and a watcher asking ten times a second must not.
	Combat: {
		trustedPosition: (player: Player) -> Vector3?,
		grantIFrames: (player: Player, seconds: number) -> (),
	},
	Movement: { isDown: (player: Player) -> boolean },
	Match: { isInMatch: (player: Player) -> boolean },
	Hub: { teleportToHub: (player: Player) -> () },
	-- Each refuses with the Strings key the player is shown, or with none when there is nothing to say. `admits`
	-- asks without moving anyone.
	Battleground: {
		admits: (player: Player) -> (boolean, string?),
		enter: (player: Player) -> (boolean, string?),
		leave: (player: Player) -> (),
	},
	WorldBoss: {
		enterFromPortal: (player: Player) -> (boolean, string?, { [string]: any }?),
		leave: (player: Player) -> (),
	},
}

-- What the server knows of one player and the circles: the one they stand in (nil for none) and where it leads,
-- since when, whether it has already done what it does for this stay, and whether their band is up.
type Watch = { Seal: BasePart?, Id: PortalId?, Since: number, Fired: boolean, Shown: boolean }

local CHECK_SECONDS = 1 / PortalConfig.CheckHz
local RADIUS = PortalConfig.ZoneRadiusStuds
local HEIGHT = PortalConfig.ZoneHeightStuds
local ZONES = PortalConfig.Zones
local CHANGED_REMOTE = "PortalChanged"
local TRAVELLED_REMOTE = "Travelled"

local PortalService = {}

local deps: Deps
-- Every seal standing in the Workspace -> where its circle leads.
local seals: { [BasePart]: PortalId } = {}
local watches: { [Player]: Watch } = {}
-- Players whose trip is under way. Not watched until it is over: the circle they left keeps its Fired, so a
-- refused trip re-arms only when they step out.
local travelling: { [Player]: true } = {}
local cooldownUntil: { [Player]: number } = {}
local accumulator = 0

----------------------------------------------------------------
-- Seals
----------------------------------------------------------------

-- A tagged part becomes a circle only in the Workspace, and only if it names a destination this service knows.
local function addSeal(instance: Instance)
	if not instance:IsA("BasePart") or not instance:IsDescendantOf(Workspace) then
		return
	end
	local id = instance:GetAttribute(PortalConfig.SealAttribute)
	if type(id) ~= "string" or ZONES[id] == nil then
		log.warn(
			"%s is a seal that leads nowhere: %s is %s",
			instance:GetFullName(),
			PortalConfig.SealAttribute,
			tostring(id)
		)
		return
	end
	seals[instance] = id :: PortalId
end

local function removeSeal(instance: Instance)
	if instance:IsA("BasePart") then
		seals[instance] = nil
	end
end

-- The circle a position stands in: the nearest seal within the zone's radius on the ground and its height
-- above or below. Circles never overlap where they are built; the nearest wins if they ever do.
local function sealAt(position: Vector3): BasePart?
	local found: BasePart? = nil
	local nearest = math.huge
	for seal in pairs(seals) do
		local center = seal.Position
		if math.abs(position.Y - center.Y) <= HEIGHT then
			local dx, dz = position.X - center.X, position.Z - center.Z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= RADIUS and distance < nearest then
				found = seal
				nearest = distance
			end
		end
	end
	return found
end

----------------------------------------------------------------
-- Trips
----------------------------------------------------------------

-- Moves `player` through the gate to `id`: true, or false with the Strings key of the refusal -- none for a
-- silent one, such as no body to move -- and its params.
local function dispatch(player: Player, id: PortalId): (boolean, string?, { [string]: any }?)
	if id == "Battleground" then
		-- A participant of the Erasure's fight who walks off to the Battleground has left that fight -- once the
		-- page has said it takes them: one it refuses stays in the fight, and is only told why.
		local open, closed = deps.Battleground.admits(player)
		if not open then
			return false, closed, nil
		end
		deps.WorldBoss.leave(player)
		local entered, refusal = deps.Battleground.enter(player)
		return entered, refusal, nil
	elseif id == "WorldBoss" then
		return deps.WorldBoss.enterFromPortal(player)
	end
	-- Back to the hub: out of wherever the gate stood first, so neither place still counts them as its own.
	deps.Battleground.leave(player)
	deps.WorldBoss.leave(player)
	deps.Hub.teleportToHub(player)
	return true, nil, nil
end

-- A trip, and what follows it: the refusal said, or the arrival's cooldown, protection and news.
local function journey(player: Player, id: PortalId)
	local moved, refusal, params = dispatch(player, id)
	if not moved then
		if refusal ~= nil then
			deps.Notify.send(player, refusal, params, "Error")
		end
		return
	end
	-- A player who left while the world streamed in is already gone from every map here: writing their
	-- cooldown back would keep them in it for the life of the server.
	if player.Parent ~= Players then
		return
	end
	cooldownUntil[player] = os.clock() + PortalConfig.CooldownSeconds
	deps.Combat.grantIFrames(player, PortalConfig.EntryIFrameSeconds)
	deps.Registry.fire(TRAVELLED_REMOTE, player, id)
end

-- One trip, in its own thread. Whatever happens in it, the player is watched again afterwards.
local function travel(player: Player, id: PortalId)
	log.try(("%s through the %s gate"):format(player.Name, id), journey, player, id)
	travelling[player] = nil
end

----------------------------------------------------------------
-- Watch
----------------------------------------------------------------

-- Where a circle may find `player`: the position the server trusts, and none while a match holds them or
-- while they are dead -- a body lying in a circle goes nowhere.
local function standing(player: Player): Vector3?
	if deps.Match.isInMatch(player) then
		return nil
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return deps.Combat.trustedPosition(player)
end

local function onCooldown(player: Player, now: number): boolean
	return now < (cooldownUntil[player] or 0)
end

local function show(player: Player, watch: Watch, id: PortalId)
	watch.Shown = true
	local snapshot: Types.PortalSnapshot = { Id = id, Seconds = ZONES[id].DwellSeconds }
	deps.Registry.fire(CHANGED_REMOTE, player, snapshot)
end

local function hide(player: Player, watch: Watch)
	if watch.Shown then
		watch.Shown = false
		deps.Registry.fire(CHANGED_REMOTE, player, nil)
	end
end

-- The circle under `player` is another one than a tick ago, or none: its dwell starts over, and the band shows
-- it -- unless a trip has just ended, when nothing shows until the cooldown has run out.
local function moveTo(player: Player, watch: Watch, seal: BasePart?, now: number)
	local id: PortalId? = if seal ~= nil then seals[seal] else nil
	watch.Seal = seal
	watch.Id = id
	watch.Since = now
	watch.Fired = false
	if id ~= nil and not onCooldown(player, now) then
		show(player, watch, id)
	else
		hide(player, watch)
	end
end

local function step(player: Player, watch: Watch, now: number)
	local position = standing(player)
	local seal = if position ~= nil then sealAt(position) else nil
	if seal ~= watch.Seal then
		moveTo(player, watch, seal, now)
		return
	end
	local id: PortalId? = watch.Id
	if id == nil or watch.Fired then
		return
	end
	local cooling = onCooldown(player, now)
	if not cooling and not watch.Shown then
		-- The cooldown ran out while they stood here: the dwell counts from now, under the band that says so,
		-- so nobody is ever taken by a circle that never showed it would.
		watch.Since = now
		show(player, watch, id)
		return
	end
	-- A player on the ground is not standing in anything yet: the next tick asks again.
	if now - watch.Since < ZONES[id].DwellSeconds or deps.Movement.isDown(player) then
		return
	end
	watch.Fired = true
	if cooling then
		deps.Notify.send(player, "portal.cooldown", nil, "Info")
		return
	end
	hide(player, watch)
	travelling[player] = true
	task.spawn(travel, player, id)
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < CHECK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - CHECK_SECONDS, CHECK_SECONDS)
	local now = os.clock()
	for player, watch in pairs(watches) do
		if travelling[player] == nil then
			step(player, watch, now)
		end
	end
end

local function track(player: Player)
	watches[player] = { Seal = nil, Id = nil, Since = 0, Fired = false, Shown = false }
end

local function forget(player: Player)
	watches[player] = nil
	travelling[player] = nil
	cooldownUntil[player] = nil
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function PortalService.Init(injected: Deps)
	deps = injected
end

-- After every builder of a gate has started, so the first look finds the hub's and the Battleground's seals;
-- the Erasure's arena copies arrive later, through the tag's signal.
function PortalService.Start()
	CollectionService:GetInstanceAddedSignal(PortalConfig.SealTag):Connect(addSeal)
	CollectionService:GetInstanceRemovedSignal(PortalConfig.SealTag):Connect(removeSeal)
	for _, instance in ipairs(CollectionService:GetTagged(PortalConfig.SealTag)) do
		addSeal(instance)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(forget)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
	RunService.Heartbeat:Connect(onHeartbeat)
	local count = 0
	for _ in pairs(seals) do
		count += 1
	end
	log.info("watching %d portal circles at %d Hz", count, PortalConfig.CheckHz)
end

return PortalService
