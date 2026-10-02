--!strict
-- Server-side remote registry. Creates every remote declared in Shared/Remotes, validates each
-- client→server call with Guard, rate-limits with a per-player token bucket, and reports every
-- rejection to AntiCheat. Handlers never see an invalid payload.
--
-- Rejections are reported under two kinds, because they mean different things:
--   "Schema"    wrong direction, wrong arity or a payload Guard refuses — only a tampered or broken
--               client produces these, so AntiCheat counts them against its low kick threshold;
--   "RateLimit" token-bucket overflow — a burst of legitimate input (mashing, a laggy re-send) also
--               produces these, so AntiCheat counts them separately against a much higher threshold.
--
-- It also remembers when each player's last VALID call arrived (`lastInbound`): proof the client is still
-- sending, which the movement guard needs before it may call a body that stopped moving a cheat rather
-- than a connection that stopped.
--
-- A server→client event is still an event a client can FireServer on. Nothing listened to those, so the
-- engine queued what a tampered client sent them and dropped it unseen: no strike, however much of it came.
-- Each one gets a sink at creation, its only listener (`on` refuses them), which reports the call as a wrong
-- direction, like any other call a well-formed client can never make.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Guard = require(Shared.Util.Guard)
local Log = require(Shared.Util.Log)
local Remotes = require(Shared.Remotes)
local TokenBucket = require(Shared.Util.TokenBucket)

local log = Log.new("RemoteRegistry")

export type AbuseKind = "Schema" | "RateLimit"
export type AbuseReporter = (player: Player, remoteName: string, reason: string, kind: AbuseKind) -> ()

export type Registry = {
	on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
	setCallback: (name: string, callback: (player: Player, ...any) -> ...any) -> (),
	fire: (name: string, player: Player, ...any) -> (),
	fireAll: (name: string, ...any) -> (),
	fireExcept: (name: string, except: Player, ...any) -> (),
	get: (name: string) -> Instance,
	lastInbound: (player: Player) -> number,
	removePlayer: (player: Player) -> (),
}

local RemoteRegistry = {}

function RemoteRegistry.create(reportAbuse: AbuseReporter): Registry
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FolderName

	local instances: { [string]: Instance } = {}
	local buckets: { [Player]: { [string]: TokenBucket.Bucket } } = {}
	-- os.clock of each player's last call that passed validation. A rejected call proves nothing: a
	-- flooder's refused spam must not read as a live, honest client.
	local lastInbound: { [Player]: number } = {}

	for name, definition in pairs(Remotes.Definitions) do
		local instance = Instance.new(definition.Kind)
		instance.Name = name
		instance.Parent = folder
		instances[name] = instance
		if definition.Direction == "ServerToClient" and definition.Kind ~= "RemoteFunction" then
			(instance :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
				reportAbuse(player, name, "wrong direction", "Schema")
			end)
		end
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
			reportAbuse(player, name, "wrong direction", "Schema")
			return false
		end
		local bucket = bucketFor(player, name)
		if bucket ~= nil and not TokenBucket.tryTake(bucket, os.clock()) then
			reportAbuse(player, name, "rate limit", "RateLimit")
			return false
		end
		local schemas = definition.Args or {}
		if count > #schemas then
			reportAbuse(player, name, "too many arguments", "Schema")
			return false
		end
		for index, schema in ipairs(schemas) do
			local ok, reason = Guard.check(schema, args[index])
			if not ok then
				reportAbuse(player, name, "argument " .. tostring(index) .. " " .. tostring(reason), "Schema")
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
		if Remotes.Definitions[name].Direction ~= "ClientToServer" then
			error("[RemoteRegistry] " .. name .. " is server-to-client: its only listener is the sink")
		end
		(instance :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: any)
			local args = table.pack(...)
			if not validate(player, name, args, args.n) then
				return
			end
			lastInbound[player] = os.clock()
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
			lastInbound[player] = os.clock()
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

	-- When `player`'s last valid call arrived (os.clock), or -math.huge if none has.
	function registry.lastInbound(player: Player): number
		return lastInbound[player] or -math.huge
	end

	function registry.removePlayer(player: Player)
		buckets[player] = nil
		lastInbound[player] = nil
	end

	log.info("%d remotes created", #Remotes.names())
	return registry :: Registry
end

return RemoteRegistry
