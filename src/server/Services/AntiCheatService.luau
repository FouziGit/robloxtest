--!strict
-- AntiCheatService: counts rejected remote calls per player inside a rolling window and kicks
-- repeat offenders. RemoteRegistry reports every Guard / rate-limit rejection through `strike`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local log = Log.new("AntiCheatService")

type Deps = { [string]: any }

local AntiCheatService = {}

-- Strike timestamps (os.clock) per player, oldest first, pruned to the abuse window.
local strikes: { [Player]: { number } } = {}

local function prune(list: { number }, now: number)
	local cutoff = now - GameConfig.Server.AbuseWindowSeconds
	while #list > 0 and list[1] < cutoff do
		table.remove(list, 1)
	end
end

-- Records one rejected call from `source` (remote name). Kicks once the window holds
-- `GameConfig.Server.AbuseKickThreshold` strikes.
function AntiCheatService.strike(player: Player, source: string, reason: string)
	if player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local list = strikes[player]
	if list == nil then
		list = {}
		strikes[player] = list
	end
	prune(list, now)
	table.insert(list, now)

	local threshold = GameConfig.Server.AbuseKickThreshold
	log.warn("%s strike %d/%d (%s): %s", player.Name, #list, threshold, source, reason)
	if #list >= threshold then
		strikes[player] = nil
		log.warn(
			"%s kicked: %d rejected calls within %ds",
			player.Name,
			threshold,
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
		"started (kick after %d strikes within %ds)",
		GameConfig.Server.AbuseKickThreshold,
		GameConfig.Server.AbuseWindowSeconds
	)
end

return AntiCheatService
