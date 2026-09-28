--!strict
-- What a player buys must be what a player sees. Until D-109 not one of the forty cosmetics was drawn:
-- CosmeticService published what each character wore and no client ever read it, the kill effects were
-- never sent, and the skins were promised to "travel with the packet" by a comment and by nothing else.
-- The catalogue itself broke the art bible -- a violet aura, a blue Brand -- so it was redrawn in the
-- page's inks before it was wired (CosmeticConfig's header says why each rule applies).
--
-- This file holds the catalogue to the bible and to its renderers, and the renderers to the catalogue.
--
-- D-148 amended rule 1 for what a body wears: an aura and a trail are coloured now, because in the page's
-- charcoal the legendary "Illuminated Aura" drew a few black dots round a dark avatar. The colours are
-- measured here with the metric tests/Config.spec.luau holds the pigments apart by, on every colour the
-- renderer can draw: the stops of Pure/AuraMath.colors, the function CosmeticController paints with, and
-- every colour the engine draws between two of them.
local AssetIds = require("../src/shared/Config/AssetIds")
local AuraMath = require("../src/shared/Pure/AuraMath")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local Strings = require("../src/shared/Strings")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PAGE = WorldConfig.Colors.Page
local INK = WorldConfig.Colors.Ink
local WHITE = { 255, 255, 255 }
-- Rule 7's cyan, the colour of "us" (ThemeConfig.Ally on the interface's branch, D-147).
local ALLY = { 115, 227, 255 }
-- How far a worn colour stays from each pigment, from the ally's cyan, from white and from the page.
local MIN_FROM_PIGMENT = 60
local MIN_FROM_ALLY = 60
local MIN_FROM_WHITE = 130
local MIN_FROM_PAGE = 100

-- The redmean distance tests/Config.spec.luau uses for the pigments, for the same question.
local function distance(a: { number }, b: { number }): number
	local rmean = (a[1] + b[1]) / 2
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt((2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db)
end

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
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

local function isInk(tone: string): boolean
	return table.find(CosmeticConfig.Inks, tone) ~= nil
end

describe("the tones a cosmetic is drawn in", function()
	it("keep the page's inks as inks: never a colour, never white, and legible on vellum", function()
		-- Rule 1 for what is not worn: a kill effect, the dash's sketches, the kit outline.
		for _, name in ipairs(CosmeticConfig.Inks) do
			local rgb = CosmeticConfig.Tones[name]
			if rgb == nil then
				error(("the ink %s is not a tone"):format(name))
			end
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
		expect(#CosmeticConfig.Inks).toBeGreaterThanOrEqual(3)
	end)

	it("give a kill effect an ink, never a colour: it lands in somebody else's fight", function()
		for _, item in ipairs(itemsIn("KillEffect")) do
			local tone = item.Look.Tone
			if tone ~= nil and not isInk(tone) then
				error(("%s is drawn in %s, which is not one of the page's inks"):format(item.Id, tone))
			end
		end
	end)

	it("are never white, which means invulnerable", function()
		local count = 0
		for name, rgb in pairs(CosmeticConfig.Tones) do
			count += 1
			if distance(rgb, WHITE) < MIN_FROM_WHITE then
				error(("tone %s is %.0f from white"):format(name, distance(rgb, WHITE)))
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

-- Every aura and trail, with the style data each of its layers is drawn from and the tone of that layer.
type Layer = { Item: CosmeticConfig.CosmeticDef, Name: string, Style: CosmeticConfig.Style?, Tone: string? }
local function wornLayers(): { Layer }
	local layers: { Layer } = {}
	for slot, styles in pairs({ Aura = CosmeticConfig.AuraStyles, Trail = CosmeticConfig.TrailStyles }) do
		for _, item in ipairs(itemsIn(slot)) do
			for index, name in ipairs(item.Look.Styles or {}) do
				local tones = item.Look.Tones
				table.insert(layers, {
					Item = item,
					Name = name,
					Style = styles[name],
					Tone = if tones ~= nil then tones[index] else item.Look.Tone,
				})
			end
		end
	end
	return layers
end

local function emissionsOf(style: CosmeticConfig.Style): { CosmeticConfig.Emission }
	return style.Emissions or {}
end

local function ribbonsOf(style: CosmeticConfig.Style): { CosmeticConfig.Ribbon }
	return style.Ribbons or {}
end

-- How finely the colours between two stops are measured. The engine draws a ColorSequence by carrying each
-- channel in a straight line from one keypoint to the next, and a line between two colours that each keep
-- their distance from a pigment can still pass close to it: an ember drying toward ink crosses Umber's
-- brown on the way (found by review: 38 from Umber, with both of its stops over 80).
local STEPS_BETWEEN_STOPS = 32

local function between(a: { number }, b: { number }, t: number): { number }
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

-- Every colour one layer can put on screen: each stop of each of its emissions' and ribbons' ramps, and
-- every colour the engine draws between two of them.
local function colorsOf(layer: Layer): { { number } }
	local rgb = CosmeticConfig.Tones[layer.Tone or ""]
	local out: { { number } } = {}
	local style = layer.Style
	if rgb == nil or style == nil then
		return out
	end
	local ramps: { AuraMath.Ramp } = {}
	for _, emission in ipairs(emissionsOf(style)) do
		table.insert(ramps, emission)
	end
	for _, ribbon in ipairs(ribbonsOf(style)) do
		table.insert(ramps, { Dries = ribbon.Dries })
	end
	for _, ramp in ipairs(ramps) do
		local stops = AuraMath.colors(rgb, ramp, CosmeticConfig.Tones.Ink, CosmeticConfig.Flow.HoldShare)
		for index, stop in ipairs(stops) do
			table.insert(out, stop.Rgb)
			local after = stops[index + 1]
			if after ~= nil then
				for step = 1, STEPS_BETWEEN_STOPS - 1 do
					table.insert(out, between(stop.Rgb, after.Rgb, step / STEPS_BETWEEN_STOPS))
				end
			end
		end
	end
	return out
end

-- The most particles a look keeps alive at once at the High tier.
local function liveOf(item: CosmeticConfig.CosmeticDef, styles: { [string]: CosmeticConfig.Style }): number
	local total = 0
	for _, name in ipairs(item.Look.Styles or {}) do
		for _, emission in ipairs(emissionsOf(styles[name] or {})) do
			total += AuraMath.live(emission)
		end
	end
	return total
end

describe("an aura and a trail", function()
	it("are built from styles that exist and draw something, each in a tone that exists", function()
		for _, layer in ipairs(wornLayers()) do
			local style = layer.Style
			if style == nil then
				error(("%s wears %s, which is not a %s style"):format(layer.Item.Id, layer.Name, layer.Item.Slot))
			end
			expect(#emissionsOf(style) + #ribbonsOf(style)).toBeGreaterThan(0)
			if CosmeticConfig.Tones[layer.Tone or ""] == nil then
				error(("%s's %s names no tone"):format(layer.Item.Id, layer.Name))
			end
		end
		for slot, styles in pairs({ Aura = CosmeticConfig.AuraStyles, Trail = CosmeticConfig.TrailStyles }) do
			for _, item in ipairs(itemsIn(slot)) do
				local count = #(item.Look.Styles or {})
				expect(count).toBeGreaterThan(0)
				local tones = item.Look.Tones
				if tones ~= nil and #tones ~= count then
					error(("%s has %d styles and %d tones"):format(item.Id, count, #tones))
				end
			end
			-- No style nobody wears: data with no purchase behind it is dead code.
			for name in pairs(styles) do
				local worn = false
				for _, item in ipairs(itemsIn(slot)) do
					worn = worn or table.find(item.Look.Styles or {}, name) ~= nil
				end
				if not worn then
					error(("the %s style %s is worn by nothing"):format(slot, name))
				end
			end
		end
	end)

	it("are drawn by the renderer: every place, path, direction and texture is one it knows", function()
		local math_ = strip(fs.readFile("src/shared/Pure/AuraMath.luau"))
		local point = math_:match("function AuraMath%.point%(.-\nend\n") or ""
		local path = math_:match("function AuraMath%.path%(.-\nend\n") or ""
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		local emission = controller:match("local EMISSION: .-\n}\n") or ""
		-- A place kind AuraMath does not branch on falls through to an orbit: a typo would draw somewhere else.
		local POINTS =
			{ Ring = true, Feet = true, Floor = true, Hands = true, Behind = true, Orbit = true, Scrawl = true }
		local PATHS = { Behind = true, Orbit = true, Scrawl = true }
		for _, kind in ipairs({ "Ring", "Feet", "Floor", "Hands", "Behind" }) do
			expect(point:find('kind == "' .. kind .. '"', 1, true)).never.toBe(nil)
		end
		for _, kind in ipairs({ "Behind", "Scrawl" }) do
			expect(path:find('place.Kind == "' .. kind .. '"', 1, true)).never.toBe(nil)
		end
		for _, styles in ipairs({ CosmeticConfig.AuraStyles, CosmeticConfig.TrailStyles }) do
			for name, style in pairs(styles) do
				for _, spec in ipairs(emissionsOf(style)) do
					if not POINTS[spec.Place.Kind] then
						error(("%s is born at a %s, which the renderer does not place"):format(name, spec.Place.Kind))
					end
					if emission:find("\n\t" .. spec.Emit .. " = Enum.NormalId.", 1, true) == nil then
						error(
							("%s emits %s, which the renderer does not turn into a direction"):format(name, spec.Emit)
						)
					end
					local asset = AssetIds.Textures[spec.Texture]
					if asset == nil or asset.Id == "" then
						error(("%s is drawn with %s, which is not an uploaded texture"):format(name, spec.Texture))
					end
				end
				for _, ribbon in ipairs(ribbonsOf(style)) do
					if not PATHS[ribbon.Path.Kind] then
						error(("%s runs a %s, which the renderer does not trace"):format(name, ribbon.Path.Kind))
					end
				end
			end
		end
		-- Every emission and every ribbon of a style is built.
		local build = controller:match("local function buildStyles%(.-\nend\n") or ""
		expect(build:find("for _, emission in ipairs(style.Emissions or {}) do", 1, true)).never.toBe(nil)
		expect(build:find("for _, ribbon in ipairs(style.Ribbons or {}) do", 1, true)).never.toBe(nil)
		expect(build:find("look.Tones[index] else look.Tone", 1, true)).never.toBe(nil)
	end)

	it("are coloured, and never in a school's colour, white, or the ally's cyan", function()
		-- D-148. Rule 2 read from the other side: a school IS its pigment, so what a body wears keeps a
		-- measured distance from all five; rule 7: white is invulnerable, cyan is an ally.
		local layers = wornLayers()
		expect(#layers).toBeGreaterThanOrEqual(20)
		for _, layer in ipairs(layers) do
			local colours = colorsOf(layer)
			expect(#colours).toBeGreaterThan(0)
			for _, rgb in ipairs(colours) do
				local what = ("%s's %s draws %d,%d,%d"):format(layer.Item.Id, layer.Name, rgb[1], rgb[2], rgb[3])
				for _, pigment in ipairs(PigmentConfig.Order) do
					local gap = distance(rgb, PigmentConfig.Colors[pigment])
					if gap < MIN_FROM_PIGMENT then
						error(("%s, %.0f from %s"):format(what, gap, pigment))
					end
				end
				if distance(rgb, ALLY) < MIN_FROM_ALLY then
					error(("%s, the ally's cyan"):format(what))
				end
				if distance(rgb, WHITE) < MIN_FROM_WHITE then
					error(("%s, near white"):format(what))
				end
				if distance(rgb, PAGE) < MIN_FROM_PAGE then
					error(("%s, lost on the page"):format(what))
				end
			end
		end
		-- And every tone -- the headline, what the shop shows and the first thing seen, and the tone of each
		-- layer -- is a colour, not an ink: a legendary with two of its three layers back in charcoal would
		-- keep every distance above and show a few black dots again (found by review).
		for _, slot in ipairs({ "Aura", "Trail" }) do
			for _, item in ipairs(itemsIn(slot)) do
				local tones = table.clone(item.Look.Tones or {})
				table.insert(tones, item.Look.Tone or "")
				for _, tone in ipairs(tones) do
					local rgb = CosmeticConfig.Tones[tone]
					if rgb == nil or isInk(tone) then
						error(("%s is drawn in %s, which is not a colour"):format(item.Id, tone))
					end
					local high = math.max(rgb[1], rgb[2], rgb[3])
					local saturation = (high - math.min(rgb[1], rgb[2], rgb[3])) / high
					if high / 255 < 0.2 or saturation <= 0.25 then
						error(("%s's %s is too grey to be a colour: saturation %.2f"):format(item.Id, tone, saturation))
					end
				end
			end
		end
	end)

	it("carry their rarity in craft and intensity: one layer, two, three with a light core", function()
		for _, slot in ipairs({ "Aura", "Trail" }) do
			for _, item in ipairs(itemsIn(slot)) do
				local want = CosmeticConfig.LayersByRarity[item.Rarity]
				if #(item.Look.Styles or {}) ~= want then
					error(
						("%s is %s and layers %d styles, not %d"):format(
							item.Id,
							item.Rarity,
							#(item.Look.Styles or {}),
							want
						)
					)
				end
			end
		end
		expect(CosmeticConfig.LayersByRarity.Rare).toBe(1)
		expect(CosmeticConfig.LayersByRarity.Epic).toBe(2)
		expect(CosmeticConfig.LayersByRarity.Legendary).toBe(3)
		-- A Legendary aura, and only a Legendary aura, wears exactly one core.
		for _, item in ipairs(itemsIn("Aura")) do
			local cores = 0
			for _, name in ipairs(item.Look.Styles or {}) do
				local style = CosmeticConfig.AuraStyles[name]
				if style ~= nil and style.Core == true then
					cores += 1
				end
			end
			expect(cores).toBe(if item.Rarity == "Legendary" then 1 else 0)
		end
		for name, style in pairs(CosmeticConfig.TrailStyles) do
			if style.Core == true then
				error(("the trail style %s is a core: only an aura shines"):format(name))
			end
		end
	end)

	it("add light only at a core, and never a core alone on the page", function()
		for _, styles in ipairs({ CosmeticConfig.AuraStyles, CosmeticConfig.TrailStyles }) do
			for name, style in pairs(styles) do
				local lit, unlit = 0, 0
				for _, emission in ipairs(emissionsOf(style)) do
					local shines = (emission.Glow or 0) > 0 or (emission.Heat or 0) > 0
					if shines and style.Core ~= true then
						error(("%s adds light or heat and is not a core"):format(name))
					end
					if shines then
						lit += 1
					else
						unlit += 1
					end
				end
				if style.Core == true then
					-- A heart that shines, and a halo of its tone round it (rule 10: a pale core alone is a smudge).
					expect(lit).toBeGreaterThanOrEqual(1)
					expect(unlit).toBeGreaterThanOrEqual(1)
				end
			end
		end
		-- The renderer lights nothing else: its only LightEmission on a particle is the one AuraMath.glow gives.
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		expect(controller:find("e.LightEmission = AuraMath.glow(spec.Glow, fighting, FIGHT.Glow)", 1, true)).never.toBe(
			nil
		)
		for value in controller:gmatch("LightEmission = ([^\n]+)") do
			if value ~= "AuraMath.glow(spec.Glow, fighting, FIGHT.Glow)" and value ~= "0" then
				error("CosmeticController sets a LightEmission of " .. value)
			end
		end
	end)

	it("keep one body's particles within its budget, at every tier", function()
		expect(CosmeticConfig.Budget.LiveParticles).toBeLessThanOrEqual(60)
		local most = 0
		for _, aura in ipairs(itemsIn("Aura")) do
			for _, trail in ipairs(itemsIn("Trail")) do
				local live = liveOf(aura, CosmeticConfig.AuraStyles) + liveOf(trail, CosmeticConfig.TrailStyles)
				if live > CosmeticConfig.Budget.LiveParticles then
					error(("%s with %s keeps %.1f particles alive"):format(aura.Id, trail.Id, live))
				end
				most = math.max(most, live)
			end
		end
		-- Measured, so the gate is not passing on an empty catalogue.
		expect(most).toBeGreaterThan(20)
		for _, styles in ipairs({ CosmeticConfig.AuraStyles, CosmeticConfig.TrailStyles }) do
			for name, style in pairs(styles) do
				for _, emission in ipairs(emissionsOf(style)) do
					if AuraMath.live(emission) <= 0 then
						error(("%s emits nothing"):format(name))
					end
				end
			end
		end
		-- A tier scales the flow; the floor tier draws nobody else's; the local player's own survives it.
		local floor = QualityConfig.Tiers[QualityConfig.Order[#QualityConfig.Order]].ParticleScale
		expect(AuraMath.density(1, false, false, false, 0.4)).toBe(1)
		expect(AuraMath.density(0.6, false, false, false, 0.4)).toBe(0.6)
		expect(AuraMath.density(floor, false, true, false, 0.4)).toBe(0)
		expect(AuraMath.density(floor, true, true, false, 0.4)).toBe(floor)
		expect(floor).toBeGreaterThan(0)
	end)

	it("are emitted by the renderer on its own clock, never by the engine's Rate", function()
		-- D-124: the engine thins a Rate about nine times at its automatic graphics quality, never an Emit.
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		local rates = 0
		for value in controller:gmatch("%.Rate = ([^\n]+)") do
			rates += 1
			if value ~= "0" then
				error("CosmeticController gives an emitter a Rate of " .. value)
			end
		end
		expect(rates).toBe(1)
		local emission = controller:match("local function buildEmission%(.-\nend\n") or ""
		expect(emission:find("e.Rate = 0\n\te.Enabled = false", 1, true)).never.toBe(nil)
		expect(emission:find("Owed = { Rate = spec.Rate * density, Carry = 0 }", 1, true)).never.toBe(nil)
		local flow = controller:match("local function emitFlow%(.-\nend\n") or ""
		expect(flow:find("local count = AuraMath.owed(flow.Owed, dt, FLOW.MaxStepSeconds)", 1, true)).never.toBe(nil)
		expect(flow:find("flow.Emitter:Emit(1)", 1, true)).never.toBe(nil)
		local beat = controller:match("local function onHeartbeat%(.-\nend\n") or ""
		expect(beat:find("if moving or not flow.Moving then\n\t\t\t\t\temitFlow(entry, flow, dt, now)", 1, true)).never.toBe(
			nil
		)
		expect(controller:find("RunService.Heartbeat:Connect(onHeartbeat)", 1, true)).never.toBe(nil)
		-- The accumulator: a steady second owes its rate exactly, and a hitch is not paid back as a burst.
		local flowState: AuraMath.Flow = { Rate = 12, Carry = 0 }
		local total = 0
		for _ = 1, 60 do
			total += AuraMath.owed(flowState, 1 / 60, CosmeticConfig.Flow.MaxStepSeconds)
		end
		expect(total >= 11 and total <= 12).toBe(true)
		local hitch: AuraMath.Flow = { Rate = 12, Carry = 0 }
		expect(AuraMath.owed(hitch, 2, CosmeticConfig.Flow.MaxStepSeconds)).toBeLessThanOrEqual(
			math.ceil(12 * CosmeticConfig.Flow.MaxStepSeconds)
		)
	end)

	it("steps back while the local player fights: fewer, fainter, and unlit", function()
		local fight = CosmeticConfig.Fight
		expect(fight.Density).toBeLessThanOrEqual(0.4)
		expect(fight.Density).toBeGreaterThan(0)
		expect(fight.Transparency).toBeGreaterThanOrEqual(0.25)
		expect(fight.Glow).toBe(0)
		expect(AuraMath.density(1, true, false, true, fight.Density)).toBe(fight.Density)
		expect(AuraMath.glow(0.6, true, fight.Glow)).toBe(0)
		expect(AuraMath.glow(0.6, false, fight.Glow)).toBe(0.6)
		local lifted = AuraMath.lifted({ 0, 0.9, 1 }, fight.Transparency)
		expect(lifted[1]).toBe(fight.Transparency)
		expect(lifted[2]).toBe(1)
		expect(lifted[3]).toBe(1)
		-- Wired: the match and the portals say when, and every piece reads it when it is built.
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		local start = controller:match("function CosmeticController%.Start%(.-\nend\n") or ""
		expect(start:find("matchController.MatchChanged:Connect(refreshFight)", 1, true)).never.toBe(nil)
		expect(start:find("travelController.FightChanged:Connect(refreshFight)", 1, true)).never.toBe(nil)
		local refresh = controller:match("local function refreshFight%(.-\nend\n") or ""
		expect(refresh:find("local now = matchController.getMatch() ~= nil or travelController.inFight()", 1, true)).never.toBe(
			nil
		)
		expect(refresh:find("fighting = now\n\trebuildAll()", 1, true)).never.toBe(nil)
		local density = controller:match("local function densityFor%(.-\nend\n") or ""
		expect(density:find("floorTier, fighting, FIGHT.Density)", 1, true)).never.toBe(nil)
		local emission = controller:match("local function buildEmission%(.-\nend\n") or ""
		expect(emission:find("AuraMath.lifted(spec.Transparency, if fighting then FIGHT.Transparency else 0)", 1, true)).never.toBe(
			nil
		)
		local ribbon = controller:match("local function buildRibbon%(.-\nend\n") or ""
		expect(ribbon:find("spec.Transparency + (if fighting then FIGHT.Transparency else 0)", 1, true)).never.toBe(nil)
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
		-- Only a player, a training proof or a Forger (D-131): not the World Boss, whose last hit ends on
		-- BossDefeated.
		local killed = service:match("local function onKilled%(.-\nend\n") or ""
		-- The exact guard, not the words: a condition that merely mentions them can guard nothing.
		local guard = "if\n\t\tPlayers:GetPlayerFromCharacter(victimModel) == nil\n"
			.. "\t\tand not CollectionService:HasTag(victimModel, GameConfig.Enemy.Tag)\n"
			.. "\t\tand not CollectionService:HasTag(victimModel, BotConfig.Tag)\n\tthen\n\t\treturn\n\tend"
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
	it("draws an aura where it can be seen, big enough to see, and nothing it may not draw", function()
		local controller = strip(fs.readFile("src/client/Controllers/CosmeticController.luau"))
		-- Found by review: motes born inside the torso, sorted behind it, were hidden for most of their life.
		expect(controller:find("ZOffset = -", 1, true)).toBe(nil)
		for _, styles in ipairs({ CosmeticConfig.AuraStyles, CosmeticConfig.TrailStyles }) do
			for name, style in pairs(styles) do
				for _, emission in ipairs(emissionsOf(style)) do
					local place = emission.Place
					if (place.Kind == "Ring" or place.Kind == "Orbit") and (place.Radius or 0) < 1.5 then
						error(("%s is born inside the body"):format(name))
					end
					-- The motes that were 0.2 to 0.6 studs and shrank to nothing: a purchase nobody saw.
					if math.max(table.unpack(emission.Size)) < 0.45 then
						error(
							("%s is never bigger than %.2f studs"):format(name, math.max(table.unpack(emission.Size)))
						)
					end
				end
				for _, ribbon in ipairs(ribbonsOf(style)) do
					if ribbon.Width < 0.3 then
						error(("%s is a hairline of %.2f studs"):format(name, ribbon.Width))
					end
				end
			end
		end
		-- Rule 8: on the floor tier nothing of somebody else's, ribbons included.
		local build = controller:match("local function buildStyles%(.-\nend\n") or ""
		expect(build:find("if density <= 0 then\n\t\treturn worn", 1, true)).never.toBe(nil)
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
