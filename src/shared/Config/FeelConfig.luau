--!strict
-- Every number that decides how the game FEELS. Nothing here is gameplay: no value in this file changes
-- damage, range, cost or cooldown, so it can be tuned without rebalancing anything. Pure data, so it
-- loads under Lune and tests/Config.spec.luau can hold it to the ranges docs/JUICE_PLAN.md asked for.
--
-- Vectors are written as plain {x, y, z} number triples, not Vector3: this module must stay engine-free
-- (tests/Purity.spec.luau). The client converts them once at load.

export type Triple = { number }

-- One impact profile: what the camera does when something lands. Amplitude is in studs at the closest
-- distance, Frequency is the Perlin sampling rate (higher = faster, more nervous), and the three times
-- are the fade in, the hold and the fade out, which is why a heavy hit can land instantly and let go
-- slowly while a light one is over before it is read.
export type ShakeProfile = {
	Amplitude: number,
	Frequency: number,
	FadeInSeconds: number,
	SustainSeconds: number,
	FadeOutSeconds: number,
	PositionInfluence: Triple,
	RotationInfluence: Triple,
}

local FeelConfig = {}

-- Hit-stop: the pause on impact. docs/JUICE_PLAN.md fixes the window at 40 to 90 ms; below 40 nobody
-- feels it and above 90 the game stutters. The duration rides the damage between the two, so an M1 jab
-- and an ultimate do not stop the world for the same length of time.
--
-- It never stacks. A second hit inside a running stop re-arms the timer at the longer of the two rather
-- than adding, because three quick hits adding up to 270 ms reads as a freeze, not as impact.
FeelConfig.HitStop = {
	MinSeconds = 0.04,
	MaxSeconds = 0.09,
	MinDamage = 8, -- a single melee jab
	MaxDamage = 45, -- the heaviest ultimate in the roster
	-- The camera eases back out over this, instead of snapping, so the release is not a second jolt.
	ReleaseSeconds = 0.08,
	-- While the local player is the one who LANDED the hit, their own horizontal velocity is held at
	-- zero for the stop. Planting the feet is most of what makes a melee hit feel heavy. It is never
	-- applied to the player taking the hit, whose knockback has to land.
	PlantOnDealt = true,
}

-- Camera shake, per impact profile. Perlin noise (sleitnick/shake), never random jitter: random reads
-- as a broken camera, noise reads as weight. Rotation influence is deliberately tiny — roll past about
-- 0.05 rad makes people motion sick on mobile.
FeelConfig.Shake = {
	Profiles = {
		Melee = {
			Amplitude = 0.55,
			Frequency = 0.08,
			FadeInSeconds = 0,
			SustainSeconds = 0.02,
			FadeOutSeconds = 0.18,
			PositionInfluence = { 0.9, 0.9, 0.35 },
			RotationInfluence = { 0.02, 0.02, 0.035 },
		} :: ShakeProfile,
		Light = {
			Amplitude = 0.45,
			Frequency = 0.1,
			FadeInSeconds = 0,
			SustainSeconds = 0,
			FadeOutSeconds = 0.22,
			PositionInfluence = { 1, 1, 0.3 },
			RotationInfluence = { 0.015, 0.015, 0.03 },
		} :: ShakeProfile,
		Heavy = {
			Amplitude = 1.6,
			Frequency = 0.055,
			FadeInSeconds = 0.01,
			SustainSeconds = 0.06,
			FadeOutSeconds = 0.5,
			PositionInfluence = { 1, 1, 0.5 },
			RotationInfluence = { 0.03, 0.03, 0.05 },
		} :: ShakeProfile,
		-- The caster's own cast: felt, not seen. It must never compete with the impact that follows.
		Cast = {
			Amplitude = 0.3,
			Frequency = 0.14,
			FadeInSeconds = 0.02,
			SustainSeconds = 0,
			FadeOutSeconds = 0.14,
			PositionInfluence = { 0.6, 0.8, 0.2 },
			RotationInfluence = { 0.01, 0.01, 0.02 },
		} :: ShakeProfile,
		Dash = {
			Amplitude = 0.35,
			Frequency = 0.2,
			FadeInSeconds = 0,
			SustainSeconds = 0,
			FadeOutSeconds = 0.12,
			PositionInfluence = { 0.4, 0.4, 1 },
			RotationInfluence = { 0.005, 0.005, 0.02 },
		} :: ShakeProfile,
	},
	-- Past this the impact is somebody else's fight and the camera stays still.
	FalloffRadiusStuds = 70,
	-- Below this scale a shake is not worth the frame it costs, so it is skipped entirely.
	MinScale = 0.06,
	-- Concurrent shakes are summed, but a six-player fight can start twenty at once. Only the strongest
	-- few are kept, so the sum stays a shake instead of becoming noise.
	MaxConcurrent = 4,
}

-- Field-of-view punches, all driven by one spring so they compose instead of fighting each other. A
-- punch is an impulse on that spring's velocity, not a goal: the FOV always returns to whatever the
-- camera's own base is, which means a punch can never leave the view permanently wrong.
FeelConfig.Fov = {
	Tension = 220,
	Friction = 22,
	-- Degrees of impulse. Negative pulls the view in (a blow landing), positive pushes it out (speed).
	CastImpulse = -34,
	HeavyCastImpulse = -70,
	DashImpulse = 46,
	HitTakenImpulse = -58,
	HitDealtImpulse = -26,
	-- The spring is never allowed to move the view further than this from the base, whatever lands.
	MaxOffsetDegrees = 9,
	-- Under this, the punch is done and the spring is released rather than stepped forever.
	SettleEpsilon = 0.05,
}

-- The brief white-hot outline on whatever was just hit. A Highlight, so it reads through walls and
-- through other players, which is the point: in a six-player fight you must see that YOUR hit landed.
FeelConfig.Flash = {
	Seconds = 0.09,
	FillTransparency = 0.55,
	OutlineTransparency = 0,
	-- More than this many at once and the screen is a light show; the oldest is released first.
	MaxConcurrent = 6,
}

-- The ink impact frame (D-112): on a heavy hit or a chain's finisher, the two bodies in it are printed
-- as solid ink for a few frames, over the page flash the impact already throws -- the inverse print of an
-- overexposed page. The bodies only, never the screen: a frame that drained the colour from everything
-- would hide the spells for its length, which is the one thing D-108 exists to forbid, and the lighting
-- bands have no room for it besides. Once per MinIntervalSeconds, so a flurry is not a strobe. At least as
-- long as the hit outline it covers: shorter, the outline flickered back for one frame after it (review).
FeelConfig.ImpactFrame = {
	Seconds = 0.1,
	MinIntervalSeconds = 0.5,
}

-- Floating damage numbers.
FeelConfig.DamageNumbers = {
	Seconds = 0.85,
	RiseStuds = 4.2,
	-- Horizontal scatter so two hits in the same place do not print on top of each other.
	SpreadStuds = 1.6,
	-- Studs above the target's root where the number is born.
	HeightStuds = 2.4,
	-- The number pops past its size and settles back, on the shared spring.
	PopScale = 1.45,
	Tension = 320,
	Friction = 18,
	BaseTextSize = 26,
	-- A big hit is a bigger number, up to this multiple of the base size.
	MaxSizeScale = 1.9,
	-- It holds full opacity for this fraction of its life, then fades. Fading from the first frame
	-- makes every number look weak.
	HoldFraction = 0.45,
	-- Past this many on screen the oldest is retired, so a boss fight cannot cost the frame.
	MaxConcurrent = 14,
}

-- Knockback and dash are driven by a decaying speed curve rather than a flat velocity held for a fixed
-- time. The exponent shapes the decay; the curve is normalised (Pure/FeelMath) so the TOTAL distance is
-- exactly what the server granted. That matters: this is a feel change, and it must not become a
-- balance change.
FeelConfig.Impulse = {
	KnockbackExponent = 1.9,
	DashExponent = 0.9,
	-- The curve is re-evaluated at most this often; between evaluations the mover holds its value.
	StepSeconds = 1 / 60,
}

-- Haptics. Roblox exposes a large and a small motor; the small one is the only one many gamepads have,
-- so nothing important is put on the large motor alone.
FeelConfig.Haptics = {
	Enabled = true,
	Cast = { Small = 0.25, Large = 0.1, Seconds = 0.06 },
	HitDealt = { Small = 0.45, Large = 0.25, Seconds = 0.08 },
	HitTaken = { Small = 0.7, Large = 0.55, Seconds = 0.12 },
	Dash = { Small = 0.3, Large = 0, Seconds = 0.05 },
}

-- Default spring constants for anything that moves and is not the FOV. Tension is the pull toward the
-- goal, friction the damping: friction near 2*sqrt(tension) is critically damped (no overshoot), below
-- it the value overshoots and comes back, which is what makes UI feel alive.
FeelConfig.Springs = {
	Ui = { Tension = 260, Friction = 24 },
	UiSnappy = { Tension = 420, Friction = 30 },
	-- The ghost of a bar: what was just lost, catching up slowly and never overshooting -- an overshoot
	-- on a health bar reads as health coming back.
	UiGhost = { Tension = 28, Friction = 11 },
	Camera = { Tension = 180, Friction = 26 },
}

return FeelConfig
