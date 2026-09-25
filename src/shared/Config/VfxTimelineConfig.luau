--!strict
-- A spell's visual, as data.
--
-- docs/JUICE_AUDIT.md measured what the imperative version produced: 34 renderers, 72 visual layers, 2.1
-- layers per effect, zero Beams, three PointLights, no ground marks, and one shared Cast visual for all
-- twenty spells. The reason is not that the renderers were written badly. It is that each one was a
-- function, so "does this effect have an anticipation" and "does this effect leave a trace" were
-- questions nobody could ask of the codebase, and therefore questions nobody answered.
--
-- Written as data, they are answerable, and tests/VfxTimeline.spec.luau asks them on every build: every
-- timeline has an anticipation phase, at least four layers, no linear interpolation, a texture key that
-- exists, and a total duration that fits inside the window the packet's Trove lives for.
--
-- The five phases are the shape of every action worth feeling (docs/JUICE_PLAN.md):
--   Anticipation  the wind-up. The one phase the old version had none of, and the reason nothing had
--                 weight: an effect that starts at full strength has no before, so it has no impact.
--   Cast          the release.
--   Travel        the projectile's flight. Absent for an instant effect.
--   Impact        the landing.
--   Residue       what the world keeps for a few seconds (art bible rule 5).
--
-- Pure data: no require, no Roblox global. Colours are not here at all -- a timeline is tinted by the
-- pigment of whatever plays it, which is what keeps art bible rule 2 (one glyph, one pigment, one colour)
-- true by construction rather than by discipline.

export type PhaseName = "Anticipation" | "Cast" | "Travel" | "Impact" | "Residue"

-- Easing curves, as Enum.EasingStyle names. "Linear" is deliberately not in this union: art bible rule 4
-- says nothing moves linearly, and the type is where that rule is cheapest to enforce.
export type Ease = "Quad" | "Cubic" | "Quart" | "Quint" | "Sine" | "Back" | "Exponential" | "Circular"
export type Direction = "In" | "Out" | "InOut"

-- What a layer's geometry is measured against. A layer that names none is written in studs and scales
-- with the effect, which is what every layer did before this existed. A layer that names one is written
-- in multiples of a length the PACKET carried, because some shapes are not this file's to know:
-- L'Effacement covers a radius that changes with the attack and with how far into the fight it is, and a
-- warning painted at any other size is a lie about where the damage is.
--   Radius  the inner measure: what a Circle attack covers, the safe centre of a Ring one, the
--           half-width a Cone has opened to by the end of its reach
--   Reach   the outer measure: how far forward a Cone goes, the outer edge of a Ring
export type Measure = "Radius" | "Reach"

-- What a layer is made of. One kind, one Roblox concept, so the runtime never has to guess.
--   Carrier  an invisible part that travels, for the phase a projectile is in flight. Layers in the
--            same phase that declare Ride are built on it instead of on a fixed point, so a trail, a
--            light and a spark stream all ride the same body without any of them knowing how it moves.
--   Sprite   a flat textured plane: seals, rings, shockwaves
--   Emitter  a ParticleEmitter
--   Beam     a Beam between two points, drawn rather than revealed
--   Trail    a Trail behind a moving part
--   Light    a PointLight
--   Mark     a ground decal that fades (the trace rule 5 demands)
--   Outline  the body the renderer passed (Context.Follow's figure) drawn as a figure: a Highlight, its
--            contour the page's ink and its fill the layer's colour, Transparency to EndTransparency (D-125)
--   Shake    a camera profile, through Feel
--   Flash    a screen pulse, through the world lighting's post-processing
--   Sound    one play through SoundController, placed like any other layer: on the carrier, on the
--            body, or at its offset. Fire and forget, like Shake and Flash.
export type LayerKind =
	"Carrier"
	| "Sprite"
	| "Emitter"
	| "Beam"
	| "Trail"
	| "Light"
	| "Mark"
	| "Mesh"
	| "Debris"
	| "Afterimage"
	| "Outline"
	| "Shake"
	| "Flash"
	| "Sound"

-- The four voices every pigment has (SoundConfig.Voices), in the order a glyph spends them. A Sound
-- layer names a voice and the renderer names the pigment, so twenty glyphs share five matters instead
-- of carrying eighty sound ids -- a school is a matter (docs/ART_BIBLE.md), and a player should tell
-- the school with their eyes shut.
export type Voice = "Attack" | "Body" | "Tail" | "Impact"

-- What a layer is coloured as (D-119). Never a colour: every role is derived from the pigment of whoever
-- plays the timeline, so one glyph still has one school.
--   Pigment  the pigment itself, wet at birth and drying (VfxConfig.InkRamp): the body of every effect
--   Core     the pigment heated toward white (VfxConfig.Heat), cooling into its pigment as it lives: the
--            hot centre that makes a burst read as energy on a pale page. Never pure white -- white is
--            invulnerability (art bible rule 7)
--   Ink      the page's charcoal: the contour and the shadow that detach a pale effect from the vellum
export type Role = "Pigment" | "Core" | "Ink"

export type Layer = {
	Kind: LayerKind,
	-- Seconds after its phase begins, and how long it lives. A layer that starts at 0 and lasts the whole
	-- phase is the exception, not the rule: the offsets between layers are what makes an effect read as
	-- one event instead of as several things happening at once.
	At: number,
	For: number,
	Ease: Ease?,
	EaseDirection: Direction?,

	-- An AssetIds.Textures key. Absent means untextured, which is legal and is what every layer falls back
	-- to while the PNG has not been uploaded.
	Texture: string?,

	-- Studs. Size is where the layer starts, EndSize where it arrives; equal values mean it does not
	-- change size, which is different from not declaring EndSize at all.
	Size: number?,
	EndSize: number?,
	-- Sprite and Mark only: the plane's second extent, Size being its width. On a Mark that is its depth
	-- along the effect's direction; on a Sprite, which stands facing the direction, it is its height. A
	-- layer that declares no Span is square, which is what every plane was before this existed, and it
	-- does not animate: something that has to grow along both axes is two layers.
	Span: number?,
	-- Studs from the effect's own frame, as {right, up, forward}. On a Mark the up component lifts it off
	-- the floor instead of moving it there, because two marks drawn in the same place z-fight, and
	-- flicker is worst exactly where a telegraph has to be legible. That lift is always studs scaled with
	-- the effect, even when OffsetFrom measures the rest of the offset against the damage: a z-fight gap
	-- is a stud quantity, never a fraction of a forty-stud reach.
	Offset: { number }?,
	-- The measure Size and EndSize, Span, and Offset are expressed in when they are not studs. A layer
	-- naming a measure the renderer did not pass is not drawn at all and the runtime says so once: the
	-- alternative is a warning painted at a twentieth of the danger it exists to warn about.
	SizeFrom: Measure?,
	SpanFrom: Measure?,
	OffsetFrom: Measure?,
	-- Carrier only: the measure its Travel is in (D-126). A hitscan ruled to where the server's ray stopped,
	-- a step to where the server put the body: Travel 1 of Reach is the whole of it.
	TravelFrom: Measure?,
	-- Built on the phase's Carrier rather than at a fixed point. Ignored when the timeline has no
	-- carrier, so a layer that rides is still drawn, standing still, rather than not drawn at all.
	Ride: boolean?,
	-- Anchored to Context.Follow -- the caster's own body -- and moved with it every frame.
	--
	-- Not a convenience. Several glyphs are zones the server re-centres on the caster on every tick
	-- (GlyphEffects.Scorch calls trustedOrigin each time), so a visual pinned to the cast point would
	-- draw a lit boundary around empty floor while the player carries an unmarked kill radius around
	-- with them. And a Trail has no meaning at all on a part that never moves: buildTrail would hand
	-- back a ribbon between two attachments that never separate, which draws nothing while costing
	-- three pooled instances to do it.
	--
	-- A layer that follows nothing is not drawn, and the runtime says so once, naming the timeline.
	Follow: boolean?,
	-- Carrier only: studs travelled over the layer's duration. The distance is scaled by Context.Scale
	-- like everything else, so one timeline serves a short poke and a long-range projectile.
	Travel: number?,
	-- Carrier only: studs the flight rises and falls again over its length, which is what separates a
	-- thrown thing from a beam that happens to move.
	Arc: number?,
	-- Mesh only (D-114): a generated volume (MeshConfig), drawn by VfxVolumes. Size and EndSize are studs of
	-- the mesh's reference extent -- an ensō's outer ink, a crown's base, a drop's length -- and Stretch and
	-- EndStretch multiply them per axis {right, up, forward} (absent: {1, 1, 1}). Face "Ground" lays it on
	-- the floor under its place, lifted by Offset's up value; "Aim" (the default) stands it at its place,
	-- turned to the effect's facing. NeedsGround skips it where there is no floor. Roll tilts it about its
	-- aim, in degrees; Spin turns it about its mesh's own axis, rad/s, from a seeded start angle within
	-- ±Jitter. Chain hands one volume from a layer to the next of the same name, which goes on from exactly
	-- where the last left it. Flourish marks a volume the lower graphics tiers leave out.
	Mesh: string?,
	Stretch: { number }?,
	EndStretch: { number }?,
	Face: ("Aim" | "Ground" | "Camera")?,
	NeedsGround: boolean?,
	Roll: number?,
	Jitter: number?,
	Chain: string?,
	Flourish: boolean?,
	-- Debris only (D-114): Count scraps of the page, each one of Meshes, thrown within Spread degrees of
	-- straight up at Speed {min, max}, slowed by Drag toward a gentle Fall (studs/s), tumbling at Tumble
	-- {min, max} rad/s, lasting Lifetime {min, max} and coloured at random from Tones (WorldConfig.Colors
	-- names: paper, never a pigment). Size is a scrap's long side in studs, give or take 30 %.
	Meshes: { string }?,
	Count: number?,
	Fall: number?,
	Tumble: { number }?,
	Tones: { string }?,
	-- Sprite only, D-119: Face "Camera" stands the plane upright and turns it, every frame, to whoever is
	-- looking -- a shockwave or a stroke read by the thrower, the target and every bystander alike, where a
	-- plane facing the aim is a hairline to anyone beside it. Roll turns a Sprite about its own facing, in
	-- degrees, before any Spin: 90 stands a horizontal brush stroke on end.
	--
	-- Afterimage only (D-116): an ink print of the body the renderer passed (Context.Follow's), left where
	-- it stood -- not Follow, which would drag it along with the body it copies -- flat in Tone (a
	-- CosmeticConfig.Tones name: ink, never a pigment, for a dodge names no school), never moved again,
	-- bleeding from Size to EndSize (a scale) and shrinking away at the end (VfxConfig.Afterimage). Laid
	-- when the body has covered Along of the path (a share of Context.Reach from Context.Origin along
	-- Context.Direction). Print is its rank: a tier draws only the prints up to QualityConfig.Afterimages.
	Tone: string?,
	Print: number?,
	Along: number?,
	-- Carrier only: how much of the flight follows the ease, the rest following time itself. A projectile
	-- the server steps at a constant speed is drawn mostly with it: fully eased, the drawn Brand trailed
	-- the damage by up to 22 studs; with 15 % of a Sine In it trails by under 3 and is never ahead
	-- (D-114). Absent means 1: the whole flight eased, as every other carrier is.
	EaseShare: number?,
	-- Radians per second about the layer's own facing axis.
	Spin: number?,
	-- What the layer is coloured as (Role above). Absent: Pigment, which is what every layer was before.
	Role: Role?,
	-- Emitter, Beam and Trail: how much of the layer's colour is added as light (LightEmission), capped by
	-- VfxConfig.MaxGlow. Absent: VfxConfig.LightEmission, ink laid on the page.
	Glow: number?,
	-- Emitter only: which way the particles leave their host. "Up" (the default, what every emitter did
	-- before) is the world's up; "Aim" is along the effect's aim -- a release thrown forward, sparks that
	-- scatter toward the target -- and "Back" against it.
	Emit: ("Up" | "Aim" | "Back")?,
	-- Placed at the caster's throwing hand (Context.Hand) rather than at the effect's origin, still turned
	-- the way the effect is aimed; Offset is then measured from the hand. A play with no hand places it
	-- at the origin as usual.
	Anchor: "Hand"?,
	-- Trail only: seconds of flight its ribbon keeps behind the head (Trail.Lifetime), when that is shorter
	-- than the layer's life. A ribbon as long as the flight is a line from the thrower to the target; a
	-- quarter of a second of it is a streak that reads as speed. Absent: the layer's For.
	Ribbon: number?,

	Transparency: number?,
	EndTransparency: number?,
	-- Sprite, Mark and Beam. A layer that fades out does so no faster than ink dries (FeelMath.inkFade),
	-- whatever ease its size was given. True when the fade IS the gesture and rides the size's own curve:
	-- a print that lightens as it spreads, ink shoved to a rim and gone. Only for a mark that states no
	-- danger once drawn -- held on the page, it would read as ground that still hurts.
	FadesWithSize: boolean?,

	-- Emitter only.
	Rate: number?,
	-- The box, in studs {across, up, along} of the layer's frame and scaled with the effect, that the
	-- particles are born anywhere in (D-123). A fire along a stroke is one emitter over the whole of it.
	-- Absent: a point.
	Area: { number }?,
	-- With an Area: born on the rim of the ellipse its across and along draw (a disc's edge) rather than
	-- anywhere in the box -- a ring of fire at a radius, not a disc of it.
	Ring: boolean?,
	-- Degrees either side of upright a particle is born leaning, and twice that per second it keeps
	-- turning: the flicker of a flame. Only on a texture that stands up (VfxConfig.UprightTextures).
	Sway: number?,
	-- With a Rate: the renderer emits the flow itself (ParticleEmitter:Emit, on the effect clock) instead of
	-- the engine's Rate, which the engine's automatic graphics quality thins -- in the lab, eighty tongues a
	-- second of fire burned as five (D-124). The game's own tiers still scale it. For an effect whose
	-- density IS its meaning (a fire), not for every trickle of sparks: the engine's thinning is also how a
	-- weak device keeps its frame rate.
	Driven: boolean?,
	Burst: number?,
	Speed: { number }?, -- {min, max}, studs per second; negative pulls inward
	Lifetime: { number }?, -- {min, max}, seconds
	Spread: number?, -- degrees
	Drag: number?,
	-- Studs per second squared pulling the particles down (ParticleEmitter.Acceleration): a bead of ink
	-- thrown up falls back to the page instead of drifting off as a cloud. Absent: none.
	Weight: number?,
	-- The share of a particle's life by which it has popped past its EndSize (VfxConfig.PopOvershoot), to
	-- relax back to it by its end: 0 -> 120 % -> 100 %, the swell that makes a flash hit rather than grow.
	-- Absent: it goes from Size to EndSize in a straight line, as every particle did before.
	Pop: number?,
	-- How stretched a particle is at birth, relaxing to its drawn shape by the end of its life, which is
	-- what makes a spark read as moving rather than as a dot that happens to be somewhere else next frame.
	-- On a streak texture it is laid along the flight (VfxTimeline.buildEmitter applies it negated: along
	-- the image's X a negative ParticleEmitter.Squash is the long one); anywhere else it is Squash as is.
	Squash: number?,

	-- Light: its brightness. Emitter, Beam and Trail: the instance's Brightness, which above 1 is what the
	-- resting bloom (threshold 1.6) catches -- only a glyph's core should ever get there.
	Range: number?,
	Brightness: number?,
	-- Where the brightness arrives. Absent means zero, which is the fade every light had before this
	-- existed. A wind-up is the case that needs the other direction: a floor that brightens as the hit
	-- approaches is the telegraph.
	EndBrightness: number?,

	-- Shake and Flash only: the profile name in FeelConfig.Shake.Profiles or LightingConfig's pulses.
	Profile: string?,

	-- Sound only. Exactly one of Sfx (a SoundConfig.Sfx key, for a sound that is its own -- the kit,
	-- the boss) and Voice (one of the four every pigment has, resolved against Context.Pigment).
	Sfx: string?,
	Voice: Voice?,
	-- The play is stretched by PlaybackSpeed so the file ends when the layer does. Only meaningful in a
	-- windowed phase: it is how a two-second warning fits a one-second window and sounds more urgent
	-- doing it, and a test keeps it there.
	Fit: boolean?,
	-- Seconds the music is pulled down for, from this play. The plan's "ducking sur les impacts lourds":
	-- a boss landing and an ultimate's own landing here; a hit past VfxLibrary's DUCK_HIT_DAMAGE there.
	-- Not a jab, and not Brand.
	Duck: number?,
}

export type Phase = {
	Name: PhaseName,
	-- Seconds. The phase's own length, which is not the same as the longest layer in it: a layer may
	-- outlive its phase, and usually does in Residue.
	Duration: number,
	-- The phase takes its length from the packet (Context.Window) instead of from Duration, and the At
	-- and For of its layers are FRACTIONS of that length rather than seconds. Duration is the fallback
	-- for a play that carried no window.
	--
	-- One thing needs this, and it needs it badly. L'Effacement warns for between 0.6 and 2 seconds
	-- depending on the attack and on the phase of the fight, and the warning has to fill exactly that
	-- window: a fixed anticipation either finishes early -- telling six players the hit has landed while
	-- it has not -- or is still filling when it lands.
	Window: boolean?,
	Layers: { Layer },
}

export type Timeline = {
	-- Why this effect looks the way it does, for whoever changes it next. Not player-visible.
	Intent: string,
	Phases: { Phase },
}

local VfxTimelineConfig = {}

-- The cast. Every glyph in the game plays this before its own effect, so it is the single most repeated
-- visual in Vellum and the one the art direction lives or dies on.
--
-- The glyph lights in the hand that casts it (D-119): a blot of its pigment pops open round a hot point, a
-- stud outside the body so the caster's own camera sees it past the shoulder, and a seal snaps open
-- around the fist and folds shut as the spell leaves. It used to draw the seal in the air three studs
-- ahead over a third of a second -- after most glyphs had already left (the Brand acts at 0.06 s, the
-- Serif at 0.03): the seal arrived behind the spell it announced, hidden by the caster's body.
-- Fourteen hundredths now, and the glyph's own timeline takes the release from there.
local CAST: Timeline = {
	Intent = "The glyph lights in the casting hand: a blot of pigment round a hot point, a seal that snaps open and folds",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.08,
			Layers = {
				-- The pigment's attack: heard as the seal is seen, which is what a wind-up sounds like.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Attack" },
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.04,
					Offset = { 0.8, 0.8, 0.2 },
					Texture = "InkBlot",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.14, 0.16 },
					Spread = 0,
					Size = 0.3,
					EndSize = 2.2,
					Pop = 0.25,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- Heated pigment, never white (rule 7): the only thing in the cast that shines.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					Role = "Core",
					Glow = 1,
					Brightness = 3,
					At = 0,
					For = 0.04,
					Offset = { 0.8, 0.8, 0.2 },
					Texture = "DustMote",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.2,
					EndSize = 0.9,
					Pop = 0.25,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The seal snapping open round the fist: Back is the overshoot, so it lands rather than arrives.
				{
					Kind = "Sprite",
					Anchor = "Hand",
					At = 0,
					For = 0.08,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 0.2,
					EndSize = 3,
					Offset = { 0.8, 0.8, 0.6 },
					Spin = 4,
					Transparency = 0,
					EndTransparency = 0.1,
				},
				-- The caster lit by their own pigment the instant they cast: how a player reads an opponent's
				-- intent from behind.
				{
					Kind = "Light",
					Anchor = "Hand",
					At = 0,
					For = 0.2,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0.8, 0.8, 0.2 },
					Range = 7,
					Brightness = 2,
				},
				-- Felt, not seen, on the release.
				{ Kind = "Shake", At = 0.04, For = 0.06, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.06,
			Layers = {
				-- The seal folds to a point. Quint-in means it barely moves, then goes all at once, which
				-- is the shape of something snapping shut.
				{
					Kind = "Sprite",
					Anchor = "Hand",
					At = 0,
					For = 0.08,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 3,
					EndSize = 0.2,
					Offset = { 0.8, 0.8, 0.6 },
					Spin = 9,
					Transparency = 0.1,
					EndTransparency = 0.6,
				},
				-- The release: sparks of the pigment flicked out of the hand along the aim.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					Emit = "Aim",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0.8, 0.8, 0.4 },
					Burst = 12,
					Speed = { 18, 32 },
					Lifetime = { 0.1, 0.2 },
					Spread = 25,
					Drag = 5,
					Squash = 0.6,
					Size = 1.1,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.4,
			Layers = {
				-- A mote or two of the pigment left hanging where the hand was. A cast is remembered for
				-- half a second, not littered over the arena.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.3,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0.8, 0.8, 0.2 },
					Rate = 8,
					Speed = { 0.4, 1.6 },
					Lifetime = { 0.4, 0.7 },
					Spread = 140,
					Drag = 1.2,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
	},
}

-- The impact. Played by every hit in the game, which makes it the second most repeated visual.
--
-- The recipe's strongest beat (D-119), small: a hot point that pops at the contact, the ring thrown along
-- the blow, a star of hot sparks, a short geyser of ink, and the burn it leaves. A fist's hit is the same
-- gesture in the page's charcoal and does not shine (Context.Unlit, D-116).
local HIT: Timeline = {
	Intent = "The blow lands: a hot point pops, a ring and a star of sparks, a spurt of ink, and the burn it leaves",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.18,
			Layers = {
				-- The hot point at the contact. Under the resting bloom's threshold: a hit is the most
				-- repeated impact in the game, and a halo on every one of them fogged a fight.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.08, 0.11 },
					Spread = 0,
					Size = 0.5,
					EndSize = 3,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The ring, thrown along the blow rather than symmetrically, so an impact reads as having
				-- come from somewhere.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.26,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Size = 0.6,
					EndSize = 10,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The blow's own stroke, cut across the point of contact the way it came (D-116): a small
				-- crescent turning the other way from the swing's. Weight, not meaning: the ring already says
				-- where, so the lower tiers leave it out.
				{
					Kind = "Mesh",
					Mesh = "Crescent",
					Flourish = true,
					At = 0,
					For = 0.14,
					Ease = "Quart",
					EaseDirection = "Out",
					Roll = -25,
					Size = 0.8,
					EndSize = 3.2,
					Transparency = 0.05,
					EndTransparency = 1,
					Spin = -10,
				},
				-- The star: hot sparks every way from the contact.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Burst = 12,
					Speed = { 18, 36 },
					Lifetime = { 0.12, 0.25 },
					Spread = 180,
					Drag = 5,
					Squash = 0.6,
					Size = 0.9,
					EndSize = 0,
				},
				-- Pigment knocked out of the target along the blow.
				{
					Kind = "Emitter",
					Emit = "Aim",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Burst = 12,
					Speed = { 14, 28 },
					Lifetime = { 0.18, 0.35 },
					Spread = 40,
					Drag = 4,
					Squash = 0.4,
					Size = 0.7,
					EndSize = 0,
				},
				-- A short spurt of ink straight up, which is what clears the attacker's own shoulder.
				{
					Kind = "Emitter",
					Role = "Ink",
					Emit = "Up",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Burst = 7,
					Speed = { 18, 32 },
					Lifetime = { 0.15, 0.28 },
					Spread = 35,
					Drag = 4,
					Squash = 0.5,
					Size = 0.9,
					EndSize = 0,
				},
				-- A light at the point of contact, which is the cheapest way to make a flat world read as
				-- having been struck in three dimensions.
				{
					Kind = "Light",
					At = 0,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 12,
					Brightness = 3.2,
				},
				{ Kind = "Flash", At = 0, For = 0.12, Profile = "PageFlash" },
			},
		},
		{
			Name = "Residue",
			Duration = 2.4,
			Layers = {
				-- The burn. It is on the ground, it is the pigment that made it, and it fades over
				-- seconds, so a fight leaves a record of itself that a player can read at a glance.
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					-- Smaller than the character it marks. A burn wider than the person who took it reads
					-- as a puddle, and a fight at two hits a second would tile the floor with them; the
					-- world is meant to remember, not to be repainted.
					Size = 3.4,
					EndSize = 4.2,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				-- A few motes of the pigment rising off the burn: the heat going out of it, not a cloud.
				{
					Kind = "Emitter",
					At = 0.04,
					For = 0.4,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Rate = 10,
					Speed = { 1.5, 3.5 },
					Lifetime = { 0.5, 0.9 },
					Spread = 55,
					Drag = 2.5,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
	},
}

-- The dodge. The third most repeated action in a match, and the one the plan says to fix before any
-- ultimate, because a player presses it hundreds of times and an ultimate once.
local DASH: Timeline = {
	Intent = "The body gathers, smears along its path, and leaves the dust it kicked up",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.05,
			Layers = {
				-- Barely a frame, but it is what makes a dash feel like a push-off instead of a teleport.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.05,
					Texture = "SmokeSoft",
					Offset = { 0, -2.6, 0 },
					Burst = 6,
					Speed = { 1, 4 },
					Lifetime = { 0.25, 0.45 },
					Spread = 90,
					Drag = 3,
					Size = 0.8,
					EndSize = 2.6,
					Transparency = 0.6,
					EndTransparency = 1,
				},
				-- The body leaves its sketch (D-116): twice, printed flat in graphite where it was a third of
				-- the way into the dash and again two thirds along, each bleeding a little and shrinking away.
				-- Here and not in Travel: a print waits for its body from the push itself, and the push on the
				-- dasher's own screen starts with this phase -- from Travel, the first was laid at half way.
				{
					Kind = "Afterimage",
					At = 0,
					For = 0.22,
					Print = 1,
					Along = 0.3,
					Tone = "Graphite",
					Ease = "Quad",
					EaseDirection = "Out",
					Size = 1,
					EndSize = 1.04,
				},
				{
					Kind = "Afterimage",
					At = 0,
					For = 0.2,
					Print = 2,
					Along = 0.7,
					Tone = "Graphite",
					Ease = "Quad",
					EaseDirection = "Out",
					Size = 1,
					EndSize = 1.04,
				},
			},
		},
		{
			Name = "Travel",
			Duration = 0.22,
			Layers = {
				-- The smear. A trail is the only layer that reads the body's real path, so it is the one
				-- that has to be there.
				{
					Kind = "Trail",
					At = 0,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					-- The dashing body itself. It drew before this said so, because buildTrail happens to
					-- prefer Context.Follow when a renderer passes one -- which made it correct by accident
					-- of the builder rather than by declaration, and invisible to every gate.
					Follow = true,
					-- Bare, like every glyph's since D-119: a brush texture on a Trail is stretched over its whole
					-- length and rendered as a faint smudge; a tapered ribbon reads as a wedge.
					Size = 3.2,
					EndSize = 0,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.22,
					Texture = "DustMote",
					Rate = 26,
					Speed = { -2, 2 },
					Lifetime = { 0.2, 0.45 },
					Spread = 120,
					Drag = 4,
					Size = 0.4,
					EndSize = 0,
				},
				-- No Shake layer here, on purpose. The dasher's own camera is pushed by MovementController
				-- the instant the command is accepted, before any packet comes back, and a second push from
				-- this packet summed on top of it (FeelConfig.Shake sums concurrent shakes) is what made the
				-- dodge feel like a stumble. Nobody else needs to feel a dodge: it is not an impact. Nor a
				-- light: the kit is charcoal ink (D-114), and ink is laid on the page, it does not shine.
				--
			},
		},
		{
			Name = "Residue",
			Duration = 0.6,
			Layers = {
				-- Where the feet left. Faint and short: a dodge is not an impact and must not look like
				-- one, or a player reading the arena mistakes a dodge for a spell that landed.
				{
					Kind = "Mark",
					At = 0,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 2.4,
					EndSize = 3,
					Transparency = 0.7,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- The punch. Thrown hundreds of times a match and the single most repeated ACTION in the game, which is
-- why docs/JUICE_PLAN.md puts it before every ultimate. It has no Impact phase: the swing is this, and
-- whether it lands is the Hit timeline's business.
local MELEE: Timeline = {
	Intent = "A short gather, one stroke swept across the front, and the dust it knocked loose",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.06,
			Layers = {
				-- Two frames of gather. It is the whole difference between a punch and a hand appearing
				-- somewhere else, and it is short enough that it never delays the input.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "DustMote",
					Offset = { 0, 0.2, 1.8 },
					Rate = 40,
					Speed = { -6, -2 },
					Lifetime = { 0.1, 0.18 },
					Spread = 150,
					Drag = 3,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.1,
			Layers = {
				-- The stroke itself: one charcoal brush crescent flicked across the front, turning as it
				-- opens, tilted so it is not a plate (D-116). It replaced a flat sprite of the same stroke,
				-- which read as a card held up in front of the fist. A swing that reads as a shape is a
				-- weapon; one that reads as a mark is a hand.
				{
					Kind = "Mesh",
					Mesh = "Crescent",
					At = 0,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0.1, 2.6 },
					Roll = 15,
					Size = 1.4,
					EndSize = 4.8,
					Transparency = 0.1,
					EndTransparency = 1,
					Spin = 9,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0, 0.1, 3.2 },
					Burst = 9,
					Speed = { 10, 20 },
					Lifetime = { 0.12, 0.24 },
					Spread = 55,
					Drag = 5,
					Squash = 0.35,
					Size = 0.4,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.3,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.25,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0, 2.6 },
					Rate = 10,
					Speed = { 0.5, 2 },
					Lifetime = { 0.3, 0.6 },
					Spread = 130,
					Drag = 1.5,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
	},
}

-- The tap (D-119): what a player's own hand does on the frame they press a pigment, before the server has
-- heard of it. A hot point of that pigment lit in the throwing hand and a few beads of it shaken off -- the
-- spell visibly starting where it will leave from, at the press, rather than a round trip later.
--
-- Local only (VfxController.tap): nobody else sees it, and it promises nothing. The server's Cast, and the
-- glyph's own anticipation in the same hand, are what everybody sees.
local TAP: Timeline = {
	Intent = "A pigment pressed lights in the hand that will throw it",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.05,
			Layers = {
				-- The same place the glyph will light in: outside the body, where the thrower's camera sees it.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					Role = "Core",
					Glow = 1,
					Brightness = 2.5,
					At = 0,
					For = 0.04,
					Offset = { 0.8, 0.8, 0.2 },
					Texture = "DustMote",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.08, 0.1 },
					Spread = 0,
					Size = 0.2,
					EndSize = 1.2,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.04,
					Offset = { 0.8, 0.8, 0.2 },
					Texture = "InkBlot",
					Burst = 7,
					Speed = { 5, 10 },
					Lifetime = { 0.15, 0.25 },
					Spread = 180,
					Drag = 6,
					Size = 0.45,
					EndSize = 0.15,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Anchor = "Hand",
					At = 0,
					Offset = { 0.8, 0.8, 0.2 },
					For = 0.12,
					Ease = "Quad",
					EaseDirection = "Out",
					Range = 5,
					Brightness = 1.2,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.2,
			Layers = {
				-- A mote or two of the pigment still hanging where the hand was.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.15,
					Offset = { 0.8, 0.8, 0.2 },
					Texture = "DustMote",
					Rate = 12,
					Speed = { 0.3, 1 },
					Lifetime = { 0.3, 0.5 },
					Spread = 180,
					Drag = 1.5,
					Size = 0.2,
					EndSize = 0,
				},
			},
		},
	},
}

-- Brand (Cinnabar, projectile). The first glyph every player learns and the one they throw most, so it
-- is the first of the twenty to be rebuilt, twice: in ink (D-114), then with a heated core (D-119).
--
-- What it replaced was a ball with Roblox's own Fire class on it, flying in a straight line at a constant
-- speed for a full second. Three of those four words are a rule broken: nothing travels linearly (rule
-- 4), nothing in this game is a stock engine effect, and a thing thrown by a hand arcs.
--
-- Three beats, and each one is somewhere the eye already is. It is born in the hand: the shared Cast lights
-- a blot of pigment round a hot point at the fist, and the throw flicks sparks and a stroke of ink out of
-- it along the aim. It flies as a drop
-- of pigment with a short dark stroke behind it and a burning line inside that stroke -- a streak a
-- quarter of a second long, not a line from the thrower to the target. And it lands (Explosion).
--
-- It has no Impact phase, because its impact is a separate packet: the server detonates it and emits
-- Explosion, which has its own timeline below. That split is not an accident of the old code, it is
-- correct -- the projectile does not know where it will end, and the blast does not know where it began.
local BRAND: Timeline = {
	Intent = "Born hot in the hand, flicked out along the throw, and flown as a drop with a burning stroke behind it",
	Phases = {
		{
			Name = "Anticipation",
			-- With Cast, exactly GlyphConfig's Windup: the flight starts on the frame the server lets
			-- go (D-114). tests/Flight.spec.luau holds the two together.
			Duration = 0.04,
			Layers = {
				-- The glyph lights in the hand with the shared Cast timeline (the blot, the hot point, the seal and
				-- the light at the fist); what is the Brand's own is the drop, and the throw below.
				--
				-- The drop gathering where the server lets go of it: grown, never appeared, drawn out along the
				-- throw, and handed to the flight (Chain), which carries it on from exactly where this leaves it
				-- (D-114). Quad Out, not Back: in 0.06 s a Back did most of its growth in one frame and overshot.
				{
					Kind = "Mesh",
					Mesh = "Drop",
					Chain = "Head",
					At = 0,
					For = 0.06,
					Ease = "Quad",
					EaseDirection = "Out",
					Offset = { 0, 0.4, 4 },
					Size = 0.2,
					EndSize = 1.6,
					Stretch = { 1, 1, 1 },
					EndStretch = { 0.7, 0.7, 1.8 },
					Transparency = 0,
					EndTransparency = 0,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.02,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The release: sparks of the pigment flicked out of the hand along the throw, stretched by their
				-- speed. The pigment, not the core: pale sparks vanish against a pale floor.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					Offset = { 0.8, 0.8, 0.2 },
					Emit = "Aim",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Burst = 14,
					Speed = { 24, 42 },
					Lifetime = { 0.1, 0.22 },
					Spread = 20,
					Drag = 5,
					Squash = 0.7,
					Size = 1.3,
					EndSize = 0,
				},
				-- The throwing hand's sweep: one crescent of the page's ink flicked out of the hand, tilted so it
				-- is not a flat plate, spinning, and gone in a sixth of a second. Dark, so it holds on a pale page.
				{
					Kind = "Mesh",
					Mesh = "Crescent",
					Anchor = "Hand",
					Role = "Ink",
					At = 0,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0.8, 0.8, 0.6 },
					Roll = 25,
					Size = 0.8,
					EndSize = 3.6,
					Transparency = 0,
					EndTransparency = 1,
					Spin = 9,
				},
			},
		},
		{
			Name = "Travel",
			-- One second at ninety studs a second, which is exactly GlyphConfig's Speed and Fuse for this
			-- glyph. tests/VfxTimeline.spec.luau holds the carrier's distance to the glyph's declared
			-- Range: a visual that outflies the spell lies to the player about where they are safe.
			Duration = 1,
			Layers = {
				-- From the server's spawn point, SpawnOffset ahead, at its speed: mostly time, 15 % of a
				-- Sine In, so the drawn one trails the real one by under three studs and meets it at the
				-- end (D-114). It used to leave from the chest on Sine Out, 0.2 s late, and trailed the
				-- damage by up to 22 studs. A burst lands it early (VfxTimeline.land).
				{
					Kind = "Carrier",
					At = 0,
					For = 1,
					Offset = { 0, 0.4, 4 },
					Ease = "Sine",
					EaseDirection = "In",
					EaseShare = 0.15,
					Travel = 90,
					-- A stud and a half of rise and fall over ninety. Barely visible, and the whole reason
					-- it reads as thrown rather than fired; halved so the drawn one stays inside the blast.
					Arc = 1.5,
				},
				-- The drop itself, riding the flight head first: stretched along its speed at the throw, settling
				-- round as drag would. It is the threat, so it does not fade in flight: its burst splats it
				-- (VfxTimeline.land), and so does the end of a flight nothing burst.
				{
					Kind = "Mesh",
					Mesh = "Drop",
					Chain = "Head",
					Ride = true,
					At = 0,
					For = 1,
					Ease = "Exponential",
					EaseDirection = "Out",
					Size = 1.6,
					EndSize = 1.3,
					Stretch = { 0.7, 0.7, 1.8 },
					EndStretch = { 1, 1, 1.1 },
					Transparency = 0,
					EndTransparency = 0,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- The stroke behind it, in the page's ink: as thick as the drop where it leaves it and tapering to
				-- a point a fifth of a second back. The contour that detaches a red drop from a pale floor.
				-- Untextured on purpose: a trail stretches its texture over its whole length, and the brush
				-- stroke drawn that way was a faint smudge in the lab where a bare ribbon is a clean wedge.
				{
					Kind = "Trail",
					At = 0,
					For = 1,
					Ride = true,
					Role = "Ink",
					Ribbon = 0.2,
					Size = 1.1,
					EndSize = 0.05,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The burning line inside it: hot at the drop, cooling into the pigment along the ribbon.
				{
					Kind = "Trail",
					At = 0,
					For = 1,
					Ride = true,
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					Ribbon = 0.12,
					Size = 0.5,
					EndSize = 0.02,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- Embers shed by the heat, and beads of pigment flung off the drop: what makes the stroke a
				-- thing moving through air rather than a line drawn on the screen.
				{
					Kind = "Emitter",
					At = 0,
					For = 1,
					Ride = true,
					Texture = "DustMote",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					Rate = 30,
					Speed = { 0.5, 2 },
					Lifetime = { 0.15, 0.3 },
					Spread = 180,
					Drag = 2,
					Size = 0.35,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1,
					Ride = true,
					Texture = "InkBlot",
					Rate = 20,
					Speed = { 0.5, 3 },
					Lifetime = { 0.25, 0.5 },
					Spread = 180,
					Drag = 2,
					Size = 0.45,
					EndSize = 0.15,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 1,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 14,
					Brightness = 2.4,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.6,
			Layers = {
				-- What hangs in the air along the path after the body has gone. Not a mark on the ground:
				-- the projectile never touched it.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Rate = 6,
					Speed = { 0.3, 1.4 },
					Lifetime = { 0.5, 0.9 },
					Spread = 160,
					Drag = 1.2,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
	},
}

-- The detonation every exploding projectile shares (GlyphEffects.explode). Scaled by the blast radius
-- the server sends, so one timeline serves a Brand at seven studs and a Blot at ten.
--
-- The loudest frame of the throw, built so that its first frames are its biggest (D-119): a hot flash
-- that pops, a ring of pigment struck toward the thrower's camera, a star of hot sparks and dark ones,
-- beads of pigment thrown up and a crown of ink falling back -- then the drawn clock holds still for a
-- few hundredths of a second on a hit (FeelConfig.EffectHold) while the page keeps the burn.
local EXPLOSION: Timeline = {
	Intent = "The page is struck through: a hot flash, a ring and a star of sparks, a splash, and a burn that stays",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.22,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The flash: one hot point swelling past the blast's heart and gone in a seventh of a second.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.14 },
					Spread = 0,
					Size = 1,
					EndSize = 5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The shock: a ring of the pigment struck out of the burst, standing turned to whoever looks, so
				-- the thrower, the target and a bystander all see it whole. Quart Out: at its widest in the
				-- first frames.
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.25,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Size = 1,
					EndSize = 18,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The blast's edge, drawn: one brush circle of the page's ink laid on the floor, opening to exactly
				-- the reach the server damaged (twice its radius), its open end toward the thrower (D-114).
				{
					Kind = "Mesh",
					Mesh = "Enso",
					Face = "Ground",
					Role = "Ink",
					At = 0,
					For = 0.45,
					Ease = "Quint",
					EaseDirection = "Out",
					SizeFrom = "Radius",
					Size = 0.3,
					EndSize = 2,
					Offset = { 0, 0.12, 0 },
					Transparency = 0.05,
					EndTransparency = 1,
					Spin = 1.1,
					Jitter = 0.35,
				},
				-- A thinner ring of the pigment overtaking it the other way round: weight, not meaning, so the
				-- lower tiers leave it out.
				{
					Kind = "Mesh",
					Mesh = "SplitRing",
					Face = "Ground",
					Flourish = true,
					At = 0.03,
					For = 0.26,
					Ease = "Exponential",
					EaseDirection = "Out",
					SizeFrom = "Radius",
					Size = 0.2,
					EndSize = 1.9,
					Offset = { 0, 0.14, 0 },
					Transparency = 0.3,
					EndTransparency = 1,
					Spin = -2.5,
					Jitter = math.pi,
				},
				-- The splash: a crown of ink thrown up off the page and falling back into it -- round beads,
				-- never points, below the waist, and high and dark for under a third of a second (rule 9).
				-- Only on a floor: a crown in mid-air is a crown of nothing.
				{
					Kind = "Mesh",
					Mesh = "Crown",
					Face = "Ground",
					NeedsGround = true,
					Chain = "Crown",
					At = 0.02,
					For = 0.12,
					Ease = "Back",
					EaseDirection = "Out",
					SizeFrom = "Radius",
					Size = 0.45,
					EndSize = 0.8,
					Stretch = { 1, 0.08, 1 },
					EndStretch = { 1, 0.5, 1 },
					Offset = { 0, 0.1, 0 },
					Transparency = 0,
					EndTransparency = 0,
					Spin = 0.6,
					Jitter = math.pi,
				},
				{
					Kind = "Mesh",
					Mesh = "Crown",
					Face = "Ground",
					NeedsGround = true,
					Chain = "Crown",
					At = 0.14,
					For = 0.22,
					Ease = "Quad",
					EaseDirection = "In",
					SizeFrom = "Radius",
					Size = 0.8,
					EndSize = 0.95,
					Stretch = { 1, 0.5, 1 },
					EndStretch = { 1.05, 0.04, 1.05 },
					Offset = { 0, 0.1, 0 },
					Transparency = 0,
					EndTransparency = 1,
					Spin = 0.6,
					Jitter = math.pi,
				},
				-- Scraps of the page torn up by the blast, tumbling, rocking down and lying where they fall until
				-- they fade. Soaked in the burn: charcoal, never a pigment -- and never a pale tone either: the
				-- page's own and the training ring's wash were measured invisible on the floors they fell on.
				-- Weight, not meaning: the lower tiers leave them out.
				{
					Kind = "Debris",
					Meshes = { "ScrapA", "ScrapB" },
					Flourish = true,
					At = 0.02,
					For = 0.04,
					Count = 8,
					Size = 0.8,
					Speed = { 12, 24 },
					Spread = 55,
					Lifetime = { 1, 1.6 },
					Drag = 3,
					Fall = 7,
					Tumble = { 6, 14 },
					Tones = { "Ink" },
				},
				-- Beads of pigment thrown up out of the burst, braked, and falling back to the page as they dry:
				-- a splash, not a cloud drifting over the target.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "InkBlot",
					Burst = 16,
					Speed = { 18, 32 },
					Lifetime = { 0.22, 0.38 },
					Spread = 60,
					Drag = 4,
					Weight = 60,
					Size = 0.8,
					EndSize = 0.15,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The star: hot sparks in every direction, long at birth and gone in a third of a second, and a
				-- geyser of dark ones straight up, tall enough to clear the thrower's own head from behind -- the
				-- camera a thrower has puts the target right behind it.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					At = 0,
					For = 0.06,
					Texture = "SparkStreak",
					Burst = 24,
					Speed = { 26, 52 },
					Lifetime = { 0.15, 0.3 },
					Spread = 180,
					Drag = 5,
					Squash = 0.7,
					Size = 1.2,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					Emit = "Up",
					At = 0,
					For = 0.06,
					Texture = "SparkStreak",
					Burst = 12,
					Speed = { 26, 44 },
					Lifetime = { 0.2, 0.35 },
					Spread = 35,
					Drag = 4,
					Squash = 0.6,
					Size = 1.3,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 26,
					Brightness = 5,
				},
				{ Kind = "Shake", At = 0, For = 0.12, Profile = "Heavy" },
				{ Kind = "Flash", At = 0, For = 0.16, Profile = "PageFlash" },
			},
		},
		{
			Name = "Residue",
			Duration = 3,
			Layers = {
				-- The burn: a blot of the pigment drying on the page over cracks of its charcoal. Larger and
				-- longer than a plain hit's, because a detonation is the loudest thing that happens to a patch
				-- of ground in this game.
				{
					Kind = "Mark",
					At = 0,
					For = 2.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 6.5,
					EndSize = 7.5,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					Role = "Ink",
					At = 0,
					For = 3,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 9,
					EndSize = 11,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				-- Embers still rising off the burn: the heat going out of it, not a cloud over it.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 0.6,
					At = 0.05,
					For = 0.7,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Rate = 10,
					Speed = { 1, 3 },
					Lifetime = { 0.6, 1.2 },
					Spread = 50,
					Drag = 1.5,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
	},
}

-- Wash (Indigo, area). The Indigo school is what contains, and this is its wave: a front that leaves the
-- caster's hand and sweeps the thirty-four studs between SpawnOffset (6) and Range (40), damaging each
-- target once inside a sphere of HitRadius 8 and shoving it back.
--
-- The French name is the design: a lavis is a broad dilute layer of pigment dragged across a page with a
-- loaded flat brush. So this glyph is not water. It is a wash -- a wide wet stroke painted across the
-- floor, darkest at its leading edge where the pigment piles up against the dry paper, thinning behind it.
-- That leading line is the whole read, and it is the one image no other battleground has.
--
-- What it replaced was a translucent Glass slab the width of the hit sphere, tweened to the end of its
-- range and then shrunk flat. Glass is a stock Roblox material, the slab was a rectangle rather than a
-- mark, nothing preceded it, and the floor it crossed forgot it instantly.
--
-- THE TIMING IS THE WHOLE SPELL, so it is worth the paragraph. GlyphEffects.Wash emits this packet and
-- then steps its damage sphere immediately, at a constant rate, 6 to 40 over TravelTime 0.8. Every phase
-- in front of the carrier is a phase the damage spends ahead of the ink, so Anticipation and Cast are cut
-- to 0.06 and 0.04 -- two frames and one, the floor MELEE already runs on -- and the carrier takes the
-- remaining 0.7 and lands at 0.80 with the server. Sine/Out over that span keeps the drawn front within
-- 4.2 studs behind and 5.4 ahead of the true centre, which means it never leaves the sphere that hurts.
-- That number is the point: a front drawn outside its own hitbox is a hit out of nothing in one direction
-- and a free dodge in the other, and rule 4 still forbids drawing the server's constant rate as a constant
-- rate. A longer wind-up on this glyph is not a style choice, it is a lie with a measurable size in studs.
--
-- How it is built: the start line is wetted on the page (not in the air -- the shared Cast timeline is
-- drawing the seal in front of the caster over exactly these frames, and it owns that space), the pigment
-- is thrown low, and then ONE invisible carrier flies the front. The leading edge, the wet curtain, the
-- shed pigment and the light all ride it, so none of them can disagree about where the danger is. Three
-- marks are laid on the floor as the front crosses them, in that order, and they are what the world keeps.
--
-- This timeline must be played with no Follow in its Context. buildTrail anchors to Context.Follow when it
-- is given one, and followCarrier then writes that part's CFrame every frame: a Follow here would drag the
-- caster's own root thirty-four studs down the wave.
local WASH: Timeline = {
	Intent = "A loaded brush is dragged forward: a dark wet front at the edge of the damage, on the server's own clock, and the strip it soaks",
	Phases = {
		{
			Name = "Anticipation",
			-- Two frames. Everything spent here is spent behind the damage (see above), and the mark and
			-- the draw-in both outlive the phase anyway.
			Duration = 0.06,
			Layers = {
				-- The page wetted where the wash will start, at the real SpawnOffset. Wet paper is what
				-- makes a wash possible, it is the earliest honest word the glyph can say about where the
				-- sweep begins, and it is on the floor rather than in the air so it never competes with
				-- the seal the Cast timeline is drawing over the same frames.
				{
					Kind = "Mark",
					At = 0,
					For = 0.34,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 1,
					EndSize = 9,
					Offset = { 0, 0, 6 },
					Transparency = 0.55,
					EndTransparency = 0.85,
				},
				-- The brush loading: beads of pigment pulled INTO the hand, not off it. Negative speed is the
				-- idea the cast uses -- a wind-up must read as gathering or it reads as a spell already half
				-- spent -- and the matter is ink, because Indigo is wet; it was grey smoke, and grey smoke on a
				-- pale page is nobody's school (D-119).
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.06,
					Texture = "InkBlot",
					Offset = { 0.8, 0.8, 0.2 },
					Burst = 10,
					Speed = { -12, -6 },
					Lifetime = { 0.08, 0.14 },
					Spread = 180,
					Drag = 2.6,
					Size = 0.6,
					EndSize = 0.1,
					Transparency = 0,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.04,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The pigment leaving the brush, thrown forward and falling onto the floor: a wash is laid down,
				-- it is not sprayed. There is no Shake here; the Cast timeline playing in parallel already
				-- fired the Cast profile, and firing it twice is two shakes, not weight.
				{
					Kind = "Emitter",
					Emit = "Aim",
					At = 0,
					For = 0.04,
					Texture = "InkBlot",
					Offset = { 0, -1.4, 5 },
					Burst = 14,
					Speed = { 14, 26 },
					Lifetime = { 0.3, 0.55 },
					Spread = 30,
					Drag = 3,
					Weight = 40,
					Size = 1,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Travel",
			-- Starts 0.1 after the packet and runs 0.7, so it ends at 0.80: the instant the server's own
			-- front reaches Range. The two fronts finish together and stay within one hit radius of each
			-- other the whole way.
			Duration = 0.7,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.65, For = 0.05, Voice = "Impact" },
				{
					Kind = "Carrier",
					At = 0,
					For = 0.7,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, -2.2, 6 },
					Travel = 34,
					-- A stud and a half of crest. A wave at exactly floor height is a sliding decal; one
					-- that lifts and settles once is water, and 1.6 studs is far inside the eight the
					-- sphere forgives.
					Arc = 1.6,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- The leading edge, the signature layer: a stroke turned to whoever looks at it, widening to the full sixteen-stud hit diameter as it goes. It ends half a stud wider than the
				-- sphere that hurts, never narrower -- and it is drawn seven studs AHEAD of the carrier, at the
				-- sphere's leading edge: the damage reaches a target when the sphere's rim does, and a front
				-- drawn at its centre arrived a third of a second after the hit it announced (the lab, D-119).
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.7,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0.6, 7 },
					Size = 9,
					EndSize = 16.6,
					Transparency = 0.05,
					EndTransparency = 0.55,
				},
				-- Its wet lip in the page's ink, just in front: where the pigment piles up against dry paper,
				-- the darkest line of a wash, and what detaches an indigo front from a pale floor.
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.7,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Role = "Ink",
					Offset = { 0, 0.1, 7.6 },
					Size = 8,
					EndSize = 15,
					Transparency = 0.1,
					EndTransparency = 0.8,
				},
				-- The wet curtain: a five-stud ribbon riding the front, tapering to 1.4 at its tail. A
				-- riding trail turns its face to the camera (buildTrail), because a sheet standing along
				-- the line of travel is seen edge-on by the caster and by whoever the wave is sweeping
				-- toward -- the two people it is for. The Offset lifts it off the floor. The stroke ON the
				-- floor is the business of the three marks below; Mark is the only layer kind that lies
				-- flat.
				{
					Kind = "Trail",
					At = 0,
					For = 0.7,
					Ride = true,
					Ribbon = 0.25,
					Size = 4,
					EndSize = 0.5,
					Offset = { 0, 1.7, 0 },
					Transparency = 0.35,
					EndTransparency = 1,
				},
				-- Beads of pigment shed off the back of the front and falling to the page: a brush depositing,
				-- where a file of identical grey puffs read as exhaust (the lab's before sheet).
				{
					Kind = "Emitter",
					At = 0,
					For = 0.66,
					Ride = true,
					Emit = "Back",
					Texture = "InkBlot",
					Offset = { 0, -0.6, -1.6 },
					Rate = 30,
					Speed = { 2, 6 },
					Lifetime = { 0.3, 0.5 },
					Spread = 40,
					Drag = 3,
					Weight = 30,
					Size = 0.8,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The crest: hot points of the pigment spitting off the leading edge, and spray of ink torn up
				-- by it -- the only things on the wave that shine, and the dark that makes them read.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.66,
					Ride = true,
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					Emit = "Up",
					Texture = "DustMote",
					Offset = { 0, 1, 7 },
					Rate = 30,
					Speed = { 1, 4 },
					Lifetime = { 0.15, 0.3 },
					Spread = 60,
					Drag = 2,
					Size = 0.5,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.66,
					Ride = true,
					Role = "Ink",
					Emit = "Up",
					Texture = "SparkStreak",
					Offset = { 0, 0.5, 7 },
					Rate = 24,
					Speed = { 8, 16 },
					Lifetime = { 0.12, 0.22 },
					Spread = 50,
					Drag = 3,
					Squash = 0.5,
					Size = 0.8,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.7,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 16,
					Brightness = 2.6,
				},
				-- The stroke itself, on the page, in three marks at twelve, twenty-three and thirty-four
				-- studs. Their At values are not spaced by eye: they are the times the carrier's own
				-- Sine/Out curve puts the front over each point, so the floor stains in the order the
				-- brush crossed it and the strip reads as dragged rather than dropped. EndSize 11 against
				-- an 11-stud spacing makes them abut instead of overlap: two marks sharing a patch of
				-- floor share the same 0.03 ground lift and z-fight, which reads as flicker. Narrower than
				-- the sixteen that hurt, and that is the safe side: each is laid behind the front, on floor
				-- the damage has already crossed, so nothing about them is a warning. They hold dark while
				-- the front is still travelling -- ink dries, it does not flash (FeelMath.inkFade).
				{
					Kind = "Mark",
					At = 0.08,
					For = 2.4,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 5,
					EndSize = 11,
					Offset = { 0, 0, 12 },
					Transparency = 0.32,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.23,
					For = 2.4,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 5,
					EndSize = 11,
					Offset = { 0, 0, 23 },
					Transparency = 0.32,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.48,
					For = 2.4,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 5,
					EndSize = 11,
					Offset = { 0, 0, 34 },
					Transparency = 0.32,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			-- The marks laid during the flight are still soaking through most of this phase; what is left
			-- to add is the page drying over the middle of the strip.
			Duration = 2.2,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.7,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, -1, 23 },
					Rate = 8,
					Speed = { 0.4, 1.6 },
					Lifetime = { 0.5, 0.9 },
					Spread = 150,
					Drag = 1.2,
					Size = 0.32,
					EndSize = 0,
				},
			},
		},
	},
}

-- Bleed (Indigo, zone). A bleed is what printers call ink running past the edge it was given, wicking into
-- the fibre of paper that is already wet. That is the glyph: a patch of the page ruined, that drinks
-- whatever stands in it -- the slow -- and drinks three times before it dries.
--
-- The three drinks are not decoration. GlyphEffects.Bleed calls tickZone with Ticks = 3 and
-- TickInterval = 1, so the zone damages at t = 0, 1 and 2 and then does nothing. A zone drawn as one
-- continuous cloud makes those three moments invisible, and a player who cannot see the rhythm of a zone
-- cannot cross it on purpose.
--
-- IT HAS NO ANTICIPATION PHASE, and that is deliberate rather than an omission. The server does not wind
-- up: it emits this packet and damages in the same instant. Bleed declares neither Cast nor Travel, so the
-- spec asks for no anticipation, and HIT and EXPLOSION both open on Impact for exactly this reason -- the
-- wind-up is the shared Cast timeline playing in parallel, which is the seal the player actually reads.
-- Anything in front of the Impact phase here would push all three drinks behind damage that has already
-- landed. With it gone they fall on 0, 1 and 2 to the frame.
--
-- What it replaced was a Ball part grown to the zone radius and a steam emitter switched off at the end:
-- a sphere that grows and fades, which is the one shape this direction exists to refuse. It also said
-- nothing about ticks, nothing about the slow, and left no trace on a floor it stood on for three seconds.
--
-- The packet's Origin is already the zone centre (the server offsets it twelve studs forward before
-- emitting), so nothing here carries a forward offset. The whole thing runs 4.6 seconds, which is not a
-- round number chosen for the tail: SlowDuration is 2.5 and the last tick applies it at t = 2, so 4.5 is
-- when the last player it slowed gets their speed back. The page finishes drying when the spell is over.
local BLEED: Timeline = {
	Intent = "The page is wetted, drinks three times on the server's clock, and dries stained",
	Phases = {
		{
			Name = "Impact",
			-- Two point two: the third drink fires at 2.0 and its layers outlive the phase, which is the
			-- tail of a zone that has stopped hurting but has not dried.
			Duration = 2.2,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The page wetted to the zone's edge in a seventh of a second, then soaking: one spread of the
				-- pigment, held darker than it was (a pale stain on a pale page said nothing).
				{
					Kind = "Mark",
					At = 0,
					For = 0.14,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2,
					EndSize = 19.5,
					Transparency = 0.6,
					EndTransparency = 0.35,
				},
				{
					Kind = "Mark",
					At = 0.14,
					For = 2.06,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 19.5,
					EndSize = 21,
					Transparency = 0.35,
					EndTransparency = 0.5,
				},
				-- The zone's edge, in the page's charcoal, as far as the server drinks and no further: the
				-- boundary a player crosses on purpose (D-121).
				{
					Kind = "Mesh",
					Mesh = "Enso",
					Face = "Ground",
					Role = "Ink",
					At = 0,
					For = 2.2,
					Ease = "Quint",
					EaseDirection = "Out",
					SizeFrom = "Radius",
					Size = 0.3,
					EndSize = 2,
					Offset = { 0, 0.12, 0 },
					Transparency = 0.1,
					EndTransparency = 1,
					Spin = 0.4,
					Jitter = 0.35,
				},
				-- The drink at 0 s, on the server's tick: a spike of the pigment struck up at the heart and a hot
				-- point where it lands, and a ring of the pigment drawn in from the zone's edge to its heart,
				-- the page drinking.
				{
					Kind = "Mark",
					At = 0,
					For = 0.4,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 19,
					EndSize = 4,
					Transparency = 0.15,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -1.2, -3, 0.8 },
					Size = 1,
					EndSize = 8,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { -1.2, -1.5, 0.8 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 15,
					Brightness = 2.4,
				},
				-- The drink at 1 s, on the server's tick: a spike of the pigment struck up at the heart and a hot
				-- point where it lands, and a ring of the pigment drawn in from the zone's edge to its heart,
				-- the page drinking.
				{
					Kind = "Mark",
					At = 1,
					For = 0.4,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 19,
					EndSize = 4,
					Transparency = 0.15,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 1,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 1.4, -3, -0.6 },
					Size = 1,
					EndSize = 8,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 1,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 1.4, -1.5, -0.6 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 1,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 15,
					Brightness = 2.4,
				},
				-- The drink at 2 s, on the server's tick: a spike of the pigment struck up at the heart and a hot
				-- point where it lands, and a ring of the pigment drawn in from the zone's edge to its heart,
				-- the page drinking.
				{
					Kind = "Mark",
					At = 2,
					For = 0.4,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 19,
					EndSize = 4,
					Transparency = 0.15,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 2,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -0.4, -3, -1.4 },
					Size = 1,
					EndSize = 8,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 2,
					For = 0.04,
					Texture = "DustMote",
					Offset = { -0.4, -1.5, -1.4 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 2,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 15,
					Brightness = 2.4,
				},
				-- Beads of the pigment drawn inward across the zone the whole time it drinks.
				{
					Kind = "Emitter",
					At = 0.04,
					For = 2.1,
					Texture = "InkBlot",
					Offset = { 0, 1.2, 0 },
					Rate = 16,
					Speed = { -7, -2 },
					Lifetime = { 0.4, 0.85 },
					Spread = 180,
					Drag = 2.4,
					Size = 0.6,
					EndSize = 0.1,
					Transparency = 0,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Residue",
			-- Two point four, ending at 4.6. The last tick's slow expires at 4.5: the stain finishes
			-- drying when the spell finishes acting, not when a round number ran out.
			Duration = 2.4,
			Layers = {
				-- What is left: a patch of page that took too much ink and will not take any more. It
				-- picks up exactly where the pool ends, so the floor never carries two decals at one
				-- height.
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 21,
					EndSize = 22.5,
					Transparency = 0.62,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.8,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.6, 0 },
					Rate = 7,
					Speed = { 0.4, 1.8 },
					Lifetime = { 0.5, 0.95 },
					Spread = 160,
					Drag = 1.2,
					Size = 0.34,
					EndSize = 0,
				},
			},
		},
	},
}

-- Binding (Indigo, counter). The French name decides this one: a reliure is a bookbinding, the sewing that
-- holds a signature into a spine. So the glyph does not cage anybody. It SEWS them into the page -- a
-- frame ruled around them, a stitch pulled shut, a thread through the body, and the whole thing holding
-- until the ink runs out.
--
-- What it replaced was a Glass ball grown around each target with a swirl emitter inside: stock material,
-- a sphere that grows and fades, and no relationship at all to the one number that matters here.
--
-- That number is RootDuration. GlyphEffects.Binding pins WalkSpeed at zero for one and a half seconds and
-- leaves the victim able to fight back, so both players spend that time deciding what to do with it. The
-- ink emptying out of the binding IS the timer, readable by the person held and the person holding, with
-- no icon, bar or number -- which only works if it empties on the right frame. The server applies the root
-- BEFORE it emits this packet, so the clock is already running when the first layer is drawn: the phases
-- are cut so that anticipation plus cast plus impact comes to exactly 1.50, the ink is gone the instant the
-- legs work, and the Residue burst that announces the release is not a fifth of a second late.
--
-- The server sends Targets, the roots it actually pinned, and the renderer plays this once per point (it
-- falls back to Origin when the grab caught nobody). So the frame is sized to a BODY, not to the grab: a
-- ring at the fourteen-stud grab diameter would be centred on a victim rather than on the grab centre
-- eight studs ahead of the caster, so it would show nobody's reach and bury the person it binds.
-- D-123: struck on the frame the server roots, round the one it caught (VfxLibrary.Binding plays it on the
-- target), as four bars of ink standing for the whole root.
local BINDING: Timeline = {
	Intent = "A prison of ink bars is struck up round the one it catches and holds for as long as the root",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- Ink drawn toward the catch in two frames: the server roots on the packet.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Offset = { 0, 0.2, -1.4 },
					Burst = 12,
					Speed = { -15, -8 },
					Lifetime = { 0.08, 0.14 },
					Spread = 28,
					Squash = 0.5,
					Size = 0.45,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
			},
		},
		{
			Name = "Impact",
			Duration = 1.5,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The prison, on the frame the server roots the target and for as long (RootDuration 1.5): four bars of the
				-- pigment struck up out of the page round it, turned to every camera, standing until the root ends (D-123).
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 1.5,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 2.2, -3, 0 },
					Size = 1,
					EndSize = 9,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.02,
					For = 1.48,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -2.2, -3, 0 },
					Size = 1,
					EndSize = 9,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.04,
					For = 1.46,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 2.2 },
					Size = 1,
					EndSize = 9,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.06,
					For = 1.44,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, -2.2 },
					Size = 1,
					EndSize = 9,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The seal under it, on the page, for the same time.
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 2,
					EndSize = 8,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 4,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- A spurt of ink off the snap, up past the bars.
				{
					Kind = "Emitter",
					Role = "Ink",
					Emit = "Up",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 0 },
					Burst = 10,
					Speed = { 22, 40 },
					Lifetime = { 0.15, 0.3 },
					Spread = 30,
					Drag = 4,
					Squash = 0.6,
					Size = 1.1,
					EndSize = 0,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 5,
					EndSize = 5.8,
					Transparency = 0.22,
					EndTransparency = 0.58,
				},
				{
					Kind = "Light",
					Brightness = 2.6,
					At = 0,
					For = 1.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 12,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Residue",
			Duration = 1.2,
			Layers = {
				-- The bars let go: the ink they were made of thrown out as they fall.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.1,
					Texture = "SparkStreak",
					Burst = 20,
					Speed = { 11, 24 },
					Lifetime = { 0.22, 0.45 },
					Spread = 180,
					Squash = 0.5,
					Size = 0.5,
					EndSize = 0,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.2,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 5.8,
					EndSize = 7.2,
					Transparency = 0.58,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Margin (Umber, wall). An Indigo sequence that ends on Umber, and the Umber half is what gets drawn: a
-- margin is a line ruled down a page, and this glyph stands that line up. Fourteen studs wide, nine high,
-- solid, six seconds, and it stops projectiles -- stepProjectile's ray is what makes "Umber blocks" true.
--
-- What it replaced was a Mud-material slab tweened up out of the floor and back down. The motion was
-- right, which is why it survives here; everything around it was not. Mud is a stock material, the slab
-- arrived with no warning, and the floor it stood in for six seconds kept nothing.
--
-- How it is built: the margin is RULED FIRST, a stroke on the floor before anything rises. It is not a
-- warning, and must not be read as one: the collision rises with the server's slab, which is the wall
-- itself in the Margin's pigment coming up out of the page (WorldConfig.Glyphs, D-110), and this ink marks
-- the faces of that wall as it stands. Then two courses of ink grow out of that line -- and they are NOT
-- coplanar. The packet's Origin is the slab's centre, so the courses sit just proud of either face, 1.32
-- studs fore and aft of a 2.5-stud slab: inside it, where they were, they showed through the old
-- translucent pane and are buried in the solid wall (D-110); on a face, a quad fights it for the same
-- pixel. The slab is a paler shade of the pigment, so the courses read darker on it. On the leaf's two
-- faces they read as recto and verso, ruled in two passes by a hand rather than extruded by a machine.
--
-- Both are centred ON the floor line, which is forced and is also correct. buildSprite draws Size x Size
-- and a sprite can only grow about its own centre, so a course centred anywhere above the floor would have
-- to APPEAR in mid-air (rule 3) instead of growing out of the page. Centred on the line, fourteen studs of
-- width is exactly the collision's width and seven of its nine studs of height. The two undrawn studs are
-- the safe side of that error: a shot clears the ink and is blocked anyway, where an overdrawn wall would
-- have a player shelter behind nothing.
--
-- The sink is split off from the stand, and that is the fix that matters most here. A single long Quint/In
-- over the wall's life puts the ink at 84% of its height four seconds in, 38% at five, and 6% with a full
-- second of solid collision still to go -- a player walks into a knee-high smear and bounces off nine
-- studs of slab. So each course holds its height to 5.36 and then drops in about half a second, finishing
-- at 5.88 and 5.94, a tenth before Debris takes the real slab at 6.0. What is left as a lie is an
-- invisible wall that still blocks, never visible ink that does not.
local MARGIN: Timeline = {
	Intent = "A margin is ruled on the floor, two courses of ink rise from it, stand, and sink back in",
	Phases = {
		{
			Name = "Anticipation",
			-- Two frames: GlyphEffects.Margin raises its slab the instant it emits this packet, in
			-- WorldConfig.Glyphs.WallRiseSeconds (0.22). The line and its courses used to take 0.76 to come
			-- up, rising beside a wall that had stood for half a second already (the lab, D-121).
			Duration = 0.03,
			Layers = {
				-- The ruling. Exponential/Out throws most of the line out in a quarter of a second and
				-- then creeps the last of it, which is a dry brush running out of pigment. Its
				-- transparency does not move: this is a line being drawn, not a light coming up.
				-- Fourteen, never more -- the rule may not promise more floor than the wall will occupy.
				-- It ends at 0.25, where the drying line below begins, so the floor never carries two
				-- marks at one height.
				{
					Kind = "Mark",
					At = 0,
					For = 0.25,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 1,
					EndSize = 14,
					Transparency = 0.24,
					EndTransparency = 0.24,
				},
				-- Earth pulled down into the line before anything comes out of it. DustMote, because Umber
				-- is dry: SmokeSoft is the wet pigment the Indigo glyphs throw, and a school you can name
				-- by its matter is one less thing the colour has to carry alone.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.03,
					Texture = "DustMote",
					Offset = { 0, -4.5, 0 },
					Burst = 12,
					Speed = { -9, -3 },
					Lifetime = { 0.16, 0.3 },
					Spread = 150,
					Drag = 2.6,
					Size = 0.6,
					EndSize = 0.05,
				},
			},
		},
		{
			Name = "Cast",
			-- The server's own rise, to the frame.
			Duration = 0.22,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.18, For = 0.05, Voice = "Impact" },
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The near face, the broad pass: fourteen studs of ink out of the floor line, the
				-- collision's width exactly, on the server tween's own Quart Out. It ends at 0.25 on the nail,
				-- where the standing course below starts at the same size -- a butt joint, not an overlap. onHeartbeat activates pending layers before it
				-- releases expired ones, so there is no frame of nothing between them to defend against.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.22,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.8,
					EndSize = 14,
					Offset = { 0, -4.5, -1.32 },
					Transparency = 0.34,
					EndTransparency = 0.14,
				},
				-- The far face, a few hundredths later and narrower: ink that did not soak all the way
				-- through the leaf. Two passes, two planes, one slab.
				{
					Kind = "Sprite",
					At = 0.03,
					For = 0.19,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.6,
					EndSize = 12,
					Offset = { 0, -4.5, 1.32 },
					Transparency = 0.4,
					EndTransparency = 0.3,
				},
				{
					Kind = "Emitter",
					At = 0.02,
					For = 0.3,
					Texture = "DustMote",
					Offset = { 0, -4.5, 0 },
					Burst = 26,
					Speed = { 5, 13 },
					Lifetime = { 0.4, 0.85 },
					Spread = 45,
					Drag = 3.4,
					Weight = 20,
					Size = 0.7,
					EndSize = 2.6,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				-- The page torn up along the foot of the wall as it comes out: spikes of the pigment struck up
				-- out of the floor on both faces, turned to whoever looks -- the rise read from anywhere, where
				-- a slab coming out of a pale floor in a pale shade of its pigment was a slab, not a spell.
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -6, -4.5, -1.9 },
					Size = 1,
					EndSize = 7,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -3, -4.5, 1.9 },
					Size = 1,
					EndSize = 7,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -4.5, -1.9 },
					Size = 1,
					EndSize = 7,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 3, -4.5, 1.9 },
					Size = 1,
					EndSize = 7,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 6, -4.5, -1.9 },
					Size = 1,
					EndSize = 7,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- A hot point where the slab hits its stops, in front of the near face.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0.18,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -2.5, -1.8 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.8,
					EndSize = 4,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.7,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 18,
					Brightness = 2.8,
				},
				-- The punch profile, not the blast's. A slab reaching its stops is a heavy impact on the
				-- floor; it is not a detonation, and borrowing Heavy would make a defensive glyph hit the
				-- camera harder than the ultimate that breaks it.
				{ Kind = "Shake", At = 0.18, For = 0.08, Profile = "Melee" },
			},
		},
		{
			Name = "Residue",
			-- A Margin standing IS what the world keeps, which is what this phase is for. There is no
			-- Impact phase because the wall lands on nobody: its Damage is zero and it hits only the floor.
			Duration = 5.2,
			Layers = {
				-- The line, drying under the wall and after it. Drawn first, gone last, and the longest
				-- lived layer in the game: the margin is the mark, the wall was only the margin standing
				-- up.
				{
					Kind = "Mark",
					At = 0,
					For = 5.7,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 14,
					EndSize = 15.4,
					Transparency = 0.24,
					EndTransparency = 1,
				},
				-- The near face standing. Its size does not move: a wall that is solid at full height has
				-- no business shrinking, and the easing here is spent on the transparency instead, so the
				-- ink settles darker into the page the longer it stands.
				{
					Kind = "Sprite",
					At = 0,
					For = 5.11,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "BrushStroke",
					Size = 14,
					EndSize = 14,
					Offset = { 0, -4.5, -1.32 },
					Transparency = 0.14,
					EndTransparency = 0.2,
				},
				-- And sinking, in the last half second and not before. Quint/In over a span this short is
				-- a drop rather than a slouch, which is the only shape that keeps the window where the ink
				-- is shorter than the collision down to a fraction of a second.
				{
					Kind = "Sprite",
					At = 5.11,
					For = 0.52,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 14,
					EndSize = 0.8,
					Offset = { 0, -4.5, -1.32 },
					Transparency = 0.2,
					EndTransparency = 0.5,
				},
				-- The far face does the same, four hundredths later at each end. A wall that leaves in one
				-- piece was never in the page; this one goes back in the order it came out.
				{
					Kind = "Sprite",
					At = 0,
					For = 5.15,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "BrushStroke",
					Size = 12,
					EndSize = 12,
					Offset = { 0, -4.5, 1.32 },
					Transparency = 0.3,
					EndTransparency = 0.34,
				},
				{
					Kind = "Sprite",
					At = 5.15,
					For = 0.54,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 12,
					EndSize = 0.6,
					Offset = { 0, -4.5, 1.32 },
					Transparency = 0.34,
					EndTransparency = 0.6,
				},
			},
		},
	},
}

-- Sweep (Verdigris, aoe -- GlyphConfig's own archetype: ONE damageArea pass, MaxHits 1, no ticks). The
-- cheapest glyph in the game -- fifteen ink, three seconds, twelve damage -- so a Verdigris player opens
-- with it and then throws it as often as a punch. Its damage is not the point: the point is the seventy
-- studs of Push and the thirty of Lift in Params. It is a displacement wearing twelve damage.
--
-- Air is invisible, so the wind is never drawn -- only what it moves is, and in this game what the wind
-- moves is ink. The hand flicks a crescent of ink; at the centre the page is wiped: a crescent of the
-- page's charcoal sweeps round the whole hitbox on the floor, the ink under it is shoved out to the rim and
-- gone, and scraps of the page and spurts of ink are torn UP, which is the Lift the server applies. The
-- ground trace is the one WIPE in Vellum -- every other glyph burns a mark onto the page, this one pushes
-- the ink off it -- and it lasts a second where a burn lasts two and a half.
--
-- Everything lands at 0, with the damage (D-119). GlyphEffects.Sweep damages the moment the packet leaves;
-- this timeline used to spend 0.16 s on a wind-up and a hand stroke first, so the wipe was drawn a sixth
-- of a second after the targets had already been thrown. The wind-up is the shared Cast lighting the hand,
-- which plays with the same packet; the gesture here is the release.
--
-- It is played at the CENTRE the server damaged (VfxLibrary.Sweep adds Params.Offset along the aim: the
-- server sends the caster's position), so the wipe and the trace sit on the hitbox, measured by its radius.
-- Verdigris is the palest pigment on the page (contrast 1.06 on the training floor): the charcoal carries
-- the shape, the pigment carries the school.
--
-- No Flash layer. PageFlash belongs to impacts, and a glyph cast every three seconds that borrowed the
-- loudest thing in the vocabulary would make it mean nothing everywhere else.
local SWEEP: Timeline = {
	Intent = "The page is wiped in front of the caster: a sweep of ink round the hitbox, the ink thrown off and torn up",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.2,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The hand's own stroke: a crescent of ink flicked out of the fist, spinning the way the arm
				-- swept, and gone in a sixth of a second.
				{
					Kind = "Mesh",
					Mesh = "Crescent",
					Anchor = "Hand",
					Role = "Ink",
					At = 0,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0.8, 0.8, 0.8 },
					Roll = 30,
					Size = 1,
					EndSize = 5,
					Transparency = 0,
					EndTransparency = 1,
					Spin = -12,
				},
				-- The gust leaving the hand toward the centre: sparks of the pigment along the aim.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					Emit = "Aim",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0.8, 0.8, 0.4 },
					Burst = 12,
					Speed = { 24, 40 },
					Lifetime = { 0.12, 0.22 },
					Spread = 20,
					Drag = 4,
					Squash = 0.7,
					Size = 1.1,
					EndSize = 0,
				},
				-- The wipe: a crescent of charcoal laid on the floor, its ink reaching the hitbox's edge and not
				-- past it, sweeping round it once and gone. Quart Out: at full width in the first frames.
				{
					Kind = "Mesh",
					Mesh = "Crescent",
					Face = "Ground",
					Role = "Ink",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					SizeFrom = "Radius",
					Size = 0.3,
					EndSize = 1.85,
					Offset = { 0, 0.14, 0 },
					Transparency = 0,
					EndTransparency = 1,
					Spin = 7,
					Jitter = math.pi,
				},
				-- The ink already on the page, shoved outward to the rim in a quarter second and gone. It
				-- states the hitbox on the ground, where a zone is read from, and it is the only mark in
				-- the game that grows to its full width and then stops existing rather than fading in
				-- place: the ink was not burnt, it was moved. FadesWithSize keeps it that way.
				{
					Kind = "Mark",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 14,
					EndSize = 24,
					Transparency = 0.2,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				-- A small hot point where the wind struck, ringed by the pigment it throws. Under the resting
				-- bloom's threshold: heated Verdigris is the palest core on the page, and bloomed it turned the
				-- whole hitbox cyan, which is the colour of an ally (rule 7).
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 1.2, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.5,
					EndSize = 2.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- Torn off the floor, upward: Params.Lift is thirty studs and these show it. Spurts of ink,
				-- tall enough to clear the caster's own head from behind...
				{
					Kind = "Emitter",
					Role = "Ink",
					Emit = "Up",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0, -1.4, 0 },
					Burst = 14,
					Speed = { 22, 40 },
					Lifetime = { 0.2, 0.35 },
					Spread = 40,
					Drag = 3,
					Squash = 0.6,
					Size = 1.1,
					EndSize = 0,
				},
				-- ...and the pigment's own dust, thrown up and falling back.
				{
					Kind = "Emitter",
					Emit = "Up",
					At = 0,
					For = 0.06,
					Texture = "DustMote",
					Offset = { 0, -1.4, 0 },
					Burst = 26,
					Speed = { 16, 34 },
					Lifetime = { 0.3, 0.55 },
					Spread = 62,
					Drag = 2.6,
					Weight = 30,
					Squash = 0.4,
					Size = 0.7,
					EndSize = 0.1,
				},
				-- Scraps of the page torn up by the wipe. Weight, not meaning: the lower tiers leave them out.
				{
					Kind = "Debris",
					Meshes = { "ScrapA", "ScrapB" },
					Flourish = true,
					At = 0,
					For = 0.04,
					Count = 6,
					Size = 0.7,
					Speed = { 14, 26 },
					Spread = 45,
					Lifetime = { 0.8, 1.3 },
					Drag = 3,
					Fall = 7,
					Tumble = { 6, 14 },
					Tones = { "Ink" },
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.2,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 1.2, 0 },
					Range = 16,
					Brightness = 2.2,
				},
				-- Light, not Heavy: it displaces a body, it does not detonate. A cheap glyph that punched
				-- the camera like an explosion would flatten the whole scale.
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Residue",
			Duration = 0.9,
			Layers = {
				-- What is left of the wipe. Shorter-lived than a hit's burn -- dust that was pushed aside
				-- settles back, it does not stay burnt -- and thirteen studs rather than twenty-four on
				-- purpose: the hitbox was stated by the blot while the damage was happening, and a MEMORY
				-- as wide as the damage would tile the arena at one cast per three seconds.
				{
					Kind = "Mark",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 13,
					EndSize = 19,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.02,
					For = 0.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.3, 0 },
					Rate = 9,
					Speed = { 0.4, 1.8 },
					Lifetime = { 0.5, 0.95 },
					Spread = 150,
					Drag = 1.3,
					Size = 0.3,
					EndSize = 0,
				},
			},
		},
	},
}

-- Hairline (Verdigris, projectile). A délié is the thin upstroke of a pen, and this is the thinnest and
-- fastest thing in the game: a hundred and thirty studs a second over sixty of range, fourteen damage,
-- three second cooldown, and it leaves its target Fanned for the next Cinnabar hit. It must read as a line
-- being ruled across the page.
--
-- What it replaced was a blade: a part 0.35 studs thick that ROLLED as it flew, moved with
-- Enum.EasingStyle.Linear, behind a stock Trail. Art bible rule 4 forbids linear motion and the old
-- renderer named it in the source. A blade that rolls is a weapon; this glyph is not a weapon, it is a
-- stroke, and a stroke does not roll.
--
-- It leaves on the server's frame (D-121). GlyphEffects.Hairline steps its projectile from the instant it
-- emits this packet; the drawn one used to load its nib for a tenth of a second and touch the page for a
-- twentieth first, so it left 0.15 s late -- twenty studs behind the line that hurts, and at twenty-four
-- studs the target was struck before the drawn line had left the hand (the lab). The wind-up is the shared
-- Cast lighting the hand; this timeline spends three hundredths on its own gather and release, and its
-- carrier runs like the Brand's -- mostly time, 15 % of a Sine In, the pace the server keeps -- from the
-- server's spawn point. There is no Arc at all, the server firing it at zero gravity, and a ruled line
-- does not sag.
--
-- The body of the flight is a pen stroke: a ribbon of the page's ink a tenth of a second long, tapering
-- to nothing, and a burning line of the pigment inside it, cooling as it trails -- bare ribbons, because a
-- trail stretches its texture over its whole length and the brush stroke drawn that way was a smudge
-- (D-119). And a nib: hot points shed at the head.
--
-- It has no Impact phase and no Mark. It touches nothing: what happens when it lands belongs to the shared
-- Hit timeline, which leaves the burn. Same split as Brand, for the same reason.
local HAIRLINE: Timeline = {
	Intent = "A single thin line is ruled across the page, a burning line inside a stroke of ink",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The nib loading in the hand: sparks of the pigment drawn in. A burst: over two hundredths a
				-- rate draws nothing.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Offset = { 0.8, 0.8, 0.2 },
					Burst = 10,
					Speed = { -10, -5 },
					Lifetime = { 0.06, 0.1 },
					Spread = 180,
					Drag = 3,
					Squash = 0.5,
					Size = 0.4,
					EndSize = 0.02,
				},
				{
					Kind = "Light",
					Anchor = "Hand",
					At = 0,
					For = 0.14,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0.8, 0.8, 0.2 },
					Range = 5,
					Brightness = 1.2,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The flick: needles of the pigment thrown out of the hand along the line.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					Emit = "Aim",
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0.8, 0.8, 0.4 },
					Burst = 10,
					Speed = { 40, 70 },
					Lifetime = { 0.06, 0.12 },
					Spread = 10,
					Drag = 5,
					Squash = 0.9,
					Size = 0.8,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Travel",
			Duration = 0.46,
			Layers = {
				-- The landing sound, at the end of the flight in which it lands.
				{ Kind = "Sound", At = 0.41, For = 0.05, Voice = "Impact" },
				-- From where the server's line is when this one leaves: SpawnOffset ahead, plus the four studs
				-- it covers in the three hundredths spent above. It ends sixty-four from the caster, which is
				-- exactly where stepProjectile stops (it measures from the spawn point), and by the server's own
				-- schedule stays within about a stud of the line that hurts.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.46,
					Offset = { 0, 0.35, 8 },
					Ease = "Sine",
					EaseDirection = "In",
					EaseShare = 0.15,
					Travel = 56,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- The stroke, in the page's ink: a tenth of a second of ribbon, thirteen studs, tapering to a
				-- point.
				{
					Kind = "Trail",
					At = 0,
					For = 0.46,
					Ride = true,
					Role = "Ink",
					Ribbon = 0.1,
					Size = 0.7,
					EndSize = 0.02,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The burning line inside it. Under the resting bloom's threshold: heated Verdigris bloomed is
				-- cyan, an ally's colour (rule 7).
				{
					Kind = "Trail",
					At = 0,
					For = 0.46,
					Ride = true,
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					Ribbon = 0.07,
					Size = 0.3,
					EndSize = 0.02,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The nib: hot points of the pigment shed at the head of the line.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.46,
					Ride = true,
					Texture = "DustMote",
					Rate = 40,
					Speed = { 0.5, 2 },
					Lifetime = { 0.08, 0.16 },
					Spread = 180,
					Drag = 2,
					Size = 0.35,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.46,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 7,
					Brightness = 1.6,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.5,
			Layers = {
				-- Dust hanging over the far half of the line after it has been ruled.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.42,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.35, 32 },
					Rate = 8,
					Speed = { -2.2, -0.5 },
					Lifetime = { 0.5, 0.9 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.26,
					EndSize = 0,
				},
			},
		},
	},
}

-- Spiral (Verdigris, zone). The only zone in the game that PULLS. The other four push, burn, slow or stun;
-- this one drags everything it damages toward its own centre at thirty-five studs a second, four times,
-- every 0.6 s (GlyphEffects.Spiral, Params.PullSpeed and PullMinDistance). A player who reads it as a zone
-- that pushes runs the wrong way, which makes a mistaken reading here worse than in any other effect.
--
-- What it replaced said the opposite of what the server does in the layer that mattered most: it stacked
-- ForceField rings into a funnel and gave its dust Acceleration = (0, 14, 0), so the particles left
-- through the TOP while the code pulled inward. (Its wisps did run from the rim to the eye, which was the
-- one honest thing in it.) A tornado is also a catalogue image, and a tornado throws things out.
--
-- It is built by inversion, and by only claiming inversions the runtime can draw. On the ground the rings
-- do not open, they SHUT -- twenty-two studs of diameter driven down to two, Circular In so they hang and
-- then go all at once -- and there are exactly four of them, at 0, 0.6, 1.2 and 1.8, the instants tickZone
-- actually pulls. Each is a Mark, so it lies flat: a zone is read from above. In the air the pull is drawn
-- as a FALL: buildEmitter never sets EmissionDirection, so a point emitter at a hundred and eighty degrees
-- of spread is symmetric and the sign of its Speed is invisible -- the streaks would read as a burst
-- whichever way they were authored. Hung eight and ten studs above the eye at twenty-odd degrees, negative
-- speed is a direction the engine really gives, and what it gives is matter driven down into one point.
-- Rings inward on the page, everything else down through it: the zone is a hole the page is being drawn
-- into. The camera takes four small Dash tugs on the same beat, so the pull has a rhythm a player can
-- count, and the tugs are free -- a Shake layer borrows no instances.
--
-- The footprint never narrows. It grows from nineteen to the true twenty-two of Params.Radius and then
-- holds, fading by transparency alone, because tickZone damages at radius eleven on every one of the four
-- ticks: a zone whose drawn edge contracts while its hitbox does not tells the player they have left when
-- they have not. Contraction belongs to the rings, which are events, not to the footprint, which is a
-- statement of where the danger is.
--
-- D-125: it was drawn a tenth of a second after its first pull (the server pulls on the packet), under a
-- grey cloud and a verdigris light that tinted the page cyan, an ally's colour. It is drawn on the packet
-- now, as a whirlpool -- two seals turning on the page -- that shuts four times, each time dragging streaks
-- of ink in from a dome round the zone.
local SPIRAL: Timeline = {
	Intent = "Four times, the page is drawn into one point and does not let go",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "DustMote",
					Offset = { 0, -2.4, 0 },
					Burst = 14,
					Speed = { -12, -5 },
					Lifetime = { 0.1, 0.16 },
					Spread = 175,
					Size = 0.4,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 2.4,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The footprint, honest from the packet: the true twenty-two studs of Params.Radius, never narrowing.
				{
					Kind = "Mark",
					At = 0,
					For = 2.9,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "GradientRadial",
					Size = 19,
					EndSize = 22,
					Transparency = 0.45,
					EndTransparency = 0.8,
				},
				-- The vortex (D-125): two seals turning on the page, the inner one faster, so the zone reads as a
				-- whirlpool from any camera, and turning the way the pull is drawn.
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Texture = "SealRing",
					Offset = { 0, 0.04, 0 },
					Size = 22,
					EndSize = 22,
					Transparency = 0.25,
					EndTransparency = 0.7,
					Spin = 1.4,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Texture = "SealRing",
					Offset = { 0, 0.08, 0 },
					Size = 11,
					EndSize = 10,
					Transparency = 0.2,
					EndTransparency = 0.7,
					Spin = 3.2,
				},
				{
					Kind = "Light",
					Brightness = 0.9,
					At = 0,
					For = 2.4,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, -1, 0 },
					Range = 12,
				},
				-- Tick one of four: the ring shuts on the eye and the page is pulled in -- streaks of ink from a
				-- dome round the zone, all toward the point -- and the eye flares.
				{
					Kind = "Mark",
					At = 0,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.05,
					EndTransparency = 0.6,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, -2, 0 },
					Burst = 36,
					Speed = { -26, -18 },
					Lifetime = { 0.35, 0.45 },
					Spread = 180,
					Squash = 0.6,
					Size = 1.7,
					EndSize = 0.2,
					Transparency = 0,
					EndTransparency = 0.3,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 0.3,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Dash" },
				{
					Kind = "Mark",
					At = 0.6,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.05,
					EndTransparency = 0.6,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					At = 0.6,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, -2, 0 },
					Burst = 36,
					Speed = { -26, -18 },
					Lifetime = { 0.35, 0.45 },
					Spread = 180,
					Squash = 0.6,
					Size = 1.7,
					EndSize = 0.2,
					Transparency = 0,
					EndTransparency = 0.3,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 0.9,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 0.6, For = 0.05, Profile = "Dash" },
				{
					Kind = "Mark",
					At = 1.2,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.05,
					EndTransparency = 0.6,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					At = 1.2,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, -2, 0 },
					Burst = 36,
					Speed = { -26, -18 },
					Lifetime = { 0.35, 0.45 },
					Spread = 180,
					Squash = 0.6,
					Size = 1.7,
					EndSize = 0.2,
					Transparency = 0,
					EndTransparency = 0.3,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 1.5,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 1.2, For = 0.05, Profile = "Dash" },
				{
					Kind = "Mark",
					At = 1.8,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.05,
					EndTransparency = 0.6,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					At = 1.8,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, -2, 0 },
					Burst = 36,
					Speed = { -26, -18 },
					Lifetime = { 0.35, 0.45 },
					Spread = 180,
					Squash = 0.6,
					Size = 1.7,
					EndSize = 0.2,
					Transparency = 0,
					EndTransparency = 0.3,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 2.1,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 1.8, For = 0.05, Profile = "Dash" },
			},
		},
		{
			Name = "Residue",
			Duration = 2.2,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2.2,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 8,
					EndSize = 5.5,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.7,
					Texture = "DustMote",
					Offset = { 0, -1.5, 0 },
					Rate = 8,
					Speed = { 0.5, 2 },
					Lifetime = { 0.7, 1.2 },
					Spread = 150,
					Size = 0.32,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Pounce (Verdigris, zone). Pounce is the powder -- pumice, cuttlefish bone -- shaken over vellum to key
-- the surface and to dry wet ink; the French name the glyph already ships with, Poncif, is the pricked
-- pattern it is dusted through. So this is not a sandstorm, it is a pouring of powder over thirteen studs
-- of page, three times, and everything under it keeps seven tenths of its speed for a second and a half
-- (Params.SlowFactor, SlowDuration). It is the one glyph of the school that displaces nothing: it takes
-- displacement away.
--
-- What it replaced was a ball of Roblox's Sand material growing from two studs to twenty-six and fading,
-- with grit blown past the camera. The growing sphere is the named failure case, but the worse error is
-- that a DOME is shelter, which is Umber's vocabulary -- "ce qui résiste". The effect offered cover on the
-- one patch of ground a player should be leaving.
--
-- A soft shadow covers the full twenty-six studs of Params.Radius within half a second and is visible
-- while it does it -- forty-five per cent transparent, not eighty, which is a layer that is authored and
-- never seen -- because the server damages immediately and the footprint has to be honest at once. It
-- fades exactly as the first powder arrives to replace it, so nothing vanishes with nothing in its place.
-- Then three pours, at 0, 0.9 and 1.8, the server's own intervals: each falls from seven studs up on a
-- negative speed in a fifty-eight degree cone, which is the one thing an emitter in this format can state
-- truthfully -- its host's own axis is up, so down is the direction it really gives. Under them a low haze
-- that SINKS instead of rising, and fine grain over it, because powder without hard grain is smoke and
-- smoke belongs to Cinnabar. Each pour widens the stain on the floor one step, twelve then seventeen then
-- twenty-one studs, so the zone visibly counts its ticks and the last one arrives at the twenty-six the
-- shadow promised.
--
-- What it leaves is a dusting, not a burn, and it is a GradientRadial and not PaperGrain. Paper grain is
-- the world's own tileable surface at five to twenty-four per cent alpha with no shape: on the floor it is
-- a hard-edged square of pigment laid over the very texture it is made of. A soft radial disc has no edge
-- to give it away, which is what a patch of settled powder looks like.
--
-- No Shake and no Flash anywhere in it, which is the point rather than an omission: it applies no force at
-- all, and a camera that jumped at a fall of powder would erase the only difference between this and every
-- other zone. The art bible calls silence a material; here it is the main one.
--
-- D-125: drawn on the packet (it was 0.12 s behind a slow the server lays at once), its pours are bursts of
-- grain over the whole zone -- the grey clouds that carried them read as dirt, and a Rate is thinned by the
-- engine -- and its edge is held in the pigment while it pours.
local POUNCE: Timeline = {
	Intent = "Powder is poured over the page three times until nothing on it can move",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The shadow of the pour over the full twenty-six studs, honest at once: the server slows from its
				-- first tick, on the packet.
				{
					Kind = "Mark",
					At = 0,
					For = 0.5,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "GradientRadial",
					Size = 20,
					EndSize = 26,
					Transparency = 0.45,
					EndTransparency = 0.9,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 2.7,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The zone's edge in the pigment, held while it pours (D-125).
				{
					Kind = "Mark",
					At = 0,
					For = 2.6,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Offset = { 0, 0.04, 0 },
					Size = 18,
					EndSize = 26,
					Transparency = 0.25,
					EndTransparency = 0.75,
				},
				-- Each of the server's three ticks: a pour of grain over the whole zone, falling (bursts, which
				-- the engine never thins), and the stain it leaves one step wider.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 4, 0 },
					Burst = 70,
					Speed = { 0, 1 },
					Lifetime = { 0.55, 0.85 },
					Spread = 20,
					Weight = 25,
					Area = { 24, 0.3, 24 },
					Size = 0.45,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.2,
				},
				{
					Kind = "Emitter",
					At = 0.9,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 4, 0 },
					Burst = 70,
					Speed = { 0, 1 },
					Lifetime = { 0.55, 0.85 },
					Spread = 20,
					Weight = 25,
					Area = { 24, 0.3, 24 },
					Size = 0.45,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.2,
				},
				{
					Kind = "Emitter",
					At = 1.8,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 4, 0 },
					Burst = 70,
					Speed = { 0, 1 },
					Lifetime = { 0.55, 0.85 },
					Spread = 20,
					Weight = 25,
					Area = { 24, 0.3, 24 },
					Size = 0.45,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.2,
				},
				{
					Kind = "Mark",
					At = 0.35,
					For = 1.2,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 12,
					EndSize = 16,
					Transparency = 0.35,
					EndTransparency = 0.55,
				},
				{
					Kind = "Mark",
					At = 1.25,
					For = 1.2,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 17,
					EndSize = 21,
					Transparency = 0.35,
					EndTransparency = 0.55,
				},
				{
					Kind = "Mark",
					At = 2.15,
					For = 1.2,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 21,
					EndSize = 25,
					Transparency = 0.35,
					EndTransparency = 0.55,
				},
				-- Fine grain settling between the pours, driven (D-124): powder with no grain is smoke.
				{
					Kind = "Emitter",
					At = 0.05,
					For = 2.4,
					Texture = "DustMote",
					Offset = { 0, 1, 0 },
					Rate = 30,
					Speed = { 0, 0.5 },
					Lifetime = { 0.8, 1.2 },
					Spread = 30,
					Weight = 4,
					Area = { 22, 3, 22 },
					Driven = true,
					Size = 0.3,
					EndSize = 0.12,
					Transparency = 0.1,
					EndTransparency = 0.6,
				},
				{
					Kind = "Light",
					Brightness = 0.7,
					At = 0,
					For = 2.7,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, -0.5, 0 },
					Range = 14,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 2,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "GradientRadial",
					Size = 26,
					EndSize = 30,
					Transparency = 0.5,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.8,
					Texture = "DustMote",
					Offset = { 0, -1.3, 0 },
					Rate = 8,
					Speed = { 0.3, 1 },
					Lifetime = { 0.7, 1.2 },
					Spread = 150,
					Size = 0.34,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Serif (Umber, area). Five points struck one after another down a line: GlyphEffects.Serif damages a
-- five-stud sphere at StartOffset, then every Spacing studs after it, waiting StepDelay between each, so
-- the strikes land at six, eleven, sixteen, twenty-one and twenty-six studs over 0.32 seconds, and the
-- far edge of the last sphere is exactly the glyph's thirty-one-stud Range.
--
-- What it replaced was five box parts on Roblox's Slate material, rising out of the floor with a Back
-- tween, holding a second and a half, and sinking back. Two visual layers each, no light, no trace, no
-- camera, and a stock material carrying the whole identity -- which is the one thing docs/ART_BIBLE.md
-- rules out, because a tinted Slate spike is in every battleground on the platform and belongs to none
-- of them.
--
-- The reading is the name. A serif is the stroke at the foot of a letter, so the nib lays the line down
-- the page first and the feet are struck through it in order. Nothing retracts: ink does not go back into
-- the page, it dries.
--
-- Built out of what the runtime can actually draw, which is the difference between this and the draft it
-- replaces. VfxTimeline.buildMark makes a SQUARE part whose yaw comes from the ground normal and not from
-- the aim, so a Mark cannot draw an oriented stroke and is not asked to: the line is a Beam, the one kind
-- that runs along the aim, faces the camera from every seat in the arena, and carries the brush texture at
-- something near its own aspect. The art bible says so in as many words -- "un trait qui se dessine est un
-- Beam". The five feet are Marks, flat on the floor at the five points the server damages, because a Mark
-- reads the same from the side, from above and from behind; and a Mark's arbitrary yaw stops being a
-- limitation and starts being five separate strikes instead of one decal tiled five times.
local SERIF: Timeline = {
	Intent = "A stroke is laid down the page and five feet are struck through it, one after another",
	Phases = {
		{
			-- Two frames, and they are the whole of the disagreement with the server: Serif damages its
			-- first point in the same frame it emits the packet, so every frame spent here draws the line
			-- after the damage it belongs to. Two is the least that still lets the page be marked before
			-- it splits, which is what rule 3 asks for.
			Name = "Anticipation",
			Duration = 0.03,
			Layers = {
				-- The stroke. Size is the near width AND sets the length at eight times itself
				-- (buildBeam), so 3.4 lays a 27.2-stud line from three and a half studs out to thirty
				-- and a half: inside the damaged corridor at both ends and never past it. Width1 tapers
				-- to a third on its own, which is the brush texture's own shape -- wet where the nib
				-- landed, dry where it ran out.
				--
				-- It inks IN here and dries OUT in Residue as a second Beam, because a layer has one
				-- ramp. Both declare the same Size, since a Beam's length is read from Size at build
				-- time: change it between the two and the line would shorten when they hand over.
				{
					Kind = "Beam",
					At = 0,
					For = 0.35,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 3.4,
					EndSize = 3.4,
					Offset = { 0, -2.4, 3.5 },
					Transparency = 1,
					EndTransparency = 0.18,
				},
				-- Ink pulled down into the line. Negative speed, at floor height, along the middle of the
				-- run: the page is soaking before it tears.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.03,
					Texture = "DustMote",
					Offset = { 0, -2.2, 16 },
					Rate = 90,
					Speed = { -12, -5 },
					Lifetime = { 0.1, 0.2 },
					Spread = 180,
					Drag = 4,
					Size = 0.45,
					EndSize = 0.04,
				},
			},
		},
		{
			-- 0.32 is four StepDelays exactly: the phase IS the server's loop, so a change to StepDelay
			-- shows up here as a disagreement rather than as a spell that looks wrong for no reason.
			Name = "Impact",
			Duration = 0.32,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The five feet. At and Offset are the server's schedule and the server's damage points
				-- written out -- 0.08 apart, FIVE studs apart, from six to twenty-six. Nothing derives
				-- them at runtime, which is why a balance change to Spacing has to be made here too and
				-- will be seen if it is not.
				--
				-- One layer does the whole print. Size 2.2 to 7.0 on Quart-Out lands it inside a fifth of
				-- a second, and the transparency runs the other way on the same curve, so the mark is
				-- darkest the instant the nib struck and lightens as it spreads and soaks. That is what
				-- ink does on paper; it is one layer instead of two; and it means nothing pops, because
				-- the print is never handed from one instance to another and ends at transparency 1.
				--
				-- Seven studs across is a half-diagonal of 4.95 against a HitRadius of five: the print
				-- never claims a corner of ground the sphere did not. The line's longer memory is the
				-- Beam drying in Residue, not these -- the feet are the strikes, the stroke is the trace.
				-- Hence FadesWithSize: under the ink-drying fade every other mark follows, five dark prints
				-- held for a second look like Ligature's burning pools, and Serif's damage is already over.
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2.2,
					EndSize = 7,
					Offset = { 0, 0, 6 },
					Transparency = 0.1,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				{
					Kind = "Mark",
					At = 0.08,
					For = 1.5,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2.2,
					EndSize = 7,
					Offset = { 0, 0, 11 },
					Transparency = 0.1,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				{
					Kind = "Mark",
					At = 0.16,
					For = 1.5,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2.2,
					EndSize = 7,
					Offset = { 0, 0, 16 },
					Transparency = 0.1,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				{
					Kind = "Mark",
					At = 0.24,
					For = 1.5,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2.2,
					EndSize = 7,
					Offset = { 0, 0, 21 },
					Transparency = 0.1,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				-- The terminal. Same print, held longer, because that is where the stroke stops and it is
				-- the one a target at the end of the line is standing next to. Heavier by its LIFE and
				-- not by its size: a wider print here would claim ground the last sphere never reached.
				{
					Kind = "Mark",
					At = 0.32,
					For = 1.9,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2.2,
					EndSize = 7,
					Offset = { 0, 0, 26 },
					Transparency = 0.1,
					EndTransparency = 1,
					FadesWithSize = true,
				},
				-- The five serifs themselves: at each point the server damages, a spike of the pigment struck
				-- up out of the page (InkSpike: its root on the plane's middle line, so a plane centred on the
				-- floor shows it rising), turned to whoever looks, overshooting as it lands and drying out.
				-- Five points, five beats, eight studs tall, enough to clear the caster's own head from behind; a
				-- print on the floor never was, sparks at twenty studs were a few grey dashes, and a brush stroke
				-- stood on end was a smudge (the lab, D-119). The fifth is the terminal: a hot point and a spurt
				-- of ink where the stroke stops.
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.2,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 6 },
					Size = 1.5,
					EndSize = 16,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.08,
					For = 0.2,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 11 },
					Size = 1.5,
					EndSize = 16,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.16,
					For = 0.2,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 16 },
					Size = 1.5,
					EndSize = 16,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.24,
					For = 0.2,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 21 },
					Size = 1.5,
					EndSize = 16,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.32,
					For = 0.2,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 26 },
					Size = 1.5,
					EndSize = 16,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					At = 0.32,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1, 26 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.5,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					Emit = "Up",
					At = 0.32,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 26 },
					Burst = 14,
					Speed = { 28, 48 },
					Lifetime = { 0.18, 0.32 },
					Spread = 25,
					Drag = 4,
					Squash = 0.7,
					Size = 1.6,
					EndSize = 0,
				},
				-- The light at the far end, where the stroke stops and where a target standing on the line is
				-- lit by it; the near end is lit by the caster's own cast. One and not five: PoolPolicy caps
				-- PointLight at 24 live, the tightest row in the file, and five spikes are the budget's worth.
				{
					Kind = "Light",
					At = 0.16,
					For = 0.42,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1, 21 },
					Range = 18,
					Brightness = 2.8,
				},
				-- Two taps, not one jolt and not five: the line has a near beat and a far beat and the
				-- camera says so, and FeelConfig.Shake.MaxConcurrent is four, so five would be noise.
				-- "Light" and not "Heavy", because this is a twenty-two-damage area and Rupture below has
				-- to be allowed to be the heaviest thing an Umber player does.
				{ Kind = "Shake", At = 0, For = 0.08, Profile = "Light" },
				{ Kind = "Shake", At = 0.3, For = 0.08, Profile = "Light" },
			},
		},
		{
			Name = "Residue",
			Duration = 1.95,
			Layers = {
				-- The other half of the stroke: same Size, so the same length, and the fade instead of
				-- the ink. It dries from a full brush to a hairline over nearly two seconds, which is the
				-- line's memory -- the page keeps the stroke longer than it keeps the feet, exactly as a
				-- page does.
				{
					Kind = "Beam",
					At = 0,
					For = 1.9,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 3.4,
					EndSize = 0.5,
					Offset = { 0, -2.4, 3.5 },
					Transparency = 0.18,
					EndTransparency = 1,
				},
				-- Dust of the pigment settling over the line once the strokes have dried.
				{
					Kind = "Emitter",
					At = 0.25,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, -1.6, 16 },
					Rate = 12,
					Speed = { 0.6, 2 },
					Lifetime = { 0.5, 0.9 },
					Spread = 90,
					Drag = 1.5,
					Size = 0.35,
					EndSize = 0,
				},
			},
		},
	},
}

-- Stipple (Umber, projectile). The Umber jab: eighteen ink, four seconds, sixteen damage and a slow to
-- sixty per cent for two seconds. GlyphEffects.Stipple steps it at a hundred and ten studs a second with
-- no gravity at all and stops it on the first model within four studs or at the seventy-stud Range,
-- whichever comes first, which is 0.64 seconds of flight.
--
-- What it replaced was a ball on Roblox's Mud material with a trail, moved by a tween whose easing style
-- was written out as Enum.EasingStyle.Linear -- rule 4 broken in the source rather than by accident --
-- and a cylinder that grew and faded on landing. A stock material, a stock disc, and the one word the
-- art bible forbids.
--
-- The reading is the name again. A stipple is a mark made of dots, and this glyph's job is weight: the dot
-- sheds dots of the pigment the whole way across and they fall onto the page, so the flight leaves a dotted
-- line under it and the target watches the thing that is about to slow them arrive. The gather is dots too,
-- where Brand's is streaks: same grammar, different hand.
--
-- Its arrival IS its damage, so the drawn dot must be where the one that hurts is. It leaves on the server's
-- frame (D-122): GlyphEffects.Stipple steps its projectile from the packet, and the drawn dot used to gather
-- for 0.12 s first and flew seventeen studs behind. It gathers for three hundredths now, leaves from where the
-- server's dot already is, and flies like the Brand -- mostly time, 15 % of a Sine In, the server's own pace.
local STIPPLE: Timeline = {
	Intent = "A dot of the pigment is flicked across the page, stippling a dotted line behind it",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The dot loading in the hand: grains of the pigment drawn in. A burst: over two hundredths a rate
				-- draws nothing.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.02,
					Texture = "InkBlot",
					Offset = { 0.8, 0.8, 0.2 },
					Burst = 10,
					Speed = { -12, -6 },
					Lifetime = { 0.06, 0.1 },
					Spread = 180,
					Drag = 3,
					Size = 0.4,
					EndSize = 0.05,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 1.1,
					Anchor = "Hand",
					At = 0,
					For = 0.12,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0.8, 0.8, 0.2 },
					Range = 5,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The flick, along the aim.
				{
					Kind = "Emitter",
					Emit = "Aim",
					Anchor = "Hand",
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0.8, 0.8, 0.4 },
					Burst = 10,
					Speed = { 30, 50 },
					Lifetime = { 0.08, 0.16 },
					Spread = 14,
					Drag = 5,
					Squash = 0.8,
					Size = 0.8,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Travel",
			Duration = 0.64,
			Layers = {
				{ Kind = "Sound", At = 0.59, For = 0.05, Voice = "Impact" },
				-- From where the server's dot already is when this one leaves: SpawnOffset, plus the three studs it
				-- covers in the three hundredths above; mostly time, 15 % of a Sine In, the server's own pace. It ends
				-- seventy-four from the caster, where stepProjectile stops (it measures from the spawn point).
				{
					Kind = "Carrier",
					At = 0,
					For = 0.64,
					Ease = "Sine",
					EaseDirection = "In",
					Offset = { 0, 0.3, 7.3 },
					Travel = 66.7,
					EaseShare = 0.15,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				-- The dot itself: a blot of the pigment turned to whoever looks, riding the flight.
				{
					Kind = "Sprite",
					Face = "Camera",
					Ride = true,
					At = 0,
					For = 0.64,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 1.8,
					EndSize = 1.4,
					Transparency = 0,
					EndTransparency = 0.3,
				},
				-- A short stroke of the page's ink behind it, bare: a textured ribbon was a smudge (D-119).
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 0.64,
					Size = 1.1,
					EndSize = 0.05,
					Ribbon = 0.12,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The stipple: dots of the pigment dropped along the path, falling onto the page.
				{
					Kind = "Emitter",
					Ride = true,
					At = 0,
					For = 0.64,
					Texture = "InkBlot",
					Rate = 40,
					Speed = { 0.5, 2 },
					Lifetime = { 0.3, 0.6 },
					Spread = 60,
					Drag = 2,
					Weight = 25,
					Size = 0.55,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- A hot point in the dot, under the bloom's threshold.
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					Ride = true,
					At = 0,
					For = 0.64,
					Texture = "DustMote",
					Rate = 30,
					Speed = { 0, 1 },
					Lifetime = { 0.06, 0.12 },
					Spread = 180,
					Size = 0.7,
					EndSize = 0.2,
				},
				{
					Kind = "Light",
					Brightness = 1.6,
					Ride = true,
					At = 0,
					For = 0.64,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 10,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				-- Dust of the pigment settling over the start of the line.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.4, 5 },
					Rate = 9,
					Speed = { -1.2, -0.3 },
					Lifetime = { 0.6, 1.1 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.32,
					EndSize = 0,
				},
			},
		},
	},
}

-- Gilding (Umber, buff). It scans for nothing and damages nobody: GlyphEffects.Gilding asks CombatService
-- for the status and emits one packet on the caster. Forty per cent off every incoming hit, immune to
-- knockback, four seconds.
--
-- What it replaced was six Slate plates orbiting the caster and crumbling. It followed the body, which is
-- more than a timeline can easily manage, but it was a rock shell on a stock material -- the armour of
-- every earth user on the platform -- and this direction has no rock in it. Umber is what resists, and on
-- a page what resists is gold leaf: gilding is what a scribe puts on the part of the manuscript that must
-- survive. So the leaf is laid on the caster and burnished down, and the caster is briefly an illuminated
-- figure rather than a man wearing stones.
--
-- Two shapes, and the split is the point. The ACT is short and where the caster is: leaf drawn onto the
-- body from every direction, a halo pulled out to twelve studs -- twice the glyph's Range, so the aura is
-- the size it claims -- and folded onto him with Quint-In, the cast seal's own gesture used for the
-- opposite purpose (there it closes to fire, here it closes to stay). The FOUR SECONDS are on the body
-- and nowhere else.
--
-- The gap this was once shaped around is closed: a Sprite, a Light and an Emitter follow a body now
-- (followBody), so the four seconds are ON HIM (D-125) -- the chain of brush-textured trails it used
-- instead rendered as smudges in the lab (D-119), and the act waited 0.38 s for an armour the server gives
-- on the packet. The one thing this must still NOT do is leave a ring burning on the floor for four
-- seconds: that is a zone's grammar, and it is in the wrong place the moment he walks.
local GILDING: Timeline = {
	Intent = "Leaf is struck onto the caster and burnished, and he wears it, shedding flakes, until it wears off",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The armour is the server's from the packet (CombatService.applyStoneSkin): two frames of dust,
				-- no more.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "DustMote",
					Offset = { 0, -2.4, 0 },
					Burst = 10,
					Speed = { -12, -5 },
					Lifetime = { 0.1, 0.16 },
					Spread = 175,
					Size = 0.4,
					EndSize = 0.04,
				},
				{ Kind = "Shake", At = 0, For = 0.06, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.02,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.46,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The caster made a figure (D-125): contoured in ink and washed in the pigment from the packet to the
				-- last of the server's four seconds, fading only at the end. On the body, where the armour is; never
				-- through a wall.
				{
					Kind = "Outline",
					At = 0,
					For = 3.96,
					Ease = "Quint",
					EaseDirection = "In",
					Transparency = 0,
					EndTransparency = 0.9,
				},
				-- The leaf struck on: flakes of the pigment drawn onto the body from every side, plates of it jutting
				-- up round him, a hot point at his chest and the seal under his feet. All of it on the BODY (Follow),
				-- which is where the armour is (D-125).
				{
					Kind = "Emitter",
					Follow = true,
					At = 0,
					For = 0.04,
					Texture = "PaperScrap",
					Burst = 24,
					Speed = { -12, -7 },
					Lifetime = { 0.2, 0.3 },
					Spread = 180,
					Size = 0.9,
					EndSize = 0.5,
					Transparency = 0,
					EndTransparency = 0.2,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					Follow = true,
					At = 0,
					For = 0.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 1.62, -1.4, 0.53 },
					Size = 1,
					EndSize = 4.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					Follow = true,
					At = 0,
					For = 0.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -1.4, 1.7 },
					Size = 1,
					EndSize = 4.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					Follow = true,
					At = 0,
					For = 0.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -1.62, -1.4, 0.53 },
					Size = 1,
					EndSize = 4.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					Follow = true,
					At = 0,
					For = 0.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -1, -1.4, -1.38 },
					Size = 1,
					EndSize = 4.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					Follow = true,
					At = 0,
					For = 0.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 1, -1.4, -1.38 },
					Size = 1,
					EndSize = 4.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					Follow = true,
					At = 0.04,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 0.6, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 4.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 0.5,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 2,
					EndSize = 7,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 2,
					Follow = true,
					At = 0,
					For = 0.46,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0.5, 0 },
					Range = 10,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 3.5,
			Layers = {
				-- The four seconds: the caster sheds leaf and glints as he moves -- on him, not on the floor where
				-- he stood -- and the leaf comes off in a last fall when the server's armour ends. Driven: the engine
				-- would thin a trickle of flakes to nothing (D-124).
				{
					Kind = "Emitter",
					Follow = true,
					At = 0,
					For = 3.36,
					Texture = "PaperScrap",
					Offset = { 0, -0.4, 0 },
					Rate = 14,
					Speed = { 0.5, 1.5 },
					Lifetime = { 0.5, 0.9 },
					Spread = 90,
					Weight = 10,
					Area = { 2.4, 4.6, 1.4 },
					Driven = true,
					Size = 0.55,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 0.7,
					Brightness = 1.3,
					Follow = true,
					At = 0,
					For = 3.36,
					Texture = "DustMote",
					Offset = { 0, -0.2, 0 },
					Rate = 10,
					Speed = { 0, 0.5 },
					Lifetime = { 0.15, 0.3 },
					Spread = 180,
					Area = { 2.2, 4.4, 1.4 },
					Driven = true,
					Size = 0.2,
					EndSize = 0.5,
					Pop = 0.4,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 0.8,
					Follow = true,
					At = 0,
					For = 3.5,
					Ease = "Sine",
					EaseDirection = "In",
					Offset = { 0, 0.5, 0 },
					Range = 7,
				},
				{
					Kind = "Emitter",
					Follow = true,
					At = 3.36,
					For = 0.04,
					Texture = "PaperScrap",
					Offset = { 0, -0.2, 0 },
					Burst = 18,
					Speed = { 2, 5 },
					Lifetime = { 0.5, 0.8 },
					Spread = 120,
					Weight = 18,
					Area = { 2.4, 4.4, 1.4 },
					Size = 0.7,
					EndSize = 0.35,
					Transparency = 0,
					EndTransparency = 0.5,
				},
			},
		},
	},
}

-- Rupture (Umber, ultimate). The biggest thing an Umber player does: forty-five ink, fifteen seconds,
-- thirty-five damage, and it breaks guards. GlyphEffects.Rupture is instant and centred on the caster --
-- one damageArea of Radius 18 -- and its knockback is Vector3.yAxis * Launch and nothing else, so
-- everything inside eighteen studs goes straight UP and is stunned for 0.8 seconds.
--
-- What it replaced was three Slate cylinders expanding on the ground on a stagger, forty dust particles,
-- and a camera shake. Three rings that expand, which is the example the standing rule uses for an effect
-- that could be pasted into any other game on the platform. No anticipation on an ultimate, no light, no
-- trace, no screen pulse: the loudest ability in the pigment and nothing on screen said so.
--
-- The word is the design. The page ruptures. The nib is driven down through the vellum at the caster's
-- feet and the tear runs out to exactly the studs that are damaged; everyone standing on the torn page is
-- thrown upward because the page itself has buckled under them. That is why the fountain is a fountain and
-- not a radial spray -- the server throws bodies up and nowhere else, and a spray would be a lie about
-- which way a player is about to go.
--
-- Every layer that carries information reads from every angle. The radial reading is two flat Marks, and the
-- tear propagates in TWO beats rather than one smooth expansion: three studs to twenty in 0.14, then twenty to
-- thirty-six in 0.26 -- a fracture that runs outward in stages, on the page. The edge of what launched is inked
-- at the radius the packet carries. And the page erupts: a crown of spikes of the pigment thrown up round the
-- caster, turned to every camera, the tallest at the heart, with the grit of the page thrown up and falling
-- back. It lands on the packet, with the launch (D-122): it was drawn 0.07 s later, and a grey smoke cloud hid
-- the ultimate it was.
local RUPTURE: Timeline = {
	Intent = "The page under the caster ruptures: cracks to the edge, a crown of spikes thrown up, and everyone with them",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- Grit pulled down into the ground in two frames: a burst, not a rate.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 0 },
					Burst = 16,
					Speed = { -26, -14 },
					Lifetime = { 0.08, 0.14 },
					Spread = 180,
					Squash = 0.5,
					Size = 0.7,
					EndSize = 0.05,
				},
				{
					Kind = "Light",
					Brightness = 1.8,
					At = 0,
					For = 0.1,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, -1.6, 0 },
					Range = 8,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.3,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The page cracks out to the whole radius in a third of a second.
				{
					Kind = "Mark",
					At = 0,
					For = 0.14,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 3,
					EndSize = 20,
					Transparency = 0.05,
					EndTransparency = 0.18,
				},
				{
					Kind = "Mark",
					At = 0.12,
					For = 0.26,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 20,
					EndSize = 36,
					Transparency = 0.18,
					EndTransparency = 0.2,
				},
				-- The edge of what launched, in the page's ink, as far as the server reached and no further.
				{
					Kind = "Mesh",
					Mesh = "Enso",
					Face = "Ground",
					Role = "Ink",
					At = 0,
					For = 0.5,
					Ease = "Quint",
					EaseDirection = "Out",
					SizeFrom = "Radius",
					Offset = { 0, 0.12, 0 },
					Size = 0.3,
					EndSize = 2,
					Transparency = 0.05,
					EndTransparency = 1,
					Spin = 0.8,
					Jitter = 0.35,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 12,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The page erupting: a ring of great spikes of the pigment struck up round the caster inside
				-- the radius, and the tallest at the heart. An ultimate is the same recipe as a jab, larger.
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.4,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 0, -3, 0 },
					Size = 2,
					EndSize = 24,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.36,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 8.56, -3, 2.78 },
					Size = 1,
					EndSize = 14,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.36,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -2.78, -3, 8.56 },
					Size = 1,
					EndSize = 14,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.36,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { -8.56, -3, -2.78 },
					Size = 1,
					EndSize = 14,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.36,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "InkSpike",
					Offset = { 2.78, -3, -8.56 },
					Size = 1,
					EndSize = 14,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- Grit of the page thrown up with everyone in it, and falling back.
				{
					Kind = "Emitter",
					Emit = "Up",
					At = 0,
					For = 0.12,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 0 },
					Burst = 52,
					Speed = { 28, 56 },
					Lifetime = { 0.7, 1.3 },
					Spread = 48,
					Drag = 2,
					Weight = 40,
					Squash = 0.6,
					Size = 1,
					EndSize = 0.1,
				},
				{
					Kind = "Light",
					Brightness = 4.4,
					At = 0,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 34,
				},
				{ Kind = "Shake", At = 0, For = 0.14, Profile = "Heavy" },
				{ Kind = "Flash", At = 0, For = 0.16, Profile = "PageFlash" },
			},
		},
		{
			Name = "Residue",
			Duration = 2.9,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2.9,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 36,
					EndSize = 39,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 8,
					EndSize = 10,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				-- Dust of the page settling back: short, falling, not a cloud.
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, -2, 0 },
					Rate = 14,
					Speed = { 1.5, 4 },
					Lifetime = { 0.6, 1.1 },
					Spread = 60,
					Drag = 1.5,
					Weight = 6,
					Size = 0.45,
					EndSize = 0,
				},
			},
		},
	},
}

-- Scorch (Cinnabar, zone). GlyphEffects.Scorch burns a 13-stud radius three times, 0.8 apart, ten each,
-- and re-centres on the caster's TRUSTED ORIGIN on every tick. So this is not a spell that lands
-- somewhere: it is a spell a player CARRIES, and the two things it has to say are that he is on fire and
-- that the fire catches again three times.
--
-- What it replaced said the second thing not at all: eight ember balls orbiting the caster with a sine
-- bob and one spark emitter, no light, no trace on the page, and three discrete bursts of damage rendered
-- as one continuous decoration, so the only way to learn the rhythm was to lose health to it. The one
-- thing it did have right was that it FOLLOWED -- animate(ringTrove, packet.Origin, casterRoot(packet))
-- re-centred the whole visual every frame -- and that is the thing a timeline must not lose.
--
-- Every tick on the server's clock (D-122). The first burn is at the cast point, laid on the packet with the
-- server's first damage (it used to be drawn a third of a second later): a seal struck to the zone's edge and
-- the page blotted to it -- the one place the fire has certainly been. Then, on each tick, the live danger is
-- drawn where it is: a ring of fire burning on the zone's edge, FOLLOWING the caster the server re-centres
-- the damage on, that leaps on each tick with a hot point at the caster's feet and a light. It used to be
-- carried by curtains of brush-textured ribbon on the body, which in the lab were smudges, then by a ring
-- of ink spikes on a blotted floor -- which a player called puddles, not fire (D-123): a fire stands up
-- and moves. The ring says the radius and the rhythm at once, from any camera.
local SCORCH: Timeline = {
	Intent = "The ground round the caster catches three times, a ring of fire struck on each of the server's ticks",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The ground under the caster darkening, two frames before the first tick.
				{
					Kind = "Mark",
					At = 0,
					For = 0.3,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 0.8,
					EndSize = 4.2,
					Transparency = 0.18,
					EndTransparency = 0.85,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "DustMote",
					Offset = { 0, -2.4, 0 },
					Burst = 10,
					Speed = { -12, -5 },
					Lifetime = { 0.1, 0.18 },
					Spread = 175,
					Size = 0.4,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
			},
		},
		{
			Name = "Impact",
			-- Its layers are laid three hundredths after the packet: the server's ticks, less that.
			Duration = 1.6,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The first burn, at the cast point, on the server's first tick: a seal struck to the zone's edge, the
				-- page blotted to it.
				{
					Kind = "Mark",
					At = 0,
					For = 0.46,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 3,
					EndSize = 26,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.06,
					For = 0.5,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 9,
					EndSize = 24,
					Transparency = 0.3,
					EndTransparency = 0.42,
				},
				{
					Kind = "Mark",
					At = 0.48,
					For = 1.12,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 24,
					EndSize = 25.5,
					Transparency = 0.42,
					EndTransparency = 0.5,
				},
				-- The fire itself (D-123), on the zone's edge -- the server's Radius -- and FOLLOWING the caster the
				-- server re-centres the burn on: a ring of pigment tongues burning through all three ticks, a hot
				-- heart low in it and soot of ink licking off its top. Driven: the engine's own quality thins a
				-- rate to a few embers, and a ring of fire with gaps in it is a ring of puddles.
				{
					Kind = "Emitter",
					Follow = true,
					At = 0,
					For = 1.62,
					Texture = "InkFlame",
					Offset = { 0, -1.6, 0 },
					Area = { 26, 0.3, 26 },
					Ring = true,
					Rate = 110,
					Driven = true,
					Speed = { 3, 6 },
					Lifetime = { 0.4, 0.7 },
					Spread = 6,
					Drag = 1,
					Sway = 10,
					Size = 3.4,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 0.8,
					Brightness = 1.4,
					Follow = true,
					At = 0,
					For = 1.62,
					Texture = "InkFlame",
					Offset = { 0, -2.1, 0 },
					Area = { 25, 0.2, 25 },
					Ring = true,
					Rate = 40,
					Driven = true,
					Speed = { 2, 4 },
					Lifetime = { 0.25, 0.4 },
					Spread = 6,
					Drag = 1,
					Sway = 8,
					Size = 1.5,
					EndSize = 0.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Ink",
					Follow = true,
					At = 0.1,
					For = 1.52,
					Texture = "InkFlame",
					Offset = { 0, -0.4, 0 },
					Area = { 26, 0.4, 26 },
					Ring = true,
					Rate = 22,
					Driven = true,
					Speed = { 4, 7 },
					Lifetime = { 0.3, 0.5 },
					Spread = 10,
					Drag = 1.5,
					Sway = 16,
					Size = 1.7,
					EndSize = 0.2,
					Transparency = 0.1,
					EndTransparency = 0.7,
				},
				-- Each tick of the server's (0, 0.8 and 1.6 s after the packet; three hundredths in here): the ring
				-- leaps, tall tongues of the pigment all round the caster at the zone's edge, a hot point at their
				-- feet and the light. The ring and its leaps say the radius and the rhythm at once (D-122, D-123).
				{
					Kind = "Emitter",
					Follow = true,
					At = 0,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 0 },
					Area = { 26, 0.3, 26 },
					Ring = true,
					Burst = 20,
					Speed = { 9, 13 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 4.4,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.5, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 4,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 2.6,
					Follow = true,
					At = 0,
					For = 0.6,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.4, 0 },
					Range = 20,
				},
				{
					Kind = "Emitter",
					Follow = true,
					At = 0.77,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 0 },
					Area = { 26, 0.3, 26 },
					Ring = true,
					Burst = 20,
					Speed = { 9, 13 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 4.4,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0.77,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.5, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 4,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 2.6,
					Follow = true,
					At = 0.77,
					For = 0.6,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.4, 0 },
					Range = 20,
				},
				{
					Kind = "Emitter",
					Follow = true,
					At = 1.57,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 0 },
					Area = { 26, 0.3, 26 },
					Ring = true,
					Burst = 20,
					Speed = { 9, 13 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 4.4,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 1.57,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.5, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 4,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 2.6,
					Follow = true,
					At = 1.57,
					For = 0.6,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.4, 0 },
					Range = 20,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 25,
					EndSize = 27,
					Transparency = 0.5,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Rate = 10,
					Speed = { 0.6, 2.2 },
					Lifetime = { 0.8, 1.5 },
					Spread = 150,
					Size = 0.34,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Ligature (Cinnabar, mobility). A ligature is the stroke that joins two letters without lifting the nib,
-- and that is what the server does: GlyphEffects.Ligature dashes the caster its full 20 studs in 0.25 s
-- and lays five pools at cast time, at 0, 4, 8, 12 and 16 studs, five studs of radius each, burning five
-- times 0.4 apart. One stroke, written once, still wet, and on fire.
--
-- What it replaced was a ball tweened with Enum.EasingStyle.Linear written into the call -- rule 4 broken
-- in the source, not by accident -- followed by five Roblox cylinders growing out of the floor, each in
-- 0.2 s whenever its own task.delay fired, which is to say in no relation to the stroke that was supposed
-- to have dropped it. No light, and nothing the world kept.
--
-- Here there is one body: an invisible carrier travelling the ink line's own 16 studs, with the trail, the
-- embers and the light riding it, so none of the three can disagree about where the nib is. The five
-- pools are Mark layers offset forward by the server's own spacing, and their start times are where the
-- carrier's eased curve puts the nib over each one -- the ink lands UNDER the nib, not near it.
--
-- Each pool is TWO marks, and that is not decoration: stepMark used to drive size and transparency off
-- the same eased alpha (D-108 decoupled them), so the single Circular-out stain this replaced was 75 %
-- transparent within 0.6 s of a 2.3 s life while the server went on damaging those exact points at 0.8,
-- 1.2 and 1.6. The wick lands fast (Circular/Out to the full ten studs, which is twice TrailRadius, so the
-- stain IS the hitbox) and hands over at its own transparency to a burn that holds through the last tick
-- on Quint/In and only then chars away.
--
-- The offsets 0/4/8/12/16 are GlyphConfig's TrailSegments and TrailSpacing spelled out, because data
-- cannot read Params: changing either there, or passing a Scale other than 1, de-registers every stain
-- from the hitbox it draws.
--
-- Same clock compromise as Scorch: the four flares land on the server's 0.4, 0.8, 1.2 and 1.6. The fifth
-- tick is the one at zero, and its visual is the stroke being written. No Shake layer -- the dash goes
-- through grantMovement, so MovementController already shakes the camera of whoever ran it.
-- D-123: the pools spread where the server laid them within a tenth of a second (its first tick burns on
-- the packet), the stroke under the dash is bare ink with a burning line, a fire of standing tongues burns
-- on the pools (a stain alone read as a puddle), and each later tick makes it leap.
local LIGATURE: Timeline = {
	Intent = "The caster runs a burning stroke along the floor; its pools flare on each of the server's ticks",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- Dust kicked off the first step, two frames: the dash is the server's, it starts now, and the
				-- floor under it is the first pool's (D-123).
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "DustMote",
					Offset = { 0, -2.2, 0 },
					Burst = 10,
					Speed = { -10, -4 },
					Lifetime = { 0.1, 0.16 },
					Spread = 170,
					Size = 0.34,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Travel",
			Duration = 0.25,
			Layers = {
				-- The ink laid under the dash, along the path the server moves the body (DashDuration, Range).
				{
					Kind = "Carrier",
					At = 0,
					For = 0.25,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, -1.8, 0 },
					Travel = 20,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				-- The stroke, bare: a ribbon of the page's ink along the dash and a burning line inside it.
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 0.25,
					Size = 2.4,
					EndSize = 0.3,
					Ribbon = 0.25,
					Transparency = 0.05,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					Ride = true,
					At = 0,
					For = 0.25,
					Size = 1,
					EndSize = 0.1,
					Ribbon = 0.16,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 2.2,
					Ride = true,
					At = 0,
					For = 0.26,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 12,
				},
				-- The fire (D-123): the pools are the floor the server burns, and a stain on its own read as a
				-- puddle. A bed of pigment tongues stands on the whole stroke until its last tick, with a hot
				-- heart inside it; the soot licking off its top is the Impact's, once the fire has taken.
				{
					Kind = "Emitter",
					At = 0.02,
					For = 1.62,
					Texture = "InkFlame",
					Offset = { 0, -1.6, 8 },
					Area = { 7, 0.3, 19 },
					Rate = 80,
					Driven = true,
					Speed = { 3, 6 },
					Lifetime = { 0.4, 0.7 },
					Spread = 6,
					Drag = 1,
					Sway = 10,
					Size = 3,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 0.8,
					Brightness = 1.4,
					At = 0.02,
					For = 1.62,
					Texture = "InkFlame",
					Offset = { 0, -2.1, 8 },
					Area = { 4, 0.2, 17 },
					Rate = 40,
					Driven = true,
					Speed = { 2, 4 },
					Lifetime = { 0.25, 0.4 },
					Spread = 6,
					Drag = 1,
					Sway = 8,
					Size = 1.3,
					EndSize = 0.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The five pools, where the server laid them at the cast and burns them from its first tick: all
				-- five spread within a tenth of a second, ahead of the dash, not as it passes (D-123).
				{
					Kind = "Mark",
					At = 0,
					For = 0.3,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 0 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.15,
					EndTransparency = 0.3,
				},
				{
					Kind = "Mark",
					At = 0.02,
					For = 0.3,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 4 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.15,
					EndTransparency = 0.3,
				},
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.3,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 8 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.15,
					EndTransparency = 0.3,
				},
				{
					Kind = "Mark",
					At = 0.06,
					For = 0.3,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 12 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.15,
					EndTransparency = 0.3,
				},
				{
					Kind = "Mark",
					At = 0.08,
					For = 0.3,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 16 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.15,
					EndTransparency = 0.3,
				},
				{
					Kind = "Mark",
					At = 0.3,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 0 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.32,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 4 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.34,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 8 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.36,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 12 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.38,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 16 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 1.44,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- Soot of ink licking off the fire's top: what detaches a pale pigment's fire from a pale page.
				{
					Kind = "Emitter",
					Role = "Ink",
					At = 0.01,
					For = 1.35,
					Texture = "InkFlame",
					Offset = { 0, -0.4, 8 },
					Area = { 6, 0.4, 18 },
					Rate = 22,
					Driven = true,
					Speed = { 4, 7 },
					Lifetime = { 0.3, 0.5 },
					Spread = 10,
					Drag = 1.5,
					Sway = 16,
					Size = 1.5,
					EndSize = 0.2,
					Transparency = 0.1,
					EndTransparency = 0.7,
				},
				-- Each of the server's later ticks: the fire leaps, tall tongues of its pigment, and the light.
				{
					Kind = "Light",
					Brightness = 1.9,
					At = 0.13,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
				},
				{
					Kind = "Emitter",
					At = 0.13,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 8 },
					Area = { 6, 0.3, 18 },
					Burst = 10,
					Speed = { 8, 12 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 3.8,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Light",
					Brightness = 1.9,
					At = 0.53,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
				},
				{
					Kind = "Emitter",
					At = 0.53,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 8 },
					Area = { 6, 0.3, 18 },
					Burst = 10,
					Speed = { 8, 12 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 3.8,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Light",
					Brightness = 1.9,
					At = 0.93,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
				},
				{
					Kind = "Emitter",
					At = 0.93,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 8 },
					Area = { 6, 0.3, 18 },
					Burst = 10,
					Speed = { 8, 12 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 3.8,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
				{
					Kind = "Light",
					Brightness = 1.9,
					At = 1.33,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
				},
				{
					Kind = "Emitter",
					At = 1.33,
					For = 0.04,
					Texture = "InkFlame",
					Offset = { 0, -1.2, 8 },
					Area = { 6, 0.3, 18 },
					Burst = 10,
					Speed = { 8, 12 },
					Lifetime = { 0.22, 0.34 },
					Spread = 8,
					Drag = 3,
					Sway = 8,
					Size = 3.8,
					EndSize = 0.4,
					Transparency = 0,
					EndTransparency = 0.4,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.3,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, -1.4, 8 },
					Rate = 10,
					Speed = { 0.5, 2 },
					Lifetime = { 0.7, 1.3 },
					Spread = 150,
					Size = 0.32,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Blot (Cinnabar, ultimate). Fifty ink, twenty seconds, forty-five damage, and it breaks guards: the
-- heaviest single thing a Cinnabar player owns. Its name is the whole image -- a blot is what an
-- overloaded nib drops on a page, and what it lands on is not readable again.
--
-- What it replaced was a CrackedLava ball wearing Roblox's own Fire class: the same defect Brand had, in
-- the same school, on the game's most expensive spell. It also flew wrong at both ends. The renderer took
-- its flight as min(Fuse, Range / Speed) = 1.364 s, but the server measures Range along the PATH of a
-- bell arc rather than along the ground, so stepProjectile stops at 1.208 s, 66.4 studs out and 9.5 studs
-- UP -- the rock kept flying 8.6 studs past a detonation that had already been broadcast, and ended
-- 7.6 studs below it.
--
-- So: 66 studs, not 75, and 20 studs of arc, which is ArcHeight and peaks where the server's parabola
-- peaks. The body is not a sphere -- a sphere that grows and fades is the failure the mission names -- it
-- is a clot of ink particles, ragged, tumbling with the carrier, shedding smoke and dragging one wide wet
-- stroke across the sky.
--
-- The carrier is offset four studs up as well as the server's five forward, and that is the arc's one
-- unfixable seam paid down as far as the format allows: stepCarrier's rise is Arc * sin(alpha * pi), which
-- is zero at both ends, so a flight cannot END above where it began, while the server's does, by 9.5
-- studs. Four splits the error at the landing and is closer to the truth in the middle too, since the real
-- projectile is already thirteen studs up by the time this visual launches.
--
-- The flight is 0.92 s rather than the true 1.208 because a wind-up is not free: the server threw at the
-- instant the packet left, and 0.28 s of anticipation has to be paid back. It is paid in the middle of the
-- arc -- about 19 studs behind early, 4 ahead late -- and not at the ends, because the launch point and
-- the landing instant are the two things a player reads off an ultimate, and Travel ending at 1.20 s puts
-- the clot where the blast opens within eight milliseconds. The real telegraph an ultimate wants is a
-- server cast time; there is none, and no timeline can invent one without lying about when it fired.
-- D-123: the server's own flight -- speed, fuse and bell arc -- from its packet (it left 0.28 s late and flew
-- faster and lower than the meteor that burns), a heavy drop with a bare wake, named so its burst lands it.
local BLOT: Timeline = {
	Intent = "A meteor of ink is heaved up the page and comes down as the loudest blot on it",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- Ink pulled into the hand in two frames: the server lets the meteor go on its packet.
				{
					Kind = "Emitter",
					Anchor = "Hand",
					At = 0,
					For = 0.02,
					Texture = "InkBlot",
					Offset = { 0.8, 0.8, 0.2 },
					Burst = 14,
					Speed = { -17, -9 },
					Lifetime = { 0.1, 0.18 },
					Spread = 180,
					Size = 1.2,
					EndSize = 0.2,
					Transparency = 0.05,
					EndTransparency = 0.9,
				},
				{
					Kind = "Light",
					Brightness = 3,
					Anchor = "Hand",
					At = 0,
					For = 0.24,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0.8, 0.8, 0.2 },
					Range = 11,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The heave: ink thrown out of the hand along the aim.
				{
					Kind = "Emitter",
					Emit = "Aim",
					Anchor = "Hand",
					At = 0,
					For = 0.05,
					Texture = "InkBlot",
					Offset = { 0.8, 0.8, 0.4 },
					Burst = 20,
					Speed = { 18, 34 },
					Lifetime = { 0.2, 0.4 },
					Spread = 35,
					Drag = 3,
					Weight = 30,
					Size = 1.2,
					EndSize = 0.2,
					Transparency = 0.05,
					EndTransparency = 0.9,
				},
				-- The caster's feet stained by the heave.
				{
					Kind = "Mark",
					At = 0,
					For = 2.3,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 2.2,
					EndSize = 3.8,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Travel",
			Duration = 1.37,
			Layers = {
				-- The server's own flight (D-123): its speed (55) and fuse (1.4), its bell arc of ArcHeight 20 peaking at
				-- half the fuse, from where the meteor already is three hundredths in. It used to leave 0.28 s late and
				-- fly faster and lower than the one that burns. Its burst lands it (VfxTimeline.land).
				{
					Kind = "Carrier",
					At = 0,
					For = 1.37,
					Ease = "Sine",
					EaseDirection = "In",
					Offset = { 0, 0.4, 6.6 },
					Travel = 73.3,
					Arc = 20,
					EaseShare = 0.15,
				},
				-- The meteor itself: a drop swelling as it leaves the hand, riding the flight. Its burst splats it
				-- (VfxTimeline.land).
				{
					Kind = "Mesh",
					Mesh = "Drop",
					Ride = true,
					At = 0,
					For = 1.37,
					Ease = "Quart",
					EaseDirection = "Out",
					Size = 0.8,
					EndSize = 3.2,
					Stretch = { 0.8, 0.8, 1.5 },
					EndStretch = { 1, 1, 1.1 },
					Transparency = 0,
					EndTransparency = 0,
				},
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				-- Its wake, bare: a wide stroke of the page's ink and a burning line inside it -- an ultimate may bloom.
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 1.37,
					Size = 3.4,
					EndSize = 0.2,
					Ribbon = 0.3,
					Transparency = 0.05,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					Ride = true,
					At = 0,
					For = 1.37,
					Size = 1.4,
					EndSize = 0.05,
					Ribbon = 0.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- Beads of the pigment shaken off, falling to the page all along the arc.
				{
					Kind = "Emitter",
					Ride = true,
					At = 0,
					For = 1.37,
					Texture = "InkBlot",
					Rate = 40,
					Driven = true,
					Speed = { 0.5, 3 },
					Lifetime = { 0.35, 0.7 },
					Spread = 180,
					Drag = 2,
					Weight = 30,
					Size = 0.9,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 2,
					Ride = true,
					At = 0,
					For = 1.37,
					Texture = "DustMote",
					Rate = 30,
					Driven = true,
					Speed = { 0.5, 2 },
					Lifetime = { 0.15, 0.3 },
					Spread = 180,
					Drag = 2,
					Size = 0.5,
					EndSize = 0,
				},
				-- The meteor burns as it falls (D-123): tongues of its pigment standing off it and left burning
				-- along its arc, driven so no device thins its fire to a few sparks (D-124).
				{
					Kind = "Emitter",
					Ride = true,
					At = 0,
					For = 1.37,
					Texture = "InkFlame",
					Rate = 60,
					Driven = true,
					Speed = { 1, 3 },
					Lifetime = { 0.25, 0.45 },
					Spread = 20,
					Drag = 1,
					Sway = 12,
					Size = 2.8,
					EndSize = 0.3,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Light",
					Brightness = 3.6,
					Ride = true,
					At = 0,
					For = 1.37,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 24,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.5,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.7,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Rate = 7,
					Speed = { 0.3, 1.5 },
					Lifetime = { 0.6, 1.1 },
					Spread = 160,
					Size = 0.34,
					EndSize = 0,
				},
			},
		},
	},
}

-- Strike (Orpiment, hitscan). The school's thesis, in one glyph: Orpiment does not fly, it is already
-- there. Its French name is Rature -- a strikethrough -- and that is literally the effect: a line ruled
-- across the page, through whatever was standing in it.
--
-- What it replaced was a jittered neon bolt drawn between the caster and the victim, with a spark flash at
-- the far end. It failed on every count that matters. Random per-segment jitter is stock Roblox lightning,
-- so the effect would have gone unnoticed in any other game, which is the failure criterion. It appeared
-- whole, at full strength, with no before (rules 3 and 4). It left nothing on the ground (rule 5). And it
-- lit nothing, so at range the only thing that told a player they had been hit was their health bar.
--
-- The line is RULED, not revealed: a carrier crosses the glyph's whole range in eighty milliseconds with a
-- Trail riding it. Eighty milliseconds is below the threshold at which a player can track a moving thing,
-- so it reads as already there -- and yet nothing appeared, because the stroke was drawn, from the hand
-- outward, in the direction a pen moves. That is how an instant effect obeys rule 3 instead of arguing
-- with it. The carrier is declared in the CAST phase and not in TRAVEL on purpose: there is no flight
-- here. The nib crosses the page; nothing is going anywhere.
--
-- It has no Arc, and that absence is the school. Cinnabar's Brand rises and falls three studs because a
-- thing thrown by a hand curves; a ruled line is straight. Those two carriers differ by one field, and
-- that field is the whole difference between the two houses.
--
-- Renderer contract (VfxLibrary.Strike, D-126): Origin is the muzzle (packet Origin advanced by
-- Params.SpawnOffset) and Reach is Params.Range -- the length the ray ACTUALLY reached, past the body it
-- damaged and up to the wall that stopped it, which is correct for a strikethrough. The carrier travels
-- exactly that (TravelFrom), and the line left on the page is that long. It used to be drawn from the
-- caster over a fixed seventy studs, 0.21 s after the damage: the contract written here was never played.
-- A riding Trail never moves its caster (followBody), so Follow may be set.
--
-- It has no Impact phase and no page flash. Its landing is the Hit packet CombatService.ApplyDamage
-- already emits for the model it damaged, which brings the ring, the bleach and the ink burn at the exact
-- point the server validated. Two PageFlash pulses composed would pin saturation at its clamp (see the
-- Erasure note in LightingConfig), so the one that is correctly placed is the one that plays.
local STRIKE: Timeline = {
	Intent = "A line is ruled across the page, through whatever was standing in it, and left to dry",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The nib touches the page at the hand: two frames, because the server's ray has already been cast.
				{
					Kind = "Emitter",
					Emit = "Aim",
					Anchor = "Hand",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Burst = 12,
					Speed = { 14, 26 },
					Lifetime = { 0.08, 0.14 },
					Spread = 20,
					Squash = 0.4,
					Size = 0.5,
					EndSize = 0.05,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Travel",
			Duration = 0.3,
			Layers = {
				{ Kind = "Sound", At = 0.05, For = 0.05, Voice = "Impact" },
				-- Ruled in six hundredths to where the server's ray stopped (TravelFrom Reach, D-126): past the body
				-- it struck, up to the wall. A ruled line: a thin one of ink in a band of the pigment, a hot line inside.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.06,
					Ease = "Sine",
					EaseDirection = "Out",
					TravelFrom = "Reach",
					Travel = 1,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				{
					Kind = "Trail",
					Ride = true,
					At = 0,
					For = 0.3,
					Size = 1.3,
					EndSize = 0.5,
					Ribbon = 0.3,
					Transparency = 0.1,
					EndTransparency = 0.8,
				},
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 0.3,
					Size = 0.6,
					EndSize = 0.3,
					Ribbon = 0.3,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Trail",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					Ride = true,
					At = 0,
					For = 0.3,
					Size = 0.3,
					EndSize = 0.08,
					Ribbon = 0.22,
					Transparency = 0,
					EndTransparency = 0.7,
				},
				{
					Kind = "Light",
					Brightness = 2.4,
					Ride = true,
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 10,
				},
				{
					Kind = "Emitter",
					Ride = true,
					At = 0,
					For = 0.06,
					Texture = "SparkStreak",
					Rate = 250,
					Speed = { 2, 6 },
					Lifetime = { 0.2, 0.35 },
					Spread = 60,
					Drag = 2,
					Driven = true,
					Squash = 0.4,
					Size = 0.45,
					EndSize = 0,
				},
				-- Where it stopped: the nib kicks back off the wall or the body, sparks and a hot point.
				{
					Kind = "Emitter",
					Emit = "Back",
					At = 0.06,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 14,
					Speed = { 8, 16 },
					Lifetime = { 0.12, 0.24 },
					Spread = 50,
					Squash = 0.4,
					Size = 0.55,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0.06,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.5,
			Layers = {
				-- The line left on the page, the length the server ruled, drying.
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0.04, 0.5 },
					Span = 1,
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Size = 1,
					EndSize = 1.3,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Texture = "DustMote",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Rate = 11,
					Speed = { 0.5, 2 },
					Lifetime = { 0.5, 0.9 },
					Spread = 150,
					Size = 0.32,
					EndSize = 0,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Caret (Orpiment, mobility). The proofreader's insertion mark. The body is struck out where it was and
-- inserted where it arrives, which is the only teleport this art direction can have: on a page, moving is
-- an edit.
--
-- What it replaced was a jittered bolt between the two ends, an identical spark flash at each, and a
-- ForceField ball at the destination for the i-frame window. The ForceField is Roblox's own bubble and
-- belongs to every other game; the bolt is stock lightning; and the two ends being identical is the real
-- defect, because it is a competitive one. A player who sees a blink from thirty studs has to know which
-- end is the arrival, instantly, or the effect has told them a fight is happening somewhere without
-- telling them where. Nothing was left on the ground either, so an opponent who looked away for a frame
-- lost the information entirely.
--
-- The two ends are therefore OPPOSITE GESTURES in the same pigment. Departure collapses: ink is pulled off
-- the page, a stroke closes over the silhouette, smoke is sucked inward into the hole. Arrival opens: a
-- mark overshoots outward, ink is thrown forward, the light comes up. Nobody has to learn this; inward and
-- outward are read before they are thought about.
--
-- Between them, the caret itself. A carrier crosses the gap in seventy milliseconds with five studs of Arc
-- and a Trail riding it, so the ink traces a rise and a fall -- the glyph's own typographic mark, drawn in
-- the air, in one gesture, by the path. Sine-in-out puts the apex in the middle and makes the stroke start,
-- accelerate and land, which is rule 4 satisfied by the shape rather than by a curve name. Two hundred and
-- fifty studs a second with a pronounced arc cannot be mistaken for the Ligature dash at eighty studs a
-- second and flat, which is the one confusion that would be expensive.
--
-- Its Anticipation is not a wind-up and must not be read as one. The server teleports on the frame it
-- emits, so by the time the packet lands the body has already gone: this phase is the hole he left,
-- closing, which is why it collapses inward instead of gathering. Eighty milliseconds, so the arrival is
-- never late.
--
-- Renderer contract (VfxLibrary.Caret, D-126): Origin is the departure (the packet's own Origin) and
-- Reach is Params.Range, the distance the server validated against walls and ground: the carrier travels
-- it (TravelFrom) and everything of the arrival is at Offset {0, 0, 1} of it. It used to fly a fixed
-- eighteen studs 0.18 s after the body had already moved. The Anticipation is two frames now, for the same
-- reason it was never a wind-up: the body has already gone.
local CARET: Timeline = {
	Intent = "The body is struck out where it stood and inserted where it lands, the caret drawn between",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The hole he left, closing: the server has already moved the body.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Offset = { 0, 0.6, 0 },
					Burst = 18,
					Speed = { -14, -8 },
					Lifetime = { 0.12, 0.18 },
					Spread = 180,
					Squash = 0.4,
					Size = 0.5,
					EndSize = 0.04,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Dash" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
			},
		},
		{
			Name = "Travel",
			Duration = 0.34,
			Layers = {
				{ Kind = "Sound", At = 0.05, For = 0.05, Voice = "Impact" },
				-- Struck out where he stood: a stroke of ink across the spot, standing, turned to whoever looks.
				{
					Kind = "Sprite",
					Face = "Camera",
					Role = "Ink",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0.4, 0 },
					Span = 1.3,
					Size = 5,
					EndSize = 3.2,
					Transparency = 0,
					EndTransparency = 1,
				},
				-- The caret between, drawn in the air: a rise and a fall to where the server put him (TravelFrom
				-- Reach, D-126): a band of the pigment, a thin line of ink in it, a hot line inside.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.07,
					Ease = "Sine",
					EaseDirection = "InOut",
					TravelFrom = "Reach",
					Offset = { 0, 0.6, 0 },
					Travel = 1,
					Arc = 5,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				{
					Kind = "Trail",
					Ride = true,
					At = 0,
					For = 0.3,
					Size = 1.4,
					EndSize = 0.4,
					Ribbon = 0.3,
					Transparency = 0.1,
					EndTransparency = 0.8,
				},
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 0.3,
					Size = 0.6,
					EndSize = 0.25,
					Ribbon = 0.3,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Trail",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					Ride = true,
					At = 0,
					For = 0.3,
					Size = 0.3,
					EndSize = 0.06,
					Ribbon = 0.2,
					Transparency = 0,
					EndTransparency = 0.7,
				},
				-- Inserted where he lands: a ring that opens toward the camera, ink thrown forward, a hot point.
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.07,
					For = 0.3,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Size = 1,
					EndSize = 7,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Emit = "Aim",
					At = 0.07,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 18,
					Speed = { 10, 20 },
					Lifetime = { 0.14, 0.26 },
					Spread = 45,
					Squash = 0.4,
					Size = 0.5,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 0.07,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					Brightness = 2,
					At = 0.07,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Range = 10,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.2,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.2,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2.8,
					EndSize = 3.6,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.2,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0.04, 1 },
					OffsetFrom = "Reach",
					Size = 3.4,
					EndSize = 4.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Watermark (Orpiment, zone). A watermark is not drawn on a sheet, it is pressed INTO it by the mould and
-- shows when the light catches the paper. That is the whole effect, and it is the one glyph in the game
-- that has a reason to use the PaperGrain texture: the mark is a change in the page itself.
--
-- What it replaced was a cylinder that grew to the zone's radius, a continuous spark emitter, and four
-- bursts of randomly aimed jitter-bolts flung at the rim. It looked the same at every moment of its life
-- except for the bolts, which were noise rather than information, and the disc's constant crackle said
-- "dangerous" without ever saying "dangerous NOW". The server micro-stuns on a tick, not continuously.
--
-- So it is built as four presses, at zero, seven tenths, one and four tenths and two and one tenth --
-- exactly GlyphEffects.tickZone's schedule for Ticks = 4, TickInterval = 0.7, whose first tick fires on
-- the frame the packet is emitted and which waits the interval only BEFORE each later tick. The four are
-- IDENTICAL, deliberately: the four ticks are identical, and a fourth press drawn heavier would promise
-- damage the server does not deal.
--
-- Each press is lit FROM UNDER THE FLOOR. That is the glyph, and it is the one thing in here no other
-- effect may borrow: buildLight sets Shadows = false, so a PointLight a stud and a bit below the ground is
-- not occluded by it and the sheet lights from beneath, underlighting the legs of everyone standing in the
-- zone. A light pulsing at the centre of a disc is the stock Roblox zone tick and would go unnoticed
-- anywhere; a page lit from behind is what a watermark IS.
--
-- The fibre is thrown far enough to be seen by the person it threatens. A burst that dies two studs from
-- the centre of a twenty-four-stud footprint is invisible to someone standing at the rim, which is where
-- the decision to leave gets made; at Speed 16-26 with Drag 1.4 it carries nine or ten studs and stops.
--
-- The zone stops DRAWING danger on the frame it stops DEALING it. The last damaging tick lands at 2.1, so
-- the Impact phase is 2.34 -- that tick plus its own press -- and not the 2.8 the packet's Duration field
-- carries, because Ticks * TickInterval overshoots the server's own last tick by a whole interval. A floor
-- that says "you cannot stand here" after it is safe is the same lie as a projectile outflying its range,
-- pointed the other way.
--
-- It has no Anticipation phase, and that is the same rule Hit and Explosion follow: a zone that damages on
-- the frame it lands has no window to telegraph, and drawing one would promise a window that does not
-- exist. Its wind-up was the Cast seal the player already watched.
--
-- It uses no Sprite layer, which is a decision and not an oversight. A Sprite is a plane oriented by the
-- play's Direction, so a flat disc on the ground would depend on the renderer passing a vertical direction
-- -- and would silently become a standing wall if anyone later passed the cast direction instead. A Mark
-- is flat by construction. Everything of this glyph that belongs to the floor is a Mark, and everything
-- else is light, particles and camera.
--
-- No Flash layer either. Each press damages everyone standing in it, and every one of those hits emits its
-- own Hit packet with its own PageFlash; four presses times three targets is twelve pulses already, and
-- LightingConfig's Erasure note explains what composing them does to saturation.
--
-- Renderer contract: Origin is the packet's Origin, which GlyphEffects.Watermark has ALREADY moved
-- Params.Offset studs ahead of the caster -- no forward offset here. Its edge and each press are measured
-- against the Radius the packet sends (SizeFrom): the mould is the zone. D-126: the presses were paper grain
-- laid on paper, invisible; they are a seal pressed onto an ink edge now.
local WATERMARK: Timeline = {
	Intent = "The mould comes down on the page four times, and the paper keeps the impression",
	Phases = {
		{
			Name = "Impact",
			Duration = 2.34,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The mould's edge, in ink, at the server's Radius for as long as it presses (D-126): Orpiment on
				-- vellum is gold on cream, and the ink is what says where the zone ends.
				{
					Kind = "Mark",
					Role = "Ink",
					At = 0,
					For = 2.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					SizeFrom = "Radius",
					Offset = { 0, 0.04, 0 },
					Size = 1.6,
					EndSize = 2,
					Transparency = 0.25,
					EndTransparency = 0.6,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "GradientRadial",
					SizeFrom = "Radius",
					Size = 1.6,
					EndSize = 2,
					Transparency = 0.5,
					EndTransparency = 0.85,
				},
				-- Each press of the server's (0, 0.7, 1.4, 2.1): the mould comes down onto the zone's edge, a hot
				-- point at its heart, flecks of the pigment jumping and falling, the light.
				{
					Kind = "Mark",
					At = 0,
					For = 0.45,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "SealRing",
					SizeFrom = "Radius",
					Offset = { 0, 0.08, 0 },
					Size = 2.4,
					EndSize = 2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.4, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 26,
					Speed = { 4, 9 },
					Lifetime = { 0.35, 0.6 },
					Spread = 70,
					Weight = 18,
					Size = 0.4,
					EndSize = 0.1,
				},
				{
					Kind = "Light",
					Brightness = 1.8,
					At = 0,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 16,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
				{
					Kind = "Mark",
					At = 0.7,
					For = 0.45,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "SealRing",
					SizeFrom = "Radius",
					Offset = { 0, 0.08, 0 },
					Size = 2.4,
					EndSize = 2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 0.7,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.4, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.7,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 26,
					Speed = { 4, 9 },
					Lifetime = { 0.35, 0.6 },
					Spread = 70,
					Weight = 18,
					Size = 0.4,
					EndSize = 0.1,
				},
				{
					Kind = "Light",
					Brightness = 1.8,
					At = 0.7,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 16,
				},
				{ Kind = "Shake", At = 0.7, For = 0.05, Profile = "Light" },
				{
					Kind = "Mark",
					At = 1.4,
					For = 0.45,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "SealRing",
					SizeFrom = "Radius",
					Offset = { 0, 0.08, 0 },
					Size = 2.4,
					EndSize = 2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 1.4,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.4, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 1.4,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 26,
					Speed = { 4, 9 },
					Lifetime = { 0.35, 0.6 },
					Spread = 70,
					Weight = 18,
					Size = 0.4,
					EndSize = 0.1,
				},
				{
					Kind = "Light",
					Brightness = 1.8,
					At = 1.4,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 16,
				},
				{ Kind = "Shake", At = 1.4, For = 0.05, Profile = "Light" },
				{
					Kind = "Mark",
					At = 2.1,
					For = 0.45,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "SealRing",
					SizeFrom = "Radius",
					Offset = { 0, 0.08, 0 },
					Size = 2.4,
					EndSize = 2,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.4,
					At = 2.1,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.4, 0 },
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.12 },
					Spread = 0,
					Size = 0.6,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 2.1,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, -1.8, 0 },
					Burst = 26,
					Speed = { 4, 9 },
					Lifetime = { 0.35, 0.6 },
					Spread = 70,
					Weight = 18,
					Size = 0.4,
					EndSize = 0.1,
				},
				{
					Kind = "Light",
					Brightness = 1.8,
					At = 2.1,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 16,
				},
				{ Kind = "Shake", At = 2.1, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Residue",
			Duration = 2,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.9,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 13,
					EndSize = 17,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.1,
					Texture = "DustMote",
					Offset = { 0, -1.5, 0 },
					Rate = 10,
					Speed = { 0.5, 2 },
					Lifetime = { 0.7, 1.2 },
					Spread = 150,
					Size = 0.42,
					EndSize = 0,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Colophon (Orpiment, ultimate). A colophon is the inscription at the end of a manuscript: the mark that
-- says here ends, and who made it. This is the heaviest thing in the roster -- four Orpiment inputs, fifty
-- five ink, twenty-five seconds, forty damage, breaks guards, six tenths of a second of stun on every link
-- -- so the image has to be the last word, not a big version of a small spell.
--
-- What it replaced was a bolt out of the sky onto the first victim and then jittered bolts chaining, each
-- with a spark flash and a large camera shake. It is the single most copied ultimate on the platform, so by
-- the mission's own criterion it had already failed; but the worse defect is that it CONTRADICTED the
-- spell. The server fires a hitscan forward from the caster's hand. A bolt falling out of the sky tells
-- every player watching that this ultimate comes from above, which is unlearnable and therefore
-- undodgeable -- the visual was teaching the wrong lesson about a twenty-five-second cooldown. And after
-- stunning three people for six tenths of a second each, it left the floor exactly as it found it.
--
-- It is a SIGNATURE: one broad stroke, ruled from the hand, that does not lift. The stroke is a Beam
-- because a Beam's length is eight times its width by construction -- do not "fix" that ratio, it is
-- load-bearing: seven and a half studs wide over sixty long is a pen bearing down, and it is nearly five
-- times the width of Strike's hairline for a glyph that does not quite double the damage. That gap in
-- weight is what stops an ultimate from reading as a basic. The stroke is laid twice, a bright pass that
-- snaps shut and a drier pass that takes half a second to go, because a signature is never one pass.
--
-- The seal doubles. Colophon is the only glyph in the game whose Anticipation draws a SECOND SealRing,
-- counter-turning against the Cast seal's own rotation, and that is a gameplay feature rather than a
-- flourish: it is the only warning anyone gets that a guard-breaker is coming, and it buys them two tenths
-- of a second. No other glyph may borrow it.
--
-- The mark on the body is TWO crossed strokes, not one stroke and a puff of smoke. What was there was a
-- 180-degree SmokeSoft burst, which is the stock impact puff AND redundant: ApplyDamage emits a Hit packet
-- for this same body and the Hit timeline already puts smoke off the burn there. The layer is better spent
-- crossing the first stroke with a second, counter-turning, slightly nearer the camera so the two decals
-- are not coplanar -- because two crossed strokes written on a body is a colophon, and a smoke puff is
-- anybody's.
--
-- No Flash layer, for the reason Watermark has none: every link takes damage, every one of those emits a
-- Hit packet with its own PageFlash, and three of those composed with a fourth of mine would pin
-- saturation at the clamp LightingConfig warns about. The screen work is already correctly placed.
--
-- The chain is COLOPHON_LINK below. Params.ChainCount is 3 and the server's loop counts the first hitscan
-- target as points[1], so three bodies are struck and the chain makes TWO jumps: two plays of the link,
-- not three. This timeline is the ceremony and the first stroke, and it plays once -- replaying the whole
-- thing per link would draw the doubled seal three times, which would turn the roster's only guard-break
-- warning into noise.
--
-- Renderer contract (VfxLibrary.Colophon, D-127): Origin is the muzzle (packet Origin advanced by
-- Params.SpawnOffset), Direction toward Targets[1], Reach the distance from the muzzle to it -- not
-- Params.Range, which is the distance to the WALL: geometryStop re-casts past every character -- or
-- Params.Range when the cast struck nobody. The stroke travels exactly that (TravelFrom). This contract was
-- written here and never played: the stroke was a fixed sixty studs from the caster, 0.38 s after the
-- chain had struck. It is drawn on the packet now, and the doubled seal of the ceremony is the Cast seal
-- every glyph shares.
local COLOPHON: Timeline = {
	Intent = "The last page is signed: a stroke ruled to the first body, a doubled mark struck on it",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				-- The nib at the hand, two frames: the server's whole chain has already struck.
				{
					Kind = "Emitter",
					Emit = "Aim",
					Anchor = "Hand",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Burst = 18,
					Speed = { 16, 30 },
					Lifetime = { 0.08, 0.16 },
					Spread = 25,
					Squash = 0.4,
					Size = 0.6,
					EndSize = 0.05,
				},
				{ Kind = "Shake", At = 0, For = 0.07, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.01,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
			},
		},
		{
			Name = "Travel",
			-- As long as the stroke takes to arrive: its ribbons outlive the phase, the mark it strikes must not wait.
			Duration = 0.06,
			Layers = {
				-- The signature, ruled in six hundredths from the muzzle to the first body it struck, or to the wall
				-- (TravelFrom Reach, D-127): the Strike's line at an ultimate's weight.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.06,
					Ease = "Sine",
					EaseDirection = "Out",
					TravelFrom = "Reach",
					Travel = 1,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				{
					Kind = "Trail",
					Ride = true,
					At = 0,
					For = 0.34,
					Size = 2.2,
					EndSize = 0.8,
					Ribbon = 0.34,
					Transparency = 0.05,
					EndTransparency = 0.8,
				},
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 0.34,
					Size = 0.9,
					EndSize = 0.4,
					Ribbon = 0.34,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Trail",
					Role = "Core",
					Glow = 1,
					Brightness = 1.6,
					Ride = true,
					At = 0,
					For = 0.34,
					Size = 0.45,
					EndSize = 0.1,
					Ribbon = 0.24,
					Transparency = 0,
					EndTransparency = 0.7,
				},
				{
					Kind = "Light",
					Brightness = 3,
					Ride = true,
					At = 0,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 14,
				},
				{
					Kind = "Emitter",
					Ride = true,
					At = 0,
					For = 0.06,
					Texture = "SparkStreak",
					Rate = 300,
					Speed = { 3, 8 },
					Lifetime = { 0.25, 0.45 },
					Spread = 70,
					Drag = 2,
					Driven = true,
					Squash = 0.4,
					Size = 0.55,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.3,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact", Duck = 0.5 },
				{ Kind = "Shake", At = 0, For = 0.14, Profile = "Heavy" },
				-- The mark struck on the first body: two crossed strokes, ink and gold, a hot point that bursts,
				-- a ring face-on to whoever looks and a star of sparks -- the strongest frame of the Orpiment school.
				{
					Kind = "Sprite",
					Face = "Camera",
					Role = "Ink",
					At = 0,
					For = 0.5,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0, 1 },
					Span = 1.69,
					OffsetFrom = "Reach",
					Size = 1.3,
					EndSize = 6.5,
					Roll = 35,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.5,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0, 1 },
					Span = 1.69,
					OffsetFrom = "Reach",
					Size = 1.3,
					EndSize = 6.5,
					Roll = -35,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.6,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.14 },
					Spread = 0,
					Size = 0.8,
					EndSize = 6,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Size = 1,
					EndSize = 14,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 28,
					Speed = { 26, 48 },
					Lifetime = { 0.14, 0.28 },
					Spread = 180,
					Drag = 3,
					Squash = 0.5,
					Size = 0.7,
					EndSize = 0,
				},
				{
					Kind = "Light",
					Brightness = 3,
					At = 0,
					For = 0.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Range = 16,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.8,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.7,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Offset = { 0, 0.04, 1 },
					OffsetFrom = "Reach",
					Size = 8.5,
					EndSize = 10.5,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				-- The stroke left on the page, the length the server ruled, drying.
				{
					Kind = "Mark",
					At = 0,
					For = 1.6,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0.08, 0.5 },
					Span = 1,
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Size = 1.4,
					EndSize = 1.8,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 1.2,
					Texture = "DustMote",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Rate = 10,
					Speed = { 0.5, 2 },
					Lifetime = { 0.7, 1.2 },
					Spread = 150,
					Size = 0.42,
					EndSize = 0,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- One jump of the Colophon's chain, played once per entry in the packet's Targets after the first. With
-- Params.ChainCount = 3 and the first hitscan target counted as points[1], that is TWO plays, not three.
--
-- It exists because a timeline has one Origin and the server picks the link positions at runtime
-- (GlyphEffects.nextLink, nearest untouched model within ChainRadius), so the only way the drawn path can
-- be the path that was actually resolved is one play per segment. Replaying COLOPHON itself would draw the
-- doubled seal once per link and spend two tenths of a second gathering at each, and the server resolves
-- the entire chain in a single frame with no waits: the arcs have to be fast or the second victim is seen
-- flinching before the ink reaches him.
--
-- So the ceremony is gone and what is left is the stroke, at the same proportions, half the weight: the
-- arc collects on the body it is leaving for fifty milliseconds, rules a stroke to the next, writes the
-- same held mark on him, and leaves its segment on the floor. Same texture, same taper, same easing family
-- as the first stroke, which is what makes three plays read as one gesture that did not lift.
--
-- Renderer contract (VfxLibrary.Colophon, D-127): one play per JUMP, Origin the body it leaves, Direction
-- toward the next, Reach the jump itself (TravelFrom). Not staggered: the server strikes the whole chain
-- in one frame, and a stagger would draw the last body hit after it had flinched.
local COLOPHON_LINK: Timeline = {
	Intent = "The stroke jumps from one struck body to the next and signs him too",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.02,
			Layers = {
				{
					Kind = "Emitter",
					Emit = "Aim",
					At = 0,
					For = 0.02,
					Texture = "SparkStreak",
					Burst = 12,
					Speed = { 12, 22 },
					Lifetime = { 0.08, 0.14 },
					Spread = 30,
					Squash = 0.4,
					Size = 0.5,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Travel",
			-- As long as the stroke takes to arrive: its ribbons outlive the phase, the mark it strikes must not wait.
			Duration = 0.05,
			Layers = {
				-- From the body it is leaving to the next, exactly the jump the server made (TravelFrom Reach,
				-- D-127), in five hundredths: the server chained in one frame.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.05,
					Ease = "Sine",
					EaseDirection = "Out",
					TravelFrom = "Reach",
					Travel = 1,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", Ride = true, At = 0, For = 0.05, Voice = "Tail" },
				{
					Kind = "Trail",
					Ride = true,
					At = 0,
					For = 0.34,
					Size = 1.32,
					EndSize = 0.48,
					Ribbon = 0.34,
					Transparency = 0.05,
					EndTransparency = 0.8,
				},
				{
					Kind = "Trail",
					Role = "Ink",
					Ride = true,
					At = 0,
					For = 0.34,
					Size = 0.54,
					EndSize = 0.24,
					Ribbon = 0.34,
					Transparency = 0,
					EndTransparency = 0.5,
				},
				{
					Kind = "Trail",
					Role = "Core",
					Glow = 1,
					Brightness = 1.6,
					Ride = true,
					At = 0,
					For = 0.34,
					Size = 0.27,
					EndSize = 0.06,
					Ribbon = 0.24,
					Transparency = 0,
					EndTransparency = 0.7,
				},
				{
					Kind = "Light",
					Brightness = 2,
					Ride = true,
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 10,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.2,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				{ Kind = "Shake", At = 0, For = 0.06, Profile = "Melee" },
				-- Signed too: the same crossed mark, smaller, a hot point and sparks.
				{
					Kind = "Sprite",
					Face = "Camera",
					Role = "Ink",
					At = 0,
					For = 0.4,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0, 1 },
					Span = 1.04,
					OffsetFrom = "Reach",
					Size = 0.8,
					EndSize = 4,
					Roll = 35,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					Face = "Camera",
					At = 0.03,
					For = 0.4,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0, 1 },
					Span = 1.04,
					OffsetFrom = "Reach",
					Size = 0.8,
					EndSize = 4,
					Roll = -35,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					Role = "Core",
					Glow = 1,
					Brightness = 1.5,
					At = 0,
					For = 0.04,
					Texture = "DustMote",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 1,
					Speed = { 0, 0 },
					Lifetime = { 0.1, 0.14 },
					Spread = 0,
					Size = 0.8,
					EndSize = 3.5,
					Pop = 0.3,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, 0, 1 },
					OffsetFrom = "Reach",
					Burst = 16,
					Speed = { 18, 34 },
					Lifetime = { 0.12, 0.24 },
					Spread = 180,
					Drag = 3,
					Squash = 0.5,
					Size = 0.55,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0.04, 1 },
					OffsetFrom = "Reach",
					Size = 5,
					EndSize = 6.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.4,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0.08, 0.5 },
					Span = 1,
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Size = 0.9,
					EndSize = 1.2,
					Transparency = 0.25,
					EndTransparency = 1,
				},
			},
		},
	},
}

----------------------------------------------------------------
-- L'Effacement (docs/GAME_DESIGN.md §7)
----------------------------------------------------------------

-- The World Boss is the only thing in Vellum that hits six players at once, and its four attacks are the
-- only effects in the game whose visual is load-bearing: the paint on the floor IS the rule. So these are
-- the only timelines that measure themselves against the packet instead of against Scale -- the radius
-- comes from WorldBossConfig, changes per attack, and tests/BossTelegraph.spec.luau proves the paint
-- covers the floor the server will damage -- and the only ones whose wind-up lasts exactly as long as the
-- server is really waiting.
--
-- They draw with the four Telegraph textures and nothing else on the floor they warn about, because those
-- are the only textures whose ink reaches the edge of the plane it is drawn on (AssetIds.Ink). The blot's
-- ink stops at six tenths of its plane; a warning drawn with it would warn about six tenths of the floor.
--
-- The four share one vocabulary, because a boss you can learn is a boss whose language repeats:
--   the floor lights first, then ink floods the ground it is about to erase, readable from its first
--     frame and filling faster as the hit approaches (Quad in), so the last third reads as "now";
--   a ring sweeps at a steady pace toward the heart of the danger, which is the same sentence as "away
--     from safety": inward for a Circle, back to the boss for a Cone, outward for a Ring;
--   the page's own grain is pulled off the floor INTO the point of the hit -- the Erasure takes in,
--     where every glyph in the game throws out, and sparks belong to Cinnabar and Orpiment, not to it;
--   and what is left is not a scorch mark. It is bare paper, in the colour of paper, laid by BOSS_SCOUR
--     as a second play once the damage is over: the one thing only this boss leaves behind.

local BOSS_SLAM: Timeline = {
	Intent = "The floor lights, ink floods it to the exact radius, a ring closes on the centre, and the page tears",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 1.2,
			Window = true,
			Layers = {
				-- The warning, stretched to the window: a shorter warning is the same sound, higher and faster.
				{ Kind = "Sound", At = 0, For = 1, Sfx = "BossWarn", Fit = true },
				-- The light is the earliest legible thing at forty studs, so it goes first and spans the
				-- whole window.
				{
					Kind = "Light",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, 3, 0 },
					Range = 26,
					Brightness = 0.2,
					EndBrightness = 2.4,
				},
				-- The damage area, at the damage size, for the whole warning, and readable from the first
				-- frame: a warning three quarters transparent for half its window is a warning about the
				-- last half.
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.96,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphDisc",
					Size = 2,
					SizeFrom = "Radius",
					Transparency = 0.72,
					EndTransparency = 0.2,
				},
				-- The clock. A steady sweep (Sine in-out is the nearest legal thing to one) rather than a
				-- curve that has barely moved at the halfway mark: its whole job is to be read mid-window.
				{
					Kind = "Mark",
					At = 0.12,
					For = 0.88,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "TelegraphRing",
					Size = 2,
					EndSize = 0.12,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Radius",
					Transparency = 0.4,
					EndTransparency = 0.06,
				},
				-- The page's grain, drawn in. Negative speed converges from a shell the runtime sizes to
				-- the particle's own flight, so this really arrives at the point instead of leaving it.
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0, 0.5, 0 },
					Rate = 18,
					Speed = { -16, -8 },
					Lifetime = { 0.7, 1.1 },
					Spread = 40,
					Drag = 1.2,
					Size = 0.5,
					EndSize = 0.05,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				-- The last beat of the wind-up, which is the one that makes a player move.
				{
					Kind = "Emitter",
					At = 0.86,
					For = 0.14,
					Texture = "DustMote",
					Offset = { 0, 0.5, 0 },
					Burst = 30,
					Speed = { -30, -18 },
					Lifetime = { 0.12, 0.2 },
					Spread = 30,
					Size = 0.6,
					EndSize = 0.05,
				},
				{ Kind = "Shake", At = 0.9, For = 0.1, Profile = "Light" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.4,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossImpact", Duck = 0.8 },
				-- The flood is not switched off on the frame the hit lands: it burns off the page, which is
				-- the hand-off rule 3 asks for.
				{
					Kind = "Mark",
					At = 0,
					For = 0.4,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "TelegraphDisc",
					Size = 2,
					SizeFrom = "Radius",
					Transparency = 0.2,
					EndTransparency = 1,
				},
				-- The wave runs out to exactly the radius that hurt, and stops there.
				{
					Kind = "Mark",
					At = 0,
					For = 0.36,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "TelegraphRing",
					Size = 0.25,
					EndSize = 2,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Radius",
					Transparency = 0.06,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.02,
					For = 0.38,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 1.7,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Radius",
					Transparency = 1,
					EndTransparency = 0.28,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "SmokeSoft",
					Offset = { 0, 0.5, 0 },
					Burst = 30,
					Speed = { 14, 30 },
					Lifetime = { 0.7, 1.2 },
					Spread = 75,
					Drag = 2.2,
					Size = 3,
					EndSize = 7,
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.35,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 3, 0 },
					Range = 34,
					Brightness = 3.2,
				},
				{ Kind = "Flash", At = 0, For = 0.05, Profile = "PageFlash" },
				{ Kind = "Shake", At = 0, For = 0.1, Profile = "Heavy" },
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				-- The tear, fading. The bare page itself is BOSS_SCOUR, played in the paper's colour.
				{
					Kind = "Mark",
					At = 0,
					For = 1.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 1.7,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Radius",
					Transparency = 0.28,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.1,
					Texture = "DustMote",
					Offset = { 0, 0.8, 0 },
					Rate = 10,
					Speed = { 0.5, 2.5 },
					Lifetime = { 0.6, 1 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.4,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Fury is the phase-three attack: thirty studs, forty-five damage, two full seconds of warning. It is the
-- same language spoken louder, and it has to be told from the Slam in one frame, mid-fight, before a
-- player commits: both are discs, and thirty studs against twenty-two is not a difference a bare floor
-- shows. So it has two clocks from its first frame, concentric and closing at different rates -- a
-- silhouette no other attack has -- and two waves on the landing, a front and a body, so the hit has
-- weight rather than only speed.
local BOSS_FURY: Timeline = {
	Intent = "The same flood with two clocks inside it from the first frame: the attack that ends a careless player",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 2,
			Window = true,
			Layers = {
				-- The warning, stretched to the window: a shorter warning is the same sound, higher and faster.
				{ Kind = "Sound", At = 0, For = 1, Sfx = "BossWarn", Fit = true },
				{
					Kind = "Light",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, 3, 0 },
					Range = 34,
					Brightness = 0.2,
					EndBrightness = 3.4,
				},
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.96,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphDisc",
					Size = 2,
					SizeFrom = "Radius",
					Transparency = 0.72,
					EndTransparency = 0.16,
				},
				{
					Kind = "Mark",
					At = 0.12,
					For = 0.88,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "TelegraphRing",
					Size = 2,
					EndSize = 0.12,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Radius",
					Transparency = 0.36,
					EndTransparency = 0.05,
				},
				-- The second clock: inside the first, turning, and closing on a harder curve, so the two
				-- separate as the window runs and the inner one arrives last.
				{
					Kind = "Mark",
					At = 0.12,
					For = 0.88,
					Ease = "Quart",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 1.5,
					EndSize = 0.2,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Radius",
					Spin = 2.2,
					Transparency = 0.45,
					EndTransparency = 0.05,
				},
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0, 0.5, 0 },
					Rate = 26,
					Speed = { -20, -10 },
					Lifetime = { 0.8, 1.2 },
					Spread = 40,
					Drag = 1.2,
					Size = 0.6,
					EndSize = 0.05,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.82,
					For = 0.18,
					Texture = "DustMote",
					Offset = { 0, 0.5, 0 },
					Burst = 44,
					Speed = { -36, -20 },
					Lifetime = { 0.14, 0.24 },
					Spread = 30,
					Size = 0.7,
					EndSize = 0.05,
				},
				{ Kind = "Shake", At = 0.62, For = 0.2, Profile = "Light" },
				{ Kind = "Shake", At = 0.9, For = 0.1, Profile = "Melee" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.5,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossImpact", Duck = 0.8 },
				{
					Kind = "Mark",
					At = 0,
					For = 0.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "TelegraphDisc",
					Size = 2,
					SizeFrom = "Radius",
					Transparency = 0.16,
					EndTransparency = 1,
				},
				-- The front, fast and thin, to the exact radius.
				{
					Kind = "Mark",
					At = 0,
					For = 0.3,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "TelegraphRing",
					Size = 0.25,
					EndSize = 2,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Radius",
					Transparency = 0.04,
					EndTransparency = 1,
				},
				-- The body behind it, slower and past the front, which is what gives the hit weight rather
				-- than speed. Ink, not a warning, so the blot is the right texture here.
				{
					Kind = "Mark",
					At = 0.06,
					For = 0.44,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 0.6,
					EndSize = 2.4,
					Offset = { 0, 0.06, 0 },
					SizeFrom = "Radius",
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.02,
					For = 0.48,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 1.8,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Radius",
					Transparency = 1,
					EndTransparency = 0.2,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Texture = "SmokeSoft",
					Offset = { 0, 0.5, 0 },
					Burst = 38,
					Speed = { 18, 40 },
					Lifetime = { 0.8, 1.4 },
					Spread = 80,
					Drag = 2.4,
					Size = 4,
					EndSize = 9,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.45,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 3, 0 },
					Range = 44,
					Brightness = 4.4,
				},
				{ Kind = "Flash", At = 0, For = 0.05, Profile = "PageFlash" },
				{ Kind = "Shake", At = 0, For = 0.12, Profile = "Heavy" },
			},
		},
		{
			Name = "Residue",
			Duration = 2,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 1.8,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Radius",
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.4,
					Texture = "DustMote",
					Offset = { 0, 1, 0 },
					Rate = 12,
					Speed = { 0.5, 3 },
					Lifetime = { 0.7, 1.2 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.45,
					EndSize = 0,
					Transparency = 0.45,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Sweep is the only boss attack that is not a disc, and the wedge it opens is the reason the format
-- learned Span. The server's shape (WorldBossMode.isInShape) is a triangle that opens to Radius of
-- half-width by the end of Range and never closes below the boss's own body, so the warning is five
-- full-bleed bars laid end to end along the reach, each as wide as the wedge is by the time it leaves
-- that bar. Every one of them is wider than the damage rather than narrower -- the last thing a warning
-- may do is tell somebody they are outside it -- and tests/BossTelegraph.spec.luau samples the whole
-- length against the numbers WorldBossConfig actually ships, and against the bar's own ink.
--
-- They are painted outward with a stagger, all finishing together, so the direction is readable before
-- the shape is finished: the stroke leaves the boss and arrives at its own end as the hit lands.
local BOSS_SWEEP: Timeline = {
	Intent = "A bar of ink painted outward from the boss, arriving at its far end as the blow lands",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 1,
			Window = true,
			Layers = {
				-- The warning, stretched to the window: a shorter warning is the same sound, higher and faster.
				{ Kind = "Sound", At = 0, For = 1, Sfx = "BossWarn", Fit = true },
				{
					Kind = "Light",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, 3, 18 },
					Range = 40,
					Brightness = 0.2,
					EndBrightness = 2.2,
				},
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.96,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphBar",
					Size = 0.62,
					Span = 0.2,
					Offset = { 0, 0, 0.1 },
					SizeFrom = "Radius",
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Transparency = 0.72,
					EndTransparency = 0.2,
				},
				{
					Kind = "Mark",
					At = 0.09,
					For = 0.91,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphBar",
					Size = 0.86,
					Span = 0.2,
					Offset = { 0, 0, 0.3 },
					SizeFrom = "Radius",
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Transparency = 0.72,
					EndTransparency = 0.2,
				},
				{
					Kind = "Mark",
					At = 0.14,
					For = 0.86,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphBar",
					Size = 1.26,
					Span = 0.2,
					Offset = { 0, 0, 0.5 },
					SizeFrom = "Radius",
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Transparency = 0.72,
					EndTransparency = 0.2,
				},
				{
					Kind = "Mark",
					At = 0.19,
					For = 0.81,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphBar",
					Size = 1.66,
					Span = 0.2,
					Offset = { 0, 0, 0.7 },
					SizeFrom = "Radius",
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Transparency = 0.72,
					EndTransparency = 0.2,
				},
				{
					Kind = "Mark",
					At = 0.24,
					For = 0.76,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphBar",
					Size = 2.06,
					Span = 0.2,
					Offset = { 0, 0, 0.9 },
					SizeFrom = "Radius",
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Transparency = 0.72,
					EndTransparency = 0.2,
				},
				-- The clock, at the apex: it closes on the boss, which is where the stroke is coming from
				-- and therefore the one direction that is not a way out.
				{
					Kind = "Mark",
					At = 0.12,
					For = 0.88,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "TelegraphRing",
					Size = 1.4,
					EndSize = 0.12,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Radius",
					Transparency = 0.4,
					EndTransparency = 0.06,
				},
				-- The grain of the stroke, gathered back into the boss.
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0, 0.5, 0 },
					Rate = 18,
					Speed = { -14, -7 },
					Lifetime = { 0.7, 1.1 },
					Spread = 40,
					Drag = 1.2,
					Size = 0.5,
					EndSize = 0.05,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 0.9, For = 0.1, Profile = "Light" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.4,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossImpact", Duck = 0.8 },
				-- The blow itself is one stroke down the whole length, narrower than the widest part of
				-- the wedge: the warning was the shape, this is the weight. The bars end at 0.2 and this
				-- opens at 0.06, so nothing on the floor is switched off.
				{
					Kind = "Mark",
					At = 0,
					For = 0.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 1.4,
					Span = 1,
					Offset = { 0, 0.1, 0.5 },
					SizeFrom = "Radius",
					SpanFrom = "Reach",
					OffsetFrom = "Reach",
					Transparency = 0.06,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.02,
					For = 0.38,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 1.3,
					Offset = { 0, 0.16, 0.5 },
					SizeFrom = "Radius",
					OffsetFrom = "Reach",
					Transparency = 1,
					EndTransparency = 0.3,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "SmokeSoft",
					Offset = { 0, 0.6, 16 },
					Burst = 26,
					Speed = { 16, 34 },
					Lifetime = { 0.6, 1.1 },
					Spread = 65,
					Drag = 2.2,
					Size = 3,
					EndSize = 7,
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.4,
					Texture = "DustMote",
					Offset = { 0, 0.6, 24 },
					Burst = 30,
					Speed = { 26, 52 },
					Lifetime = { 0.3, 0.6 },
					Spread = 35,
					Drag = 2,
					Size = 0.8,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.35,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 3, 18 },
					Range = 40,
					Brightness = 3,
				},
				{ Kind = "Flash", At = 0, For = 0.05, Profile = "PageFlash" },
				{ Kind = "Shake", At = 0, For = 0.1, Profile = "Heavy" },
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 1.3,
					Offset = { 0, 0.16, 0.5 },
					SizeFrom = "Radius",
					OffsetFrom = "Reach",
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.1,
					Texture = "DustMote",
					Offset = { 0, 0.8, 18 },
					Rate = 9,
					Speed = { 0.5, 2.5 },
					Lifetime = { 0.6, 1 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.4,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Eruption is the one attack whose safe place is inside it, so its clock runs the other way: the ring
-- leaves the centre and travels out to the far edge, which is the same sentence as "inward is the way
-- out". The bare centre is a second play (BOSS_ERUPTION_SAFE) because a timeline carries one colour and
-- the safe disc is the one thing on this floor that must not be the colour of danger.
--
-- Its matter sits on the ring it is about to lift, measured against the reach so a Range changed in
-- WorldBossConfig moves it with the paint: three risers, because two read as a pair and three as a ring.
local BOSS_ERUPTION: Timeline = {
	Intent = "Ink floods everything but the middle, the ring runs outward, and the page erupts where it was inked",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 1.6,
			Window = true,
			Layers = {
				-- The warning, stretched to the window: a shorter warning is the same sound, higher and faster.
				{ Kind = "Sound", At = 0, For = 1, Sfx = "BossWarn", Fit = true },
				{
					Kind = "Light",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, 3, 0 },
					Range = 46,
					Brightness = 0.2,
					EndBrightness = 2.6,
				},
				-- The outer reach, which is where the damage stops.
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.96,
					Ease = "Quad",
					EaseDirection = "In",
					Texture = "TelegraphDisc",
					Size = 2,
					SizeFrom = "Reach",
					Transparency = 0.72,
					EndTransparency = 0.22,
				},
				-- The clock, outward. It crosses the safe boundary on its way, which is exactly what it is
				-- saying: this is coming through here, and it is going that way.
				{
					Kind = "Mark",
					At = 0.12,
					For = 0.88,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "TelegraphRing",
					Size = 0.12,
					EndSize = 2,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Reach",
					Transparency = 0.4,
					EndTransparency = 0.06,
				},
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0, 0.01, 0.67 },
					OffsetFrom = "Reach",
					Rate = 14,
					Speed = { 4, 11 },
					Lifetime = { 0.5, 0.9 },
					Spread = 50,
					Drag = 1.6,
					Size = 0.55,
					EndSize = 0,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0.58, 0.01, -0.335 },
					OffsetFrom = "Reach",
					Rate = 14,
					Speed = { 4, 11 },
					Lifetime = { 0.5, 0.9 },
					Spread = 50,
					Drag = 1.6,
					Size = 0.55,
					EndSize = 0,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { -0.58, 0.01, -0.335 },
					OffsetFrom = "Reach",
					Rate = 14,
					Speed = { 4, 11 },
					Lifetime = { 0.5, 0.9 },
					Spread = 50,
					Drag = 1.6,
					Size = 0.55,
					EndSize = 0,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{ Kind = "Shake", At = 0.88, For = 0.12, Profile = "Light" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.5,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossImpact", Duck = 0.8 },
				{
					Kind = "Mark",
					At = 0,
					For = 0.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "TelegraphDisc",
					Size = 2,
					SizeFrom = "Reach",
					Transparency = 0.22,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 0.44,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "TelegraphRing",
					Size = 0.4,
					EndSize = 2,
					Offset = { 0, 0.1, 0 },
					SizeFrom = "Reach",
					Transparency = 0.06,
					EndTransparency = 1,
				},
				-- The page splitting from the middle outward. The safe disc is drawn above this one, so the
				-- centre of the crack is covered and the middle still reads as intact.
				{
					Kind = "Mark",
					At = 0.02,
					For = 0.48,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 1.9,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Reach",
					Transparency = 1,
					EndTransparency = 0.26,
				},
				-- Three columns of ink smoke off the ring, where the risers stood.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "SmokeSoft",
					Offset = { 0, 0.01, 0.67 },
					OffsetFrom = "Reach",
					Burst = 22,
					Speed = { 30, 55 },
					Lifetime = { 0.6, 1.1 },
					Spread = 18,
					Drag = 1.4,
					Size = 2,
					EndSize = 5,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "SmokeSoft",
					Offset = { 0.58, 0.01, -0.335 },
					OffsetFrom = "Reach",
					Burst = 22,
					Speed = { 30, 55 },
					Lifetime = { 0.6, 1.1 },
					Spread = 18,
					Drag = 1.4,
					Size = 2,
					EndSize = 5,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "SmokeSoft",
					Offset = { -0.58, 0.01, -0.335 },
					OffsetFrom = "Reach",
					Burst = 22,
					Speed = { 30, 55 },
					Lifetime = { 0.6, 1.1 },
					Spread = 18,
					Drag = 1.4,
					Size = 2,
					EndSize = 5,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.45,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 3, 0 },
					Range = 52,
					Brightness = 3.8,
				},
				{ Kind = "Flash", At = 0, For = 0.05, Profile = "PageFlash" },
				{ Kind = "Shake", At = 0, For = 0.12, Profile = "Heavy" },
			},
		},
		{
			Name = "Residue",
			Duration = 1.8,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.8,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 1.9,
					Offset = { 0, 0.16, 0 },
					SizeFrom = "Reach",
					Transparency = 0.26,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.2,
					Texture = "DustMote",
					Offset = { 0, 1, 0 },
					Rate = 12,
					Speed = { 0.5, 3 },
					Lifetime = { 0.7, 1.2 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.45,
					EndSize = 0,
					Transparency = 0.45,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- The safe middle of an Eruption, played alongside it in the one colour on this floor that does not mean
-- danger. It is a separate play rather than a layer because a timeline is tinted by whoever plays it, and
-- that rule is what keeps a glyph from ever showing two pigments at once; the World Boss is not a reason
-- to break it. It takes the same window, so the bare page fills and the line around it holds for exactly
-- as long as there is still time to get inside.
--
-- The page is a disc (TelegraphPage), not the world's grain on a square plate: a square of safety has
-- corners six studs into the damage, and that is the one lie on this floor that kills. It outlives the
-- erasure drawn around it, because the page keeps what was not erased.
local BOSS_ERUPTION_SAFE: Timeline = {
	Intent = "The one disc of bare page an Eruption does not touch, and the line around it",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 1.6,
			Window = true,
			Layers = {
				-- The boundary, at exactly the radius the server reads as safe, held rather than animated:
				-- it is the one line on this floor whose whole job is to not move.
				{
					Kind = "Mark",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "TelegraphRing",
					Size = 2,
					Offset = { 0, 0.26, 0 },
					SizeFrom = "Radius",
					Transparency = 0.3,
					EndTransparency = 0.1,
				},
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.96,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "TelegraphPage",
					Size = 2,
					Offset = { 0, 0.22, 0 },
					SizeFrom = "Radius",
					Transparency = 0.55,
					EndTransparency = 0.22,
				},
				{
					Kind = "Emitter",
					At = 0.1,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0, 0.8, 0 },
					Rate = 12,
					Speed = { 2, 5 },
					Lifetime = { 0.6, 1 },
					Spread = 120,
					Drag = 1.4,
					Size = 0.5,
					EndSize = 0,
					Transparency = 0.45,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.8,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.8,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "TelegraphPage",
					Size = 2,
					Offset = { 0, 0.22, 0 },
					SizeFrom = "Radius",
					Transparency = 0.22,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- What the Erasure leaves behind, laid once the damage is over and in the colour of the page itself --
-- which the attack's own play cannot do, since it carries the colour of danger. A second play, the way
-- the safe disc is one, scheduled by the renderer on the attack's own Residue phase (phaseAt). The disc
-- is measured against whatever the renderer passes as Radius: the attack's radius for a Circle, its reach
-- for a Ring, and a blot at mid-stroke for the Cone.
local BOSS_SCOUR: Timeline = {
	Intent = "Bare page where the ink was, in the colour of paper, fading as the world writes itself back",
	Phases = {
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				-- The halo of the scrubbing goes first, wider than the wound and gone in half a second.
				{
					Kind = "Mark",
					At = 0,
					For = 0.55,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "TelegraphPage",
					Size = 2.3,
					Offset = { 0, 0.04, 0 },
					SizeFrom = "Radius",
					Transparency = 0.78,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "TelegraphPage",
					Size = 1.9,
					Offset = { 0, 0.06, 0 },
					SizeFrom = "Radius",
					Transparency = 0.3,
					EndTransparency = 1,
				},
				-- The page glows faintly where it was scrubbed, and stops.
				{
					Kind = "Light",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, 3, 0 },
					Range = 28,
					Brightness = 0.9,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.1,
					Texture = "DustMote",
					Offset = { 0, 0.8, 0 },
					Rate = 10,
					Speed = { 0.5, 2.5 },
					Lifetime = { 0.6, 1 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.4,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- The arrival. Nothing is being warned about here -- the boss damages nobody by landing -- so this one
-- measures nothing and is authored in studs against the body WorldBossConfig ships; the renderer scales
-- it by the body's own height, so a bigger boss lands bigger.
--
-- It is the only effect in Vellum that fires the Erasure pulse (LightingConfig), which is nearly five
-- seconds of the screen being drained rather than flashed, and it is the only one that should: the pulse
-- was written for this arrival and nothing else in the game is allowed to cost that much attention.
--
-- The wind-up runs backwards on purpose. The page's grain is pulled INTO the point the boss will land on
-- from fourteen studs out, the seal is drawn in place rather than closing -- a closing ring is the
-- attacks' clock, and the first thing six players see must not teach them that the clock can be
-- harmless -- and the floor goes dark before it goes bright.
local BOSS_SPAWN: Timeline = {
	Intent = "The page is drained into one point, and what lands there has taken the colour of the paper",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.9,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossArrival", Duck = 2.6 },
				{
					Kind = "Mark",
					At = 0,
					For = 0.9,
					Ease = "Quad",
					EaseDirection = "Out",
					Texture = "TelegraphDisc",
					Size = 4,
					EndSize = 26,
					Transparency = 0.85,
					EndTransparency = 0.3,
				},
				-- The seal, drawn in place: it turns and darkens and does not move.
				{
					Kind = "Mark",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 30,
					Offset = { 0, 0.1, 0 },
					Spin = 1.6,
					Transparency = 0.95,
					EndTransparency = 0.15,
				},
				-- Inward, from fourteen studs. This is the whole idea of the character.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.9,
					Texture = "DustMote",
					Offset = { 0, 7, 0 },
					Rate = 34,
					Speed = { -28, -14 },
					Lifetime = { 0.5, 0.8 },
					Spread = 20,
					Drag = 1.2,
					Size = 0.8,
					EndSize = 0.05,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.9,
					Ease = "Quart",
					EaseDirection = "In",
					Offset = { 0, 4, 0 },
					Range = 30,
					Brightness = 0.05,
					EndBrightness = 3,
				},
				{ Kind = "Shake", At = 0.6, For = 0.3, Profile = "Light" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.6,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 0.55,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "TelegraphRing",
					Size = 4,
					EndSize = 60,
					Offset = { 0, 0.1, 0 },
					Transparency = 0.05,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.02,
					For = 0.58,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 40,
					Offset = { 0, 0.16, 0 },
					Transparency = 1,
					EndTransparency = 0.26,
				},
				-- The arrival is allowed the one borrowed thing in the boss's whole vocabulary: the bloom
				-- every detonation in the game opens with, because this is the one time it is louder than
				-- any of them.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "ExplosionBloom",
					Offset = { 0, 7, 0 },
					Burst = 10,
					Speed = { 3, 9 },
					Lifetime = { 0.5, 0.8 },
					Spread = 180,
					Size = 14,
					EndSize = 22,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Texture = "SmokeSoft",
					Offset = { 0, 1, 0 },
					Burst = 34,
					Speed = { 20, 44 },
					Lifetime = { 0.9, 1.5 },
					Spread = 80,
					Drag = 2.4,
					Size = 5,
					EndSize = 12,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.45,
					Texture = "DustMote",
					Offset = { 0, 2, 0 },
					Burst = 40,
					Speed = { 30, 60 },
					Lifetime = { 0.4, 0.8 },
					Spread = 90,
					Drag = 1.8,
					Size = 1,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.55,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 6, 0 },
					Range = 60,
					Brightness = 5,
				},
				{ Kind = "Flash", At = 0, For = 0.1, Profile = "Erasure" },
				{ Kind = "Shake", At = 0, For = 0.14, Profile = "Heavy" },
			},
		},
		{
			Name = "Residue",
			Duration = 1.8,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 1.7,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "TelegraphPage",
					Size = 44,
					Offset = { 0, 0.06, 0 },
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.8,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 40,
					Offset = { 0, 0.16, 0 },
					Transparency = 0.26,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.3,
					Texture = "DustMote",
					Offset = { 0, 1.4, 0 },
					Rate = 12,
					Speed = { 0.5, 3 },
					Lifetime = { 0.8, 1.3 },
					Spread = 170,
					Drag = 1.2,
					Size = 0.5,
					EndSize = 0,
					Transparency = 0.45,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- The end of the fight, and the mirror of the arrival: what it took in comes back out, and what it wrote
-- over is given back. The collapse is Quint-in, so the seal gathers, hesitates, and then goes -- the one
-- beat in the whole fight that belongs to the players watching it rather than to the boss.
local BOSS_PHASE: Timeline = {
	Intent = "The erasure spreads: the band across its face widens, and the page around it takes the blow",
	Phases = {
		{
			-- The ink is drawn in before it is laid down: the page's grain converges on the body from a
			-- shell, the way the arrival did, but from closer and faster -- this is a spreading, not a
			-- coming.
			Name = "Anticipation",
			Duration = 0.4,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.4,
					Texture = "DustMote",
					Offset = { 0, 6, 0 },
					Rate = 60,
					Speed = { -30, -18 },
					Lifetime = { 0.25, 0.4 },
					Spread = 180,
					Drag = 1.2,
					Size = 0.7,
					EndSize = 0.05,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.4,
					Ease = "Exponential",
					EaseDirection = "In",
					Offset = { 0, 5, 0 },
					Range = 20,
					Brightness = 0.1,
					EndBrightness = 3.5,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.5,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossImpact", Duck = 0.8 },
				{ Kind = "Shake", At = 0, For = 0.16, Profile = "Heavy" },
				{ Kind = "Flash", At = 0, For = 0.14, Profile = "PageFlash" },
				-- The band's own width, thrown out over the floor as a ring.
				{
					Kind = "Mark",
					At = 0,
					For = 0.5,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "TelegraphRing",
					Size = 6,
					EndSize = 48,
					Offset = { 0, 0.1, 0 },
					Transparency = 0.08,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "InkBlot",
					Offset = { 0, 3.4, 0 },
					Burst = 28,
					Speed = { 24, 48 },
					Lifetime = { 0.4, 0.8 },
					Spread = 180,
					Drag = 2,
					Size = 1,
					EndSize = 0,
				},
			},
		},
		{
			-- What the phase took from the page stays under the body a moment: the floor, darker where
			-- the erasure stands.
			Name = "Residue",
			Duration = 2.4,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 14,
					EndSize = 16,
					Offset = { 0, 0.06, 0 },
					Transparency = 0.3,
					EndTransparency = 1,
				},
			},
		},
	},
}

local BOSS_DEFEATED: Timeline = {
	Intent = "The erasure folds into itself and gives the page back",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.6,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Sfx = "BossDefeat", Duck = 2.2 },
				{
					Kind = "Mark",
					At = 0,
					For = 0.6,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 30,
					EndSize = 2,
					Offset = { 0, 0.1, 0 },
					Spin = 4.5,
					Transparency = 0.4,
					EndTransparency = 0.06,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Texture = "DustMote",
					Offset = { 0, 7, 0 },
					Rate = 40,
					Speed = { -40, -22 },
					Lifetime = { 0.35, 0.6 },
					Spread = 20,
					Drag = 1.6,
					Size = 0.9,
					EndSize = 0.05,
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.6,
					Ease = "Exponential",
					EaseDirection = "In",
					Offset = { 0, 5, 0 },
					Range = 26,
					Brightness = 0.1,
					EndBrightness = 5,
				},
				{ Kind = "Shake", At = 0.4, For = 0.2, Profile = "Melee" },
			},
		},
		{
			Name = "Impact",
			Duration = 0.7,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 0.65,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "TelegraphRing",
					Size = 2,
					EndSize = 70,
					Offset = { 0, 0.1, 0 },
					Transparency = 0.04,
					EndTransparency = 1,
				},
				-- The ink it took, thrown back over the page.
				{
					Kind = "Mark",
					At = 0.04,
					For = 0.66,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "TelegraphDisc",
					Size = 6,
					EndSize = 46,
					Offset = { 0, 0.04, 0 },
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.7,
					Texture = "DustMote",
					Offset = { 0, 6, 0 },
					Burst = 46,
					Speed = { 36, 72 },
					Lifetime = { 0.6, 1.2 },
					Spread = 180,
					Drag = 1.6,
					Size = 1.2,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.7,
					Texture = "SmokeSoft",
					Offset = { 0, 2, 0 },
					Burst = 32,
					Speed = { 18, 40 },
					Lifetime = { 1, 1.6 },
					Spread = 90,
					Drag = 2.6,
					Size = 5,
					EndSize = 13,
					Transparency = 0.22,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.6,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 5, 0 },
					Range = 64,
					Brightness = 5.5,
				},
				{ Kind = "Flash", At = 0, For = 0.06, Profile = "PageFlash" },
				{ Kind = "Shake", At = 0, For = 0.16, Profile = "Heavy" },
			},
		},
		{
			Name = "Residue",
			Duration = 2,
			Layers = {
				-- The page comes back: the bare paper goes first and the ink returns over it, which is the
				-- opposite order of every other residue in the game. The ink arrives in one layer and
				-- leaves in a second, because a layer only ever goes one way.
				{
					Kind = "Mark",
					At = 0,
					For = 1.1,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "TelegraphPage",
					Size = 44,
					Offset = { 0, 0.06, 0 },
					Transparency = 0.24,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.3,
					For = 0.8,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 40,
					Transparency = 0.9,
					EndTransparency = 0.45,
				},
				{
					Kind = "Mark",
					At = 1.1,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 40,
					Transparency = 0.45,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1.5,
					Texture = "DustMote",
					Offset = { 0, 1.6, 0 },
					Rate = 14,
					Speed = { 0.5, 3.5 },
					Lifetime = { 0.9, 1.5 },
					Spread = 170,
					Drag = 1.1,
					Size = 0.5,
					EndSize = 0,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- The four KillEffect cosmetics (CosmeticConfig, D-109): what a killer's page does where the victim fell.
-- They are the one family of timelines that is never a pigment. A kill is not a spell, and a kill effect
-- drawn in a school's colour would put a fifth attack on screen that hurts nobody (docs/ART_BIBLE.md
-- rule 1), so VfxLibrary.KillEffect tints them in the page's inks only (CosmeticConfig.Tones). No light,
-- because a light tinted with ink lights nothing; no sound of their own yet, because the killer already
-- hears the kill confirmation and the recorded kit is the developer's (docs/DECISIONS.md D-109). And no
-- shake and no screen flash: those land on the cameras of everyone nearby, and a cosmetic somebody paid
-- for must never reach into the screen of a player still fighting (found by review).
--
-- Torn Page: the page is ripped across the body -- a tear drawn in the air, scraps thrown off it, and the
-- tear left on the floor.
local KILL_TEAR: Timeline = {
	Intent = "The page is torn across where they stood: a rip in the air, scraps flung off it, the tear on the floor",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.24,
			Layers = {
				{
					Kind = "Sprite",
					At = 0,
					For = 0.55,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 1.5,
					EndSize = 7.5,
					Transparency = 0.05,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "PaperScrap",
					Burst = 16,
					Speed = { 9, 20 },
					Lifetime = { 0.9, 1.5 },
					Spread = 75,
					Drag = 2.4,
					Size = 0.9,
					EndSize = 0.5,
					Transparency = 0,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 2.4,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "CrackWeb",
					Size = 4,
					EndSize = 7,
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.7,
					Texture = "PaperScrap",
					Rate = 7,
					Speed = { 1, 3 },
					Lifetime = { 1.2, 1.9 },
					Spread = 160,
					Drag = 1.4,
					Size = 0.55,
					EndSize = 0.35,
					Transparency = 0.2,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Redaction: three bars of ink struck through where they stood, one after the other, like a censor's
-- pen through a name -- and the last of them left on the floor.
local KILL_REDACTION: Timeline = {
	Intent = "Their name is struck out: three ink bars drawn through the air in turn, one left on the page",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.3,
			Layers = {
				{
					Kind = "Sprite",
					At = 0,
					For = 1.1,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 1,
					EndSize = 8,
					Span = 1,
					Offset = { 0, 1.3, 0 },
					Transparency = 0.02,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					At = 0.07,
					For = 1.1,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 1,
					EndSize = 8.5,
					Span = 1.1,
					Offset = { 0, 0, 0 },
					Transparency = 0.02,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					At = 0.14,
					For = 1.1,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 1,
					EndSize = 7.5,
					Span = 1,
					Offset = { 0, -1.3, 0 },
					Transparency = 0.02,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 2.6,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2.6,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 3,
					EndSize = 8,
					Span = 1.4,
					Transparency = 0.2,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Paper Petals: the page comes apart into a slow cloud of scraps that hang in the air and dry away.
local KILL_SCRAPS: Timeline = {
	Intent = "The page comes apart into scraps that rise, hang and dry away, over a stain where they fell",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.2,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.08,
					Texture = "PaperScrap",
					Burst = 24,
					Speed = { 6, 15 },
					Lifetime = { 1.6, 2.4 },
					Spread = 65,
					Drag = 1.3,
					Size = 0.8,
					EndSize = 0.55,
					Transparency = 0,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					At = 0,
					For = 0.5,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Size = 1,
					EndSize = 9,
					Transparency = 0.2,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 2.2,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 1.1,
					Texture = "PaperScrap",
					Rate = 9,
					Speed = { 1.5, 4 },
					Lifetime = { 1.4, 2.1 },
					Spread = 180,
					Drag = 0.9,
					Size = 0.6,
					EndSize = 0.4,
					Transparency = 0.15,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 2.2,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2,
					EndSize = 4.5,
					Transparency = 0.35,
					EndTransparency = 1,
				},
			},
		},
	},
}

-- Seal: a seal is struck where they stood -- a ring, a seal drawn open and spun shut -- and leaves its
-- scorch on the floor. (The id says Overexposure: it used to pulse every nearby screen white.)
local KILL_OVEREXPOSURE: Timeline = {
	Intent = "A seal is struck where they stood: a ring, a seal drawn open and spun shut, its scorch left on the page",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.3,
			Layers = {
				{
					Kind = "Sprite",
					At = 0,
					For = 0.5,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Size = 1,
					EndSize = 15,
					Transparency = 0.05,
					EndTransparency = 1,
				},
				{
					Kind = "Sprite",
					At = 0.04,
					For = 0.8,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 1,
					EndSize = 8,
					Spin = 2.4,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "DustMote",
					Burst = 30,
					Speed = { 12, 26 },
					Lifetime = { 0.4, 0.8 },
					Spread = 180,
					Drag = 3,
					Size = 0.45,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 2.6,
			Layers = {
				{
					Kind = "Mark",
					At = 0,
					For = 2.6,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 3,
					EndSize = 8,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 2.2,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2,
					EndSize = 5,
					Offset = { 0, 0.02, 0 },
					Transparency = 0.3,
					EndTransparency = 1,
				},
			},
		},
	},
}

VfxTimelineConfig.Timelines = {
	Cast = CAST,
	Tap = TAP,
	Hit = HIT,
	Dash = DASH,
	Melee = MELEE,
	Brand = BRAND,
	Explosion = EXPLOSION,
	Strike = STRIKE,
	Caret = CARET,
	Watermark = WATERMARK,
	Colophon = COLOPHON,
	ColophonLink = COLOPHON_LINK,
	Scorch = SCORCH,
	Ligature = LIGATURE,
	Blot = BLOT,
	Serif = SERIF,
	Stipple = STIPPLE,
	Gilding = GILDING,
	Rupture = RUPTURE,
	Sweep = SWEEP,
	Hairline = HAIRLINE,
	Spiral = SPIRAL,
	Pounce = POUNCE,
	Wash = WASH,
	Bleed = BLEED,
	Binding = BINDING,
	Margin = MARGIN,
	BossSpawn = BOSS_SPAWN,
	BossSlam = BOSS_SLAM,
	BossSweep = BOSS_SWEEP,
	BossEruption = BOSS_ERUPTION,
	BossEruptionSafe = BOSS_ERUPTION_SAFE,
	BossScour = BOSS_SCOUR,
	BossFury = BOSS_FURY,
	BossPhase = BOSS_PHASE,
	BossDefeated = BOSS_DEFEATED,
	KillTear = KILL_TEAR,
	KillRedaction = KILL_REDACTION,
	KillScraps = KILL_SCRAPS,
	KillOverexposure = KILL_OVEREXPOSURE,
} :: { [string]: Timeline }

-- How a thrown thing is brought down (VfxTimeline.land, D-114): the drawn carrier glides the last few studs
-- to where it burst over Seconds and holds there for Hold, while what rode it drains -- a trail runs out,
-- smoke thins, a light dims over Fade -- and what lingers after the flight is drawn there. Nothing it
-- carried vanishes. Grace is how long a thrown carrier waits at the end of its flight for its burst: the
-- throw and the burst reach a client equally late, so at full range the burst arrives just as the drawn
-- flight ends -- a frame after it in three throws out of four, measured -- and one that never comes lands
-- it where it stopped.
VfxTimelineConfig.Land = { Seconds = 0.05, Hold = 0.1, Fade = 0.1, Grace = 0.25 }

-- Phases always play in this order, whichever subset a timeline declares. The runtime reads it rather
-- than the table order, so a timeline that lists Residue before Impact still plays correctly and the test
-- that checks ordering is checking the author's intent rather than a bug it would otherwise create.
VfxTimelineConfig.PhaseOrder = { "Anticipation", "Cast", "Travel", "Impact", "Residue" } :: { PhaseName }

-- Layers live for a scheduled time, but a client whose frame rate collapses can fall behind, so every
-- layer is also force-released this long after it started. It is the backstop that makes a leak
-- impossible rather than unlikely.
VfxTimelineConfig.MaxLayerSeconds = 6

-- {min, max} seconds a particle lives when its Emitter layer declares no Lifetime.
VfxTimelineConfig.DefaultParticleLifetime = { 0.3, 0.6 }

-- How long a layer stays on screen once it starts, given `drawn`: its For, times its window factor. An
-- emitter's For is how long it EMITS; its particles then live out their Lifetime, and the layer is kept
-- until the last of them can have died. Released at For, it took every particle in the air with it: 35 of
-- the 60 burst emitters lived shorter than their particles' SHORTEST life, and the Wash cast's puffs were
-- on screen for two frames of their half second. The renderer, the cost model and duration() all ask
-- this, so what is drawn, what is budgeted and what the packet lifetime is checked against agree.
function VfxTimelineConfig.layerSeconds(layer: Layer, drawn: number): number
	if layer.Kind ~= "Emitter" and layer.Kind ~= "Debris" then
		return drawn
	end
	local lifetime = layer.Lifetime or VfxTimelineConfig.DefaultParticleLifetime
	return drawn + math.max(lifetime[2] or 0, 0)
end

-- Art bible rule 8: particle density is capped. This is the cap. It is a hard ceiling on layers alive at
-- once across every effect on screen; past it the oldest is released early, so a six-player exchange
-- degrades into fewer effects rather than into a frame rate.
VfxTimelineConfig.MaxLiveLayers = 90

-- Bounds on a phase whose length comes from the packet. The ceiling is the longest warning
-- WorldBossConfig can ask for -- tests/BossTelegraph.spec.luau holds the config to it, so a longer
-- one fails the build rather than being quietly cut short -- and the floor is there so a zero, a negative
-- or a NaN cannot turn a warning into an instant.
VfxTimelineConfig.MaxWindowSeconds = 2
VfxTimelineConfig.MinWindowSeconds = 0.1

-- The length of `phase` in seconds. `window` is whatever the packet carried and is ignored by a phase
-- that did not ask for one. Pure, and shared by the runtime, by duration() below and by the tests, so the
-- three can never disagree about the moment a warning ends.
function VfxTimelineConfig.phaseSeconds(phase: Phase, window: number?): number
	if phase.Window ~= true then
		return phase.Duration
	end
	-- window ~= window is the NaN test: it arrives from a remote packet, so it is not trusted to be a
	-- number that behaves.
	if window == nil or window ~= window or window <= 0 then
		return phase.Duration
	end
	return math.clamp(window, VfxTimelineConfig.MinWindowSeconds, VfxTimelineConfig.MaxWindowSeconds)
end

-- Seconds from the start of `id` to the moment its phase `name` begins, resolved against the window the
-- packet carried. A renderer with something to line up with a phase -- the boss's impact sound, the bare
-- page it lays once the damage is over -- reads it here instead of adding up durations of its own, so the
-- sound cannot land at a time the data no longer says. nil for an unknown id or a timeline without that
-- phase: a sound for an effect that does not exist is a hit heard from nowhere, and nil is what makes the
-- caller decide rather than schedule.
function VfxTimelineConfig.phaseAt(id: string, name: PhaseName, window: number?): number?
	local timeline: Timeline? = VfxTimelineConfig.Timelines[id]
	if timeline == nil then
		return nil
	end
	local elapsed = 0
	for _, phaseName in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == phaseName then
				if phaseName == name then
					return elapsed
				end
				elapsed += VfxTimelineConfig.phaseSeconds(phase, window)
			end
		end
	end
	return nil
end

-- Total duration of a timeline, phases end to end plus the tail of whatever layer outlives the last one.
-- Used by the runtime to size its own bookkeeping and by the test to keep a timeline inside the window
-- its packet's Trove lives for.
function VfxTimelineConfig.duration(timeline: Timeline): number
	local phaseStart = 0
	local longest = 0
	for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == name then
				-- The longest window a windowed phase can be given, because this number is what every
				-- budget check is made of: a timeline that only fits while the boss is warning for its
				-- shortest window does not fit.
				local seconds = VfxTimelineConfig.phaseSeconds(phase, VfxTimelineConfig.MaxWindowSeconds)
				local factor = if phase.Window == true then seconds else 1
				for _, layer in ipairs(phase.Layers) do
					local lives = VfxTimelineConfig.layerSeconds(layer, layer.For * factor)
					longest = math.max(longest, phaseStart + layer.At * factor + lives)
				end
				phaseStart += seconds
			end
		end
	end
	return math.max(longest, phaseStart)
end

-- Whether a timeline is drawn on the server's own time: it flies a Carrier the server steps, or fills a
-- window the server waits through. Such a play runs on VfxClock's steady clock, which an impact's hold
-- never stops (D-119): held, it would fall behind the damage it draws.
function VfxTimelineConfig.steady(timeline: Timeline): boolean
	for _, phase in ipairs(timeline.Phases) do
		if phase.Window == true then
			return true
		end
		for _, layer in ipairs(phase.Layers) do
			if layer.Kind == "Carrier" then
				return true
			end
		end
	end
	return false
end

return VfxTimelineConfig
