--!strict
-- An ink contour is never drawn over a body that is not opaque (D-280).
--
-- Found playing the place: the Emboss read as a solid black ring and the Dagger's strike-out as a black bar. A
-- body form is three volumes -- pigment, core, ink -- and the ink is an inverted hull around the pigment. Opaque,
-- the two sort and the hull reads as a contour; but Roblox does not sort two transparent parts that share a
-- centre, so while the pigment fades in or out the hull is drawn over it, and the body is black. Nearly every
-- body fades its ink with its pigment, link for link, so nearly every body went black as it faded.
--
-- The renderer holds the rule (VolumeMath.drawnTransparency): an ink volume is drawn only while the body it
-- outlines is drawn opaque. Held here on every timeline, by the runtime's own arithmetic: each volume's
-- transparency as VfxVolumes.step computes it (the layer's ease, FeelMath.layerFade, its lerp), the body the
-- runtime gives each ink (VfxTimelineConfig.contours), and the rule; checked against the body form each ink
-- belongs to as an author reads it -- the pigment of its mesh family that starts with it.
local Easing = require("./easing")
local FeelMath = require("../src/shared/Pure/FeelMath")
local Harness = require("./harness")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local VolumeMath = require("../src/shared/Pure/VolumeMath")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Pigment, by the runtime's reading of a Mesh layer's Role.
local function roleOf(layer: any): string
	return layer.Role or "Pigment"
end

-- The family a mesh belongs to: an ink mesh is its family's name and "Ink" (StippleInk, CaretWideInk).
local function familyOf(inkMesh: string): string
	return (inkMesh:gsub("Ink$", ""))
end

type Link = { Start: number, Seconds: number, Layer: any, Index: number }
type Volume = { Role: string, Mesh: string, Start: number, Phase: string, At: number, Links: { Link } }

-- Every volume of a timeline as the runtime draws it: a layer with no Chain is one, a Chain is one handed from
-- link to link. Times are on the timeline's clock at its default window, links in the order they start; layer
-- numbers as VfxTimeline.play counts them.
local function volumesOf(id: string): ({ Volume }, { [number]: Volume })
	local timeline = VfxTimelineConfig.Timelines[id]
	local out: { Volume } = {}
	local byIndex: { [number]: Volume } = {}
	local byChain: { [string]: Volume } = {}
	local start, index = 0, 0
	for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == name then
				local seconds = VfxTimelineConfig.phaseSeconds(phase, nil)
				local factor = if phase.Window == true then seconds else 1
				for _, layer in ipairs(phase.Layers) do
					index += 1
					if layer.Kind == "Mesh" then
						local link = {
							Start = start + layer.At * factor,
							Seconds = layer.For * factor,
							Layer = layer,
							Index = index,
						}
						local chain = layer.Chain
						local volume = if chain ~= nil then byChain[chain] else nil
						if volume == nil then
							volume = {
								Role = roleOf(layer),
								Mesh = layer.Mesh,
								Start = link.Start,
								Phase = phase.Name,
								At = layer.At,
								Links = {},
							}
							table.insert(out, volume :: Volume)
							if chain ~= nil then
								byChain[chain] = volume
							end
						end
						table.insert((volume :: Volume).Links, link)
						byIndex[index] = volume :: Volume
					end
				end
				start += seconds
			end
		end
	end
	return out, byIndex
end

-- A link's transparency `elapsed` of the way through it, as VfxVolumes.step computes it: its ease
-- (VfxTimeline's eased, TweenService's curves), FeelMath.layerFade, and the lerp with 0 for what it leaves out.
local function own(layer: any, elapsed: number): number
	local alpha = if layer.Ease ~= nil then Easing.value(layer.Ease, layer.EaseDirection or "Out", elapsed) else elapsed
	local from: number = layer.Transparency or 0
	local to: number = layer.EndTransparency or from
	local fade = FeelMath.layerFade(from, to, elapsed, alpha, layer.FadesWithSize == true)
	local finish: number? = layer.EndTransparency
	local value = if finish == nil then from else from + (finish - from) * fade
	return math.clamp(value, 0, 1)
end

-- What `volume` asks for at `t`, or nil when it is not on screen then.
local function ownAt(volume: Volume, t: number): number?
	for _, link in ipairs(volume.Links) do
		if t >= link.Start - 1e-9 and t < link.Start + link.Seconds then
			return own(link.Layer, (t - link.Start) / link.Seconds)
		end
	end
	return nil
end

local function finishOf(volume: Volume): number
	local last = volume.Links[#volume.Links]
	return last.Start + last.Seconds
end

-- The pigment volume of `ink`'s body form: of its mesh family, starting with it.
local function formBody(volumes: { Volume }, ink: Volume): Volume?
	local family = familyOf(ink.Mesh)
	for _, volume in ipairs(volumes) do
		if
			volume.Role == "Pigment"
			and volume.Mesh:sub(1, #family) == family
			and math.abs(volume.Start - ink.Start) < 1e-6
		then
			return volume
		end
	end
	return nil
end

local function sortedIds(): { string }
	local ids: { string } = {}
	for id in pairs(VfxTimelineConfig.Timelines) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local SAMPLE = 1 / 240

describe("an ink contour", function()
	it("is drawn only over an opaque body, and opaque below a hair of transparency", function()
		expect(VolumeMath.drawnTransparency(0.01, nil)).toBe(0)
		expect(VolumeMath.drawnTransparency(0.3, nil)).toBe(0.3)
		expect(VolumeMath.drawnTransparency(0, 0)).toBe(0)
		expect(VolumeMath.drawnTransparency(0.4, 0)).toBe(0.4)
		expect(VolumeMath.drawnTransparency(0, 0.05)).toBe(1)
		expect(VolumeMath.drawnTransparency(0, 1)).toBe(1)
		expect(VolumeMath.drawnTransparency(0 / 0, nil)).toBe(1)
		expect(VolumeMath.drawnTransparency(1.5, nil)).toBe(1)
	end)

	it("is given the body of its form, in every timeline", function()
		local paired, failures = 0, {}
		for _, id in ipairs(sortedIds()) do
			local volumes, byIndex = volumesOf(id)
			local contours = VfxTimelineConfig.contours(id)
			for _, ink in ipairs(volumes) do
				if ink.Role == "Ink" then
					local head = ink.Links[1].Index
					local given = contours[head]
					local body = formBody(volumes, ink)
					local where = ("%s: %s at %.2f s"):format(id, ink.Mesh, ink.Start)
					if body == nil then
						-- A stroke of ink alone (the Brand's crescent): no pigment of its family starts with it.
						if given ~= nil then
							table.insert(failures, where .. " is given a body although none of its form starts with it")
						end
					elseif given == nil or byIndex[given] ~= body then
						table.insert(failures, where .. " is not given " .. body.Mesh .. ", the pigment of its form")
					else
						paired += 1
					end
				end
			end
		end
		if #failures > 0 then
			error("\n" .. table.concat(failures, "\n"))
		end
		-- Non-vacuous: the twenty-six glyph bodies and their links.
		expect(paired).toBeGreaterThanOrEqual(40)
	end)

	it("is never drawn over its body while that body is not opaque", function()
		local failures: { string } = {}
		local checked = 0
		for _, id in ipairs(sortedIds()) do
			local volumes, byIndex = volumesOf(id)
			local contours = VfxTimelineConfig.contours(id)
			for _, ink in ipairs(volumes) do
				local body = if ink.Role == "Ink" then formBody(volumes, ink) else nil
				if body ~= nil then
					local given = contours[ink.Links[1].Index]
					local runtimeBody = if given ~= nil then byIndex[given] else nil
					local finish = finishOf(ink)
					local worst: string? = nil
					local t = ink.Start
					while t < finish do
						local inkOwn, bodyOwn = ownAt(ink, t), ownAt(body, t)
						if inkOwn ~= nil and bodyOwn ~= nil then
							checked += 1
							local pigment = VolumeMath.drawnTransparency(bodyOwn, nil)
							-- The body the runtime reads, at this frame or as it was last drawn.
							local under: number? = nil
							if runtimeBody ~= nil then
								local at = ownAt(runtimeBody, t)
									or ownAt(runtimeBody, finishOf(runtimeBody) - 1e-6)
									or 0
								under = VolumeMath.drawnTransparency(at, nil)
							end
							local contour = VolumeMath.drawnTransparency(inkOwn, under)
							if pigment > 0.02 and contour < 0.98 and worst == nil then
								worst = ("%s: %s drawn at %.2f over %s at %.2f, %.2f s in"):format(
									id,
									ink.Mesh,
									contour,
									body.Mesh,
									pigment,
									t
								)
							end
						end
						t += SAMPLE
					end
					if worst ~= nil then
						table.insert(failures, worst)
					end
				end
			end
		end
		expect(checked).toBeGreaterThan(1000)
		if #failures > 0 then
			error("\n" .. table.concat(failures, "\n"))
		end
	end)

	it("is wired so: the play hands each ink its body, which it reads after the body has drawn", function()
		local function code(path: string): string
			return ((fs.readFile(path):gsub("%-%-[^\n]*", "")):gsub("%s+", " "))
		end
		local timeline = code("src/client/Controllers/VfxTimeline.luau")
		local volumes = code("src/client/Controllers/VfxVolumes.luau")
		local function has(source: string, fragment: string): boolean
			return source:find(fragment, 1, true) ~= nil
		end
		expect(has(timeline, "local contours = VfxTimelineConfig.contours(id)")).toBe(true)
		expect(has(timeline, "Body = contours[layerIndex],")).toBe(true)
		expect(
			has(
				timeline,
				"if other.PlayId == item.PlayId and other.LayerIndex == outlined and other.Volume ~= nil then volume.Body = other.Volume"
			)
		).toBe(true)
		-- Stepped after every body: the transparency it reads is this frame's.
		expect(has(timeline, "if volume ~= nil and volume.Body ~= nil then table.insert(contours, entry) else")).toBe(
			true
		)
		expect(
			has(
				timeline,
				"for _, entry in ipairs(contours) do local now = if entry.Steady then steadyNow else heldNow stepLive("
			)
		).toBe(true)
		-- The one transparency a volume's part is given each frame, after a landing's splat.
		local stepStart = volumes:find("function VfxVolumes.step(", 1, true) :: number
		local step = volumes:sub(stepStart, volumes:find(" end function ", stepStart, true) :: number)
		expect(
			has(
				step,
				"local drawn = VolumeMath.drawnTransparency(transparency, if body ~= nil then body.Drawn else nil) volume.Drawn = drawn part.Transparency = drawn"
			)
		).toBe(true)
		local writes = 0
		for _ in step:gmatch("part%.Transparency = ") do
			writes += 1
		end
		expect(writes).toBe(1)
		local splatted = step:find("transparency = ending.From", 1, true) :: number
		local drawn = step:find("local drawn =", 1, true) :: number
		expect(splatted < drawn).toBe(true)
	end)
end)
