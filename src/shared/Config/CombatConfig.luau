--!strict
-- Combat tuning: chakra, health, melee, dash, block, hit rules. Pure data.

local CombatConfig = {}

CombatConfig.Health = {
	Max = 100,
	RegenPerSecond = 3, -- only out of combat
	RegenDelaySeconds = 8, -- after last damage taken
}

CombatConfig.Chakra = {
	Max = 100,
	RegenOutOfCombat = 12, -- per second
	RegenInCombat = 4, -- per second
	InCombatSeconds = 6, -- time after dealing/taking damage during which "in combat" applies
	StartFraction = 1, -- chakra at spawn (1 = full)
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
	Cost = 10, -- chakra
}

CombatConfig.Block = {
	DamageReduction = 0.7, -- 70% of incoming damage removed
	MaxHoldSeconds = 4,
	CooldownSeconds = 1.5,
	BreakStunSeconds = 1.0,
	WalkSpeedFactor = 0.5,
	-- Damage sources that break a guard instead of being reduced.
	BrokenBy = { Ultimate = true, MeleeFinisher = true },
}

CombatConfig.Hit = {
	-- The same jutsu instance cannot damage the same target twice within this window.
	IFrameSeconds = 0.3,
	KnockbackDurationSeconds = 0.25,
	StunMaxSeconds = 2,
	RagdollSeconds = 0.6,
	-- Client-side juice (read by VfxController).
	HitStopSeconds = 0.06,
	CameraShakeSmall = 0.35,
	CameraShakeLarge = 0.9,
}

CombatConfig.Status = {
	SlowAttribute = "CombatSlow", -- Humanoid attribute set by the server while slowed
	StunAttribute = "CombatStun",
	BlockAttribute = "CombatBlock",

	-- Elemental interactions (docs/GAME_DESIGN.md §6). A mark is a Humanoid attribute holding its
	-- own expiry: CombatService.ApplyDamage writes it when the damage element is AppliedByElement
	-- and multiplies the damage by DamageMultiplier when the element is AmplifiesElement and the
	-- mark is still live. Flat, visible bonuses (vfx + floating text), never hidden stacking.
	Fanned = {
		Attribute = "CombatFanned",
		AppliedByElement = "Verdigris", -- any Wind jutsu marks the targets it damages
		AmplifiesElement = "Cinnabar",
		DurationSeconds = 3,
		DamageMultiplier = 1.25,
		NameKey = "status.fanned",
	},
	Conductive = {
		Attribute = "CombatConductive",
		AppliedByElement = "Indigo", -- water on the target conducts: refreshed by every water tick
		AmplifiesElement = "Orpiment",
		DurationSeconds = 1.5, -- shorter than a zone tick interval + travel: "still soaked"
		DamageMultiplier = 1.25,
		NameKey = "status.conductive",
	},

	-- StoneSkin buff (jutsu StoneSkin). The effect grants it for DurationSeconds; CombatService
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
