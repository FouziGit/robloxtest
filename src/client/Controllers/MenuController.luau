--!strict
-- MenuController: opens and closes the full-screen menus (Menu, Settings, Battlepass, Play, Result,
-- Leaderboard, Quests, Daily, Loadout, Shop) built by the UI/screens modules. Screens are created
-- lazily with the controller dependencies they need, gameplay input is suspended while one is open,
-- and the Roblox menu (Escape) closes whatever is open.
--
-- The screens a player walks through form a stack (Shared.Pure.MenuStack, D-147): a screen that opens
-- another (its OnNavigate) stacks it on itself, so Back -- the band's button, or B on a gamepad through
-- InputController -- returns to it; the cross closes them all. Anything else that opens a screen (the HUD,
-- a hub prompt, a key, a match that ends) replaces the stack. `open` carries arguments to the screen's Open:
-- the Shop opened on its Folios tab.
--
-- Each screen owns its own open/close sound: its Open/Close guard on `Visible`, so they fire exactly
-- once per real transition, including on a screen-to-screen navigation. The controller plays none, so
-- a single UiOpen/UiClose is heard per transition whatever the entry point.
--
-- Matches drive two transitions: the screen in front is closed when a match starts (a suspended input
-- would make the countdown unplayable) and the result screen is opened when one ends. A portal that has just
-- moved the player closes it too (TravelController.Travelled): a circle takes whoever stands in it, menu open
-- or not, and nobody may arrive among the Forgers or before the Erasure with their input suspended.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Log = require(Shared.Util.Log)
local MenuStack = require(Shared.Pure.MenuStack)

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
	-- `args`: what the screen was opened with, from `open` or kept by the stack for Back.
	Open: (self: Screen, args: any?) -> (),
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
	HudController: any,
	TravelController: any,
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
local travelController: any
local screenDeps: { [string]: any }
local screens: { [string]: Screen } = {}
local stack = MenuStack.new()
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
	return MenuStack.depth(stack) > 0
end

-- Carries out a move of the stack: the screen that leaves closes before the one that arrives opens, and
-- gameplay input is suspended for exactly as long as a screen is open.
local function apply(move: MenuStack.Move)
	local leave = move.Leave
	if leave ~= nil then
		local screen = screens[leave.Id]
		if screen ~= nil then
			screen:Close()
		end
	end
	local arrive = move.Arrive
	if arrive ~= nil then
		local screen = screens[arrive.Id]
		if screen ~= nil then
			screen:Open(arrive.Args)
		end
	end
	inputController.setSuspended(MenuStack.depth(stack) > 0)
end

-- The screen is built before the stack records it, so a screen that cannot be made never enters it.
local function present(id: string, args: any?, fromScreen: boolean)
	if getScreen(id) == nil then
		return
	end
	apply(MenuStack.open(stack, id, args, fromScreen))
end

-- Opens `id` with `args` in place of whatever was open: the HUD, a hub prompt, a key, a match that ends.
function MenuController.open(id: string, args: any?)
	present(id, args, false)
end

-- What a screen calls to open another (its OnNavigate): on top of itself, so Back returns to it.
local function navigate(id: string, args: any?)
	present(id, args, true)
end

-- One screen back, or closed when it was the first.
function MenuController.back()
	apply(MenuStack.back(stack))
end

-- Whether Back has somewhere to go: what a screen's band reads to show its button.
function MenuController.canGoBack(): boolean
	return MenuStack.depth(stack) > 1
end

function MenuController.close()
	apply(MenuStack.clear(stack))
end

-- Opens `id` (Menu by default); closes when that screen is already the open one.
function MenuController.toggle(id: string?)
	local target = id or DEFAULT_SCREEN
	local top = MenuStack.top(stack)
	if (top ~= nil and top.Id == target) or (id == nil and top ~= nil) then
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
	travelController = deps.TravelController
	screenDeps = {
		Localize = deps.Localize,
		ClientData = deps.ClientData,
		RemoteClient = deps.RemoteClient,
		InputController = deps.InputController,
		SoundController = deps.SoundController,
		HudController = deps.HudController,
		-- Queue and match state for the Play and Result screens; they never touch those remotes directly.
		MatchController = deps.MatchController,
		OnClose = MenuController.close,
		OnNavigate = navigate,
		-- For the band's way back (Panel's OnBack and ShowBack).
		OnBack = MenuController.back,
		CanGoBack = MenuController.canGoBack,
	}
end

function MenuController.Start()
	GuiService.MenuOpened:Connect(MenuController.close)
	matchController.MatchChanged:Connect(onMatchChanged)
	matchController.MatchEnded:Connect(onMatchEnded)
	travelController.Travelled:Connect(MenuController.close)
	log.info("started")
end

return MenuController
