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

-- The pairs the interface really puts on screen (D-147), each at the floor its size asks for. A gate that
-- loops over every role against one paper checks pairs nobody draws and misses the ones somebody does.
-- `Ink` and `On` name a ThemeConfig.Colors role, or `Pigment.<Id>` for an exact pigment (Orpiment and
-- Verdigris: exact Indigo and Umber are the Info and Bronze roles).
local TEXT_PAIRS = {
	{ Ink = "Text", On = "Panel", Ratio = BODY_CONTRAST, Where = "body text on the page" },
	{ Ink = "Text", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "body text on a card or a Secondary button" },
	{ Ink = "Text", On = "Chalk", Ratio = BODY_CONTRAST, Where = "the Common ribbon, the silver plinth" },
	{ Ink = "TextMuted", On = "Panel", Ratio = BODY_CONTRAST, Where = "a secondary line on the page" },
	{ Ink = "TextMuted", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "a secondary line on a card" },
	{ Ink = "TextMuted", On = "Chalk", Ratio = BODY_CONTRAST, Where = "the label of a disabled button" },
	{ Ink = "Success", On = "Panel", Ratio = BODY_CONTRAST, Where = "+120 XP, a rating that rose" },
	{ Ink = "Success", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "Owned, Claimed on a card" },
	{ Ink = "Premium", On = "Panel", Ratio = BODY_CONTRAST, Where = "a premium label" },
	{ Ink = "Premium", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "a Robux or premium label on a card" },
	{ Ink = "Info", On = "Panel", Ratio = BODY_CONTRAST, Where = "an info line" },
	{ Ink = "Info", On = "PanelRaised", Ratio = BODY_CONTRAST, Where = "an info line on a card" },
	{ Ink = "Text", On = "Primary", Ratio = BODY_CONTRAST, Where = "a Primary button, the Play and Daily bands" },
	{
		Ink = "Text",
		On = "SuccessFill",
		Ratio = BODY_CONTRAST,
		Where = "the Shop band, an Owner button, the claimed stamp",
	},
	{
		Ink = "Text",
		On = "InfoFill",
		Ratio = BODY_CONTRAST,
		Where = "the Quests band, the Rare ribbon, the Script seal",
	},
	{ Ink = "Text", On = "DangerFill", Ratio = BODY_CONTRAST, Where = "a destructive confirm, the warning medallion" },
	{ Ink = "Text", On = "Ally", Ratio = BODY_CONTRAST, Where = "the ally score, your own health number" },
	{ Ink = "Text", On = "Pigment.Orpiment", Ratio = BODY_CONTRAST, Where = "a sigil on an Orpiment chip or disc" },
	{ Ink = "Text", On = "Pigment.Verdigris", Ratio = BODY_CONTRAST, Where = "a sigil on a Verdigris chip or disc" },
	{ Ink = "PanelRaised", On = "Epic", Ratio = BODY_CONTRAST, Where = "the Pass band title, the Epic ribbon" },
	{ Ink = "TextInverse", On = "Epic", Ratio = BODY_CONTRAST, Where = "vellum text on Tyrian" },
	{ Ink = "TextInverse", On = "Info", Ratio = BODY_CONTRAST, Where = "a sigil on an Indigo chip" },
	{ Ink = "TextInverse", On = "Bronze", Ratio = BODY_CONTRAST, Where = "a sigil on an Umber chip, the Sketch seal" },
	{ Ink = "PanelRaised", On = "Bronze", Ratio = BODY_CONTRAST, Where = "an Umber damage number in its stroke" },
	{ Ink = "PanelRaised", On = "Info", Ratio = BODY_CONTRAST, Where = "the Defeat title" },
	{ Ink = "TextInverse", On = "Plate", Ratio = BODY_CONTRAST, Where = "text on a HUD plate or an ink band" },
	{ Ink = "PanelRaised", On = "Plate", Ratio = BODY_CONTRAST, Where = "hero text on a plate" },
	{ Ink = "PanelRaised", On = "Well", Ratio = BODY_CONTRAST, Where = "a number inside a bar track" },
	{ Ink = "Chalk", On = "Plate", Ratio = BODY_CONTRAST, Where = "a hint line on a HUD plate or a hub sign" },
	{ Ink = "Primary", On = "Plate", Ratio = BODY_CONTRAST, Where = "the level and the Folios on hub plates" },
	{ Ink = "Ally", On = "Plate", Ratio = BODY_CONTRAST, Where = "ally names, your share of the boss" },
	{ Ink = "InfoFill", On = "Plate", Ratio = BODY_CONTRAST, Where = "an Indigo damage number, the ink value" },
	{ Ink = "DangerFill", On = "Plate", Ratio = BODY_CONTRAST, Where = "the boss's attack word" },
	{ Ink = "Pigment.Orpiment", On = "Plate", Ratio = BODY_CONTRAST, Where = "an Orpiment damage number, the chain" },
	{ Ink = "Pigment.Verdigris", On = "Plate", Ratio = BODY_CONTRAST, Where = "a Verdigris damage number, the chain" },
	-- Cinnabar is a pigment before it is a colour of text: it stays exact (rule 7), so it is only ever
	-- set large -- the rating line when it falls, a sigil, a number of thirty pixels and up.
	{ Ink = "Danger", On = "Panel", Ratio = ACCENT_CONTRAST, Where = "a rating that fell, 24 units and up" },
	{ Ink = "Danger", On = "PanelRaised", Ratio = ACCENT_CONTRAST, Where = "large danger text on a card" },
	{ Ink = "Text", On = "Danger", Ratio = ACCENT_CONTRAST, Where = "a Cinnabar sigil on its chip" },
	{ Ink = "Danger", On = "Plate", Ratio = ACCENT_CONTRAST, Where = "a Cinnabar damage number" },
	{ Ink = "DangerFill", On = "PanelRaised", Ratio = ACCENT_CONTRAST, Where = "damage taken, in its sheet stroke" },
}

-- Graphics against what they are drawn on (WCAG 1.4.11: 3 for a part of the interface): a bar's fill on
-- its empty track, the ghost beside the fill, and a plate or an outline against the cream world.
local GRAPHIC_PAIRS = {
	{ Ink = "Ally", On = "Well", Where = "the health bar" },
	{ Ink = "InfoFill", On = "Well", Where = "the ink bar" },
	{ Ink = "Primary", On = "Well", Where = "XP, quests and pass progress" },
	{ Ink = "SuccessFill", On = "Well", Where = "a claimed quest's bar" },
	{ Ink = "DangerFill", On = "Well", Where = "low health, the boss's bar" },
	{ Ink = "Danger", On = "Well", Where = "the health ghost on the empty track" },
	{ Ink = "Danger", On = "Ally", Where = "the health ghost beside the cyan fill" },
	{ Ink = "Plate", On = "Panel", Where = "every HUD plate and every sticker outline on the page" },
}

-- The redmean distance tests/Config.spec.luau holds the pigments apart with.
local function redmean(a: { number }, b: { number }): number
	local rmean = (a[1] + b[1]) / 2
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt((2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db)
end

-- The colour a pair names: a role, or an exact pigment.
local function pairColor(name: string): ThemeConfig.Rgb
	local pigment = string.match(name, "^Pigment%.(%w+)$")
	local rgb = if pigment ~= nil then (PigmentConfig.Colors :: any)[pigment] else ThemeConfig.Colors[name]
	assert(rgb ~= nil, "no such role or pigment in a pair: " .. name)
	return rgb
end

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
-- "une ronde d'affiche pour les titres": the rounded poster face the engine ships.
local ROUNDED_DISPLAY = { FredokaOne = true }
-- "une grotesque ronde pour les mots".
local ROUNDED_GROTESQUE = { Nunito = true }
-- "la romane garde le lore": the serifs the engine ships.
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
		expect(#TEXT_PAIRS).toBeGreaterThanOrEqual(12)
		for _, pair in ipairs(TEXT_PAIRS) do
			local ratio = ThemeConfig.contrast(pairColor(pair.Ink), pairColor(pair.On))
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

	it("draws graphics at 3 against their track", function()
		for _, pair in ipairs(GRAPHIC_PAIRS) do
			local ratio = ThemeConfig.contrast(pairColor(pair.Ink), pairColor(pair.On))
			if ratio < ACCENT_CONTRAST then
				error(("%s does not stand out: %s on %s measures %.2f"):format(pair.Where, pair.Ink, pair.On, ratio))
			end
		end
	end)

	it("its primary is poster ink, not the default gold", function()
		-- The bible bans the default Roblox gold by value ("accent or `230,180,60`"); the primary yellow is
		-- held at least 100 (redmean) away from it, and charcoal reads on it as body text.
		local banned = { string.match(fs.readFile(BIBLE), "accent or `(%d+),(%d+),(%d+)`") }
		assert(#banned == 3, "docs/ART_BIBLE.md no longer names the banned gold: this gate would check nothing")
		local gold = { tonumber(banned[1]) :: number, tonumber(banned[2]) :: number, tonumber(banned[3]) :: number }
		expect(redmean(ThemeConfig.Colors.Primary, gold)).toBeGreaterThanOrEqual(100)
		expect(ThemeConfig.contrast(ThemeConfig.Colors.Text, ThemeConfig.Colors.Primary)).toBeGreaterThanOrEqual(
			BODY_CONTRAST
		)
	end)

	it("picks the ink that reads on each pigment", function()
		local colors = ThemeConfig.Colors
		expect(ThemeConfig.inkOn(PigmentConfig.Colors.Orpiment)).toEqual(colors.Text)
		expect(ThemeConfig.inkOn(PigmentConfig.Colors.Indigo)).toEqual(colors.TextInverse)
		expect(ThemeConfig.inkOn(PigmentConfig.Colors.Umber)).toEqual(colors.TextInverse)
		for _, role in ipairs({ "Primary", "SuccessFill", "InfoFill", "DangerFill", "Ally" }) do
			if ThemeConfig.inkOn(colors[role]) ~= colors.Text then
				error(("the ink on %s should be charcoal"):format(role))
			end
		end
		for _, role in ipairs({ "Epic", "Plate", "Bronze" }) do
			if ThemeConfig.inkOn(colors[role]) ~= colors.TextInverse then
				error(("the ink on %s should be vellum"):format(role))
			end
		end
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
			local style = def.Style
			if style ~= nil and string.find(dump, "\t" .. style .. ": EnumFontStyle\n", 1, true) == nil then
				error(("%s asks for style %s, which Enum.FontStyle does not have"):format(role, style))
			end
		end
	end)

	it(
		"sets display in a rounded poster face, words in a rounded grotesque, numbers in a condensed grotesque, and keeps the roman for lore",
		function()
			local fonts = ThemeConfig.Fonts
			local function setIn(roles: { string }, faces: { [string]: boolean }, what: string)
				for _, role in ipairs(roles) do
					local def = fonts[role]
					if def == nil or not faces[def.Font] then
						error(("%s is not set in %s"):format(role, what))
					end
				end
			end
			setIn({ "Title", "Display" }, ROUNDED_DISPLAY, "a rounded poster face")
			setIn({ "Body", "Bold", "Label" }, ROUNDED_GROTESQUE, "a rounded grotesque")
			setIn({ "Numeric" }, CONDENSED, "a condensed grotesque")
			setIn({ "Lore", "Initial", "Symbol" }, SERIFS, "a roman")
			-- Words are one face at three weights, and the lore, the drop cap and the arrows one roman.
			expect(fonts.Bold.Font).toBe(fonts.Body.Font)
			expect(fonts.Label.Font).toBe(fonts.Body.Font)
			expect(fonts.Initial.Font).toBe(fonts.Lore.Font)
			expect(fonts.Symbol.Font).toBe(fonts.Lore.Font)
			expect(fonts.Lore.Style).toBe("Italic")
		end
	)
end)

describe("the interface's motion", function()
	it(
		"has the five presets Motion names; only the ghost is critically damped; the pop overshoots by a fifth to a third",
		function()
			for _, name in ipairs({ "Ui", "UiSnappy", "UiPop", "UiExit" }) do
				local def = FeelConfig.Springs[name]
				-- Under critical friction the value overshoots and comes back: what makes it alive.
				expect(def.Friction).toBeLessThan(Spring.criticalFriction(def.Tension))
			end
			local ghost = FeelConfig.Springs.UiGhost
			-- At or above critical the ghost of a bar never overshoots: an overshoot is health coming back.
			expect(ghost.Friction).toBeGreaterThanOrEqual(Spring.criticalFriction(ghost.Tension))
			-- A damping ratio of 0.32 to 0.52 overshoots by 35 % down to 15 %: a pop, neither a wobble nor a nudge.
			local pop = FeelConfig.Springs.UiPop
			local ratio = pop.Friction / (2 * math.sqrt(pop.Tension))
			expect(ratio).toBeGreaterThanOrEqual(0.32)
			expect(ratio).toBeLessThanOrEqual(0.52)
			-- And every preset Motion's type names is one FeelConfig has.
			local line = string.match(fs.readFile("src/ui/Motion.luau"), "export type Preset = ([^\n]+)")
			assert(line ~= nil, "Motion no longer declares its presets: this gate would check nothing")
			local count = 0
			for name in string.gmatch(line :: string, '"(%w+)"') do
				count += 1
				if FeelConfig.Springs[name] == nil then
					error(("Motion names the preset %s, which FeelConfig.Springs does not have"):format(name))
				end
			end
			expect(count).toBeGreaterThanOrEqual(3)
		end
	)

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
