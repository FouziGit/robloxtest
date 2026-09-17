--!strict
-- Server-side remote registry. Creates every remote declared in Shared/Remotes, validates each
-- client→server call with Guard, rate-limits with a per-player token bucket, and reports abuse to
-- AntiCheat. Handlers never see an invalid payload.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Guard = require(Shared.Util.Guard)
local Log = require(Shared.Util.Log)
local Remotes = require(Shared.Remotes)
local TokenBucket = require(Shared.Util.TokenBucket)

local log = Log.new("RemoteRegistry")

export type AbuseReporter = (player: Player, remoteName: string, reason: string) -> ()

export type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	setCallback: (name: string, callback: (player: Player, ...any) -> ...any) -> (),
	fire: (name: string, player: Player, ...any) -> (),
	fireAll: (name: string, ...any) -> (),
	fireExcept: (name: string, except: Player, ...any) -> (),
	get: (name: string) -> Instance,
	removePlayer: (player: Player) -> (),
}

local RemoteRegistry = {}

function RemoteRegistry.create(reportAbuse: AbuseReporter): Registry
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FolderName

	local instances: { [string]: Instance } = {}
	local buckets: { [Player]: { [string]: TokenBucket.Bucket } } = {}

	for name, definition in pairs(Remotes.Definitions) do
		local instance = Instance.new(definition.Kind)
		instance.Name = name
		instance.Parent = folder
		instances[name] = instance
	end
	folder.Parent = ReplicatedStorage

	local function bucketFor(player: Player, name: string): TokenBucket.Bucket?
		local definition = Remotes.Definitions[name]
		if definition.Rate == nil then
			return nil
		end
		local playerBuckets = buckets[player]
		if playerBuckets == nil then
			playerBuckets = {}
			buckets[player] = playerBuckets
		end
		local bucket = playerBuckets[name]
		if bucket == nil then
			bucket = TokenBucket.new(definition.Rate.Capacity, definition.Rate.Refill, os.clock())
			playerBuckets[name] = bucket
		end
		return bucket
	end

	-- Returns true when the call passes rate limit and schema validation.
	local function validate(player: Player, name: string, args: { any }, count: number): boolean
		local definition = Remotes.Definitions[name]
		if definition.Direction ~= "ClientToServer" then
			reportAbuse(player, name, "wrong direction")
			return false
		end
		local bucket = bucketFor(player, name)
		if bucket ~= nil and not TokenBucket.tryTake(bucket, os.clock()) then
			reportAbuse(player, name, "rate limit")
			return false
		end
		local schemas = definition.Args or {}
		if count > #schemas then
			reportAbuse(player, name, "too many arguments")
			return false
		end
		for index, schema in ipairs(schemas) do
			local ok, reason = Guard.check(schema, args[index])
			if not ok then
				reportAbuse(player, name, "argument " .. tostring(index) .. " " .. tostring(reason))
				return false
			end
		end
		return true
	end

	local registry = {}

	function registry.get(name: string): Instance
		local instance: Instance? = instances[name]
		if instance == nil then
			error("[RemoteRegistry] unknown remote " .. name)
		end
		return instance
	end

	function registry.on(name: string, handler: (player: Player, ...any) -> ())
		local instance = registry.get(name)
		if not (instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")) then
			error("[RemoteRegistry] " .. name .. " is not an event")
		end
		(instance :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: any)
			local args = table.pack(...)
			if not validate(player, name, args, args.n) then
				return
			end
			xpcall(handler, function(err)
				log.error("handler %s failed for %s: %s", name, player.Name, tostring(err))
			end, player, table.unpack(args, 1, args.n))
		end)
	end

	function registry.setCallback(name: string, callback: (player: Player, ...any) -> ...any)
		local instance = registry.get(name)
		if not instance:IsA("RemoteFunction") then
			error("[RemoteRegistry] " .. name .. " is not a function")
		end
		instance.OnServerInvoke = function(player: Player, ...: any): ...any
			local args = table.pack(...)
			if not validate(player, name, args, args.n) then
				return nil
			end
			local results = table.pack(pcall(callback, player, table.unpack(args, 1, args.n)))
			if not results[1] then
				log.error("callback %s failed for %s: %s", name, player.Name, tostring(results[2]))
				return nil
			end
			return table.unpack(results, 2, results.n)
		end
	end

	function registry.fire(name: string, player: Player, ...: any)
		local instance = registry.get(name)
		if instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent") then
			(instance :: RemoteEvent):FireClient(player, ...)
		else
			error("[RemoteRegistry] cannot fire " .. name)
		end
	end

	function registry.fireAll(name: string, ...: any)
		local instance = registry.get(name)
		if instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent") then
			(instance :: RemoteEvent):FireAllClients(...)
		else
			error("[RemoteRegistry] cannot fire " .. name)
		end
	end

	function registry.fireExcept(name: string, except: Player, ...: any)
		local instance = registry.get(name)
		if not (instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")) then
			error("[RemoteRegistry] cannot fire " .. name)
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= except then
				(instance :: RemoteEvent):FireClient(player, ...)
			end
		end
	end

	function registry.removePlayer(player: Player)
		buckets[player] = nil
	end

	log.info("%d remotes created", #Remotes.names())
	return registry :: Registry
end

return RemoteRegistry
