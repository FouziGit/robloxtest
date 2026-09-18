--!strict
-- ClientData: the single client-side copy of the player's profile. Loaded once via RequestProfile,
-- then kept in sync through ProfileChanged(section, value). Controllers subscribe to `Changed`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Log = require(Shared.Util.Log)
-- WaitForChild: a sibling of this module's folder may not have been copied into PlayerScripts yet.
local RemoteClient = require(script.Parent.Parent:WaitForChild("RemoteClient"))
local Signal = require(Packages.Signal)
local Types = require(Shared.Types)

type ProfileData = Types.ProfileData

local log = Log.new("ClientData")

local REQUEST_TIMEOUT = 20
local REQUEST_RETRIES = 3

local ClientData = {}

ClientData.Changed = Signal.new() -- (section: string)
ClientData.Loaded = Signal.new() -- ()

local data: ProfileData? = nil
local loaded = false

function ClientData.get(): ProfileData?
	return data
end

function ClientData.isLoaded(): boolean
	return loaded
end

-- Yields until the profile is available (or returns nil after the retries are exhausted).
function ClientData.waitForLoad(): ProfileData?
	if loaded then
		return data
	end
	local thread = coroutine.running()
	local connection
	connection = ClientData.Loaded:Connect(function()
		connection:Disconnect()
		task.spawn(thread)
	end)
	coroutine.yield()
	return data
end

local function applySection(section: string, value: any)
	if section == "*" then
		if type(value) ~= "table" then
			return
		end
		data = value :: ProfileData
		if not loaded then
			loaded = true
			ClientData.Loaded:Fire()
		end
		ClientData.Changed:Fire("*")
		return
	end
	if data == nil then
		return
	end
	(data :: any)[section] = value
	ClientData.Changed:Fire(section)
end

function ClientData.Init()
	RemoteClient.on("ProfileChanged", applySection)
end

function ClientData.Start()
	task.spawn(function()
		for attempt = 1, REQUEST_RETRIES do
			if loaded then
				return
			end
			local ok, result = RemoteClient.invoke("RequestProfile", REQUEST_TIMEOUT)
			if ok and type(result) == "table" then
				applySection("*", result)
				return
			end
			log.warn("profile request attempt %d failed: %s", attempt, tostring(result))
			task.wait(2 * attempt)
		end
		if not loaded then
			log.error("profile could not be loaded from the server")
		end
	end)
end

return ClientData
