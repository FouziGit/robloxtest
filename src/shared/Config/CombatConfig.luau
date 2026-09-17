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
}

return CombatConfig
