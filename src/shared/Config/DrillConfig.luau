--!strict
-- The Drills at the Lectern (docs/GAME_DESIGN.md §9 bis). Pure data: no require, no Roblox global.
--
-- A drill is a set of repetitions of one thing, done on the hub's training proofs: a glyph's recipe (one drill
-- per glyph), or a move of the kit -- the four strokes of the melee string, the dash that cancels the finisher's
-- recovery, a chain of three glyphs. The server counts a repetition, and a miss, from the events GlyphService and
-- CombatService fire on what they accepted (DrillService, Pure/DrillLogic), never from the client. A finished set
-- is graded, and each grade of each drill is paid once (ProfileData.Drills keeps the best one reached):
--
--   Draft        Brouillon      the set finished, whatever it cost
--   FairCopy     Mise au net    at most Slips misses on the way
--   Calligraphy  Calligraphie   no miss at all, from the first counted event to the last repetition inside Par
--
-- Nothing here is a gameplay number: a drill is played with the game's own glyphs, costs, cooldowns and ink.

export type GradeDef = { Id: string, NameKey: string, Folios: number, Xp: number }
export type KitKind = "String" | "Cancel" | "Chain"
export type KitDef = {
	Id: string,
	Kind: KitKind,
	NameKey: string,
	HintKey: string,
	Reps: number,
	ParSeconds: number,
	-- A Chain drill's length: how many glyphs one chain must reach.
	Length: number?,
}

local DrillConfig = {}

-- In order, from the lowest. docs/ECONOMY.md §2 counts what a drill pays at most.
DrillConfig.Grades = {
	{ Id = "Draft", NameKey = "drills.grade.draft", Folios = 15, Xp = 50 },
	{ Id = "FairCopy", NameKey = "drills.grade.fairCopy", Folios = 30, Xp = 100 },
	{ Id = "Calligraphy", NameKey = "drills.grade.calligraphy", Folios = 60, Xp = 200 },
} :: { GradeDef }

-- The misses a Fair Copy may still have.
DrillConfig.Slips = 1

-- A glyph's recipe drill: this many casts of it that land on a body (or, for a glyph that deals no damage, that
-- the server accepts), inside Par = the glyph's cooldown between each two, plus this slack.
DrillConfig.Recipe = {
	Reps = 3,
	ParSlackSeconds = 8,
	HintKey = "drills.recipe.hint",
	UtilityHintKey = "drills.recipe.hintUtility",
}

-- The kit's drills, before the recipes on the Lectern. Par is measured against the kit's own timings in
-- tests/Drills.spec.luau: never tighter than twice what the fastest hands can do.
DrillConfig.Kit = {
	{
		Id = "KitString",
		Kind = "String",
		NameKey = "drills.kit.string",
		HintKey = "drills.kit.string.hint",
		Reps = 3,
		ParSeconds = 12,
	},
	{
		Id = "KitCancel",
		Kind = "Cancel",
		NameKey = "drills.kit.cancel",
		HintKey = "drills.kit.cancel.hint",
		Reps = 3,
		ParSeconds = 15,
	},
	{
		Id = "KitChain",
		Kind = "Chain",
		NameKey = "drills.kit.chain",
		HintKey = "drills.kit.chain.hint",
		Reps = 2,
		ParSeconds = 20,
		Length = 3,
	},
} :: { KitDef }

-- A set nobody touches for this long is put down (the Lectern's drill is not a state to forget in the hub).
DrillConfig.IdleSeconds = 60

-- How often DrillService looks for a set left idle or taken out of the hub.
DrillConfig.CheckSeconds = 1

return DrillConfig
