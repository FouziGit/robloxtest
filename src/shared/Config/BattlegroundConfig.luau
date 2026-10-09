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
-- An open book (Map.Books).
export type Book = {
	Name: string,
	X: number,
	Z: number,
	PageWidth: number,
	Length: number,
	Valley: number,
	Profile: { number },
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
		{ X = -325, Z = -120 },
		{ X = -325, Z = -250 },
		{ X = -200, Z = -330 },
		{ X = -40, Z = -325 },
		{ X = 110, Z = -330 },
		{ X = 325, Z = -100 },
		{ X = 325, Z = 70 },
		{ X = 320, Z = 230 },
		{ X = 170, Z = 330 },
		{ X = -10, Z = 330 },
		{ X = -180, Z = 325 },
		{ X = -325, Z = 140 },
	} :: { Point },
	ArrivalSpacingStuds = 80,
	-- The central place (D-282): a chalk dais Height studs above the floor, edged in ink, and a flight of steps
	-- Width wide down the middle of each side, Rise high and Tread deep, the top one level with the dais. A Forger
	-- climbs it only up the steps (BattlegroundLayout's ledges); a Rise of one stud is the step it walks up.
	Dais = { Size = 200, Height = 7, Stairs = { Width = 60, Rise = 1, Tread = 3.5 } },
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
		-- The broken parapet: an L at each corner of the dais, clear of the stairs.
		{ Name = "ParapetNorthWestA", X = -84, Z = -98, SizeX = 30, SizeZ = 2 },
		{ Name = "ParapetNorthWestB", X = -98, Z = -83, SizeX = 2, SizeZ = 28 },
		{ Name = "ParapetNorthEastA", X = 84, Z = -98, SizeX = 30, SizeZ = 2 },
		{ Name = "ParapetNorthEastB", X = 98, Z = -83, SizeX = 2, SizeZ = 28 },
		{ Name = "ParapetSouthWestA", X = -84, Z = 98, SizeX = 30, SizeZ = 2 },
		{ Name = "ParapetSouthWestB", X = -98, Z = 83, SizeX = 2, SizeZ = 28 },
		{ Name = "ParapetSouthEastA", X = 84, Z = 98, SizeX = 30, SizeZ = 2 },
		{ Name = "ParapetSouthEastB", X = 98, Z = 83, SizeX = 2, SizeZ = 28 },
	} :: { Cover },
	-- The landmarks a player climbs and a Forger walks around (it stays on the ground: what is high escapes it).
	Pieces = {
		-- The folio cliffs, north-east: a rock 15 high filling the corner, closed books stacked on it in tiers of
		-- 30, 45 and 60, the highest point, each reached by a ramp (one from the floor on the west and the south).
		{ Name = "FolioRock", Shape = "Block", X = 245, Z = -245, Base = 0, Size = { 190, 15, 190 } },
		{ Name = "FolioRockWest", Shape = "Block", X = 150, Z = -290, Base = 0, Size = { 24, 9, 40 }, Yaw = 15 },
		{ Name = "FolioRockSouth", Shape = "Block", X = 320, Z = -150, Base = 0, Size = { 30, 11, 22 }, Yaw = -12 },
		{ Name = "FolioTier1", Shape = "Block", X = 270, Z = -280, Base = 15, Size = { 120, 15, 100 } },
		{ Name = "FolioTier2", Shape = "Block", X = 290, Z = -300, Base = 30, Size = { 80, 15, 60 } },
		{ Name = "FolioTier3", Shape = "Block", X = 307.5, Z = -310, Base = 45, Size = { 45, 15, 40 } },
		{ Name = "FolioLoose1", Shape = "Block", X = 185, Z = -305, Base = 15, Size = { 44, 10, 34 }, Yaw = 12 },
		{ Name = "FolioLoose2", Shape = "Block", X = 185, Z = -305, Base = 25, Size = { 34, 8, 26 }, Yaw = -6 },
		{ Name = "FolioLoose3", Shape = "Block", X = 225, Z = -255, Base = 30, Size = { 24, 8, 30 }, Yaw = 20 },
		{ Name = "FolioRampWest", Shape = "Wedge", X = 135, Z = -200, Base = 0, Size = { 16, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRampSouth", Shape = "Wedge", X = 180, Z = -135, Base = 0, Size = { 16, 15, 30 }, Yaw = 180 },
		{ Name = "FolioRamp1", Shape = "Wedge", X = 270, Z = -215, Base = 15, Size = { 16, 15, 30 }, Yaw = 180 },
		{ Name = "FolioRamp2", Shape = "Wedge", X = 235, Z = -300, Base = 30, Size = { 16, 15, 30 }, Yaw = 90 },
		{ Name = "FolioRamp3", Shape = "Wedge", X = 270, Z = -310, Base = 45, Size = { 16, 15, 30 }, Yaw = 90 },
		-- The stitched bridge, east, over the ruled bed: a deck between two ramps.
		{ Name = "BridgeDeck", Shape = "Block", X = 260, Z = -30, Base = 0, Size = { 76, 4, 30 } },
		{ Name = "BridgeRampWest", Shape = "Wedge", X = 216, Z = -30, Base = 0, Size = { 30, 4, 12 }, Yaw = 90 },
		{ Name = "BridgeRampEast", Shape = "Wedge", X = 304, Z = -30, Base = 0, Size = { 30, 4, 12 }, Yaw = -90 },
		-- The field of seals, south, either side of the bed: wax discs, a smaller one stacked on some.
		{ Name = "Seal1", Shape = "Cylinder", X = 40, Z = 175, Base = 0, Size = { 36, 4, 36 } },
		{ Name = "Seal1Top", Shape = "Cylinder", X = 40, Z = 175, Base = 4, Size = { 22, 3, 22 } },
		{ Name = "Seal2", Shape = "Cylinder", X = 75, Z = 245, Base = 0, Size = { 26, 3, 26 } },
		{ Name = "Seal3", Shape = "Cylinder", X = 5, Z = 250, Base = 0, Size = { 32, 5, 32 } },
		{ Name = "Seal3Top", Shape = "Cylinder", X = 5, Z = 250, Base = 5, Size = { 20, 3, 20 } },
		{ Name = "Seal4", Shape = "Cylinder", X = 55, Z = 315, Base = 0, Size = { 22, 2, 22 } },
		{ Name = "Seal5", Shape = "Cylinder", X = -45, Z = 300, Base = 0, Size = { 28, 4, 28 } },
		{ Name = "Seal6", Shape = "Cylinder", X = 305, Z = 160, Base = 0, Size = { 34, 4, 34 } },
		{ Name = "Seal6Top", Shape = "Cylinder", X = 305, Z = 160, Base = 4, Size = { 20, 3, 20 } },
		{ Name = "Seal7", Shape = "Cylinder", X = 275, Z = 255, Base = 0, Size = { 24, 3, 24 } },
		{ Name = "Seal8", Shape = "Cylinder", X = 225, Z = 315, Base = 0, Size = { 28, 4, 28 } },
		-- The scriptorium's broken desks, east of its arcade: tops on the floor, some tipped, and stumps.
		{ Name = "Desk1", Shape = "Block", X = -240, Z = 165, Base = 0, Size = { 14, 6, 9 }, Yaw = 20 },
		{ Name = "Desk2", Shape = "Block", X = -205, Z = 160, Base = 0, Size = { 14, 5, 9 }, Yaw = -10 },
		{ Name = "Desk3", Shape = "Block", X = -170, Z = 175, Base = 0, Size = { 14, 6, 9 }, Yaw = 35 },
		{ Name = "Desk4", Shape = "Wedge", X = -235, Z = 205, Base = 0, Size = { 14, 6, 9 }, Yaw = 160 },
		{ Name = "Desk5", Shape = "Block", X = -200, Z = 200, Base = 0, Size = { 14, 6, 9 }, Yaw = 5 },
		{ Name = "Desk6", Shape = "Block", X = -165, Z = 215, Base = 0, Size = { 14, 5, 9 }, Yaw = -30 },
		{ Name = "Desk7", Shape = "Block", X = -240, Z = 245, Base = 0, Size = { 14, 5, 9 }, Yaw = -25 },
		{ Name = "Desk8", Shape = "Wedge", X = -205, Z = 240, Base = 0, Size = { 14, 6, 9 }, Yaw = 80 },
		{ Name = "Desk9", Shape = "Block", X = -170, Z = 255, Base = 0, Size = { 14, 6, 9 }, Yaw = 50 },
		{ Name = "DeskStump1", Shape = "Block", X = -220, Z = 280, Base = 0, Size = { 8, 14, 8 }, Yaw = 15 },
		{ Name = "DeskStump2", Shape = "Block", X = -185, Z = 285, Base = 0, Size = { 7, 20, 7 } },
	} :: { Piece },
	-- The open books: two half-pages PageWidth wide and Length long either side of a valley Valley wide down the
	-- spine, each a hill whose height rises from its outer edge to the spine through Profile, evenly spaced. The
	-- big one fills the north-west; the little one lies south-west of the place.
	Books = {
		{
			Name = "OpenBook",
			X = -200,
			Z = -240,
			PageWidth = 90,
			Length = 140,
			Valley = 20,
			Profile = { 4, 9, 14, 17, 18, 8 },
		},
		{ Name = "LittleBook", X = -70, Z = 200, PageWidth = 30, Length = 56, Valley = 20, Profile = { 2, 5, 7, 4 } },
	} :: { Book },
	-- The fallen quill, north: from its foot at (X, Z) along Yaw, a flight of Steps, each Rise higher and Tread deep,
	-- between two rails sloping as high, then a landing Landing deep and the bevelled tip back down to the floor.
	Quill = {
		X = 50,
		Z = -140,
		Yaw = 170,
		Width = 24,
		RailStuds = 6,
		Steps = 30,
		Rise = 2,
		Tread = 5,
		Landing = 14,
		TipLength = 26,
	},
	-- The inkwell's crater, west: a rim ring of Segments blocks, OuterRadius out and RimStuds thick, broken by four
	-- breaches of BreachSegments facing north, east, south and west. Its floor is the page's.
	Crater = { X = -215, Z = 0, OuterRadius = 70, RimStuds = 8, Height = 7, Segments = 32, BreachSegments = 2 },
	-- The scriptorium's arcade, south-west: Arches openings between Arches + 1 piers Pier wide, all under one beam
	-- Beam deep that tops it at Height, with a corbel in each upper corner of every opening.
	Arcade = {
		X = -290,
		Z = 215,
		Yaw = 70,
		Arches = 4,
		Pier = 6,
		Opening = 18,
		Thickness = 8,
		Height = 30,
		Beam = 5,
		Corbel = { Width = 3, Height = 5 },
	},
	-- The ruled bed: Width wide along Points, from the cliffs to the south edge, drawn flat with its banks and Lines
	-- ink lines along it (D-282: dug, it would put a member under the floor the page holds them to).
	Bed = {
		Points = { { X = 260, Z = -150 }, { X = 260, Z = 40 }, { X = 150, Z = 220 }, { X = 120, Z = 330 } },
		Width = 60,
		BankStuds = 2,
		Lines = 3,
	},
	-- Ink drawn on the page: blots on the floor, the books' spines, and the bridge's cross stitches on its deck.
	Marks = {
		{ Name = "Blot1", Shape = "Cylinder", X = 100, Z = 180, Base = 0, SizeX = 30, SizeZ = 30 },
		{ Name = "Blot2", Shape = "Cylinder", X = -20, Z = 330, Base = 0, SizeX = 16, SizeZ = 16 },
		{ Name = "Blot3", Shape = "Cylinder", X = 175, Z = -70, Base = 0, SizeX = 24, SizeZ = 24 },
		{ Name = "Blot4", Shape = "Cylinder", X = 290, Z = 305, Base = 0, SizeX = 30, SizeZ = 30 },
		{ Name = "Blot5", Shape = "Cylinder", X = -140, Z = -130, Base = 0, SizeX = 14, SizeZ = 14 },
		{ Name = "OpenBookSpine", Shape = "Block", X = -200, Z = -240, Base = 0, SizeX = 2, SizeZ = 140 },
		{ Name = "LittleBookSpine", Shape = "Block", X = -70, Z = 200, Base = 0, SizeX = 2, SizeZ = 56 },
		{ Name = "Stitch1A", Shape = "Block", X = 245, Z = -30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch1B", Shape = "Block", X = 245, Z = -30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
		{ Name = "Stitch2A", Shape = "Block", X = 260, Z = -30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch2B", Shape = "Block", X = 260, Z = -30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
		{ Name = "Stitch3A", Shape = "Block", X = 275, Z = -30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = 45 },
		{ Name = "Stitch3B", Shape = "Block", X = 275, Z = -30, Base = 4, SizeX = 10, SizeZ = 1, Yaw = -45 },
	} :: { Mark },
	-- Where a Forger appears: the one furthest from every player (BotBrain.pickSpawn), on open ground.
	BotSpawns = {
		{ X = 0, Z = -150 },
		{ X = 100, Z = -240 },
		{ X = 170, Z = -80 },
		{ X = 170, Z = 90 },
		{ X = 0, Z = 150 },
		{ X = -140, Z = 140 },
		{ X = -150, Z = -60 },
		{ X = 300, Z = 0 },
	} :: { Point },
	MinSpawnDistanceStuds = 60,
	-- The Forgers' waypoints: a node every StepStuds inside Size / 2 - MarginStuds (33 x 33 candidates), minus those
	-- inside an obstacle or the camp. A Forger never walks past them toward the torn edge.
	Grid = { StepStuds = 20, MarginStuds = 30 },
	-- The landmarks' skins (D-283): tools/meshes/page/ reads these to draw them, BattlegroundLayout.skins to place them.
	-- A skin's face stands Out studs outside the box face it covers and a walkable top Top studs over the box's top;
	-- the rest are the sizes a kind's one mesh is drawn at, each instance scaled from it to its own box.
	Skin = {
		Out = 0.12,
		Top = 0.07,
		Seal = { Diameter = 28, Height = 4 },
		BlotStuds = 12,
		Wall = { Length = 20, Thickness = 2 },
	},
	-- Every part the page is built of, the gate, the markers and the skins included.
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

-- The attribute the server sets on a member's body for as long as the page holds them: how another member's lock-on
-- (LockOnController) tells who it may take, as the Flyleaf's does (FlyleafConfig.MemberAttribute).
BattlegroundConfig.MemberAttribute = "BattlegroundMember"

-- What one member's kill of another pays its killer: XP, out of a daily allowance of DailyXpCap kept in the profile
-- (Daily.PlayerKillDay, PlayerKillXp), and Folios out of the same daily allowance as the Forgers'
-- (BotConfig.Credit.DailyFolioCap); both before VIP and boosts. A pair of players, whichever killed the other, pays
-- once, then nothing until PairCooldownSeconds have passed since its last kill, paid or not
-- (FlyleafRules.recordKill).
BattlegroundConfig.PlayerKill = { Xp = 60, Folios = 3, PairCooldownSeconds = 300, DailyXpCap = 1200 }

return BattlegroundConfig
