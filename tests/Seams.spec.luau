--!strict
-- Where the slices of the colour pass meet (D-147, slice G). Slices A, B and C each held their own screens
-- to the spec; what none of them could see alone is two of them doing one thing two ways -- a badge counted
-- on the player's clock beside one counted on the server's. These rules hold the joins. The screens are
-- engine code Lune cannot run, so they are read.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CLAIMS = "src/ui/Claims.luau"
local CLAIMABLES = "src/shared/Pure/Claimables.luau"
local MENU = "src/ui/screens/MenuScreen.luau"
local DAILY = "src/ui/screens/DailyScreen.luau"

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function code(path: string): string
	return stripComments(fs.readFile(path))
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
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

describe("a claim", function()
	it("is counted in one place, on the day the servers keep", function()
		-- Claims is the one caller of the pure count: every badge, seal and the daily reward's own opening go
		-- through it, so none of them can count on another clock or another context.
		local files = {}
		collect("src", files)
		local callers = {}
		for _, path in ipairs(files) do
			if path ~= CLAIMABLES and has(code(path), "Claimables.count(") then
				table.insert(callers, path)
			end
		end
		expect(#callers).toBe(1)
		expect(callers[1]).toBe(CLAIMS)
		-- The menu's tiles count as the HUD's Menu button and seals do, on the server's clock.
		expect(has(code(MENU), "Claims.count(data, workspace:GetServerTimeNow())")).toBe(true)
		-- And the screen they open agrees: its "today" is the server's, never the player's own clock.
		local daily = code(DAILY)
		expect(has(daily, "DailyStreak.dayIndex(workspace:GetServerTimeNow())")).toBe(true)
		expect(has(daily, "os.time(")).toBe(false)
	end)
end)
