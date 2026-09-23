--!strict
-- Every number that decides how a BODY moves. Until this file existed there was not one Motor6D, one
-- Animator and one animation asset in the whole repository: a character swung nothing, guarded with its
-- arms down and dashed standing upright, while the damage, the ink and the screen shake all behaved. A
-- player reads the body before they read the numbers, so the game looked like a tech demo that hurts.
--
-- No animation asset here. An Animation needs an uploaded asset id, and the only ids available to
-- borrow are other studios' -- which docs/ART_BIBLE.md forbids outright, and which is how every Roblox
-- battleground ends up sharing four animations. This is procedural instead: an ADDITIVE rotation
-- multiplied into each joint's Transform right after the Animator has written the frame's pose, so the
-- engine's own idle and walk keep running underneath (src/client/Controllers/Posture.luau).
--
-- Angles are DEGREES, applied in the parent part's space, about the joint's own pivot. Parent space is
-- the one thing an R6 torso and an R15 UpperTorso agree on (X right, Y up, Z back), so a pose written
-- once reads the same on both rigs even though the two rigs' joint frames differ by 90 degrees. The
-- controller does the conversion once (src/client/Controllers/Posture.luau).
--
-- Pure data: no require and no Roblox global, so it loads under Lune (tests/Purity.spec.luau).

-- The joints a pose may name. Semantic, not per-rig: "the right arm", not "RightShoulder", because the
-- joint that swings a right arm is called two different things on the two rigs and lives under two
-- different parents.
export type Joint = "RightArm" | "LeftArm" | "RightForearm" | "LeftForearm" | "Torso" | "Head"

-- Degrees about X, Y, Z in parent space, and the signs were MEASURED, not assumed: in a live client the
-- right hand was tracked against the upper torso while each axis was driven to +-90 on its own. X+
-- swings a limb forward and up (the right hand went from the hip to shoulder height in front). Z+ carries
-- the RIGHT arm away from the body and Z- across it; the left arm mirrors, so Z+ brings it across. Y
-- turns a hanging arm about its own length, which barely moves the hand. On a forearm, X+ folds it
-- forward at the elbow.
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

-- The joints, in the order the controller walks them.
--
-- The forearms are here because nothing reads without them. A live session drove the old four-joint
-- guard (shoulders, waist, neck) and the difference between guard up and guard down was hard to see from
-- the front and invisible from behind, which is where the camera is: a straight arm swung forward points
-- AWAY from a camera behind the character. Folding the elbow is what puts the fists up by the head, and
-- that silhouette is what says "guard" from every side.
PostureConfig.JointOrder = { "RightArm", "LeftArm", "RightForearm", "LeftForearm", "Torso", "Head" } :: { string }

-- Semantic joint -> the NAME of the joint that carries it, per rig type. A name and not a class,
-- because the class changed under this project's feet: on R15 the joint is a Motor6D in experiences
-- that opted out of Roblox's Avatar Joint Upgrade and an AnimationConstraint everywhere else (the
-- default since May 2026, and the opt-out is scheduled to disappear). Both carry the names below and a
-- Transform the Animator rewrites every frame, which is all the controller needs. R6 is not touched by
-- the upgrade and keeps Motor6D.
--
-- R6 has no waist, so its torso lean is taken at the RootJoint and moves the legs with it. That is the
-- rig's limitation, not a shortcut: an R6 character leaning is a whole character leaning, and it still
-- reads.
PostureConfig.JointNames = {
	R6 = {
		RightArm = "Right Shoulder",
		LeftArm = "Left Shoulder",
		Torso = "RootJoint",
		Head = "Neck",
	},
	R15 = {
		RightArm = "RightShoulder",
		LeftArm = "LeftShoulder",
		RightForearm = "RightElbow",
		LeftForearm = "LeftElbow",
		Torso = "Waist",
		Head = "Neck",
	},
} :: { [string]: { [string]: string } }

-- The joints a rig physically does not have. R6 arms are one part each, so there is no elbow to fold:
-- its guard is the shoulders alone, which reads less well and is the rig's limit, not a missing entry.
-- tests/Posture.spec.luau holds every other joint to being named on every rig.
PostureConfig.AbsentOnRig = {
	R6 = { RightForearm = true, LeftForearm = true },
} :: { [string]: { [string]: boolean } }

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
	-- A right jab: the striking arm straight out, the other hand coming up by the face, the shoulders
	-- turning into it. From behind, which is where the camera is, a straight arm points away and hides
	-- behind the body; what reads is the turn of the torso and the off hand rising.
	Melee1 = {
		AttackSeconds = 0.07,
		HoldSeconds = 0.03,
		ReleaseSeconds = 0.16,
		Angles = {
			RightArm = { 96, 0, -12 },
			RightForearm = { 8, 0, 0 },
			LeftArm = { 60, 0, 22 },
			LeftForearm = { 84, 0, 0 },
			Torso = { 6, -24, 0 },
			Head = { 6, -10, 0 },
		},
	},
	-- The left jab, mirrored.
	Melee2 = {
		AttackSeconds = 0.07,
		HoldSeconds = 0.03,
		ReleaseSeconds = 0.16,
		Angles = {
			RightArm = { 60, 0, -22 },
			RightForearm = { 84, 0, 0 },
			LeftArm = { 96, 0, 12 },
			LeftForearm = { 8, 0, 0 },
			Torso = { 6, 24, 0 },
			Head = { 6, 10, 0 },
		},
	},
	-- A right hook: the elbow bent square and the arm carried ACROSS the body, with the whole torso
	-- turning behind it. The sideways travel is what a camera behind the character can actually see.
	Melee3 = {
		AttackSeconds = 0.08,
		HoldSeconds = 0.04,
		ReleaseSeconds = 0.18,
		Angles = {
			RightArm = { 86, 0, -52 },
			RightForearm = { 78, 0, 0 },
			LeftArm = { 60, 0, 22 },
			LeftForearm = { 84, 0, 0 },
			Torso = { 8, -38, 0 },
			Head = { 8, -14, 0 },
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
			RightArm = { 150, 0, -22 },
			RightForearm = { 36, 0, 0 },
			LeftArm = { 150, 0, 22 },
			LeftForearm = { 36, 0, 0 },
			Torso = { 30, 0, 0 },
			Head = { 18, 0, 0 },
		},
	},
	-- A glyph leaving the hand: the arm swings up and OUT to the side, nearly straight, and the torso
	-- opens rather than twisting. Nothing here mirrors the melee chain -- casting and punching must not
	-- look alike, or the opponent cannot read which one is coming.
	Cast = {
		AttackSeconds = 0.09,
		HoldSeconds = 0.08,
		ReleaseSeconds = 0.26,
		Angles = {
			-- Out and UP to the side, arm nearly straight: the one pose in this file whose hand travels
			-- away from the body sideways, which is what separates it from every punch from behind.
			RightArm = { 70, 0, 58 },
			RightForearm = { 14, 0, 0 },
			LeftArm = { 28, 0, 16 },
			LeftForearm = { 40, 0, 0 },
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
	-- Chosen on screen, in a live client, from the front and from behind, over four versions. The first
	-- (shoulders only, 74 degrees forward, arms carried outward) was indistinguishable from guard down.
	-- Elbows folded with the arms spread framed the face like a surrender. Brought together, the fists
	-- met under the chin and vanished behind the body when seen from the camera. These values keep the
	-- elbows out just far enough that, from behind, a fist shows either side of the head.
	Angles = {
		RightArm = { 104, 0, -36 },
		LeftArm = { 104, 0, 36 },
		RightForearm = { 118, 0, 0 },
		LeftForearm = { 118, 0, 0 },
		Torso = { 10, 0, 0 },
		Head = { 14, 0, 0 },
	} :: { [string]: Angles },
}

return PostureConfig
