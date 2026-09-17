--!strict
-- Client entry point. Requires every controller, then Init(deps) and Start() each one in dependency
-- order (docs/ARCHITECTURE.md). A failing controller is logged and never blocks the others.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local RemoteClient = require(script.Parent.RemoteClient)

local log = Log.new("ClientBootstrap")

-- Init and Start order: each controller only depends on controllers listed before it.
local ORDER = {
	"ClientData",
	"Localize",
	"SoundController",
	"VfxController",
	"HudController",
	"MenuController",
	"InputController",
	"ComboController",
	"CombatController",
	"MovementController",
}

local controllersFolder = script.Parent:WaitForChild("Controllers")

local deps: { [string]: any } = { RemoteClient = RemoteClient }
local loaded: { string } = {}

for _, name in ipairs(ORDER) do
	local module = controllersFolder:WaitForChild(name)
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		deps[name] = result
		table.insert(loaded, name)
	else
		log.error("could not load controller %s: %s", name, tostring(result))
	end
end

for _, name in ipairs(loaded) do
	local controller = deps[name]
	if type(controller.Init) == "function" then
		log.try("Init " .. name, controller.Init, deps)
	end
end

for _, name in ipairs(loaded) do
	local controller = deps[name]
	if type(controller.Start) == "function" then
		log.try("Start " .. name, controller.Start)
	end
end

log.info("%d/%d controllers started", #loaded, #ORDER)
