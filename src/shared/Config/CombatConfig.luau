--!strict
-- Combat tuning: ink, health, melee, dash, block, hit rules. Pure data.

local CombatConfig = {}

CombatConfig.Health = {
	Max = 100,
	RegenPerSecond = 3, -- only out of combat
	RegenDelaySeconds = 8, -- after last damage taken
}

CombatConfig.Ink = {
	Max = 100,
	RegenOutOfCombat = 12, -- per second
	RegenInCombat = 4, -- per second
	InCombatSeconds = 6, -- time after dealing/taking damage during which "in combat" applies
	StartFraction = 1, -- ink at spawn (1 = full)
}

CombatConfig.Melee = {
	Damage = { 8, 8, 8, 14 }, -- per hit; the last entry is the finisher
	Range = 7, -- studs in front of the attacker
	Width = 5, -- studs (box half-extent sideways)
	HitboxHeight = 6, -- studs (vertical extent of the melee box)
	ComboWindowSeconds = 0.9, -- time to chain the next hit before the combo resets
	HitIntervalSeconds = 0.22, -- minimum time between two hits
	FinisherCooldownSeconds = 1.2, -- cooldown after the finisher lands or whiffs
	FinisherKnockback = 45,
	FinisherLift = 18,
	FinisherStunSeconds = 0.5,
	HitStunSeconds = 0.15,
}

CombatConfig.Dash = {
	Distance = 22,
	DurationSeconds = 0.22,
	CooldownSeconds = 2.5,
	IFrameSeconds = 0.25,
	Cost = 10, -- ink
	-- A dash inside the finisher's recovery (Melee.FinisherCooldownSeconds) ends that recovery on the
	-- spot: the cancel every fighting game's skill ceiling is made of, bought with ink on top of the
	-- dash's own cost, so it is a choice and not a free reset.
	CancelCost = 15,
}

CombatConfig.Block = {
	DamageReduction = 0.7, -- 70% of incoming damage removed
	-- The guard has NO timer. It is held for exactly as long as the key is held and paid for in ink --
	-- the same pool a glyph and a dash come out of -- so turtling costs offence, which is the trade a
	-- guard is supposed to be. What was here before was a four-second cut that dropped the stance while
	-- the key was still down, with nothing on screen to say why: the player read it as the guard being
	-- broken by nothing.
	--
	-- Net of Ink.RegenInCombat (4/s) this drains 8/s, so a full pool buys about twelve seconds of
	-- unbroken guard and leaves the player with nothing to cast when it ends. Raising it above the
	-- regeneration rate is what makes the stance finite at all; it must stay above it.
	InkPerSecond = 12,
	-- Long enough that a guard cannot be flickered on and off between two frames to eat one hit each
	-- time, short enough that letting go to answer and guarding again is a rhythm rather than a
	-- punishment. The 1.5 s this used to be made re-guarding feel broken.
	CooldownSeconds = 0.4,
	BreakStunSeconds = 1.0,
	WalkSpeedFactor = 0.5,
	-- The walk-speed slow is re-applied every server tick while the stance is held, so it carries no
	-- duration of its own and cannot outlive the guard. Any value comfortably above one tick works.
	SlowRefreshSeconds = 0.5,
	-- Damage sources that break a guard instead of being reduced.
	BrokenBy = { Ultimate = true, MeleeFinisher = true },
}

CombatConfig.Hit = {
	-- The same glyph instance cannot damage the same target twice within this window.
	IFrameSeconds = 0.3,
	KnockbackDurationSeconds = 0.25,
	StunMaxSeconds = 2,
	RagdollSeconds = 0.6,
	-- Camera weight for the spells phase 4 of docs/JUICE_PLAN.md has not reworked yet, on the old 0-to-1
	-- scale VfxLibrary.shakeNear still takes. Everything already reworked names a profile in
	-- Config/FeelConfig instead, and these two leave with the last renderer that reads them. Hit-stop
	-- moved there outright: its length is derived from the damage now, not fixed at one duration.
	CameraShakeSmall = 0.35,
	CameraShakeLarge = 0.9,
}

CombatConfig.Status = {
	SlowAttribute = "CombatSlow", -- Humanoid attribute set by the server while slowed
	StunAttribute = "CombatStun",
	BlockAttribute = "CombatBlock",

	-- Pigment interactions (docs/GAME_DESIGN.md §6). A mark is a Humanoid attribute holding its
	-- own expiry: CombatService.ApplyDamage writes it when the damage pigment is AppliedByPigment
	-- and multiplies the damage by DamageMultiplier when the pigment is AmplifiesPigment and the
	-- mark is still live. Flat, visible bonuses (vfx + floating text), never hidden stacking.
	Fanned = {
		Attribute = "CombatFanned",
		AppliedByPigment = "Verdigris", -- any Verdigris glyph marks the targets it damages
		AmplifiesPigment = "Cinnabar",
		DurationSeconds = 3,
		DamageMultiplier = 1.25,
		NameKey = "status.fanned",
	},
	Conductive = {
		Attribute = "CombatConductive",
		AppliedByPigment = "Indigo", -- water on the target conducts: refreshed by every water tick
		AmplifiesPigment = "Orpiment",
		DurationSeconds = 1.5, -- shorter than a zone tick interval + travel: "still soaked"
		DamageMultiplier = 1.25,
		NameKey = "status.conductive",
	},

	-- Gilding buff (glyph Gilding). The effect grants it for DurationSeconds; CombatService
	-- removes DamageReduction of every incoming hit and skips knockback while it is live.
	Gilding = {
		Attribute = "CombatStoneSkin",
		DamageReduction = 0.4,
		DurationSeconds = 4,
		KnockbackImmune = true,
		NameKey = "status.stoneSkin",
	},
}

return CombatConfig
