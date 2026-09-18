--!strict
-- Server entry point (the only server Script). Creates the remote registry, wires every service
-- with its dependencies, then runs Init and Start in dependency order.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = script.Parent.Services
local Effects = script.Parent.Effects

local AnalyticsService = require(Services.AnalyticsService)
local AntiCheatService = require(Services.AntiCheatService)
local ArenaService = require(Services.ArenaService)
local BattlepassService = require(Services.BattlepassService)
local CombatService = require(Services.CombatService)
local CosmeticService = require(Services.CosmeticService)
local CurrencyService = require(Services.CurrencyService)
local DailyRewardService = require(Services.DailyRewardService)
local DataService = require(Services.DataService)
local EnemyService = require(Services.EnemyService)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphEffects = require(Effects.GlyphEffects)
local GlyphService = require(Services.GlyphService)
local HubService = require(Services.HubService)
local LeaderboardService = require(Services.LeaderboardService)
local LoadoutService = require(Services.LoadoutService)
local Log = require(Shared.Util.Log)
local MatchService = require(Services.MatchService)
local MatchmakingService = require(Services.MatchmakingService)
local MonetizationService = require(Services.MonetizationService)
local MovementService = require(Services.MovementService)
local NotifyService = require(Services.NotifyService)
local ProgressionService = require(Services.ProgressionService)
local QuestService = require(Services.QuestService)
local RankingService = require(Services.RankingService)
local RemoteRegistry = require(script.Parent.RemoteRegistry)
local SettingsService = require(Services.SettingsService)
local ShopService = require(Services.ShopService)
local Types = require(Shared.Types)
local VfxBroadcaster = require(Services.VfxBroadcaster)
local WorldBossService = require(Services.WorldBossService)

local log = Log.new("Bootstrap")

type Service = { Init: (deps: any) -> (), Start: () -> () }
type Entry = { Name: string, Service: Service }

-- Bound so an abandoned RequestProfile never pins a server thread for long; ClientData retries on
-- its own timeout and gets the snapshot immediately once the profile is loaded.
local PROFILE_REQUEST_TIMEOUT_SECONDS = 25

local registry = RemoteRegistry.create(
	function(player: Player, remote: string, reason: string, kind: AntiCheatService.StrikeKind?)
		AntiCheatService.strike(player, remote, reason, kind)
	end
)

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
	Glyph = GlyphService,
	Effects = GlyphEffects,
	Vfx = VfxBroadcaster,
	Enemy = EnemyService,
	Hub = HubService,
	Arena = ArenaService,
	Ranking = RankingService,
	Leaderboard = LeaderboardService,
	Match = MatchService,
	Matchmaking = MatchmakingService,
	Analytics = AnalyticsService,
	Quest = QuestService,
	Daily = DailyRewardService,
	Loadout = LoadoutService,
	Cosmetic = CosmeticService,
	Shop = ShopService,
	Monetization = MonetizationService,
	WorldBoss = WorldBossService,
}

-- Dependency order: each service only reads services listed before it.
local ordered: { Entry } = {
	-- HubService builds HubSpawn first: CombatService resolves its safe zone and EnemyService its
	-- dummy ring from the first SpawnLocation in the Workspace.
	{ Name = "HubService", Service = HubService },
	{ Name = "ArenaService", Service = ArenaService },
	{ Name = "DataService", Service = DataService },
	{ Name = "AntiCheatService", Service = AntiCheatService },
	{ Name = "NotifyService", Service = NotifyService },
	{ Name = "AnalyticsService", Service = AnalyticsService },
	{ Name = "CurrencyService", Service = CurrencyService },
	{ Name = "ProgressionService", Service = ProgressionService },
	{ Name = "CosmeticService", Service = CosmeticService },
	{ Name = "BattlepassService", Service = BattlepassService },
	{ Name = "LoadoutService", Service = LoadoutService },
	{ Name = "QuestService", Service = QuestService },
	{ Name = "DailyRewardService", Service = DailyRewardService },
	{ Name = "ShopService", Service = ShopService },
	{ Name = "SettingsService", Service = SettingsService },
	{ Name = "MovementService", Service = MovementService },
	{ Name = "VfxBroadcaster", Service = VfxBroadcaster },
	{ Name = "CombatService", Service = CombatService },
	{ Name = "GlyphService", Service = GlyphService },
	{ Name = "EnemyService", Service = EnemyService },
	{ Name = "RankingService", Service = RankingService },
	{ Name = "LeaderboardService", Service = LeaderboardService },
	{ Name = "MatchService", Service = MatchService },
	{ Name = "MatchmakingService", Service = MatchmakingService },
	{ Name = "WorldBossService", Service = WorldBossService },
	-- Last: it applies pass ownership through Loadout / Cosmetic / Battlepass, which must all be up.
	{ Name = "MonetizationService", Service = MonetizationService },
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

log.info("Vellum v%s ready: %d services started", GameConfig.Version, #ordered)
