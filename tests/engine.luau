--!strict
-- A pretend engine, just deep enough to run the interface's own modules under Lune: instances with a
-- parent, children and the signals the interface listens to; a Heartbeat and a clock the test advances by
-- hand; task.delay on that clock; and require by the paths Rojo gives the modules, so `script.Parent.Motion`
-- and `Shared.Config.FeelConfig` load the files in src/. The datatypes (UDim2, Color3, Vector2, Enum...) are
-- Lune's, which are the engine's own.
--
-- Most of the interface's gates read its source, because Lune has no engine. That cannot see an order of
-- events: a callback that restarts a spring the loop is about to drop, a splat handed back after its screen
-- destroyed it. Those are what this runs. A module is given what it asks for and nothing else: an unknown
-- service or a module that is not on disk is an error, so a spec cannot pass on code it never ran.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local Engine = {}

----------------------------------------------------------------
-- Signals
----------------------------------------------------------------

local SignalClass = {}
SignalClass.__index = SignalClass
local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }
export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	count: (self: Signal) -> number,
}

function Engine.signal(): Signal
	return setmetatable({ _handlers = {} }, SignalClass) :: any
end

function SignalClass.Connect(self: any, fn: (...any) -> ()): Connection
	local connection = setmetatable({ Connected = true, _signal = self, _fn = fn }, ConnectionClass)
	table.insert(self._handlers, connection)
	return connection :: any
end

function SignalClass.Once(self: any, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = SignalClass.Connect(self, function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function SignalClass.Fire(self: any, ...: any)
	for _, connection in ipairs(table.clone(self._handlers)) do
		if connection.Connected then
			connection._fn(...)
		end
	end
end

-- How many handlers are connected: what a leak is counted in.
function SignalClass.count(self: any): number
	return #self._handlers
end

function SignalClass.disconnectAll(self: any)
	for _, connection in ipairs(table.clone(self._handlers)) do
		connection:Disconnect()
	end
end

function ConnectionClass.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index ~= nil then
		table.remove(handlers, index)
	end
end

----------------------------------------------------------------
-- Instances
----------------------------------------------------------------

-- Which classes answer IsA for the abstract ones the interface asks about.
local GUI_OBJECTS = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	ViewportFrame = true,
}
local ABSTRACT: { [string]: { [string]: boolean } } = {
	GuiObject = GUI_OBJECTS,
	GuiButton = { TextButton = true, ImageButton = true },
	LayerCollector = { ScreenGui = true, BillboardGui = true, SurfaceGui = true },
	BasePart = { Part = true, MeshPart = true, WedgePart = true, SpawnLocation = true },
	ValueBase = { NumberValue = true, StringValue = true, BoolValue = true, IntValue = true, ObjectValue = true },
}

-- Whether the pad may select a class unless told otherwise, as the engine answers it (the reflection database Lune
-- builds its instances from): a button, a text box and a scrolling frame are selectable, a frame or a label is not.
local selectableByDefault: { [string]: boolean } = {}
local function selectable(className: string): boolean
	local known = selectableByDefault[className]
	if known == nil then
		known = roblox.Instance.new(className).Selectable == true
		selectableByDefault[className] = known
	end
	return known :: boolean
end

local function defaults(className: string): { [string]: any }
	local values: { [string]: any } = {}
	if GUI_OBJECTS[className] then
		values.Visible = true
		values.Size = roblox.UDim2.new()
		values.Position = roblox.UDim2.new()
		values.AnchorPoint = roblox.Vector2.zero
		values.Rotation = 0
		values.ZIndex = 1
		values.LayoutOrder = 0
		values.BackgroundTransparency = 0
		values.AbsoluteSize = roblox.Vector2.zero
		values.AbsolutePosition = roblox.Vector2.zero
		values.Selectable = selectable(className)
		values.Active = false
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		values.Text = ""
	end
	if className == "ScrollingFrame" then
		values.CanvasPosition = roblox.Vector2.zero
		values.CanvasSize = roblox.UDim2.new()
		values.AbsoluteCanvasSize = roblox.Vector2.zero
		values.AbsoluteWindowSize = roblox.Vector2.zero
	end
	if className == "ScreenGui" then
		values.Enabled = true
	elseif className == "CanvasGroup" then
		-- What a screen's exit fades from.
		values.GroupTransparency = 0
	elseif className == "UIScale" then
		values.Scale = 1
	elseif className == "UIGradient" then
		values.Offset = roblox.Vector2.zero
		values.Rotation = 0
		values.Enabled = true
	elseif className == "UIPadding" then
		values.PaddingTop = roblox.UDim.new()
		values.PaddingBottom = roblox.UDim.new()
		values.PaddingLeft = roblox.UDim.new()
		values.PaddingRight = roblox.UDim.new()
	elseif className == "UIListLayout" then
		values.Padding = roblox.UDim.new()
	elseif className == "UISizeConstraint" then
		values.MinSize = roblox.Vector2.zero
		values.MaxSize = roblox.Vector2.new(math.huge, math.huge)
	elseif className == "UIStroke" then
		values.Thickness = 1
		values.Transparency = 0
	elseif ABSTRACT.ValueBase[className] then
		values.Value = if className == "NumberValue" or className == "IntValue" then 0 else nil
	end
	return values
end

type Data = {
	ClassName: string,
	Name: string,
	Parent: any,
	Children: { any },
	Destroyed: boolean,
	Props: { [string]: any },
	Attributes: { [string]: any },
	Signals: { [string]: any },
	PropertySignals: { [string]: any },
}

local dataOf: { [any]: Data } = setmetatable({}, { __mode = "k" }) :: any
local InstanceMeta: any = {}

local function signalOf(data: Data, name: string): any
	local signal = data.Signals[name]
	if signal == nil then
		signal = Engine.signal()
		data.Signals[name] = signal
	end
	return signal
end

local function propertySignal(data: Data, property: string): any
	local signal = data.PropertySignals[property]
	if signal == nil then
		signal = Engine.signal()
		data.PropertySignals[property] = signal
	end
	return signal
end

local function descendants(instance: any, out: { any })
	for _, child in ipairs(dataOf[instance].Children) do
		table.insert(out, child)
		descendants(child, out)
	end
end

local function fireAncestry(instance: any)
	local all = { instance }
	descendants(instance, all)
	local parent = dataOf[instance].Parent
	for _, each in ipairs(all) do
		signalOf(dataOf[each], "AncestryChanged"):Fire(instance, parent)
	end
end

local function setParent(instance: any, parent: any)
	local data = dataOf[instance]
	if data.Destroyed then
		error(
			("The Parent property of %s is locked, current parent: NULL, new parent %s"):format(
				data.Name,
				if parent ~= nil then dataOf[parent].Name else "NULL"
			),
			3
		)
	end
	if data.Parent == parent then
		return
	end
	local old = data.Parent
	if old ~= nil then
		local siblings = dataOf[old].Children
		local index = table.find(siblings, instance)
		if index ~= nil then
			table.remove(siblings, index)
		end
	end
	data.Parent = parent
	if parent ~= nil then
		table.insert(dataOf[parent].Children, instance)
	end
	propertySignal(data, "Parent"):Fire()
	fireAncestry(instance)
	if parent ~= nil then
		signalOf(dataOf[parent], "ChildAdded"):Fire(instance)
		-- Every ancestor hears of the instance and of everything it brings with it, as the engine tells them.
		local arrived = { instance }
		descendants(instance, arrived)
		local ancestor = parent
		while ancestor ~= nil do
			for _, each in ipairs(arrived) do
				signalOf(dataOf[ancestor], "DescendantAdded"):Fire(each)
			end
			ancestor = dataOf[ancestor].Parent
		end
	end
end

local Methods: { [string]: any } = {}
-- Each world's services, by its DataModel.
local servicesOf: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

function Methods.GetService(self: any, name: string): any
	local services = servicesOf[self]
	if services == nil then
		error("GetService is the DataModel's", 2)
	end
	local service = services[name]
	if service == nil then
		error(("the spec gives no %s: add it to the world's Services"):format(name), 2)
	end
	return service
end

function Methods.IsA(self: any, className: string): boolean
	local own = dataOf[self].ClassName
	if own == className or className == "Instance" then
		return true
	end
	local members = ABSTRACT[className]
	return members ~= nil and members[own] == true
end

function Methods.IsDescendantOf(self: any, ancestor: any): boolean
	local parent = dataOf[self].Parent
	while parent ~= nil do
		if parent == ancestor then
			return true
		end
		parent = dataOf[parent].Parent
	end
	return false
end

function Methods.FindFirstAncestorOfClass(self: any, className: string): any
	local parent = dataOf[self].Parent
	while parent ~= nil do
		if dataOf[parent].ClassName == className then
			return parent
		end
		parent = dataOf[parent].Parent
	end
	return nil
end

function Methods.FindFirstAncestorWhichIsA(self: any, className: string): any
	local parent = dataOf[self].Parent
	while parent ~= nil do
		if Methods.IsA(parent, className) then
			return parent
		end
		parent = dataOf[parent].Parent
	end
	return nil
end

function Methods.FindFirstChild(self: any, name: string, recursive: boolean?): any
	for _, child in ipairs(dataOf[self].Children) do
		if dataOf[child].Name == name then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(dataOf[self].Children) do
			local found = Methods.FindFirstChild(child, name, true)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

function Methods.FindFirstChildOfClass(self: any, className: string): any
	for _, child in ipairs(dataOf[self].Children) do
		if dataOf[child].ClassName == className then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildWhichIsA(self: any, className: string, recursive: boolean?): any
	for _, child in ipairs(dataOf[self].Children) do
		if Methods.IsA(child, className) then
			return child
		end
	end
	if recursive then
		for _, child in ipairs(dataOf[self].Children) do
			local found = Methods.FindFirstChildWhichIsA(child, className, true)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

-- A spec cannot yield: a child that is not there yet is nil at once when the caller gave a timeout (the
-- engine's answer once it runs out), and an error when it did not (the engine would wait forever).
function Methods.WaitForChild(self: any, name: string, timeout: number?): any
	local child = Methods.FindFirstChild(self, name)
	if child == nil and timeout == nil then
		error(("%s has no child %s, and nothing in a spec will ever add it"):format(dataOf[self].Name, name), 2)
	end
	return child
end

function Methods.GetChildren(self: any): { any }
	return table.clone(dataOf[self].Children)
end

function Methods.GetDescendants(self: any): { any }
	local all = {}
	descendants(self, all)
	return all
end

function Methods.GetFullName(self: any): string
	local names = {}
	local current = self
	while current ~= nil do
		table.insert(names, 1, dataOf[current].Name)
		current = dataOf[current].Parent
	end
	return table.concat(names, ".")
end

function Methods.GetPropertyChangedSignal(self: any, property: string): any
	return propertySignal(dataOf[self], property)
end

function Methods.GetAttribute(self: any, name: string): any
	return dataOf[self].Attributes[name]
end

function Methods.SetAttribute(self: any, name: string, value: any)
	dataOf[self].Attributes[name] = value
end

function Methods.ClearAllChildren(self: any)
	for _, child in ipairs(table.clone(dataOf[self].Children)) do
		Methods.Destroy(child)
	end
end

-- The engine's order: Destroying first, then the children, the parent set to nil and locked, and every
-- connection to the instance's own signals cut.
function Methods.Destroy(self: any)
	local data = dataOf[self]
	if data.Destroyed then
		return
	end
	signalOf(data, "Destroying"):Fire()
	for _, child in ipairs(table.clone(data.Children)) do
		Methods.Destroy(child)
	end
	setParent(self, nil)
	data.Destroyed = true
	for _, signal in pairs(data.Signals) do
		signal:disconnectAll()
	end
	for _, signal in pairs(data.PropertySignals) do
		signal:disconnectAll()
	end
end

local SIGNALS = {
	Destroying = true,
	AncestryChanged = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	Changed = true,
	Activated = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseEnter = true,
	MouseLeave = true,
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	SelectionGained = true,
	SelectionLost = true,
	PromptShown = true,
	PromptHidden = true,
	Triggered = true,
	Touched = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	Died = true,
	Ended = true,
	JumpRequest = true,
	LastInputTypeChanged = true,
	GamepadConnected = true,
	GamepadDisconnected = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	MenuOpened = true,
}

InstanceMeta.__index = function(self: any, key: string): any
	local method = Methods[key]
	if method ~= nil then
		return method
	end
	local data = dataOf[self]
	if key == "ClassName" or key == "Name" or key == "Parent" then
		return (data :: any)[key]
	end
	if SIGNALS[key] then
		return signalOf(data, key)
	end
	return data.Props[key]
end

InstanceMeta.__newindex = function(self: any, key: string, value: any)
	local data = dataOf[self]
	if key == "Parent" then
		setParent(self, value)
		return
	end
	-- A spec that hands an instance its own signal (a kill zone's Touched) reads back the one it handed.
	if SIGNALS[key] then
		data.Signals[key] = value
		return
	end
	if key == "Name" then
		data.Name = value
		propertySignal(data, key):Fire()
		return
	end
	if data.Props[key] == value then
		return
	end
	data.Props[key] = value
	propertySignal(data, key):Fire()
	if ABSTRACT.ValueBase[data.ClassName] and key == "Value" then
		signalOf(data, "Changed"):Fire(value)
	else
		signalOf(data, "Changed"):Fire(key)
	end
end

InstanceMeta.__tostring = function(self: any): string
	return dataOf[self].Name
end

function Engine.instance(className: string, parent: any?): any
	local instance = setmetatable({}, InstanceMeta)
	dataOf[instance] = {
		ClassName = className,
		Name = className,
		Parent = nil,
		Children = {},
		Destroyed = false,
		Props = defaults(className),
		Attributes = {},
		Signals = {},
		PropertySignals = {},
	}
	if parent ~= nil then
		setParent(instance, parent)
	end
	return instance
end

-- True once Destroy has run on `instance`: what the engine shows as a locked Parent.
function Engine.destroyed(instance: any): boolean
	return dataOf[instance].Destroyed
end

-- The engine's typeof, for the fakes as well as Lune's datatypes.
local function typeOf(value: any): string
	if type(value) == "table" then
		local meta = getmetatable(value)
		if meta == InstanceMeta then
			return "Instance"
		elseif meta == SignalClass then
			return "RBXScriptSignal"
		elseif meta == ConnectionClass then
			return "RBXScriptConnection"
		end
	end
	return typeof(value)
end

----------------------------------------------------------------
-- Module paths, as Rojo lays them out (default.project.json)
----------------------------------------------------------------

local PathMeta: any = {}
local pathOf: { [any]: string } = setmetatable({}, { __mode = "k" }) :: any

-- Theme, and the client's reader of how the player plays, which the bootstrap hands it (Engine.world's load).
local THEME = "src/ui/Theme"
local INPUT_MODE = "src/client/Controllers/InputMode"

-- ReplicatedStorage's children, and where they come from on disk.
local REPLICATED = { Shared = "src/shared", UI = "src/ui", Packages = "Packages" }
local REPLICATED_ROOT = "<ReplicatedStorage>"

local function pathNode(path: string): any
	local node = setmetatable({}, PathMeta)
	pathOf[node] = path
	return node
end

local function childPath(path: string, name: string): string
	if path == REPLICATED_ROOT then
		local mapped = REPLICATED[name]
		if mapped == nil then
			error(("ReplicatedStorage has no %s in this project"):format(name), 3)
		end
		return mapped
	end
	return path .. "/" .. name
end

PathMeta.__index = function(node: any, key: string): any
	local path = pathOf[node]
	if key == "Parent" then
		return pathNode(string.match(path, "^(.*)/[^/]+$") or REPLICATED_ROOT)
	elseif key == "Name" then
		return string.match(path, "([^/]+)$")
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(self: any, name: string): any
			return pathNode(childPath(pathOf[self], name))
		end
	elseif key == "IsA" then
		-- A path is a ModuleScript when a module is on disk there: how MenuController checks a screen it found.
		return function(self: any, className: string): boolean
			local at = pathOf[self]
			return className == "ModuleScript" and (fs.isFile(at .. ".luau") or fs.isFile(at .. "/init.luau"))
		end
	end
	return pathNode(childPath(path, key))
end

local function sourceOf(path: string): string?
	for _, suffix in ipairs({ ".luau", ".lua", "/init.luau", "/init.lua" }) do
		if fs.isFile(path .. suffix) then
			return fs.readFile(path .. suffix)
		end
	end
	return nil
end

----------------------------------------------------------------
-- The world: one engine, its clock, and the modules loaded in it
----------------------------------------------------------------

-- The player's accessibility answers (src/ui/UiPrefs) at Roblox's defaults, and a silent UiSound: what every
-- interface module reads. A spec passes its own fields to change one.
function Engine.interfaceStubs(prefs: { [string]: any }?): { [string]: any }
	local values: { [string]: any } = {
		reducedMotion = false,
		lowQuality = false,
		shakes = true,
		transparency = 1,
		textScale = 1,
		textSize = "Medium",
	}
	for key, value in pairs(prefs or {}) do
		values[key] = value
	end
	local uiPrefs: { [string]: any } = { Changed = Engine.signal() }
	for key in pairs(values) do
		uiPrefs[key] = function(): any
			return values[key]
		end
	end
	uiPrefs.setLowQuality = function(low: boolean)
		values.lowQuality = low
	end
	uiPrefs.setShakes = function(on: boolean)
		values.shakes = on
	end
	return {
		["src/ui/UiPrefs"] = uiPrefs,
		["src/ui/UiSound"] = { play = function(_id: string) end },
	}
end

export type Options = {
	-- Modules replaced by a table, by their path without extension ("src/ui/UiPrefs").
	Stubs: { [string]: any }?,
	-- Services beyond RunService and ReplicatedStorage, by name.
	Services: { [string]: any }?,
	-- The second the world begins, for a spec whose result depends on the day: os.time() and the servers'
	-- clock then start there and move on by the world's own. Without it, the real time it began.
	Epoch: number?,
}

-- An action bound through ContextActionService: at what priority, on which inputs, and whether it asked the engine
-- for a touch button.
export type Binding = { Priority: number?, Inputs: { any }, Touch: boolean }

export type World = {
	game: any,
	workspace: any,
	player: any,
	playerGui: any,
	guiService: any,
	userInput: any,
	-- UserSettings(), and its GetService("UserGameSettings").
	userSettings: any,
	gameSettings: any,
	actions: { [string]: (string, any, any) -> any },
	bindings: { [string]: Binding },
	now: number,
	Heartbeat: Signal,
	warnings: { string },
	require: (path: string) -> any,
	advance: (self: World, seconds: number, frameSeconds: number?) -> (),
	frames: (self: World, count: number, frameSeconds: number?) -> (),
}

function Engine.world(options: Options?): World
	local stubs = if options ~= nil and options.Stubs ~= nil then options.Stubs else {}
	local extraServices = if options ~= nil and options.Services ~= nil then options.Services else {}

	local world: any = {
		now = 0,
		Heartbeat = Engine.signal(),
		warnings = {},
	}

	local game = Engine.instance("DataModel")
	game.Name = "Game"
	-- A public server, as the engine says it: no private server id and no owner (Pure/ServerKind).
	game.PrivateServerId = ""
	game.PrivateServerOwnerId = 0
	world.game = game

	-- The camera a screen measures the viewport from: a 1080p desktop until a spec says otherwise.
	local workspace = Engine.instance("Workspace", game)
	workspace.Name = "Workspace"
	local camera = Engine.instance("Camera", workspace)
	camera.ViewportSize = roblox.Vector2.new(1920, 1080)
	workspace.CurrentCamera = camera
	world.workspace = workspace
	-- The servers' clock: the time the world began (the real one unless the spec fixed it), moved on by the
	-- world's own.
	local epoch = if options ~= nil then options.Epoch else nil
	local began = epoch or os.time()
	workspace.GetServerTimeNow = function(): number
		return began + world.now
	end

	-- A keyboard and a mouse, no touch and no pad, unless the spec says otherwise (Engine.phone, Engine.plays).
	local userInput = Engine.instance("UserInputService", game)
	userInput.TouchEnabled = false
	userInput.KeyboardEnabled = true
	userInput.MouseEnabled = true
	userInput.GamepadEnabled = false
	userInput.PreferredInput = roblox.Enum.PreferredInput.KeyboardAndMouse
	userInput.GetLastInputType = function(self: any): any
		if self.GamepadEnabled then
			return roblox.Enum.UserInputType.Gamepad1
		elseif self.TouchEnabled and not self.KeyboardEnabled then
			return roblox.Enum.UserInputType.Touch
		end
		return roblox.Enum.UserInputType.MouseButton1
	end
	userInput.GetFocusedTextBox = function(): any
		return nil
	end

	-- The player's Roblox settings (UserSettings()), as a LocalScript reads them: the graphics level left to
	-- Roblox unless the spec sets one.
	local gameSettings = Engine.instance("UserGameSettings")
	gameSettings.SavedQualityLevel = roblox.Enum.SavedQualitySetting.Automatic
	world.gameSettings = gameSettings
	local userSettings = {
		GetService = function(_self: any, name: string): any
			if name ~= "UserGameSettings" then
				error(("the spec gives no %s in UserSettings()"):format(name), 2)
			end
			return gameSettings
		end,
	}
	world.userSettings = userSettings

	-- The local player and their PlayerGui, where every screen is parented.
	local players = Engine.instance("Players", game)
	players.Name = "Players"
	local player = Engine.instance("Player", players)
	player.Name = "Player"
	players.LocalPlayer = player
	local playerGui = Engine.instance("PlayerGui", player)
	playerGui.Name = "PlayerGui"
	world.player = player
	world.playerGui = playerGui

	-- The gamepad's selection and the topbar's inset (none, as on a desktop window).
	local guiService = Engine.instance("GuiService", game)
	guiService.SelectedObject = nil
	guiService.GetGuiInset = function(_self: any): (any, any)
		return roblox.Vector2.zero, roblox.Vector2.zero
	end
	world.guiService = guiService
	world.userInput = userInput

	-- The actions bound through ContextActionService, by name: what a spec presses a key or a button with, and
	-- at what priority and on which inputs each was bound.
	local actions: { [string]: (string, any, any) -> any } = {}
	local bindings: { [string]: Binding } = {}
	world.actions = actions
	world.bindings = bindings
	local contextActions = {
		BindAction = function(_self: any, name: string, handler: any, touch: boolean, ...: any)
			actions[name] = handler
			bindings[name] = { Priority = nil, Inputs = { ... }, Touch = touch }
		end,
		BindActionAtPriority = function(
			_self: any,
			name: string,
			handler: any,
			touch: boolean,
			priority: number,
			...: any
		)
			actions[name] = handler
			bindings[name] = { Priority = priority, Inputs = { ... }, Touch = touch }
		end,
		UnbindAction = function(_self: any, name: string)
			actions[name] = nil
			bindings[name] = nil
		end,
		-- The engine's own touch button for an action, which it makes on a real touch screen only: none here.
		GetButton = function(_self: any, _name: string): any
			return nil
		end,
	}

	local services: { [string]: any } = {
		ContextActionService = contextActions,
		Players = players,
		GuiService = guiService,
		RunService = {
			Heartbeat = world.Heartbeat,
			RenderStepped = Engine.signal(),
			IsStudio = function()
				return false
			end,
		},
		ReplicatedStorage = pathNode(REPLICATED_ROOT),
		UserInputService = userInput,
		Workspace = workspace,
	}
	for name, service in pairs(extraServices) do
		services[name] = service
	end
	servicesOf[game] = services

	-- task, on the world's clock. A delay is a thread, so task.cancel and Trove treat it as the engine's.
	type Timer = { At: number, Order: number, Thread: thread, Args: { any } }
	local timers: { Timer } = {}
	local order = 0
	local function resume(thread: thread, ...: any)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			error(err, 0)
		end
	end
	local function schedule(seconds: number, fn: any, ...: any): thread
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		order += 1
		table.insert(timers, { At = world.now + seconds, Order = order, Thread = thread, Args = { ... } })
		return thread
	end
	local fakeTask = {
		delay = function(seconds: number?, fn: any, ...: any): thread
			return schedule(seconds or 0, fn, ...)
		end,
		defer = function(fn: any, ...: any): thread
			return schedule(0, fn, ...)
		end,
		spawn = function(fn: any, ...: any): thread
			local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
			resume(thread, ...)
			return thread
		end,
		cancel = function(thread: thread)
			for index = #timers, 1, -1 do
				if timers[index].Thread == thread then
					table.remove(timers, index)
				end
			end
		end,
		wait = function()
			error("task.wait has no place in the interface, and a spec cannot yield", 2)
		end,
	}

	local function runDue()
		while true do
			local due: Timer? = nil
			for _, timer in ipairs(timers) do
				if
					timer.At <= world.now
					and (due == nil or timer.At < due.At or (timer.At == due.At and timer.Order < due.Order))
				then
					due = timer
				end
			end
			if due == nil then
				return
			end
			table.remove(timers, table.find(timers, due) :: number)
			resume(due.Thread, table.unpack(due.Args))
		end
	end

	-- One frame: the timers that are due, then the Heartbeat, as the engine's frame runs them.
	local function frame(seconds: number)
		world.now += seconds
		runDue()
		world.Heartbeat:Fire(seconds)
	end

	function world.advance(_self: any, seconds: number, frameSeconds: number?)
		local step = frameSeconds or 1 / 60
		local count = math.max(1, math.floor(seconds / step + 0.5))
		for _ = 1, count do
			frame(step)
		end
	end

	function world.frames(_self: any, count: number, frameSeconds: number?)
		for _ = 1, count do
			frame(frameSeconds or 1 / 60)
		end
	end

	local cache: { [string]: any } = {}
	local environment: { [string]: any } = {
		game = game,
		workspace = workspace,
		task = fakeTask,
		typeof = typeOf,
		warn = function(...: any)
			local parts = {}
			for index = 1, select("#", ...) do
				table.insert(parts, tostring((select(index, ...))))
			end
			table.insert(world.warnings, table.concat(parts, " "))
		end,
		time = function(): number
			return world.now
		end,
		os = {
			clock = function(): number
				return world.now
			end,
			-- A fixed epoch is the screens' day too: a screen that reads os.time() (the Shop's rotation, the
			-- quests' period) otherwise drew a different day from the one the spec measured.
			time = if epoch == nil
				then os.time
				else function(date: any?): number
					if date ~= nil then
						return os.time(date)
					end
					return began + math.floor(world.now)
				end,
			date = os.date,
		},
		Instance = {
			new = function(className: string, parent: any?): any
				return Engine.instance(className, parent)
			end,
		},
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		Font = roblox.Font,
		Enum = roblox.Enum,
		UserSettings = function(): any
			return userSettings
		end,
		-- A ray's filter, as a module builds one at load (Feel's camera sight): its fields, and nothing casts it.
		RaycastParams = {
			new = function(): any
				return {}
			end,
		},
	}

	local function load(path: string): any
		local stub = stubs[path]
		if stub ~= nil then
			return stub
		end
		local cached = cache[path]
		if cached ~= nil then
			return cached
		end
		local source = sourceOf(path)
		if source == nil then
			error(("no module at %s"):format(path), 3)
		end
		local env = table.clone(environment)
		env.script = pathNode(path)
		env.require = function(target: any): any
			local targetPath = pathOf[target]
			if targetPath == nil then
				error(("%s requires something that is not a module path: %s"):format(path, tostring(target)), 2)
			end
			return load(targetPath)
		end
		local chunk = luau.load(source, { debugName = path, environment = env })
		local result = chunk()
		cache[path] = result
		-- The interface's door to how the player plays, opened as the client bootstrap opens it: before any
		-- screen reads Theme (src/client/Bootstrap.client.luau, D-228).
		if path == THEME and stubs[INPUT_MODE] == nil then
			local inputMode = load(INPUT_MODE)
			inputMode.start()
			result.useInput(inputMode)
		end
		return result
	end

	world.require = load
	return world
end

-- A phone's top bar, in pixels (tests/TouchCluster.spec.luau).
Engine.TOP_INSET = 36

-- Makes `world` a landscape phone `width` x `height` points: a touch screen with no keyboard, and the top
-- bar over its game. Returns the height of its screens in design units, at the scale the interface takes.
function Engine.phone(world: any, width: number, height: number): number
	world.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(width, height)
	world.guiService.GetGuiInset = function(): (any, any)
		return roblox.Vector2.new(0, Engine.TOP_INSET), roblox.Vector2.zero
	end
	Engine.plays(world, "Touch")
	local Theme = world.require("src/ui/Theme")
	return height / Theme.activeScale()
end

-- The devices of `world` for a way of playing, and the engine's answer to them (UserInputService.PreferredInput),
-- last, as the engine changes it when the player switches:
--   "Touch"          a phone or a tablet: a touch screen, no keyboard, touched
--   "Pointer"        a desktop: a keyboard and a mouse
--   "Gamepad"        a desktop with a pad, playing with the pad
--   "TouchKeyboard"  a touch laptop, or a tablet with a keyboard, typed on
--   "TouchGamepad"   a phone or a tablet with a pad paired, playing with the pad
--   "TouchLaptop"    a touch laptop, or a tablet with a keyboard, touched
export type Plays = "Touch" | "Pointer" | "Gamepad" | "TouchKeyboard" | "TouchGamepad" | "TouchLaptop"
local DEVICES: { [string]: { Touch: boolean, Keyboard: boolean, Gamepad: boolean, Preferred: string } } = {
	Touch = { Touch = true, Keyboard = false, Gamepad = false, Preferred = "Touch" },
	Pointer = { Touch = false, Keyboard = true, Gamepad = false, Preferred = "KeyboardAndMouse" },
	Gamepad = { Touch = false, Keyboard = true, Gamepad = true, Preferred = "Gamepad" },
	TouchKeyboard = { Touch = true, Keyboard = true, Gamepad = false, Preferred = "KeyboardAndMouse" },
	TouchGamepad = { Touch = true, Keyboard = false, Gamepad = true, Preferred = "Gamepad" },
	TouchLaptop = { Touch = true, Keyboard = true, Gamepad = false, Preferred = "Touch" },
}

function Engine.plays(world: any, plays: Plays)
	local device = DEVICES[plays]
	local userInput = world.userInput
	userInput.TouchEnabled = device.Touch
	userInput.KeyboardEnabled = device.Keyboard
	userInput.MouseEnabled = device.Keyboard
	userInput.GamepadEnabled = device.Gamepad
	userInput.PreferredInput = (roblox.Enum.PreferredInput :: any)[device.Preferred]
end

return Engine
