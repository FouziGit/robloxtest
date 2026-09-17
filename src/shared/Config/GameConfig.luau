--!strict
-- Global game constants. Pure data (no requires, no Roblox globals).

local GameConfig = {}

GameConfig.Version = "2.0.0"

-- Season identifier used by battlepass, ranking and leaderboards. Bump to start a new season.
GameConfig.SeasonId = "S1"

GameConfig.Currency = {
	Id = "Ryo",
	NameKey = "currency.ryo",
}

GameConfig.Combo = {
	MaxLength = 4, -- longest recipe
	TimeoutSeconds = 1.2, -- inactivity before a pending sequence resolves or resets
	ExtendWindowSeconds = 0.35, -- shorter wait when the pending sequence is already a recipe (e.g. Fire Fire → Fire Fire Earth)
}

GameConfig.Server = {
	TickRate = 20, -- Heartbeat accumulator ticks per second for gameplay services
	ProfileLoadTimeoutSeconds = 30,
	AbuseKickThreshold = 25, -- rejected remote calls before kick
	AbuseWindowSeconds = 60,
}

GameConfig.Latency = {
	-- Maximum distance (studs) between the server-known root position and the one implied by
	-- the client's last replicated position when validating cast origins.
	OriginToleranceStuds = 12,
	-- Anti-teleport: max studs per second a character may travel (dash included) before flagging.
	MaxSpeedStudsPerSecond = 120,
	-- Consecutive violations before a rubber-band + strike.
	ViolationsBeforeStrike = 3,
}

GameConfig.Movement = {
	WalkSpeed = 16,
	JumpPower = 50,
	DoubleJumpVelocity = 50,
	MaxJumps = 2,
}

GameConfig.Spawn = {
	ProtectionSeconds = 4, -- no damage taken/dealt right after (re)spawn
}

GameConfig.Enemy = {
	Tag = "Enemy",
	DummyCount = 6,
	DummyHealth = 150,
	DummyRingRadius = 22,
	DummyRespawnSeconds = 3,
}

return GameConfig
