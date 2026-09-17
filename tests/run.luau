--!strict
-- Test runner for Lune: discovers tests/**/*.spec.luau, runs them, exits non-zero on failure.
-- Usage: lune run tests/run

local fs = require("@lune/fs")
local process = require("@lune/process")

local Harness = require("./harness")

local function collectSpecs(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collectSpecs(path, out)
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local specs: { string } = {}
collectSpecs("tests", specs)
table.sort(specs)

for _, spec in ipairs(specs) do
	-- Paths are relative to this file (tests/run.luau).
	local relative = "./" .. string.gsub(string.sub(spec, #"tests/" + 1), "%.luau$", "")
	local ok, err = pcall(require, relative)
	if not ok then
		print(("✖ failed to load %s: %s"):format(spec, tostring(err)))
		process.exit(1)
	end
end

local summary = Harness.run()

for _, failure in ipairs(summary.failures) do
	print(("✖ %s\n    %s"):format(failure.path, failure.message))
end

print(("%d passed, %d failed, %d spec file(s)"):format(summary.passed, summary.failed, #specs))
process.exit(if summary.failed == 0 then 0 else 1)
