--!strict
-- The fight's HUD (D-147): the dock under the player's thumbs, and what stands over it. Its pieces are engine
-- code Lune cannot run, so what can regress silently is held by reading them -- a low health that stops
-- burning, a dock that grows over the discs, a colour that loses its meaning -- and the numbers they are
-- built from are checked here.
local GameConfig = require("../src/shared/Config/GameConfig")
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
local COMBO_ROW = "src/ui/components/ComboRow.luau"
local COMBO_CONTROLLER = "src/client/Controllers/ComboController.luau"
local GLYPH_SERVICE = "src/server/Services/GlyphService.luau"
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

-- The keys of the table literal `name` in `source`.
local function keysOf(source: string, name: string): { [string]: boolean }
	local block = string.match(source, "local " .. name .. ": { %[string%]: boolean } = (%b{})")
	assert(block ~= nil, ("no table %s: this gate would check nothing"):format(name))
	local keys: { [string]: boolean } = {}
	for key in string.gmatch(block :: string, '%["([%w%.]+)"%] = true') do
		keys[key] = true
	end
	return keys
end

describe("the combo row", function()
	it("says a refused cast under the chips, which shake, and never as a toast", function()
		local hud = code(HUD_CONTROLLER)
		local inline = keysOf(hud, "INLINE_KEYS")
		local expected = {
			"hud.cast.cooldown",
			"hud.cast.notEnoughInk",
			"hud.cast.locked",
			"hud.cast.notEquipped",
			"hud.cast.failed",
			"hud.combo.noMatch",
			"hud.combo.dissipated",
		}
		local count = 0
		for _ in pairs(inline) do
			count += 1
		end
		expect(count).toBe(#expected)
		-- Every one of them is really said, by the server or by the combo controller.
		local sayers = code(GLYPH_SERVICE) .. code(COMBO_CONTROLLER)
		for _, key in ipairs(expected) do
			expect(inline[key]).toBe(true)
			if not has(sayers, '"' .. key .. '"') then
				error(key .. " is routed under the chips, and nothing says it")
			end
		end
		local show = body(hud, "show")
		local refused = string.find(show, "if INLINE_KEYS[key] then comboRow:Refuse(text)", 1, true)
		local toasted = string.find(show, "toast:Show(", 1, true)
		assert(refused ~= nil and toasted ~= nil, "show no longer routes a refusal under the chips")
		expect(refused :: number).toBeLessThan(toasted :: number)
		-- A cooldown flashes the glyph's slot, found by the name key the server sends with it.
		expect(has(hud, 'local COOLDOWN_KEY = "hud.cast.cooldown"\n')).toBe(true)
		expect(has(show, 'if key == COOLDOWN_KEY and type(name) == "string" then hotbar:Refuse(name) end')).toBe(true)
		expect(has(code(GLYPH_SERVICE), '"hud.cast.cooldown", { name = def.NameKey, seconds = seconds }')).toBe(true)
		expect(has(body(code(HOTBAR), "refuse"), "def.NameKey == nameKey")).toBe(true)
		-- The words, on an ink pill, for a moment; the chips shake.
		local row = code(COMBO_ROW)
		local refuse = body(row, "refuse")
		expect(has(refuse, "refusalText.Text = text")).toBe(true)
		expect(has(refuse, "Motion.shake(line, SHAKE)")).toBe(true)
		expect(number(row, "REFUSAL_SECONDS")).toBe(1.4)
		expect(number(row, "SHAKE")).toBe(8)
		expect(has(row, 'local text = label("Text", Theme.Fonts.Bold, REFUSAL_TEXT, Theme.Colors.TextInverse)')).toBe(
			true
		)
	end)

	it("turns a chain's refund into ink on the ink bar, and leaves the chain to the counter", function()
		local hud = code(HUD_CONTROLLER)
		expect(has(hud, 'local CHAIN_KEY = "hud.cast.chain"\n')).toBe(true)
		expect(
			has(
				body(hud, "show"),
				'elseif key == CHAIN_KEY then if type(ink) == "number" then combatDock:GainInk(ink) end'
			)
		).toBe(true)
		expect(has(code(GLYPH_SERVICE), "ink = GameConfig.Combo.ChainInkRefund")).toBe(true)
		expect(has(body(code(DOCK), "gainInk"), "inkBar:Gain(amount, Theme.Glyphs.Plus .. tostring(amount))")).toBe(
			true
		)
		expect(GameConfig.Combo.ChainInkRefund).toBeGreaterThan(0)
	end)

	it("names the glyph the sequence already is while the controller waits, and drains the wait", function()
		local combo = code(COMBO_CONTROLLER)
		expect(has(combo, "setPreview(ComboResolver.resolve(resolver, next), GameConfig.Combo.ExtendWindowSeconds)")).toBe(
			true
		)
		-- Cleared on every other outcome: a cast, a reset, the wait running out, a menu.
		expect(select(2, string.gsub(combo, "setPreview%(nil%)", ""))).toBeGreaterThanOrEqual(5)
		local row = code(COMBO_ROW)
		local preview = body(row, "setPreview")
		expect(has(preview, "local fill = Theme.pigmentOnInk(def.Pigment)")).toBe(true)
		expect(has(preview, 'previewStroke.Enabled = def.Pigment == "Umber"')).toBe(true)
		expect(has(preview, 'previewText.Text = Theme.Glyphs.Arrow .. " " .. localize.t(def.NameKey)')).toBe(true)
		expect(has(preview, 'Motion.to(previewLine, { Size = UDim2.fromOffset(0, PREVIEW_LINE) }, "Ui")')).toBe(true)
		expect(GameConfig.Combo.ExtendWindowSeconds).toBeGreaterThan(0)
		-- Every pigment's name reads on the ink pill: the four with a colour, and Umber as the sheet.
		for _, pigment in ipairs(PigmentConfig.Order) do
			local onInk = ThemeConfig.PigmentOnInk[pigment] or COLORS.PanelRaised
			expect(ThemeConfig.contrast(onInk, COLORS.Plate)).toBeGreaterThanOrEqual(GRAPHIC_CONTRAST)
		end
	end)

	it("marks the pending glyph's cost on the ink bar, and warns before the last press", function()
		expect(has(body(code(HUD_CONTROLLER), "onPreview"), "combatDock:SetCost(if def ~= nil then def.Cost else nil)")).toBe(
			true
		)
		local cost = body(code(DOCK), "setCost")
		expect(has(cost, "costTick.Position = UDim2.fromScale(math.clamp(cost / maxInk, 0, 1), 0.5)")).toBe(true)
		expect(has(cost, "if ink < cost then flashRing() end")).toBe(true)
		local flash = body(code(DOCK), "flashRing")
		expect(select(2, string.gsub(flash, "Theme%.Colors%.Chalk", ""))).toBe(2)
		-- Neutral: neither red nor a value colour, since it is a warning, not a danger.
		expect(has(flash, "Danger")).toBe(false)
	end)

	it("hints the next pigments after one press or two: one step ahead, never the whole tree", function()
		local hud = code(HUD_CONTROLLER)
		expect(number(hud, "HINT_MIN_PRESSES")).toBe(1)
		expect(number(hud, "HINT_MAX_PRESSES")).toBe(2)
		local sequence = body(hud, "onSequence")
		expect(has(sequence, "local hinted = #sequence >= HINT_MIN_PRESSES and #sequence <= HINT_MAX_PRESSES")).toBe(
			true
		)
		expect(
			has(sequence, "comboRow:SetContinuations(if hinted then comboController.continuations(sequence) else {})")
		).toBe(true)
		expect(has(code(COMBO_CONTROLLER), "return ComboResolver.continuations(resolver, pending)")).toBe(true)
		expect(has(code(COMBO_ROW), 'replaceFaint(nexts, "Next", NEXT_ORDER, pigments)')).toBe(true)
	end)

	it("keeps its order: the chips, the next pigments, the preview, the chain, the ghosts", function()
		local row = code(COMBO_ROW)
		local stride = number(row, "CHIP_ORDER_STRIDE")
		local lastChip = GameConfig.Combo.MaxLength * stride + 1
		local nextOrder = number(row, "NEXT_ORDER")
		expect(lastChip).toBeLessThan(nextOrder)
		expect(nextOrder + 5).toBeLessThan(number(row, "PREVIEW_ORDER"))
		expect(number(row, "PREVIEW_ORDER")).toBeLessThan(number(row, "STREAK_ORDER"))
		expect(number(row, "STREAK_ORDER")).toBeLessThan(number(row, "GHOST_ORDER"))
		expect(number(row, "STREAK_ORDER")).toBe(160)
		expect(number(row, "PREVIEW_ORDER")).toBe(150)
	end)

	it("grows the chain counter with the chain, on a splat from four and a ring from six", function()
		local row = code(COMBO_ROW)
		local cast = body(row, "cast")
		expect(has(cast, "local rest = math.min(STREAK_MAX_SCALE, 1 + STREAK_GROWTH * (streak - STREAK_MIN_SHOWN))")).toBe(
			true
		)
		expect(has(cast, 'Motion.to(streakScale, { Scale = rest }, "UiPop")')).toBe(true)
		expect(has(cast, "color, edge = Theme.pigmentOnInk(pigment)")).toBe(true)
		expect(number(row, "STREAK_GROWTH")).toBe(0.08)
		expect(number(row, "STREAK_MAX_SCALE")).toBe(1.4)
		expect(number(row, "STREAK_SPLAT")).toBe(4)
		expect(number(row, "STREAK_RING")).toBe(6)
		expect(has(body(row, "streakBacking"), "if streak < STREAK_SPLAT then")).toBe(true)
		expect(has(body(row, "streakPulse"), "if streak < STREAK_RING then")).toBe(true)
		expect(has(code(HUD_CONTROLLER), "comboRow:Cast(chain, if def ~= nil then def.Pigment else nil)")).toBe(true)
	end)

	it("draws each press as a sticker of its pigment, popping in, dark pigments ringed", function()
		local row = code(COMBO_ROW)
		expect(HUD.ChipSize).toBe(44)
		expect(has(row, "local CHIP_SIZE = HUD.ChipSize\n")).toBe(true)
		expect(has(body(row, "grow"), 'Motion.to(chip, { Size = CHIP_OPEN }, "UiPop")')).toBe(true)
		expect(has(body(row, "fold"), '"UiSnappy"')).toBe(true)
		local chip = body(row, "makeChip")
		expect(has(chip, "local color = Theme.pigmentColor(pigment)")).toBe(true)
		expect(has(chip, 'Kind = "Card",')).toBe(true)
		expect(has(row, "local RINGED: { [string]: boolean } = { Indigo = true, Umber = true }")).toBe(true)
		expect(has(chip, "Theme.inkOn(color)")).toBe(true)
	end)
end)
