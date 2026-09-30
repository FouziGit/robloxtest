--!strict
-- MatchmakingService: one Pure/MatchmakingCore queue per MatchConfig.ModeOrder entry.
--
-- Handles JoinQueue / LeaveQueue, then scans every queue on a single Heartbeat accumulator each
-- MatchConfig.Matchmaking.TickSeconds: long waits are dequeued and told so, the remaining entries are
-- paired inside a rating window that widens while they wait (MatchmakingCore), and each formed match
-- goes to MatchService. A match MatchService refuses (no free arena, a player gone) puts its players
-- back in the queue with the wait they had, instead of dropping them.
--
-- The client only ever asks to join or leave: ratings come from RankingService and the roster is
-- decided here, never sent up.
--
-- A player may fight a practice duel while they wait (SparService, E10-S6). They keep their place: their entry
-- never expires while they spar, and no pairing takes them while a round of it is played (setSparring). At a
-- break of the spar they are paired like anybody else, and Handover tells SparService so before the match
-- starts, so the spar ends the moment a match is found.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local MatchmakingCore = require(Shared.Pure.MatchmakingCore)
local RankingConfig = require(Shared.Config.RankingConfig)
local Signal = require(Packages.Signal)
local Types = require(Shared.Types)

local log = Log.new("MatchmakingService")

type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	fire: (name: string, player: Player, ...any) -> (),
}
type RankingApi = { getRating: (player: Player, modeId: string) -> number }
type MatchApi = {
	isInMatch: (player: Player) -> boolean,
	isFinishing: (player: Player) -> boolean,
	releaseFromResult: (player: Player) -> boolean,
	start: (modeId: string, teams: { { number } }) -> string?,
}
type WorldBossApi = { isLive: () -> boolean }
type Deps = {
	Registry: Registry,
	Notify: NotifyApi,
	Ranking: RankingApi,
	Match: MatchApi,
	WorldBoss: WorldBossApi,
}

-- MatchmakingCore.Config: the widening window and the maximum wait.
local WINDOW = MatchConfig.Matchmaking
local TICK_SECONDS = MatchConfig.Matchmaking.TickSeconds

local MatchmakingService = {}

-- (player: Player): a sparring player a formed match takes, fired before the match starts.
MatchmakingService.Handover = Signal.new()

local registry: Registry
local notify: NotifyApi
local ranking: RankingApi
local match: MatchApi
local worldBoss: WorldBossApi

local queues: { [string]: MatchmakingCore.Queue } = {}
-- userId -> mode asked for from the result screen, honoured by the first scan after the match lets the
-- player go: the one-click loop (docs/JUICE_PLAN.md phase 8, item 2). Shown to the client as queued.
local pending: { [number]: string } = {}
-- userId -> the spar they fight (setSparring): true while one of its rounds is played, false at its breaks.
local sparring: { [number]: boolean? } = {}
local accumulator = 0
-- Scan time of the previous tick, so a scan suspended by a World Boss event knows how long the queues
-- stood still and can hand that time back to everybody waiting.
local lastTickAt: number? = nil

local function neededFor(def: MatchConfig.ModeDef): number
	return def.TeamSize * def.Teams
end

-- The queue holding `userId`, if any.
local function queueOf(userId: number): (string?, MatchmakingCore.Queue?, MatchmakingCore.Entry?)
	for _, modeId in ipairs(MatchConfig.ModeOrder) do
		local queue = queues[modeId]
		if queue ~= nil then
			local entry = queue.ById[userId]
			if entry ~= nil then
				return modeId, queue, entry
			end
		end
	end
	return nil, nil, nil
end

local function ratingOf(player: Player, modeId: string): number
	local ok, rating = pcall(ranking.getRating, player, modeId)
	if ok and type(rating) == "number" then
		return rating
	end
	log.warn("getRating failed for %s (%s): %s", player.Name, modeId, tostring(rating))
	return RankingConfig.InitialRating
end

local function snapshotFor(userId: number, now: number): Types.QueueSnapshot
	local modeId, queue, entry = queueOf(userId)
	if modeId == nil or queue == nil or entry == nil then
		local wanted = pending[userId]
		if wanted ~= nil and queues[wanted] ~= nil then
			return {
				Queued = true,
				ModeId = (wanted :: any) :: Types.MatchModeId,
				WaitedSeconds = 0,
				QueuedCount = MatchmakingCore.size(queues[wanted]),
				NeededCount = neededFor(MatchConfig.Modes[wanted]),
			}
		end
		return { Queued = false, ModeId = nil, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 0 }
	end
	return {
		Queued = true,
		ModeId = (modeId :: any) :: Types.MatchModeId,
		WaitedSeconds = math.max(0, math.floor(now - entry.JoinedAt)),
		QueuedCount = MatchmakingCore.size(queue),
		NeededCount = neededFor(MatchConfig.Modes[modeId]),
	}
end

-- Pushes the queue state of `player`: on every change, on every tick while queued, and after a
-- rejection so the client never stays stuck on "joining".
local function push(player: Player, now: number)
	if player.Parent ~= Players then
		return
	end
	registry.fire("QueueChanged", player, snapshotFor(player.UserId, now))
end

local function pushUserId(userId: number, now: number)
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		push(player, now)
	end
end

local function onJoinQueue(player: Player, modeId: string)
	local now = os.clock()
	local def = MatchConfig.Modes[modeId]
	local queue = queues[modeId]
	if def == nil or queue == nil then
		log.warn("JoinQueue from %s with unknown mode %s", player.Name, tostring(modeId))
		push(player, now)
		return
	end
	if match.isInMatch(player) then
		-- The result screen's "play again". The match lets this player go at once -- it stays alive for
		-- everybody else -- and they join the queue here and now: waiting out the eight seconds of the
		-- result phase is what put the plan's ten-second loop out of reach.
		if match.isFinishing(player) and match.releaseFromResult(player) then
			pending[player.UserId] = nil
		elseif match.isFinishing(player) then
			-- It would not let go (a phase that moved under us): keep the wish for the next scan.
			pending[player.UserId] = modeId
			notify.send(player, "queue.joined", { mode = def.NameKey }, "Success")
			push(player, now)
			return
		else
			notify.send(player, "queue.inMatch", nil, "Error")
			push(player, now)
			return
		end
	end
	pending[player.UserId] = nil
	if queueOf(player.UserId) ~= nil then
		notify.send(player, "queue.alreadyQueued", nil, "Error")
		push(player, now)
		return
	end
	local rating = ratingOf(player, modeId)
	if not MatchmakingCore.enqueue(queue, { UserId = player.UserId, Rating = rating, JoinedAt = now }) then
		notify.send(player, "queue.alreadyQueued", nil, "Error")
		push(player, now)
		return
	end
	notify.send(player, "queue.joined", { mode = def.NameKey }, "Success")
	push(player, now)
	log.info("%s queued for %s (rating %d, %d waiting)", player.Name, modeId, rating, MatchmakingCore.size(queue))
end

local function onLeaveQueue(player: Player)
	local now = os.clock()
	if pending[player.UserId] ~= nil then
		pending[player.UserId] = nil
		notify.send(player, "queue.left", nil, "Info")
		push(player, now)
		return
	end
	local modeId, queue = queueOf(player.UserId)
	if queue ~= nil and MatchmakingCore.dequeue(queue, player.UserId) then
		notify.send(player, "queue.left", nil, "Info")
		log.info("%s left the %s queue", player.Name, tostring(modeId))
	end
	push(player, now)
end

-- A refused match: everybody still here and still free goes back in with their original wait, so the
-- window they had earned is not lost.
local function requeue(modeId: string, teams: { { number } }, joinedAt: { [number]: number }, now: number)
	local queue = queues[modeId]
	if queue == nil then
		return
	end
	local restored = 0
	for _, members in ipairs(teams) do
		for _, userId in ipairs(members) do
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil and not match.isInMatch(player) then
				local entry = {
					UserId = userId,
					Rating = ratingOf(player, modeId),
					JoinedAt = joinedAt[userId] or now,
				}
				if MatchmakingCore.enqueue(queue, entry) then
					restored += 1
				end
				push(player, now)
			end
		end
	end
	log.warn("match %s was refused: %d player(s) requeued", modeId, restored)
end

-- Runs `fn` over `queue` with the entries `aside` names taken out of it, then puts them back with the wait they
-- had: whatever `fn` asks MatchmakingCore about the queue, it never sees them.
local function without(queue: MatchmakingCore.Queue, aside: (userId: number) -> boolean, fn: () -> ())
	local kept: { MatchmakingCore.Entry } = {}
	for _, entry in ipairs(table.clone(queue.Entries)) do
		if aside(entry.UserId) then
			MatchmakingCore.dequeue(queue, entry.UserId)
			table.insert(kept, entry)
		end
	end
	fn()
	for _, entry in ipairs(kept) do
		MatchmakingCore.enqueue(queue, entry)
	end
end

local function isSparring(userId: number): boolean
	return sparring[userId] ~= nil
end

local function inSparRound(userId: number): boolean
	return sparring[userId] == true
end

-- Pairs whatever the queue holds now and hands each formed match to MatchService.
local function formMatches(modeId: string, def: MatchConfig.ModeDef, queue: MatchmakingCore.Queue, now: number)
	-- Captured before findMatches removes the entries, for the requeue of a refused match.
	local joinedAt: { [number]: number } = {}
	for _, entry in ipairs(queue.Entries) do
		joinedAt[entry.UserId] = entry.JoinedAt
	end
	for _, formed in ipairs(MatchmakingCore.findMatches(queue, def.TeamSize, def.Teams, now, WINDOW)) do
		-- They are out of the queue now: their client leaves the searching state either way. A spar at its break
		-- ends before the match starts.
		for _, members in ipairs(formed.Teams) do
			for _, userId in ipairs(members) do
				pushUserId(userId, now)
				local player = Players:GetPlayerByUserId(userId)
				if player ~= nil and isSparring(userId) then
					MatchmakingService.Handover:Fire(player)
				end
			end
		end
		if match.start(modeId, formed.Teams) == nil then
			requeue(modeId, formed.Teams, joinedAt, now)
		else
			log.info("%s match formed (average rating %d)", modeId, math.floor(formed.AverageRating + 0.5))
		end
	end
end

local function tick(now: number)
	-- A World Boss event owns the single CombatService PvP policy for its whole duration, so a match
	-- started now would lose participant PvP. Match formation is suspended for the event and the wait it
	-- costs is handed back: every JoinedAt slides forward by the paused interval, so a queue only ages
	-- while the server is really trying to pair it. Otherwise an event (375s) outlasts MaxQueueSeconds
	-- (240s) and every entry would be dropped mid-event for a wait nobody was serving. Clients still get
	-- QueueChanged while paused, and the first scan after the event pairs the queue again.
	local paused = worldBoss.isLive()
	local pausedSeconds = 0
	if paused and lastTickAt ~= nil then
		pausedSeconds = math.max(0, now - lastTickAt)
	end
	lastTickAt = now
	-- The wishes kept from result screens: every player the match has let go joins now, with a fresh
	-- wait, the same way a JoinQueue would have.
	for userId, modeId in pairs(pending) do
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			pending[userId] = nil
		elseif not match.isInMatch(player) then
			pending[userId] = nil
			onJoinQueue(player, modeId)
		end
	end
	for _, modeId in ipairs(MatchConfig.ModeOrder) do
		local def = MatchConfig.Modes[modeId]
		local queue = queues[modeId]
		if def == nil or queue == nil then
			continue
		end
		if pausedSeconds > 0 then
			for _, entry in ipairs(queue.Entries) do
				-- Clamped to now: an entry that joined inside the paused interval has waited nothing yet.
				entry.JoinedAt = math.min(now, entry.JoinedAt + pausedSeconds)
			end
		end
		-- A wait already too long before the event still ends here: the pause excuses only its own seconds. A
		-- sparring player's does not: the spar is what they wait with.
		without(queue, isSparring, function()
			for _, userId in ipairs(MatchmakingCore.expire(queue, now, WINDOW)) do
				local player = Players:GetPlayerByUserId(userId)
				if player ~= nil then
					-- News, not a failure: nobody else was queuing. The toast says it in the neutral medallion (the
					-- red "!" is for a refused purchase or claim, D-147), and the Play screen turns the card into a
					-- state.
					notify.send(player, "queue.timedOut", nil, "Info")
					push(player, now)
				end
			end
		end)
		if not paused then
			-- A round of a spar is never interrupted: its player is paired at its next break.
			without(queue, inSparRound, function()
				formMatches(modeId, def, queue, now)
			end)
		end
		-- Everybody still waiting sees their timer: advancing normally, standing still while paused.
		for _, entry in ipairs(queue.Entries) do
			pushUserId(entry.UserId, now)
		end
	end
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	tick(os.clock())
end

local function onPlayerRemoving(player: Player)
	pending[player.UserId] = nil
	sparring[player.UserId] = nil
	for _, modeId in ipairs(MatchConfig.ModeOrder) do
		local queue = queues[modeId]
		if queue ~= nil then
			MatchmakingCore.dequeue(queue, player.UserId)
		end
	end
end

-- The queue `player` waits in, how long they have waited and how many wait in it with them; nil, 0 and 0 when
-- they wait in none.
function MatchmakingService.waiting(player: Player): (string?, number, number)
	local modeId, queue, entry = queueOf(player.UserId)
	if modeId == nil or queue == nil or entry == nil then
		return nil, 0, 0
	end
	return modeId, math.max(0, os.clock() - entry.JoinedAt), MatchmakingCore.size(queue)
end

-- SparService: `player` fights a spar -- `inRound` while one of its rounds is played, which no pairing may
-- interrupt -- or, with nil, no longer does.
function MatchmakingService.setSparring(player: Player, inRound: boolean?)
	sparring[player.UserId] = inRound
end

function MatchmakingService.Init(deps: Deps)
	registry = deps.Registry
	notify = deps.Notify
	ranking = deps.Ranking
	match = deps.Match
	worldBoss = deps.WorldBoss
	for _, modeId in ipairs(MatchConfig.ModeOrder) do
		queues[modeId] = MatchmakingCore.newQueue(modeId)
	end
end

function MatchmakingService.Start()
	registry.on("JoinQueue", onJoinQueue)
	registry.on("LeaveQueue", onLeaveQueue)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (%d queues, scan every %.1fs)", #MatchConfig.ModeOrder, TICK_SECONDS)
end

return MatchmakingService
