--!strict
-- World Boss: a periodic server-wide event. Pure data.
-- The boss scales with the number of participants, telegraphs each attack, and rewards by damage
-- contribution. PvP is disabled for the duration (MatchService policy), see docs/GAME_DESIGN.md §7.

export type AttackDef = {
	Id: string,
	NameKey: string,
	TelegraphSeconds: number, -- warning window before the hit lands
	Damage: number,
	Radius: number, -- studs; meaning depends on Shape
	Shape: "Circle" | "Cone" | "Ring", -- Circle: centred on the boss; Cone: forward; Ring: safe centre
	Range: number, -- forward reach for Cone, outer reach for Ring
	StunSeconds: number,
	Knockback: number,
	CooldownSeconds: number,
	MinPhase: number, -- first phase that can use this attack
	VfxId: string,
}

local WorldBossConfig = {}

WorldBossConfig.Schedule = {
	IntervalSeconds = 1200, -- one event every 20 minutes
	AnnounceSeconds = 60, -- warning before the boss spawns
	FightSeconds = 300, -- hard timer: the boss despawns and nobody wins
	CleanupSeconds = 15, -- victory / defeat screen before the arena is released
	MinPlayers = 2, -- fewer players on the server: the event is skipped
}

WorldBossConfig.Health = {
	Base = 4000, -- health for MinPlayers
	PerExtraPlayer = 2500, -- added per player above MinPlayers
	Max = 40000,
}

-- Phases switch at these remaining-health fractions; each phase speeds the boss up.
WorldBossConfig.Phases = {
	{ Threshold = 1.0, AttackSpeed = 1.0, MoveSpeed = 12 },
	{ Threshold = 0.6, AttackSpeed = 1.25, MoveSpeed = 15 },
	{ Threshold = 0.3, AttackSpeed = 1.6, MoveSpeed = 18 },
} :: { { Threshold: number, AttackSpeed: number, MoveSpeed: number } }

WorldBossConfig.Attacks = {
	{
		Id = "Slam",
		NameKey = "boss.attack.slam",
		TelegraphSeconds = 1.2,
		Damage = 28,
		Radius = 22,
		Shape = "Circle",
		Range = 22,
		StunSeconds = 0.5,
		Knockback = 55,
		CooldownSeconds = 7,
		MinPhase = 1,
		VfxId = "BossSlam",
	},
	{
		Id = "Sweep",
		NameKey = "boss.attack.sweep",
		TelegraphSeconds = 1.0,
		Damage = 22,
		Radius = 14,
		Shape = "Cone",
		Range = 40,
		StunSeconds = 0,
		Knockback = 70,
		CooldownSeconds = 9,
		MinPhase = 1,
		VfxId = "BossSweep",
	},
	{
		Id = "Eruption",
		NameKey = "boss.attack.eruption",
		TelegraphSeconds = 1.6,
		Damage = 35,
		Radius = 16,
		Shape = "Ring",
		Range = 46,
		StunSeconds = 0.6,
		Knockback = 40,
		CooldownSeconds = 13,
		MinPhase = 2,
		VfxId = "BossEruption",
	},
	{
		Id = "Fury",
		NameKey = "boss.attack.fury",
		TelegraphSeconds = 2.0,
		Damage = 45,
		Radius = 30,
		Shape = "Circle",
		Range = 30,
		StunSeconds = 0.8,
		Knockback = 80,
		CooldownSeconds = 18,
		MinPhase = 3,
		VfxId = "BossFury",
	},
} :: { AttackDef }

-- Reward tiers by share of the boss health a player personally removed.
WorldBossConfig.Rewards = {
	MinShareToReward = 0.01, -- below 1% of the damage: participation only
	KillBonusShare = 0.15, -- a player above this share also gets the kill bonus
}

WorldBossConfig.Boss = {
	Name = "WorldBoss", -- instance name (not shown to players; the HUD uses boss.name)
	-- The CollectionService tag the boss model carries, which is how a client finds it to lock onto
	-- (D-115). Never GameConfig.Enemy.Tag: that one means a training proof, and a boss wearing it would
	-- count as a proof in the quests and take a killer's kill effect.
	Tag = "WorldBoss",
	NameKey = "boss.name",
	-- Studs {X, Y, Z}; the service builds the vector (this module stays pure). Flat on Z: it is the
	-- collider and the figure inside it (WorldConfig.Erasure) is a flat silhouette, so a deeper hull
	-- would be an invisible wall two studs in front of anything the player can see -- and the surface
	-- every projectile detonates against. contactRadius stays max(X, Z) / 2 = 4.
	BodySize = { 8, 14, 4.4 },
	AggroRadius = 70,
	ContactDamage = 12, -- per second while standing inside the boss
}

-- How close a target has to be to count as standing inside the boss body, which is also the narrowest a
-- Cone attack's wedge ever gets: hugging the boss is not a dodge (WorldBossMode.isInShape). It lives here
-- rather than in WorldBossMode because the client's telegraph has to paint at least this much floor, and
-- tests/BossTelegraph.spec.luau proves it does -- and a rule proved against a copy of the number is a rule
-- proved against nothing.
function WorldBossConfig.contactRadius(): number
	local body = WorldBossConfig.Boss.BodySize
	return math.max(body[1], body[3]) / 2
end

function WorldBossConfig.healthFor(playerCount: number): number
	local extra = math.max(0, playerCount - WorldBossConfig.Schedule.MinPlayers)
	return math.min(
		WorldBossConfig.Health.Max,
		WorldBossConfig.Health.Base + extra * WorldBossConfig.Health.PerExtraPlayer
	)
end

-- Phase index (1-based) for a remaining-health fraction.
function WorldBossConfig.phaseFor(healthFraction: number): number
	local phase = 1
	for index, definition in ipairs(WorldBossConfig.Phases) do
		if healthFraction <= definition.Threshold then
			phase = index
		end
	end
	return phase
end

return WorldBossConfig
