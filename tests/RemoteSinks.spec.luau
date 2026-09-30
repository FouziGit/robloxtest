--!strict
-- Every server→client event has a sink (E9-S5, D-218).
--
-- A RemoteEvent the server only ever fires is still one a client can FireServer on. With nothing listening, the
-- engine queued each such call and dropped it unseen: a tampered client could hammer ProfileChanged or Vfx and
-- never be counted. RemoteRegistry.create now connects one sink to each, which reports the call as a wrong
-- direction (a Schema strike, against AntiCheat's low threshold), and `on` refuses to add a listener to one.
--
-- This runs the real RemoteRegistry: the engine's instances and signals come from tests/engine.luau, and the
-- shared modules it requires (Guard, Log, Remotes, TokenBucket) are the files in src/shared.
local Engine = require("./engine")
local Harness = require("./harness")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Report = { Player: any, Remote: string, Reason: string, Kind: string }

-- A fresh registry over fake instances, and every abuse it reported.
local function build(): (any, { Report }, any)
	local world = Engine.world()
	local shared = Engine.instance("Folder")
	shared.Name = "Shared"
	shared.Util = {
		Guard = world.require("src/shared/Util/Guard"),
		Log = world.require("src/shared/Util/Log"),
		TokenBucket = world.require("src/shared/Util/TokenBucket"),
	}
	shared.Remotes = world.require("src/shared/Remotes")
	local replicated = Engine.instance("ReplicatedStorage")
	shared.Parent = replicated
	local players = {
		GetPlayers = function()
			return {}
		end,
	}
	local services: { [string]: any } = { Players = players, ReplicatedStorage = replicated }
	local env = {
		game = {
			GetService = function(_self: any, name: string): any
				return assert(services[name], "RemoteRegistry asked for " .. name)
			end,
		},
		-- The shared modules are already loaded: a require of one is the module itself.
		require = function(module: any): any
			return module
		end,
		Instance = {
			new = function(className: string): any
				local instance = Engine.instance(className)
				if className ~= "Folder" then
					instance.OnServerEvent = Engine.signal()
				end
				return instance
			end,
		},
	}
	local chunk = luau.load(fs.readFile("src/server/RemoteRegistry.luau"), {
		debugName = "src/server/RemoteRegistry",
		environment = env,
	})
	local RemoteRegistry = chunk()
	local reports: { Report } = {}
	local registry = RemoteRegistry.create(function(player: any, remote: string, reason: string, kind: string)
		table.insert(reports, { Player = player, Remote = remote, Reason = reason, Kind = kind })
	end)
	return registry, reports, shared.Remotes
end

local function eventNames(Remotes: any, direction: string): { string }
	local names: { string } = {}
	for _, name in ipairs(Remotes.names()) do
		local definition = Remotes.Definitions[name]
		if definition.Direction == direction and definition.Kind ~= "RemoteFunction" then
			table.insert(names, name)
		end
	end
	return names
end

describe("server→client events", function()
	it("exist, so nothing below passes vacuously", function()
		local _, _, Remotes = build()
		expect(#eventNames(Remotes, "ServerToClient")).toBeGreaterThanOrEqual(10)
		expect(#eventNames(Remotes, "ClientToServer")).toBeGreaterThanOrEqual(10)
	end)

	it("each have exactly one listener, the sink", function()
		local registry, _, Remotes = build()
		for _, name in ipairs(eventNames(Remotes, "ServerToClient")) do
			local count = registry.get(name).OnServerEvent:count()
			if count ~= 1 then
				error(("%s has %d server listener(s), not the one sink"):format(name, count))
			end
		end
		-- A client→server event gets its listener from `on`, not from creation.
		for _, name in ipairs(eventNames(Remotes, "ClientToServer")) do
			expect(registry.get(name).OnServerEvent:count()).toBe(0)
		end
	end)

	it("strike whoever fires them, once per call, as a wrong direction under Schema", function()
		local registry, reports, Remotes = build()
		local player = Engine.instance("Player")
		for _, name in ipairs(eventNames(Remotes, "ServerToClient")) do
			local before = #reports
			registry.get(name).OnServerEvent:Fire(player, { junk = true }, 42)
			expect(#reports).toBe(before + 1)
			local report = reports[#reports]
			expect(report.Player).toBe(player)
			expect(report.Remote).toBe(name)
			expect(report.Reason).toBe("wrong direction")
			expect(report.Kind).toBe("Schema")
		end
	end)

	it("refuse a second listener through `on`", function()
		local registry, _, Remotes = build()
		for _, name in ipairs(eventNames(Remotes, "ServerToClient")) do
			expect(function()
				registry.on(name, function() end)
			end).toThrow("server-to-client")
			expect(registry.get(name).OnServerEvent:count()).toBe(1)
		end
		-- And a client→server event still takes its handler.
		local name = eventNames(Remotes, "ClientToServer")[1]
		registry.on(name, function() end)
		expect(registry.get(name).OnServerEvent:count()).toBe(1)
	end)
end)
