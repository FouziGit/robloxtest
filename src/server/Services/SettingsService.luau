--!strict
-- SettingsService: validates and persists keybinds and audio / camera settings. Keybinds are
-- checked against InputConfig (complete, whitelisted keys, rebindable actions only, no duplicates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local QualityConfig = require(Shared.Config.QualityConfig)
local Types = require(Shared.Types)

local log = Log.new("SettingsService")

export type BindKind = "Keyboard" | "Gamepad"
export type SettingsPayload = { MusicVolume: number, SfxVolume: number, CameraShake: boolean, Quality: string }

type ProfileData = Types.ProfileData
type KeybindMap = Types.KeybindMap
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type Registry = { on: (name: string, handler: (player: Player, ...any) -> ()) -> () }
type Deps = { Registry: Registry, DataService: DataApi, Notify: NotifyApi }

local SettingsService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi

local rebindable: { [string]: boolean } = {}
for _, action in ipairs(InputConfig.Rebindable) do
	rebindable[action] = true
end

-- Returns a clean copy of `incoming` (known actions only) or nil with the rejection reason.
local function validateKeybinds(
	current: KeybindMap,
	incoming: { [string]: string },
	kind: BindKind
): (KeybindMap?, string?)
	local allowed = if kind == "Keyboard" then InputConfig.AllowedKeyboard else InputConfig.AllowedGamepad
	for action in pairs(incoming) do
		if not InputConfig.isAction(action) then
			return nil, "unknown action " .. action
		end
	end

	local clean: KeybindMap = {}
	local seen: { [string]: boolean } = {}
	for _, action in ipairs(InputConfig.Actions) do
		local key = incoming[action]
		if key == nil then
			return nil, "missing action " .. action
		end
		if allowed[key] ~= true then
			return nil, "key " .. key .. " not allowed for " .. kind
		end
		if not rebindable[action] and key ~= current[action] then
			return nil, "action " .. action .. " is not rebindable"
		end
		if seen[key] then
			return nil, "key " .. key .. " bound twice"
		end
		seen[key] = true
		clean[action] = key
	end
	return clean, nil
end

local function onUpdateKeybinds(player: Player, kind: BindKind, incoming: { [string]: string })
	local data = dataService.get(player)
	if data == nil then
		log.warn("keybinds rejected for %s: profile not loaded", player.Name)
		notify.send(player, "settings.saveFailed", nil, "Error")
		return
	end
	local current = if kind == "Keyboard" then data.Settings.Keyboard else data.Settings.Gamepad
	local clean, reason = validateKeybinds(current, incoming, kind)
	if clean == nil then
		log.warn("%s keybinds rejected for %s: %s", kind, player.Name, tostring(reason))
		notify.send(player, "settings.saveFailed", nil, "Error")
		dataService.push(player, "Settings") -- lets the client leave its "saving" state
		return
	end
	if kind == "Keyboard" then
		data.Settings.Keyboard = clean
	else
		data.Settings.Gamepad = clean
	end
	dataService.push(player, "Settings")
	notify.send(player, "settings.saved", nil, "Success", "UiClick")
	log.info("%s keybinds saved for %s", kind, player.Name)
end

local function onUpdateSettings(player: Player, settings: SettingsPayload)
	local data = dataService.get(player)
	if data == nil then
		log.warn("settings rejected for %s: profile not loaded", player.Name)
		return
	end
	data.Settings.MusicVolume = settings.MusicVolume
	data.Settings.SfxVolume = settings.SfxVolume
	data.Settings.CameraShake = settings.CameraShake
	-- The remote's Guard already refuses anything that is not a tier name (Shared/Remotes), so this is
	-- the belt to that brace: a profile is never written a tier the renderer cannot resolve.
	if QualityConfig.isTier(settings.Quality) then
		data.Settings.Quality = settings.Quality
	end
	dataService.push(player, "Settings")
end

function SettingsService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
end

function SettingsService.Start()
	registry.on("UpdateKeybinds", onUpdateKeybinds)
	registry.on("UpdateSettings", onUpdateSettings)
	log.info("started")
end

return SettingsService
