--!strict
-- Cosmetic catalog. Pure data. Cosmetics never affect gameplay.
-- Slots: Aura | Trail | KillEffect | Title | Skin (Skin applies to one glyph id via Target).
--
-- Every look obeys docs/ART_BIBLE.md, and that is a constraint on what a cosmetic may BE, not a style:
--   * rule 2, a glyph is one pigment -- so a skin is a SHADE of its glyph's pigment (darker toward ink,
--     paler toward the page), never another hue: a blue Brand would be read as Indigo from thirty studs;
--   * rule 7, white means invulnerable and cyan means an ally -- so nothing worn is white or that cyan;
--   * a kill effect is drawn in the page's inks (Inks below): it lands on somebody else's screen, in their
--     fight.
-- What a body WEARS -- an aura, a trail -- is the one amendment to rule 1 (D-148): it is coloured, in the
-- materials of the book (gold leaf, lapis, madder, iron-gall, soot, silverpoint, sap green, ochre, murex
-- purple), because a purchase in the page's charcoal on a dark avatar was a few black dots nobody saw. It
-- still never takes a school's colour (tests/Cosmetics.spec.luau holds every colour it can draw away from
-- each pigment, from white and from the ally cyan), and it steps back in a fight (Fight below) so the glyphs
-- keep the colour of the fight.
-- Rarity is carried by craft AND intensity: a Rare is one layer, an Epic two, a Legendary three with a small
-- light core, the only thing worn that adds light (LayersByRarity).
-- Ids are storage keys (profiles, passes, rewards) and keep their historical names; what a player sees
-- is the NameKey and the Look (docs/DECISIONS.md D-109).

export type Slot = "Aura" | "Trail" | "KillEffect" | "Title" | "Skin"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type Tone =
	"Ink"
	| "Graphite"
	| "Wash"
	| "GoldLeaf"
	| "Lapis"
	| "Madder"
	| "IronGall"
	| "Lilac"
	| "Ember"
	| "Silverpoint"
	| "SapGreen"
	| "Ochre"
	| "Tyrian"
	| "Void"
-- Styles are the keys of AuraStyles and TrailStyles below; CosmeticController draws what their data says.
export type Look = {
	Styles: { string }?, -- Aura, Trail: layered, most visible first
	Tone: Tone?, -- Aura, Trail: the headline colour, the one a shop shows; KillEffect: its ink
	Tones: { string }?, -- Aura, Trail: the Tone of each style, in Styles' order (absent: every style in Tone)
	Timeline: string?, -- KillEffect: a VfxTimelineConfig timeline
	TextKey: string?, -- Title: the words shown above the head
	Shade: number?, -- Skin: -1 toward ink .. +1 toward the page, inside PigmentConfig.ShadeRange
}
export type CosmeticDef = {
	Id: string,
	Slot: Slot,
	Rarity: Rarity,
	NameKey: string,
	Sellable: boolean, -- false = reward only (battle pass, season, pack)
	Target: string?, -- glyph id for skins
	Look: Look,
}

local CosmeticConfig = {}

CosmeticConfig.Items = {
	-- Battle pass free track
	{
		Id = "BlankHeadband",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.BlankHeadband",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.BlankHeadband" },
	},
	{
		Id = "SteelStylus",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.SteelStylus",
		Sellable = false,
		Look = { Styles = { "Hairline" }, Tone = "Silverpoint" },
	},
	{
		Id = "PalimpsestCape",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.PalimpsestCape",
		Sellable = false,
		Look = { Styles = { "Pages" }, Tone = "Madder" },
	},
	{
		Id = "FrisketMask",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.FrisketMask",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.FrisketMask" },
	},
	{
		Id = "BlueInkAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.BlueInkAura",
		Sellable = false,
		Look = { Styles = { "Drips", "Pool" }, Tone = "Lapis" },
	},
	{
		Id = "ScriptoriumRobe",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.ScriptoriumRobe",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.ScriptoriumRobe" },
	},
	{
		Id = "VioletInkAura",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.VioletInkAura",
		Sellable = false,
		Look = { Styles = { "Wisps", "Motes" }, Tone = "IronGall", Tones = { "IronGall", "Lilac" } },
	},
	{
		Id = "ScribeCloak",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.ScribeCloak",
		Sellable = false,
		Look = { Styles = { "Stroke", "Flecks" }, Tone = "Lapis" },
	},
	{
		Id = "GoldenInkAura",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.GoldenInkAura",
		Sellable = false,
		Look = { Styles = { "Orbit", "Leaf", "Core" }, Tone = "GoldLeaf", Tones = { "GoldLeaf", "GoldLeaf", "Lapis" } },
	},
	{
		Id = "CodexCloak",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.CodexCloak",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.CodexCloak" },
	},
	-- Battle pass premium track
	{
		Id = "TrailEmber",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.TrailEmber",
		Sellable = false,
		Look = { Styles = { "Soot" }, Tone = "Ember" },
	},
	{
		Id = "AuraCrimson",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.AuraCrimson",
		Sellable = false,
		Look = { Styles = { "Plume", "Motes" }, Tone = "Tyrian", Tones = { "Tyrian", "Madder" } },
	},
	{
		Id = "KillEffectShatter",
		Slot = "KillEffect",
		Rarity = "Epic",
		NameKey = "cosmetic.KillEffectShatter",
		Sellable = false,
		Look = { Timeline = "KillTear" },
	},
	{
		Id = "TitleShadow",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleShadow",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleShadow" },
	},
	{
		Id = "SkinBrandAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinBrandAzure",
		Sellable = false,
		Target = "Brand",
		Look = { Shade = -0.25 },
	},
	{
		Id = "TrailStorm",
		Slot = "Trail",
		Rarity = "Epic",
		NameKey = "cosmetic.TrailStorm",
		Sellable = false,
		Look = { Styles = { "Scrawl", "Flecks" }, Tone = "SapGreen" },
	},
	{
		Id = "SkinRuptureMagma",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinRuptureMagma",
		Sellable = false,
		Target = "Rupture",
		Look = { Shade = -0.25 },
	},
	{
		Id = "KillEffectRedaction",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectRedaction",
		Sellable = false,
		Look = { Timeline = "KillRedaction" },
	},
	{
		Id = "TitleCodex",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleCodex",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleCodex" },
	},
	{
		Id = "AuraCodex",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraCodex",
		Sellable = false,
		Look = { Styles = { "Pages", "Seal", "Core" }, Tone = "Lapis", Tones = { "Lapis", "GoldLeaf", "GoldLeaf" } },
	},
	-- Season rewards
	{
		Id = "TitleScript",
		Slot = "Title",
		Rarity = "Rare",
		NameKey = "cosmetic.TitleScript",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleScript" },
	},
	{
		Id = "TitleIllumination",
		Slot = "Title",
		Rarity = "Epic",
		NameKey = "cosmetic.TitleIllumination",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleIllumination" },
	},
	{
		Id = "TitleCodexSeason",
		Slot = "Title",
		Rarity = "Legendary",
		NameKey = "cosmetic.TitleCodexSeason",
		Sellable = false,
		Look = { TextKey = "cosmetic.title.TitleCodexSeason" },
	},
	-- Skin pack (game pass)
	{
		Id = "SkinWashJade",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinWashJade",
		Sellable = false,
		Target = "Wash",
		Look = { Shade = -0.25 },
	},
	{
		Id = "SkinSerifObsidian",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinSerifObsidian",
		Sellable = false,
		Target = "Serif",
		Look = { Shade = -0.25 },
	},
	{
		Id = "SkinSweepSilver",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinSweepSilver",
		Sellable = false,
		Target = "Sweep",
		Look = { Shade = 0.2 },
	},
	-- VIP game pass: the aura docs/ECONOMY.md and the pass description promise (MonetizationConfig.VipCosmetics).
	{
		Id = "VipAura",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.VipAura",
		Sellable = false,
		Look = { Styles = { "Seal", "Leaf", "Core" }, Tone = "Tyrian", Tones = { "Tyrian", "GoldLeaf", "GoldLeaf" } },
	},
	-- Shop catalog (Folios or Robux)
	{
		Id = "TrailFolio",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailFolio",
		Sellable = true,
		Look = { Styles = { "Scraps" }, Tone = "Madder" },
	},
	{
		Id = "TrailSand",
		Slot = "Trail",
		Rarity = "Common",
		NameKey = "cosmetic.TrailSand",
		Sellable = true,
		Look = { Styles = { "Dust" }, Tone = "Ochre" },
	},
	{
		Id = "TitleRookie",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.TitleRookie",
		Sellable = true,
		Look = { TextKey = "cosmetic.title.TitleRookie" },
	},
	{
		Id = "TitleWanderer",
		Slot = "Title",
		Rarity = "Common",
		NameKey = "cosmetic.TitleWanderer",
		Sellable = true,
		Look = { TextKey = "cosmetic.title.TitleWanderer" },
	},
	{
		Id = "AuraFrost",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.AuraFrost",
		Sellable = true,
		Look = { Styles = { "Glints" }, Tone = "Silverpoint" },
	},
	{
		Id = "AuraEmber",
		Slot = "Aura",
		Rarity = "Rare",
		NameKey = "cosmetic.AuraEmber",
		Sellable = true,
		Look = { Styles = { "Soot" }, Tone = "Ember" },
	},
	{
		Id = "TrailViolet",
		Slot = "Trail",
		Rarity = "Rare",
		NameKey = "cosmetic.TrailViolet",
		Sellable = true,
		Look = { Styles = { "Stroke" }, Tone = "IronGall" },
	},
	{
		Id = "SkinBrandEmerald",
		Slot = "Skin",
		Rarity = "Rare",
		NameKey = "cosmetic.SkinBrandEmerald",
		Sellable = true,
		Target = "Brand",
		Look = { Shade = 0.2 },
	},
	{
		Id = "KillEffectPetals",
		Slot = "KillEffect",
		Rarity = "Epic",
		NameKey = "cosmetic.KillEffectPetals",
		Sellable = true,
		Look = { Timeline = "KillScraps", Tone = "Wash" },
	},
	{
		Id = "AuraStorm",
		Slot = "Aura",
		Rarity = "Epic",
		NameKey = "cosmetic.AuraStorm",
		Sellable = true,
		Look = { Styles = { "Scrawl", "Spatter" }, Tone = "SapGreen" },
	},
	{
		Id = "SkinScorchAzure",
		Slot = "Skin",
		Rarity = "Epic",
		NameKey = "cosmetic.SkinScorchAzure",
		Sellable = true,
		Target = "Scorch",
		Look = { Shade = -0.25 },
	},
	{
		Id = "AuraVoid",
		Slot = "Aura",
		Rarity = "Legendary",
		NameKey = "cosmetic.AuraVoid",
		Sellable = true,
		Look = { Styles = { "Inward", "Seal", "Core" }, Tone = "Void", Tones = { "Void", "Void", "Tyrian" } },
	},
	{
		Id = "KillEffectSupernova",
		Slot = "KillEffect",
		Rarity = "Legendary",
		NameKey = "cosmetic.KillEffectSupernova",
		Sellable = true,
		Look = { Timeline = "KillOverexposure" },
	},
	{
		Id = "SkinRuptureCrystal",
		Slot = "Skin",
		Rarity = "Legendary",
		NameKey = "cosmetic.SkinRuptureCrystal",
		Sellable = true,
		Target = "Rupture",
		Look = { Shade = 0.2 },
	},
} :: { CosmeticDef }

-- Every tone, as RGB 0-255, by name: what a look names in Tone and Tones, and what a shop preview paints.
-- The first three are the page's inks (Inks below): tints, never colours, none of them white. Ink is
-- WorldConfig.Colors.Ink; Graphite and Wash are the two greys between it and the page. The rest are what a
-- body wears (D-148), each a material of the book, each measured away from every pigment, from white and
-- from the ally cyan (tests/Cosmetics.spec.luau), and each dark or strong enough to be read on vellum.
CosmeticConfig.Tones = {
	Ink = { 23, 21, 15 },
	Graphite = { 74, 70, 63 },
	Wash = { 128, 120, 104 },
	-- Burnished gold leaf, laid on a bole: warmer and deeper than Orpiment's arsenic yellow.
	GoldLeaf = { 206, 152, 44 },
	-- Ultramarine ground from lapis lazuli, the illuminator's blue: brighter and purer than a vat of Indigo.
	Lapis = { 44, 92, 230 },
	-- Madder lake, the rose of rubrics scraped off a palimpsest.
	Madder = { 224, 84, 140 },
	-- Iron-gall ink as it is written, violet before the page darkens it.
	IronGall = { 132, 86, 214 },
	-- Fresh iron-gall thinned with water.
	Lilac = { 182, 146, 232 },
	-- A coal before it is soot.
	Ember = { 244, 136, 40 },
	-- The line a silver stylus scores: graphite's blue sheen.
	Silverpoint = { 136, 164, 224 },
	-- Sap green, pressed from buckthorn berries.
	SapGreen = { 128, 188, 44 },
	-- Yellow ochre, the colour of pumice-dressed parchment.
	Ochre = { 206, 156, 86 },
	-- Murex purple, the dye of a patron's parchment.
	Tyrian = { 150, 40, 120 },
	-- The violet at the edge of a hole in the page.
	Void = { 88, 44, 160 },
} :: { [string]: { number } }

-- The page's inks among the tones: what a kill effect is drawn in (it lands on somebody else's screen) and
-- what the dash's sketches and the kit outline read.
CosmeticConfig.Inks = { "Ink", "Graphite", "Wash" } :: { string }

-- Where a particle is born or a moving point runs, in the wearer's root space (studs, +Y up, +Z behind), as
-- Pure/AuraMath reads it (AuraMath.point, AuraMath.path):
--   Ring   -- anywhere on a cylinder of Radius, between Low and High
--   Feet   -- anywhere on a disc of Radius at the floor, Lift above it
--   Floor  -- the floor under the body, Lift above it
--   Hands  -- Radius to either side, at Height and Depth
--   Behind -- Depth behind the body: between Low and High, or for a ribbon at Height, each further stroke Gap
--             lower, rising and falling by Bob every Seconds when Seconds is given
--   Orbit  -- a circle of Radius at Height, rising and falling by Bob, once every Seconds
--   Scrawl -- the same circle swelling and climbing: a pen's loops
export type Place = {
	Kind: string, -- one of the seven above
	Radius: number?,
	Low: number?,
	High: number?,
	Lift: number?,
	Height: number?,
	Seconds: number?,
	Bob: number?,
	Depth: number?,
	Gap: number?,
}

-- A stream of particles, emitted by CosmeticController itself on its Heartbeat (never by a Rate, which the
-- engine thins about nine times at its automatic graphics quality: D-124).
export type Emission = {
	Texture: string, -- an AssetIds.Textures key
	Place: Place,
	Rate: number, -- particles a second at the High tier, one body
	Lifetime: { number }, -- seconds, least and most
	Speed: { number }, -- studs a second, least and most
	Emit: string, -- Up, Down, In or Out: In and Out toward and away from the body's axis
	Spread: number?, -- degrees either side of Emit
	Size: { number }, -- studs over the life, evenly spaced
	Transparency: { number }, -- over the life, evenly spaced
	Rise: number?, -- vertical acceleration, studs a second squared (negative falls)
	Drag: number?,
	Spin: number?, -- degrees a second, either way
	Stretch: number?, -- taller than wide, as the engine's Squash
	Flat: boolean?, -- lies on the floor instead of facing the camera
	Front: boolean?, -- drawn over the style's other particles
	Dries: number?, -- share of the way to ink by the end of its life
	Glint: number?, -- flickers that share toward white, Flickers times over its life
	Flickers: number?,
	Heat: number?, -- born that share toward white: a core's heart only
	Glow: number?, -- added as light (LightEmission): a Core style only
}

-- A bare ribbon drawn between two moving attachments, tapered toward its tail. A texture on a Trail is
-- stretched over its whole length and read as a smudge (vellum-vfx), so it has none.
export type Ribbon = {
	Path: Place, -- Behind, Orbit or Scrawl
	Count: number, -- strokes sharing the path
	Width: number, -- studs at its head
	Lifetime: number,
	Transparency: number, -- at its head; the tail fades to nothing
	Dries: number?, -- share of the way to ink at its tail
	FaceCamera: boolean?, -- a thin stroke reads from every side; a band worn on the body stands (D-108)
}

export type Style = {
	Emissions: { Emission }?,
	Ribbons: { Ribbon }?,
	-- The light core: the only style whose particles may add light, and only a Legendary aura wears one.
	Core: boolean?,
}

-- How many styles a look layers, by rarity: intensity is read by how much is layered, and craft by what.
CosmeticConfig.LayersByRarity = { Common = 1, Rare = 1, Epic = 2, Legendary = 3 } :: { [Rarity]: number }

-- The most particles one body's aura and trail keep alive at once at the High tier, together (the sum
-- AuraMath.live gives for their styles). Every lower tier scales it by its ParticleScale.
CosmeticConfig.Budget = { LiveParticles = 60 }

-- What every aura and trail becomes while the local player fights -- a ranked match, the Battleground, the
-- Erasure's arena: this share of its particles, this much fainter, and no light at all. The glyphs keep
-- the colour of the fight.
CosmeticConfig.Fight = { Density = 0.4, Transparency = 0.25, Glow = 0 }

-- How a driven flow is paced: at most this much of a long frame is owed (a hitch never comes back as a
-- burst), and how much of a particle's life it keeps its tone before it dries or after it has cooled.
CosmeticConfig.Flow = { MaxStepSeconds = 0.1, HoldShare = 0.3 }

-- Where the floor is under a body with no Humanoid to say so: this far below its root.
CosmeticConfig.FloorDepth = 3

-- The light core's path: a small comet of colour going round the chest, never inside the body.
local CORE_PATH: Place = { Kind = "Orbit", Radius = 1.9, Height = 0.6, Seconds = 2.8, Bob = 0.4 }

-- Aura styles: what hangs around a body, standing or moving. tests/Cosmetics.spec.luau holds the catalogue,
-- this data and CosmeticController to each other.
CosmeticConfig.AuraStyles = {
	-- Motes of colour rising round the body, knees to crown.
	Motes = {
		Emissions = {
			{
				Texture = "DustMote",
				Place = { Kind = "Ring", Radius = 1.8, Low = -2.2, High = 1.2 },
				Rate = 12,
				Lifetime = { 1.5, 2 },
				Speed = { 0.4, 1 },
				Emit = "Up",
				Spread = 20,
				Size = { 0.55, 0.7, 0 },
				Transparency = { 0.3, 0, 1 },
				Rise = 1.2,
			},
		},
	},
	-- Graphite: the same column, each mote catching the light three times as it climbs.
	Glints = {
		Emissions = {
			{
				Texture = "DustMote",
				Place = { Kind = "Ring", Radius = 1.8, Low = -2.4, High = 1.4 },
				Rate = 14,
				Lifetime = { 1.4, 2 },
				Speed = { 0.3, 0.8 },
				Emit = "Up",
				Spread = 15,
				Size = { 0.5, 0.65, 0 },
				Transparency = { 0.25, 0, 1 },
				Rise = 1.4,
				Glint = 0.3,
				Flickers = 3,
			},
		},
	},
	-- Leaves torn from a manuscript, turning as they rise.
	Pages = {
		Emissions = {
			{
				Texture = "PaperScrap",
				Place = { Kind = "Ring", Radius = 2, Low = -2.2, High = 1 },
				Rate = 6,
				Lifetime = { 2.2, 2.8 },
				Speed = { 0.5, 1.1 },
				Emit = "Up",
				Spread = 30,
				Size = { 0.8, 1, 0.7 },
				Transparency = { 0.2, 0, 1 },
				Rise = 0.5,
				Spin = 120,
			},
		},
	},
	-- Embers leaving the feet in a column, cooling to soot as they climb.
	Soot = {
		Emissions = {
			{
				Texture = "SmokeSoft",
				Place = { Kind = "Feet", Radius = 1.1, Lift = 0.3 },
				Rate = 16,
				Lifetime = { 1.1, 1.6 },
				Speed = { 2.5, 4 },
				Emit = "Up",
				Spread = 15,
				Size = { 0.5, 0.8, 0.3 },
				Transparency = { 0.1, 0.15, 1 },
				Drag = 0.9,
				Rise = 0.4,
				Spin = 90,
				Dries = 0.85,
			},
		},
	},
	-- Tongues of ink rising from the feet and darkening as the air takes them.
	Wisps = {
		Emissions = {
			{
				Texture = "SmokeSoft",
				Place = { Kind = "Feet", Radius = 0.9, Lift = 0.2 },
				Rate = 6,
				Lifetime = { 1.6, 2.1 },
				Speed = { 1.6, 2.6 },
				Emit = "Up",
				Spread = 18,
				Size = { 0.9, 1.8, 2.4 },
				Transparency = { 0.6, 0.25, 1 },
				Drag = 0.7,
				Spin = 40,
				Dries = 0.55,
			},
		},
	},
	-- A column of coloured smoke, wide and slow, left behind when the body runs.
	Plume = {
		Emissions = {
			{
				Texture = "SmokeSoft",
				Place = { Kind = "Feet", Radius = 1.3, Lift = 0.4 },
				Rate = 7,
				Lifetime = { 1.8, 2.4 },
				Speed = { 1.2, 2 },
				Emit = "Up",
				Spread = 25,
				Size = { 1.4, 2.6, 3.4 },
				Transparency = { 0.7, 0.3, 1 },
				Drag = 0.5,
				Rise = 0.3,
				Spin = 30,
				Dries = 0.3,
			},
		},
	},
	-- Drops falling from both hands, drawn long as they fall.
	Drips = {
		Emissions = {
			{
				Texture = "InkBlot",
				Place = { Kind = "Hands", Radius = 1.3, Height = -0.8, Depth = -0.2 },
				Rate = 14,
				Lifetime = { 0.5, 0.7 },
				Speed = { 0, 0.4 },
				Emit = "Down",
				Spread = 10,
				Size = { 0.45, 0.35 },
				Transparency = { 0, 0.1, 0.8 },
				Rise = -22,
				Stretch = 1.4,
			},
		},
	},
	-- A wet blot spreading on the floor under the feet and soaking away. It does not dry darker: lapis
	-- darkened toward ink passes within reach of Indigo (tests/Cosmetics.spec.luau measured 46).
	Pool = {
		Emissions = {
			{
				Texture = "InkBlot",
				Place = { Kind = "Floor", Lift = 0.06 },
				Rate = 2,
				Lifetime = { 1.6, 2 },
				Speed = { 0.05, 0.05 },
				Emit = "Up",
				Size = { 1.4, 4.2 },
				Transparency = { 0.3, 0.35, 1 },
				Spin = 12,
				Flat = true,
			},
		},
	},
	-- Two gilt strokes traced round the body, a glyph drawn in the air forever.
	Orbit = {
		Ribbons = {
			{
				Path = { Kind = "Orbit", Radius = 2.1, Height = 0, Seconds = 2.4, Bob = 0.9 },
				Count = 2,
				Width = 0.55,
				Lifetime = 0.5,
				Transparency = 0,
				Dries = 0.35,
				FaceCamera = true,
			},
		},
	},
	-- Two pen lines looping round the body without ever lifting.
	Scrawl = {
		Ribbons = {
			{
				Path = { Kind = "Scrawl", Radius = 1.9, Height = 0.2, Seconds = 1.6, Bob = 1.3 },
				Count = 2,
				Width = 0.45,
				Lifetime = 0.7,
				Transparency = 0,
				Dries = 0.5,
				FaceCamera = true,
			},
		},
	},
	-- Ink flicked off a scribbling pen, flying out and falling.
	Spatter = {
		Emissions = {
			{
				Texture = "InkBlot",
				Place = { Kind = "Ring", Radius = 1.6, Low = -1.2, High = 1.2 },
				Rate = 14,
				Lifetime = { 0.5, 0.8 },
				Speed = { 3, 6 },
				Emit = "Out",
				Spread = 25,
				Size = { 0.45, 0.3 },
				Transparency = { 0, 0.1, 1 },
				Rise = -14,
				Stretch = 0.8,
			},
		},
	},
	-- Flakes of gold leaf drifting down from above the head, flashing as they turn.
	Leaf = {
		Emissions = {
			{
				Texture = "PaperScrap",
				Place = { Kind = "Ring", Radius = 1.9, Low = 0.6, High = 2.6 },
				Rate = 9,
				Lifetime = { 2, 2.6 },
				Speed = { 0.2, 0.5 },
				Emit = "Down",
				Spread = 40,
				Size = { 0.45, 0.5, 0.4 },
				Transparency = { 0.2, 0, 1 },
				Drag = 0.6,
				Rise = -0.3,
				Spin = 200,
				Glint = 0.4,
				Flickers = 4,
			},
		},
	},
	-- A seal pressed into the floor under the feet, turning as it fades: the ring the game's casts open.
	Seal = {
		Emissions = {
			{
				Texture = "SealRing",
				Place = { Kind = "Floor", Lift = 0.1 },
				Rate = 1.2,
				Lifetime = { 1.8, 2.2 },
				Speed = { 0.05, 0.05 },
				Emit = "Up",
				Size = { 3.2, 4.4 },
				Transparency = { 0.7, 0.25, 1 },
				Spin = 25,
				Flat = true,
			},
		},
	},
	-- Colour drawn in from all round the body and swallowed, blackening as it goes.
	Inward = {
		Emissions = {
			{
				Texture = "SmokeSoft",
				Place = { Kind = "Ring", Radius = 3.2, Low = -2.2, High = 1.4 },
				Rate = 22,
				Lifetime = { 0.8, 1 },
				Speed = { 2.2, 2.8 },
				Emit = "In",
				Spread = 10,
				Size = { 0.9, 0.3 },
				Transparency = { 0.6, 0.1, 1 },
				Spin = 60,
				Dries = 0.7,
			},
		},
	},
	-- The light core: a halo of its tone and, over it, a small heart heated toward white -- never white, and
	-- never alone on the page (a pale core on vellum is a pale smudge, D-119) -- going round the chest.
	Core = {
		Core = true,
		Emissions = {
			{
				Texture = "DustMote",
				Place = CORE_PATH,
				Rate = 20,
				Lifetime = { 0.4, 0.5 },
				Speed = { 0, 0 },
				Emit = "Up",
				Size = { 1.2, 0.3 },
				Transparency = { 0.15, 1 },
			},
			{
				Texture = "DustMote",
				Place = CORE_PATH,
				Rate = 20,
				Lifetime = { 0.25, 0.3 },
				Speed = { 0, 0 },
				Emit = "Up",
				Size = { 0.6, 0.15 },
				Transparency = { 0, 1 },
				Front = true,
				Heat = 0.45,
				Glow = 0.6,
			},
		},
	},
} :: { [string]: Style }

-- Trail styles: what a body leaves when it moves. Their particles are emitted only while it does.
CosmeticConfig.TrailStyles = {
	-- A band of colour the height of the body, standing behind it, a little darker at its tail (no further:
	-- lapis dried by half toward ink is 48 from Indigo).
	Stroke = {
		Ribbons = {
			{
				Path = { Kind = "Behind", Height = 0, Depth = 0.4 },
				Count = 1,
				Width = 1.8,
				Lifetime = 0.4,
				Transparency = 0.1,
				Dries = 0.2,
				FaceCamera = false,
			},
		},
	},
	-- One bright line at the waist, the stroke of a stylus.
	Hairline = {
		Ribbons = {
			{
				Path = { Kind = "Behind", Height = 0.3, Depth = 0.45 },
				Count = 1,
				Width = 0.35,
				Lifetime = 0.55,
				Transparency = 0,
				FaceCamera = true,
			},
		},
	},
	-- Two lines scribbled up and down behind the runner, out of step with each other.
	Scrawl = {
		Ribbons = {
			{
				Path = { Kind = "Behind", Height = 0.8, Gap = 1.2, Depth = 0.45, Seconds = 0.5, Bob = 0.35 },
				Count = 2,
				Width = 0.3,
				Lifetime = 0.55,
				Transparency = 0,
				Dries = 0.4,
				FaceCamera = true,
			},
		},
	},
	-- Embers kicked up by the feet, cooling to soot.
	Soot = {
		Emissions = {
			{
				Texture = "SmokeSoft",
				Place = { Kind = "Feet", Radius = 0.5, Lift = 0.3 },
				Rate = 14,
				Lifetime = { 0.6, 0.9 },
				Speed = { 0.8, 1.8 },
				Emit = "Up",
				Spread = 35,
				Size = { 0.6, 1.1, 0.6 },
				Transparency = { 0.15, 0.3, 1 },
				Drag = 0.8,
				Spin = 60,
				Dries = 0.85,
			},
		},
	},
	-- Scraps of coloured leaf kicked up and falling back.
	Scraps = {
		Emissions = {
			{
				Texture = "PaperScrap",
				Place = { Kind = "Feet", Radius = 0.6, Lift = 0.2 },
				Rate = 5,
				Lifetime = { 1, 1.4 },
				Speed = { 2, 3.5 },
				Emit = "Up",
				Spread = 40,
				Size = { 0.6, 0.5 },
				Transparency = { 0, 0, 1 },
				Drag = 1.4,
				Rise = -2,
				Spin = 200,
			},
		},
	},
	-- Pumice dust puffing up from each step.
	Dust = {
		Emissions = {
			{
				Texture = "SmokeSoft",
				Place = { Kind = "Feet", Radius = 0.6, Lift = 0.15 },
				Rate = 12,
				Lifetime = { 0.6, 1 },
				Speed = { 1, 2.2 },
				Emit = "Up",
				Spread = 55,
				Size = { 0.5, 1.2 },
				Transparency = { 0.3, 1 },
				Drag = 1.5,
				Rise = -0.6,
				Spin = 40,
			},
		},
	},
	-- Drops flicked off the stroke, falling behind the runner.
	Flecks = {
		Emissions = {
			{
				Texture = "InkBlot",
				Place = { Kind = "Behind", Low = -0.6, High = 0.8, Depth = 0.5 },
				Rate = 8,
				Lifetime = { 0.5, 0.7 },
				Speed = { 1, 2 },
				Emit = "Down",
				Spread = 45,
				Size = { 0.45, 0.3 },
				Transparency = { 0, 0.1, 1 },
				Rise = -16,
				Stretch = 1.2,
			},
		},
	},
} :: { [string]: Style }

-- A skin's Look.Shade moves its glyph's pigment toward ink or page, inside PigmentConfig.ShadeRange: the
-- measured range in which every school stays its own (PigmentConfig.shade).

CosmeticConfig.ById = {} :: { [string]: CosmeticDef }
for _, item in ipairs(CosmeticConfig.Items) do
	CosmeticConfig.ById[item.Id] = item
end

CosmeticConfig.Slots = { "Aura", "Trail", "KillEffect", "Title", "Skin" } :: { Slot }

-- Equipped slot key for a cosmetic (skins are per glyph).
function CosmeticConfig.slotKey(item: CosmeticDef): string
	if item.Slot == "Skin" then
		return "Skin:" .. tostring(item.Target)
	end
	return item.Slot
end

return CosmeticConfig
