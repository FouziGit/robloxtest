--!strict
-- The Roblox type definitions the strict gate reads are those of the luau-lsp release the toolchain pins (E2-S4).
-- CI and scripts/setup.sh downloaded them from luau-lsp's main branch: the same commit could pass on Monday and fail
-- on Tuesday, or pass in CI and fail on a machine set up a month earlier, because upstream added or changed an API.
-- rokit.toml pins luau-lsp; both downloads must name that same release.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DOWNLOADERS = { ".github/workflows/ci.yml", "scripts/setup.sh" }
local DEFINITIONS = "raw%.githubusercontent%.com/JohnnyMorganz/luau%-lsp/([^/%s\"']+)/scripts/globalTypes%.d%.luau"

-- The luau-lsp version rokit.toml pins.
local function pinned(): string
	local version = fs.readFile("rokit.toml"):match('luau%-lsp%s*=%s*"JohnnyMorganz/luau%-lsp@([^"]+)"')
	assert(version ~= nil, "rokit.toml pins no luau-lsp")
	return version
end

-- The release each definitions download of `path` names.
local function downloads(path: string): { string }
	local found: { string } = {}
	for ref in fs.readFile(path):gmatch(DEFINITIONS) do
		table.insert(found, ref)
	end
	return found
end

describe("the Roblox type definitions (E2-S4)", function()
	it("are downloaded from the luau-lsp release rokit.toml pins, by CI and by the setup alike", function()
		local version = pinned()
		for _, path in ipairs(DOWNLOADERS) do
			local refs = downloads(path)
			if #refs == 0 then
				error(path .. " downloads no Roblox type definitions")
			end
			for _, ref in ipairs(refs) do
				if ref ~= version then
					error(
						("%s downloads the definitions of %s, and rokit.toml pins luau-lsp %s"):format(
							path,
							ref,
							version
						)
					)
				end
			end
		end
	end)

	it("are the file the strict gate reads, in check.sh and in CI", function()
		for _, path in ipairs({ "scripts/check.sh", ".github/workflows/ci.yml" }) do
			expect(fs.readFile(path)).toContain("--definitions=globalTypes.d.luau")
		end
		expect(fs.readFile("scripts/setup.sh")).toContain("-o globalTypes.d.luau")
	end)
end)

return nil
