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
-- is a colour rather than a tint, and holds the ambient and the brightness inside their stated bands --
-- both ends of them, since this file has already been wrong at the bright end. A later "let us make it
-- pop" edit, or a later "let us tone it down" one, has to argue with a test.
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

-- The bands this direction tunes inside. They are not engine limits: Brightness accepts far more than 4
-- and an ambient of 255 is legal. They are the range in which this is still a lit page -- and BOTH ends
-- of each one are a real failure.
--
-- These used to be {0, 4} and {0, 255}, with the test demanding the upper half of each. That rule was
-- written to keep the page from becoming a dungeon, and it worked; what nobody checked is what the upper
-- half does. At Brightness 2.8 over an ambient of 146, a vellum surface (232, 224, 206) clips to pure
-- white: the first screenshot of the finished hub was white floor, white walls, white characters, with
-- the cream the whole direction is built on nowhere on screen and every shadow washed flat. A white void
-- is exactly the failure the old band named and then sat inside.
--
-- So the bands are TIGHTER now, not looser, and they are bounded above for the first time: below the
-- floor this is a dark room, above the ceiling the paper burns out and the world has no colour at all.
LightingConfig.Bands = {
	Brightness = { 1.2, 2.2 },
	AmbientChannel = { 88, 125 },
}

LightingConfig.Lighting = {
	Colors = {
		-- Ambient is what fills a shadow, and it is the single property that decides whether a shadow
		-- reads as a wash or as a hole. Warm, and high enough that nothing in this world goes black --
		-- but no longer high enough to fill the shadow in completely, which is what it was doing at 146:
		-- with the sun and the fill that close together there was no shadow left to see.
		Ambient = { 104, 99, 89 },
		-- A little more outdoors, so stepping out of cover brightens rather than only changing hue.
		OutdoorAmbient = { 118, 113, 102 },
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
		-- 1.55, not the 2.8 this shipped with. Brightness multiplies the sun on top of the ambient, and
		-- the two together decide whether a cream surface stays cream. At 2.8 it did not: the page read
		-- as #FFFFFF and the only way to tell a wall from a floor was the thin ink rule between them.
		Brightness = 1.55,
		-- Early afternoon at a near-equatorial latitude: the sun sits high, so shadows are short enough
		-- that the ground still reads as a flat page, and far enough off vertical that a wall has a lit
		-- side and a shaded one.
		ClockTime = 14.2,
		GeographicLatitude = 8,
		-- Zero. A push on top of a correct exposure is a look; a push on top of an exposure that was
		-- already clipping was a second reason the page had no tone left.
		ExposureCompensation = 0,
		FogStart = 180,
		FogEnd = 860,
		-- 0.35, measured in Studio once the sky became vellum (D-284): the sky lights every surface through
		-- this, and at 1 a pale sky burned the plaza floors to pure white.
		EnvironmentDiffuseScale = 0.35,
		-- Near zero, because the art bible's materials are SmoothPlastic at zero reflectance: no metal,
		-- no glass, no neon. A world with specular highlights is the look this direction was chosen
		-- against, and this property is where that look gets back in by accident.
		EnvironmentSpecularScale = 0.05,
	},
	Flags = {
		-- Shadows stay on. Against this ambient they land as warm grey washes instead of black
		-- cutouts, and they are the only thing giving volume to a world made of primitives.
		GlobalShadows = true,
	},
	-- Per-light shadows. A glyph's own light actually casting is the single lighting cue this direction
	-- has, since there is no model and no painted texture to carry one. Hardware that cannot run this
	-- falls back on its own, so naming it costs a low-end device nothing.
	Technology = "Future",
}

-- The Atmosphere: what the distance fades into.
--
-- This used to end with "and it is also the sky", on the reasoning that a Sky object needs six uploaded
-- textures, that borrowing somebody else's is forbidden, and that the Atmosphere would therefore carry
-- the horizon on its own. Every step of that is true and the conclusion was still wrong: leaving the Sky
-- alone does not give you no sky, it gives you ROBLOX's sky. The first screenshot of the finished hub
-- has a cream page under a stock blue sky with stock clouds -- the single most interchangeable thing in
-- the frame, in a direction whose whole premise is not being interchangeable.
--
-- LightingConfig.Sky below is the answer, and it needs no asset either: see it.
LightingConfig.Atmosphere = {
	Numbers = {
		-- Enough to lift the distance toward paper and separate a far silhouette from a near one. Past
		-- roughly 0.45 the far half of an arena stops being readable, which is a gameplay cost, not a
		-- taste one.
		-- 0.18 since the Battleground grew to 700 studs (D-282): at 0.38 the vellum sky swallowed everything
		-- past ~250 studs, so the Page's landmarks vanished from across the map. Measured in Studio.
		Density = 0.18,
		Offset = 0.45,
		Glare = 0,
		-- 2.6, measured in Studio: the sky is vellum now (D-284), so the Haze only softens the distance; the
		-- 4.2 it took to fight Roblox's blue default sky muddied the vellum one to tan.
		Haze = 2.6,
	},
	Colors = {
		-- Very close to vellum itself, so distance fades into the page rather than into weather.
		Color = { 226, 220, 204 },
		-- What light decays toward. Roblox's default decays warm brown; a page has no brown distance.
		Decay = { 226, 218, 200 },
	},
}

-- The sky: a Sky object whose six faces carry one flat sheet of vellum (AssetIds SkyVellum).
--
-- Measured in a running client: a Sky with empty faces is not "no sky", it is Roblox's default BLUE sky,
-- and that blue also lights every surface through the environment lighting, so the hub and the
-- Battleground read teal instead of warm paper. Six faces set to a paper texture turned the world cream
-- at once; a dark texture turned it dark, so the texture is the page colour itself. Until the PNG is
-- uploaded the id is "" and the faces stay empty, which is the old behaviour.
--
-- Six Neon slabs around the camera were tried first and dropped: past a few hundred studs the renderer
-- culls them, at a distance that depends on the player's graphics quality.
--
-- CelestialBodiesShown is false for the same reason Glare is zero: a sun disc and a moon are the most
-- borrowed objects in the genre, and neither belongs on a page.
LightingConfig.Sky = {
	CelestialBodiesShown = false,
	-- The six face properties, named so the client writes exactly these and a seventh cannot appear by
	-- accident.
	Faces = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
}

-- Every face mapped to `textureId` ("" while the sky has not been uploaded): what the client writes.
function LightingConfig.skyFaces(textureId: string): { [string]: string }
	local faces: { [string]: string } = {}
	for _, face in ipairs(LightingConfig.Sky.Faces) do
		faces[face] = textureId
	end
	return faces
end

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
			-- 0.1, which is the most a resting post-processing value may sit from neutral in this project
			-- (tests/LightingConfig.spec.luau). With the ambient down there is finally a dark end for it
			-- to act on; at the old exposure it was doing nothing, because everything was already at the
			-- top of the range. It stops at the rule rather than arguing with it: the exposure above is
			-- the honest lever, and a contrast that needs to go further is hiding a bad exposure.
			Contrast = 0.1,
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
	-- An impact's punch on the whole frame, in the 40 ms the art bible gave it (D-119). It used to bleach the
	-- page -- brightness up, saturation down by more than half -- and, seen in the VFX lab, it drained the
	-- very burst it marked: the frame of every glyph's landing was a pale pink wash. Now the ink bites
	-- instead: contrast and saturation up a notch, a touch of light, and the bloom spilling off the burst's
	-- hot core. Held for about a frame and let go over four times the attack, because a flash that leaves
	-- as fast as it arrives reads as a dropped frame rather than as an impact.
	PageFlash = {
		AttackSeconds = 0.04,
		HoldSeconds = 0.02,
		ReleaseSeconds = 0.16,
		Deltas = {
			ColorCorrection = { Brightness = 0.06, Saturation = 0.18, Contrast = 0.2 },
			Bloom = { Intensity = 0.6 },
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
			-- Saturation is -0.36, not the -0.45 this first carried, because pulses COMPOSE: rest is
			-- -0.08 and PageFlash takes another -0.55, so -0.45 here summed to -1.08 and spent the
			-- overlap pinned at the -1 clamp, which is a fully grey screen nobody chose. An impact
			-- landing while the Erasure arrives is not a rare case, it IS the World Boss fight.
			ColorCorrection = { Brightness = 0.1, Contrast = -0.18, Saturation = -0.36 },
			Bloom = { Intensity = 0.8, Threshold = -0.5 },
			SunRays = { Intensity = 0.18, Spread = 0.2 },
			DepthOfField = { FarIntensity = 0.25 },
			Blur = { Size = 6 },
		},
	},
}

LightingConfig.Pulses = pulses

return LightingConfig
