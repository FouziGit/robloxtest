--!strict
-- Shared type definitions. Only types: no runtime code.

export type PigmentId = "Cinnabar" | "Indigo" | "Umber" | "Verdigris" | "Orpiment"

export type Rgb = { number }

export type KeybindMap = { [string]: string } -- ActionId -> key name

export type SettingsData = {
	Keyboard: KeybindMap,
	Gamepad: KeybindMap,
	MusicVolume: number,
	SfxVolume: number,
	CameraShake: boolean,
	-- A QualityConfig tier name: the ceiling on what this player's client draws. The client may draw
	-- BELOW it when the frame rate asks (QualityController), never above.
	Quality: string,
}

export type ProgressionData = {
	Level: number,
	XP: number, -- XP inside the current level
	TotalXP: number,
}

export type CurrencyData = {
	Folios: number,
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
	Equipped: { [string]: string }, -- slot -> cosmetic id ("Aura", "Trail", "KillEffect", "Title", "Skin:<glyphId>")
	-- The owned ids a developer account bought with Folios the developer list waived (D-129): they leave the
	-- profile when the account leaves the list (CosmeticService.revokeWaived).
	Waived: { string },
}

export type LoadoutData = {
	Slots: { string }, -- glyph ids
	ExtraSlots: number, -- purchased slots (0..PassExtraSlots)
	-- How many slots this player may fill, decided by LoadoutService and replicated. The client used to
	-- recompute it from ExtraSlots, which duplicated the rule and could not express an exception such as a
	-- developer account holding the whole roster.
	SlotLimit: number,
}

export type UnlocksData = {
	Glyphs: { string },
	Pigments: { string },
}

export type RankModeData = {
	Rating: number,
	Matches: number,
	Wins: number,
	Losses: number,
	PeakRating: number,
}

-- Matches played today against each opponent, ranked or not (Pure/OpponentLedger): the UTC day the counts belong to,
-- and the count by opponent user id, as a string. RankingService writes it with every result MatchService pays.
export type RankOpponentsData = { Day: number, Counts: { [string]: number } }

export type RankData = {
	SeasonId: string,
	Modes: { [string]: RankModeData }, -- "Duel1v1" / "Team3v3"
	LastRewardedSeason: string,
	Opponents: RankOpponentsData,
}

export type StatsData = {
	Kills: number,
	Deaths: number,
	GlyphsCast: number,
	-- The longest chain of glyphs this profile has ever cast inside GameConfig.Combo.ChainWindowSeconds:
	-- the personal best of docs/JUICE_PLAN.md phase 8, counted by the server on accepted casts only.
	BestChain: number,
	GlyphsHit: number,
	MatchesPlayed: number,
	BossKills: number,
	PlayTimeSeconds: number,
}

export type QuestProgress = { [string]: number } -- questId -> progress
export type QuestSetData = {
	PeriodKey: string, -- day or week key the set belongs to, with the pool revision it was drawn at (QuestLogic.setKey)
	Progress: QuestProgress,
	Claimed: { [string]: boolean },
	-- The quests of the draw a free reroll replaced, each by the quest that took its place (QuestLogic.reroll).
	Swaps: { [string]: string },
}
export type QuestsData = {
	Daily: QuestSetData,
	Weekly: QuestSetData,
}

export type DailyData = {
	LastClaimDay: number, -- days since epoch
	Streak: number, -- days claimed in a row, a day missed with a Signet included in none
	-- The login calendar (DailyConfig.Calendar): the last of its days claimed (0 before the first), and the Signets
	-- held, each of which keeps the streak through one missed day (Pure/DailyStreak).
	CalendarDay: number,
	Signets: number,
	FirstWinDay: number,
	PremiumBonusDay: number,
	-- Daily caps kept in the profile, so switching servers never resets them (DailyCap.take): the day each
	-- count belongs to, and the count. Folios paid by the Battleground's Forgers (BotConfig.Credit), practice
	-- fights against the Erasure that paid out (WorldBossConfig.Practice), and Folios paid for the Flyleaf's
	-- kills (FlyleafConfig.Rewards).
	ForgerDay: number,
	ForgerFolios: number,
	PracticeDay: number,
	PracticePaid: number,
	-- When a practice last paid out (os.time, 0 for never): WorldBossConfig.Practice.RewardGapSeconds runs from
	-- it, whichever server the next practice is fought on.
	PracticeLastPaidAt: number,
	-- The hub's Trials (TrialPay): the day both counts belong to, the kills paid their whole XP, and the Folios
	-- paid (GameConfig.Enemy.Pay).
	TrialDay: number,
	TrialKills: number,
	TrialFolios: number,
	-- The Folios ranked matches paid (MatchConfig.DailyFolioCap).
	MatchDay: number,
	MatchFolios: number,
	-- The Flyleaf's daily allowance (FlyleafConfig): the day it belongs to and the Folios its kills paid.
	FlyleafDay: number,
	FlyleafFolios: number,
	-- The practice duels against a Forger that paid out today (MatchConfig.Spar.PaidPerDay, SparService).
	SparDay: number,
	SparPaid: number,
}

-- The level road's milestones already paid (ProgressionConfig.Milestones, Pure/LevelRoad): the milestone's level
-- as a string (JSON-safe) -> true. HonoursService is its one writer, and a milestone in it is never paid again.
export type MilestonesData = { [string]: boolean }

-- The best grade each drill of the Lectern reached (DrillConfig, Pure/DrillLogic): drill id -> 1 Draft, 2 Fair
-- Copy, 3 Calligraphy. DrillService is its one writer, and every grade at or under it has been paid.
export type DrillsData = { [string]: number }

-- The plates of the Ex-libris earned (ExLibrisConfig, Pure/ExLibris): plate id -> the os.time() it was granted.
-- HonoursService is its one writer, and a plate in it is never granted again.
export type ExLibrisData = { [string]: number }

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
	-- Bumped by DataService.saveNow before each forced save, and matched against the value ProfileStore
	-- reports as written. It is the only way to tell a save that CONTAINS the caller's mutation from one
	-- that was already in flight when the mutation happened, which matters because a purchase is only
	-- acknowledged to Roblox on a confirmed write.
	SaveToken: number,
	-- True while this profile holds unlocks handed out by the developer list rather than earned. Lets
	-- LoadoutService put them back if the account ever leaves that list.
	DevGranted: boolean,
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
	Milestones: MilestonesData,
	Drills: DrillsData,
	ExLibris: ExLibrisData,
	Purchases: PurchasesData,
	Passes: PassesData,
	Boosts: BoostsData,
	Meta: MetaData,
}

export type GlyphArchetype = "Projectile" | "Aoe" | "Zone" | "Wall" | "Mobility" | "Counter" | "Ultimate" | "Buff"

export type GlyphDef = {
	Id: string,
	Pigment: PigmentId,
	Combo: { PigmentId },
	Cost: number, -- ink
	Cooldown: number, -- seconds
	Damage: number, -- per hit / per tick
	Range: number, -- studs (projectile travel, AoE reach, zone radius…)
	Archetype: GlyphArchetype,
	Effect: string, -- server effect function id
	VfxId: string,
	Unlock: { Kind: "Default" | "Level" | "Pigment", Value: number? },
	NameKey: string,
	DescriptionKey: string,
	Params: { [string]: number }, -- effect-specific tuning (radius, ticks, duration…)
}

export type DamageKind = "Glyph" | "Melee" | "Boss" | "Environment"

export type HitEvent = {
	Source: number, -- attacker UserId (0 for boss/environment)
	Target: number, -- victim UserId (0 for NPC)
	Amount: number,
	Kind: DamageKind,
	Tags: { string },
	Killed: boolean,
}

export type MatchModeId = "Duel1v1" | "Team3v3" | "WorldBoss" | "Spar1v1"

export type MatchResult = {
	-- Identifies which match this result belongs to, so a rating move already written for a player who
	-- walked out of THIS match is not written a second time here (RankingService.applyAbandon).
	MatchId: string,
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
	-- Shown on the match's announcement (E10-S7): their level, and the Strings key of their rank tier, "" for a
	-- player still in the quick duel.
	Level: number,
	RankKey: string,
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
	-- Whether the match moves ratings: false for the quick duel of a newcomer (E10-S7).
	Ranked: boolean,
}

-- Sent once when a match ends (MatchEnded), then the player returns to the hub.
export type MatchOutcome = {
	ModeId: MatchModeId,
	Won: boolean,
	Draw: boolean,
	Scores: { number },
	Xp: number,
	Folios: number,
	RatingBefore: number,
	RatingAfter: number,
	RankKeyBefore: string, -- Strings key of the rank tier
	RankKeyAfter: string,
	FirstWinOfDay: boolean,
	-- The execution: what the server counted for this player over the match, and the grade cut from it
	-- (Pure/Execution). Grade is a Strings key.
	Casts: number,
	Hits: number,
	DamageDealt: number,
	DamageTaken: number,
	Grade: string,
}

-- Queue state of the local player (QueueChanged); Queued = false means "not in any queue".
export type QueueSnapshot = {
	Queued: boolean,
	ModeId: MatchModeId?,
	WaitedSeconds: number,
	QueuedCount: number, -- players waiting in that mode on this server
	NeededCount: number, -- players required to start
}

-- The practice duel against a Forger, as the queue's card shows it (SparChanged): whether it is offered now,
-- whether the player is fighting one, and how many of today's paid spars are left (MatchConfig.Spar).
export type SparSnapshot = {
	Offered: boolean,
	Sparring: boolean,
	PaidLeft: number,
	PaidPerDay: number,
}

export type LeaderboardEntry = {
	Rank: number,
	UserId: number,
	Name: string,
	Rating: number,
	RankKey: string, -- Strings key of the rank tier
}

-- World Boss state (BossChanged): replicated to everyone on the server while the event runs, and to its own
-- participants only while a practice does.
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
	Practice: boolean, -- a practice one player opened from the hub's gate (D-132), not the scheduled event
}

-- The Battleground as its member sees it (BattlegroundChanged), or nil once they are no longer one: how many
-- Forgers stand on the page, and how many this member has defeated since they came in.
export type BattlegroundSnapshot = {
	Standing: number,
	Defeated: number,
}

-- The Flyleaf as its member sees it (FlyleafChanged), or nil once they are no longer one: how many members fight
-- on the page, how many lives this member took since they came in, and how many since they last lost theirs.
export type FlyleafSnapshot = {
	Members: number,
	Kills: number,
	Streak: number,
}

-- The portal circle a player stands in (PortalChanged), or nil once they step out or set off: where it leads
-- (a PortalConfig.PortalId) and how long, from now, they must stay in it before it takes them.
export type PortalSnapshot = {
	Id: string,
	Seconds: number,
}

-- One purchasable entry of today's rotation (ShopChanged).
export type ShopEntry = {
	CosmeticId: string,
	NameKey: string,
	Slot: string,
	Rarity: string,
	PriceFolios: number,
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
