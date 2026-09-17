--!strict
-- Daily / weekly quests. Pure data. Quests are selected deterministically per period from the pool
-- (QuestLogic.select), so every player sees the same set for a given day or week.

export type Period = "Daily" | "Weekly"
export type QuestDef = { Id: string, Period: Period, Event: string, Target: number, NameKey: string }

local QuestConfig = {}

-- Events emitted by gameplay services: JutsuCast, JutsuHit, DummyKill, PlayerKill, MatchPlayed,
-- MatchWin, DamageDealt, Dash, MeleeHit, BossParticipation, BossKill.
QuestConfig.Pool = {
	{ Id = "DailyCastJutsus", Period = "Daily", Event = "JutsuCast", Target = 30, NameKey = "quest.castJutsus" },
	{ Id = "DailyHitJutsus", Period = "Daily", Event = "JutsuHit", Target = 20, NameKey = "quest.hitJutsus" },
	{ Id = "DailyDummies", Period = "Daily", Event = "DummyKill", Target = 10, NameKey = "quest.defeatDummies" },
	{ Id = "DailyWin", Period = "Daily", Event = "MatchWin", Target = 1, NameKey = "quest.winMatches" },
	{ Id = "DailyPlay", Period = "Daily", Event = "MatchPlayed", Target = 3, NameKey = "quest.playMatches" },
	{ Id = "DailyDamage", Period = "Daily", Event = "DamageDealt", Target = 1500, NameKey = "quest.dealDamage" },
	{ Id = "DailyDash", Period = "Daily", Event = "Dash", Target = 15, NameKey = "quest.useDash" },
	{ Id = "DailyMelee", Period = "Daily", Event = "MeleeHit", Target = 25, NameKey = "quest.landMelee" },
	{ Id = "WeeklyWins", Period = "Weekly", Event = "MatchWin", Target = 10, NameKey = "quest.winMatches" },
	{ Id = "WeeklyKills", Period = "Weekly", Event = "PlayerKill", Target = 25, NameKey = "quest.defeatPlayers" },
	{ Id = "WeeklyBoss", Period = "Weekly", Event = "BossParticipation", Target = 3, NameKey = "quest.joinBoss" },
	{ Id = "WeeklyCasts", Period = "Weekly", Event = "JutsuCast", Target = 200, NameKey = "quest.castJutsus" },
	{ Id = "WeeklyDamage", Period = "Weekly", Event = "DamageDealt", Target = 10000, NameKey = "quest.dealDamage" },
} :: { QuestDef }

QuestConfig.Periods = {
	Daily = { Count = 3, RewardXp = 250, RewardRyo = 50 },
	Weekly = { Count = 3, RewardXp = 900, RewardRyo = 200 },
}

return QuestConfig
