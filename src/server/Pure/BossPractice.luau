--!strict
-- The rules of a practice fight against the Erasure, opened on demand from the hub's gate (D-132), and of
-- joining any fight in progress through that gate. Pure module: no require, no Roblox global; every number
-- comes from WorldBossConfig through the caller, so each rule reads and is tested on its own.
--
-- A practice uses the one encounter slot the scheduled event uses. What keeps the two apart lives here: a
-- practice is refused when the event is due before it would end and could actually run, and a player who
-- opens one and walks straight out cannot keep reopening it.

export type StartInput = {
	Now: number,
	-- When the scheduled event is next announced (WorldBossService's nextEventAt).
	NextEventAt: number,
	-- Players the event would take right now, and the fewest it runs with.
	Eligible: number,
	MinPlayers: number,
	-- How long a practice holds the slot: its fight and its cleanup.
	FightSeconds: number,
	CleanupSeconds: number,
	-- When this player may open a practice again.
	CooldownUntil: number,
}

export type StartVerdict = "Start" | "Cooldown" | "EventSoon"
export type EntryVerdict = "Join" | "Rejoin" | "Announced" | "Closing" | "NoReentry"

local BossPractice = {}

-- Whether a player may open a practice now, and the seconds the refusal's toast names (0 for Start). The
-- player's own cooldown first; then the event: a practice that would still hold the slot when the event is
-- announced would push the event back, which is only allowed where the event could not have run anyway.
function BossPractice.startVerdict(input: StartInput): (StartVerdict, number)
	if input.Now < input.CooldownUntil then
		return "Cooldown", math.ceil(input.CooldownUntil - input.Now)
	end
	local holdsUntil = input.Now + input.FightSeconds + input.CleanupSeconds
	if input.NextEventAt < holdsUntil and input.Eligible >= input.MinPlayers then
		return "EventSoon", math.max(math.ceil(input.NextEventAt - input.Now), 0)
	end
	return "Start", 0
end

-- The phase the gate reads for a fight: the fight's own (Types.BossPhaseSnapshot), except that a boss already
-- brought down is Defeated. The killing blow lands between two of the fight's ticks and the phase still reads
-- Fighting until the next one records it; a player let in during those frames would be placed in a fight that
-- is over. `bossHealth` is the live boss's, nil while no boss stands in the arena (an announce).
function BossPractice.gatePhase(phase: string, bossHealth: number?): string
	if phase == "Fighting" and bossHealth ~= nil and bossHealth <= 0 then
		return "Defeated"
	end
	return phase
end

-- What the gate does for a player while a fight holds the slot. `phase` is the fight's (Types.BossPhaseSnapshot),
-- `isParticipant` whether the player already took part in it, `reentries` how many times they already walked
-- back in. The scheduled event lets a participant back in as often as they like; a practice MaxReentries times.
function BossPractice.entryVerdict(
	phase: string,
	isParticipant: boolean,
	reentries: number,
	maxReentries: number,
	practice: boolean
): EntryVerdict
	if phase == "Announced" then
		return "Announced"
	end
	if phase ~= "Fighting" then
		return "Closing"
	end
	if not isParticipant then
		return "Join"
	end
	if practice and reentries >= maxReentries then
		return "NoReentry"
	end
	return "Rejoin"
end

-- The health a practice gains for one more player: `perJoiner`, but never past `cap`, and never negative.
function BossPractice.grownHealth(maxHealth: number, perJoiner: number, cap: number): number
	return math.max(math.min(perJoiner, cap - maxHealth), 0)
end

-- The health a practice gains on the first hit of a player who joined it in progress, `healthAfterHit` being
-- the boss's once that hit has landed. The gate only books the growth; the first hit pays it, so a player who
-- walks in and straight back out, or stands idle, never raises the health the others must remove. A hit that
-- brought the boss down ends the fight instead: a dead Erasure never grows back.
function BossPractice.growthOnHit(healthAfterHit: number, maxHealth: number, perJoiner: number, cap: number): number
	if healthAfterHit <= 0 then
		return 0
	end
	return BossPractice.grownHealth(maxHealth, perJoiner, cap)
end

-- A reward amount scaled by a practice's factor, rounded to the nearest whole point; nothing for a factor of
-- zero or less.
function BossPractice.scaled(amount: number, factor: number): number
	if factor <= 0 then
		return 0
	end
	return math.floor(amount * factor + 0.5)
end

-- Whether a practice's pay counts against the day's paid practices and the server's gap: only a pay of at least
-- `minFolios` Folios (before multipliers) does. Anything less is paid its XP alone, charged nothing, so a late
-- joiner whose share rounds to no Folio keeps the day's paid practices for a fight of their own.
function BossPractice.charged(folios: number, minFolios: number): boolean
	return folios >= minFolios
end

-- Whether a practice nobody stands in is kept open. It is, while anyone is present; while nobody is but a
-- participant may still be on the way back (dead, or between gates), for `grace` seconds after it emptied.
function BossPractice.keepAlive(
	anyPresent: boolean,
	anyReturning: boolean,
	emptySince: number?,
	now: number,
	grace: number
): boolean
	if anyPresent then
		return true
	end
	if not anyReturning then
		return false
	end
	return emptySince == nil or now - emptySince < grace
end

-- The seconds the player who opened a practice waits before opening another, once it has ended empty:
-- `penalty` if they walked out of it through a gate within `early` seconds of opening it, `base` otherwise. Only
-- the walk-out is what holds the gate by opening and leaving; a ranked match that took them, a death, or a
-- departure from the server is not a choice to leave it, and costs no more than any other practice.
function BossPractice.startPenalty(
	walkedOut: boolean,
	startedAt: number,
	now: number,
	early: number,
	penalty: number,
	base: number
): number
	if walkedOut and now - startedAt < early then
		return penalty
	end
	return base
end

return BossPractice
