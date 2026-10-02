--!strict
-- Daily / weekly quests. Pure data. Quests are selected deterministically per period from the pool
-- (QuestLogic.select), so every player sees the same set for a given day or week -- but on the day a deploy
-- grows the pool, when a set drawn before it keeps its quests (PoolRevision below).
--
-- `Needs` says whether a player alone on a server can finish the quest (Solo) or needs others there (Players:
-- a match, a player to defeat, the Erasure's scheduled event, which waits for WorldBossConfig.Schedule.MinPlayers).

export type Period = "Daily" | "Weekly"
export type Needs = "Solo" | "Players"
export type QuestDef = {
	Id: string,
	Period: Period,
	Event: string,
	Target: number,
	NameKey: string,
	Needs: Needs,
	Since: number?,
}

local QuestConfig = {}

-- Events emitted by gameplay services: GlyphCast, GlyphHit, Chain, DummyKill, PlayerKill, MatchPlayed,
-- MatchWin, DamageDealt, Dash, DashCancel, MeleeHit, BossParticipation, BossKill, BotKill.
QuestConfig.Pool = {
	{
		Id = "DailyCastGlyphs",
		Period = "Daily",
		Event = "GlyphCast",
		Target = 30,
		NameKey = "quest.castGlyphs",
		Needs = "Solo",
	},
	{
		Id = "DailyHitGlyphs",
		Period = "Daily",
		Event = "GlyphHit",
		Target = 20,
		NameKey = "quest.hitGlyphs",
		Needs = "Solo",
	},
	{
		Id = "DailyDummies",
		Period = "Daily",
		Event = "DummyKill",
		Target = 10,
		NameKey = "quest.defeatDummies",
		Needs = "Solo",
	},
	{
		Id = "DailyWin",
		Period = "Daily",
		Event = "MatchWin",
		Target = 1,
		NameKey = "quest.winMatch",
		Needs = "Players",
	},
	{
		Id = "DailyPlay",
		Period = "Daily",
		Event = "MatchPlayed",
		Target = 3,
		NameKey = "quest.playMatches",
		Needs = "Players",
	},
	{
		Id = "DailyDamage",
		Period = "Daily",
		Event = "DamageDealt",
		Target = 1500,
		NameKey = "quest.dealDamage",
		Needs = "Solo",
	},
	{
		Id = "DailyDash",
		Period = "Daily",
		Event = "Dash",
		Target = 15,
		NameKey = "quest.useDash",
		Needs = "Solo",
	},
	{
		Id = "DailyMelee",
		Period = "Daily",
		Event = "MeleeHit",
		Target = 25,
		NameKey = "quest.landMelee",
		Needs = "Solo",
	},
	-- Execution challenges (docs/JUICE_PLAN.md phase 8): the chain and the cancel, both server-counted.
	{
		Id = "DailyChain",
		Period = "Daily",
		Event = "Chain",
		Target = 10,
		NameKey = "quest.chainCasts",
		Needs = "Solo",
	},
	{
		Id = "DailyCancel",
		Period = "Daily",
		Event = "DashCancel",
		Target = 5,
		NameKey = "quest.cancelRecovery",
		Needs = "Solo",
	},
	-- The Battleground's Forgers (D-131), paid to the killer and every assist.
	{
		Id = "DailyForgers",
		Period = "Daily",
		Event = "BotKill",
		Target = 15,
		NameKey = "quest.defeatForgers",
		Needs = "Solo",
		Since = 2,
	},
	{
		Id = "WeeklyWins",
		Period = "Weekly",
		Event = "MatchWin",
		Target = 10,
		NameKey = "quest.winMatches",
		Needs = "Players",
	},
	{
		Id = "WeeklyKills",
		Period = "Weekly",
		Event = "PlayerKill",
		Target = 25,
		NameKey = "quest.defeatPlayers",
		Needs = "Players",
	},
	{
		Id = "WeeklyBoss",
		Period = "Weekly",
		Event = "BossParticipation",
		Target = 3,
		NameKey = "quest.joinBoss",
		Needs = "Players",
	},
	{
		Id = "WeeklyCasts",
		Period = "Weekly",
		Event = "GlyphCast",
		Target = 200,
		NameKey = "quest.castGlyphs",
		Needs = "Solo",
	},
	{
		Id = "WeeklyDamage",
		Period = "Weekly",
		Event = "DamageDealt",
		Target = 10000,
		NameKey = "quest.dealDamage",
		Needs = "Solo",
	},
	-- Revision 3 (E10-S10): a week a player alone can finish, beside the one played with others.
	{
		Id = "WeeklyForgers",
		Period = "Weekly",
		Event = "BotKill",
		Target = 60,
		NameKey = "quest.defeatForgers",
		Needs = "Solo",
		Since = 3,
	},
	{
		Id = "WeeklyChains",
		Period = "Weekly",
		Event = "Chain",
		Target = 40,
		NameKey = "quest.chainCasts",
		Needs = "Solo",
		Since = 3,
	},
	{
		Id = "WeeklyMelee",
		Period = "Weekly",
		Event = "MeleeHit",
		Target = 150,
		NameKey = "quest.landMelee",
		Needs = "Solo",
		Since = 3,
	},
} :: { QuestDef }

-- The pool's revision. A set is drawn from the pool of the revision its day or week started under, and
-- keeps it to the end (QuestLogic.setKey): a quest added by a deploy first appears the next day or week,
-- and today's quests never change under a player who has claimed them. So a new quest carries `Since`
-- set to the next revision, and PoolRevision moves to it in the same change. An entry is never removed
-- nor moved among its period's: that would change the draw of every revision at once
-- (tests/QuestLogic.spec.luau pins each revision's pool).
QuestConfig.PoolRevision = 3

-- From revision 3 on, every draw holds at least two Solo quests (QuestLogic.select): a player alone on a server
-- can always finish two of their three. Earlier revisions draw exactly as they did.
QuestConfig.SoloFloor = { Since = 3, Count = 2 }

-- Free rerolls a set may spend in its period (QuestLogic.reroll): one a day, on a daily quest. It swaps the
-- quest for a Solo one not drawn today, never a claimed or completed quest. A weekly quest has the week.
QuestConfig.Rerolls = { Daily = 1, Weekly = 0 }

QuestConfig.Periods = {
	Daily = { Count = 3, RewardXp = 250, RewardFolios = 50 },
	Weekly = { Count = 3, RewardXp = 900, RewardFolios = 200 },
}

return QuestConfig
