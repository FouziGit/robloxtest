--!strict
-- Every event named in QuestConfig.Pool must have a producer on the server, otherwise the quest it
-- belongs to sits at 0 forever and the player silently loses its reward. QuestLogic.select picks its
-- quests from the whole pool, so one dead event breaks a share of every day's quest log.
--
-- A producer is a QuestService.report / quest.report call with the event as a literal, or a
-- CombatService signal handler that reports it. The check reads the server sources as text: it stays
-- honest when a service is renamed, and fails loudly when a new quest arrives without a producer.
local Harness = require("./harness")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SERVER_ROOT = "src/server"

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

-- Strips comments so the event names listed in a doc comment never count as a producer.
local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

describe("quest events", function()
	it("has a server producer for every event in the pool", function()
		local files: { string } = {}
		collect(SERVER_ROOT, files)
		expect(#files).toBeGreaterThan(10)

		local sources = {}
		for _, path in ipairs(files) do
			table.insert(sources, stripComments(fs.readFile(path)))
		end
		local code = table.concat(sources, "\n")

		local events: { [string]: boolean } = {}
		for _, quest in ipairs(QuestConfig.Pool) do
			events[quest.Event] = true
		end
		local count = 0
		for event in pairs(events) do
			count += 1
			-- Any call whose name starts with `report` carrying the event as a literal argument:
			-- QuestService.report(player, "Event", n), quest.report(...) and the reportQuest(player,
			-- "Event") wrapper of WorldBossService all match.
			local pattern = 'report%w*%s*%([^%)]*"' .. event .. '"'
			if string.find(code, pattern) == nil then
				error(
					("quest event %q has no report call in %s: the quests using it can never progress"):format(
						event,
						SERVER_ROOT
					)
				)
			end
		end
		expect(count).toBeGreaterThan(5)
	end)

	it("has a quest for every declared target and a sane pool", function()
		for _, quest in ipairs(QuestConfig.Pool) do
			expect(type(quest.Id)).toBe("string")
			expect(quest.Target > 0).toBe(true)
			expect(quest.Period == "Daily" or quest.Period == "Weekly").toBe(true)
			expect(#quest.NameKey > 0).toBe(true)
		end
		-- Each period must offer strictly more quests than it selects, or the rotation is constant.
		local counts: { [string]: number } = { Daily = 0, Weekly = 0 }
		for _, quest in ipairs(QuestConfig.Pool) do
			counts[quest.Period] += 1
		end
		for period, def in pairs(QuestConfig.Periods) do
			expect(counts[period] > def.Count).toBe(true)
		end
	end)
end)
