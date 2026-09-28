--!strict
-- The Battleground (D-131): one permanent page built in code far east of the hub, where the Forgers
-- (BotConfig) come at whoever walks in through the hub's gate. PvE only. Pure data.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A world position is Map.Origin
-- plus a local one. The whole layout -- walls, ruling, the camp, pillars, stele, cover, the waypoint grid
-- -- is derived from Map by BattlegroundLayout, and tests/BattlegroundLayout.spec.luau holds every claim
-- the comments below make.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }

local BattlegroundConfig = {}

BattlegroundConfig.Map = {
	-- The centre of the floor's top face. Its west wall stands at x 1413, more than 1300 studs from the hub's
	-- edge: past the fog (LightingConfig FogEnd), past every effect packet's reach
	-- (GameConfig.Vfx.BroadcastRadiusStuds), and clear of the arenas stacked above x = z = 0.
	Origin = { 1500, 0, 0 },
	-- Its diagonal, 240.4, is inside GameConfig.Vfx.BroadcastRadiusStuds (250): every packet fired anywhere on
	-- the page reaches everyone on it.
	Size = 170,
	WallHeight = 30,
	WallThickness = 2,
	FloorThickness = 4,
	-- The kill plane: under the floor, far above the engine's FallenPartsDestroyHeight (-500), and wide enough
	-- that nothing thrown off an edge can miss it.
	KillZoneDepth = -40,
	KillZoneSpread = 3,
	KillZoneThickness = 1,
	-- The ruling of the page, as on the hub (WorldConfig.Hub.RuleInsetStuds).
	RuleInsetStuds = 8,
	RuleWidthStuds = 0.6,
	-- The camp, against the west wall: where players arrive, respawn and heal, behind an ink line at its
	-- east edge. A Forger never enters it and never targets anyone inside it.
	Camp = { MinX = -85, MaxX = -59, MinZ = -22, MaxZ = 22 } :: Rect,
	-- The gate back to the hub, facing east; its back posts end flush on the west wall's inner face.
	ReturnGate = { X = -78.5, Z = 0 } :: Point,
	-- Where a player lands, taken in turn. Each is more than the return circle's radius plus two studs from
	-- its seal, so nobody lands in the circle that sends them home.
	Arrivals = {
		{ X = -70, Z = -10 },
		{ X = -70, Z = 0 },
		{ X = -70, Z = 10 },
		{ X = -64, Z = -10 },
		{ X = -64, Z = 0 },
		{ X = -64, Z = 10 },
	} :: { Point },
	Pillars = { Radius = 46, Count = 8, AngleOffsetDegrees = 22.5, Size = { 6, 18, 6 } },
	Stele = { Size = { 12, 20, 12 } },
	-- 14 > the double jump's reach, 12.74 (two jumps of GameConfig.Movement's 50 under the engine's 196.2):
	-- no cover is a perch a player could stand on out of every Forger's reach.
	CoverHeight = 14,
	Covers = {
		{ Name = "CoverEast", X = 66, Z = 0, SizeX = 2, SizeZ = 24 },
		{ Name = "CoverNorth", X = 0, Z = -66, SizeX = 24, SizeZ = 2 },
		{ Name = "CoverSouth", X = 0, Z = 66, SizeX = 24, SizeZ = 2 },
		{ Name = "CoverNorthEast", X = 58, Z = -40, SizeX = 12, SizeZ = 2 },
		{ Name = "CoverSouthEast", X = 58, Z = 40, SizeX = 12, SizeZ = 2 },
		-- Screens the camp from the central sight lines.
		{ Name = "CoverWest", X = -36, Z = 0, SizeX = 2, SizeZ = 16 },
	} :: { Cover },
	-- Where a Forger appears: the one furthest from every player (BotBrain.pickSpawn). The nearest arrival is
	-- 72.5 studs away.
	BotSpawns = {
		{ X = 74, Z = 0 },
		{ X = 40, Z = 0 },
		{ X = 72, Z = -30 },
		{ X = 72, Z = 30 },
		{ X = 30, Z = -74 },
		{ X = 30, Z = 74 },
		{ X = -30, Z = -74 },
		{ X = -30, Z = 74 },
	} :: { Point },
	MinSpawnDistanceStuds = 60,
	-- The Forgers' waypoints: a node every StepStuds inside Size / 2 - MarginStuds (17 x 17 candidates), minus
	-- those inside an obstacle or the camp.
	Grid = { StepStuds = 10, MarginStuds = 5 },
}

-- What the map's parts are called, for every reader (docs/GAME_DESIGN.md §8): the Workspace model, the
-- landing and spawn markers (the prefix plus their index), the kill plane and the floor.
BattlegroundConfig.Anchors = {
	Map = "Battleground",
	Arrival = "Arrival_",
	BotSpawn = "BotSpawn_",
	KillZone = "KillZone",
	Floor = "Floor",
}

-- Players inside at once. Past it, the gate refuses with a toast.
BattlegroundConfig.MaxMembers = 12
-- Dying here puts a player back in the camp, not in the hub: the loop goes on. Only while the respawn comes
-- within Players.RespawnTime + RespawnRedirectGraceSeconds of the death, and nothing else claimed the player
-- meanwhile (a match, the Erasure's event).
BattlegroundConfig.RespawnInside = true
BattlegroundConfig.RespawnRedirectGraceSeconds = 5
-- A member stays one while the position CombatService trusts is over the floor, between BoundsDepthStuds under
-- its top face and BoundsHeightStuds above it. Anyone the server moved elsewhere fails it and is let go.
BattlegroundConfig.BoundsHeightStuds = 60
-- Half a stud: the lowest an honest root gets is a body lying on the floor, about half a stud OVER its top face,
-- so a root under this has sunk into a floor that collides. Every tier's swing still reaches this deep (its
-- standing root, StandingRootStuds times its Scale, less its HalfHeight), so no member is ever under every
-- Forger's blow while their own hits reach the Forgers' legs -- at 10, a client sunk out of every reach stayed a
-- member and was paid for every kill.
BattlegroundConfig.BoundsDepthStuds = 0.5
-- The root height of a character standing on a floor: the same half-a-character the arenas place bodies
-- at (ArenaService CHARACTER_PIVOT_STUDS). The markers stand at it, and a root farther from it than
-- BotConfig.Reach.UnreachableHeightStuds, above or below, is off the floor.
BattlegroundConfig.StandingRootStuds = 3.5

return BattlegroundConfig
