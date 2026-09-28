--!strict
-- The frame every screen shares (D-147): the root's backdrop, its entrance and exit, the card and its band.
-- Most of it is engine code that Lune cannot run, so what can regress silently is held by reading it: a
-- screen that vanishes instead of leaving, a dim that ignores the player's own setting, a HUD that grows
-- with the menus' text size, a cross that turns red. The drop cap's split is pure and runs here.
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOT = "src/ui/components/ScreenRoot.luau"
local PANEL = "src/ui/components/Panel.luau"
local BAND = "src/ui/components/ChapterBand.luau"
local CONTENT = "src/ui/components/CardContent.luau"
local HUD = "src/client/Controllers/HudController.luau"

-- The title of every screen that has one, as the player reads it.
local TITLE_KEYS = {
	"menu.title",
	"queue.title",
	"shop.title",
	"battlepass.title",
	"daily.title",
	"menu.quests",
	"loadout.title",
	"leaderboard.title",
	"settings.title",
}

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

-- The body of the local function `name` in `source`, up to its closing `end` at the same indent.
local function body(source: string, name: string): string
	local indent, rest = string.match(source, "\n(\t*)local function " .. name .. "%((.*)")
	assert(indent ~= nil and rest ~= nil, ("no local function %s: this gate would check nothing"):format(name))
	local finish = string.find(rest :: string, "\n" .. (indent :: string) .. "end\n", 1, true)
	assert(finish ~= nil, ("%s has no end"):format(name))
	return string.sub(rest :: string, 1, finish :: number)
end

local function count(source: string, plain: string): number
	local found, from = 0, 1
	while true do
		local at = string.find(source, plain, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + 1
	end
end

describe("the drop cap", function()
	it("takes a title's first letter, accented or not, and leaves the rest", function()
		local letter, rest = ThemeConfig.dropCap("Quêtes")
		expect(letter).toBe("Q")
		expect(rest).toBe("uêtes")
		letter, rest = ThemeConfig.dropCap("Équipement")
		expect(letter).toBe("É")
		expect(rest).toBe("quipement")
		letter, rest = ThemeConfig.dropCap("M")
		expect(letter).toBe("M")
		expect(rest).toBe("")
	end)

	it("is never a digit, a quote or a sign: that title stays whole", function()
		for _, title in ipairs({ "3v3", "« Menu »", "×2", "", "—" }) do
			local letter, rest = ThemeConfig.dropCap(title)
			if letter ~= nil then
				error(("%q opens on %q, which is no letter"):format(title, letter))
			end
			expect(rest).toBe(title)
		end
	end)

	it("opens every screen's title in both languages, as one character", function()
		for _, key in ipairs(TITLE_KEYS) do
			local entry = Strings.Table[key]
			assert(entry ~= nil, ("no title %s"):format(key))
			for _, title in ipairs({ entry.en, entry.fr }) do
				local letter, rest = ThemeConfig.dropCap(title)
				if letter == nil then
					error(("%s (%q) has no drop cap"):format(key, title))
				end
				expect(utf8.len(letter :: string)).toBe(1)
				expect((letter :: string) .. rest).toBe(title)
			end
		end
	end)
end)

describe("the backdrop", function()
	it("dims by the player's own background-transparency setting, and takes the clicks", function()
		local root = code(ROOT)
		expect(string.find(root, "local DIM = 0.35\n", 1, true)).never.toBeNil()
		expect(string.find(body(root, "dimTarget"), "return DIM * UiPrefs.transparency()", 1, true)).never.toBeNil()
		expect(string.find(root, "overlay.Active = true", 1, true)).never.toBeNil()
	end)

	it("draws no corner blots on the lowest graphics tier", function()
		expect(string.find(body(code(ROOT), "showCorners"), "local shown = not UiPrefs.lowQuality()", 1, true)).never.toBeNil()
	end)

	it("leaves the screen at least half of its splats", function()
		local blots = count(string.match(code(ROOT), "local CORNERS[^=]*= (%b{})") or "", "Position =")
		local drips = count(string.match(code(BAND), "local DRIPS[^=]*= (%b{})") or "", "X =")
		expect(blots).toBe(3)
		expect(drips).toBe(3)
		expect(blots + drips).toBeLessThanOrEqual(ThemeConfig.Budget.MaxSplats / 2)
	end)
end)

describe("the player's text size", function()
	it("grows a menu that asks for it, and never the HUD", function()
		expect(
			string.find(
				code(ROOT),
				"currentScale = Theme.activeScale() * (if textScalable then UiPrefs.textScale() else 1)",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(code(ROOT), "local textScalable = props.TextScalable == true", 1, true)).never.toBeNil()
		-- The HUD's geometry is measured at the designed sizes (D-147 §2.9).
		local hud: string? = nil
		for call in string.gmatch(code(HUD), "ScreenRoot%.new(%b())") do
			if string.find(call, 'Name = "Hud"', 1, true) ~= nil then
				hud = call
			end
		end
		assert(hud ~= nil, "the HUD builds no root: this gate would check nothing")
		expect(string.find(hud :: string, "TextScalable", 1, true)).toBeNil()
	end)
end)

describe("a screen that leaves", function()
	it("is disabled only once its card has faded out (rule 3: nothing vanishes)", function()
		local root = code(ROOT)
		-- One place turns a screen off: the end of its exit.
		expect(count(root, "gui.Enabled = false")).toBe(1)
		expect(string.find(body(root, "finish"), "gui.Enabled = false", 1, true)).never.toBeNil()
		expect(string.find(body(root, "playExit"), "current:PlayExit(finish)", 1, true)).never.toBeNil()
	end)

	it("fades once when asked to leave twice, and the second caller waits for the same end", function()
		local exit = body(code(ROOT), "playExit")
		local guard = string.find(exit, "if exiting then\n\t\t\treturn\n\t\tend", 1, true)
		local start = string.find(exit, "exitToken += 1", 1, true)
		assert(guard ~= nil and start ~= nil, "the exit has no guard: a second call would cut the first short")
		expect(guard :: number).toBeLessThan(start :: number)
		expect(string.find(exit, "table.insert(exitCallbacks, onDone)", 1, true)).never.toBeNil()
	end)

	it("fades its card as one piece, through a group that does not outlive the exit", function()
		local panel = code(PANEL)
		local exit = body(panel, "playExit")
		expect(string.find(exit, 'Instance.new("CanvasGroup")', 1, true)).never.toBeNil()
		expect(string.find(exit, 'Motion.to(group, { GroupTransparency = 1 }, "UiExit", function()', 1, true)).never.toBeNil()
		expect(string.find(body(panel, "restoreFromExit"), "group:Destroy()", 1, true)).never.toBeNil()
		-- Under reduced motion only the fade runs.
		expect(string.find(exit, "if not UiPrefs.reducedMotion() then", 1, true)).never.toBeNil()
		-- An entrance catches an exit in flight: the card comes back, and that exit never calls its end.
		expect(string.find(body(panel, "playEnter"), "exitToken += 1\n\t\trestoreFromExit()", 1, true)).never.toBeNil()
	end)
end)

describe("the card", function()
	it("is a vellum sticker, its band outlined in ink (rule 11)", function()
		local panel = code(PANEL)
		expect(string.find(panel, 'Kind = "Card",\n\t\tFill = Theme.Colors.Panel,', 1, true)).never.toBeNil()
		expect(string.find(code(BAND), 'Theme.stroke(band, "Accent", Theme.Sizes.Stroke)', 1, true)).never.toBeNil()
	end)

	it("closes without red: leaving a screen is no danger", function()
		for _, path in ipairs({ ROOT, PANEL, BAND, CONTENT }) do
			if string.find(code(path), "Danger", 1, true) ~= nil then
				error(path .. " draws in red")
			end
		end
	end)

	it("springs up the first rows in view at an entrance, and never one scrolled past", function()
		local content = code(CONTENT)
		local enter = body(content, "playEnter")
		expect(string.find(enter, "child.Visible and not scrolledPast(child)", 1, true)).never.toBeNil()
		expect(string.find(enter, 'Motion.stagger(scales, { Scale = 1 }, "UiPop")', 1, true)).never.toBeNil()
		local past = body(content, "scrolledPast")
		expect(
			string.find(past, "child.AbsolutePosition.Y + child.AbsoluteSize.Y <= content.AbsolutePosition.Y", 1, true)
		).never.toBeNil()
		expect(
			string.find(past, "child.AbsolutePosition.X + child.AbsoluteSize.X <= content.AbsolutePosition.X", 1, true)
		).never.toBeNil()
	end)

	it("bobs its more-below arrow only while there is more and the screen is up", function()
		expect(string.find(body(code(CONTENT), "update"), "setBobbing(more and shown)", 1, true)).never.toBeNil()
	end)
end)
