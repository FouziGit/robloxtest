--!strict
-- The rules of the practice duel against a Forger (E10-S6, SparService): when it is offered, when a round is over
-- and to whom, when the matchmaker may take the player out of it, and what it pays. Pure module: no require, no
-- Roblox global; every number comes from MatchConfig.Spar and ProgressionConfig through the caller. Only the
-- server needs it, so it lives in src/server/Pure, which no client receives.

-- Where the player stands when the offer is looked at: the queue they wait in (nil when none), for how long, how
-- many others wait in it, and what else holds them.
export type OfferInput = {
	QueuedFor: string?,
	WaitedSeconds: number,
	Others: number,
	Sparring: boolean,
	InMatch: boolean,
	EventLive: boolean,
	Engaged: boolean,
}
export type OfferRules = { QueueModeId: string, OfferAfterSeconds: number }
-- One side of a round: standing or not, and its health.
export type Side = { Alive: boolean, Health: number, MaxHealth: number }
export type Verdict = "Player" | "Forger" | "Draw"
export type Outcome = "Win" | "Loss" | "Draw"

local SparRules = {}

-- Whether the spar is offered: after OfferAfterSeconds in its queue with nobody else waiting there, and nothing
-- else holding the player -- a spar already, a match, the Erasure's event (which takes everyone not in a match).
function SparRules.offered(input: OfferInput, rules: OfferRules): boolean
	return input.QueuedFor == rules.QueueModeId
		and input.WaitedSeconds >= rules.OfferAfterSeconds
		and input.Others <= 0
		and not input.Sparring
		and not input.InMatch
		and not input.EventLive
		and not input.Engaged
end

-- Whether the matchmaker may pair a sparring player now: at any break of the spar -- its count, the pause after a
-- round, its result -- never while a round is played.
function SparRules.pairable(phase: string): boolean
	return phase ~= "Playing"
end

local function share(side: Side): number
	if side.MaxHealth <= 0 then
		return 0
	end
	return math.max(side.Health, 0) / side.MaxHealth
end

-- Who takes the round, or nil while it goes on. A side down loses it, both down is a draw; when the round's time
-- is up (`timedOut`) with both standing, the bigger share of health left takes it, and an exact tie is a draw.
-- Shares, not points: the Forger's health is not the player's.
function SparRules.roundVerdict(player: Side, forger: Side, timedOut: boolean): Verdict?
	if not player.Alive and not forger.Alive then
		return "Draw"
	end
	if not forger.Alive then
		return "Player"
	end
	if not player.Alive then
		return "Forger"
	end
	if not timedOut then
		return nil
	end
	local mine, theirs = share(player), share(forger)
	if mine > theirs then
		return "Player"
	elseif theirs > mine then
		return "Forger"
	end
	return "Draw"
end

-- The player's outcome of a finished series, from its rounds (index 1 the player's, 2 the Forger's).
function SparRules.outcome(scores: { number }): Outcome
	local mine, theirs = scores[1] or 0, scores[2] or 0
	if mine > theirs then
		return "Win"
	elseif theirs > mine then
		return "Loss"
	end
	return "Draw"
end

-- `amount` at `factor`, rounded to the nearest whole point; nothing for a factor of zero or less.
function SparRules.scaled(amount: number, factor: number): number
	if factor <= 0 then
		return 0
	end
	return math.floor(amount * factor + 0.5)
end

-- The paid spars left today, `used` being today's count (DailyCap).
function SparRules.paidLeft(used: number, perDay: number): number
	return math.max(perDay - math.max(used, 0), 0)
end

return SparRules
