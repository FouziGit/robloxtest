--!strict
-- The touch cluster and the hub's shortcuts (D-147). The layout is pure (TouchCluster) and is run here on the
-- phones and the tablet the interface is checked on, with the engine's own jump button: no two discs touch,
-- Melee is the bigger one, and the kit row still leaves the combat dock its room between the thumbs. The
-- discs and the wiring around them are engine code, held by reading it.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local TouchCluster = require("../src/shared/Pure/TouchCluster")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local INPUT = "src/client/Controllers/InputController.luau"
local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
local COMBAT = "src/client/Controllers/CombatController.luau"
local DISC = "src/ui/components/TouchButton.luau"
local CLAIMS = "src/ui/Claims.luau"
local DOCK = "src/ui/components/CombatDock.luau"
local HOTBAR = "src/ui/components/Hotbar.luau"
local CONFIG: TouchCluster.Config = InputConfig.Touch :: any
local ACTIONS: { string } = InputConfig.Actions :: any
local COLORS = ThemeConfig.Colors
local PHONE_SCALE = ThemeConfig.Scale.TouchFloor
local EPSILON = 0.01
-- The top bar over a phone's game, in pixels.
local TOP_INSET = 36

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

type Device = { Name: string, Width: number, Height: number, Scale: number }

-- The screens of the device checklist (spec §12.2) that have a touch screen.
local DEVICES: { Device } = {
	{ Name = "an 844 x 390 phone", Width = 844, Height = 390, Scale = PHONE_SCALE },
	{ Name = "a 667 x 375 phone", Width = 667, Height = 375, Scale = PHONE_SCALE },
	{ Name = "a 1180 x 820 tablet", Width = 1180, Height = 820, Scale = 820 / ThemeConfig.Scale.ReferenceHeight },
}

-- The engine's jump button (TouchJump): 70 px, 95 in from the right and 90 up from the bottom on a screen whose
-- short side is 500 px or less; 120 px, 170 in and 210 up otherwise.
local function jumpOf(device: Device): TouchCluster.Rect
	local small = math.min(device.Width, device.Height - TOP_INSET) <= 500
	local size = if small then 70 else 120
	local x = device.Width - (if small then 95 else 170)
	local y = device.Height - (if small then 90 else 210)
	return { Min = { X = x, Y = y }, Max = { X = x + size, Y = y + size } }
end

local function screenOf(device: Device): TouchCluster.Rect
	return { Min = { X = 0, Y = TOP_INSET }, Max = { X = device.Width, Y = device.Height } }
end

local function layoutOn(device: Device, config: TouchCluster.Config?): { [string]: TouchCluster.Disc }
	return TouchCluster.layout(config or CONFIG, ACTIONS, screenOf(device), jumpOf(device), device.Scale)
end

local function distance(a: TouchCluster.Point, b: TouchCluster.Point): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
end

-- The leftmost edge of any disc: where the thumbs' cluster starts.
local function leftmost(discs: { [string]: TouchCluster.Disc }): number
	local edge = math.huge
	for _, disc in pairs(discs) do
		edge = math.min(edge, disc.Centre.X - disc.Diameter / 2)
	end
	return edge
end

describe("the touch cluster's layout", function()
	it("keeps every disc clear of the others, of the jump button and of the edges", function()
		for _, device in ipairs(DEVICES) do
			local discs = layoutOn(device)
			local gap = CONFIG.Gap * device.Scale
			local margin = CONFIG.Margin * device.Scale
			local jump = jumpOf(device)
			local count = 0
			for action, disc in pairs(discs) do
				count += 1
				local radius = disc.Diameter / 2
				for other, next in pairs(discs) do
					if other ~= action then
						local need = radius + next.Diameter / 2 + gap
						if distance(disc.Centre, next.Centre) < need - EPSILON then
							error(
								("on %s, %s and %s are closer than their radii and the gap"):format(
									device.Name,
									action,
									other
								)
							)
						end
					end
				end
				-- Inside the safe area, off the top bar.
				expect(disc.Centre.X - radius).toBeGreaterThanOrEqual(margin - EPSILON)
				expect(disc.Centre.X + radius).toBeLessThanOrEqual(device.Width - margin + EPSILON)
				expect(disc.Centre.Y - radius).toBeGreaterThanOrEqual(TOP_INSET + margin - EPSILON)
				expect(disc.Centre.Y + radius).toBeLessThanOrEqual(device.Height - margin + EPSILON)
				-- Off the jump button, by the gap.
				local nearestX = math.clamp(disc.Centre.X, jump.Min.X, jump.Max.X)
				local nearestY = math.clamp(disc.Centre.Y, jump.Min.Y, jump.Max.Y)
				if distance(disc.Centre, { X = nearestX, Y = nearestY }) < radius + gap - EPSILON then
					error(("on %s, %s touches the jump button"):format(device.Name, action))
				end
			end
			expect(count).toBe(#ACTIONS)
		end
	end)

	it("draws Melee bigger: 55 points on a phone to the others' 44", function()
		expect(TouchCluster.diameter(CONFIG, "Melee", PHONE_SCALE)).toBeCloseTo(55, 5)
		for _, action in ipairs({ "Cinnabar", "Orpiment", "Block", "Dash", "LockOn", "Menu" }) do
			expect(TouchCluster.diameter(CONFIG, action, PHONE_SCALE)).toBe(CONFIG.MinButtonSize)
		end
		local sizes = InputConfig.Touch.SizeScale :: { [string]: number }
		local count = 0
		for action, factor in pairs(sizes) do
			count += 1
			expect(CONFIG.Positions[action] ~= nil).toBe(true)
			expect(factor).toBeGreaterThan(1)
			expect(factor).toBeLessThanOrEqual(1.5)
		end
		expect(count).toBe(1)
		local discs = layoutOn(DEVICES[1])
		expect(discs.Melee.Diameter).toBeGreaterThan(discs.Block.Diameter)
	end)

	it("reads the kit row from the jump button out, and keeps the Menu disc in the top-right corner", function()
		for _, device in ipairs(DEVICES) do
			local discs = layoutOn(device)
			expect(discs.Melee.Centre.X).toBeGreaterThan(discs.Block.Centre.X)
			expect(discs.Block.Centre.X).toBeGreaterThan(discs.Dash.Centre.X)
			expect(discs.Dash.Centre.X).toBeGreaterThan(discs.LockOn.Centre.X)
			expect(discs.Melee.Centre.Y).toBeCloseTo(discs.LockOn.Centre.Y, 3)
			for action, disc in pairs(discs) do
				if action ~= "Menu" then
					expect(discs.Menu.Centre.Y).toBeLessThan(disc.Centre.Y)
				end
			end
		end
	end)

	it("pays for the bigger Melee disc next to it, not along the whole row", function()
		-- One step for every pair, sized for the biggest disc, would push the row about 38 points toward the
		-- middle of a phone; spacing each pair by its own radii costs only what Melee adds.
		local phone = DEVICES[1]
		local flat = table.clone(InputConfig.Touch) :: any
		flat.SizeScale = {}
		local cost = leftmost(layoutOn(phone, flat)) - leftmost(layoutOn(phone))
		local added = TouchCluster.diameter(CONFIG, "Melee", PHONE_SCALE) - CONFIG.MinButtonSize
		expect(cost).toBeLessThanOrEqual(added + EPSILON)
		-- And the dock still holds a row of six pips between the thumbs (HudController.fitDock).
		local clearance = number(code(HUD_CONTROLLER), "DOCK_DISC_CLEARANCE")
		local free = 2 * (leftmost(layoutOn(phone)) - clearance - phone.Width / 2) / PHONE_SCALE
		local hotbar = code(HOTBAR)
		local pips = 6 * ThemeConfig.Hud.HotbarPipsHeight + 5 * number(hotbar, "PIP_GAP")
		expect(free).toBeGreaterThanOrEqual(pips + 2 * number(code(DOCK), "PADDING"))
	end)
end)

describe("the combat dock between the thumbs", function()
	local HUD = ThemeConfig.Hud
	local LIMITS = { Clearance = 12, Widest = HUD.DockWidthTouchMax, Narrowest = HUD.DockWidthTouchMin }

	it("stands centred where the thumbs leave it room, as wide as the room", function()
		local phone = DEVICES[1]
		local nearest = leftmost(layoutOn(phone))
		local width, offset = TouchCluster.dockSpan(nearest, phone.Width / 2, PHONE_SCALE, LIMITS)
		expect(offset).toBe(0)
		expect(width).toBeCloseTo(2 * (nearest - 12 - phone.Width / 2) / PHONE_SCALE, 5)
		expect(width).toBeLessThanOrEqual(HUD.DockWidthTouchMax)
		expect(width).toBeGreaterThanOrEqual(HUD.DockWidthTouchMin)
		-- Never wider than its token, however much room a tablet leaves.
		local wide = TouchCluster.dockSpan(10000, 0, 1, LIMITS)
		expect(wide).toBe(HUD.DockWidthTouchMax)
	end)

	it("slides left of the discs on a small phone, at its narrowest, and stays on the screen", function()
		local phone = DEVICES[2]
		local nearest = leftmost(layoutOn(phone))
		local centre = phone.Width / 2
		local width, offset = TouchCluster.dockSpan(nearest, centre, PHONE_SCALE, LIMITS)
		expect(width).toBe(HUD.DockWidthTouchMin)
		expect(offset).toBeLessThan(0)
		-- Its right edge clears the nearest disc exactly; its left edge is still on the screen.
		local right = centre + (offset + width / 2) * PHONE_SCALE
		local left = centre + (offset - width / 2) * PHONE_SCALE
		expect(right).toBeCloseTo(nearest - 12, 5)
		expect(left).toBeGreaterThan(CONFIG.Margin * PHONE_SCALE)
		-- With room for exactly its narrowest it still stands centred.
		local exactWidth, centred = TouchCluster.dockSpan(12 + HUD.DockWidthTouchMin / 2, 0, 1, LIMITS)
		expect(centred).toBe(0)
		expect(exactWidth).toBe(HUD.DockWidthTouchMin)
	end)

	it("holds six pips at its narrowest", function()
		local pips = 6 * HUD.HotbarPipsHeight + 5 * number(code(HOTBAR), "PIP_GAP")
		expect(HUD.DockWidthTouchMin).toBeGreaterThanOrEqual(pips + 2 * number(code(DOCK), "PADDING"))
		expect(HUD.DockWidthTouchMin).toBeLessThan(HUD.DockWidthTouchMax)
	end)
end)

describe("the touch discs", function()
	it("dim a pigment that leads to no glyph the ink can pay for, and allocate nothing", function()
		local recipes = {
			{ Combo = { "Cinnabar", "Cinnabar" }, Cost = 20 },
			{ Combo = { "Indigo", "Umber" }, Cost = 35 },
		}
		local into: { [string]: boolean } = { Verdigris = true }
		local result = TouchCluster.affordable(recipes, 34, into)
		expect(result == into).toBe(true)
		expect(result.Cinnabar).toBe(true)
		expect(result.Indigo).toBeNil()
		expect(result.Umber).toBeNil()
		expect(result.Verdigris).toBeNil()
		-- Exactly enough ink is enough.
		TouchCluster.affordable(recipes, 35, into)
		expect(into.Indigo).toBe(true)
		expect(into.Umber).toBe(true)
		-- The HUD weighs the equipped glyphs at every push and hands the result to the discs.
		local combat = body(code(HUD_CONTROLLER), "refreshCombat")
		expect(has(combat, "inputController.setAffordable(TouchCluster.affordable(recipes, state.Ink, payable))")).toBe(
			true
		)
		expect(has(body(code(HUD_CONTROLLER), "recipesOf"), "{ Combo = def.Combo, Cost = def.Cost }")).toBe(true)
		local disc = code(DISC)
		expect(number(disc, "DIMMED")).toBe(0.5)
		expect(
			has(
				body(disc, "setAvailable"),
				'Motion.to(label, { TextTransparency = if value then 0 else DIMMED }, "Ui")'
			)
		).toBe(true)
		expect(has(body(code(INPUT), "available"), "payable == nil or not PigmentConfig.isPigment(action)")).toBe(true)
	end)

	it("wear their colour: the exact pigment on its own lip, the kit an ink plate, the Menu the sheet", function()
		local disc = code(DISC)
		local look = body(disc, "lookFor")
		expect(has(look, 'local fill = Theme.pigmentColor(pigment or "")')).toBe(true)
		expect(has(look, "Ink = Theme.inkOn(fill),")).toBe(true)
		expect(
			has(
				look,
				"Fill = Theme.Colors.Plate, Lip = Theme.Colors.Chalk, Ink = Theme.Colors.TextInverse, Outline = false,"
			)
		).toBe(true)
		expect(
			has(
				look,
				'Fill = Theme.Colors.PanelRaised, Lip = Theme.lip("Secondary"), Ink = Theme.Colors.Text, Outline = true, Ring = false,'
			)
		).toBe(true)
		expect(
			has(
				body(disc, "pigmentLip"),
				"return Theme.rgb(PigmentConfig.shade(rgb, -0.25, ThemeConfig.Charcoal, ThemeConfig.Vellum))"
			)
		).toBe(true)
		-- The same shade the buttons' lips are made of.
		local lips = { Cinnabar = "Danger", Indigo = "Info", Verdigris = "Success", Orpiment = "Primary" }
		for pigment, lip in pairs(lips) do
			local rgb =
				PigmentConfig.shade(PigmentConfig.Colors[pigment], -0.25, ThemeConfig.Charcoal, ThemeConfig.Vellum)
			expect(rgb).toEqual(ThemeConfig.Lips[lip])
		end
		-- Nearly opaque, by the player's own setting: 5 % of the world through a pigment, 8 % through the kit.
		expect(has(disc, "local FACE_TRANSPARENCY: { [Kind]: number } = { Pigment = 0.05, Kit = 0.08, Menu = 0 }")).toBe(
			true
		)
		expect(has(disc, "face.BackgroundTransparency = FACE_TRANSPARENCY[kind] * UiPrefs.transparency()")).toBe(true)
		-- Every sigil and word reads on its disc: a sigil is large (60 % of the disc), a word is body text.
		for _, pigment in ipairs(PigmentConfig.Order) do
			local fill = PigmentConfig.Colors[pigment]
			expect(ThemeConfig.contrast(ThemeConfig.inkOn(fill), fill)).toBeGreaterThanOrEqual(3)
		end
		expect(number(disc, "SIGIL_SHARE")).toBe(0.6)
		expect(ThemeConfig.contrast(COLORS.TextInverse, COLORS.Plate)).toBeGreaterThanOrEqual(4.5)
		expect(ThemeConfig.contrast(COLORS.Text, COLORS.PanelRaised)).toBeGreaterThanOrEqual(4.5)
		-- The sheet ring inside the outline, on the pigments and the kit.
		expect(has(disc, 'local stroke = Theme.stroke(frame, "PanelRaised", thickness)')).toBe(true)
		expect(has(disc, 'ring = ringFrame("Ring", face, RING_INSET, Theme.Sizes.StrokeThin)')).toBe(true)
	end)

	it("sink onto their lip when pressed and throw a blot, but not for less motion or the lowest tier", function()
		local disc = code(DISC)
		local pressed = body(disc, "setPressed")
		expect(has(pressed, 'sticker:SetState(if value then "Pressed" else "Idle")')).toBe(true)
		expect(has(pressed, 'Motion.to(scale, { Scale = if value then PRESSED_SCALE else 1 }, "UiSnappy")')).toBe(true)
		expect(has(pressed, "if value then burst() end")).toBe(true)
		expect(number(disc, "PRESSED_SCALE")).toBe(0.88)
		local burst = body(disc, "burst")
		expect(has(burst, "if UiPrefs.reducedMotion() or UiPrefs.lowQuality() then return end")).toBe(true)
		expect(has(burst, 'Motion.to(blotScale, { Scale = BURST_TO }, "Ui")')).toBe(true)
		expect(has(disc, "local BURST_FROM, BURST_TO = 0.6, 1.4")).toBe(true)
		-- The blot goes back to the pool out of the disc, before the disc goes.
		local destroy = body(disc, "destroy")
		local released = string.find(destroy, "releaseBurst()", 1, true)
		local cleaned = string.find(destroy, "trove:Destroy()", 1, true)
		assert(released ~= nil and cleaned ~= nil, "the disc no longer hands its blot back")
		expect(released :: number).toBeLessThan(cleaned :: number)
		local release = body(disc, "releaseBurst")
		expect(has(release, "Splat.release(blot) blot.Parent = nil")).toBe(true)
	end)

	it("breathe a thicker ring on a disc that continues the sequence, in no value colour", function()
		local disc = code(DISC)
		local hint = body(disc, "setHint")
		expect(number(disc, "HINT_RING")).toBe(4)
		expect(has(disc, "local HINT_FROM, HINT_TO = 0.1, 0.6")).toBe(true)
		expect(has(hint, 'Breath.join(HINT_BREATH, HINT_FROM, HINT_TO, Theme.Timing.IdleBreathSeconds, "Ui")')).toBe(
			true
		)
		expect(has(hint, "if ring ~= nil then ring.Visible = not value end")).toBe(true)
		expect(has(hint, "if UiPrefs.reducedMotion() then hintStroke.Transparency = HINT_FROM return end")).toBe(true)
		-- Any source of hints lights a disc; the HUD's sequence is one of them.
		local input = code(INPUT)
		expect(
			has(
				body(input, "hinted"),
				"for _, pigments in pairs(hintsBySource) do if pigments[action] then return true end end"
			)
		).toBe(true)
		expect(has(body(input, "applyTouchButton"), "visual:SetHint(hinted(action))")).toBe(true)
	end)

	it("veil the dash disc for as long as the dash waits, drained from the top at the server's pace", function()
		local disc = code(DISC)
		local cooldown = body(disc, "setCooldown")
		local changed = string.find(cooldown, "if fraction ~= shownFraction then", 1, true)
		local sprung =
			string.find(cooldown, 'Motion.to(cooldown, { Size = UDim2.fromScale(1, fraction) }, "UiSnappy")', 1, true)
		assert(changed ~= nil and sprung ~= nil, "the veil no longer springs to the wait")
		expect(changed :: number).toBeLessThan(sprung :: number)
		expect(has(cooldown, "seconds.Visible = remaining > 0")).toBe(true)
		expect(has(cooldown, "label.Visible = remaining <= 0")).toBe(true)
		expect(number(disc, "VEIL_TRANSPARENCY")).toBe(0.4)
		expect(has(disc, 'textLabel("Seconds", Theme.Fonts.Numeric, Theme.Colors.TextInverse,')).toBe(true)
		-- The wait is the local throttle's: CombatController sends no dash inside Dash.CooldownSeconds of the last.
		expect(has(code(COMBAT), "Dash = CombatConfig.Dash.CooldownSeconds,")).toBe(true)
		local input = code(INPUT)
		local pressed = body(input, "onDashPressed")
		local waiting = string.find(pressed, "if not touching or now < dashReadyAt then return end", 1, true)
		local started = string.find(pressed, "dashReadyAt = now + CombatConfig.Dash.CooldownSeconds", 1, true)
		assert(waiting ~= nil and started ~= nil, "the dash disc no longer follows the throttle")
		expect(waiting :: number).toBeLessThan(started :: number)
		expect(has(body(input, "onAction"), "elseif actionName == DASH_ACTION then onDashPressed()")).toBe(true)
		expect(has(input, "local DASH_TICK_SECONDS = 1 / GameConfig.Server.CombatStateHz\n")).toBe(true)
		expect(GameConfig.Server.CombatStateHz).toBeGreaterThan(0)
		expect(has(body(input, "tickDash"), "if token ~= dashToken then return end")).toBe(true)
		expect(has(input, "Players.LocalPlayer.CharacterAdded:Connect(clearDash)")).toBe(true)
		expect(CombatConfig.Dash.CooldownSeconds).toBeGreaterThan(0)
	end)

	it("show a locked pigment no disc, and give it one when it unlocks", function()
		local input = code(INPUT)
		local bind = body(input, "bindAll")
		expect(has(bind, "local touch = touchScreen and not locked[action]")).toBe(true)
		local locked = body(input, "lockedPigments")
		expect(has(locked, "for _, pigment in ipairs(PigmentConfig.Unlockable) do")).toBe(true)
		expect(
			has(
				locked,
				"if data == nil or table.find(data.Unlocks.Pigments, pigment) == nil then locked[pigment] = true"
			)
		).toBe(true)
		expect(has(input, 'local unlocked = section == "Unlocks" and signatureOf(lockedPigments()) ~= lockedSignature')).toBe(
			true
		)
		expect(has(input, 'if section == "*" or section == "Settings" or unlocked then')).toBe(true)
		expect(#PigmentConfig.Unlockable).toBeGreaterThan(0)
	end)
end)

-- InputController run (tests/engine.luau) on `plays`, every pigment unlocked, as the bootstrap wires it: the
-- world, whose bindings say whether each action asked the engine for a disc, and the controller.
local function inputOn(plays: Engine.Plays): (any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs(), Services = { HapticService = {} } })
	Engine.plays(world, plays)
	local Input = world.require("src/client/Controllers/InputController")
	local profile = {
		Settings = {
			Keyboard = table.clone(InputConfig.DefaultKeyboard),
			Gamepad = table.clone(InputConfig.DefaultGamepad),
		},
		Unlocks = { Glyphs = {}, Pigments = table.clone(PigmentConfig.Unlockable) },
	}
	Input.Init({
		ClientData = {
			get = function(): any
				return profile
			end,
			Changed = Engine.signal(),
		},
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		MenuController = {},
		InputMode = world.require("src/client/Controllers/InputMode"),
	})
	Input.Start()
	return world, Input
end

-- The actions bound with a disc, and all the actions bound.
local function discsOf(world: any): (number, number)
	local discs, bound = 0, 0
	for _, action in ipairs(ACTIONS) do
		local binding = world.bindings[action]
		if binding ~= nil then
			bound += 1
			if binding.Touch then
				discs += 1
			end
		end
	end
	return discs, bound
end

describe("the touch discs, by how the player plays, run", function()
	it("are drawn for a phone, and for nothing a keyboard or a pad plays, touch screen or not", function()
		local world = inputOn("Touch")
		local discs, bound = discsOf(world)
		expect(bound).toBe(#ACTIONS)
		expect(discs).toBe(#ACTIONS)
		for _, plays in ipairs({ "Pointer", "Gamepad", "TouchKeyboard", "TouchGamepad" }) do
			local other = inputOn(plays :: Engine.Plays)
			local drawn, keys = discsOf(other)
			if drawn ~= 0 then
				error(("%s is drawn %d touch discs"):format(plays, drawn))
			end
			-- Every action keeps its keys and its buttons.
			expect(keys).toBe(#ACTIONS)
		end
	end)

	it("come when a touch laptop is touched, and go when it is typed on again, with their places", function()
		local world, Input = inputOn("TouchKeyboard")
		local laidOut = 0
		Input.TouchLayoutChanged:Connect(function()
			laidOut += 1
		end)
		Engine.plays(world, "TouchLaptop")
		expect((discsOf(world))).toBe(#ACTIONS)
		Engine.plays(world, "TouchKeyboard")
		expect((discsOf(world))).toBe(0)
		-- Gone, not suspended: what lays itself out around them hears there is nothing left.
		expect(laidOut).toBe(1)
		expect(next(Input.touchRects())).toBeNil()
		-- A pad picked up on a phone puts the discs away too, and they come back when the pad is put down.
		Engine.plays(world, "Touch")
		expect((discsOf(world))).toBe(#ACTIONS)
		Engine.plays(world, "TouchGamepad")
		expect((discsOf(world))).toBe(0)
	end)
end)

describe("the hub's shortcuts", function()
	it("name each screen with its icon, and put the Menu's key on a cap beside it", function()
		local hud = code(HUD_CONTROLLER)
		expect(
			has(
				hud,
				'local QUICK_ICONS: { [string]: Icon.Name } = { Play = "Play", Shop = "Coin", Leaderboard = "Podium" }'
			)
		).toBe(true)
		expect(
			has(hud, "quickButton(entry.NameKey, entry.Variant, index, QUICK_ICONS[entry.Screen], quickBar, function()")
		).toBe(true)
		local key = body(hud, "refreshMenuKey")
		expect(has(key, 'local saved = if device == "Gamepad" then data.Settings.Gamepad else data.Settings.Keyboard')).toBe(
			true
		)
		expect(has(key, "local key = saved[MENU_ACTION] or defaults[MENU_ACTION]")).toBe(true)
		-- In the Menu's own row, before the button: the hub's, and in a fight the board's word-only pill after it
		-- (D-179), the cap before whichever shows.
		expect(has(key, "LayoutOrder = 1, Parent = menuRow,")).toBe(true)
		expect(has(hud, 'quickButton(MENU_NAME_KEY, "Secondary", 2, "Burger", menuRow, function()')).toBe(true)
		expect(has(hud, 'quickButton(MENU_NAME_KEY, "Secondary", 3, nil, menuRow, function()')).toBe(true)
		local quick = body(hud, "quickButton")
		expect(has(quick, "local compact = icon == nil")).toBe(true)
		expect(has(quick, "Compact = compact,")).toBe(true)
		expect(
			has(
				quick,
				"Size = UDim2.fromOffset(0, if compact then Theme.MinTouchTarget else Theme.Sizes.ButtonHeight),"
			)
		).toBe(true)
		local hub = body(hud, "refreshHub")
		expect(has(hub, "menuButton.Instance.Visible = hub menuPill.Instance.Visible = not hub")).toBe(true)
		expect(has(body(hud, "refreshQuickBar"), "menuPill:SetText(localize.t(MENU_NAME_KEY))")).toBe(true)
		-- The button plays its own click now: the bar no longer doubles it.
		expect(has(quick, "soundController.play")).toBe(false)
	end)

	it("show the value yellow in the hub only: shortcuts, Play sticker and claims badge (rule 11)", function()
		local hud = code(HUD_CONTROLLER)
		local hub = body(hud, "refreshHub")
		expect(has(hub, "local hub = not (inMatch or inArena)")).toBe(true)
		expect(has(hub, "button.Instance.Visible = hub")).toBe(true)
		expect(
			has(
				hub,
				"sticker.Instance.Visible = hub and not queued and inputController.touchRects()[MENU_ACTION] ~= nil"
			)
		).toBe(true)
		expect(has(body(hud, "refreshFight"), "refreshHub()")).toBe(true)
		expect(has(body(hud, "refreshQuickBar"), "button.Instance.Visible = not (inMatch or inArena)")).toBe(true)
		local claims = body(hud, "refreshClaims")
		expect(has(claims, "menuButton:SetBadge(if inMatch or inArena then nil else counts.Total)")).toBe(true)
		local queue = body(hud, "onQueue")
		expect(has(queue, "queued = snapshot.Queued metaCluster:SetQueue(snapshot) refreshHub()")).toBe(true)
		expect(has(hud, "matchController.QueueChanged:Connect(onQueue)")).toBe(true)
		expect(has(hud, "onQueue(matchController.getQueue())")).toBe(true)
	end)

	it("count the claims on the server's day, and again when it turns", function()
		local hud = code(HUD_CONTROLLER)
		local claims = body(hud, "refreshClaims")
		expect(has(claims, "local now = Workspace:GetServerTimeNow()")).toBe(true)
		expect(has(claims, "local counts = Claims.count(clientData.get(), now)")).toBe(true)
		-- One wait for the day's turn at a time: the claims are counted on every queue snapshot.
		local pending = string.find(claims, "if dayTurnPending then return end dayTurnPending = true", 1, true)
		local waits = string.find(
			claims,
			"task.delay(Claims.nextCountIn(now), function() dayTurnPending = false refreshClaims() end)",
			1,
			true
		)
		assert(pending ~= nil and waits ~= nil, "the claims no longer wait once for the day's turn")
		expect(pending :: number).toBeLessThan(waits :: number)
		expect(
			has(
				body(hud, "refreshProfile"),
				'if section == "*" or section == "Daily" or section == "Quests" or section == "Battlepass" then refreshClaims()'
			)
		).toBe(true)
		local builder = code(CLAIMS)
		expect(has(builder, "Today = DailyStreak.dayIndex(unixTime),")).toBe(true)
		expect(has(builder, "Live = QuestLogic.periodKey(name, unixTime),")).toBe(true)
		-- Drawn as the server draws, floor and swaps included, so a badge counts what the board shows.
		expect(
			has(
				builder,
				"local drawn = QuestLogic.select(QuestConfig.Pool, name, count, setKey, QuestConfig.SoloFloor)"
			)
		).toBe(true)
		expect(has(builder, "return QuestLogic.swapped(QuestConfig.Pool, drawn, swaps)")).toBe(true)
		expect(has(builder, "local season = BattlepassConfig.Seasons[GameConfig.SeasonId]")).toBe(true)
		expect(has(builder, "return SECONDS_PER_DAY - unixTime % SECONDS_PER_DAY + TURN_MARGIN_SECONDS")).toBe(true)
		expect(number(builder, "SECONDS_PER_DAY")).toBe(86400)
	end)

	it("put Play one tap away on a phone, left of the Menu disc and level with it", function()
		local hud = code(HUD_CONTROLLER)
		local build = body(hud, "buildPlaySticker")
		expect(has(build, 'Variant = "Primary", Icon = "Play",')).toBe(true)
		expect(has(build, "menuController.open(PLAY_SCREEN)")).toBe(true)
		expect(has(build, "sticker.Instance.AnchorPoint = Vector2.new(1, 0.5)")).toBe(true)
		expect(has(hud, 'local PLAY_SCREEN = "Play"\n')).toBe(true)
		expect(number(hud, "PLAY_STICKER_HEIGHT")).toBe(44)
		-- From inside the safe area's padding, where a child of it is placed (ScreenRoot:ToContent), not from its
		-- corner a whole top bar higher.
		local place = body(hud, "placePlaySticker")
		expect(has(place, "local at = root:ToContent(Vector2.new(menu.Min.X, (menu.Min.Y + menu.Max.Y) / 2))")).toBe(
			true
		)
		expect(has(place, "sticker.Instance.Position = UDim2.fromOffset(at.X - PLAY_STICKER_GAP, at.Y)")).toBe(true)
		expect(has(place, "AbsolutePosition")).toBe(false)
		local toasts = body(hud, "placeToasts")
		expect(has(toasts, "local top = toastRoot:ToContent(Vector2.new(menu.Min.X, menu.Max.Y)).Y")).toBe(true)
		expect(has(toasts, "AbsolutePosition")).toBe(false)
		expect(number(hud, "PLAY_STICKER_GAP")).toBe(8)
		-- Built on every device and shown only once the Menu disc is laid out (refreshHub): a touch laptop gets it
		-- when it is touched, and loses it with the discs.
		expect(has(body(hud, "build"), "buildPlaySticker(content)")).toBe(true)
		expect(has(hud, "inputController.TouchLayoutChanged:Connect(placePlaySticker)")).toBe(true)
		local placed = string.find(place, "if sticker ~= nil and menu ~= nil then", 1, true)
		local refreshed = string.find(place, "end refreshHub()", 1, true)
		assert(placed ~= nil and refreshed ~= nil, "the sticker is no longer hidden with the disc")
		expect(placed :: number).toBeLessThan(refreshed :: number)
	end)
end)
