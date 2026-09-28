--!strict
-- The centre splashes a match calls for (D-147): found, each digit of the count, the fight, a round won or
-- lost -- from the snapshots the server pushes, compared with the one before.
local Harness = require("./harness")
local MatchSplash = require("../src/shared/Pure/MatchSplash")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function snapshot(phase: string, seconds: number, ours: number, theirs: number, id: string?): MatchSplash.Snapshot
	return { MatchId = id or "m1", Phase = phase, SecondsLeft = seconds, Scores = { ours, theirs }, LocalTeam = 1 }
end

local function kinds(splashes: { MatchSplash.Splash }): { string }
	local out: { string } = {}
	for _, splash in ipairs(splashes) do
		table.insert(out, splash.Kind)
	end
	return out
end

describe("the match's splashes", function()
	it("say a match was found on its first snapshot, and on the first of the next match", function()
		expect(kinds(MatchSplash.between(nil, snapshot("Countdown", 3, 0, 0)))).toEqual({ "MatchFound", "Countdown" })
		local last = snapshot("RoundOver", 2, 2, 0, "m1")
		expect(kinds(MatchSplash.between(last, snapshot("Countdown", 3, 0, 0, "m2")))).toEqual({
			"MatchFound",
			"Countdown",
		})
		expect(MatchSplash.between(snapshot("Playing", 40, 0, 0), nil)).toEqual({})
	end)

	it("count each whole second once, and never zero", function()
		local three = snapshot("Countdown", 2.6, 0, 0)
		local first = MatchSplash.between(snapshot("Countdown", 3.4, 0, 0), three)
		expect(first).toEqual({ { Kind = "Countdown", Digit = 3 } })
		-- The same second pushed again says nothing.
		expect(MatchSplash.between(three, snapshot("Countdown", 2.1, 0, 0))).toEqual({})
		expect(MatchSplash.between(three, snapshot("Countdown", 1.9, 0, 0))).toEqual({
			{ Kind = "Countdown", Digit = 2 },
		})
		expect(MatchSplash.between(snapshot("Countdown", 0.4, 0, 0), snapshot("Countdown", 0, 0, 0))).toEqual({})
	end)

	it("call the fight when the count ends, and only then", function()
		expect(kinds(MatchSplash.between(snapshot("Countdown", 0.2, 0, 0), snapshot("Playing", 60, 0, 0)))).toEqual({
			"Fight",
		})
		expect(MatchSplash.between(snapshot("Playing", 60, 0, 0), snapshot("Playing", 59, 0, 0))).toEqual({})
		-- A player who joins a round already on has no count to end.
		expect(kinds(MatchSplash.between(nil, snapshot("Playing", 40, 0, 0)))).toEqual({ "MatchFound" })
	end)

	it("say a round won or lost by whose score moved, once, and nothing for a round nobody took", function()
		local playing = snapshot("Playing", 5, 1, 1)
		expect(kinds(MatchSplash.between(playing, snapshot("RoundOver", 3, 2, 1)))).toEqual({ "RoundWon" })
		expect(kinds(MatchSplash.between(playing, snapshot("RoundOver", 3, 1, 2)))).toEqual({ "RoundLost" })
		expect(MatchSplash.between(playing, snapshot("RoundOver", 3, 1, 1))).toEqual({})
		expect(MatchSplash.between(snapshot("RoundOver", 3, 2, 1), snapshot("RoundOver", 2, 2, 1))).toEqual({})
		-- The phase opened on the old score and the next snapshot counted the round: it is said then, once.
		local opened = snapshot("RoundOver", 3, 1, 1)
		expect(MatchSplash.between(playing, opened)).toEqual({})
		expect(kinds(MatchSplash.between(opened, snapshot("RoundOver", 2.8, 2, 1)))).toEqual({ "RoundWon" })
		-- Their score is the best of the other teams'.
		local three: MatchSplash.Snapshot =
			{ MatchId = "m1", Phase = "Playing", SecondsLeft = 5, Scores = { 0, 0, 0 }, LocalTeam = 2 }
		local over: MatchSplash.Snapshot =
			{ MatchId = "m1", Phase = "RoundOver", SecondsLeft = 3, Scores = { 1, 0, 0 }, LocalTeam = 2 }
		expect(kinds(MatchSplash.between(three, over))).toEqual({ "RoundLost" })
	end)
end)
