--!strict
-- The uploaded ids, held to what was actually uploaded.
--
-- scripts/upload_assets.py uploads the generated textures and sounds through Open Cloud, records each one
-- in assets/roblox-assets.lock.json with the SHA-256 of the file it sent, and writes the ids into one
-- generated block in each config module. Three things can drift apart after that, and each one fails in a
-- running game without a single error:
--   * a generator is changed and a PNG or WAV regenerated -- the id still points at the OLD upload, so the
--     game quietly renders last week's art;
--   * a block is edited by hand, or copied from another branch -- an id points at a file it is not;
--   * a file is renamed -- its id sits in the block under a name no config entry reads.
-- This file closes all three.
local AnimationConfig = require("../src/shared/Config/AnimationConfig")
local AssetIds = require("../src/shared/Config/AssetIds")
local Harness = require("./harness")
local MeshConfig = require("../src/shared/Config/MeshConfig")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local LOCK_PATH = "assets/roblox-assets.lock.json"
local TARGETS = {
	{ Module = "src/shared/Config/AssetIds.luau", Prefix = "assets/textures/", Config = AssetIds :: any },
	{ Module = "src/shared/Config/SoundConfig.luau", Prefix = "assets/audio/", Config = SoundConfig :: any },
	{
		Module = "src/shared/Config/AnimationConfig.luau",
		Prefix = "assets/animations/",
		Config = AnimationConfig :: any,
	},
	-- A mesh's block carries the id of the MeshPart the import made (D-114), not the Model's, and only
	-- once Studio has resolved it: see `expectedId`.
	{ Module = "src/shared/Config/MeshConfig.luau", Prefix = "assets/meshes/", Config = MeshConfig :: any },
}

type Record = { assetId: string, sha256: string, assetType: string?, meshId: string?, native: { number }? }

-- The id a block must carry for `path`, or nil when it must carry none: a mesh renders the MeshPart the
-- import made, known only after `record-meshes`; everything else renders the asset it uploaded.
local function expectedId(path: string, record: Record): string?
	if path:sub(1, #"assets/meshes/") == "assets/meshes/" then
		if record.meshId == nil then
			return nil
		end
		return "rbxassetid://" .. record.meshId
	end
	return "rbxassetid://" .. record.assetId
end

local function readLock(): { [string]: Record }
	if not fs.isFile(LOCK_PATH) then
		return {}
	end
	local decoded = serde.decode("json", fs.readFile(LOCK_PATH))
	return (decoded.assets or {}) :: { [string]: Record }
end

-- The generated block of one module, as source path -> id.
local function readBlock(modulePath: string): { [string]: string }
	local source = fs.readFile(modulePath)
	local startAt = source:find("-- BEGIN UPLOADED", 1, true)
	local endAt = source:find("-- END UPLOADED", 1, true)
	if startAt == nil or endAt == nil or endAt < startAt then
		error(("%s has no generated UPLOADED block"):format(modulePath))
	end
	local block = source:sub(startAt, endAt)
	local out: { [string]: string } = {}
	-- A plain id, or a mesh's { Id = ..., Native = ... }: two exact shapes, so a malformed row matches
	-- neither and is reported missing.
	local rows: { { string } } = {}
	for path, id in block:gmatch('%["([^"]+)"%]%s*=%s*"([^"]+)"') do
		table.insert(rows, { path, id })
	end
	for path, id in block:gmatch('%["([^"]+)"%]%s*=%s*{%s*Id%s*=%s*"([^"]+)"') do
		table.insert(rows, { path, id })
	end
	for _, row in ipairs(rows) do
		local path, id = row[1], row[2]
		if not id:match("^rbxassetid://%d+$") then
			error(("%s: %s = %s is not a content id"):format(modulePath, path, id))
		end
		out[path] = id
	end
	return out
end

-- Every table in a config module that declares a Source, whatever its nesting.
local function collect(value: any, out: { [string]: any }, seen: { [any]: boolean })
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	if type(value.Source) == "string" and type(value.Id) == "string" then
		out[value.Source] = value
	end
	for _, child in pairs(value) do
		collect(child, out, seen)
	end
end

local function entriesOf(config: any): { [string]: any }
	local out: { [string]: any } = {}
	collect(config, out, {})
	return out
end

local lock = readLock()

describe("the lock file", function()
	it("records only files that exist, byte for byte as they were uploaded", function()
		for path, record in pairs(lock) do
			if not fs.isFile(path) then
				error(("%s was uploaded as %s and no longer exists"):format(path, record.assetId))
			end
			local now = serde.hash("sha256", fs.readFile(path))
			if now ~= record.sha256 then
				error(
					(
						"%s changed since it was uploaded as %s: its id now points at the old file. Re-upload it "
						.. "(python3 scripts/upload_assets.py upload --reupload) or restore the file"
					):format(path, record.assetId)
				)
			end
			if type(record.assetId) ~= "string" or not record.assetId:match("^%d+$") then
				error(("%s has a malformed asset id %s"):format(path, tostring(record.assetId)))
			end
		end
	end)
end)

describe("the generated blocks", function()
	it("carry exactly what the lock file says, in both directions", function()
		for _, target in ipairs(TARGETS) do
			local block = readBlock(target.Module)
			for path, record in pairs(lock) do
				if path:sub(1, #target.Prefix) == target.Prefix then
					local expected = expectedId(path, record)
					if block[path] ~= expected then
						error(
							("%s: %s should read %s, reads %s"):format(
								target.Module,
								path,
								expected,
								tostring(block[path])
							)
						)
					end
				end
			end
			for path, id in pairs(block) do
				local record = lock[path]
				if record == nil or id ~= expectedId(path, record) then
					error(
						("%s: %s = %s is not in the lock file: the block was edited by hand"):format(
							target.Module,
							path,
							id
						)
					)
				end
			end
		end
	end)

	it("name only files a config entry actually reads, and every such entry picks its id up", function()
		local wired = 0
		for _, target in ipairs(TARGETS) do
			local entries = entriesOf(target.Config)
			for path, id in pairs(readBlock(target.Module)) do
				local entry = entries[path]
				if entry == nil then
					error(("%s: %s has an id but no entry reads that file"):format(target.Module, path))
				end
				if entry.Id ~= id then
					error(
						("%s: the entry for %s reads %q, the block says %q"):format(target.Module, path, entry.Id, id)
					)
				end
				wired += 1
			end
		end
		-- Non-vacuous whenever anything has been uploaded: a block that parses to nothing would pass the
		-- two loops above trivially.
		local recorded = 0
		for path, record in pairs(lock) do
			if expectedId(path, record) ~= nil then
				recorded += 1
			end
		end
		expect(wired).toBe(recorded)
	end)
end)
