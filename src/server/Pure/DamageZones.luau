--!strict
-- DamageZones: the rule of ZoneConfig, as CombatService applies it to every hit a player deals (E16-S1, D-XXX).
-- Pure module: no require, no Roblox global, tested under Lune (tests/DamageZones.spec.luau).

export type Between = "Never" | "Owner"
export type Rule = { BetweenPlayers: Between, OnBodies: boolean, CombatPaysKills: boolean }
-- "Allow" and "Refuse" are final; "Owner" hands the pair to the owner of the zone both players stand in.
export type Verdict = "Allow" | "Refuse" | "Owner"

local DamageZones = {}

-- The zone `who` is in: the first of `order` that `holds` them, or `fallback` when none does. The fallback holds
-- everybody, so it is never asked.
function DamageZones.zoneOf<T>(
	order: { string },
	fallback: string,
	holds: (zone: string, who: T) -> boolean,
	who: T
): string
	for _, zone in ipairs(order) do
		if zone ~= fallback and holds(zone, who) then
			return zone
		end
	end
	return fallback
end

-- A hit from a player standing in `sourceZone` on a body: another player's, standing in `targetZone`, or one no
-- player owns (`targetZone` nil). Players in two different zones never hurt each other, whatever either zone
-- allows; a zone nobody wrote a rule for allows nothing.
function DamageZones.judge(rules: { [string]: Rule }, sourceZone: string, targetZone: string?): Verdict
	local rule = rules[sourceZone]
	if rule == nil then
		return "Refuse"
	end
	if targetZone == nil then
		return if rule.OnBodies then "Allow" else "Refuse"
	end
	if targetZone ~= sourceZone or rule.BetweenPlayers ~= "Owner" then
		return "Refuse"
	end
	return "Owner"
end

-- Whether CombatService pays a kill made from `zone` itself, rather than leaving it to the zone's owner.
function DamageZones.combatPays(rules: { [string]: Rule }, zone: string): boolean
	local rule = rules[zone]
	return rule ~= nil and rule.CombatPaysKills
end

return DamageZones
