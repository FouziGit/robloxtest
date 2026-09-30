--!strict
-- Every module under src/shared/Config, src/shared/Pure and src/server/Pure must stay pure: no Roblox
-- global, so it loads under Lune and can be unit-tested. This test fails the moment one of them reaches for the
-- engine (Vector3, Color3, Instance, Enum, game, workspace, task…).
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOTS = { "src/shared/Config", "src/shared/Pure", "src/server/Pure" }
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

-- Strips line comments and block comments so the word "Vector3" in prose never fails the test, and the
-- contents of string literals, which name things rather than reach for them: a quest that needs "Players"
-- (QuestConfig) is data, and `Players` outside quotes is still the engine's global.
local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		local code = string.gsub(line, "%-%-.*$", "")
		code = string.gsub(code, '"[^"]*"', '""')
		code = string.gsub(code, "'[^']*'", "''")
		table.insert(lines, code)
	end
	return table.concat(lines, "\n")
end

-- The Roblox globals `code` reaches for, and whether it requires anything.
local function violations(code: string): ({ string }, boolean)
	local stripped = stripComments(code)
	local found = {}
	for _, word in ipairs(FORBIDDEN) do
		if string.find(stripped, "%f[%w_]" .. word .. "%f[^%w_]") ~= nil then
			table.insert(found, word)
		end
	end
	return found, string.find(stripped, "%f[%w_]require%f[^%w_]") ~= nil
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
			local words, requires = violations(fs.readFile(path))
			if #words > 0 then
				error(("%s uses the Roblox global %q; keep Config and Pure modules engine-free"):format(path, words[1]))
			end
			expect(requires).toBe(false)
		end
	end)

	it("reads a global outside quotes and a name inside them for what each is", function()
		expect((violations("local needs = \"Players\"\nlocal other = 'Players'"))).toEqual({})
		expect((violations("local list = Players:GetPlayers()"))).toEqual({ "Players" })
		expect((violations('local list = game:GetService("Players")'))).toEqual({ "game" })
		expect((violations('local label = "Vector3" .. tostring(Vector3.zero)'))).toEqual({ "Vector3" })
		expect(select(2, violations('local x = require("./y")'))).toBe(true)
		expect(select(2, violations('local text = "require"'))).toBe(false)
	end)
end)
