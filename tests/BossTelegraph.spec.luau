--!strict
-- L'Effacement is the only thing in Vellum that hits six players at once, and its warnings are the only
-- visuals in the game that are rules rather than decoration: a player reads the paint on the floor and
-- decides where to stand. Which makes one class of bug uniquely expensive -- paint that does not match the
-- damage -- and it is invisible from a screenshot, because a wedge drawn at nine tenths of its true width
-- looks exactly like a wedge.
--
-- So the shapes are checked here against the numbers WorldBossConfig actually ships, by sampling the floor
-- the server will damage (WorldBossMode.isInShape, quoted in each case below) and asking whether anything
-- is painted over it. Under-covering fails: the one thing a warning may never do is tell somebody they are
-- outside it. Over-covering is allowed and says so -- a rectangle laid along a wedge has corners.
--
-- It also holds the two clocks together: the phase whose length comes from the packet must resolve to the
-- window the server is really waiting, unclamped, for every attack in every phase of the fight, and the
-- Impact phase must begin at the end of it. That is what makes the hit land when it is shown to land.
local AssetIds = require("../src/shared/Config/AssetIds")
local Harness = require("./harness")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Layer = VfxTimelineConfig.Layer

-- The companion timeline played beside BossEruption for its safe centre, in the one colour on that floor
-- that does not mean danger. It is not a packet id (the server never sends it), so no other test sees it.
local SAFE_ID = "BossEruptionSafe"
-- Which timelines paint which of the server's three shapes. Every attack has to be in the row for its
-- own Shape, and every row has to be non-empty: the shape tests below are guarded on Shape, and a guard
-- that stopped matching would otherwise pass every one of them without measuring anything.
local PAINTS: { [string]: { [string]: boolean } } = {
	Circle = { BossSlam = true, BossFury = true },
	Cone = { BossSweep = true },
	Ring = { BossEruption = true },
}
local EPSILON = 1e-6
-- Two pixels of a 512-texture on the plane, in half-widths: the rim of a telegraph texture is anti-aliased
-- over about that, and it is the whole tolerance a warning gets in either direction -- a sixth of a stud
-- on the largest attack.
local PIXEL = 2 / 256
-- A warning has to be readable on its first frame, not only on its last: the fill accelerates toward the
-- hit (Quad in), and a mark that starts at 0.95 transparency spends half its window invisible.
local MAX_START_TRANSPARENCY = 0.8
-- How much of the warning the paint has to be up for. Not the whole of it: the Sweep paints its wedge
-- outward with a stagger, which is what makes the direction readable before the shape is finished, so its
-- far segments arrive a fifth of the way in.
local MAX_PAINT_START = 0.35

local function timelineOf(id: string): VfxTimelineConfig.Timeline
	local timeline = VfxTimelineConfig.Timelines[id]
	if timeline == nil then
		error(("no timeline named %s; the World Boss renders through Timelines"):format(id))
	end
	return timeline
end

local function windowedPhase(id: string): VfxTimelineConfig.Phase
	for _, phase in ipairs(timelineOf(id).Phases) do
		if phase.Window == true then
			return phase
		end
	end
	error(("timeline %s has no phase whose length comes from the packet"):format(id))
end

-- The layers a warning is actually made of: a mark whose size does not change (so the travelling clock is
-- not mistaken for the paint), up early enough to be read, and still there when the hit lands.
local function steadyMarks(phase: VfxTimelineConfig.Phase): { Layer }
	local marks: { Layer } = {}
	for _, layer in ipairs(phase.Layers) do
		local moves = layer.EndSize ~= nil and layer.EndSize ~= layer.Size
		if layer.Kind == "Mark" and not moves and layer.At <= MAX_PAINT_START and layer.At + layer.For >= 0.999 then
			table.insert(marks, layer)
		end
	end
	return marks
end

-- How far the ink of `layer`'s texture reaches, in half-widths, in the direction it reaches least and the
-- direction it reaches most. A plane is sized to its edge; a player reads the alpha. A layer with no
-- texture is a bare plate and paints its whole square; a texture with no measurement is a texture no
-- warning may be drawn with.
local function inkOf(layer: Layer): (number, number)
	local key = layer.Texture
	if key == nil then
		return 1, math.sqrt(2)
	end
	local asset = AssetIds.Textures[key]
	if asset == nil or asset.Ink == nil then
		error(
			("texture %s carries no ink measurement, so nothing can be proven about a warning drawn with it"):format(
				key
			)
		)
	end
	return asset.Ink.Least, asset.Ink.Most
end

-- Studs from the centre of the effect to the edge of what `layer` really paints: the plane's half-width,
-- which Size measures, times how far the texture's ink reaches across it. `least` asks for the direction
-- the ink reaches least (what a warning covers); otherwise the direction it reaches most (what a refuge
-- promises).
local function paintedHalfWidth(layer: Layer, radius: number, reach: number, least: boolean): number
	local size = layer.Size or 0
	local measure = layer.SizeFrom
	if measure == nil then
		-- Authored in studs. Legal, but it cannot follow a radius the server changed, so it is not counted
		-- as covering anything.
		return 0
	end
	local inkLeast, inkMost = inkOf(layer)
	return size * (if measure == "Radius" then radius else reach) / 2 * (if least then inkLeast else inkMost)
end

describe("the Erasure's telegraphs", function()
	it("warn for exactly as long as the server waits", function()
		-- The window is divided by the phase's AttackSpeed, so every attack has as many windows as the boss
		-- has phases, and the shortest and the longest both have to survive the clamp untouched. A clamp
		-- that bites is a warning that ends at a different moment from the hit.
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			local phase = windowedPhase(attack.VfxId)
			for index, definition in ipairs(WorldBossConfig.Phases) do
				local window = attack.TelegraphSeconds / definition.AttackSpeed
				local resolved = VfxTimelineConfig.phaseSeconds(phase, window)
				if math.abs(resolved - window) > EPSILON then
					error(
						("%s in fight phase %d warns for %.3fs and the timeline resolves %.3fs"):format(
							attack.Id,
							index,
							window,
							resolved
						)
					)
				end
				-- And the hit is drawn at the end of it, not at a time the renderer guessed.
				local impact = VfxTimelineConfig.phaseAt(attack.VfxId, "Impact", window)
				if impact == nil or math.abs(impact - window) > EPSILON then
					error(
						("%s lands at %.3fs and its Impact phase begins at %s"):format(
							attack.Id,
							window,
							tostring(impact)
						)
					)
				end
			end
		end
	end)

	it("fit inside the bounds the format declares", function()
		-- The ceiling exists because a windowed phase has to be budgeted at its worst case
		-- (VfxTimelineConfig.duration). This is the assertion that makes the number right rather than
		-- plausible: it is the longest warning the config can ask for.
		local longest = 0
		local shortest = math.huge
		local fastest = 1
		for _, definition in ipairs(WorldBossConfig.Phases) do
			fastest = math.max(fastest, definition.AttackSpeed)
		end
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			longest = math.max(longest, attack.TelegraphSeconds)
			shortest = math.min(shortest, attack.TelegraphSeconds / fastest)
		end
		expect(longest).toBeLessThanOrEqual(VfxTimelineConfig.MaxWindowSeconds)
		expect(shortest).toBeGreaterThanOrEqual(VfxTimelineConfig.MinWindowSeconds)
	end)

	it("paint each of the three shapes with a timeline written for it", function()
		local seen: { [string]: number } = { Circle = 0, Cone = 0, Ring = 0 }
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			local row = PAINTS[attack.Shape]
			if row == nil or not row[attack.VfxId] then
				error(("%s is a %s and %s is not written to paint one"):format(attack.Id, attack.Shape, attack.VfxId))
			end
			seen[attack.Shape] += 1
		end
		-- Each shape test below is guarded on the shape; this is what keeps those guards from all
		-- silently skipping.
		for shape, count in pairs(seen) do
			if count == 0 then
				error(("no attack is a %s, so its coverage test proves nothing"):format(shape))
			end
		end
	end)

	it("are readable from their first frame", function()
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			for _, layer in ipairs(steadyMarks(windowedPhase(attack.VfxId))) do
				if (layer.Transparency or 0) > MAX_START_TRANSPARENCY then
					error(
						("%s opens its warning at transparency %.2f, invisible for most of its window"):format(
							attack.Id,
							layer.Transparency or 0
						)
					)
				end
			end
		end
	end)

	it("paint at least the floor a Circle attack damages", function()
		-- "Circle: within Radius of the boss" (WorldBossMode.isInShape).
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			if attack.Shape == "Circle" then
				local widest = 0
				for _, layer in ipairs(steadyMarks(windowedPhase(attack.VfxId))) do
					widest = math.max(widest, paintedHalfWidth(layer, attack.Radius, attack.Range, true))
				end
				if widest + attack.Radius * PIXEL < attack.Radius then
					error(("%s damages %d studs and paints %.1f"):format(attack.Id, attack.Radius, widest))
				end
			end
		end
	end)

	it("paint at least the floor a Ring attack damages", function()
		-- "Ring: outside Radius -- the safe centre -- and within Range."
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			if attack.Shape == "Ring" then
				local widest = 0
				for _, layer in ipairs(steadyMarks(windowedPhase(attack.VfxId))) do
					widest = math.max(widest, paintedHalfWidth(layer, attack.Radius, attack.Range, true))
				end
				if widest + attack.Range * PIXEL < attack.Range then
					error(("%s reaches %d studs and paints %.1f"):format(attack.Id, attack.Range, widest))
				end
			end
		end
	end)

	it("never promise a safe place larger than it is", function()
		-- The one error in this file that kills people rather than startling them: a safe disc drawn wider
		-- than the server's safe radius tells a player standing in the danger that they are not. So the
		-- companion timeline's disc may be smaller than the real safe centre, never larger -- and not so
		-- much smaller that the only way out stops looking like a way out.
		local marks = steadyMarks(windowedPhase(SAFE_ID))
		expect(#marks).toBeGreaterThanOrEqual(1)
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			if attack.Shape == "Ring" then
				for _, layer in ipairs(marks) do
					-- The direction the ink reaches MOST: a square plate of page reaches 1.41 radii into
					-- the ring on its diagonals, and that is exactly what this must refuse.
					local painted = paintedHalfWidth(layer, attack.Radius, attack.Range, false)
					if painted > attack.Radius * (1 + PIXEL) then
						error(
							("%s is safe within %d studs and %s paints %.1f of it"):format(
								attack.Id,
								attack.Radius,
								SAFE_ID,
								painted
							)
						)
					end
					if paintedHalfWidth(layer, attack.Radius, attack.Range, true) < attack.Radius * 0.9 then
						error(("%s paints only %.1f of a %d-stud refuge"):format(SAFE_ID, painted, attack.Radius))
					end
				end
			end
		end
	end)

	it("paint at least the floor a Cone attack damages, the whole way out", function()
		-- "Cone: in front of it up to Range, inside a wedge that opens to Radius at that range and never
		-- closes below the body itself (hugging the boss is not a dodge)." The wedge is painted as
		-- rectangles laid end to end, so this samples the length rather than trusting the ends: a segment
		-- one notch too narrow is invisible to the eye and lethal to whoever is standing at its edge.
		local contact = WorldBossConfig.contactRadius()
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			if attack.Shape == "Cone" then
				local segments = steadyMarks(windowedPhase(attack.VfxId))
				expect(#segments).toBeGreaterThanOrEqual(2)
				local step = 0.25
				local distance = step
				while distance <= attack.Range do
					local trueHalf = math.max(attack.Radius * (distance / attack.Range), contact)
					local paintedHalf = 0
					for _, layer in ipairs(segments) do
						local span = layer.Span
						local offset = layer.Offset
						if span ~= nil and offset ~= nil and layer.SpanFrom ~= nil and layer.OffsetFrom ~= nil then
							local along = if layer.OffsetFrom == "Radius" then attack.Radius else attack.Range
							local depth = span * (if layer.SpanFrom == "Radius" then attack.Radius else attack.Range)
							local centre = offset[3] * along
							if
								distance >= centre - depth / 2 - EPSILON
								and distance <= centre + depth / 2 + EPSILON
							then
								paintedHalf =
									math.max(paintedHalf, paintedHalfWidth(layer, attack.Radius, attack.Range, true))
							end
						end
					end
					if paintedHalf + trueHalf * PIXEL < trueHalf then
						error(
							("%s damages %.1f studs either side at %.2f studs out, and paints %.1f"):format(
								attack.Id,
								trueHalf,
								distance,
								paintedHalf
							)
						)
					end
					distance += step
				end
			end
		end
	end)

	it("keep the bookends and the phase change out of the measuring", function()
		-- The spawn and the defeat damage nobody, so their renderer passes no shape and no window. A layer
		-- in one of them that measured itself against a radius would simply not be drawn -- the runtime
		-- skips it and warns once -- and the effect would look thinner for a reason nobody could see.
		for _, id in ipairs({ "BossSpawn", "BossPhase", "BossDefeated" }) do
			for _, phase in ipairs(timelineOf(id).Phases) do
				if phase.Window == true then
					error(("%s takes a window its renderer does not pass"):format(id))
				end
				for _, layer in ipairs(phase.Layers) do
					if layer.SizeFrom ~= nil or layer.SpanFrom ~= nil or layer.OffsetFrom ~= nil then
						error(("%s / %s measures itself against a shape nobody sends"):format(id, phase.Name))
					end
				end
			end
		end
	end)

	it("are played the way they are written", function()
		-- The other half of every assertion above: the data can be perfect and the renderer can still fail
		-- to hand it the two lengths it measures against, or forget the companion play that paints the only
		-- way out of an Eruption. VfxLibrary is a controller full of Roblox globals and cannot be required
		-- here, so its source is read, the way tests/EffectCoverage.spec.luau reads its own.
		local source = fs.readFile("src/client/Controllers/VfxLibrary.luau")
		local attacks = string.match(source, "local function playBossAttack.-\nend\n")
		if attacks == nil then
			error("VfxLibrary has no playBossAttack; this test is checking nothing")
		end
		for _, key in ipairs({ "Window = ", "Radius = ", "Reach = " }) do
			if string.find(attacks, key, 1, true) == nil then
				error(("playBossAttack passes no %sto the timeline it plays"):format(key))
			end
		end
		local events = string.match(source, "local function playBossEvent.-\nend\n")
		if events == nil then
			error("VfxLibrary has no playBossEvent; this test is checking nothing")
		end
		for _, key in ipairs({ "Window = ", "Radius = ", "Reach = " }) do
			if string.find(events, key, 1, true) ~= nil then
				error(("playBossEvent passes %swhich its timelines do not measure"):format(key))
			end
		end
		-- The safe play belongs to the Ring renderer and to no other: a refuge painted under a Slam is a
		-- refuge painted in the middle of a slam.
		local eruption = string.match(source, "VfxLibrary%.BossEruption = function.-\nend\n")
		if eruption == nil or string.find(eruption, '"' .. SAFE_ID .. '"', 1, true) == nil then
			error(("BossEruption does not play %s, so an Eruption paints no way out of itself"):format(SAFE_ID))
		end
		local others = string.gsub(source, "VfxLibrary%.BossEruption = function.-\nend\n", "")
		if string.find(others, 'play("' .. SAFE_ID .. '"', 1, true) ~= nil then
			error(("%s is played by a renderer that is not the Ring attack's"):format(SAFE_ID))
		end
	end)
end)
