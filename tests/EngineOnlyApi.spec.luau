--!strict
-- Roblox reserves some members for engine scripts. A normal LocalScript or Script that touches one
-- raises "lacking capability RobloxScript" at runtime, and nothing else catches it: it is valid Luau, it
-- passes the linter, it passes the type analysis, and no unit test can load a Roblox service.
--
-- That cost a whole release. ScreenRoot connected to GuiService.SafeZoneOffsetsChanged to refresh the
-- safe-area padding. The call raised, ScreenRoot.new never returned, and with it died the HUD and all ten
-- screens: the server built the hub and the player saw an empty screen with no explanation.
--
-- The list below holds only members proven to need the capability. Add one the day it bites, with the
-- error it produced, rather than guessing: a wrong entry fails an innocent build.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOTS = { "src/client", "src/server", "src/ui", "src/shared" }

-- member -> why it is reserved, quoted in the failure so the reader knows what to use instead.
local RESERVED: { [string]: string } = {
	SafeZoneOffsetsChanged = "GuiService event reserved for engine scripts; re-apply from a viewport change instead",
	SetGlobalGuiInset = "GuiService method reserved for engine scripts; read GetGuiInset instead",
	CoreGuiNavigationEnabled = "GuiService property reserved for engine scripts",
	AddSelectionParent = "GuiService method reserved for engine scripts",
	AddSelectionTuple = "GuiService method reserved for engine scripts",
}

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

-- Strips comments so this file's own explanation, and any comment naming a member, never fails the test.
local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

describe("engine-only API", function()
	it("is never touched from game code", function()
		local files: { string } = {}
		for _, root in ipairs(ROOTS) do
			collect(root, files)
		end
		expect(#files).toBeGreaterThan(50)

		local offences: { string } = {}
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			for member, reason in pairs(RESERVED) do
				if string.find(code, "%f[%w_]" .. member .. "%f[^%w_]") ~= nil then
					table.insert(offences, ("%s uses %s (%s)"):format(path, member, reason))
				end
			end
		end
		table.sort(offences)
		if #offences > 0 then
			error(table.concat(offences, "\n"))
		end
	end)
end)
