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

local AuraMath = require("../src/shared/Pure/AuraMath")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local ParticleBudget = require("../src/shared/Pure/ParticleBudget")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local Strings = require("../src/shared/Strings")
local VfxConfig = require("../src/shared/Config/VfxConfig")
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
	-- A generated volume: a part carrying its mesh (VfxVolumes). A link of a Chain takes over the link
	-- before it and borrows nothing, and the two never overlap, so counting each is the same peak.
	Mesh = { Part = 1, SpecialMesh = 1 },
	-- Per scrap (costOf multiplies by the layer's Count): a part and its mesh.
	Debris = { Part = 1, SpecialMesh = 1 },
	-- A sketch of a body: a part and a mesh per limb (VfxConfig.Afterimage names fifteen), in one model
	-- drawn flat by one highlight.
	Afterimage = { Part = 15, SpecialMesh = 15, Model = 1, Highlight = 1 },
	-- A figure drawn round a body (D-125): one highlight, on the body the renderer passed.
	Outline = { Highlight = 1 },
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
	Mesh = true,
	Debris = true,
	Afterimage = true,
	Outline = true,
}

local function phaseSeconds(phase: any): number
	-- A windowed phase is as long as the packet says; the longest window the config allows is what a cost
	-- has to be measured against, because that is the frame where the most is on screen at once.
	return VfxTimelineConfig.phaseSeconds(phase, VfxTimelineConfig.MaxWindowSeconds)
end

type Span = { At: number, Until: number, Kind: string, Count: number }

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
						-- Occupied for as long as the renderer keeps it, which for an emitter includes the life
						-- of the particles it leaves in the air.
						local lives = VfxTimelineConfig.layerSeconds(layer, for_)
						if layer.Kind == "Afterimage" then
							-- A print waits for its body before it is laid (D-116): counted from its earliest
							-- possible start to its latest possible end, so the peak is the worst case.
							lives += VfxConfig.Afterimage.CeilingSeconds
						end
						table.insert(
							spans,
							{ At = at, Until = at + lives, Kind = layer.Kind, Count = layer.Count or 1 }
						)
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
					borrowed[class] = (borrowed[class] or 0) + count * other.Count
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

-- The most particles one effect may ask for over its life (tests/EffectCost.spec.luau). CHOSEN, not measured: no
-- device has run this game, and it is a ratchet against drift, the first number to replace with a measurement.
-- docs/PERFORMANCE.md quotes it with the worst effect beside it (ceilingLine below).
CostReport.ParticleCeiling = 400

-- The scene every tier's particle budget is held to (tests/ParticleBudget.spec.luau): six Scorches -- the most
-- particles alive of any glyph -- cast at once among six bodies wearing the heaviest aura and trail.
CostReport.Scene = { Plays = { "Scorch", "Scorch", "Scorch", "Scorch", "Scorch", "Scorch" }, Bodies = 6 }

----------------------------------------------------------------
-- A scene, frame by frame: the particles alive on one client
----------------------------------------------------------------

-- The particles a scene keeps alive on one screen, frame by frame, asked exactly as the renderers ask
-- (Pure/ParticleBudget, through VfxParticles): a timeline's burst at its start, a flow the renderer emits (Driven)
-- a frame at a time, an emitter the engine runs slowed to what fits and reserved for its life, and every body's
-- aura and trail a frame at a time within their share. What is alive is counted apart, each particle until the
-- top of its life: the budget has to hold THAT, not the ledger it keeps.
export type SceneOptions = {
	-- Timelines played at once, after the worn looks have run a second.
	Plays: { string },
	-- Bodies wearing the heaviest aura and the heaviest trail, walking; the first is the local player's.
	Bodies: number,
	Tier: string,
	-- Whether the local player fights (CosmeticConfig.Fight): the worn looks step back.
	Fighting: boolean,
	-- The budget asked against; the tier's own when absent, math.huge for the scene as authored.
	Budget: number?,
	-- One kind of emission that skips the brake, as a renderer that forgot to ask would: "Burst", "Driven",
	-- "Rate" or "Worn". A gate proves each one is what keeps the scene under its budget.
	Unbraked: string?,
}

export type SceneResult = {
	-- The most particles alive at one frame, and the budget they were asked against.
	Peak: number,
	Budget: number,
	-- Everything the scene asked for over its life, and what it drew.
	Asked: number,
	Drawn: number,
	-- What the local player's own look asked for and drew: the look he put on, on his own screen.
	LocalAsked: number,
	LocalDrawn: number,
}

local FRAME = 1 / 60
local WARM_SECONDS = 1

-- A flow of one layer: the renderer's (Driven), owed a frame at a time, or the engine's, born one every 1 / Rate
-- seconds from its start (Next) as the engine emits it.
type Flow = { Rate: number, Carry: number, At: number, Until: number, Life: number, Engine: boolean, Next: number }

-- The flows of the heaviest look of `slot`: the one whose flows keep the most particles alive.
local function heaviestLook(slot: string, styles: { [string]: CosmeticConfig.Style }): { CosmeticConfig.Emission }
	local best: { CosmeticConfig.Emission } = {}
	local most = -1
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Slot == slot then
			local emissions: { CosmeticConfig.Emission } = {}
			local live = 0
			for _, name in ipairs(item.Look.Styles or {}) do
				local style = styles[name]
				for _, emission in ipairs(if style ~= nil then style.Emissions or {} else {}) do
					table.insert(emissions, emission)
					live += AuraMath.live(emission)
				end
			end
			if live > most then
				most = live
				best = emissions
			end
		end
	end
	return best
end

-- When an emitter layer of a play starts, what it is, and how long it emits.
type Start = { At: number, Layer: VfxTimelineConfig.Layer, Seconds: number }

-- Every emitter layer of `plays`, all cast after the warm-up, in the order they start; and when the last play ends.
local function emitterStarts(plays: { string }): ({ Start }, number)
	local starts: { Start } = {}
	local ends = WARM_SECONDS
	for _, id in ipairs(plays) do
		local timeline = VfxTimelineConfig.Timelines[id]
		assert(timeline ~= nil, "no timeline named " .. id)
		local offset = WARM_SECONDS
		for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
			for _, phase in ipairs(timeline.Phases) do
				if phase.Name == name then
					local seconds = VfxTimelineConfig.phaseSeconds(phase, VfxTimelineConfig.MaxWindowSeconds)
					local factor = if phase.Window == true then seconds else 1
					for _, layer in ipairs(phase.Layers) do
						if layer.Kind == "Emitter" then
							table.insert(
								starts,
								{ At = offset + layer.At * factor, Layer = layer, Seconds = layer.For * factor }
							)
						end
					end
					offset += seconds
				end
			end
		end
		ends = math.max(ends, WARM_SECONDS + VfxTimelineConfig.duration(timeline))
	end
	table.sort(starts, function(a: Start, b: Start): boolean
		return a.At < b.At
	end)
	return starts, ends
end

-- The worn flows of `bodies` bodies, each with the heaviest aura and trail, at the density this screen draws them
-- at, the longest life of each flow's particles, and whether each is the local player's own (the first body's).
local function wornFlows(
	bodies: number,
	tierName: string,
	fighting: boolean
): ({ AuraMath.Flow }, { number }, { boolean })
	local flows: { AuraMath.Flow } = {}
	local lives: { number } = {}
	local own: { boolean } = {}
	local looks = { heaviestLook("Aura", CosmeticConfig.AuraStyles), heaviestLook("Trail", CosmeticConfig.TrailStyles) }
	local floorTier = tierName == QualityConfig.Order[#QualityConfig.Order]
	local scale = QualityConfig.Tiers[tierName].ParticleScale
	for body = 1, bodies do
		local share = AuraMath.density(scale, body == 1, floorTier, fighting, CosmeticConfig.Fight.Density)
		if share > 0 then
			for _, look in ipairs(looks) do
				for _, emission in ipairs(look) do
					table.insert(flows, { Rate = emission.Rate * share, Carry = 0 })
					table.insert(lives, emission.Lifetime[2])
					table.insert(own, body == 1)
				end
			end
		end
	end
	return flows, lives, own
end

function CostReport.scene(options: SceneOptions): SceneResult
	local tier = QualityConfig.Tiers[options.Tier]
	assert(tier ~= nil, "no tier named " .. options.Tier)
	local budget = options.Budget or tier.Particles
	local unbraked = options.Unbraked
	local settings = QualityConfig.ParticleLedger
	local density = tier.ParticleScale
	local effects = ParticleBudget.ledger(settings.Step)
	local worn = ParticleBudget.ledger(settings.Step)
	-- What is really alive, apart from any ledger: the particles that die at each frame, by frame index.
	local alive = 0
	local deaths: { [number]: number } = {}
	local asked, drawn = 0, 0
	-- `count` particles born at `at` (at most this frame's time) living `life`: alive at every frame before the one
	-- their life ends at, where they are gone.
	local function born(at: number, count: number, life: number)
		local frame = math.ceil((at + life) / FRAME - 1e-9)
		deaths[frame] = (deaths[frame] or 0) + count
		alive += count
	end
	local function live(): number
		return effects.Live + worn.Live
	end
	-- Draws what the budget grants of `wanted` particles living `life`, counted in `ledger`; all of them, counted
	-- nowhere, for the kind that skips the brake. What a body wears asks within its share, the local player's own
	-- look (`own`) only what is left of the whole (VfxParticles.grantWorn). Returns how many it drew.
	local function emit(
		now: number,
		wanted: number,
		life: number,
		ledger: ParticleBudget.Ledger,
		kind: string,
		own: boolean?
	): number
		local granted = if unbraked == kind
			then math.floor(wanted)
			elseif kind == "Worn" and own ~= true then ParticleBudget.grant(
				wanted,
				ParticleBudget.wornRoom(budget, settings.WornShare, live(), worn.Live)
			)
			else ParticleBudget.grant(wanted, ParticleBudget.room(budget, live()))
		asked += wanted
		if granted <= 0 then
			return 0
		end
		drawn += granted
		if unbraked ~= kind then
			ParticleBudget.count(ledger, now, granted, life)
		end
		born(now, granted, life)
		return granted
	end

	local flows: { Flow } = {}
	-- A layer that starts (VfxTimeline.activate, then buildEmitter): its burst, then its flow, the renderer's or
	-- the engine's, the engine's slowed to what fits and reserved for as long as it can have particles alive.
	local function begin(start: Start, now: number)
		local layer = start.Layer
		local life = (layer.Lifetime or VfxTimelineConfig.DefaultParticleLifetime)[2]
		local burst = if layer.Burst ~= nil then math.max(1, math.floor(layer.Burst * density)) else 0
		local flowing = if layer.Rate ~= nil then layer.Rate * density * start.Seconds else 0
		if burst + flowing < 1 then
			return
		end
		if layer.Burst ~= nil then
			emit(now, burst, life, effects, "Burst")
		end
		if layer.Rate == nil then
			return
		end
		local rate = layer.Rate * density
		local engine = layer.Driven ~= true
		if not engine then
			-- The renderer's flow owes its tier's share of its rate (VfxTimeline.buildEmitter, D-229).
			rate *= QualityConfig.drivenShare(tier)
		end
		if engine then
			local allowed = if unbraked == "Rate"
				then rate
				else ParticleBudget.rate(rate, life, ParticleBudget.room(budget, live()))
			asked += rate * start.Seconds
			drawn += allowed * start.Seconds
			if unbraked ~= "Rate" then
				ParticleBudget.count(effects, now, ParticleBudget.held(allowed, life), start.Seconds + life)
			end
			rate = allowed
		end
		table.insert(flows, {
			Rate = rate,
			Carry = 0,
			At = now,
			Until = now + start.Seconds,
			Life = life,
			Engine = engine,
			Next = now,
		})
	end
	-- A flow's frame: the renderer's owes what its rate gave since the last (VfxTimeline.stepEmitter); an engine's
	-- is born here, one every 1 / Rate seconds, only to count what is alive.
	local function flowOn(flow: Flow, now: number)
		if flow.Engine then
			while flow.Rate > 0 and flow.Next <= now and flow.Next < flow.Until do
				born(flow.Next, 1, flow.Life)
				flow.Next += 1 / flow.Rate
			end
			return
		end
		local upTo = math.min(now, flow.Until)
		if upTo > flow.At then
			flow.Carry += (upTo - flow.At) * flow.Rate
			flow.At = upTo
			local count = math.floor(flow.Carry)
			if count > 0 then
				flow.Carry -= count
				emit(now, count, flow.Life, effects, "Driven")
			end
		end
	end

	local starts, ends = emitterStarts(options.Plays)
	local wearing, lives, own = wornFlows(options.Bodies, options.Tier, options.Fighting)
	local localAsked, localDrawn = 0, 0
	local nextStart = 1
	local peak = 0
	for frame = 0, math.ceil((ends + 1) / FRAME) do
		local now = frame * FRAME
		alive -= deaths[frame] or 0
		deaths[frame] = nil
		ParticleBudget.sweep(effects, now)
		ParticleBudget.sweep(worn, now)
		while starts[nextStart] ~= nil and starts[nextStart].At <= now do
			begin(starts[nextStart], now)
			nextStart += 1
		end
		for _, flow in ipairs(flows) do
			flowOn(flow, now)
		end
		-- What bodies wear (CosmeticController's emitFlow), within their share.
		for index, flow in ipairs(wearing) do
			local count = AuraMath.owed(flow, FRAME, CosmeticConfig.Flow.MaxStepSeconds)
			if count > 0 then
				local granted = emit(now, count, lives[index], worn, "Worn", own[index])
				if own[index] then
					localAsked += count
					localDrawn += granted
				end
			end
		end
		peak = math.max(peak, alive)
	end
	return {
		Peak = peak,
		Budget = budget,
		Asked = asked,
		Drawn = drawn,
		LocalAsked = localAsked,
		LocalDrawn = localDrawn,
	}
end

-- Exposed so tests/EffectCost.spec.luau can hold this set against the renderer's own early returns: a kind
-- listed here that the renderer hands off (or missing here while the renderer draws it) makes every peak in
-- the report wrong in one direction or the other.
CostReport.Occupies = OCCUPIES
CostReport.Borrows = BORROWS

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

-- A number as the French documents write it: a comma before the tenths.
local function decimal(value: number): string
	return (string.format("%.1f", value):gsub("%.", ","))
end

-- The row of docs/PERFORMANCE.md's ceilings table for the particles of one effect: the ceiling, how far above the
-- worst effect it stands, and which effect that is. Generated, so the document cannot keep a worst effect the
-- data has moved past (it said 201 for the Pounce while the Scorch asked for 358).
function CostReport.ceilingLine(costs: { Cost }): string
	local worst, worstId = 0, ""
	for _, cost in ipairs(costs) do
		if cost.Particles > worst then
			worst = cost.Particles
			worstId = cost.Id
		end
	end
	return ("| particules d'un effet | **choisi** : un cliquet contre la dérive, %s fois le pire effet | ≤ %d (pire : %d, `%s`) |"):format(
		decimal(CostReport.ParticleCeiling / math.max(worst, 1)),
		CostReport.ParticleCeiling,
		math.floor(worst + 0.5),
		worstId
	)
end

-- docs/PERFORMANCE.md's table of each tier's particle budget against its scene (CostReport.Scene): the most
-- particles alive at once as authored, then with every emitter asking the budget, in a fight and out of it.
function CostReport.budgetLines(): { string }
	local lines = {
		"| Niveau | Budget de particules | En combat : sans frein → avec | Hors combat : sans frein → avec |",
		"|---|---|---|---|",
	}
	for _, name in ipairs(QualityConfig.Order) do
		local tier = QualityConfig.Tiers[name]
		local cells = { Strings.t(tier.NameKey, nil, "fr"), tostring(tier.Particles) }
		for _, fighting in ipairs({ true, false }) do
			local scene = CostReport.Scene
			local free = CostReport.scene({
				Plays = scene.Plays,
				Bodies = scene.Bodies,
				Tier = name,
				Fighting = fighting,
				Budget = math.huge,
			})
			local braked =
				CostReport.scene({ Plays = scene.Plays, Bodies = scene.Bodies, Tier = name, Fighting = fighting })
			local cell = ("%d → %d"):format(free.Peak, braked.Peak)
			if braked.Drawn < braked.Asked then
				cell ..= (" (%d %% tirées)"):format(math.floor(braked.Drawn / braked.Asked * 100))
			end
			table.insert(cells, cell)
		end
		table.insert(lines, "| " .. table.concat(cells, " | ") .. " |")
	end
	return lines
end

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
	print("")
	print(CostReport.ceilingLine(costs))
	print("")
	for _, line in ipairs(CostReport.budgetLines()) do
		print(line)
	end
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
