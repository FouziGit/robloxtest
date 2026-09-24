--!strict
-- The craft of a single particle (D-111): ink that dries over its life, and a spark drawn along its
-- flight. Both were measured in a live client before being written down: every spark of the game was a
-- horizontal dash whatever way it flew, and every particle, trail and floor mark kept one flat colour from
-- birth to death.
local AssetIds = require("../src/shared/Config/AssetIds")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local timeline = strip(fs.readFile("src/client/Controllers/VfxTimeline.luau"))
local function body(name: string): string
	local code = timeline:match("local function " .. name .. "%(.-\nend\n") or ""
	if code == "" then
		error(name .. " is not in VfxTimeline: this gate would check nothing")
	end
	return code
end

describe("ink", function()
	it("is born wet and dries darker, inside the range where its school stays its own", function()
		local ramp = VfxConfig.InkRamp
		expect(ramp.Wet).toBeGreaterThan(0)
		expect(ramp.Dry).toBeLessThan(0)
		expect(ramp.Wet).toBeLessThanOrEqual(PigmentConfig.ShadeRange[2])
		expect(ramp.Dry).toBeGreaterThanOrEqual(PigmentConfig.ShadeRange[1])
		-- A ramp nobody can see is decoration without the effect.
		expect(ramp.Wet - ramp.Dry).toBeGreaterThanOrEqual(0.2)
	end)

	it("dries in every particle, every trail and every floor mark a glyph draws", function()
		expect(body("buildEmitter"):find("emitter.Color = inkRamp(entry.Context, entry.Context.Color)", 1, true)).never.toBe(
			nil
		)
		expect(body("buildTrail"):find("trail.Color = inkRamp(entry.Context, entry.Context.Color)", 1, true)).never.toBe(
			nil
		)
		local mark = body("buildMark")
		expect(mark:find("wet, dry = wetAndDry(entry.Context, ink)", 1, true)).never.toBe(nil)
		expect(mark:find("decal.Color3 = wet:Lerp(dry, driedBy(entry, entry.StartedAt))", 1, true)).never.toBe(nil)
		expect(body("stepMark"):find("child.Color3 = wet:Lerp(dry, driedBy(entry, now))", 1, true)).never.toBe(nil)
	end)

	it("dries a floor mark on its play's clock, so a stain drawn in links does not flash wet at each one", function()
		-- Dried on each mark's own life, Margin's ruled line went from dry to wet in one frame at 0.76 s, and
		-- Scorch's char pulsed three times (found by review, D-111).
		expect(body("driedBy"):find("(now - entry.PlayStartedAt) / VfxConfig.InkRamp.Seconds", 1, true)).never.toBe(nil)
		expect(body("stepMark"):find("elapsed, 0, 1", 1, true)).toBe(nil)
		expect(body("activate"):find("PlayStartedAt = item.PlayStartedAt", 1, true)).never.toBe(nil)
		local play = timeline:match("function VfxTimeline%.play%(.-\nend\n") or ""
		local stamp = timeline:match("function VfxTimeline%.stamp%(.-\nend\n") or ""
		expect(play:find("PlayStartedAt = now,", 1, true)).never.toBe(nil)
		expect(stamp:find("PlayStartedAt = now,", 1, true)).never.toBe(nil)
		-- A mark the impact lays is still more wet than dry: the drying outlasts twice the latest impact.
		local latest = 0
		for id in pairs(VfxTimelineConfig.Timelines) do
			latest = math.max(latest, VfxTimelineConfig.phaseAt(id, "Impact", 1) or 0)
		end
		expect(latest).toBeGreaterThan(0)
		expect(VfxConfig.InkRamp.Seconds).toBeGreaterThanOrEqual(2 * latest)
		-- And it finishes while the longest mark is still on the floor.
		expect(VfxConfig.InkRamp.Seconds).toBeLessThanOrEqual(VfxTimelineConfig.MaxLayerSeconds)
	end)

	it("still dries under every skin sold, and the skin stays a purchase someone can see", function()
		-- A skin and the drying share one axis, and the range is 0.45 wide for a 0.32 ramp: a skin at the
		-- edge of the range keeps its distance from the default at one end of the life and shares the other.
		-- Dark skins show at birth, where a glyph is brightest; pale ones in the tail (D-111).
		local ramp = VfxConfig.InkRamp
		local low, high = PigmentConfig.ShadeRange[1], PigmentConfig.ShadeRange[2]
		local skins = 0
		for _, item in ipairs(CosmeticConfig.Items) do
			local shade = if item.Slot == "Skin" and item.Look ~= nil then item.Look.Shade else nil
			if shade ~= nil then
				skins += 1
				local wet = math.clamp(shade + ramp.Wet, low, high)
				local dry = math.clamp(shade + ramp.Dry, low, high)
				expect(wet - dry).toBeGreaterThanOrEqual(0.1)
				expect(math.max(math.abs(wet - ramp.Wet), math.abs(dry - ramp.Dry))).toBeGreaterThanOrEqual(0.15)
			end
		end
		expect(skins).toBeGreaterThanOrEqual(5)
	end)

	it("dries from the pigment, with the skin, clamped once: never out of the school", function()
		-- Shading the already skinned colour compounded a -0.25 skin and a -0.2 drying to -0.45, past the
		-- point where a darkened Cinnabar reads as Umber (found before commit, D-111).
		local dry = body("wetAndDry")
		expect(dry:find("(PigmentConfig.Colors :: any)[pigment]", 1, true)).never.toBe(nil)
		expect(dry:find("PigmentConfig.shade(base, shade + ramp.Wet", 1, true)).never.toBe(nil)
		expect(dry:find("PigmentConfig.shade(base, shade + ramp.Dry", 1, true)).never.toBe(nil)
		-- Whatever a skin and the drying add up to, what is drawn is the clamped shade.
		for _, skin in ipairs({ PigmentConfig.ShadeRange[1], 0, PigmentConfig.ShadeRange[2] }) do
			for _, step in ipairs({ VfxConfig.InkRamp.Wet, VfxConfig.InkRamp.Dry }) do
				local base = PigmentConfig.Colors.Cinnabar
				local drawn = PigmentConfig.shade(base, skin + step, { 23, 21, 15 }, { 232, 224, 206 })
				local limit = math.clamp(skin + step, PigmentConfig.ShadeRange[1], PigmentConfig.ShadeRange[2])
				local expected = PigmentConfig.shade(base, limit, { 23, 21, 15 }, { 232, 224, 206 })
				expect(drawn[1]).toBe(expected[1])
				expect(drawn[2]).toBe(expected[2])
			end
		end
	end)

	it("only when it is a pigment: the page-coloured Erasure and a kill effect's inks keep their colour", function()
		local dry = body("wetAndDry")
		expect(dry:find("if base == nil then\n\t\treturn color, color", 1, true)).never.toBe(nil)
		expect(body("buildMark"):find("if entry.Context.Ink == nil then", 1, true)).never.toBe(nil)
		-- The glyph plays carry the pigment and the skin; a kill effect and the boss carry no pigment.
		local library = strip(fs.readFile("src/client/Controllers/VfxLibrary.luau"))
		local shaded = 0
		for _ in library:gmatch('Shade = numberParam%(packet, "Shade", 0%)') do
			shaded += 1
		end
		expect(shaded).toBeGreaterThanOrEqual(6)
		-- A glyph's hit dries in its pigment; a melee hit, which has none, does not.
		local hit = library:match("VfxLibrary%.Hit = function.-\nend\n") or ""
		expect(hit:find('Pigment = if pigment ~= "" then pigment else nil', 1, true)).never.toBe(nil)
		local kill = library:match("VfxLibrary%.KillEffect = function.-\nend\n") or ""
		expect(kill:find("Pigment =", 1, true)).toBe(nil)
	end)
end)

describe("a streak", function()
	it("is drawn along its flight, and only a texture that is a streak", function()
		local streaks = 0
		for key, isStreak in pairs(VfxConfig.StreakTextures) do
			expect(isStreak).toBe(true)
			expect(AssetIds.Textures[key]).never.toBe(nil)
			streaks += 1
		end
		expect(streaks).toBeGreaterThanOrEqual(1)
		local emitter = body("buildEmitter")
		expect(emitter:find("VfxConfig.StreakTextures[layer.Texture] == true", 1, true)).never.toBe(nil)
		expect(emitter:find("emitter.Orientation = Enum.ParticleOrientation.VelocityParallel", 1, true)).never.toBe(nil)
		-- Head first: the image's head is at -X and VelocityParallel lays +X on the flight.
		expect(emitter:find("emitter.Rotation = NumberRange.new(180, 180)", 1, true)).never.toBe(nil)
		-- Along the flight a negative Squash is the long one.
		expect(emitter:find("squash = -squash", 1, true)).never.toBe(nil)
		-- The pool puts every borrowed emitter back to facing the camera, or a smoke puff inherits the
		-- orientation of the spark that used the instance before it.
		local pool = strip(fs.readFile("src/client/Controllers/VfxPool.luau"))
		expect(pool:find("emitter.Orientation = Enum.ParticleOrientation.FacingCamera", 1, true)).never.toBe(nil)
	end)

	it("is stretched when it is fastest and round once drag has stopped it", function()
		local emitter = body("buildEmitter")
		expect(emitter:find("NumberSequenceKeypoint.new(0, squash)", 1, true)).never.toBe(nil)
		expect(emitter:find("NumberSequenceKeypoint.new(1, 0)", 1, true)).never.toBe(nil)
		-- And the streak texture is what the timelines stretch.
		local stretched = 0
		for _, entry in pairs(VfxTimelineConfig.Timelines) do
			for _, phase in ipairs(entry.Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Squash ~= nil and layer.Texture ~= nil and VfxConfig.StreakTextures[layer.Texture] then
						stretched += 1
					end
				end
			end
		end
		expect(stretched).toBeGreaterThanOrEqual(20)
	end)
end)
