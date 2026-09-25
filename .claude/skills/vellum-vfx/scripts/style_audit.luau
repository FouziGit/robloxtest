--!strict
-- Where each glyph timeline stands against the Vellum VFX recipe (D-119), in the order players meet the
-- glyphs (GlyphConfig), from the data alone:
--
--   lune run .claude/skills/vellum-vfx/scripts/style_audit
--
-- Columns: layers by role (Pigment / Core / Ink), whether a core shines, a hand-anchored layer (born in the
-- hand), trails still textured (a brush texture on a trail renders as a smudge), emitters still firing
-- straight up with a wide spread (the audit's "sparks go up"), particles that pop, the peak of layers
-- alive at once and the particles asked for (scripts/effect-cost), and whether the play is steady (flies a
-- carrier or fills a server window: never held by the impact freeze). A glyph with no core, no ink and
-- a textured trail has not been through the recipe yet.
local EffectCost = require("../../../../scripts/effect-cost")
local GlyphConfig = require("../../../../src/shared/Config/GlyphConfig")
local VfxTimelineConfig = require("../../../../src/shared/Config/VfxTimelineConfig")

local costs: { [string]: any } = {}
for _, cost in ipairs(EffectCost.all()) do
	costs[cost.Id] = cost
end

local function audit(id: string): string
	local timeline = VfxTimelineConfig.Timelines[id]
	if timeline == nil then
		return ("| %s | (no timeline) |"):format(id)
	end
	local pigment, core, ink, hand, textured, upward, pops = 0, 0, 0, 0, 0, 0, 0
	for _, phase in ipairs(timeline.Phases) do
		for _, layer in ipairs(phase.Layers) do
			local drawn = layer.Kind ~= "Sound" and layer.Kind ~= "Shake" and layer.Kind ~= "Flash"
			if drawn and layer.Kind ~= "Carrier" and layer.Kind ~= "Light" then
				if layer.Role == "Core" then
					core += 1
				elseif layer.Role == "Ink" or layer.Kind == "Debris" then
					ink += 1
				else
					pigment += 1
				end
			end
			if layer.Anchor == "Hand" then
				hand += 1
			end
			if layer.Kind == "Trail" and layer.Texture ~= nil then
				textured += 1
			end
			local fast = layer.Speed ~= nil and layer.Speed[2] > 2
			if layer.Kind == "Emitter" and layer.Emit == nil and (layer.Spread or 0) < 90 and layer.Burst ~= nil and fast then
				upward += 1
			end
			if layer.Pop ~= nil then
				pops += 1
			end
		end
	end
	local cost = costs[id]
	return ("| %s | %d / %d / %d | %s | %d | %d | %d | %d | %d | %d | %s |"):format(
		id,
		pigment,
		core,
		ink,
		if core > 0 then "yes" else "no",
		hand,
		textured,
		upward,
		pops,
		cost and cost.Peak or 0,
		cost and math.floor(cost.Particles + 0.5) or 0,
		if VfxTimelineConfig.steady(timeline) then "steady" else "held"
	)
end

print("| Glyph | P / C / I | Core | Hand | Textured trails | Narrow bursts, no Emit | Pops | Peak | Particles | Clock |")
print("|---|---|---|---|---|---|---|---|---|---|")
local seen: { [string]: boolean } = {}
for _, def in ipairs(GlyphConfig.Glyphs) do
	if not seen[def.VfxId] then
		seen[def.VfxId] = true
		print(audit(def.VfxId))
	end
end
for _, id in ipairs({ "Tap", "Cast", "Explosion", "Hit", "Melee", "Dash" }) do
	print(audit(id))
end
