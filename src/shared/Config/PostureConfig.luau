--!strict
-- Every number that decides how a BODY moves. Until this file existed there was not one Motor6D, one
-- Animator and one animation asset in the whole repository: a character swung nothing, guarded with its
-- arms down and dashed standing upright, while the damage, the ink and the screen shake all behaved. A
-- player reads the body before they read the numbers, so the game looked like a tech demo that hurts.
--
-- No animation asset and no Animator here, on purpose and permanently. An Animation needs an uploaded
-- asset id, and the only ids available to borrow are other studios' -- which docs/ART_BIBLE.md forbids
-- outright, and which is how every Roblox battleground ends up sharing four animations. This is
-- procedural instead: an ADDITIVE rotation written onto each joint's C0, composed on top of whatever
-- the engine's own idle and walk are doing through Motor6D.Transform. The two never fight, because they
-- write different properties.
--
-- Angles are DEGREES, applied in the parent part's space, about the joint's own pivot. Parent space is
-- the one thing an R6 torso and an R15 UpperTorso agree on (X right, Y up, Z back), so a pose written
-- once reads the same on both rigs even though the two rigs' joint frames differ by 90 degrees. The
-- controller does the conversion once (src/client/Controllers/Posture.luau).
--
-- Pure data: no require and no Roblox global, so it loads under Lune (tests/Purity.spec.luau).

-- The joints a pose may name. Semantic, not per-rig: "the right arm", not "RightShoulder", because the
-- Motor6D that swings a right arm is called two different things on the two rigs and lives under two
-- different parents.
export type Joint = "RightArm" | "LeftArm" | "Torso" | "Head"

-- Degrees about X, Y, Z in parent space. X swings a limb forward, Y turns it outward, Z lifts it
-- sideways.
export type Angles = { number }

-- A transient pose: it arrives, holds, and leaves. The three phases are the same envelope the lighting
-- pulses use (Config/LightingConfig), for the same reason -- a pose that leaves as fast as it arrives
-- reads as a dropped frame.
export type PoseDef = {
	AttackSeconds: number,
	HoldSeconds: number,
	ReleaseSeconds: number,
	Angles: { [string]: Angles },
}

local PostureConfig = {}

-- The four joints, in the order the controller walks them.
PostureConfig.JointOrder = { "RightArm", "LeftArm", "Torso", "Head" } :: { string }

-- Semantic joint -> the Motor6D that carries it, per rig type.
--
-- R6 has no waist, so its torso lean is taken at the RootJoint and moves the legs with it. That is the
-- rig's limitation, not a shortcut: an R6 character leaning is a whole character leaning, and it still
-- reads.
PostureConfig.Motors = {
	R6 = {
		RightArm = "Right Shoulder",
		LeftArm = "Left Shoulder",
		Torso = "RootJoint",
		Head = "Neck",
	},
	R15 = {
		RightArm = "RightShoulder",
		LeftArm = "LeftShoulder",
		Torso = "Waist",
		Head = "Neck",
	},
} :: { [string]: { [string]: string } }

-- How far a character is still worth animating, and how many at once. Posture is cheap -- four CFrame
-- writes per character per frame, no instances created, nothing allocated -- so this is a sanity bound
-- rather than a quality tier: a 12-player server in one place is 48 CFrame writes.
PostureConfig.RangeStuds = 140
PostureConfig.MaxCharacters = 12

-- The envelope conversion, identical to LightingConfig.Envelope and for the same reason: this project
-- has one integrator, it is tested under Lune, and a second easing curve written by hand here would be
-- a second thing to be wrong. A critically damped spring is within 2% of its goal after Settle/omega
-- seconds, so the tension covering a declared phase is (Settle / seconds)^2.
PostureConfig.Envelope = {
	Settle = 6,
	SettleEpsilon = 0.02,
	MinPhaseSeconds = 1 / 60,
}

-- The melee chain. One pose per entry of CombatConfig.Melee.Damage, in the same order, which
-- tests/Posture.spec.luau enforces: adding a fifth swing to the combo without a fifth pose would give
-- the game a hit that nobody throws.
--
-- The chain alternates arms and grows: the first is a jab that barely turns the shoulders, the last is
-- the finisher and commits the whole body. That escalation is the only thing telling a player, without
-- a number, that the fourth hit is the one that launches.
local poses: { [string]: PoseDef } = {
	Melee1 = {
		AttackSeconds = 0.07,
		HoldSeconds = 0.03,
		ReleaseSeconds = 0.16,
		Angles = {
			RightArm = { 96, -14, 10 },
			LeftArm = { -22, 0, 0 },
			Torso = { 4, -16, 0 },
			Head = { 5, -8, 0 },
		},
	},
	Melee2 = {
		AttackSeconds = 0.07,
		HoldSeconds = 0.03,
		ReleaseSeconds = 0.16,
		Angles = {
			RightArm = { -22, 0, 0 },
			LeftArm = { 96, 14, -10 },
			Torso = { 4, 16, 0 },
			Head = { 5, 8, 0 },
		},
	},
	Melee3 = {
		AttackSeconds = 0.08,
		HoldSeconds = 0.04,
		ReleaseSeconds = 0.18,
		Angles = {
			RightArm = { 118, -26, 22 },
			LeftArm = { -34, 0, -8 },
			Torso = { 9, -26, 0 },
			Head = { 9, -12, 0 },
		},
	},
	-- The finisher: both arms come over the top and the body follows them down. Twice the attack of a
	-- jab and three times the release, because this is the hit that knocks a player into the air and the
	-- recovery is the window the dash-cancel is paid to skip (CombatConfig.Dash.CancelCost).
	Melee4 = {
		AttackSeconds = 0.13,
		HoldSeconds = 0.06,
		ReleaseSeconds = 0.34,
		Angles = {
			RightArm = { 142, -10, 26 },
			LeftArm = { 142, 10, -26 },
			Torso = { 26, 0, 0 },
			Head = { 16, 0, 0 },
		},
	},
	-- A glyph leaving the hand: the arm comes up and forward, palm out, and the torso opens rather than
	-- twisting. Nothing here mirrors the melee chain -- casting and punching must not look alike, or the
	-- opponent cannot read which one is coming.
	Cast = {
		AttackSeconds = 0.09,
		HoldSeconds = 0.08,
		ReleaseSeconds = 0.26,
		Angles = {
			RightArm = { 104, -34, 30 },
			LeftArm = { 28, 0, -16 },
			Torso = { -8, -10, 0 },
			Head = { -6, -6, 0 },
		},
	},
	-- The dash: the body leads and the arms trail. Short, because the dash itself is 0.22 s, and a lean
	-- still leaning when the character has stopped moving is the single most common tell of a procedural
	-- animation nobody timed.
	Dash = {
		AttackSeconds = 0.06,
		HoldSeconds = 0.06,
		ReleaseSeconds = 0.2,
		Angles = {
			RightArm = { -52, 0, 14 },
			LeftArm = { -52, 0, -14 },
			Torso = { 22, 0, 0 },
			Head = { -10, 0, 0 },
		},
	},
	-- Taking a hit. Small on purpose: the knockback, the hit-stop and the damage number already say it
	-- was a hit, and a flinch big enough to compete with them would hide the guard going up.
	Flinch = {
		AttackSeconds = 0.05,
		HoldSeconds = 0.02,
		ReleaseSeconds = 0.22,
		Angles = {
			RightArm = { -16, 0, 12 },
			LeftArm = { -16, 0, -12 },
			Torso = { -14, 0, 0 },
			Head = { -18, 0, 0 },
		},
	},
	-- The guard breaking: arms thrown apart, head back. This is the one pose that is meant to look bad,
	-- because the second it plays the player is open for CombatConfig.Block.BreakStunSeconds.
	GuardBreak = {
		AttackSeconds = 0.06,
		HoldSeconds = 0.14,
		ReleaseSeconds = 0.4,
		Angles = {
			RightArm = { -30, -40, 58 },
			LeftArm = { -30, 40, -58 },
			Torso = { -26, 0, 0 },
			Head = { -30, 0, 0 },
		},
	},
}

PostureConfig.Poses = poses

-- The melee chain, by index. Read by the controller against the packet's Params.Index.
PostureConfig.MeleeChain = { "Melee1", "Melee2", "Melee3", "Melee4" } :: { string }

-- The guard is NOT in the table above, because it is not a pulse: it is a state, held for exactly as
-- long as the player holds the key, and it has no hold and no release of its own. It rises when the
-- humanoid's guard attribute turns on and falls when it turns off, and nothing else in this file can
-- make it leave early.
PostureConfig.Guard = {
	RiseSeconds = 0.1,
	FallSeconds = 0.16,
	Angles = {
		RightArm = { 74, -52, 30 },
		LeftArm = { 74, 52, -30 },
		Torso = { 10, 0, 0 },
		Head = { 6, 0, 0 },
	} :: { [string]: Angles },
}

return PostureConfig
