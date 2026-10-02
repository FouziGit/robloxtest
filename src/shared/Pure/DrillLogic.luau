--!strict
-- DrillLogic: what a drill counts and how a finished set is graded (DrillConfig, docs/GAME_DESIGN.md §9 bis). Pure
-- module: no require, no Roblox global, tested under Lune (tests/Drills.spec.luau). DrillService feeds it the events
-- the server fired on what it accepted; the Lectern reads the same drills to list them.
--
--   recipeDrill / kitDrill  a drill, from a glyph's facts or a DrillConfig.Kit entry
--   start                   a set, begun now
--   feed                    one event of the player's: "Rep", "Miss", or nil when it says nothing to this drill
--   done                    the set holds its repetitions
--   grade                   the grade a finished set earned: 1 Draft, 2 Fair Copy, 3 Calligraphy
--   toPay                   the grades a new result pays, over the best one already paid: each grade once
--
-- A drill reads four events:
--   Landed  a glyph's effect resolved, with how many bodies it struck (GlyphService.CastLanded)
--   Cast    a glyph the server accepted, with the length of the chain it belongs to (GlyphService.Cast)
--   Swing   a melee swing the server accepted: which of the string, whether it was its last, how many it struck
--   Dash    a dash the server granted, and whether it cancelled a finisher's recovery (CombatService.Dashed)

export type Kind = "Recipe" | "String" | "Cancel" | "Chain"
export type Drill = {
	Id: string,
	Kind: Kind,
	NameKey: string,
	HintKey: string,
	Reps: number,
	ParSeconds: number,
	-- Recipe: the glyph, and whether it deals no damage (a wall, a buff, a leap: accepted is landed).
	Glyph: string?,
	Utility: boolean,
	-- Chain: the length one chain must reach.
	Length: number,
}

export type Event =
	{ Kind: "Landed", Glyph: string, Hits: number }
	| { Kind: "Cast", Glyph: string, Chain: number }
	| { Kind: "Swing", Index: number, Last: boolean, Hits: number }
	| { Kind: "Dash", Cancelled: boolean }

export type Outcome = "Rep" | "Miss"

export type Run = {
	Drill: Drill,
	Reps: number,
	Misses: number,
	-- os.clock of the first event that counted, and of the last one: the clock starts at the proofs, not at the
	-- Lectern.
	FirstAt: number?,
	LastAt: number,
	-- String: how many swings of the running string struck, each after the one before.
	Streak: number,
	-- Cancel: the last finisher struck, and a cancel may follow it.
	Armed: boolean,
	-- Chain: the length of the chain running.
	Chain: number,
}

export type GlyphFacts = { Id: string, NameKey: string, Cooldown: number, Utility: boolean }
-- A recipe drill's hint says to land the glyph, or only to cast it when it deals no damage.
export type RecipeShape = { Reps: number, ParSlackSeconds: number, HintKey: string, UtilityHintKey: string }
export type KitFacts = {
	Id: string,
	Kind: "String" | "Cancel" | "Chain",
	NameKey: string,
	HintKey: string,
	Reps: number,
	ParSeconds: number,
	Length: number?,
}

-- A chain drill with no length set chains this many.
local DEFAULT_CHAIN = 3

local DrillLogic = {}

DrillLogic.MaxGrade = 3

function DrillLogic.recipeDrill(glyph: GlyphFacts, shape: RecipeShape): Drill
	return {
		Id = glyph.Id,
		Kind = "Recipe",
		NameKey = glyph.NameKey,
		HintKey = if glyph.Utility then shape.UtilityHintKey else shape.HintKey,
		Reps = shape.Reps,
		ParSeconds = (shape.Reps - 1) * glyph.Cooldown + shape.ParSlackSeconds,
		Glyph = glyph.Id,
		Utility = glyph.Utility,
		Length = 0,
	}
end

function DrillLogic.kitDrill(kit: KitFacts): Drill
	local kind: Kind = kit.Kind
	return {
		Id = kit.Id,
		Kind = kind,
		NameKey = kit.NameKey,
		HintKey = kit.HintKey,
		Reps = kit.Reps,
		ParSeconds = kit.ParSeconds,
		Glyph = nil,
		Utility = false,
		Length = if kind == "Chain" then kit.Length or DEFAULT_CHAIN else 0,
	}
end

function DrillLogic.start(drill: Drill, now: number): Run
	return {
		Drill = drill,
		Reps = 0,
		Misses = 0,
		FirstAt = nil,
		LastAt = now,
		Streak = 0,
		Armed = false,
		Chain = 0,
	}
end

-- What `event` is to a recipe drill: its glyph landing is a repetition, its glyph striking nothing a miss, and
-- any other glyph the wrong recipe.
local function recipe(run: Run, event: Event): Outcome?
	if event.Kind ~= "Landed" then
		return nil
	end
	if event.Glyph ~= run.Drill.Glyph then
		return "Miss"
	end
	return if run.Drill.Utility or event.Hits > 0 then "Rep" else "Miss"
end

-- The four strokes: every swing of one string strikes, the last one too. A swing that strikes nothing is a miss.
local function strokes(run: Run, event: Event): Outcome?
	if event.Kind ~= "Swing" then
		return nil
	end
	if event.Hits <= 0 then
		run.Streak = 0
		return "Miss"
	end
	run.Streak = if event.Index == 1 then 1 elseif run.Streak == event.Index - 1 then event.Index else 0
	if event.Last and run.Streak == event.Index then
		run.Streak = 0
		return "Rep"
	end
	return nil
end

-- The cancel: a finisher that struck, then the dash that cuts its recovery. A dash that cancels nothing, or that
-- cancels a finisher that struck nothing, is a miss.
local function cancel(run: Run, event: Event): Outcome?
	if event.Kind == "Swing" then
		if event.Last then
			run.Armed = event.Hits > 0
		end
		return nil
	elseif event.Kind == "Dash" then
		local armed = run.Armed
		run.Armed = false
		return if event.Cancelled and armed then "Rep" else "Miss"
	end
	return nil
end

-- The chain: one chain reaching the length is a repetition; a chain that ended short of it -- told by the next
-- cast starting a chain of its own -- a miss.
local function chain(run: Run, event: Event): Outcome?
	if event.Kind ~= "Cast" then
		return nil
	end
	local previous = run.Chain
	run.Chain = event.Chain
	if event.Chain == 1 and previous > 0 and previous < run.Drill.Length then
		return "Miss"
	end
	return if event.Chain == run.Drill.Length then "Rep" else nil
end

function DrillLogic.feed(run: Run, event: Event, now: number): Outcome?
	if DrillLogic.done(run) then
		return nil
	end
	local kind = run.Drill.Kind
	local outcome: Outcome? = if kind == "Recipe"
		then recipe(run, event)
		elseif kind == "String" then strokes(run, event)
		elseif kind == "Cancel" then cancel(run, event)
		else chain(run, event)
	if outcome == nil then
		return nil
	end
	if run.FirstAt == nil then
		run.FirstAt = now
	end
	run.LastAt = now
	if outcome == "Rep" then
		run.Reps += 1
	else
		run.Misses += 1
	end
	return outcome
end

function DrillLogic.done(run: Run): boolean
	return run.Reps >= run.Drill.Reps
end

-- The grade of a finished set; 0 for a set that is not finished.
function DrillLogic.grade(run: Run, slips: number): number
	if not DrillLogic.done(run) then
		return 0
	end
	local elapsed = run.LastAt - (run.FirstAt or run.LastAt)
	if run.Misses == 0 and elapsed <= run.Drill.ParSeconds then
		return 3
	elseif run.Misses <= slips then
		return 2
	end
	return 1
end

-- Every grade above `best` up to `grade`, lowest first: a Calligraphy straight away pays the Draft and the Fair
-- Copy with it, and a result no better than the best pays nothing.
function DrillLogic.toPay(best: number, grade: number): { number }
	local grades: { number } = {}
	for value = math.max(best, 0) + 1, math.min(grade, DrillLogic.MaxGrade) do
		table.insert(grades, value)
	end
	return grades
end

return DrillLogic
