--!strict
-- Glyph cooldowns belong to the player, not to the character, so a fresh character between two rounds left them
-- running (docs/QA.md R13). D-20 promises that nothing a round did leaks into the next: every round, the match
-- itself and the way home start with every glyph ready. MatchService and GlyphService run for real in a
-- pretend server (tests/server.luau).
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local Server = require("./server")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
-- The longest cooldown of the starting loadout, and the longest of the roster: each outlasts the pause it is
-- cast across, so only a reset lets it be cast again.
local MARGIN = "Margin"
local COLOPHON = "Colophon"

local function knockOut(setup: Server.Services, player: any)
	player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.world:advance(0.2)
end

-- Two players in a ranked duel, past the countdown.
local function duel(): (Server.Services, any, any)
	local setup = Server.services()
	local a = setup.world:join(301, "Ada")
	local b = setup.world:join(302, "Bea")
	expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBe(nil)
	setup.world:advance(DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(a).Phase).toBe("Playing")
	return setup, a, b
end

-- The next round, past its pause and its countdown.
local function nextRound(setup: Server.Services, player: any)
	setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(player).Phase).toBe("Playing")
end

-- Equips the roster's longest cooldown, which the starting loadout does not hold.
local function equipColophon(setup: Server.Services, player: any)
	local data = setup.data.get(player)
	table.insert(data.Unlocks.Glyphs, COLOPHON)
	table.insert(data.Loadout.Slots, COLOPHON)
end

-- A duel won 2-0 by `a`, with `glyphId` cast just before the knock-out that decides it. Returns on the result.
local function wonWith(glyphId: string): (Server.Services, any)
	local setup, a, b = duel()
	equipColophon(setup, a)
	knockOut(setup, b)
	nextRound(setup, a)
	expect(setup.cast(a, glyphId)).toBe(true)
	knockOut(setup, b)
	setup.world:advance(MatchConfig.RoundOverSeconds + 0.1)
	expect(setup.match.getMatch(a).Phase).toBe("Result")
	return setup, a
end

describe("glyph cooldowns in a match (R13)", function()
	it("are running when a cast is repeated inside a round", function()
		local setup, a = duel()
		expect(GlyphConfig.ById[MARGIN].Cooldown > MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds).toBe(true)
		expect(setup.cast(a, MARGIN)).toBe(true)
		expect(setup.cast(a, MARGIN)).toBe(false)
		expect(setup.notices[#setup.notices].Key).toBe("hud.cast.cooldown")
	end)

	it("are all ready when the next round starts", function()
		local setup, a, b = duel()
		expect(setup.cast(a, MARGIN)).toBe(true)
		knockOut(setup, b)
		nextRound(setup, a)
		expect(setup.cast(a, MARGIN)).toBe(true)
	end)

	it("are all ready when a match starts, whatever the hub cost", function()
		local setup = Server.services()
		local a = setup.world:join(303, "Cyd")
		local b = setup.world:join(304, "Dov")
		a:LoadCharacterAsync()
		expect(setup.cast(a, MARGIN)).toBe(true)
		expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBe(nil)
		setup.world:advance(DUEL.CountdownSeconds + 0.5)
		expect(setup.cast(a, MARGIN)).toBe(true)
	end)

	it("are all ready when the match sends the player home", function()
		local setup, a = wonWith(COLOPHON)
		expect(GlyphConfig.ById[COLOPHON].Cooldown > MatchConfig.RoundOverSeconds + DUEL.ResultSeconds).toBe(true)
		setup.world:advance(DUEL.ResultSeconds)
		expect(setup.match.isInMatch(a)).toBe(false)
		expect(setup.cast(a, COLOPHON)).toBe(true)
	end)

	it("are all ready when the player asks for another duel from the result", function()
		local setup, a = wonWith(COLOPHON)
		expect(setup.match.releaseFromResult(a)).toBe(true)
		expect(setup.cast(a, COLOPHON)).toBe(true)
	end)

	it("cannot be cleared by anything a player does: a fresh character outside a match keeps them", function()
		local setup = Server.services()
		local a = setup.world:join(305, "Eli")
		a:LoadCharacterAsync()
		expect(setup.cast(a, MARGIN)).toBe(true)
		a:LoadCharacterAsync()
		expect(setup.cast(a, MARGIN)).toBe(false)
		-- The one caller is the match flow, which no remote reaches.
		local callers = {}
		local function scan(directory: string)
			for _, entry in ipairs(fs.readDir(directory)) do
				local path = directory .. "/" .. entry
				if fs.isDir(path) then
					scan(path)
				elseif string.find(fs.readFile(path), "resetCooldowns(", 1, true) ~= nil then
					table.insert(callers, path)
				end
			end
		end
		scan("src")
		table.sort(callers)
		expect(callers).toEqual({
			"src/server/Services/GlyphService.luau",
			"src/server/Services/MatchService.luau",
		})
	end)
end)
