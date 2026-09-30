--!strict
-- The Ex-libris (E17-S2): the lifetime plates a player earns once and keeps. Each reads a measure the server counted
-- (the profile's lifetime stats and the Lectern's grades), and the server grants each once: its Folios, and for four
-- of them a title. Worded in both languages, and shown on the Lectern's third tab.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DrillConfig = require("../src/shared/Config/DrillConfig")
local Engine = require("./engine")
local ExLibris = require("../src/shared/Pure/ExLibris")
local ExLibrisConfig = require("../src/shared/Config/ExLibrisConfig")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local KIT_IDS: { string } = {}
for _, kit in ipairs(DrillConfig.Kit) do
	table.insert(KIT_IDS, kit.Id)
end

local function stats(overrides: { [string]: number }?): any
	local base = { Kills = 0, MatchesPlayed = 0, GlyphsCast = 0, BestChain = 0, BossKills = 0 }
	for key, value in pairs(overrides or {}) do
		base[key] = value
	end
	return base
end

local function plate(id: string): ExLibrisConfig.Plate
	for _, entry in ipairs(ExLibrisConfig.Plates) do
		if entry.Id == id then
			return entry
		end
	end
	error("no plate " .. id)
end

describe("the Ex-libris", function()
	it("names every plate and its measure in both languages, pays Folios, and titles only with a real title", function()
		local seen: { [string]: boolean } = {}
		local titled = 0
		for _, entry in ipairs(ExLibrisConfig.Plates) do
			if seen[entry.Id] then
				error("two plates are " .. entry.Id)
			end
			seen[entry.Id] = true
			for _, key in ipairs({ entry.NameKey, entry.DescKey }) do
				if not Strings.has(key) then
					error(("%s has no words for %s"):format(entry.Id, key))
				end
				-- A measure counts its target: its sentence has its two forms (Strings.Plurals, E12-S3).
				local forms = if Strings.Plurals[key] ~= nil then { key .. ".one", key .. ".other" } else { key }
				for _, form in ipairs(forms) do
					local words = (Strings.Table :: any)[form]
					expect(type(words.en)).toBe("string")
					expect(type(words.fr)).toBe("string")
				end
			end
			expect(entry.Target).toBeGreaterThan(0)
			expect(entry.Folios).toBeGreaterThan(0)
			expect(entry.Folios).toBe(math.floor(entry.Folios))
			local title = entry.Title
			if title ~= nil then
				titled += 1
				local item = CosmeticConfig.ById[title]
				if item == nil then
					error(("%s names %s, which is no cosmetic"):format(entry.Id, title))
				end
				expect(item.Slot).toBe("Title")
				expect(item.Sellable).toBe(false)
			end
		end
		expect(titled).toBe(4)
		-- Every measure a plate reads is one the facts give.
		local facts = ExLibris.facts(stats(), {}, KIT_IDS)
		for _, entry in ipairs(ExLibrisConfig.Plates) do
			if facts[entry.Measure] == nil then
				error(("%s reads %s, which no fact gives"):format(entry.Id, entry.Measure))
			end
		end
		-- A thousand is grouped the way the reader writes it.
		expect(Strings.t("exlibris.desc.GlyphsCast", { amount = 10000 }, "fr")).toBe("Trace 10\u{202F}000 glyphes")
	end)

	-- A count of one is the likeliest: the first plate of every profile, and the one milestone a profile between 45
	-- and 49 is owed at its first load. The words say it the way the game says any count ("New glyphs unlocked: 1"),
	-- never "1 plates" nor, in French, where 0 and 1 are both singular, "1 plaques" or "0 plaques".
	it("never puts a count of none or one before a plural, in either language", function()
		-- Each line with the placeholder its count is given in; the Folios they pay are hundreds.
		local lines: { { Key: string, Count: string, Locales: { string } } } = {
			{ Key = "milestone.caughtUp", Count = "count", Locales = { "en", "fr" } },
			{ Key = "exlibris.caughtUp", Count = "count", Locales = { "en", "fr" } },
			{ Key = "lectern.exlibris.count", Count = "count", Locales = { "en", "fr" } },
			-- "fois" is the same in the singular: the French reads right at one.
			{ Key = "exlibris.desc.BossKills", Count = "amount", Locales = { "en" } },
		}
		for _, line in ipairs(lines) do
			for _, locale in ipairs(line.Locales) do
				for _, count in ipairs({ 0, 1 }) do
					local params: { [string]: any } = { count = 450, amount = 450, total = 13 }
					params[line.Count] = count
					local text = Strings.t(line.Key, params, locale)
					local plural = string.match(text, "%f[%w]" .. count .. " ([^%s%p]+s)%f[%s%p%z]")
					if plural ~= nil and not (locale == "en" and count == 0) then
						error(("%s says %q in %s"):format(line.Key, text, locale))
					end
				end
			end
		end
	end)

	it("reads the lifetime stats, and the Lectern's grades by their grade", function()
		local drills = { KitString = 3, KitCancel = 3, KitChain = 2, Brand = 3, Wash = 2, Serif = 1 }
		local facts = ExLibris.facts(stats({ Kills = 120, BestChain = 5 }), drills, KIT_IDS)
		expect(facts.Kills).toBe(120)
		expect(facts.BestChain).toBe(5)
		expect(facts.KitCalligraphy).toBe(2)
		expect(facts.DrillsCalligraphy).toBe(3)
		expect(facts.DrillsFairCopy).toBe(5)
		expect(ExLibris.progress(plate("Erasures100"), facts)).toBe(100)
		expect(ExLibris.progress(plate("Erasures1000"), facts)).toBe(120)
	end)

	it("is due once its measure reaches its target, and never again once granted", function()
		local facts = ExLibris.facts(stats({ BestChain = 4 }), {}, KIT_IDS)
		expect(ExLibris.due(plate("Breath4"), facts, {})).toBe(true)
		expect(ExLibris.due(plate("Breath6"), facts, {})).toBe(false)
		expect(ExLibris.due(plate("Breath4"), facts, { Breath4 = 1 })).toBe(false)
	end)
end)

----------------------------------------------------------------
-- The server, run: HonoursService granting plates
----------------------------------------------------------------

type Fixture = {
	world: any,
	player: any,
	data: any,
	paid: { { Reason: string, Amount: number } },
	granted: { string },
	told: { string },
	-- The profile's sections replicated, in order, and whether each payment found its plate written and replicated
	-- before it.
	pushed: { string },
	marked: { boolean },
	loaded: Engine.Signal,
}

local function honours(): Fixture
	local player = { Name = "Scribe", UserId = 7 }
	local players = {
		GetPlayers = function(): { any }
			return { player }
		end,
	}
	local world = Engine.world({ Services = { Players = players } })
	local fixture: Fixture = {
		world = world,
		player = player,
		data = {
			Progression = { Level = 3, XP = 0, TotalXP = 0 },
			Milestones = {},
			Stats = stats(),
			Drills = {},
			ExLibris = {},
		},
		paid = {},
		granted = {},
		told = {},
		pushed = {},
		marked = {},
		loaded = Engine.signal(),
	}
	local service = world.require("src/server/Services/HonoursService")
	service.Init({
		DataService = {
			get = function(): any
				return fixture.data
			end,
			push = function(_player: any, section: string)
				table.insert(fixture.pushed, section)
			end,
			ProfileLoaded = fixture.loaded,
		},
		Notify = {
			send = function(_player: any, key: string)
				table.insert(fixture.told, key)
			end,
		},
		Currency = {
			add = function(_player: any, amount: number, reason: string): number
				table.insert(fixture.paid, { Reason = reason, Amount = amount })
				local id = string.match(reason, "^ExLibris(.+)$")
				table.insert(
					fixture.marked,
					id ~= nil and fixture.data.ExLibris[id] ~= nil and fixture.pushed[#fixture.pushed] == "ExLibris"
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
		Progression = { LevelUp = Engine.signal() },
	})
	service.Start()
	return fixture
end

local function wait(fixture: Fixture)
	fixture.world:advance(ExLibrisConfig.CheckSeconds + 0.5, 0.25)
end

describe("a plate of the Ex-libris", function()
	it("is granted by the server once its measure is met, once, however long it stays met", function()
		local fixture = honours()
		wait(fixture)
		expect(#fixture.paid).toBe(0)
		fixture.data.Stats.BestChain = 4
		wait(fixture)
		expect(fixture.paid).toEqual({ { Reason = "ExLibrisBreath4", Amount = 150 } })
		expect(type(fixture.data.ExLibris.Breath4)).toBe("number")
		-- Written and told to the client before a Folio of it is paid: the mark is what stops a second grant.
		expect(fixture.marked).toEqual({ true })
		expect(fixture.pushed).toEqual({ "ExLibris" })
		expect(fixture.told).toEqual({ "exlibris.granted" })
		for _ = 1, 3 do
			wait(fixture)
		end
		fixture.loaded:Fire(fixture.player, fixture.data)
		expect(#fixture.paid).toBe(1)
	end)

	it("hands over its title with its Folios", function()
		local fixture = honours()
		fixture.data.Stats.BestChain = 6
		wait(fixture)
		expect(fixture.granted).toEqual({ "TitleOneBreath" })
		expect(fixture.told).toEqual({ "exlibris.granted", "exlibris.grantedTitle" })
	end)

	it("reads the Lectern's grades as the server wrote them", function()
		local fixture = honours()
		fixture.data.Drills = { KitString = 3, KitCancel = 3, KitChain = 3 }
		wait(fixture)
		expect(fixture.paid).toEqual({ { Reason = "ExLibrisSteadyKit", Amount = 200 } })
	end)

	it("is given at load to a profile that met it before, quietly, in one line", function()
		local fixture = honours()
		fixture.data.Stats.Kills = 1500
		fixture.data.Stats.MatchesPlayed = 30
		fixture.loaded:Fire(fixture.player, fixture.data)
		local reasons: { string } = {}
		for _, payment in ipairs(fixture.paid) do
			table.insert(reasons, payment.Reason)
		end
		expect(reasons).toEqual({ "ExLibrisErasures100", "ExLibrisErasures1000", "ExLibrisPages25" })
		expect(fixture.told).toEqual({ "exlibris.caughtUp" })
		expect(fixture.granted).toEqual({ "TitleThousandErasures" })
		wait(fixture)
		expect(#fixture.paid).toBe(3)
	end)
end)

----------------------------------------------------------------
-- The Lectern's third tab, run
----------------------------------------------------------------

describe("the Lectern's Ex-libris", function()
	it("seals what the server granted and counts the rest from the profile", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Screen = world.require("src/ui/screens/LecternScreen")
		local data = {
			Progression = { Level = 3, XP = 0, TotalXP = 0 },
			Unlocks = { Glyphs = { "Brand" }, Pigments = {} },
			Loadout = { Slots = { "Brand" } },
			Stats = stats({ Kills = 140, BestChain = 3 }),
			Drills = {},
			Milestones = {},
			ExLibris = { Erasures100 = 1790000000 },
		}
		local screen = Screen.new({
			Localize = {
				t = function(key: string, params: any?): string
					return Strings.t(key, params, "en")
				end,
			},
			ClientData = {
				get = function(): any
					return data
				end,
				Changed = Engine.signal(),
			},
			RemoteClient = {
				fire = function() end,
				on = function(_name: string, handler: (...any) -> ()): any
					return Engine.signal():Connect(handler)
				end,
			},
			SoundController = { play = function() end },
			OnClose = function() end,
			OnNavigate = function() end,
			OnBack = function() end,
			CanGoBack = function(): boolean
				return false
			end,
		})
		screen:Open({ Tab = "ExLibris" })
		world:advance(0.5)
		local function line(name: string): string
			local row = screen.Instance:FindFirstChild(name, true)
			assert(row ~= nil, "the Ex-libris has no row " .. name)
			return row:FindFirstChild("Subtitle", true).Text
		end
		expect(screen.Instance:FindFirstChild("Count", true):FindFirstChild("Label", true).Text).toBe(
			("Plates: 1 / %d"):format(#ExLibrisConfig.Plates)
		)
		expect(line("Erasures100")).toBe("Defeat 100 foes, dummies and Forgers included · earned")
		expect(line("Erasures1000")).toBe("Defeat 1,000 foes, dummies and Forgers included · 140 / 1000")
		expect(line("Breath4")).toBe("Chain 4 glyphs · 3 / 4")
		local seal = screen.Instance:FindFirstChild("Erasures100", true):FindFirstChild("Seal", true)
		expect(seal:FindFirstChildWhichIsA("TextLabel").Text).toBe("√")
	end)
end)

return nil
