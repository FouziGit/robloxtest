--!strict
-- Who may hurt whom, place by place (E16-S1, D-266). Pure data.
--
-- Every player stands in one zone at a time, the first of Order whose owner claims them (CombatService.claimZone):
-- a match holds its participants, the Erasure's fight the players it engaged, the Flyleaf and the Battleground their
-- members, and the hub everybody else. A hit from one player on another lands only when both stand in the same zone
-- and that zone lets players hurt each other there -- and then its owner judges the pair (opponents of the same live
-- match, two members of the Flyleaf out of their protection, any two members of the Battleground). Damage the server
-- authors (the boss, the Forgers, the arenas' kill planes) carries no player and is never a zone's business.

export type ZoneId = "Match" | "Boss" | "Flyleaf" | "Battleground" | "Hub"
-- "Never": no player hurts another here. "Owner": the zone's owner judges each pair (CombatService.claimZone).
export type Between = "Never" | "Owner"
export type Rule = {
	BetweenPlayers: Between,
	-- Whether a player of this zone may hurt a body no player owns: a training proof, the Erasure, a Forger.
	OnBodies: boolean,
	-- Whether CombatService pays a player kill here itself (its XP, ProgressionConfig.XP.PlayerKill), or leaves the pay
	-- to the zone's owner, which hears every kill through CombatService.Killed.
	CombatPaysKills: boolean,
}

local ZoneConfig = {}

-- The zone a player is in: the first of these whose owner holds them. The last one holds everybody.
ZoneConfig.Order = { "Match", "Boss", "Flyleaf", "Battleground", "Hub" } :: { ZoneId }
ZoneConfig.Fallback = "Hub" :: ZoneId

ZoneConfig.Rules = {
	-- Opponents of the same live match, and nothing else: no NPC in the middle of a duel. A kill is the match's, paid
	-- with its result under its share, its repeated pair's quarter and the day's Folio cap (MatchService).
	Match = { BetweenPlayers = "Owner", OnBodies = false, CombatPaysKills = false },
	-- Never between players, event or practice; the Erasure takes every hit.
	Boss = { BetweenPlayers = "Never", OnBodies = true, CombatPaysKills = true },
	-- The free-for-all page (E16-S2): members against members, paid by the page itself under its own cap.
	Flyleaf = { BetweenPlayers = "Owner", OnBodies = false, CombatPaysKills = false },
	-- The Battleground (D-282): every member against every other, and the Forgers against all of them; the page pays
	-- its own player kills, under its pair rule and the Forgers' daily cap.
	Battleground = { BetweenPlayers = "Owner", OnBodies = true, CombatPaysKills = false },
	-- Nobody hurts anybody; the training proofs and the Forgers are open to all.
	Hub = { BetweenPlayers = "Never", OnBodies = true, CombatPaysKills = true },
} :: { [ZoneId]: Rule }

return ZoneConfig
