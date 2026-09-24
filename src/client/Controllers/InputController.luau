--!strict
-- InputController: binds every InputConfig action through ContextActionService for keyboard (+ mouse),
-- gamepad and touch, from the player's saved keybinds. Emits `Action(actionId, began)`; ComboController,
-- CombatController and MenuController consume it. `captureNext` suspends the actions and resolves the
-- next raw key of the requested kind for the rebind screen (Escape and the Roblox menu cancel it);
-- `setSuspended` unbinds everything (touch buttons disappear with the bindings) while a menu is open.
-- Touch buttons are laid out in absolute screen space from `InputConfig.Touch`, clear of the engine
-- jump button and of each other (see `touchLayout`).

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

local InputConfig = require(Shared.Config.InputConfig)
local Log = require(Shared.Util.Log)
local PigmentConfig = require(Shared.Config.PigmentConfig)
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
type Rect = { Min: Vector2, Max: Vector2 }
type TouchStyle = { Layout: { [string]: Vector2 }, Size: number, Origin: Vector2 }

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
local CLUSTER_ANCHOR: InputConfig.TouchAnchor = "Cluster"
local ANCHOR_PRIORITY: { [string]: number } = { TopRight = 1, JumpRow = 2, Cluster = 3 }
-- Relaxation passes applied per disc so a clamped placement still respects the minimum distance.
local SEPARATION_PASSES = 4
-- Frames waited for the engine to lay its button frame out (AbsolutePosition is the layout origin).
local LAYOUT_WAIT_FRAMES = 4
local FALLBACK_VIEWPORT = Vector2.new(1280, 720)
local EPSILON = 0.001
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

local bindTrove = Trove.new() -- touch button visuals and layout watchers of the current bindings
local touchVisuals: { [string]: TouchButton.TouchButton } = {}
local boundActions: { string } = {}
local bound = false
local bindGeneration = 0 -- bumped by every bind/unbind so a deferred styling pass can abort
local suspended = false
local capture: Capture? = nil
local warnedKeys: { [string]: boolean } = {}
local hapticSupport: { [Enum.UserInputType]: boolean } = {}
local relayoutTouch: () -> ()

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

-- Diameter of a touch disc in real screen px. The discs are the primary combat controls and sit under
-- no UIScale, so the scaled size is floored at the smallest reliable touch target.
local function touchButtonSize(scale: number): number
	return math.max(InputConfig.Touch.ButtonSize * scale, InputConfig.Touch.MinButtonSize)
end

local function shrink(rect: Rect, amount: Vector2): Rect
	local min = rect.Min + amount
	local max = rect.Max - amount
	return { Min = min, Max = Vector2.new(math.max(min.X, max.X), math.max(min.Y, max.Y)) }
end

local function clampPoint(point: Vector2, bounds: Rect): Vector2
	return Vector2.new(math.clamp(point.X, bounds.Min.X, bounds.Max.X), math.clamp(point.Y, bounds.Min.Y, bounds.Max.Y))
end

-- Screen area below the Roblox top bar; touch buttons are laid out in these absolute coordinates.
local function screenRect(): Rect
	local topInset = GuiService:GetGuiInset()
	return { Min = Vector2.new(0, topInset.Y), Max = viewportSize() }
end

-- The engine jump button once TouchGui exists, else the corner InputConfig reserves for it.
local function jumpRect(screen: Rect): Rect
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touchGui = if playerGui ~= nil then playerGui:FindFirstChild(TOUCH_GUI_NAME) else nil
	local jump = if touchGui ~= nil then touchGui:FindFirstChild(JUMP_BUTTON_NAME, true) else nil
	if jump ~= nil and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 0 then
		return { Min = jump.AbsolutePosition, Max = jump.AbsolutePosition + jump.AbsoluteSize }
	end
	local reserve = InputConfig.Touch.JumpReserve
	return { Min = screen.Max - Vector2.new(reserve.Width, reserve.Height), Max = screen.Max }
end

local function ringOffset(placement: InputConfig.TouchPlacement, step: number): Vector2
	local angle = placement.Angle
	if angle == nil then
		return Vector2.zero
	end
	local radians = math.rad(angle)
	return Vector2.new(math.cos(radians), -math.sin(radians)) * step
end

-- Half extent of the pigment ring: centre to the outermost ring centre, per axis.
local function clusterExtent(step: number): Vector2
	local extent = Vector2.zero
	for _, action in ipairs(InputConfig.Actions) do
		local placement = InputConfig.Touch.Positions[action :: any]
		if placement ~= nil and placement.Anchor == CLUSTER_ANCHOR then
			local offset = ringOffset(placement, step)
			extent = Vector2.new(math.max(extent.X, math.abs(offset.X)), math.max(extent.Y, math.abs(offset.Y)))
		end
	end
	return extent
end

local function placementRank(placement: InputConfig.TouchPlacement): number
	local anchor = ANCHOR_PRIORITY[placement.Anchor] or #InputConfig.Actions
	local detail = placement.Step or 0
	if placement.Anchor == CLUSTER_ANCHOR then
		detail = if placement.Angle == nil then 0 else 1 + placement.Angle / 360
	end
	return anchor * 10 + detail
end

-- Deterministic placement order: the fixed corner first, then the jump row, then the ring.
local function placementOrder(): { string }
	local order: { string } = {}
	for _, action in ipairs(InputConfig.Actions) do
		if InputConfig.Touch.Positions[action :: any] ~= nil then
			table.insert(order, action)
		end
	end
	table.sort(order, function(left: string, right: string): boolean
		local leftRank = placementRank(InputConfig.Touch.Positions[left :: any])
		local rightRank = placementRank(InputConfig.Touch.Positions[right :: any])
		if leftRank == rightRank then
			return left < right
		end
		return leftRank < rightRank
	end)
	return order
end

-- Pushes `point` at least `step` away from every disc placed before it.
local function pushNeighbours(point: Vector2, placed: { Vector2 }, step: number, bounds: Rect): Vector2
	local result = point
	for _, other in ipairs(placed) do
		local delta = result - other
		local distance = delta.Magnitude
		if distance < step - EPSILON then
			local direction = if distance > EPSILON then delta.Unit else Vector2.new(-1, 0)
			result = clampPoint(other + direction * step, bounds)
		end
	end
	return result
end

-- Lifts `point` above the jump button when it fell inside the button plus its clearance.
local function clearJump(point: Vector2, jump: Rect, clearance: number, bounds: Rect): Vector2
	local outside = point.X < jump.Min.X - clearance + EPSILON
		or point.X > jump.Max.X + clearance - EPSILON
		or point.Y < jump.Min.Y - clearance + EPSILON
		or point.Y > jump.Max.Y + clearance - EPSILON
	if outside then
		return point
	end
	return clampPoint(Vector2.new(point.X, jump.Min.Y - clearance), bounds)
end

-- Resolves InputConfig.Touch to absolute screen centres: the pigment ring above and left of the engine
-- jump button, Melee/Block/Dash/LockOn in a row left of it, Menu in the top-right corner. Every centre stays
-- inside the safe area, at least (diameter + gap) from its neighbours and clear of the jump button.
local function touchLayout(scale: number): { [string]: Vector2 }
	local config = InputConfig.Touch
	local diameter = touchButtonSize(scale)
	local radius = diameter * 0.5
	local gap = config.Gap * scale
	local step = diameter + gap
	local clearance = radius + gap
	local screen = screenRect()
	local inset = config.Margin * scale + radius
	local bounds = shrink(screen, Vector2.new(inset, inset))
	local jump = jumpRect(screen)
	local rowY = jump.Min.Y + (jump.Max.Y - jump.Min.Y) * 0.5
	local rowX = jump.Min.X - clearance
	local extent = clusterExtent(step)
	local ringBounds = shrink(bounds, extent)
	local ringCentre = Vector2.new(
		math.max(ringBounds.Min.X, math.min(ringBounds.Max.X, jump.Max.X - extent.X)),
		math.max(
			ringBounds.Min.Y,
			math.min(ringBounds.Max.Y, rowY - step - extent.Y, jump.Min.Y - clearance - extent.Y)
		)
	)
	local centres: { [string]: Vector2 } = {}
	local placed: { Vector2 } = {}
	for _, action in ipairs(placementOrder()) do
		local placement = config.Positions[action :: any]
		local point = ringCentre + ringOffset(placement, step)
		if placement.Anchor == "TopRight" then
			point = Vector2.new(bounds.Max.X, bounds.Min.Y)
		elseif placement.Anchor == "JumpRow" then
			point = Vector2.new(rowX - ((placement.Step or 1) - 1) * step, rowY)
		end
		point = clampPoint(point, bounds)
		for _ = 1, SEPARATION_PASSES do
			local moved = clearJump(pushNeighbours(point, placed, step, bounds), jump, clearance, bounds)
			local settled = (moved - point).Magnitude < EPSILON
			point = moved
			if settled then
				break
			end
		end
		centres[action] = point
		table.insert(placed, point)
	end
	return centres
end

-- Replaces the engine's default touch button look with the themed TouchButton visual.
local function applyTouchButton(action: string, button: ImageButton, style: TouchStyle)
	local centre: Vector2? = style.Layout[action]
	button.Image = ""
	button.PressedImage = ""
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(style.Size, style.Size)
	if centre ~= nil then
		button.Position = UDim2.fromOffset(centre.X - style.Origin.X, centre.Y - style.Origin.Y)
	end

	local isPigment = PigmentConfig.isPigment(action)
	local visual = TouchButton.new({
		-- The short label, not the full name: a disc is Touch.MinButtonSize wide and "Corps à corps"
		-- clips at that width whatever the text size.
		Label = if isPigment
			then PigmentConfig.Sigils[action :: any]
			else localize.t(
				InputConfig.ActionShortKeys[action :: any] or InputConfig.ActionNameKeys[action :: any]
			),
		Color = if isPigment then Theme.pigmentColor(action) else Theme.Colors.PanelRaised,
		Size = style.Size,
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = button,
		Name = action,
	})
	visual.Instance.Interactable = false -- the ContextActionService button underneath receives the touch
	bindTrove:Add(visual)
	touchVisuals[action] = visual
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
	local scale = touchScale()
	local style: TouchStyle = {
		Layout = touchLayout(scale),
		Size = touchButtonSize(scale),
		Origin = frame.AbsolutePosition,
	}
	for _, action in ipairs(boundActions) do
		local button: ImageButton? = buttons[action]
		if button ~= nil then
			applyTouchButton(action, button, style)
		end
	end
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

local function bindAll()
	if bound then
		return
	end
	bound = true
	bindGeneration += 1
	local generation = bindGeneration
	local keyboard = keybinds("Keyboard")
	local gamepad = keybinds("Gamepad")
	local touch = UserInputService.TouchEnabled

	for _, action in ipairs(InputConfig.Actions) do
		local inputs = bindInputs(action, keyboard, gamepad)
		if #inputs == 0 and not touch then
			continue
		end
		ContextActionService:BindActionAtPriority(action, onAction, touch, ACTION_PRIORITY, table.unpack(inputs))
		table.insert(boundActions, action)
	end
	if not touch then
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
		if section == "*" or section == "Settings" then
			InputController.rebuild()
		end
	end)
	applyBindings()
	log.info("started (%d actions, touch %s)", #boundActions, tostring(UserInputService.TouchEnabled))
end

return InputController
