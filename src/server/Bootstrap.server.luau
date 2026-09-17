--!strict
-- Server entry point (the only server Script). Creates the remote registry, wires every service
-- with its dependencies, then runs Init and Start in dependency order.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = script.Parent.Services
local Effects = script.Parent.Effects

local AntiCheatService = require(Services.AntiCheatService)
local BattlepassService = require(Services.BattlepassService)
local CombatService = require(Services.CombatService)
local CurrencyService = require(Services.CurrencyService)
local DataService = require(Services.DataService)
local EnemyService = require(Services.EnemyService)
local GameConfig = require(Shared.Config.GameConfig)
local JutsuEffects = require(Effects.JutsuEffects)
local JutsuService = require(Services.JutsuService)
local Log = require(Shared.Util.Log)
local MovementService = require(Services.MovementService)
local NotifyService = require(Services.NotifyService)
local ProgressionService = require(Services.ProgressionService)
local RemoteRegistry = require(script.Parent.RemoteRegistry)
local SettingsService = require(Services.SettingsService)
local Types = require(Shared.Types)
local VfxBroadcaster = require(Services.VfxBroadcaster)

local log = Log.new("Bootstrap")

type Service = { Init: (deps: any) -> (), Start: () -> () }
type Entry = { Name: string, Service: Service }

-- Bound so an abandoned RequestProfile never pins a server thread for long; ClientData retries on
-- its own timeout and gets the snapshot immediately once the profile is loaded.
local PROFILE_REQUEST_TIMEOUT_SECONDS = 25

local registry = RemoteRegistry.create(function(player: Player, remote: string, reason: string)
	AntiCheatService.strike(player, remote, reason)
end)

local deps = {
	Registry = registry,
	DataService = DataService,
	AntiCheat = AntiCheatService,
	Notify = NotifyService,
	Currency = CurrencyService,
	Progression = ProgressionService,
	Battlepass = BattlepassService,
	Settings = SettingsService,
	Movement = MovementService,
	Combat = CombatService,
	Jutsu = JutsuService,
	Effects = JutsuEffects,
	Vfx = VfxBroadcaster,
	Enemy = EnemyService,
}

-- Dependency order: each service only reads services listed before it.
local ordered: { Entry } = {
	{ Name = "DataService", Service = DataService },
	{ Name = "AntiCheatService", Service = AntiCheatService },
	{ Name = "NotifyService", Service = NotifyService },
	{ Name = "CurrencyService", Service = CurrencyService },
	{ Name = "ProgressionService", Service = ProgressionService },
	{ Name = "BattlepassService", Service = BattlepassService },
	{ Name = "SettingsService", Service = SettingsService },
	{ Name = "MovementService", Service = MovementService },
	{ Name = "VfxBroadcaster", Service = VfxBroadcaster },
	{ Name = "CombatService", Service = CombatService },
	{ Name = "JutsuService", Service = JutsuService },
	{ Name = "EnemyService", Service = EnemyService },
}

for _, entry in ipairs(ordered) do
	log.try(entry.Name .. ".Init", entry.Service.Init, deps)
end
for _, entry in ipairs(ordered) do
	log.try(entry.Name .. ".Start", entry.Service.Start)
end

registry.setCallback("RequestProfile", function(player: Player): Types.ProfileData?
	local snapshot = DataService.snapshot(player)
	if snapshot ~= nil then
		return snapshot
	end
	if DataService.waitFor(player, PROFILE_REQUEST_TIMEOUT_SECONDS) == nil then
		return nil
	end
	return DataService.snapshot(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	registry.removePlayer(player)
end)

log.info("Jutsu Battlegrounds v%s ready: %d services started", GameConfig.Version, #ordered)
