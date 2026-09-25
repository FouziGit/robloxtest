--!strict
-- Visual effect ids. Pure data: the single source of truth shared by the server (which emits
-- packets) and the client (VfxLibrary, which renders them). Adding an effect means adding its id
-- here, a renderer in src/client/Controllers/VfxLibrary.luau, and — for a glyph — referencing the
-- id from GlyphConfig.VfxId. Tests assert every GlyphConfig.VfxId is listed here; VfxController
-- warns at startup for any id listed here without a renderer.

local VfxConfig = {}

-- How much of an effect's colour is ADDED as light rather than laid down as ink, for every particle,
-- beam and trail the renderers build. Zero, because this world is a page: ink darkens the paper, it does
-- not light it. The renderers used to hard-code 0.35, 0.4, 0.3 and 0.6 -- the glowing-magic defaults --
-- and on a cream page additive light is the one colour that cannot be seen. Measured side by side in a
-- live client: the same Umber smoke at 0.35 came out pale and orange and at 0 dense and brown, and the
-- developer's report that the spells had faded to smudges was the rest of the evidence. A glow that is
-- really wanted is a Light layer, which lights the page around it instead of bleaching the ink.
VfxConfig.LightEmission = 0

-- The glyph's own light (D-119). The page stays ink; a spell is the one thing on it allowed to burn. A layer
-- may add up to MaxGlow of its colour as light (its Glow), and its Core role is the pigment pushed Toward
-- white by that share at birth -- never white itself, which is invulnerability -- cooling into the wet
-- pigment by `Cools` of its life.
VfxConfig.MaxGlow = 1
VfxConfig.Heat = { Toward = 0.72, Cools = 0.35 }

-- How far past its end size a particle that pops (Layer.Pop) swells before it settles.
VfxConfig.PopOvershoot = 1.2

-- With shakes and flashes turned off (the profile's switch, or the platform's reduced motion), a core is
-- still the hot centre of its pigment but adds at most Glow of its colour as light and shines no brighter
-- than Brightness, so nothing on screen blooms (D-119).
VfxConfig.Calm = { Glow = 0.25, Brightness = 1 }

-- The hand a spell is born in and thrown from (Layer.Anchor, the local tap): R15's right hand, where every
-- cast animation puts the release.
VfxConfig.Hand = "RightHand"

-- Ink dries (D-111). Every particle, trail and floor mark of a glyph is born a shade paler -- wet -- and
-- dries a shade darker, in its own pigment: the same shading PigmentConfig measures, so the school stays
-- readable at both ends. A thing drawn in one flat colour from birth to death is a sticker; one that
-- changes as it lives is ink. Only a pigment dries: the page-coloured Erasure and the ink tones of a kill
-- effect stay the colour they were given.
-- A particle dries over its own life and a trail along its length. A floor mark dries over `Seconds` of
-- its PLAY: the timelines draw one stain as a chain of marks, each starting where the last one ended, and
-- dried on its own life each link was born wet on top of a dry one -- the stain flashed pale at every
-- hand-off (found by review). Two and a half seconds is more than twice the latest impact of any timeline,
-- so a mark the impact lays is still more wet than dry.
VfxConfig.InkRamp = { Wet = 0.12, Dry = -0.2, Seconds = 2.5 }

-- A dash's sketches (D-116, VfxVolumes.buildAfterimage): every limb of an R15 body copied and drawn flat
-- by one Highlight -- a fill in the layer's Tone and an Outline in ink, an ink print of the body; a
-- translucent copy read as a ghost (review). Nothing worn is copied: an accessory is someone's purchase,
-- and a hat left hanging in the air reads as a bug.
--
-- A print is laid when the body has really covered its share of the dash (the layer's Along), on each
-- screen as that screen sees it move -- the dasher's own a moment after the push, everyone else's after
-- the latency that shows it moving -- exactly at that share of the path, however far the body got in the
-- frame it was noticed. It is given up WaitSeconds after the body started moving (more than MoveStuds)
-- without getting there, a dash stopped by a wall, or CeilingSeconds after its time if the body never
-- moved at all. It shrinks away as one body, about its root, over the last ShrinkShare of its life. The dasher's own is drawn in the paler OwnTone, and
-- not at all when the dash runs within OwnHiddenWithinDegrees of the camera's aim or the camera is
-- inside the character (first person): there it would stand between the player and what they run at.
-- At most MaxAlive at once: each is fifteen parts and meshes and one of the engine's 31 highlights.
VfxConfig.Afterimage = {
	BodyParts = {
		"Head",
		"UpperTorso",
		"LowerTorso",
		"LeftUpperArm",
		"LeftLowerArm",
		"LeftHand",
		"RightUpperArm",
		"RightLowerArm",
		"RightHand",
		"LeftUpperLeg",
		"LeftLowerLeg",
		"LeftFoot",
		"RightUpperLeg",
		"RightLowerLeg",
		"RightFoot",
	},
	Outline = "Ink",
	OwnTone = "Wash",
	OwnHiddenWithinDegrees = 45,
	WaitSeconds = 0.5,
	CeilingSeconds = 1,
	MoveStuds = 0.5,
	ShrinkShare = 0.5,
	MaxAlive = 4,
}

-- Textures drawn along their flight. A spark streak tapers along its image's X, and a particle faces the
-- camera by default, so every spark in the game was a horizontal dash on screen whatever way it flew.
-- VelocityParallel turns the image to its velocity; checked live with sparks thrown straight up (D-111).
VfxConfig.StreakTextures = { SparkStreak = true } :: { [string]: boolean }

-- Textures that stand up in the world (D-123). A particle faces the camera and turns with it, so a flame
-- seen from a raised camera leaned with the screen; FacingCameraWorldUp keeps its tip to the sky.
VfxConfig.UprightTextures = { InkFlame = true } :: { [string]: boolean }

-- The ink each client paints on a Margin's slab (VfxLibrary.Margin, D-110). The slab is the server's
-- -- its collision, its paled pigment, its rise and sink -- and was a smooth board; tried live, two
-- rhythms of horizontal brush courses over the page's grain read as earth laid by a hand, where one
-- rhythm read as planks. U and V are studs per tile, Offset shifts a rhythm off the other's joints.
VfxConfig.WallPaint = {
	Courses = {
		{ U = 7, V = 1.6, OffsetU = 0, OffsetV = 0, Transparency = 0.3 },
		{ U = 4.5, V = 2.3, OffsetU = 2, OffsetV = 0.8, Transparency = 0.55 },
	},
	-- The grain in a darker shade of the pigment (PigmentConfig.shade), so it reads as the slab's own.
	Grain = { U = 6, V = 6, Transparency = 0.7, Shade = -0.25 },
	-- How long a client waits for the slab to replicate after the packet: the server parents it first.
	FindSeconds = 0.6,
}

-- Emitted by GlyphEffects: one per glyph, plus the shared detonation ("Explosion", reused by
-- Brand and Blot when they blow up).
VfxConfig.GlyphIds = {
	"Brand",
	"Explosion",
	"Wash",
	"Serif",
	"Sweep",
	"Bleed",
	"Margin",
	"Scorch",
	"Rupture",
	-- Phase 2 roster (docs/GAME_DESIGN.md §5)
	"Ligature",
	"Blot",
	"Binding",
	"Stipple",
	"Gilding",
	"Hairline",
	"Spiral",
	"Pounce",
	"Strike",
	"Caret",
	"Watermark",
	"Colophon",
} :: { string }

-- Emitted by GlyphService and CombatService (casting, hits, melee kit, guard).
VfxConfig.CombatIds = {
	"Cast",
	"Hit",
	"Melee",
	"Dash",
	"BlockStart",
	"BlockHit",
	"GuardBreak",
	-- A killer's KillEffect cosmetic, drawn where the victim fell (CosmeticService).
	"KillEffect",
	-- A thrown Brand that never burst -- its caster stunned, guarding or dead before it landed: the
	-- drawn one stops where the real one was (GlyphEffects.Brand, D-114).
	"Fizzle",
} :: { string }

-- Emitted by the World Boss encounter. The four attacks name themselves in WorldBossConfig, and the two
-- bookends in WorldBossService's Context.
--
-- They were missing from this file entirely, which meant six effects the game really does emit were
-- outside every gate that exists: VfxController's startup audit walks VfxConfig.Ids, and so does
-- tests/EffectCoverage.spec.luau, so a boss renderer deleted or renamed would have been silent. That is
-- the exact shape of the defect that made all twenty glyphs uncastable, found the same way -- by asking
-- what the lists do NOT contain.
VfxConfig.BossIds = {
	"BossSpawn",
	"BossSlam",
	"BossSweep",
	"BossEruption",
	"BossFury",
	-- The boss entering a new phase: the band across its face widening.
	"BossPhase",
	"BossDefeated",
} :: { string }

VfxConfig.Ids = {} :: { string }
VfxConfig.IdSet = {} :: { [string]: boolean }
for _, list in ipairs({ VfxConfig.GlyphIds, VfxConfig.CombatIds, VfxConfig.BossIds }) do
	for _, id in ipairs(list) do
		table.insert(VfxConfig.Ids, id)
		VfxConfig.IdSet[id] = true
	end
end

function VfxConfig.isId(value: any): boolean
	return type(value) == "string" and VfxConfig.IdSet[value] == true
end

return VfxConfig
