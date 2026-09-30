--!strict
-- ExLibris: where a player stands on each plate of the Ex-libris, and which ones they have just earned
-- (ExLibrisConfig). Pure module: no require, no Roblox global, tested under Lune (tests/ExLibris.spec.luau).
-- HonoursService grants from it and the Lectern shows it, from the same profile.
--
--   facts     every measure a plate can read, from the profile's lifetime stats and drill grades
--   progress  how far a plate is, up to its target
--   due       whether a plate is met and was never granted: what HonoursService grants, each plate once

export type Facts = { [string]: number }

-- The profile's pieces a measure is read from.
export type Stats = {
	Kills: number,
	MatchesPlayed: number,
	GlyphsCast: number,
	BestChain: number,
	BossKills: number,
}

-- The measures a plate can read: ExLibrisConfig.Measure, spelled again because a pure module requires nothing.
export type Measure =
	"Kills"
	| "MatchesPlayed"
	| "GlyphsCast"
	| "BestChain"
	| "BossKills"
	| "KitCalligraphy"
	| "DrillsFairCopy"
	| "DrillsCalligraphy"

export type PlateSource = { Id: string, Measure: Measure, Target: number }

-- The grades of DrillLogic: a Fair copy is 2, a Calligraphy 3.
local FAIR_COPY = 2
local CALLIGRAPHY = 3

local ExLibris = {}

-- `drills` is ProfileData.Drills (drill id -> best grade), `kitIds` the ids of the kit's drills.
function ExLibris.facts(stats: Stats, drills: { [string]: number }, kitIds: { string }): Facts
	local fairCopies, calligraphies, kit = 0, 0, 0
	for _, grade in pairs(drills) do
		if grade >= FAIR_COPY then
			fairCopies += 1
		end
		if grade >= CALLIGRAPHY then
			calligraphies += 1
		end
	end
	for _, id in ipairs(kitIds) do
		if (drills[id] or 0) >= CALLIGRAPHY then
			kit += 1
		end
	end
	return {
		Kills = stats.Kills,
		MatchesPlayed = stats.MatchesPlayed,
		GlyphsCast = stats.GlyphsCast,
		BestChain = stats.BestChain,
		BossKills = stats.BossKills,
		KitCalligraphy = kit,
		DrillsFairCopy = fairCopies,
		DrillsCalligraphy = calligraphies,
	}
end

function ExLibris.progress(plate: PlateSource, facts: Facts): number
	return math.clamp(facts[plate.Measure] or 0, 0, plate.Target)
end

function ExLibris.due(plate: PlateSource, facts: Facts, granted: { [string]: number }): boolean
	return granted[plate.Id] == nil and ExLibris.progress(plate, facts) >= plate.Target
end

return ExLibris
