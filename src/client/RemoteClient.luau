--!strict
-- Client-side access to the remotes created by the server's RemoteRegistry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local RemoteClient = {}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder == nil then
		folder = ReplicatedStorage:WaitForChild(Remotes.FolderName) :: Folder
	end
	return folder :: Folder
end

function RemoteClient.get(name: string): Instance
	if Remotes.Definitions[name] == nil then
		error("[RemoteClient] unknown remote " .. name)
	end
	return getFolder():WaitForChild(name)
end

function RemoteClient.event(name: string): RemoteEvent
	local instance = RemoteClient.get(name)
	if instance:IsA("RemoteEvent") then
		return instance
	end
	error("[RemoteClient] " .. name .. " is not a RemoteEvent")
end

function RemoteClient.unreliable(name: string): UnreliableRemoteEvent
	local instance = RemoteClient.get(name)
	if instance:IsA("UnreliableRemoteEvent") then
		return instance
	end
	error("[RemoteClient] " .. name .. " is not an UnreliableRemoteEvent")
end

function RemoteClient.fire(name: string, ...: any)
	local instance = RemoteClient.get(name)
	if instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent") then
		(instance :: RemoteEvent):FireServer(...)
	else
		error("[RemoteClient] cannot fire " .. name)
	end
end

function RemoteClient.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local instance = RemoteClient.get(name)
	if instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent") then
		return (instance :: RemoteEvent).OnClientEvent:Connect(handler)
	end
	error("[RemoteClient] cannot listen to " .. name)
end

-- Invokes a RemoteFunction with a timeout. Returns (true, results…) or (false, "timeout" | error).
function RemoteClient.invoke(name: string, timeout: number, ...: any): (boolean, ...any)
	local instance = RemoteClient.get(name)
	if not instance:IsA("RemoteFunction") then
		error("[RemoteClient] " .. name .. " is not a RemoteFunction")
	end
	local thread = coroutine.running()
	local finished = false
	local args = table.pack(...)

	task.spawn(function()
		local results = table.pack(pcall(function()
			return instance:InvokeServer(table.unpack(args, 1, args.n))
		end))
		if finished then
			return
		end
		finished = true
		task.spawn(thread, table.unpack(results, 1, results.n))
	end)

	task.delay(timeout, function()
		if finished then
			return
		end
		finished = true
		task.spawn(thread, false, "timeout")
	end)

	return coroutine.yield()
end

return RemoteClient
