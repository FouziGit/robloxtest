--!strict
-- The style the effects were rebuilt in, seen in the Studio lab before it was written down (D-119): live
-- ink with a heated core. Each rule here is one the lab showed breaking an effect -- a pale core alone on a
-- pale page, a freeze frame that let a projectile fall behind its damage, a spell that appeared a round
-- trip after the press -- and each is held on the data and on the renderer's own source.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
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
		expect(emitter:find("emitter.Brightness = brightnessOf(layer)", 1, true)).never.toBe(nil)
		expect(emitter:find("emitter.LightEmission = glowOf(layer)", 1, true)).never.toBe(nil)
		expect(body(TIMELINE, "local function buildTrail("):find("trail.Brightness = brightnessOf(layer)", 1, true)).never.toBe(
			nil
		)
		expect(body(TIMELINE, "local function buildBeam("):find("beam.Brightness = brightnessOf(layer)", 1, true)).never.toBe(
			nil
		)
		-- The same switch Feel and the page flash ask: one question, one answer.
		expect(read("src/client/Controllers/Feel.luau"):find("Feel.motionAllowed = motionAllowed", 1, true)).never.toBe(
			nil
		)
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
		local _, handed = library:gsub("Hand = casterHand%(packet%),", "")
		expect(handed).toBe(2)
		local anchored = 0
		for _, phase in ipairs(TIMELINES.Brand.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Anchor == "Hand" then
					anchored += 1
				end
			end
		end
		expect(anchored).toBeGreaterThanOrEqual(4)
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
