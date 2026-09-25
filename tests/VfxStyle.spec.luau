--!strict
-- The style the effects were rebuilt in, seen in the Studio lab before it was written down (D-119): live
-- ink with a heated core. Each rule here is one the lab showed breaking an effect -- a pale core alone on a
-- pale page, a freeze frame that let a projectile fall behind its damage, a spell that appeared a round
-- trip after the press -- and each is held on the data and on the renderer's own source.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local FeelConfig = require("../src/shared/Config/FeelConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local TIMELINES = VfxTimelineConfig.Timelines

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function fold(source: string): string
	return (source:gsub("%s+", " "))
end

local function read(path: string): string
	return fold(strip(fs.readFile(path)))
end

-- A function's body in a file, comments stripped and whitespace folded.
local function body(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return fold(source:sub(start, finish or #source))
end

local TIMELINE = "src/client/Controllers/VfxTimeline.luau"
local CLOCK = "src/client/Controllers/VfxClock.luau"

local function eachLayer(fn: (id: string, phase: VfxTimelineConfig.Phase, layer: VfxTimelineConfig.Layer) -> ())
	for id, timeline in pairs(TIMELINES) do
		for _, phase in ipairs(timeline.Phases) do
			for _, layer in ipairs(phase.Layers) do
				fn(id, phase, layer)
			end
		end
	end
end

describe("the heated core", function()
	it("is the only thing that shines, and never past the cap", function()
		local cores = 0
		eachLayer(function(id, phase, layer)
			local shines = layer.Glow ~= nil
				or (layer.Kind ~= "Light" and layer.Brightness ~= nil and layer.Brightness > 1)
			if layer.Role == "Core" then
				cores += 1
			end
			if shines and layer.Role ~= "Core" then
				error(("%s / %s: a %s layer that is not a core shines"):format(id, phase.Name, layer.Kind))
			end
			if layer.Glow ~= nil then
				expect(layer.Glow > 0 and layer.Glow <= VfxConfig.MaxGlow).toBe(true)
				local kind = layer.Kind
				expect(kind == "Emitter" or kind == "Beam" or kind == "Trail").toBe(true)
			end
		end)
		expect(cores).toBeGreaterThanOrEqual(5)
	end)

	it("is the pigment heated, never white, which is invulnerability", function()
		expect(VfxConfig.Heat.Toward > 0 and VfxConfig.Heat.Toward <= 0.8).toBe(true)
		expect(VfxConfig.Heat.Cools > 0 and VfxConfig.Heat.Cools < 1).toBe(true)
		for _, pigment in ipairs(PigmentConfig.Order) do
			local rgb = PigmentConfig.Colors[pigment]
			local short = 0
			for channel = 1, 3 do
				local heated = rgb[channel] + (255 - rgb[channel]) * VfxConfig.Heat.Toward
				short += 255 - heated
			end
			if short < 60 then
				error(("%s heated is within %d of white"):format(pigment, math.floor(short)))
			end
		end
	end)

	it("never stands alone on the page: every phase with a core has its pigment or its ink beside it", function()
		-- A pale core on a pale floor is a pale smudge (the lab's first Brand): ringed by its pigment it
		-- reads as heat.
		for id, timeline in pairs(TIMELINES) do
			for _, phase in ipairs(timeline.Phases) do
				local core, surround = false, false
				for _, layer in ipairs(phase.Layers) do
					local drawn = layer.Kind ~= "Sound" and layer.Kind ~= "Shake" and layer.Kind ~= "Flash"
					if layer.Role == "Core" then
						core = true
					elseif drawn and layer.Kind ~= "Light" and layer.Kind ~= "Carrier" then
						surround = true
					end
				end
				if core and not surround then
					error(("%s / %s draws a core with nothing of its pigment around it"):format(id, phase.Name))
				end
			end
		end
	end)

	it("dims when the player turns shakes and flashes off", function()
		expect(VfxConfig.Calm.Glow < VfxConfig.MaxGlow).toBe(true)
		-- Nothing crosses the resting bloom's threshold (LightingConfig: 1.6) once calmed.
		expect(VfxConfig.Calm.Brightness <= 1).toBe(true)
		expect(body(TIMELINE, "local function calm("):find("return feel ~= nil and not feel.motionAllowed()", 1, true)).never.toBe(
			nil
		)
		expect(
			body(TIMELINE, "local function glowOf("):find("if calm() then math.min(glow, VfxConfig.Calm.Glow)", 1, true)
		).never.toBe(nil)
		expect(
			body(TIMELINE, "local function brightnessOf("):find(
				"if calm() then math.min(brightness, VfxConfig.Calm.Brightness)",
				1,
				true
			)
		).never.toBe(nil)
		local emitter = body(TIMELINE, "local function buildEmitter(")
		expect(emitter:find("emitter.Brightness = brightnessOf(entry.Context, layer)", 1, true)).never.toBe(nil)
		expect(emitter:find("emitter.LightEmission = glowOf(entry.Context, layer)", 1, true)).never.toBe(nil)
		expect(
			body(TIMELINE, "local function buildTrail("):find(
				"trail.Brightness = brightnessOf(entry.Context, layer)",
				1,
				true
			)
		).never.toBe(nil)
		expect(
			body(TIMELINE, "local function buildBeam("):find(
				"beam.Brightness = brightnessOf(entry.Context, layer)",
				1,
				true
			)
		).never.toBe(nil)
		-- The same switch Feel and the page flash ask: one question, one answer.
		expect(read("src/client/Controllers/Feel.luau"):find("Feel.motionAllowed = motionAllowed", 1, true)).never.toBe(
			nil
		)
	end)
end)

describe("a play that must not shine", function()
	it("keeps a fist's core in its own ink: no heat, no light, no bloom (D-116)", function()
		local glow = body(TIMELINE, "local function glowOf(")
		expect(glow:find("if context.Unlit == true then return VfxConfig.LightEmission end", 1, true)).never.toBe(nil)
		local bright = body(TIMELINE, "local function brightnessOf(")
		expect(bright:find("if context.Unlit == true then 1 else layer.Brightness or 1", 1, true)).never.toBe(nil)
		expect(
			body(TIMELINE, "local function roleRamp("):find('if role == "Core" and context.Unlit ~= true then', 1, true)
		).never.toBe(nil)
		expect(
			body(TIMELINE, "local function roleColor("):find(
				'elseif role == "Core" and context.Unlit ~= true then',
				1,
				true
			)
		).never.toBe(nil)
		expect(
			body(TIMELINE, "local function roleWetDry("):find(
				'if layer.Role == "Core" and context.Unlit ~= true then',
				1,
				true
			)
		).never.toBe(nil)
	end)
end)

describe("the impact's freeze frame", function()
	it("holds what is drawn with the camera's hit-stop, on the burst's widest frames", function()
		expect(
			body("src/client/Controllers/Feel.luau", "function Feel.hitStop("):find("VfxClock.hold(seconds)", 1, true)
		).never.toBe(nil)
		local hold = body(CLOCK, "function VfxClock.hold(")
		expect(hold:find("EffectClock.hold(state, os.clock(), seconds, config.Longest, config.After)", 1, true)).never.toBe(
			nil
		)
		-- Only the effect clock: the steady one is never held.
		expect(hold:find("steady", 1, true)).toBe(nil)
		local after = FeelConfig.EffectHold.After
		expect(after > 0 and after <= 0.1).toBe(true)
		expect(after < FeelConfig.EffectHold.Longest).toBe(true)
	end)

	it("never holds what is drawn on the server's own time", function()
		-- Held, a Brand in flight fell behind the one that hurts by its speed times the hold, and a boss
		-- warning filled late by every hit landed on the boss while it filled.
		expect(VfxTimelineConfig.steady(TIMELINES.Brand)).toBe(true)
		expect(VfxTimelineConfig.steady(TIMELINES.Wash)).toBe(true)
		expect(VfxTimelineConfig.steady(TIMELINES.Explosion)).toBe(false)
		expect(VfxTimelineConfig.steady(TIMELINES.Hit)).toBe(false)
		local windowed = 0
		for id, timeline in pairs(TIMELINES) do
			for _, phase in ipairs(timeline.Phases) do
				local timed = phase.Window == true
				for _, layer in ipairs(phase.Layers) do
					timed = timed or layer.Kind == "Carrier"
				end
				if timed then
					windowed += 1
					if not VfxTimelineConfig.steady(timeline) then
						error(("%s is drawn on the server's time and would be held"):format(id))
					end
				end
			end
		end
		expect(windowed).toBeGreaterThanOrEqual(5)
		-- Each play reads one clock, from its first layer to its landing.
		local play = body(TIMELINE, "function VfxTimeline.play(")
		expect(play:find("local steady = VfxTimelineConfig.steady(timeline) local now = clockOf(steady)", 1, true)).never.toBe(
			nil
		)
		expect(play:find("Steady = steady,", 1, true)).never.toBe(nil)
		local beat = body(TIMELINE, "local function onHeartbeat(")
		expect(beat:find("local now = if item.Steady then steadyNow else heldNow", 1, true)).never.toBe(nil)
		expect(beat:find("local now = if entry.Steady then steadyNow else heldNow", 1, true)).never.toBe(nil)
		expect(beat:find("followRate(entry, if entry.Steady then steadyRate else rate)", 1, true)).never.toBe(nil)
		expect(body(TIMELINE, "local function activate("):find("Steady = item.Steady,", 1, true)).never.toBe(nil)
		local land = body(TIMELINE, "function VfxTimeline.land(")
		expect(land:find("local now = if entry.Steady then steadyNow else heldNow", 1, true)).never.toBe(nil)
		-- And the Studio lab scales both clocks alike.
		local clock = read(CLOCK)
		local _, rescales = clock:gsub("EffectClock%.rescale%(steady,", "")
		expect(rescales).toBe(2)
	end)
end)

describe("a spell born in the hand", function()
	it("lights on the press, on this screen only", function()
		local combo = body("src/client/Controllers/ComboController.luau", "local function onAction(")
		expect(
			combo:find(
				'if decision.Action == "Cast" or decision.Action == "Wait" then vfxController.tap(actionId) end',
				1,
				true
			)
		).never.toBe(nil)
		local tap = body("src/client/Controllers/VfxController.luau", "function VfxController.tap(")
		expect(tap:find('timeline.play("Tap", {', 1, true)).never.toBe(nil)
		expect(tap:find("Hand = hand,", 1, true)).never.toBe(nil)
		expect(tap:find("character:FindFirstChild(VfxConfig.Hand)", 1, true)).never.toBe(nil)
		-- Local and silent: the press already plays its note, and a shake or a flash nobody else sees
		-- would be one the player took for a hit.
		local layers = 0
		for _, phase in ipairs(TIMELINES.Tap.Phases) do
			for _, layer in ipairs(phase.Layers) do
				layers += 1
				expect(layer.Kind ~= "Sound" and layer.Kind ~= "Shake" and layer.Kind ~= "Flash").toBe(true)
				expect(layer.Anchor).toBe("Hand")
			end
		end
		expect(layers).toBeGreaterThanOrEqual(4)
	end)

	it("places what is anchored to the hand at the hand, turned the way the spell is aimed", function()
		expect(
			body(TIMELINE, "local function activate("):find(
				'if layer.Anchor == "Hand" and hand ~= nil and hand.Parent ~= nil then base = base.Rotation + hand.Position end',
				1,
				true
			)
		).never.toBe(nil)
		local library = read("src/client/Controllers/VfxLibrary.luau")
		expect(library:find("character:FindFirstChild(VfxConfig.Hand)", 1, true)).never.toBe(nil)
		-- The shared cast lights every glyph in the hand; the Brand's throw leaves it too.
		local _, handed = library:gsub("Hand = casterHand%(packet%),", "")
		expect(handed).toBeGreaterThanOrEqual(3)
		local cast = body("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Cast = function(")
		expect(cast:find("Hand = casterHand(packet),", 1, true)).never.toBe(nil)
		local function anchored(id: string): number
			local count = 0
			for _, phase in ipairs(TIMELINES[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Anchor == "Hand" then
						count += 1
					end
				end
			end
			return count
		end
		expect(anchored("Cast")).toBeGreaterThanOrEqual(5)
		expect(anchored("Brand")).toBeGreaterThanOrEqual(2)
	end)
end)

describe("the motion of a particle and a ribbon", function()
	it("pops past its size and settles, only where a layer asks", function()
		expect(VfxConfig.PopOvershoot > 1 and VfxConfig.PopOvershoot <= 1.5).toBe(true)
		local emitter = body(TIMELINE, "local function buildEmitter(")
		expect(emitter:find("NumberSequenceKeypoint.new(pop, endSize * VfxConfig.PopOvershoot)", 1, true)).never.toBe(
			nil
		)
		expect(emitter:find("emitter.Acceleration = Vector3.new(0, -(layer.Weight or 0) * scale, 0)", 1, true)).never.toBe(
			nil
		)
		expect(emitter:find('emitter.EmissionDirection = EMISSION[layer.Emit or "Up"]', 1, true)).never.toBe(nil)
		local pops = 0
		eachLayer(function(_id, _phase, layer)
			if layer.Pop ~= nil then
				pops += 1
				expect(layer.Kind).toBe("Emitter")
				expect(layer.Pop > 0 and layer.Pop < 1).toBe(true)
			end
			if layer.Weight ~= nil then
				expect(layer.Kind).toBe("Emitter")
				expect(layer.Weight > 0).toBe(true)
			end
			if layer.Emit ~= nil then
				expect(layer.Kind).toBe("Emitter")
			end
		end)
		expect(pops).toBeGreaterThanOrEqual(3)
	end)

	it("keeps a ribbon a streak rather than a line from the thrower to the target", function()
		eachLayer(function(id, phase, layer)
			-- D-119: a texture on a Trail is stretched over its whole length; the brush stroke rendered as a
			-- smudge on every glyph and on the dodge. A ribbon is bare, tapered by its size.
			if layer.Kind == "Trail" and layer.Texture ~= nil then
				error(("%s / %s textures a trail (%s): it renders as a smudge"):format(id, phase.Name, layer.Texture))
			end
			if layer.Ribbon ~= nil then
				expect(layer.Kind).toBe("Trail")
				if layer.Ribbon <= 0 or layer.Ribbon > layer.For then
					error(("%s / %s keeps a ribbon longer than its life"):format(id, phase.Name))
				end
			end
		end)
		expect(
			body(TIMELINE, "local function ribbonOf("):find(
				"math.min(entry.Layer.Ribbon or entry.Seconds, entry.Seconds)",
				1,
				true
			)
		).never.toBe(nil)
		expect(
			body(TIMELINE, "local function buildTrail("):find(
				"trail.Lifetime = ribbonOf(entry) / VfxClock.labScale()",
				1,
				true
			)
		).never.toBe(nil)
		-- A trail stretches its texture over its whole length, and the brush stroke drawn that way was a
		-- faint smudge in the lab: the Brand's ribbons are bare, tapered wedges.
		for _, phase in ipairs(TIMELINES.Brand.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == "Trail" then
					expect(layer.Texture).toBe(nil)
					expect((layer.EndSize or 1) < (layer.Size or 1)).toBe(true)
				end
			end
		end
	end)
end)

describe("a glyph drawn where it hurts, when it hurts", function()
	it("draws the Wash's front at the rim of its damage, not at its centre", function()
		-- The server's sphere hurts a target when its rim reaches it; drawn at the carrier (its centre)
		-- the front arrived a third of a second after the hit it announced (the lab, D-119).
		local radius = (GlyphConfig.ById.Wash.Params :: any).HitRadius
		local fronts = 0
		for _, phase in ipairs(TIMELINES.Wash.Phases) do
			if phase.Name == "Travel" then
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Sprite" and layer.Ride == true then
						fronts += 1
						local ahead = (layer.Offset or { 0, 0, 0 })[3]
						expect(ahead >= radius - 2 and ahead <= radius).toBe(true)
					end
				end
			end
		end
		expect(fronts).toBeGreaterThanOrEqual(1)
	end)

	it("plays the Sweep at the centre the server struck, on the frame it struck", function()
		local sweep = body("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Sweep = function(")
		expect(
			sweep:find('local centre = packet.Origin + directionOf(packet) * numberParam(packet, "Offset", 0)', 1, true)
		).never.toBe(nil)
		expect(sweep:find("Origin = centre,", 1, true)).never.toBe(nil)
		expect(sweep:find('Radius = numberParam(packet, "Radius", 12),', 1, true)).never.toBe(nil)
		-- GlyphEffects.Sweep damages as the packet leaves: nothing is drawn before the wipe.
		expect(TIMELINES.Sweep.Phases[1].Name).toBe("Impact")
		expect(TIMELINES.Sweep.Phases[1].Layers[1].At).toBe(0)
	end)

	it("turns a plane to whoever looks at it, and stands a spike up out of the page", function()
		eachLayer(function(id, phase, layer)
			if layer.Face == "Camera" and layer.Kind ~= "Sprite" then
				error(("%s / %s turns a %s to the camera, which only a Sprite can"):format(id, phase.Name, layer.Kind))
			end
		end)
		local step = body(TIMELINE, "local function stepSprite(")
		expect(step:find('if layer.Face == "Camera" and camera ~= nil then', 1, true)).never.toBe(nil)
		expect(step:find("part.CFrame = CFrame.lookAt(position, toward) * CFrame.Angles(0, 0, turned)", 1, true)).never.toBe(
			nil
		)
		expect(
			body(TIMELINE, "local function buildSprite("):find(
				"CFrame.Angles(0, 0, math.rad(layer.Roll or 0))",
				1,
				true
			)
		).never.toBe(nil)
		-- The Serif's five feet are spikes rising out of the floor at the five points the server damages.
		local spikes = 0
		for _, phase in ipairs(TIMELINES.Serif.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Texture == "InkSpike" then
					spikes += 1
					expect(layer.Face).toBe("Camera")
				end
			end
		end
		expect(spikes).toBe((GlyphConfig.ById.Serif.Params :: any).Count)
	end)
end)

describe("a fire", function()
	-- The burning glyphs were drawn as stains, and a player saw it at once: "les flammes c'est des flaques"
	-- (D-123). A fire stands up and moves, and it does so on every device.
	local BURNING = { "Ligature", "Scorch" }

	local function lead(id: string): number
		local seconds = 0
		for _, phase in ipairs(TIMELINES[id].Phases) do
			if phase.Name == "Anticipation" or phase.Name == "Cast" then
				seconds += phase.Duration
			end
		end
		return seconds
	end

	it("burns every burning glyph as standing tongues from its first tick through its last", function()
		for _, id in ipairs(BURNING) do
			local params = GlyphConfig.ById[id].Params :: any
			local lastTick = (params.Ticks - 1) * params.TickInterval
			local covered = false
			local offset = 0
			for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
				for _, phase in ipairs(TIMELINES[id].Phases) do
					if phase.Name == name then
						for _, layer in ipairs(phase.Layers) do
							local upright = layer.Texture ~= nil and VfxConfig.UprightTextures[layer.Texture] == true
							-- Pigment: the fire itself, not its heart or its soot.
							if upright and layer.Rate ~= nil and layer.Driven == true and layer.Role == nil then
								local from = offset + layer.At
								if from <= lead(id) + 0.05 and from + layer.For >= lastTick then
									covered = true
								end
							end
						end
						offset += phase.Duration
					end
				end
			end
			if not covered then
				error(("%s burns without a fire standing from its first tick to its last"):format(id))
			end
		end
	end)

	it("keeps a flame upright, swaying, born over an area and emitted by the renderer", function()
		eachLayer(function(id, phase, layer)
			local where = ("%s / %s"):format(id, phase.Name)
			if layer.Sway ~= nil then
				expect(layer.Kind).toBe("Emitter")
				if layer.Texture == nil or not VfxConfig.UprightTextures[layer.Texture] then
					error(where .. " sways a particle that does not stand up")
				end
			end
			if layer.Area ~= nil then
				expect(layer.Kind).toBe("Emitter")
				expect(#layer.Area).toBe(3)
				for _, extent in ipairs(layer.Area) do
					expect(extent > 0).toBe(true)
				end
			end
			if layer.Ring ~= nil and layer.Area == nil then
				error(where .. " rings an emitter with no area to ring")
			end
			if layer.Driven ~= nil and (layer.Kind ~= "Emitter" or layer.Rate == nil) then
				error(where .. " drives a flow that is not a rate")
			end
		end)
		local emitter = body(TIMELINE, "local function buildEmitter(")
		expect(emitter:find("elseif area ~= nil then Vector3.new(area[1], area[2], area[3]) * scale", 1, true)).never.toBe(
			nil
		)
		expect(emitter:find("emitter.Shape = Enum.ParticleEmitterShape.Disc", 1, true)).never.toBe(nil)
		expect(emitter:find("emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface", 1, true)).never.toBe(nil)
		expect(
			emitter:find(
				"VfxConfig.UprightTextures[layer.Texture] == true then emitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp",
				1,
				true
			)
		).never.toBe(nil)
		expect(emitter:find("emitter.Rotation = NumberRange.new(-sway, sway)", 1, true)).never.toBe(nil)
		-- A driven flow never hands its rate to the engine, which would thin it.
		expect(
			emitter:find(
				"if layer.Driven == true then entry.Owed = { Rate = layer.Rate * density, Carry = 0, At = entry.StartedAt } else emitter.Rate = layer.Rate * density",
				1,
				true
			)
		).never.toBe(nil)
		local step = body(TIMELINE, "local function stepEmitter(")
		expect(step:find("local upTo = math.min(now, entry.StartedAt + entry.Seconds)", 1, true)).never.toBe(nil)
		expect(step:find("emitter:Emit(count)", 1, true)).never.toBe(nil)
	end)
end)

describe("a glyph on the server's own clock", function()
	local function phaseLength(id: string, name: string): number
		for _, phase in ipairs(TIMELINES[id].Phases) do
			if phase.Name == name then
				return phase.Duration
			end
		end
		return 0
	end

	-- The glyphs the lab has put back on the frame of their damage (D-120 to D-122): each draws what hurts
	-- within two frames of the packet the server damages on. A glyph joins this list when it is reworked.
	local ON_THE_FRAME = {
		"Sweep",
		"Bleed",
		"Serif",
		"Hairline",
		"Stipple",
		"Scorch",
		"Rupture",
		"Ligature",
		"Blot",
		"Binding",
		"Gilding",
		"Spiral",
		"Pounce",
		"Strike",
		"Caret",
		"Watermark",
		"Colophon",
		"ColophonLink",
	}

	it("draws a glyph that strikes on its packet within two frames of it", function()
		for _, id in ipairs(ON_THE_FRAME) do
			local lead = phaseLength(id, "Anticipation") + phaseLength(id, "Cast")
			if lead > 0.05 then
				error(("%s draws its strike %.2f s after the damage it announces"):format(id, lead))
			end
		end
	end)

	it("flies a projectile from where the server's is when the drawn one leaves", function()
		-- GlyphEffects steps these from the packet: the drawn Hairline left 0.15 s late, twenty studs behind,
		-- and struck a target at twenty-four before it had left the hand; the Stipple flew seventeen behind.
		for _, id in ipairs({ "Hairline", "Stipple" }) do
			local def = GlyphConfig.ById[id]
			local params = def.Params :: any
			local lead = phaseLength(id, "Anticipation") + phaseLength(id, "Cast")
			local carriers = 0
			for _, phase in ipairs(TIMELINES[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Carrier" then
						carriers += 1
						local start = (layer.Offset :: { number })[3]
						expect(math.abs(start - (params.SpawnOffset + params.Speed * lead))).toBeLessThanOrEqual(1)
						expect(start + (layer.Travel or 0)).toBeLessThanOrEqual(params.SpawnOffset + def.Range + 1e-6)
					end
				end
			end
			expect(carriers).toBe(1)
		end
	end)

	it("rings the Scorch's fire round the body the server re-centres it on, on each tick", function()
		-- A ring of fire on the zone's edge (D-123; ink spikes on a blot before it, which read as puddles):
		-- every fire layer follows the caster, burns on the rim of the server's Radius, and leaps on each tick.
		local params = GlyphConfig.ById.Scorch.Params :: any
		local lead = phaseLength("Scorch", "Anticipation") + phaseLength("Scorch", "Cast")
		local ticks: { [number]: number } = {}
		local rings = 0
		for _, phase in ipairs(TIMELINES.Scorch.Phases) do
			if phase.Name == "Impact" then
				for _, layer in ipairs(phase.Layers) do
					if layer.Texture == "InkFlame" then
						rings += 1
						expect(layer.Follow).toBe(true)
						expect(layer.Ring).toBe(true)
						local area = layer.Area :: { number }
						expect(area[1]).toBe(area[3])
						expect(math.abs(area[1] / 2 - params.Radius)).toBeLessThanOrEqual(1)
						if layer.Burst ~= nil then
							local tick = math.floor((layer.At + lead) / params.TickInterval + 0.5)
							expect(math.abs(layer.At + lead - tick * params.TickInterval)).toBeLessThanOrEqual(0.035)
							ticks[tick] = (ticks[tick] or 0) + 1
						end
					end
				end
			end
		end
		expect(rings >= params.Ticks + 1).toBe(true)
		for tick = 0, params.Ticks - 1 do
			expect(ticks[tick]).toBe(1)
		end
	end)

	it("beats the Spiral's pull and the Pounce's pours on each of the server's ticks", function()
		-- D-125: both were drawn a tenth of a second after the packet the server acts on.
		local function beats(id: string, matches: (VfxTimelineConfig.Layer) -> boolean)
			local params = GlyphConfig.ById[id].Params :: any
			local lead = phaseLength(id, "Anticipation") + phaseLength(id, "Cast")
			local ticks: { [number]: number } = {}
			for _, phase in ipairs(TIMELINES[id].Phases) do
				if phase.Name == "Impact" then
					for _, layer in ipairs(phase.Layers) do
						if matches(layer) then
							local tick = math.floor((layer.At + lead) / params.TickInterval + 0.5)
							expect(math.abs(layer.At + lead - tick * params.TickInterval)).toBeLessThanOrEqual(0.035)
							ticks[tick] = (ticks[tick] or 0) + 1
						end
					end
				end
			end
			for tick = 0, params.Ticks - 1 do
				if ticks[tick] ~= 1 then
					error(("%s draws %d beats on its tick %d"):format(id, ticks[tick] or 0, tick))
				end
			end
		end
		beats("Spiral", function(layer)
			return layer.Texture == "ShockwaveRing"
		end)
		beats("Pounce", function(layer)
			return layer.Kind == "Emitter" and layer.Burst ~= nil and layer.Area ~= nil
		end)
		-- The whirlpool turns: a seal on the page that spins, and the renderer that spins a mark.
		local turning = 0
		for _, phase in ipairs(TIMELINES.Spiral.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == "Mark" and layer.Spin ~= nil then
					turning += 1
				end
			end
		end
		expect(turning >= 2).toBe(true)
		expect(
			body(TIMELINE, "local function stepMark("):find(
				"if spin ~= nil then part.CFrame = part.CFrame * CFrame.Angles(0, 0, spin * deltaTime)",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("rules the Strike to where the server's ray stopped and steps the Caret to where it put the body", function()
		-- D-126: both flew a fixed distance (70 and 18 studs) whatever the server measured, the Strike from the
		-- caster rather than the muzzle.
		for _, id in ipairs({ "Strike", "Caret" }) do
			local carriers = 0
			for _, phase in ipairs(TIMELINES[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Carrier" then
						carriers += 1
						expect(layer.TravelFrom).toBe("Reach")
						expect(layer.Travel).toBe(1)
					end
				end
			end
			expect(carriers).toBe(1)
			local handler = body("src/client/Controllers/VfxLibrary.luau", ("VfxLibrary.%s = function("):format(id))
			expect(handler:find('Reach = math.max(numberParam(packet, "Range", def.Range), 1),', 1, true)).never.toBe(
				nil
			)
		end
		local strike = body("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Strike = function(")
		expect(strike:find('Origin = packet.Origin + direction * numberParam(packet, "SpawnOffset", 0),', 1, true)).never.toBe(
			nil
		)
	end)

	it("rules the Colophon to the first body it struck, then one stroke per jump of the server's chain", function()
		-- D-127: a fixed sixty studs from the caster, then a stroke from EVERY body toward the next (the last
		-- toward nothing), each a fixed twenty-six studs.
		for _, id in ipairs({ "Colophon", "ColophonLink" }) do
			local carriers = 0
			for _, phase in ipairs(TIMELINES[id].Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Carrier" then
						carriers += 1
						expect(layer.TravelFrom).toBe("Reach")
						expect(layer.Travel).toBe(1)
						-- The mark on the body lands when the stroke arrives, not when its ribbon has faded.
						expect(math.abs(phase.Duration - layer.For)).toBeLessThanOrEqual(0.01)
					end
				end
			end
			expect(carriers).toBe(1)
		end
		local handler = body("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Colophon = function(")
		for _, line in ipairs({
			'local muzzle = packet.Origin + directionOf(packet) * numberParam(packet, "SpawnOffset", 0)',
			'Reach = if struck then toFirst.Magnitude else math.max(numberParam(packet, "Range", def.Range), 1),',
			"for index = 1, #points - 1 do",
			"local from, to = points[index], points[index + 1]",
			"Origin = from, Direction = jump.Unit,",
			"Reach = jump.Magnitude,",
		}) do
			if handler:find(line, 1, true) == nil then
				error("VfxLibrary.Colophon no longer plays the chain the server struck: " .. line)
			end
		end
	end)

	it("presses the Watermark's mould on each of the server's ticks, inside an edge at its radius", function()
		local params = GlyphConfig.ById.Watermark.Params :: any
		local lead = phaseLength("Watermark", "Anticipation") + phaseLength("Watermark", "Cast")
		local presses: { [number]: number } = {}
		local edge = false
		for _, phase in ipairs(TIMELINES.Watermark.Phases) do
			if phase.Name == "Impact" then
				for _, layer in ipairs(phase.Layers) do
					if layer.Texture == "SealRing" and layer.Role == "Ink" then
						edge = layer.SizeFrom == "Radius"
							and layer.EndSize == 2
							and layer.At + layer.For >= (params.Ticks - 1) * params.TickInterval
					elseif layer.Texture == "SealRing" then
						expect(layer.SizeFrom).toBe("Radius")
						local tick = math.floor((layer.At + lead) / params.TickInterval + 0.5)
						expect(math.abs(layer.At + lead - tick * params.TickInterval)).toBeLessThanOrEqual(0.035)
						presses[tick] = (presses[tick] or 0) + 1
					end
				end
			end
		end
		expect(edge).toBe(true)
		for tick = 0, params.Ticks - 1 do
			expect(presses[tick]).toBe(1)
		end
	end)

	it("wears the Gilding's armour on the body for as long as the server gives it", function()
		-- D-125: the four seconds were brush-textured trails (smudges), after an act that waited 0.38 s.
		local seconds = CombatConfig.Status.Gilding.DurationSeconds
		local offset, total, worn = 0, 0, 0
		for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
			for _, phase in ipairs(TIMELINES.Gilding.Phases) do
				if phase.Name == name then
					for _, layer in ipairs(phase.Layers) do
						if layer.Follow == true and layer.Kind == "Emitter" and layer.Rate ~= nil then
							worn = math.max(worn, offset + layer.At + layer.For)
						end
					end
					offset += phase.Duration
				end
			end
		end
		total = offset
		expect(math.abs(total - seconds)).toBeLessThanOrEqual(0.05)
		expect(worn >= seconds - 0.2).toBe(true)
		-- And the figure itself, drawn round the body for the whole of it: flakes alone vanished into it.
		local figure = 0
		offset = 0
		for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
			for _, phase in ipairs(TIMELINES.Gilding.Phases) do
				if phase.Name == name then
					for _, layer in ipairs(phase.Layers) do
						if layer.Kind == "Outline" then
							figure = math.max(figure, offset + layer.At + layer.For)
						end
					end
					offset += phase.Duration
				end
			end
		end
		expect(figure >= seconds - 0.05).toBe(true)
		local outline = body(TIMELINE, "local function buildOutline(")
		expect(outline:find("highlight.DepthMode = Enum.HighlightDepthMode.Occluded", 1, true)).never.toBe(nil)
		expect(outline:find("highlight.OutlineColor = INK_COLOR", 1, true)).never.toBe(nil)
		for _, phase in ipairs(TIMELINES.Gilding.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == "Trail" then
					error("the Gilding wears a trail again: a brush-textured ribbon is a smudge (D-119)")
				end
			end
		end
	end)

	it("raises the Margin's ink with the server's slab, not after it", function()
		local rise = phaseLength("Margin", "Anticipation") + phaseLength("Margin", "Cast")
		expect(math.abs(rise - WorldConfig.Glyphs.WallRiseSeconds)).toBeLessThanOrEqual(0.05)
	end)

	it("strikes each of the Bleed's drinks on the server's tick, at the radius it drinks from", function()
		local params = GlyphConfig.ById.Bleed.Params :: any
		local spikes = {}
		for _, phase in ipairs(TIMELINES.Bleed.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Texture == "InkSpike" then
					table.insert(spikes, layer.At)
				end
			end
		end
		expect(#spikes).toBe(params.Ticks)
		table.sort(spikes)
		for index, at in ipairs(spikes) do
			expect(at).toBe((index - 1) * params.TickInterval)
		end
		local bleed = body("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Bleed = function(")
		expect(bleed:find('Radius = numberParam(packet, "Radius", 9),', 1, true)).never.toBe(nil)
	end)

	it("flies the Blot on the server's own arc and lands it where it burst", function()
		-- It left 0.28 s late and flew faster and lower than the meteor that burns (D-123).
		local def = GlyphConfig.ById.Blot
		local params = def.Params :: any
		local lead = phaseLength("Blot", "Anticipation") + phaseLength("Blot", "Cast")
		local carrier: any = nil
		for _, phase in ipairs(TIMELINES.Blot.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Kind == "Carrier" then
					carrier = layer
				end
			end
		end
		expect(carrier).never.toBe(nil)
		expect(math.abs(carrier.For + lead - params.Fuse)).toBeLessThanOrEqual(0.05)
		expect(math.abs(carrier.Travel / carrier.For - params.Speed) / params.Speed).toBeLessThanOrEqual(0.05)
		expect(carrier.Arc).toBe(params.ArcHeight)
		expect(math.abs(carrier.Offset[3] - (params.SpawnOffset + params.Speed * lead))).toBeLessThanOrEqual(1)
		-- Named like the Brand's, so its burst lands the drawn one; the shared player passes the name on.
		local blot = body("src/server/Effects/GlyphEffects.luau", "function GlyphEffects.Blot(")
		expect(blot:find("local shot = nextShot()", 1, true)).never.toBe(nil)
		expect(blot:find("Shot = shot,", 1, true)).never.toBe(nil)
		expect(blot:find("params.Knockback, params.Lift, shot)", 1, true)).never.toBe(nil)
		expect(blot:find('Id = "Fizzle"', 1, true)).never.toBe(nil)
		local play = body("src/client/Controllers/VfxLibrary.luau", "local function playGlyph(")
		expect(play:find("Shot = shotKey(packet),", 1, true)).never.toBe(nil)
	end)

	it("strikes the Binding's prison round the one it caught, for as long as the root", function()
		local params = GlyphConfig.ById.Binding.Params :: any
		local bars = 0
		for _, phase in ipairs(TIMELINES.Binding.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Texture == "InkSpike" then
					bars += 1
					expect(math.abs(layer.At + layer.For - params.RootDuration)).toBeLessThanOrEqual(0.05)
				end
			end
		end
		expect(bars).toBeGreaterThanOrEqual(3)
		local binding = body("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Binding = function(")
		expect(binding:find('Origin = if typeof(caught) == "Vector3" then caught else packet.Origin,', 1, true)).never.toBe(
			nil
		)
	end)

	it("spreads the Ligature's pools where the server laid them before its first tick is a tenth old", function()
		local params = GlyphConfig.ById.Ligature.Params :: any
		local lead = phaseLength("Ligature", "Anticipation")
		local pools: { number } = {}
		for _, phase in ipairs(TIMELINES.Ligature.Phases) do
			if phase.Name == "Travel" then
				for _, layer in ipairs(phase.Layers) do
					if layer.Kind == "Mark" and layer.At + lead <= 0.12 then
						table.insert(pools, (layer.Offset :: { number })[3])
					end
				end
			end
		end
		table.sort(pools)
		expect(#pools).toBe(params.TrailSegments)
		for index, z in ipairs(pools) do
			expect(z).toBe((index - 1) * params.TrailSpacing)
		end
	end)
end)
