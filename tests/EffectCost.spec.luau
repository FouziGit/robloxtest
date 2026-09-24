--!strict
-- What an effect is allowed to cost, and what each graphics tier is allowed to promise.
--
-- docs/JUICE_PLAN.md phase 9 asks for a particle ceiling, an estimated client cost per glyph and an
-- automatic degradation. The cost is computed from the data that draws it (scripts/effect-cost.luau), so
-- the ceilings below are checked against the real thing on every run of the gates rather than against a
-- table somebody updated by hand.
--
-- Two of the three ceilings here are DERIVED from another number in the repository:
--   * an effect's peak layers must fit twice inside the lowest tier's budget, so the worst machine in the
--     game can still show two effects at once;
--   * CONCURRENT_EFFECTS of any single effect must fit inside every pool ceiling of PoolPolicy, so the
--     heaviest effect in the game cannot exhaust a class on its own.
-- The third -- the particle ceiling -- is CHOSEN, and nothing in this repository has measured it. No device
-- has run this game. It is set at roughly twice the heaviest effect the data asks for, which is a
-- ratchet against drift and not a statement about any phone: it is the first number to replace with a
-- measurement (docs/PERFORMANCE.md says the same).
local EffectCost = require("../scripts/effect-cost")
local Harness = require("./harness")
local PoolPolicy = require("../src/shared/Pure/PoolPolicy")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local Strings = require("../src/shared/Strings")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- How many copies of one effect the pool must be able to hold at once. Four is a 3v3 exchange where
-- everybody casts the same thing in the same second, which is the worst case a class ceiling has to
-- survive without refusing a borrow.
local CONCURRENT_EFFECTS = 4
-- Chosen, not measured. See the header.
local PARTICLE_CEILING = 400
-- Every class the renderer borrows, so the cost model cannot silently miss one.
local BORROWED_CLASSES =
	{ "Part", "Decal", "ParticleEmitter", "Attachment", "Trail", "Beam", "PointLight", "SpecialMesh" }
local RENDERER = "src/client/Controllers/VfxTimeline.luau"
-- Every file that borrows from the pool for a layer: the runtime, and the volumes it hands its own
-- borrow to (VfxVolumes, `kit.borrow`).
local BORROWERS = { RENDERER, "src/client/Controllers/VfxVolumes.luau" }
-- The three kinds the renderer hands to another system and never puts in the live list.
local HANDED_OFF = { "Shake", "Flash", "Sound" }
-- Where each tier field is read, and the gate is the reader's own source: a field nothing reads is a
-- promise to the player that nothing keeps. Each reader holds its row in a local named `tier` and the
-- search is for `tier.<Field>` in the source with its comments stripped -- a looser search matched a
-- commented-out read, and "Footprints" alone matched WorldConfig's own field in the same file.
local READERS: { { Field: string, Path: string } } = {
	{ Field = "Layers", Path = "src/client/Controllers/VfxTimeline.luau" },
	{ Field = "ParticleScale", Path = "src/client/Controllers/VfxTimeline.luau" },
	{ Field = "Lights", Path = "src/client/Controllers/VfxTimeline.luau" },
	{ Field = "PostProcessing", Path = "src/client/Controllers/WorldLighting.luau" },
	{ Field = "Footprints", Path = "src/client/Controllers/FootprintController.luau" },
	{ Field = "Flourishes", Path = "src/client/Controllers/VfxTimeline.luau" },
	{ Field = "NameKey", Path = "src/ui/screens/SettingsScreen.luau" },
}

describe("the cost of an effect", function()
	local costs = EffectCost.all()

	it("is measured for every timeline in the game", function()
		local counted = 0
		for _ in pairs(VfxTimelineConfig.Timelines) do
			counted += 1
		end
		expect(#costs).toBe(counted)
		expect(#costs).toBeGreaterThanOrEqual(30)
	end)

	it("fits twice inside the lowest tier's layer budget", function()
		local floorBudget = QualityConfig.Tiers[QualityConfig.Order[#QualityConfig.Order]].Layers
		for _, cost in ipairs(costs) do
			expect(cost.Peak).toBeGreaterThan(0)
			if cost.Peak * 2 > floorBudget then
				error(
					("%s holds %d layers at once; the lowest tier's budget is %d, and two effects have to fit"):format(
						cost.Id,
						cost.Peak,
						floorBudget
					)
				)
			end
		end
	end)

	it("leaves room in every pool class for four of itself", function()
		for _, cost in ipairs(costs) do
			for class, count in pairs(cost.Instances) do
				local limits = PoolPolicy.Limits[class]
				if limits == nil then
					error(("%s borrows a %s, which PoolPolicy has no ceiling for"):format(cost.Id, class))
				end
				if count * CONCURRENT_EFFECTS > limits.Live then
					error(
						("%d x %s borrows %d %s and the ceiling is %d"):format(
							CONCURRENT_EFFECTS,
							cost.Id,
							count * CONCURRENT_EFFECTS,
							class,
							limits.Live
						)
					)
				end
			end
		end
	end)

	it("asks for no more particles than the ceiling this repository chose", function()
		for _, cost in ipairs(costs) do
			if cost.Particles > PARTICLE_CEILING then
				error(("%s asks for %d particles; the ceiling is %d"):format(cost.Id, cost.Particles, PARTICLE_CEILING))
			end
		end
	end)

	it("counts every kind that takes a slot, and no kind that does not", function()
		-- A shake, a flash and a sound are handed to Feel, WorldLighting and SoundController and never enter
		-- the live list, so counting them in a peak overstated twenty-six of the thirty-five timelines
		-- against the very budget the peak is compared to. The other direction is worse: a kind the
		-- renderer DOES draw and this set forgets would understate every peak.
		local renderer = fs.readFile(RENDERER)
		for _, kind in ipairs(HANDED_OFF) do
			if string.find(renderer, 'layer.Kind == "' .. kind .. '"', 1, true) == nil then
				error(("the renderer no longer hands %s off: the cost model's OCCUPIES set is stale"):format(kind))
			end
			if EffectCost.Occupies[kind] then
				error(("%s takes no slot of the budget and the cost model counts it"):format(kind))
			end
		end
		-- Every kind the data really uses is one or the other, so a new kind cannot be silently dropped.
		local used: { [string]: boolean } = {}
		for _, timeline in pairs(VfxTimelineConfig.Timelines) do
			for _, phase in ipairs(timeline.Phases) do
				for _, layer in ipairs(phase.Layers) do
					used[layer.Kind] = true
				end
			end
		end
		for kind in pairs(used) do
			local handed = table.find(HANDED_OFF, kind) ~= nil
			if handed == (EffectCost.Occupies[kind] == true) then
				error(("%s is neither drawn nor handed off, or it is both"):format(kind))
			end
		end
		for _, cost in ipairs(costs) do
			expect(cost.Drawn).toBeLessThanOrEqual(cost.Layers)
			expect(cost.Peak).toBeLessThanOrEqual(cost.Drawn)
		end
	end)

	it("borrows the classes the renderer really borrows", function()
		-- The model is a copy of what the renderer does, and a copy drifts. This does not prove the counts
		-- (only an engine could), but it proves the SET: a class the renderer borrows and the model never
		-- names would make every pool comparison below optimistic.
		local named: { [string]: boolean } = {}
		for _, path in ipairs(BORROWERS) do
			for class in string.gmatch(stripComments(fs.readFile(path)), 'borrow%(entry, "([%a]+)"%)') do
				named[class] = true
			end
		end
		-- `host` is itself a Part borrow, which is why Part is not in the matches above.
		named.Part = true
		expect(next(named)).never.toBeNil()
		for class in pairs(named) do
			if not table.find(BORROWED_CLASSES, class) then
				error(("the renderer borrows a %s and the cost model does not know the class"):format(class))
			end
		end
		for _, class in ipairs(BORROWED_CLASSES) do
			if not named[class] then
				error(("the cost model counts %s and the renderer never borrows one"):format(class))
			end
		end
		-- Kind by kind: the classes each builder borrows (a host is a Part) are the classes the model gives
		-- that kind, so a class dropped from one kind -- the Mesh's own SpecialMesh -- cannot hide behind
		-- another kind that still counts it.
		local BUILDERS: { [string]: { Path: string, Header: string } } = {
			Sprite = { Path = RENDERER, Header = "local function buildSprite(" },
			Mark = { Path = RENDERER, Header = "local function buildMark(" },
			Emitter = { Path = RENDERER, Header = "local function buildEmitter(" },
			Light = { Path = RENDERER, Header = "local function buildLight(" },
			Beam = { Path = RENDERER, Header = "local function buildBeam(" },
			Carrier = { Path = RENDERER, Header = "local function buildCarrier(" },
			Trail = { Path = RENDERER, Header = "local function buildTrail(" },
			Mesh = { Path = BORROWERS[2], Header = "function VfxVolumes.build(" },
			Debris = { Path = BORROWERS[2], Header = "function VfxVolumes.buildDebris(" },
		}
		for kind in pairs(EffectCost.Occupies) do
			local builder = BUILDERS[kind]
			if builder == nil then
				error(("%s is drawn and this gate does not know its builder"):format(kind))
			end
			local source = stripComments(fs.readFile(builder.Path))
			local start = source:find(builder.Header, 1, true)
			local finish = if start ~= nil then source:find("\nend\n", start, true) else nil
			if start == nil or finish == nil then
				error(("%s is not in %s: this gate would check nothing"):format(builder.Header, builder.Path))
			end
			local code = source:sub(start :: number, finish :: number)
			local borrows: { [string]: boolean } = {}
			for class in string.gmatch(code, 'borrow%(entry, "([%a]+)"%)') do
				borrows[class] = true
			end
			if code:find("host(entry,", 1, true) ~= nil then
				borrows.Part = true
			end
			local modelled = EffectCost.Borrows[kind] or {}
			for class in pairs(borrows) do
				if (modelled[class] or 0) < 1 then
					error(("a %s layer borrows a %s and the cost model does not count it"):format(kind, class))
				end
			end
			for class in pairs(modelled) do
				if not borrows[class] then
					error(("the cost model counts a %s for a %s layer that never borrows one"):format(class, kind))
				end
			end
		end
		-- And the model really counts each of them somewhere: a class it stopped counting would drop out of
		-- every pool comparison below without a word.
		for _, class in ipairs(BORROWED_CLASSES) do
			local counted = false
			for _, cost in ipairs(EffectCost.all()) do
				if (cost.Instances[class] or 0) > 0 then
					counted = true
					break
				end
			end
			if not counted then
				error(("the renderer borrows %s and no effect's cost counts one"):format(class))
			end
		end
	end)
end)

describe("the graphics tiers", function()
	it("are ordered, and every step down costs less", function()
		local order = QualityConfig.Order
		expect(#order).toBe(4)
		local previous: QualityConfig.TierDef? = nil
		for _, name in ipairs(order) do
			local tier = QualityConfig.Tiers[name]
			assert(tier ~= nil, "no tier named " .. name)
			expect(tier.Layers).toBeGreaterThan(0)
			expect(tier.ParticleScale).toBeGreaterThan(0)
			expect(tier.Footprints).toBeGreaterThanOrEqual(0)
			if previous ~= nil then
				local before = previous :: QualityConfig.TierDef
				expect(tier.Layers).toBeLessThan(before.Layers)
				expect(tier.ParticleScale).toBeLessThan(before.ParticleScale)
				expect(tier.Footprints).toBeLessThanOrEqual(before.Footprints)
				-- A feature only ever turns off on the way down, never back on.
				if tier.Lights and not before.Lights then
					error(("%s lights what the tier above it does not"):format(name))
				end
				if tier.PostProcessing and not before.PostProcessing then
					error(("%s post-processes what the tier above it does not"):format(name))
				end
			end
			previous = tier
		end
	end)

	it("start at the ceiling the rest of the game is written against", function()
		-- QualityConfig may not require another config (purity), so the top tier repeats the timeline's own
		-- ceiling. This is what stops the two from drifting.
		expect(QualityConfig.Tiers.High.Layers).toBe(VfxTimelineConfig.MaxLiveLayers)
		expect(QualityConfig.Tiers.High.ParticleScale).toBe(1)
		expect(QualityConfig.Tiers.High.Lights).toBe(true)
		expect(QualityConfig.Tiers.High.PostProcessing).toBe(true)
		expect(QualityConfig.Tiers.High.Footprints).toBe(1)
		expect(QualityConfig.Default).toBe("High")
	end)

	it("cut the post-processing at the floor, and nowhere above it", function()
		-- The plan's wording: three graphics settings plus a Performance mode that cuts post-processing.
		local off = 0
		for _, name in ipairs(QualityConfig.Order) do
			if not QualityConfig.Tiers[name].PostProcessing then
				off += 1
				expect(name).toBe("Performance")
			end
		end
		expect(off).toBe(1)
	end)

	it("are each named by a key a player can read", function()
		for _, name in ipairs(QualityConfig.Order) do
			expect(Strings.has(QualityConfig.Tiers[name].NameKey)).toBe(true)
		end
	end)

	it("resolve any name, and step in both directions", function()
		expect(QualityConfig.isTier("High")).toBe(true)
		expect(QualityConfig.isTier("Ultra")).toBe(false)
		expect(QualityConfig.isTier(nil)).toBe(false)
		-- A profile from an older build, or a payload that made a name up, still gets a budget.
		expect(QualityConfig.tier("Ultra")).toEqual(QualityConfig.Tiers.High)
		expect(QualityConfig.lower("High")).toBe("Medium")
		expect(QualityConfig.lower("Performance")).toBeNil()
		expect(QualityConfig.higher("Performance")).toBe("Low")
		expect(QualityConfig.higher("High")).toBeNil()
		-- The effective tier is the worse of what the player chose and what the frame rate forced.
		expect(QualityConfig.worse("High", "Low")).toBe("Low")
		expect(QualityConfig.worse("Performance", "Medium")).toBe("Performance")
		expect(QualityConfig.worse("Medium", "Medium")).toBe("Medium")
	end)

	it("drop slowly and recover slower, with a gap between the two thresholds", function()
		local auto = QualityConfig.Auto
		expect(auto.SampleSeconds).toBeGreaterThan(0)
		expect(auto.DropBelowFps).toBeLessThan(auto.RaiseAboveFps)
		expect(auto.DropAfterSeconds).toBeGreaterThan(0)
		-- Giving a tier back is slower than taking it away: every change re-enables post-processing, which
		-- compiles shaders, so a tier that oscillates costs more than the tier it was leaving.
		expect(auto.RaiseAfterSeconds).toBeGreaterThan(auto.DropAfterSeconds)
	end)

	it("have a reader for every field they declare", function()
		local sample = QualityConfig.Tiers.High
		local fields = 0
		for _ in pairs(sample) do
			fields += 1
		end
		expect(fields).toBe(#READERS)
		for _, reader in ipairs(READERS) do
			expect((sample :: any)[reader.Field]).toBeTruthy()
			local source = stripComments(fs.readFile(reader.Path))
			if string.find(source, "tier." .. reader.Field, 1, true) == nil then
				error(("QualityConfig declares %s and %s never reads it"):format(reader.Field, reader.Path))
			end
		end
	end)
end)
