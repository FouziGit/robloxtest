--!strict
-- BattlegroundService: the Battleground (D-131), a permanent page built in code at world X = 1500 where the
-- Forgers -- server-owned ink figures driven by BotBrain -- come at whoever walks in. PvE only: the PvP rule
-- MatchService installs already lets server-authored damage through and nothing else.
--
-- This module owns the lifecycle, the public API and the one Heartbeat accumulator every Forger and every
-- member is stepped from: the roster (Roster), how many Forgers the page holds for how many active members,
-- what each Forger perceives when it thinks, and the orders BotBrain gives back, applied through Motion and
-- Attacks. The page is Map, the bodies Bots, the pay Rewards.
--
-- It reacts to CombatService, never the other way round: a Forger hurt by a player (Damaged), thrown
-- (Shoved), held by a glyph (Controlled) or killed (Killed) is found by its model. Nothing here runs a thread
-- per Forger or per player, and with no member active for BotConfig.IdleDespawnSeconds the page holds nobody
-- and every tick is empty.
--
-- Entry is `enter`, which a portal calls: it refuses with a Strings key the caller shows, or places the player
-- in the camp, where a player who dies here also comes back (BattlegroundConfig.RespawnInside).
--
-- It also lends the pits of the practice duel (Pits, E10-S6): SparService runs the duel's rounds, and every pit's
-- Forger is stepped from the same tick as the page's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Attacks = require(script.Attacks)
local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BotBrain = require(Shared.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Bots = require(script.Bots)
local Context = require(script.Context)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Map = require(script.Map)
local Motion = require(script.Motion)
local Perception = require(script.Perception)
local Pits = require(script.Pits)
local PortalConfig = require(Shared.Config.PortalConfig)
local Rewards = require(script.Rewards)
local Roster = require(script.Roster)
local Trove = require(Packages.Trove)

local log = Log.new("BattlegroundService")

type Deps = Context.Deps
type Bot = Bots.Bot

local TICK_SECONDS = 1 / GameConfig.Server.TickRate
-- Every Forger thinks once per this many ticks, on the tick its slot falls on, so the thinks spread out.
local TICKS_PER_THINK = math.max(1, math.floor(GameConfig.Server.TickRate / BotConfig.ThinkHz))
local RULES = Context.Rules
local PITS = BattlegroundConfig.Pits
local RESPAWN = BotConfig.Respawn
local CAMP = BotConfig.Camp

local BattlegroundService = {}

local deps: Deps
local handle: Map.Handle? = nil
-- User id -> until when no Forger may start a melee chain on them (BotBrain.tokenFree). A rest that is over is
-- dropped on the next tick, so nobody who left the server mid-chain stays in it.
local restUntil: { [number]: number } = {}
-- Until when a camp hitter is not told again that the camp's hits do not count (noticeCampHit).
local campNoticeUntil: { [Player]: number } = {}
local accumulator = 0
local lastTickAt = 0
local tickCount = 0
local emptySince: number? = nil
local lastStanding = -1

----------------------------------------------------------------
-- Orders
----------------------------------------------------------------

-- Rests a player until `untilTime`, never cutting short a rest they already have.
local function rest(userId: number, untilTime: number)
	restUntil[userId] = math.max(restUntil[userId] or 0, untilTime)
end

-- Applies one think's orders: the blow that came due against `members` (the page's roster, or a pit's duellist),
-- the rests it earns, the next wind-up, the heal at home, then the walk or the stop and the facing.
local function apply(bot: Bot, decision: BotBrain.Decision, now: number, members: { Roster.Member })
	local resolve = decision.Resolve
	if resolve ~= nil then
		local outcome = Attacks.resolve(bot, resolve, members, now)
		if resolve.Final then
			for userId, untilTime in pairs(BotBrain.finisherRests(RULES, now, resolve.TargetUserId, outcome.Held)) do
				rest(userId, untilTime)
			end
		end
	end
	local ended = decision.Ended
	if ended ~= nil then
		rest(ended.TargetUserId, BotBrain.restAfter(RULES, now, false, 0))
	end
	local attack = decision.Start or decision.Continue
	if attack ~= nil then
		Attacks.windup(bot, attack, attack.ResolveAt - now, now)
	end
	if decision.Heal then
		bot.Humanoid.Health = bot.Humanoid.MaxHealth
		table.clear(bot.Ledger)
	end
	local goal = decision.Goal
	if decision.Stand then
		Motion.stand(bot)
	elseif goal ~= nil then
		Motion.walkTo(bot, goal.X, goal.Z, now)
	end
	local holding = bot.Memory.Attack ~= nil
	local faceX, faceZ = decision.FaceX, decision.FaceZ
	if faceX ~= nil and faceZ ~= nil then
		Motion.face(bot, faceX, faceZ, holding)
	elseif not holding then
		Motion.release(bot)
	end
end

-- A stagger that applied cuts the wind-up it caught, and every client takes its tell back; a cut melee chain
-- rests its target like a finished one.
local function stagger(bot: Bot, now: number, source: BotBrain.StaggerSource, seconds: number?)
	local applied, cancelled = BotBrain.stagger(bot.Def, RULES, bot.Memory, now, source, seconds)
	if not applied then
		return
	end
	if cancelled ~= nil then
		Attacks.retract(bot)
		if cancelled.Kind == "Melee" then
			rest(cancelled.TargetUserId, BotBrain.restAfter(RULES, now, false, 0))
		end
	end
	Motion.flinch(bot)
	Motion.stand(bot)
	Motion.release(bot)
end

----------------------------------------------------------------
-- Tick
----------------------------------------------------------------

-- A Forger that died with a wind-up pending, whatever killed it: that blow never comes, so its tell is taken
-- back, on the first tick after the death.
local function dropAttack(bot: Bot)
	if bot.Memory.Attack ~= nil then
		bot.Memory.Attack = nil
		Attacks.retract(bot)
	end
end

-- The body between two thinks: a corpse removed when its time is up, a Forger that fell off the page killed
-- (no credit), and the throw, the slow, the scheduled clip and the walk cycle stepped.
local function maintain(map: Map.Handle, bot: Bot, now: number)
	if bot.Model.Parent == nil then
		Bots.kill(bot, now)
		dropAttack(bot)
		Bots.destroy(bot)
		return
	end
	if bot.Dead then
		dropAttack(bot)
		if now >= bot.DestroyAt then
			Bots.destroy(bot)
		end
		return
	end
	if bot.Root.Position.Y < map.FloorY - BotConfig.FallMarginStuds then
		Bots.kill(bot, now)
		return
	end
	Motion.stepMover(bot, now)
	Motion.stepSlow(bot, now)
	Motion.stepClip(bot, now)
	Motion.stepLocomotion(bot)
end

-- Fills the empty slots up to the page's population for `active` members, each once its respawn delay since
-- the last death there is over, on the spawn furthest from every member (and from any Forger that appeared in
-- the same tick).
local function populate(map: Map.Handle, now: number, active: number)
	if not Bots.ready() then
		return
	end
	local count = BotBrain.population(active, BotConfig.BaseCount, BotConfig.PerExtraMember, BotConfig.MaxBots)
	local delay = BotBrain.respawnSeconds(active, RESPAWN.BaseSeconds, RESPAWN.StepSeconds, RESPAWN.MinSeconds)
	local spawns = map.Layout.BotSpawns
	local avoid: { BotBrain.Point } = {}
	for _, member in ipairs(Roster.list()) do
		local point = Context.targetPoint(deps.Combat, member.Player)
		if point ~= nil then
			local x, _, z = Context.toLocal(point)
			table.insert(avoid, { X = x, Z = z })
		end
	end
	for slot = 1, count do
		local since = Bots.vacantSince(slot)
		if Bots.bySlot(slot) == nil and (since == nil or now - since >= delay) then
			local index = BotBrain.pickSpawn(spawns, avoid, (slot - 1) % #spawns + 1)
			if Bots.spawn(slot, BotConfig.Roster[slot], index) ~= nil then
				table.insert(avoid, spawns[index])
			end
		end
	end
end

-- Every living Forger whose think falls on this tick, and any whose wind-up came due -- a blow never lands
-- more than one tick after the moment its tell promised.
local function think(now: number)
	local bots: { Bot } = {}
	for _, bot in ipairs(Bots.all()) do
		if not bot.Dead then
			table.insert(bots, bot)
		end
	end
	if #bots == 0 then
		return
	end
	local seen = Perception.survey()
	local engaged = Perception.engagement(bots, seen)
	for _, bot in ipairs(bots) do
		local attack = bot.Memory.Attack
		local due = attack ~= nil and now >= attack.ResolveAt
		if not bot.Dead and (due or (bot.Slot + tickCount) % TICKS_PER_THINK == 0) then
			local perception = Perception.perceive(bot, now, seen, engaged, bots, restUntil)
			apply(bot, BotBrain.decide(bot.Def, RULES, bot.Memory, perception), now, Roster.list())
		end
	end
end

-- A player's body at the kill plane under the page: a death of the environment, credited to nobody.
local function fell(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.Health > 0 and Players:GetPlayerFromCharacter(model) ~= nil then
		humanoid.Health = 0
	end
end

-- The kill plane as the server sees it, every tick: Touched is the owning client's word, so a tampered client
-- simply never touched it and stayed under the page. Any player whose root is under the plane, inside its
-- footprint, fell off -- members or not, since the roster lets a member go as soon as the trusted position leaves
-- the floor, long before the plane.
local function judgeFalls(map: Map.Handle)
	local plane = map.KillZone
	local half = plane.Size / 2
	for _, player in ipairs(Players:GetPlayers()) do
		local root = Context.liveRoot(player)
		local character = player.Character
		if root ~= nil and character ~= nil then
			local offset = plane.CFrame:PointToObjectSpace(root.Position)
			if offset.Y < 0 and math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then
				fell(character)
			end
		end
	end
end

-- The pits' Forgers (Pits): each kept like the page's between thinks, and thought for on its slot's tick -- or when
-- its wind-up comes due -- while its round is on, with its one duellist for all it sees. A duellist whose root
-- falls FallDepthStuds under the floor has fallen out of the pit.
local function stepPits(map: Map.Handle, now: number)
	for _, pit in ipairs(Pits.occupied()) do
		local bot = pit.Bot
		if bot ~= nil and Bots.byModel(bot.Model) == bot then
			maintain(map, bot, now)
		end
		local member = pit.Member
		local attack = if bot ~= nil then bot.Memory.Attack else nil
		local due = attack ~= nil and now >= attack.ResolveAt
		if
			bot ~= nil
			and member ~= nil
			and pit.Ground.Live
			and not bot.Dead
			and (due or (bot.Slot + tickCount) % TICKS_PER_THINK == 0)
		then
			local seen = Perception.see(member)
			local perception = Perception.perceive(
				bot,
				now,
				if seen ~= nil then { seen } else {},
				{},
				{ bot },
				restUntil
			)
			perception.CenterX, perception.CenterZ = pit.FaceX, pit.FaceZ
			apply(bot, BotBrain.decide(bot.Def, RULES, bot.Memory, perception), now, { member })
		end
		local owner = pit.Owner
		local root = if owner ~= nil then Context.liveRoot(owner) else nil
		local character = if owner ~= nil then owner.Character else nil
		if root ~= nil and character ~= nil and root.Position.Y < map.FloorY - PITS.FallDepthStuds then
			fell(character)
		end
	end
end

local function tick(map: Map.Handle, now: number, dt: number)
	-- A rest that is over is forgotten, whoever it was for: one written for a player who left mid-chain too.
	for userId, untilTime in pairs(restUntil) do
		if untilTime <= now then
			restUntil[userId] = nil
		end
	end
	judgeFalls(map)
	Roster.step(now, dt)
	for _, bot in ipairs(Bots.all()) do
		maintain(map, bot, now)
	end
	local active = Roster.activeCount(now)
	if active == 0 then
		-- Nobody to fill the page for: once that has lasted IdleDespawnSeconds, it holds nobody. Until then the
		-- Forgers keep thinking, so no wind-up is ever left hanging to land on whoever comes back.
		local since = emptySince or now
		emptySince = since
		if now - since >= BotConfig.IdleDespawnSeconds then
			Bots.destroyAll()
		end
	else
		emptySince = nil
		populate(map, now, active)
	end
	think(now)
	stepPits(map, now)
	local standing = Bots.standing()
	if standing ~= lastStanding then
		lastStanding = standing
		Roster.pushAll()
	end
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local map = handle
	if map == nil then
		return
	end
	local now = os.clock()
	local dt = if lastTickAt > 0 then now - lastTickAt else 0
	lastTickAt = now
	tickCount += 1
	tick(map, now, dt)
end

----------------------------------------------------------------
-- Reactions
----------------------------------------------------------------

local function livingBot(model: Model): Bot?
	local bot = Bots.byModel(model)
	if bot == nil or bot.Dead then
		return nil
	end
	return bot
end

-- Whether the player behind a hit stands in the camp, where a Forger sees them (Context.targetPoint).
local function hitFromCamp(map: Map.Handle, sourceUserId: number): boolean
	local source = Players:GetPlayerByUserId(sourceUserId)
	local point = if source ~= nil then Context.targetPoint(deps.Combat, source) else nil
	return point ~= nil and Context.inCamp(map.Layout, point)
end

-- The camp's hitter is told why the Forger's health bar did not move -- the damage number still shows, the
-- hit having landed before it was given back -- at most once per CAMP.HitNoticeSeconds.
local function noticeCampHit(sourceUserId: number, now: number)
	local source = Players:GetPlayerByUserId(sourceUserId)
	if source == nil or now < (campNoticeUntil[source] or 0) then
		return
	end
	campNoticeUntil[source] = now + CAMP.HitNoticeSeconds
	deps.Notify.send(source, "battleground.campHit", nil, "Info")
end

-- A player's hit: counted toward their share of the kill -- the killing blow too, whether or not the engine
-- has already delivered the body's Died -- unless it came from the camp, which earns nothing, is given back
-- to a Forger it did not kill (BotBrain.creditHit) and neither staggers it nor draws it: a Forger never
-- answers the camp, so nothing done from there may hold one off a player outside. Otherwise, on a Forger
-- still standing, remembered for retaliation and a stagger unless its poise holds.
local function onDamaged(sourceUserId: number, model: Model, applied: number, _kind: string)
	local bot = Bots.byModel(model)
	local map = handle
	if bot == nil or map == nil or applied <= 0 then
		return
	end
	local fromCamp = hitFromCamp(map, sourceUserId)
	local refund = BotBrain.creditHit(bot.Ledger, sourceUserId, applied, fromCamp)
	if bot.Dead then
		return
	end
	local humanoid = bot.Humanoid
	if refund > 0 and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.Health + refund, humanoid.MaxHealth)
	end
	local now = os.clock()
	if fromCamp then
		noticeCampHit(sourceUserId, now)
		return
	end
	BotBrain.noteHit(bot.Memory, sourceUserId, now)
	stagger(bot, now, "Hit", nil)
end

local function onShoved(model: Model, velocity: Vector3, duration: number)
	local bot = livingBot(model)
	if bot == nil then
		return
	end
	local now = os.clock()
	Motion.shove(bot, velocity, duration, now)
	stagger(bot, now, "Knockback", nil)
end

local function onControlled(model: Model, kind: string, seconds: number, factor: number, key: string)
	local bot = livingBot(model)
	if bot == nil then
		return
	end
	local now = os.clock()
	if kind == "Stun" then
		stagger(bot, now, "Control", seconds)
	elseif kind == "Slow" then
		Motion.slow(bot, key, factor, seconds, now)
	end
end

-- Fired inside ApplyDamage, before or after the body's Died: the Forger is found by model either way, dead or
-- not, and credited once.
local function onKilled(sourceUserId: number, model: Model)
	local bot = Bots.byModel(model)
	if bot == nil or bot.Credited then
		return
	end
	bot.Credited = true
	log.try("Rewards.pay", Rewards.pay, bot, sourceUserId, os.clock())
end

-- The closest ancestor Model that owns a Humanoid: accessories and tools nest their parts under it.
local function bodyOf(part: BasePart): Model?
	local ancestor: Instance? = part.Parent
	while ancestor ~= nil do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") ~= nil then
			return ancestor :: Model
		end
		ancestor = ancestor.Parent
	end
	return nil
end

-- The kill plane as the client that owns the falling body reports it: Touched. Any player's body that reaches it
-- dies (a member who fell has already left the roster by then), and so does a Forger.
local function onKillZoneTouched(part: BasePart)
	local model = bodyOf(part)
	if model == nil then
		return
	end
	local bot = Bots.byModel(model)
	if bot ~= nil then
		Bots.kill(bot, os.clock())
		return
	end
	fell(model)
end

local function onPlayerRemoving(player: Player)
	local pit = Pits.of(player)
	if pit ~= nil then
		Pits.release(pit)
	end
	Roster.forget(player)
	Rewards.forget(player)
	restUntil[player.UserId] = nil
	campNoticeUntil[player] = nil
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Whether the page would take `player` now, or the Strings key it refuses with: it is not ready, they are in a
-- match, or it is full. The hub's gate asks before it lets a player out of the Erasure's fight, so a trip the
-- page refuses leaves them in that fight.
function BattlegroundService.admits(player: Player): (boolean, string?)
	if handle == nil or not Bots.ready() then
		return false, "portal.unavailable"
	end
	if deps.Match.isInMatch(player) then
		return false, "queue.inMatch"
	end
	if not Roster.hasRoom(player) then
		return false, "battleground.full"
	end
	return true, nil
end

-- Puts `player` in the camp. Refuses with a Strings key the caller shows (or none, silently): the page does not
-- admit them, or they have no body to move. Everything that can change while the world streams in around the
-- landing is asked again after that wait.
function BattlegroundService.enter(player: Player): (boolean, string?)
	local admitted, refusal = BattlegroundService.admits(player)
	if not admitted then
		return false, refusal
	end
	local character = player.Character
	if character == nil or Context.liveRoot(player) == nil then
		return false, nil
	end
	local landing = Roster.nextLanding()
	if Workspace.StreamingEnabled then
		log.try("RequestStreamAroundAsync", function()
			player:RequestStreamAroundAsync(landing, PortalConfig.StreamTimeoutSeconds)
		end)
	end
	if deps.Match.isInMatch(player) then
		return false, "queue.inMatch"
	end
	if not Roster.hasRoom(player) then
		return false, "battleground.full"
	end
	-- The Erasure's event may have pulled them in while the world streamed: they are its, not ours.
	if deps.WorldBoss.isEngaged(player) or player.Character ~= character or Context.liveRoot(player) == nil then
		return false, nil
	end
	Roster.place(player, character, landing)
	local previous = Roster.get(player)
	local member =
		Roster.admit(player, character, landing, os.clock(), if previous ~= nil then previous.Defeated else 0)
	Roster.pushSnapshot(member)
	deps.Notify.send(player, "battleground.entered", nil, "Info")
	return true
end

-- Lets `player` go now (a gate took them elsewhere). Nothing for a player who is not a member.
function BattlegroundService.leave(player: Player)
	Roster.drop(player)
end

-- A member standing on the page by the position the server trusts, or a duellist on their pit's floor.
-- GlyphService refuses free casting here: the Forgers and the spars pay out.
function BattlegroundService.isInside(player: Player): boolean
	local map = handle
	if map == nil then
		return false
	end
	if Pits.holds(player) then
		return true
	end
	if Roster.get(player) == nil then
		return false
	end
	local trusted = deps.Combat.trustedPosition(player)
	return trusted ~= nil and Context.insideBounds(map.Layout, trusted)
end

----------------------------------------------------------------
-- The practice duel's pits (SparService)
----------------------------------------------------------------

-- Lends `player` a pit for a practice duel. False when the Forgers are not built yet or every pit is taken.
function BattlegroundService.openPit(player: Player): boolean
	if handle == nil or not Bots.ready() then
		return false
	end
	return Pits.acquire(player) ~= nil
end

-- Sets up a round in `player`'s pit: a fresh Forger, and their `character` on their pad (Pits.seat). False with no
-- pit, or when the Forger could not be put down.
function BattlegroundService.seatPit(player: Player, character: Model): boolean
	local pit = Pits.of(player)
	return pit ~= nil and Pits.seat(pit, player, character, os.clock())
end

-- Starts or stops the round in `player`'s pit.
function BattlegroundService.setPitLive(player: Player, live: boolean)
	local pit = Pits.of(player)
	if pit ~= nil then
		Pits.setLive(pit, live)
	end
end

-- The Forger of `player`'s pit: standing or not, its health and its most, and its body (nil once gone).
function BattlegroundService.pitForger(player: Player): (boolean, number, number, Model?)
	local pit = Pits.of(player)
	if pit == nil then
		return false, 0, 0, nil
	end
	local alive, health, maxHealth = Pits.forger(pit)
	return alive, health, maxHealth, if pit.Bot ~= nil then pit.Bot.Model else nil
end

-- Gives `player`'s pit back. Nothing for a player who holds none.
function BattlegroundService.closePit(player: Player)
	local pit = Pits.of(player)
	if pit ~= nil then
		Pits.release(pit)
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function BattlegroundService.Init(injected: Deps)
	deps = injected
end

function BattlegroundService.Start()
	-- The service's connections, for the life of the server.
	local trove = Trove.new()
	local map = Map.build(trove)
	Bots.Init(map)
	Motion.Init(map)
	Roster.Init(deps, map, Bots.standing)
	Attacks.Init(deps, map)
	Perception.Init(deps, map)
	Rewards.Init(deps, map)
	Pits.Init(deps)
	Pits.build()
	handle = map

	trove:Connect(map.KillZone.Touched, onKillZoneTouched)
	trove:Add(deps.Combat.Damaged:Connect(onDamaged))
	trove:Add(deps.Combat.Killed:Connect(onKilled))
	trove:Add(deps.Combat.Shoved:Connect(onShoved))
	trove:Add(deps.Combat.Controlled:Connect(onControlled))
	trove:Connect(Players.PlayerAdded, Roster.track)
	trove:Connect(Players.PlayerRemoving, onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		Roster.track(player)
	end
	-- The engine builds each rig, which yields. Until every tier is built the page takes nobody.
	task.spawn(function()
		log.succeeded("building the Forgers (the Battleground stays closed without them)", Bots.buildTemplates)
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info(
		"page built at x %d: %d studs, %d waypoints, up to %d members and %d Forgers",
		map.Origin.X,
		BattlegroundConfig.Map.Size,
		#map.Layout.Nodes,
		BattlegroundConfig.MaxMembers,
		BotConfig.MaxBots
	)
end

return BattlegroundService
