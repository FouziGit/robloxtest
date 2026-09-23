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
	-- The ruling of a manuscript page: one inset rectangle of thin ink lines on the platform. It is what
	-- makes the hub read as a sheet in a screenshot rather than as a cream floor, and it is geometry, so
	-- it is there whether or not a texture has been uploaded.
	Rule = "Ink",
	RuleInsetStuds = 22,
	RuleWidthStuds = 0.6,
	-- The emblems of the queue terminal and the shop kiosk: ink, told apart by their bars, never by a
	-- colour. A saturated emblem standing permanently in the hub is rule 1 of docs/ART_BIBLE.md broken
	-- by the one thing that is on screen the longest.
	Emblem = "Ink",
}

-- A glyph that leaves something standing in the world. Its collision is the server's, so its look is too:
-- the Margin's slab used to be invisible (Transparency 1) and trusted the client's effect to show where it
-- stood. That effect is a thin brush stroke centred on the floor line -- half of it underground -- and it
-- is one of the layers the lower quality tiers are allowed to drop, so on some screens a nine-stud wall
-- that stops shots and bodies was drawn as a smear, or as nothing. A thing that blocks must be seen by
-- everyone it blocks, on every tier, for exactly as long as it blocks. The client's ink still rules the
-- margin and marks the faces; this is the wall under it.
WorldConfig.Glyphs = {
	-- Charcoal: the ink the margin is ruled in, and the colour with the most contrast on the page.
	Wall = "Ink",
	-- See-through enough to read an opponent behind it, solid enough to read as a wall at once.
	WallTransparency = 0.3,
	-- It appears with its collision, over a few frames, and leaves over the last moments of it rather
	-- than blinking out when Debris takes it.
	WallFadeInSeconds = 0.12,
	WallFadeOutSeconds = 0.4,
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
-- The hull itself is drawn invisible: it is the contact shape, not the body. It is 8 x 14 x 4.4 -- flat,
-- because docs/ART_BIBLE.md asks for flat silhouettes and because a hull deeper than the figure is an
-- invisible wall the player bumps into two studs from anything they can see.
WorldConfig.Erasure = {
	Parts = {
		{ Name = "Core", Color = "Page", Size = { 6, 13, 3.5 }, Offset = { 0, -0.5, 0 } },
		{ Name = "Crown", Color = "Chalk", Size = { 7.2, 1.6, 4.2 }, Offset = { 0, 6.2, 0 } },
		{ Name = "StrokeLeft", Color = "Ink", Size = { 0.8, 9, 1.2 }, Offset = { -3.6, -1.5, 0 } },
		{ Name = "StrokeRight", Color = "Ink", Size = { 0.8, 9, 1.2 }, Offset = { 3.6, -1.5, 0 } },
	} :: { { Name: string, Color: string, Size: Triple, Offset: Triple } },
	-- What the Erasure leaves ON the page. Its effects are drawn in ink -- a seal, a ring, a blot -- and
	-- what it has erased is the ghost of what was written, a grey wash. Neither may be the colour of the
	-- floor: VfxLibrary used the page's own vellum for both, which on a vellum floor is nothing at all.
	Mark = "Ink",
	Erased = "Wash",
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
	-- Ink, the same role the ruling and the furniture use: one source for one colour.
	Color = "Ink",
	-- Studs between two prints of the same character.
	StrideStuds = 2.4,
	-- Studs to the side of the root, alternating: a left foot, then a right. Wider than half a print, so
	-- the two tracks read as two feet instead of as one dotted line.
	FootOffsetStuds = 0.62,
	-- Characters further than this from the camera leave nothing this client draws.
	RangeStuds = 80,
	-- Prints alive at once on this client, all characters together, and per character. One walker at a
	-- run lays a print every 0.15 s, so without the per-character share a single player would hold every
	-- slot and nobody else would leave a mark; the nearest walkers are served first.
	MaxLive = 24,
	MaxPerCharacter = 8,
	-- No print is stamped once the timeline is carrying this FRACTION of the budget of the tier being drawn
	-- (QualityConfig). Eviction is oldest-first across every effect, so this -- not MaxLive -- is what
	-- keeps a crowd in the hub from pushing a fight's own residue off the screen. It has to be a fraction:
	-- as an absolute sixty it equalled the Medium tier's whole budget, so on that tier it only became true
	-- once the timeline was already full and already evicting, which is exactly what it exists to prevent.
	YieldAboveBudget = 0.66,
	-- A print is longer than it is wide and lies along the walk: Size is its width, Span its length.
	Layer = {
		Kind = "Mark",
		At = 0,
		For = 3.2,
		Ease = "Sine",
		EaseDirection = "In",
		Texture = "InkBlot",
		Size = 0.7,
		EndSize = 0.62,
		Span = 1.3,
		Transparency = 0.55,
		EndTransparency = 1,
	},
}

return WorldConfig
