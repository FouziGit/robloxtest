--!strict
-- A pretend Roblox AnalyticsService that writes down every call it is given, for the real
-- src/server/Services/AnalyticsService to talk to inside a pretend engine (tests/engine.luau). What reaches it is
-- exactly what would reach Roblox: the per-player budget, the refusals and the transport are the service's own.
local AnalyticsConfig = require("../src/server/Config/AnalyticsConfig")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")

local Analytics = {}

-- One call, as the engine would have received it: the method, the player, and its arguments after the player.
export type Call = { Method: string, Player: any, Args: { any } }

export type Recorder = {
	calls: { Call },
	-- The two services the real AnalyticsService asks the DataModel for, to hand to Engine.world.
	services: { [string]: any },
	-- The calls of `method` (and, when given, of `name`: a custom event's name, an economy event's transaction
	-- type), in order.
	of: (self: Recorder, method: string, name: string?) -> { Call },
	clear: (self: Recorder) -> (),
}

local METHODS = { "LogEconomyEvent", "LogCustomEvent", "LogFunnelStepEvent", "LogProgressionEvent" }

function Analytics.recorder(): Recorder
	local calls: { Call } = {}
	local service: { [string]: any } = {}
	for _, method in ipairs(METHODS) do
		service[method] = function(_self: any, player: any, ...: any)
			table.insert(calls, { Method = method, Player = player, Args = table.pack(...) })
		end
	end
	local guids = 0
	local http = {
		GenerateGUID = function(_self: any, _braces: boolean): string
			guids += 1
			return ("guid-%d"):format(guids)
		end,
	}

	local recorder: any = { calls = calls, services = { AnalyticsService = service, HttpService = http } }

	function recorder.of(_self: Recorder, method: string, name: string?): { Call }
		local found: { Call } = {}
		for _, call in ipairs(calls) do
			local named = if method == "LogEconomyEvent" then call.Args[5] else call.Args[1]
			if call.Method == method and (name == nil or named == name) then
				table.insert(found, call)
			end
		end
		return found
	end

	function recorder.clear(_self: Recorder)
		table.clear(calls)
	end

	return recorder :: Recorder
end

local function keysOf(map: { [string]: any }): { string }
	local keys: { string } = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Every word a custom field of AnalyticsConfig.Events may hold, by the name of the list the field names: the
-- config's own Vocabulary, and the lists the game's config keeps.
function Analytics.domains(): { [string]: { string } }
	local domains = table.clone(AnalyticsConfig.Vocabulary)
	domains.Pass = keysOf(MonetizationConfig.Passes)
	domains.Product = keysOf(MonetizationConfig.Products)
	domains.PurchaseKey = table.clone(domains.Pass)
	for _, key in ipairs(domains.Product) do
		table.insert(domains.PurchaseKey, key)
	end
	domains.Mode = table.clone(MatchConfig.ModeOrder)
	return domains
end

return Analytics
