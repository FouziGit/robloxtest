--!strict
-- UiPrefs: the player's own Roblox accessibility settings, read and followed rather than rebuilt (D-147).
-- Roblox already asks every player whether they want less motion, larger text and opaque backgrounds, in
-- its own menu, and lets an experience read the answers: a toggle of ours for the same thing would be a
-- second switch that disagrees with the first.
--
--   reducedMotion()  GuiService.ReducedMotionEnabled: Motion trades its overshoot for plain springs, loops
--                    stop, staggers land at once, shakes are skipped
--   textScale()      GuiService.PreferredTextSize, as ThemeConfig.TextScale's multiplier of the menus and
--                    toasts (never the HUD, whose geometry is measured)
--   transparency()   GuiService.PreferredTransparency, 0 to 1, default 1: every background transparency
--                    of the interface is multiplied by it, so 0 makes them opaque and 1 changes nothing
--
-- And two things the client knows that Roblox does not, pushed in by the HUD: whether the player turned off
-- "Shakes and flashes" (their Settings.CameraShake), and whether the graphics tier is the lowest one.
--
-- Every read is guarded: an engine that refuses one of these properties leaves its neutral value and one
-- warning naming it, never a broken interface.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log"))
local Signal = require(Packages:WaitForChild("Signal"))
local ThemeConfig = require(Shared:WaitForChild("Config"):WaitForChild("ThemeConfig"))

local log = Log.new("UiPrefs")

local UiPrefs = {}

-- Fired whenever one of the preferences changes, with no arguments: read the getters.
UiPrefs.Changed = Signal.new()

local WATCHED = { "ReducedMotionEnabled", "PreferredTextSize", "PreferredTransparency" }

local reduced = false
local textScale = 1
-- The name of the player's text size (an Enum.PreferredTextSize item), for the Settings screen to show.
local textSize = "Medium"
local transparency = 1
local shakes = true
local lowQuality = false
local started = false

-- One property of GuiService, or nil with a warning naming it.
local function read(property: string): any
	local ok, value = pcall(function(): any
		return (GuiService :: any)[property]
	end)
	if not ok then
		log.warn("could not read GuiService.%s, keeping its neutral value: %s", property, tostring(value))
		return nil
	end
	return value
end

local function refresh()
	reduced = read("ReducedMotionEnabled") == true
	local size = read("PreferredTextSize")
	textScale = if typeof(size) == "EnumItem" then ThemeConfig.TextScale[(size :: EnumItem).Name] or 1 else 1
	textSize = if typeof(size) == "EnumItem" then (size :: EnumItem).Name else "Medium"
	local preferred = read("PreferredTransparency")
	transparency = if type(preferred) == "number" then math.clamp(preferred, 0, 1) else 1
end

-- Reads the settings once and follows them from then on. Called once by the client bootstrap, before any
-- screen is built; calling it again does nothing.
function UiPrefs.start()
	if started then
		return
	end
	started = true
	refresh()
	for _, property in ipairs(WATCHED) do
		local ok, err = pcall(function()
			GuiService:GetPropertyChangedSignal(property):Connect(function()
				refresh()
				UiPrefs.Changed:Fire()
			end)
		end)
		if not ok then
			log.warn("cannot follow GuiService.%s; it is read once: %s", property, tostring(err))
		end
	end
end

function UiPrefs.reducedMotion(): boolean
	return reduced
end

function UiPrefs.textScale(): number
	return textScale
end

-- Which of Roblox's text sizes the player chose: Medium unless they asked for larger.
function UiPrefs.textSize(): string
	return textSize
end

function UiPrefs.transparency(): number
	return transparency
end

-- False when the player turned off "Shakes and flashes": what pulses stands still instead.
function UiPrefs.shakes(): boolean
	return shakes
end

function UiPrefs.setShakes(enabled: boolean)
	if shakes == enabled then
		return
	end
	shakes = enabled
	UiPrefs.Changed:Fire()
end

-- True on the lowest graphics tier: no shimmer, no backdrop splats, no press bursts.
function UiPrefs.lowQuality(): boolean
	return lowQuality
end

function UiPrefs.setLowQuality(low: boolean)
	if lowQuality == low then
		return
	end
	lowQuality = low
	UiPrefs.Changed:Fire()
end

return UiPrefs
