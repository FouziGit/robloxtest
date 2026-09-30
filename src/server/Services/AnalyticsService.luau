--!strict
-- AnalyticsService: the only module that talks to the Roblox analytics service. It exposes the four
-- event families the game records (economy, funnel, progression, custom) behind a per-player token
-- bucket, so a noisy caller can never flood the quota, and it drops every event silently when the
-- Roblox service is unavailable (Studio without API access, quota outage): telemetry never breaks
-- gameplay and never blocks a caller.
--
-- Callers pass plain values (a flow type as "Source" / "Sink", a status as "Start" / "Complete" / …);
-- the Roblox enums live here so no other service needs to know them.
--
-- A custom event carries its dimensions in the only three custom fields Roblox reads, CustomField01 to 03, as
-- text: every caller builds them with `fields`, and `custom` refuses an event AnalyticsConfig does not name, or
-- fields that are not exactly the ones its entry there declares. Refused, never sent: a key Roblox ignores
-- would record the event with its dimensions silently gone.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The Roblox analytics service, aliased so it never shadows this module's own name.
local RobloxAnalytics = game:GetService("AnalyticsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local AnalyticsConfig = require(script.Parent.Parent.Config.AnalyticsConfig)
local Log = require(Shared.Util.Log)
local TokenBucket = require(Shared.Util.TokenBucket)
local Trove = require(Packages.Trove)

local log = Log.new("AnalyticsService")

export type FlowType = "Source" | "Sink"
export type ProgressionStatus = "Start" | "Complete" | "Fail" | "Custom"
-- Custom fields as Roblox reads them: CustomField01 to 03, each a string. Built by `fields`, never by hand.
export type Fields = { [string]: string }
export type FieldValue = string | number

type Deps = {}

-- Per-player budget (AnalyticsConfig.Budget).
local EVENT_BURST = AnalyticsConfig.Budget.Burst
local EVENT_REFILL_PER_SECOND = AnalyticsConfig.Budget.PerMinute / 60
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
-- Custom events already refused, by name: the refusal is logged once, the next ones are dropped quietly.
local refused: { [string]: boolean } = {}
-- Currency reasons AnalyticsConfig does not list, already warned about.
local unlisted: { [string]: boolean } = {}

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

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Why `eventName` with this value and these fields cannot be sent, or nil when it can: its name is in
-- AnalyticsConfig.Events, and its fields are exactly the keys that entry declares, in order, each a string.
local function refusal(eventName: string, value: number?, fields: Fields?): string?
	local declared = AnalyticsConfig.Events[eventName]
	if declared == nil then
		return "not in AnalyticsConfig.Events"
	end
	if value ~= nil and not isFinite(value) then
		return "invalid value " .. tostring(value)
	end
	local given = 0
	for key, text in pairs(fields or {}) do
		local index = table.find(AnalyticsConfig.FieldKeys, key)
		if index == nil or index > #declared then
			return "custom field " .. tostring(key) .. " is not one it declares"
		end
		if type(text) ~= "string" then
			return "custom field " .. key .. " is not text"
		end
		given += 1
	end
	if given ~= #declared then
		return ("%d custom field(s) given, %d declared"):format(given, #declared)
	end
	return nil
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- One currency movement, from CurrencyService only: `reason` is the one it was handed, and says the Roblox
-- transaction type the Economy dashboards file the movement under and its item (AnalyticsConfig.economyOf). A
-- reason AnalyticsConfig does not list is still sent, under FallbackTransaction, and warned about once.
function AnalyticsService.economy(
	player: Player,
	flowType: FlowType,
	currency: string,
	amount: number,
	endingBalance: number,
	reason: string
)
	if not isPositive(amount) then
		log.warn("economy %s for %s dropped: invalid amount %s", reason, player.Name, tostring(amount))
		return
	end
	local transaction, itemSku, listed = AnalyticsConfig.economyOf(reason)
	if not listed and not unlisted[reason] then
		unlisted[reason] = true
		log.warn("economy reason %s is not in AnalyticsConfig: filed under %s", reason, transaction)
	end
	if not allow(player) then
		return
	end
	local flow = if flowType == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
	send("LogEconomyEvent " .. transaction, function()
		RobloxAnalytics:LogEconomyEvent(
			player,
			flow,
			currency,
			amount,
			math.max(0, endingBalance),
			transaction,
			itemSku
		)
	end)
end

-- One step of the onboarding funnel (first touch, first glyph, first match…).
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

-- The custom fields of one event, as Roblox reads them: `first` in CustomField01, then `second` and `third`,
-- each written as text. Every custom event's fields are built here.
function AnalyticsService.fields(first: FieldValue, second: FieldValue?, third: FieldValue?): Fields
	local keys = AnalyticsConfig.FieldKeys
	local fields: Fields = { [keys[1]] = tostring(first) }
	if second ~= nil then
		fields[keys[2]] = tostring(second)
	end
	if third ~= nil then
		fields[keys[3]] = tostring(third)
	end
	return fields
end

-- Anything that is not a currency movement, a funnel step or a level: prompts, match results, boss fights,
-- glyph balance. `eventName` is a name of AnalyticsConfig.Events and `fields` what `fields` built for it;
-- anything else is refused (see the header). `value` defaults to 1, a count.
function AnalyticsService.custom(player: Player, eventName: string, value: number?, fields: Fields?)
	local problem = refusal(eventName, value, fields)
	if problem ~= nil then
		if not refused[eventName] then
			refused[eventName] = true
			log.warn("custom event %s dropped: %s", eventName, problem)
		end
		return
	end
	if not allow(player) then
		return
	end
	send("LogCustomEvent " .. eventName, function()
		RobloxAnalytics:LogCustomEvent(player, eventName, value or 1, fields)
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
	log.info("started (%d events per player per minute, %d at once)", AnalyticsConfig.Budget.PerMinute, EVENT_BURST)
end

return AnalyticsService
