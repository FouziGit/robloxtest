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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local MatchmakingCore = require(Shared.Pure.MatchmakingCore)
local RankingConfig = require(Shared.Config.RankingConfig)
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
	start: (modeId: string, teams: { { number } }) -> string?,
}
type Deps = { Registry: Registry, Notify: NotifyApi, Ranking: RankingApi, Match: MatchApi }

-- MatchmakingCore.Config: the widening window and the maximum wait.
local WINDOW = MatchConfig.Matchmaking
local TICK_SECONDS = MatchConfig.Matchmaking.TickSeconds

local MatchmakingService = {}

local registry: Registry
local notify: NotifyApi
local ranking: RankingApi
local match: MatchApi

local queues: { [string]: MatchmakingCore.Queue } = {}
local accumulator = 0

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
		notify.send(player, "queue.inMatch", nil, "Error")
		push(player, now)
		return
	end
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

local function tick(now: number)
	for _, modeId in ipairs(MatchConfig.ModeOrder) do
		local def = MatchConfig.Modes[modeId]
		local queue = queues[modeId]
		if def == nil or queue == nil then
			continue
		end
		for _, userId in ipairs(MatchmakingCore.expire(queue, now, WINDOW)) do
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				notify.send(player, "queue.timedOut", nil, "Error")
				push(player, now)
			end
		end
		-- Captured before findMatches removes the entries, for the requeue of a refused match.
		local joinedAt: { [number]: number } = {}
		for _, entry in ipairs(queue.Entries) do
			joinedAt[entry.UserId] = entry.JoinedAt
		end
		for _, formed in ipairs(MatchmakingCore.findMatches(queue, def.TeamSize, def.Teams, now, WINDOW)) do
			-- They are out of the queue now: their client leaves the searching state either way.
			for _, members in ipairs(formed.Teams) do
				for _, userId in ipairs(members) do
					pushUserId(userId, now)
				end
			end
			if match.start(modeId, formed.Teams) == nil then
				requeue(modeId, formed.Teams, joinedAt, now)
			else
				log.info("%s match formed (average rating %d)", modeId, math.floor(formed.AverageRating + 0.5))
			end
		end
		-- Everybody still waiting sees their timer advance.
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
	for _, modeId in ipairs(MatchConfig.ModeOrder) do
		local queue = queues[modeId]
		if queue ~= nil then
			MatchmakingCore.dequeue(queue, player.UserId)
		end
	end
end

function MatchmakingService.Init(deps: Deps)
	registry = deps.Registry
	notify = deps.Notify
	ranking = deps.Ranking
	match = deps.Match
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
