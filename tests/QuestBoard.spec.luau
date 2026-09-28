--!strict
-- The quests board (D-147, slice B): what can be claimed comes first and what is done sinks, the countdown
-- to the next draw never reads "none" while time is left, and the screen reads both the way this file
-- computes them -- on the server's clock, refreshed when the minute turns, never per frame.
local Harness = require("./harness")
local QuestBoard = require("../src/shared/Pure/QuestBoard")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SCREEN = "src/ui/screens/QuestsScreen.luau"
local CARD = "src/ui/components/QuestCard.luau"

local function stripComments(source: string): string
	local lines = {}
	for line in string.gmatch(source .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function status(claimed: boolean, completed: boolean): QuestBoard.Status
	return { Claimed = claimed, Completed = completed }
end

describe("the quests board", function()
	it("names the state of a quest from what the server counted", function()
		expect(QuestBoard.state(status(false, true))).toBe("Claimable")
		expect(QuestBoard.state(status(false, false))).toBe("InProgress")
		expect(QuestBoard.state(status(true, true))).toBe("Claimed")
	end)

	it("lists what can be claimed first, then what is played, then what is done, each in its drawn order", function()
		local states: { QuestBoard.State } = {
			"Claimed", -- 1
			"InProgress", -- 2
			"Claimable", -- 3
			"InProgress", -- 4
			"Claimable", -- 5
			"Claimed", -- 6
		}
		expect(QuestBoard.order(states)).toEqual({ 3, 5, 2, 4, 1, 6 })
		expect(QuestBoard.order({})).toEqual({})
		-- Nothing to reorder: the drawn order stands.
		expect(QuestBoard.order({ "InProgress", "InProgress" })).toEqual({ 1, 2 })
		expect(QuestBoard.order({ "Claimed", "Claimable" })).toEqual({ 2, 1 })
	end)

	it("counts down in hours and minutes under a day, rounded up to the minute", function()
		local key, params = QuestBoard.countdown(4 * 3600 + 12 * 60)
		expect(key).toBe("time.hoursMinutes")
		expect(params).toEqual({ hours = 4, minutes = 12 })
		-- One second past the minute is the next minute: time left never reads as less than it is.
		local _, early = QuestBoard.countdown(4 * 3600 + 11 * 60 + 1)
		expect(early).toEqual({ hours = 4, minutes = 12 })
		-- A last few seconds still read as a minute left, and only nothing left reads as nothing.
		local _, last = QuestBoard.countdown(5)
		expect(last).toEqual({ hours = 0, minutes = 1 })
		local _, none = QuestBoard.countdown(0)
		expect(none).toEqual({ hours = 0, minutes = 0 })
		-- A clock a little past the draw (the push has not landed yet) reads nothing left, not "-1h 59m".
		local _, late = QuestBoard.countdown(-90)
		expect(late).toEqual({ hours = 0, minutes = 0 })
	end)

	it("counts down in days and hours from a day on", function()
		local key, params = QuestBoard.countdown(3 * 86400 + 4 * 3600 + 59 * 60)
		expect(key).toBe("time.daysHours")
		expect(params).toEqual({ days = 3, hours = 4 })
		-- The last minute of a day is still hours and minutes; its last second, rounded up, is a whole day.
		local lastKey, lastMinute = QuestBoard.countdown(86400 - 60)
		expect(lastKey).toBe("time.hoursMinutes")
		expect(lastMinute).toEqual({ hours = 23, minutes = 59 })
		local edgeKey, edge = QuestBoard.countdown(86399)
		expect(edgeKey).toBe("time.daysHours")
		expect(edge).toEqual({ days = 1, hours = 0 })
		local dayKey, day = QuestBoard.countdown(86400)
		expect(dayKey).toBe("time.daysHours")
		expect(day).toEqual({ days = 1, hours = 0 })
	end)

	it("says both in both languages, with every placeholder it fills", function()
		for _, key in ipairs({ "time.hoursMinutes", "time.daysHours", "quest.resetsIn" }) do
			local entry = Strings.Table[key]
			assert(entry ~= nil, key .. " is missing from Strings")
			expect(entry.en ~= "" and entry.fr ~= "").toBe(true)
		end
		for _, seconds in ipairs({ 90, 86400 * 2 }) do
			local key, params = QuestBoard.countdown(seconds)
			for name in pairs(params) do
				expect(Strings.Table[key].en).toContain("{" .. name .. "}")
				expect(Strings.Table[key].fr).toContain("{" .. name .. "}")
			end
		end
	end)
end)

describe("the quests screen", function()
	local screen = stripComments(fs.readFile(SCREEN))
	local card = stripComments(fs.readFile(CARD))

	it("lists its cards in the board's order and counts down on the server's clock", function()
		expect(screen).toContain("for position, index in ipairs(QuestBoard.order(states)) do")
		expect(screen).toContain("card.Instance.LayoutOrder = LAYOUT_BASE[period] + position")
		local resetsIn = string.match(screen, "local function resetsIn%(.-\n\tend\n")
		assert(resetsIn ~= nil, "QuestsScreen has no resetsIn: this gate would check nothing")
		expect(resetsIn).toContain("local now = workspace:GetServerTimeNow()")
		expect(resetsIn).toContain("QuestBoard.countdown(QuestLogic.periodEndsAt(asPeriod(period), now) - now)")
	end)

	it("rewrites its countdown when the minute turns, and never from a frame loop", function()
		expect(screen).toContain("task.delay(SECONDS_PER_MINUTE - now % SECONDS_PER_MINUTE, tickCountdown, mine)")
		for _, source in ipairs({ screen, card }) do
			for _, loop in ipairs({ "Heartbeat", "RenderStepped", "Stepped", "while true" }) do
				expect(string.find(source, loop, 1, true)).toBeNil()
			end
		end
	end)

	it("wiggles only a claim that can be pressed, and holds still under reduced motion", function()
		local wiggle = string.match(card, "local function wiggle%(.-\n\tend\n")
		assert(wiggle ~= nil, "QuestCard has no wiggle: this gate would check nothing")
		expect(wiggle).toContain('if state ~= "Claimable" or pending or UiPrefs.reducedMotion() then')
	end)

	it("waits for the server before it stamps a claim", function()
		-- The click only sends and waits; the seal is stamped when the push says the quest is claimed.
		local click = string.match(card, "OnClick = function%(%)(.-)end,")
		assert(click ~= nil, "QuestCard's Claim has no OnClick: this gate would check nothing")
		expect(click).toContain("button:SetPending(true)")
		expect(string.find(click :: string, "Stamp", 1, true)).toBeNil()
		expect(card).toContain('if animate and previous == "Claimable" and next == "Claimed" then')
	end)
end)
