--!strict
-- One line per layer of the named timelines, the fields that matter to a look -- what a timeline IS, at a
-- glance, without its comments:
--
--   lune run .claude/skills/vellum-vfx/scripts/dump Brand Explosion
local process = require("@lune/process")
local V = require("../../../../src/shared/Config/VfxTimelineConfig")
for _, id in ipairs(process.args) do
	print("=== " .. id)
	for _, phase in ipairs(V.Timelines[id].Phases) do
		print(("-- %s %.2f%s"):format(phase.Name, phase.Duration, if phase.Window then " (window)" else ""))
		for i, l in ipairs(phase.Layers) do
			local parts = {}
			for _, k in ipairs({ "Kind", "Mesh", "Texture", "Role", "Face", "At", "For", "Size", "EndSize", "Span", "Transparency", "EndTransparency", "Burst", "Rate", "Speed", "Lifetime", "Spread", "Emit", "Offset", "Ride", "Follow", "Travel", "Ribbon", "Range", "Brightness", "Voice", "Profile", "SizeFrom", "Flourish", "Chain", "Glow", "Anchor", "Count", "Window", "Ease" }) do
				local v = l[k]
				if v ~= nil then
					if type(v) == "table" then
						v = "{" .. table.concat(v, ",") .. "}"
					end
					table.insert(parts, k .. "=" .. tostring(v))
				end
			end
			print(("  %d %s"):format(i, table.concat(parts, " ")))
		end
	end
end
