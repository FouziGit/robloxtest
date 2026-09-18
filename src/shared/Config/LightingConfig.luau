--!strict
-- Every number that decides what the WORLD looks like. docs/JUICE_AUDIT.md found that nothing in this
-- repository ever touched Lighting: the game ran on Roblox's default sky and default light, which
-- docs/ART_BIBLE.md names as the first reason a screenshot of it was interchangeable with any other
-- game's.
--
-- The direction is high key and inverted: the world is bright, unsaturated cream (vellum, 232/224/206)
-- and the only saturated thing on screen is a glyph. A player who sees a colour is seeing a threat.
-- That inversion is the whole identity, so it is encoded here rather than described:
-- tests/LightingConfig.spec.luau converts every colour below to HSV and fails the build if one of them
-- is a colour rather than a tint, and checks that the ambient and the brightness sit in the upper half
-- of their stated bands. A later "let us make it pop" edit has to argue with a test.
--
-- Pure data: no require and no Roblox global, so it loads under Lune (tests/Purity.spec.luau). Colours
-- are {r, g, b} triples in 0-255 and the lighting technology is a plain string; the client converts both
-- once at load.

export type Rgb = { number }
export type Numbers = { [string]: number }
-- {min, max}, inclusive.
export type Band = { number }

-- One post-processing effect: the class to look for under Lighting, the values it sits at when nothing is
-- happening, and the band each of those values may reach once a pulse pushes it. The band is this
-- project's, tightened to the engine's domain where the engine has one (a saturation past ±1 and a
-- sun-ray intensity past 1 do not exist).
export type EffectDef = {
	ClassName: string,
	Rest: Numbers,
	Limits: { [string]: Band },
	RestColors: { [string]: Rgb }?,
}

-- A pulse is a set of OFFSETS from rest, never a set of target values, and that is what makes "never
-- permanent" structural instead of a promise: the applied value is rest plus the sum of whatever is live,
-- so the moment an envelope reaches zero the value IS rest again, whatever happened in between and
-- whatever else is running.
export type PulseProfile = {
	AttackSeconds: number,
	HoldSeconds: number,
	ReleaseSeconds: number,
	Deltas: { [string]: Numbers },
}

local LightingConfig = {}

-- The bands this direction tunes inside, stated so that a later edit has something to be in the upper
-- half OF. They are not engine limits: Brightness accepts far more than 4 and an ambient of 255 is legal.
-- They are the range in which this is still a lit page rather than a dark room or a white void.
LightingConfig.Bands = {
	Brightness = { 0, 4 },
	AmbientChannel = { 0, 255 },
}

LightingConfig.Lighting = {
	Colors = {
		-- Ambient is what fills a shadow, and it is the single property that decides whether this reads
		-- as a page or as a dungeon. High, and barely warm: on vellum a shadow is a grey wash, not a
		-- hole. Everything else here is mixed down from the same cream.
		Ambient = { 146, 140, 128 },
		-- A little more outdoors, so stepping out of cover brightens rather than only changing hue.
		OutdoorAmbient = { 163, 157, 142 },
		-- Legacy distance fog, superseded by the Atmosphere below wherever one exists. Set anyway, and
		-- set pale: on a client where the Atmosphere could not be created, the alternative showing at the
		-- horizon is Roblox's default blue-grey.
		FogColor = { 214, 208, 192 },
		-- Additive tints on the light itself: warm from above, a cooler bounce from below, which is what
		-- keeps a flat primitive from reading as one flat tone. Both are deliberately near black, because
		-- these are added to every lit surface in the world and a shift big enough to name is a colour in
		-- the scenery, which rule 1 forbids outright.
		ColorShift_Top = { 28, 24, 16 },
		ColorShift_Bottom = { 18, 20, 26 },
	},
	Numbers = {
		Brightness = 2.8,
		-- Early afternoon at a near-equatorial latitude: the sun sits high, so shadows are short enough
		-- that the ground still reads as a flat page, and far enough off vertical that a wall has a lit
		-- side and a shaded one.
		ClockTime = 14.2,
		GeographicLatitude = 8,
		-- A push, not a look. The cream should sit near the top of the range without clipping, and
		-- anything larger here would be a permanent post-processing effect wearing the name of a Lighting
		-- property to get past the rule against them.
		ExposureCompensation = 0.1,
		FogStart = 180,
		FogEnd = 860,
		EnvironmentDiffuseScale = 1,
		-- Near zero, because the art bible's materials are SmoothPlastic at zero reflectance: no metal,
		-- no glass, no neon. A world with specular highlights is the look this direction was chosen
		-- against, and this property is where that look gets back in by accident.
		EnvironmentSpecularScale = 0.05,
	},
	Flags = {
		-- Shadows stay on. Against an ambient this high they land as pale washes instead of black
		-- cutouts, and they are the only thing giving volume to a world made of primitives.
		GlobalShadows = true,
	},
	-- Per-light shadows. A glyph's own light actually casting is the single lighting cue this direction
	-- has, since there is no model and no painted texture to carry one. Hardware that cannot run this
	-- falls back on its own, so naming it costs a low-end device nothing.
	Technology = "Future",
}

-- The Atmosphere, which in this configuration is also the sky.
--
-- There is no Sky here and no asset id anywhere in this file. A solid pale field would beat a borrowed
-- skybox, but a Sky needs six texture assets, this repository has none it has verified, and a Sky created
-- with its default faces would trade an unconfigured sky for somebody else's clouds: the same defect with
-- a different author. So the clear-sky properties carry it instead. Under Future lighting the
-- Atmosphere's Color, Decay and Haze are what recolour the horizon, and the two colour shifts above tint
-- the gradient above it. Glare is zero on purpose: a lens flare around the sun is the most borrowed thing
-- in the genre.
LightingConfig.Atmosphere = {
	Numbers = {
		-- Enough to lift the distance toward paper and separate a far silhouette from a near one. Past
		-- roughly 0.45 the far half of an arena stops being readable, which is a gameplay cost, not a
		-- taste one.
		Density = 0.32,
		Offset = 0.25,
		Glare = 0,
		Haze = 1.4,
	},
	Colors = {
		-- Very close to vellum itself, so distance fades into the page rather than into weather.
		Color = { 226, 220, 204 },
		-- What light decays toward. Roblox's default decays warm brown; a page has no brown distance.
		Decay = { 186, 182, 170 },
	},
}

-- The five post-processing effects. None of them is ever a look: docs/JUICE_PLAN.md phase 3 requires them
-- animated and never permanent, so every resting value below is within a hair of the effect's neutral and
-- the only thing that moves one is a pulse that comes back.
--
-- All five are created even where their resting value is exactly neutral, because enabling a
-- post-processing effect compiles a shader, and the frame that costs is not one to spend at the moment
-- the Erasure arrives.
LightingConfig.EffectOrder = { "Bloom", "ColorCorrection", "DepthOfField", "SunRays", "Blur" }

local effects: { [string]: EffectDef } = {
	Bloom = {
		ClassName = "BloomEffect",
		Rest = {
			Intensity = 0.25,
			Size = 24,
			-- The threshold has to be high HERE and nowhere else: in a cream world an ordinary wall is
			-- already bright, so a default threshold blooms the scenery and the page turns to milk. At
			-- 1.6 only something genuinely overexposed blooms, and in this direction that means a glyph.
			Threshold = 1.6,
		},
		Limits = { Intensity = { 0, 4 }, Size = { 0, 56 }, Threshold = { 0, 8 } },
	},
	ColorCorrection = {
		ClassName = "ColorCorrectionEffect",
		Rest = {
			Brightness = 0,
			-- A hair of contrast against an ambient this high, which otherwise flattens into mush.
			Contrast = 0.06,
			-- And a hair off the saturation: rule 1 applied to the whole frame at once. It costs the
			-- scenery almost nothing and a glyph nothing at all, since a glyph is saturated far past what
			-- this takes back.
			Saturation = -0.08,
		},
		Limits = { Brightness = { -1, 1 }, Contrast = { -1, 1 }, Saturation = { -1, 1 } },
		RestColors = {
			-- Barely off white, warm: the whole frame is graded onto paper instead of onto a screen.
			TintColor = { 252, 248, 238 },
		},
	},
	DepthOfField = {
		ClassName = "DepthOfFieldEffect",
		Rest = {
			FocusDistance = 28,
			InFocusRadius = 64,
			-- Nothing close to the camera is ever softened. The glyph a player is drawing is the one
			-- thing that must be sharp in every frame of every fight.
			NearIntensity = 0,
			FarIntensity = 0.1,
		},
		Limits = {
			FocusDistance = { 0, 400 },
			InFocusRadius = { 0, 400 },
			NearIntensity = { 0, 1 },
			FarIntensity = { 0, 1 },
		},
	},
	SunRays = {
		ClassName = "SunRaysEffect",
		-- Off at rest. Shafts of light are weather, and weather in the scenery competes with the one
		-- thing allowed to be bright.
		Rest = { Intensity = 0, Spread = 0.6 },
		Limits = { Intensity = { 0, 1 }, Spread = { 0, 1 } },
	},
	Blur = {
		ClassName = "BlurEffect",
		-- Zero is not "disabled": the effect is live and its size is what a pulse moves, so a blur never
		-- costs a shader compile at the instant it is wanted.
		Rest = { Size = 0 },
		Limits = { Size = { 0, 20 } },
	},
}

LightingConfig.Effects = effects

-- How an envelope is shaped.
--
-- The envelope is a spring (src/shared/Pure/Spring.luau), not a curve of its own: rule 4 of the art bible
-- bans linear motion, and this repository already has one integrator that is tested under Lune. A spring
-- is shaped by a tension and a friction rather than by a duration, so a declared attack or release time
-- is converted into the critically damped spring that covers it. Critically damped and never under: an
-- overshooting attack would push a value past the peak this file declares and out of its own Limits.
LightingConfig.Envelope = {
	-- The conversion constant. A critically damped spring is within 2% of its goal after Settle/omega
	-- seconds, so tension is (Settle / seconds)^2 and the friction is critical for that tension.
	Settle = 6,
	-- The same statement from the other side: the 2% left when the attack time is up. A pulse is armed
	-- when its weight is this close to one and dropped when it is this close to zero, and 2% of the
	-- largest offset in this file is a change nobody can see.
	SettleEpsilon = 0.02,
	-- An attack or release shorter than this would divide the conversion above by something close to
	-- zero, and a tension of infinity is a value that never comes back. The test holds every declared
	-- phase above this, so the clamp never silently changes a time somebody chose.
	MinPhaseSeconds = 1 / 60,
}

local pulses: { [string]: PulseProfile } = {
	-- The art bible's impact: the screen bleaches like an overexposed page, and the 40 ms is its number.
	-- Brightness up and saturation down TOGETHER is what makes it read as paper catching too much light
	-- rather than as a white flash -- the colour leaves the page before the light does. Held for about a
	-- frame and let go over four times the attack, because a flash that leaves as fast as it arrives
	-- reads as a dropped frame rather than as an impact.
	PageFlash = {
		AttackSeconds = 0.04,
		HoldSeconds = 0.02,
		ReleaseSeconds = 0.16,
		Deltas = {
			ColorCorrection = { Brightness = 0.22, Saturation = -0.55, Contrast = 0.1 },
			-- Enough bloom that the overexposure spills off the bright edges instead of stopping dead
			-- at them.
			Bloom = { Intensity = 0.5 },
		},
	},
	-- The Erasure arriving: the page being wiped rather than written on. Slow and heavy on purpose, most
	-- of five seconds end to end, because all it has to do is be impossible to miss and impossible to
	-- mistake for an impact. Everything drains at once: the ink goes, the light comes up past what the
	-- paper can hold, the distance softens, light starts coming through where nothing was, and the frame
	-- loses its edge. It drives all five effects, which is the only honest reason to create five.
	Erasure = {
		AttackSeconds = 1.6,
		HoldSeconds = 0.8,
		ReleaseSeconds = 2.4,
		Deltas = {
			ColorCorrection = { Brightness = 0.1, Contrast = -0.18, Saturation = -0.45 },
			Bloom = { Intensity = 0.8, Threshold = -0.5 },
			SunRays = { Intensity = 0.18, Spread = 0.2 },
			DepthOfField = { FarIntensity = 0.25 },
			Blur = { Size = 6 },
		},
	},
}

LightingConfig.Pulses = pulses

return LightingConfig
