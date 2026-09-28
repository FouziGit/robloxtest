--!strict
-- The colourful interface (D-147) held to its own rules: lips computed from the pigments, chapters that are
-- never red nor ours, rarities and ranks that never rely on colour alone, a cyan and a blue that a
-- colour-blind player still tells apart, and no value colour in a fight. Source-level where it has to
-- be: a HUD file that names the primary yellow is only caught by reading it.
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local THEME = "src/ui/Theme.luau"
local STICKER = "src/ui/components/Sticker.luau"
-- The components of the colourful interface: every line they draw goes through Theme.stroke, which fixes
-- its sizing mode and floors its thickness. Each one joins in the commit that builds or restyles it.
local STROKED_COMPONENTS = {
	"Sticker",
	"Icon",
	"Badge",
	"Seal",
	"Pips",
	"Splat",
	"DropCap",
	"Keycap",
	"RarityRibbon",
	"ConfirmSheet",
}
local BODY_CONTRAST = 4.5

-- Fight surfaces: what is on screen during a round. Each one is added here in the commit that makes it
-- comply; HudController joins when its roster stops naming Success (spec slice C).
local FIGHT_FILES = {
	"src/client/Controllers/BossController.luau",
	"src/client/Controllers/Feel.luau",
	"src/client/Controllers/LockOnController.luau",
	"src/client/Controllers/SpectateController.luau",
	"src/ui/components/DamageNumber.luau",
	"src/ui/components/LockMarker.luau",
	"src/ui/components/TouchButton.luau",
}
-- Rule 11: the value colours never enter a fight, by role, by helper, or through a chapter, a rarity or
-- a rank.
local VALUE_PATTERNS = {
	"Theme%.Colors%.Primary%f[%W]",
	"Theme%.Colors%.Epic",
	"Theme%.Colors%.Premium",
	"Theme%.Colors%.SuccessFill",
	"Theme%.Colors%.Success%f[%W]",
	"Theme%.chapter%(",
	"Theme%.rarity%(",
	"Theme%.rank%(",
}
-- The same roles asked for by name.
local VALUE_ROLES = { Primary = true, Epic = true, Premium = true, SuccessFill = true, Success = true }
local VALUE_LIPS = { Primary = true, Epic = true, Success = true }

-- Luau's string.upper is ASCII-only: "Réclamer" comes out "RéCLAMER". Sentence case everywhere instead.
local UPPER_ROOTS = { "src/ui" }
local UPPER_PREFIXES = {
	"src/client/Controllers/Hud",
	"src/client/Controllers/Menu",
	"src/client/Controllers/HubSigns",
}

-- Machado, Oliveira and Fernandes (2009), severity 1.0, applied in linear sRGB.
local CVD: { [string]: { { number } } } = {
	Protan = {
		{ 0.152286, 1.052583, -0.204868 },
		{ 0.114503, 0.786281, 0.099216 },
		{ -0.003882, -0.048116, 1.051998 },
	},
	Deutan = {
		{ 0.367322, 0.860646, -0.227968 },
		{ 0.280085, 0.672501, 0.047413 },
		{ -0.011820, 0.042940, 0.968881 },
	},
}

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

-- The redmean distance tests/Config.spec.luau holds the pigments apart with.
local function redmean(a: { number }, b: { number }): number
	local rmean = (a[1] + b[1]) / 2
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt((2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db)
end

local function toLinear(value: number): number
	local c = value / 255
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function toSrgb(value: number): number
	local c = math.clamp(value, 0, 1)
	local encoded = if c <= 0.0031308 then 12.92 * c else 1.055 * c ^ (1 / 2.4) - 0.055
	return math.floor(encoded * 255 + 0.5)
end

-- What a viewer with the deficiency `kind` sees of `rgb`.
local function simulate(rgb: { number }, kind: string): { number }
	local matrix = CVD[kind]
	local linear = { toLinear(rgb[1]), toLinear(rgb[2]), toLinear(rgb[3]) }
	local out = {}
	for row = 1, 3 do
		local m = matrix[row]
		out[row] = toSrgb(m[1] * linear[1] + m[2] * linear[2] + m[3] * linear[3])
	end
	return out
end

local function shade(rgb: { number }): { number }
	return PigmentConfig.shade(rgb, -0.25, ThemeConfig.Charcoal, ThemeConfig.Vellum)
end

describe("the lips", function()
	it("are each pigment shaded a quarter toward the ink", function()
		local lips = ThemeConfig.Lips
		expect(lips.Primary).toEqual(shade(PigmentConfig.Colors.Orpiment))
		expect(lips.Success).toEqual(shade(PigmentConfig.Colors.Verdigris))
		expect(lips.Info).toEqual(shade(PigmentConfig.Colors.Indigo))
		expect(lips.Danger).toEqual(shade(PigmentConfig.Colors.Cinnabar))
		-- Tyrian is no pigment, so the same formula is applied to the role itself.
		expect(lips.Epic).toEqual(shade(ThemeConfig.Colors.Epic))
		expect(lips.Secondary).toEqual(ThemeConfig.Colors.Chalk)
		expect(lips.Plate).toEqual(ThemeConfig.Colors.Chalk)
	end)

	it("sit under a face they name, and every face role names one", function()
		for face, lip in pairs(ThemeConfig.LipFor) do
			if ThemeConfig.Colors[face] == nil then
				error(("a lip is set for %s, which is no colour role"):format(face))
			end
			if ThemeConfig.Lips[lip] == nil then
				error(("%s sits on the lip %s, which does not exist"):format(face, lip))
			end
		end
	end)
end)

describe("the chapters", function()
	it("are colour roles, never red and never ours", function()
		local count = 0
		for screen, role in pairs(ThemeConfig.Chapters) do
			count += 1
			if ThemeConfig.Colors[role] == nil then
				error(("%s's chapter %s is no colour role"):format(screen, role))
			end
			if role == "Danger" or role == "DangerFill" or role == "Ally" or role == "Health" then
				error(("%s's chapter is %s: red is danger and cyan is us, never a chapter"):format(screen, role))
			end
		end
		expect(count).toBeGreaterThanOrEqual(9)
	end)

	it("title every band in an ink that reads on it", function()
		for screen, role in pairs(ThemeConfig.Chapters) do
			local ink = ThemeConfig.labelRole(role)
			local ratio = ThemeConfig.contrast(ThemeConfig.Colors[ink], ThemeConfig.Colors[role])
			if ratio < BODY_CONTRAST then
				error(("%s's title, %s on %s, measures %.2f"):format(screen, ink, role, ratio))
			end
		end
		-- The inks the design fixes: vellum on the ink band, the sheet on Tyrian and on Indigo.
		expect(ThemeConfig.labelRole("Plate")).toBe("TextInverse")
		expect(ThemeConfig.labelRole("Primary")).toBe("Text")
		expect(ThemeConfig.labelRole("SuccessFill")).toBe("Text")
		expect(ThemeConfig.labelRole("InfoFill")).toBe("Text")
		expect(ThemeConfig.labelRole("Epic")).toBe("PanelRaised")
		expect(ThemeConfig.labelRole("Info")).toBe("PanelRaised")
		expect(ThemeConfig.labelRole("Bronze")).toBe("PanelRaised")
		expect(ThemeConfig.labelRole("Chalk")).toBe("Text")
	end)

	it("give every menu screen a lip for its Owner buttons", function()
		for _, screen in ipairs({
			"Menu",
			"Play",
			"Daily",
			"Shop",
			"Quests",
			"Battlepass",
			"Loadout",
			"Leaderboard",
			"Settings",
		}) do
			local role = ThemeConfig.Chapters[screen]
			if role == nil or ThemeConfig.LipFor[role] == nil then
				error(("%s has no chapter lip"):format(screen))
			end
		end
	end)

	it("stripe only ink bands", function()
		for screen in pairs(ThemeConfig.ChapterStripe) do
			expect(ThemeConfig.Chapters[screen]).toBe("Plate")
		end
	end)
end)

describe("the rarities and the ranks", function()
	it("never rely on colour alone: four rarities, one to four pips, and a word each", function()
		local seen: { [number]: string } = {}
		local count = 0
		for rarity, def in pairs(ThemeConfig.Rarity) do
			count += 1
			if ThemeConfig.Colors[def.Fill] == nil then
				error(("%s is filled with %s, which is no colour role"):format(rarity, def.Fill))
			end
			if seen[def.Pips] ~= nil then
				error(("%s and %s both show %d pips"):format(rarity, seen[def.Pips], def.Pips))
			end
			seen[def.Pips] = rarity
			if not Strings.has("shop.rarity." .. rarity) then
				error(("%s has no word in Strings"):format(rarity))
			end
			local ink = ThemeConfig.labelRole(def.Fill)
			expect(ThemeConfig.contrast(ThemeConfig.Colors[ink], ThemeConfig.Colors[def.Fill])).toBeGreaterThanOrEqual(
				BODY_CONTRAST
			)
		end
		expect(count).toBe(4)
		for pips = 1, 4 do
			expect(seen[pips] ~= nil).toBe(true)
		end
	end)

	it("give every rank of the ladder a seal", function()
		local tiers: { [string]: boolean } = {}
		for _, tier in ipairs(RankingConfig.Tiers) do
			tiers[tier.Id] = true
			local def = ThemeConfig.Ranks[tier.Id]
			if def == nil then
				error(("the rank %s has no seal"):format(tier.Id))
			end
			for _, role in ipairs({ def.Fill, def.Rim or def.Fill }) do
				if ThemeConfig.Colors[role] == nil then
					error(("the rank %s names %s, which is no colour role"):format(tier.Id, role))
				end
			end
			local ink = ThemeConfig.labelRole(def.Fill)
			expect(ThemeConfig.contrast(ThemeConfig.Colors[ink], ThemeConfig.Colors[def.Fill])).toBeGreaterThanOrEqual(
				BODY_CONTRAST
			)
		end
		for id in pairs(ThemeConfig.Ranks) do
			if not tiers[id] then
				error(("a seal is drawn for %s, which is no rank"):format(id))
			end
		end
	end)
end)

describe("colour-blind players", function()
	it("tell their health from their ink, and Rare from Epic", function()
		local colors = ThemeConfig.Colors
		for _, kind in ipairs({ "Deutan", "Protan" }) do
			local health = redmean(simulate(colors.Health, kind), simulate(colors.Ink, kind))
			if health < 200 then
				error(("%s: health and ink are %.0f apart"):format(kind, health))
			end
			local rarity = redmean(simulate(colors.InfoFill, kind), simulate(colors.Epic, kind))
			if rarity < 100 then
				error(("%s: Rare and Epic are %.0f apart"):format(kind, rarity))
			end
		end
	end)
end)

describe("the pigments the interface copies", function()
	it("are the exact pigments", function()
		local pigments = PigmentConfig.Colors
		local colors = ThemeConfig.Colors
		expect(colors.Danger).toEqual(pigments.Cinnabar)
		expect(colors.Info).toEqual(pigments.Indigo)
		expect(colors.Bronze).toEqual(pigments.Umber)
		expect(ThemeConfig.PigmentOnInk.Cinnabar).toEqual(pigments.Cinnabar)
		expect(ThemeConfig.PigmentOnInk.Verdigris).toEqual(pigments.Verdigris)
		expect(ThemeConfig.PigmentOnInk.Orpiment).toEqual(pigments.Orpiment)
		-- Exact Indigo is 2.15 on ink: its number is the vivid one.
		expect(ThemeConfig.PigmentOnInk.Indigo).toEqual(colors.InfoFill)
		expect(ThemeConfig.PigmentOnInk.Umber).toBeNil()
	end)
end)

describe("no value colour in a fight", function()
	it("is named by any fight surface", function()
		local found: { string } = {}
		for _, path in ipairs(FIGHT_FILES) do
			local code = stripComments(fs.readFile(path))
			for _, pattern in ipairs(VALUE_PATTERNS) do
				if string.find(code, pattern) ~= nil then
					table.insert(found, ("%s matches %s"):format(path, pattern))
				end
			end
			for role in string.gmatch(code, 'Theme%.color%(%s*"(%w+)"') do
				if VALUE_ROLES[role] then
					table.insert(found, ("%s asks for Theme.color(%q)"):format(path, role))
				end
			end
			for lip in string.gmatch(code, 'Theme%.lip%(%s*"(%w+)"') do
				if VALUE_LIPS[lip] then
					table.insert(found, ("%s asks for Theme.lip(%q)"):format(path, lip))
				end
			end
		end
		table.sort(found)
		if #found > 0 then
			error("a fight shows no value colour (docs/ART_BIBLE.md rule 11):\n" .. table.concat(found, "\n"))
		end
	end)
end)

describe("the setting of words", function()
	it("never upper-cases with Luau's ASCII-only upper", function()
		local files: { string } = {}
		for _, root in ipairs(UPPER_ROOTS) do
			collect(root, files)
		end
		local controllers: { string } = {}
		collect("src/client/Controllers", controllers)
		for _, path in ipairs(controllers) do
			for _, prefix in ipairs(UPPER_PREFIXES) do
				if string.sub(path, 1, #prefix) == prefix then
					table.insert(files, path)
				end
			end
		end
		expect(#files).toBeGreaterThan(20)
		local found: { string } = {}
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			if string.find(code, "string%.upper") ~= nil or string.find(code, ":upper%(") ~= nil then
				table.insert(found, path)
			end
		end
		table.sort(found)
		if #found > 0 then
			error("sentence case, not ASCII capitals:\n" .. table.concat(found, "\n"))
		end
	end)
end)

describe("the theme", function()
	it("converts every colour role", function()
		local theme = stripComments(fs.readFile(THEME))
		for role in pairs(ThemeConfig.Colors) do
			local line = ("\t%s = fromRgb(ThemeConfig.Colors.%s),"):format(role, role)
			if string.find(theme, line, 1, true) == nil then
				error(("Theme.Colors has no %s"):format(role))
			end
		end
	end)

	it("builds every gradient from two or three colours and at most five transparencies", function()
		local kinds = { Linear = true, Radial = true, Conical = true }
		for name, def in pairs(ThemeConfig.Gradients) do
			expect(#def.Color).toBeGreaterThanOrEqual(2)
			expect(#def.Color).toBeLessThanOrEqual(3)
			for index, stop in ipairs(def.Color) do
				if stop.Role ~= "Base" and ThemeConfig.Colors[stop.Role] == nil then
					error(("%s names %s, which is no colour role"):format(name, stop.Role))
				end
				if index > 1 and stop.Time <= def.Color[index - 1].Time then
					error(("%s's colours are out of order"):format(name))
				end
			end
			expect(def.Color[1].Time).toBe(0)
			expect(def.Color[#def.Color].Time).toBe(1)
			local transparency = def.Transparency
			if transparency ~= nil then
				expect(#transparency).toBeLessThanOrEqual(5)
				expect(transparency[1][1]).toBe(0)
				expect(transparency[#transparency][1]).toBe(1)
				for index = 2, #transparency do
					expect(transparency[index][1]).toBeGreaterThan(transparency[index - 1][1])
				end
			end
			local kind = def.Kind
			if kind ~= nil and not kinds[kind] then
				error(("%s is a %s gradient, which the engine does not draw"):format(name, kind))
			end
		end
	end)

	it("draws the Result's ring spent past what is left", function()
		local half = ThemeConfig.ringTransparency(0.5)
		expect(#half).toBe(4)
		expect(half[1]).toEqual({ 0, 0 })
		expect(half[2][1]).toBe(0.5)
		expect(half[2][2]).toBe(0)
		expect(half[3][1]).toBeGreaterThan(0.5)
		expect(half[3][2]).toBeGreaterThan(0.5)
		expect(half[4][1]).toBe(1)
		-- Whole and gone are two keypoints each, never a time repeated at an end.
		expect(ThemeConfig.ringTransparency(1)).toEqual({ { 0, 0 }, { 1, 0 } })
		expect(#ThemeConfig.ringTransparency(0)).toBe(2)
		expect(ThemeConfig.ringTransparency(0)[1][2]).toBeGreaterThan(0.5)
		expect(ThemeConfig.ringTransparency(2)).toEqual(ThemeConfig.ringTransparency(1))
		expect(ThemeConfig.ringTransparency(-1)).toEqual(ThemeConfig.ringTransparency(0))
	end)
end)

describe("the sticker", function()
	it("draws every line through Theme.stroke, fixed-size and floored at two pixels", function()
		local theme = stripComments(fs.readFile(THEME))
		local body = string.match(theme, "function Theme%.stroke%((.-)\nend\n")
		assert(body ~= nil, "Theme.stroke is gone: this gate would check nothing")
		expect(string.find(body :: string, "stroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize", 1, true)).never.toBeNil()
		expect(
			string.find(
				body :: string,
				"stroke.Thickness = math.max(thickness, MIN_STROKE_PIXELS / Theme.activeScale())",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(theme, "local MIN_STROKE_PIXELS = 2\n", 1, true)).never.toBeNil()
		local found: { string } = {}
		for _, name in ipairs(STROKED_COMPONENTS) do
			local path = "src/ui/components/" .. name .. ".luau"
			local code = stripComments(fs.readFile(path))
			if
				string.find(code, 'Instance.new("UIStroke")', 1, true) ~= nil
				or string.find(code, "%.Thickness%s*=") ~= nil
			then
				table.insert(found, path)
			end
		end
		if #found > 0 then
			error("a line drawn around Theme.stroke:\n" .. table.concat(found, "\n"))
		end
		local sticker = stripComments(fs.readFile(STICKER))
		expect(select(2, string.gsub(sticker, "Theme%.stroke%(", ""))).toBeGreaterThanOrEqual(2)
	end)

	it("wears its ink outline unless it is a plate (rule 11)", function()
		local sticker = stripComments(fs.readFile(STICKER))
		expect(
			string.find(
				sticker,
				'local outline = if props.Outline ~= nil then props.Outline else kind ~= "Plate"',
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(sticker, 'if outline then\n%s+Theme%.stroke%(face, "Accent"')).never.toBeNil()
	end)

	it("keeps a badge out of red: nothing is wrong, something is owed", function()
		local badge = stripComments(fs.readFile("src/ui/components/Badge.luau"))
		expect(string.find(badge, "Danger")).toBeNil()
		expect(string.find(badge, "Theme.Colors.Primary", 1, true)).never.toBeNil()
	end)
end)

describe("the keycaps", function()
	it("name every rebindable key that is more than a letter, in both languages", function()
		local missing: { string } = {}
		local count = 0
		for key in pairs(InputConfig.AllowedKeyboard) do
			if #key > 3 then
				count += 1
				if not Strings.has("key." .. key) then
					table.insert(missing, key)
				end
			end
		end
		for key in pairs(InputConfig.AllowedGamepad) do
			if string.sub(key, 1, 4) ~= "DPad" then
				count += 1
				if not Strings.has("key." .. key) then
					table.insert(missing, key)
				end
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error("keys a keycap cannot name: " .. table.concat(missing, ", "))
		end
		expect(count).toBeGreaterThanOrEqual(15)
	end)

	it("reads a key's word from Strings, and draws the D-pad as arrows", function()
		local keycap = stripComments(fs.readFile("src/ui/components/Keycap.luau"))
		expect(string.find(keycap, 'return localize.t("key." .. keyName)', 1, true)).never.toBeNil()
		for _, pad in ipairs({ "DPadUp", "DPadRight", "DPadDown", "DPadLeft" }) do
			expect(string.find(keycap, "\t" .. pad .. ' = "', 1, true)).never.toBeNil()
		end
		expect(string.find(keycap, "Theme.Fonts.Symbol", 1, true)).never.toBeNil()
	end)
end)
