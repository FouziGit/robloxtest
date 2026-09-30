--!strict
-- How a session ends, and what a ranked match makes of it (docs/QA.md R3, R4, R15). DataService, RankingService
-- and MatchService run for real in a pretend server (tests/server.luau): the order of a departure, a shutdown and
-- another server taking the profile is exactly what the source gates could not see.
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Server = require("./server")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
local GRACE = GameConfig.Server.LeaveGraceSeconds
local VENDOR = "src/server/Vendor/ProfileStore.luau"
local ELSEWHERE_FR = Strings.t("kick.sessionElsewhere", nil, "fr")

local function key(player: any): string
	return "Player_" .. tostring(player.UserId)
end

-- Two players in a ranked duel, past the countdown: the round is being played.
local function duel(): (Server.Services, any, any)
	local setup = Server.services()
	local a = setup.world:join(101, "Ada")
	local b = setup.world:join(102, "Bea")
	expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBe(nil)
	setup.world:advance(DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(a).Phase).toBe("Playing")
	return setup, a, b
end

-- The duel is fought: a hit each way, and the rounds played past MatchConfig.MinPlayedSeconds. A forfeit before
-- that is void (D-255, tests/RankedFarm.spec.luau): whoever stays gets no result.
local function fought(setup: Server.Services, a: any, b: any)
	setup.hit(a, b, 10)
	setup.hit(b, a, 10)
	setup.world:advance(MatchConfig.MinPlayedSeconds)
end

-- The duel record a key last wrote to the DataStore, or nil when none was ever written.
local function writtenDuel(world: Server.World, player: any): any
	local saved = world.store.written[key(player)]
	assert(saved ~= nil, "nothing was written for " .. player.Name)
	return saved.Rank.Modes[DUEL.Id]
end

-- Takes `player` down, and lets the tick that sees it close the round.
local function knockOut(setup: Server.Services, player: any)
	player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.world:advance(0.2)
end

local function kicked(world: Server.World, player: any): string?
	for _, kick in ipairs(world.kicks) do
		if kick.Player == player then
			return kick.Message
		end
	end
	return nil
end

describe("a shutdown during a ranked duel (R3)", function()
	it("debits nobody when the players are removed before the server says it is closing", function()
		-- Studio's order, and a live server's when the race goes that way.
		local setup, a, b = duel()
		setup.world:leave(a)
		setup.world:leave(b)
		setup.world:advance(0.5)
		setup.world:close()
		setup.world.store:shutdown()
		setup.world:advance(GRACE + 1)
		expect(writtenDuel(setup.world, a)).toBeNil()
		expect(writtenDuel(setup.world, b)).toBeNil()
		expect(setup.world:said("abandoned " .. DUEL.Id)).toBe(false)
	end)

	it("debits nobody when the server says it is closing first", function()
		local setup, a, b = duel()
		setup.world:close()
		setup.world.store:shutdown()
		setup.world:leave(a)
		setup.world:advance(0.2)
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(writtenDuel(setup.world, a)).toBeNil()
		expect(writtenDuel(setup.world, b)).toBeNil()
		expect(setup.world:said("abandoned " .. DUEL.Id)).toBe(false)
	end)

	it("pays no forfeit to the one left standing once the server is closing", function()
		-- The server's own bind has run, ProfileStore's has not released anything yet: a departure then ends its
		-- session at once, and the duel ends without a result however long the other one stays.
		local setup, a, b = duel()
		setup.world:close()
		setup.world:leave(a)
		expect(writtenDuel(setup.world, a)).toBeNil()
		setup.world:advance(GRACE + 1)
		expect(setup.match.isInMatch(b)).toBe(false)
		expect(setup.data.get(b).Rank.Modes[DUEL.Id]).toBeNil()
	end)

	it("debits nobody whose session ends in the same frame the rest of the match walked out", function()
		-- The session of the first to go ends on the frame the last one's departure is seen, before the tick that
		-- ends the match: the match is empty all the same. Quarter-second frames keep the clock exact.
		local setup, a, b = duel()
		setup.world:leave(a)
		setup.world.engine:advance(GRACE - 0.25, 0.25)
		setup.world:leave(b)
		setup.world.engine:advance(0.25, 0.25)
		expect(writtenDuel(setup.world, a)).toBeNil()
		setup.world:advance(GRACE + 1)
		expect(writtenDuel(setup.world, b)).toBeNil()
	end)

	it("debits nobody and pays nobody when a migration takes the whole match out, a tick apart", function()
		-- Restart servers for updates: the players are teleported out, and the server only closes once empty.
		local setup, a, b = duel()
		setup.world:leave(a)
		setup.world:advance(0.3)
		setup.world:leave(b)
		setup.world:advance(GRACE + 1)
		expect(writtenDuel(setup.world, a)).toBeNil()
		expect(writtenDuel(setup.world, b)).toBeNil()
	end)

	it("still debits a player who walks out on an opponent who stays", function()
		local setup, a, b = duel()
		fought(setup, a, b)
		setup.world:leave(a)
		-- The forfeit waits for the grace, like the debit: nothing is decided before it runs out.
		setup.world:advance(GRACE / 2)
		expect(setup.match.getMatch(b).Phase).toBe("Playing")
		expect(setup.world.store.written[key(a)]).toBeNil()
		setup.world:advance(GRACE)
		local lost = writtenDuel(setup.world, a)
		expect(lost.Losses).toBe(1)
		expect(lost.Rating < RankingConfig.InitialRating).toBe(true)
		expect(setup.world:said("Ada abandoned " .. DUEL.Id)).toBe(true)
		expect(setup.match.getMatch(b).Phase).toBe("Result")
		local won = setup.data.get(b).Rank.Modes[DUEL.Id]
		expect(won.Wins).toBe(1)
	end)

	it("never debits a player who leaves a series they have already won (D-34)", function()
		local setup, a, b = duel()
		knockOut(setup, b)
		expect(setup.match.getMatch(a).Phase).toBe("RoundOver")
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		expect(setup.match.getMatch(a).Phase).toBe("Playing")
		knockOut(setup, b)
		expect(setup.match.getMatch(a).Scores[1]).toBe(DUEL.RoundsToWin)
		setup.world:leave(a)
		setup.world:advance(GRACE + 1)
		expect(writtenDuel(setup.world, a)).toBeNil()
	end)

	it("settles a player who comes back to the same server before the grace ran out", function()
		local setup, a, _b = duel()
		setup.world:leave(a)
		setup.world:advance(GRACE / 4)
		local again = setup.world:join(a.UserId, a.Name)
		expect(setup.data.get(again)).never.toBeNil()
		expect(writtenDuel(setup.world, a).Losses).toBe(1)
		expect(setup.match.isInMatch(again)).toBe(false)
	end)
end)

describe("another server takes the profile mid-duel (R4)", function()
	it("writes the forfeit into the final save of the session, before the player is removed", function()
		local setup, a, b = duel()
		fought(setup, a, b)
		setup.world.store:external(key(a))
		local lost = writtenDuel(setup.world, a)
		expect(lost).never.toBeNil()
		expect(lost.Losses).toBe(1)
		expect(kicked(setup.world, a)).toBe(ELSEWHERE_FR)
		setup.world:leave(a)
		setup.world:advance(GRACE + 1)
		-- Debited once, and the one who stayed takes the match.
		expect(writtenDuel(setup.world, a).Losses).toBe(1)
		expect(setup.data.get(b).Rank.Modes[DUEL.Id].Wins).toBe(1)
	end)

	it("writes it too when the other server takes the profile after the player left", function()
		local setup, a, _b = duel()
		setup.world:leave(a)
		setup.world:advance(GRACE / 4)
		setup.world.store:external(key(a))
		expect(writtenDuel(setup.world, a).Losses).toBe(1)
	end)
end)

describe("the message a session end shows (R15)", function()
	it("says nothing about another server when the shutdown releases a player still here", function()
		local setup = Server.services()
		local a = setup.world:join(201, "Cyd")
		setup.world:close()
		setup.world.store:shutdown()
		expect(kicked(setup.world, a)).toBeNil()
		expect(setup.data.get(a)).toBeNil()
	end)

	it("says nothing either when ProfileStore closes before the server's own bind ran", function()
		local setup = Server.services()
		local a = setup.world:join(202, "Dov")
		setup.world.store:shutdown()
		expect(kicked(setup.world, a)).toBeNil()
	end)

	it("says nothing during a shutdown, even of a session another server takes meanwhile", function()
		-- Roblox's own shutdown message is the one the player reads; a second one would only cover it.
		local setup = Server.services()
		local a = setup.world:join(206, "Hal")
		setup.world:close()
		setup.world.store:external(key(a))
		expect(kicked(setup.world, a)).toBeNil()
	end)

	it("still tells a player whose session another server took, in their language", function()
		local setup = Server.services()
		local a = setup.world:join(203, "Eli")
		local b = setup.world:join(204, "Fay")
		setup.world.store:external(key(a))
		setup.world.store:steal(key(b))
		expect(kicked(setup.world, a)).toBe(ELSEWHERE_FR)
		expect(kicked(setup.world, b)).toBe(ELSEWHERE_FR)
	end)

	it("never kicks a player who left: their session ends after them, without a word", function()
		local setup = Server.services()
		local a = setup.world:join(205, "Gil")
		setup.world:leave(a)
		setup.world:advance(GRACE + 1)
		expect(kicked(setup.world, a)).toBeNil()
		expect(setup.world.store.written[key(a)]).never.toBeNil()
	end)
end)

describe("the pretend ProfileStore", function()
	-- Each of these is what tests/server.luau assumes of the vendored module. If ProfileStore is updated and one
	-- of them stops being true, the spec above is testing a store that no longer exists.
	local source = fs.readFile(VENDOR)
	local function bodyOf(header: string): string
		local start = string.find(source, header, 1, true)
		assert(start ~= nil, VENDOR .. " has no " .. header .. ": this gate would check nothing")
		local finish = string.find(source, "\nend\n", start :: number, true)
		return string.sub(source, start :: number, finish or #source)
	end

	it("fires OnLastSave, then OnSessionEnd, and writes only after both", function()
		local save = bodyOf("local function SaveProfileAsync(")
		local last = string.find(save, 'profile.OnLastSave:Fire(last_save_reason or "Manual")', 1, true)
		local ended = string.find(save, "profile.OnSessionEnd:Fire()", 1, true)
		local write = string.find(save, "UpdateAsync(", 1, true)
		expect(last).never.toBeNil()
		expect(ended).never.toBeNil()
		expect(write).never.toBeNil()
		expect((last :: number) < (ended :: number) and (ended :: number) < (write :: number)).toBe(true)
	end)

	it("ends a session for Manual, External and Shutdown, and a stolen one with no last save", function()
		expect(
			string.find(bodyOf("function Profile:EndSession("), 'SaveProfileAsync, self, true, nil, "Manual"', 1, true)
		).never.toBeNil()
		expect(string.find(source, 'SaveProfileAsync(profile, true, false, "External")', 1, true)).never.toBeNil()
		expect(string.find(source, 'SaveProfileAsync(profile, true, nil, "Shutdown")', 1, true)).never.toBeNil()
		-- A session this server no longer owns ends on its autosave without OnLastSave.
		local save = bodyOf("local function SaveProfileAsync(")
		local stolen = string.find(
			save,
			"if is_active == true then\n\t\t\t\t\tRemoveProfileFromAutoSave(profile)\n\t\t\t\t\tprofile.OnSessionEnd:Fire()",
			1,
			true
		)
		expect(stolen).never.toBeNil()
	end)

	it("refuses to open a key this server still holds", function()
		local start = bodyOf("function ProfileStore:StartSessionAsync(")
		expect(string.find(start, "is already loaded in this session", 1, true)).never.toBeNil()
	end)
end)
