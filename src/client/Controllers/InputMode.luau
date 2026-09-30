--!strict
-- InputMode: the one place that decides how the player is playing right now, and the one reader of the device's
-- touch screen (D-XXX). Three modules used to decide it three ways: Theme called a touch screen with no keyboard a
-- phone, the HUD and the discs called any touch screen one, and the key hints followed the type of the last input.
-- A touch laptop got the pointer's scale and corner with the phone's discs over them, and a tablet with a pad
-- pressed its buttons under discs nobody touched.
--
-- The engine's own answer is UserInputService.PreferredInput: the input the player is most likely using, from the
-- devices there and the one used last, updated as they switch. It is read whenever it can be; where it cannot,
-- the devices decide the way Theme did: a touch screen with no keyboard is touch, a pad's last input is a pad,
-- anything else is a pointer.
--   get()       "Touch" | "Pointer" | "Gamepad": which discs are bound (InputController), which shortcuts show
--               and which keys the hints draw (HudController, and src/ui through Theme.input)
--   handheld()  a screen held in the hand: touched now, or a touch screen with no keyboard -- a phone or a tablet,
--               whatever pad is paired to it. The interface's scale floor and its phone layouts (Theme.touchOnly)
--   Changed     fired with get() whenever either answer changes
--
-- Started by the client bootstrap before any screen is built, and handed to src/ui through Theme.useInput, as
-- UiPrefs and UiSound are: src/ui never requires a controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log"))
local Signal = require(Packages:WaitForChild("Signal"))

local log = Log.new("InputMode")

export type Mode = "Touch" | "Pointer" | "Gamepad"

local PREFERRED = "PreferredInput"
local GAMEPAD_PREFIX = "Gamepad"

local InputMode = {}

-- (mode: Mode) -- fired whenever get() or handheld() changes.
InputMode.Changed = Signal.new()

local mode: Mode = "Pointer"
local handheld = false
local started = false
-- An engine that does not answer PreferredInput is said so once; the devices decide from then on.
local preferredWarned = false

-- The engine's answer, or nil where it gives none.
local function preferred(): Mode?
	local ok, value = pcall(function(): any
		return (UserInputService :: any)[PREFERRED]
	end)
	if ok and typeof(value) == "EnumItem" then
		if value == Enum.PreferredInput.Touch then
			return "Touch"
		elseif value == Enum.PreferredInput.KeyboardAndMouse then
			return "Pointer"
		end
		-- A pad, or the remote the engine counts as a small one.
		return "Gamepad"
	end
	if not preferredWarned then
		preferredWarned = true
		log.warn("could not read UserInputService.%s (%s): the devices decide", PREFERRED, tostring(value))
	end
	return nil
end

-- A touch screen and no keyboard: a phone or a tablet, in the hand.
local function touchScreenOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- The devices' answer, where the engine gives none: Theme's old rule for touch, the last input for a pad.
local function fromDevices(): Mode
	if touchScreenOnly() then
		return "Touch"
	end
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, #GAMEPAD_PREFIX) == GAMEPAD_PREFIX then
		return "Gamepad"
	end
	return "Pointer"
end

local function read(): (Mode, boolean)
	local current: Mode = preferred() or fromDevices()
	return current, current == "Touch" or touchScreenOnly()
end

local function announce()
	log.info("playing by %s%s", mode, if handheld then ", in the hand" else "")
end

local function refresh()
	local nextMode: Mode, nextHandheld: boolean = read()
	if nextMode == mode and nextHandheld == handheld then
		return
	end
	mode = nextMode
	handheld = nextHandheld
	announce()
	InputMode.Changed:Fire(mode)
end

-- How the player plays right now.
function InputMode.get(): Mode
	return mode
end

-- Whether the screen is held in the hand (see the header).
function InputMode.handheld(): boolean
	return handheld
end

-- Reads the input once and follows it from then on. Called once by the client bootstrap, before any screen is
-- built; calling it again does nothing.
function InputMode.start()
	if started then
		return
	end
	started = true
	mode, handheld = read()
	local ok, err = pcall(function()
		UserInputService:GetPropertyChangedSignal(PREFERRED):Connect(refresh)
	end)
	if not ok then
		log.warn("cannot follow UserInputService.%s; the last input is followed instead: %s", PREFERRED, tostring(err))
	end
	-- A keyboard plugged into a tablet has no signal of its own; the next input it makes re-reads the devices.
	UserInputService.LastInputTypeChanged:Connect(refresh)
	announce()
end

return InputMode
