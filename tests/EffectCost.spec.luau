--!strict
-- What an effect is allowed to cost, and what each graphics tier is allowed to promise.
--
-- docs/JUICE_PLAN.md phase 9 asks for a particle ceiling, an estimated client cost per glyph and an
-- automatic degradation. The cost is computed from the data that draws it (scripts/effect-cost.luau), so
-- the ceilings below are checked against the real thing on every run of the gates rather than against a
-- table somebody updated by hand.
--
-- Every ceiling here is DERIVED from another number in the repository, never chosen:
--   * an effect's peak layers must fit twice inside the lowest tier's budget, so the worst machine in the
--     game can still show two effects at once;
--   * CONCURRENT_EFFECTS of any single effect must fit inside every pool ceiling of PoolPolicy, so the
--     heaviest effect in the game cannot exhaust a class on its own;
--   * the particle ceiling is the one number with a device behind it rather than a config: two of the
--     worst effect at the top tier, which is what docs/PERFORMANCE.md records as tested.
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
local PARTICLE_CEILING = 400
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

	it("asks for no more particles than a device was measured holding", function()
		for _, cost in ipairs(costs) do
			if cost.Particles > PARTICLE_CEILING then
				error(("%s asks for %d particles; the ceiling is %d"):format(cost.Id, cost.Particles, PARTICLE_CEILING))
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
