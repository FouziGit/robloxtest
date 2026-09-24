--!strict
-- The generated volumes (D-114), held to their files and to what Studio measured.
--
-- tools/meshes/generate_all.py writes assets/meshes/manifest.json and the manifest block of MeshConfig from
-- the same run; scripts/upload_assets.py writes the uploaded block from what Studio resolved. Three things
-- can drift apart after that, each silently in a running game: a mesh regenerated without its block (the
-- runtime offsets it from the old bounds and a crown floats or sinks), a resolve that recorded the wrong
-- MeshPart, and an importer that stops turning one unit into one stud.
local Harness = require("./harness")
local MeshConfig = require("../src/shared/Config/MeshConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local manifest = serde.decode("json", fs.readFile("assets/meshes/manifest.json"))

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

	it("keeps every volume a few hundred triangles", function()
		for key, mesh in pairs(MeshConfig.Meshes) do
			if mesh.Tris > 450 then
				error(("%s has %d triangles: a volume is a brush stroke, not a model"):format(key, mesh.Tris))
			end
		end
	end)
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

describe("the volumes the timelines draw", function()
	it("name a mesh MeshConfig has, and every mesh is drawn by some timeline", function()
		local used: { [string]: boolean } = {}
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
		for key in pairs(MeshConfig.Meshes) do
			if not used[key] then
				error(("mesh %s is generated and uploaded and no timeline draws it"):format(key))
			end
		end
	end)
end)
