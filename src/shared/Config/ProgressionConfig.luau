--!strict
-- Player level, XP sources, unlocks. Pure data + pure curve functions.

local ProgressionConfig = {}

ProgressionConfig.MaxLevel = 100

-- XP needed to go from `level` to `level + 1`. Level 1→2 = 100, 10→11 = 590, 50→51 = 4,120, 99→100 = 9,730.
-- Cumulative to 100 = 524,416 XP (≈ 55-70 h of play at the expected 2-2.5 XP/s in matches).
function ProgressionConfig.xpForLevel(level: number): number
	return math.floor(100 + 25 * (level - 1) ^ 1.35)
end

-- XP rewards. Cast XP is only granted when the glyph hit at least one target (see GlyphService).
ProgressionConfig.XP = {
	GlyphHit = 8,
	DummyKill = 40,
	PlayerKill = 120,
	MatchWin = 350,
	MatchLoss = 120,
	MatchDraw = 200,
	BossParticipation = 400,
	BossKillBonus = 600,
	QuestDaily = 250,
	QuestWeekly = 900,
	FirstWinOfDay = 500,
}

-- Ryo rewards.
ProgressionConfig.Ryo = {
	DummyKill = 2,
	PlayerKill = 15,
	MatchWin = 60,
	MatchLoss = 20,
	MatchDraw = 35,
	BossParticipation = 80,
	BossKillBonus = 150,
	QuestDaily = 50,
	QuestWeekly = 200,
	FirstWinOfDay = 100,
}

-- Battlepass XP mirrors player XP with this multiplier.
ProgressionConfig.BattlepassXpMultiplier = 1

-- VIP game pass multiplies XP and Ryo from every source.
ProgressionConfig.VipXpMultiplier = 2
ProgressionConfig.VipRyoMultiplier = 1.5

-- Timed XP boost (battlepass reward and the XpBoost product, docs/ECONOMY.md §4). It stacks with VIP.
ProgressionConfig.XpBoostMultiplier = 2

-- Level required to unlock each glyph id not unlocked by default (see GlyphConfig.Unlock).
-- Orpiment pigment: free unlock at this level, or instantly via the Orpiment game pass.
ProgressionConfig.OrpimentUnlockLevel = 40

-- Loadout: how many glyphs a player may equip. Extra slots come from the LoadoutSlots game pass.
ProgressionConfig.Loadout = {
	BaseSlots = 6,
	MaxSlots = 10,
	PassExtraSlots = 4,
}

return ProgressionConfig
