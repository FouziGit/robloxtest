--!strict
-- Glyph roster. Pure data (no requires, no Roblox globals) so tests can validate it under Lune.
-- The 28 glyphs of docs/GAME_DESIGN.md §5: the 8 V1 glyphs (unlocked by default) first, then the
-- 12 Phase 2 additions grouped by pigment, then the 8 of the second roster (D-145). Cost, Cooldown and
-- Damage come straight from that table; every other number a server effect or a client renderer needs
-- lives in Params, so no effect ever carries a magic constant.
--
-- Field reference (see Types.GlyphDef):
--   Id           stable identifier (persisted in loadouts/unlocks): never rename
--   Pigment      primary pigment (cast sound, skins, interactions of GAME_DESIGN §6)
--   Combo        pigment sequence, 2..4 entries (GameConfig.Combo.MinLength..MaxLength)
--   Cost         ink spent on cast
--   Cooldown     seconds before the same glyph can be cast again
--   Damage       per hit (or per tick with Params.Ticks); an Ultimate with Params.TickDamage: Damage is its
--                opening hit, TickDamage each tick
--   Range        studs; reach of the effect: projectile / hitscan travel, AoE radius, forward
--                offset of a zone centre, dash or teleport distance, aura radius of a self buff
--   Archetype    Projectile | Aoe | Zone | Wall | Mobility | Counter | Ultimate | Buff
--                (Ultimate breaks guards through CombatConfig.Block.BrokenBy)
--   Effect       server effect function id (GlyphEffects)
--   VfxId        client rendering id (VfxConfig); the sound is the pigment's, named by the timeline
--   Unlock       {Kind="Default"} | {Kind="Level", Value=n} | {Kind="Pigment", Value=0}
--                ("Pigment" = gated by the glyph's own pigment, Orpiment at
--                ProgressionConfig.OrpimentUnlockLevel or through its game pass)
--   Params       effect-specific tuning, all numeric

export type Unlock = { Kind: "Default" | "Level" | "Pigment", Value: number? }

export type GlyphDef = {
	Id: string,
	Pigment: string,
	Combo: { string },
	Cost: number,
	Cooldown: number,
	Damage: number,
	Range: number,
	Archetype: string,
	Effect: string,
	VfxId: string,
	Unlock: Unlock,
	NameKey: string,
	DescriptionKey: string,
	Params: { [string]: number },
}

local GlyphConfig = {}

GlyphConfig.Glyphs = {
	-- V1 roster: unlocked for every new profile
	{
		Id = "Brand",
		Pigment = "Cinnabar",
		Combo = { "Cinnabar", "Cinnabar" },
		Cost = 20,
		Cooldown = 4,
		Damage = 25,
		Range = 90,
		Archetype = "Projectile",
		Effect = "Brand",
		VfxId = "Brand",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Brand.name",
		DescriptionKey = "glyph.Brand.desc",
		-- Windup: seconds between the throw's packet and the projectile leaving the hand, which is the
		-- client's gather (VfxTimelineConfig BRAND, D-114).
		Params = { Speed = 90, BlastRadius = 7, Fuse = 1.0, SpawnOffset = 4, Windup = 0.06 },
	},
	{
		Id = "Wash",
		Pigment = "Indigo",
		Combo = { "Indigo", "Indigo" },
		Cost = 22,
		Cooldown = 5,
		Damage = 18,
		Range = 40,
		Archetype = "Aoe",
		Effect = "Wash",
		VfxId = "Wash",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Wash.name",
		DescriptionKey = "glyph.Wash.desc",
		Params = { TravelTime = 0.8, HitRadius = 8, SpawnOffset = 6, Knockback = 30 },
	},
	{
		Id = "Serif",
		Pigment = "Umber",
		Combo = { "Umber", "Umber" },
		Cost = 22,
		Cooldown = 5,
		Damage = 22,
		Range = 31,
		Archetype = "Aoe",
		Effect = "Serif",
		VfxId = "Serif",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Serif.name",
		DescriptionKey = "glyph.Serif.desc",
		Params = { Count = 5, Spacing = 5, StartOffset = 6, HitRadius = 5, StepDelay = 0.08, Stun = 0.4 },
	},
	{
		Id = "Sweep",
		Pigment = "Verdigris",
		Combo = { "Verdigris", "Verdigris" },
		Cost = 15,
		Cooldown = 3,
		Damage = 12,
		Range = 12,
		Archetype = "Aoe",
		Effect = "Sweep",
		VfxId = "Sweep",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Sweep.name",
		DescriptionKey = "glyph.Sweep.desc",
		Params = { Radius = 12, Offset = 10, Push = 70, Lift = 30 },
	},
	{
		Id = "Bleed",
		Pigment = "Indigo",
		Combo = { "Indigo", "Cinnabar" },
		Cost = 28,
		Cooldown = 8,
		Damage = 8,
		Range = 12,
		Archetype = "Zone",
		Effect = "Bleed",
		VfxId = "Bleed",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Bleed.name",
		DescriptionKey = "glyph.Bleed.desc",
		Params = { Radius = 9, Ticks = 3, TickInterval = 1, SlowFactor = 0.4, SlowDuration = 2.5, Offset = 12 },
	},
	{
		-- Indigo combo, Umber pigment: the wall is the Umber half of GAME_DESIGN §6 ("Umber blocks").
		Id = "Margin",
		Pigment = "Umber",
		Combo = { "Indigo", "Indigo", "Umber" },
		Cost = 30,
		Cooldown = 10,
		Damage = 0,
		Range = 8,
		Archetype = "Wall",
		Effect = "Margin",
		VfxId = "Margin",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Margin.name",
		DescriptionKey = "glyph.Margin.desc",
		Params = { Duration = 6, Width = 14, Height = 9, Thickness = 2.5, Offset = 8 },
	},
	{
		Id = "Scorch",
		Pigment = "Cinnabar",
		Combo = { "Cinnabar", "Cinnabar", "Verdigris" },
		Cost = 35,
		Cooldown = 12,
		Damage = 10,
		Range = 13,
		Archetype = "Zone",
		Effect = "Scorch",
		VfxId = "Scorch",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Scorch.name",
		DescriptionKey = "glyph.Scorch.desc",
		Params = { Radius = 13, Ticks = 3, TickInterval = 0.8 },
	},
	{
		Id = "Rupture",
		Pigment = "Umber",
		Combo = { "Umber", "Umber", "Umber" },
		Cost = 45,
		Cooldown = 15,
		Damage = 35,
		Range = 18,
		Archetype = "Ultimate",
		Effect = "Rupture",
		VfxId = "Rupture",
		Unlock = { Kind = "Default" },
		NameKey = "glyph.Rupture.name",
		DescriptionKey = "glyph.Rupture.desc",
		Params = { Radius = 18, Launch = 60, Stun = 0.8 },
	},

	-- Cinnabar additions
	{
		-- Short forward dash (Range studs in DashDuration) that drops TrailSegments burning pools
		-- along the path; each pool ticks Ticks times, and a single target burns at most
		-- MaxHitsPerTarget times per cast (6 x 2 = 12 damage, GAME_DESIGN's 6 per crossing).
		Id = "Ligature",
		Pigment = "Cinnabar",
		Combo = { "Cinnabar", "Verdigris" },
		Cost = 15,
		Cooldown = 6,
		Damage = 6,
		Range = 20,
		Archetype = "Mobility",
		Effect = "Ligature",
		VfxId = "Ligature",
		Unlock = { Kind = "Level", Value = 10 },
		NameKey = "glyph.Ligature.name",
		DescriptionKey = "glyph.Ligature.desc",
		Params = {
			DashDuration = 0.25,
			TrailSegments = 5,
			TrailSpacing = 4,
			TrailRadius = 5,
			Ticks = 5,
			TickInterval = 0.4,
			MaxHitsPerTarget = 2,
		},
	},
	{
		-- Heavy arcing projectile: travels at Speed along a bell of ArcHeight studs, detonates on
		-- the first hit or when Fuse expires (BlastRadius, "Explosion" vfx) and breaks guards.
		Id = "Blot",
		Pigment = "Cinnabar",
		Combo = { "Cinnabar", "Cinnabar", "Umber" },
		Cost = 50,
		Cooldown = 20,
		-- Forty, not forty-five: a Cinnabar hit on a Fanned target is multiplied by 1.25
		-- (CombatConfig.Status.Fanned), and forty-five became fifty-six -- over the ceiling
		-- docs/GAME_DESIGN.md §5 states for an ultimate. Forty lands at exactly fifty on a marked target,
		-- which is the ceiling, and tests/Config.spec.luau now holds every ultimate to its AMPLIFIED hit.
		Damage = 40,
		Range = 75,
		Archetype = "Ultimate",
		Effect = "Blot",
		VfxId = "Blot",
		Unlock = { Kind = "Level", Value = 25 },
		NameKey = "glyph.Blot.name",
		DescriptionKey = "glyph.Blot.desc",
		Params = {
			Speed = 55,
			ArcHeight = 20,
			BlastRadius = 10,
			Fuse = 1.4,
			SpawnOffset = 5,
			Knockback = 45,
			Lift = 30,
		},
	},

	-- Indigo additions
	{
		-- Grabs MaxTargets target(s) inside a sphere of HitRadius centred Offset studs ahead and
		-- roots them: MovementService.applySlow(id, RootSlowFactor, RootDuration) pins WalkSpeed at
		-- zero while leaving the victim able to fight back (see docs/DECISIONS.md).
		Id = "Binding",
		Pigment = "Indigo",
		Combo = { "Indigo", "Verdigris" },
		Cost = 30,
		Cooldown = 12,
		Damage = 10,
		Range = 15,
		Archetype = "Counter",
		Effect = "Binding",
		VfxId = "Binding",
		Unlock = { Kind = "Level", Value = 10 },
		NameKey = "glyph.Binding.name",
		DescriptionKey = "glyph.Binding.desc",
		Params = { Offset = 8, HitRadius = 7, MaxTargets = 1, RootDuration = 1.5, RootSlowFactor = 0 },
	},

	-- Umber additions
	{
		-- Fast direct-hit projectile (no blast): Speed studs/s for at most Fuse seconds, damages the
		-- first model within HitRadius of the ray and slows it to SlowFactor for SlowDuration.
		Id = "Stipple",
		Pigment = "Umber",
		Combo = { "Umber", "Indigo" },
		Cost = 18,
		Cooldown = 4,
		Damage = 16,
		Range = 70,
		Archetype = "Projectile",
		Effect = "Stipple",
		VfxId = "Stipple",
		Unlock = { Kind = "Level", Value = 5 },
		NameKey = "glyph.Stipple.name",
		DescriptionKey = "glyph.Stipple.desc",
		Params = { Speed = 110, Fuse = 0.9, SpawnOffset = 4, HitRadius = 4, SlowFactor = 0.6, SlowDuration = 2 },
	},
	{
		-- Self buff, no target scan: the effect grants the CombatConfig.Status.Gilding buff, which
		-- owns every number (damage reduction, duration, knockback immunity) because CombatService
		-- reads it in ApplyDamage. Range is the aura radius the client renders around the caster.
		Id = "Gilding",
		Pigment = "Umber",
		Combo = { "Umber", "Verdigris" },
		Cost = 25,
		Cooldown = 14,
		Damage = 0,
		Range = 6,
		Archetype = "Buff",
		Effect = "Gilding",
		VfxId = "Gilding",
		Unlock = { Kind = "Level", Value = 15 },
		NameKey = "glyph.Gilding.name",
		DescriptionKey = "glyph.Gilding.desc",
		Params = {},
	},

	-- Verdigris additions
	{
		-- Fast direct-hit projectile; being a Verdigris glyph it marks its target Fanned
		-- (CombatConfig.Status.Fanned) through CombatService, which amplifies the next Cinnabar hit.
		Id = "Hairline",
		Pigment = "Verdigris",
		Combo = { "Verdigris", "Cinnabar" },
		Cost = 15,
		Cooldown = 3,
		Damage = 14,
		Range = 60,
		Archetype = "Projectile",
		Effect = "Hairline",
		VfxId = "Hairline",
		Unlock = { Kind = "Level", Value = 5 },
		NameKey = "glyph.Hairline.name",
		DescriptionKey = "glyph.Hairline.desc",
		Params = { Speed = 130, Fuse = 0.6, SpawnOffset = 4, HitRadius = 3.5, Knockback = 14 },
	},
	{
		-- Zone centred Offset studs ahead (Range = that offset). Every tick it damages and drags
		-- targets toward the centre at PullSpeed, ignoring those already closer than PullMinDistance.
		Id = "Spiral",
		Pigment = "Verdigris",
		Combo = { "Verdigris", "Verdigris", "Indigo" },
		Cost = 35,
		Cooldown = 12,
		Damage = 6,
		Range = 14,
		Archetype = "Zone",
		Effect = "Spiral",
		VfxId = "Spiral",
		Unlock = { Kind = "Level", Value = 20 },
		NameKey = "glyph.Spiral.name",
		DescriptionKey = "glyph.Spiral.desc",
		Params = { Radius = 11, Offset = 14, Ticks = 4, TickInterval = 0.6, PullSpeed = 35, PullMinDistance = 3 },
	},
	{
		Id = "Pounce",
		Pigment = "Verdigris",
		Combo = { "Verdigris", "Verdigris", "Umber" },
		Cost = 30,
		Cooldown = 10,
		Damage = 5,
		Range = 14,
		Archetype = "Zone",
		Effect = "Pounce",
		VfxId = "Pounce",
		Unlock = { Kind = "Level", Value = 15 },
		NameKey = "glyph.Pounce.name",
		DescriptionKey = "glyph.Pounce.desc",
		Params = { Radius = 13, Offset = 14, Ticks = 3, TickInterval = 0.9, SlowFactor = 0.7, SlowDuration = 1.5 },
	},

	-- Orpiment: sidegrade pigment, gated by PigmentConfig.Unlockable
	{
		-- Hitscan: one ray from SpawnOffset studs ahead of the caster out to Range, damaging the
		-- MaxTargets nearest models within HitRadius of that ray. No travel time, no Speed.
		Id = "Strike",
		Pigment = "Orpiment",
		Combo = { "Orpiment", "Orpiment" },
		Cost = 20,
		Cooldown = 4,
		Damage = 22,
		Range = 70,
		Archetype = "Projectile",
		Effect = "Strike",
		VfxId = "Strike",
		Unlock = { Kind = "Pigment", Value = 0 },
		NameKey = "glyph.Strike.name",
		DescriptionKey = "glyph.Strike.desc",
		Params = { SpawnOffset = 3, HitRadius = 3, MaxTargets = 1, Knockback = 18 },
	},
	{
		-- Teleport: the server raycasts Range studs forward, stops WallBackoffStuds short of the
		-- first obstruction, checks ClearanceRadius around the destination and snaps it down by at
		-- most GroundSnapStuds so the caster never lands inside geometry or over the void.
		Id = "Caret",
		Pigment = "Orpiment",
		Combo = { "Orpiment", "Verdigris" },
		Cost = 20,
		Cooldown = 7,
		Damage = 0,
		Range = 18,
		Archetype = "Mobility",
		Effect = "Caret",
		VfxId = "Caret",
		Unlock = { Kind = "Pigment", Value = 0 },
		NameKey = "glyph.Caret.name",
		DescriptionKey = "glyph.Caret.desc",
		Params = { IFrameSeconds = 0.4, WallBackoffStuds = 3, ClearanceRadius = 2.5, GroundSnapStuds = 12 },
	},
	{
		Id = "Watermark",
		Pigment = "Orpiment",
		Combo = { "Orpiment", "Orpiment", "Umber" },
		Cost = 35,
		Cooldown = 12,
		Damage = 6,
		Range = 13,
		Archetype = "Zone",
		Effect = "Watermark",
		VfxId = "Watermark",
		Unlock = { Kind = "Pigment", Value = 0 },
		NameKey = "glyph.Watermark.name",
		DescriptionKey = "glyph.Watermark.desc",
		Params = { Radius = 12, Offset = 13, Ticks = 4, TickInterval = 0.7, StunSeconds = 0.18 },
	},
	{
		-- Hitscan to the first target, then arcs to the nearest untouched model within ChainRadius
		-- of the previous one until ChainCount models have been struck. Stuns every link.
		Id = "Colophon",
		Pigment = "Orpiment",
		Combo = { "Orpiment", "Orpiment", "Orpiment", "Orpiment" },
		Cost = 55,
		Cooldown = 25,
		Damage = 40,
		Range = 60,
		Archetype = "Ultimate",
		Effect = "Colophon",
		VfxId = "Colophon",
		Unlock = { Kind = "Pigment", Value = 0 },
		NameKey = "glyph.Colophon.name",
		DescriptionKey = "glyph.Colophon.desc",
		Params = { SpawnOffset = 3, HitRadius = 5, ChainCount = 3, ChainRadius = 26, StunSeconds = 0.6, Knockback = 25 },
	},

	-- Second roster (D-145): one glyph for each two-key recipe left free, an Indigo ultimate and an Umber
	-- three-key. Two of them charge and one rushes, which holds the caster (the channel, D-142).
	{
		-- Charged melee: winds Windup s in the hand (a channel: no M1, no glyph, a dash drops it), then strikes
		-- the nearest body it may damage within HitRadius of a point Offset ahead of where the caster stands at
		-- the release: hurled away (Knockback, Lift) and stunned StunSeconds. Range = Offset + HitRadius.
		Id = "Volute",
		Pigment = "Indigo",
		Combo = { "Indigo", "Umber" },
		Cost = 25,
		Cooldown = 6,
		Damage = 24,
		Range = 8,
		Archetype = "Aoe",
		Effect = "Volute",
		VfxId = "Volute",
		Unlock = { Kind = "Level", Value = 8 },
		NameKey = "glyph.Volute.name",
		DescriptionKey = "glyph.Volute.desc",
		Params = {
			Windup = 0.4,
			Offset = 4,
			HitRadius = 4,
			MaxTargets = 1,
			Knockback = 80,
			Lift = 25,
			StunSeconds = 0.4,
		},
	},
	{
		-- Charged hitscan: aim locked at the press, caster rooted (ChargeSlowFactor) and channelled for Windup s;
		-- then one ray from SpawnOffset ahead of the PRESS point (or from the wall in that gap, D-144) to Range or
		-- the first wall, damaging up to MaxTargets bodies within HitRadius of it and pushing them along the aim.
		-- A caster carried more than ReleaseDriftStuds off the press point by the release has lost the charge
		-- (D-141): the client's round trip at a run, the slack the origin check also gives an action.
		Id = "Rubric",
		Pigment = "Cinnabar",
		Combo = { "Cinnabar", "Indigo" },
		Cost = 24,
		Cooldown = 6,
		Damage = 25,
		Range = 85,
		Archetype = "Projectile",
		Effect = "Rubric",
		VfxId = "Rubric",
		Unlock = { Kind = "Level", Value = 33 },
		NameKey = "glyph.Rubric.name",
		DescriptionKey = "glyph.Rubric.desc",
		Params = {
			Windup = 0.7,
			ChargeSlowFactor = 0,
			SpawnOffset = 3,
			HitRadius = 4,
			MaxTargets = 3,
			Knockback = 30,
			ReleaseDriftStuds = 6,
		},
	},
	{
		-- A flourish along the ground: its front moves at Speed from SpawnOffset to Range, stopping at the first
		-- wall (a Margin included, and one inside the SpawnOffset gap, D-144), damaging once every body its
		-- Width x Height box sweeps (Depth deep) and pushing it along the aim.
		Id = "Swash",
		Pigment = "Umber",
		Combo = { "Umber", "Cinnabar" },
		Cost = 25,
		Cooldown = 7,
		Damage = 20,
		Range = 45,
		Archetype = "Aoe",
		Effect = "Swash",
		VfxId = "Swash",
		Unlock = { Kind = "Level", Value = 12 },
		NameKey = "glyph.Swash.name",
		DescriptionKey = "glyph.Swash.desc",
		Params = { Speed = 75, SpawnOffset = 4, Width = 12, Height = 5, Depth = 3, Knockback = 35, Lift = 12 },
	},
	{
		-- Teleports behind the nearest body within Range and ConeDegrees of the aim that it may damage now
		-- (canDamage, D-143) and can see, BehindStuds past its back (validated like the Caret: ground within
		-- GroundSnapStuds, ClearanceRadius free), then strikes its back and pushes it away. No target: nothing
		-- happens, and the ink stays spent (the Caret's rule, D-146).
		Id = "Dagger",
		Pigment = "Verdigris",
		Combo = { "Verdigris", "Umber" },
		Cost = 25,
		Cooldown = 10,
		Damage = 14,
		Range = 25,
		Archetype = "Mobility",
		Effect = "Dagger",
		VfxId = "Dagger",
		Unlock = { Kind = "Level", Value = 28 },
		NameKey = "glyph.Dagger.name",
		DescriptionKey = "glyph.Dagger.desc",
		Params = {
			ConeDegrees = 35,
			BehindStuds = 3,
			ClearanceRadius = 2,
			GroundSnapStuds = 12,
			IFrameSeconds = 0.2,
			Knockback = 14,
		},
	},
	{
		-- Ultimate frame fixed at the cast point: a seal of Damage on everything within Radius (it breaks guards,
		-- and its StunSeconds is the only stun), then Ticks ticks every TickInterval of TickDamage that never
		-- break a guard and slow whoever they hurt (D-140). Stops ticking when its caster is stunned, guards or dies.
		Id = "Cartouche",
		Pigment = "Indigo",
		Combo = { "Indigo", "Indigo", "Indigo", "Indigo" },
		Cost = 50,
		Cooldown = 20,
		Damage = 28,
		Range = 16,
		Archetype = "Ultimate",
		Effect = "Cartouche",
		VfxId = "Cartouche",
		Unlock = { Kind = "Level", Value = 36 },
		NameKey = "glyph.Cartouche.name",
		DescriptionKey = "glyph.Cartouche.desc",
		Params = {
			Radius = 16,
			StunSeconds = 0.4,
			Ticks = 5,
			TickInterval = 0.8,
			TickDamage = 4,
			SlowFactor = 0.5,
			SlowDuration = 1,
		},
	},
	{
		-- Instant blast centred on the caster: everything within Radius is damaged once and thrown horizontally
		-- away (Push, plus Lift). No stun, no guard break: the three-key "get off me", under the Rupture.
		Id = "Emboss",
		Pigment = "Umber",
		Combo = { "Umber", "Umber", "Verdigris" },
		Cost = 35,
		Cooldown = 12,
		Damage = 24,
		Range = 13,
		Archetype = "Aoe",
		Effect = "Emboss",
		VfxId = "Emboss",
		Unlock = { Kind = "Level", Value = 30 },
		NameKey = "glyph.Emboss.name",
		DescriptionKey = "glyph.Emboss.desc",
		Params = { Radius = 13, Push = 100, Lift = 25 },
	},
	{
		-- A stitch thrown at Speed for at most Fuse s (a projectile a Margin stops, one inside the SpawnOffset gap
		-- included, D-144): the first body it meets is damaged, dragged to PullStopStuds of the caster in
		-- PullSeconds and rooted (RootSlowFactor) for RootDuration. Speed x Fuse = Range.
		Id = "Stitch",
		Pigment = "Verdigris",
		Combo = { "Verdigris", "Indigo" },
		Cost = 25,
		Cooldown = 10,
		Damage = 10,
		Range = 32,
		Archetype = "Counter",
		Effect = "Stitch",
		VfxId = "Stitch",
		Unlock = { Kind = "Level", Value = 22 },
		NameKey = "glyph.Stitch.name",
		DescriptionKey = "glyph.Stitch.desc",
		Params = {
			Speed = 100,
			Fuse = 0.32,
			SpawnOffset = 3,
			HitRadius = 3,
			PullSeconds = 0.35,
			PullStopStuds = 4,
			RootSlowFactor = 0,
			RootDuration = 0.8,
		},
	},
	{
		-- A channelled rush (no M1, no glyph; a dash ends it, D-142): Ticks strokes every TickInterval (above
		-- CombatConfig.Hit.IFrameSeconds, the per-glyph hit memory, with a frame to spare), each in a Width x
		-- Height box Range deep in front of the caster's validated frame. Strokes slow; the last one launches
		-- (FinisherPush, FinisherLift) and stuns.
		Id = "Hatching",
		Pigment = "Cinnabar",
		Combo = { "Cinnabar", "Umber" },
		Cost = 25,
		Cooldown = 7,
		Damage = 5,
		Range = 7,
		Archetype = "Aoe",
		Effect = "Hatching",
		VfxId = "Hatching",
		Unlock = { Kind = "Level", Value = 18 },
		NameKey = "glyph.Hatching.name",
		DescriptionKey = "glyph.Hatching.desc",
		Params = {
			Ticks = 5,
			TickInterval = 0.34,
			Width = 6,
			Height = 6,
			SlowFactor = 0.35,
			SlowDuration = 0.45,
			FinisherPush = 45,
			FinisherLift = 35,
			StunSeconds = 0.4,
		},
	},
} :: { GlyphDef }

-- Indexes built once at load.
GlyphConfig.ById = {} :: { [string]: GlyphDef }
for _, glyph in ipairs(GlyphConfig.Glyphs) do
	GlyphConfig.ById[glyph.Id] = glyph
end

-- Recipes for ComboResolver ({Id, Combo} pairs).
local byId: { [string]: GlyphDef } = {}
for _, def in ipairs(GlyphConfig.Glyphs) do
	byId[def.Id] = def
end

-- The definition of `id`, or nil. Built once at load: the grade asks it whether a cast could have hit
-- anything at all (MatchService), which is a question per cast.
function GlyphConfig.byId(id: string): GlyphDef?
	return byId[id]
end

-- True when a glyph deals no damage at all -- a wall, a buff, a teleport. It cannot land a hit, so it is
-- neither a hit nor a miss: counting one as a miss made every use of the three structural answers of
-- docs/GAME_DESIGN.md §5 bis lower the player's execution grade exactly like a whiff.
function GlyphConfig.isUtility(id: string): boolean
	local def = byId[id]
	return def ~= nil and def.Damage <= 0
end

-- What one body takes from a whole cast, which is what the loadout card shows: one hit for most glyphs, every
-- tick of a zone and every stroke of a rush (Params.Ticks, capped by MaxHitsPerTarget for a trail a body crosses
-- twice at most), and for an ultimate that opens with a hit and ticks after it (Params.TickDamage, D-140) that hit
-- plus its ticks -- the Cartouche's 48, not its seal's 28. tests/Config.spec.luau counts a cast the same way, on
-- its own, for the damage budgets.
function GlyphConfig.castDamage(def: GlyphDef): number
	local params = def.Params
	local tickDamage = params.TickDamage
	if tickDamage ~= nil then
		return def.Damage + tickDamage * (params.Ticks or 0)
	end
	return def.Damage * (params.MaxHitsPerTarget or params.Ticks or 1)
end

function GlyphConfig.recipes(): { { Id: string, Combo: { string } } }
	local recipes = {}
	for _, glyph in ipairs(GlyphConfig.Glyphs) do
		table.insert(recipes, { Id = glyph.Id, Combo = glyph.Combo })
	end
	return recipes
end

-- Ids unlocked for a brand-new profile.
function GlyphConfig.defaultUnlocks(): { string }
	local ids = {}
	for _, glyph in ipairs(GlyphConfig.Glyphs) do
		if glyph.Unlock.Kind == "Default" then
			table.insert(ids, glyph.Id)
		end
	end
	return ids
end

-- Ids a player unlocks on reaching `level` (see ProgressionService).
function GlyphConfig.unlocksForLevel(level: number): { string }
	local ids = {}
	for _, glyph in ipairs(GlyphConfig.Glyphs) do
		if glyph.Unlock.Kind == "Level" and glyph.Unlock.Value == level then
			table.insert(ids, glyph.Id)
		end
	end
	return ids
end

-- Every glyph a level unlocks, with that level, in the roster's order: the glyphs of the level road
-- (Pure/LevelRoad), which the Result card and the Lectern read and HonoursService pays beside.
function GlyphConfig.levelUnlocks(): { { Id: string, NameKey: string, Level: number } }
	local unlocks = {}
	for _, glyph in ipairs(GlyphConfig.Glyphs) do
		local level = glyph.Unlock.Value
		if glyph.Unlock.Kind == "Level" and level ~= nil then
			table.insert(unlocks, { Id = glyph.Id, NameKey = glyph.NameKey, Level = level })
		end
	end
	return unlocks
end

-- Ids gated by `pigment` (Orpiment): granted with the pigment itself, never before.
function GlyphConfig.unlocksForPigment(pigment: string): { string }
	local ids = {}
	for _, glyph in ipairs(GlyphConfig.Glyphs) do
		if glyph.Unlock.Kind == "Pigment" and glyph.Pigment == pigment then
			table.insert(ids, glyph.Id)
		end
	end
	return ids
end

return GlyphConfig
