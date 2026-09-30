--!strict
-- The Ex-libris: the plates a player earns once in a lifetime and keeps (docs/GAME_DESIGN.md §9). Pure data: no
-- require, no Roblox global.
--
-- Each plate reads one measure of the profile, counted by the services that own it, never by a client:
--   Kills              ProfileData.Stats.Kills: every foe defeated, a training dummy and a Forger included
--   MatchesPlayed      Stats.MatchesPlayed
--   GlyphsCast         Stats.GlyphsCast: glyphs the server accepted
--   BestChain          Stats.BestChain: the longest chain ever drawn
--   BossKills          Stats.BossKills: the Erasure defeated in its event (a practice never counts)
--   KitCalligraphy     the kit's drills at Calligraphy (ProfileData.Drills, DrillConfig.Kit)
--   DrillsFairCopy     drills at Fair copy or better
--   DrillsCalligraphy  drills at Calligraphy
-- HonoursService grants a plate the moment its measure reaches its target, once: its Folios, and for four of them a
-- title (CosmeticConfig, reward only). docs/ECONOMY.md §2 counts what they add.

export type Measure =
	"Kills"
	| "MatchesPlayed"
	| "GlyphsCast"
	| "BestChain"
	| "BossKills"
	| "KitCalligraphy"
	| "DrillsFairCopy"
	| "DrillsCalligraphy"

export type Plate = {
	Id: string,
	NameKey: string,
	DescKey: string,
	Measure: Measure,
	Target: number,
	Folios: number,
	Title: string?,
}

local ExLibrisConfig = {}

-- In the order the Lectern lists them. An id is a storage key (ProfileData.ExLibris): never rename one.
ExLibrisConfig.Plates = {
	{
		Id = "Erasures100",
		NameKey = "exlibris.Erasures100",
		DescKey = "exlibris.desc.Kills",
		Measure = "Kills",
		Target = 100,
		Folios = 150,
	},
	{
		Id = "Erasures1000",
		NameKey = "exlibris.Erasures1000",
		DescKey = "exlibris.desc.Kills",
		Measure = "Kills",
		Target = 1000,
		Folios = 500,
		Title = "TitleThousandErasures",
	},
	{
		Id = "Pages25",
		NameKey = "exlibris.Pages25",
		DescKey = "exlibris.desc.MatchesPlayed",
		Measure = "MatchesPlayed",
		Target = 25,
		Folios = 150,
	},
	{
		Id = "Pages250",
		NameKey = "exlibris.Pages250",
		DescKey = "exlibris.desc.MatchesPlayed",
		Measure = "MatchesPlayed",
		Target = 250,
		Folios = 500,
		Title = "TitleDogEared",
	},
	{
		Id = "Strokes1000",
		NameKey = "exlibris.Strokes1000",
		DescKey = "exlibris.desc.GlyphsCast",
		Measure = "GlyphsCast",
		Target = 1000,
		Folios = 150,
	},
	{
		Id = "Strokes10000",
		NameKey = "exlibris.Strokes10000",
		DescKey = "exlibris.desc.GlyphsCast",
		Measure = "GlyphsCast",
		Target = 10000,
		Folios = 500,
	},
	{
		Id = "Breath4",
		NameKey = "exlibris.Breath4",
		DescKey = "exlibris.desc.BestChain",
		Measure = "BestChain",
		Target = 4,
		Folios = 150,
	},
	{
		Id = "Breath6",
		NameKey = "exlibris.Breath6",
		DescKey = "exlibris.desc.BestChain",
		Measure = "BestChain",
		Target = 6,
		Folios = 400,
		Title = "TitleOneBreath",
	},
	{
		Id = "Erasure1",
		NameKey = "exlibris.Erasure1",
		DescKey = "exlibris.desc.BossKills",
		Measure = "BossKills",
		Target = 1,
		Folios = 150,
	},
	{
		Id = "Erasure10",
		NameKey = "exlibris.Erasure10",
		DescKey = "exlibris.desc.BossKills",
		Measure = "BossKills",
		Target = 10,
		Folios = 500,
	},
	{
		Id = "SteadyKit",
		NameKey = "exlibris.SteadyKit",
		DescKey = "exlibris.desc.KitCalligraphy",
		Measure = "KitCalligraphy",
		Target = 3,
		Folios = 200,
	},
	{
		Id = "Copyist",
		NameKey = "exlibris.Copyist",
		DescKey = "exlibris.desc.DrillsFairCopy",
		Measure = "DrillsFairCopy",
		Target = 10,
		Folios = 250,
	},
	{
		Id = "Calligrapher",
		NameKey = "exlibris.Calligrapher",
		DescKey = "exlibris.desc.DrillsCalligraphy",
		Measure = "DrillsCalligraphy",
		Target = 20,
		Folios = 600,
		Title = "TitleCalligrapher",
	},
} :: { Plate }

-- How often HonoursService reads every loaded profile for a plate newly earned. The measures move in half a dozen
-- services; reading them on one slow accumulator catches every one of them without a hook in any.
ExLibrisConfig.CheckSeconds = 2

return ExLibrisConfig
