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
	| "Shake"
	| "Flash"
	| "Sound"

-- The four voices every pigment has (SoundConfig.Voices), in the order a glyph spends them. A Sound
-- layer names a voice and the renderer names the pigment, so twenty glyphs share five matters instead
-- of carrying eighty sound ids -- a school is a matter (docs/ART_BIBLE.md), and a player should tell
-- the school with their eyes shut.
export type Voice = "Attack" | "Body" | "Tail" | "Impact"

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
	-- Radians per second about the layer's own facing axis.
	Spin: number?,

	Transparency: number?,
	EndTransparency: number?,

	-- Emitter only.
	Rate: number?,
	Burst: number?,
	Speed: { number }?, -- {min, max}, studs per second; negative pulls inward
	Lifetime: { number }?, -- {min, max}, seconds
	Spread: number?, -- degrees
	Drag: number?,
	-- Squash below 1 stretches a particle along its travel, which is what makes a spark read as moving
	-- rather than as a dot that happens to be somewhere else next frame.
	Squash: number?,

	-- Light only.
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
-- The direction is literal about what a cast is: "Le pouvoir ne « sort » pas d'un personnage : il se
-- dessine. Une incantation trace un sceau lumineux dans l'air, trait par trait, avant de se replier et de
-- partir." So the seal is drawn by growing a ring, held for a beat, then collapsed inward to a point that
-- fires. Nothing appears and nothing moves linearly (rules 3 and 4).
local CAST: Timeline = {
	Intent = "A seal is drawn in the air, held, then folded into a point that releases",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.22,
			Layers = {
				-- The pigment's attack: heard before the seal is seen, which is what a wind-up sounds like.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Attack" },
				-- The seal itself, growing from nothing with a slight overshoot so it lands rather than
				-- arrives. Back easing is the overshoot.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.34,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 0.2,
					EndSize = 5.2,
					Offset = { 0, 0.6, 3 },
					Spin = 1.1,
					Transparency = 1,
					EndTransparency = 0.12,
				},
				-- Ink gathering into the seal. Negative speed is the whole idea: particles fly inward, so
				-- the cast reads as drawing power in rather than as already spending it.
				{
					Kind = "Emitter",
					At = 0.02,
					For = 0.2,
					Texture = "SparkStreak",
					Offset = { 0, 0.6, 3 },
					Rate = 34,
					Speed = { -9, -5 },
					Lifetime = { 0.16, 0.26 },
					Spread = 180,
					Drag = 2,
					Squash = 0.45,
					Size = 0.5,
					EndSize = 0.05,
				},
				-- A light that rises with the seal, so the caster is lit by their own pigment before the
				-- spell exists. This is what makes a cast visible from behind, which is how a player reads
				-- an opponent's intent.
				{
					Kind = "Light",
					At = 0,
					For = 0.26,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, 0.6, 2.4 },
					Range = 4,
					Brightness = 0,
					EndBrightness = 1.6,
				},
				-- Felt, not seen. Late in the wind-up, so it reads as the moment before release.
				{ Kind = "Shake", At = 0.16, For = 0.06, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.12,
			Layers = {
				-- The seal folds to a point. Quint-in means it barely moves, then goes all at once, which
				-- is the shape of something snapping shut.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.12,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 5.2,
					EndSize = 0.3,
					Offset = { 0, 0.6, 3 },
					Spin = 5.5,
					Transparency = 0.12,
					EndTransparency = 0.5,
				},
				-- The release: everything the seal gathered, thrown forward along the aim.
				{
					Kind = "Emitter",
					At = 0.08,
					For = 0.06,
					Texture = "SparkStreak",
					Offset = { 0, 0.6, 3 },
					Burst = 22,
					Speed = { 16, 30 },
					Lifetime = { 0.18, 0.34 },
					Spread = 26,
					Drag = 3,
					Squash = 0.3,
					Size = 0.8,
					EndSize = 0,
				},
				-- The stroke that leaves the hand. A brush stroke, dry at both ends, not a laser.
				{
					Kind = "Beam",
					At = 0.08,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 1.4,
					EndSize = 0,
					Offset = { 0, 0.6, 3 },
					Transparency = 0.2,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.5,
			Layers = {
				-- What is left hanging where the seal was. Slow, faint, and short: a cast should be
				-- remembered for half a second, not litter the arena.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.4,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.6, 3 },
					Rate = 8,
					Speed = { 0.4, 1.6 },
					Lifetime = { 0.5, 0.9 },
					Spread = 140,
					Drag = 1.2,
					Size = 0.35,
					EndSize = 0,
				},
			},
		},
	},
}

-- The impact. Played by every hit in the game, which makes it the second most repeated visual.
--
-- "Un impact blanchit l'écran comme une page surexposée, puis laisse une brûlure d'encre qui s'efface."
-- That is the whole effect: a white flash, a ring, and a mark on the ground that outlives it (rule 5).
local HIT: Timeline = {
	Intent = "The page is overexposed for a frame, then keeps the burn where it was struck",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.18,
			Layers = {
				-- The ring, thrown along the blow rather than symmetrically, so an impact reads as having
				-- come from somewhere.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.3,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Size = 0.6,
					EndSize = 9,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Burst = 14,
					Speed = { 12, 26 },
					Lifetime = { 0.18, 0.4 },
					Spread = 42,
					Drag = 4,
					Squash = 0.3,
					Size = 0.55,
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
				-- Smoke off the burn, rising and slowing.
				{
					Kind = "Emitter",
					At = 0.04,
					For = 0.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Rate = 12,
					Speed = { 1.5, 3.5 },
					Lifetime = { 0.7, 1.2 },
					Spread = 55,
					Drag = 2.5,
					Size = 1.2,
					EndSize = 3.4,
					Transparency = 0.55,
					EndTransparency = 1,
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
					Texture = "BrushStroke",
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
				-- dodge feel like a stumble. Nobody else needs to feel a dodge: it is not an impact.
				{
					Kind = "Light",
					At = 0,
					For = 0.22,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 6,
					Brightness = 1.1,
				},
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
				{
					Kind = "Light",
					At = 0,
					For = 0.1,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, 0.2, 1.8 },
					Range = 3,
					Brightness = 0.8,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.1,
			Layers = {
				-- The stroke itself, swept across the front on a brush texture rather than drawn as a
				-- hard arc. A melee swing that reads as a shape is a weapon; one that reads as a mark is
				-- a hand.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0.1, 3.2 },
					Size = 1.2,
					EndSize = 6.4,
					Spin = 7,
					Transparency = 0.15,
					EndTransparency = 1,
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

-- Brand (Cinnabar, projectile). The first glyph every player learns and the one they throw most, so it
-- is the first of the twenty to be rebuilt.
--
-- What it replaced was a ball with Roblox's own Fire class on it, flying in a straight line at a constant
-- speed for a full second. Three of those four words are a rule broken: nothing travels linearly (rule
-- 4), nothing in this game is a stock engine effect, and a thing thrown by a hand arcs.
--
-- It has no Impact phase, because its impact is a separate packet: the server detonates it and emits
-- Explosion, which has its own timeline below. That split is not an accident of the old code, it is
-- correct -- the projectile does not know where it will end, and the blast does not know where it began.
local BRAND: Timeline = {
	Intent = "An ember is gathered, thrown, and arcs away trailing ink",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.14,
			Layers = {
				-- Drawn in, not thrown out. The cast's seal has already closed by now; this is the glyph
				-- itself taking shape in the hand.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.14,
					Texture = "SparkStreak",
					Offset = { 0, 0.4, 3 },
					Rate = 46,
					Speed = { -12, -6 },
					Lifetime = { 0.12, 0.2 },
					Spread = 180,
					Drag = 3,
					Squash = 0.4,
					Size = 0.45,
					EndSize = 0.05,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.18,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, 0.4, 3 },
					Range = 6,
					Brightness = 1.4,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.06,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				{
					Kind = "Emitter",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0, 0.4, 3 },
					Burst = 16,
					Speed = { 14, 26 },
					Lifetime = { 0.2, 0.38 },
					Spread = 30,
					Drag = 3,
					Squash = 0.3,
					Size = 0.6,
					EndSize = 0,
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
				{
					Kind = "Carrier",
					At = 0,
					For = 1,
					Ease = "Sine",
					EaseDirection = "Out",
					Travel = 90,
					-- Three studs of rise and fall over ninety. Barely visible, and the whole reason it
					-- reads as thrown rather than fired.
					Arc = 3,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				{
					Kind = "Trail",
					At = 0,
					For = 1,
					Ride = true,
					Texture = "BrushStroke",
					Size = 2.2,
					EndSize = 0.4,
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 1,
					Ride = true,
					Texture = "SmokeSoft",
					Rate = 22,
					Speed = { -3, 1 },
					Lifetime = { 0.35, 0.7 },
					Spread = 60,
					Drag = 2,
					Size = 0.9,
					EndSize = 2.6,
					Transparency = 0.5,
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
local EXPLOSION: Timeline = {
	Intent = "The page is struck through: a ring, a bloom of ink, and a burn that stays",
	Phases = {
		{
			Name = "Impact",
			Duration = 0.22,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				{
					Kind = "Sprite",
					At = 0,
					For = 0.4,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "ShockwaveRing",
					Size = 1,
					EndSize = 16,
					Transparency = 0.05,
					EndTransparency = 1,
				},
				-- The flipbook: an ink bloom opening and dispersing, which is the one place in the game a
				-- 64-frame texture earns its size.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.08,
					Texture = "ExplosionBloom",
					Burst = 5,
					Speed = { 2, 6 },
					Lifetime = { 0.45, 0.6 },
					Spread = 180,
					Drag = 3,
					Size = 7,
					EndSize = 13,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "SparkStreak",
					Burst = 26,
					Speed = { 18, 40 },
					Lifetime = { 0.25, 0.5 },
					Spread = 180,
					Drag = 4,
					Squash = 0.28,
					Size = 0.7,
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
				-- The burn. Larger and longer than a plain hit's, because a detonation is the loudest
				-- thing that happens to a patch of ground in this game.
				{
					Kind = "Mark",
					At = 0,
					For = 3,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 9,
					EndSize = 11,
					Transparency = 0.25,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 2.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 5.5,
					EndSize = 7,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.7,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Rate = 18,
					Speed = { 2, 5 },
					Lifetime = { 0.9, 1.6 },
					Spread = 50,
					Drag = 2.2,
					Size = 2,
					EndSize = 6,
					Transparency = 0.5,
					EndTransparency = 1,
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
	Intent = "A loaded brush is dragged forward: a dark wet front on the server's own clock, and the strip it soaks",
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
				-- The brush loading: pigment pulled INTO it, not off it. Negative speed is the idea the
				-- cast uses -- a wind-up must read as gathering or it reads as a spell already half spent
				-- -- and the matter is SmokeSoft, because Indigo is wet. Sparks belong to Cinnabar and
				-- Orpiment; a school legible by its matter as well as its colour is free legibility in a
				-- six-way fight.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "SmokeSoft",
					Offset = { 0, -1.4, 4 },
					Rate = 60,
					Speed = { -13, -6 },
					Lifetime = { 0.1, 0.18 },
					Spread = 170,
					Drag = 2.6,
					Size = 0.8,
					EndSize = 0.1,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.04,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The pigment leaving the brush, thrown at the floor rather than into the air: a wash is
				-- laid down, it is not sprayed. There is no Shake here; the Cast timeline playing in
				-- parallel already fired the Cast profile 0.06 earlier, and firing it twice is two shakes,
				-- not weight.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.04,
					Texture = "SmokeSoft",
					Offset = { 0, -1.4, 5 },
					Burst = 18,
					Speed = { 10, 22 },
					Lifetime = { 0.3, 0.55 },
					Spread = 35,
					Drag = 3.4,
					Size = 1.2,
					EndSize = 4.4,
					Transparency = 0.45,
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
				-- The leading edge, the signature layer: a stroke facing whoever it is about to reach,
				-- widening to the full sixteen-stud hit diameter and diluting as it goes. It ends half a
				-- stud wider than the sphere that hurts, never narrower.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.7,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 9,
					EndSize = 16.6,
					Transparency = 0.22,
					EndTransparency = 0.72,
				},
				-- The wet curtain. buildTrail spans its ribbon vertically about its anchor, so this is a
				-- five-stud sheet standing on the page, not a stroke lying on it -- the Offset lifts it so
				-- its lower edge meets the floor instead of half of it being buried. The stroke on the
				-- floor is the business of the three marks below; Mark is the only layer kind that lies
				-- flat.
				{
					Kind = "Trail",
					At = 0,
					For = 0.7,
					Ride = true,
					Texture = "BrushStroke",
					Size = 5,
					EndSize = 1.4,
					Offset = { 0, 1.7, 0 },
					Transparency = 0.28,
					EndTransparency = 1,
				},
				-- Pigment shed off the BACK of the front and dropped toward the page. Outward at seventy
				-- degrees is the puff every moving thing in Roblox trails; inward and down is a brush
				-- depositing, which is what the comment above promises and what a wash actually does.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.66,
					Ride = true,
					Texture = "SmokeSoft",
					Offset = { 0, -1.2, -1.6 },
					Rate = 34,
					Speed = { -5, 0 },
					Lifetime = { 0.35, 0.7 },
					Spread = 30,
					Drag = 3.2,
					Size = 1.1,
					EndSize = 3.8,
					Transparency = 0.45,
					EndTransparency = 1,
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
				-- the sixteen that hurt, and that is the safe side -- by the time these are legible the
				-- front is gone and nothing about them is a warning.
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
				-- The wetting. Exponential/Out puts the full radius down in about a tenth of a second,
				-- because the zone hurts from frame one and a pool drawn smaller than the damage is the
				-- lie that costs a player a round. It hands off to the pool at 0.14 rather than
				-- overlapping it: two marks on one patch of floor share the same 0.03 lift and flicker.
				{
					Kind = "Mark",
					At = 0,
					For = 0.14,
					Ease = "Exponential",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 2,
					EndSize = 19.5,
					Transparency = 0.7,
					EndTransparency = 0.5,
				},
				-- The pool, one mark for the zone's whole life. A stud over the radius that hurts, because
				-- the blot's edge is ragged: the decal is square but the ink inside it is not, which is
				-- why this direction draws a blot instead of a circle. It darkens rather than fading --
				-- the page is taking on more ink the whole time it is hurting somebody.
				{
					Kind = "Mark",
					At = 0.14,
					For = 2.06,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 19.5,
					EndSize = 21,
					Transparency = 0.5,
					EndTransparency = 0.62,
				},
				-- Tick one, two, three: ink RUNNING, not vapour rising. A ring of smoke thrown outward
				-- three times is the stock damage-over-time pulse and belongs to every other game; a
				-- bleed is defined by wicking along fibre, so each drink sends a stroke racing low across
				-- the page. They run parallel because paper has a grain and ink follows it. Same numbers
				-- three times on purpose: an uneven pulse reads as a bug, an even one reads as a clock,
				-- and a clock is what somebody crossing this needs. buildBeam makes a beam eight times as
				-- long as it is wide, so 0.9 is a seven-stud run inside a nine-stud radius.
				{
					Kind = "Beam",
					At = 0,
					For = 0.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.9,
					EndSize = 0.15,
					Offset = { -4.6, -2.4, 1.5 },
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Beam",
					At = 1,
					For = 0.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.9,
					EndSize = 0.15,
					Offset = { 3.8, -2.4, -3.4 },
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Beam",
					At = 2,
					For = 0.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.9,
					EndSize = 0.15,
					Offset = { -1.2, -2.4, 4.8 },
					Transparency = 0.2,
					EndTransparency = 1,
				},
				-- One light per drink, on the same three frames. stepLight only ever fades, so each of
				-- these is a flare that decays: the zone pulses three times and is then just a stain.
				{
					Kind = "Light",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 15,
					Brightness = 2.4,
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
				{
					Kind = "Light",
					At = 2,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 15,
					Brightness = 2.4,
				},
				-- The slow, made visible. Everything else here moves outward; this one thing is
				-- continuously pulled in, because the page is drinking. It is the only layer that says why
				-- standing here costs you your speed, and it runs for the zone's whole life. SmokeSoft,
				-- not sparks: Indigo is wet, and the school should be nameable by its matter as well as
				-- its colour.
				{
					Kind = "Emitter",
					At = 0.04,
					For = 2.1,
					Texture = "SmokeSoft",
					Offset = { 0, 1.2, 0 },
					Rate = 22,
					Speed = { -7, -2 },
					Lifetime = { 0.4, 0.85 },
					Spread = 180,
					Drag = 2.4,
					Size = 0.9,
					EndSize = 0.1,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				-- Once, on the first drink. Three camera shakes a second apart, on a zone somebody may be
				-- standing in for its whole duration, is a broken camera rather than weight.
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
local BINDING: Timeline = {
	Intent = "A frame is ruled round the target, the stitch is pulled shut, and the ink empties as the root runs out",
	Phases = {
		{
			Name = "Anticipation",
			-- A tenth, and no more. The root is already applied, so every frame here is a frame of the
			-- hold spent not reading as a hold. It exists only so the stitch has something to close from:
			-- rule 3 says nothing appears, and a binding that starts at full size appeared.
			Duration = 0.1,
			Layers = {
				-- The frame ruled round the body. Back/Out overshoots and settles, which is a hand drawing
				-- a closed shape in one motion. It runs a hundredth past its phase so the stitch takes
				-- over on a frame where both are the same size -- a longer overlap shows two rings, one
				-- growing and one shrinking, which reads as the spell splitting in half.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.11,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 0.4,
					EndSize = 7.4,
					Spin = 2.2,
					Transparency = 1,
					EndTransparency = 0.2,
				},
				-- Fibre drawn along the line the stitch will take, not an aura around the victim. A tight
				-- spread on the thread's own axis is what separates thread from a charge-up: these streaks
				-- enter at one end and leave at the other, and Squash stretches each one so it reads as
				-- being pulled rather than as a dot that moved.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, 0.2, -1.4 },
					Rate = 70,
					Speed = { -15, -8 },
					Lifetime = { 0.08, 0.16 },
					Spread = 28,
					Drag = 2.2,
					Squash = 0.35,
					Size = 0.45,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.12,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The stitch pulled tight. Quint/In barely moves and then goes all at once, and the spin
				-- reverses: everything else in this game opens outward, and a knot is the one thing that
				-- has to close.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.12,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 7.4,
					EndSize = 4.6,
					Spin = -6,
					Transparency = 0.2,
					EndTransparency = 0.1,
				},
				{ Kind = "Shake", At = 0.05, For = 0.04, Profile = "Light" },
			},
		},
		{
			Name = "Impact",
			-- RootDuration minus the 0.22 the drawing and the closing already spent, so this phase ends at
			-- 1.50 absolute: the frame MovementService gives the legs back.
			Duration = 1.28,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The binding holding, and the clock. It turns slowly the wrong way and empties over
				-- exactly the root that is left. When the ink is gone the victim can move, and nothing
				-- else had to say so.
				{
					Kind = "Sprite",
					At = 0,
					For = 1.28,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "SealRing",
					Size = 4.6,
					EndSize = 4.2,
					Spin = -0.5,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				-- The thread. buildBeam runs a beam forward for eight times its width, so placing it two
				-- and a half studs behind the body carries it through and out the far side: a stroke
				-- passing THROUGH a thing, which is the single image that separates a binding from a
				-- bubble.
				{
					Kind = "Beam",
					At = 0.02,
					For = 1.26,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 0.6,
					EndSize = 0.18,
					Offset = { 0, 0.2, -2.4 },
					Transparency = 0.18,
					EndTransparency = 1,
				},
				-- Fibre still being drawn along the stitch while it holds. Kept narrow and on the thread's
				-- axis for the same reason as the wind-up: a particle ring orbiting a held character is
				-- the stock stunned aura, and this has to read as sewing.
				{
					Kind = "Emitter",
					At = 0.04,
					For = 1.2,
					Texture = "SparkStreak",
					Offset = { 0, 0.2, -1.2 },
					Rate = 22,
					Speed = { -6, -2 },
					Lifetime = { 0.3, 0.6 },
					Spread = 30,
					Drag = 2.4,
					Squash = 0.4,
					Size = 0.4,
					EndSize = 0.05,
				},
				-- The floor of the cell, held for the whole root and darkening rather than fading: the one
				-- layer that says the ground under this person belongs to somebody else right now.
				{
					Kind = "Mark",
					At = 0,
					For = 1.28,
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
					At = 0,
					For = 1.28,
					Ease = "Sine",
					EaseDirection = "Out",
					Range = 12,
					Brightness = 2.6,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.2,
			Layers = {
				-- A binding ends by breaking. One outward burst on the frame the root expires -- 1.50, not
				-- 1.72 -- so the release is an event the victim can act on rather than an absence they
				-- have to notice. This is the one place in the timeline where anything is thrown outward,
				-- which is what makes it read as a thing giving way.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.1,
					Texture = "SparkStreak",
					Burst = 20,
					Speed = { 11, 24 },
					Lifetime = { 0.22, 0.45 },
					Spread = 180,
					Drag = 4,
					Squash = 0.3,
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
-- How it is built: the margin is RULED FIRST. A stroke is drawn on the floor before anything rises, so an
-- opponent gets a quarter of a second to read a wall coming and an ally gets the same to stop running at
-- it. Then two courses of ink grow out of that line -- and they are NOT coplanar. The packet's Origin is
-- the slab's centre, so the courses sit on either face of it, 0.9 studs fore and aft inside its 2.5 of
-- thickness: two coplanar textured quads fight for the same pixel as long as they both live, and a wall
-- that flickers for five seconds is worse than no wall. On the leaf's two faces they read as recto and
-- verso, ruled in two passes by a hand rather than extruded by a machine.
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
			Duration = 0.26,
			Layers = {
				-- The ruling. Exponential/Out throws most of the line out in a quarter of a second and
				-- then creeps the last of it, which is a dry brush running out of pigment. Its
				-- transparency does not move: this is a line being drawn, not a light coming up.
				-- Fourteen, never more -- the rule may not promise more floor than the wall will occupy.
				-- It ends at 0.76, where the drying line below begins, so the floor never carries two
				-- marks at one height.
				{
					Kind = "Mark",
					At = 0,
					For = 0.76,
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
					For = 0.26,
					Texture = "DustMote",
					Offset = { 0, -4.5, 0 },
					Rate = 50,
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
			Duration = 0.5,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.45, For = 0.05, Voice = "Impact" },
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The near face, the broad pass: fourteen studs of ink out of the floor line, the
				-- collision's width exactly. Back/Out overshoots and settles, which is a slab hitting its
				-- stops. It ends at 0.76 on the nail, where the standing course below starts at the same
				-- size -- a butt joint, not an overlap. onHeartbeat activates pending layers before it
				-- releases expired ones, so there is no frame of nothing between them to defend against.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.5,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.8,
					EndSize = 14,
					Offset = { 0, -4.5, -0.9 },
					Transparency = 0.34,
					EndTransparency = 0.14,
				},
				-- The far face, an eighth of a second later and narrower: ink that did not soak all the
				-- way through the leaf. Two passes, two planes, one slab.
				{
					Kind = "Sprite",
					At = 0.08,
					For = 0.42,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.6,
					EndSize = 12,
					Offset = { 0, -4.5, 0.9 },
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
					Size = 0.7,
					EndSize = 2.6,
					Transparency = 0.4,
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
				{ Kind = "Shake", At = 0.12, For = 0.08, Profile = "Melee" },
			},
		},
		{
			Name = "Residue",
			-- A Margin standing IS what the world keeps, which is what this phase is for. There is no
			-- Impact phase because the wall lands on nobody: its Damage is zero and it hits only the floor.
			Duration = 4.7,
			Layers = {
				-- The line, drying under the wall and after it. Drawn first, gone last, and the longest
				-- lived layer in the game: the margin is the mark, the wall was only the margin standing
				-- up.
				{
					Kind = "Mark",
					At = 0,
					For = 5.2,
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
					For = 4.6,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "BrushStroke",
					Size = 14,
					EndSize = 14,
					Offset = { 0, -4.5, -0.9 },
					Transparency = 0.14,
					EndTransparency = 0.2,
				},
				-- And sinking, in the last half second and not before. Quint/In over a span this short is
				-- a drop rather than a slouch, which is the only shape that keeps the window where the ink
				-- is shorter than the collision down to a fraction of a second.
				{
					Kind = "Sprite",
					At = 4.6,
					For = 0.52,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 14,
					EndSize = 0.8,
					Offset = { 0, -4.5, -0.9 },
					Transparency = 0.2,
					EndTransparency = 0.5,
				},
				-- The far face does the same, four hundredths later at each end. A wall that leaves in one
				-- piece was never in the page; this one goes back in the order it came out.
				{
					Kind = "Sprite",
					At = 0,
					For = 4.64,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "BrushStroke",
					Size = 12,
					EndSize = 12,
					Offset = { 0, -4.5, 0.9 },
					Transparency = 0.3,
					EndTransparency = 0.34,
				},
				{
					Kind = "Sprite",
					At = 4.64,
					For = 0.54,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 12,
					EndSize = 0.6,
					Offset = { 0, -4.5, 0.9 },
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
-- What it replaced was a ball of Roblox's ForceField material growing from two studs to twenty-four and
-- fading out, plus a burst of twenty-four sparks. Two failures in one object: a sphere that grows and
-- fades is the effect every Roblox game already ships, and ForceField is an engine material carrying its
-- own hex lattice, so the glyph wore somebody else's identity in a game whose whole direction is that
-- nothing is borrowed.
--
-- Air is invisible, so the wind is never drawn -- only what it moves is, and in this game what the wind
-- moves is ink. A small stroke leaves the hand; a stroke eight times its size answers it at the burst
-- centre, wide as the hitbox; the ink on the page underneath is shoved out to the rim and gone; the dust
-- is torn UP off the floor, which is the Lift the server applies. The ground trace is the one WIPE in
-- Vellum -- every other glyph burns a mark onto the page, this one pushes the ink off it, so its Mark is a
-- brush stroke and not a blot, and it lasts a second where a burn lasts two and a half.
--
-- The big stroke is deliberately not a plate of PaperGrain. That texture is the world's own surface: five
-- to twenty-four per cent alpha, edge to edge, tileable, no shape of its own (tools/textures/paper.py), so
-- drawn as a twenty-four stud sprite it is a hard-edged translucent square with half of itself buried in
-- the floor. BrushStroke is fifteen to one with dry broken ends, so the same square draws a band of ink
-- across the front and everything outside the band is transparent, which is also what keeps it above
-- ground.
--
-- No Flash layer. PageFlash belongs to impacts, and a glyph cast every three seconds that borrowed the
-- loudest thing in the vocabulary would make it mean nothing everywhere else. For the same reason the
-- anticipation is one frame of gather -- a Burst, not a Rate: GlyphEffects.Sweep damages the moment the
-- packet leaves, and a Rate of forty-four over sixty milliseconds is two and a half particles, which is
-- not a wind-up, it is an appearance (rule 3).
--
-- It is played at the CENTRE the server damaged, not at the caster, so the footprint and the trace sit on
-- the hitbox at any Scale; the hand layers carry the ten studs of Params.Offset backwards.
local SWEEP: Timeline = {
	Intent = "The page is snapped flat in front of the caster and the ink on it is thrown off",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.06,
			Layers = {
				-- One frame. Air pulled into the hand, negative speed, exactly as the cast gathers ink --
				-- the difference between a shove and a hand that was suddenly somewhere else.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "DustMote",
					Offset = { 0, 0.2, -7.6 },
					Burst = 14,
					Speed = { -8, -3 },
					Lifetime = { 0.08, 0.16 },
					Spread = 180,
					Drag = 3,
					Size = 0.35,
					EndSize = 0.02,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.1,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The hand's own stroke, on the brush texture and not as a cone: a cone is a shape and a
				-- shape is a weapon, a stroke is a gesture. It spins slowly rather than fast, because a
				-- swipe that spins fast is a propeller.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.16,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 3,
					EndSize = 9,
					Offset = { 0, 0.5, -6 },
					Spin = 1.6,
					Transparency = 0.12,
					EndTransparency = 1,
				},
				-- Grit knocked loose at the hand. Wide spread on purpose: buildEmitter never sets
				-- EmissionDirection, so a narrow cone would fire straight up the host's own axis rather
				-- than along the aim, and a layer cannot be authored to claim a direction the runtime does
				-- not give it.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "SparkStreak",
					Offset = { 0, 0.4, -6 },
					Burst = 16,
					Speed = { 18, 34 },
					Lifetime = { 0.12, 0.26 },
					Spread = 120,
					Drag = 4,
					Squash = 0.25,
					Size = 0.5,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.18,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The wipe in the air, at the width of the damage. Params.Radius is 12, so the sphere the
				-- server queries is twenty-four studs across (twenty-three where it crosses the floor,
				-- being centred at root height), and this is drawn at twenty-four inside a quarter second,
				-- because the damage was instant and a footprint drawn smaller than what it hurts is the
				-- most expensive lie a fighting game can tell.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.26,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 8,
					EndSize = 24,
					Offset = { 0, 2.2, 0 },
					Spin = 0.5,
					Transparency = 0.1,
					EndTransparency = 1,
				},
				-- The ink already on the page, shoved outward to the rim in a quarter second and gone. It
				-- states the hitbox on the ground, where a zone is read from, and it is the only mark in
				-- the game that grows to its full width and then stops existing rather than fading in
				-- place: the ink was not burnt, it was moved.
				{
					Kind = "Mark",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 14,
					EndSize = 24,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				-- Torn off the floor, upward: Params.Lift is thirty studs and this is the only layer that
				-- shows it. Emitted from below the centre, where a host part's own up axis is the one
				-- direction an emitter here can be trusted to state, so the dust genuinely leaves the
				-- ground instead of hanging in the air.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "DustMote",
					Offset = { 0, -1.4, 0 },
					Burst = 30,
					Speed = { 16, 34 },
					Lifetime = { 0.3, 0.6 },
					Spread = 62,
					Drag = 2.6,
					Squash = 0.4,
					Size = 0.6,
					EndSize = 0.1,
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
-- The nib loads first -- a burst rather than a rate, because a rate of thirty-four over a tenth of a
-- second is three particles and an invisible wind-up is an appearance (rule 3) -- then a three-stud Beam
-- at the hand is the bec touching the page. The carrier starts at Params.SpawnOffset, so the sixty studs
-- it flies end sixty-four studs from the caster, which is exactly where stepProjectile stops: it measures
-- its maxDistance from the spawn point, not from the root. There is no Arc at all, the server firing it at
-- zero gravity, and a ruled line does not sag.
--
-- The body of the flight is TWO trails on the same stroke texture, both riding the one carrier: a
-- fifty-five hundredths core and a 1.6 stud dry edge over it. That is a pen stroke -- a wet centre inside
-- a broken outer edge -- where one thin trail plus a dust wake is a bullet with exhaust, and it costs the
-- same. There is no bullet, because there is nothing to see except the mark being made.
--
-- Sine InOut on the carrier is a measured choice. The server moves at a constant velocity, rule 4 forbids
-- copying it, and of the eight curves available this one departs from constant by the least: the curve is
-- symmetric, so the visual is up to six studs BEHIND the hitbox through the first half of the flight and
-- up to six studs AHEAD of it through the second, which at a hundred and thirty studs a second is
-- forty-eight milliseconds either way. Quad In would keep the visual permanently behind, but by fifteen
-- studs at mid-flight, which means being hit by a line that has not arrived -- the worse of the two.
--
-- It has no Impact phase and no Mark. It touches nothing: what happens when it lands belongs to the shared
-- Hit timeline, which bleaches the page and leaves the burn. Same split as Brand, for the same reason.
local HAIRLINE: Timeline = {
	Intent = "A single thin line is ruled across the page, wet at the core and dry at the edge",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.1,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, 0.3, 3 },
					Burst = 16,
					Speed = { -9, -4 },
					Lifetime = { 0.08, 0.16 },
					Spread = 180,
					Drag = 2.5,
					Squash = 0.3,
					Size = 0.32,
					EndSize = 0.02,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.14,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, 0.3, 3 },
					Range = 5,
					Brightness = 1.2,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.05,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The nib touching down: three studs of brush stroke, dry at both ends, gone before the
				-- body has cleared the hand.
				{
					Kind = "Beam",
					At = 0,
					For = 0.12,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.45,
					EndSize = 0,
					Offset = { 0, 0.3, 3.4 },
					Transparency = 0.15,
					EndTransparency = 1,
				},
				-- Eight particles of ink spat at the nib. Not a narrow cone: a narrow cone would fire up
				-- the host's own axis rather than down the line, so the spread is left wide enough that
				-- the layer claims nothing the runtime cannot draw.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.04,
					Texture = "SparkStreak",
					Offset = { 0, 0.3, 4 },
					Burst = 8,
					Speed = { 14, 26 },
					Lifetime = { 0.1, 0.2 },
					Spread = 110,
					Drag = 4,
					Squash = 0.25,
					Size = 0.35,
					EndSize = 0,
				},
			},
		},
		{
			Name = "Travel",
			-- Sixty studs at Params.Speed of a hundred and thirty is 0.46 s, which is when the server's
			-- projectile expires on distance -- before its 0.6 s fuse, so the fuse is not the number that
			-- decides the length of the flight.
			Duration = 0.46,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.41, For = 0.05, Voice = "Impact" },
				{
					Kind = "Carrier",
					At = 0,
					For = 0.46,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, 0.35, 4 },
					Travel = 60,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- The core of the stroke. The thinnest trail in the game: 0.55 studs against the Marque's
				-- 2.2.
				{
					Kind = "Trail",
					At = 0,
					For = 0.46,
					Ride = true,
					Texture = "BrushStroke",
					Size = 0.55,
					EndSize = 0.05,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				-- The dry edge around it, three times as wide and three times as faint. Two trails on one
				-- carrier cannot disagree about where the line is, and the pair is what makes it read as
				-- ink laid by a nib rather than as a tracer.
				{
					Kind = "Trail",
					At = 0,
					For = 0.46,
					Ride = true,
					Texture = "BrushStroke",
					Size = 1.6,
					EndSize = 0.1,
					Transparency = 0.62,
					EndTransparency = 1,
				},
				-- Small on purpose: a seven-stud light against the Marque's fourteen. The pigment still
				-- names the school from behind, which is how a player reads an opponent's intent, but a
				-- thin stroke that lit a room like a fireball would be lying about its weight.
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
				-- The afterimage of the line, hanging over the middle of its own path. Offset forward
				-- thirty-two studs rather than left at the origin: a residue with no offset and no carrier
				-- to ride is drawn at the caster's feet, which is the one place the stroke never was.
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
					Drag = 1.4,
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
local SPIRAL: Timeline = {
	Intent = "Four times, the page is drawn into one point and does not let go",
	Phases = {
		{
			Name = "Anticipation",
			-- A tenth of a second, and it is not a telegraph: the server's first tick lands with the
			-- packet, so this is only what keeps the zone from APPEARING (rule 3). Brand can afford 0.14 s
			-- of wind-up because it then flies for a second; a zone already dealing damage cannot afford
			-- more than the shortest gather that still reads as growth.
			Duration = 0.1,
			Layers = {
				-- The first draught, punched down into the point from ten studs up before anything else
				-- exists.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, 10, 0 },
					Burst = 24,
					Speed = { -40, -26 },
					Lifetime = { 0.25, 0.45 },
					Spread = 22,
					Drag = 1.5,
					Squash = 0.3,
					Size = 1,
					EndSize = 0.05,
				},
				-- The footprint, out to the true twenty-two studs inside the first half second and held
				-- there for the whole life of the zone. One long layer rather than one per tick: it is the
				-- statement of where the danger is, and that statement never blinks and never narrows.
				{
					Kind = "Mark",
					At = 0,
					For = 2.9,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "GradientRadial",
					Size = 19,
					EndSize = 22,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Impact",
			-- Params.Ticks (4) times Params.TickInterval (0.6), which is the Duration the server puts in
			-- the packet.
			Duration = 2.4,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- Four rings, closing, one per pull. The anti-shockwave: in every other game a ring on the
				-- ground means a blast went off, so a ring that runs backwards is the cheapest way to say
				-- this one takes instead of gives.
				{
					Kind = "Mark",
					At = 0,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.6,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 1.2,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 1.8,
					For = 0.55,
					Ease = "Circular",
					EaseDirection = "In",
					Texture = "ShockwaveRing",
					Size = 22,
					EndSize = 2,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				-- Streaks falling into the eye for the whole zone, from eight studs up at twenty-six
				-- degrees: the tight cone is what makes the direction real, and the direction is the only
				-- thing this layer is for.
				{
					Kind = "Emitter",
					At = 0.02,
					For = 2.2,
					Texture = "SparkStreak",
					Offset = { 0, 8, 0 },
					Rate = 24,
					Speed = { -30, -18 },
					Lifetime = { 0.3, 0.55 },
					Spread = 26,
					Drag = 1.6,
					Squash = 0.4,
					Size = 0.9,
					EndSize = 0.04,
				},
				-- The body under the streaks, falling more slowly and SHRINKING as it goes, so the volume
				-- itself reads as being consumed rather than as smoke that happens to drift.
				{
					Kind = "Emitter",
					At = 0.02,
					For = 2.2,
					Texture = "SmokeSoft",
					Offset = { 0, 5.5, 0 },
					Rate = 12,
					Speed = { -9, -4 },
					Lifetime = { 0.5, 0.9 },
					Spread = 38,
					Drag = 2,
					Size = 3.4,
					EndSize = 0.6,
					Transparency = 0.55,
					EndTransparency = 1,
				},
				-- The eye. One light decaying across the whole life: the runtime fades a light by
				-- brightness, so a single layer is the zone running out rather than four that restate it.
				{
					Kind = "Light",
					At = 0,
					For = 2.4,
					Ease = "Sine",
					EaseDirection = "In",
					Offset = { 0, 2, 0 },
					Range = 16,
					Brightness = 2.6,
				},
				-- Dash and not Light: the profile is weighted along the view axis, which is what a tug
				-- feels like. Four of them, on the tick, so the camera counts the pulls with the damage.
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Dash" },
				{ Kind = "Shake", At = 0.6, For = 0.05, Profile = "Dash" },
				{ Kind = "Shake", At = 1.2, For = 0.05, Profile = "Dash" },
				{ Kind = "Shake", At = 1.8, For = 0.05, Profile = "Dash" },
			},
		},
		{
			Name = "Residue",
			Duration = 2.2,
			Layers = {
				-- A knot, not a crater, and the only mark in the game that SHRINKS as it fades. Everywhere
				-- else a trace spreads while it pales; here it keeps tightening after the zone is gone,
				-- because that is the last thing the spell did to the page. It is safe here and it was not
				-- safe on the footprint: nothing is being damaged any more.
				{
					Kind = "Mark",
					At = 0,
					For = 2.2,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 8,
					EndSize = 5.5,
					Transparency = 0.28,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.7,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 3, 0 },
					Rate = 8,
					Speed = { -3, -0.8 },
					Lifetime = { 0.6, 1.1 },
					Spread = 150,
					Drag = 1.2,
					Size = 0.32,
					EndSize = 0,
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
local POUNCE: Timeline = {
	Intent = "Powder is poured over the page three times until nothing on it can move",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.12,
			Layers = {
				-- The shadow of what is about to land, at the true diameter of Params.Radius (13), grown
				-- in half a second and handed straight to the first stain.
				{
					Kind = "Mark",
					At = 0,
					For = 0.5,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "GradientRadial",
					Size = 20,
					EndSize = 26,
					Transparency = 0.45,
					EndTransparency = 1,
				},
				-- The first grains over the edge of the pot, falling in a narrow thread before the pour
				-- opens. Grain and not smoke: what is coming is powder, and the layer that announces it
				-- should be made of the same thing.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.12,
					Texture = "DustMote",
					Offset = { 0, 8, 0 },
					Burst = 18,
					Speed = { -9, -3 },
					Lifetime = { 0.3, 0.5 },
					Spread = 30,
					Drag = 2.5,
					Size = 0.5,
					EndSize = 0.12,
				},
			},
		},
		{
			Name = "Impact",
			-- Params.Ticks (3) times Params.TickInterval (0.9).
			Duration = 2.7,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- Three pours. Seven studs of fall at thirteen to twenty-two studs a second lands well
				-- inside the tick, which is what keeps the powder and the damage on the same beat.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.55,
					Texture = "SmokeSoft",
					Offset = { 0, 7, 0 },
					Burst = 22,
					Speed = { -22, -13 },
					Lifetime = { 0.5, 0.85 },
					Spread = 58,
					Drag = 2.4,
					Size = 2.2,
					EndSize = 6,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.9,
					For = 0.55,
					Texture = "SmokeSoft",
					Offset = { 0, 7, 0 },
					Burst = 22,
					Speed = { -22, -13 },
					Lifetime = { 0.5, 0.85 },
					Spread = 58,
					Drag = 2.4,
					Size = 2.2,
					EndSize = 6,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 1.8,
					For = 0.55,
					Texture = "SmokeSoft",
					Offset = { 0, 7, 0 },
					Burst = 22,
					Speed = { -22, -13 },
					Lifetime = { 0.5, 0.85 },
					Spread = 58,
					Drag = 2.4,
					Size = 2.2,
					EndSize = 6,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				-- The haze the pours land in, sinking rather than rising and spreading as it settles. This
				-- is the layer a player standing in it actually sees, so it is the one that has to feel
				-- heavy: long lifetimes, high drag, almost no speed.
				{
					Kind = "Emitter",
					At = 0.05,
					For = 2.4,
					Texture = "SmokeSoft",
					Offset = { 0, 1.2, 0 },
					Rate = 22,
					Speed = { -2.6, -0.8 },
					Lifetime = { 1.1, 1.9 },
					Spread = 150,
					Drag = 2.2,
					Size = 3,
					EndSize = 8,
					Transparency = 0.55,
					EndTransparency = 1,
				},
				-- The grain. Without it the zone is a cloud, and a cloud in this game is Indigo's or
				-- Cinnabar's; powder is what makes it Verdigris and what makes it pounce.
				{
					Kind = "Emitter",
					At = 0.1,
					For = 2.4,
					Texture = "DustMote",
					Offset = { 0, 2.6, 0 },
					Rate = 24,
					Speed = { -7, -2 },
					Lifetime = { 0.55, 1.1 },
					Spread = 160,
					Drag = 1.5,
					Size = 0.45,
					EndSize = 0.12,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				-- Wide and dim. The world is bright and the magic is dark: this is the dullest light of the
				-- four Verdigris glyphs, because the zone deadens the page rather than lighting it.
				{
					Kind = "Light",
					At = 0,
					For = 2.7,
					Ease = "Sine",
					EaseDirection = "In",
					Offset = { 0, 2.5, 0 },
					Range = 20,
					Brightness = 1.5,
				},
				-- One stain per pour, a beat after it, each wider than the last. Three steps on the floor
				-- is how a zone that ticks looks like it is ticking, and the last one arrives at the real
				-- twenty-six studs the shadow promised in the first half second.
				{
					Kind = "Mark",
					At = 0.35,
					For = 1.2,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 12,
					EndSize = 16,
					Transparency = 0.5,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 1.25,
					For = 1.2,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 17,
					EndSize = 21,
					Transparency = 0.45,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 2.15,
					For = 1.2,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 21,
					EndSize = 25,
					Transparency = 0.4,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 2,
			Layers = {
				-- The dusting. Soft-edged, wider than the zone was, and the last thing to go: the powder
				-- outlives the cloud that carried it, which is the whole reason a scribe reaches for it.
				{
					Kind = "Mark",
					At = 0,
					For = 2,
					Ease = "Sine",
					EaseDirection = "In",
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
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 1.6, 0 },
					Rate = 8,
					Speed = { -2.4, -0.6 },
					Lifetime = { 0.8, 1.4 },
					Spread = 150,
					Drag = 1.6,
					Size = 0.34,
					EndSize = 0,
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
					For = 0.38,
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
				},
				-- Grit off the split page, one burst per damaged point, on the server's own schedule. An
				-- emitter is fixed where it is built and cannot walk down the line, so five of them at
				-- the five points do what one of them cannot -- and the count is the information: five
				-- spheres, five beats. An emitter's default direction is its host part's up, so a narrow
				-- spread is a short column rather than a spray, which is right for a glyph whose server
				-- stuns and does not launch.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 6 },
					Burst = 12,
					Speed = { 14, 30 },
					Lifetime = { 0.3, 0.6 },
					Spread = 55,
					Drag = 3.5,
					Squash = 0.35,
					Size = 0.55,
					EndSize = 0.05,
				},
				{
					Kind = "Emitter",
					At = 0.08,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 11 },
					Burst = 12,
					Speed = { 14, 30 },
					Lifetime = { 0.3, 0.6 },
					Spread = 55,
					Drag = 3.5,
					Squash = 0.35,
					Size = 0.55,
					EndSize = 0.05,
				},
				{
					Kind = "Emitter",
					At = 0.16,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 16 },
					Burst = 12,
					Speed = { 14, 30 },
					Lifetime = { 0.3, 0.6 },
					Spread = 55,
					Drag = 3.5,
					Squash = 0.35,
					Size = 0.55,
					EndSize = 0.05,
				},
				{
					Kind = "Emitter",
					At = 0.24,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 21 },
					Burst = 12,
					Speed = { 14, 30 },
					Lifetime = { 0.3, 0.6 },
					Spread = 55,
					Drag = 3.5,
					Squash = 0.35,
					Size = 0.55,
					EndSize = 0.05,
				},
				{
					Kind = "Emitter",
					At = 0.32,
					For = 0.1,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 26 },
					Burst = 16,
					Speed = { 14, 32 },
					Lifetime = { 0.3, 0.7 },
					Spread = 55,
					Drag = 3.5,
					Squash = 0.35,
					Size = 0.6,
					EndSize = 0.05,
				},
				-- The light marches, near end then far end, so the pigment travels down the line and a
				-- player watching from the side reads which way the danger is going instead of seeing a
				-- patch of ground lit all at once. Two and not five: PoolPolicy caps PointLight at 24
				-- live, the tightest row in the file, and Roblox drops the surplus per surface anyway.
				{
					Kind = "Light",
					At = 0,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1, 8 },
					Range = 14,
					Brightness = 2.6,
				},
				{
					Kind = "Light",
					At = 0.24,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1, 23 },
					Range = 16,
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
				{
					Kind = "Emitter",
					At = 0.04,
					For = 0.8,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Offset = { 0, -1.6, 16 },
					Rate = 16,
					Speed = { 1.4, 3.4 },
					Lifetime = { 0.7, 1.3 },
					Spread = 55,
					Drag = 2.4,
					Size = 1.4,
					EndSize = 3.8,
					Transparency = 0.5,
					EndTransparency = 1,
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
-- The reading is the name again. A stipple is a mark made of dots, and this glyph's job is weight: the
-- dart sheds dots the whole way across and they hang in the air, so the flight leaves a dotted line drawn
-- over the arena and the target watches the thing that is about to slow them arrive. The gather is dots
-- too, where Brand's is streaks: same grammar, different hand.
--
-- The carrier eases Sine-InOut and not Sine-Out like Brand's. Brand detonates on a fuse and announces its
-- own arrival with a separate packet, so a visual that runs ahead costs nothing. This one's arrival IS its
-- damage, so a systematic lead would show the dart passing through a target who has not been hit and a
-- systematic lag would damage them before it got there. InOut is zero at both ends and at the middle and
-- 7.25 studs behind at the quarter points, which is the smallest honest error the format can express.
local STIPPLE: Timeline = {
	Intent = "A dot is pressed into the hand and flicked flat across the page, stippling the air behind it",
	Phases = {
		{
			-- Half of Brand's wind-up. Every frame spent here is studs of disagreement with a projectile
			-- the server has already started stepping, and this one is twenty studs a second faster than
			-- Brand. A dart is flicked, not thrown.
			Name = "Anticipation",
			Duration = 0.08,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.08,
					Texture = "DustMote",
					Offset = { 0, 0.3, 2.6 },
					Rate = 72,
					Speed = { -14, -7 },
					Lifetime = { 0.08, 0.16 },
					Spread = 180,
					Drag = 4,
					Size = 0.35,
					EndSize = 0.04,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.12,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, 0.3, 2.6 },
					Range = 5,
					Brightness = 1.1,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.04,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- A tight cone, not a spray. Fourteen degrees says a dart left the hand; Brand's thirty
				-- says something was lobbed.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.05,
					Texture = "SparkStreak",
					Offset = { 0, 0.3, 3.4 },
					Burst = 12,
					Speed = { 18, 32 },
					Lifetime = { 0.16, 0.3 },
					Spread = 14,
					Drag = 3,
					Squash = 0.3,
					Size = 0.5,
					EndSize = 0,
				},
			},
		},
		{
			-- Seventy studs in 0.64 seconds is the glyph's whole Range at its own Speed, and the test
			-- holds the carrier to that Range.
			--
			-- NAMED AS A GAP: it flies the full distance even when the server stopped the dart at twenty.
			-- The packet is emitted BEFORE stepProjectile resolves, so the client does not know the stop
			-- point at the moment it starts drawing, and Context.Scale -- the only lever a timeline has --
			-- would have to be set from information nobody has yet. Pinning Travel to Range rather than to
			-- the ninety-nine studs Speed x Fuse would allow is the honest half of it, and it is as far as
			-- this file can go. Closing it needs a second packet on stop, not a change here.
			Name = "Travel",
			Duration = 0.64,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.59, For = 0.05, Voice = "Impact" },
				{
					Kind = "Carrier",
					At = 0,
					For = 0.64,
					Ease = "Sine",
					EaseDirection = "InOut",
					Travel = 70,
					-- Barely one stud of rise over seventy, against Brand's three, because the server
					-- gives this one no gravity whatsoever -- and Brand, which has none either, already
					-- carries three. It stays well inside the four-stud hit radius, so the curve is
					-- character and not a claim about where the dart is, but it IS a disagreement with a
					-- dead-flat flight and it is written down as one rather than sold as physics.
					Arc = 1.2,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- The dot itself: an irregular blot, not the radial gradient -- a soft round glow sprite
				-- is the single most borrowed image in the genre, and an off-centre blot is ink.
				--
				-- NO SPIN. A Sprite's plane is perpendicular to the carrier's facing, so the blot is
				-- face-on to whoever it is flying at, which is the one player who has to read it, and
				-- edge-on to a bystander, who reads the trail instead. A Spin here would also be dead
				-- weight: stepLive calls followCarrier before stepSprite for anything that rides, and
				-- followCarrier assigns anchor.CFrame = carrier.CFrame outright, so a rotation applied
				-- after it is discarded on the next frame. MELEE's Spin works because MELEE does not ride.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.64,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 1.8,
					EndSize = 1.2,
					Transparency = 0.05,
					EndTransparency = 0.45,
				},
				-- Thinner than Brand's, because this is a nib and that is a thrown ember. Camera-facing,
				-- so the flight reads from every angle even though the head does not.
				--
				-- The renderer for this glyph must NOT pass Context.Follow. buildTrail takes Follow over
				-- the carrier as its anchor, and this Trail rides, so followCarrier would then drive the
				-- caster's own HumanoidRootPart along the dart's path every frame.
				{
					Kind = "Trail",
					At = 0,
					For = 0.64,
					Ride = true,
					Texture = "BrushStroke",
					Size = 1.4,
					EndSize = 0.2,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				-- The stipple. Dense rate, almost no speed, long lifetime and low drag, so the dots the
				-- dart sheds stay roughly where they were shed: the flight writes a dotted line across the
				-- arena instead of trailing smoke behind a body. This is the layer the glyph is named
				-- after and the one a target reads as "that is going to slow me".
				{
					Kind = "Emitter",
					At = 0,
					For = 0.64,
					Ride = true,
					Texture = "DustMote",
					Rate = 46,
					Speed = { -2, 2 },
					Lifetime = { 0.5, 0.9 },
					Spread = 40,
					Drag = 1.5,
					Size = 0.5,
					EndSize = 0.26,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.64,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 10,
					Brightness = 1.6,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				-- At the nib end, five studs out, which is the one point on the path that exists whatever
				-- the flight did: the server spawns the dart at SpawnOffset four. Negative speed, so the
				-- last dots are drawn back down into the page rather than dispersing.
				--
				-- No Mark anywhere in this timeline, and that is deliberate: the dart touched nothing. The
				-- burn belongs to the Hit packet CombatService emits from ApplyDamage, at the point the
				-- damage actually landed, exactly as Brand leaves its crater to Explosion.
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
					Drag = 1,
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
-- NAMED AS A GAP, and it decides the whole shape: VfxTimeline honours Context.Follow in buildTrail and in
-- no other builder -- line 419 is the only reference in the file. A Sprite, a Light, an Emitter or a Mark
-- placed on the caster is nailed to the spot the caster stood on when the packet arrived. So the sustained
-- tell is a chain of overlapping Trails on his root, which is a tell only while he moves, and the ground
-- keeps nothing but a small short print of where he armoured. The one thing this must NOT do is leave a
-- twelve-stud ring burning on the floor for four seconds: that is the grammar this game already uses for a
-- zone (Bleed nine studs, Scorch thirteen), it is in the wrong place the moment he walks, and the armour's
-- remaining time is the HUD's job through status.stoneSkin. A following aura needs the runtime to accept
-- Follow for every kind. That is not done, and it is not claimed done.
local GILDING: Timeline = {
	Intent = "Leaf is laid onto the caster and burnished down, and the gilt stays on the body until it wears",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.16,
			Layers = {
				-- Leaf drawn onto the body. Negative speed and a full sphere of spread: it comes from
				-- everywhere onto him, which is the opposite of a spell leaving a hand and the reason this
				-- reads as armouring rather than as casting.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.16,
					Texture = "DustMote",
					Rate = 80,
					Speed = { -11, -5 },
					Lifetime = { 0.18, 0.3 },
					Spread = 180,
					Drag = 2.5,
					Size = 0.4,
					EndSize = 0.05,
				},
				-- The halo, drawn out to the aura's real diameter with an overshoot so it lands rather
				-- than arrives. An illuminated figure has a gold field behind them; this is that field,
				-- and it is the same seal texture the cast uses, which is what keeps one school's visual
				-- grammar one grammar. Short on purpose: it cannot follow him, so it must be over before
				-- he has walked out of it.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.26,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 0.4,
					EndSize = 12,
					Offset = { 0, 0.4, 0 },
					Spin = 0.8,
					Transparency = 1,
					EndTransparency = 0.18,
				},
				-- The glyph's dynamic light, spent where the caster actually is rather than on the patch
				-- of ground he is about to leave.
				{
					Kind = "Light",
					At = 0,
					For = 0.3,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, 0.4, 0 },
					Range = 8,
					Brightness = 1.4,
				},
				-- Felt by the caster, who is the only person this glyph happens to.
				{ Kind = "Shake", At = 0.1, For = 0.06, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.22,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.17, For = 0.05, Voice = "Impact" },
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The burnish. The halo collapses onto the body: Quint-In barely moves, then goes all at
				-- once, which is the shape of leaf being pressed down. It does not fold to a point like
				-- the cast's seal -- it stops at 3.4 studs, on him, because it is not going anywhere.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.22,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 12,
					EndSize = 3.4,
					Offset = { 0, 0.4, 0 },
					Spin = 4.2,
					Transparency = 0.18,
					EndTransparency = 0.5,
				},
				-- Flakes coming off under the burnisher. Heavy drag and a full sphere: they go nowhere,
				-- which is what distinguishes waste from a discharge.
				{
					Kind = "Emitter",
					At = 0.08,
					For = 0.12,
					Texture = "SparkStreak",
					Offset = { 0, 0.2, 0 },
					Burst = 20,
					Speed = { 6, 14 },
					Lifetime = { 0.25, 0.5 },
					Spread = 180,
					Drag = 5,
					Squash = 0.4,
					Size = 0.5,
					EndSize = 0.06,
				},
			},
		},
		{
			-- 0.16 + 0.22 + 3.62 = 4.00, which is CombatConfig.Status.Gilding.DurationSeconds to the
			-- frame. A change to DurationSeconds that is not made here shows up as gilt that outlives the
			-- armour, which is the only lie a defensive buff can tell.
			Name = "Residue",
			Duration = 3.62,
			Layers = {
				-- Where he gilded. Small -- five and a half studs, his own footprint and a margin, not the
				-- twelve the aura claims -- and gone inside a second and a half, so it reads as the print
				-- of an act and can never be mistaken for a live area. Rule 5 wants the world to remember
				-- for a few seconds; it does not want a buff to draw a zone.
				{
					Kind = "Mark",
					At = 0,
					For = 1.4,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "SealRing",
					Size = 5.5,
					EndSize = 6.8,
					Transparency = 0.4,
					EndTransparency = 1,
				},
				-- The armour, on the body, for the whole four seconds. Seven Trails half a second apart
				-- and 0.55 long, so the gilt is continuous and never blinks out mid-buff: an opponent
				-- deciding whether to commit needs the tell present at the moment they decide, not for
				-- three flashes out of four seconds. Each one's Lifetime is its For, so the ribbon is
				-- eight studs of leaf catching the light, not a four-second banner.
				--
				-- They taper -- width 2.8 down to 1.4, transparency 0.3 up to 0.55 -- and THAT is the
				-- clock: the leaf visibly wears off, on the body, where the forty per cent is.
				--
				-- Follow says so rather than the renderer being asked to remember: these are on the caster's
				-- body, Gilding has no Carrier, and a trail on a part that never moves draws nothing at all.
				-- The renderer passes the body; the data states that it needs one, and a gate checks.
				{
					Kind = "Trail",
					Follow = true,
					At = 0,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 2.8,
					EndSize = 0.5,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Follow = true,
					At = 0.5,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 2.6,
					EndSize = 0.45,
					Transparency = 0.32,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Follow = true,
					At = 1,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 2.4,
					EndSize = 0.4,
					Transparency = 0.35,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Follow = true,
					At = 1.5,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 2.2,
					EndSize = 0.36,
					Transparency = 0.38,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Follow = true,
					At = 2,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 2,
					EndSize = 0.32,
					Transparency = 0.42,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Follow = true,
					At = 2.5,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 1.7,
					EndSize = 0.28,
					Transparency = 0.48,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					Follow = true,
					At = 3,
					For = 0.55,
					Texture = "BrushStroke",
					Size = 1.4,
					EndSize = 0.24,
					Transparency = 0.55,
					EndTransparency = 1,
				},
				-- Leaf dust still coming off for the first second, faintly, where the burnishing happened.
				-- It is what tells the eye the print on the floor was made of something.
				{
					Kind = "Emitter",
					At = 0.08,
					For = 1,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.3, 0 },
					Rate = 9,
					Speed = { 0.3, 1.4 },
					Lifetime = { 0.7, 1.3 },
					Spread = 150,
					Drag = 1.2,
					Size = 0.3,
					EndSize = 0,
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
-- Every layer that carries information reads from every angle, which is the one thing the draft before
-- this got wrong. A Sprite's plane is perpendicular to the aim, so it is authored for the caster's camera
-- and absent to anyone standing beside him -- and an ultimate cannot spend a layer on the caster's seat
-- alone. So the radial reading is two flat Marks, and the tear propagates in TWO beats rather than one
-- smooth expansion: three studs to twenty in 0.14, then twenty to thirty-six in 0.26. A ring that expands
-- is a shape; a fracture that runs outward in stages, on the page, stopping exactly where the damage
-- stops, is this game.
local RUPTURE: Timeline = {
	Intent = "The nib goes through the page and the tear runs to the edge of the damage, throwing it all up",
	Phases = {
		{
			-- Two frames, on an ultimate, and that is not timidity: the server damages in the frame it
			-- emits. A longer wind-up would promise a window to dodge in that does not exist. The window
			-- was the cast seal, which every glyph plays before this one; what this phase buys is the read
			-- -- everything is pulled DOWN before anything goes up.
			Name = "Anticipation",
			Duration = 0.07,
			Layers = {
				{
					Kind = "Emitter",
					At = 0,
					For = 0.07,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 0 },
					Rate = 120,
					Speed = { -26, -14 },
					Lifetime = { 0.1, 0.18 },
					Spread = 180,
					Drag = 3,
					Squash = 0.4,
					Size = 0.7,
					EndSize = 0.05,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.1,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, -1.6, 0 },
					Range = 8,
					Brightness = 1.8,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.3,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact", Duck = 0.5 },
				-- The tear opening, first beat: the nib goes through and the crack runs twenty studs out
				-- in two frames. Quart-Out throws it and lets it arrive.
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
				-- Second beat: it runs on to thirty-six studs, which is twice the server's Radius, so the
				-- drawn edge IS the damaged edge. Quint-Out is slower off the mark than the first beat and
				-- that gap between them is the whole difference from an expanding ring -- a fracture
				-- hesitates and goes again, a ring does not. It picks up exactly where the first left off,
				-- in size and in transparency, so there is no frame where the ground is whole.
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
				-- The launch. An emitter's default direction is its host part's up, so a narrow spread is
				-- a column: these rise at twenty-eight to fifty-six studs a second against the server's
				-- Launch of sixty, which means the flecks and the bodies leave the ground together. That
				-- agreement is the whole readability of the ability -- a player thrown fifty studs up
				-- needs the ground to have told them it was going to happen.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.12,
					Texture = "SparkStreak",
					Offset = { 0, -2.4, 0 },
					Burst = 52,
					Speed = { 28, 56 },
					Lifetime = { 0.7, 1.3 },
					Spread = 48,
					Drag = 1.6,
					Squash = 0.35,
					Size = 1,
					EndSize = 0.1,
				},
				-- And the sheet the tear pushes out sideways, hugging the floor, growing to roughly the
				-- radius it is allowed to claim. Wide spread and heavy drag: it spreads and stops.
				{
					Kind = "Emitter",
					At = 0.03,
					For = 0.2,
					Texture = "SmokeSoft",
					Offset = { 0, -2.6, 0 },
					Burst = 34,
					Speed = { 22, 40 },
					Lifetime = { 0.8, 1.5 },
					Spread = 180,
					Drag = 3.2,
					Size = 2,
					EndSize = 7,
					Transparency = 0.45,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 34,
					Brightness = 4.4,
				},
				-- "Heavy" and a page flash, which in this file are spent on the detonation and on this. An
				-- ultimate that shares a camera profile with a jab is not an ultimate.
				{ Kind = "Shake", At = 0, For = 0.14, Profile = "Heavy" },
				{ Kind = "Flash", At = 0, For = 0.16, Profile = "PageFlash" },
			},
		},
		{
			Name = "Residue",
			Duration = 2.9,
			Layers = {
				-- The tear again, holding at the size and the transparency the second beat left it, and
				-- drying over nearly three seconds. A third layer because a layer has one ramp: the two
				-- spreads and the fade are three curves, and each hands over with about 0.08 of overlap,
				-- so there is no frame in which the ground is whole again.
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
				-- The hole the nib actually made, under the caster. Two overlapping traces at different
				-- sizes and different lives, for the reason the detonation gives: one trace reads as a
				-- decal, two read as a place where something happened.
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
				{
					Kind = "Emitter",
					At = 0.05,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Offset = { 0, -2, 0 },
					Rate = 20,
					Speed = { 1.5, 4 },
					Lifetime = { 1, 1.8 },
					Spread = 60,
					Drag = 2.4,
					Size = 2.5,
					EndSize = 7,
					Transparency = 0.5,
					EndTransparency = 1,
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
-- The format can anchor exactly one kind of layer to a body it does not own: a Trail, through
-- Context.Follow, which buildTrail reads. So the live danger is carried by trails -- a curtain of burning
-- ink dragged by whoever holds the fire, reborn on every server tick, which puts the flare AT the damage
-- centre instead of next to it -- and the page keeps only what is true about the page: a seal burnt at
-- the radius while the caster is still standing in it, and the char that spreads from where it was lit.
--
-- Two honest compromises, stated because they will look like mistakes otherwise. The ticks are placed on
-- the server's clock, not 0.8 apart from a start the server does not share: the timeline spends 0.32 s
-- drawing (rule 3, nothing appears), so curtains two and three fall at 0.80 and 1.60 exactly and tick one
-- is covered by the ignition. And there is no light on the moving centre, because a Light cannot ride
-- Follow; the lights sit on the char, which is the one place the fire has certainly been.
local SCORCH: Timeline = {
	Intent = "The page under the caster catches, is carried burning, and catches again on every tick",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.16,
			Layers = {
				-- The nib set into the page. A dot of ink is where every stroke in this game begins, and it
				-- is the one wind-up in this school that is not Brand's spark inhale copied over.
				{
					Kind = "Mark",
					At = 0,
					For = 0.42,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 0.8,
					EndSize = 4.2,
					Transparency = 0.18,
					EndTransparency = 0.85,
				},
				-- The page gives: flakes lifted off the floor and pulled toward the nib. Negative speed is
				-- the same statement Brand's wind-up makes -- power gathered, not yet spent -- but it is
				-- paper that moves and not sparks, because nothing is burning yet.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.16,
					Texture = "DustMote",
					Offset = { 0, -2.4, 0 },
					Rate = 44,
					Speed = { -12, -5 },
					Lifetime = { 0.12, 0.2 },
					Spread = 175,
					Drag = 3,
					Size = 0.4,
					EndSize = 0.04,
				},
				-- Low and at the feet, so the pigment is readable from behind and from above: in a 3v3 the
				-- question "is he standing in something" is asked about somebody else's screen position.
				{
					Kind = "Light",
					At = 0.02,
					For = 0.2,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, -2, 0 },
					Range = 9,
					Brightness = 1.6,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.16,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The radius, written ONCE, on the seal texture rather than the shockwave ring: AssetIds
				-- calls SealRing "the art direction's signature image", and the boundary of an ink zone is a
				-- seal burnt into the page. Size is a diameter, so 26 is exactly the 13 studs the server
				-- damages, and Back-out overshoots outward for a tenth of a second -- a boundary that errs
				-- must send a player further back, never closer.
				--
				-- It is not held. The server re-centres on the caster every tick, so a ring left lying on
				-- the floor is a lie the moment he moves. It is true while it is being drawn, it teaches
				-- the radius once, and then it burns off; what the zone IS is on the caster, below.
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
				-- The page catching, once: a stain racing from the nib out to the line the seal drew.
				-- Circular-out spends almost all of the spread in the first third, which reads as ignition
				-- rather than as a disc being animated.
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
				-- And the char it holds as. Two layers, because stepMark lerps transparency off the SAME
				-- eased alpha as size: one layer cannot spread fast and fade slowly, and a single
				-- Circular-out stain is 90 % transparent within half a second -- which is when the zone
				-- still has two ticks to go. The handover is invisible, this starting at the transparency
				-- the spread ended on and ending at the one the Residue char begins with.
				{
					Kind = "Mark",
					At = 0.48,
					For = 1.12,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 24,
					EndSize = 25.5,
					Transparency = 0.42,
					EndTransparency = 0.5,
				},
				-- Tick one, and the only kind of layer in the format that is where the damage is: a Trail
				-- built on Context.Follow tracks a body the timeline does not own. Seven studs of curtain
				-- reaches from under the feet to over the head.
				{
					Kind = "Trail",
					-- On the caster, because the ZONE is on the caster: GlyphEffects.Scorch re-centres its
					-- thirteen-stud radius on trustedOrigin at every one of its three passes. A curtain pinned
					-- to the cast point would draw a burning boundary around empty floor while the player
					-- carried an unmarked kill radius away with them, which tells the other five people in
					-- the arena exactly the wrong thing.
					Follow = true,
					At = 0.02,
					For = 0.92,
					Texture = "BrushStroke",
					Size = 7,
					EndSize = 1.2,
					Transparency = 0.18,
					EndTransparency = 1,
				},
				-- What lifts off a burning page is the page, so flakes and not sparks. Thrown up and out,
				-- dragged hard so they stall inside the radius instead of overstating it.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "DustMote",
					Offset = { 0, -2, 0 },
					Burst = 26,
					Speed = { 8, 18 },
					Lifetime = { 0.3, 0.65 },
					Spread = 130,
					Drag = 3.5,
					Size = 0.55,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.4,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.4, 0 },
					Range = 20,
					Brightness = 2.8,
				},
				-- Once, at the ignition. The ticks are already felt: every damaged target emits its own Hit
				-- packet and Hit bleaches the page. Three zone shakes on top of nine hits in a 3v3 is a
				-- camera nobody can aim.
				{ Kind = "Shake", At = 0, For = 0.06, Profile = "Light" },
			},
		},
		{
			Name = "Impact",
			-- 1.44: the phase begins 0.32 s in and ends 0.16 s after the third and last tick at 1.60. Not
			-- 2.4 -- Params.Duration is Ticks * TickInterval, which counts an interval that never elapses,
			-- and 0.8 s of burning drawn over safe ground teaches a rhythm the server does not have.
			Duration = 1.44,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- Ticks two and three, on the server's own clock, each a fresh curtain caught by the body
				-- carrying the fire. Two curtains overlap for a moment at every handover and that doubling
				-- IS the flare: the page catching again, at the centre the server is damaging.
				{
					Kind = "Trail",
					-- On the caster, because the ZONE is on the caster: GlyphEffects.Scorch re-centres its
					-- thirteen-stud radius on trustedOrigin at every one of its three passes. A curtain pinned
					-- to the cast point would draw a burning boundary around empty floor while the player
					-- carried an unmarked kill radius away with them, which tells the other five people in
					-- the arena exactly the wrong thing.
					Follow = true,
					At = 0.48,
					For = 0.92,
					Texture = "BrushStroke",
					Size = 7,
					EndSize = 1.2,
					Transparency = 0.18,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					-- On the caster, because the ZONE is on the caster: GlyphEffects.Scorch re-centres its
					-- thirteen-stud radius on trustedOrigin at every one of its three passes. A curtain pinned
					-- to the cast point would draw a burning boundary around empty floor while the player
					-- carried an unmarked kill radius away with them, which tells the other five people in
					-- the arena exactly the wrong thing.
					Follow = true,
					At = 1.28,
					For = 0.7,
					Texture = "BrushStroke",
					Size = 7,
					EndSize = 1.2,
					Transparency = 0.18,
					EndTransparency = 1,
				},
				-- The wick under them, so the fire never goes out between ticks. Two short ones rather than
				-- one long one: a Trail's Lifetime is its own For, and a two-second ribbon holds forty studs
				-- of the caster's path around a thirteen-stud zone.
				{
					Kind = "Trail",
					-- On the caster, because the ZONE is on the caster: GlyphEffects.Scorch re-centres its
					-- thirteen-stud radius on trustedOrigin at every one of its three passes. A curtain pinned
					-- to the cast point would draw a burning boundary around empty floor while the player
					-- carried an unmarked kill radius away with them, which tells the other five people in
					-- the arena exactly the wrong thing.
					Follow = true,
					At = 0,
					For = 0.8,
					Texture = "BrushStroke",
					Size = 2.4,
					EndSize = 0.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				{
					Kind = "Trail",
					-- On the caster, because the ZONE is on the caster: GlyphEffects.Scorch re-centres its
					-- thirteen-stud radius on trustedOrigin at every one of its three passes. A curtain pinned
					-- to the cast point would draw a burning boundary around empty floor while the player
					-- carried an unmarked kill radius away with them, which tells the other five people in
					-- the arena exactly the wrong thing.
					Follow = true,
					At = 0.74,
					For = 0.8,
					Texture = "BrushStroke",
					Size = 2.4,
					EndSize = 0.4,
					Transparency = 0.3,
					EndTransparency = 1,
				},
				-- The char smoulders for the zone's life. A Light cannot ride Follow, so it is here and not
				-- on the caster: this is the one place the fire has certainly been, and a light claiming to
				-- be the centre would be wrong every time its owner moved.
				{
					Kind = "Light",
					At = 0,
					For = 1.42,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, -1.4, 0 },
					Range = 18,
					Brightness = 1.9,
				},
				-- Burning paper smokes, and the smoke is what makes the char readable from above, which is
				-- where a player deciding whether to cross is looking.
				{
					Kind = "Emitter",
					At = 0,
					For = 1.4,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Offset = { 0, -1.9, 0 },
					Rate = 14,
					Speed = { 2, 5 },
					Lifetime = { 0.9, 1.5 },
					Spread = 75,
					Drag = 2.4,
					Size = 2.2,
					EndSize = 7.5,
					Transparency = 0.55,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.6,
			Layers = {
				-- What is left is char, not a boundary: the information is gone and the burn stays, fading
				-- over seconds (rule 5). It takes over the ignition stain at the transparency that one
				-- ended on, so the page darkens once and then forgets.
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
					Drag = 1.3,
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
-- Each pool is TWO marks, and that is not decoration: stepMark drives size and transparency off the same
-- eased alpha, so the single Circular-out stain this replaced was 75 % transparent within 0.6 s of a
-- 2.3 s life while the server went on damaging those exact points at 0.8, 1.2 and 1.6. The wick lands
-- fast (Circular/Out to the full ten studs, which is twice TrailRadius, so the stain IS the hitbox) and
-- hands over at its own transparency to a burn that holds through the last tick on Quint/In and only then
-- chars away.
--
-- The offsets 0/4/8/12/16 are GlyphConfig's TrailSegments and TrailSpacing spelled out, because data
-- cannot read Params: changing either there, or passing a Scale other than 1, de-registers every stain
-- from the hitbox it draws.
--
-- Same clock compromise as Scorch: the four flares land on the server's 0.4, 0.8, 1.2 and 1.6. The fifth
-- tick is the one at zero, and its visual is the stroke being written. No Shake layer -- the dash goes
-- through grantMovement, so MovementController already shakes the camera of whoever ran it.
local LIGATURE: Timeline = {
	Intent = "One joining stroke written across the page in wet ink, which then burns where it was written",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.07,
			Layers = {
				-- Two frames. A mobility glyph that delays its own input is worse than one with no wind-up,
				-- so this is the shortest gather in the file: the nib set down, nothing more. It is also the
				-- first pool's own first ink -- the server's pool one is at offset zero -- so the wind-up
				-- and the first damage point are the same mark.
				{
					Kind = "Mark",
					At = 0,
					For = 0.26,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Size = 0.6,
					EndSize = 2.6,
					Transparency = 0.2,
					EndTransparency = 0.34,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.07,
					Texture = "DustMote",
					Offset = { 0, -2.2, 0 },
					Rate = 60,
					Speed = { -10, -4 },
					Lifetime = { 0.1, 0.16 },
					Spread = 170,
					Drag = 3,
					Size = 0.34,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Travel",
			-- The server's DashDuration. The stroke finishes a hair early, at 0.22, so the ink is down as
			-- the foot lands rather than after it.
			Duration = 0.25,
			Layers = {
				-- Sixteen studs, not twenty: the caster travels 20 but the INK ends at 16, and the ink is
				-- what burns. Two studs of arc because a joining stroke bows, and sine-in-out because a
				-- stroke is pressed, carried and lifted -- which is also what puts the nib over each pool at
				-- the start times below.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.22,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, -1.8, 0 },
					Travel = 16,
					Arc = 2,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- Wet ink. It outlives the stroke by a tenth, so the line is still glistening once the body
				-- has stopped.
				{
					Kind = "Trail",
					At = 0,
					For = 0.34,
					Ride = true,
					Texture = "BrushStroke",
					Size = 3.6,
					EndSize = 0.8,
					Transparency = 0.18,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.24,
					Ride = true,
					Texture = "SparkStreak",
					Rate = 70,
					Speed = { 2, 7 },
					Lifetime = { 0.2, 0.4 },
					Spread = 150,
					Drag = 5,
					Squash = 0.32,
					Size = 0.5,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.26,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 12,
					Brightness = 2.2,
				},
				-- The five wicks: a drop of ink lands at the size of the drop and takes the paper, which is
				-- the one thing here allowed not to be drawn -- rule 3 allows drawn, grown OR thrown. Ten
				-- studs across is twice TrailRadius, so the stain is the hitbox and not a study of it.
				{
					Kind = "Mark",
					At = 0,
					For = 0.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 0 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.18,
					EndTransparency = 0.34,
				},
				{
					Kind = "Mark",
					At = 0.07,
					For = 0.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 4 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.18,
					EndTransparency = 0.34,
				},
				{
					Kind = "Mark",
					At = 0.11,
					For = 0.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 8 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.18,
					EndTransparency = 0.34,
				},
				{
					Kind = "Mark",
					At = 0.15,
					For = 0.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 12 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.18,
					EndTransparency = 0.34,
				},
				{
					Kind = "Mark",
					At = 0.21,
					For = 0.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "InkBlot",
					Offset = { 0, 0, 16 },
					Size = 6,
					EndSize = 10,
					Transparency = 0.18,
					EndTransparency = 0.34,
				},
				-- And the five burns. Each takes over from its wick at the same transparency, holds at the
				-- hitbox's own ten studs on Quint-in through the last tick at 1.6, then chars out. This is
				-- the trace as well: five stains fading where the stroke was written, which is why the
				-- Residue carries no mark of its own -- a sixth painted over five would read as a decal.
				{
					Kind = "Mark",
					At = 0.36,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "InkBlot",
					Offset = { 0, 0, 0 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.34,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.43,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "InkBlot",
					Offset = { 0, 0, 4 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.34,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.47,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "InkBlot",
					Offset = { 0, 0, 8 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.34,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.51,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "InkBlot",
					Offset = { 0, 0, 12 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.34,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0.57,
					For = 1.62,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "InkBlot",
					Offset = { 0, 0, 16 },
					Size = 10,
					EndSize = 11.4,
					Transparency = 0.34,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Impact",
			-- 1.44, so the phase ends 0.16 s after the fifth and last tick at 1.6. The line is inert after
			-- that and nothing here outlives it except the char.
			Duration = 1.44,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- Four flares on the server's own tick times. One light at the line's midpoint with a range
				-- of 17 reaches both ends of a 16-stud stroke, which reads better and costs less than five
				-- lights arguing about which pool flared.
				{
					Kind = "Light",
					At = 0.08,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
					Brightness = 1.9,
				},
				{
					Kind = "Light",
					At = 0.48,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
					Brightness = 1.9,
				},
				{
					Kind = "Light",
					At = 0.88,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
					Brightness = 1.9,
				},
				{
					Kind = "Light",
					At = 1.28,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.6, 8 },
					Range = 17,
					Brightness = 1.9,
				},
				-- Embers at the near end of the line, where the stroke began and the paper has burnt
				-- longest.
				{
					Kind = "Emitter",
					At = 0,
					For = 1.4,
					Texture = "SparkStreak",
					Offset = { 0, -2, 4 },
					Rate = 20,
					Speed = { 5, 12 },
					Lifetime = { 0.35, 0.7 },
					Spread = 110,
					Drag = 3,
					Squash = 0.35,
					Size = 0.55,
					EndSize = 0,
				},
				-- And the page itself coming off the far end: flakes, not a second spark fountain. Two
				-- points four and twelve studs along make the whole line read as alight without one emitter
				-- per pool.
				{
					Kind = "Emitter",
					At = 0,
					For = 1.4,
					Texture = "DustMote",
					Offset = { 0, -2, 12 },
					Rate = 18,
					Speed = { 3, 9 },
					Lifetime = { 0.4, 0.8 },
					Spread = 120,
					Drag = 2.6,
					Size = 0.4,
					EndSize = 0,
				},
				-- Burning paper smokes. It is what makes the line visible from above, which is where a
				-- player about to cross it is looking.
				{
					Kind = "Emitter",
					At = 0.04,
					For = 1.36,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Offset = { 0, -1.8, 8 },
					Rate = 15,
					Speed = { 1.5, 4 },
					Lifetime = { 0.8, 1.4 },
					Spread = 80,
					Drag = 2.4,
					Size = 1.8,
					EndSize = 6,
					Transparency = 0.55,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.3,
			Layers = {
				-- Ash off a cooling line, drifting rather than rising: the fire is out and the page is not.
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
					Drag = 1.3,
					Size = 0.32,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Offset = { 0, -1.8, 8 },
					Rate = 7,
					Speed = { 1, 3 },
					Lifetime = { 0.9, 1.5 },
					Spread = 90,
					Drag = 2,
					Size = 2,
					EndSize = 6.5,
					Transparency = 0.62,
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
local BLOT: Timeline = {
	Intent = "An overloaded nib drops a blot too heavy to hold, thrown overhand and arcing down the page",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.2,
			Layers = {
				-- Ink drawn up into the hand in clots, not sparks: this is the one glyph whose wind-up has
				-- to read as MASS gathering rather than as heat.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.2,
					Texture = "InkBlot",
					Offset = { 0, 0.9, 2.4 },
					Rate = 52,
					Speed = { -17, -9 },
					Lifetime = { 0.12, 0.22 },
					Spread = 180,
					Drag = 3,
					Size = 1.5,
					EndSize = 0.2,
					Transparency = 0.08,
					EndTransparency = 0.9,
				},
				-- The page gives: flakes lifted off the floor by what is being pulled out of it. Nothing
				-- else in the roster takes anything from the world to cast, and this one costs fifty.
				{
					Kind = "Emitter",
					At = 0.03,
					For = 0.17,
					Texture = "DustMote",
					Offset = { 0, -2.4, 0 },
					Rate = 28,
					Speed = { 3, 7 },
					Lifetime = { 0.3, 0.6 },
					Spread = 55,
					Drag = 2,
					Size = 0.42,
					EndSize = 0.08,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.24,
					Ease = "Quad",
					EaseDirection = "In",
					Offset = { 0, 0.9, 2.4 },
					Range = 11,
					Brightness = 3,
				},
				{ Kind = "Shake", At = 0.13, For = 0.07, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.08,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- Ink spattered off the hand, not a spark burst: an overloaded nib throws matter, and this
				-- is the same substance the clot is made of two frames later. It is also what separates the
				-- school's most expensive release from its cheapest, which shared one burst until now.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.06,
					Texture = "InkBlot",
					Offset = { 0, 0.9, 2.4 },
					Burst = 24,
					Speed = { 18, 34 },
					Lifetime = { 0.22, 0.45 },
					Spread = 40,
					Drag = 3,
					Size = 1.2,
					EndSize = 0.15,
					Transparency = 0.06,
					EndTransparency = 0.9,
				},
				-- The arm's stroke, thick and dry at both ends. It is the release, so it outlives the phase
				-- and dies while the body is already climbing.
				{
					Kind = "Beam",
					At = 0,
					For = 0.18,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Offset = { 0, 0.7, 2.4 },
					Size = 2.6,
					EndSize = 0,
					Transparency = 0.16,
					EndTransparency = 1,
				},
				-- Brand leaves nothing on the ground and says why: it never touched it. Blot leaves one
				-- small stain at the caster's feet, and that is not a contradiction -- an overloaded nib
				-- drips. It is HERE and not in the Residue phase, which does not begin until the flight is
				-- over: a drip that fades in 1.2 s after the throw, at the same instant as a detonation 66
				-- studs away, is two events wearing one timestamp. This is also the only lasting sign of
				-- where an ultimate was thrown from.
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
				-- The throw, felt. Heavier than the wind-up's Cast and far lighter than the detonation's
				-- Heavy, so the three escalate instead of competing.
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Travel",
			Duration = 0.92,
			Layers = {
				-- Five studs forward is the server's SpawnOffset; four up is the arc's seam, split (see the
				-- block comment). Spin makes the clot tumble: every rider takes the carrier's whole CFrame,
				-- so one field turns four layers.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.92,
					Ease = "Sine",
					EaseDirection = "InOut",
					Offset = { 0, 4, 5 },
					Travel = 66,
					Arc = 20,
					Spin = 2.2,
				},
				-- After the carrier, so it exists when the tail starts riding it.
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Tail", Ride = true },
				-- The body. A dense clump of ink billets with almost no speed of its own, so it holds
				-- together as a ragged mass instead of resolving into a ball.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.92,
					Ride = true,
					Texture = "InkBlot",
					Rate = 66,
					Speed = { 0, 2 },
					Lifetime = { 0.18, 0.32 },
					Spread = 180,
					Drag = 1.5,
					Size = 4.6,
					EndSize = 6.4,
					Transparency = 0.05,
					EndTransparency = 0.85,
				},
				-- Twice the width of Brand's, because the difference between the school's first glyph and
				-- its last should be legible in the sky from the other end of the arena.
				{
					Kind = "Trail",
					At = 0,
					For = 0.92,
					Ride = true,
					Texture = "BrushStroke",
					Size = 4.6,
					EndSize = 1,
					Transparency = 0.16,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.92,
					Ride = true,
					Texture = "SmokeSoft",
					Rate = 30,
					Speed = { -4, 2 },
					Lifetime = { 0.5, 1 },
					Spread = 70,
					Drag = 2,
					Size = 1.8,
					EndSize = 6,
					Transparency = 0.45,
					EndTransparency = 1,
				},
				-- The brightest travelling light in the game. A 45-damage guard-breaker crossing the arena
				-- should change the light on the people it crosses over.
				{
					Kind = "Light",
					At = 0,
					For = 0.92,
					Ride = true,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 24,
					Brightness = 3.6,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.5,
			Layers = {
				-- What hangs where the throw happened. The drip itself was laid at the cast and is still
				-- fading under this.
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
					Drag = 1.2,
					Size = 0.34,
					EndSize = 0,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "SmokeSoft",
					Offset = { 0, -1.8, 0 },
					Rate = 6,
					Speed = { 0.8, 2.4 },
					Lifetime = { 0.9, 1.4 },
					Spread = 90,
					Drag = 2,
					Size = 1.6,
					EndSize = 5,
					Transparency = 0.62,
					EndTransparency = 1,
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
-- Renderer contract: Origin is the muzzle (packet Origin advanced by Params.SpawnOffset, which is what
-- GlyphEffects.Strike documents), Scale is Params.Range / 70 -- the server sends the length the ray
-- ACTUALLY reached, past the body it damaged and up to the wall that stopped it, which is correct for a
-- strikethrough -- and Follow must be nil. A riding Trail with Follow set would move the caster's own root
-- part to the carrier: buildTrail anchors a Trail on Context.Follow when Follow exists, and followCarrier
-- writes the anchor's CFrame. Brand is played with Follow nil for exactly this reason.
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
			Duration = 0.09,
			Layers = {
				-- Ink drawn to the nib. A Burst and not a Rate: Rate is particles per second and
				-- stepEmitter disables it at 85% of For, so a rate of fifty-two over ninety milliseconds
				-- would have put FOUR particles on the screen. One throw of sixteen, with a lifetime that
				-- lands them on the hand at the frame the stroke leaves, is four times the ink for the
				-- same layer and stops dead when the gather is over.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.16,
					Texture = "SparkStreak",
					Offset = { 0, 0.4, 0 },
					Burst = 16,
					Speed = { -13, -6 },
					Lifetime = { 0.1, 0.15 },
					Spread = 180,
					Drag = 3,
					Squash = 0.35,
					Size = 0.45,
					EndSize = 0.04,
				},
				-- A light always decays in this runtime (stepLight writes Brightness * (1 - alpha)), and
				-- the easing shapes the decay rather than the rise. Exponential-in holds it at full and
				-- then drops it off a cliff on the frame the stroke leaves: the nib is charged, then spent.
				{
					Kind = "Light",
					At = 0,
					For = 0.13,
					Ease = "Exponential",
					EaseDirection = "In",
					Offset = { 0, 0.4, 0 },
					Range = 6,
					Brightness = 2,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.12,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.07, For = 0.05, Voice = "Impact" },
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The crack of the nib on the page. Short and sharp rather than heavy: this is a
				-- four-second basic, and it must never feel like the ultimate four inputs away.
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
				-- Seventy studs in eighty milliseconds. Quint-out spends three quarters of the distance
				-- in the first twenty, then settles into the far end, which is a nib slammed down and
				-- stopped, not a body travelling.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.08,
					Ease = "Quint",
					EaseDirection = "Out",
					Travel = 70,
				},
				-- The line itself. A Trail is the only layer whose length is independent of its width,
				-- which is the only reason a seventy-stud hairline is possible at all: a Beam's length is
				-- eight times its width by construction, so a Beam this long would be nine studs thick.
				--
				-- EndTransparency is 0.42 and NOT 1, and there is no EndSize, because of how this runtime
				-- draws a Trail: buildTrail writes Transparency once as a NumberSequence, which Roblox
				-- samples along the trail's LENGTH -- 0 at the newest point, 1 at the oldest -- and there
				-- is no stepTrail at all. An EndTransparency of 1 therefore erases the line from the hand
				-- end and leaves a bright head fading behind it, which is what Brand and Dash correctly
				-- use it for and is the most generic projectile visual on the platform. 0.1 to 0.42 keeps
				-- all seventy studs legible with the oldest end the drier one, which is a stroke. EndSize
				-- is gone because buildTrail reads only Size: a Trail's width cannot change here, and data
				-- that looks load-bearing and is not is worse than no data.
				{
					Kind = "Trail",
					At = 0,
					For = 0.42,
					Ride = true,
					Texture = "BrushStroke",
					Size = 1.6,
					Transparency = 0.1,
					EndTransparency = 0.42,
				},
				-- Rides the nib, so the page is lit along the line as the line is laid, and is left
				-- burning at the far end when the carrier goes back to the pool and followCarrier stops
				-- finding it.
				{
					Kind = "Light",
					At = 0,
					For = 0.26,
					Ride = true,
					Ease = "Quart",
					EaseDirection = "Out",
					Range = 15,
					Brightness = 3.4,
				},
				-- Scheduled at four fifths of the flight, so activate() builds it where the body IS at
				-- that moment -- the far end -- rather than where the cast began. This is the ink flicked
				-- off the end of a stroke, and it is what tells the player where the line stopped. Spread
				-- 40 and not 130: a near-spherical burst is a sparkle, which any game has, and ink leaving
				-- a nib goes where the nib was going. For is 0.36 because the layer's release destroys
				-- every particle still in the air, so a For of 0.07 under a lifetime of 0.34 showed a
				-- fifth of the throw.
				{
					Kind = "Emitter",
					At = 0.065,
					For = 0.36,
					Ride = true,
					Texture = "SparkStreak",
					Burst = 22,
					Speed = { 11, 26 },
					Lifetime = { 0.16, 0.34 },
					Spread = 40,
					Drag = 4.5,
					Squash = 0.26,
					Size = 0.5,
					EndSize = 0,
				},
				-- Backsplash at the hand. A hitscan with nothing at its origin has no author: an opponent
				-- has to be able to tell WHO ruled the line, from the side, in one frame.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.58,
					Texture = "SmokeSoft",
					Offset = { 0, 0.3, 0 },
					Burst = 8,
					Speed = { 3, 9 },
					Lifetime = { 0.3, 0.55 },
					Spread = 70,
					Drag = 3.5,
					Size = 0.7,
					EndSize = 2.4,
					Transparency = 0.5,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.7,
			Layers = {
				-- The page keeps the rature. A Mark is square by construction, so this is one dash under
				-- the middle of the line rather than a seventy-stud rule on the floor -- which is correct
				-- as well as forced: a line that long painted on the ground would read as a wall. Offset
				-- is scaled with everything else, so thirty-five is always half the length the ray
				-- actually reached.
				{
					Kind = "Mark",
					At = 0,
					For = 1.5,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 6.5,
					EndSize = 7.6,
					Offset = { 0, 0, 35 },
					Transparency = 0.42,
					EndTransparency = 1,
				},
				-- What hangs in the air where the line was. Not at the hand: the event happened along the
				-- ray, and residue at the caster would say the spell was about him. The lifetime is short
				-- against For on purpose -- a Rate emitter cannot outlive its own layer, so what the
				-- release cuts has to be a handful of motes already most of the way faded.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.6, 35 },
					Rate = 11,
					Speed = { 0.4, 1.8 },
					Lifetime = { 0.45, 0.62 },
					Spread = 175,
					Drag = 1.3,
					Size = 0.32,
					EndSize = 0,
					Transparency = 0.5,
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
-- Renderer contract: Origin is the departure (the packet's own Origin), Scale is Params.Range / 18 -- the
-- distance the server actually validated against walls and ground, so Offset {0, y, 18} is exactly the
-- landing -- and Follow must be nil, for the same reason as Strike.
local CARET: Timeline = {
	Intent = "The body is struck out where it stood and inserted where it lands, the caret drawn between",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.08,
			Layers = {
				-- Ink pulled off the page. Negative speed is the departure: he is not spending power
				-- here, he is being removed. A Burst, for the reason Strike's gather is one: a rate of
				-- sixty-four over eighty milliseconds is five particles.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.18,
					Texture = "SparkStreak",
					Offset = { 0, 0.6, 0 },
					Burst = 20,
					Speed = { -15, -7 },
					Lifetime = { 0.1, 0.16 },
					Spread = 180,
					Drag = 3.5,
					Squash = 0.4,
					Size = 0.5,
					EndSize = 0.04,
				},
				-- The strike-out over the silhouette, drawn where he no longer is. Quint-in barely moves
				-- and then shuts all at once, which is the shape of a line being closed rather than of a
				-- shape shrinking.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.16,
					Ease = "Quint",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 5.4,
					EndSize = 0.5,
					Offset = { 0, 0.6, 0 },
					Spin = -4.2,
					Transparency = 0.28,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.12,
					Ease = "Exponential",
					EaseDirection = "In",
					Offset = { 0, 0.6, 0 },
					Range = 8,
					Brightness = 2.4,
				},
				-- The push-off profile, not the cast one: this is the mobility button, and it should feel
				-- like the dodge it competes with.
				{ Kind = "Shake", At = 0.02, For = 0.05, Profile = "Dash" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.1,
			Layers = {
				-- The landing, at the end of the phase in which it lands: this glyph has no Impact phase.
				{ Kind = "Sound", At = 0.05, For = 0.05, Voice = "Impact" },
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- Travel is the glyph's Range and Arc is the caret's rise. The mark is not drawn ON the
				-- path; the path IS the mark.
				{
					Kind = "Carrier",
					At = 0,
					For = 0.07,
					Ease = "Sine",
					EaseDirection = "InOut",
					Travel = 18,
					Arc = 5,
				},
				-- 0.55 rather than 1, and no EndSize: see the note on Strike's trail. The caret's rise
				-- and fall is the whole point of this layer, and a gradient running to invisible along
				-- the length would have erased the half of it nearest the departure.
				{
					Kind = "Trail",
					At = 0,
					For = 0.5,
					Ride = true,
					Texture = "BrushStroke",
					Size = 1.5,
					Transparency = 0.1,
					EndTransparency = 0.55,
				},
				-- The page closing over the gap. Inward, at the departure, and the only inward-moving
				-- smoke in the roster: it is what a hole in a sheet does.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.58,
					Texture = "SmokeSoft",
					Offset = { 0, 0.6, 0 },
					Burst = 16,
					Speed = { -7, -2 },
					Lifetime = { 0.3, 0.55 },
					Spread = 180,
					Drag = 4,
					Size = 1.5,
					EndSize = 0.25,
					Transparency = 0.42,
					EndTransparency = 1,
				},
				-- The insertion mark, opening at the landing. Back-out overshoots and settles, so it lands
				-- rather than arrives; it is the exact inverse of the stroke that closed at the departure,
				-- and it is the layer that answers "where is he now".
				{
					Kind = "Sprite",
					At = 0.06,
					For = 0.24,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.5,
					EndSize = 5,
					Offset = { 0, 0.6, 18 },
					Spin = 3.6,
					Transparency = 0.22,
					EndTransparency = 1,
				},
				-- Ink thrown forward by the body being inserted. Spread 55, not 150: a spherical burst at
				-- the far end is the teleport sparkle every blink in the catalogue has, and a fan along
				-- the caret's own direction says which end this is a second time.
				{
					Kind = "Emitter",
					At = 0.06,
					For = 0.36,
					Texture = "SparkStreak",
					Offset = { 0, 0.6, 18 },
					Burst = 20,
					Speed = { 9, 22 },
					Lifetime = { 0.16, 0.34 },
					Spread = 55,
					Drag = 4,
					Squash = 0.3,
					Size = 0.5,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0.05,
					For = 0.3,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0.6, 18 },
					Range = 13,
					Brightness = 3.2,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 0.9,
			Layers = {
				-- Where he was. Smaller and fainter than where he went, because the asymmetry is the
				-- information: an opponent reading the floor a second later still knows the direction.
				{
					Kind = "Mark",
					At = 0,
					For = 1.3,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 2.8,
					EndSize = 3.6,
					Transparency = 0.48,
					EndTransparency = 1,
				},
				{
					Kind = "Mark",
					At = 0,
					For = 1.3,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 3.4,
					EndSize = 4.4,
					Offset = { 0, 0, 18 },
					Transparency = 0.4,
					EndTransparency = 1,
				},
				-- The i-frame window, made visible, and the arithmetic is the whole layer. The server
				-- grants Params.IFrameSeconds = 0.4 on the frame it emits; this phase begins 0.18 in
				-- (0.08 of Anticipation plus 0.10 of Cast); 0.40 - 0.18 = 0.22. A Burst with a lifetime
				-- that ends inside For, so every mote is born at the arrival and dies of old age on the
				-- exact frame he becomes hittable -- rather than being destroyed by the layer's release,
				-- which is what a For under the lifetime actually does. If GlyphConfig's IFrameSeconds
				-- moves, or either phase ahead of this one changes length, this number moves with them.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.22,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 1.2, 18 },
					Burst = 20,
					Speed = { 0.5, 2.2 },
					Lifetime = { 0.18, 0.22 },
					Spread = 180,
					Drag = 1.6,
					Size = 0.3,
					EndSize = 0,
					Transparency = 0.4,
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
-- Params.Offset studs ahead of the caster -- no forward offset here. Scale is Params.Radius / 12, so the
-- nominal diameter of twenty-four is the zone's real footprint. Follow must be nil.
local WATERMARK: Timeline = {
	Intent = "The mould comes down on the page four times, and the paper keeps the impression",
	Phases = {
		{
			Name = "Impact",
			-- The last tick (2.1) plus the press it fires. Not the packet's Duration: see the header.
			Duration = 2.34,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- The watermark coming up in the light. Circular-out spreads to the rim fast and then
				-- settles, and the transparency runs the WRONG way on purpose -- from almost invisible to
				-- half -- because a watermark does not arrive, it becomes visible.
				{
					Kind = "Mark",
					At = 0,
					For = 0.6,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "PaperGrain",
					Size = 7,
					EndSize = 24,
					Transparency = 0.95,
					EndTransparency = 0.46,
				},
				-- Held for exactly as long as the zone can still hurt somebody, barely moving, so the
				-- footprint answers "where can I not stand" for that long and not one frame longer. It
				-- takes over on the frame the first mark ends and hands off to the residue blot on the
				-- frame it ends, so no two PaperGrain marks are ever coplanar and nothing appears.
				{
					Kind = "Mark",
					At = 0.55,
					For = 1.79,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "PaperGrain",
					Size = 24,
					EndSize = 25.5,
					Transparency = 0.46,
					EndTransparency = 0.92,
				},
				-- Press one. Under the floor: the sheet lit from behind.
				{
					Kind = "Light",
					At = 0,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 22,
					Brightness = 3.6,
				},
				-- The page's own fibres jumping off the sheet under the mould. DustMote rather than
				-- sparks: this is paper being compressed, not something burning. For covers the whole
				-- lifetime because the layer's release destroys every particle still in the air.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.5,
					Texture = "DustMote",
					Burst = 26,
					Speed = { 16, 26 },
					Lifetime = { 0.35, 0.5 },
					Spread = 170,
					Drag = 1.4,
					Squash = 0.5,
					Size = 0.4,
					EndSize = 0,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Light" },
				-- Press two.
				{
					Kind = "Light",
					At = 0.7,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 22,
					Brightness = 3.6,
				},
				{
					Kind = "Emitter",
					At = 0.7,
					For = 0.5,
					Texture = "DustMote",
					Burst = 26,
					Speed = { 16, 26 },
					Lifetime = { 0.35, 0.5 },
					Spread = 170,
					Drag = 1.4,
					Squash = 0.5,
					Size = 0.4,
					EndSize = 0,
				},
				{ Kind = "Shake", At = 0.7, For = 0.05, Profile = "Light" },
				-- Press three.
				{
					Kind = "Light",
					At = 1.4,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 22,
					Brightness = 3.6,
				},
				{
					Kind = "Emitter",
					At = 1.4,
					For = 0.5,
					Texture = "DustMote",
					Burst = 26,
					Speed = { 16, 26 },
					Lifetime = { 0.35, 0.5 },
					Spread = 170,
					Drag = 1.4,
					Squash = 0.5,
					Size = 0.4,
					EndSize = 0,
				},
				{ Kind = "Shake", At = 1.4, For = 0.05, Profile = "Light" },
				-- Press four.
				{
					Kind = "Light",
					At = 2.1,
					For = 0.24,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 22,
					Brightness = 3.6,
				},
				{
					Kind = "Emitter",
					At = 2.1,
					For = 0.5,
					Texture = "DustMote",
					Burst = 26,
					Speed = { 16, 26 },
					Lifetime = { 0.35, 0.5 },
					Spread = 170,
					Drag = 1.4,
					Squash = 0.5,
					Size = 0.4,
					EndSize = 0,
				},
				{ Kind = "Shake", At = 2.1, For = 0.05, Profile = "Light" },
			},
		},
		{
			Name = "Residue",
			Duration = 2,
			Layers = {
				-- What the page keeps of four presses. Clearly smaller than the footprint it replaces --
				-- thirteen studs against twenty-four -- because the moment this takes over is the moment
				-- the zone stopped being dangerous, and a residue the size of the zone would go on
				-- claiming the ground.
				{
					Kind = "Mark",
					At = 0,
					For = 1.9,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 13,
					EndSize = 17,
					Transparency = 0.42,
					EndTransparency = 1,
				},
				-- The motes that hang after a zone ends, which is the thing this texture exists for.
				{
					Kind = "Emitter",
					At = 0,
					For = 1.1,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Rate = 10,
					Speed = { 0.4, 2 },
					Lifetime = { 0.55, 0.85 },
					Spread = 180,
					Drag = 1.3,
					Size = 0.42,
					EndSize = 0,
					Transparency = 0.5,
					EndTransparency = 1,
				},
				-- The light leaves the paper rather than being switched off, and it leaves from the same
				-- side it came from: the last thing the zone does must not contradict the four presses.
				{
					Kind = "Light",
					At = 0,
					For = 0.5,
					Ease = "Sine",
					EaseDirection = "Out",
					Offset = { 0, -1.2, 0 },
					Range = 14,
					Brightness = 1.2,
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
-- Renderer contract: Origin is the muzzle (packet Origin advanced by Params.SpawnOffset), Direction the
-- packet's, Scale the distance from the muzzle to Targets[1] divided by 60 -- the glyph's Range -- because
-- Params.Range is the distance to the WALL: geometryStop re-casts past every character, so the server's
-- Range measures the ray's end and not the body it crossed. Fall back to Params.Range / 60 when the cast
-- struck nobody, and clamp at the bottom to about 0.6 so a point-blank ultimate is still an ultimate.
-- Follow must be nil.
local COLOPHON: Timeline = {
	Intent = "The page is signed off: a doubled seal, one broad stroke ruled through a body, and the mark kept",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.22,
			Layers = {
				-- The second seal. Transparency runs from almost gone to nearly solid: it is drawn, and
				-- the negative spin turns it against the Cast seal that is still closing, so two seals at
				-- once are unmistakably two seals rather than one that stuttered.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.26,
					Ease = "Back",
					EaseDirection = "Out",
					Texture = "SealRing",
					Size = 0.3,
					EndSize = 6.2,
					Offset = { 0, 0.5, 0.6 },
					Spin = -2.4,
					Transparency = 0.9,
					EndTransparency = 0.14,
				},
				-- Everything the stroke will spend, gathered first. This one stays a Rate rather than a
				-- Burst because the wind-up is long enough for a stream to read -- ninety a second over
				-- the 0.204 it emits for is eighteen particles -- and a stream is what "gathering" looks
				-- like. The lifetime is short so the release at 0.24 cuts two motes and not the stream.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.24,
					Texture = "SparkStreak",
					Offset = { 0, 0.5, 0.6 },
					Rate = 90,
					Speed = { -19, -9 },
					Lifetime = { 0.1, 0.15 },
					Spread = 180,
					Drag = 3,
					Squash = 0.32,
					Size = 0.65,
					EndSize = 0.05,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.3,
					Ease = "Exponential",
					EaseDirection = "In",
					Offset = { 0, 0.5, 0.6 },
					Range = 12,
					Brightness = 3,
				},
				-- Late in the wind-up: the weight of the thing before it leaves, not the impact of it
				-- landing. The impact has its own, and it is Heavy.
				{ Kind = "Shake", At = 0.15, For = 0.07, Profile = "Cast" },
			},
		},
		{
			Name = "Cast",
			Duration = 0.16,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Body" },
				-- The pressure. Size is width AND an eighth of the length: 7.5 draws a sixty-stud stroke
				-- seven and a half studs wide at its root, tapering to a third of that at the tip, which
				-- is the wedge a pen makes when it is pressed and lifted. buildBeam fixes the length from
				-- Size at build, so EndSize thins the stroke without shortening it.
				{
					Kind = "Beam",
					At = 0,
					For = 0.16,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 7.5,
					EndSize = 0.5,
					Offset = { 0, 0.5, 0 },
					Transparency = 0.06,
					EndTransparency = 0.5,
				},
				-- The second pass, drier and slower, over the same line. It is what makes the stroke read
				-- as ink on a page instead of as a beam switching off.
				{
					Kind = "Beam",
					At = 0.04,
					For = 0.5,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 7.5,
					EndSize = 0.06,
					Offset = { 0, 0.5, 0 },
					Transparency = 0.45,
					EndTransparency = 1,
				},
				-- Spray off the stroke where it crosses the body. Spread 60 and For over the lifetime: a
				-- 150-degree burst cut at 0.09 was a sparkle that never spread.
				{
					Kind = "Emitter",
					At = 0.03,
					For = 0.45,
					Texture = "SparkStreak",
					Offset = { 0, 0.5, 60 },
					Burst = 30,
					Speed = { 14, 34 },
					Lifetime = { 0.2, 0.42 },
					Spread = 60,
					Drag = 4,
					Squash = 0.26,
					Size = 0.8,
					EndSize = 0,
				},
				{
					Kind = "Light",
					At = 0.02,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0.5, 60 },
					Range = 30,
					Brightness = 5,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.2,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact", Duck = 0.5 },
				-- activate() places a Shake at the play's Origin, not at a layer's Offset, so this is
				-- felt from the muzzle rather than from the body it struck. That is the right end anyway:
				-- the caster should feel what fifty-five ink bought. Every link's own weight arrives with
				-- its own Hit packet, correctly placed.
				{ Kind = "Shake", At = 0, For = 0.14, Profile = "Heavy" },
				-- The crossing stroke. Opens outward across the first, turning the other way, a third of
				-- a stud nearer the camera so two BrushStroke decals are never coplanar. Two strokes
				-- crossed on a body is a signature; the smoke puff this replaces was the Hit packet's job.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.34,
					Ease = "Quart",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 0.6,
					EndSize = 5.6,
					Offset = { 0, 0.62, 59.6 },
					Spin = -5.2,
					Transparency = 0.2,
					EndTransparency = 1,
				},
				-- The colophon written ON the victim, and held for six tenths of a second, which is
				-- Params.StunSeconds. It hangs there for exactly as long as he cannot move, so the mark
				-- leaving is the frame he can act again -- the longest lockout in the game, made readable
				-- to the person who has to punish it. COLOPHON_LINK carries the same layer, because the
				-- server stuns every link and not just the first.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "BrushStroke",
					Size = 4.4,
					EndSize = 5.2,
					Offset = { 0, 0.5, 60 },
					Spin = 0.7,
					Transparency = 0.3,
					EndTransparency = 1,
				},
			},
		},
		{
			Name = "Residue",
			Duration = 1.8,
			Layers = {
				-- The page torn under the body. Longer and wider than a plain hit's, because this is the
				-- heaviest single thing that happens to a patch of this floor.
				{
					Kind = "Mark",
					At = 0,
					For = 1.7,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "CrackWeb",
					Size = 8.5,
					EndSize = 10.5,
					Offset = { 0, 0, 60 },
					Transparency = 0.3,
					EndTransparency = 1,
				},
				-- The stroke's own shadow, under the middle of the line. With COLOPHON_LINK's copy at each
				-- of the two jumps, the floor ends up carrying the whole chain as one broken stroke: for
				-- nearly two seconds afterwards, anyone can read where the ultimate went and who it passed
				-- through. That is the colophon -- the page is signed.
				{
					Kind = "Mark",
					At = 0,
					For = 1.6,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 13,
					EndSize = 15,
					Offset = { 0, 0, 30 },
					Transparency = 0.38,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0.05,
					For = 1.2,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.5, 60 },
					Rate = 10,
					Speed = { 0.4, 2.2 },
					Lifetime = { 0.6, 0.85 },
					Spread = 170,
					Size = 0.42,
					EndSize = 0,
					Transparency = 0.5,
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
-- Renderer contract: one play per jump, Origin the previous link, Direction toward this one, Scale the gap
-- divided by 26 -- Params.ChainRadius, the longest jump the server will make -- clamped to about
-- [0.35, 1.05] so two players standing on each other still get a visible arc, and staggered by about eight
-- hundredths of a second per link so the whole chain lands inside a quarter of a second. Follow nil.
local COLOPHON_LINK: Timeline = {
	Intent = "The signature does not lift: it collects on one body and rules a stroke to the next",
	Phases = {
		{
			Name = "Anticipation",
			Duration = 0.05,
			Layers = {
				-- Fifty milliseconds of the arc gathering on the victim before it leaves him. The shortest
				-- anticipation in the game, and still the difference between a chain that flows and two
				-- bolts that happen to share a colour. A Burst: a rate of seventy over fifty milliseconds
				-- would have emitted three particles.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.11,
					Texture = "SparkStreak",
					Offset = { 0, 0.5, 0 },
					Burst = 18,
					Speed = { -14, -6 },
					Lifetime = { 0.06, 0.1 },
					Spread = 180,
					Drag = 3,
					Squash = 0.34,
					Size = 0.5,
					EndSize = 0.04,
				},
			},
		},
		{
			Name = "Cast",
			Duration = 0.12,
			Layers = {
				-- 3.25 is twenty-six studs long and three and a quarter wide: the same eight-to-one wedge
				-- as the first stroke, at the scale of a jump instead of a hitscan.
				{
					Kind = "Beam",
					At = 0,
					For = 0.14,
					Ease = "Quint",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 3.25,
					EndSize = 0.3,
					Offset = { 0, 0.5, 0 },
					Transparency = 0.08,
					EndTransparency = 0.55,
				},
				{
					Kind = "Beam",
					At = 0.03,
					For = 0.4,
					Ease = "Circular",
					EaseDirection = "Out",
					Texture = "BrushStroke",
					Size = 3.25,
					EndSize = 0.05,
					Offset = { 0, 0.5, 0 },
					Transparency = 0.5,
					EndTransparency = 1,
				},
				{
					Kind = "Light",
					At = 0,
					For = 0.26,
					Ease = "Quart",
					EaseDirection = "Out",
					Offset = { 0, 0.5, 26 },
					Range = 22,
					Brightness = 4,
				},
			},
		},
		{
			Name = "Impact",
			Duration = 0.14,
			Layers = {
				{ Kind = "Sound", At = 0, For = 0.05, Voice = "Impact" },
				-- Spray along the arc, not a sphere at the end of it, and long enough to actually spread.
				{
					Kind = "Emitter",
					At = 0,
					For = 0.38,
					Texture = "SparkStreak",
					Offset = { 0, 0.5, 26 },
					Burst = 22,
					Speed = { 12, 28 },
					Lifetime = { 0.18, 0.36 },
					Spread = 55,
					Drag = 4,
					Squash = 0.28,
					Size = 0.6,
					EndSize = 0,
				},
				-- Melee's profile, not Heavy: the link is felt, and the ultimate's Heavy has already fired
				-- once from the first stroke. Three Heavy shakes inside a quarter second would be a camera
				-- nobody can read, on mobile especially.
				{ Kind = "Shake", At = 0, For = 0.06, Profile = "Melee" },
				-- The same held mark the first stroke writes, for the same six tenths, because the server
				-- stuns EVERY link for Params.StunSeconds and not only the first. Without this, two of the
				-- three bodies are locked out of the game for six tenths of a second with nothing on them
				-- saying so, which is exactly the information a teammate needs to convert the ultimate.
				{
					Kind = "Sprite",
					At = 0,
					For = 0.6,
					Ease = "Sine",
					EaseDirection = "InOut",
					Texture = "BrushStroke",
					Size = 3.6,
					EndSize = 4.4,
					Offset = { 0, 0.5, 26 },
					Spin = 0.7,
					Transparency = 0.3,
					EndTransparency = 1,
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
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "InkBlot",
					Size = 5,
					EndSize = 6.4,
					Offset = { 0, 0, 26 },
					Transparency = 0.34,
					EndTransparency = 1,
				},
				-- This segment of the signature, on the floor. Two of these plus the first stroke's are
				-- the whole path, kept for a second and a half.
				{
					Kind = "Mark",
					At = 0,
					For = 1.4,
					Ease = "Sine",
					EaseDirection = "In",
					Texture = "BrushStroke",
					Size = 8,
					EndSize = 9.4,
					Offset = { 0, 0, 13 },
					Transparency = 0.4,
					EndTransparency = 1,
				},
				{
					Kind = "Emitter",
					At = 0,
					For = 0.9,
					Ease = "Sine",
					EaseDirection = "Out",
					Texture = "DustMote",
					Offset = { 0, 0.5, 26 },
					Rate = 9,
					Speed = { 0.4, 2 },
					Lifetime = { 0.45, 0.62 },
					Spread = 170,
					Drag = 1.3,
					Size = 0.36,
					EndSize = 0,
					Transparency = 0.5,
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

VfxTimelineConfig.Timelines = {
	Cast = CAST,
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
} :: { [string]: Timeline }

-- Phases always play in this order, whichever subset a timeline declares. The runtime reads it rather
-- than the table order, so a timeline that lists Residue before Impact still plays correctly and the test
-- that checks ordering is checking the author's intent rather than a bug it would otherwise create.
VfxTimelineConfig.PhaseOrder = { "Anticipation", "Cast", "Travel", "Impact", "Residue" } :: { PhaseName }

-- Layers live for a scheduled time, but a client whose frame rate collapses can fall behind, so every
-- layer is also force-released this long after it started. It is the backstop that makes a leak
-- impossible rather than unlikely.
VfxTimelineConfig.MaxLayerSeconds = 6

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
					longest = math.max(longest, phaseStart + (layer.At + layer.For) * factor)
				end
				phaseStart += seconds
			end
		end
	end
	return math.max(longest, phaseStart)
end

return VfxTimelineConfig
