--!strict
-- The fight's HUD (D-147): the dock under the player's thumbs, and what stands over it. Its pieces are engine
-- code Lune cannot run, so what can regress silently is held by reading them -- a low health that stops
-- burning, a dock that grows over the discs, a colour that loses its meaning -- and the numbers they are
-- built from are checked here.
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
local DOCK = "src/ui/components/CombatDock.luau"
local HOTBAR = "src/ui/components/Hotbar.luau"
local HUD = ThemeConfig.Hud
local COLORS = ThemeConfig.Colors
local GRAPHIC_CONTRAST = 3
local BODY_CONTRAST = 4.5

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function code(path: string): string
	return stripComments(fs.readFile(path))
end

-- The body of the local function `name` in `source`, up to its closing `end` at the same indent, folded.
local function body(source: string, name: string): string
	local indent, rest = string.match(source, "\n(\t*)local function " .. name .. "%((.*)")
	assert(indent ~= nil and rest ~= nil, ("no local function %s: this gate would check nothing"):format(name))
	local finish = string.find(rest :: string, "\n" .. (indent :: string) .. "end\n", 1, true)
	assert(finish ~= nil, ("%s has no end"):format(name))
	return (string.gsub(string.sub(rest :: string, 1, finish :: number), "%s+", " "))
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

local function number(source: string, name: string): number
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("no number %s: this gate would check nothing"):format(name))
	return value :: number
end

describe("the combat dock", function()
	it("says low health four ways: a red, hatched, pulsing bar, burning edges, and one sound", function()
		local dock = code(DOCK)
		expect(HUD.LowHealthFraction).toBe(0.3)
		local state = body(dock, "setState")
		expect(has(state, "setLow(state.MaxHealth > 0 and state.Health <= state.MaxHealth * HUD.LowHealthFraction)")).toBe(
			true
		)
		local low = body(dock, "setLow")
		local guard = string.find(low, "if next == low then return end", 1, true)
		local bar = string.find(low, "healthBar:SetLow(next)", 1, true)
		local sound = string.find(low, "if next then UiSound.play(LOW_SOUND) end", 1, true)
		assert(guard ~= nil and bar ~= nil and sound ~= nil, "setLow no longer turns the bar and sounds the line")
		-- Once, as the line is crossed: a push that stays low sounds nothing.
		expect(guard :: number).toBeLessThan(sound :: number)
		expect(has(low, "refreshEdges()")).toBe(true)
		expect(has(dock, 'local LOW_SOUND = "Error"\n')).toBe(true)
		expect(SoundConfig.Sfx.Error ~= nil).toBe(true)
		-- The edges: the linear gradient, in Cinnabar, breathing between two faint transparencies.
		expect(has(dock, 'Theme.texture("GradientLinear")')).toBe(true)
		expect(has(dock, "strip.ImageColor3 = Theme.Colors.Danger")).toBe(true)
		expect(number(dock, "VIGNETTE_FROM")).toBe(0.55)
		expect(number(dock, "VIGNETTE_TO")).toBe(0.75)
		expect(number(dock, "VIGNETTE_DEPTH")).toBe(0.18)
		expect(has(dock, 'Breath.join("LowHealth", VIGNETTE_FROM, VIGNETTE_TO, VIGNETTE_HOLD, "Ui")')).toBe(true)
	end)

	it("keeps the edges still for a player who asked for no shakes or less motion", function()
		local dock = code(DOCK)
		expect(number(dock, "VIGNETTE_STILL")).toBe(0.7)
		local edges = body(dock, "refreshEdges")
		expect(has(edges, "vignette.Visible = low")).toBe(true)
		expect(has(edges, "local breathes = low and UiPrefs.shakes() and not UiPrefs.reducedMotion()")).toBe(true)
		expect(has(edges, "if not breathes then stopBreath() setEdges(VIGNETTE_STILL) return end")).toBe(true)
		expect(has(dock, "UiPrefs.Changed:Connect(refreshEdges)")).toBe(true)
		-- And the HUD tells the interface what the player chose.
		local prefs = body(code(HUD_CONTROLLER), "refreshPrefs")
		expect(has(prefs, "UiPrefs.setShakes(data.Settings.CameraShake ~= false)")).toBe(true)
		expect(
			has(prefs, "UiPrefs.setLowQuality(qualityController.get() == QualityConfig.Order[#QualityConfig.Order])")
		).toBe(true)
		expect(QualityConfig.Order[#QualityConfig.Order]).toBe("Performance")
		local hud = code(HUD_CONTROLLER)
		expect(has(body(hud, "refreshProfile"), "refreshPrefs(data)")).toBe(true)
		expect(
			string.find(hud, "qualityController%.Changed:Connect%(function%(%)%s+refreshPrefs%(clientData%.get%(%)%)")
		).never.toBeNil()
	end)

	it("keeps each colour's meaning: cyan is us, the ink is Indigo, red is only danger (rules 7 and 11)", function()
		local dock = code(DOCK)
		expect(has(dock, "Color = Theme.Colors.Health,")).toBe(true)
		expect(has(dock, "Ghost = Theme.Colors.Danger,")).toBe(true)
		expect(has(dock, "Color = Theme.Colors.Ink,")).toBe(true)
		expect(select(2, string.gsub(dock, "OnPlate = true,", ""))).toBe(2)
		expect(COLORS.Health).toEqual(COLORS.Ally)
		expect(COLORS.Ink).toEqual(COLORS.InfoFill)
		-- Every fill stands out from its well, and the ghost from the well and from the cyan beside it.
		for _, fill in ipairs({ COLORS.Health, COLORS.Ink, COLORS.DangerFill, COLORS.Danger }) do
			expect(ThemeConfig.contrast(fill, COLORS.Well)).toBeGreaterThanOrEqual(GRAPHIC_CONTRAST)
		end
		expect(ThemeConfig.contrast(COLORS.Danger, COLORS.Health)).toBeGreaterThanOrEqual(GRAPHIC_CONTRAST)
		-- The numbers are vellum on the ink plate.
		expect(has(dock, "label.TextColor3 = Theme.Colors.TextInverse")).toBe(true)
		expect(ThemeConfig.contrast(COLORS.TextInverse, COLORS.Plate)).toBeGreaterThanOrEqual(BODY_CONTRAST)
		expect(has(dock, 'Kind = "Plate",')).toBe(true)
		expect(has(dock, 'Theme.stroke(ring, "PanelRaised", Theme.Sizes.StrokeThin)')).toBe(true)
	end)

	it("lights its diamond while the player guards, and its dot while the ink waits", function()
		local state = body(code(DOCK), "setState")
		expect(
			has(
				state,
				"diamond.BackgroundColor3 = if state.Blocking then Theme.Colors.PanelRaised else Theme.Colors.Chalk"
			)
		).toBe(true)
		expect(has(state, "combatDot.Visible = state.InCombat")).toBe(true)
	end)

	it("is as tall as what it holds, and fits between the thumbs on a phone", function()
		local dock = code(DOCK)
		local held = number(dock, "HEALTH_HEIGHT")
			+ number(dock, "INK_HEIGHT")
			+ number(dock, "PADDING") * 2
			+ number(dock, "GAP")
		expect(held).toBe(HUD.DockHeight)
		-- The thumbs leave about 264 points between them on the smallest landscape phone.
		expect(HUD.DockWidthTouchMax * ThemeConfig.Scale.TouchFloor).toBeLessThanOrEqual(264)
		local fit = body(code(HUD_CONTROLLER), "fitDock")
		expect(has(fit, "nearest = math.min(nearest, rect.Min.X)")).toBe(true)
		expect(has(fit, "local free = 2 * (nearest - DOCK_DISC_CLEARANCE - centre)")).toBe(true)
		expect(has(fit, "combatDock:SetWidth(math.min(HUD.DockWidthTouchMax, free / root:GetScale()))")).toBe(true)
		local hud = code(HUD_CONTROLLER)
		expect(has(hud, "inputController.TouchLayoutChanged:Connect(fitDock)")).toBe(true)
		expect(has(hud, "Width = if touch then HUD.DockWidthTouchMax else HUD.DockWidthPointer,")).toBe(true)
	end)
end)

describe("the hotbar", function()
	it("draws every equipped glyph in its own pigment, over the keys that cast it", function()
		local hotbar = code(HOTBAR)
		local draw = body(hotbar, "draw")
		expect(has(draw, "fill(slot, Theme.pigmentColor(def.Pigment), false)")).toBe(true)
		expect(has(draw, "sigil.Text = PigmentConfig.Sigils[def.Pigment :: any]")).toBe(true)
		local keys = body(hotbar, "drawKeys")
		expect(has(keys, "for step, pigment in ipairs(def.Combo) do")).toBe(true)
		expect(has(keys, "Key = keys[pigment]")).toBe(true)
		-- Each key wears the strip of the pigment it presses: the legend of the keyboard.
		expect(has(keys, "Pigment = pigment,")).toBe(true)
		-- The sigil reads on whatever the chip is filled with.
		expect(has(body(hotbar, "fill"), "sigil.TextColor3 = Theme.inkOn(color)")).toBe(true)
		-- The player's own keys, for every pigment, on the device in use.
		local refresh = body(code(HUD_CONTROLLER), "refreshHotbarKeys")
		expect(has(refresh, "for _, pigment in ipairs(PigmentConfig.Order) do")).toBe(true)
		expect(has(refresh, "keys[pigment] = saved[pigment] or defaults[pigment]")).toBe(true)
		expect(has(refresh, 'hotbar:SetKeys(if gamepad then "Gamepad" else "Keyboard", keys)')).toBe(true)
		expect(#PigmentConfig.Order).toBe(5)
		local profile = body(code(HUD_CONTROLLER), "refreshProfile")
		expect(has(profile, "hotbar:SetLoadout(data.Loadout.Slots)")).toBe(true)
		expect(has(profile, "refreshHotbarKeys(data)")).toBe(true)
	end)

	it("drains a cooling glyph at the server's pace and pops it when it is ready, rebuilding nothing", function()
		local hotbar = code(HOTBAR)
		local state = body(hotbar, "setState")
		expect(
			has(state, "local fraction = if def.Cooldown > 0 then math.clamp(remaining / def.Cooldown, 0, 1) else 0")
		).toBe(true)
		local changed = string.find(state, "if fraction ~= slot.Fraction then", 1, true)
		local sprung =
			string.find(state, 'Motion.to(slot.Drain, { Size = UDim2.fromScale(1, fraction) }, "UiSnappy")', 1, true)
		assert(changed ~= nil and sprung ~= nil, "the drain no longer springs to the cooldown")
		expect(changed :: number).toBeLessThan(sprung :: number)
		expect(has(state, "if slot.Remaining > 0 and remaining <= 0 then ready(slot) end")).toBe(true)
		expect(number(hotbar, "READY_PUNCH")).toBe(1.12)
		expect(has(body(hotbar, "ready"), "Motion.punch(slot.Scale, READY_PUNCH)")).toBe(true)
		-- Five pushes a second allocate nothing: the slots are pooled by index.
		expect(has(state, "Instance.new")).toBe(false)
		expect(has(state, "Keycap.new")).toBe(false)
		expect(has(state, "Motion.loop")).toBe(false)
		expect(has(code(HUD_CONTROLLER), "hotbar:SetState(state)")).toBe(true)
	end)

	it("chalks a glyph the ink cannot pay for, and marks it with a drop", function()
		local hotbar = code(HOTBAR)
		local state = body(hotbar, "setState")
		expect(has(state, "local unaffordable = state.Ink < def.Cost")).toBe(true)
		expect(has(state, "if unaffordable then Theme.Colors.Chalk else Theme.pigmentColor(def.Pigment)")).toBe(true)
		expect(has(state, "drop.Visible = unaffordable")).toBe(true)
		expect(has(hotbar, 'Icon.new("Drop", DROP, Theme.Colors.InfoFill)')).toBe(true)
		expect(ThemeConfig.contrast(COLORS.InfoFill, COLORS.Plate)).toBeGreaterThanOrEqual(GRAPHIC_CONTRAST)
	end)

	it("keys the slots with a pointer, and puts pips inside the dock on touch", function()
		local hud = code(HUD_CONTROLLER)
		expect(has(hud, 'Mode = if touch then "Pips" else "Slots",')).toBe(true)
		expect(has(hud, "Parent = if touch then combatDock.PipRow or bottomStack else bottomStack,")).toBe(true)
		expect(has(hud, "Pips = touch,")).toBe(true)
		local hotbar = code(HOTBAR)
		-- A cap on its three-unit lip fills the key strip exactly; ten pips still fit the touch dock.
		expect(has(hotbar, "local CAP = HUD.HotbarKeyStrip - 3\n")).toBe(true)
		local shrunk = HUD.HotbarPipsHeight - number(hotbar, "PIP_SHRINK")
		local ten = 10 * shrunk + 9 * number(hotbar, "PIP_GAP")
		expect(ten).toBeLessThanOrEqual(HUD.DockWidthTouchMax - 2 * number(code(DOCK), "PADDING"))
		expect(HUD.HotbarSlot).toBe(56)
		expect(HUD.HotbarPipsHeight).toBe(26)
		local dock = code(DOCK)
		expect(has(dock, "local height = HUD.DockHeight + (if props.Pips then HUD.HotbarPipsHeight + GAP else 0)")).toBe(
			true
		)
	end)
end)
