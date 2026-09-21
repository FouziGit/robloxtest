--!strict
-- The world is held to docs/ART_BIBLE.md the way the lighting is: nothing in the scenery is a colour,
-- the world is light, what is drawn on it is ink, one material and no other, and the Erasure's figure
-- lies inside the hull its damage is measured on. Source-level where it has to be: no builder in
-- src/server may name a Color3 or a Material of its own.
local AssetIds = require("../src/shared/Config/AssetIds")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- The same measure tests/LightingConfig.spec.luau uses: saturation for the pale colours, absolute chroma
-- for the dark ones, where saturation is a ratio that explodes toward black.
local VALUE_FLOOR = 0.2
local SATURATION_MAX = 0.25
local CHROMA_MAX = 0.06
-- The page and what stands on it are light; ink is dark. In between is a wash.
local LIGHT_VALUE_MIN = 0.78
local INK_VALUE_MAX = 0.15
local LIGHT_ROLES = { "Page", "Chalk", "Bone" }
local INK_ROLES = { "Ink" }

-- The builders, which name roles and never colours.
local BUILDER_ROOT = "src/server"
local PALETTE = "src/shared/Util/Palette.luau"

-- The saturated roles of the interface's palette. A screen may say danger in Cinnabar; the WORLD may not
-- carry one for a whole session (docs/ART_BIBLE.md rule 1: every vivid colour on screen belongs to a
-- glyph). The hub's queue terminal wore an exact Indigo emblem, permanently, which is the longest-lived
-- thing on screen.
local FORBIDDEN_THEME_ROLES = { "Info", "Danger", "Success", "Premium", "Ink" }

-- What has to be legible against what. A colour that matches the surface it is drawn on is not a subtle
-- bug: it is nothing at all, which is what happened to every mark of the Erasure when the floor became
-- the page (D-86) while its marks stayed the page's own vellum.
local READABLE_PAIRS = {
	{ Label = "the Erasure's mark on the arena floor", Ink = "Erasure.Mark", On = "Arena.Floor", Ratio = 4.5 },
	{ Label = "what the Erasure erased, on the floor", Ink = "Erasure.Erased", On = "Arena.Floor", Ratio = 1.4 },
	{ Label = "a footprint on the hub platform", Ink = "Footprints.Color", On = "Hub.Platform", Ratio = 4.5 },
	{ Label = "the rule along an arena wall", Ink = "Arena.WallRule", On = "Arena.Wall", Ratio = 3 },
	{ Label = "the hub's kerb on its platform", Ink = "Hub.Kerb", On = "Hub.Platform", Ratio = 3 },
	{ Label = "the page's ruling on the platform", Ink = "Hub.Rule", On = "Hub.Platform", Ratio = 3 },
	{ Label = "the seal of the spawn on its rim", Ink = "Hub.Spawn", On = "Hub.SpawnRim", Ratio = 3 },
	{ Label = "a proof's registration cross on its body", Ink = "Proof.Mark", On = "Proof.Body", Ratio = 4.5 },
}

-- Easings the timelines already use, which tests/VfxTimeline.spec.luau holds to the art bible's rule 4.
-- The footprint layer is played through the same runtime without being one of their layers, so a name
-- nothing else uses would only be found by Enum.EasingStyle handing the renderer a nil, every frame.
local function timelineEasings(): ({ [string]: boolean }, { [string]: boolean })
	local eases: { [string]: boolean } = {}
	local directions: { [string]: boolean } = {}
	for _, timeline in pairs(VfxTimelineConfig.Timelines) do
		for _, phase in ipairs(timeline.Phases) do
			for _, layer in ipairs(phase.Layers) do
				if layer.Ease ~= nil then
					eases[layer.Ease] = true
				end
				if layer.EaseDirection ~= nil then
					directions[layer.EaseDirection] = true
				end
			end
		end
	end
	return eases, directions
end

-- The colour a dotted role path ("Hub.Kerb") resolves to.
local function roleColor(path: string): WorldConfig.Rgb
	local group, field = string.match(path, "^(%w+)%.(%w+)$")
	assert(group ~= nil and field ~= nil, "not a role path: " .. path)
	local table_ = (WorldConfig :: any)[group]
	assert(type(table_) == "table", "no such group in WorldConfig: " .. tostring(group))
	local role = table_[field]
	assert(type(role) == "string", ("%s is not a role name"):format(path))
	local rgb = WorldConfig.Colors[role]
	assert(rgb ~= nil, ("%s names %s, which WorldConfig.Colors does not have"):format(path, role))
	return rgb
end

local function measure(rgb: WorldConfig.Rgb): (number, number, number)
	local high = math.max(rgb[1], rgb[2], rgb[3])
	local low = math.min(rgb[1], rgb[2], rgb[3])
	local saturation = if high == 0 then 0 else (high - low) / high
	return high / 255, saturation, (high - low) / 255
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- Every role name a builder table points at, labelled by where it is used. EVERY string in those tables
-- is a role -- their other fields are numbers and triples -- so an unknown one reaches the assertion
-- instead of being dropped here, which is what made the check below pass whatever the tables said.
local function roleUses(): { { Label: string, Role: string } }
	local out: { { Label: string, Role: string } } = {}
	local function take(label: string, table_: { [string]: any })
		for key, value in pairs(table_) do
			if type(value) == "string" then
				table.insert(out, { Label = label .. "." .. key, Role = value })
			end
		end
	end
	take("Hub", WorldConfig.Hub)
	take("Arena", WorldConfig.Arena)
	take("Proof", WorldConfig.Proof)
	table.insert(out, { Label = "Footprints.Color", Role = WorldConfig.Footprints.Color })
	table.insert(out, { Label = "Erasure.Mark", Role = WorldConfig.Erasure.Mark })
	table.insert(out, { Label = "Erasure.Erased", Role = WorldConfig.Erasure.Erased })
	for _, part in ipairs(WorldConfig.Erasure.Parts) do
		table.insert(out, { Label = "Erasure." .. part.Name, Role = part.Color })
	end
	table.insert(out, { Label = "Erasure.Band", Role = WorldConfig.Erasure.Band.Color })
	return out
end

describe("the world's colours", function()
	it("are tints, never colours", function()
		local count = 0
		for name, rgb in pairs(WorldConfig.Colors) do
			count += 1
			expect(rgb).toHaveLength(3)
			local value, saturation, chroma = measure(rgb)
			if value >= VALUE_FLOOR then
				if saturation > SATURATION_MAX then
					error(("%s is a colour, not a tint: saturation %.3f"):format(name, saturation))
				end
			elseif chroma > CHROMA_MAX then
				error(("%s is too far off grey for a value that dark: chroma %.3f"):format(name, chroma))
			end
		end
		expect(count).toBeGreaterThanOrEqual(5)
	end)

	it("keep the world light and the ink dark", function()
		for _, role in ipairs(LIGHT_ROLES) do
			local value = measure(WorldConfig.Colors[role])
			if value < LIGHT_VALUE_MIN then
				error(("%s is dark (value %.2f): the world is a lit page"):format(role, value))
			end
		end
		for _, role in ipairs(INK_ROLES) do
			local value = measure(WorldConfig.Colors[role])
			if value > INK_VALUE_MAX then
				error(("%s is not ink (value %.2f)"):format(role, value))
			end
		end
	end)

	it("are the page's own: the floor is vellum and the ink is charcoal", function()
		-- The same two hexes docs/ART_BIBLE.md gives the interface (tests/Interface.spec.luau holds
		-- ThemeConfig to them); a floor that is not the interface's page is two pages.
		expect(WorldConfig.Colors.Page).toEqual({ 232, 224, 206 })
		expect(WorldConfig.Colors.Ink).toEqual({ 23, 21, 15 })
	end)

	it("are the only colours the builders name, and every role resolves", function()
		local uses = roleUses()
		expect(#uses).toBeGreaterThanOrEqual(14)
		for _, use in ipairs(uses) do
			if WorldConfig.Colors[use.Role] == nil then
				error(("%s names %s, which WorldConfig.Colors does not have"):format(use.Label, use.Role))
			end
		end
		-- The floors are the page and the furniture is ink: the two roles every builder starts from.
		expect(WorldConfig.Hub.Platform).toBe("Page")
		expect(WorldConfig.Arena.Floor).toBe("Page")
		expect(WorldConfig.Hub.Kerb).toBe("Ink")
		expect(WorldConfig.Arena.WallRule).toBe("Ink")
	end)

	it("come with one material, and it is the bible's", function()
		expect(WorldConfig.Material).toBe("SmoothPlastic")
	end)

	it("are legible against what they are drawn on", function()
		for _, pair in ipairs(READABLE_PAIRS) do
			local ratio = ThemeConfig.contrast(roleColor(pair.Ink), roleColor(pair.On))
			if ratio < pair.Ratio then
				error(("%s is invisible: contrast %.2f, floor %.2f"):format(pair.Label, ratio, pair.Ratio))
			end
		end
	end)
end)

describe("the Erasure's figure", function()
	local hull = WorldBossConfig.Boss.BodySize
	-- Studs the figure may fall short of its own hull on an axis before the gap is a lie.
	local HULL_FILL_TOLERANCE_STUDS = 0.3

	local function inside(label: string, size: WorldConfig.Triple, offset: WorldConfig.Triple)
		for axis = 1, 3 do
			local reach = math.abs(offset[axis]) + size[axis] / 2
			if reach > hull[axis] / 2 + 1e-6 then
				error(
					("%s reaches %.2f studs on axis %d; the hull allows %.2f"):format(
						label,
						reach,
						axis,
						hull[axis] / 2
					)
				)
			end
		end
	end

	it("lies inside the hull its damage is measured on", function()
		expect(#WorldConfig.Erasure.Parts).toBeGreaterThanOrEqual(3)
		for _, part in ipairs(WorldConfig.Erasure.Parts) do
			inside(part.Name, part.Size, part.Offset)
		end
		local band = WorldConfig.Erasure.Band
		local tallest = band.Heights[#band.Heights]
		inside(band.Name, { band.Width, tallest, band.Depth }, band.Offset)
	end)

	it("fills the hull, so what is drawn is what is hit", function()
		-- The other half of the rule above. A figure that merely FITS inside its hull leaves the
		-- difference as an invisible wall the player bumps into, and as the surface every projectile
		-- detonates against: at 8 studs of depth for a 4.2-deep figure, two studs in front of its face.
		local reach = { 0, 0, 0 }
		local function take(size: WorldConfig.Triple, offset: WorldConfig.Triple)
			for axis = 1, 3 do
				reach[axis] = math.max(reach[axis], math.abs(offset[axis]) + size[axis] / 2)
			end
		end
		for _, part in ipairs(WorldConfig.Erasure.Parts) do
			take(part.Size, part.Offset)
		end
		local band = WorldConfig.Erasure.Band
		take({ band.Width, band.Heights[#band.Heights], band.Depth }, band.Offset)
		for axis = 1, 3 do
			local half = hull[axis] / 2
			if reach[axis] < half - HULL_FILL_TOLERANCE_STUDS then
				error(
					("the figure reaches %.2f studs on axis %d and the hull %.2f: the difference is an invisible wall"):format(
						reach[axis],
						axis,
						half
					)
				)
			end
		end
	end)

	it("wears one band height per phase, widening", function()
		local heights = WorldConfig.Erasure.Band.Heights
		expect(#heights).toBe(#WorldBossConfig.Phases)
		for index = 2, #heights do
			expect(heights[index]).toBeGreaterThan(heights[index - 1])
		end
		expect(heights[1]).toBeGreaterThan(0)
	end)

	it("is the page: blank body, ink strokes", function()
		local roles: { [string]: string } = {}
		for _, part in ipairs(WorldConfig.Erasure.Parts) do
			roles[part.Name] = part.Color
		end
		expect(roles.Core).toBe("Page")
		expect(WorldConfig.Erasure.Band.Color).toBe("Ink")
	end)
end)

describe("the footprints", function()
	local footprints = WorldConfig.Footprints

	it("are a mark that fades to nothing, on a texture that exists", function()
		local layer = footprints.Layer
		expect(layer.Kind).toBe("Mark")
		expect(layer.For).toBeGreaterThan(0)
		expect(layer.Size).toBeGreaterThan(0)
		expect(layer.EndTransparency).toBe(1)
		expect(layer.Ease ~= nil and layer.Ease ~= "Linear").toBe(true)
		expect(AssetIds.Textures[layer.Texture]).toBeTruthy()
	end)

	it("are eased the way the timelines are, since the same runtime draws them", function()
		local eases, directions = timelineEasings()
		local layer = footprints.Layer
		if layer.Ease == nil or not eases[layer.Ease] then
			error(("the footprint is eased %s, which no timeline uses"):format(tostring(layer.Ease)))
		end
		if layer.EaseDirection == nil or not directions[layer.EaseDirection] then
			error(("the footprint eases %s, which no timeline uses"):format(tostring(layer.EaseDirection)))
		end
		-- A print is longer than it is wide and lies along the walk: without a Span it is a round blot.
		expect(layer.Span).toBeGreaterThan(layer.Size)
	end)

	it("can never push an effect's residue out of the pool", function()
		-- MaxLive alone was never the guarantee the config claimed: eviction inside the timeline is
		-- oldest-first across every effect, so a print stamped at the cap removes whatever is oldest,
		-- which in a fight is the fight's own residue. YieldAboveLayers is the real bound -- prints stop
		-- being stamped before the pool can fill -- and this is the arithmetic that says so.
		expect(footprints.MaxLive).toBeGreaterThan(0)
		expect(footprints.MaxPerCharacter).toBeGreaterThan(0)
		expect(footprints.MaxPerCharacter).toBeLessThanOrEqual(footprints.MaxLive)
		expect(footprints.YieldAboveLayers + footprints.MaxLive).toBeLessThanOrEqual(VfxTimelineConfig.MaxLiveLayers)
		expect(footprints.StrideStuds).toBeGreaterThan(0)
		expect(footprints.RangeStuds).toBeGreaterThan(footprints.StrideStuds)
	end)
end)

describe("the builders", function()
	it("name roles, never a colour or a material of their own", function()
		local files: { string } = {}
		collect(BUILDER_ROOT, files)
		expect(#files).toBeGreaterThan(20)
		local found: { string } = {}
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			for _, pattern in ipairs({ "Color3%.fromRGB%(", "Color3%.new%(", "Color3%.fromHex%(", "Enum%.Material%." }) do
				if string.find(code, pattern) ~= nil then
					table.insert(found, ("%s matches %s"):format(path, pattern))
				end
			end
		end
		table.sort(found)
		if #found > 0 then
			error(
				"the world's colours and material come from WorldConfig through Util/Palette:\n"
					.. table.concat(found, "\n")
			)
		end
	end)

	it("carry no saturated colour of the interface into the world", function()
		local files: { string } = {}
		collect(BUILDER_ROOT, files)
		local found: { string } = {}
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			for _, role in ipairs(FORBIDDEN_THEME_ROLES) do
				if string.find(code, "Theme%.Colors%." .. role) ~= nil then
					table.insert(found, ("%s paints the world with Theme.Colors.%s"):format(path, role))
				end
			end
		end
		table.sort(found)
		if #found > 0 then
			error("the scenery is never saturated (docs/ART_BIBLE.md rule 1):\n" .. table.concat(found, "\n"))
		end
	end)

	it("actually convert through Palette, so this cannot pass vacuously", function()
		local palette = stripComments(fs.readFile(PALETTE))
		expect(string.find(palette, "Color3%.fromRGB%(") ~= nil).toBe(true)
		expect(string.find(palette, "Enum%.Material") ~= nil).toBe(true)
	end)
end)
