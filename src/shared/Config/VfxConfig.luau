--!strict
-- Visual effect ids. Pure data: the single source of truth shared by the server (which emits
-- packets) and the client (VfxLibrary, which renders them). Adding an effect means adding its id
-- here, a renderer in src/client/Controllers/VfxLibrary.luau, and — for a jutsu — referencing the
-- id from JutsuConfig.VfxId. Tests assert every JutsuConfig.VfxId is listed here; VfxController
-- warns at startup for any id listed here without a renderer.

local VfxConfig = {}

-- Emitted by JutsuEffects: one per jutsu, plus the shared detonation ("Explosion", reused by
-- Fireball and Meteor when they blow up).
VfxConfig.JutsuIds = {
	"Brand",
	"Explosion",
	"Wash",
	"Serif",
	"Sweep",
	"Bleed",
	"Margin",
	"Scorch",
	"Rupture",
	-- Phase 2 roster (docs/GAME_DESIGN.md §5)
	"Ligature",
	"Blot",
	"Binding",
	"Stipple",
	"Gilding",
	"Hairline",
	"Spiral",
	"Pounce",
	"Strike",
	"Caret",
	"Watermark",
	"Colophon",
} :: { string }

-- Emitted by JutsuService and CombatService (casting, hits, melee kit, guard).
VfxConfig.CombatIds = {
	"Cast",
	"Hit",
	"Melee",
	"Dash",
	"BlockStart",
	"BlockHit",
	"GuardBreak",
} :: { string }

VfxConfig.Ids = {} :: { string }
VfxConfig.IdSet = {} :: { [string]: boolean }
for _, list in ipairs({ VfxConfig.JutsuIds, VfxConfig.CombatIds }) do
	for _, id in ipairs(list) do
		table.insert(VfxConfig.Ids, id)
		VfxConfig.IdSet[id] = true
	end
end

function VfxConfig.isId(value: any): boolean
	return type(value) == "string" and VfxConfig.IdSet[value] == true
end

return VfxConfig
