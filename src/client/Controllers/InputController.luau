--!strict
-- InputController: binds every InputConfig action through ContextActionService for keyboard (+ mouse),
-- gamepad and touch, from the player's saved keybinds. Emits `Action(actionId, began)`; ComboController,
-- CombatController and MenuController consume it. `captureNext` suspends the actions and resolves the
-- next raw key of the requested kind for the rebind screen; `setSuspended` unbinds everything (touch
-- buttons disappear with the bindings) while a menu is open.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local ElementConfig = require(Shared.Config.ElementConfig)
local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Packages.Signal)
local Theme = require(UI.Theme)
local TouchButton = require(UI.components.TouchButton)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("InputController")

export type CaptureKind = "Keyboard" | "Gamepad"

type TroveType = typeof(Trove.new())
type Deps = { ClientData: any, Localize: any, MenuController: any }
type Capture = { Kind: CaptureKind, Callback: (keyName: string?) -> (), Trove: TroveType }
type BindInput = Enum.KeyCode | Enum.UserInputType

local MOUSE_PREFIX = "MouseButton"
local GAMEPAD_PREFIX = "Gamepad"
local MENU_ACTION = "Menu"
local HAPTIC_STRENGTH = 0.5
local HAPTIC_SECONDS = 0.06
-- Analog sticks fire InputBegan past their deadzone; they are never a valid gamepad binding.
local THUMBSTICKS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Thumbstick1] = true,
	[Enum.KeyCode.Thumbstick2] = true,
}

-- Config maps are keyed by the ActionId literal union; bindings work with plain string keys.
local function stringMap(map: { [InputConfig.ActionId]: string }): Types.KeybindMap
	return (map :: any) :: Types.KeybindMap
end

local DEFAULTS: { [string]: Types.KeybindMap } = {
	Keyboard = stringMap(InputConfig.DefaultKeyboard),
	Gamepad = stringMap(InputConfig.DefaultGamepad),
}

local InputController = {}

InputController.Action = Signal.new() -- (actionId: string, began: boolean)
InputController.SuspendedChanged = Signal.new() -- (suspended: boolean)

local clientData: any
local localize: any
local menuController: any

local bindTrove = Trove.new() -- touch button visuals of the current bindings
local touchVisuals: { [string]: TouchButton.TouchButton } = {}
local boundActions: { string } = {}
local bound = false
local suspended = false
local capture: Capture? = nil
local warnedKeys: { [string]: boolean } = {}
local hapticSupport: { [Enum.UserInputType]: boolean } = {}

local keyCodeByName: { [string]: Enum.KeyCode } = {}
for _, item in ipairs(Enum.KeyCode:GetEnumItems()) do
	keyCodeByName[item.Name] = item :: Enum.KeyCode
end
local inputTypeByName: { [string]: Enum.UserInputType } = {}
for _, item in ipairs(Enum.UserInputType:GetEnumItems()) do
	inputTypeByName[item.Name] = item :: Enum.UserInputType
end

local function isGamepad(inputType: Enum.UserInputType): boolean
	return string.sub(inputType.Name, 1, #GAMEPAD_PREFIX) == GAMEPAD_PREFIX
end

local function keyboardInput(name: string): BindInput?
	if string.sub(name, 1, #MOUSE_PREFIX) == MOUSE_PREFIX then
		return inputTypeByName[name]
	end
	return keyCodeByName[name]
end

local function warnUnknownKey(kind: CaptureKind, action: string, name: string)
	local id = kind .. ":" .. action .. ":" .. name
	if warnedKeys[id] then
		return
	end
	warnedKeys[id] = true
	log.warn("unknown %s key %s for %s: action left unbound", kind, name, action)
end

-- Saved keybinds merged over the defaults so an incomplete map never leaves an action unbound.
local function keybinds(kind: CaptureKind): Types.KeybindMap
	local data: Types.ProfileData? = clientData.get()
	local defaults = DEFAULTS[kind]
	local saved: Types.KeybindMap? = nil
	if data ~= nil then
		saved = if kind == "Keyboard" then data.Settings.Keyboard else data.Settings.Gamepad
	end
	local map: Types.KeybindMap = {}
	for _, action in ipairs(InputConfig.Actions) do
		local name = if saved ~= nil then saved[action] else nil
		map[action] = if type(name) == "string" then name else defaults[action]
	end
	return map
end

local function hapticType(input: InputObject): Enum.UserInputType?
	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.Touch or isGamepad(inputType) then
		return inputType
	end
	return nil
end

local function pulseHaptics(input: InputObject)
	local inputType = hapticType(input)
	if inputType == nil then
		return
	end
	local supported = hapticSupport[inputType]
	if supported == nil then
		supported = HapticService:IsVibrationSupported(inputType)
			and HapticService:IsMotorSupported(inputType, Enum.VibrationMotor.Small)
		hapticSupport[inputType] = supported
	end
	if not supported then
		return
	end
	HapticService:SetMotor(inputType, Enum.VibrationMotor.Small, HAPTIC_STRENGTH)
	task.delay(HAPTIC_SECONDS, function()
		HapticService:SetMotor(inputType, Enum.VibrationMotor.Small, 0)
	end)
end

local function onAction(actionName: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
	if suspended or capture ~= nil then
		return Enum.ContextActionResult.Pass
	end
	local visual = touchVisuals[actionName]
	if state == Enum.UserInputState.Begin then
		pulseHaptics(input)
		if visual ~= nil then
			visual:SetPressed(true)
		end
		InputController.Action:Fire(actionName, true)
		if actionName == MENU_ACTION then
			menuController.toggle()
		end
		return Enum.ContextActionResult.Sink
	end
	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if visual ~= nil then
			visual:SetPressed(false)
		end
		InputController.Action:Fire(actionName, false)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function touchScale(): number
	local camera: Camera? = Workspace.CurrentCamera
	if camera == nil then
		return 1
	end
	return Theme.scaleFor(camera.ViewportSize)
end

-- Replaces the engine's default touch button look with the themed TouchButton visual.
local function styleTouchButton(action: string)
	local button: ImageButton? = ContextActionService:GetButton(action)
	if button == nil then
		return
	end
	local position = InputConfig.Touch.Positions[action :: any]
	local size = InputConfig.Touch.ButtonSize * touchScale()
	button.Image = ""
	button.PressedImage = ""
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	if position ~= nil then
		button.Position = UDim2.fromScale(position.X, position.Y)
	end

	local isElement = ElementConfig.isElement(action)
	local visual = TouchButton.new({
		Label = if isElement
			then ElementConfig.Glyphs[action :: any]
			else localize.t(InputConfig.ActionNameKeys[action :: any]),
		Color = if isElement then Theme.elementColor(action) else Theme.Colors.PanelRaised,
		Size = size,
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = button,
		Name = action,
	})
	visual.Instance.Interactable = false -- the ContextActionService button underneath receives the touch
	bindTrove:Add(visual)
	touchVisuals[action] = visual
end

local function bindAll()
	if bound then
		return
	end
	bound = true
	local keyboard = keybinds("Keyboard")
	local gamepad = keybinds("Gamepad")
	local touch = UserInputService.TouchEnabled

	for _, action in ipairs(InputConfig.Actions) do
		local inputs: { BindInput } = {}
		local keyboardName = keyboard[action]
		local keyboardKey = keyboardInput(keyboardName)
		if keyboardKey ~= nil then
			table.insert(inputs, keyboardKey)
		else
			warnUnknownKey("Keyboard", action, keyboardName)
		end
		local gamepadName = gamepad[action]
		local gamepadKey = keyCodeByName[gamepadName]
		if gamepadKey ~= nil then
			table.insert(inputs, gamepadKey)
		else
			warnUnknownKey("Gamepad", action, gamepadName)
		end
		if #inputs == 0 and not touch then
			continue
		end
		ContextActionService:BindAction(action, onAction, touch, table.unpack(inputs))
		table.insert(boundActions, action)
		if touch then
			styleTouchButton(action)
		end
	end
end

local function unbindAll()
	if not bound then
		return
	end
	bound = false
	bindTrove:Clean()
	table.clear(touchVisuals)
	for _, action in ipairs(boundActions) do
		ContextActionService:UnbindAction(action)
	end
	table.clear(boundActions)
end

local function applyBindings()
	if suspended or capture ~= nil then
		unbindAll()
	else
		bindAll()
	end
end

local function keyNameFor(kind: CaptureKind, input: InputObject): string?
	local inputType = input.UserInputType
	if kind == "Keyboard" then
		if inputType == Enum.UserInputType.Keyboard then
			return input.KeyCode.Name
		end
		if string.sub(inputType.Name, 1, #MOUSE_PREFIX) == MOUSE_PREFIX then
			return inputType.Name
		end
		return nil
	end
	if isGamepad(inputType) and not THUMBSTICKS[input.KeyCode] then
		return input.KeyCode.Name
	end
	return nil
end

local function finishCapture(keyName: string?)
	local pending = capture
	if pending == nil then
		return
	end
	capture = nil
	pending.Trove:Destroy()
	applyBindings()
	pending.Callback(keyName)
end

-- Resolves the next raw key of `kind` (Escape or the Roblox menu cancel with nil). Actions stay
-- unbound until the capture resolves; a capture started while another is pending cancels it.
function InputController.captureNext(kind: CaptureKind, callback: (keyName: string?) -> ())
	finishCapture(nil)
	local captureTrove = Trove.new()
	capture = { Kind = kind, Callback = callback, Trove = captureTrove }
	applyBindings()
	captureTrove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.Escape then
			finishCapture(nil)
			return
		end
		if processed and kind == "Keyboard" then
			return
		end
		local name = keyNameFor(kind, input)
		if name ~= nil then
			finishCapture(name)
		end
	end)
	captureTrove:Connect(GuiService.MenuOpened, function()
		finishCapture(nil)
	end)
end

-- Drops a pending capture without invoking its callback (screen closed).
function InputController.cancelCapture()
	local pending = capture
	if pending == nil then
		return
	end
	capture = nil
	pending.Trove:Destroy()
	applyBindings()
end

function InputController.setSuspended(value: boolean)
	if suspended == value then
		return
	end
	suspended = value
	applyBindings()
	InputController.SuspendedChanged:Fire(value)
end

function InputController.isSuspended(): boolean
	return suspended
end

-- Re-reads the keybinds. When the actions are currently unbound the next bind reads them anyway.
function InputController.rebuild()
	if not bound then
		return
	end
	unbindAll()
	bindAll()
end

function InputController.Init(deps: Deps)
	clientData = deps.ClientData
	localize = deps.Localize
	menuController = deps.MenuController
end

function InputController.Start()
	clientData.Changed:Connect(function(section: string)
		if section == "*" or section == "Settings" then
			InputController.rebuild()
		end
	end)
	applyBindings()
	log.info("started (%d actions, touch %s)", #boundActions, tostring(UserInputService.TouchEnabled))
end

return InputController
