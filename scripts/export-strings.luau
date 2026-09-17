--!strict
-- Exports src/shared/Strings.luau to localization.csv in the Roblox localization portal format
-- (columns: Key, Source, Context, Example, en, fr). Usage: lune run scripts/export-strings
-- With --check, exits non-zero when the committed CSV is out of date.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Strings = require("../src/shared/Strings")

local OUTPUT = "localization.csv"

local function csvEscape(value: string): string
	if string.find(value, '[",\n]') then
		return '"' .. string.gsub(value, '"', '""') .. '"'
	end
	return value
end

local lines = { "Key,Source,Context,Example,en,fr" }
for _, key in ipairs(Strings.keys()) do
	local entry = Strings.Table[key]
	table.insert(
		lines,
		table.concat(
			{
				csvEscape(key),
				csvEscape(entry.en),
				csvEscape("JutsuBattlegrounds"),
				"",
				csvEscape(entry.en),
				csvEscape(entry.fr),
			},
			","
		)
	)
end
local content = table.concat(lines, "\n") .. "\n"

local checkOnly = table.find(process.args, "--check") ~= nil
if checkOnly then
	local existing = if fs.isFile(OUTPUT) then fs.readFile(OUTPUT) else ""
	if existing ~= content then
		print("localization.csv is out of date: run `lune run scripts/export-strings`")
		process.exit(1)
	end
	print(("localization.csv up to date (%d keys)"):format(#lines - 1))
	process.exit(0)
end

fs.writeFile(OUTPUT, content)
print(("wrote %s (%d keys)"):format(OUTPUT, #lines - 1))
