--!strict
-- Every colour and every material the WORLD is built from: the hub, the arenas, the training proofs and
-- the Erasure's body. Pure data, held to docs/ART_BIBLE.md by tests/WorldConfig.spec.luau.
--
-- Rule 1 of the bible: the scenery is never saturated, and the world is LIGHT. The floors are the page
-- (vellum), what stands on them is the page in shadow (bone) or lighter than it (chalk), and everything
-- drawn on it -- kerbs, rules, cover, furniture, the Erasure's band -- is ink (charcoal). A player who
-- sees a colour is seeing a glyph. The builders (HubService, ArenaService, EnemyService,
-- WorldBossService) name roles from this file and convert them once through Util/Palette; none of them
-- writes a Color3 or a Material of its own.
--
-- Colours are {r, g, b} in 0..255. Sizes and offsets are studs, {x, y, z}.

local WorldConfig = {}

export type Rgb = { number }
export type Triple = { number }

WorldConfig.Colors = {
	-- Vellum: floors, platforms, the Erasure's blank body. docs/ART_BIBLE.md #E8E0CE.
	Page = { 232, 224, 206 },
	-- Lighter than the page: a spawn pad, a proof's head, the Erasure's crown.
	Chalk = { 244, 240, 230 },
	-- The page in shadow: arena walls.
	Bone = { 214, 206, 188 },
	-- A grey wash: the training ring, drawn faintly.
	Wash = { 168, 156, 132 },
	-- Charcoal: everything drawn ON the page. docs/ART_BIBLE.md #17150F.
	Ink = { 23, 21, 15 },
} :: { [string]: Rgb }

-- The one material. docs/ART_BIBLE.md: SmoothPlastic at zero reflectance; no metal, no glass, no neon.
WorldConfig.Material = "SmoothPlastic"

-- The hub: a page with an ink border, a chalk seal at its centre for the spawn, a grey ring for the
-- training ground, charcoal furniture.
WorldConfig.Hub = {
	Platform = "Page",
	Kerb = "Ink",
	Spawn = "Chalk",
	SpawnRim = "Ink",
	-- Studs the ink rim shows around the pad.
	SpawnRimStuds = 1.2,
	Training = "Wash",
	Pedestal = "Ink",
	Board = "Ink",
	BoardLeg = "Ink",
}

-- An arena: a page walled in bone, with an ink rule drawn along the top of every wall so the box reads
-- as a bordered sheet rather than as a cream room, and ink blocks for cover.
WorldConfig.Arena = {
	Floor = "Page",
	Wall = "Bone",
	WallRule = "Ink",
	-- Height of the rule, and how much thicker than the wall it is: a coplanar face flickers.
	WallRuleStuds = 0.6,
	WallRuleProudStuds = 0.1,
	CoverWall = "Ink",
}

-- The training dummies, which the lexicon calls proofs (Épreuve): blank figures wearing a printer's
-- registration cross on the chest, in ink. Something to aim at, on a thing that is nothing yet.
WorldConfig.Proof = {
	Body = "Page",
	Head = "Chalk",
	Mark = "Ink",
	-- The cross: arm length, arm thickness, depth; and where it sits on the body's front face.
	MarkStuds = { 1.1, 0.16, 0.12 },
	MarkOffset = { 0, 0.4, -0.56 },
}

-- L'Effacement. A blank figure -- the absence of writing -- inside the hull WorldBossConfig.Boss.BodySize
-- describes for contact damage: a vellum slab with a chalk crown, two ink strokes hanging at its sides
-- (what erases), and an ink BAND across its face that widens with each phase, so a player reads the
-- phase off the body from thirty studs the way rule 2 asks a pigment to be read. Every part lies inside
-- the hull, so what looks like the boss is never wider than what hits.
--
-- The hull itself is drawn invisible: it is the contact shape, not the body.
WorldConfig.Erasure = {
	Parts = {
		{ Name = "Core", Color = "Page", Size = { 6, 13, 3.5 }, Offset = { 0, -0.5, 0 } },
		{ Name = "Crown", Color = "Chalk", Size = { 7.2, 1.6, 4.2 }, Offset = { 0, 6.2, 0 } },
		{ Name = "StrokeLeft", Color = "Ink", Size = { 0.8, 9, 1.2 }, Offset = { -3.6, -1.5, 0 } },
		{ Name = "StrokeRight", Color = "Ink", Size = { 0.8, 9, 1.2 }, Offset = { 3.6, -1.5, 0 } },
	} :: { { Name: string, Color: string, Size: Triple, Offset: Triple } },
	Band = {
		Name = "Band",
		Color = "Ink",
		Width = 6.3,
		Depth = 3.8,
		Offset = { 0, 3.4, 0 },
		-- One height per phase of WorldBossConfig.Phases, in order: the erasure spreading.
		Heights = { 1, 2.2, 3.8 },
	},
}

-- The page remembers where you walked: an ink print under each step, fading in a few seconds
-- (FootprintController). Drawn through VfxTimeline as one Mark layer, so it shares the pool, the ground
-- probe and the eviction of every other mark.
WorldConfig.Footprints = {
	-- Studs between two prints of the same character.
	StrideStuds = 2.4,
	-- Studs to the side of the root, alternating: a left foot, then a right.
	FootOffsetStuds = 0.4,
	-- Characters further than this from the camera leave nothing this client draws.
	RangeStuds = 80,
	-- Prints alive at once on this client, all characters together. A third of the mark budget at
	-- most (tests/WorldConfig.spec.luau), so a crowd never evicts a fight's own marks.
	MaxLive = 24,
	Layer = {
		Kind = "Mark",
		At = 0,
		For = 3.2,
		Ease = "Sine",
		EaseDirection = "In",
		Texture = "InkBlot",
		Size = 1.1,
		EndSize = 1,
		Transparency = 0.55,
		EndTransparency = 1,
	},
}

return WorldConfig
