--!strict
-- What every effect in the game costs a client, computed from the data that draws it.
--
-- `lune run scripts/effect-cost` prints the table docs/PERFORMANCE.md quotes, and
-- tests/EffectCost.spec.luau holds every number below its ceiling on each run of the gates. Nothing here
-- is measured on a device: these are the instances the renderer WILL borrow and the particles it WILL ask
-- for, which is the half of the cost the repository can know exactly. What a frame then takes is the half
-- only a device can answer, and docs/PERFORMANCE.md says so rather than inventing it.
--
-- Per timeline: its layers, the instances each layer kind borrows from the pool, the particles emitted
-- (a burst, plus a rate over the layer's own life), and the peak number of layers alive at the same time,
-- which is what the live-layer budget of QualityConfig is spent on.

local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local process = require("@lune/process")

type Cost = {
	Id: string,
	Layers: number, -- every layer, including the three kinds that occupy no slot
	Drawn: number, -- the layers that take a slot of the live budget
	Peak: number, -- the most of those alive at the same instant
	Seconds: number,
	Particles: number,
	-- Peak CONCURRENT borrows per pool class, which is what a pool ceiling is about: a lifetime total
	-- compared against a concurrency ceiling compares two different things.
	Instances: { [string]: number },
}

-- What one layer of each kind borrows from VfxPool. Kept beside the renderer's own borrows
-- (src/client/Controllers/VfxTimeline.luau): a Sprite is a part carrying two decals so it reads from both
-- sides, a Mark is a part carrying one, an Emitter is a part carrying an emitter, a Trail is a part with
-- two attachments and the trail between them, a Beam is two attachments and the beam.
local BORROWS: { [string]: { [string]: number } } = {
	Sprite = { Part = 1, Decal = 2 },
	Mark = { Part = 1, Decal = 1 },
	Emitter = { Part = 1, ParticleEmitter = 1 },
	Trail = { Part = 1, Attachment = 2, Trail = 1 },
	-- Two parts: a beam is drawn between an attachment at each end, and each end is its own host.
	Beam = { Part = 2, Attachment = 2, Beam = 1 },
	Light = { Part = 1, PointLight = 1 },
	Carrier = { Part = 1 },
	-- A shake, a flash and a sound borrow nothing and never enter the live list: they are handed to Feel,
	-- WorldLighting and SoundController and never come back (VfxTimeline.activate returns early).
	Shake = {},
	Flash = {},
	Sound = {},
}

-- The kinds that occupy a slot of the live-layer budget. Counting the other three in a peak overstated
-- twenty-six of the thirty-five timelines against the very budget the peak is compared to.
local OCCUPIES: { [string]: boolean } = {
	Sprite = true,
	Mark = true,
	Emitter = true,
	Trail = true,
	Beam = true,
	Light = true,
	Carrier = true,
}

local function phaseSeconds(phase: any): number
	-- A windowed phase is as long as the packet says; the longest window the config allows is what a cost
	-- has to be measured against, because that is the frame where the most is on screen at once.
	return VfxTimelineConfig.phaseSeconds(phase, VfxTimelineConfig.MaxWindowSeconds)
end

type Span = { At: number, Until: number, Kind: string }

local function costOf(id: string, timeline: any): Cost
	local particles = 0
	local layers = 0
	-- Every layer that takes a slot, in the timeline's own clock, so the peak and the borrows at the peak
	-- are measured at the same instants.
	local spans: { Span } = {}
	local offset = 0

	for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == name then
				local seconds = phaseSeconds(phase)
				local factor = if phase.Window == true then seconds else 1
				for _, layer in ipairs(phase.Layers) do
					layers += 1
					local at = offset + layer.At * factor
					local for_ = layer.For * factor
					if OCCUPIES[layer.Kind] then
						table.insert(spans, { At = at, Until = at + for_, Kind = layer.Kind })
					end
					if layer.Burst ~= nil then
						particles += layer.Burst
					end
					if layer.Rate ~= nil then
						particles += layer.Rate * for_
					end
				end
				offset += seconds
			end
		end
	end

	-- The peak, and what is borrowed there: walk every start and measure the set alive at that instant.
	local peak = 0
	local instances: { [string]: number } = {}
	for _, span in ipairs(spans) do
		local alive = 0
		local borrowed: { [string]: number } = {}
		for _, other in ipairs(spans) do
			if other.At <= span.At and other.Until > span.At then
				alive += 1
				for class, count in pairs(BORROWS[other.Kind] or {}) do
					borrowed[class] = (borrowed[class] or 0) + count
				end
			end
		end
		peak = math.max(peak, alive)
		for class, count in pairs(borrowed) do
			instances[class] = math.max(instances[class] or 0, count)
		end
	end

	return {
		Id = id,
		Layers = layers,
		Drawn = #spans,
		Peak = peak,
		Seconds = offset,
		Particles = particles,
		Instances = instances,
	}
end

local CostReport = {}

-- Exposed so tests/EffectCost.spec.luau can hold this set against the renderer's own early returns: a kind
-- listed here that the renderer hands off (or missing here while the renderer draws it) makes every peak in
-- the report wrong in one direction or the other.
CostReport.Occupies = OCCUPIES

-- Every timeline's cost, sorted by id.
function CostReport.all(): { Cost }
	local out: { Cost } = {}
	for id, timeline in pairs(VfxTimelineConfig.Timelines) do
		table.insert(out, costOf(id, timeline))
	end
	table.sort(out, function(a: Cost, b: Cost): boolean
		return a.Id < b.Id
	end)
	return out
end

function CostReport.instanceTotal(cost: Cost): number
	local total = 0
	for _, count in pairs(cost.Instances) do
		total += count
	end
	return total
end

local CLASSES = { "Part", "Decal", "ParticleEmitter", "Attachment", "Trail", "Beam", "PointLight" }

-- Printed as a Markdown table, so docs/PERFORMANCE.md quotes what this produced rather than a number
-- somebody remembered.
local function report()
	local costs = CostReport.all()
	print(
		"| Effet | Couches | Dessinées | Pic simultané | Durée (s) | Particules | Instances au pic | Part | Decal | Emitter | Attach | Trail | Beam | Light |"
	)
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	local worstLayers, worstParticles, worstInstances = 0, 0, 0
	local totalLayers = 0
	local totalDrawn = 0
	for _, cost in ipairs(costs) do
		local row = { cost.Id, tostring(cost.Layers), tostring(cost.Drawn), tostring(cost.Peak) }
		table.insert(row, string.format("%.2f", cost.Seconds))
		table.insert(row, string.format("%d", math.floor(cost.Particles + 0.5)))
		table.insert(row, tostring(CostReport.instanceTotal(cost)))
		for _, class in ipairs(CLASSES) do
			table.insert(row, tostring(cost.Instances[class] or 0))
		end
		print("| " .. table.concat(row, " | ") .. " |")
		worstLayers = math.max(worstLayers, cost.Peak)
		worstParticles = math.max(worstParticles, cost.Particles)
		worstInstances = math.max(worstInstances, CostReport.instanceTotal(cost))
		totalLayers += cost.Layers
		totalDrawn += cost.Drawn
	end
	print("")
	print(
		("%d timelines et %d couches, dont %d qui prennent une place du budget."):format(
			#costs,
			totalLayers,
			totalDrawn
		)
	)
	print(
		("Pire effet : %d couches vivantes au même instant, %d particules, %d instances empruntées au pic."):format(
			worstLayers,
			math.floor(worstParticles + 0.5),
			worstInstances
		)
	)
	print(
		("Budget de couches : %d (QualityConfig.Tiers.High.Layers), soit %.1f fois le pire effet à la fois."):format(
			VfxTimelineConfig.MaxLiveLayers,
			VfxTimelineConfig.MaxLiveLayers / math.max(worstLayers, 1)
		)
	)
end

-- Printed only when asked, because tests/EffectCost.spec.luau requires this file for its numbers and a
-- gate that prints forty lines of table is a gate nobody reads.
for _, argument in ipairs(process.args) do
	if argument == "--table" then
		report()
		break
	end
end

return CostReport
