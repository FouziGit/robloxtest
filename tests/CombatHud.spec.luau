--!strict
-- The fight's HUD (D-147): the dock under the player's thumbs, and what stands over it. Its pieces are engine
-- code Lune cannot run, so what can regress silently is held by reading them -- a low health that stops
-- burning, a dock that grows over the discs, a colour that loses its meaning -- and the numbers they are
-- built from are checked here.
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
local DOCK = "src/ui/components/CombatDock.luau"
local HOTBAR = "src/ui/components/Hotbar.luau"
local COMBO_ROW = "src/ui/components/ComboRow.luau"
local COMBO_CONTROLLER = "src/client/Controllers/ComboController.luau"
local GLYPH_SERVICE = "src/server/Services/GlyphService.luau"
local SCORE_BAND = "src/ui/components/ScoreBand.luau"
local BOSS = "src/client/Controllers/BossController.luau"
local TRAVEL = "src/client/Controllers/TravelController.luau"
local TOAST = "src/ui/components/Toast.luau"
local BANNER = "src/ui/components/Banner.luau"
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
		-- The numbers are the sheet on the ink plate, as the board writes them.
		expect(has(dock, "label.TextColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(has(dock, "TextInverse")).toBe(false)
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Plate)).toBeGreaterThanOrEqual(BODY_CONTRAST)
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
		-- The span itself is TouchCluster.dockSpan's, run on real phones in tests/TouchCluster.spec.luau.
		expect(has(fit, "local width, offset = TouchCluster.dockSpan(nearest, centre, root:GetScale(), DOCK_SPAN)")).toBe(
			true
		)
		expect(has(fit, "combatDock:SetWidth(width)")).toBe(true)
		expect(has(fit, "bottomStack.Position = UDim2.new(0.5, offset, 1, -HUD.DockBottomPadTouch)")).toBe(true)
		expect(
			has(
				code(HUD_CONTROLLER),
				"local DOCK_SPAN = { Clearance = DOCK_DISC_CLEARANCE, Widest = HUD.DockWidthTouchMax, Narrowest = HUD.DockWidthTouchMin }"
			)
		).toBe(true)
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
		-- Each key wears the strip of the pigment it presses: the legend of the keyboard, standing on no lip.
		expect(has(keys, "Pigment = pigment,")).toBe(true)
		expect(has(keys, "Lip = false,")).toBe(true)
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
		-- On a rim of the sheet, the same drop a size larger (run in tests/BottomStack.spec.luau).
		expect(has(hotbar, 'Icon.new("Drop", rimmed, Theme.Colors.PanelRaised)')).toBe(true)
		expect(has(hotbar, "local rimmed = DROP + DROP_RIM * 2")).toBe(true)
		expect(number(hotbar, "DROP_RIM")).toBe(2)
	end)

	it("keys the slots with a pointer, and puts pips inside the dock on touch", function()
		local hud = code(HUD_CONTROLLER)
		expect(has(hud, 'Mode = if touch then "Pips" else "Slots",')).toBe(true)
		expect(has(hud, "Parent = if touch then combatDock.PipRow or bottomStack else bottomStack,")).toBe(true)
		expect(has(hud, "Pips = touch,")).toBe(true)
		local hotbar = code(HOTBAR)
		-- A cap of 19 in the key strip, on no lip: the three left are the gap under the slot. How many pips fit
		-- the dock is run in tests/BottomStack.spec.luau.
		expect(has(hotbar, "local CAP = HUD.HotbarKeyStrip - 3\n")).toBe(true)
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
		expect(has(preview, "local fill, edge = Theme.pigmentOnInk(def.Pigment)")).toBe(true)
		expect(has(preview, "previewText.Text = localize.t(def.NameKey)")).toBe(true)
		expect(has(preview, 'Motion.to(previewLine, { Size = UDim2.fromOffset(0, PREVIEW_LINE) }, "Ui")')).toBe(true)
		expect(GameConfig.Combo.ExtendWindowSeconds).toBeGreaterThan(0)
		-- The window is held at its left end and drains from its right, inside the pill's ends (the board's 14).
		expect(has(row, "previewLine.AnchorPoint = Vector2.new(0, 1)")).toBe(true)
		expect(has(row, "previewLine.Position = UDim2.new(0, PREVIEW_PADDING, 1, -PREVIEW_LINE)")).toBe(true)
		expect(number(row, "PREVIEW_PADDING")).toBe(14)
		expect(has(preview, "Motion.set(previewLine, { Size = UDim2.new(1, -PREVIEW_PADDING * 2, 0, PREVIEW_LINE) })")).toBe(
			true
		)
		-- The chips stand the board's gap apart, and the ghosts' keys stay over their chips.
		expect(has(row, "layout.Padding = UDim.new(0, HUD.ChipRowGap)")).toBe(true)
		expect(has(row, "keyLayout.Padding = UDim.new(0, HUD.ChipRowGap)")).toBe(true)
		expect(HUD.ChipRowGap).toBe(8)
		-- How every pigment's name reads on the ink pill is run in tests/BottomStack.spec.luau.
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
		expect(has(sequence, "local nexts = if hinted then comboController.continuations(sequence) else {}")).toBe(true)
		expect(has(sequence, "comboRow:SetContinuations(nexts)")).toBe(true)
		-- On touch the same pigments breathe on their discs, and nothing else does.
		expect(has(sequence, "inputController.setHints(SEQUENCE_HINTS, nexts)")).toBe(true)
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

describe("the top bands", function()
	it("score the match cyan for us and the sheet for them, straight on an ink pill, never red", function()
		local band = code(SCORE_BAND)
		expect(has(band, 'local oursScore = line("Ours", Theme.Fonts.Numeric, SCORE_TEXT, Theme.Colors.Ally, 1, top)')).toBe(
			true
		)
		expect(
			has(
				band,
				'local theirsScore = line("Theirs", Theme.Fonts.Numeric, SCORE_TEXT, Theme.Colors.PanelRaised, 3, top)'
			)
		).toBe(true)
		expect(has(band, "local SCORE_TEXT = Theme.Sizes.Num\n")).toBe(true)
		-- On the ink itself: no pill of their own, ringed or lipped.
		expect(has(band, "Sticker")).toBe(false)
		expect(has(band, "Corner = Theme.Pill,")).toBe(true)
		-- Red is what is about to hit you, and the other team is not that (D-89).
		expect(string.find(band, "Danger")).toBeNil()
		expect(ThemeConfig.contrast(COLORS.Ally, COLORS.Plate)).toBeGreaterThanOrEqual(BODY_CONTRAST)
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Plate)).toBeGreaterThanOrEqual(BODY_CONTRAST)
		expect(ThemeConfig.contrast(COLORS.Chalk, COLORS.Plate)).toBeGreaterThanOrEqual(BODY_CONTRAST)
	end)

	it("ring each fighter with their health, ours cyan, and rewrite a ring only when it moved", function()
		local band = code(SCORE_BAND)
		local disc = body(band, "member")
		expect(has(disc, 'Theme.stroke( disc, if ally then "Ally" else "PanelRaised", if ally then ALLY_RING else')).toBe(
			true
		)
		expect(number(band, "ALLY_RING")).toBe(3)
		expect(has(disc, 'local arc = Theme.gradient("ResultRing") arc.Parent = edge')).toBe(true)
		expect(ThemeConfig.Gradients.ResultRing.Kind).toBe("Conical")
		local refresh = body(band, "refreshMember")
		local moved = string.find(refresh, "if fraction ~= entry.Fraction then", 1, true)
		local written = string.find(refresh, "entry.Arc.Transparency = Theme.ringTransparency(fraction)", 1, true)
		assert(moved ~= nil and written ~= nil, "the rings are no longer drawn from the health")
		expect(moved :: number).toBeLessThan(written :: number)
		-- A fallen fighter: chalk under a cross, faded.
		expect(has(refresh, "if fighter.Alive then Theme.Colors.Plate else Theme.Colors.Chalk")).toBe(true)
		expect(has(refresh, "if fighter.Alive then initialOf(fighter.Name) else Theme.Glyphs.Close")).toBe(true)
		expect(number(band, "FALLEN")).toBe(0.6)
	end)

	it("tick the last ten seconds of a round without turning the clock red, and name the round and the mode", function()
		local band = code(SCORE_BAND)
		expect(number(band, "LAST_SECONDS")).toBe(10)
		expect(number(band, "LAST_PUNCH")).toBe(1.08)
		expect(has(band, 'local TICK_SOUND = "Countdown"')).toBe(true)
		expect(SoundConfig.Sfx.Countdown ~= nil).toBe(true)
		local set = body(band, "set")
		expect(
			has(
				set,
				"if snapshot.Phase == PLAYING_PHASE and seconds <= LAST_SECONDS and seconds > 0 and seconds ~= lastSecond then"
			)
		).toBe(true)
		expect(has(set, "Motion.punch(timerScale, LAST_PUNCH) UiSound.play(TICK_SOUND)")).toBe(true)
		-- The clock keeps the one colour it was built with.
		expect(has(set, "TextColor3")).toBe(false)
		-- The board's words, in every phase: the round, and the mode as the leaderboard names it.
		expect(
			has(
				set,
				'roundLabel.Text = localize.t("match.band", { round = snapshot.Round, mode = localize.t(MODE_KEY .. snapshot.ModeId), })'
			)
		).toBe(true)
		expect(has(band, 'local MODE_KEY = "leaderboard.board."\n')).toBe(true)
		expect(has(set, "roundLabel.Visible")).toBe(false)
		expect(Strings.Table["match.band"].en).toBe("Round {round} · {mode}")
		expect(Strings.Table["match.band"].fr).toBe("Manche {round} · {mode}")
		-- Every mode a match can be played in has its word, in both languages: a mode added without one would
		-- print its key in the band.
		local modes = 0
		for id in pairs(MatchConfig.Modes) do
			modes += 1
			expect(Strings.has("leaderboard.board." .. id)).toBe(true)
			expect(Strings.Table["leaderboard.board." .. id].fr).never.toBeNil()
		end
		expect(modes).toBeGreaterThanOrEqual(2)
		-- The series' pips are gone with the round's total.
		expect(Strings.has("match.round")).toBe(false)
		expect(has(band, "Pip")).toBe(false)
	end)

	it("draw the board's band, run: the words, a duel with no discs, a team with them", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local ScoreBand = world.require("src/ui/components/ScoreBand")
		local Theme = world.require("src/ui/Theme")
		local gui = Engine.instance("ScreenGui", world.playerGui)
		local function make(locale: string): any
			return ScoreBand.new({
				Parent = gui,
				Localize = {
					t = function(key: string, params: { [string]: any }?): string
						return Strings.t(key, params, locale)
					end,
				},
				LayoutOrder = 1,
			})
		end
		local function snapshot(mode: string, perTeam: number): any
			local teams = {}
			for side = 1, 2 do
				local team = {}
				for index = 1, perTeam do
					table.insert(team, { Name = "P" .. side .. index, Health = 80, MaxHealth = 100, Alive = true })
				end
				table.insert(teams, team)
			end
			return {
				ModeId = mode,
				Phase = "Playing",
				SecondsLeft = 42,
				Round = 3,
				RoundsToWin = 2,
				Scores = { 2, 1 },
				Teams = teams,
				LocalTeam = 1,
			}
		end
		local duel = make("fr")
		duel:Set(snapshot("Duel1v1", 1))
		local plate = duel.Instance
		expect(plate.Visible).toBe(true)
		-- As wide as what it says.
		expect(plate.Size.X.Offset).toBe(0)
		expect(plate.AutomaticSize).toBe(roblox.Enum.AutomaticSize.XY)
		local ours = plate:FindFirstChild("Ours", true)
		local theirs = plate:FindFirstChild("Theirs", true)
		local words = plate:FindFirstChild("Round", true)
		local clock = plate:FindFirstChild("Timer", true)
		expect(ours.Text).toBe("2")
		expect(ours.TextColor3).toBe(Theme.Colors.Ally)
		expect(ours.TextSize).toBe(Theme.Sizes.Num)
		expect(theirs.Text).toBe("1")
		expect(theirs.TextColor3).toBe(Theme.Colors.PanelRaised)
		expect(theirs.TextSize).toBe(Theme.Sizes.Num)
		expect(theirs:FindFirstChildOfClass("UIStroke")).toBeNil()
		expect(words.Text).toBe("Manche 3 · 1v1")
		expect(words.TextColor3).toBe(Theme.Colors.Chalk)
		expect(words.TextSize).toBe(Theme.Sizes.TextSmall)
		expect(clock.Visible).toBe(true)
		expect(clock.TextColor3).toBe(Theme.Colors.PanelRaised)
		expect(plate:FindFirstChild("Roster", true).Visible).toBe(false)
		-- Before a round, the words only.
		local counting = snapshot("Duel1v1", 1)
		counting.Phase = "Countdown"
		duel:Set(counting)
		expect(clock.Visible).toBe(false)
		expect(words.Text).toBe("Manche 3 · 1v1")
		local team = make("en")
		team:Set(snapshot("Team3v3", 3))
		expect(team.Instance:FindFirstChild("Round", true).Text).toBe("Round 3 · 3v3")
		local roster = team.Instance:FindFirstChild("Roster", true)
		expect(roster.Visible).toBe(true)
		expect(roster:FindFirstChild("Ours3", true)).never.toBeNil()
		expect(roster:FindFirstChild("Theirs3", true)).never.toBeNil()
		-- Nothing in it takes its width from what sizes itself on its content (Sticker's Host, D-170).
		local content = plate:FindFirstChild("Content")
		expect(content.AutomaticSize).toBe(roblox.Enum.AutomaticSize.XY)
		for _, part in ipairs({ content, table.unpack(content:GetDescendants()) }) do
			local parent = part.Parent
			local sized = if parent ~= nil and parent:IsA("GuiObject") then parent.AutomaticSize else nil
			local automatic = if sized ~= nil then sized.Name else "None"
			if part:IsA("GuiObject") and (automatic == "X" or automatic == "XY") and part.Size.X.Scale ~= 0 then
				error(part:GetFullName() .. " takes its width from a frame that sizes itself on it")
			end
		end
		-- The pill's inset is the board's, 6 over and under and 16 at the ends.
		local inset = content:FindFirstChildOfClass("UIPadding")
		expect(inset.PaddingTop.Offset).toBe(6)
		expect(inset.PaddingBottom.Offset).toBe(6)
		expect(inset.PaddingLeft.Offset).toBe(16)
		expect(inset.PaddingRight.Offset).toBe(16)
		expect(plate:FindFirstChild("Face"):FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
		-- A plate given its width keeps it, and stands as tall as it holds: the boss's, the portal's, the place's.
		local HudPlate = world.require("src/ui/components/HudPlate")
		local fixed = HudPlate.new({ Name = "Fixed", Width = 360, Parent = gui })
		expect(fixed.Instance.Size.X.Offset).toBe(360)
		expect(fixed.Instance.AutomaticSize).toBe(roblox.Enum.AutomaticSize.Y)
		expect(fixed.Content.Size.X.Scale).toBe(1)
		expect(fixed.Content.AutomaticSize).toBe(roblox.Enum.AutomaticSize.Y)
		local sides = fixed.Content:FindFirstChildOfClass("UIPadding")
		expect(sides.PaddingLeft.Offset).toBe(sides.PaddingTop.Offset)
		local held = HudPlate.new({ Name = "Held", Width = 300, Height = 40, Parent = gui })
		expect(held.Instance.AutomaticSize).toBe(roblox.Enum.AutomaticSize.None)
		expect(held.Content.Size).toBe(roblox.UDim2.fromScale(1, 1))
	end)

	it("draw the boss as the danger, our hits in cyan behind it, and a mark at each phase", function()
		local boss = code(BOSS)
		expect(has(boss, "Color = Theme.Colors.DangerFill,")).toBe(true)
		expect(has(boss, "Ghost = Theme.Colors.Ally,")).toBe(true)
		expect(has(boss, "Ticks = phases,")).toBe(true)
		expect(has(boss, "for index = 2, #WorldBossConfig.Phases do")).toBe(true)
		expect(#WorldBossConfig.Phases).toBeGreaterThanOrEqual(2)
		expect(has(boss, 'makeLabel("Share", INFO_HEIGHT, SHARE_TEXT, Theme.Colors.Ally')).toBe(true)
		expect(has(boss, 'makeLabel("Phase", INFO_HEIGHT, INFO_TEXT, Theme.Colors.Chalk')).toBe(true)
		expect(ThemeConfig.contrast(COLORS.Ally, COLORS.Plate)).toBeGreaterThanOrEqual(BODY_CONTRAST)
		expect(ThemeConfig.contrast(COLORS.DangerFill, COLORS.Well)).toBeGreaterThanOrEqual(GRAPHIC_CONTRAST)
	end)

	it("raise the boss's warning at two thirds of the screen, turned once toward it, and hold the toasts", function()
		local boss = code(BOSS)
		expect(number(boss, "WARNING_HEIGHT_SHARE")).toBe(0.65)
		expect(has(boss, "medallion.BackgroundColor3 = Theme.Colors.DangerFill")).toBe(true)
		local warning = body(boss, "showWarning")
		expect(has(warning, "hud.setWarning(up)")).toBe(true)
		expect(select(2, string.gsub(boss, "chevronRotation%(%)", ""))).toBe(2) -- declared, and read in one place
		expect(has(warning, "if up then local rotation = chevronRotation()")).toBe(true)
		expect(has(body(boss, "refresh"), "chevronRotation")).toBe(false)
		expect(has(body(boss, "chevronRotation"), "CollectionService:GetTagged(WorldBossConfig.Boss.Tag)")).toBe(true)
		-- The HUD holds its messages while the warning is up.
		local hud = code(HUD_CONTROLLER)
		expect(
			string.find(
				hud,
				"function HudController%.setWarning%(active: boolean%)%s+if toast ~= nil then%s+toast:Pause%(active%)"
			)
		).never.toBeNil()
		expect(has(code(TOAST), "ToastQueue.pause(queue, paused)")).toBe(true)
	end)

	it("fill the portal's dwell in Indigo in a ringed well, and punch the place's count as it moves", function()
		local travel = code(TRAVEL)
		local fill = body(travel, "makeFill")
		expect(has(fill, "track.BackgroundColor3 = Theme.Colors.Well")).toBe(true)
		expect(has(fill, 'Theme.stroke(track, "PanelRaised", Theme.Sizes.StrokeThin)')).toBe(true)
		expect(has(fill, "fill.BackgroundColor3 = Theme.Colors.InfoFill")).toBe(true)
		expect(number(travel, "FILL_HEIGHT")).toBe(18)
		expect(ThemeConfig.contrast(COLORS.InfoFill, COLORS.Well)).toBeGreaterThanOrEqual(GRAPHIC_CONTRAST)
		local changed = body(travel, "onBattlegroundChanged")
		expect(has(changed, "if not placeBand.Visible then lastDefeated = nil end")).toBe(true)
		expect(
			has(changed, "if lastDefeated ~= nil and defeated ~= lastDefeated then Motion.punch(placeLineScale) end")
		).toBe(true)
		expect(has(travel, "HudPlate.new(")).toBe(true)
	end)
end)

describe("the centre splashes", function()
	local VALUE_OR_RED = {
		Primary = true,
		Epic = true,
		Premium = true,
		SuccessFill = true,
		Success = true,
		Danger = true,
		DangerFill = true,
	}

	it("follow the match's snapshots, and leave with it", function()
		local match = body(code(HUD_CONTROLLER), "refreshMatch")
		expect(has(match, "for _, splash in ipairs(MatchSplash.between(lastMatch :: any, snapshot :: any)) do")).toBe(
			true
		)
		expect(has(match, "banner:Show(splash.Kind, splash.Digit)")).toBe(true)
		-- The versus plate leaves with the match, and a change of language no longer writes it (D-252, D-269).
		expect(has(match, "if snapshot == nil and lastMatch ~= nil then banner:Clear() versusShown = false end")).toBe(
			true
		)
		expect(has(match, "lastMatch = snapshot")).toBe(true)
	end)

	it("stand on their own layer, over the HUD and under every menu", function()
		expect(has(code(BANNER), 'ScreenRoot.new({ Name = "Banner", DisplayOrder = Theme.Layers.Banner')).toBe(true)
		local theme = code("src/ui/Theme.luau")
		local layer = function(name: string): number
			local value = tonumber(string.match(theme, "\n\t" .. name .. " = (%d+),"))
			assert(value ~= nil, "no layer " .. name)
			return value :: number
		end
		expect(layer("Hud")).toBeLessThan(layer("Banner"))
		expect(layer("Banner")).toBeLessThan(layer("Screen"))
	end)

	it("are short, cyan or ink, never a value colour and never red", function()
		local banner = code(BANNER)
		local looks = string.match(banner, "local LOOKS: { %[Kind%]: Look } = (%b{})")
		assert(looks ~= nil, "no LOOKS: this gate would check nothing")
		local count = 0
		for role in string.gmatch(looks :: string, 'Tint = "(%w+)"') do
			count += 1
			expect(VALUE_OR_RED[role]).toBeNil()
			expect(COLORS[role] ~= nil).toBe(true)
		end
		expect(count).toBe(5)
		for role in string.gmatch(looks :: string, 'Swash = "(%w+)"') do
			expect(VALUE_OR_RED[role]).toBeNil()
		end
		for seconds in string.gmatch(looks :: string, "Seconds = ([%d%.]+)") do
			expect(tonumber(seconds) :: number).toBeLessThanOrEqual(ThemeConfig.Timing.SplashSeconds)
		end
		-- The words: the sheet on a hard ink stroke, tipped; a digit one way, the next the other.
		expect(has(banner, "words.TextColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(has(banner, 'Theme.stroke(words, "Outline", STROKE, "Contextual")')).toBe(true)
		expect(number(banner, "STROKE")).toBe(6)
		expect(has(banner, "if entry.Digit % 2 == 0 then DIGIT_TILT else -DIGIT_TILT")).toBe(true)
		-- A lost round drops in with no overshoot.
		expect(
			has(
				body(banner, "present"),
				'if look.Heavy then Motion.set(shown.Scale, { Scale = ENTER_SCALE }) Motion.to(shown.Scale, { Scale = 1 }, "UiExit")'
			)
		).toBe(true)
	end)

	it("show one at a time, a digit giving way to what follows it at once", function()
		local banner = code(BANNER)
		local start = string.find(banner, "\n\tpump = function()", 1, true)
		assert(start ~= nil, "no pump: this gate would check nothing")
		local finish = string.find(banner, "\n\tend\n", start :: number, true)
		local pump = string.gsub(string.sub(banner, start :: number, finish or #banner), "%s+", " ")
		expect(has(pump, 'if shown ~= nil and shown.Kind == "Countdown" and #queue > 0 then leave(shown) end')).toBe(
			true
		)
		expect(has(pump, "if current ~= nil or #queue == 0 then return end")).toBe(true)
		expect(has(pump, "if suppressed then return end")).toBe(true)
	end)

	it("wait while a boss's warning is up, and drop what waited more than two seconds", function()
		local banner = code(BANNER)
		expect(number(banner, "SUPPRESS_DROP_SECONDS")).toBe(2)
		local suppress = body(banner, "suppress")
		expect(has(suppress, "if now - queue[index].At > SUPPRESS_DROP_SECONDS then table.remove(queue, index) end")).toBe(
			true
		)
		expect(string.find(code(HUD_CONTROLLER), "toast:Pause%(active%)%s+banner:Suppress%(active%)")).never.toBeNil()
	end)

	it("pop the player's takedown off the centre in cyan, and keep its toast for the XP", function()
		local banner = code(BANNER)
		expect(has(banner, "local POP_POSITION = UDim2.fromScale(0.62, 0.35)")).toBe(true)
		local pop = body(banner, "pop")
		expect(has(pop, "Fill = Theme.Colors.Ally,")).toBe(true)
		expect(has(pop, 'localize.t("hud.splash.defeated")')).toBe(true)
		expect(has(pop, "Theme.Timing.KillPopSeconds")).toBe(true)
		local hud = code(HUD_CONTROLLER)
		expect(has(hud, 'local TAKEDOWN_KEY = "hud.playerKill"')).toBe(true)
		local show = body(hud, "show")
		expect(has(show, "if key == TAKEDOWN_KEY then banner:Pop() end")).toBe(true)
		expect(has(code(GLYPH_SERVICE) .. code("src/server/Services/CombatService.luau"), '"hud.playerKill"')).toBe(
			true
		)
	end)

	it("say a round won or lost once, at the centre, and not again as a toast", function()
		local hud = code(HUD_CONTROLLER)
		expect(
			has(
				hud,
				'local SPLASH_KEYS: { [string]: boolean } = { ["match.roundWon"] = true, ["match.roundLost"] = true }'
			)
		).toBe(true)
		local show = body(hud, "show")
		local skipped = string.find(show, "elseif SPLASH_KEYS[key] then return", 1, true)
		local toasted = string.find(show, "toast:Show(", 1, true)
		assert(skipped ~= nil and toasted ~= nil, "show no longer keeps the rounds to the centre")
		expect(skipped :: number).toBeLessThan(toasted :: number)
		-- The count's digits left the band for the centre.
		local band = code(SCORE_BAND)
		expect(has(band, "timerLabel.Visible = not counting")).toBe(true)
		expect(has(band, '"match.countdown"')).toBe(false)
		expect(has(code(BANNER), 'Key = "match.countdown"')).toBe(true)
	end)
end)
