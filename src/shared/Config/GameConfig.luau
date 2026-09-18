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
	Id = "Ryo",
	NameKey = "currency.ryo",
}

GameConfig.Combo = {
	MinLength = 2, -- shortest recipe: a shorter sequence can never resolve
	MaxLength = 4, -- longest recipe
	TimeoutSeconds = 1.2, -- inactivity before a pending sequence resolves or resets
	ExtendWindowSeconds = 0.35, -- shorter wait when the pending sequence is already a recipe (e.g. Fire Fire → Fire Fire Earth)
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
}

GameConfig.Vfx = {
	-- Players farther than this from a packet origin do not receive it. Sized on the scene scale: the
	-- largest arena (MatchConfig.Arenas.Boss, a 160x160 floor behind 30-stud walls) spans about 230
	-- studs corner to corner, and live arenas sit MatchConfig.ArenaSpacingStuds (400) apart in altitude,
	-- so this covers everyone in the scene a packet fires in and nobody in the scene above or below.
	BroadcastRadiusStuds = 250,
	-- Client-side gate: an effect whose centre is farther than this from the local character is not
	-- stepped per frame (its tweens still play). Covers both PvP arenas whole (Duel 113 studs corner to
	-- corner, Team 170), so ranked play never freezes an effect a player could be watching.
	AnimateRadiusStuds = 180,
	LifetimeSeconds = 6, -- hard cap on any client effect's lifetime (cleanup)
}

GameConfig.Latency = {
	-- Maximum distance (studs) between the server-known root position and the one implied by
	-- the client's last replicated position when validating cast origins.
	OriginToleranceStuds = 12,
	-- Anti-teleport: max studs per second a character may travel (dash included) before flagging.
	MaxSpeedStudsPerSecond = 120,
	-- Consecutive implausible origins on an ACTION (melee, cast) before AntiCheatService is struck. The
	-- per-tick sampling never strikes: a long fall is faster than MaxSpeedStudsPerSecond and would
	-- otherwise kick an honest player. Clamping the origin already removes the exploit on its own, so the
	-- strike is only there for a client that keeps attacking from positions the server never believed.
	ViolationsBeforeStrike = 3,
	-- Server-granted movement (dash, knockback) is added to the travel budget for its duration plus this
	-- grace, which covers the client round trip. A dash is 22 studs in 0.22 s, i.e. 100 studs per second,
	-- and a client that replicates it in a single frame must not look like a teleport.
	AllowanceGraceSeconds = 0.5,
}

GameConfig.Movement = {
	WalkSpeed = 16,
	JumpPower = 50,
	DoubleJumpVelocity = 50,
	MaxJumps = 2,
}

GameConfig.Spawn = {
	ProtectionSeconds = 4, -- no damage taken/dealt right after (re)spawn
	SafeZoneMarginStuds = 10, -- PvP disabled within DummyRingRadius + this margin of the hub spawn
}

GameConfig.Enemy = {
	Tag = "Enemy",
	DummyCount = 6,
	DummyHealth = 150,
	DummyRingRadius = 22,
	DummyRespawnSeconds = 3,
}

return GameConfig
