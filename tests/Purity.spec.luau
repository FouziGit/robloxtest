--!strict
-- Every module under src/shared/Config and src/shared/Pure must stay pure: no Roblox global, so it
-- loads under Lune and can be unit-tested. This test fails the moment one of them reaches for the
-- engine (Vector3, Color3, Instance, Enum, game, workspace, task…).
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOTS = { "src/shared/Config", "src/shared/Pure" }
local FORBIDDEN = {
	"Vector3",
	"CFrame",
	"Color3",
	"UDim2",
	"UDim",
	"Instance",
	"Enum",
	"game",
	"workspace",
	"task",
	"Players",
	"RunService",
}

-- Strips line comments and block comments so the word "Vector3" in prose never fails the test.
local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

describe("shared purity", function()
	it("has no Roblox global in Config and Pure modules", function()
		local files: { string } = {}
		for _, root in ipairs(ROOTS) do
			collect(root, files)
		end
		expect(#files).toBeGreaterThan(10)
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			for _, word in ipairs(FORBIDDEN) do
				if string.find(code, "%f[%w_]" .. word .. "%f[^%w_]") ~= nil then
					error(("%s uses the Roblox global %q; keep Config and Pure modules engine-free"):format(path, word))
				end
			end
			expect(string.find(code, "%f[%w_]require%f[^%w_]")).toBeNil()
		end
	end)
end)
