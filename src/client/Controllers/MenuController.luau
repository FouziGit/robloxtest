--!strict
-- MenuController: opens and closes the full-screen menus (Menu, Settings, Battlepass, Play, Result,
-- Leaderboard, Quests, Daily, Loadout, Shop) built by the UI/screens modules. Screens are created
-- lazily with the controller dependencies they need, gameplay input is suspended while one is open,
-- and the Roblox menu (Escape) closes whatever is open.
--
-- Each screen owns its own open/close sound: its Open/Close guard on `Visible`, so they fire exactly
-- once per real transition, including on a screen-to-screen navigation. The controller plays none, so
-- a single UiOpen/UiClose is heard per transition whatever the entry point.
--
-- Matches drive two transitions: the screen in front is closed when a match starts (a suspended input
-- would make the countdown unplayable) and the result screen is opened when one ends.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Log = require(Shared.Util.Log)

local log = Log.new("MenuController")

export type ScreenId =
	"Menu"
	| "Settings"
	| "Battlepass"
	| "Play"
	| "Result"
	| "Leaderboard"
	| "Quests"
	| "Daily"
	| "Loadout"
	| "Shop"

type Screen = {
	Instance: Instance,
	Open: (self: Screen) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
	Visible: boolean,
}
type Deps = {
	Localize: any,
	ClientData: any,
	RemoteClient: any,
	InputController: any,
	SoundController: any,
	MatchController: any,
}

local SCREENS_FOLDER = "screens"
local MODULE_NAMES: { [string]: string } = {
	Menu = "MenuScreen",
	Settings = "SettingsScreen",
	Battlepass = "BattlepassScreen",
	Play = "PlayScreen",
	Result = "ResultScreen",
	Leaderboard = "LeaderboardScreen",
	Quests = "QuestsScreen",
	Daily = "DailyScreen",
	Loadout = "LoadoutScreen",
	Shop = "ShopScreen",
}
local DEFAULT_SCREEN: ScreenId = "Menu"
local RESULT_SCREEN: ScreenId = "Result"

local MenuController = {}

local inputController: any
local matchController: any
local screenDeps: { [string]: any }
local screens: { [string]: Screen } = {}
local current: string? = nil
local inMatch = false

local function findModule(id: string): ModuleScript?
	local moduleName = MODULE_NAMES[id]
	if moduleName == nil then
		log.warn("unknown screen id %s", id)
		return nil
	end
	local folder: Instance? = UI:FindFirstChild(SCREENS_FOLDER)
	if folder == nil then
		log.warn("UI.%s folder missing: cannot open %s", SCREENS_FOLDER, id)
		return nil
	end
	local module: Instance? = folder:FindFirstChild(moduleName)
	if module == nil or not module:IsA("ModuleScript") then
		log.warn("screen module %s missing under UI.%s", moduleName, SCREENS_FOLDER)
		return nil
	end
	return module
end

local function getScreen(id: string): Screen?
	local existing = screens[id]
	if existing ~= nil then
		return existing
	end
	local module = findModule(id)
	if module == nil then
		return nil
	end
	local ok, result = pcall(function(): Screen
		local class = (require :: any)(module)
		return class.new(screenDeps)
	end)
	if not ok then
		log.warn("screen %s could not be created: %s", id, tostring(result))
		return nil
	end
	local screen = result :: Screen
	screens[id] = screen
	return screen
end

function MenuController.isOpen(): boolean
	return current ~= nil
end

function MenuController.open(id: string)
	if current == id then
		return
	end
	local screen = getScreen(id)
	if screen == nil then
		return
	end
	local previous = current
	if previous ~= nil then
		local previousScreen = screens[previous]
		if previousScreen ~= nil then
			previousScreen:Close()
		end
	end
	current = id
	screen:Open()
	if previous == nil then
		inputController.setSuspended(true)
	end
end

function MenuController.close()
	local id = current
	if id == nil then
		return
	end
	current = nil
	local screen = screens[id]
	if screen ~= nil then
		screen:Close()
	end
	inputController.setSuspended(false)
end

-- Opens `id` (Menu by default); closes when that screen is already the open one.
function MenuController.toggle(id: string?)
	local target = id or DEFAULT_SCREEN
	if current == target or (id == nil and current ~= nil) then
		MenuController.close()
	else
		MenuController.open(target)
	end
end

-- A match starting takes the screen away (only on the nil -> snapshot transition, so the player can
-- still open the menu mid-match); a match ending brings the result screen in front of it.
local function onMatchChanged(snapshot: any)
	local active = snapshot ~= nil
	if active and not inMatch then
		MenuController.close()
	end
	inMatch = active
end

local function onMatchEnded(outcome: any)
	if outcome == nil then
		return
	end
	MenuController.open(RESULT_SCREEN)
end

function MenuController.Init(deps: Deps)
	inputController = deps.InputController
	matchController = deps.MatchController
	screenDeps = {
		Localize = deps.Localize,
		ClientData = deps.ClientData,
		RemoteClient = deps.RemoteClient,
		InputController = deps.InputController,
		SoundController = deps.SoundController,
		-- Queue and match state for the Play and Result screens; they never touch those remotes directly.
		MatchController = deps.MatchController,
		OnClose = MenuController.close,
		OnNavigate = MenuController.open,
	}
end

function MenuController.Start()
	GuiService.MenuOpened:Connect(MenuController.close)
	matchController.MatchChanged:Connect(onMatchChanged)
	matchController.MatchEnded:Connect(onMatchEnded)
	log.info("started")
end

return MenuController
