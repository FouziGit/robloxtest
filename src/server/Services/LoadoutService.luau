--!strict
-- LoadoutService: the single writer of ProfileData.Loadout and ProfileData.Unlocks. Grants the jutsus
-- a profile has earned (level gates of JutsuConfig.Unlock, every jutsu of an owned element), unlocks
-- Lightning at ProgressionConfig.LightningUnlockLevel and validates every SetLoadout.
--
-- The client only names jutsu ids: the slot budget, the duplicates and what is unlocked are decided
-- here. A refusal is replicated too, so the client never stays on a loadout the server did not accept.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ElementConfig = require(Shared.Config.ElementConfig)
local JutsuConfig = require(Shared.Config.JutsuConfig)
local Log = require(Shared.Util.Log)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Types = require(Shared.Types)

local log = Log.new("LoadoutService")

type ProfileData = Types.ProfileData
type ProfileSignal = { Connect: (self: ProfileSignal, fn: (player: Player, data: ProfileData) -> ()) -> any }
type LevelSignal = { Connect: (self: LevelSignal, fn: (player: Player, level: number) -> ()) -> any }
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	ProfileLoaded: ProfileSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type ProgressionApi = { LevelUp: LevelSignal }
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Progression: ProgressionApi,
}

local LOADOUT = ProgressionConfig.Loadout
local LIGHTNING_ELEMENT = "Lightning"
local LIGHTNING_LEVEL = ProgressionConfig.LightningUnlockLevel
local ELEMENT_NAME_KEYS = (ElementConfig.NameKeys :: any) :: { [string]: string? }
-- Strings has no dedicated unlock key; "{name} unlocked!" is the closest fit (see notes).
local UNLOCKED_KEY = "purchase.passGranted"

local LoadoutService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi

-- Adds `jutsuId` to the unlocks when it is missing and tells the player. Returns true when it was just
-- granted (the caller pushes "Unlocks" once for the whole batch).
local function grantJutsu(player: Player, data: ProfileData, jutsuId: string): boolean
	if table.find(data.Unlocks.Jutsus, jutsuId) ~= nil then
		return false
	end
	local def = JutsuConfig.ById[jutsuId]
	if def == nil then
		log.error("unknown jutsu %s for %s", jutsuId, player.Name)
		return false
	end
	table.insert(data.Unlocks.Jutsus, jutsuId)
	notify.send(player, UNLOCKED_KEY, { name = def.NameKey }, "Success", "LevelUp")
	return true
end

-- Grants every jutsu the profile has already earned: the level gates up to its current level and the
-- jutsus of every owned element. Catches up a profile that predates a roster change or comes from V1.
local function grantEarned(player: Player, data: ProfileData): number
	local granted = 0
	for level = 1, data.Progression.Level do
		for _, jutsuId in ipairs(JutsuConfig.unlocksForLevel(level)) do
			if grantJutsu(player, data, jutsuId) then
				granted += 1
			end
		end
	end
	for _, element in ipairs(data.Unlocks.Elements) do
		for _, jutsuId in ipairs(JutsuConfig.unlocksForElement(element)) do
			if grantJutsu(player, data, jutsuId) then
				granted += 1
			end
		end
	end
	return granted
end

-- Grants `elementId` and every jutsu it gates (the Lightning game pass, the level gate). Idempotent:
-- false when the element is already owned or unknown.
function LoadoutService.grantElement(player: Player, elementId: string): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("grantElement skipped for %s: profile not loaded", player.Name)
		return false
	end
	if not ElementConfig.isElement(elementId) then
		log.error("unknown element %s for %s", elementId, player.Name)
		return false
	end
	if table.find(data.Unlocks.Elements, elementId) ~= nil then
		return false
	end
	table.insert(data.Unlocks.Elements, elementId)
	local nameKey = ELEMENT_NAME_KEYS[elementId]
	if nameKey ~= nil then
		notify.send(player, UNLOCKED_KEY, { name = nameKey }, "Success", "LevelUp")
	end
	for _, jutsuId in ipairs(JutsuConfig.unlocksForElement(elementId)) do
		grantJutsu(player, data, jutsuId)
	end
	dataService.push(player, "Unlocks")
	log.info("%s unlocked the %s element", player.Name, elementId)
	return true
end

-- Validates and stores a loadout: at most the slots the profile owns, no duplicate, nothing locked.
function LoadoutService.setLoadout(player: Player, slots: { string }): boolean
	local data = dataService.get(player)
	if data == nil then
		log.warn("setLoadout skipped for %s: profile not loaded", player.Name)
		return false
	end
	local limit = math.min(LOADOUT.MaxSlots, LOADOUT.BaseSlots + data.Loadout.ExtraSlots)

	local function reject(reason: string): boolean
		log.warn("setLoadout rejected for %s: %s", player.Name, reason)
		notify.send(player, "loadout.invalid", nil, "Error", "Error")
		dataService.push(player, "Loadout")
		return false
	end

	if #slots > limit then
		return reject(string.format("%d ids for %d slots", #slots, limit))
	end
	local seen: { [string]: boolean } = {}
	for _, jutsuId in ipairs(slots) do
		if seen[jutsuId] then
			return reject("duplicate " .. jutsuId)
		end
		seen[jutsuId] = true
		if JutsuConfig.ById[jutsuId] == nil then
			return reject("unknown jutsu " .. jutsuId)
		end
		if table.find(data.Unlocks.Jutsus, jutsuId) == nil then
			return reject(jutsuId .. " is not unlocked")
		end
	end

	data.Loadout.Slots = table.clone(slots)
	dataService.push(player, "Loadout")
	notify.send(player, "loadout.saved", nil, "Success", "UiClick")
	log.info("%s saved a loadout of %d jutsu(s)", player.Name, #slots)
	return true
end

local function onLevelUp(player: Player, level: number)
	local data = dataService.get(player)
	if data == nil then
		return
	end
	local granted = 0
	for _, jutsuId in ipairs(JutsuConfig.unlocksForLevel(level)) do
		if grantJutsu(player, data, jutsuId) then
			granted += 1
		end
	end
	if granted > 0 then
		dataService.push(player, "Unlocks")
		log.info("%s unlocked %d jutsu(s) at level %d", player.Name, granted, level)
	end
	if level >= LIGHTNING_LEVEL then
		LoadoutService.grantElement(player, LIGHTNING_ELEMENT)
	end
end

local function onProfileLoaded(player: Player, data: ProfileData)
	if data.Progression.Level >= LIGHTNING_LEVEL then
		LoadoutService.grantElement(player, LIGHTNING_ELEMENT)
	end
	if grantEarned(player, data) > 0 then
		dataService.push(player, "Unlocks")
	end
end

function LoadoutService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
end

function LoadoutService.Start()
	dataService.ProfileLoaded:Connect(onProfileLoaded)
	progression.LevelUp:Connect(onLevelUp)
	registry.on("SetLoadout", function(player: Player, slots: { string })
		LoadoutService.setLoadout(player, slots)
	end)
	log.info("started (%d base slots, %d max)", LOADOUT.BaseSlots, LOADOUT.MaxSlots)
end

return LoadoutService
