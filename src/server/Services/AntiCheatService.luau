--!strict
-- AntiCheatService: counts rejected remote calls per player inside a rolling window and kicks repeat
-- offenders. RemoteRegistry reports every rejection through `strike`.
--
-- The two rejection kinds are counted independently, each against its own threshold:
--   "Schema"    (default) a payload Guard refused, a wrong direction or a wrong arity. Only a
--               tampered or broken client produces one, so `GameConfig.Server.AbuseKickThreshold`
--               (low) applies.
--   "RateLimit" a token-bucket overflow. Legitimate input also produces these (input mashing beyond
--               the server's own acceptance interval, a laggy client re-sending), so they must never
--               share the schema counter: they use `RATE_LIMIT_KICK_THRESHOLD` (much higher) and only
--               sustained flooding, far above any human input rate, still reaches a kick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local log = Log.new("AntiCheatService")

type Deps = { [string]: any }

export type StrikeKind = "Schema" | "RateLimit"

-- Rate-limit overflows tolerated inside `GameConfig.Server.AbuseWindowSeconds`. 600 over 60 s is a
-- sustained 10 rejected calls per second: an order of magnitude above what any human input can
-- produce once the client throttles its sends (CombatController), while an automated flooder still
-- reaches it in a couple of seconds.
local RATE_LIMIT_KICK_THRESHOLD = GameConfig.Server.RateLimitKickThreshold
-- Kind assumed when a caller does not state one: the strict schema threshold.
local DEFAULT_KIND: StrikeKind = "Schema"

local AntiCheatService = {}

-- Strike timestamps (os.clock) per player and per kind, oldest first, pruned to the abuse window.
local strikes: { [Player]: { [string]: { number } } } = {}

local function thresholdFor(kind: StrikeKind): number
	if kind == "RateLimit" then
		return RATE_LIMIT_KICK_THRESHOLD
	end
	return GameConfig.Server.AbuseKickThreshold
end

local function prune(list: { number }, now: number)
	local cutoff = now - GameConfig.Server.AbuseWindowSeconds
	while #list > 0 and list[1] < cutoff do
		table.remove(list, 1)
	end
end

-- Records one rejected call of `kind` from `source` (remote name). Kicks once the window holds the
-- threshold for that kind; the two kinds never add up to a kick together.
function AntiCheatService.strike(player: Player, source: string, reason: string, kind: StrikeKind?)
	if player.Parent ~= Players then
		return
	end
	local strikeKind: StrikeKind = kind or DEFAULT_KIND
	local now = os.clock()
	local byKind = strikes[player]
	if byKind == nil then
		byKind = {}
		strikes[player] = byKind
	end
	local list = byKind[strikeKind]
	if list == nil then
		list = {}
		byKind[strikeKind] = list
	end
	prune(list, now)
	table.insert(list, now)

	local threshold = thresholdFor(strikeKind)
	log.warn("%s %s strike %d/%d (%s): %s", player.Name, strikeKind, #list, threshold, source, reason)
	if #list >= threshold then
		strikes[player] = nil
		log.warn(
			"%s kicked: %d rejected %s calls within %ds",
			player.Name,
			threshold,
			strikeKind,
			GameConfig.Server.AbuseWindowSeconds
		)
		player:Kick(Strings.t("kick.abuse", nil, Strings.localeFromId(player.LocaleId)))
	end
end

-- Strikes may arrive before Start (the registry reporter is wired first), so the cleanup hook is
-- connected as soon as the service is initialised.
function AntiCheatService.Init(_deps: Deps)
	Players.PlayerRemoving:Connect(function(player: Player)
		strikes[player] = nil
	end)
end

function AntiCheatService.Start()
	log.info(
		"started (kick after %d Schema or %d RateLimit strikes within %ds)",
		GameConfig.Server.AbuseKickThreshold,
		RATE_LIMIT_KICK_THRESHOLD,
		GameConfig.Server.AbuseWindowSeconds
	)
end

return AntiCheatService
