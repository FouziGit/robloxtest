--!strict
-- Client entry point (docs/ARCHITECTURE.md). A failing controller is logged and never blocks the others.
--
-- Bootstrap contract: three separate passes over ORDER, never one interleaved chain.
--   1. Require every controller module. `deps` is therefore complete, and whatever a module builds at
--      load time -- its Signals, its default state table -- exists for every controller, before any
--      Init runs.
--   2. Init(deps) for each one. Init may reference any controller module whatever its rank in ORDER
--      (pass 1 guarantees it is there) and store it. It must not depend on another Init having run.
--   3. Start() for each one. Start may connect to any controller's Signal and call any accessor that
--      only reads load-time state, for any rank, since pass 1 guarantees both. It may only drive
--      behaviour that another controller's Start installs -- remote handlers, input bindings, built
--      widgets -- when that controller is listed earlier in ORDER.
-- ORDER is thus the order in which Start-installed behaviour becomes available. It does not restrict
-- which modules an Init may look at, so adding a controller dependency needs no reordering.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

-- WaitForChild the whole way down, siblings included. StarterPlayerScripts is COPIED into PlayerScripts
-- one child at a time when the player spawns, and this script can start before its own siblings have
-- arrived: indexing RemoteClient directly raised "not a valid member of PlayerScripts" and killed the
-- entire client, HUD and all ten screens with it, while the server ran on perfectly.
local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log"))
local RemoteClient = require(script.Parent:WaitForChild("RemoteClient"))

local log = Log.new("ClientBootstrap")

-- Order in which Start-installed behaviour becomes available (see the contract above).
local ORDER = {
	"ClientData",
	"Localize",
	"SoundController",
	-- Before anything that pulses it: WorldLighting builds the five post-processing effects at Start, and
	-- a pulse fired against effects that do not exist yet is a pulse nobody sees.
	"WorldLighting",
	"Feel",
	-- The pool hands out instances, the timeline borrows them, the renderers play timelines. Each one
	-- needs the previous one's Start to have run.
	"VfxPool",
	"VfxTimeline",
	"VfxController",
	-- Stamps through VfxTimeline, so after it.
	"FootprintController",
	"MatchController",
	"HudController",
	"BossController",
	"MenuController",
	"InputController",
	"ComboController",
	-- Listens to the combo and draws in the HUD: after both.
	"OnboardingController",
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
