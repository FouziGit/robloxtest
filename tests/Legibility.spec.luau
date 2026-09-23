--!strict
-- What a player must be able to SEE, held where a later tuning pass cannot quietly undo it.
--
-- Both rules come from the developer playing the game once the textures were online: "on voit plus le
-- mur, les autres spells je les vois plus du tout". The wall was an invisible slab behind a smear, and
-- every particle, beam and trail was partly additive light -- which a cream page swallows.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local RENDERERS = {
	"src/client/Controllers/VfxTimeline.luau",
	"src/client/Controllers/VfxLibrary.luau",
	"src/client/Controllers/VfxPool.luau",
}

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

describe("ink", function()
	it("is laid on the page, never added to it as light", function()
		-- Measured side by side in a live client: the same Umber smoke at LightEmission 0.35 read pale and
		-- orange on the page, and at 0 dense and brown.
		expect(VfxConfig.LightEmission).toBeGreaterThanOrEqual(0)
		expect(VfxConfig.LightEmission).toBeLessThanOrEqual(0.1)
	end)

	it("takes its emission from the config in every renderer, with no number of its own", function()
		local assignments = 0
		for _, path in ipairs(RENDERERS) do
			local code = strip(fs.readFile(path))
			for value in code:gmatch("LightEmission%s*=%s*([^\n]+)") do
				assignments += 1
				local literal = tonumber((value:gsub("%s+$", "")))
				-- The pool's reset writes a plain zero, which is the config's value and no look of its own;
				-- anything else must be read from VfxConfig.
				if literal ~= nil and literal ~= 0 then
					error(("%s hard-codes LightEmission = %s: read VfxConfig.LightEmission"):format(path, value))
				end
			end
		end
		-- Non-vacuous: the renderers do set it, so a pattern that stopped matching would pass silently.
		expect(assignments).toBeGreaterThanOrEqual(4)
	end)
end)

describe("a drawn layer", function()
	local timeline = strip(fs.readFile("src/client/Controllers/VfxTimeline.luau"))
	local function body(name: string): string
		local code = timeline:match("local function " .. name .. "%(.-\nend\n") or ""
		if code == "" then
			error(name .. " is not in VfxTimeline: this gate would check nothing")
		end
		return code
	end

	it("fades on the ink's clock, not on the ease that spreads it", function()
		-- The Wash stains spread on Exponential Out and faded on the same curve: 73 % transparent a third
		-- of the way into a 2.4 s life. The law is FeelMath.layerFade (tests/FeelMath.spec.luau); this
		-- holds the renderer to it, from the clock to the call.
		local step = body("stepLive")
		expect(
			step:find(
				"local elapsed = if span > 0 then math.clamp((now - entry.StartedAt) / span, 0, 1) else 1",
				1,
				true
			)
		).never.toBe(nil)
		expect(step:find("local alpha = eased(entry.Layer, elapsed)", 1, true)).never.toBe(nil)
		-- The clock is defined once and never overwritten by the eased value.
		local writes = 0
		for _ in step:gmatch("elapsed%s*=[^=]") do
			writes += 1
		end
		expect(writes).toBe(1)
		for _, call in ipairs({
			"stepSprite(entry, alpha, elapsed, deltaTime)",
			"stepMark(entry, alpha, elapsed)",
			"stepBeam(entry, alpha, elapsed)",
		}) do
			if not step:find(call, 1, true) then
				error("stepLive no longer calls " .. call)
			end
		end
		for _, name in ipairs({ "stepSprite", "stepMark", "stepBeam" }) do
			local code = body(name)
			if not code:find("fadeOf(layer, elapsed, alpha", 1, true) then
				error(name .. " fades its layer without fadeOf: the ease that spreads it would fade it too")
			end
			if code:find("EndTransparency, alpha", 1, true) then
				error(name .. " lerps its transparency on the eased alpha")
			end
		end
		local fade = body("fadeOf")
		expect(
			fade:find(
				"FeelMath.layerFade(from, layer.EndTransparency or from, elapsed, alpha, layer.FadesWithSize == true)",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("lets a fade stay the gesture only where holding the ink would state a danger that is over", function()
		-- Serif's damage is instant, and Sweep's ink is shoved to the rim and gone: held on the page by the
		-- ink-drying fade, their prints read as ground that still hurts, like Ligature's burning pools.
		local function marks(id: string, phaseName: string): { any }
			local found = {}
			for _, phase in ipairs(VfxTimelineConfig.Timelines[id].Phases) do
				if phase.Name == phaseName then
					for _, layer in ipairs(phase.Layers) do
						if layer.Kind == "Mark" then
							table.insert(found, layer)
						end
					end
				end
			end
			return found
		end
		local feet = marks("Serif", "Impact")
		expect(#feet).toBe(5)
		for index, foot in ipairs(feet) do
			if foot.FadesWithSize ~= true then
				error(("Serif's foot %d dries like a burning pool instead of lightening as it spreads"):format(index))
			end
		end
		local wiped = 0
		for _, mark in ipairs(marks("Sweep", "Impact")) do
			if mark.Texture == "InkBlot" and mark.FadesWithSize == true then
				wiped += 1
			end
		end
		expect(wiped).toBe(1)
		-- And nowhere it would mean nothing: only on a drawn plane that fades out.
		for id, entry in pairs(VfxTimelineConfig.Timelines) do
			for _, phase in ipairs(entry.Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.FadesWithSize ~= nil then
						local drawn = layer.Kind == "Mark" or layer.Kind == "Sprite" or layer.Kind == "Beam"
						local fadesOut = (layer.EndTransparency or 0) > (layer.Transparency or 0)
						if not (drawn and fadesOut and layer.FadesWithSize == true) then
							error(
								("%s / %s declares FadesWithSize on a layer it cannot apply to"):format(id, phase.Name)
							)
						end
					end
				end
			end
		end
	end)

	it("keeps an emitter until its last particle can have died", function()
		-- Released at For, an emitter took every particle in the air with it: the Wash cast's puffs (For
		-- 0.04, Lifetime up to 0.55) were on screen for two frames.
		local wash = VfxTimelineConfig.Timelines.Wash.Phases[2].Layers[2]
		expect(wash.Kind).toBe("Emitter")
		expect(VfxTimelineConfig.layerSeconds(wash, wash.For)).toBeCloseTo(0.04 + 0.55, 6)
		local emitters = 0
		for id, entry in pairs(VfxTimelineConfig.Timelines) do
			for _, phase in ipairs(entry.Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Emitter" then
						emitters += 1
						local lifetime = layer.Lifetime or VfxTimelineConfig.DefaultParticleLifetime
						if VfxTimelineConfig.layerSeconds(layer, layer.For) < layer.For + lifetime[2] - 1e-9 then
							error(("%s / %s releases an emitter before its particles die"):format(id, phase.Name))
						end
					elseif VfxTimelineConfig.layerSeconds(layer, layer.For) ~= layer.For then
						error(("%s / %s keeps a %s past its own life"):format(id, phase.Name, layer.Kind))
					end
				end
			end
		end
		expect(emitters).toBeGreaterThan(100)
		-- The renderer, the budget and the packet lifetime all ask the same function, so what is drawn is
		-- what is budgeted.
		local activate = body("activate")
		expect(activate:find("VfxTimelineConfig.layerSeconds(layer, item.Seconds)", 1, true)).never.toBe(nil)
		expect(activate:find("EndsAt = now + lives", 1, true)).never.toBe(nil)
		local cost = strip(fs.readFile("scripts/effect-cost.luau"))
		expect(cost:find("Until = at + lives", 1, true)).never.toBe(nil)
		expect(cost:find("VfxTimelineConfig.layerSeconds(layer, for_)", 1, true)).never.toBe(nil)
		local oneEmitter: any = {
			Phases = {
				{
					Name = "Impact",
					Duration = 0.1,
					Layers = { { Kind = "Emitter", At = 0, For = 0.1, Lifetime = { 0.1, 0.5 } } },
				},
			},
		}
		expect(VfxTimelineConfig.duration(oneEmitter)).toBeCloseTo(0.6, 6)
	end)

	it("stops a continuous emitter at the end of its own life, on the clock", function()
		-- Read off the eased value, 26 emitters with a Sine Out ease stopped at 65 % of their life.
		local code = body("stepEmitter")
		expect(code:find("now - entry.StartedAt >= entry.Seconds then", 1, true)).never.toBe(nil)
		expect(code:find("alpha", 1, true)).toBe(nil)
		expect(timeline:find("stepEmitter(entry, now)", 1, true)).never.toBe(nil)
	end)

	it("turns a thrown trail's face to the camera, leaves a curtain on the body standing, and tapers both", function()
		-- Spanned vertically along its flight line, a trail thrown straight ahead is seen edge-on by the
		-- thrower and by its target: Brand, the glyph thrown most, was a hairline to both. A ribbon on the
		-- caster's own body is a curtain, and turned to a chase camera it would lie flat across their legs.
		local code = body("buildTrail")
		expect(code:find("trail.FaceCamera = layer.Follow ~= true", 1, true)).never.toBe(nil)
		expect(code:find("trail.WidthScale", 1, true)).never.toBe(nil)
	end)
end)

describe("a part a renderer builds", function()
	it("is laid in the page's material, never in one that adds light", function()
		local library = strip(fs.readFile("src/client/Controllers/VfxLibrary.luau"))
		for _, material in ipairs({ "Neon", "ForceField", "Glass" }) do
			if library:find("Enum.Material." .. material, 1, true) then
				error("VfxLibrary builds a part in " .. material .. ", which a cream page washes out")
			end
		end
		expect(library:find("part.Material = props.Material or Palette.material()", 1, true)).never.toBe(nil)
	end)
end)

describe("a glyph that blocks", function()
	local effects = strip(fs.readFile("src/server/Effects/GlyphEffects.luau"))
	local margin = effects:match("function GlyphEffects%.Margin.-\nend") or ""

	it("is drawn by the thing that blocks, on every quality tier", function()
		-- The collision is the server's, so the look is too: a client effect can be dropped by the lower
		-- tiers, and a wall that stops shots must never be drawn by something optional.
		expect(#margin).toBeGreaterThan(0)
		expect(margin:find("Palette.world(look.Wall)", 1, true)).never.toBe(nil)
		expect(margin:find("Palette.material()", 1, true)).never.toBe(nil)
		expect(margin:find("look.WallTransparency", 1, true)).never.toBe(nil)
	end)

	it("is solid enough to read at a glance and clear enough to see an opponent through", function()
		local glyphs = WorldConfig.Glyphs
		expect(WorldConfig.Colors[glyphs.Wall]).never.toBe(nil)
		expect(glyphs.WallTransparency).toBeGreaterThan(0)
		expect(glyphs.WallTransparency).toBeLessThanOrEqual(0.5)
	end)

	it("fades in with its collision and out before it is gone, within the life of the shortest wall", function()
		local glyphs = WorldConfig.Glyphs
		expect(glyphs.WallFadeInSeconds).toBeGreaterThan(0)
		expect(glyphs.WallFadeInSeconds).toBeLessThanOrEqual(0.2)
		expect(glyphs.WallFadeOutSeconds).toBeGreaterThan(0)
		-- A wall shorter than its two fades would start fading out at once, cancel its own fade-in and
		-- block for its whole life at Transparency 1: the invisible slab this file exists to forbid.
		local walls = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			if def.Effect == "Margin" then
				walls += 1
				local duration = (def.Params :: any).Duration
				if glyphs.WallFadeInSeconds + glyphs.WallFadeOutSeconds > duration then
					error(("%s lasts %.2f s, less than its fade in and out"):format(def.Id, duration))
				end
			end
		end
		expect(walls).toBeGreaterThanOrEqual(1)
	end)
end)
