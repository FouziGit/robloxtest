--!strict
-- Fails when a player-facing string literal is hard-coded outside src/shared/Strings.luau.
-- Player-facing = assigned to a GuiObject text property, a Humanoid DisplayName, or passed to Kick.
-- Usage: lune run scripts/check-strings

local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOTS = { "src/server", "src/client", "src/ui" }
local PATTERNS = {
	'%.Text%s*=%s*"([^"]+)"',
	'[^%w_]Text%s*=%s*"([^"]+)"',
	'PlaceholderText%s*=%s*"([^"]+)"',
	'DisplayName%s*=%s*"([^"]+)"',
	':Kick%(%s*"([^"]+)"',
}

local function isAllowed(literal: string): boolean
	-- glyphs, symbols and format-only strings are not localizable text
	if #literal <= 2 then
		return true
	end
	if string.match(literal, "^[%p%s%d]+$") ~= nil then
		return true
	end
	return false
end

local violations: { string } = {}

local function scan(path: string)
	for _, entry in ipairs(fs.readDir(path)) do
		local child = path .. "/" .. entry
		if fs.isDir(child) then
			if entry ~= "Vendor" then
				scan(child)
			end
		elseif string.match(entry, "%.luau$") then
			local lineNumber = 0
			for line in string.gmatch(fs.readFile(child) .. "\n", "(.-)\n") do
				lineNumber += 1
				local code = string.gsub(line, "%-%-.*$", "")
				for _, pattern in ipairs(PATTERNS) do
					for literal in string.gmatch(code, pattern) do
						if not isAllowed(literal) then
							table.insert(violations, ("%s:%d: %q"):format(child, lineNumber, literal))
						end
					end
				end
			end
		end
	end
end

for _, root in ipairs(ROOTS) do
	if fs.isDir(root) then
		scan(root)
	end
end

if #violations > 0 then
	print("Hard-coded player-facing strings found (use Strings keys):")
	for _, violation in ipairs(violations) do
		print("  " .. violation)
	end
	process.exit(1)
end
print("no hard-coded player-facing strings")
