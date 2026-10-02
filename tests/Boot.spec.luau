--!strict
-- A server that half started sends its players elsewhere (E9-S3, D-219).
--
-- The Bootstrap used to run every Init and Start under log.try and open the server whatever happened, so a server
-- whose DataService or MonetizationService had thrown kept its players: nothing they earned was saved, and a
-- purchase could be taken and never granted. src/server/Boot runs the same steps, and closes the server when a
-- service marked Critical failed. This runs the real Boot over fake services and players.
local Engine = require("./engine")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local BOOTSTRAP = "src/server/Bootstrap.server.luau"
local KEY = "kick.serverError"
-- The services the game cannot run without (docs/ROADMAP.md, E9-S3).
local CRITICAL = { "AntiCheatService", "CombatService", "DataService", "MatchService", "MonetizationService" }

type Stage = "Init" | "Start"

-- A world whose Players hold `present`, the Boot module loaded in it, and the kicks it handed out.
local function boot(present: { any }): (any, any, { [any]: string })
	local players = Engine.instance("Players")
	players.GetPlayers = function(): { any }
		return table.clone(present)
	end
	local world = Engine.world({ Services = { Players = players } })
	local kicks: { [any]: string } = {}
	for _, player in ipairs(present) do
		player.Kick = function(self: any, message: string)
			kicks[self] = message
		end
	end
	return world.require("src/server/Boot"), players, kicks
end

local function player(localeId: string): any
	local each = Engine.instance("Player")
	each.LocaleId = localeId
	return each
end

-- A service that records its steps in `log` and throws at `throwAt`, if any.
local function service(name: string, log: { string }, throwAt: Stage?): any
	return {
		Init = function(_deps: any)
			table.insert(log, name .. ".Init")
			if throwAt == "Init" then
				error(name .. " cannot init")
			end
		end,
		Start = function()
			table.insert(log, name .. ".Start")
			if throwAt == "Start" then
				error(name .. " cannot start")
			end
		end,
	}
end

describe("Boot.run", function()
	it("inits every service, then starts every one, whatever throws", function()
		local Boot = boot({})
		local steps: { string } = {}
		local failed = Boot.run({
			{ Name = "A", Service = service("A", steps, "Init"), Critical = true },
			{ Name = "B", Service = service("B", steps, nil) },
			{ Name = "C", Service = service("C", steps, "Start") },
		}, {})
		expect(steps).toEqual({ "A.Init", "B.Init", "C.Init", "A.Start", "B.Start", "C.Start" })
		-- Only a critical failure is reported, once however many of its steps threw.
		expect(failed).toEqual({ "A" })
	end)

	it("reports each critical service that failed at Init or at Start, in boot order", function()
		local Boot = boot({})
		local steps: { string } = {}
		local failed = Boot.run({
			{ Name = "Data", Service = service("Data", steps, "Start"), Critical = true },
			{ Name = "Quest", Service = service("Quest", steps, "Init") },
			{ Name = "Combat", Service = service("Combat", steps, "Init"), Critical = true },
			{ Name = "Match", Service = service("Match", steps, nil), Critical = true },
		}, {})
		expect(failed).toEqual({ "Data", "Combat" })
	end)

	it("keeps the server open when only a non-critical service failed", function()
		local present = { player("en-us") }
		local Boot, players, kicks = boot(present)
		local steps: { string } = {}
		local failed = Boot.run({
			{ Name = "Data", Service = service("Data", steps, nil), Critical = true },
			{ Name = "Leaderboard", Service = service("Leaderboard", steps, "Start") },
		}, {})
		expect(#failed).toBe(0)
		expect(next(kicks)).toBeNil()
		expect(players.PlayerAdded:count()).toBe(0)
	end)
end)

describe("Boot.close", function()
	-- The language each player reads, as LocaleService answers it: their translator's, which the language picked in
	-- the experience menu moves away from the app's (E12-S3).
	local function translated(each: any): string
		return if each.LocaleId == "en-us" then "fr" else "en"
	end

	it("kicks every player present, in the language LocaleService reads for them", function()
		local english, french = player("en-us"), player("fr-fr")
		local Boot, _, kicks = boot({ english, french })
		Boot.close({ "DataService" }, translated)
		expect(kicks[english]).toBe(Strings.t(KEY, nil, "fr"))
		expect(kicks[french]).toBe(Strings.t(KEY, nil, "en"))
		expect(kicks[english]).never.toBe(kicks[french])
	end)

	it("kicks every player who arrives afterwards", function()
		local Boot, players, _ = boot({})
		Boot.close({ "MonetizationService" }, translated)
		local late = player("fr-fr")
		local message: string? = nil
		late.Kick = function(_self: any, text: string)
			message = text
		end
		players.PlayerAdded:Fire(late)
		expect(message).toBe(Strings.t(KEY, nil, "en"))
	end)

	it("says server error and rejoin, in every locale", function()
		expect(Strings.has(KEY)).toBe(true)
		expect(Strings.t(KEY, nil, "en")).toContain("rejoin")
		expect(Strings.t(KEY, nil, "fr")).toContain("Rejoins")
	end)
end)

describe("the Bootstrap", function()
	local source = ((fs.readFile(BOOTSTRAP)):gsub("%-%-[^\n]*", ""))

	it("marks exactly the services the game cannot run without as critical", function()
		local marked: { string } = {}
		for name in source:gmatch('{ Name = "([%w_]+)", Service = [%w_]+, Critical = true }') do
			table.insert(marked, name)
		end
		table.sort(marked)
		expect(marked).toEqual(CRITICAL)
		-- Nothing else carries the flag in another spelling.
		local _, flags = source:gsub("Critical%s*=", "")
		expect(flags).toBe(#CRITICAL)
	end)

	it("boots through Boot and closes the server on a critical failure, and only then", function()
		local folded = source:gsub("%s+", " ")
		expect(folded).toContain(
			"local failed = Boot.run(ordered, deps) if #failed > 0 then Boot.close(failed, LocaleService.of) end"
		)
		expect(source:find(".Service.Init", 1, true)).toBeNil()
		expect(source:find(".Service.Start", 1, true)).toBeNil()
	end)
end)
