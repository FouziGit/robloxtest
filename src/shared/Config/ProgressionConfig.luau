--!strict
-- Player level, XP sources, unlocks. Pure data + pure curve functions.

local ProgressionConfig = {}

ProgressionConfig.MaxLevel = 100

-- XP needed to go from `level` to `level + 1`. Level 1→2 = 100, 10→11 = 590, 50→51 = 4,120, 99→100 = 9,730.
-- Cumulative to 100 = 524,416 XP (≈ 55-70 h of play at the expected 2-2.5 XP/s in matches).
function ProgressionConfig.xpForLevel(level: number): number
	return math.floor(100 + 25 * (level - 1) ^ 1.35)
end

-- Where a player stood before `gained` XP landed on (level, xp): the result card animates its bar from
-- there to here, so the gain is SEEN rather than read. Walks the curve back level by level, and never
-- below the start of the first one.
function ProgressionConfig.rewind(level: number, xp: number, gained: number): (number, number)
	local remaining = math.max(0, gained)
	local currentLevel = math.max(1, level)
	local currentXp = math.max(0, xp)
	while remaining > 0 do
		if currentXp >= remaining then
			currentXp -= remaining
			remaining = 0
		else
			remaining -= currentXp
			if currentLevel <= 1 then
				currentXp = 0
				break
			end
			currentLevel -= 1
			currentXp = ProgressionConfig.xpForLevel(currentLevel)
		end
	end
	return currentLevel, currentXp
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
	-- The Battleground's Forgers, keyed by BotConfig's RewardKey. XP has no cap there; their Folios below stop
	-- at BotConfig.Credit.DailyFolioCap a day.
	BotSmudger = 30,
	BotQuill = 35,
	BotOverwriter = 100,
}

-- Folios rewards.
ProgressionConfig.Folios = {
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
	BotSmudger = 1,
	BotQuill = 1,
	BotOverwriter = 4,
}

-- Battlepass XP mirrors player XP with this multiplier.
ProgressionConfig.BattlepassXpMultiplier = 1
-- XP sources (the reason ProgressionService.addXp is given) whose XP never reaches the pass: the Trials of the
-- hub are practice, and a pass is earned by playing (E10-S3).
ProgressionConfig.PassExcluded = { DummyKill = true } :: { [string]: boolean }

-- VIP game pass multiplies XP and Folios from every source.
ProgressionConfig.VipXpMultiplier = 2
ProgressionConfig.VipFolioMultiplier = 1.5

-- Timed XP boost (battlepass reward and the XpBoost product, docs/ECONOMY.md §4). It stacks with VIP.
ProgressionConfig.XpBoostMultiplier = 2

-- Level required to unlock each glyph id not unlocked by default (see GlyphConfig.Unlock).
-- Orpiment pigment: free unlock at this level, or instantly via the Orpiment game pass.
ProgressionConfig.OrpimentUnlockLevel = 40

-- The milestones of the level road past the last unlock (docs/GAME_DESIGN.md §9): the glyphs stop at 36 and
-- the pigment at 40, and a veteran then climbed sixty levels for a number. From 45 to MaxLevel, every five
-- levels pays its Folios once (ten per level of the milestone), and three of them a title too (CosmeticConfig,
-- reward only). HonoursService pays them; Pure/LevelRoad sets them on the road beside the unlocks, which is
-- how the Result card always has a next reward to name. docs/ECONOMY.md §2 counts what they add.
export type Milestone = { Level: number, Folios: number, Title: string? }
ProgressionConfig.Milestones = {
	{ Level = 45, Folios = 450 },
	{ Level = 50, Folios = 500, Title = "TitleRubricator" },
	{ Level = 55, Folios = 550 },
	{ Level = 60, Folios = 600 },
	{ Level = 65, Folios = 650 },
	{ Level = 70, Folios = 700 },
	{ Level = 75, Folios = 750, Title = "TitleMasterCopyist" },
	{ Level = 80, Folios = 800 },
	{ Level = 85, Folios = 850 },
	{ Level = 90, Folios = 900 },
	{ Level = 95, Folios = 950 },
	{ Level = 100, Folios = 1000, Title = "TitleHundredLeaves" },
} :: { Milestone }

-- Loadout: how many glyphs a player may equip. Extra slots come from the LoadoutSlots game pass.
ProgressionConfig.Loadout = {
	BaseSlots = 6,
	MaxSlots = 10,
	PassExtraSlots = 4,
}

return ProgressionConfig
