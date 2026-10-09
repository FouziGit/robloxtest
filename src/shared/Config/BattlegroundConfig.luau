--!strict
-- The Battleground (D-131, D-282): one permanent page built in code far east of the hub, 700 studs a side, where
-- every member may hurt every other and the Forgers (BotConfig) come at all of them. Pure data.
--
-- Local frame: x is east, z is south, and y = 0 is the floor's top face. A world position is Map.Origin plus a
-- local one. The whole layout -- the floor and its torn edge, the ruling, the camp, the central place, the
-- landmarks, the arrivals, the waypoint grid -- is derived from Map by BattlegroundLayout, and
-- tests/BattlegroundLayout.spec.luau holds every claim the comments below make.

export type Point = { X: number, Z: number }
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type Shape = "Block" | "Wedge" | "Cylinder"
export type Cover = { Name: string, X: number, Z: number, SizeX: number, SizeZ: number }
-- A solid piece of a landmark: its footprint's centre, the height of its underside, its size (x, y, z) and its turn
-- about the vertical in degrees. A Wedge rises toward its own +z; a Cylinder stands on its flat face, its x and z
-- both the diameter.
export type Piece = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	Size: { number },
	Yaw: number?,
}
-- A mark drawn flat on a top face Base studs above the floor: ink that touches nothing, a Rule on the floor and a
-- Trim on anything raised.
export type Mark = {
	Name: string,
	Shape: Shape,
	X: number,
	Z: number,
	Base: number,
	SizeX: number,
	SizeZ: number,
	Yaw: number?,
}

local BattlegroundConfig = {}

BattlegroundConfig.Map = {
	-- The centre of the floor's top face: the page runs from x 1150 to 1850, past the fog (LightingConfig FogEnd)
	-- and every effect packet's reach (GameConfig.Vfx.BroadcastRadiusStuds) from the hub, clear of the arenas
	-- stacked above x = z = 0. A fight at one end of it is no longer sent to the other end (D-282).
	Origin = { 1500, 0, 0 },
	Size = 700,
	FloorThickness = 4,
	-- The kill plane: under the floor, far above the engine's FallenPartsDestroyHeight (-500), and wide enough that
	-- nothing thrown off an edge can miss it.
	KillZoneDepth = -40,
	KillZoneSpread = 1.5,
	KillZoneThickness = 1,
	-- The torn edge: a band this deep round the page, cut in SlotStuds tabs, each torn Tears[i] studs in from the
	-- edge, the tears taken in turn round the page. Every tear is shallower than the band.
	Deckle = { BandStuds = 10, SlotStuds = 20, Tears = { 0, 5, 8, 2, 6, 3, 7, 1, 4 } },
	-- The ruling, as on the hub: a line along x every RuleSpacingStuds, and the margin along z at MarginX.
	RuleSpacingStuds = 20,
	RuleWidthStuds = 0.6,
	MarginX = -300,
	-- The camp, at the west edge: where the first six arrivals are and the gate home stands, behind an ink line at
	-- its east edge. It protects nobody from another member (D-282); a Forger never enters it nor answers it.
	Camp = { MinX = -336, MaxX = -310, MinZ = -22, MaxZ = 22 } :: Rect,
	-- The gate back to the hub, facing east; its back posts end flush on the camp's west edge.
	ReturnGate = { X = -329.5, Z = 0 } :: Point,
	-- Where a player lands, taken in turn: six in the camp, more than the return circle's radius plus two studs
	-- from its seal, then twelve round the edge, ArrivalSpacingStuds apart from every other arrival.
	Arrivals = {
		{ X = -321, Z = -10 },
		{ X = -321, Z = 0 },
		{ X = -321, Z = 10 },
		{ X = -315, Z = -10 },
		{ X = -315, Z = 0 },
		{ X = -315, Z = 10 },
		{ X = -305, Z = -305 },
		{ X = -50, Z = -315 },
		{ X = 180, Z = -315 },
		{ X = 305, Z = -305 },
		{ X = 310, Z = -100 },
		{ X = 310, Z = 100 },
		{ X = 305, Z = 305 },
		{ X = 100, Z = 310 },
		{ X = -100, Z = 310 },
		{ X = -305, Z = 305 },
		{ X = -310, Z = 100 },
		{ X = -310, Z = -100 },
	} :: { Point },
	ArrivalSpacingStuds = 80,
	-- The central place: a dais one step high, which a Forger walks onto, edged in ink.
	Dais = { Size = 200, Height = 1 },
	-- Low walls on the dais. Over a Forger's eyes (StandingRootStuds + BotConfig.Reach.SightHeightStuds), so they
	-- hide whoever crouches behind them.
	CoverHeight = 6,
	Covers = {
		{ Name = "CoverNorth", X = 0, Z = -60, SizeX = 30, SizeZ = 2 },
		{ Name = "CoverSouth", X = 0, Z = 60, SizeX = 30, SizeZ = 2 },
		{ Name = "CoverWest", X = -60, Z = 0, SizeX = 2, SizeZ = 30 },
		{ Name = "CoverEast", X = 60, Z = 0, SizeX = 2, SizeZ = 30 },
		{ Name = "CoverNorthEastA", X = 60, Z = -70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverNorthEastB", X = 69, Z = -59, SizeX = 2, SizeZ = 20 },
		{ Name = "CoverNorthWestA", X = -60, Z = -70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverNorthWestB", X = -69, Z = -59, SizeX = 2, SizeZ = 20 },
		{ Name = "CoverSouthEastA", X = 60, Z = 70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverSouthEastB", X = 69, Z = 59, SizeX = 2, SizeZ = 20 },
		{ Name = "CoverSouthWestA", X = -60, Z = 70, SizeX = 20, SizeZ = 2 },
		{ Name = "CoverSouthWestB", X = -69, Z = 59, SizeX = 2, SizeZ = 20 },
	} :: { Cover },
	-- The landmarks a player climbs and a Forger walks around (it stays on the ground: what is high escapes it).
	Pieces = {
		-- The open book, north-west: two half-pages in three steps of six, rising to the spine, a 20-stud valley
		-- along it.
		{ Name = "BookLeft1", Shape = "Block", X = -250, Z = -220, Base = 0, Size = { 80, 6, 140 } },
		{ Name = "BookLeft2", Shape = "Block", X = -230, Z = -220, Base = 6, Size = { 40, 6, 140 } },
		{ Name = "BookLeft3", Shape = "Block", X = -220, Z = -220, Base = 12, Size = { 20, 6, 140 } },
		{ Name = "BookRight1", Shape = "Block", X = -150, Z = -220, Base = 0, Size = { 80, 6, 140 } },
		{ Name = "BookRight2", Shape = "Block", X = -170, Z = -220, Base = 6, Size = { 40, 6, 140 } },
		{ Name = "BookRight3", Shape = "Block", X = -180, Z = -220, Base = 12, Size = { 20, 6, 140 } },
		-- The folio cliffs, north-east: books stacked in landings of 15, 30, 45 and 60 studs, the highest point,
		-- each reached by a ramp rising east.
		{ Name = "Folio1", Shape = "Block", X = 230, Z = -220, Base = 0, Size = { 120, 15, 100 } },
		{ Name = "Folio2", Shape = "Block", X = 245, Z = -220, Base = 15, Size = { 90, 15, 80 } },
		{ Name = "Folio3", Shape = "Block", X = 260, Z = -220, Base = 30, Size = { 60, 15, 60 } },
		{ Name = "Folio4", Shape = "Block", X = 275, Z = -220, Base = 45, Size = { 30, 15, 40 } },
		{ Name = "FolioRamp1", Shape = "Wedge", X = 155, Z = -220, Base = 0, Size = { 12, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp2", Shape = "Wedge", X = 185, Z = -220, Base = 15, Size = { 12, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp3", Shape = "Wedge", X = 215, Z = -220, Base = 30, Size = { 12, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp4", Shape = "Wedge", X = 245, Z = -220, Base = 45, Size = { 12, 15, 30 }, Yaw = 90 },
		-- The stitched bridge, east, over the ruled bed: a deck between two ramps.
		{ Name = "BridgeDeck", Shape = "Block", X = 240, Z = 30, Base = 0, Size = { 60, 4, 30 } },
		{ Name = "BridgeRampWest", Shape = "Wedge", X = 204, Z = 30, Base = 0, Size = { 30, 4, 12 }, Yaw = 90 },
		{ Name = "BridgeRampEast", Shape = "Wedge", X = 276, Z = 30, Base = 0, Size = { 30, 4, 12 }, Yaw = -90 },
		-- The field of seals, south: wax discs.
		{ Name = "Seal1", Shape = "Cylinder", X = -40, Z = 210, Base = 0, Size = { 24, 3, 24 } },
		{ Name = "Seal2", Shape = "Cylinder", X = 20, Z = 200, Base = 0, Size = { 16, 2, 16 } },
		{ Name = "Seal3", Shape = "Cylinder", X = 80, Z = 215, Base = 0, Size = { 30, 6, 30 } },
		{ Name = "Seal4", Shape = "Cylinder", X = 140, Z = 205, Base = 0, Size = { 20, 4, 20 } },
		{ Name = "Seal5", Shape = "Cylinder", X = -20, Z = 265, Base = 0, Size = { 28, 5, 28 } },
		{ Name = "Seal6", Shape = "Cylinder", X = 45, Z = 260, Base = 0, Size = { 18, 2, 18 } },
		{ Name = "Seal7", Shape = "Cylinder", X = 110, Z = 270, Base = 0, Size = { 24, 4, 24 } },
		{ Name = "Seal8", Shape = "Cylinder", X = 0, Z = 315, Base = 0, Size = { 20, 3, 20 } },
		{ Name = "Seal9", Shape = "Cylinder", X = 150, Z = 300, Base = 0, Size = { 22, 6, 22 } },
		-- The scriptorium's ruins, south-west: three arches (two piles and a lintel, 24 studs) and broken desks.
		{ Name = "Arch1West", Shape = "Block", X = -280, Z = 170, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch1East", Shape = "Block", X = -260, Z = 170, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch1Lintel", Shape = "Block", X = -270, Z = 170, Base = 20, Size = { 24, 4, 4 } },
		{ Name = "Arch2West", Shape = "Block", X = -200, Z = 190, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch2East", Shape = "Block", X = -180, Z = 190, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch2Lintel", Shape = "Block", X = -190, Z = 190, Base = 20, Size = { 24, 4, 4 } },
		{ Name = "Arch3West", Shape = "Block", X = -260, Z = 250, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch3East", Shape = "Block", X = -240, Z = 250, Base = 0, Size = { 4, 20, 4 } },
		{ Name = "Arch3Lintel", Shape = "Block", X = -250, Z = 250, Base = 20, Size = { 24, 4, 4 } },
		{ Name = "Desk1", Shape = "Block", X = -220, Z = 140, Base = 0, Size = { 8, 6, 6 }, Yaw = 20 },
		{ Name = "Desk2", Shape = "Block", X = -305, Z = 225, Base = 0, Size = { 6, 4, 8 }, Yaw = -15 },
		{ Name = "Desk3", Shape = "Block", X = -180, Z = 260, Base = 0, Size = { 8, 5, 8 }, Yaw = 35 },
	} :: { Piece },
	-- The fallen quill, north: a stem lying across the page from south-west to north-east, rising from the floor to
	-- Height along Length - TipLength, then a bevelled tip back down.
	Plume = { X = 60, Z = -240, Yaw = 135, Length = 180, TipLength = 20, Width = 24, Height = 40 },
	-- The inkwell's crater, west: a rim ring of Segments blocks, OuterRadius out and RimStuds thick, broken by four
	-- breaches of BreachSegments facing north, east, south and west.
	Crater = { X = -220, Z = -20, OuterRadius = 60, RimStuds = 6, Height = 6, Segments = 24, BreachSegments = 2 },
	-- The ruled bed, east: from the cliffs to the south edge, drawn flat with Lines ink lines along it (D-282: dug,
	-- it would put a member under the floor the page holds them to).
	Bed = { MinX = 220, MaxX = 260, MinZ = -170, MaxZ = 340, Lines = 3 },
	-- Ink drawn on the page: blots on the floor, and the bridge's cross stitches on its deck.
	Marks = {
		{ Name = "Blot1", Shape = "Cylinder", X = -70, Z = 245, Base = 0, SizeX = 14, SizeZ = 14 },
		{ Name = "Blot2", Shape = "Cylinder", X = 60, Z = 300, Base = 0, SizeX = 10, SizeZ = 10 },
		{ Name = "Blot3", Shape = "Cylinder", X = 180, Z = 240, Base = 0, SizeX = 12, SizeZ = 12 },
		{ Name = "Stitch1A", Shape = "Block", X = 225, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch1B", Shape = "Block", X = 225, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
		{ Name = "Stitch2A", Shape = "Block", X = 240, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch2B", Shape = "Block", X = 240, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
		{ Name = "Stitch3A", Shape = "Block", X = 255, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch3B", Shape = "Block", X = 255, Z = 30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
	} :: { Mark },
	-- Where a Forger appears: the one furthest from every player (BotBrain.pickSpawn), on open ground.
	BotSpawns = {
		{ X = 0, Z = -140 },
		{ X = 150, Z = -100 },
		{ X = 160, Z = 100 },
		{ X = 0, Z = 150 },
		{ X = -130, Z = 150 },
		{ X = -140, Z = -60 },
		{ X = -60, Z = -150 },
		{ X = 300, Z = 0 },
	} :: { Point },
	MinSpawnDistanceStuds = 60,
	-- The Forgers' waypoints: a node every StepStuds inside Size / 2 - MarginStuds (33 x 33 candidates), minus those
	-- inside an obstacle or the camp. A Forger never walks past them toward the torn edge.
	Grid = { StepStuds = 20, MarginStuds = 30 },
	-- Every part the page is built of, the gate and the markers included.
	PartBudget = 1500,
}

-- The pits of the practice duel (MatchConfig.Spar, E10-S6): walled floors in the page's own frame, east of it and
-- in a row along its axis, where one player meets one Duelist Forger. A pit holds one duel at a time; Count is
-- how many a server runs at once.
--   * Its floor is the page's height, so the Forgers walk, aim and fall in it as they do on the page (Motion,
--     Attacks, the page's frame).
--   * Each is more than GameConfig.Vfx.BroadcastRadiusStuds (250) from the page and from the next pit, and clear
--     of the page's kill plane: nothing drawn in one is sent to anybody in another.
--   * Its walls stand higher than the double jump reaches (12.74, as the page's covers).
--   * The player's pad is on its east side and the Forger's on its west, both on the page's axis: a body put down
--     facing the page's centre (Roster.place) faces the Forger.
BattlegroundConfig.Pits = {
	Count = 4,
	-- The centre of the first pit's floor, in the page's frame, and the step to the next one along x.
	FirstX = 650,
	SpacingX = 330,
	Size = 60,
	WallHeight = 20,
	WallThickness = 2,
	-- Each pad this far in from its wall.
	PadInsetStuds = 14,
	-- A body whose root falls this far under the floor has fallen out of the pit: a death of the environment.
	FallDepthStuds = 40,
}

-- What the map's parts are called, for every reader (docs/GAME_DESIGN.md §8): the Workspace model, the
-- landing and spawn markers (the prefix plus their index), the kill plane and the floor.
BattlegroundConfig.Anchors = {
	Map = "Battleground",
	Arrival = "Arrival_",
	BotSpawn = "BotSpawn_",
	KillZone = "KillZone",
	Floor = "Floor",
	-- The Workspace folder the pits stand in, and each one's model (the prefix plus its index).
	Pits = "SparPits",
	Pit = "Pit_",
}

-- Players inside at once. Past it, the gate refuses with a toast.
BattlegroundConfig.MaxMembers = 12
-- Dying here puts a player back in the camp, not in the hub: the loop goes on. Only while the respawn comes
-- within Players.RespawnTime + RespawnRedirectGraceSeconds of the death, and nothing else claimed the player
-- meanwhile (a match, the Erasure's event).
BattlegroundConfig.RespawnInside = true
BattlegroundConfig.RespawnRedirectGraceSeconds = 5
-- A member stays one while the position CombatService trusts is over the floor, between BoundsDepthStuds under
-- its top face and BoundsHeightStuds above it -- a jump off the highest landing included. Anyone the server moved
-- elsewhere fails it and is let go.
BattlegroundConfig.BoundsHeightStuds = 80
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

-- Arriving, and every time a member comes back to the page, nobody hurts them for this long; the first blow they
-- strike themselves ends it at once (CombatService.protect).
BattlegroundConfig.ArrivalProtectionSeconds = 3

-- What one member's kill of another pays its killer: XP, and Folios out of the same daily allowance as the
-- Forgers' (BotConfig.Credit.DailyFolioCap). A pair pays once, then nothing until PairCooldownSeconds have passed
-- since its last kill, paid or not (FlyleafRules.recordKill).
BattlegroundConfig.PlayerKill = { Xp = 60, Folios = 3, PairCooldownSeconds = 300 }

return BattlegroundConfig
