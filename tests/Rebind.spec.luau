--!strict
-- The Settings screen (D-147, slice B): what a captured key does to a binding map, what Reset does, how a
-- push confirms a save, and the screen's promises read from its source -- every change saved as it is made
-- and paced to the remote's budget, a refusal that puts the rows back, a reset that asks with the only red
-- confirm of the menus, a pad never told to click or press Escape, and Roblox's own accessibility settings
-- shown as they are.
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local Rebind = require("../src/shared/Pure/Rebind")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SCREEN = "src/ui/screens/SettingsScreen.luau"
local BINDINGS = "src/ui/screens/SettingsBindings.luau"
local VALUES = "src/ui/screens/SettingsValues.luau"
local GLOBAL_TYPES = "globalTypes.d.luau"

local function stripComments(source: string): string
	local lines = {}
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- The body of `local function <name>(`, up to the `end` at `indent`.
local function body(source: string, name: string, indent: string): string
	local found = string.match(source, "local function " .. name .. "%(.-\n" .. indent .. "end\n")
	if found == nil then
		error(("no local function %s: this gate would check nothing"):format(name))
	end
	return found
end

local ALLOWED = { J = true, K = true, H = true, F = true, M = true, LeftShift = true }
local REBINDABLE = { Cinnabar = true, Indigo = true, Dash = true }
local function map(): Rebind.Map
	return { Cinnabar = "J", Indigo = "K", Dash = "LeftShift", Menu = "M" }
end

describe("a captured key", function()
	it("binds a free key, leaving the map it was given alone", function()
		local before = map()
		local result, updated, holder = Rebind.apply(before, "Cinnabar", "H", ALLOWED, REBINDABLE)
		expect(result).toBe("Bound")
		expect(updated.Cinnabar).toBe("H")
		expect(holder).toBeNil()
		expect(before.Cinnabar).toBe("J")
	end)

	it("swaps with an action that may move, and refuses the one that may not", function()
		local result, updated, holder = Rebind.apply(map(), "Cinnabar", "K", ALLOWED, REBINDABLE)
		expect(result).toBe("Swapped")
		expect(holder).toBe("Indigo")
		expect(updated.Cinnabar).toBe("K")
		expect(updated.Indigo).toBe("J")
		-- The Menu key keeps the screen reachable: nothing takes it.
		local refused, unchanged, owner = Rebind.apply(map(), "Cinnabar", "M", ALLOWED, REBINDABLE)
		expect(refused).toBe("Duplicate")
		expect(owner).toBe("Menu")
		expect(unchanged).toEqual(map())
	end)

	it("changes nothing for a cancelled capture, a key not allowed, or the key already there", function()
		for _, case in ipairs({ { nil :: string?, "Cancelled" }, { "Z", "NotAllowed" }, { "J", "Same" } }) do
			local result, updated = Rebind.apply(map(), "Cinnabar", case[1], ALLOWED, REBINDABLE)
			expect(result).toBe(case[2])
			expect(updated).toEqual(map())
		end
	end)

	it("resets only what may be rebound, and knows the push that holds what was sent", function()
		local moved = { Cinnabar = "H", Indigo = "F", Dash = "J", Menu = "M" }
		local defaults = { Cinnabar = "J", Indigo = "K", Dash = "LeftShift", Menu = "Q" }
		local reset = Rebind.reset(moved, defaults, { "Cinnabar", "Indigo", "Dash" })
		expect(reset).toEqual({ Cinnabar = "J", Indigo = "K", Dash = "LeftShift", Menu = "M" })
		expect(moved.Cinnabar).toBe("H")
		local actions = { "Cinnabar", "Indigo", "Dash", "Menu" }
		expect(Rebind.same(map(), map(), actions)).toBe(true)
		expect(Rebind.same(map(), moved, actions)).toBe(false)
	end)
end)

describe("the settings screen", function()
	local screen = stripComments(fs.readFile(SCREEN))
	local bindings = stripComments(fs.readFile(BINDINGS))

	it("saves each change as it is made, with no Save button to forget", function()
		expect(string.find(screen, "common.save", 1, true)).toBeNil()
		expect(string.find(bindings, "common.save", 1, true)).toBeNil()
		local commit = body(bindings, "commit", "\t")
		expect(commit).toContain("waiting[kind] = true")
		expect(commit).toContain("trySend()")
		expect(bindings).toContain('props.RemoteClient.fire("UpdateKeybinds", kind, table.clone(map))')
	end)

	it("paces its sends to the remote's budget, one in flight at a time", function()
		expect(bindings).toContain("local UPDATE_KEYBINDS_RATE = Remotes.Definitions.UpdateKeybinds.Rate")
		expect(bindings).toContain("then 1 / UPDATE_KEYBINDS_RATE.Refill")
		expect(bindings).toContain("if inFlight ~= nil or sendTimer ~= nil then")
		expect(bindings).toContain("local wait = MIN_INTERVAL_SECONDS - (os.clock() - lastSentAt)")
	end)

	it("flashes what the server holds, and puts back what it refuses", function()
		expect(bindings).toContain("if kind ~= nil and map ~= nil and Rebind.same(stored(kind), map, ACTIONS) then")
		expect(bindings).toContain("row.Key:Flash()")
		expect(bindings).toContain('if key == "settings.saveFailed" and kind ~= nil then\n\t\t\t\trefused(kind)')
		expect(body(bindings, "refused", "\t")).toContain("sync(kind)")
	end)

	it("asks before a reset, with the one red confirm of the menus", function()
		expect(screen).toContain("bindings:AskReset()")
		expect(bindings).toContain('Confirm = { Text = t("common.reset"), Variant = "Danger" },')
		local ask = body(bindings, "askReset", "\t")
		expect(ask).toContain("OnConfirm = function()\n\t\t\t\tcloseSheet()\n\t\t\t\treset()")
		expect(ask).toContain("OnCancel = closeSheet,")
	end)

	it("speaks to a pad of buttons, never of clicks or Escape", function()
		expect(bindings).toContain(
			'local prompt = if kind == "Gamepad" then "settings.pressButton" else "settings.pressKey"'
		)
		expect(bindings).toContain('t(if kind == "Gamepad" then "settings.hint.gamepad" else "settings.hint")')
		for _, key in ipairs({ "settings.pressButton", "settings.hint.gamepad" }) do
			for _, language in ipairs({ "en", "fr" }) do
				local text = string.lower((Strings.Table[key] :: any)[language])
				for _, word in ipairs({ "click", "clique", "esc", "échap" }) do
					expect(string.find(text, word, 1, true)).toBeNil()
				end
			end
		end
		-- A is the pad's cancel: InputConfig says so, and so must the words.
		expect(table.find(InputConfig.CaptureCancelKeys, "ButtonA")).never.toBeNil()
		expect(Strings.Table["settings.pressButton"].en).toContain("A")
	end)

	it("keeps shakes with accessibility, and shows Roblox's own settings as they are", function()
		local valuesSource = stripComments(fs.readFile(VALUES))
		expect(string.find(body(valuesSource, "buildAudio", "\t"), "Toggle.new", 1, true)).toBeNil()
		local page = body(valuesSource, "buildAccessibility", "\t")
		expect(page).toContain('row(nil, page, t("settings.cameraShake"), toggle.Instance, 1)')
		expect(page).toContain('motion.Text = t(if UiPrefs.reducedMotion() then "common.on" else "common.off")')
		expect(page).toContain("size.Text = t(TEXT_SIZE_PREFIX .. UiPrefs.textSize())")
		expect(page).toContain("transparency.Text = percent(UiPrefs.transparency())")
		expect(page).toContain("local following = UiPrefs.Changed:Connect(refresh)")
		expect(valuesSource).toContain('local TEXT_SIZE_PREFIX = "settings.textSize."')
		expect(screen).toContain("values:BuildAccessibility(pageTrove)")
	end)

	it("names every text size Roblox offers", function()
		local dump = fs.readFile(GLOBAL_TYPES)
		local block = string.match(dump, "EnumPreferredTextSize_INTERNAL extends Enum with\n(.-)\tfunction")
		assert(block ~= nil, "the engine's text sizes are no longer in globalTypes.d.luau")
		local count = 0
		for name in string.gmatch(block :: string, "\t(%w+): EnumPreferredTextSize\n") do
			count += 1
			local entry = Strings.Table["settings.textSize." .. name]
			if entry == nil then
				error(("Roblox offers the text size %s, which the Settings screen cannot name"):format(name))
			end
		end
		expect(count).toBeGreaterThanOrEqual(4)
		-- And UiPrefs reads the name from the same guarded read as the scale.
		local prefs = stripComments(fs.readFile("src/ui/UiPrefs.luau"))
		expect(prefs).toContain('textSize = if typeof(size) == "EnumItem" then (size :: EnumItem).Name else "Medium"')
	end)

	it("plays the Effects preview at the new volume, once the server holds it", function()
		local valuesSource = stripComments(fs.readFile(VALUES))
		expect(valuesSource).toContain("if pending or inFlight then\n\t\t\t\tpreviewOnPush = true")
		expect(valuesSource).toContain(
			'if previewOnPush and not pending then\n\t\t\t\tpreviewOnPush = false\n\t\t\t\tUiSound.play("UiClick")'
		)
	end)

	it("clicks on a tab, on the quality strip and on a key, which make no sound of their own", function()
		local _, tabClicks =
			string.gsub(screen, 'OnSelect = function%(id: string%)\n\t+deps%.SoundController%.play%("UiClick"%)', "")
		expect(tabClicks).toBe(2)
		local key = stripComments(fs.readFile("src/ui/components/KeyButton.luau"))
		expect(key).toContain('UiSound.play("UiClick")\n\t\tprops.OnClick()')
	end)
end)
