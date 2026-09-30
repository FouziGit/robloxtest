--!strict
-- The quick duel for newcomers, ranked at level 10 (E10-S7). The gate itself is RankedGate's
-- (tests/RankedGate.spec.luau) and the newcomer's window MatchmakingCore's (tests/Matchmaking.spec.luau). Here the
-- real DataService, RankingService and MatchService play it on a pretend server: a match with a newcomer in it is
-- played and counted, and never writes a rating, not even by walking out; the announcement carries each fighter's
-- level and rank. Then the Play screen says why and how far, and the announcement names the opponents.
local Engine = require("./engine")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local RankTiers = require("../src/shared/Pure/RankTiers")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Server = require("./server")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
local RULES = MatchConfig.Newcomer

-- Makes `player` somebody ranked asks nothing more of, at `rating`.
local function veteran(setup: Server.Services, player: any, rating: number)
	local data = setup.data.get(player)
	data.Stats.MatchesPlayed = RULES.MinMatches
	data.Progression.Level = RULES.MinLevel + 2
	data.Rank.Modes[DUEL.Id] = { Rating = rating, Matches = 30, Wins = 15, Losses = 15, PeakRating = rating }
end

-- Plays the duel out: `winner` takes both rounds.
local function playOut(setup: Server.Services, winner: any, loser: any)
	for _ = 1, DUEL.RoundsToWin do
		setup.world:advance(DUEL.CountdownSeconds + 0.5)
		expect(setup.match.getMatch(winner).Phase).toBe("Playing")
		loser.Character:FindFirstChildOfClass("Humanoid").Health = 0
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.5)
	end
	expect(setup.match.getMatch(winner).Phase).toBe("Result")
	setup.world:advance(DUEL.ResultSeconds + 1)
	expect(setup.match.isInMatch(winner)).toBe(false)
end

local function lastOutcome(setup: Server.Services, player: any): any
	local found = nil
	for _, event in ipairs(setup.fired) do
		if event.Name == "MatchEnded" and event.Player == player then
			found = event.Payload
		end
	end
	return found
end

local function snapshotOf(setup: Server.Services, player: any): any
	local GameModes = setup.world.require("src/server/GameModes")
	return GameModes.snapshot(setup.match.getMatch(player), 0)
end

describe("who is a newcomer", function()
	it("is RankingService's answer, from the profile, and a player it cannot read is one", function()
		local setup = Server.services()
		local a = setup.world:join(101, "Ada")
		expect(setup.ranking.isNewcomer(a)).toBe(true)
		veteran(setup, a, 1000)
		expect(setup.ranking.isNewcomer(a)).toBe(false)
		setup.data.get(a).Stats.MatchesPlayed = RULES.MinMatches - 1
		expect(setup.ranking.isNewcomer(a)).toBe(true)
		local stranger = { Name = "Nobody", UserId = 999 }
		expect(setup.ranking.isNewcomer(stranger)).toBe(true)
	end)

	it("lets Studio's test players play ranked only when StudioConfig says so, and only in Studio", function()
		local setup = Server.services()
		local a = setup.world:join(101, "Ada")
		local StudioConfig = setup.world.require("src/server/Config/StudioConfig")
		expect(StudioConfig.RankedFromTheStart).toBe(false)
		StudioConfig.RankedFromTheStart = true
		-- A live server never reads it.
		expect(setup.ranking.isNewcomer(a)).toBe(true)
		local runService = setup.world.engine.game:GetService("RunService")
		runService.IsStudio = function(): boolean
			return true
		end
		expect(setup.ranking.isNewcomer(a)).toBe(false)
		StudioConfig.RankedFromTheStart = false
		expect(setup.ranking.isNewcomer(a)).toBe(true)
	end)
end)

describe("a quick duel on the server", function()
	it("plays two newcomers unranked, counts the match, and writes no rating anywhere", function()
		local setup = Server.services()
		local a = setup.world:join(101, "Ada")
		local b = setup.world:join(102, "Bea")
		expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBe(nil)
		local snapshot = snapshotOf(setup, a)
		expect(snapshot.Ranked).toBe(false)
		expect(snapshot.Teams[2][1].Level).toBe(1)
		expect(snapshot.Teams[2][1].RankKey).toBe("")
		playOut(setup, a, b)
		for _, player in ipairs({ a, b }) do
			expect(setup.data.get(player).Rank.Modes[DUEL.Id]).toBeNil()
			expect(setup.data.get(player).Stats.MatchesPlayed).toBe(1)
			local outcome = lastOutcome(setup, player)
			expect(outcome ~= nil).toBe(true)
			-- No rank on the Result: it says nothing of a rating that could not move.
			expect(outcome.RankKeyAfter).toBe("")
			expect(outcome.RatingAfter).toBe(outcome.RatingBefore)
		end
		expect(setup.world:said("(2 players, unranked)")).toBe(true)
	end)

	it("keeps a veteran's rating where it was when a newcomer is in the match", function()
		local setup = Server.services()
		local old = setup.world:join(101, "Ada")
		local novice = setup.world:join(102, "Bea")
		veteran(setup, old, 1300)
		setup.data.get(novice).Progression.Level = 25
		setup.data.get(novice).Stats.MatchesPlayed = RULES.MinMatches - 1
		setup.match.start(DUEL.Id, { { old.UserId }, { novice.UserId } })
		local snapshot = snapshotOf(setup, novice)
		expect(snapshot.Ranked).toBe(false)
		-- The announcement: the veteran's rank, and the newcomer's level with no rank yet.
		expect(snapshot.Teams[1][1].RankKey).toBe(RankTiers.tierFor(1300, RankingConfig.Tiers).NameKey)
		expect(snapshot.Teams[1][1].Level).toBe(RULES.MinLevel + 2)
		expect(snapshot.Teams[2][1].RankKey).toBe("")
		expect(snapshot.Teams[2][1].Level).toBe(25)
		playOut(setup, novice, old)
		expect(setup.data.get(old).Rank.Modes[DUEL.Id].Rating).toBe(1300)
		expect(setup.data.get(old).Rank.Modes[DUEL.Id].Matches).toBe(30)
		expect(setup.data.get(novice).Rank.Modes[DUEL.Id]).toBeNil()
		expect(lastOutcome(setup, old).RankKeyAfter).toBe("")
	end)

	it("costs nothing to walk out of", function()
		local setup = Server.services()
		local a = setup.world:join(101, "Ada")
		local b = setup.world:join(102, "Bea")
		veteran(setup, b, 1200)
		setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })
		setup.world:advance(DUEL.CountdownSeconds + 0.5)
		setup.world:leave(a)
		setup.world:advance(10)
		expect(setup.world:said("abandoned " .. DUEL.Id)).toBe(false)
		local saved = setup.world.store.written["Player_101"]
		expect(saved ~= nil).toBe(true)
		expect(saved.Rank.Modes[DUEL.Id]).toBeNil()
		expect(setup.data.get(b).Rank.Modes[DUEL.Id].Rating).toBe(1200)
	end)

	it("plays two veterans ranked, as it always did, and moves their ratings", function()
		local setup = Server.services()
		local a = setup.world:join(101, "Ada")
		local b = setup.world:join(102, "Bea")
		veteran(setup, a, 1200)
		veteran(setup, b, 1200)
		setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })
		expect(snapshotOf(setup, a).Ranked).toBe(true)
		playOut(setup, a, b)
		expect(setup.data.get(a).Rank.Modes[DUEL.Id].Rating > 1200).toBe(true)
		expect(setup.data.get(b).Rank.Modes[DUEL.Id].Rating < 1200).toBe(true)
		expect(lastOutcome(setup, a).RankKeyAfter ~= "").toBe(true)
	end)
end)

----------------------------------------------------------------
-- The Play screen and the announcement
----------------------------------------------------------------

local function key(text: string): string
	return text
end

-- The Play screen for a player with `played` matches at `level`; its words are their keys.
local function playScreen(played: number, level: number): (any, any, any, { { Key: string, Params: any } })
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local data: any = { Stats = { MatchesPlayed = played }, Progression = { Level = level } }
	local changed = Engine.signal()
	local signal = Engine.signal
	local said: { { Key: string, Params: any } } = {}
	local PlayScreen = world.require("src/ui/screens/PlayScreen")
	local screen = PlayScreen.new({
		Localize = {
			t = function(text: string, params: any): string
				table.insert(said, { Key = text, Params = params })
				return key(text)
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = changed,
		},
		RemoteClient = { fire = function() end },
		InputController = { captureNext = function() end },
		SoundController = { play = function() end },
		MatchController = {
			getQueue = function(): any
				return { Queued = false, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 2 }
			end,
			joinQueue = function() end,
			leaveQueue = function() end,
			QueueChanged = signal(),
		},
		HudController = { Notified = signal() },
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	} :: any)
	screen:Open()
	return screen, data, changed, said
end

local function gates(screen: any): { any }
	local found = {}
	for _, descendant in ipairs(screen.Instance:GetDescendants()) do
		if descendant.Name == "Gate" then
			table.insert(found, descendant)
		end
	end
	return found
end

describe("the Play screen of a newcomer", function()
	it("says on every ranked card why the duel is quick and how far ranked is, and nothing once ranked", function()
		local screen, data, changed, said = playScreen(2, 7)
		local lines = gates(screen)
		expect(#lines).toBe(#MatchConfig.ModeOrder)
		for _, line in ipairs(lines) do
			expect(line.Visible).toBe(true)
			expect(line.Text).toBe("queue.gate.both")
		end
		-- How far: the level and the matches ranked asks for, against the player's own.
		local asked = nil
		for _, call in ipairs(said) do
			if call.Key == "queue.gate.both" then
				asked = call.Params
			end
		end
		expect(asked).toEqual({ level = RULES.MinLevel, current = 7, count = RULES.MinMatches, played = 2 })
		data.Progression.Level = RULES.MinLevel
		changed:Fire("Progression")
		expect(lines[1].Text).toBe("queue.gate.matches")
		data.Stats.MatchesPlayed = RULES.MinMatches
		data.Progression.Level = 3
		changed:Fire("Stats")
		expect(lines[1].Text).toBe("queue.gate.level")
		data.Progression.Level = RULES.MinLevel
		changed:Fire("Progression")
		for _, line in ipairs(lines) do
			expect(line.Visible).toBe(false)
		end
	end)
end)

describe("the match's announcement", function()
	it("names each opponent with their level and rank on a plate that leaves when the fight is called", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Banner = world.require("src/ui/components/Banner")
		local banner = Banner.new({
			Localize = {
				t = function(text: string): string
					return text
				end,
			},
			Parent = world.playerGui,
		})
		banner:ShowVersus({ "match.quickDuel", "Bea · 3 · unranked" })
		world:advance(0.5)
		local plate = world.playerGui:FindFirstChild("Versus", true)
		expect(plate ~= nil).toBe(true)
		expect(plate:FindFirstChild("Words").Text).toBe("match.quickDuel\nBea · 3 · unranked")
		banner:ShowVersus(nil)
		world:advance(1)
		expect(world.playerGui:FindFirstChild("Versus", true)).toBeNil()
		banner:ShowVersus({ "Bea" })
		world:advance(0.5)
		banner:Clear()
		world:advance(1)
		expect(world.playerGui:FindFirstChild("Versus", true)).toBeNil()
	end)

	it("is shown by the HUD from the first snapshot of a match, and withdrawn when it fights", function()
		local Hud = require("./hud")
		local fixture = Hud.build()
		local snapshot = Hud.match("Duel1v1", 1)
		snapshot.Phase = "Countdown"
		snapshot.SecondsLeft = 5
		snapshot.Ranked = false
		snapshot.Teams[2][1].Level = 4
		snapshot.Teams[2][1].RankKey = ""
		fixture.match(snapshot)
		fixture.world:advance(0.5)
		local plate = fixture.world.playerGui:FindFirstChild("Versus", true)
		expect(plate ~= nil).toBe(true)
		expect(plate:FindFirstChild("Words").Text).toBe("match.quickDuel\nmatch.versus")
		local fight = table.clone(snapshot)
		fight.Phase = "Playing"
		fixture.match(fight)
		fixture.world:advance(1)
		expect(fixture.world.playerGui:FindFirstChild("Versus", true)).toBeNil()
	end)
end)

describe("the client's copy of a match", function()
	it("keeps each fighter's level and rank and whether the match is ranked, and never trusts their shape", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local handlers: { [string]: (any) -> () } = {}
		local MatchController = world.require("src/client/Controllers/MatchController")
		MatchController.Init({
			RemoteClient = {
				on = function(name: string, handler: (any) -> ())
					handlers[name] = handler
				end,
				fire = function() end,
			},
			SoundController = { play = function() end, wantMusic = function() end },
		})
		MatchController.Start()
		local function payload(ranked: any, level: any, rankKey: any): any
			return {
				MatchId = "m",
				ModeId = "Duel1v1",
				Phase = "Countdown",
				SecondsLeft = 5,
				Round = 1,
				RoundsToWin = 2,
				Scores = { 0, 0 },
				Teams = {
					{ { UserId = 1, Name = "Ada", Team = 1, Alive = true, Health = 100, MaxHealth = 100 } },
					{
						{
							UserId = 2,
							Name = "Bea",
							Team = 2,
							Alive = true,
							Health = 100,
							MaxHealth = 100,
							Level = level,
							RankKey = rankKey,
						},
					},
				},
				LocalTeam = 1,
				Ranked = ranked,
			}
		end
		handlers.MatchChanged(payload(true, 12, "rank.ink"))
		local snapshot = MatchController.getMatch()
		expect(snapshot.Ranked).toBe(true)
		expect(snapshot.Teams[2][1].Level).toBe(12)
		expect(snapshot.Teams[2][1].RankKey).toBe("rank.ink")
		handlers.MatchChanged(payload("yes", "twelve", 7))
		snapshot = MatchController.getMatch()
		expect(snapshot.Ranked).toBe(false)
		expect(snapshot.Teams[2][1].Level).toBe(1)
		expect(snapshot.Teams[2][1].RankKey).toBe("")
	end)
end)
