--!strict
-- InputController: binds every InputConfig action through ContextActionService for keyboard (+ mouse),
-- gamepad and touch, from the player's saved keybinds. Emits `Action(actionId, began)`; ComboController,
-- CombatController and MenuController consume it. `captureNext` suspends the actions and resolves the
-- next raw key of the requested kind for the rebind screen (Escape and the Roblox menu cancel it);
-- `setSuspended` unbinds everything (touch buttons disappear with the bindings) while a menu is open, but
-- the Menu key, which closes it.
-- Touch buttons are laid out in absolute screen space from `InputConfig.Touch`, clear of the engine
-- jump button and of each other (TouchCluster.layout). A locked pigment keeps its keys but gets no disc; the
-- dash disc shows the cooldown the local throttle keeps (CombatController), and the HUD tells the discs
-- which ones continue the sequence and which ones the ink can still pay for (setHints, setAffordable).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local UI = ReplicatedStorage:WaitForChild("UI")

local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local PigmentConfig = require(Shared.Config.PigmentConfig)
local Signal = require(Packages.Signal)
local Theme = require(UI.Theme)
local TouchButton = require(UI.components.TouchButton)
local TouchCluster = require(Shared.Pure.TouchCluster)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("InputController")

export type CaptureKind = "Keyboard" | "Gamepad"

type TroveType = typeof(Trove.new())
type Deps = { ClientData: any, Localize: any, MenuController: any }
type Capture = { Kind: CaptureKind, Callback: (keyName: string?) -> (), Trove: TroveType }
type BindInput = Enum.KeyCode | Enum.UserInputType
export type Rect = { Min: Vector2, Max: Vector2 }
type TouchStyle = { Discs: { [string]: TouchCluster.Disc }, Origin: Vector2 }

-- Above the default camera's own bindings: at the same priority, the most recently bound wins, and the
-- camera re-binds the right stick's click (its zoom) every time it is re-enabled -- so the lock's button
-- worked or zoomed depending on who bound last (D-115). The stun's input lock sits above this.
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
local MOUSE_PREFIX = "MouseButton"
local GAMEPAD_PREFIX = "Gamepad"
local MENU_ACTION = "Menu"
local HAPTIC_STRENGTH = 0.5
local HAPTIC_SECONDS = 0.06
-- Rebind capture cancel. Keyboard only: every gamepad button a player may bind is whitelisted in
-- InputConfig.AllowedGamepad, and a button that cancels the capture could never be bound. The rebind
-- screen cancels in-UI instead, by re-activating the highlighted row.
-- Built from InputConfig.CaptureCancelKeys, which a test keeps disjoint from the rebind whitelists.
local CAPTURE_CANCEL: { [Enum.KeyCode]: boolean } = {}
for _, name in ipairs(InputConfig.CaptureCancelKeys) do
	local keyCode = (Enum.KeyCode :: any)[name]
	if keyCode ~= nil then
		CAPTURE_CANCEL[keyCode] = true
	else
		log.error("CaptureCancelKeys names the unknown key %s", name)
	end
end
local TOUCH_GUI_NAME = "TouchGui"
local JUMP_BUTTON_NAME = "JumpButton"
-- What the touch layout was last measured on: the engine's jump button, or the corner kept for it while TouchGui
-- has not built it. Said once per change, for the smoke test to read (docs/QA.md, what Lune cannot see).
type JumpSource = "JumpButton" | "Reserve"
-- Frames waited for the engine to lay its button frame out (AbsolutePosition is the layout origin).
local LAYOUT_WAIT_FRAMES = 4
local FALLBACK_VIEWPORT = Vector2.new(1280, 720)
-- The layout reads the touch config as plain data (TouchCluster is pure and knows no ActionId).
local TOUCH_CONFIG: TouchCluster.Config = InputConfig.Touch :: any
local ACTIONS: { string } = InputConfig.Actions :: any
local DASH_ACTION = "Dash"
-- The dash disc's veil moves at the pace the hotbar's drains do: the server's combat pushes.
local DASH_TICK_SECONDS = 1 / GameConfig.Server.CombatStateHz
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
-- Fired at the end of every layout of the touch discs: what the HUD lays out around them reads touchRects.
InputController.TouchLayoutChanged = Signal.new()

local clientData: any
local localize: any
local menuController: any

local bindTrove = Trove.new() -- touch button visuals and layout watchers of the current bindings
local touchVisuals: { [string]: TouchButton.TouchButton } = {}
local boundActions: { string } = {}
local bound = false
local bindGeneration = 0 -- bumped by every bind/unbind so a deferred styling pass can abort
local suspended = false
local capture: Capture? = nil
local warnedKeys: { [string]: boolean } = {}
local hapticSupport: { [Enum.UserInputType]: boolean } = {}
-- The square each touch disc covers since the last layout, by action. Kept while a menu unbinds the discs:
-- they come back in the same places.
local touchRectsByAction: { [string]: Rect } = {}
local relayoutTouch: () -> ()
local jumpMeasuredOn: JumpSource? = nil
-- The pigments each source of hints says continue the sequence (setHints), and those the ink can pay for.
local hintsBySource: { [string]: { [string]: boolean } } = {}
local affordable: { [string]: boolean }? = nil
-- The locked pigments the discs were last bound without, so an unlock rebinds only when it changes them.
local lockedSignature = ""
-- When the local throttle lets the next dash through (os.clock), and the tick chain drawing its veil.
local dashReadyAt = 0
local dashToken = 0

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

-- The dash disc's veil, from the throttle's clock: drawn again at the server's combat pace until the next
-- dash can go. A newer dash starts a new chain and the old one stops.
local function tickDash(token: number)
	if token ~= dashToken then
		return
	end
	local remaining = math.max(0, dashReadyAt - os.clock())
	local visual = touchVisuals[DASH_ACTION]
	if visual ~= nil then
		visual:SetCooldown(remaining, CombatConfig.Dash.CooldownSeconds)
	end
	if remaining > 0 then
		task.delay(DASH_TICK_SECONDS, tickDash, token)
	end
end

-- A dash press the local throttle lets through (CombatController drops any other inside
-- Dash.CooldownSeconds of the last it sent): the disc shows the wait until the next.
local function onDashPressed()
	local now = os.clock()
	if not UserInputService.TouchEnabled or now < dashReadyAt then
		return
	end
	dashReadyAt = now + CombatConfig.Dash.CooldownSeconds
	dashToken += 1
	tickDash(dashToken)
end

-- A respawn clears the throttle (CombatController) and the server's cooldowns: the disc is ready.
local function clearDash()
	dashReadyAt = 0
	dashToken += 1
	tickDash(dashToken)
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
		elseif actionName == DASH_ACTION then
			onDashPressed()
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

local function viewportSize(): Vector2
	local camera: Camera? = Workspace.CurrentCamera
	if camera == nil then
		return FALLBACK_VIEWPORT
	end
	return camera.ViewportSize
end

local function touchScale(): number
	return Theme.scaleFor(viewportSize())
end

-- Screen area below the Roblox top bar; touch buttons are laid out in these absolute coordinates.
local function screenRect(): Rect
	local topInset = GuiService:GetGuiInset()
	return { Min = Vector2.new(0, topInset.Y), Max = viewportSize() }
end

local function measuredOn(source: JumpSource)
	if jumpMeasuredOn == source then
		return
	end
	jumpMeasuredOn = source
	if source == "JumpButton" then
		log.info("touch layout measured on the engine's JumpButton")
	else
		log.info("touch layout measured on the reserved corner: TouchGui has no JumpButton yet")
	end
end

-- The engine jump button once TouchGui exists, else the corner InputConfig reserves for it.
local function jumpRect(screen: Rect): Rect
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touchGui = if playerGui ~= nil then playerGui:FindFirstChild(TOUCH_GUI_NAME) else nil
	local jump = if touchGui ~= nil then touchGui:FindFirstChild(JUMP_BUTTON_NAME, true) else nil
	if jump ~= nil and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 0 then
		measuredOn("JumpButton")
		return { Min = jump.AbsolutePosition, Max = jump.AbsolutePosition + jump.AbsoluteSize }
	end
	measuredOn("Reserve")
	local reserve = InputConfig.Touch.JumpReserve
	return { Min = screen.Max - Vector2.new(reserve.Width, reserve.Height), Max = screen.Max }
end

local function toCluster(rect: Rect): TouchCluster.Rect
	return { Min = { X = rect.Min.X, Y = rect.Min.Y }, Max = { X = rect.Max.X, Y = rect.Max.Y } }
end

-- Every disc's centre (absolute screen px) and diameter: the pigment ring above and left of the engine jump
-- button, Melee/Block/Dash/LockOn in a row left of it, Menu in the top-right corner (TouchCluster.layout).
local function touchLayout(scale: number): { [string]: TouchCluster.Disc }
	local screen = screenRect()
	return TouchCluster.layout(TOUCH_CONFIG, ACTIONS, toCluster(screen), toCluster(jumpRect(screen)), scale)
end

-- Whether any source of hints says `action` continues the sequence.
local function hinted(action: string): boolean
	for _, pigments in pairs(hintsBySource) do
		if pigments[action] then
			return true
		end
	end
	return false
end

-- Whether a pigment disc leads to a glyph the ink can pay for; the kit is always there.
local function available(action: string): boolean
	local payable = affordable
	return payable == nil or not PigmentConfig.isPigment(action) or payable[action] == true
end

local function refreshDiscs()
	for action, visual in pairs(touchVisuals) do
		visual:SetHint(hinted(action))
		visual:SetAvailable(available(action))
	end
end

local function discKind(action: string): TouchButton.Kind
	if PigmentConfig.isPigment(action) then
		return "Pigment"
	end
	return if action == MENU_ACTION then "Menu" else "Kit"
end

-- Replaces the engine's default touch button look with the themed TouchButton visual.
local function applyTouchButton(action: string, button: ImageButton, style: TouchStyle)
	local disc = style.Discs[action]
	if disc == nil then
		return
	end
	button.Image = ""
	button.PressedImage = ""
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(disc.Diameter, disc.Diameter)
	button.Position = UDim2.fromOffset(disc.Centre.X - style.Origin.X, disc.Centre.Y - style.Origin.Y)

	local kind: TouchButton.Kind = discKind(action)
	local visual = TouchButton.new({
		-- The short label, not the full name: a disc is Touch.MinButtonSize wide and "Corps à corps"
		-- clips at that width whatever the text size.
		Label = if kind == "Pigment"
			then PigmentConfig.Sigils[action :: any]
			else localize.t(
				InputConfig.ActionShortKeys[action :: any] or InputConfig.ActionNameKeys[action :: any]
			),
		Kind = kind,
		Pigment = if kind == "Pigment" then action else nil,
		Size = disc.Diameter,
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = button,
		Name = action,
	})
	visual.Instance.Interactable = false -- the ContextActionService button underneath receives the touch
	bindTrove:Add(visual)
	touchVisuals[action] = visual
	visual:SetHint(hinted(action))
	visual:SetAvailable(available(action))
end

-- ContextActionService:GetButton yields, so the generation is re-checked after every call: an unbind
-- during the walk must abort the pass instead of styling buttons that are no longer bound.
local function collectButtons(generation: number): ({ [string]: ImageButton }, GuiObject?)
	local buttons: { [string]: ImageButton } = {}
	local frame: GuiObject? = nil
	for _, action in ipairs(boundActions) do
		local button: ImageButton? = ContextActionService:GetButton(action)
		if bindGeneration ~= generation then
			return {}, nil
		end
		if button ~= nil then
			buttons[action] = button
			local parent = button.Parent
			if frame == nil and parent ~= nil and parent:IsA("GuiObject") then
				frame = parent
			end
		end
	end
	return buttons, frame
end

-- Positions and skins the touch buttons once every action is bound.
local function styleTouchButtons(generation: number)
	local buttons, frame = collectButtons(generation)
	if frame == nil then
		return
	end
	for _ = 1, LAYOUT_WAIT_FRAMES do
		if frame.AbsoluteSize.X > 0 then
			break
		end
		task.wait()
		if bindGeneration ~= generation then
			return
		end
	end
	-- The engine parents its buttons to a small bottom-right frame; the layout is in screen space.
	frame.ClipsDescendants = false
	local style: TouchStyle = { Discs = touchLayout(touchScale()), Origin = frame.AbsolutePosition }
	for _, action in ipairs(boundActions) do
		local button: ImageButton? = buttons[action]
		if button ~= nil then
			applyTouchButton(action, button, style)
		end
	end
	tickDash(dashToken)
	-- Only the discs that are there: a layout places every action, bound or not.
	table.clear(touchRectsByAction)
	for action, disc in pairs(style.Discs) do
		local button: ImageButton? = buttons[action]
		if button ~= nil then
			local centre = Vector2.new(disc.Centre.X, disc.Centre.Y)
			local half = Vector2.new(disc.Diameter, disc.Diameter) * 0.5
			touchRectsByAction[action] = { Min = centre - half, Max = centre + half }
		end
	end
	InputController.TouchLayoutChanged:Fire()
end

-- The layout is measured, so it is rebuilt when the viewport changes or when the engine finally
-- creates its jump button (TouchGui is built after the first character spawn).
local function watchTouchLayout()
	local camera: Camera? = Workspace.CurrentCamera
	if camera ~= nil then
		bindTrove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
			relayoutTouch()
		end)
	end
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui ~= nil then
		bindTrove:Connect(playerGui.DescendantAdded, function(descendant: Instance)
			if descendant.Name == JUMP_BUTTON_NAME then
				relayoutTouch()
			end
		end)
	end
end

local function bindInputs(action: string, keyboard: Types.KeybindMap, gamepad: Types.KeybindMap): { BindInput }
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
	return inputs
end

-- The pigments the profile has not unlocked (PigmentConfig.Unlockable): all of them before it loads.
local function lockedPigments(): { [string]: boolean }
	local data: Types.ProfileData? = clientData.get()
	local locked: { [string]: boolean } = {}
	for _, pigment in ipairs(PigmentConfig.Unlockable) do
		if data == nil or table.find(data.Unlocks.Pigments, pigment) == nil then
			locked[pigment] = true
		end
	end
	return locked
end

local function signatureOf(locked: { [string]: boolean }): string
	local names: { string } = {}
	for pigment in pairs(locked) do
		table.insert(names, pigment)
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function bindAll()
	if bound then
		return
	end
	bound = true
	bindGeneration += 1
	local generation = bindGeneration
	local keyboard = keybinds("Keyboard")
	local gamepad = keybinds("Gamepad")
	local touchScreen = UserInputService.TouchEnabled
	-- A pigment the player cannot cast yet keeps its keys, which the server answers with why, but gets no
	-- disc: the cluster shows what can be pressed (D-147).
	local locked = lockedPigments()
	lockedSignature = signatureOf(locked)

	for _, action in ipairs(InputConfig.Actions) do
		local inputs = bindInputs(action, keyboard, gamepad)
		local touch = touchScreen and not locked[action]
		if #inputs == 0 and not touch then
			continue
		end
		ContextActionService:BindActionAtPriority(action, onAction, touch, ACTION_PRIORITY, table.unpack(inputs))
		table.insert(boundActions, action)
	end
	if not touchScreen then
		return
	end
	-- Every action is bound before the first yielding GetButton, so an unbind can never leave one
	-- bound behind, and the engine lays all of its buttons out before they are repositioned.
	watchTouchLayout()
	task.defer(function()
		if bindGeneration == generation then
			styleTouchButtons(generation)
		end
	end)
end

local function unbindAll()
	if not bound then
		return
	end
	bound = false
	bindGeneration += 1 -- aborts a styling pass that is still walking the bound actions
	bindTrove:Clean()
	table.clear(touchVisuals)
	for _, action in ipairs(boundActions) do
		ContextActionService:UnbindAction(action)
	end
	table.clear(boundActions)
end

-- While a screen is open every action is unbound, and the Menu key went with them: the key that opened
-- the menu could not close it (D-128). This one binding stays while a screen is open, and goes during a
-- rebind capture so that the capture receives the key. No screen has a text box for it to steal from.
local MENU_CLOSE_ACTION = "MenuClose"
local menuCloseBound = false

-- Both edges are deferred past the press being dispatched: closing re-binds the Menu action to the same
-- key, and opening binds this one, so neither may be handed the press that caused it -- the menu would
-- close as it opened, or open again as it closed.
local function onMenuClose(_actionName: string, state: Enum.UserInputState): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	task.defer(menuController.close)
	return Enum.ContextActionResult.Sink
end

-- B on a gamepad walks back through the screens a player opened one from another, and closes the first
-- (MenuController.back, D-147). It lives with MenuClose and goes with it during a rebind capture, since B is a
-- key a player may bind; and it is deferred for the same reason: closing the last screen binds the game's
-- actions again, B among them.
local MENU_BACK_ACTION = "MenuBack"
local MENU_BACK_KEY = Enum.KeyCode.ButtonB

local function onMenuBack(_actionName: string, state: Enum.UserInputState): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	task.defer(menuController.back)
	return Enum.ContextActionResult.Sink
end

local function bindMenuClose()
	if menuCloseBound then
		return
	end
	local inputs = bindInputs(MENU_ACTION, keybinds("Keyboard"), keybinds("Gamepad"))
	if #inputs == 0 then
		return
	end
	menuCloseBound = true
	ContextActionService:BindActionAtPriority(
		MENU_CLOSE_ACTION,
		onMenuClose,
		false,
		ACTION_PRIORITY,
		table.unpack(inputs)
	)
	-- A player who made B their Menu key closes with it, like any Menu key.
	if table.find(inputs, MENU_BACK_KEY) == nil then
		ContextActionService:BindActionAtPriority(MENU_BACK_ACTION, onMenuBack, false, ACTION_PRIORITY, MENU_BACK_KEY)
	end
end

local function unbindMenuClose()
	if not menuCloseBound then
		return
	end
	menuCloseBound = false
	ContextActionService:UnbindAction(MENU_CLOSE_ACTION)
	ContextActionService:UnbindAction(MENU_BACK_ACTION)
end

local function applyBindings()
	if suspended or capture ~= nil then
		unbindAll()
	else
		bindAll()
	end
	if suspended and capture == nil then
		task.defer(function()
			if suspended and capture == nil then
				bindMenuClose()
			end
		end)
	else
		unbindMenuClose()
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

-- Resolves the next raw key of `kind`, or nil when cancelled (Escape or the Roblox menu). Actions stay
-- unbound until the capture resolves; a new capture cancels the pending one.
function InputController.captureNext(kind: CaptureKind, callback: (keyName: string?) -> ())
	finishCapture(nil)
	local captureTrove = Trove.new()
	capture = { Kind = kind, Callback = callback, Trove = captureTrove }
	applyBindings()
	-- The press that opened this capture reaches InputBegan flagged as game-processed, and so does
	-- every later press: the rebind screen covers the viewport with an Active frame. Processed input is
	-- therefore ignored only until the end of the activating frame (Heartbeat runs after the input of
	-- that frame) — long enough that the press cannot bind itself, short enough that the whitelisted
	-- mouse buttons stay assignable.
	local activating = true
	captureTrove:Add(RunService.Heartbeat:Once(function()
		activating = false
	end))
	captureTrove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed and activating then
			return
		end
		if CAPTURE_CANCEL[input.KeyCode] then
			finishCapture(nil)
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

-- The square each touch disc covered at the last layout, by action, in the space of a GuiObject's
-- AbsolutePosition: the toast lane hangs under the Menu disc, the combat dock fits between the thumbs.
-- Empty until the discs are first laid out (and on a device with no touch screen).
function InputController.touchRects(): { [string]: Rect }
	return table.clone(touchRectsByAction)
end

function InputController.isSuspended(): boolean
	return suspended
end

-- The pigments `source` says go on from the sequence being pressed (the HUD's "Sequence", the onboarding's
-- recipe): their discs breathe a thicker ring. A disc is hinted while any source hints it; an empty list
-- withdraws that source's hints.
function InputController.setHints(source: string, pigments: { string })
	local set: { [string]: boolean } = {}
	for _, pigment in ipairs(pigments) do
		set[pigment] = true
	end
	hintsBySource[source] = set
	refreshDiscs()
end

-- The pigments that still lead to a glyph the ink can pay for (TouchCluster.affordable): the other pigment
-- discs dim their sigil. The table is read, never kept apart from the caller's.
function InputController.setAffordable(pigments: { [string]: boolean })
	affordable = pigments
	refreshDiscs()
end

-- Re-reads the keybinds. When the actions are currently unbound the next bind reads them anyway.
function InputController.rebuild()
	if not bound then
		return
	end
	unbindAll()
	bindAll()
end

function relayoutTouch()
	if UserInputService.TouchEnabled then
		InputController.rebuild()
	end
end

function InputController.Init(deps: Deps)
	clientData = deps.ClientData
	localize = deps.Localize
	menuController = deps.MenuController
end

function InputController.Start()
	clientData.Changed:Connect(function(section: string)
		-- New keys, or a pigment just unlocked, which gets its disc.
		local unlocked = section == "Unlocks" and signatureOf(lockedPigments()) ~= lockedSignature
		if section == "*" or section == "Settings" or unlocked then
			InputController.rebuild()
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(clearDash)
	applyBindings()
	log.info("started (%d actions, touch %s)", #boundActions, tostring(UserInputService.TouchEnabled))
end

return InputController
