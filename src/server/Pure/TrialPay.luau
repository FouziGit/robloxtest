--!strict
-- TrialPay: what a Trial proof of the hub pays the player who fells it (E10-S3). Pure module: no require, no
-- Roblox global, so EnemyService and scripts/pacing.luau run the very same rule and tests/Pacing.spec.luau
-- fails the moment it is lifted.
--
-- The Trials are where a player learns their hand, which makes them the safest thing in the game to farm: a
-- proof never dodges and never hits back. So they pay a day's worth and no more. Their Folios stop at
-- DailyFolioCap a day, their XP is whole for the first FullXpKills kills of the day and TailXpShare of it after,
-- and a kill pays nothing at all unless the player cast a glyph or dashed in the last ActiveWindowSeconds: a
-- macro that only swings at a proof is not practising anything. What a proof pays never reaches the pass
-- (ProgressionConfig.PassExcluded).
--
-- The day's counts live in the profile beside the day they belong to (Types.DailyData.TrialDay, TrialKills,
-- TrialFolios), never in a server's memory, and go through the same DailyCap.take the Forgers' Folios do. It
-- is handed in rather than required, as DataMigration is handed its legacy maps: this module may not require.

export type Rules = {
	DailyFolioCap: number,
	FullXpKills: number,
	TailXpShare: number,
	ActiveWindowSeconds: number,
}
-- What the profile holds: the day the two counts belong to, the kills paid in full XP, and the Folios paid.
export type Ledger = { Day: number, Kills: number, Folios: number }
-- DailyCap.take.
export type Take = (day: number, used: number, today: number, cap: number, want: number) -> (number, number)
-- One kill's pay before VIP and boosts, today's ledger after it, and whether this kill is the one that ended
-- the day's full pay: true on exactly one kill a day, the one the player is told about.
export type Pay = { Xp: number, Folios: number, Ledger: Ledger, Capped: boolean }

local TrialPay = {}

-- Whether the player's last glyph or dash, at `lastActiveAt` on the clock `now` reads, is recent enough for a
-- kill to pay. A player who has done neither since they arrived (nil) is not.
function TrialPay.active(lastActiveAt: number?, now: number, rules: Rules): boolean
	return lastActiveAt ~= nil and now >= lastActiveAt and now - lastActiveAt <= rules.ActiveWindowSeconds
end

-- Whether a kill on `ledger`, today, would still pay in full: Folios left under the cap and a full-XP kill
-- left. A ledger from another day is a fresh one.
local function paysInFull(ledger: Ledger, today: number, rules: Rules): boolean
	if ledger.Day ~= today then
		return true
	end
	return ledger.Folios < rules.DailyFolioCap and ledger.Kills < rules.FullXpKills
end

-- One kill of a proof worth `xp` and `folios`, on today's `ledger`. The caller has already checked `active`.
function TrialPay.kill(ledger: Ledger, today: number, rules: Rules, xp: number, folios: number, take: Take): Pay
	local paidFolios, foliosUsed = take(ledger.Day, ledger.Folios, today, rules.DailyFolioCap, folios)
	local fullKills, killsUsed = take(ledger.Day, ledger.Kills, today, rules.FullXpKills, 1)
	local paidXp = if fullKills >= 1 then xp else math.floor(xp * rules.TailXpShare)
	local after: Ledger = { Day = today, Kills = killsUsed, Folios = foliosUsed }
	return {
		Xp = paidXp,
		Folios = paidFolios,
		Ledger = after,
		Capped = paysInFull(ledger, today, rules) and not paysInFull(after, today, rules),
	}
end

return TrialPay
