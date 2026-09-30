--!strict
-- The colourful interface (D-147) held to its own rules: lips computed from the pigments, chapters that are
-- never red nor ours, rarities and ranks that never rely on colour alone, a cyan and a blue that a
-- colour-blind player still tells apart, and no value colour in a fight. Source-level where it has to
-- be: a HUD file that names the primary yellow is only caught by reading it.
local Engine = require("./engine")
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

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
	"Button",
	"Tabs",
	"ListRow",
	"ProgressBar",
	"Toggle",
	"Slider",
	"ScreenRoot",
	"Panel",
	"ChapterBand",
	"CardContent",
	"Toast",
	"CombatDock",
	"ComboRow",
	"ScoreBand",
	"MetaCluster",
	"Hotbar",
	"HudPlate",
	"Banner",
	"TouchButton",
	"DamageNumber",
	"LockMarker",
	"SpectatePlate",
	"CircleButton",
}
local BODY_CONTRAST = 4.5

-- Fight surfaces: what is on screen during a round. Each one is added here in the commit that makes it
-- comply. HudController joined when the roster that named Success left it for ScoreBand, which joined when
-- that roster turned cyan (spec slice C). MetaCluster is the one HUD piece that may show value colours: it
-- is hub-only, and HudController hides it in a fight (below).
local FIGHT_FILES = {
	"src/client/Controllers/BossController.luau",
	"src/client/Controllers/Feel.luau",
	"src/client/Controllers/LockOnController.luau",
	"src/client/Controllers/SpectateController.luau",
	"src/ui/components/DamageNumber.luau",
	"src/ui/components/LockMarker.luau",
	"src/ui/components/TouchButton.luau",
	"src/client/Controllers/HudController.luau",
	"src/ui/components/CombatDock.luau",
	"src/ui/components/ComboRow.luau",
	"src/ui/components/Hotbar.luau",
	"src/ui/components/ScoreBand.luau",
	"src/ui/components/HudPlate.luau",
	"src/client/Controllers/TravelController.luau",
	"src/ui/components/Banner.luau",
	"src/ui/components/SpectatePlate.luau",
	"src/ui/components/CircleButton.luau",
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
		-- The top of the ladder is full gold leaf: rimmed in gold and shimmering, as the board's Codex seal.
		local top = ThemeConfig.Ranks[RankingConfig.Tiers[#RankingConfig.Tiers].Id]
		expect(top.Fill).toBe("Primary")
		expect(top.Rim).toBe("Primary")
		expect(top.Shimmer).toBe(true)
		-- And a seal is a seal: no rank carries a flag nothing reads.
		for id, def in pairs(ThemeConfig.Ranks) do
			if (def :: any).Seal ~= nil then
				error(id .. " still says Seal, which no seal reads")
			end
		end
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Theme = world.require("src/ui/Theme")
		local codex = Theme.rank(RankingConfig.Tiers[#RankingConfig.Tiers].Id)
		expect(codex.Rim).toBe(Theme.Colors.Primary)
		expect(codex.Shimmer).toBe(true)
		expect(codex.Seal).toBeNil()
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

	it("reaches the toasts too: what a toast draws in a fight is no value colour", function()
		-- Toast.luau draws the hub's toasts as well, so it cannot join FIGHT_FILES: its fight branch is scanned.
		local toast = stripComments(fs.readFile("src/ui/components/Toast.luau"))
		local branch = string.match(toast, "local FIGHT_FILLS: { %[string%]: Color3 } = (%b{})")
		assert(branch ~= nil, "Toast.luau no longer has a fight branch: this gate would check nothing")
		for _, pattern in ipairs(VALUE_PATTERNS) do
			if string.find(branch :: string, pattern) ~= nil then
				error("a toast in a fight shows a value colour: " .. pattern)
			end
		end
		expect(string.find(branch :: string, "Success = ", 1, true)).never.toBeNil()
		local hud = stripComments(fs.readFile("src/client/Controllers/HudController.luau"))
		expect(string.find(hud, "toast:SetFight(fighting)", 1, true)).never.toBeNil()
	end)

	it("is kept out of it: the hub's meta cluster hides in a match and in an arena", function()
		local hud = stripComments(fs.readFile("src/client/Controllers/HudController.luau"))
		expect(string.find(hud, "metaCluster:SetVisible(not (inMatch or inArena))", 1, true)).never.toBeNil()
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
		expect(string.find(body :: string, "stroke.Thickness = Theme.strokeThickness(thickness)", 1, true)).never.toBeNil()
		local floor = string.match(theme, "function Theme%.strokeThickness%((.-)\nend\n")
		assert(floor ~= nil, "Theme.strokeThickness is gone: this gate would check nothing")
		expect(
			string.find(floor :: string, "return math.max(thickness, MIN_STROKE_PIXELS / Theme.activeScale())", 1, true)
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

	it("shows a pressable's whole lip, rimmed in ink from outside, and chalk under a disabled one", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Sticker = world.require("src/ui/components/Sticker")
		local Theme = world.require("src/ui/Theme")
		local Button = world.require("src/ui/components/Button")
		local function base(object: any): (any, any)
			local frame = object:FindFirstChild("Base")
			assert(frame ~= nil, "the sticker has no base: this gate would check nothing")
			return frame, frame:FindFirstChildOfClass("UIStroke")
		end
		-- The board's `0 5px 0 0 lip, 0 5px 0 3px ink`: the ink lies outside the lip, not over it.
		local lip = Theme.lip("Primary")
		local pressable =
			Sticker.new({ Kind = "Pressable", Fill = Theme.Colors.Primary, Lip = lip, Parent = world.playerGui })
		local frame, stroke = base(pressable.Instance)
		expect(stroke.BorderStrokePosition.Name).toBe("Outer")
		expect(stroke.Color).toBe(Theme.Colors.Accent)
		expect(frame.BackgroundColor3).toBe(lip)
		-- A card's shadow is a plain ink one, and keeps its outline inside it.
		local card = Sticker.new({ Kind = "Card", Fill = Theme.Colors.PanelRaised, Parent = world.playerGui })
		local cardBase, cardStroke = base(card.Instance)
		expect(cardStroke.BorderStrokePosition.Name).toBe("Inner")
		expect(cardBase.BackgroundColor3).toBe(Theme.Colors.Plate)
		-- Disabled, it sits on chalk; awake, on its own lip again.
		pressable:SetState("Disabled")
		expect(frame.BackgroundColor3).toBe(Theme.Colors.Chalk)
		pressable:SetState("Hover")
		expect(frame.BackgroundColor3).toBe(lip)
		pressable:SetState("Disabled")
		pressable:SetState("Idle")
		expect(frame.BackgroundColor3).toBe(lip)
		-- Through a button: disabled, woken, then given another face.
		local button = Button.new({ Text = "Go", Variant = "Primary", Disabled = true, Parent = world.playerGui })
		expect((base(button.Instance)).BackgroundColor3).toBe(Theme.Colors.Chalk)
		button:SetDisabled(false)
		expect((base(button.Instance)).BackgroundColor3).toBe(lip)
		button:SetDisabled(true)
		button:SetVariant("Secondary")
		expect((base(button.Instance)).BackgroundColor3).toBe(Theme.Colors.Chalk)
		button:SetDisabled(false)
		expect((base(button.Instance)).BackgroundColor3).toBe(Theme.lip("Secondary"))
	end)

	it("keeps a pressable's outer rim whole in a frame that clips it: the ghosts' keys", function()
		-- A ghost's key opens in a slot that clips; the cap's lip is rimmed from outside, so the cap stands that
		-- rim above the slot's foot -- the rim as drawn, floored at two pixels on a small screen.
		for _, phone in ipairs({ false, true }) do
			local world = Engine.world({ Stubs = Engine.interfaceStubs() })
			if phone then
				Engine.phone(world, 667, 375)
			end
			local ComboRow = world.require("src/ui/components/ComboRow")
			local gui = Engine.instance("ScreenGui", world.playerGui)
			local row = ComboRow.new({
				Parent = gui,
				Localize = {
					t = function(key: string): string
						return key
					end,
				},
			})
			row:ShowGhosts({ "Cinnabar" }, { Device = "Keyboard", Keys = { Cinnabar = "J" } })
			local slot = row.Instance:FindFirstChild("Key1", true)
			assert(slot ~= nil, "no ghost key was drawn: this gate would check nothing")
			expect(slot.ClipsDescendants).toBe(true)
			local cap = slot:GetChildren()[1]
			local base = cap:FindFirstChild("Base")
			assert(base ~= nil, "the ghost key has no lip: this gate would check nothing")
			local rim = base:FindFirstChildOfClass("UIStroke")
			expect(rim.BorderStrokePosition.Name).toBe("Outer")
			expect(cap.AnchorPoint.Y).toBe(1)
			expect(cap.Position.Y.Scale).toBe(1)
			expect(cap.Position.Y.Offset + rim.Thickness).toBeLessThanOrEqual(0)
			if phone then
				expect(rim.Thickness).toBeGreaterThan(2)
			end
		end
	end)

	it("catches its gloss inside the ink, and carries it where the face goes", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Button = world.require("src/ui/components/Button")
		local Theme = world.require("src/ui/Theme")
		local stroke = Theme.Sizes.Stroke
		local function gloss(button: any): any
			local found = button.Instance:FindFirstChild("Gloss")
			assert(found ~= nil, "the button has no gloss: this gate would check nothing")
			return found
		end
		-- The board measures its insets from inside the border, and its height as a share of what the border
		-- encloses: the face, less the lip under it and the outline above and below.
		local function enclosed(share: number, elevation: number): number
			return -math.round(share * (elevation + stroke * 2))
		end
		-- A pill's: 10 in from its ends and 3 under its outline, both inside the ink, over 38 %, a pill itself.
		local primary = Button.new({ Text = "Go", Variant = "Primary", Parent = world.playerGui })
		local light = gloss(primary)
		expect(light.Position.X.Offset).toBe(stroke + 10)
		expect(light.Position.Y.Offset).toBe(stroke + 3)
		expect(light.Size.X.Scale).toBe(1)
		expect(light.Size.X.Offset).toBe(-(stroke + 10) * 2)
		expect(light.Size.Y.Scale).toBeCloseTo(0.38, 5)
		expect(light.Size.Y.Offset).toBe(enclosed(0.38, 5))
		expect(light:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
		-- A tile's (the board's `.4cqw .8cqw`, at the tile's 10 units a cqw): 8 in from its sides and 4 under its
		-- outline, inside the ink, over 36 %, under a corner 4 tighter than the tile's.
		local tile = Button.new({ Text = "Shop", Variant = "Tile", Chapter = "Shop", Parent = world.playerGui })
		local tileLight = gloss(tile)
		expect(tileLight.Position.X.Offset).toBe(stroke + 8)
		expect(tileLight.Position.Y.Offset).toBe(stroke + 4)
		expect(tileLight.Size.X.Offset).toBe(-(stroke + 8) * 2)
		expect(tileLight.Size.Y.Scale).toBeCloseTo(0.36, 5)
		expect(tileLight.Size.Y.Offset).toBe(enclosed(0.36, 6))
		expect(tileLight:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(Theme.Sizes.CornerTile - 4)
		-- It rides a press and comes back to rest inside the ink.
		local face = primary.Instance:FindFirstChild("Face")
		primary.Instance.MouseButton1Down:Fire()
		world:advance(1)
		expect(light.Position.Y.Offset - face.Position.Y.Offset).toBe(stroke + 3)
		expect(face.Position.Y.Offset).toBeGreaterThan(0)
		primary.Instance.MouseButton1Up:Fire()
		world:advance(2)
		expect(light.Position.X.Offset).toBeCloseTo(stroke + 10, 3)
		expect(light.Position.Y.Offset).toBeCloseTo(stroke + 3, 3)
		-- Half the sheet at its top, fading out, as the board's `opacity: .5`.
		expect(ThemeConfig.Gradients.Gloss.Transparency).toEqual({ { 0, 0.5 }, { 1, 1 } })
	end)

	it("keeps red in a menu for what is refused or lost, and a badge in the gold, the sheet on a gold face", function()
		-- The palette's "Danger ... rien d'autre" speaks of the fight (D-180): out of it, red says a refusal, a
		-- destructive confirm, a rating that fell or a balance that falls short, and no screen says anything
		-- else in it.
		local screens: { string } = {}
		collect("src/ui/screens", screens)
		local red: { string } = {}
		for _, path in ipairs(screens) do
			local code = stripComments(fs.readFile(path))
			if
				string.find(code, "Colors.Danger", 1, true) ~= nil
				or string.find(code, '"Danger"', 1, true) ~= nil
				or string.find(code, 'lip("Danger")', 1, true) ~= nil
			then
				table.insert(red, path)
			end
		end
		table.sort(red)
		expect(red).toEqual({ "src/ui/screens/SettingsBindings.luau", "src/ui/screens/shop/Purchase.luau" })
		local function has(path: string, plain: string): boolean
			return string.find(stripComments(fs.readFile(path)), plain, 1, true) ~= nil
		end
		expect(
			has("src/ui/screens/SettingsBindings.luau", 'Confirm = { Text = t("common.reset"), Variant = "Danger" },')
		).toBe(true)
		expect(
			has(
				"src/ui/screens/shop/Purchase.luau",
				"line.TextColor3 = if short then Theme.Colors.Danger else Theme.Colors.Text"
			)
		).toBe(true)
		expect(has("src/ui/components/Toast.luau", "Error = Theme.Colors.DangerFill,")).toBe(true)
		expect(
			has(
				"src/ui/components/ResultCard.luau",
				"ratingLine.TextColor3 = if delta >= 0 then Theme.Colors.Success else Theme.Colors.Danger"
			)
		).toBe(true)
		-- The board paints its tile badges red, against its own palette: a badge keeps the gold, and on a gold
		-- face the sheet, whatever shape it takes.
		local button = stripComments(fs.readFile("src/ui/components/Button.luau"))
		expect(
			select(
				2,
				string.gsub(
					button,
					"if look%.Face == Theme%.Colors%.Primary then Theme%.Colors%.PanelRaised else nil",
					""
				)
			)
		).toBe(2)
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

	it("sets a cap's character in the number face, its word in the label face, an arrow in the roman", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Keycap = world.require("src/ui/components/Keycap")
		local Theme = world.require("src/ui/Theme")
		local localize = {
			t = function(key: string): string
				return Strings.t(key, nil, "fr")
			end,
		}
		local faces = {
			DPadUp = Theme.Fonts.Symbol,
			Q = Theme.Fonts.Numeric,
			One = Theme.Fonts.Numeric,
			F3 = Theme.Fonts.Numeric,
			LeftShift = Theme.Fonts.Label,
			MouseButton1 = Theme.Fonts.Label,
			ButtonSelect = Theme.Fonts.Label,
		}
		for key, face in pairs(faces) do
			local cap = Keycap.new({ Key = key, Device = "Keyboard", Localize = localize })
			local label = cap.Instance:FindFirstChild("Key", true)
			local measure = cap.Instance:FindFirstChild("Measure")
			if label.FontFace.Family ~= face.Family or label.FontFace.Weight ~= face.Weight then
				error(("the cap of %s (%q) is set in %s"):format(key, label.Text, label.FontFace.Family))
			end
			-- The width is measured in the face the word is drawn in.
			expect(measure.FontFace.Family).toBe(face.Family)
			expect(measure.FontFace.Weight).toBe(face.Weight)
		end
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

describe("the restyled controls", function()
	local function source(name: string): string
		return stripComments(fs.readFile("src/ui/components/" .. name .. ".luau"))
	end

	-- The body of the first function in `code` that starts with `head`, up to its closing `end` one tab in
	-- (`end)` for a handler, `end` for a local function).
	local function handler(code: string, head: string): string
		local start = string.find(code, head, 1, true)
		assert(start ~= nil, "no " .. head .. ": this gate would check nothing")
		local stop = string.find(code, "\n\tend[%)\n]", start :: number)
		assert(stop ~= nil, "no end to " .. head)
		return string.sub(code, start :: number, stop :: number)
	end

	it("never cut a button's word, and never make a button narrower than a thumb", function()
		local button = source("Button")
		expect(string.find(button, "label.TextTruncate = Enum.TextTruncate.None", 1, true)).never.toBeNil()
		expect(string.find(button, "TextTruncate.AtEnd", 1, true)).toBeNil()
		expect(string.find(button, "button.AutomaticSize = Enum.AutomaticSize.X", 1, true)).never.toBeNil()
		local minimum = tonumber(string.match(button, "local MIN_WIDTH = (%d+)"))
		local wide = tonumber(string.match(button, "local WIDE_WIDTH = (%d+)"))
		assert(minimum ~= nil and wide ~= nil, "Button no longer names its minimum widths")
		expect(minimum :: number).toBeGreaterThanOrEqual(140)
		expect(wide :: number).toBeGreaterThanOrEqual(220)
		expect(string.find(button, "measure.Size = UDim2.new(0, minWidth, 1, 0)", 1, true)).never.toBeNil()
		-- The fight's compact pill drops the 140 for its snug word, never below a thumb (D-179).
		expect(
			string.find(
				button,
				"local minWidth = if props.Wide then WIDE_WIDTH elseif compact then Theme.MinTouchTarget else MIN_WIDTH",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(button, "Theme.minPixelSize(button, Theme.MinTouchTarget)", 1, true)).never.toBeNil()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Button = world.require("src/ui/components/Button")
		local Theme = world.require("src/ui/Theme")
		local regular = Button.new({ Text = "Menu", Parent = world.playerGui })
		local pill = Button.new({ Text = "Menu", Compact = true, Parent = world.playerGui })
		expect(regular.Instance:FindFirstChild("Measure").Size.X.Offset).toBeGreaterThanOrEqual(140)
		expect(pill.Instance:FindFirstChild("Measure").Size.X.Offset).toBe(Theme.MinTouchTarget)
		expect(pill.Instance:FindFirstChildOfClass("UISizeConstraint").MinSize.X).toBeGreaterThanOrEqual(
			Theme.MinTouchTarget
		)
		expect(pill.Instance.Size.Y.Offset).toBe(Theme.MinTouchTarget)
		expect(regular.Instance.Size.Y.Offset).toBe(Theme.Sizes.ButtonHeight)
		local measure = pill.Instance:FindFirstChild("Measure")
		local padding = measure:FindFirstChildOfClass("UIPadding")
		expect(padding.PaddingLeft.Offset).toBe(13)
		expect(padding.PaddingRight.Offset).toBe(13)
		expect(measure.TextSize).toBe(14)
		expect(measure.FontFace.Weight).toBe(Theme.Fonts.Label.Weight)
		local word = pill.Instance:FindFirstChild("Label", true)
		expect(word.TextSize).toBe(measure.TextSize)
		expect(word.FontFace.Weight).toBe(measure.FontFace.Weight)
	end)

	it("lift a hovered button and sink a pressed one, and never grow or shrink one", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Button = world.require("src/ui/components/Button")
		for _, variant in ipairs({ "Primary", "Secondary", "Tile" }) do
			local button =
				Button.new({ Text = "Go", Variant = variant :: any, Chapter = "Shop", Parent = world.playerGui })
			local instance = button.Instance
			local face = instance:FindFirstChild("Face")
			local scale = instance:FindFirstChildOfClass("UIScale")
			local function scaled(): number
				return if scale ~= nil then scale.Scale else 1
			end
			instance.MouseEnter:Fire()
			world:advance(1)
			expect(face.Position.Y.Offset).toBeLessThan(0)
			expect(scaled()).toBe(1)
			instance.MouseButton1Down:Fire()
			world:advance(1)
			expect(face.Position.Y.Offset).toBeGreaterThan(0)
			expect(scaled()).toBe(1)
			instance.MouseButton1Up:Fire()
			instance.MouseLeave:Fire()
			instance.SelectionGained:Fire()
			world:advance(1)
			-- A gamepad's focus is its ring, not a bigger button.
			expect(scaled()).toBe(1)
			expect(face.Position.Y.Offset).toBeCloseTo(0, 3)
		end
		local code = source("Button")
		for _, name in ipairs({ "HOVER_SCALE", "PRESSED_SCALE", "FOCUS_SCALE" }) do
			expect(string.find(code, name, 1, true)).toBeNil()
		end
	end)

	it("click only when they act: a disabled or pending button is silent", function()
		local activated = handler(source("Button"), "trove:Connect(button.Activated, function()")
		local guard = string.find(activated, "if disabled or pending then%s+return%s+end")
		local click = string.find(activated, 'UiSound.play("UiClick")', 1, true)
		assert(guard ~= nil and click ~= nil, "the button no longer guards and plays its click")
		expect(guard :: number).toBeLessThan(click :: number)
		expect(string.find(source("Button"), "task.delay(Theme.Timing.PendingTimeoutSeconds", 1, true)).never.toBeNil()
	end)

	it("give the gamepad the double ring on every control", function()
		for _, name in ipairs({ "Button", "Tabs", "Toggle", "Slider" }) do
			local code = source(name)
			if
				string.find(code, "Theme.focusRing(", 1, true) == nil
				or string.find(code, "makeSelectionImage", 1, true) ~= nil
			then
				error(name .. " draws its own focus instead of Theme.focusRing")
			end
		end
		-- The board's focus: outward from the edge, ink to 5, the yellow from 5 to 8, ink again to 9.
		local theme = stripComments(fs.readFile(THEME))
		expect(string.find(theme, "local FOCUS_HALO = 9\n", 1, true)).never.toBeNil()
		expect(string.find(theme, "local FOCUS_RING_OFFSET = 5\n", 1, true)).never.toBeNil()
		expect(string.find(theme, 'ring("Halo", 0, "Accent", FOCUS_HALO, 1)', 1, true)).never.toBeNil()
		expect(
			string.find(
				theme,
				'ring("Ring", FOCUS_RING_OFFSET * 2, if kind == "Fight" then "PanelRaised" else "Primary", Theme.Sizes.Stroke, 2)',
				1,
				true
			)
		).never.toBeNil()
		-- Run: each ring's frame, its line, its colour for each kind, and its corner concentric with the target.
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Theme = world.require("src/ui/Theme")
		for _, case in ipairs({
			{ Kind = nil, Ring = Theme.Colors.Primary },
			{ Kind = "Menu", Ring = Theme.Colors.Primary },
			{ Kind = "Fight", Ring = Theme.Colors.PanelRaised },
		}) do
			for _, corner in ipairs({ Theme.Pill, roblox.UDim.new(0, Theme.Sizes.CornerTile) }) do
				local focus = Theme.focusRing(case.Kind :: any, corner)
				local halo, ring = focus:FindFirstChild("Halo"), focus:FindFirstChild("Ring")
				assert(halo ~= nil and ring ~= nil, "the focus has no halo or no ring: this gate would check nothing")
				expect(#focus:GetChildren()).toBe(2)
				expect(focus.Size).toBe(roblox.UDim2.fromScale(1, 1))
				expect(halo.Size).toBe(roblox.UDim2.fromScale(1, 1))
				expect(ring.Size).toBe(roblox.UDim2.new(1, 10, 1, 10))
				expect(ring.ZIndex).toBeGreaterThan(halo.ZIndex)
				local haloLine = halo:FindFirstChildOfClass("UIStroke")
				local ringLine = ring:FindFirstChildOfClass("UIStroke")
				expect(haloLine.BorderStrokePosition.Name).toBe("Outer")
				expect(ringLine.BorderStrokePosition.Name).toBe("Outer")
				expect(haloLine.Thickness).toBe(9)
				expect(ringLine.Thickness).toBe(Theme.Sizes.Stroke)
				expect(haloLine.Color).toBe(Theme.Colors.Accent)
				expect(ringLine.Color).toBe(case.Ring)
				local haloCorner = halo:FindFirstChildOfClass("UICorner").CornerRadius
				local ringCorner = ring:FindFirstChildOfClass("UICorner").CornerRadius
				expect(haloCorner).toBe(corner)
				expect(ringCorner).toBe(if corner.Scale > 0 then corner else roblox.UDim.new(0, corner.Offset + 5))
			end
		end
	end)

	it("write a chapter's button in the ink where it reads, and in the sheet on purple and on ink", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Button = world.require("src/ui/components/Button")
		local Theme = world.require("src/ui/Theme")
		local checked = 0
		for screen, role in pairs(ThemeConfig.Chapters) do
			for _, variant in ipairs({ "Tile", "Owner" }) do
				local button = Button.new({
					Text = "Go",
					Variant = variant :: any,
					Chapter = screen,
					Icon = "Coin",
					Parent = world.playerGui,
				})
				local label = button.Instance:FindFirstChild("Label", true)
				local fill = ThemeConfig.Colors[role]
				local dark = ThemeConfig.inkOn(fill) ~= ThemeConfig.Colors.Text
				local expected = if dark then Theme.Colors.PanelRaised else Theme.Colors.Text
				if label.TextColor3 ~= expected then
					error(("a %s on %s's %s writes in the wrong ink"):format(variant, screen, role))
				end
				local ratio = Theme.contrast(label.TextColor3, Theme.color(role))
				if ratio < BODY_CONTRAST then
					error(("a %s on %s's %s reads at %.2f"):format(variant, screen, role, ratio))
				end
				checked += if dark then 1 else 0
			end
		end
		-- The pass's purple and the ink of the Menu, the Loadout, the Leaderboard and the Settings, at least.
		expect(checked).toBeGreaterThanOrEqual(10)
	end)

	it("paint the invite, and only the invite, in the cyan of us, and mark the settings with three lines", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Button = world.require("src/ui/components/Button")
		local Theme = world.require("src/ui/Theme")
		local button = Button.new({ Text = Theme.Glyphs.Plus, Variant = "Ally", Parent = world.playerGui })
		local face = button.Instance:FindFirstChild("Face")
		local base = button.Instance:FindFirstChild("Base")
		expect(face.BackgroundColor3).toBe(Theme.Colors.Ally)
		expect(base.BackgroundColor3).toBe(Theme.lip("Secondary"))
		expect(button.Instance:FindFirstChild("Gloss")).toBeNil()
		local word = button.Instance:FindFirstChild("Label", true)
		expect(word.TextColor3).toBe(Theme.Colors.Text)
		expect(Theme.contrast(word.TextColor3, Theme.Colors.Ally)).toBeGreaterThanOrEqual(BODY_CONTRAST)
		-- The Menu's invite, a "+" on it: bring an ally (D-176).
		local menu = stripComments(fs.readFile("src/ui/screens/MenuScreen.luau"))
		expect(string.find(menu, 'iconButton("Invite", Theme.Glyphs.Plus, nil, "Ally", 7, function()', 1, true)).never.toBeNil()
		-- And no other button: the cyan stays the fight's "us". No screen names it but the Menu's invite, and
		-- nothing asks a Button for it by its Variant.
		local files: { string } = {}
		collect("src", files)
		local users: { string } = {}
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			local screen = string.sub(path, 1, #"src/ui/screens/") == "src/ui/screens/"
			if
				string.find(code, 'Variant = "Ally"', 1, true) ~= nil
				or (screen and string.find(code, '"Ally"', 1, true) ~= nil)
			then
				table.insert(users, path)
			end
		end
		expect(users).toEqual({ "src/ui/screens/MenuScreen.luau" })
		expect(select(2, string.gsub(menu, '"Ally"', ""))).toBe(1)
		-- The board's settings are its ≡, the Burger, on the sheet beside it.
		expect(string.find(menu, 'iconButton("Settings", "", "Burger", "Secondary", 6, function()', 1, true)).never.toBeNil()
		for screen, role in pairs(ThemeConfig.Chapters) do
			if role == "Ally" or role == "Health" then
				error(screen .. "'s chapter is the cyan of us")
			end
		end
	end)

	it("put the Folios on an ink pill, its gold coin drawn in it, and the way to more at its end", function()
		local clicks: { string } = {}
		local stubs = Engine.interfaceStubs()
		stubs["src/ui/UiSound"] = {
			play = function(id: string)
				table.insert(clicks, id)
			end,
		}
		local world = Engine.world({ Stubs = stubs })
		local FoliosPill = world.require("src/ui/components/FoliosPill")
		local Theme = world.require("src/ui/Theme")
		local asked = 0
		local pill = FoliosPill.new({
			Height = 44,
			Parent = world.playerGui,
			OnMore = function()
				asked += 1
			end,
		})
		pill:Set(2480, false)
		local root = pill.Instance
		-- The board's `.pill`: ink, its count the sheet in the number face.
		expect(root.BackgroundColor3).toBe(Theme.Colors.Plate)
		local count = root:FindFirstChild("Count")
		expect(count.Text).toBe("2480")
		expect(count.TextColor3).toBe(Theme.Colors.PanelRaised)
		expect(count.FontFace.Family).toBe(Theme.Fonts.Numeric.Family)
		expect(Theme.contrast(count.TextColor3, root.BackgroundColor3)).toBeGreaterThanOrEqual(BODY_CONTRAST)
		-- Its `.coin`: gold in a sheet rim, a ring of the gold's lip inside the rim, and no letter on it.
		local coin = root:FindFirstChild("Coin")
		expect(coin.BackgroundColor3).toBe(Theme.Colors.Primary)
		expect(coin:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.PanelRaised)
		local ring = coin:FindFirstChild("Ring")
		expect(ring:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.lip("Primary"))
		for _, part in ipairs(coin:GetDescendants()) do
			if part:IsA("TextLabel") or part:IsA("ImageLabel") then
				error("the coin carries " .. part.Name)
			end
		end
		-- Its `.plus`: a disc of the sheet at the pill's end, a "+" of ink, and the whole pill a button taking it.
		local more = root:FindFirstChild("More")
		expect(more.BackgroundColor3).toBe(Theme.Colors.PanelRaised)
		expect(more.Text).toBe(Theme.Glyphs.Plus)
		expect(more.TextColor3).toBe(Theme.Colors.Text)
		expect(more.LayoutOrder).toBeGreaterThan(count.LayoutOrder)
		expect(root.ClassName).toBe("TextButton")
		expect(root.Selectable).toBe(true)
		expect(root.SelectionImageObject).never.toBeNil()
		expect(root:FindFirstChildOfClass("UISizeConstraint").MinSize.Y).toBeGreaterThanOrEqual(Theme.MinTouchTarget)
		root.Activated:Fire()
		expect(asked).toBe(1)
		expect(clicks).toEqual({ "UiClick" })
		-- With nowhere to go, it is only read: a frame, no "+".
		local plain = FoliosPill.new({ Parent = world.playerGui })
		expect(plain.Instance.ClassName).toBe("Frame")
		expect(plain.Instance:FindFirstChild("More")).toBeNil()
		-- The Menu's pill takes the player to the Shop's Folios; no second "+" stands beside it.
		local menu = stripComments(fs.readFile("src/ui/screens/MenuScreen.luau"))
		local call = string.match(menu, "local pill = FoliosPill%.new(%b())")
		assert(call ~= nil, "the Menu shows no Folios pill")
		expect(string.find(call :: string, 'OnMore = function%(%)%s+navigate%("Shop", { Tab = "Folios" }%)%s+end')).never.toBeNil()
		expect(select(2, string.gsub(menu, 'Tab = "Folios"', ""))).toBe(1)
	end)

	it("write the selected tab in an ink that reads on its thumb, whatever the chapter or the pigment", function()
		local tabs = source("Tabs")
		expect(string.find(tabs, "return if band == Theme.Colors.Plate then Theme.Colors.Primary else band", 1, true)).never.toBeNil()
		expect(string.find(tabs, "label.TextColor3 = Theme.inkOn(fill)", 1, true)).never.toBeNil()
		-- Bold at 20 is large text: the floor on a thumb is 3.
		expect(string.find(tabs, "label.TextSize = Theme.Sizes.TextButton", 1, true)).never.toBeNil()
		local fills: { { number } } = {}
		for _, role in pairs(ThemeConfig.Chapters) do
			table.insert(fills, if role == "Plate" then ThemeConfig.Colors.Primary else ThemeConfig.Colors[role])
		end
		for _, id in ipairs(PigmentConfig.Order) do
			table.insert(fills, PigmentConfig.Colors[id])
		end
		for _, fill in ipairs(fills) do
			local ratio = ThemeConfig.contrast(ThemeConfig.inkOn(fill), fill)
			if ratio < 3 then
				error(("a tab on %d,%d,%d reads at %.2f"):format(fill[1], fill[2], fill[3], ratio))
			end
		end
	end)

	it("write a bar's number in the sheet on an ink stroke, with no halo", function()
		local bar = source("ProgressBar")
		expect(string.find(bar, "label.TextColor3 = Theme.Colors.PanelRaised", 1, true)).never.toBeNil()
		expect(string.find(bar, 'Theme.stroke(label, "Outline", LABEL_STROKE, "Contextual")', 1, true)).never.toBeNil()
		expect(string.find(bar, "TextStrokeTransparency", 1, true)).toBeNil()
		expect(ThemeConfig.contrast(ThemeConfig.Colors.PanelRaised, ThemeConfig.Colors.Outline)).toBeGreaterThanOrEqual(
			4.5
		)
	end)

	it("keep every bar flat, and ring the well of one on a plate in the sheet", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local ProgressBar = world.require("src/ui/components/ProgressBar")
		local Theme = world.require("src/ui/Theme")
		local function ring(bar: any): any
			local track = bar.Instance:FindFirstChild("Track")
			assert(track ~= nil, "the bar has no track: this gate would check nothing")
			return track:FindFirstChildOfClass("UIStroke")
		end
		-- The board's `.bar i` are flat everywhere: the Menu's XP, the pass, the quests, the dock, the boss.
		for _, props in ipairs({
			{ Color = Theme.Colors.Primary, Progress = 0.6 },
			{ Color = Theme.Colors.Health, Ghost = Theme.Colors.Danger, OnPlate = true, Progress = 0.7 },
			{ Color = Theme.Colors.Ink, OnPlate = true, Ticks = { 0.25 }, Progress = 0.4 },
		}) do
			local bar = ProgressBar.new(props :: any)
			bar.Instance.Parent = world.playerGui
			bar:SetLow(true)
			bar:Gain(5)
			for _, part in ipairs(bar.Instance:GetDescendants()) do
				if part.Name == "Gloss" or part.ClassName == "UIGradient" then
					error("a bar catches light: " .. part:GetFullName())
				end
			end
			-- On a plate the ink border would vanish and the empty well read at 1.23: its ring is the sheet (D-150).
			local edge = ring(bar)
			expect(edge.Color).toBe(if props.OnPlate then Theme.Colors.PanelRaised else Theme.Colors.Accent)
		end
	end)

	it("run every fill in a track it stands out from", function()
		-- The inkwell for the vivid fills; the sheet for an ink one, which would vanish in the well.
		local bar = source("ProgressBar")
		expect(string.find(bar, "if Theme.contrast(fill, Theme.Colors.Well) >= GRAPHIC_CONTRAST then", 1, true)).never.toBeNil()
		expect(string.find(bar, "local GRAPHIC_CONTRAST = 3\n", 1, true)).never.toBeNil()
		expect(select(2, string.gsub(bar, "track%.BackgroundColor3 = trackFor%(", ""))).toBe(2)
		local colors = ThemeConfig.Colors
		expect(ThemeConfig.contrast(colors.Accent, colors.Well)).toBeLessThan(3)
		expect(ThemeConfig.contrast(colors.Accent, colors.PanelRaised)).toBeGreaterThanOrEqual(3)
	end)

	it("keep a row's title the full height a caller's own frame is sized to, unless a line goes under it", function()
		local row = source("ListRow")
		expect(
			string.find(
				row,
				"left.Frame.Size = if props.Subtitle ~= nil%s+then UDim2.new%(1, 0, 0, Theme.Sizes.TextButton %+ 6%)%s+else UDim2.fromScale%(1, 1%)"
			)
		).never.toBeNil()
	end)

	it("say low health three ways: red, hatching and a pulse", function()
		local low = handler(source("ProgressBar"), "local function setLow(")
		expect(string.find(low, "fill.BackgroundColor3 = Theme.Colors.DangerFill", 1, true)).never.toBeNil()
		expect(string.find(low, "hatch.Visible = next", 1, true)).never.toBeNil()
		expect(string.find(low, "Motion%.loop%(%s*fill,")).never.toBeNil()
	end)

	it("switch a toggle with a word that reads on its pill", function()
		local toggle = source("Toggle")
		expect(string.find(toggle, "if value then Theme.Colors.SuccessFill else Theme.Colors.Chalk", 1, true)).never.toBeNil()
		expect(string.find(toggle, "if value then Theme.Colors.Text else Theme.Colors.TextMuted", 1, true)).never.toBeNil()
		local colors = ThemeConfig.Colors
		expect(ThemeConfig.contrast(colors.Text, colors.SuccessFill)).toBeGreaterThanOrEqual(4.5)
		expect(ThemeConfig.contrast(colors.TextMuted, colors.Chalk)).toBeGreaterThanOrEqual(4.5)
	end)

	it("nudge a slider by a twentieth on the D-pad", function()
		expect(string.find(source("Slider"), "local GAMEPAD_STEPS = 20%s")).never.toBeNil()
	end)

	it("breathe what idles on one shared loop", function()
		for _, name in ipairs({ "Badge", "ListRow" }) do
			local code = source(name)
			if
				string.find(code, "Breath.join(", 1, true) == nil
				or string.find(code, "Motion.loop(", 1, true) ~= nil
			then
				error(name .. " breathes on a loop of its own")
			end
		end
		local breath = stripComments(fs.readFile("src/ui/Breath.luau"))
		expect(select(2, string.gsub(breath, "Motion%.loop%(", ""))).toBe(1)
	end)
end)
