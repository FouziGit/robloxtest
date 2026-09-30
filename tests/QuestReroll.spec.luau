--!strict
-- One free reroll a day (E10-S10), end to end: the remote a client may send, the server that decides it, and
-- the Quests screen that offers it. Its rules are QuestLogic.reroll's and are held in tests/QuestLogic.spec.luau;
-- here, that the server hands every one of them to it, answers every path, and that the board offers the swap
-- exactly where the server would take it.
local Engine = require("./engine")
local Harness = require("./harness")
local QuestConfig = require("../src/shared/Config/QuestConfig")
local QuestLogic = require("../src/shared/Pure/QuestLogic")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function strip(path: string): string
	return (fs.readFile(path):gsub("%-%-[^\n]*", ""))
end

-- The body of the function `header` opens in `source`, its whitespace folded to single spaces.
local function body(source: string, header: string): string
	local start = source:find(header, 1, true)
	if start == nil then
		error(("no %s: this gate would check nothing"):format(header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
end

local function has(text: string, needle: string): boolean
	return text:find(needle, 1, true) ~= nil
end

describe("the free reroll, on the server", function()
	it("is a client call with a Guard on each argument and a bucket of two", function()
		local remotes = strip("src/shared/Remotes.luau")
		local start = remotes:find("\tRerollQuest = {", 1, true)
		if start == nil then
			error("Remotes has no RerollQuest: the Swap button has no way to the server")
		end
		local definition = (remotes:sub(start, remotes:find("\n\t},", start, true) :: number):gsub("%s+", " "))
		expect(has(definition, 'Kind = "RemoteEvent", Direction = "ClientToServer",')).toBe(true)
		expect(has(definition, 'Args = { Guard.oneOf({ "Daily", "Weekly" }), Guard.string({ min = 1, max = 64 }) },')).toBe(
			true
		)
		expect(has(definition, "Rate = { Capacity = 2, Refill = 0.2 },")).toBe(true)
	end)

	it("hands every rule to QuestLogic.reroll, on the set the period check aligned, and answers every path", function()
		local service = strip("src/server/Services/QuestService.luau")
		local reroll = body(service, "function QuestService.reroll(")
		local ordered = {
			"local data = dataService.get(player)",
			"local set = ensureSet(player, data, period, os.time())",
			"Pool = QuestConfig.Pool, Count = PERIOD_DEFS[period].Count, Floor = QuestConfig.SoloFloor, Allowance = REROLLS[period],",
			"local verdict, drawn = QuestLogic.reroll(rules, period, set, questId)",
			"push(player)",
			'if verdict ~= "Rerolled" or drawn == nil then',
			'notify.send(player, "quest.rerollRefused", nil, "Error")',
			'notify.send(player, "quest.rerolled", { name = drawn.NameKey, target = drawn.Target }, "Success")',
		}
		local from = 1
		for _, line in ipairs(ordered) do
			local at = reroll:find(line, from, true)
			if at == nil then
				error(("QuestService.reroll lost, or reordered, %q"):format(line))
			end
			from = at + #line
		end
		expect(has(service, "local REROLLS = (QuestConfig.Rerolls :: any) :: { [string]: number }")).toBe(true)
		-- The only writer of a swap is QuestLogic.reroll: the service never touches Swaps itself.
		expect(has(service, "Swaps[")).toBe(false)
		local start = body(service, "function QuestService.Start(")
		expect(
			has(
				start,
				'registry.on("RerollQuest", function(player: Player, period: Period, questId: string) QuestService.reroll(player, period, questId) end)'
			)
		).toBe(true)
	end)
end)

type Fixture = { world: any, screen: any, data: any, changed: any, fired: { { any } } }

local DAILY_KEY = QuestLogic.setKey(QuestLogic.periodKey("Daily", os.time()), QuestConfig.PoolRevision)
local WEEKLY_KEY = QuestLogic.setKey(QuestLogic.periodKey("Weekly", os.time()), QuestConfig.PoolRevision)

local function drawn(period: QuestConfig.Period, key: string): { QuestConfig.QuestDef }
	return QuestLogic.select(QuestConfig.Pool, period, QuestConfig.Periods[period].Count, key, QuestConfig.SoloFloor)
end

local function setup(daily: any): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Screen = world.require("src/ui/screens/QuestsScreen")
	local fired: { { any } } = {}
	local changed = Engine.signal()
	local data = {
		Currency = { Folios = 0 },
		Quests = {
			Daily = daily,
			Weekly = { PeriodKey = WEEKLY_KEY, Progress = {}, Claimed = {}, Swaps = {} },
		},
	}
	local screen = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = changed,
		},
		RemoteClient = {
			fire = function(name: string, ...: any)
				table.insert(fired, { name, ... })
			end,
		},
		SoundController = { play = function() end },
		HudController = { showLocalToast = function() end },
		OnClose = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	return { world = world, screen = screen, data = data, changed = changed, fired = fired }
end

-- The card of `questId` on the board, and its Swap button when it has one.
local function card(fixture: Fixture, questId: string): (any, any)
	local found = fixture.screen.Instance:FindFirstChild(questId, true)
	assert(found ~= nil, ("no card for %s on the board"):format(questId))
	return found, found:FindFirstChild("Swap", true)
end

local function swapShown(fixture: Fixture, questId: string): boolean
	local _, swap = card(fixture, questId)
	return swap ~= nil and swap.Visible
end

describe("the free reroll, on the Quests screen", function()
	it("offers a swap on every daily quest being played, and none on a weekly one", function()
		local quests = drawn("Daily", DAILY_KEY)
		local fixture = setup({ PeriodKey = DAILY_KEY, Progress = {}, Claimed = {}, Swaps = {} })
		for _, def in ipairs(quests) do
			expect(swapShown(fixture, def.Id)).toBe(true)
		end
		for _, def in ipairs(drawn("Weekly", WEEKLY_KEY)) do
			local _, swap = card(fixture, def.Id)
			expect(swap).toBeNil()
		end
	end)

	it("offers none on a quest completed or claimed, where the server refuses it", function()
		local quests = drawn("Daily", DAILY_KEY)
		local set = { PeriodKey = DAILY_KEY, Progress = {}, Claimed = {}, Swaps = {} }
		set.Progress[quests[1].Id] = quests[1].Target
		set.Progress[quests[2].Id] = quests[2].Target
		set.Claimed[quests[2].Id] = true
		local fixture = setup(set)
		expect(swapShown(fixture, quests[1].Id)).toBe(false)
		expect(swapShown(fixture, quests[2].Id)).toBe(false)
		expect(swapShown(fixture, quests[3].Id)).toBe(true)
	end)

	it("sends the quest's period and id, and waits for the server", function()
		local quests = drawn("Daily", DAILY_KEY)
		local fixture = setup({ PeriodKey = DAILY_KEY, Progress = {}, Claimed = {}, Swaps = {} })
		local _, swap = card(fixture, quests[2].Id)
		swap.Activated:Fire()
		fixture.world:advance(0.1)
		expect(fixture.fired).toEqual({ { "RerollQuest", "Daily", quests[2].Id } })
	end)

	it("plays the replacement in the rerolled quest's place once the swap lands, and offers no other", function()
		local quests = drawn("Daily", DAILY_KEY)
		local set = { PeriodKey = DAILY_KEY, Progress = {}, Claimed = {}, Swaps = {} }
		local fixture = setup(set)
		-- What the server writes: QuestLogic.reroll on the same set.
		local verdict, taken = QuestLogic.reroll({
			Pool = QuestConfig.Pool,
			Count = QuestConfig.Periods.Daily.Count,
			Floor = QuestConfig.SoloFloor,
			Allowance = QuestConfig.Rerolls.Daily,
		}, "Daily", set :: any, quests[1].Id)
		expect(verdict).toBe("Rerolled")
		fixture.changed:Fire("Quests")
		fixture.world:advance(0.1)
		local id = (taken :: QuestConfig.QuestDef).Id
		expect(fixture.screen.Instance:FindFirstChild(quests[1].Id, true)).toBeNil()
		local replacement = card(fixture, id)
		expect(replacement.LayoutOrder).toBeGreaterThan(0)
		-- The day's reroll is spent: no card offers another.
		expect(swapShown(fixture, id)).toBe(false)
		expect(swapShown(fixture, quests[2].Id)).toBe(false)
		expect(swapShown(fixture, quests[3].Id)).toBe(false)
	end)
end)
