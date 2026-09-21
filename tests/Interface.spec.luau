--!strict
-- The interface is held to docs/ART_BIBLE.md: the page's two colours are the bible's hexes, the pigments
-- it names are the ones PigmentConfig carries, every text role reads on the paper it is set on, the
-- fonts are not the engine's defaults the bible replaces, and nothing in src/ui moves on a tween or
-- names a colour or a font of its own.
--
-- Source-level where it has to be: no Lune test can hold a TweenService or a Color3, and a component
-- that reaches for either is only caught by reading it.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local Spring = require("../src/shared/Pure/Spring")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local BIBLE = "docs/ART_BIBLE.md"
local THEME = "src/ui/Theme.luau"
-- The engine's own API dump, which is what Theme resolves its faces against at load.
local GLOBAL_TYPES = "globalTypes.d.luau"
-- The renderers own their own colours (an effect is not the interface), and WorldLighting converts its
-- config's triples the way Theme does.
local COLOR_OWNERS: { [string]: boolean } = {
	[THEME] = true,
	["src/client/Controllers/WorldLighting.luau"] = true,
}
local COLOR_OWNER_PREFIX = "src/client/Controllers/Vfx"

-- WCAG: 4.5 for body text, 3 for large text, accents and interface parts.
local BODY_CONTRAST = 4.5
local ACCENT_CONTRAST = 3

-- The pairs the interface really puts on screen, each at the floor its size asks for. A gate that loops
-- over every role against one paper checks pairs nobody draws and misses the ones somebody does: the
-- battle pass sets gold at thirteen pixels on the SHADED sheet, and the loadout set Cinnabar there.
local TEXT_PAIRS = {
	{ Ink = "Text", On = "Panel", Ratio = BODY_CONTRAST, Where = "body text on the page" },
	{ Ink = "TextMuted", On = "Panel", Ratio = BODY_CONTRAST, Where = "a secondary line on the page" },
	{ Ink = "Text", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "body text on a shaded sheet" },
	{ Ink = "TextMuted", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "a locked glyph's line" },
	{ Ink = "Info", On = "Panel", Ratio = BODY_CONTRAST, Where = "the rating line" },
	{ Ink = "Success", On = "Panel", Ratio = BODY_CONTRAST, Where = "the first win of the day" },
	{ Ink = "Success", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "a claimed reward" },
	{ Ink = "Premium", On = "Panel", Ratio = BODY_CONTRAST, Where = "the premium column" },
	{ Ink = "Premium", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "a premium row of the pass" },
	{ Ink = "TextInverse", On = "Accent", Ratio = BODY_CONTRAST, Where = "the label of a primary button" },
	-- Cinnabar is a pigment before it is a colour of text: it stays exact (rule 7), so it is only ever
	-- set large -- the rating line when it falls, and a Danger button -- and only on the page itself.
	{ Ink = "Danger", On = "Panel", Ratio = ACCENT_CONTRAST, Where = "a rating that fell" },
	{ Ink = "Text", On = "Danger", Ratio = ACCENT_CONTRAST, Where = "the label of a Danger button" },
}

-- The engine's defaults, which docs/ART_BIBLE.md says are replaced.
local DEFAULT_FONTS = {
	"Gotham",
	"GothamMedium",
	"GothamBold",
	"GothamBlack",
	"RobotoMono",
	"SourceSans",
	"SourceSansBold",
	"SourceSansSemibold",
	"SourceSansLight",
	"BuilderSans",
	"BuilderSansMedium",
	"BuilderSansBold",
	"Arial",
	"ArialBold",
	"Legacy",
}
-- "une romane à empattements pour les titres": the serifs the engine ships.
local SERIFS = { Merriweather = true, Garamond = true, Bodoni = true }
-- "une grotesque condensée pour les chiffres": the condensed faces the engine ships.
local CONDENSED = { Oswald = true, RobotoCondensed = true }
local WEIGHTS = {
	Thin = true,
	ExtraLight = true,
	Light = true,
	Regular = true,
	Medium = true,
	SemiBold = true,
	Bold = true,
	ExtraBold = true,
	Heavy = true,
}

local function hexToRgb(hex: string): ThemeConfig.Rgb
	return {
		tonumber(string.sub(hex, 1, 2), 16) :: number,
		tonumber(string.sub(hex, 3, 4), 16) :: number,
		tonumber(string.sub(hex, 5, 6), 16) :: number,
	}
end

-- The hex the bible writes after `name`, as in "Vélin `#E8E0CE`".
local function bibleHex(name: string): ThemeConfig.Rgb
	local bible = fs.readFile(BIBLE)
	local hex = string.match(bible, name .. " `#(%x%x%x%x%x%x)`")
	assert(hex ~= nil, "docs/ART_BIBLE.md no longer names " .. name .. " with a hex")
	return hexToRgb(hex :: string)
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function offenders(roots: { string }, patterns: { string }, allowed: (string) -> boolean): { string }
	local files: { string } = {}
	for _, root in ipairs(roots) do
		collect(root, files)
	end
	assert(#files > 10, "found almost no interface files: the roots are wrong")
	local found: { string } = {}
	for _, path in ipairs(files) do
		if not allowed(path) then
			local code = stripComments(fs.readFile(path))
			for _, pattern in ipairs(patterns) do
				if string.find(code, pattern) ~= nil then
					table.insert(found, ("%s matches %s"):format(path, pattern))
				end
			end
		end
	end
	table.sort(found)
	return found
end

local function never(_path: string): boolean
	return false
end

describe("the page", function()
	it("is the bible's vellum and charcoal", function()
		expect(ThemeConfig.Vellum).toEqual(bibleHex("Vélin"))
		expect(ThemeConfig.Charcoal).toEqual(bibleHex("Charbon"))
		expect(ThemeConfig.Colors.Panel).toEqual(ThemeConfig.Vellum)
		expect(ThemeConfig.Colors.Text).toEqual(ThemeConfig.Charcoal)
		expect(ThemeConfig.Colors.TextInverse).toEqual(ThemeConfig.Vellum)
	end)

	it("has no gold accent: the accent of a page is its ink", function()
		expect(ThemeConfig.Colors.Accent).toEqual(ThemeConfig.Charcoal)
	end)

	it("says danger in Cinnabar and information in Indigo, exactly", function()
		expect(ThemeConfig.Colors.Danger).toEqual(PigmentConfig.Colors.Cinnabar)
		expect(ThemeConfig.Colors.Info).toEqual(PigmentConfig.Colors.Indigo)
	end)

	it("reads: every pair the interface draws has its contrast", function()
		local colors = ThemeConfig.Colors
		expect(#TEXT_PAIRS).toBeGreaterThanOrEqual(12)
		for _, pair in ipairs(TEXT_PAIRS) do
			local ink = colors[pair.Ink]
			local paper = colors[pair.On]
			assert(ink ~= nil and paper ~= nil, ("no such role in the pair %s / %s"):format(pair.Ink, pair.On))
			local ratio = ThemeConfig.contrast(ink, paper)
			if ratio < pair.Ratio then
				error(
					("%s is under its floor: %s on %s measures %.2f, floor %.2f"):format(
						pair.Where,
						pair.Ink,
						pair.On,
						ratio,
						pair.Ratio
					)
				)
			end
		end
	end)

	it("picks the ink that reads on each pigment", function()
		expect(ThemeConfig.inkOn(PigmentConfig.Colors.Orpiment)).toEqual(ThemeConfig.Colors.Text)
		expect(ThemeConfig.inkOn(PigmentConfig.Colors.Indigo)).toEqual(ThemeConfig.Colors.TextInverse)
		expect(ThemeConfig.inkOn(PigmentConfig.Colors.Umber)).toEqual(ThemeConfig.Colors.TextInverse)
	end)

	it("measures contrast the WCAG way", function()
		expect(ThemeConfig.contrast({ 0, 0, 0 }, { 255, 255, 255 })).toBeCloseTo(21, 1)
		expect(ThemeConfig.contrast({ 128, 128, 128 }, { 128, 128, 128 })).toBeCloseTo(1, 3)
	end)
end)

describe("the type", function()
	it("is not the engine's default faces", function()
		for role, def in pairs(ThemeConfig.Fonts) do
			for _, banned in ipairs(DEFAULT_FONTS) do
				if def.Font == banned then
					error(("%s is set in %s, which docs/ART_BIBLE.md replaces"):format(role, banned))
				end
			end
			if not WEIGHTS[def.Weight] then
				error(("%s has no such weight: %s"):format(role, def.Weight))
			end
		end
	end)

	it("names faces and weights the engine really has", function()
		-- Theme turns each name into a Font at LOAD: `Font.fromEnum((Enum.Font :: any)[name])` on a name the
		-- engine does not have passes nil to fromEnum, which throws -- and a Theme that throws takes the HUD
		-- and all ten screens with it, silently, the way GuiService.SafeZoneOffsetsChanged once did
		-- (tests/EngineOnlyApi.spec.luau). Nothing else in the repository can see that: it is valid Luau, it
		-- type-checks, and no unit test can hold an Enum. The API dump can.
		local dump = fs.readFile(GLOBAL_TYPES)
		for role, def in pairs(ThemeConfig.Fonts) do
			if string.find(dump, "\t" .. def.Font .. ": EnumFont\n", 1, true) == nil then
				error(("%s is set in %s, which Enum.Font does not have"):format(role, def.Font))
			end
			if string.find(dump, "\t" .. def.Weight .. ": EnumFontWeight\n", 1, true) == nil then
				error(("%s asks for weight %s, which Enum.FontWeight does not have"):format(role, def.Weight))
			end
		end
	end)

	it("sets words in a roman and numbers in a condensed grotesque", function()
		for _, role in ipairs({ "Title", "Body", "Bold" }) do
			local def = ThemeConfig.Fonts[role]
			if not SERIFS[def.Font] then
				error(("%s is set in %s, which is not a roman"):format(role, def.Font))
			end
		end
		expect(CONDENSED[ThemeConfig.Fonts.Numeric.Font]).toBe(true)
		-- A page is set in one face: the title is the body's face at its bold weight.
		expect(ThemeConfig.Fonts.Title.Font).toBe(ThemeConfig.Fonts.Body.Font)
		expect(ThemeConfig.Fonts.Bold.Font).toBe(ThemeConfig.Fonts.Body.Font)
	end)
end)

describe("the interface's motion", function()
	it("has the three presets Motion names, and only the ghost is critically damped", function()
		for _, name in ipairs({ "Ui", "UiSnappy" }) do
			local def = FeelConfig.Springs[name]
			-- Under critical friction the value overshoots and comes back: what makes it alive.
			expect(def.Friction).toBeLessThan(Spring.criticalFriction(def.Tension))
		end
		local ghost = FeelConfig.Springs.UiGhost
		-- At or above critical the ghost of a bar never overshoots: an overshoot is health coming back.
		expect(ghost.Friction).toBeGreaterThanOrEqual(Spring.criticalFriction(ghost.Tension))
	end)

	it("is springs: nothing in src/ui tweens", function()
		local found = offenders({ "src/ui" }, { "TweenService", "TweenInfo" }, never)
		if #found > 0 then
			error("the interface moves on src/ui/Motion.luau, not on tweens:\n" .. table.concat(found, "\n"))
		end
	end)

	it("actually drives springs in Motion, so this cannot pass vacuously", function()
		local motion = stripComments(fs.readFile("src/ui/Motion.luau"))
		expect(string.find(motion, "Spring%.step") ~= nil).toBe(true)
		expect(string.find(motion, "Heartbeat") ~= nil).toBe(true)
	end)
end)

describe("the interface's colours and fonts", function()
	it("all come from Theme: no component names a colour", function()
		local found = offenders(
			{ "src/ui", "src/client" },
			{ "Color3%.fromRGB%(", "Color3%.new%(", "Color3%.fromHex%(", "Color3%.fromHSV%(" },
			function(path)
				return COLOR_OWNERS[path] == true or string.sub(path, 1, #COLOR_OWNER_PREFIX) == COLOR_OWNER_PREFIX
			end
		)
		if #found > 0 then
			error("colours are Theme's (ThemeConfig's, really):\n" .. table.concat(found, "\n"))
		end
	end)

	it("all come from Theme: no component names a font", function()
		local found = offenders({ "src/ui", "src/client" }, { "Enum%.Font%.", "%.Font = " }, function(path)
			return path == THEME
		end)
		if #found > 0 then
			error("fonts are Theme.Fonts, written to FontFace:\n" .. table.concat(found, "\n"))
		end
	end)

	it("actually converts colours and fonts in Theme, so this cannot pass vacuously", function()
		local theme = stripComments(fs.readFile(THEME))
		expect(string.find(theme, "Color3%.fromRGB%(") ~= nil).toBe(true)
		expect(string.find(theme, "Font%.new%(") ~= nil).toBe(true)
	end)
end)
