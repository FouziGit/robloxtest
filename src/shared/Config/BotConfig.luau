--!strict
-- The Forgers (D-131): the Battleground's ink figures, R15 humanoids the server owns and drives through
-- BotBrain. Players only ever read "Forgers" ("Faussaires"); the tier ids below are internal, and each
-- avoids a name already in use (Stipple is a glyph, Scrawl a cosmetic style, Redaction a kill effect,
-- Bavure Bleed's French name, Palimpsest a cosmetic). Pure data.
--
-- Every attack a Forger makes is announced by the server for its whole wind-up (the ForgerTell effect),
-- lands through CombatService.ApplyDamage with no source, and reaches only players inside the Battleground.
-- The numbers are design values from the maths in the notes below; none has been played yet.

export type MeleeDef = {
	-- One entry per step of the chain; the last one is the finisher.
	Damage: { number },
	-- The hit box: Range studs ahead of the body, HalfWidth either side, HalfHeight above and below.
	Range: number,
	HalfWidth: number,
	HalfHeight: number,
	WindupSeconds: number,
	-- The wind-up of each later step, and of the finisher. Each step shows its own tell on a frozen aim.
	ChainGapSeconds: number,
	FinisherGapSeconds: number,
	-- How far past Range the target may have stepped for the chain to go on.
	ChainSlackStuds: number,
	RecoverySeconds: number,
	FinisherKnockback: number,
	FinisherLift: number,
	FinisherStunSeconds: number,
	FinisherBreaksGuard: boolean,
	FinisherRagdoll: boolean,
}

export type BoltDef = {
	Damage: number,
	Range: number,
	MinRange: number,
	HitRadius: number,
	HalfHeight: number,
	SpawnOffset: number,
	WindupSeconds: number,
	CooldownSeconds: number,
	KnockbackSpeed: number,
}

export type TierDef = {
	Role: "Melee" | "Ranged",
	Health: number,
	WalkSpeed: number,
	Scale: number,
	AggroRadius: number,
	LoseSightSeconds: number,
	AggroMemorySeconds: number,
	CommitSeconds: number,
	SwitchMarginStuds: number,
	-- The distance band a Forger keeps from its target, {near, far}: a melee one closes to `far` and stops,
	-- a ranged one backs off inside `near` and closes beyond `far`.
	KeepRange: { number },
	-- Hits never interrupt it; a knockback and a glyph's stun still do.
	StaggerImmune: boolean,
	Melee: MeleeDef,
	Bolt: BoltDef?,
	-- The ProgressionConfig.XP / Folios key its kill pays.
	RewardKey: string,
}

local BotConfig = {}

-- Never GameConfig.Enemy.Tag: that one means a training proof, and it feeds "Defeat {target} training
-- dummies" (quest.defeatDummies).
BotConfig.Tag = "Forger"
-- The Workspace folder they stand in. Rebuilt by name like every folder a service builds at Start, so it must
-- be no other one's name: rebuilding it would destroy that one.
BotConfig.FolderName = "Forgers"
-- Thinks per second per Forger: two gameplay ticks per think at GameConfig.Server.TickRate, staggered by slot.
BotConfig.ThinkHz = 10
-- target = clamp(BaseCount + PerExtraMember * (active members - 1), 1, MaxBots)
BotConfig.MaxBots = 10
BotConfig.BaseCount = 3
BotConfig.PerExtraMember = 1
-- The tier of each slot, in order: the first BaseCount are what a lone player faces.
BotConfig.Roster = {
	"Smudger",
	"Smudger",
	"Quill",
	"Smudger",
	"Overwriter",
	"Quill",
	"Smudger",
	"Quill",
	"Smudger",
	"Overwriter",
} :: { string }
-- A slot refills after max(MinSeconds, BaseSeconds - StepSeconds * (active members - 1)).
BotConfig.Respawn = { BaseSeconds = 8, StepSeconds = 0.5, MinSeconds = 4 }
-- A member is active while they were outside the camp within ActiveWindowSeconds: only active members bring
-- Forgers in. With nobody active for IdleDespawnSeconds, every Forger is removed and the page costs nothing.
BotConfig.ActiveWindowSeconds = 30
BotConfig.IdleDespawnSeconds = 60
-- Nobody is a target this soon after arriving: at least the spawn protection (GameConfig.Spawn).
BotConfig.ArrivalGraceSeconds = 4
-- A dead Forger lies this long before its body is removed.
BotConfig.CorpseSeconds = 1
-- The shortest tells a player ever gets: the wind-up of the first step of every attack, then of every later
-- step of a chain, each shown on its own frozen aim.
BotConfig.MinWindupSeconds = 0.5
BotConfig.MinChainGapSeconds = 0.4
-- The attack clips are sped up or slowed down so their impact frame lands on the server's resolve, within
-- these bounds (BotBrain.clipTiming).
BotConfig.ClipSpeed = { Min = 0.5, Max = 3 }
BotConfig.Targeting = {
	-- Forgers within this many ranks of a target close in; the rest circle.
	MaxEngagedPerTarget = 2,
	-- Nobody picks a target this many others already chase while a less crowded one is in reach.
	MaxAttackersPerTarget = 3,
	-- A target's score is its distance, plus this per other Forger on it, minus RetaliationStuds for whoever
	-- hit this one recently.
	LoadPenaltyStuds = 15,
	RetaliationStuds = 20,
	FlankStuds = 3,
	CircleStuds = 12,
	StrafeStuds = 6,
	StrafeSeconds = 2.5,
	-- How far apart two Forgers' strafes are phased, per slot, so a ring of them never turns as one.
	StrafePhaseSeconds = 0.7,
	HomeRadiusStuds = 4,
	-- A melee swing only starts this far inside its reach: the target has to step away to dodge it.
	MeleeStartInsetStuds = 0.5,
	-- After a chain on a target, no Forger starts another on it for this long; after a finisher, for the
	-- finisher's stun plus PostFinisherRestSeconds if that is longer.
	TargetRestSeconds = 0.8,
	PostFinisherRestSeconds = 0.5,
}
BotConfig.Reach = {
	-- A target this far above or below a Forger's root for UnreachableSeconds is ignored for IgnoreSeconds,
	-- whatever the Forger's role. Below every tier's HalfHeight, so hovering over a Forger or sinking under it
	-- can never make it whiff forever.
	UnreachableHeightStuds = 3.5,
	UnreachableSeconds = 3,
	IgnoreSeconds = 6,
	-- Sight is a ray from head to head, this far above both roots. Under CoverHeight, so cover hides. A bolt
	-- flies along the same line: what a Forger saw, it can hit.
	SightHeightStuds = 1.5,
	-- How far a body reaches out from its root's line: a bolt passing within its HitRadius plus this hits.
	TargetRadiusStuds = 1,
}
BotConfig.Path = {
	-- How wide a Forger is to the waypoint graph: every obstacle and the camp are grown by this
	-- (BattlegroundLayout), so a walk the graph calls clear never scrapes a corner.
	RadiusStuds = 2.5,
	-- A walk order is re-issued only when the goal moved RepathStuds, after RepathSeconds, or on reaching a
	-- waypoint (within WaypointReachedStuds of it).
	RepathSeconds = 0.5,
	RepathStuds = 4,
	WaypointReachedStuds = 3,
	-- The walk clip plays above this horizontal speed, the idle clip below it.
	WalkClipThreshold = 0.5,
}
-- Hits interrupt a wind-up, at most MaxPerWindow times per WindowSeconds; then the Forger shrugs hits off
-- for ImmuneSeconds.
BotConfig.Stagger = { HitSeconds = 0.3, KnockbackSeconds = 0.5, MaxPerWindow = 3, WindowSeconds = 4, ImmuneSeconds = 2 }
-- The stun a non-final step lands when it is not blocked: the players' own (CombatConfig.Melee).
BotConfig.MeleeHitStunSeconds = 0.15
-- A Forger whose root falls this far under the floor is dead, with no credit, before the kill plane.
BotConfig.FallMarginStuds = 12
-- The knockback mover's force: the body's mass times this, never an unbounded force.
BotConfig.ShoveForcePerMass = 3000
-- The killer and everyone who removed AssistShare of a Forger's health are paid. Folios from Forgers stop
-- at DailyFolioCap a day (before VIP), stored in the profile; XP never stops.
BotConfig.Credit = { AssistShare = 0.25, DailyFolioCap = 150 }
-- The camp heals a member RegenPerSecond once they have taken no damage for QuietSeconds. A hit dealt from
-- inside it counts for nothing, and its dealer is told so at most once every HitNoticeSeconds: often enough
-- to explain a health bar that does not move, rarely enough not to bury the other toasts.
BotConfig.Camp = { RegenPerSecond = 25, QuietSeconds = 1.5, HitNoticeSeconds = 20 }
-- The body: a health bar seen from HealthDisplayDistance once hurt, no name (the server cannot word one in each
-- player's language), and the humanoid states a server-driven walker must never enter -- it cannot climb,
-- swim, sit, jump, or fall over on its own; only its death and a shove move it off its feet.
BotConfig.Humanoid = {
	HealthDisplayDistance = 60,
	NameDisplayDistance = 0,
	DisabledStates = { "Climbing", "Swimming", "Seated", "PlatformStanding", "Jumping", "FallingDown", "Ragdoll" },
}
-- The walk and the idle of the engine's stock R15 Animate script: a Forger has no Animate script (its template
-- loses every script), so the server plays these itself. The walk plays at the tier's WalkSpeed over
-- WalkReferenceSpeed, the speed the stock walk is keyed for.
BotConfig.Locomotion = {
	Walk = "rbxassetid://507777826",
	Idle = "rbxassetid://507766666",
	WalkReferenceSpeed = 16,
}

-- The three tiers. The design maths (D-131): every tier walks under a player's 16, so a player can always
-- kite. A lone player facing the base roster (two Smudgers and a Quill) takes one melee chain at a time: a
-- Smudger's is 0.55 + 0.45 + 0.45 s for 18 damage, and its finisher ragdolls them for 1.1 s
-- (CombatConfig.Hit), during which nobody hits them -- 18 damage per 2.55 s, about 7 a second. A Quill's
-- bolt adds 12 every 3.7 s: about 10.3 a second in all, an unguarded player down in about 9.7 s, and
-- guarding removes 70 % of it. Player melee kills a Smudger in about 6 s.
BotConfig.Tiers = {
	-- The brawler.
	Smudger = {
		Role = "Melee",
		Health = 120,
		WalkSpeed = 14,
		Scale = 1,
		AggroRadius = 60,
		LoseSightSeconds = 4,
		AggroMemorySeconds = 6,
		CommitSeconds = 2.5,
		SwitchMarginStuds = 12,
		KeepRange = { 0, 4 },
		StaggerImmune = false,
		Melee = {
			Damage = { 5, 5, 8 },
			Range = 6.5,
			HalfWidth = 3.5,
			HalfHeight = 4,
			WindupSeconds = 0.55,
			ChainGapSeconds = 0.45,
			FinisherGapSeconds = 0.45,
			ChainSlackStuds = 2,
			RecoverySeconds = 1.6,
			FinisherKnockback = 35,
			FinisherLift = 12,
			FinisherStunSeconds = 0.3,
			FinisherBreaksGuard = false,
			FinisherRagdoll = true,
		},
		Bolt = nil,
		RewardKey = "BotSmudger",
	},
	-- The caster: keeps its distance and throws a bolt, and jabs whoever closes in.
	Quill = {
		Role = "Ranged",
		Health = 90,
		WalkSpeed = 13,
		Scale = 1,
		AggroRadius = 70,
		LoseSightSeconds = 4,
		AggroMemorySeconds = 6,
		CommitSeconds = 2.5,
		SwitchMarginStuds = 12,
		KeepRange = { 18, 32 },
		StaggerImmune = false,
		Melee = {
			Damage = { 6 },
			Range = 6,
			HalfWidth = 3,
			HalfHeight = 4,
			WindupSeconds = 0.6,
			ChainGapSeconds = 0,
			FinisherGapSeconds = 0,
			ChainSlackStuds = 0,
			RecoverySeconds = 1.4,
			FinisherKnockback = 20,
			FinisherLift = 6,
			FinisherStunSeconds = 0,
			FinisherBreaksGuard = false,
			FinisherRagdoll = false,
		},
		Bolt = {
			Damage = 12,
			Range = 60,
			MinRange = 8,
			HitRadius = 2,
			HalfHeight = 4,
			SpawnOffset = 2,
			WindupSeconds = 0.7,
			CooldownSeconds = 3,
			KnockbackSpeed = 20,
		},
		RewardKey = "BotQuill",
	},
	-- The heavy: hits shrug off, and its finisher breaks a guard.
	Overwriter = {
		Role = "Melee",
		Health = 350,
		WalkSpeed = 15,
		Scale = 1.2,
		AggroRadius = 70,
		LoseSightSeconds = 5,
		AggroMemorySeconds = 8,
		CommitSeconds = 3,
		SwitchMarginStuds = 14,
		KeepRange = { 0, 5 },
		StaggerImmune = true,
		Melee = {
			Damage = { 7, 7, 12 },
			Range = 7.5,
			HalfWidth = 4,
			HalfHeight = 5,
			WindupSeconds = 0.6,
			ChainGapSeconds = 0.4,
			FinisherGapSeconds = 0.8,
			ChainSlackStuds = 2,
			RecoverySeconds = 2,
			FinisherKnockback = 45,
			FinisherLift = 16,
			FinisherStunSeconds = 0.5,
			FinisherBreaksGuard = true,
			FinisherRagdoll = true,
		},
		Bolt = {
			Damage = 14,
			Range = 60,
			MinRange = 10,
			HitRadius = 2,
			HalfHeight = 4,
			SpawnOffset = 2.4,
			WindupSeconds = 0.8,
			CooldownSeconds = 6,
			KnockbackSpeed = 25,
		},
		RewardKey = "BotOverwriter",
	},
} :: { [string]: TierDef }

return BotConfig
