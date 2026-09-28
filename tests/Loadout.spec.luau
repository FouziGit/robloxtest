--!strict
-- What a profile hears when it is caught up at login. A roster change hands a veteran every glyph it added
-- at once -- eight, the day the second roster shipped -- and a toast per glyph buried every other message on
-- screen for twenty seconds. The service touches Roblox, so its source is read here.
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local LOADOUT = "src/server/Services/LoadoutService.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- One top-level function of a file, flattened, or an error: a gate that found nothing would pass.
local function functionIn(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local finish = source:find("\nend\n", start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + 4):gsub("%s+", " "))
end

describe("a catch-up at login", function()
	it("grants quietly, level gates and pigments alike", function()
		local earned = functionIn(LOADOUT, "local function grantEarned(")
		local _, quiet = earned:gsub("grantGlyph%(player, data, glyphId, true%)", "")
		local _, all = earned:gsub("grantGlyph%(", "")
		expect(quiet).toBe(2)
		expect(all).toBe(quiet)
	end)

	it("says so once, with how many, and only when it granted something", function()
		local loaded = functionIn(LOADOUT, "local function onProfileLoaded(")
		expect(
			loaded:find(
				'local caughtUp = grantEarned(player, data) if caughtUp > 0 then dataService.push(player, "Unlocks") notify.send(player, CAUGHT_UP_KEY, { count = caughtUp }, "Success", "LevelUp") end',
				1,
				true
			)
		).never.toBe(nil)
		expect(strip(fs.readFile(LOADOUT)):find('local CAUGHT_UP_KEY = "loadout.caughtUp"', 1, true)).never.toBe(nil)
		for _, locale in ipairs(Strings.Locales) do
			local line = Strings.t("loadout.caughtUp", { count = 8 }, locale)
			expect(line:find("8", 1, true)).never.toBe(nil)
			expect(line:find("{", 1, true)).toBe(nil)
		end
	end)
end)
