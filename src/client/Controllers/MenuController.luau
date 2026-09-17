--!strict
-- MenuController: opens and closes the full-screen menus (Menu, Settings, Battlepass) built by the
-- UI/screens modules. Screens are created lazily with the controller dependencies they need, gameplay
-- input is suspended while one is open, and the Roblox menu (Escape) closes whatever is open.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")

local Log = require(Shared.Util.Log)

local log = Log.new("MenuController")

export type ScreenId = "Menu" | "Settings" | "Battlepass"

type Screen = {
	Instance: Instance,
	Open: (self: Screen) -> (),
	Close: (self: Screen) -> (),
	Destroy: (self: Screen) -> (),
	Visible: boolean,
}
type Deps = { Localize: any, ClientData: any, RemoteClient: any, InputController: any, SoundController: any }

local SCREENS_FOLDER = "screens"
local MODULE_NAMES: { [string]: string } = {
	Menu = "MenuScreen",
	Settings = "SettingsScreen",
	Battlepass = "BattlepassScreen",
}
local DEFAULT_SCREEN: ScreenId = "Menu"
local OPEN_SFX = "UiOpen"
local CLOSE_SFX = "UiClose"

local MenuController = {}

local inputController: any
local soundController: any
local screenDeps: { [string]: any }
local screens: { [string]: Screen } = {}
local current: string? = nil

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
	soundController.play(OPEN_SFX)
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
	soundController.play(CLOSE_SFX)
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

function MenuController.Init(deps: Deps)
	inputController = deps.InputController
	soundController = deps.SoundController
	screenDeps = {
		Localize = deps.Localize,
		ClientData = deps.ClientData,
		RemoteClient = deps.RemoteClient,
		InputController = deps.InputController,
		SoundController = deps.SoundController,
		OnClose = MenuController.close,
		OnNavigate = MenuController.open,
	}
end

function MenuController.Start()
	GuiService.MenuOpened:Connect(MenuController.close)
	log.info("started")
end

return MenuController
