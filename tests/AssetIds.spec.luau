--!strict
-- AssetIds is the seam between code and content, and both sides of it can rot independently: a texture
-- can be renamed on disk while the config still names the old file, or the config can name a size the
-- PNG does not have, and in both cases the first symptom is an effect that looks subtly wrong in a
-- running game and nowhere else.
--
-- So the config is checked against the actual files. This is the only test in the suite that reads the
-- generated art, and it is the reason the generators and the config can be edited by different people on
-- different days without drifting apart.
local AssetIds = require("../src/shared/Config/AssetIds")
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Roblox reads a flipbook as a square grid of one of these sizes and nothing else, so a grid that is not
-- one of them is a texture that will render as one frame stretched over the whole particle.
local FLIPBOOK_GRIDS: { [number]: boolean } = { [1] = true, [2] = true, [4] = true, [8] = true }

-- The first eight bytes of every PNG, and then the IHDR chunk, which carries the real dimensions. Read
-- directly rather than trusted, because a generator that writes the wrong size is exactly the kind of
-- mistake nobody notices until a seal is an ellipse.
local function pngSize(path: string): (number, number)
	local bytes = fs.readFile(path)
	assert(string.sub(bytes, 1, 8) == "\137PNG\r\n\26\n", path .. " is not a PNG")
	assert(string.sub(bytes, 13, 16) == "IHDR", path .. " has no IHDR where one must be")
	local width = string.unpack(">I4", bytes, 17)
	local height = string.unpack(">I4", bytes, 21)
	return width, height
end

describe("AssetIds", function()
	it("declares something, so nothing below passes vacuously", function()
		local count = 0
		for _ in pairs(AssetIds.Textures) do
			count += 1
		end
		expect(count).toBeGreaterThanOrEqual(16)
	end)

	it("points every entry at a file that exists", function()
		local missing: { string } = {}
		for key, asset in pairs(AssetIds.Textures) do
			if not string.match(asset.Source, "^assets/textures/[%w_]+%.png$") then
				table.insert(
					missing,
					("%s has source %q, which is not a generated texture path"):format(key, asset.Source)
				)
			elseif not fs.isFile(asset.Source) then
				table.insert(missing, ("%s names %s, which does not exist"):format(key, asset.Source))
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(table.concat(missing, "\n"))
		end
	end)

	it("declares the size the file actually has", function()
		local wrong: { string } = {}
		for key, asset in pairs(AssetIds.Textures) do
			if fs.isFile(asset.Source) then
				local width, height = pngSize(asset.Source)
				if width ~= asset.Width or height ~= asset.Height then
					table.insert(
						wrong,
						("%s says %dx%d, the file is %dx%d"):format(key, asset.Width, asset.Height, width, height)
					)
				end
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			error(table.concat(wrong, "\n"))
		end
	end)

	it("lays every flipbook out on a grid Roblox can read", function()
		for key, asset in pairs(AssetIds.Textures) do
			if asset.Columns ~= 1 or asset.Rows ~= 1 then
				if asset.Columns ~= asset.Rows then
					error(("%s is %dx%d; a flipbook grid is square"):format(key, asset.Columns, asset.Rows))
				end
				if not FLIPBOOK_GRIDS[asset.Columns] then
					error(
						("%s uses a %dx%d grid, which Enum.ParticleFlipbookLayout has no value for"):format(
							key,
							asset.Columns,
							asset.Rows
						)
					)
				end
				if asset.Width % asset.Columns ~= 0 or asset.Height % asset.Rows ~= 0 then
					error(
						("%s is %dx%d and does not divide into a %d grid"):format(
							key,
							asset.Width,
							asset.Height,
							asset.Columns
						)
					)
				end
			end
		end
	end)

	it("answers an unknown key without pretending", function()
		local id, known = AssetIds.get("SomethingNobodyGenerated")
		expect(id).toBe("")
		expect(known).toBe(false)
		expect(AssetIds.frameCount("SomethingNobodyGenerated")).toBe(0)
	end)

	it("counts a flipbook's frames", function()
		for key, asset in pairs(AssetIds.Textures) do
			expect(AssetIds.frameCount(key)).toBe(asset.Columns * asset.Rows)
		end
	end)

	it("lists exactly what still has to be uploaded, in a stable order", function()
		local missing = AssetIds.missing()
		local expected = 0
		for _, asset in pairs(AssetIds.Textures) do
			if asset.Id == "" then
				expected += 1
			end
		end
		expect(#missing).toBe(expected)
		for index = 2, #missing do
			if missing[index] < missing[index - 1] then
				error("missing() is not sorted, so its warning changes order between runs")
			end
		end
	end)

	it("measures the ink of every square texture, and only those", function()
		-- The two numbers a boss warning is held to (tests/BossTelegraph.spec.luau). They are measured off
		-- the PNG by tools/textures/check_ink.py in the same gate that proves the art reproduces; here the
		-- shape of the claim is checked, because a square texture with no measurement is a texture nobody
		-- may draw a warning with, and the way it becomes one is somebody adding it to a timeline.
		for key, asset in pairs(AssetIds.Textures) do
			local square = asset.Width == asset.Height and asset.Columns == 1
			local ink = asset.Ink
			if square and ink == nil then
				error(("%s is square and carries no ink measurement"):format(key))
			end
			if not square and ink ~= nil then
				error(("%s is not square, so its ink reach is undefined"):format(key))
			end
			if ink ~= nil then
				expect(ink.Least > 0).toBe(true)
				expect(ink.Least <= ink.Most).toBe(true)
				-- The far corner of a square is at 1.414 half-widths: nothing reaches further.
				expect(ink.Most <= 1.415).toBe(true)
			end
		end
	end)

	it("never carries an id that is not a Roblox content id", function()
		-- An id filled in by hand is the likeliest place for a stray quote, a bare number, or a URL from
		-- the creator dashboard rather than the asset itself.
		for key, asset in pairs(AssetIds.Textures) do
			if asset.Id ~= "" and string.match(asset.Id, "^rbxassetid://%d+$") == nil then
				error(("%s has id %q, which is not rbxassetid://<number>"):format(key, asset.Id))
			end
		end
	end)
end)
