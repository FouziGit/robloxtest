--!strict
-- DataService: the single owner of player profiles (ProfileStore). Loads, migrates, replicates and
-- releases profiles. Other services mutate `DataService.get(player)` in place and call `push`.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local DataMigration = require(Shared.Pure.DataMigration)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local InputConfig = require(Shared.Config.InputConfig)
local LegacyNames = require(Shared.Pure.LegacyNames)
local Log = require(Shared.Util.Log)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local QualityConfig = require(Shared.Config.QualityConfig)
local Signal = require(Packages.Signal)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

type ProfileData = Types.ProfileData

local log = Log.new("DataService")

-- Every action and both default maps, as the plain strings the pure migration reads
-- (DataMigration.settleKeybinds).
local ACTION_ORDER: { string } = {}
local DEFAULT_KEYS: { [string]: { [string]: string } } = { Keyboard = {}, Gamepad = {} }
for _, action in ipairs(InputConfig.Actions) do
	table.insert(ACTION_ORDER, action)
end
for action, key in pairs(InputConfig.DefaultKeyboard) do
	DEFAULT_KEYS.Keyboard[action] = key
end
for action, key in pairs(InputConfig.DefaultGamepad) do
	DEFAULT_KEYS.Gamepad[action] = key
end

-- These two strings are DataStore names, not identifiers, and they are the only place in the codebase
-- where the old project name must survive the rename. A DataStore is addressed by its name: change the
-- string and the engine hands back a different, empty store, so every profile ever saved would read as a
-- brand new player. They stay spelled as they were written the day they were created, forever.
local STORE_NAME = "JutsuBattlegrounds_v2"
local KEY_PREFIX = "Player_"
local LEGACY_STORE_NAME = "JutsuGame_PlayerData_v1"
local LEGACY_KEY_PREFIX = "Player_"
local MAX_RECEIPTS = 100

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player: Player, data: ProfileData)
DataService.ProfileReleased = Signal.new() -- (player: Player)
-- Fired while a leaving player's profile is STILL loaded, immediately before it is released. The last
-- moment anything can be persisted for them: once the session ends, DataService.get returns nil and
-- nothing can be written for that player on this server again. MatchService debits the forfeit of an
-- abandoned ranked match here, which is what used to make quitting free.
DataService.BeforeRelease = Signal.new() -- (player: Player, data: ProfileData)

local registry -- RemoteRegistry
local store
local profiles: { [Player]: any } = {} -- ProfileStore Profile objects
local loadedSignals: { [Player]: { any } } = {}

----------------------------------------------------------------
-- Template
----------------------------------------------------------------

local function defaultLoadout(): { string }
	local slots = {}
	for _, id in ipairs(GlyphConfig.defaultUnlocks()) do
		if #slots >= ProgressionConfig.Loadout.BaseSlots then
			break
		end
		table.insert(slots, id)
	end
	return slots
end

local function seasonTemplate(): Types.BattlepassSeasonData
	return { XP = 0, Tier = 1, Premium = false, ClaimedFree = {}, ClaimedPremium = {} }
end

-- Full V2 template. `Battlepass._template` is consumed by DataMigration and stripped from results.
function DataService.template(): { [string]: any }
	return {
		DataVersion = DataMigration.CurrentVersion,
		Settings = {
			Keyboard = table.clone(InputConfig.DefaultKeyboard :: any),
			Gamepad = table.clone(InputConfig.DefaultGamepad :: any),
			MusicVolume = 0.5,
			SfxVolume = 1,
			CameraShake = true,
			Quality = QualityConfig.Default,
		},
		Progression = { Level = 1, XP = 0, TotalXP = 0 },
		Currency = { Folios = 0 },
		Battlepass = { _template = seasonTemplate() },
		Cosmetics = { Owned = {}, Equipped = {} },
		Loadout = { Slots = defaultLoadout(), ExtraSlots = 0, SlotLimit = ProgressionConfig.Loadout.BaseSlots },
		Unlocks = { Glyphs = GlyphConfig.defaultUnlocks(), Pigments = table.clone(PigmentConfig.Base) },
		Rank = { SeasonId = GameConfig.SeasonId, Modes = {}, LastRewardedSeason = "" },
		Stats = {
			Kills = 0,
			Deaths = 0,
			GlyphsCast = 0,
			GlyphsHit = 0,
			BestChain = 0,
			MatchesPlayed = 0,
			BossKills = 0,
			PlayTimeSeconds = 0,
		},
		Quests = {
			Daily = { PeriodKey = "", Progress = {}, Claimed = {} },
			Weekly = { PeriodKey = "", Progress = {}, Claimed = {} },
		},
		Daily = { LastClaimDay = 0, Streak = 0, FirstWinDay = 0, PremiumBonusDay = 0 },
		Purchases = { Receipts = {}, ProductCounts = {} },
		Passes = {},
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
		Meta = {
			FirstJoin = 0,
			LastJoin = 0,
			SessionCount = 0,
			LegacyImported = false,
			FirstSessionPromptGate = false,
			SaveToken = 0,
			DevGranted = false,
		},
	}
end

-- Template handed to ProfileStore (no migration marker).
local function storeTemplate(): { [string]: any }
	local template = DataService.template()
	template.Battlepass = {}
	return template
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value :: any) do
		copy[key] = deepCopy(item)
	end
	return (copy :: any) :: T
end

local function replaceContents(target: { [string]: any }, source: { [string]: any })
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(source) do
		target[key] = value
	end
end

local function kick(player: Player, key: string)
	if player.Parent == Players then
		player:Kick(Strings.t(key, nil, Strings.localeFromId(player.LocaleId)))
	end
end

-- Reads the V1 (ProfileService) record, if any. Returns the legacy Data table or nil.
local function readLegacy(userId: number): { [string]: any }?
	local ok, result = pcall(function()
		local legacyStore = DataStoreService:GetDataStore(LEGACY_STORE_NAME)
		return legacyStore:GetAsync(LEGACY_KEY_PREFIX .. tostring(userId))
	end)
	if not ok then
		log.warn("legacy read failed for %d: %s", userId, tostring(result))
		return nil
	end
	if type(result) == "table" and type(result.Data) == "table" then
		return result.Data
	end
	return nil
end

----------------------------------------------------------------
-- Session lifecycle
----------------------------------------------------------------

local function ensureSeason(data: { [string]: any })
	if data.Battlepass[GameConfig.SeasonId] == nil then
		data.Battlepass[GameConfig.SeasonId] = seasonTemplate()
	end
	if data.Rank.SeasonId ~= GameConfig.SeasonId then
		data.Rank.SeasonId = GameConfig.SeasonId
		data.Rank.Modes = {}
	end
end

local function onSessionEnd(player: Player)
	profiles[player] = nil
	loadedSignals[player] = nil
	DataService.ProfileReleased:Fire(player)
	kick(player, "kick.sessionElsewhere")
end

local function loadProfile(player: Player)
	local key = KEY_PREFIX .. tostring(player.UserId)
	local profile = store:StartSessionAsync(key, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		if player.Parent == Players then
			log.warn("session could not start for %s", player.Name)
			kick(player, "kick.loadFailed")
		end
		return
	end

	profile:AddUserId(player.UserId)

	-- Migration (V1 → current, or fills a profile that predates new fields). LegacyNames carries the
	-- old-to-new identifier maps; without it a profile written before the lexicon rename would load with
	-- an empty unlock list and no cosmetics, because the keys that held them were renamed too.
	local template = DataService.template()
	local migrated, info = DataMigration.migrate(profile.Data, template, GameConfig.SeasonId, LegacyNames)

	-- Brand-new profile: try to import the V1 record once.
	if info.From == 0 or (profile.SessionLoadCount == 1 and migrated.Meta.FirstJoin == 0) then
		if not migrated.Meta.LegacyImported then
			local legacy = readLegacy(player.UserId)
			if legacy ~= nil then
				local imported, legacyInfo =
					DataMigration.migrate(legacy, DataService.template(), GameConfig.SeasonId, LegacyNames)
				if legacyInfo.Migrated then
					migrated = imported
					log.info("imported V1 profile for %s", player.Name)
				end
			end
			migrated.Meta.LegacyImported = true
		end
	end

	-- A default key added to the template after the player bound it elsewhere (D-115): their key stays
	-- theirs, and the new action takes a free one, or the server would refuse every save after it.
	for kind, allowed in pairs({ Keyboard = InputConfig.AllowedKeyboard, Gamepad = InputConfig.AllowedGamepad }) do
		if DataMigration.settleKeybinds(migrated.Settings[kind], DEFAULT_KEYS[kind], allowed, ACTION_ORDER) then
			log.info("%s keybinds of %s settled around a new default", kind, player.Name)
		end
	end

	replaceContents(profile.Data, migrated)
	profile:Reconcile()
	ensureSeason(profile.Data)

	local now = os.time()
	if profile.Data.Meta.FirstJoin == 0 then
		profile.Data.Meta.FirstJoin = now
	end
	profile.Data.Meta.LastJoin = now
	profile.Data.Meta.SessionCount += 1

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	profile.OnSessionEnd:Connect(function()
		onSessionEnd(player)
	end)

	log.info(
		"profile ready for %s (v%d, session #%d)",
		player.Name,
		profile.Data.DataVersion,
		profile.Data.Meta.SessionCount
	)
	DataService.ProfileLoaded:Fire(player, profile.Data)
	DataService.push(player, "*")

	local waiters = loadedSignals[player]
	loadedSignals[player] = nil
	if waiters ~= nil then
		for _, thread in ipairs(waiters) do
			task.spawn(thread, profile.Data)
		end
	end
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		xpcall(loadProfile, function(err)
			log.error("load failed for %s: %s", player.Name, tostring(err))
			kick(player, "kick.loadFailed")
		end, player)
	end)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		-- Before the profile leaves the table, and inside log.try: a listener that throws must never
		-- cost the session its release, which would leave the key locked until ProfileStore times out.
		log.try("BeforeRelease " .. player.Name, function()
			DataService.BeforeRelease:Fire(player, profile.Data)
		end)
	end
	profiles[player] = nil
	local waiters = loadedSignals[player]
	loadedSignals[player] = nil
	if waiters ~= nil then
		for _, thread in ipairs(waiters) do
			task.spawn(thread, nil)
		end
	end
	if profile ~= nil then
		profile:EndSession()
		DataService.ProfileReleased:Fire(player)
	end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

function DataService.Init(deps: { Registry: any })
	registry = deps.Registry
	store = ProfileStore.New(STORE_NAME, storeTemplate())
	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" then
		log.info("DataStore state: %s (Studio without API access saves nothing)", ProfileStore.DataStoreState)
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	log.info("started")
end

-- Live profile data (mutate in place, then push the changed section).
function DataService.get(player: Player): ProfileData?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	return profile.Data :: ProfileData
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Yields until the profile is loaded, the player leaves, or `timeout` seconds elapse.
function DataService.waitFor(player: Player, timeout: number?): ProfileData?
	local existing = DataService.get(player)
	if existing ~= nil then
		return existing
	end
	if player.Parent ~= Players then
		return nil
	end
	local thread = coroutine.running()
	local waiters = loadedSignals[player]
	if waiters == nil then
		waiters = {}
		loadedSignals[player] = waiters
	end
	table.insert(waiters, thread)
	local timer = task.delay(timeout or GameConfig.Server.ProfileLoadTimeoutSeconds, function()
		local list = loadedSignals[player]
		if list ~= nil then
			local index = table.find(list, thread)
			if index ~= nil then
				table.remove(list, index)
			end
		end
		task.spawn(thread, nil)
	end)
	local data = coroutine.yield()
	task.cancel(timer)
	return data
end

-- Deep copy safe to hand to the client.
function DataService.snapshot(player: Player): ProfileData?
	local data = DataService.get(player)
	if data == nil then
		return nil
	end
	return deepCopy(data)
end

-- Replicates one top-level section ("Progression", "Currency", …) or the whole profile ("*").
function DataService.push(player: Player, section: string)
	local data = DataService.get(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	if section == "*" then
		registry.fire("ProfileChanged", player, "*", deepCopy(data))
	else
		local value = (data :: any)[section]
		if value == nil then
			log.warn("push: unknown section %s", section)
			return
		end
		registry.fire("ProfileChanged", player, section, deepCopy(value))
	end
end

-- Records a processed receipt id (bounded ring buffer). Returns false if already recorded.
function DataService.recordReceipt(player: Player, purchaseId: string): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	if table.find(data.Purchases.Receipts, purchaseId) ~= nil then
		return false
	end
	table.insert(data.Purchases.Receipts, purchaseId)
	while #data.Purchases.Receipts > MAX_RECEIPTS do
		table.remove(data.Purchases.Receipts, 1)
	end
	return true
end

-- Forces an immediate save and waits for ProfileStore to confirm THIS data reached the DataStore.
-- Yields. Returns true only when a write carrying the caller's mutation has been acknowledged.
--
-- Profile:Save() performs the UpdateAsync in a detached thread and returns nothing, so "it did not
-- throw" says nothing about whether the data landed. MonetizationService must not tell Roblox
-- PurchaseGranted on an unconfirmed write: the Robux are already taken, the receipt would never be
-- delivered again, and the profile could come back without the purchase.
--
-- Waiting for any OnAfterSave is not enough either. ProfileStore serialises the payload inside the
-- UpdateAsync transform and fires OnAfterSave only when that call returns, so a save already in flight
-- when the caller mutated the data fires afterwards while carrying the OLDER snapshot. The token below
-- distinguishes the two: it is bumped before the save and compared against the data ProfileStore reports
-- as written, so only a write that actually contains the mutation counts.
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end
	local meta = profile.Data.Meta
	meta.SaveToken = (if type(meta.SaveToken) == "number" then meta.SaveToken else 0) + 1
	local token = meta.SaveToken
	local confirmed = false
	local connection = profile.OnAfterSave:Connect(function(lastSavedData: any)
		local saved = if type(lastSavedData) == "table" then lastSavedData.Meta else nil
		local savedToken = if type(saved) == "table" then saved.SaveToken else nil
		if type(savedToken) == "number" and savedToken >= token then
			confirmed = true
		end
	end)
	local started = log.try("Save " .. player.Name, profile.Save, profile)
	if started then
		local deadline = os.clock() + GameConfig.Server.SaveConfirmTimeoutSeconds
		while not confirmed and os.clock() < deadline do
			task.wait(GameConfig.Server.SaveConfirmPollSeconds)
			if not profile:IsActive() then
				break
			end
		end
	end
	connection:Disconnect()
	if not confirmed then
		log.warn(
			"save of %s was not confirmed within %ds: the caller must treat it as not persisted",
			player.Name,
			GameConfig.Server.SaveConfirmTimeoutSeconds
		)
	end
	return confirmed
end

function DataService.isActive(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive()
end

return DataService
