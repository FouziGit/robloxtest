--!strict
-- DrillCatalog: every drill of the Lectern, built once from the roster (GlyphConfig) and DrillConfig through
-- Pure/DrillLogic, so the server that counts them, the remote that names them and the screen that lists them read
-- one list: the kit first, then one recipe per glyph in the roster's order. A drill's id is its glyph's id or its
-- kit entry's, and tests/Drills.spec.luau holds the two apart.

local DrillConfig = require(script.Parent.Config.DrillConfig)
local DrillLogic = require(script.Parent.Pure.DrillLogic)
local GlyphConfig = require(script.Parent.Config.GlyphConfig)

local DrillCatalog = {}

DrillCatalog.List = {} :: { DrillLogic.Drill }
DrillCatalog.ById = {} :: { [string]: DrillLogic.Drill }

for _, kit in ipairs(DrillConfig.Kit) do
	table.insert(DrillCatalog.List, DrillLogic.kitDrill(kit))
end
for _, glyph in ipairs(GlyphConfig.Glyphs) do
	local facts = {
		Id = glyph.Id,
		NameKey = glyph.NameKey,
		Cooldown = glyph.Cooldown,
		Utility = GlyphConfig.isUtility(glyph.Id),
	}
	table.insert(DrillCatalog.List, DrillLogic.recipeDrill(facts, DrillConfig.Recipe))
end
for _, drill in ipairs(DrillCatalog.List) do
	DrillCatalog.ById[drill.Id] = drill
end

-- Every drill id, in the Lectern's order: what the StartDrill remote accepts.
function DrillCatalog.ids(): { string }
	local ids = {}
	for _, drill in ipairs(DrillCatalog.List) do
		table.insert(ids, drill.Id)
	end
	return ids
end

return DrillCatalog
