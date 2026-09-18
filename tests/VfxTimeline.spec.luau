--!strict
-- The reason a spell's visual is data rather than a function is that data can be held to rules. These are
-- the rules, and they are the ones docs/JUICE_AUDIT.md found the imperative version breaking everywhere:
-- effects with two layers, no anticipation, no trace left behind, linear interpolation, and a Cast visual
-- shared by all twenty spells because nothing made a per-spell one cheap enough to write.
--
-- Every check here would have failed on the old renderers. That is the point: the format is only worth
-- the rewrite if it makes the failures visible on every build.
local AssetIds = require("../src/shared/Config/AssetIds")
local FeelConfig = require("../src/shared/Config/FeelConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local LightingConfig = require("../src/shared/Config/LightingConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local TIMELINES = VfxTimelineConfig.Timelines
local ORDER = VfxTimelineConfig.PhaseOrder

-- docs/ART_BIBLE.md rule 4: nothing moves linearly. Linear is not in the Ease union, and it is not here
-- either; a timeline that names it fails twice, which is the right number of times.
local ALLOWED_EASES: { [string]: boolean } = {
	Quad = true,
	Cubic = true,
	Quart = true,
	Quint = true,
	Sine = true,
	Back = true,
	Exponential = true,
	Circular = true,
}
local ALLOWED_DIRECTIONS: { [string]: boolean } = { In = true, Out = true, InOut = true }

-- The minimum a reworked effect ships with (docs/JUICE_PLAN.md phase 4: "Aucun sort ne sort de cette
-- phase avec moins de 4 couches"). The audit measured 2.1.
local MIN_LAYERS = 4

local function phaseNames(timeline: VfxTimelineConfig.Timeline): { [string]: boolean }
	local names: { [string]: boolean } = {}
	for _, phase in ipairs(timeline.Phases) do
		names[phase.Name] = true
	end
	return names
end

local function eachLayer(fn: (id: string, phase: VfxTimelineConfig.Phase, layer: VfxTimelineConfig.Layer) -> ())
	for id, timeline in pairs(TIMELINES) do
		for _, phase in ipairs(timeline.Phases) do
			for _, layer in ipairs(phase.Layers) do
				fn(id, phase, layer)
			end
		end
	end
end

describe("vfx timelines", function()
	it("declares some, so nothing below passes vacuously", function()
		local count = 0
		for _ in pairs(TIMELINES) do
			count += 1
		end
		expect(count).toBeGreaterThanOrEqual(3)
	end)

	it("gives every effect at least four layers", function()
		for id, timeline in pairs(TIMELINES) do
			local layers = 0
			for _, phase in ipairs(timeline.Phases) do
				layers += #phase.Layers
			end
			if layers < MIN_LAYERS then
				error(("timeline %s has %d layers; the floor is %d"):format(id, layers, MIN_LAYERS))
			end
		end
	end)

	it("anticipates anything a player performs", function()
		-- Derived from the data rather than from a list somebody has to remember to update: a timeline
		-- that has a Cast or a Travel phase is something being done, and something being done has a
		-- wind-up. An Impact has none, because its wind-up was the cast that produced it.
		for id, timeline in pairs(TIMELINES) do
			local names = phaseNames(timeline)
			if (names.Cast or names.Travel) and not names.Anticipation then
				error(("timeline %s performs an action with no anticipation phase"):format(id))
			end
		end
	end)

	it("leaves a trace, every time", function()
		-- Art bible rule 5: "Chaque impact laisse une trace qui s'efface. Le monde se souvient pendant
		-- quelques secondes." The audit counted zero decals in the whole game.
		for id, timeline in pairs(TIMELINES) do
			if not phaseNames(timeline).Residue then
				error(("timeline %s leaves nothing behind"):format(id))
			end
		end
	end)

	it("orders its phases the way they play", function()
		local rank: { [string]: number } = {}
		for index, name in ipairs(ORDER) do
			rank[name] = index
		end
		for id, timeline in pairs(TIMELINES) do
			local previous = 0
			for _, phase in ipairs(timeline.Phases) do
				local current = rank[phase.Name]
				if current == nil then
					error(("timeline %s has an unknown phase %s"):format(id, phase.Name))
				end
				if current <= previous then
					error(("timeline %s declares %s out of order"):format(id, phase.Name))
				end
				previous = current
			end
		end
	end)

	it("never interpolates linearly", function()
		eachLayer(function(id, phase, layer)
			if layer.Ease ~= nil and not ALLOWED_EASES[layer.Ease] then
				error(("timeline %s / %s uses easing %s"):format(id, phase.Name, layer.Ease))
			end
			if layer.EaseDirection ~= nil and not ALLOWED_DIRECTIONS[layer.EaseDirection] then
				error(("timeline %s / %s uses direction %s"):format(id, phase.Name, layer.EaseDirection))
			end
		end)
	end)

	it("names only textures that exist", function()
		eachLayer(function(id, phase, layer)
			if layer.Texture ~= nil then
				local _, known = AssetIds.get(layer.Texture)
				if not known then
					error(
						("timeline %s / %s wants texture %s, which AssetIds does not declare"):format(
							id,
							phase.Name,
							layer.Texture
						)
					)
				end
			end
		end)
	end)

	it("names only camera profiles that exist", function()
		eachLayer(function(id, phase, layer)
			if layer.Kind == "Shake" then
				local profile = layer.Profile
				if profile == nil or FeelConfig.Shake.Profiles[profile] == nil then
					error(("timeline %s / %s shakes with profile %s"):format(id, phase.Name, tostring(profile)))
				end
			end
		end)
	end)

	it("names only screen pulses that exist", function()
		-- The other half of the same seam. A Flash layer names a profile in LightingConfig, and the two
		-- files are edited by different people on different days; nothing but this notices when one of
		-- them renames a pulse.
		eachLayer(function(id, phase, layer)
			if layer.Kind == "Flash" then
				local profile = layer.Profile
				if profile == nil or LightingConfig.Pulses[profile] == nil then
					error(
						("timeline %s / %s flashes with pulse %s, which LightingConfig does not declare"):format(
							id,
							phase.Name,
							tostring(profile)
						)
					)
				end
			end
		end)
	end)

	it("gives every layer kind what it cannot work without", function()
		-- A layer missing its own defining field renders as nothing and costs a pooled instance to do it,
		-- which is the most expensive way to draw nothing at all.
		eachLayer(function(id, phase, layer)
			local function need(condition: boolean, what: string)
				if not condition then
					error(("timeline %s / %s: a %s layer %s"):format(id, phase.Name, layer.Kind, what))
				end
			end
			if layer.Kind == "Emitter" then
				need(layer.Rate ~= nil or layer.Burst ~= nil, "emits at no rate and bursts nothing")
				need(layer.Lifetime ~= nil and #layer.Lifetime == 2, "has no particle lifetime range")
				need(layer.Speed ~= nil and #layer.Speed == 2, "has no speed range")
			elseif layer.Kind == "Light" then
				need(layer.Range ~= nil and layer.Range > 0, "has no range")
				need(layer.Brightness ~= nil, "has no brightness")
			elseif layer.Kind == "Sprite" or layer.Kind == "Mark" or layer.Kind == "Beam" or layer.Kind == "Trail" then
				need(layer.Size ~= nil and layer.Size >= 0, "has no size")
			elseif layer.Kind == "Shake" or layer.Kind == "Flash" then
				need(layer.Profile ~= nil, "names no profile")
			end
		end)
	end)

	it("schedules every layer inside a window that can be cleaned up", function()
		eachLayer(function(id, phase, layer)
			if layer.At < 0 then
				error(("timeline %s / %s starts a layer at %.3f"):format(id, phase.Name, layer.At))
			end
			if layer.For <= 0 then
				error(("timeline %s / %s has a layer that lasts %.3f"):format(id, phase.Name, layer.For))
			end
			if layer.At + layer.For > VfxTimelineConfig.MaxLayerSeconds then
				error(("timeline %s / %s has a layer outliving the force-release backstop"):format(id, phase.Name))
			end
		end)
	end)

	it("fits inside the lifetime its packet is given", function()
		-- VfxController destroys a packet's Trove after GameConfig.Vfx.LifetimeSeconds. A timeline longer
		-- than that would have its tail cut off mid-fade, which reads as an effect blinking out.
		for id, timeline in pairs(TIMELINES) do
			local total = VfxTimelineConfig.duration(timeline)
			if total > GameConfig.Vfx.LifetimeSeconds then
				error(
					("timeline %s runs %.2fs, past the %.2fs packet lifetime"):format(
						id,
						total,
						GameConfig.Vfx.LifetimeSeconds
					)
				)
			end
		end
	end)

	it("carries no colour of its own", function()
		-- Art bible rule 2: one glyph, one pigment, one colour. A timeline is tinted by whatever plays it,
		-- so a colour written into the data is the one way two pigments could end up in one effect. The
		-- Layer type has no colour field; this catches somebody adding one.
		eachLayer(function(id, phase, layer)
			for key in pairs(layer :: any) do
				local lowered = string.lower(tostring(key))
				if string.find(lowered, "colour", 1, true) ~= nil or string.find(lowered, "color", 1, true) ~= nil then
					error(
						("timeline %s / %s declares %s; a timeline is tinted by its caster"):format(id, phase.Name, key)
					)
				end
			end
		end)
	end)

	it("measures its own duration correctly", function()
		-- Hand-computed against a fixture, because every budget check above trusts this function.
		local fixture: VfxTimelineConfig.Timeline = {
			Intent = "fixture",
			Phases = {
				{
					Name = "Anticipation",
					Duration = 0.2,
					Layers = { { Kind = "Shake", At = 0, For = 0.1, Profile = "Cast" } },
				},
				-- Starts 0.2 in, at 0.05, lasting 0.4: ends at 0.65, past the 0.5 the phases sum to.
				{
					Name = "Cast",
					Duration = 0.3,
					Layers = { { Kind = "Shake", At = 0.05, For = 0.4, Profile = "Cast" } },
				},
			},
		}
		expect(VfxTimelineConfig.duration(fixture)).toBeCloseTo(0.65, 5)

		-- A timeline whose layers all end early still lasts as long as its phases.
		local short: VfxTimelineConfig.Timeline = {
			Intent = "fixture",
			Phases = {
				{
					Name = "Residue",
					Duration = 1.5,
					Layers = { { Kind = "Shake", At = 0, For = 0.1, Profile = "Cast" } },
				},
			},
		}
		expect(VfxTimelineConfig.duration(short)).toBeCloseTo(1.5, 5)
	end)
end)
