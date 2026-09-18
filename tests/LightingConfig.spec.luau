--!strict
-- The rules of docs/ART_BIBLE.md that a reader of LightingConfig would otherwise have to take on trust,
-- turned into a gate.
--
-- All three are rules nobody breaks on purpose. Rule 1 -- nothing in the scenery is ever saturated -- goes
-- one commit at a time, when a colour is nudged to make a screenshot pop and the whole point of the
-- direction (a saturated pixel is a threat, always, without exception) quietly stops being true. "The
-- world is bright and the magic is dark" is the inversion the identity rests on, and it dies the same way,
-- half a brightness point at a time. And a post-processing effect left on a non-resting value is how every
-- game ends up with a permanent grade, which docs/JUICE_PLAN.md phase 3 forbids outright.
local Harness = require("./harness")
local LightingConfig = require("../src/shared/Config/LightingConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- HSV saturation is a RATIO, so it explodes as a colour approaches black: the additive colour shift
-- 28/24/16 measures 0.43 saturated and is invisible on screen. One threshold would therefore be either
-- useless for the pale colours or a lie for the dark ones. So the dark ones are held to the absolute
-- spread between their channels, which for them is the far tighter statement of the same rule.
local VALUE_FLOOR = 0.2
local SATURATION_MAX = 0.25
local CHROMA_MAX = 0.06

-- Nothing may hold the screen for longer than this, whatever a profile declares.
local PULSE_SECONDS_MAX = 6

-- Everything a pulse is allowed to declare. Anything else would be somewhere to write a value that
-- persists, and "a pulse comes back" is only guaranteed while there is nowhere to write one.
local PULSE_KEYS = { AttackSeconds = true, HoldSeconds = true, ReleaseSeconds = true, Deltas = true }

-- Value (how bright), saturation (how much of a colour it is) and chroma (the absolute spread between the
-- channels), all normalised.
local function measure(rgb: LightingConfig.Rgb): (number, number, number)
	local high = math.max(rgb[1], rgb[2], rgb[3])
	local low = math.min(rgb[1], rgb[2], rgb[3])
	local saturation = if high == 0 then 0 else (high - low) / high
	return high / 255, saturation, (high - low) / 255
end

local function average(rgb: LightingConfig.Rgb): number
	return (rgb[1] + rgb[2] + rgb[3]) / 3
end

local function midpoint(band: LightingConfig.Band): number
	return (band[1] + band[2]) / 2
end

-- Every colour the world sits at when nothing is happening, labelled so a failure names the property.
local function restingColors(): { { Label: string, Rgb: LightingConfig.Rgb } }
	local out: { { Label: string, Rgb: LightingConfig.Rgb } } = {}
	for property, rgb in pairs(LightingConfig.Lighting.Colors) do
		table.insert(out, { Label = "Lighting " .. property, Rgb = rgb })
	end
	for property, rgb in pairs(LightingConfig.Atmosphere.Colors) do
		table.insert(out, { Label = "Atmosphere " .. property, Rgb = rgb })
	end
	for name, def in pairs(LightingConfig.Effects) do
		if def.RestColors ~= nil then
			for property, rgb in pairs(def.RestColors) do
				table.insert(out, { Label = name .. " " .. property, Rgb = rgb })
			end
		end
	end
	return out
end

describe("LightingConfig", function()
	it("has no saturated colour in the resting configuration", function()
		local colors = restingColors()
		-- Two ambients, the fog, two colour shifts, two atmosphere colours and the grading tint.
		expect(#colors).toBeGreaterThanOrEqual(8)
		for _, entry in ipairs(colors) do
			expect(entry.Rgb).toHaveLength(3)
			for _, channel in ipairs(entry.Rgb) do
				expect(channel).toBeGreaterThanOrEqual(0)
				expect(channel).toBeLessThanOrEqual(255)
			end
			local value, saturation, chroma = measure(entry.Rgb)
			if value >= VALUE_FLOOR then
				if saturation > SATURATION_MAX then
					error(
						("%s is a colour, not a tint: saturation %.3f above %.3f"):format(
							entry.Label,
							saturation,
							SATURATION_MAX
						)
					)
				end
			elseif chroma > CHROMA_MAX then
				error(
					("%s is too far off grey for a value that dark: chroma %.3f above %.3f"):format(
						entry.Label,
						chroma,
						CHROMA_MAX
					)
				)
			end
		end
	end)

	it("keeps the world light, not dark", function()
		local numbers = LightingConfig.Lighting.Numbers
		-- Upper half of the stated band, which is the whole inversion: bright world, dark magic. A value
		-- in the lower half is the genre's default look and the reason the audit was written.
		expect(numbers.Brightness).toBeGreaterThan(midpoint(LightingConfig.Bands.Brightness))
		expect(numbers.Brightness).toBeLessThanOrEqual(LightingConfig.Bands.Brightness[2])
		local channelMid = midpoint(LightingConfig.Bands.AmbientChannel)
		-- Ambient is what fills a shadow, so it, not the brightness, is what decides between a page and a
		-- dungeon.
		expect(average(LightingConfig.Lighting.Colors.Ambient)).toBeGreaterThan(channelMid)
		expect(average(LightingConfig.Lighting.Colors.OutdoorAmbient)).toBeGreaterThan(channelMid)
		-- And the sun is up. A high-key world at four in the morning is a contradiction the numbers above
		-- cannot catch on their own.
		expect(numbers.ClockTime).toBeGreaterThan(7)
		expect(numbers.ClockTime).toBeLessThan(17)
	end)

	it("keeps the scenery matte", function()
		-- SmoothPlastic at zero reflectance: no metal, no glass, no neon. These two properties are where
		-- the specular, flared look this direction was chosen against gets back in.
		expect(LightingConfig.Lighting.Numbers.EnvironmentSpecularScale).toBeLessThanOrEqual(0.1)
		expect(LightingConfig.Atmosphere.Numbers.Glare).toBe(0)
	end)

	it("declares the five effects once each", function()
		expect(LightingConfig.EffectOrder).toHaveLength(5)
		local seenClass: { [string]: string } = {}
		for _, name in ipairs(LightingConfig.EffectOrder) do
			local def = LightingConfig.Effects[name]
			if def == nil then
				error(("%s is ordered but not declared"):format(name))
			end
			-- Two entries sharing a class would both find the same instance and fight over every property
			-- of it, and which one won would depend on the iteration order.
			local owner = seenClass[def.ClassName]
			if owner ~= nil then
				error(("%s and %s both claim %s"):format(owner, name, def.ClassName))
			end
			seenClass[def.ClassName] = name
		end
		local declared = 0
		for _ in pairs(LightingConfig.Effects) do
			declared += 1
		end
		expect(declared).toBe(#LightingConfig.EffectOrder)
	end)

	it("rests within a hair of neutral, so nothing is a permanent look", function()
		-- The effect, the property, the engine's neutral value for it and how far the resting state may
		-- sit from that. Restated here rather than read from the config on purpose: a test that asks the
		-- config whether the config is acceptable proves nothing.
		local resting = {
			{ Effect = "Bloom", Property = "Intensity", Neutral = 0, Tolerance = 0.3 },
			{ Effect = "ColorCorrection", Property = "Brightness", Neutral = 0, Tolerance = 0.02 },
			{ Effect = "ColorCorrection", Property = "Contrast", Neutral = 0, Tolerance = 0.1 },
			{ Effect = "ColorCorrection", Property = "Saturation", Neutral = 0, Tolerance = 0.1 },
			{ Effect = "DepthOfField", Property = "NearIntensity", Neutral = 0, Tolerance = 0 },
			{ Effect = "DepthOfField", Property = "FarIntensity", Neutral = 0, Tolerance = 0.15 },
			{ Effect = "SunRays", Property = "Intensity", Neutral = 0, Tolerance = 0 },
			{ Effect = "Blur", Property = "Size", Neutral = 0, Tolerance = 0 },
		}
		for _, check in ipairs(resting) do
			local def = LightingConfig.Effects[check.Effect]
			local value = def.Rest[check.Property]
			if value == nil then
				error(("%s has no resting %s"):format(check.Effect, check.Property))
			end
			if math.abs(value - check.Neutral) > check.Tolerance then
				error(
					("%s %s rests at %.3f, more than %.3f from neutral: that is a look, not a rest"):format(
						check.Effect,
						check.Property,
						value,
						check.Tolerance
					)
				)
			end
		end

		-- And every resting value, named above or not, is inside its own band: the clamp in the controller
		-- is a safety net, and a resting value it has to catch is a number that was never applied.
		for name, def in pairs(LightingConfig.Effects) do
			for property, value in pairs(def.Rest) do
				local band = def.Limits[property]
				if band == nil then
					error(("%s %s has no band"):format(name, property))
				end
				expect(band).toHaveLength(2)
				expect(band[1]).toBeLessThan(band[2])
				expect(value).toBeGreaterThanOrEqual(band[1])
				expect(value).toBeLessThanOrEqual(band[2])
			end
		end
	end)

	it("returns every pulse to rest and bounds how long one lasts", function()
		local envelope = LightingConfig.Envelope
		local driven: { [string]: boolean } = {}
		local count = 0
		for name, profile in pairs(LightingConfig.Pulses) do
			count += 1
			for key in pairs(profile) do
				if not PULSE_KEYS[key] then
					error(("pulse %s declares %s: a pulse is an envelope and offsets, nothing else"):format(name, key))
				end
			end
			-- A phase shorter than the minimum would be clamped by the controller, which would make the
			-- number here fiction.
			expect(profile.AttackSeconds).toBeGreaterThanOrEqual(envelope.MinPhaseSeconds)
			expect(profile.ReleaseSeconds).toBeGreaterThanOrEqual(envelope.MinPhaseSeconds)
			expect(profile.HoldSeconds).toBeGreaterThan(0)
			expect(profile.AttackSeconds + profile.HoldSeconds + profile.ReleaseSeconds).toBeLessThanOrEqual(
				PULSE_SECONDS_MAX
			)

			for effectName, deltas in pairs(profile.Deltas) do
				local def = LightingConfig.Effects[effectName]
				if def == nil then
					error(("pulse %s drives %s, which is not an effect"):format(name, effectName))
				end
				driven[effectName] = true
				for property, delta in pairs(deltas) do
					local rest = def.Rest[property]
					local band = def.Limits[property]
					if rest == nil or band == nil then
						error(("pulse %s drives %s %s, which has no resting value"):format(name, effectName, property))
					end
					-- An offset of zero is a line that does nothing, which is how a pulse loses a layer
					-- during a merge without anybody noticing.
					expect(delta).never.toBe(0)
					-- The declared peak has to be reachable. If rest plus the offset fell outside the band
					-- the clamp would silently decide the look instead of the config.
					local peak = rest + delta
					expect(peak).toBeGreaterThanOrEqual(band[1])
					expect(peak).toBeLessThanOrEqual(band[2])
				end
			end
		end
		-- The art bible asks for five effects, all animated. One nothing animates is either a permanent
		-- look or an instance created for nothing, and both are worth failing a build over.
		expect(count).toBeGreaterThanOrEqual(2)
		for _, effectName in ipairs(LightingConfig.EffectOrder) do
			if not driven[effectName] then
				error(("nothing animates %s, so it is a permanent value or dead weight"):format(effectName))
			end
		end
	end)
end)
