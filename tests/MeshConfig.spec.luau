--!strict
-- The generated volumes (D-114), held to their files and to what Studio measured.
--
-- tools/meshes/generate_all.py writes assets/meshes/manifest.json and the manifest block of MeshConfig from
-- the same run; scripts/upload_assets.py writes the uploaded block from what Studio resolved. Three things
-- can drift apart after that, each silently in a running game: a mesh regenerated without its block (the
-- runtime offsets it from the old bounds and a crown floats or sinks), a resolve that recorded the wrong
-- MeshPart, and an importer that stops turning one unit into one stud.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/server/Pure/BattlegroundLayout")
local BotConfig = require("../src/shared/Config/BotConfig")
local Harness = require("./harness")
local MeshConfig = require("../src/shared/Config/MeshConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local manifest = serde.decode("json", fs.readFile("assets/meshes/manifest.json"))

-- The bodies a glyph flies as (D-273, D-278), modelled after the developer's own references: more than a stroke,
-- each under its own cap -- a projectile that six players can throw at once, and a wave that one does.
local BODY_CAPS: { [string]: number } = {
	FireBody = 1000,
	FireCore = 1000,
	FireInk = 1000,
	WaveBody = 1800,
	WaveCrest = 1800,
	WaveInk = 1800,
	ScorchCrown = 1100,
	ScorchCore = 300,
	ScorchInk = 1200,
	RuptureBody = 1500,
	RuptureCore = 280,
	RuptureInk = 1750,
	HairlineBlade = 850,
	HairlineEdge = 100,
	HairlineInk = 900,
	SerifBody = 300,
	SerifCore = 60,
	SerifInk = 350,
	EmbossBody = 1400,
	EmbossBevel = 50,
	EmbossInk = 1650,
	GildingBody = 950,
	GildingCore = 150,
	GildingInk = 1200,
	PounceDunes = 1350,
	PounceCrest = 100,
	PounceInk = 1450,
	BleedPool = 1100,
	BleedSheen = 280,
	BleedInk = 1400,
	SweepBody = 1000,
	SweepCrest = 250,
	SweepInk = 1200,
	VoluteBody = 500,
	VoluteEye = 200,
	VoluteInk = 750,
	MarginBody = 1100,
	MarginLip = 500,
	MarginInk = 1800,
	LigatureBody = 1550,
	LigatureCore = 350,
	LigatureInk = 1650,
	StippleBody = 950,
	StippleGloss = 150,
	StippleInk = 1000,
	BlotTeardropBody = 750,
	BlotTeardropCore = 100,
	BlotTeardropInk = 1000,
	BlotStarBody = 850,
	BlotStarCore = 50,
	BlotStarInk = 900,
	BindingCordsBody = 950,
	BindingCordsFoam = 450,
	BindingCordsInk = 1400,
	HatchingCutBody = 300,
	HatchingCutCore = 200,
	HatchingCutInk = 400,
	HatchingLongBody = 300,
	HatchingLongCore = 200,
	HatchingLongInk = 400,
	HatchingFinisherBody = 300,
	HatchingFinisherCore = 250,
	HatchingFinisherInk = 500,
	DaggerObelusBody = 1000,
	DaggerObelusCore = 150,
	DaggerObelusInk = 950,
	DaggerStrikeBody = 100,
	DaggerStrikeCore = 100,
	DaggerStrikeInk = 150,
	SpiralBowl = 1800,
	SpiralCore = 1800,
	SpiralInk = 1800,
	StitchLoopBody = 600,
	StitchLoopCore = 100,
	StitchLoopInk = 1000,
	StitchShackleBody = 950,
	StitchShackleCore = 50,
	StitchShackleInk = 900,
	ColophonBody = 550,
	ColophonCore = 100,
	ColophonInk = 600,
	RubricBud = 950,
	RubricHeart = 150,
	RubricBudInk = 900,
	RubricBar = 600,
	RubricLobes = 100,
	RubricBarInk = 600,
	RubricHead = 400,
	RubricHeadInk = 500,
	CartoucheBody = 1750,
	CartoucheCore = 500,
	CartoucheInk = 1250,
	CaretWideBody = 450,
	CaretWideCore = 450,
	CaretWideInk = 450,
	CaretRatureBody = 450,
	CaretRatureCore = 450,
	CaretRatureInk = 450,
	StrikeBand = 450,
	StrikeSpine = 450,
	StrikeInk = 450,
	SwashBody = 1550,
	SwashEdge = 200,
	SwashInk = 1800,
	SwashSlumpBody = 1400,
	SwashSlumpEdge = 100,
	SwashSlumpInk = 1450,
	WatermarkWire = 1800,
	WatermarkGleam = 450,
	WatermarkInk = 1250,
}

-- The Page's landmark skins (D-283), Reference "Layout": scenery built once, under a cap of their own.
local DECOR_CAP = 5000

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

describe("the mesh manifest", function()
	it("is the generator's own record, entry for entry", function()
		local declared = 0
		for key, entry in pairs(manifest.meshes) do
			declared += 1
			local mesh = MeshConfig.get(key)
			if mesh == nil then
				error(key .. " is in manifest.json and not in MeshConfig: re-run tools/meshes/generate_all.py")
			end
			expect(mesh.Source).toBe(entry.Source)
			expect(mesh.Tris).toBe(entry.Tris)
			expect(mesh.Reference).toBe(entry.Reference)
			expect(mesh.Axis).toBe(entry.Axis)
			expect(mesh.Flat).toBe(entry.Flat)
			for axis = 1, 3 do
				expect(near(mesh.Min[axis], entry.Min[axis], 1e-4)).toBe(true)
				expect(near(mesh.Max[axis], entry.Max[axis], 1e-4)).toBe(true)
				expect(mesh.Pivot[axis]).toBe(entry.Pivot[axis])
			end
		end
		local configured = 0
		for _ in pairs(MeshConfig.Meshes) do
			configured += 1
		end
		expect(configured).toBe(declared)
		expect(declared).toBeGreaterThanOrEqual(3)
	end)

	it("describes the committed files, byte for byte", function()
		for key, entry in pairs(manifest.meshes) do
			if not fs.isFile(entry.Source) then
				error(("%s: %s does not exist"):format(key, entry.Source))
			end
			if serde.hash("sha256", fs.readFile(entry.Source)) ~= entry.Sha256 then
				error(("%s: %s is not the file the manifest was written from"):format(key, entry.Source))
			end
		end
	end)

	it("carries every file already turned the half turn the importer gives it", function()
		-- Roblox imports a glTF turned half a turn about Y (measured, D-114), so the generator writes each
		-- vertex as (-x, y, -z). The file's own bounds are the only place that turn shows: an extent does
		-- not change under it, so without this a mesh that lost it -- a drop flying tail first -- passes.
		for key, entry in pairs(manifest.meshes) do
			local data = fs.readFile(entry.Source)
			expect(data:sub(1, 4)).toBe("glTF")
			local length = string.unpack("<I4", data, 13)
			expect(data:sub(17, 20)).toBe("JSON")
			local document = serde.decode("json", data:sub(21, 20 + length))
			local attributes = document.meshes[1].primitives[1].attributes
			local accessor = document.accessors[attributes.POSITION + 1]
			local mesh = MeshConfig.get(key) :: MeshConfig.Mesh
			local expectedMin = { -mesh.Max[1], mesh.Min[2], -mesh.Max[3] }
			local expectedMax = { -mesh.Min[1], mesh.Max[2], -mesh.Min[3] }
			for axis = 1, 3 do
				if
					not near(accessor.min[axis], expectedMin[axis], 2e-4)
					or not near(accessor.max[axis], expectedMax[axis], 2e-4)
				then
					error(("%s is not turned in its file on axis %d"):format(key, axis))
				end
			end
		end
	end)

	it(
		"keeps every volume a few hundred triangles, a glyph's body and a landmark's skin under their own caps",
		function()
			for key, mesh in pairs(MeshConfig.Meshes) do
				local cap = if mesh.Reference == "Layout" then DECOR_CAP else BODY_CAPS[key] or 450
				if mesh.Tris > cap then
					error(("%s has %d triangles: a volume is a brush stroke, not a model"):format(key, mesh.Tris))
				end
			end
			-- A cap for a body nobody generates would hold nothing.
			for key in pairs(BODY_CAPS) do
				expect(MeshConfig.get(key)).never.toBeNil()
			end
		end
	)
end)

describe("a resolved mesh", function()
	it("imported one unit to one stud, on the axes it was generated on", function()
		-- Measured in Studio for every mesh of the first upload; a drift here means the importer changed,
		-- or a resolve recorded another MeshPart.
		local resolved = 0
		for key, mesh in pairs(MeshConfig.Meshes) do
			local native = mesh.Native
			if native ~= nil then
				resolved += 1
				for axis = 1, 3 do
					local extent = mesh.Max[axis] - mesh.Min[axis]
					if not near(native[axis], extent, math.max(extent * 0.01, 1e-3)) then
						error(("%s imported %.4f on axis %d, generated %.4f"):format(key, native[axis], axis, extent))
					end
				end
				expect(mesh.Id:match("^rbxassetid://%d+$")).never.toBe(nil)
			end
		end
		expect(resolved).toBeGreaterThanOrEqual(3)
	end)
end)

describe("the volumes the timelines and the map draw", function()
	it(
		"name a mesh MeshConfig has, and every mesh is drawn by some timeline, or a landmark's skin by the map",
		function()
			local used: { [string]: boolean } = {}
			local mapped: { [string]: boolean } = {}
			local layout = BattlegroundLayout.build(BattlegroundConfig.Map, {
				FloorName = BattlegroundConfig.Anchors.Floor,
				KillZoneName = BattlegroundConfig.Anchors.KillZone,
				FlatThickness = WorldConfig.FlatThicknessStuds,
				RuleTop = WorldConfig.Ladder.Rule,
				CampTop = WorldConfig.Ladder.Training,
				CampTransparency = WorldConfig.Battleground.CampTransparency,
			}, BotConfig.Path.RadiusStuds)
			for _, skin in ipairs(BattlegroundLayout.skins(layout, BattlegroundConfig.Map)) do
				for _, piece in ipairs(skin.Meshes) do
					mapped[piece.Mesh] = true
				end
			end
			for id, timeline in pairs(VfxTimelineConfig.Timelines) do
				for _, phase in ipairs(timeline.Phases) do
					for _, layer in ipairs(phase.Layers) do
						local names: { string } = {}
						if layer.Mesh ~= nil then
							table.insert(names, layer.Mesh)
						end
						for _, name in ipairs(layer.Meshes or {}) do
							table.insert(names, name)
						end
						for _, name in ipairs(names) do
							if MeshConfig.get(name) == nil then
								error(("timeline %s draws mesh %s, which MeshConfig does not have"):format(id, name))
							end
							used[name] = true
						end
					end
				end
			end
			-- A glyph's volume is a timeline's alone, a landmark's skin the map's alone: neither stands in for the other.
			for key, mesh in pairs(MeshConfig.Meshes) do
				if mesh.Reference == "Layout" then
					if not mapped[key] or used[key] then
						error(("landmark mesh %s must be drawn by the map and by no timeline"):format(key))
					end
				elseif not used[key] or mapped[key] then
					error(("mesh %s is generated and uploaded and no timeline draws it, or the map does"):format(key))
				end
			end
		end
	)
end)
