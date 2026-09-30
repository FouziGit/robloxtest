--!strict
-- Global game constants. Pure data (no requires, no Roblox globals).

local GameConfig = {}

GameConfig.Version = "2.0.0"

-- Season identifier used by battlepass, ranking and leaderboards. Bump to start a new season.
GameConfig.SeasonId = "S1"

-- Season that just ended, set when SeasonId is bumped ("" on the very first season). RankingService
-- pays the end-of-season rewards of this season once per player, then records it in the profile.
GameConfig.PreviousSeasonId = ""

GameConfig.Currency = {
	Id = "Folios",
	NameKey = "currency.folio",
}

GameConfig.Combo = {
	MinLength = 2, -- shortest recipe: a shorter sequence can never resolve
	MaxLength = 4, -- longest recipe
	TimeoutSeconds = 1.2, -- inactivity before a pending sequence resolves or resets
	ExtendWindowSeconds = 0.35, -- shorter wait when the pending sequence is already a recipe (e.g. Cinnabar Cinnabar → Cinnabar Cinnabar Umber)
	-- A glyph cast this soon after the previous one is a chain: the server refunds ChainInkRefund. The
	-- reward for tight execution, measured where it can be trusted (two casts the server accepted).
	ChainWindowSeconds = 1.0,
	ChainInkRefund = 5,
}

GameConfig.Server = {
	TickRate = 20, -- Heartbeat accumulator ticks per second for gameplay services
	ProfileLoadTimeoutSeconds = 30,
	AbuseKickThreshold = 25, -- malformed remote calls before kick
	RateLimitKickThreshold = 600, -- rate-limit overflows before kick (legitimate fast input must never reach it)
	AbuseWindowSeconds = 60,
	CombatStateHz = 5, -- CombatState replication rate per player
	-- DataService.saveNow waits this long for ProfileStore to confirm the write before reporting
	-- failure. A purchase is only acknowledged to Roblox once the write is confirmed.
	SaveConfirmTimeoutSeconds = 10,
	SaveConfirmPollSeconds = 0.1,
	-- How long a departure waits before it counts as a player leaving: the leaver's session stays loaded,
	-- and a forfeit it causes is not declared, until then. A shutdown or a server migration removes the
	-- players a moment before game:BindToClose says so, and a whole match walking out inside this window is
	-- the server's doing, never an abandon (docs/QA.md R3). Also what a player who rejoins another server
	-- at once may wait on top of ProfileStore's own session hand-over.
	LeaveGraceSeconds = 2,
}

GameConfig.Vfx = {
	-- Players farther than this from a packet origin do not receive it. Sized on the scene scale: the
	-- largest arena (MatchConfig.Arenas.Boss, a 160x160 floor behind 30-stud walls) spans about 230
	-- studs corner to corner, and live arenas sit MatchConfig.ArenaSpacingStuds (400) apart in altitude,
	-- so this covers everyone in the scene a packet fires in and nobody in the scene above or below.
	BroadcastRadiusStuds = 250,
	LifetimeSeconds = 6, -- hard cap on any client effect's lifetime (cleanup)
}

GameConfig.Latency = {
	-- Extra studs an ACTION may be resolved from beyond what the speed ceiling allows, to absorb the
	-- client round trip. It is never banked: an origin that needs it is honoured once until the trusted
	-- anchor catches up again (OriginGuard.follow), so a client cannot collect it sample after sample.
	-- Kept just under CombatConfig.Melee.Range (7) so at worst it lends a swing one extra body width, once.
	OriginToleranceStuds = 6,
	-- Anti-teleport ceiling, applied to HORIZONTAL travel only: vertical speed is gravity-driven and
	-- unbounded (a fall from an arena at altitude 900 reaches several hundred studs per second), while the
	-- exploit this bounds is repositioning onto a target.
	--
	-- It bounds UNASSISTED movement, not the fastest thing in the game: every burst the server itself
	-- grants (dash 22 studs, knockback, a glyph gap-close) adds its own distance on top through
	-- CombatService.grantMovement, so this does not have to cover them. The fastest a character moves on
	-- its own is Movement.WalkSpeed (16), which a jump and a fall preserve rather than exceed, plus at most
	-- the boss's own MoveSpeed (18) if it shoves someone. 40 leaves room for that and for jitter.
	--
	-- The value matters more than it looks: the trusted anchor chases the observation at this speed, so a
	-- client that holds a spoofed position long enough eventually has it accepted. At 40 a 90-stud offset
	-- is believed on the 45th tick, after 2.25 seconds of clamped, whiffing attacks, which is no longer a
	-- teleport; at 120 it took 0.75 s.
	MaxSpeedStudsPerSecond = 40,
	-- How much elapsed time the travel budget may accumulate. It must accumulate at all, because an uplink
	-- stall replicates nothing and then delivers the catch-up as one jump: measured against a single tick
	-- that honest burst reads as a teleport. It must be capped, because otherwise a player who stands still
	-- for ten seconds banks four hundred studs of free relocation. Half a second covers a stall a player
	-- can still play through and caps the bank at MaxSpeedStudsPerSecond / 2 studs.
	MaxBudgetSeconds = 0.5,
	-- Implausible origins on an ACTION (melee, cast) inside ViolationWindowSeconds before
	-- AntiCheatService is struck. Counted over a window rather than consecutively, because a client that
	-- returns to a legal position between two swings would otherwise reset the count every time and never
	-- be struck. The per-tick sampling never strikes and never absolves: it only moves the anchor.
	-- Clamping the origin already removes the exploit on its own, so the strike is only there for a
	-- client that keeps attacking from positions the server never believed.
	ViolationsBeforeStrike = 3,
	ViolationWindowSeconds = 10,
}

GameConfig.Movement = {
	WalkSpeed = 16,
	JumpPower = 50,
	DoubleJumpVelocity = 50,
	MaxJumps = 2,
	-- The collision group of every part of a player's body, which does not collide with itself: players pass
	-- through one another and nobody flings anybody (D-215). The Forgers and the Erasure stay Default.
	CharacterCollisionGroup = "Characters",
}

GameConfig.Spawn = {
	ProtectionSeconds = 4, -- no damage taken/dealt right after (re)spawn
	SafeZoneMarginStuds = 10, -- PvP disabled within DummyRingRadius + this margin of the hub spawn
	-- A Humanoid its client took out of the body and did not give back within this is replaced with a new body and a
	-- Schema strike (MovementService, D-216): without one, nothing can hurt the body.
	HumanoidReturnSeconds = 0.5,
}

GameConfig.Enemy = {
	Tag = "Enemy",
	DummyCount = 6,
	DummyHealth = 150,
	DummyRingRadius = 22,
	DummyRespawnSeconds = 3,
}

return GameConfig
