--!strict
-- LevelRoadWords: the level road as the interface reads it (Pure/LevelRoad, docs/GAME_DESIGN.md §9). The road is
-- built once from the configs the server builds it from, and a step is worded here in one place: a glyph's or the
-- pigment's name, or what a milestone pays, in the player's language. The Result card promises the next step with
-- these words and the Lectern lists the whole road with them.
--
-- What the player already holds is read from the profile the server replicated: a pigment bought with its pass or
-- a milestone paid at a login is never promised a second time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local CosmeticConfig = require(Config:WaitForChild("CosmeticConfig"))
local GlyphConfig = require(Config:WaitForChild("GlyphConfig"))
local LevelRoad = require(Shared:WaitForChild("Pure"):WaitForChild("LevelRoad"))
local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))
local Types = require(Shared:WaitForChild("Types"))

export type Translate = (key: string, params: { [string]: any }?) -> string

local LevelRoadWords = {}

LevelRoadWords.Road =
	LevelRoad.build(GlyphConfig.levelUnlocks(), ProgressionConfig.OrpimentUnlockLevel, ProgressionConfig.Milestones)

-- The words a title cosmetic writes, or nil for an id the catalog does not hold.
local function titleWords(id: string?): string?
	if id == nil then
		return nil
	end
	local item = CosmeticConfig.ById[id]
	return if item ~= nil then item.Look.TextKey else nil
end

-- What `step` gives, as a phrase that fits "Next: … at level 45".
function LevelRoadWords.reward(step: LevelRoad.Step, t: Translate): string
	if step.Kind ~= "Milestone" then
		return t(step.NameKey)
	end
	local title = titleWords(step.Title)
	if title ~= nil then
		return t("levelroad.foliosAndTitle", { amount = step.Folios, title = t(title) })
	end
	return t("levelroad.folios", { amount = step.Folios })
end

-- Whether the profile already holds what `step` gives.
function LevelRoadWords.holds(data: Types.ProfileData, step: LevelRoad.Step): boolean
	if step.Kind == "Glyph" then
		return table.find(data.Unlocks.Glyphs, step.Id) ~= nil
	elseif step.Kind == "Pigment" then
		return table.find(data.Unlocks.Pigments, step.Id) ~= nil
	end
	return data.Milestones[step.Id] == true
end

-- The next step past `level` the profile does not hold yet, or nil once the road is walked.
function LevelRoadWords.next(data: Types.ProfileData, level: number): LevelRoad.Step?
	return LevelRoad.nextReward(LevelRoadWords.Road, level, function(step: LevelRoad.Step): boolean
		return LevelRoadWords.holds(data, step)
	end)
end

return LevelRoadWords
