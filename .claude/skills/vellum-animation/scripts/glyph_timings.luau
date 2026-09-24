--!strict
-- Prints, for every glyph, when it leaves the hand: the server's hold (Params.Windup, when it has one)
-- and the moment its drawn timeline has drawn its Anticipation and Cast and acts (where a Travel starts,
-- when it has one). A cast clip's release is keyed on that moment (tests/AnimationConfig.spec.luau).
--
--     lune run .claude/skills/vellum-animation/scripts/glyph_timings
local AnimationConfig = require("../../../../src/shared/Config/AnimationConfig")
local GlyphConfig = require("../../../../src/shared/Config/GlyphConfig")
local VfxTimelineConfig = require("../../../../src/shared/Config/VfxTimelineConfig")

print("| Glyph | Combo | Archetype | Server hold | Release (drawn glyph acts) | Own cast |")
print("|---|---|---|---|---|---|")
for _, def in ipairs(GlyphConfig.Glyphs) do
	local timeline = VfxTimelineConfig.Timelines[def.VfxId]
	local leaves = "no timeline"
	if timeline ~= nil then
		local total = 0
		local travels = false
		for _, phase in ipairs(timeline.Phases) do
			if phase.Name == "Anticipation" or phase.Name == "Cast" then
				total += phase.Duration
			elseif phase.Name == "Travel" then
				travels = true
			end
		end
		leaves = ("%.2f s%s"):format(total, if travels then ", then travels" else "")
	end
	local windup = def.Params.Windup
	print(
		("| %s | %s | %s | %s | %s | %s |"):format(
			def.Id,
			table.concat(def.Combo, " + "),
			def.Archetype,
			if type(windup) == "number" then ("%.2f s"):format(windup) else "none (starts at 0)",
			leaves,
			AnimationConfig.CastByGlyph[def.Id] or "generic"
		)
	)
end
