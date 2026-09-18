--!strict
-- AnalyticsService: the only module that talks to the Roblox analytics service. It exposes the four
-- event families the game records (economy, funnel, progression, custom) behind a per-player token
-- bucket, so a noisy caller can never flood the quota, and it drops every event silently when the
-- Roblox service is unavailable (Studio without API access, quota outage): telemetry never breaks
-- gameplay and never blocks a caller.
--
-- Callers pass plain values (a flow type as "Source" / "Sink", a status as "Start" / "Complete" / …);
-- the Roblox enums live here so no other service needs to know them.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The Roblox analytics service, aliased so it never shadows this module's own name.
local RobloxAnalytics = game:GetService("AnalyticsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Log = require(Shared.Util.Log)
local TokenBucket = require(Shared.Util.TokenBucket)
local Trove = require(Packages.Trove)

local log = Log.new("AnalyticsService")

export type FlowType = "Source" | "Sink"
export type ProgressionStatus = "Start" | "Complete" | "Fail" | "Custom"
export type Fields = { [string]: any }

type Deps = {}

-- Per-player budget: a short burst (an action plus the economy event it produces) then a steady
-- trickle. An over-budget event is dropped, never queued: analytics is best-effort telemetry.
local EVENT_BURST = 8
local EVENT_REFILL_PER_SECOND = 4
-- After this many consecutive rejected calls the wrapper holds every call off for DISABLED_SECONDS,
-- then tries again. Only the first failure is logged, so a server without API access stays quiet.
local MAX_CONSECUTIVE_FAILURES = 3
local DISABLED_SECONDS = 60
-- Dimensions the Creator Dashboard groups events by.
local ONBOARDING_FUNNEL = "Onboarding"
local PROGRESSION_PATH = "PlayerLevel"

local AnalyticsService = {}

local trove = Trove.new()
local buckets: { [Player]: TokenBucket.Bucket } = {}
local sessions: { [Player]: string } = {}
local failures = 0
local disabledUntil = 0
local warned = false

----------------------------------------------------------------
-- Budget and transport
----------------------------------------------------------------

-- True when `player` is still in the server, the transport is not held off and the player's bucket
-- has a token left (which this call then consumes).
local function allow(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end
	local now = os.clock()
	if now < disabledUntil then
		return false
	end
	local bucket = buckets[player]
	if bucket == nil then
		bucket = TokenBucket.new(EVENT_BURST, EVENT_REFILL_PER_SECOND, now)
		buckets[player] = bucket
	end
	return TokenBucket.tryTake(bucket, now)
end

-- Runs one Roblox analytics call. A failure is counted and reported once with context; once the
-- streak is reached every call is held off for DISABLED_SECONDS.
local function send(context: string, fn: () -> ...any)
	local ok, err = pcall(fn)
	if ok then
		failures = 0
		return
	end
	failures += 1
	if not warned then
		warned = true
		log.warn("%s failed, events are dropped while the service is unavailable: %s", context, tostring(err))
	end
	if failures >= MAX_CONSECUTIVE_FAILURES then
		failures = 0
		disabledUntil = os.clock() + DISABLED_SECONDS
	end
end

-- Funnel session id of the player: one per visit, so funnel steps of the same session group together.
local function sessionIdFor(player: Player): string
	local existing = sessions[player]
	if existing ~= nil then
		return existing
	end
	local id = HttpService:GenerateGUID(false)
	sessions[player] = id
	return id
end

local function isPositive(value: number): boolean
	return value == value and value ~= math.huge and value > 0
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- One currency movement. `category` is a Roblox transaction type name ("Gameplay", "Shop", "IAP",
-- "TimedReward", "ContextualPurchase", "Onboarding"), `itemSku` the thing bought or rewarded.
function AnalyticsService.economy(
	player: Player,
	flowType: FlowType,
	currency: string,
	amount: number,
	endingBalance: number,
	category: string,
	itemSku: string?
)
	if not isPositive(amount) then
		log.warn("economy %s for %s dropped: invalid amount %s", category, player.Name, tostring(amount))
		return
	end
	if not allow(player) then
		return
	end
	local flow = if flowType == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
	send("LogEconomyEvent " .. category, function()
		RobloxAnalytics:LogEconomyEvent(player, flow, currency, amount, math.max(0, endingBalance), category, itemSku)
	end)
end

-- One step of the onboarding funnel (first touch, first jutsu, first match…).
function AnalyticsService.funnel(player: Player, stepName: string, stepNumber: number)
	if not allow(player) then
		return
	end
	local sessionId = sessionIdFor(player)
	send("LogFunnelStepEvent " .. stepName, function()
		RobloxAnalytics:LogFunnelStepEvent(player, ONBOARDING_FUNNEL, sessionId, stepNumber, stepName)
	end)
end

-- Player level progression ("Start" when a level begins, "Complete" when it is reached).
function AnalyticsService.progression(player: Player, status: ProgressionStatus, level: number)
	if not allow(player) then
		return
	end
	local item = Enum.AnalyticsProgressionType.Custom
	if status == "Start" then
		item = Enum.AnalyticsProgressionType.Start
	elseif status == "Complete" then
		item = Enum.AnalyticsProgressionType.Complete
	elseif status == "Fail" then
		item = Enum.AnalyticsProgressionType.Fail
	end
	send("LogProgressionEvent " .. status, function()
		RobloxAnalytics:LogProgressionEvent(player, PROGRESSION_PATH, item, level)
	end)
end

-- Anything that is not a currency movement, a funnel step or a level: prompts, match results, boss
-- kills, session length. `fields` values must be strings or numbers.
function AnalyticsService.custom(player: Player, eventName: string, value: number?, fields: Fields?)
	if not allow(player) then
		return
	end
	send("LogCustomEvent " .. eventName, function()
		RobloxAnalytics:LogCustomEvent(player, eventName, value, fields)
	end)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	buckets[player] = nil
	sessions[player] = nil
end

function AnalyticsService.Init(_deps: Deps) end

function AnalyticsService.Start()
	trove:Add(Players.PlayerRemoving:Connect(onPlayerRemoving))
	log.info("started (%d events per player per second)", EVENT_REFILL_PER_SECOND)
end

return AnalyticsService
