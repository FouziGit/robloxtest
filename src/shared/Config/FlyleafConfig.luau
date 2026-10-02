--!strict
-- The Flyleaf (« La Page de garde », E16-S2): one permanent page built in code far west of the hub, where every
-- member fights every other -- a free-for-all with no queue, no rank and light pay. Pure data.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A world position is Map.Origin plus a
-- local one. The layout -- floor, walls, ruling, cover, the six arrival seals, the gate home -- is derived from Map
-- by Pure/FlyleafLayout, and tests/Flyleaf.spec.luau holds every claim the comments below make.

export type Point = { X: number, Z: number }
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }

local FlyleafConfig = {}

FlyleafConfig.Map = {
	-- The centre of the floor's top face: as far west of the hub as the Battleground is east, past the fog, past
	-- every effect packet's reach from the hub (GameConfig.Vfx.BroadcastRadiusStuds), clear of the arenas.
	Origin = { -1500, 0, 0 },
	-- Its diagonal, 169.7, is inside the effects' reach (250): every packet fired on the page reaches everyone on it.
	Size = 120,
	WallHeight = 24,
	WallThickness = 2,
	FloorThickness = 4,
	KillZoneDepth = -40,
	KillZoneSpread = 3,
	KillZoneThickness = 1,
	RuleInsetStuds = 6,
	RuleWidthStuds = 0.6,
	-- The gate home, against the north wall and facing south: its back posts end flush on the wall's inner face.
	ReturnGate = { X = 0, Z = -53.5 } :: Point,
	-- The six arrival seals, a hexagon around the centre: where a member arrives and comes back after a death,
	-- always on the one furthest from every other member (Pure/FlyleafRules.farthestSeal).
	SealRadiusStuds = 38,
	SealCount = 6,
	-- The chalk disc a seal is drawn as, on its ink rim.
	SealDiameterStuds = 6,
	SealRimStuds = 1,
	-- 14 > the double jump's reach, 12.74 (two jumps of GameConfig.Movement's 50 under the engine's 196.2): no
	-- cover is a perch above the fight.
	CoverHeight = 14,
	Covers = {
		{ Name = "CoverNorth", X = 0, Z = -18, SizeX = 14, SizeZ = 2 },
		{ Name = "CoverSouth", X = 0, Z = 18, SizeX = 14, SizeZ = 2 },
		{ Name = "CoverWest", X = -18, Z = 0, SizeX = 2, SizeZ = 14 },
		{ Name = "CoverEast", X = 18, Z = 0, SizeX = 2, SizeZ = 14 },
	} :: { Cover },
}

-- What the map's parts are called, for every reader (docs/GAME_DESIGN.md §8): the Workspace model, the seals (the
-- prefix plus their index), the kill plane and the floor.
FlyleafConfig.Anchors = {
	Map = "Flyleaf",
	Seal = "Seal_",
	KillZone = "KillZone",
	Floor = "Floor",
}

-- Players on the page at once. Past it, the gate refuses with a toast.
FlyleafConfig.MaxMembers = 12
-- How often the page looks at its members (who stays, whose protection ends, who fell, whose respawn is due).
FlyleafConfig.TickHz = 10
-- Arriving, and every time a member comes back, nobody hurts them and they hurt nobody for this long: the
-- engine's ForceField shows it, and the page's own clock decides it (a body's client can delete what it wears).
FlyleafConfig.ProtectionSeconds = 4
-- A member who dies is back on the page this long after, on the seal furthest from the others.
FlyleafConfig.RespawnSeconds = 3
-- A respawn that has not stood its body on a seal this long after the death gives up, and the member is let go.
FlyleafConfig.RespawnGiveUpSeconds = 10
-- While a new body has no position the server trusts yet, it is put back on its seal for this long after
-- arriving; past it, a member nobody can place is let go.
FlyleafConfig.TrustGraceSeconds = 4
-- A member stays one while the position CombatService trusts is over the floor, between BoundsDepthStuds under its
-- top face and BoundsHeightStuds above it (a body lying on the floor keeps its root half a stud over it).
FlyleafConfig.BoundsHeightStuds = 60
FlyleafConfig.BoundsDepthStuds = 0.5
-- The root height of a character standing on the floor: where a seal stands a body.
FlyleafConfig.StandingRootStuds = 3.5

-- What a kill pays the killer: XP always, Folios out of a daily allowance kept in the profile (Daily.FlyleafDay,
-- Daily.FlyleafFolios, DailyCap), both before VIP and boosts.
FlyleafConfig.Rewards = {
	Xp = 60,
	Folios = 5,
	DailyFolioCap = 100,
}
-- Nothing is paid for a death past the MaxPaidDeaths-th a victim took from the same killer within WindowSeconds:
-- two friends trading kills stop earning after three each, and a stranger hunted down again and again pays nothing.
FlyleafConfig.Farm = {
	MaxPaidDeaths = 3,
	WindowSeconds = 600,
}
-- A member who takes this many lives without losing theirs wears the Manicule: the ink hand of the margins,
-- pointing down at them for every member to see, until they die or leave.
FlyleafConfig.ManiculeKills = 3
-- The attributes the server writes on a member's body, which every client reads: the page's own mark (the lock
-- takes only another member here) and the Manicule.
FlyleafConfig.MemberAttribute = "FlyleafMember"
FlyleafConfig.ManiculeAttribute = "Manicule"

return FlyleafConfig
