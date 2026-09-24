--!strict
-- What a player buys must be what a player sees. Until D-109 not one of the forty cosmetics was drawn:
-- CosmeticService published what each character wore and no client ever read it, the kill effects were
-- never sent, and the skins were promised to "travel with the packet" by a comment and by nothing else.
-- The catalogue itself broke the art bible -- a violet aura, a blue Brand -- so it was redrawn in the
-- page's inks before it was wired (CosmeticConfig's header says why each rule applies).
--
-- This file holds the catalogue to the bible and to its renderers, and the renderers to the catalogue.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local Strings = require("../src/shared/Strings")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PAGE = WorldConfig.Colors.Page
local INK = WorldConfig.Colors.Ink

-- The redmean distance tests/Config.spec.luau uses for the pigments, for the same question.
local function distance(a: { number }, b: { number }): number
	local rmean = (a[1] + b[1]) / 2
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt((2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db)
end

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, value in ipairs(list) do
		set[value] = true
	end
	return set
end

local function itemsIn(slot: string): { CosmeticConfig.CosmeticDef }
	local found = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Slot == slot then
			table.insert(found, item)
		end
	end
	return found
end

describe("the tones a cosmetic is drawn in", function()
	it("are the page's inks: never a colour, never white, and legible on vellum", function()
		-- Rule 1: every saturated colour belongs to a glyph. Rule 7: white means invulnerable.
		local count = 0
		for name, rgb in pairs(CosmeticConfig.Tones) do
			count += 1
			local high = math.max(rgb[1], rgb[2], rgb[3])
			local low = math.min(rgb[1], rgb[2], rgb[3])
			-- The thresholds tests/WorldConfig.spec.luau applies to the world's own colours: saturation above
			-- a fifth of full value, chroma below it, where a ratio of two small numbers means nothing.
			local saturation = if high == 0 then 0 else (high - low) / high
			if high / 255 >= 0.2 and saturation > 0.25 then
				error(("tone %s is a colour, not an ink: saturation %.2f"):format(name, saturation))
			elseif high / 255 < 0.2 and (high - low) / 255 > 0.06 then
				error(("tone %s is too far off grey for a value that dark"):format(name))
			end
			if high > 160 then
				error(
					("tone %s is too pale: on the page it would read as white, which means invulnerable"):format(name)
				)
			end
			if distance(rgb, PAGE) < 150 then
				error(("tone %s disappears into the page"):format(name))
			end
		end
		expect(count).toBeGreaterThanOrEqual(3)
	end)
end)

describe("a skin", function()
	it("keeps every pigment its own school at both ends of the shade range", function()
		-- Measured before it was written: at -0.35 a darkened Cinnabar was closer to Umber than to itself.
		for _, shade in ipairs(PigmentConfig.ShadeRange) do
			for _, name in ipairs(PigmentConfig.Order) do
				local own = PigmentConfig.Colors[name]
				local shaded = PigmentConfig.shade(own, shade, INK, PAGE)
				local nearest = math.min(distance(shaded, INK), distance(shaded, PAGE))
				for _, other in ipairs(PigmentConfig.Order) do
					if other ~= name then
						nearest = math.min(nearest, distance(shaded, PigmentConfig.Colors[other]))
					end
				end
				if distance(shaded, own) > 0.75 * nearest then
					error(("%s shaded by %.2f drifts out of its school"):format(name, shade))
				end
			end
		end
	end)

	it("is a shade of its own glyph's pigment, visible, and different from its glyph's other skins", function()
		local byGlyph: { [string]: { [number]: string } } = {}
		for _, item in ipairs(itemsIn("Skin")) do
			local target = item.Target
			if target == nil or GlyphConfig.ById[target] == nil then
				error(item.Id .. " targets no glyph")
			end
			local shade = item.Look.Shade
			if shade == nil then
				error(item.Id .. " declares no shade")
			end
			expect(shade).toBeGreaterThanOrEqual(PigmentConfig.ShadeRange[1])
			expect(shade).toBeLessThanOrEqual(PigmentConfig.ShadeRange[2])
			-- A skin that moves its pigment by less than this is a purchase nobody can see.
			expect(math.abs(shade)).toBeGreaterThanOrEqual(0.15)
			local seen = byGlyph[target] or {}
			if seen[shade] ~= nil then
				error(("%s and %s are the same shade of %s"):format(seen[shade], item.Id, target))
			end
			seen[shade] = item.Id
			byGlyph[target] = seen
		end
	end)

	it("clamps a forged shade, so no packet can move a spell out of its school", function()
		local cinnabar = PigmentConfig.Colors.Cinnabar
		local forged = PigmentConfig.shade(cinnabar, -1, INK, PAGE)
		local floor = PigmentConfig.shade(cinnabar, PigmentConfig.ShadeRange[1], INK, PAGE)
		expect(forged[1]).toBe(floor[1])
		expect(forged[2]).toBe(floor[2])
		expect(forged[3]).toBe(floor[3])
		local unchanged = PigmentConfig.shade(cinnabar, 0 / 0, INK, PAGE)
		expect(unchanged[1]).toBe(cinnabar[1])
	end)

	it("reaches the hit it lands, not only the cast", function()
		-- Found by review: a skinned Brand exploded in its shade and burned the floor in the default red.
		local combat = strip(fs.readFile("src/server/Services/CombatService.luau"))
		expect(combat:find("cosmetic.skinShade(source, tags[1])", 1, true)).never.toBe(nil)
		expect(combat:find("hitParams.Shade = shade", 1, true)).never.toBe(nil)
		local library = strip(fs.readFile("src/client/Controllers/VfxLibrary.luau"))
		local hit = library:match("VfxLibrary%.Hit = function.-\nend\n") or ""
		expect(hit:find("glyphColor(pigment, packet, api)", 1, true)).never.toBe(nil)
		-- One source for the shade on the server.
		local glyph = strip(fs.readFile("src/server/Services/GlyphService.luau"))
		expect(glyph:find("cosmetic.skinShade(player, def.Id)", 1, true)).never.toBe(nil)
		expect(glyph:find("local function skinShade", 1, true)).toBe(nil)
	end)

	it("is decided by the server and drawn by every renderer that paints a glyph", function()
		local glyph = strip(fs.readFile("src/server/Services/GlyphService.luau"))
		expect(glyph:find("Vfx = shadedVfx(shade)", 1, true)).never.toBe(nil)
		expect(glyph:find("Shade = shade }", 1, true)).never.toBe(nil)
		expect(glyph:find("runEffect(player, def, effect, origin, direction, shade)", 1, true)).never.toBe(nil)
		local library = strip(fs.readFile("src/client/Controllers/VfxLibrary.luau"))
		local painted = 0
		for _ in library:gmatch("Color = glyphColor%(") do
			painted += 1
		end
		-- Cast, Brand, Explosion and every other glyph through playGlyph.
		expect(painted).toBeGreaterThanOrEqual(4)
		expect(library:find("Color = api.PigmentColor(pigment),\n\t\tPigment = pigment,\n\t\tFollow", 1, true)).toBe(
			nil
		)
	end)
end)

describe("an aura and a trail", function()
	it("are built from styles the renderer draws, in a tone that exists", function()
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		for slot, styles in pairs({ Aura = CosmeticConfig.AuraStyles, Trail = CosmeticConfig.TrailStyles }) do
			local allowed = toSet(styles)
			local table_ = controller:match("local " .. string.upper(slot) .. ": .-\n}\n") or ""
			if table_ == "" then
				error("CosmeticController has no " .. string.upper(slot) .. " style table")
			end
			for _, style in ipairs(styles) do
				if not table_:find("\n\t" .. style .. " = function", 1, true) then
					error(("CosmeticController draws no %s style %s"):format(slot, style))
				end
			end
			for _, item in ipairs(itemsIn(slot)) do
				local itemStyles = item.Look.Styles or {}
				expect(#itemStyles).toBeGreaterThan(0)
				for _, style in ipairs(itemStyles) do
					if not allowed[style] then
						error(("%s wears %s, which is not a %s style"):format(item.Id, style, slot))
					end
				end
				if CosmeticConfig.Tones[(item.Look.Tone or "") :: string] == nil then
					error(item.Id .. " names no tone")
				end
			end
		end
	end)

	it("carry their rarity in craft: a legendary aura layers at least two styles", function()
		for _, item in ipairs(itemsIn("Aura")) do
			if item.Rarity == "Legendary" then
				expect(#(item.Look.Styles or {})).toBeGreaterThanOrEqual(2)
			end
		end
	end)
end)

describe("a kill effect", function()
	it("plays a timeline that exists and draws no pigment, no light and no pigment voice", function()
		local kills = itemsIn("KillEffect")
		expect(#kills).toBeGreaterThanOrEqual(4)
		for _, item in ipairs(kills) do
			local id = item.Look.Timeline
			local timeline = if id ~= nil then VfxTimelineConfig.Timelines[id] else nil
			if timeline == nil then
				error(item.Id .. " plays no timeline")
			end
			for _, phase in ipairs(timeline.Phases) do
				for _, layer in ipairs(phase.Layers) do
					-- A light tinted with ink lights nothing, and a Voice needs a pigment the kill has not got.
					if layer.Kind == "Light" or layer.Voice ~= nil then
						error(
							("%s's timeline %s has a %s layer it cannot draw"):format(item.Id, id :: string, layer.Kind)
						)
					end
					-- A shake or a screen flash lands on every nearby camera: a paid cosmetic must never reach
					-- into the screen of a player still fighting (found by review).
					if layer.Kind == "Shake" or layer.Kind == "Flash" then
						error(("%s's timeline %s reaches into other players' screens"):format(item.Id, id :: string))
					end
					-- Rule 3, nothing appears: every plane is drawn from small to large.
					if
						(layer.Kind == "Sprite" or layer.Kind == "Mark")
						and (layer.Size or 0) >= (layer.EndSize or 0)
					then
						error(("%s's timeline %s pops a %s in at full size"):format(item.Id, id :: string, layer.Kind))
					end
				end
			end
		end
	end)

	it("is sent by the server on a kill and drawn by VfxLibrary in an ink tone", function()
		local service = strip(fs.readFile("src/server/Services/CosmeticService.luau"))
		expect(service:find("combat.Killed:Connect(onKilled)", 1, true)).never.toBe(nil)
		expect(service:find('Id = "KillEffect"', 1, true)).never.toBe(nil)
		-- Reliable: one packet per kill, and a dropped one is a paid effect that never draws.
		expect(service:find("Params = { Effect = item.Id },\n\t}, true)", 1, true)).never.toBe(nil)
		-- Only a player or a training proof: not the World Boss, whose last hit ends on BossDefeated.
		local killed = service:match("local function onKilled%(.-\nend\n") or ""
		-- The exact guard, not the words: a condition that merely mentions them can guard nothing.
		local guard = "if\n\t\tPlayers:GetPlayerFromCharacter(victimModel) == nil\n"
			.. "\t\tand not CollectionService:HasTag(victimModel, GameConfig.Enemy.Tag)\n\tthen\n\t\treturn\n\tend"
		expect(killed:find(guard, 1, true)).never.toBe(nil)
		local library = strip(fs.readFile("src/client/Controllers/VfxLibrary.luau"))
		local renderer = library:match("VfxLibrary%.KillEffect = function.-\nend\n") or ""
		expect(renderer:find("CosmeticConfig.Tones", 1, true)).never.toBe(nil)
		expect(renderer:find("PigmentColor", 1, true)).toBe(nil)
	end)
end)

describe("a kill that is credited", function()
	it("is a fresh one: a death long after the last hit credits nobody", function()
		-- Found by review, older than the kill effects that made it visible: the winner of a duel, back in
		-- the hub on the same character, pressed Reset minutes later and handed the loser a kill, its XP and
		-- Folios -- and now the loser's finisher at the winner's feet.
		local combat = strip(fs.readFile("src/server/Services/CombatService.luau"))
		local credit = combat:match("local function creditDeath%(.-\nend\n") or ""
		expect(#credit).toBeGreaterThan(0)
		expect(
			credit:find(
				"if not inCombat then\n\t\tcharacter:SetAttribute(LAST_ATTACKER_ATTRIBUTE, nil)\n\t\treturn",
				1,
				true
			)
		).never.toBe(nil)
		expect(credit:find("attackerId == nil and not inCombat", 1, true)).toBe(nil)
	end)
end)

describe("a title", function()
	it("writes words that exist in both languages", function()
		local titles = itemsIn("Title")
		expect(#titles).toBeGreaterThanOrEqual(10)
		for _, item in ipairs(titles) do
			local key = item.Look.TextKey
			if key == nil or not Strings.has(key) then
				error(item.Id .. " has no words to write")
			end
			local entry = (Strings.Table :: any)[key]
			expect(type(entry.en)).toBe("string")
			expect(type(entry.fr)).toBe("string")
		end
	end)
end)

describe("what a player reads in the shop", function()
	it("never promises a colour the bible forbids a cosmetic to have", function()
		-- A name is a promise. "Azure Brand" is a blue Cinnabar spell, which rule 2 forbids.
		local colourWords = {
			"Azure",
			"Azur",
			"Jade",
			"Emerald",
			"Émeraude",
			"Violet",
			"Crimson",
			"Pourpre",
			"Golden",
			"Dorée",
			"Blue",
			"Bleue",
			"Magma",
			"Crystal",
			"Cristal",
			"Silver",
			"Argent",
			"Frost",
			"Givre",
		}
		for _, item in ipairs(CosmeticConfig.Items) do
			local entry = (Strings.Table :: any)[item.NameKey]
			for _, text in ipairs({ entry.en, entry.fr }) do
				for _, word in ipairs(colourWords) do
					if string.find(text, word, 1, true) then
						error(("%s is called %q, which promises a colour"):format(item.Id, text))
					end
				end
			end
		end
	end)
end)

describe("the VIP pass", function()
	it("grants the exclusive aura its description promises", function()
		local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
		expect(#MonetizationConfig.VipCosmetics).toBeGreaterThanOrEqual(1)
		local hasAura = false
		for _, id in ipairs(MonetizationConfig.VipCosmetics) do
			local item = CosmeticConfig.ById[id]
			expect(item).never.toBe(nil)
			expect(item.Sellable).toBe(false)
			hasAura = hasAura or item.Slot == "Aura"
		end
		expect(hasAura).toBe(true)
		local passes = strip(fs.readFile("src/server/Services/MonetizationService/Passes.luau"))
		expect(passes:find("MonetizationConfig.VipCosmetics", 1, true)).never.toBe(nil)
	end)
end)

describe("the renderer", function()
	it("draws an aura where it can be seen, and nothing it may not draw", function()
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		-- Found by review: motes born inside the torso, sorted behind it, were hidden for most of their life.
		expect(controller:find("ZOffset = -", 1, true)).toBe(nil)
		for _, style in ipairs({ "Motes", "Pages" }) do
			local body = controller:match("\n\t" .. style .. " = function.-\n\tend,") or ""
			expect(body:find("aroundBody(", 1, true)).never.toBe(nil)
		end
		-- Rule 8: on the floor tier nothing of somebody else's, ribbons included.
		local build = controller:match("local function buildStyles%(.-\nend\n") or ""
		expect(build:find("if scale <= 0 then\n\t\treturn worn", 1, true)).never.toBe(nil)
		-- A teleport wipes the ribbons rather than drawing a stroke across the jump.
		expect(controller:find("TELEPORT_STUDS then\n\t\t\twipeRibbons(entry)", 1, true)).never.toBe(nil)
	end)

	it("is started by the client and reads the attributes the server writes", function()
		local bootstrap = fs.readFile("src/client/Bootstrap.client.luau")
		expect(bootstrap:find('"CosmeticController"', 1, true)).never.toBe(nil)
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		local service = strip(fs.readFile("src/server/Services/CosmeticService.luau"))
		expect(service:find('ATTRIBUTE_PREFIX = "Cosmetic"', 1, true)).never.toBe(nil)
		expect(controller:find('ATTRIBUTE_PREFIX = "Cosmetic"', 1, true)).never.toBe(nil)
		expect(controller:find("GetAttributeChangedSignal(ATTRIBUTE_PREFIX .. slot)", 1, true)).never.toBe(nil)
	end)
end)
