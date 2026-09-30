--!strict
-- DataService: the single owner of player profiles (ProfileStore). Loads, migrates, replicates and
-- releases profiles. Other services mutate `DataService.get(player)` in place and call `push`.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local DataMigration = require(script.Parent.Parent.Pure.DataMigration)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local InputConfig = require(Shared.Config.InputConfig)
local LegacyNames = require(script.Parent.Parent.Pure.LegacyNames)
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
-- Fired at the final write of a session, while the profile is STILL loaded: whatever a listener writes
-- into `data` goes out with that write, and it is the last thing that can ever be persisted for the player
-- on this server. It comes whatever ended the session -- the player leaving, or another server taking the
-- profile before this one saw them go (docs/QA.md R4) -- and never when the server is closing: a shutdown
-- is nobody walking out (R3). MatchService debits the forfeit of an abandoned ranked match here, which is
-- what used to make quitting free.
DataService.BeforeRelease = Signal.new() -- (player: Player, data: ProfileData)

-- ProfileStore's reasons for a session's final write (Profile.OnLastSave).
local ENDED_HERE = "Manual" -- this server ended it: the player left
local ENDED_BY_SHUTDOWN = "Shutdown"
-- How long a departure waits before its session ends (see onPlayerRemoving).
local LEAVE_GRACE_SECONDS = GameConfig.Server.LeaveGraceSeconds

local registry -- RemoteRegistry
-- The language each player reads a kick's reason in (LocaleService).
local locale: { of: (player: Player) -> string }
local store
local profiles: { [Player]: any } = {} -- ProfileStore Profile objects
local loadedSignals: { [Player]: { any } } = {}
-- Set by game:BindToClose: from then on no session end is a player leaving (DataService.isClosing).
local closing = false
-- The reason ProfileStore gave for the final write of each session, read when the session ends.
local lastSaveReasons: { [Player]: string } = {}
-- Sessions of players who left, still loaded until the grace runs out: user id -> the session.
type Hold = { Profile: any, Timer: thread }
local held: { [number]: Hold } = {}

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
		Cosmetics = { Owned = {}, Equipped = {}, Waived = {} },
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
			Daily = { PeriodKey = "", Progress = {}, Claimed = {}, Swaps = {} },
			Weekly = { PeriodKey = "", Progress = {}, Claimed = {}, Swaps = {} },
		},
		Daily = {
			LastClaimDay = 0,
			Streak = 0,
			FirstWinDay = 0,
			PremiumBonusDay = 0,
			ForgerDay = 0,
			ForgerFolios = 0,
			PracticeDay = 0,
			PracticePaid = 0,
			PracticeLastPaidAt = 0,
			TrialDay = 0,
			TrialKills = 0,
			TrialFolios = 0,
		},
		Milestones = {},
		Drills = {},
		ExLibris = {},
		Purchases = { Receipts = {}, ProductCounts = {} },
		Passes = {},
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
		Meta = {
			FirstJoin = 0,
			LastJoin = 0,
			SessionCount = 0,
			LegacyImported = false,
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
		player:Kick(Strings.t(key, nil, locale.of(player)))
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

-- The final write of a session is about to go out: ProfileStore fires this before its last save, for every
-- way a session can end but a stolen one, and the data it then writes is whatever the listeners left.
local function onLastSave(player: Player, profile: any, reason: string)
	lastSaveReasons[player] = reason
	if reason == ENDED_BY_SHUTDOWN or DataService.isClosing() then
		log.info("%s's session ends with the server: nothing is settled as a departure", player.Name)
		return
	end
	-- Inside log.try: a listener that throws must never cost the session its release, which would leave the
	-- key locked until ProfileStore times out.
	log.try("BeforeRelease " .. player.Name, function()
		DataService.BeforeRelease:Fire(player, profile.Data)
	end)
end

local function onSessionEnd(player: Player, profile: any)
	if profiles[player] == profile then
		profiles[player] = nil
	end
	local hold = held[player.UserId]
	if hold ~= nil and hold.Profile == profile then
		-- Ended before the grace ran out: a shutdown, or another server that took the profile.
		held[player.UserId] = nil
		task.cancel(hold.Timer)
	end
	loadedSignals[player] = nil
	local reason = lastSaveReasons[player]
	lastSaveReasons[player] = nil
	DataService.ProfileReleased:Fire(player)
	-- Only a session another server took is news to the player (reason "External", or none at all when the
	-- other server stole it without a last save). A session this server ended belongs to a player who has
	-- already gone, and a shutdown's own message is Roblox's to show: telling them their session was opened
	-- elsewhere would be false (docs/QA.md R15).
	if reason ~= ENDED_HERE and reason ~= ENDED_BY_SHUTDOWN and not DataService.isClosing() then
		kick(player, "kick.sessionElsewhere")
	end
end

-- Ends a departed player's session once the grace ran out. Nothing to do when a shutdown or another server
-- ended it first: EndSession is a no-op on a session that is no longer active.
local function release(userId: number, profile: any)
	local hold = held[userId]
	if hold == nil or hold.Profile ~= profile then
		return
	end
	-- Cleared before EndSession: ending the session reaches onSessionEnd from inside this very thread.
	held[userId] = nil
	profile:EndSession()
end

local function loadProfile(player: Player)
	local hold = held[player.UserId]
	if hold ~= nil then
		-- Back on this server before the grace of the last visit ran out. That session ends now, exactly as it
		-- would have: ProfileStore refuses to open a key that is still loaded here.
		held[player.UserId] = nil
		task.cancel(hold.Timer)
		hold.Profile:EndSession()
	end
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
	profile.OnLastSave:Connect(function(reason: string)
		onLastSave(player, profile, reason)
	end)
	profile.OnSessionEnd:Connect(function()
		onSessionEnd(player, profile)
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

-- A departure keeps its session loaded for LEAVE_GRACE_SECONDS before ending it. A shutdown removes the
-- players a moment before game:BindToClose says the server is closing -- in Studio always, on a live server
-- when the race goes that way -- and a session ended on the spot would settle that departure as a player
-- walking out (docs/QA.md R3). Held, it is ended by the shutdown itself if one follows, and otherwise by the
-- grace; either way its final write carries what BeforeRelease settled.
local function onPlayerRemoving(player: Player)
	local waiters = loadedSignals[player]
	loadedSignals[player] = nil
	if waiters ~= nil then
		for _, thread in ipairs(waiters) do
			task.spawn(thread, nil)
		end
	end
	local profile = profiles[player]
	if profile == nil then
		return
	end
	if DataService.isClosing() then
		profile:EndSession()
		return
	end
	held[player.UserId] = {
		Profile = profile,
		Timer = task.delay(LEAVE_GRACE_SECONDS, release, player.UserId, profile),
	}
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

function DataService.Init(deps: { Registry: any, Locale: any })
	registry = deps.Registry
	locale = deps.Locale
	store = ProfileStore.New(STORE_NAME, storeTemplate())
	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" then
		log.info("DataStore state: %s (Studio without API access saves nothing)", ProfileStore.DataStoreState)
	end
end

function DataService.Start()
	-- Bound here, at Start, rather than read from ProfileStore alone: ProfileStore binds its own close only
	-- once its DataStore check has answered, which is a web call after the server started.
	game:BindToClose(function()
		closing = true
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	log.info("started")
end

-- True once the server has started shutting down (game:BindToClose). Nothing that happens from then on is
-- a player's choice: MatchService neither debits nor awards a forfeit.
function DataService.isClosing(): boolean
	return closing or ProfileStore.IsClosing
end

-- Live profile data (mutate in place, then push the changed section). Still answers for a player who left,
-- until the grace of onPlayerRemoving ends their session.
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
