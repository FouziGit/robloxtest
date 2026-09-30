--!strict
-- The level road (E17-S2): every reward a level gives, the milestones from 45 to the last level among them, the
-- Result card that always names the next one, and the server that pays each milestone once. The glyphs stopped at
-- 36 and the pigment at 40: from there a veteran climbed sixty levels for a number, and the card named nothing.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local Engine = require("./engine")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local LevelRoad = require("../src/shared/Pure/LevelRoad")
local Measure = require("./measure")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MAX = ProgressionConfig.MaxLevel
local ORPIMENT = ProgressionConfig.OrpimentUnlockLevel

local function road(): { LevelRoad.Step }
	return LevelRoad.build(GlyphConfig.levelUnlocks(), ORPIMENT, ProgressionConfig.Milestones)
end

describe("the level road", function()
	it("has a next reward at every level from 1 to 99, and none past the last level", function()
		local steps = road()
		for level = 1, MAX - 1 do
			local step = LevelRoad.nextReward(steps, level)
			if step == nil then
				error(("level %d has no next reward"):format(level))
			end
			expect(step.Level).toBeGreaterThan(level)
		end
		expect(LevelRoad.nextReward(steps, MAX)).toBeNil()
	end)

	it("sets a milestone every five levels from 45 to the last, each paying Folios and naming a real title", function()
		local levels: { number } = {}
		for _, milestone in ipairs(ProgressionConfig.Milestones) do
			table.insert(levels, milestone.Level)
			expect(milestone.Folios).toBeGreaterThan(0)
			expect(milestone.Folios).toBe(math.floor(milestone.Folios))
			local title = milestone.Title
			if title ~= nil then
				local item = CosmeticConfig.ById[title]
				if item == nil then
					error(("the milestone of level %d names %s, which is no cosmetic"):format(milestone.Level, title))
				end
				expect(item.Slot).toBe("Title")
				-- A milestone's title is earned there and nowhere else: never on a shelf.
				expect(item.Sellable).toBe(false)
				expect(Strings.has(item.NameKey)).toBe(true)
			end
		end
		local expected: { number } = {}
		for level = 45, MAX, 5 do
			table.insert(expected, level)
		end
		expect(levels).toEqual(expected)
		-- Past the last unlock, and past the pigment.
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			if glyph.Unlock.Kind == "Level" then
				expect(glyph.Unlock.Value :: number).toBeLessThan(levels[1])
			end
		end
		expect(ORPIMENT).toBeLessThan(levels[1])
	end)

	it("meets one level's rewards in the roster's order, glyphs before the pigment and the milestone", function()
		local steps = road()
		for index = 2, #steps do
			local before, after = steps[index - 1], steps[index]
			expect(after.Level).toBeGreaterThanOrEqual(before.Level)
		end
		-- Level 5 unlocks two glyphs; the road names the roster's first of them first.
		local first = LevelRoad.nextReward(steps, 4) :: LevelRoad.Step
		expect(first.Level).toBe(5)
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			if glyph.Unlock.Kind == "Level" and glyph.Unlock.Value == 5 then
				expect(first.Id).toBe(glyph.Id)
				break
			end
		end
		local tied = LevelRoad.build({}, 50, { { Level = 50, Folios = 1 } })
		expect(tied[1].Kind).toBe("Pigment")
		expect(tied[2].Kind).toBe("Milestone")
	end)

	it("skips what the player already holds", function()
		local steps = road()
		local pigment = LevelRoad.nextReward(steps, ORPIMENT - 1) :: LevelRoad.Step
		expect(pigment.Kind).toBe("Pigment")
		-- Bought with its pass: the next thing is the first milestone.
		local held = LevelRoad.nextReward(steps, ORPIMENT - 1, function(step: LevelRoad.Step): boolean
			return step.Kind == "Pigment"
		end) :: LevelRoad.Step
		expect(held.Kind).toBe("Milestone")
		expect(held.Level).toBe(45)
	end)

	it("owes a loading profile every milestone under its level it was never paid, lowest first", function()
		local steps = road()
		local due = LevelRoad.dueMilestones(steps, 62, {})
		local levels: { number } = {}
		for _, step in ipairs(due) do
			table.insert(levels, step.Level)
		end
		expect(levels).toEqual({ 45, 50, 55, 60 })
		expect(#LevelRoad.dueMilestones(steps, 62, { ["45"] = true, ["50"] = true, ["55"] = true, ["60"] = true })).toBe(
			0
		)
		expect(#LevelRoad.dueMilestones(steps, 44, {})).toBe(0)
		expect((LevelRoad.milestoneAt(steps, 50) :: LevelRoad.Step).Title).toBe("TitleRubricator")
		expect(LevelRoad.milestoneAt(steps, 51)).toBeNil()
	end)
end)

----------------------------------------------------------------
-- The Result card, run
----------------------------------------------------------------

local OUTCOME = {
	ModeId = "Duel1v1",
	Won = true,
	Draw = false,
	Scores = { 3, 1 },
	Xp = 0,
	Folios = 40,
	RatingBefore = 1000,
	RatingAfter = 1018,
	RankKeyBefore = "",
	RankKeyAfter = "",
	FirstWinOfDay = false,
	Casts = 10,
	Hits = 7,
	DamageDealt = 300,
	DamageTaken = 100,
	Grade = "grade.clean",
}

-- The line the card promises at `level`, in English, for a profile holding `pigments`.
local function promise(level: number, pigments: { string }?): (any, string)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local profile = {
		Progression = { Level = level, XP = 0, TotalXP = 0 },
		Stats = { GlyphsCast = 0, GlyphsHit = 0, Kills = 0, Deaths = 0, MatchesPlayed = 1, BestChain = 0 },
		Unlocks = { Glyphs = GlyphConfig.defaultUnlocks(), Pigments = pigments or {} },
		Milestones = {},
	}
	local Screen = world.require("src/ui/screens/ResultScreen")
	local screen = Screen.new({
		Localize = {
			t = function(key: string, params: any?): string
				return Strings.t(key, params, "en")
			end,
		},
		ClientData = {
			get = function(): any
				return profile
			end,
			Changed = Engine.signal(),
		},
		SoundController = { play = function() end },
		MatchController = {
			getLastOutcome = function(): any
				return OUTCOME
			end,
			joinQueue = function() end,
		},
		OnClose = function() end,
	})
	screen:Open()
	world:advance(1)
	local line = screen.Instance:FindFirstChild("NextUnlock", true)
	assert(line ~= nil, "the Result has no line for the next reward: this gate would check nothing")
	return line, line.Text
end

describe("the Result card", function()
	it("names the next reward at every stage of the road", function()
		for _, case in ipairs({
			{ Level = 1, Text = "at level 5" },
			{ Level = 36, Text = "Next: Orpiment at level 40" },
			{ Level = 40, Text = "Next: 450 Folios at level 45" },
			{ Level = 46, Text = "Next: the title Rubricator and 500 Folios at level 50" },
			{ Level = 99, Text = "Next: the title A Hundred Leaves and 1,000 Folios at level 100" },
		}) do
			local line, text = promise(case.Level)
			expect(line.Visible).toBe(true)
			if string.find(text, case.Text, 1, true) == nil then
				error(("at level %d the card says %q, not %q"):format(case.Level, text, case.Text))
			end
		end
	end)

	it("never promises the pigment to a player who already holds it", function()
		local _, text = promise(ORPIMENT - 2, { "Orpiment" })
		expect(text).toBe("Next: 450 Folios at level 45")
	end)

	it("names every reward of the road whole, in both languages, on the narrowest screens", function()
		for _, window in ipairs({ { 667, 375, true }, { 1366, 768, false } }) do
			local world = Engine.world({ Stubs = Engine.interfaceStubs() })
			if window[3] then
				Engine.phone(world, window[1], window[2])
			else
				world.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(window[1], window[2])
			end
			local Theme = world.require("src/ui/Theme")
			local screenWidth = window[1] / Theme.activeScale()
			local Screen = world.require("src/ui/screens/ResultScreen")
			local screen = Screen.new({
				Localize = {
					t = function(key: string): string
						return key
					end,
				},
				ClientData = {
					get = function(): any
						return nil
					end,
					Changed = Engine.signal(),
				},
				SoundController = { play = function() end },
				MatchController = {
					getLastOutcome = function(): any
						return OUTCOME
					end,
					joinQueue = function() end,
				},
				OnClose = function() end,
			})
			screen:Open()
			world:advance(1)
			local line = screen.Instance:FindFirstChild("NextUnlock", true)
			local width = Measure.widthOf(line, screenWidth)
			local Words = world.require("src/ui/LevelRoadWords")
			for _, locale in ipairs({ "en", "fr" }) do
				local function t(key: string, params: any?): string
					return Strings.t(key, params, locale)
				end
				for _, step in ipairs(Words.Road) do
					local text = t("match.nextUnlock", { name = Words.reward(step, t), level = step.Level })
					if Measure.textWidth(text, line.TextSize) > width then
						error(("%q is cut on a %d x %d window (%d wide)"):format(text, window[1], window[2], width))
					end
				end
				expect(Measure.textWidth(t("levelroad.complete"), line.TextSize)).toBeLessThanOrEqual(width)
			end
		end
	end)

	it("says the road is walked at the last level", function()
		local line, text = promise(MAX)
		expect(line.Visible).toBe(true)
		expect(text).toBe(Strings.t("levelroad.complete", nil, "en"))
	end)
end)

----------------------------------------------------------------
-- The server, run: HonoursService with its services stood in for
----------------------------------------------------------------

type Harnessed = {
	service: any,
	player: any,
	data: any,
	paid: { { Reason: string, Amount: number } },
	granted: { string },
	told: { string },
	-- The profile's sections replicated, in order, and whether each payment found its milestone written and
	-- replicated before it.
	pushed: { string },
	marked: { boolean },
	loaded: Engine.Signal,
	levelUp: Engine.Signal,
}

local function honours(level: number, milestones: { [string]: boolean }?): Harnessed
	local world = Engine.world()
	local loaded, levelUp = Engine.signal(), Engine.signal()
	local player = { Name = "Scribe", UserId = 7 }
	local data = {
		Progression = { Level = level, XP = 0, TotalXP = 0 },
		Milestones = milestones or {},
		-- A profile that has earned no plate of the Ex-libris, and meets none.
		Stats = { Kills = 0, MatchesPlayed = 0, GlyphsCast = 0, BestChain = 0, BossKills = 0 },
		Drills = {},
		ExLibris = {},
	}
	local fixture: Harnessed = {
		service = nil,
		player = player,
		data = data,
		paid = {},
		granted = {},
		told = {},
		pushed = {},
		marked = {},
		loaded = loaded,
		levelUp = levelUp,
	}
	local service = world.require("src/server/Services/HonoursService")
	service.Init({
		DataService = {
			get = function(): any
				return data
			end,
			push = function(_player: any, section: string)
				table.insert(fixture.pushed, section)
			end,
			ProfileLoaded = loaded,
		},
		Notify = {
			send = function(_player: any, key: string)
				table.insert(fixture.told, key)
			end,
		},
		Currency = {
			add = function(_player: any, amount: number, reason: string): number
				table.insert(fixture.paid, { Reason = reason, Amount = amount })
				local key = string.match(reason, "^Milestone(%d+)$")
				table.insert(
					fixture.marked,
					key ~= nil and data.Milestones[key] == true and fixture.pushed[#fixture.pushed] == "Milestones"
				)
				return amount
			end,
		},
		Cosmetic = {
			grant = function(_player: any, id: string): boolean
				table.insert(fixture.granted, id)
				return true
			end,
		},
		Progression = { LevelUp = levelUp },
	})
	service.Start()
	fixture.service = service
	return fixture
end

describe("a milestone", function()
	it("is paid by the level-up that reaches it, once, however many times that level is announced", function()
		local fixture = honours(45)
		fixture.levelUp:Fire(fixture.player, 45)
		fixture.levelUp:Fire(fixture.player, 45)
		expect(fixture.paid).toEqual({ { Reason = "Milestone45", Amount = 450 } })
		expect(fixture.data.Milestones["45"]).toBe(true)
		-- Written and told to the client before a Folio of it is paid: the mark is what stops a second payment.
		expect(fixture.marked).toEqual({ true })
		expect(fixture.pushed).toEqual({ "Milestones" })
		expect(fixture.told).toEqual({ "milestone.reached" })
		-- A level with no milestone pays nothing.
		fixture.levelUp:Fire(fixture.player, 46)
		expect(#fixture.paid).toBe(1)
	end)

	it("pays its title with its Folios", function()
		local fixture = honours(50)
		fixture.levelUp:Fire(fixture.player, 50)
		expect(fixture.paid).toEqual({ { Reason = "Milestone50", Amount = 500 } })
		expect(fixture.granted).toEqual({ "TitleRubricator" })
		expect(fixture.told).toEqual({ "milestone.reachedTitle" })
	end)

	it("is paid at the load of a profile that climbed past it unpaid, and never at the next load", function()
		local fixture = honours(62, { ["50"] = true })
		fixture.loaded:Fire(fixture.player, fixture.data)
		local reasons: { string } = {}
		for _, payment in ipairs(fixture.paid) do
			table.insert(reasons, payment.Reason)
		end
		expect(reasons).toEqual({ "Milestone45", "Milestone55", "Milestone60" })
		-- Said once, not once a milestone.
		expect(fixture.told).toEqual({ "milestone.caughtUp" })
		fixture.loaded:Fire(fixture.player, fixture.data)
		fixture.levelUp:Fire(fixture.player, 60)
		expect(#fixture.paid).toBe(3)
		expect(#fixture.granted).toBe(0)
		expect(#fixture.told).toBe(1)
	end)

	-- Every spec above stands the service in for itself: left out of the server's list, no milestone and no plate
	-- would ever be paid, and each of them would still pass.
	it("is paid by a HonoursService the server starts, after the services it pays through", function()
		local bootstrap = ((fs.readFile("src/server/Bootstrap.server.luau")):gsub("%-%-[^\n]*", ""))
		expect(bootstrap:find("Honours = HonoursService,", 1, true)).never.toBeNil()
		local at = bootstrap:find('{ Name = "HonoursService", Service = HonoursService }', 1, true)
		if at == nil then
			error("the server never starts HonoursService")
		end
		for _, before in ipairs({
			"DataService",
			"NotifyService",
			"CurrencyService",
			"ProgressionService",
			"CosmeticService",
		}) do
			-- An entry is plain, or marked Critical (the server closes when it fails to start).
			local plain = ('{ Name = "%s", Service = %s }'):format(before, before)
			local critical = ('{ Name = "%s", Service = %s, Critical = true }'):format(before, before)
			local earlier = bootstrap:find(plain, 1, true) or bootstrap:find(critical, 1, true)
			if earlier == nil or earlier > at then
				error(("HonoursService starts before %s"):format(before))
			end
		end
	end)
end)

return nil
