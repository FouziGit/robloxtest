--!strict
-- The Drills at the Lectern (E14-S2): a recipe drill per glyph and the kit's drills (the four strokes, the cancel,
-- a chain of three), graded Draft, Fair copy and Calligraphy. The grades are counted by the server from the events
-- GlyphService and CombatService fire on what they accepted, and each grade of each drill is paid once.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local DrillConfig = require("../src/shared/Config/DrillConfig")
local DrillLogic = require("../src/shared/Pure/DrillLogic")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SLIPS = DrillConfig.Slips

local function kit(id: string): DrillLogic.Drill
	for _, entry in ipairs(DrillConfig.Kit) do
		if entry.Id == id then
			return DrillLogic.kitDrill(entry)
		end
	end
	error("no kit drill " .. id)
end

local function recipe(glyphId: string): DrillLogic.Drill
	local def = GlyphConfig.byId(glyphId) :: GlyphConfig.GlyphDef
	return DrillLogic.recipeDrill({
		Id = def.Id,
		NameKey = def.NameKey,
		Cooldown = def.Cooldown,
		Utility = GlyphConfig.isUtility(def.Id),
	}, DrillConfig.Recipe)
end

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

----------------------------------------------------------------
-- What there is to drill
----------------------------------------------------------------

describe("the Lectern's drills", function()
	it("are the kit's three, then one recipe per glyph, each worded in both languages", function()
		local world = Engine.world()
		local catalog = world.require("src/shared/DrillCatalog")
		expect(#catalog.List).toBe(#DrillConfig.Kit + #GlyphConfig.Glyphs)
		local kinds: { [string]: boolean } = {}
		for index, drill in ipairs(catalog.List) do
			if index <= #DrillConfig.Kit then
				expect(drill.Glyph).toBeNil()
				kinds[drill.Kind] = true
				-- A kit drill's id is never a glyph's: StartDrill names one list.
				expect(GlyphConfig.byId(drill.Id)).toBeNil()
			else
				local glyph = GlyphConfig.Glyphs[index - #DrillConfig.Kit]
				expect(drill.Id).toBe(glyph.Id)
				expect(drill.Glyph).toBe(glyph.Id)
				expect(drill.Kind).toBe("Recipe")
			end
			for _, key in ipairs({ drill.NameKey, drill.HintKey }) do
				if not Strings.has(key) then
					error(("%s has no words for %s"):format(drill.Id, key))
				end
			end
			expect(catalog.ById[drill.Id]).toBe(drill)
		end
		expect(kinds).toEqual({ String = true, Cancel = true, Chain = true })
	end)

	it("grade in three, each paying more than the one below it, and each named", function()
		expect(#DrillConfig.Grades).toBe(DrillLogic.MaxGrade)
		for index, grade in ipairs(DrillConfig.Grades) do
			expect(Strings.has(grade.NameKey)).toBe(true)
			expect(grade.Folios).toBe(math.floor(grade.Folios))
			expect(grade.Xp).toBe(math.floor(grade.Xp))
			if index > 1 then
				expect(grade.Folios).toBeGreaterThan(DrillConfig.Grades[index - 1].Folios)
				expect(grade.Xp).toBeGreaterThan(DrillConfig.Grades[index - 1].Xp)
			end
		end
		expect(Strings.t("drills.grade.draft", nil, "fr")).toBe("Brouillon")
		expect(Strings.t("drills.grade.fairCopy", nil, "fr")).toBe("Mise au net")
		expect(Strings.t("drills.grade.calligraphy", nil, "fr")).toBe("Calligraphie")
	end)

	it("give every recipe's Calligraphy the time its cooldowns take, and the ink its casts cost", function()
		local ink = CombatConfig.Ink
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			local drill = recipe(glyph.Id)
			local fastest = (drill.Reps - 1) * glyph.Cooldown
			expect(drill.ParSeconds - fastest).toBeGreaterThanOrEqual(5)
			-- A full bar and what it regains in a fight between the casts pay for the whole set.
			if ink.Max + fastest * ink.RegenInCombat < drill.Reps * glyph.Cost then
				error(("%s's drill runs out of ink before its par"):format(glyph.Id))
			end
		end
	end)

	it("give the kit's Calligraphy twice what the fastest hands need", function()
		local melee, dash = CombatConfig.Melee, CombatConfig.Dash
		local stringTime = (#melee.Damage - 1) * melee.HitIntervalSeconds
		local strokes = kit("KitString")
		local fastestStrokes = strokes.Reps * stringTime + (strokes.Reps - 1) * melee.FinisherCooldownSeconds
		expect(strokes.ParSeconds).toBeGreaterThanOrEqual(2 * fastestStrokes)
		local cancel = kit("KitCancel")
		local fastestCancel = stringTime + (cancel.Reps - 1) * math.max(dash.CooldownSeconds, stringTime)
		expect(cancel.ParSeconds).toBeGreaterThanOrEqual(2 * fastestCancel)
		-- Three cancels, their dashes and all, from one bar.
		expect(cancel.Reps * (dash.Cost + dash.CancelCost)).toBeLessThanOrEqual(CombatConfig.Ink.Max)
		local chain = kit("KitChain")
		expect(chain.Length).toBe(3)
		-- The shortest cooldown of the three cheapest glyphs a new player holds bounds a second chain.
		local cooldowns: { number } = {}
		for _, id in ipairs(GlyphConfig.defaultUnlocks()) do
			table.insert(cooldowns, (GlyphConfig.byId(id) :: GlyphConfig.GlyphDef).Cooldown)
		end
		table.sort(cooldowns)
		local fastestChain = (chain.Length - 1) * GameConfig.Combo.ChainWindowSeconds * chain.Reps
			+ (chain.Reps - 1) * cooldowns[chain.Length]
		expect(chain.ParSeconds).toBeGreaterThanOrEqual(2 * fastestChain)
	end)
end)

----------------------------------------------------------------
-- What counts: the pure rules
----------------------------------------------------------------

describe("a recipe drill", function()
	it("counts its glyph landing, and misses it striking nothing or another glyph drawn", function()
		local run = DrillLogic.start(recipe("Brand"), 0)
		expect(DrillLogic.feed(run, { Kind = "Cast", Glyph = "Brand", Chain = 1 }, 1)).toBeNil()
		expect(DrillLogic.feed(run, { Kind = "Landed", Glyph = "Brand", Hits = 1 }, 1)).toBe("Rep")
		expect(DrillLogic.feed(run, { Kind = "Landed", Glyph = "Brand", Hits = 0 }, 2)).toBe("Miss")
		expect(DrillLogic.feed(run, { Kind = "Landed", Glyph = "Wash", Hits = 3 }, 3)).toBe("Miss")
		expect(run.Reps).toBe(1)
		expect(run.Misses).toBe(2)
	end)

	it("counts a glyph that deals no damage when the server accepted it", function()
		local run = DrillLogic.start(recipe("Margin"), 0)
		expect(recipe("Margin").Utility).toBe(true)
		expect(recipe("Margin").HintKey).toBe(DrillConfig.Recipe.UtilityHintKey)
		expect(DrillLogic.feed(run, { Kind = "Landed", Glyph = "Margin", Hits = 0 }, 1)).toBe("Rep")
	end)
end)

describe("the four strokes", function()
	local function swing(run: DrillLogic.Run, index: number, hits: number, at: number): DrillLogic.Outcome?
		return DrillLogic.feed(
			run,
			{ Kind = "Swing", Index = index, Last = index == #CombatConfig.Melee.Damage, Hits = hits },
			at
		)
	end

	it("count a string whose every stroke struck, and miss a stroke that struck nothing", function()
		local run = DrillLogic.start(kit("KitString"), 0)
		expect(swing(run, 1, 1, 1)).toBeNil()
		expect(swing(run, 2, 1, 1)).toBeNil()
		expect(swing(run, 3, 1, 1)).toBeNil()
		expect(swing(run, 4, 1, 2)).toBe("Rep")
		-- A string with a whiff in it is a miss, and its finisher does not count.
		expect(swing(run, 1, 1, 3)).toBeNil()
		expect(swing(run, 2, 0, 3)).toBe("Miss")
		expect(swing(run, 3, 1, 3)).toBeNil()
		expect(swing(run, 4, 1, 4)).toBeNil()
		expect(run.Reps).toBe(1)
		expect(run.Misses).toBe(1)
	end)
end)

describe("the cancel", function()
	it("counts a dash that cuts the recovery of a finisher that struck, and misses any other", function()
		local run = DrillLogic.start(kit("KitCancel"), 0)
		DrillLogic.feed(run, { Kind = "Swing", Index = 4, Last = true, Hits = 1 }, 1)
		expect(DrillLogic.feed(run, { Kind = "Dash", Cancelled = true }, 1)).toBe("Rep")
		-- A dash that cancels nothing.
		expect(DrillLogic.feed(run, { Kind = "Dash", Cancelled = false }, 2)).toBe("Miss")
		-- A cancel after a finisher that struck nothing.
		DrillLogic.feed(run, { Kind = "Swing", Index = 4, Last = true, Hits = 0 }, 3)
		expect(DrillLogic.feed(run, { Kind = "Dash", Cancelled = true }, 3)).toBe("Miss")
		-- The recovery a cancel answers is one finisher's: a second dash after it is not a cancel of it.
		DrillLogic.feed(run, { Kind = "Swing", Index = 4, Last = true, Hits = 1 }, 4)
		expect(DrillLogic.feed(run, { Kind = "Dash", Cancelled = true }, 4)).toBe("Rep")
		expect(DrillLogic.feed(run, { Kind = "Dash", Cancelled = true }, 5)).toBe("Miss")
	end)
end)

describe("the chain of three", function()
	it("counts a chain that reaches three, and misses one that ends short", function()
		local run = DrillLogic.start(kit("KitChain"), 0)
		local function cast(chain: number, at: number): DrillLogic.Outcome?
			return DrillLogic.feed(run, { Kind = "Cast", Glyph = "Brand", Chain = chain }, at)
		end
		expect(cast(1, 1)).toBeNil()
		expect(cast(2, 1)).toBeNil()
		expect(cast(3, 2)).toBe("Rep")
		-- Longer is no second repetition.
		expect(cast(4, 2)).toBeNil()
		expect(cast(1, 8)).toBeNil()
		expect(cast(2, 8)).toBeNil()
		expect(cast(1, 12)).toBe("Miss")
		expect(run.Reps).toBe(1)
		expect(run.Misses).toBe(1)
	end)
end)

describe("a finished set", function()
	local function landed(run: DrillLogic.Run, hits: number, at: number)
		DrillLogic.feed(run, { Kind = "Landed", Glyph = "Brand", Hits = hits }, at)
	end

	it("is Calligraphy with no miss inside par, Fair copy within the slips, Draft otherwise", function()
		local drill = recipe("Brand")
		local clean = DrillLogic.start(drill, 0)
		for rep = 1, drill.Reps do
			landed(clean, 1, 100 + rep * 4)
		end
		expect(DrillLogic.done(clean)).toBe(true)
		expect(DrillLogic.grade(clean, SLIPS)).toBe(3)
		-- The clock starts at the first counted event, not at the Lectern.
		expect(clean.FirstAt).toBe(104)

		local slow = DrillLogic.start(drill, 0)
		for rep = 1, drill.Reps do
			landed(slow, 1, rep * (drill.ParSeconds + 1))
		end
		expect(DrillLogic.grade(slow, SLIPS)).toBe(2)

		local slipped = DrillLogic.start(drill, 0)
		landed(slipped, 0, 1)
		for rep = 1, drill.Reps do
			landed(slipped, 1, 1 + rep)
		end
		expect(DrillLogic.grade(slipped, SLIPS)).toBe(2)

		local draft = DrillLogic.start(drill, 0)
		for _ = 1, SLIPS + 1 do
			landed(draft, 0, 1)
		end
		for rep = 1, drill.Reps do
			landed(draft, 1, 1 + rep)
		end
		expect(DrillLogic.grade(draft, SLIPS)).toBe(1)
		-- Nothing counts once the set is done, and an unfinished set has no grade.
		expect(DrillLogic.feed(draft, { Kind = "Landed", Glyph = "Brand", Hits = 1 }, 9)).toBeNil()
		expect(DrillLogic.grade(DrillLogic.start(drill, 0), SLIPS)).toBe(0)
	end)

	it("pays every grade above the best one already paid, and nothing else", function()
		expect(DrillLogic.toPay(0, 3)).toEqual({ 1, 2, 3 })
		expect(DrillLogic.toPay(1, 3)).toEqual({ 2, 3 })
		expect(DrillLogic.toPay(2, 2)).toEqual({})
		expect(DrillLogic.toPay(3, 1)).toEqual({})
		expect(DrillLogic.toPay(0, 0)).toEqual({})
	end)
end)

----------------------------------------------------------------
-- The server, run: DrillService with its services stood in for
----------------------------------------------------------------

type Fixture = {
	world: any,
	service: any,
	player: any,
	data: any,
	told: { string },
	paid: { number },
	xp: { number },
	changed: { any },
	inMatch: boolean,
	handlers: { [string]: (...any) -> () },
	glyphCast: Engine.Signal,
	castLanded: Engine.Signal,
	damaged: Engine.Signal,
	swung: Engine.Signal,
	dashed: Engine.Signal,
}

local function server(): Fixture
	local player = { Name = "Scribe", UserId = 7 }
	local players = {
		PlayerRemoving = Engine.signal(),
		GetPlayerByUserId = function(_self: any, userId: number): any
			return if userId == player.UserId then player else nil
		end,
	}
	local world = Engine.world({ Services = { Players = players } })
	local fixture: Fixture = {
		world = world,
		service = nil,
		player = player,
		data = {
			Unlocks = { Glyphs = { "Brand", "Wash", "Margin", "Ligature" }, Pigments = {} },
			Loadout = { Slots = { "Brand", "Wash", "Margin" } },
			Drills = {},
		},
		told = {},
		paid = {},
		xp = {},
		changed = {},
		inMatch = false,
		handlers = {},
		glyphCast = Engine.signal(),
		castLanded = Engine.signal(),
		damaged = Engine.signal(),
		swung = Engine.signal(),
		dashed = Engine.signal(),
	}
	local service = world.require("src/server/Services/DrillService")
	service.Init({
		Registry = {
			on = function(name: string, handler: (...any) -> ())
				fixture.handlers[name] = handler
			end,
			fire = function(name: string, _player: any, snapshot: any)
				if name == "DrillChanged" then
					table.insert(fixture.changed, snapshot or false)
				end
			end,
		},
		DataService = {
			get = function(): any
				return fixture.data
			end,
			push = function() end,
		},
		Notify = {
			send = function(_player: any, key: string)
				table.insert(fixture.told, key)
			end,
		},
		Currency = {
			add = function(_player: any, amount: number): number
				table.insert(fixture.paid, amount)
				return amount
			end,
		},
		Progression = {
			addXp = function(_player: any, amount: number): number
				table.insert(fixture.xp, amount)
				return amount
			end,
		},
		Glyph = { Cast = fixture.glyphCast, CastLanded = fixture.castLanded },
		Combat = { Damaged = fixture.damaged, Swung = fixture.swung, Dashed = fixture.dashed },
		Match = {
			isInMatch = function(): boolean
				return fixture.inMatch
			end,
		},
		WorldBoss = {
			isEngaged = function(): boolean
				return false
			end,
		},
		Battleground = {
			isInside = function(): boolean
				return false
			end,
		},
	})
	service.Start()
	fixture.service = service
	return fixture
end

local function sum(list: { number }): number
	local total = 0
	for _, value in ipairs(list) do
		total += value
	end
	return total
end

local function land(fixture: Fixture, glyphId: string, hits: number)
	fixture.castLanded:Fire(fixture.player, glyphId, hits)
end

describe("DrillService", function()
	it("begins a drill only on the client's word for which, and only for a glyph unlocked and equipped", function()
		local fixture = server()
		-- The only way in: a StartDrill whose one argument is a drill id the remote's guard knows.
		expect(fixture.handlers.StartDrill).never.toBeNil()
		expect(fixture.handlers.StopDrill).never.toBeNil()
		local remotes = code("src/shared/Remotes.luau")
		expect(remotes:find("Args = { Guard.oneOf((DrillCatalog.ids() :: any) :: { any }) },", 1, true)).never.toBeNil()
		fixture.handlers.StartDrill(fixture.player, "Blot")
		fixture.handlers.StartDrill(fixture.player, "Ligature")
		expect(fixture.told).toEqual({ "hud.cast.locked", "hud.cast.notEquipped" })
		expect(fixture.service.getRun(fixture.player)).toBeNil()
		fixture.inMatch = true
		fixture.handlers.StartDrill(fixture.player, "KitString")
		expect(fixture.told[3]).toBe("drills.notInHub")
		expect(fixture.service.getRun(fixture.player)).toBeNil()
	end)

	it("counts a set from the glyphs the server accepted, grades it and pays each grade once", function()
		local fixture = server()
		fixture.handlers.StartDrill(fixture.player, "Brand")
		expect(fixture.service.getRun(fixture.player)).toEqual({ Drill = "Brand", Reps = 0, Target = 3, Misses = 0 })
		for _ = 1, 3 do
			fixture.world:advance(4, 0.5)
			land(fixture, "Brand", 1)
		end
		expect(fixture.data.Drills.Brand).toBe(3)
		expect(fixture.paid).toEqual({ 15, 30, 60 })
		expect(fixture.xp).toEqual({ 50, 100, 200 })
		expect(fixture.told[#fixture.told]).toBe("drills.graded")
		expect(fixture.service.getRun(fixture.player)).toBeNil()
		expect(fixture.changed[#fixture.changed]).toBe(false)
		-- Drawn again at Calligraphy: said, and paid nothing.
		fixture.handlers.StartDrill(fixture.player, "Brand")
		for _ = 1, 3 do
			fixture.world:advance(4, 0.5)
			land(fixture, "Brand", 1)
		end
		expect(#fixture.paid).toBe(3)
		expect(fixture.told[#fixture.told]).toBe("drills.gradedAgain")
	end)

	it("pays a better grade only what it adds", function()
		local fixture = server()
		fixture.handlers.StartDrill(fixture.player, "Wash")
		for _ = 1, SLIPS + 1 do
			land(fixture, "Wash", 0)
		end
		for _ = 1, 3 do
			land(fixture, "Wash", 2)
		end
		expect(fixture.data.Drills.Wash).toBe(1)
		expect(fixture.paid).toEqual({ 15 })
		fixture.handlers.StartDrill(fixture.player, "Wash")
		for _ = 1, 3 do
			land(fixture, "Wash", 1)
		end
		expect(fixture.data.Drills.Wash).toBe(3)
		expect(fixture.paid).toEqual({ 15, 30, 60 })
		expect(sum(fixture.xp)).toBe(50 + 100 + 200)
	end)

	it("reads the four strokes from the swings and the bodies they struck", function()
		local fixture = server()
		fixture.handlers.StartDrill(fixture.player, "KitString")
		for _ = 1, 3 do
			for index = 1, #CombatConfig.Melee.Damage do
				fixture.damaged:Fire(fixture.player.UserId, {}, 8, "Melee")
				fixture.swung:Fire(fixture.player, index)
			end
		end
		expect(fixture.data.Drills.KitString).toBe(3)
		-- A glyph's damage is no stroke, and a swing that struck nothing is a miss.
		fixture.handlers.StartDrill(fixture.player, "KitString")
		fixture.damaged:Fire(fixture.player.UserId, {}, 20, "Glyph")
		fixture.swung:Fire(fixture.player, 1)
		expect(fixture.service.getRun(fixture.player).Misses).toBe(1)
	end)

	it("reads the cancel from the finisher and the dash", function()
		local fixture = server()
		fixture.handlers.StartDrill(fixture.player, "KitCancel")
		for _ = 1, 3 do
			fixture.damaged:Fire(fixture.player.UserId, {}, 14, "Melee")
			fixture.swung:Fire(fixture.player, #CombatConfig.Melee.Damage)
			fixture.dashed:Fire(fixture.player, true)
		end
		expect(fixture.data.Drills.KitCancel).toBe(3)
	end)

	it("reads the chain from the casts' own chain length", function()
		local fixture = server()
		fixture.handlers.StartDrill(fixture.player, "KitChain")
		for _ = 1, 2 do
			for chain = 1, 3 do
				fixture.glyphCast:Fire(fixture.player, "Brand", chain)
			end
		end
		expect(fixture.data.Drills.KitChain).toBe(3)
	end)

	it("puts a set down when its player leaves the hub, or lets it sit, and pays nothing for it", function()
		local fixture = server()
		fixture.handlers.StartDrill(fixture.player, "Brand")
		land(fixture, "Brand", 1)
		fixture.inMatch = true
		land(fixture, "Brand", 1)
		expect(fixture.told[#fixture.told]).toBe("drills.left")
		expect(fixture.service.getRun(fixture.player)).toBeNil()
		fixture.inMatch = false
		fixture.handlers.StartDrill(fixture.player, "Brand")
		fixture.world:advance(DrillConfig.IdleSeconds + 2 * DrillConfig.CheckSeconds, 0.5)
		expect(fixture.told[#fixture.told]).toBe("drills.lapsed")
		expect(fixture.service.getRun(fixture.player)).toBeNil()
		land(fixture, "Brand", 1)
		expect(#fixture.paid).toBe(0)
		expect(fixture.data.Drills.Brand).toBeNil()
	end)

	it("never counts a set it did not begin", function()
		local fixture = server()
		for _ = 1, 3 do
			land(fixture, "Brand", 1)
		end
		expect(fixture.data.Drills.Brand).toBeNil()
		expect(#fixture.told).toBe(0)
	end)
end)

return nil
