--!strict
-- Studio test purchases (D-211). With Enable Studio Access to API Services on, a server started in Studio holds
-- the player's real profile, and every purchase used to be granted into it for good: Folios, cosmetics, the
-- pass cache, the Orpiment pigment, the loadout slots (docs/QA.md R9). Roblox charges nothing in Studio, so
-- while StudioConfig.PersistTestPurchases is off a test purchase is acknowledged to Roblox, logged, told to the
-- player, and grants nothing. A live server never enters this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Context = require(script.Parent.Context)
local Log = require(Shared.Util.Log)
local StudioConfig = require(script.Parent.Parent.Parent.Config.StudioConfig)

local log = Log.new("MonetizationService")

local Sandbox = {}

local deps: Context.Deps

-- True on a Studio server while test purchases are kept out of the profile.
function Sandbox.active(): boolean
	return RunService:IsStudio() and not StudioConfig.PersistTestPurchases
end

-- Tells the player and the log that the test purchase of `entry` (a catalog key) granted nothing. `nameKey` is
-- the entry's Strings key, translated by the player's client.
function Sandbox.acknowledge(player: Player, entry: string, nameKey: string)
	log.info(
		"Studio test purchase of %s by %s: nothing granted or saved (StudioConfig.PersistTestPurchases is off)",
		entry,
		player.Name
	)
	deps.Notify.send(player, "purchase.sandboxed", { name = nameKey }, "Info")
end

-- Says once, at startup, what a Studio purchase does on this server.
function Sandbox.announce()
	if not RunService:IsStudio() then
		return
	end
	if StudioConfig.PersistTestPurchases then
		log.warn(
			"Studio: test purchases are granted and SAVED into the real profile (StudioConfig.PersistTestPurchases)"
		)
	else
		log.info("Studio: test purchases are sandboxed, nothing they grant reaches the profile")
	end
end

function Sandbox.Init(injected: Context.Deps)
	deps = injected
end

return Sandbox
