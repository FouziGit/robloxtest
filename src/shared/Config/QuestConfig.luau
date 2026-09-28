--!strict
-- Daily / weekly quests. Pure data. Quests are selected deterministically per period from the pool
-- (QuestLogic.select), so every player sees the same set for a given day or week -- but on the day a deploy
-- grows the pool, when a set drawn before it keeps its quests (PoolRevision below).

export type Period = "Daily" | "Weekly"
export type QuestDef = { Id: string, Period: Period, Event: string, Target: number, NameKey: string, Since: number? }

local QuestConfig = {}

-- Events emitted by gameplay services: GlyphCast, GlyphHit, Chain, DummyKill, PlayerKill, MatchPlayed,
-- MatchWin, DamageDealt, Dash, DashCancel, MeleeHit, BossParticipation, BossKill, BotKill.
QuestConfig.Pool = {
	{ Id = "DailyCastGlyphs", Period = "Daily", Event = "GlyphCast", Target = 30, NameKey = "quest.castGlyphs" },
	{ Id = "DailyHitGlyphs", Period = "Daily", Event = "GlyphHit", Target = 20, NameKey = "quest.hitGlyphs" },
	{ Id = "DailyDummies", Period = "Daily", Event = "DummyKill", Target = 10, NameKey = "quest.defeatDummies" },
	{ Id = "DailyWin", Period = "Daily", Event = "MatchWin", Target = 1, NameKey = "quest.winMatches" },
	{ Id = "DailyPlay", Period = "Daily", Event = "MatchPlayed", Target = 3, NameKey = "quest.playMatches" },
	{ Id = "DailyDamage", Period = "Daily", Event = "DamageDealt", Target = 1500, NameKey = "quest.dealDamage" },
	{ Id = "DailyDash", Period = "Daily", Event = "Dash", Target = 15, NameKey = "quest.useDash" },
	{ Id = "DailyMelee", Period = "Daily", Event = "MeleeHit", Target = 25, NameKey = "quest.landMelee" },
	-- Execution challenges (docs/JUICE_PLAN.md phase 8): the chain and the cancel, both server-counted.
	{ Id = "DailyChain", Period = "Daily", Event = "Chain", Target = 10, NameKey = "quest.chainCasts" },
	{ Id = "DailyCancel", Period = "Daily", Event = "DashCancel", Target = 5, NameKey = "quest.cancelRecovery" },
	-- The Battleground's Forgers (D-131), paid to the killer and every assist.
	{
		Id = "DailyForgers",
		Period = "Daily",
		Event = "BotKill",
		Target = 15,
		NameKey = "quest.defeatForgers",
		Since = 2,
	},
	{ Id = "WeeklyWins", Period = "Weekly", Event = "MatchWin", Target = 10, NameKey = "quest.winMatches" },
	{ Id = "WeeklyKills", Period = "Weekly", Event = "PlayerKill", Target = 25, NameKey = "quest.defeatPlayers" },
	{ Id = "WeeklyBoss", Period = "Weekly", Event = "BossParticipation", Target = 3, NameKey = "quest.joinBoss" },
	{ Id = "WeeklyCasts", Period = "Weekly", Event = "GlyphCast", Target = 200, NameKey = "quest.castGlyphs" },
	{ Id = "WeeklyDamage", Period = "Weekly", Event = "DamageDealt", Target = 10000, NameKey = "quest.dealDamage" },
} :: { QuestDef }

-- The pool's revision. A set is drawn from the pool of the revision its day or week started under, and
-- keeps it to the end (QuestLogic.setKey): a quest added by a deploy first appears the next day or week,
-- and today's quests never change under a player who has claimed them. So a new quest carries `Since`
-- set to the next revision, and PoolRevision moves to it in the same change. An entry is never removed
-- nor moved among its period's: that would change the draw of every revision at once
-- (tests/QuestLogic.spec.luau pins each revision's pool).
QuestConfig.PoolRevision = 2

QuestConfig.Periods = {
	Daily = { Count = 3, RewardXp = 250, RewardFolios = 50 },
	Weekly = { Count = 3, RewardXp = 900, RewardFolios = 200 },
}

return QuestConfig
