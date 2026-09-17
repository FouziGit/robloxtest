--!strict
-- Shared type definitions. Only types: no runtime code.

export type ElementId = "Fire" | "Water" | "Earth" | "Wind" | "Lightning"

export type Rgb = { number }

export type KeybindMap = { [string]: string } -- ActionId -> key name

export type SettingsData = {
	Keyboard: KeybindMap,
	Gamepad: KeybindMap,
	MusicVolume: number,
	SfxVolume: number,
	CameraShake: boolean,
}

export type ProgressionData = {
	Level: number,
	XP: number, -- XP inside the current level
	TotalXP: number,
}

export type CurrencyData = {
	Ryo: number,
}

export type BattlepassSeasonData = {
	XP: number,
	Tier: number,
	Premium: boolean,
	ClaimedFree: { [string]: boolean }, -- tier as string key (JSON-safe)
	ClaimedPremium: { [string]: boolean },
}

export type CosmeticsData = {
	Owned: { string },
	Equipped: { [string]: string }, -- slot -> cosmetic id ("Aura", "Trail", "KillEffect", "Title", "Skin:<jutsuId>")
}

export type LoadoutData = {
	Slots: { string }, -- jutsu ids
	ExtraSlots: number, -- purchased slots (0..PassExtraSlots)
}

export type UnlocksData = {
	Jutsus: { string },
	Elements: { string },
}

export type RankModeData = {
	Rating: number,
	Matches: number,
	Wins: number,
	Losses: number,
	PeakRating: number,
}

export type RankData = {
	SeasonId: string,
	Modes: { [string]: RankModeData }, -- "Duel1v1" / "Team3v3"
	LastRewardedSeason: string,
}

export type StatsData = {
	Kills: number,
	Deaths: number,
	JutsusCast: number,
	JutsusHit: number,
	MatchesPlayed: number,
	BossKills: number,
	PlayTimeSeconds: number,
}

export type QuestProgress = { [string]: number } -- questId -> progress
export type QuestSetData = {
	PeriodKey: string, -- day or week key the set belongs to
	Progress: QuestProgress,
	Claimed: { [string]: boolean },
}
export type QuestsData = {
	Daily: QuestSetData,
	Weekly: QuestSetData,
}

export type DailyData = {
	LastClaimDay: number, -- days since epoch
	Streak: number,
	FirstWinDay: number,
	PremiumBonusDay: number,
}

export type PurchasesData = {
	Receipts: { string }, -- processed PurchaseIds (bounded ring, newest last)
	ProductCounts: { [string]: number }, -- productKey -> times purchased
}

export type PassesData = { [string]: boolean } -- passKey -> owned (cache)

-- Timed multipliers. Expiries are os.time() stamps so they survive a rejoin; a multiplier of 1 or an
-- expiry in the past means "no boost". Granted by developer products and battle pass rewards.
export type BoostsData = {
	XpUntil: number,
	XpMultiplier: number,
}

export type MetaData = {
	FirstJoin: number,
	LastJoin: number,
	SessionCount: number,
	LegacyImported: boolean,
	FirstSessionPromptGate: boolean, -- true once the first-session no-prompt window has elapsed
}

export type ProfileData = {
	DataVersion: number,
	Settings: SettingsData,
	Progression: ProgressionData,
	Currency: CurrencyData,
	Battlepass: { [string]: BattlepassSeasonData }, -- seasonId -> data
	Cosmetics: CosmeticsData,
	Loadout: LoadoutData,
	Unlocks: UnlocksData,
	Rank: RankData,
	Stats: StatsData,
	Quests: QuestsData,
	Daily: DailyData,
	Purchases: PurchasesData,
	Passes: PassesData,
	Boosts: BoostsData,
	Meta: MetaData,
}

export type JutsuArchetype = "Projectile" | "Aoe" | "Zone" | "Wall" | "Mobility" | "Counter" | "Ultimate" | "Buff"

export type JutsuDef = {
	Id: string,
	Element: ElementId,
	Combo: { ElementId },
	Cost: number, -- chakra
	Cooldown: number, -- seconds
	Damage: number, -- per hit / per tick
	Range: number, -- studs (projectile travel, AoE reach, zone radius…)
	Archetype: JutsuArchetype,
	Effect: string, -- server effect function id
	VfxId: string,
	SfxId: string,
	Unlock: { Kind: "Default" | "Level" | "Element", Value: number? },
	NameKey: string,
	DescriptionKey: string,
	Params: { [string]: number }, -- effect-specific tuning (radius, ticks, duration…)
}

export type DamageKind = "Jutsu" | "Melee" | "Boss" | "Environment"

export type HitEvent = {
	Source: number, -- attacker UserId (0 for boss/environment)
	Target: number, -- victim UserId (0 for NPC)
	Amount: number,
	Kind: DamageKind,
	Tags: { string },
	Killed: boolean,
}

export type MatchModeId = "Duel1v1" | "Team3v3" | "WorldBoss"

export type MatchResult = {
	ModeId: MatchModeId,
	WinnerTeam: number?, -- nil = draw
	Teams: { { number } }, -- team index -> user ids
	DurationSeconds: number,
}

-- Lifecycle of a match, in order. "Countdown" freezes input, "Playing" is the round itself,
-- "RoundOver" shows the round winner between rounds, "Result" is the end screen before the hub.
export type MatchPhase = "Countdown" | "Playing" | "RoundOver" | "Result"

export type MatchPlayerSnapshot = {
	UserId: number,
	Name: string, -- DisplayName, already resolved server-side (never a Strings key)
	Team: number,
	Alive: boolean,
	Health: number,
	MaxHealth: number,
}

-- Replicated to every participant a few times per second (MatchChanged).
export type MatchSnapshot = {
	MatchId: string,
	ModeId: MatchModeId,
	Phase: MatchPhase,
	SecondsLeft: number, -- of the current phase
	Round: number,
	RoundsToWin: number,
	Scores: { number }, -- team index -> rounds won
	Teams: { { MatchPlayerSnapshot } },
	LocalTeam: number,
}

-- Sent once when a match ends (MatchEnded), then the player returns to the hub.
export type MatchOutcome = {
	ModeId: MatchModeId,
	Won: boolean,
	Draw: boolean,
	Scores: { number },
	Xp: number,
	Ryo: number,
	RatingBefore: number,
	RatingAfter: number,
	RankKeyBefore: string, -- Strings key of the rank tier
	RankKeyAfter: string,
	FirstWinOfDay: boolean,
}

-- Queue state of the local player (QueueChanged); Queued = false means "not in any queue".
export type QueueSnapshot = {
	Queued: boolean,
	ModeId: MatchModeId?,
	WaitedSeconds: number,
	QueuedCount: number, -- players waiting in that mode on this server
	NeededCount: number, -- players required to start
}

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	Name: string,
	Rating: number,
	RankKey: string, -- Strings key of the rank tier
}

-- World Boss state replicated to everyone on the server while the event runs (BossChanged).
export type BossPhaseSnapshot = "Announced" | "Fighting" | "Defeated" | "Expired"

export type BossSnapshot = {
	Phase: BossPhaseSnapshot,
	SecondsLeft: number,
	Health: number,
	MaxHealth: number,
	PhaseIndex: number,
	Participants: number,
	TelegraphKey: string?, -- Strings key of the attack being telegraphed, nil when none
	MyShare: number, -- 0..1, the receiving player's damage contribution
}

-- One purchasable entry of today's rotation (ShopChanged).
export type ShopEntry = {
	CosmeticId: string,
	NameKey: string,
	Slot: string,
	Rarity: string,
	PriceRyo: number,
	ProductKey: string, -- MonetizationConfig.Products key for the Robux path
	Owned: boolean,
}

export type ShopSnapshot = {
	DayKey: string,
	Entries: { ShopEntry },
}

export type LeaderboardSnapshot = {
	BoardId: string,
	UpdatedAt: number, -- os.time of the last refresh
	Entries: { LeaderboardEntry },
}

return nil
