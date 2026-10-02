--!strict
-- The loadout screen (D-147, slice B): what a tap does to the list, what the socket bar shows, which face a
-- glyph card wears, and the screen's promises read from its source -- a full loadout sends nothing, a
-- change can be undone, taking a glyph off is never red, and the offer of more slots is made here only
-- while the pass is not owned.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local LoadoutEdit = require("../src/shared/Pure/LoadoutEdit")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SCREEN = "src/ui/screens/LoadoutScreen.luau"
local CARD = "src/ui/components/GlyphCard.luau"
local STRIP = "src/ui/components/UndoStrip.luau"

local function stripComments(source: string): string
	local lines = {}
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- The body of `local function <name>(` at one tab of indentation, up to its own `end`.
local function body(source: string, name: string, indent: string): string
	local found = string.match(source, "local function " .. name .. "%(.-\n" .. indent .. "end\n")
	if found == nil then
		error(("no local function %s: this gate would check nothing"):format(name))
	end
	return found
end

describe("a tap on a glyph", function()
	it("puts a glyph on at the end while a slot is free", function()
		local slots = { "Brand", "Wash" }
		local updated, outcome = LoadoutEdit.toggle(slots, "Serif", 6)
		expect(outcome).toBe("Equipped")
		expect(updated).toEqual({ "Brand", "Wash", "Serif" })
		-- The list it was given is the server's last word: never written to.
		expect(slots).toEqual({ "Brand", "Wash" })
	end)

	it("takes an equipped glyph off, keeping the others in their order", function()
		local updated, outcome = LoadoutEdit.toggle({ "Brand", "Wash", "Serif" }, "Wash", 6)
		expect(outcome).toBe("Unequipped")
		expect(updated).toEqual({ "Brand", "Serif" })
	end)

	it("refuses a glyph when every slot is taken, and still takes one off", function()
		local full = { "A", "B", "C" }
		local updated, outcome = LoadoutEdit.toggle(full, "D", 3)
		expect(outcome).toBe("Full")
		expect(updated).toEqual(full)
		expect(updated == full).toBe(false)
		local _, off = LoadoutEdit.toggle(full, "B", 3)
		expect(off).toBe("Unequipped")
	end)
end)

describe("the socket bar", function()
	it("fills the equipped slots in order, leaves the rest of the budget empty, and locks what a pass opens", function()
		local sockets = LoadoutEdit.sockets({ "Brand", "Wash", "Serif" }, 6, 10)
		expect(#sockets).toBe(10)
		expect(sockets[1]).toEqual({ Kind = "Filled", Id = "Brand" })
		expect(sockets[3]).toEqual({ Kind = "Filled", Id = "Serif" })
		for index = 4, 6 do
			expect(sockets[index].Kind).toBe("Empty")
		end
		for index = 7, 10 do
			expect(sockets[index].Kind).toBe("Locked")
		end
	end)

	it("grows for an account that may fill more slots than the bar shows", function()
		local sockets = LoadoutEdit.sockets({}, #GlyphConfig.Glyphs, 10)
		expect(#sockets).toBe(#GlyphConfig.Glyphs)
		for _, socket in ipairs(sockets) do
			expect(socket.Kind).toBe("Empty")
		end
	end)
end)

describe("a glyph card", function()
	it("shows locked first, then equipped, then full, then free", function()
		expect(LoadoutEdit.cardState(false, true, true)).toBe("Locked")
		expect(LoadoutEdit.cardState(true, true, true)).toBe("Equipped")
		expect(LoadoutEdit.cardState(true, false, true)).toBe("Full")
		expect(LoadoutEdit.cardState(true, false, false)).toBe("Available")
	end)

	it("stands on the lip of its own pigment, shaded as every lip is", function()
		local card = stripComments(fs.readFile(CARD))
		local shade = tonumber(string.match(card, "local LIP_SHADE = (%-?[%d%.]+)"))
		assert(shade ~= nil, "GlyphCard has no LIP_SHADE: this gate would check nothing")
		local charcoal, vellum = ThemeConfig.Colors.Text, ThemeConfig.Colors.Panel
		-- The pigments whose lip a button already stands on must come out identical.
		local lips = { Cinnabar = "Danger", Indigo = "Info", Verdigris = "Success", Orpiment = "Primary" }
		for pigment, lip in pairs(lips) do
			local computed =
				PigmentConfig.shade((PigmentConfig.Colors :: any)[pigment], shade :: number, charcoal, vellum)
			expect(computed).toEqual(ThemeConfig.Lips[lip])
		end
		expect(card).toContain("Lip = pigmentLip(def.Pigment),")
	end)

	it("never turns red to take a glyph off", function()
		for _, path in ipairs({ SCREEN, CARD }) do
			local source = stripComments(fs.readFile(path))
			expect(string.find(source, '"Danger"', 1, true)).toBeNil()
			expect(string.find(source, "DangerFill", 1, true)).toBeNil()
		end
		local card = stripComments(fs.readFile(CARD))
		expect(card).toContain('if next == "Equipped" then\n\t\t\tbutton:SetVariant("Secondary")')
	end)

	it("still answers a tap on a full loadout's Equip", function()
		local card = stripComments(fs.readFile(CARD))
		expect(card).toContain('if state == "Full" then\n\t\t\tprops.OnRefused()')
		expect(card).toContain('button:SetDisabled(true, "Full", t("loadout.fullShort"))')
	end)
end)

describe("the loadout screen", function()
	local screen = stripComments(fs.readFile(SCREEN))

	it("sends nothing for a full loadout, and shakes the bar instead", function()
		local toggle = body(screen, "toggle", "\t")
		local refused = string.find(toggle, 'if outcome == "Full" then\n\t\t\trefuse()\n\t\t\treturn', 1, true)
		local sent = string.find(toggle, 'deps.RemoteClient.fire("SetLoadout", updated)', 1, true)
		assert(refused ~= nil and sent ~= nil, "LoadoutScreen.toggle no longer refuses or sends")
		expect(refused :: number).toBeLessThan(sent :: number)
		expect(body(screen, "refuse", "\t")).toContain("sockets:Shake()")
	end)

	it("offers every change back, and sends the list it had before", function()
		expect(body(screen, "toggle", "\t")).toContain("showUndo(outcome, def, previous)")
		local undo = body(screen, "showUndo", "\t")
		expect(undo).toContain("equipped = previous")
		expect(undo).toContain('deps.RemoteClient.fire("SetLoadout", previous)')
		local strip = stripComments(fs.readFile(STRIP))
		expect(body(strip, "show", "\t")).toContain("task.delay(Theme.Timing.UndoSeconds,")
	end)

	it("puts the strip away before the card leaves, so no group fades inside another", function()
		local close = body(screen, "close", "\t")
		local hidden = string.find(close, "undoStrip:Hide(false)", 1, true)
		local exit = string.find(close, "root:PlayExit()", 1, true)
		assert(hidden ~= nil and exit ~= nil, "LoadoutScreen.close no longer hides the strip or exits")
		expect(hidden :: number).toBeLessThan(exit :: number)
	end)

	it("offers the slots pass here, only while it is not owned, and lets the server prompt", function()
		expect(screen).toContain('local PASS_KEY = "LoadoutSlots"')
		expect(screen).toContain('deps.RemoteClient.fire("PromptPurchase", "Pass", PASS_KEY)')
		expect(screen).toContain("moreSlots.Instance.Visible = data ~= nil and data.Passes[PASS_KEY] ~= true")
	end)

	it("clicks on a tab and on a socket, which make no sound of their own", function()
		expect(screen).toContain('OnSelect = function(id: string)\n\t\t\tdeps.SoundController.play("UiClick")')
		local sockets = stripComments(fs.readFile("src/ui/components/SocketBar.luau"))
		expect(sockets).toContain('UiSound.play("UiClick")\n\t\t\t\t\tprops.OnSocket(id)')
	end)

	it("draws each recipe from the player's own bindings, and one tab per pigment in its colour", function()
		expect(body(screen, "bindingsFor", "\t")).toContain(
			"return GlyphCard.bindings(if data ~= nil then data.Settings else nil, kind)"
		)
		local card = stripComments(fs.readFile(CARD))
		expect(card).toContain("elseif gamepad then settings.Gamepad")
		expect(card).toContain("else settings.Keyboard")
		expect(screen).toContain("for _, pigment in ipairs(PigmentConfig.Order) do")
		expect(screen).toContain("Tint = Theme.pigmentColor(id),")
	end)
end)
