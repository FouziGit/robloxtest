--!strict
-- LeaderboardService: the seasonal ranked ladders. One OrderedDataStore per season and board, named
-- "<SeasonId>_<BoardId>" (RankingConfig.Leaderboard.Boards: one per ranked mode plus a cumulative
-- board scoring every rating above RankingConfig.InitialRating).
-- Writes are driven by RankingService.RatingChanged and coalesced: only the latest value of a key is
-- kept and a key is written at most once every RankingConfig.Leaderboard.MinWriteIntervalSeconds, with
-- a forced flush when the player leaves so a session never ends on a stale ladder — that flush waits
-- out the key's OrderedDataStore cooldown rather than writing through it, and a game:BindToClose waits
-- for the passes still in flight so a shutdown a second later does not take a rating with it. Every
-- board is re-read every RankingConfig.Leaderboard.RefreshSeconds with GetSortedAsync, names resolved
-- through a cache, and the rows are rendered onto the hub's LeaderboardBoard_<boardId> SurfaceGuis. Every
-- DataStore call goes through a retry with backoff and stays silent on failure, so a server without
-- DataStore access (Studio) keeps a working hub, RequestLeaderboard handler and match flow.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local GameConfig = require(Shared.Config.GameConfig)
local ListRow = require(UI.components.ListRow)
local Log = require(Shared.Util.Log)
local RankingConfig = require(Shared.Config.RankingConfig)
local Strings = require(Shared.Strings)
local Theme = require(UI.Theme)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("LeaderboardService")

type LeaderboardSnapshot = Types.LeaderboardSnapshot
type LeaderboardEntry = Types.LeaderboardEntry
type RatingSignal = {
	Connect: (
		self: RatingSignal,
		fn: (player: Player, modeId: string, before: number, after: number) -> ()
	) -> any,
}
type RankingApi = {
	getRating: (player: Player, modeId: string) -> number,
	rankKeyFor: (rating: number) -> string,
	RatingChanged: RatingSignal,
}
type Registry = { setCallback: (name: string, callback: (player: Player, ...any) -> ...any) -> () }
type Deps = { Registry: Registry, Ranking: RankingApi }

-- One coalesced ladder write. `NotBefore` is the os.clock() at which the key leaves its per-key
-- OrderedDataStore cooldown; writing earlier is rejected, so the write waits for it instead.
type Write = { BoardId: string, UserId: number, Value: number, NotBefore: number }

local STORE_SEPARATOR = "_"
local BOARD_PART_PREFIX = "LeaderboardBoard_"
-- Row container inside a board's SurfaceGui. HubService may create it to place the rows under its own
-- header; when it is missing this service creates one filling the whole surface.
local ROWS_FRAME_NAME = "LeaderboardRows"
-- Granularity of the write-queue scan. The real cadence per key stays MinWriteIntervalSeconds.
local WRITE_SCAN_SECONDS = 1
local RETRY_ATTEMPTS = 3
local RETRY_BACKOFF_SECONDS = 2 -- doubles after each failed attempt
-- Roblox rejects a second SetAsync on the same OrderedDataStore key inside this window, counted from the
-- last write that actually landed. The periodic scan is far slower than that (tests/Config.spec.luau pins
-- the relation), but the forced flush on leave is not, so it waits the remainder out: writing through the
-- cooldown spends every retry on a rejection and can still end up losing the value.
-- Budget the shutdown handler gives the write passes still in flight. Roblox kills the server 30s after
-- it starts closing, and a single key can legitimately need ~12s (cooldown wait plus the whole backoff
-- chain), so this covers one full retry chain and still leaves half the budget to the profile saves
-- running in their own BindToClose: a stuck ladder write can never be what times the shutdown out.
local CLOSE_WAIT_SECONDS = 15

local LeaderboardService = {}

local registry: Registry
local ranking: RankingApi

local trove = Trove.new()
local stores: { [string]: OrderedDataStore? } = {}
local snapshots: { [string]: LeaderboardSnapshot } = {}
-- boardId -> userId -> value waiting to be written (latest value wins).
local pending: { [string]: { [number]: number } } = {}
-- boardId -> userId -> os.clock() of the last write that landed. A failed write leaves no stamp: it earned
-- no OrderedDataStore cooldown, and stamping it would make the retry wait one out for nothing.
local lastWrite: { [string]: { [number]: number } } = {}
local names: { [number]: string } = {}
local parts: { [string]: BasePart? } = {}
local rowTroves: { [string]: typeof(Trove.new()) } = {}

local writeAccumulator = 0
local refreshAccumulator = 0
local flushing = false
local refreshing = false
-- Write passes still running. Every value one carries is already out of `pending`, so a pass that dies
-- with the server is a lost rating: the shutdown handler waits on this count.
local outstandingWrites = 0
-- os.clock() until which DataStore calls are skipped: set when a call exhausts its retries, so a
-- server without DataStore access reports the problem once per cooldown instead of on every call.
local offlineUntil = 0

----------------------------------------------------------------
-- DataStore access
----------------------------------------------------------------

-- Runs `fn` until it succeeds, backing off between attempts. Returns (false, nil) once exhausted, and
-- then holds every call off for one refresh cycle: callers stay functional without the store and a
-- server that has no DataStore access at all reports it once per cycle. Yields between attempts.
local function attempt(context: string, fn: () -> ...any): (boolean, any)
	if os.clock() < offlineUntil then
		return false, nil
	end
	local backoff = RETRY_BACKOFF_SECONDS
	for round = 1, RETRY_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if round == RETRY_ATTEMPTS then
			offlineUntil = os.clock() + RankingConfig.Leaderboard.RefreshSeconds
			log.warn("%s failed after %d attempts: %s", context, RETRY_ATTEMPTS, tostring(result))
		else
			task.wait(backoff)
			backoff *= 2
		end
	end
	return false, nil
end

local function storeFor(seasonId: string, boardId: string): OrderedDataStore?
	local name = seasonId .. STORE_SEPARATOR .. boardId
	local existing = stores[name]
	if existing ~= nil then
		return existing
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok or store == nil then
		log.warn("could not open ladder %s: %s", name, tostring(store))
		return nil
	end
	stores[name] = store
	return store
end

----------------------------------------------------------------
-- Board values
----------------------------------------------------------------

local function isModeBoard(boardId: string): boolean
	return table.find(RankingConfig.Modes, boardId) ~= nil
end

-- Cumulative score of a player: every ranked rating above the initial one, summed.
local function cumulativeScore(player: Player): number
	local total = 0
	for _, modeId in ipairs(RankingConfig.Modes) do
		total += math.max(0, ranking.getRating(player, modeId) - RankingConfig.InitialRating)
	end
	return total
end

-- A mode board stores that mode's rating, so its tier is read directly. A cumulative board stores
-- gains above the initial rating, so its tier is the one a player that far above the start would hold.
local function boardRankKey(boardId: string, value: number): string
	if isModeBoard(boardId) then
		return ranking.rankKeyFor(value)
	end
	return ranking.rankKeyFor(RankingConfig.InitialRating + value)
end

-- OrderedDataStore values are non-negative integers.
local function enqueue(boardId: string, userId: number, value: number)
	local queue = pending[boardId]
	if queue == nil then
		return
	end
	queue[userId] = math.max(0, math.floor(value))
end

local function onRatingChanged(player: Player, modeId: string, _before: number, after: number)
	names[player.UserId] = player.Name
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		if boardId == modeId then
			enqueue(boardId, player.UserId, after)
		elseif not isModeBoard(boardId) then
			enqueue(boardId, player.UserId, cumulativeScore(player))
		end
	end
end

----------------------------------------------------------------
-- Write queue
----------------------------------------------------------------

-- Takes every write that is due out of the queue. With `onlyUserId` it takes that player's writes
-- whatever the interval (used when they leave), each stamped with the time its key becomes writable.
-- Never yields, so the queue is never mutated mid-scan.
local function takeDue(onlyUserId: number?): { Write }
	local now = os.clock()
	local interval = RankingConfig.Leaderboard.MinWriteIntervalSeconds
	local due: { Write } = {}
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		local queue = pending[boardId]
		local stamps = lastWrite[boardId]
		for userId, value in pairs(queue) do
			local last = stamps[userId]
			local include: boolean
			if onlyUserId ~= nil then
				include = userId == onlyUserId
			else
				include = last == nil or now - last >= interval
			end
			if include then
				-- Only the forced path can reach a key still inside its cooldown: the periodic scan
				-- already waited a whole MinWriteIntervalSeconds, which is the longer of the two, and
				-- a stamp exists only where a write landed.
				local notBefore = if last == nil
					then now
					else math.max(now, last + RankingConfig.Leaderboard.KeyCooldownSeconds)
				queue[userId] = nil
				table.insert(due, { BoardId = boardId, UserId = userId, Value = value, NotBefore = notBefore })
			end
		end
	end
	return due
end

-- Writes taken values one by one, each once its key is out of cooldown. A write that lands stamps its key
-- and starts that cooldown; one that fails goes back to the queue unless a newer value arrived meanwhile,
-- so nothing is lost, nothing overwrites a fresher rating, and the retry is not held off. Yields.
local function writeDue(due: { Write })
	for _, item in ipairs(due) do
		local cooldown = item.NotBefore - os.clock()
		if cooldown > 0 then
			task.wait(cooldown)
		end
		local store = storeFor(GameConfig.SeasonId, item.BoardId)
		local ok = false
		if store ~= nil then
			local target: OrderedDataStore = store
			ok = attempt(item.BoardId .. " write", function()
				target:SetAsync(tostring(item.UserId), item.Value)
			end)
		end
		if ok then
			lastWrite[item.BoardId][item.UserId] = os.clock()
		else
			local queue = pending[item.BoardId]
			if queue[item.UserId] == nil then
				queue[item.UserId] = item.Value
			end
		end
	end
end

-- Runs one write pass on its own thread, counted so the shutdown handler waits for it, and reports back
-- through `finished` once the pass is over whether it threw or not.
local function spawnWrite(context: string, due: { Write }, finished: () -> ())
	outstandingWrites += 1
	task.spawn(function()
		log.try(context, writeDue, due)
		outstandingWrites -= 1
		finished()
	end)
end

-- Drops the per-key write stamps of a user id once nothing is queued for them. Without it the stamp maps
-- grow by one entry per distinct player per board and never shrink, so a server running for hours ends up
-- holding them for everyone who ever passed through.
local function forgetStamps(userId: number)
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		local queue = pending[boardId]
		if queue == nil or queue[userId] == nil then
			local stamps = lastWrite[boardId]
			if stamps ~= nil then
				stamps[userId] = nil
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	local due = takeDue(userId)
	if #due == 0 then
		forgetStamps(userId)
		return
	end
	-- Stamps are forgotten after the pass, so a write that just landed loses its stamp while a value that
	-- went back to `pending` keeps the stamp of its last successful write.
	spawnWrite("flush on leave", due, function()
		forgetStamps(userId)
	end)
end

----------------------------------------------------------------
-- Refresh
----------------------------------------------------------------

-- Username for a leaderboard row. Online players and already resolved ids cost nothing; a failed
-- lookup falls back to the raw id and is not cached, so the next refresh retries it. Yields.
local function nameFor(userId: number): string
	local cached = names[userId]
	if cached ~= nil then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		names[userId] = player.Name
		return player.Name
	end
	local ok, resolved = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(resolved) == "string" then
		names[userId] = resolved
		return resolved
	end
	return tostring(userId)
end

local renderBoard: (boardId: string) -> ()

-- Re-reads every board from its ladder and renders it. Yields; runs on its own thread.
local function refreshBoards()
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		local store = storeFor(GameConfig.SeasonId, boardId)
		if store ~= nil then
			local target: OrderedDataStore = store
			local ok, pages = attempt(boardId .. " read", function()
				return target:GetSortedAsync(false, RankingConfig.Leaderboard.TopCount)
			end)
			if ok and pages ~= nil then
				local entries: { LeaderboardEntry } = {}
				for _, record in ipairs((pages :: DataStorePages):GetCurrentPage()) do
					local userId = tonumber(record.key)
					local value = tonumber(record.value)
					if userId ~= nil and value ~= nil then
						local rank = #entries + 1
						table.insert(entries, {
							Rank = rank,
							UserId = userId,
							Name = nameFor(userId),
							Rating = value,
							RankKey = boardRankKey(boardId, value),
						})
					end
				end
				snapshots[boardId] = { BoardId = boardId, UpdatedAt = os.time(), Entries = entries }
			end
		end
		renderBoard(boardId)
	end
end

----------------------------------------------------------------
-- Hub SurfaceGuis
----------------------------------------------------------------

-- The row container of a board's SurfaceGui, created when HubService did not provide one, always with
-- a vertical layout so the rows stack whoever built the frame.
local function ensureRowsFrame(gui: SurfaceGui): Frame
	local frame: Frame
	local existing = gui:FindFirstChild(ROWS_FRAME_NAME)
	if existing ~= nil and existing:IsA("Frame") then
		frame = existing
	else
		frame = Instance.new("Frame")
		frame.Name = ROWS_FRAME_NAME
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, Theme.Sizes.Padding)
		padding.PaddingBottom = UDim.new(0, Theme.Sizes.Padding)
		padding.PaddingLeft = UDim.new(0, Theme.Sizes.Padding)
		padding.PaddingRight = UDim.new(0, Theme.Sizes.Padding)
		padding.Parent = frame
		frame.Parent = gui
	end
	if frame:FindFirstChildWhichIsA("UIListLayout") == nil then
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
		layout.Parent = frame
	end
	return frame
end

-- Rebuilds the rows of one board. A board with no entry is left empty: the localized empty state
-- belongs to the client screen.
renderBoard = function(boardId: string)
	local part = parts[boardId]
	if part == nil or part.Parent == nil then
		return
	end
	local gui = part:FindFirstChildWhichIsA("SurfaceGui")
	if gui == nil then
		return
	end
	local frame = ensureRowsFrame(gui)
	local rows = rowTroves[boardId]
	if rows == nil then
		rows = trove:Extend()
		rowTroves[boardId] = rows
	end
	rows:Clean()

	local snapshot = snapshots[boardId]
	if snapshot == nil then
		return
	end
	for _, entry in ipairs(snapshot.Entries) do
		local row = ListRow.new({
			Left = Strings.t("leaderboard.row", { rank = entry.Rank, name = entry.Name }),
			Right = Strings.t("leaderboard.rating", { rating = entry.Rating }),
			LayoutOrder = entry.Rank,
			Parent = frame,
		})
		rows:Add(row, "Destroy")
	end
end

-- Hub boards are built in HubService.Start, which may run before or after this service: the initial
-- scan catches the ones already there and DescendantAdded the ones built later.
local function registerPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local matched = string.match(instance.Name, "^" .. BOARD_PART_PREFIX .. "(.+)$")
	if type(matched) ~= "string" or snapshots[matched] == nil then
		return
	end
	local boardId: string = matched
	if parts[boardId] == instance then
		return
	end
	parts[boardId] = instance
	-- The SurfaceGui may be parented after the part itself.
	trove:Add(instance.ChildAdded:Connect(function(child: Instance)
		if child:IsA("SurfaceGui") then
			renderBoard(boardId)
		end
	end))
	renderBoard(boardId)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Last refreshed state of a board. Never nil: an unknown or not yet refreshed board reads as empty.
function LeaderboardService.getBoard(boardId: string): LeaderboardSnapshot
	local snapshot = snapshots[boardId]
	if snapshot == nil then
		return { BoardId = boardId, UpdatedAt = 0, Entries = {} }
	end
	return snapshot
end

-- Value a player ended a past season with on one board, for RankingService's end-of-season pass.
-- Returns (false, nil) when the ladder could not be read, (true, nil) when the player has no entry.
-- Yields.
function LeaderboardService.getArchivedValue(seasonId: string, boardId: string, userId: number): (boolean, number?)
	local store = storeFor(seasonId, boardId)
	if store == nil then
		return false, nil
	end
	local target: OrderedDataStore = store
	local ok, value = attempt(boardId .. " archive read", function()
		return target:GetAsync(tostring(userId))
	end)
	if not ok then
		return false, nil
	end
	return true, tonumber(value)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

-- Write passes run on their own threads, so without this the server can close between taking a rating out
-- of `pending` and writing it, and that rating is gone for good. Waits for the passes in flight, never
-- past CLOSE_WAIT_SECONDS. Yields.
local function onClose()
	local deadline = os.clock() + CLOSE_WAIT_SECONDS
	while outstandingWrites > 0 and os.clock() < deadline do
		task.wait()
	end
	if outstandingWrites > 0 then
		log.warn("closed with %d ladder write(s) unfinished after %ds", outstandingWrites, CLOSE_WAIT_SECONDS)
	end
end

local function onHeartbeat(deltaTime: number)
	writeAccumulator += deltaTime
	refreshAccumulator += deltaTime
	if writeAccumulator >= WRITE_SCAN_SECONDS then
		writeAccumulator = 0
		if not flushing then
			flushing = true
			spawnWrite("flush", takeDue(nil), function()
				flushing = false
			end)
		end
	end
	if refreshAccumulator >= RankingConfig.Leaderboard.RefreshSeconds then
		refreshAccumulator = 0
		if not refreshing then
			refreshing = true
			task.spawn(function()
				log.try("refresh", refreshBoards)
				refreshing = false
			end)
		end
	end
end

function LeaderboardService.Init(deps: Deps)
	registry = deps.Registry
	ranking = deps.Ranking
	for _, boardId in ipairs(RankingConfig.Leaderboard.Boards) do
		snapshots[boardId] = { BoardId = boardId, UpdatedAt = 0, Entries = {} }
		pending[boardId] = {}
		lastWrite[boardId] = {}
	end
end

function LeaderboardService.Start()
	registry.setCallback("RequestLeaderboard", function(_player: Player, boardId: string): LeaderboardSnapshot
		return LeaderboardService.getBoard(boardId)
	end)
	ranking.RatingChanged:Connect(onRatingChanged)

	for _, player in ipairs(Players:GetPlayers()) do
		names[player.UserId] = player.Name
	end
	trove:Add(Players.PlayerAdded:Connect(function(player: Player)
		names[player.UserId] = player.Name
	end))
	trove:Add(Players.PlayerRemoving:Connect(onPlayerRemoving))

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		registerPart(descendant)
	end
	trove:Add(Workspace.DescendantAdded:Connect(registerPart))

	trove:Add(RunService.Heartbeat:Connect(onHeartbeat))
	game:BindToClose(onClose)
	task.spawn(function()
		log.try("initial refresh", refreshBoards)
	end)
	if RunService:IsStudio() then
		log.info("Studio: ladders need API access to read and write")
	end
	log.info(
		"started (%d boards, season %s, refresh %ds)",
		#RankingConfig.Leaderboard.Boards,
		GameConfig.SeasonId,
		RankingConfig.Leaderboard.RefreshSeconds
	)
end

return LeaderboardService
