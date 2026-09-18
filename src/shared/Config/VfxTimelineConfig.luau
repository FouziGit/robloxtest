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
export type LayerKind = "Carrier" | "Sprite" | "Emitter" | "Beam" | "Trail" | "Light" | "Mark" | "Shake" | "Flash"

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
	-- Studs from the effect's own frame, as {right, up, forward}.
	Offset: { number }?,
	-- Built on the phase's Carrier rather than at a fixed point. Ignored when the timeline has no
	-- carrier, so a layer that rides is still drawn, standing still, rather than not drawn at all.
	Ride: boolean?,
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

	-- Shake and Flash only: the profile name in FeelConfig.Shake.Profiles or LightingConfig's pulses.
	Profile: string?,
}

export type Phase = {
	Name: PhaseName,
	-- Seconds. The phase's own length, which is not the same as the longest layer in it: a layer may
	-- outlive its phase, and usually does in Residue.
	Duration: number,
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
				{
					Kind = "Light",
					At = 0,
					For = 0.22,
					Ease = "Sine",
					EaseDirection = "InOut",
					Range = 6,
					Brightness = 1.1,
				},
				{ Kind = "Shake", At = 0, For = 0.05, Profile = "Dash" },
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

VfxTimelineConfig.Timelines = {
	Cast = CAST,
	Hit = HIT,
	Dash = DASH,
	Melee = MELEE,
	Brand = BRAND,
	Explosion = EXPLOSION,
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

-- Total duration of a timeline, phases end to end plus the tail of whatever layer outlives the last one.
-- Used by the runtime to size its own bookkeeping and by the test to keep a timeline inside the window
-- its packet's Trove lives for.
function VfxTimelineConfig.duration(timeline: Timeline): number
	local phaseStart = 0
	local longest = 0
	for _, name in ipairs(VfxTimelineConfig.PhaseOrder) do
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == name then
				for _, layer in ipairs(phase.Layers) do
					longest = math.max(longest, phaseStart + layer.At + layer.For)
				end
				phaseStart += phase.Duration
			end
		end
	end
	return math.max(longest, phaseStart)
end

return VfxTimelineConfig
