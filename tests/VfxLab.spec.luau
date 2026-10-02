--!strict
-- The Studio VFX lab (D-118) never reaches a published game: it lives in tools/vfxlab/, which the default
-- project never maps; its own project is the default one plus the lab and nothing else; the lab returns at
-- once outside Studio; and every hook the game's own code offers it is read in Studio only.
local Harness = require("./harness")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- The source of the `if RunService:IsStudio() then ... end` block a file opens at its top level.
local function studioBlock(path: string): string
	local source = strip(fs.readFile(path))
	local block = source:match("\nif RunService:IsStudio%(%) then\n(.-)\nend\n")
		or source:match("\n\tif RunService:IsStudio%(%) then\n(.-)\n\tend\n")
	if block == nil then
		error(("%s has no Studio-only block"):format(path))
	end
	return block
end

describe("the VFX lab", function()
	it("is never mapped by the default project", function()
		local project = fs.readFile("default.project.json")
		expect(project:find("tools/", 1, true)).toBe(nil)
		expect(project:find("vfxlab", 1, true)).toBe(nil)
	end)

	it("builds from the default project plus the lab and nothing else", function()
		local default = serde.decode("json", fs.readFile("default.project.json"))
		local lab = serde.decode("json", fs.readFile("tools/vfxlab/vfxlab.project.json"))
		local scripts = lab.tree.StarterPlayer.StarterPlayerScripts
		expect(scripts.VfxLab["$path"]).toBe("VfxLab.client.luau")
		scripts.VfxLab = nil
		local function relocate(node: any)
			for key, value in pairs(node) do
				if key == "$path" then
					node[key] = "../../" .. value
				elseif type(value) == "table" then
					relocate(value)
				end
			end
		end
		relocate(default.tree)
		lab.name = default.name
		expect(serde.encode("json", lab)).toBe(serde.encode("json", default))
	end)

	it("does nothing outside Studio", function()
		local source = strip(fs.readFile("tools/vfxlab/VfxLab.client.luau"))
		local first = source:match("^%s*(.-)\n%s*local CollectionService")
		expect(first).never.toBe(nil)
		local folded = ((first :: string):gsub("%s+", " "))
		expect(folded).toBe(
			'local RunService = game:GetService("RunService") if not RunService:IsStudio() then return end'
		)
	end)

	it("reaches the game only through hooks read in Studio", function()
		-- The effect clock's lab scale and packet holding.
		local clock = studioBlock("src/client/Controllers/VfxClock.luau")
		expect(clock:find("LabAttribute", 1, true)).never.toBe(nil)
		local clockSource = strip(fs.readFile("src/client/Controllers/VfxClock.luau"))
		local _, reads = clockSource:gsub("GetAttribute%(", "")
		local _, readsInside = clock:gsub("GetAttribute%(", "")
		expect(reads).toBe(readsInside)
		expect(clockSource:find("labActive = true", 1, true)).never.toBe(nil)
		expect(clock:find("labActive = true", 1, true)).never.toBe(nil)
		-- The pinned quality tier.
		local quality = studioBlock("src/client/Controllers/QualityController.luau")
		expect(quality:find("LAB_ATTRIBUTE", 1, true)).never.toBe(nil)
		local qualitySource = strip(fs.readFile("src/client/Controllers/QualityController.luau"))
		local _, pins = qualitySource:gsub("pinned = ", "")
		local _, pinsInside = quality:gsub("pinned = ", "")
		expect(pins).toBe(pinsInside)
		-- The held packets.
		local controller = studioBlock("src/client/Controllers/VfxController.luau")
		expect(controller:find("VfxClock.onTick(releaseHeld)", 1, true)).never.toBe(nil)
	end)
end)
