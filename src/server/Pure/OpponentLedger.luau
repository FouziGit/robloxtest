--!strict
-- How often a player met each opponent in ranked play today (E4-S3, D-XXXfarm). Pure module: no require, no
-- Roblox global.
--
-- The count lives in the profile (Rank.Opponents), beside the UTC day it belongs to: a count kept in a server's
-- memory is escaped by switching server. A ledger of any other day counts nothing. Opponents are keyed by their
-- user id as a string, the only map key a DataStore keeps.

export type Ledger = { Day: number, Counts: { [string]: number } }

local OpponentLedger = {}

-- Ranked matches `ledger` holds against `opponentId` on `today`.
function OpponentLedger.count(ledger: Ledger, today: number, opponentId: number): number
	if ledger.Day ~= today then
		return 0
	end
	return math.max(ledger.Counts[tostring(opponentId)] or 0, 0)
end

-- The ledger after one more ranked match against each of `opponentIds` on `today`. A ledger of another day starts
-- over: yesterday's opponents are forgotten, not carried.
function OpponentLedger.record(ledger: Ledger, today: number, opponentIds: { number }): Ledger
	local counts: { [string]: number } = if ledger.Day == today then table.clone(ledger.Counts) else {}
	for _, opponentId in ipairs(opponentIds) do
		local key = tostring(opponentId)
		counts[key] = math.max(counts[key] or 0, 0) + 1
	end
	return { Day = today, Counts = counts }
end

-- Which meeting of the pair today a new match between `ownId` and `opponentId` is: one past the higher of the two
-- ledgers. Either side alone is enough, so the pair counts even when one of them never wrote their own (a fresh
-- account, a profile that left before the result). `theirs` is nil when the opponent's profile is not here.
function OpponentLedger.meeting(own: Ledger, theirs: Ledger?, today: number, ownId: number, opponentId: number): number
	local seen = OpponentLedger.count(own, today, opponentId)
	if theirs ~= nil then
		seen = math.max(seen, OpponentLedger.count(theirs, today, ownId))
	end
	return seen + 1
end

-- Whether a pair's `meeting`-th match of the day is past the `fullMatches` that move a rating and pay in full.
function OpponentLedger.isRepeat(meeting: number, fullMatches: number): boolean
	return meeting > fullMatches
end

return OpponentLedger
