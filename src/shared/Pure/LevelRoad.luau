--!strict
-- LevelRoad: every reward a level gives, in the order a player meets them (docs/GAME_DESIGN.md §9). Pure module:
-- no require, no Roblox global, tested under Lune (tests/LevelRoad.spec.luau). The glyphs a level unlocks
-- (GlyphConfig.levelUnlocks), the pigment at its level (ProgressionConfig.OrpimentUnlockLevel) and the milestones
-- past them (ProgressionConfig.Milestones) are passed in, because a pure module requires nothing.
--
--   build          the road: one step per reward, by level, then in the order it was given (the roster's)
--   nextReward     the first step past a level, skipping what the player already holds: what the Result card
--                  promises. The milestones run to the last level, so there is always one before it.
--   milestoneAt    the milestone of exactly that level, what a level-up pays
--   dueMilestones  every milestone at or under a level that was never paid, lowest first: what a profile that
--                  climbed before the milestones existed is owed when it loads

export type Kind = "Glyph" | "Pigment" | "Milestone"

-- `NameKey` names a glyph or the pigment; a milestone is named by what it pays (Folios, and a Title cosmetic id).
export type Step = { Level: number, Kind: Kind, Id: string, NameKey: string, Folios: number, Title: string? }

export type GlyphSource = { Id: string, NameKey: string, Level: number }
export type MilestoneSource = { Level: number, Folios: number, Title: string? }

-- The pigment the road's pigment step unlocks, and its name.
local PIGMENT_ID = "Orpiment"
local PIGMENT_NAME_KEY = "pigment.orpiment"
-- Two rewards of one level are met glyphs first, then the pigment, then the milestone.
local KIND_ORDER: { [string]: number } = { Glyph = 1, Pigment = 2, Milestone = 3 }

local LevelRoad = {}

-- A milestone's step id is its level, as a string: the key its payment is stored under (ProfileData.Milestones).
function LevelRoad.milestoneKey(level: number): string
	return tostring(level)
end

function LevelRoad.build(glyphs: { GlyphSource }, orpimentLevel: number, milestones: { MilestoneSource }): { Step }
	local road: { Step } = {}
	local order: { [Step]: number } = {}
	local function add(step: Step)
		table.insert(road, step)
		order[step] = #road
	end
	for _, glyph in ipairs(glyphs) do
		add({ Level = glyph.Level, Kind = "Glyph", Id = glyph.Id, NameKey = glyph.NameKey, Folios = 0 })
	end
	add({ Level = orpimentLevel, Kind = "Pigment", Id = PIGMENT_ID, NameKey = PIGMENT_NAME_KEY, Folios = 0 })
	for _, milestone in ipairs(milestones) do
		add({
			Level = milestone.Level,
			Kind = "Milestone",
			Id = LevelRoad.milestoneKey(milestone.Level),
			NameKey = "",
			Folios = milestone.Folios,
			Title = milestone.Title,
		})
	end
	table.sort(road, function(a: Step, b: Step): boolean
		if a.Level ~= b.Level then
			return a.Level < b.Level
		end
		if a.Kind ~= b.Kind then
			return KIND_ORDER[a.Kind] < KIND_ORDER[b.Kind]
		end
		return order[a] < order[b]
	end)
	return road
end

-- The first step past `level` the player does not already hold (`held`, when given, says which they do: a
-- pigment bought with its pass, a glyph a developer was handed). nil only past the road's last step.
function LevelRoad.nextReward(road: { Step }, level: number, held: ((step: Step) -> boolean)?): Step?
	for _, step in ipairs(road) do
		if step.Level > level and (held == nil or not held(step)) then
			return step
		end
	end
	return nil
end

function LevelRoad.milestoneAt(road: { Step }, level: number): Step?
	for _, step in ipairs(road) do
		if step.Kind == "Milestone" and step.Level == level then
			return step
		end
	end
	return nil
end

function LevelRoad.dueMilestones(road: { Step }, level: number, paid: { [string]: boolean }): { Step }
	local due: { Step } = {}
	for _, step in ipairs(road) do
		if step.Kind == "Milestone" and step.Level <= level and paid[step.Id] ~= true then
			table.insert(due, step)
		end
	end
	return due
end

return LevelRoad
