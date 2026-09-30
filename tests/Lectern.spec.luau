--!strict
-- The Lectern's screen, run (tests/engine.luau): the real LecternScreen on a player a few levels in. It asks the
-- server for a drill and gets out of the way; it never begins one the server would refuse, it sends the player
-- to the Loadout for a glyph that is not equipped, it shows the set the server says is running with the way to
-- put it down, and its road rings the next reward. The grades it shows are the profile's.
local Engine = require("./engine")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Fixture = {
	world: any,
	screen: any,
	data: any,
	changed: any,
	fired: { { any } },
	navigated: { string },
	closed: number,
	handlers: { [string]: (...any) -> () },
}

local function setup(tab: string?): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Screen = world.require("src/ui/screens/LecternScreen")
	local fixture: Fixture = {
		world = world,
		screen = nil,
		data = {
			Progression = { Level = 12, XP = 0, TotalXP = 0 },
			-- The eight of the first roster, and every glyph a level up to 12 unlocks.
			Unlocks = {
				Glyphs = {
					"Brand",
					"Wash",
					"Serif",
					"Sweep",
					"Bleed",
					"Margin",
					"Scorch",
					"Rupture",
					"Stipple",
					"Hairline",
					"Volute",
					"Ligature",
					"Binding",
					"Swash",
				},
				Pigments = {},
			},
			Loadout = { Slots = { "Brand", "Wash", "Serif", "Stipple" } },
			Drills = { KitString = 2, Brand = 3 },
			Milestones = {},
			Stats = { Kills = 0, MatchesPlayed = 0, GlyphsCast = 0, BestChain = 0, BossKills = 0 },
			ExLibris = {},
		},
		changed = Engine.signal(),
		fired = {},
		navigated = {},
		closed = 0,
		handlers = {},
	}
	fixture.screen = Screen.new({
		Localize = {
			t = function(key: string, params: any?): string
				return Strings.t(key, params, "en")
			end,
		},
		ClientData = {
			get = function(): any
				return fixture.data
			end,
			Changed = fixture.changed,
		},
		RemoteClient = {
			fire = function(name: string, ...: any)
				table.insert(fixture.fired, { name, ... })
			end,
			on = function(name: string, handler: (...any) -> ()): any
				fixture.handlers[name] = handler
				return Engine.signal():Connect(handler)
			end,
		},
		SoundController = { play = function() end },
		OnClose = function()
			fixture.closed += 1
		end,
		OnNavigate = function(id: string)
			table.insert(fixture.navigated, id)
		end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	fixture.screen:Open(if tab ~= nil then { Tab = tab } else nil)
	world:advance(0.5)
	return fixture
end

local function row(fixture: Fixture, name: string): any
	local found = fixture.screen.Instance:FindFirstChild(name, true)
	assert(found ~= nil, ("the Lectern has no row %s: this gate would check nothing"):format(name))
	return found
end

-- The words of the row's button (what its face says, not the label it measures itself with), and the button.
local function action(fixture: Fixture, name: string): (string, any)
	local button = row(fixture, name):FindFirstChildWhichIsA("TextButton", true)
	assert(button ~= nil, name .. " has no button")
	local words = button:FindFirstChild("Words", true)
	local label = if words ~= nil then words:FindFirstChild("Label") else nil
	assert(label ~= nil, name .. "'s button has no word")
	return label.Text, button
end

-- How many of the row's ♦ are filled: the grade it shows.
local function pips(fixture: Fixture, name: string): number
	local chalk = fixture.world.require("src/ui/Theme").Colors.Chalk
	local filled = 0
	for _, pip in ipairs(row(fixture, name):FindFirstChild("Pips", true):GetChildren()) do
		if pip:IsA("TextLabel") and pip.TextColor3 ~= chalk then
			filled += 1
		end
	end
	return filled
end

describe("the Lectern, run", function()
	it("lists the kit, then every glyph's recipe, each with the grade the profile holds", function()
		local fixture = setup()
		local content = fixture.screen.Instance:FindFirstChild("Content", true)
		local kitOrder = row(fixture, "KitChain").LayoutOrder
		expect(row(fixture, "KitString").LayoutOrder).toBeLessThan(kitOrder)
		expect(row(fixture, "Brand").LayoutOrder).toBeGreaterThan(kitOrder)
		expect(content).never.toBeNil()
		expect(pips(fixture, "KitString")).toBe(2)
		expect(pips(fixture, "Brand")).toBe(3)
		expect(pips(fixture, "Wash")).toBe(0)
		local subtitle = row(fixture, "Brand"):FindFirstChild("Subtitle", true)
		expect(subtitle.Text).toContain("Calligraphy")
	end)

	it("asks the server for a drill by its id and gets out of the player's way", function()
		local fixture = setup()
		local words, button = action(fixture, "Wash")
		expect(words).toBe("Start")
		button.Activated:Fire()
		expect(fixture.fired).toEqual({ { "StartDrill", "Wash" } })
		expect(fixture.closed).toBe(1)
		-- A drill already graded is drawn again, not begun.
		expect((action(fixture, "Brand"))).toBe("Again")
	end)

	it("never offers a drill the server would refuse", function()
		local fixture = setup()
		-- Locked: its level, and nothing to press.
		local words, button = action(fixture, "Blot")
		expect(words).toContain("Unlocks at level 25")
		button.Activated:Fire()
		expect(#fixture.fired).toBe(0)
		-- A pigment's glyph says so.
		expect((action(fixture, "Strike"))).toContain("Requires the Orpiment pigment")
		-- Unlocked but not in the loadout: to the Loadout, not to the server.
		local equip, equipButton = action(fixture, "Hairline")
		expect(equip).toBe("Equip")
		equipButton.Activated:Fire()
		expect(fixture.navigated).toEqual({ "Loadout" })
		expect(#fixture.fired).toBe(0)
	end)

	it("heads the list with the set the server says is running, and puts it down on the server's word", function()
		local fixture = setup()
		fixture.handlers.DrillChanged({ Drill = "Wash", Reps = 1, Target = 3, Misses = 2 })
		local running = row(fixture, "Running")
		expect(running.LayoutOrder).toBe(1)
		expect(running:FindFirstChild("Label", true).Text).toBe("Now: Wash · 1 / 3 · missed 2")
		local words, button = action(fixture, "Running")
		expect(words).toBe("Put down")
		button.Activated:Fire()
		expect(fixture.fired).toEqual({ { "StopDrill" } })
		-- Its own row says the same.
		expect((action(fixture, "Wash"))).toBe("Put down")
		fixture.handlers.DrillChanged(nil)
		expect(fixture.screen.Instance:FindFirstChild("Running", true)).toBeNil()
	end)

	it("follows the profile: a grade paid while it is up is shown at once", function()
		local fixture = setup()
		fixture.data.Drills.Wash = 1
		fixture.changed:Fire("Drills")
		expect(pips(fixture, "Wash")).toBe(1)
	end)

	-- Equip sends the player to the Loadout, which closes this screen: whatever moved while it was away (the glyph
	-- equipped, a level, a milestone, a plate) is shown when Back brings it again, one section of the profile each.
	it("comes back showing what the profile gained while it was away", function()
		-- The words in a slot of a row, or none when the slot is empty.
		local function label(fixture: Fixture, name: string, part: string): string
			local slot = row(fixture, name):FindFirstChild(part, true)
			local words = if slot ~= nil then slot:FindFirstChild("Label", true) else nil
			return if words ~= nil then words.Text else ""
		end
		for _, case in ipairs({
			{
				Tab = nil,
				Section = "Loadout",
				Change = function(data: any)
					table.insert(data.Loadout.Slots, "Hairline")
				end,
				Shown = function(fixture: Fixture): boolean
					return (action(fixture, "Hairline")) == "Start"
				end,
			},
			{
				Tab = nil,
				Section = "Unlocks",
				Change = function(data: any)
					table.insert(data.Unlocks.Glyphs, "Blot")
				end,
				Shown = function(fixture: Fixture): boolean
					return (action(fixture, "Blot")) == "Equip"
				end,
			},
			{
				Tab = "Road",
				Section = "Progression",
				Change = function(data: any)
					data.Progression.Level = 16
				end,
				Shown = function(fixture: Fixture): boolean
					return label(fixture, "Level", "Left") == "Level 16"
				end,
			},
			{
				Tab = "Road",
				Section = "Milestones",
				Change = function(data: any)
					data.Milestones["50"] = true
				end,
				Shown = function(fixture: Fixture): boolean
					return label(fixture, "Step5050", "Right") == "Yours"
				end,
			},
			{
				Tab = "ExLibris",
				Section = "ExLibris",
				Change = function(data: any)
					data.ExLibris.Breath4 = 1
				end,
				Shown = function(fixture: Fixture): boolean
					return label(fixture, "Count", "Left"):sub(1, 5) == "1 of "
				end,
			},
			{
				Tab = "ExLibris",
				Section = "Stats",
				Change = function(data: any)
					data.Stats.BestChain = 3
				end,
				Shown = function(fixture: Fixture): boolean
					return row(fixture, "Breath4"):FindFirstChild("Subtitle", true).Text == "Chain 4 glyphs · 3 / 4"
				end,
			},
		}) do
			local fixture = setup(case.Tab)
			if case.Shown(fixture) then
				error(case.Section .. " already shows its change: this gate would check nothing")
			end
			fixture.screen:Close()
			case.Change(fixture.data)
			fixture.changed:Fire(case.Section)
			fixture.screen:Open(if case.Tab ~= nil then { Tab = case.Tab } else nil)
			fixture.world:advance(0.5)
			if not case.Shown(fixture) then
				error(("the Lectern came back without the %s it gained"):format(case.Section))
			end
		end
	end)

	it("lays the level road out, what the player holds as theirs and the next reward ringed", function()
		local fixture = setup("Road")
		expect(fixture.screen.Instance:FindFirstChild("Brand", true)).toBeNil()
		-- Level 12: Swash (12) is theirs, Gilding and Pounce (15) come next, the roster's first of them ringed.
		local held = row(fixture, "Step12Swash")
		expect(held:FindFirstChild("Right", true):FindFirstChild("Label").Text).toBe("Yours")
		local upcoming = row(fixture, "Step15Gilding")
		expect(upcoming:FindFirstChild("Right", true):FindFirstChild("Label").Text).toBe("Next")
		local milestone = row(fixture, "Step5050")
		expect(milestone:FindFirstChild("Label", true).Text).toBe("Rubricator · 500 Folios")
		expect(row(fixture, "Step100100")).never.toBeNil()
	end)
end)

return nil
