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
-- The dashboards hear of every wait's end (AnalyticsConfig.Events): MatchFormed for each player of a match that
-- formed, QueueTimedOut for each player a queue let go, both with the seconds they waited; and of every glyph a
-- player takes into a queue (GlyphPick), the pick rate of the balance telemetry.
--
-- Nothing pauses the queues: a match formed while the Erasure's event runs keeps its participant PvP, because
-- every place owns its own damage rule now (CombatService.claimZone, E16-S1), and a participant the event had
-- engaged is let go the moment the match takes them (WorldBossService's Audience).
--
-- A newcomer (RankingService.isNewcomer, MatchConfig.Newcomer) queues flagged as one: MatchmakingCore holds them to
-- the newcomer's window for their first seconds, and MatchService plays their match unranked (E10-S7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local MatchmakingCore = require(script.Parent.Parent.Pure.MatchmakingCore)
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
type RankingApi = {
	getRating: (player: Player, modeId: string) -> number,
	isNewcomer: (player: Player) -> boolean,
}
type MatchApi = {
	isInMatch: (player: Player) -> boolean,
	isFinishing: (player: Player) -> boolean,
	releaseFromResult: (player: Player) -> boolean,
	start: (modeId: string, teams: { { number } }) -> string?,
}
type DataApi = { get: (player: Player) -> Types.ProfileData? }
-- What a player fields where play pays out: their earned glyphs, cut to the slots they own (D-208).
type LoadoutApi = { fielded: (data: Types.ProfileData) -> ({ string }, { string }) }
type AnalyticsApi = {
	fields: (first: string | number, second: (string | number)?, third: (string | number)?) -> { [string]: string },
	custom: (player: Player, eventName: string, value: number?, fields: { [string]: string }?) -> (),
}
type Deps = {
	Registry: Registry,
	Notify: NotifyApi,
	Ranking: RankingApi,
	Match: MatchApi,
	DataService: DataApi,
	Loadout: LoadoutApi,
	Analytics: AnalyticsApi,
}

-- MatchmakingCore.Config: the widening window, the maximum wait, and a newcomer's cap and how long it holds.
local WINDOW: MatchmakingCore.Config = {
	BaseWindow = MatchConfig.Matchmaking.BaseWindow,
	WindowGrowthPerSecond = MatchConfig.Matchmaking.WindowGrowthPerSecond,
	MaxWindow = MatchConfig.Matchmaking.MaxWindow,
	MaxQueueSeconds = MatchConfig.Matchmaking.MaxQueueSeconds,
	NewcomerMaxWindow = MatchConfig.Newcomer.MaxWindow,
	NewcomerSeconds = MatchConfig.Newcomer.WindowSeconds,
}
local TICK_SECONDS = MatchConfig.Matchmaking.TickSeconds

local MatchmakingService = {}

local registry: Registry
local notify: NotifyApi
local ranking: RankingApi
local match: MatchApi
local dataService: DataApi
local loadout: LoadoutApi
local analytics: AnalyticsApi

local queues: { [string]: MatchmakingCore.Queue } = {}
-- userId -> mode asked for from the result screen, honoured by the first scan after the match lets the
-- player go: the one-click loop (docs/JUICE_PLAN.md phase 8, item 2). Shown to the client as queued.
local pending: { [number]: string } = {}
-- userId -> the mode and the loadout last counted into a queue (GlyphPick), until that wait ends in a match or runs
-- out: a player who leaves and joins again, a button pressed over and over, takes the same glyphs in once.
local picksTold: { [number]: string } = {}
local accumulator = 0

local function neededFor(def: MatchConfig.ModeDef): number
	return def.TeamSize * def.Teams
end

-- When each entry of `queue` joined it, by user id: read before a scan takes entries out.
local function joinTimes(queue: MatchmakingCore.Queue): { [number]: number }
	local joinedAt: { [number]: number } = {}
	for _, entry in ipairs(queue.Entries) do
		joinedAt[entry.UserId] = entry.JoinedAt
	end
	return joinedAt
end

-- Whole seconds since `joinedAt`, for the dashboards.
local function waited(joinedAt: number?, now: number): number
	return math.floor(now - (joinedAt or now) + 0.5)
end

-- Each glyph `player` takes into the `modeId` queue, for the dashboards: the loadout they will play the match with.
-- Once per wait (picksTold): the same loadout into the same queue again before a match or a time-out counts nothing.
local function tellPicks(player: Player, modeId: string)
	local data = dataService.get(player)
	if data == nil then
		return
	end
	local _, slots = loadout.fielded(data)
	local picks = modeId .. ":" .. table.concat(slots, ",")
	if picksTold[player.UserId] == picks then
		return
	end
	picksTold[player.UserId] = picks
	for _, glyphId in ipairs(slots) do
		analytics.custom(player, "GlyphPick", 1, analytics.fields(glyphId, modeId))
	end
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

-- Whether `player` still plays the quick duel, as RankingService says: a newcomer while it cannot tell.
local function isNewcomer(player: Player): boolean
	local ok, newcomer = pcall(ranking.isNewcomer, player)
	if ok and type(newcomer) == "boolean" then
		return newcomer
	end
	log.warn("isNewcomer failed for %s: %s", player.Name, tostring(newcomer))
	return true
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
	local entry = { UserId = player.UserId, Rating = rating, JoinedAt = now, Newcomer = isNewcomer(player) }
	if not MatchmakingCore.enqueue(queue, entry) then
		notify.send(player, "queue.alreadyQueued", nil, "Error")
		push(player, now)
		return
	end
	notify.send(player, "queue.joined", { mode = def.NameKey }, "Success")
	push(player, now)
	tellPicks(player, modeId)
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
					Newcomer = isNewcomer(player),
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

-- Pairs whatever the queue holds now and hands each formed match to MatchService.
local function formMatches(modeId: string, def: MatchConfig.ModeDef, queue: MatchmakingCore.Queue, now: number)
	-- Captured before findMatches removes the entries, for the requeue of a refused match.
	local joinedAt = joinTimes(queue)
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
			for _, members in ipairs(formed.Teams) do
				for _, userId in ipairs(members) do
					picksTold[userId] = nil
					local player = Players:GetPlayerByUserId(userId)
					if player ~= nil then
						analytics.custom(player, "MatchFormed", waited(joinedAt[userId], now), analytics.fields(modeId))
					end
				end
			end
			log.info("%s match formed (average rating %d)", modeId, math.floor(formed.AverageRating + 0.5))
		end
	end
end

local function tick(now: number)
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
		local joinedAt = joinTimes(queue)
		for _, userId in ipairs(MatchmakingCore.expire(queue, now, WINDOW)) do
			picksTold[userId] = nil
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				-- News, not a failure: nobody else was queuing. The toast says it in the neutral medallion (the red
				-- "!" is for a refused purchase or claim, D-147), and the Play screen turns the card into a state.
				notify.send(player, "queue.timedOut", nil, "Info")
				analytics.custom(player, "QueueTimedOut", waited(joinedAt[userId], now), analytics.fields(modeId))
				push(player, now)
			end
		end
		formMatches(modeId, def, queue, now)
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
	pending[player.UserId] = nil
	picksTold[player.UserId] = nil
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
	dataService = deps.DataService
	loadout = deps.Loadout
	analytics = deps.Analytics
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
