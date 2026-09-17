--!strict
-- Jutsu roster. Pure data (no requires, no Roblox globals) so tests can validate it under Lune.
-- The 20 jutsus of docs/GAME_DESIGN.md §5: the 8 V1 jutsus (unlocked by default) first, then the
-- 12 Phase 2 additions grouped by element. Cost, Cooldown and Damage come straight from that
-- table; every other number a server effect or a client renderer needs lives in Params, so no
-- effect ever carries a magic constant.
--
-- Field reference (see Types.JutsuDef):
--   Id           stable identifier (persisted in loadouts/unlocks): never rename
--   Element      primary element (cast sound, skins, interactions of GAME_DESIGN §6)
--   Combo        element sequence, 2..4 entries (GameConfig.Combo.MinLength..MaxLength)
--   Cost         chakra spent on cast
--   Cooldown     seconds before the same jutsu can be cast again
--   Damage       per hit (or per tick for Zone/Aoe with Params.Ticks)
--   Range        studs; reach of the effect: projectile / hitscan travel, AoE radius, forward
--                offset of a zone centre, dash or teleport distance, aura radius of a self buff
--   Archetype    Projectile | Aoe | Zone | Wall | Mobility | Counter | Ultimate | Buff
--                (Ultimate breaks guards through CombatConfig.Block.BrokenBy)
--   Effect       server effect function id (JutsuEffects)
--   VfxId/SfxId  client rendering ids (VfxConfig / SoundConfig)
--   Unlock       {Kind="Default"} | {Kind="Level", Value=n} | {Kind="Element", Value=0}
--                ("Element" = gated by the jutsu's own element, Lightning at
--                ProgressionConfig.LightningUnlockLevel or through its game pass)
--   Params       effect-specific tuning, all numeric

export type Unlock = { Kind: "Default" | "Level" | "Element", Value: number? }

export type JutsuDef = {
	Id: string,
	Element: string,
	Combo: { string },
	Cost: number,
	Cooldown: number,
	Damage: number,
	Range: number,
	Archetype: string,
	Effect: string,
	VfxId: string,
	SfxId: string,
	Unlock: Unlock,
	NameKey: string,
	DescriptionKey: string,
	Params: { [string]: number },
}

local JutsuConfig = {}

JutsuConfig.Jutsus = {
	-- V1 roster: unlocked for every new profile
	{
		Id = "Fireball",
		Element = "Fire",
		Combo = { "Fire", "Fire" },
		Cost = 20,
		Cooldown = 4,
		Damage = 25,
		Range = 90,
		Archetype = "Projectile",
		Effect = "Fireball",
		VfxId = "Fireball",
		SfxId = "CastFire",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.Fireball.name",
		DescriptionKey = "jutsu.Fireball.desc",
		Params = { Speed = 90, BlastRadius = 7, Fuse = 1.0, SpawnOffset = 4 },
	},
	{
		Id = "WaterWave",
		Element = "Water",
		Combo = { "Water", "Water" },
		Cost = 22,
		Cooldown = 5,
		Damage = 18,
		Range = 40,
		Archetype = "Aoe",
		Effect = "WaterWave",
		VfxId = "WaterWave",
		SfxId = "CastWater",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.WaterWave.name",
		DescriptionKey = "jutsu.WaterWave.desc",
		Params = { TravelTime = 0.8, HitRadius = 8, SpawnOffset = 6, Knockback = 30 },
	},
	{
		Id = "EarthSpikes",
		Element = "Earth",
		Combo = { "Earth", "Earth" },
		Cost = 22,
		Cooldown = 5,
		Damage = 22,
		Range = 31,
		Archetype = "Aoe",
		Effect = "EarthSpikes",
		VfxId = "EarthSpikes",
		SfxId = "CastEarth",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.EarthSpikes.name",
		DescriptionKey = "jutsu.EarthSpikes.desc",
		Params = { Count = 5, Spacing = 5, StartOffset = 6, HitRadius = 5, StepDelay = 0.08, Stun = 0.4 },
	},
	{
		Id = "WindGust",
		Element = "Wind",
		Combo = { "Wind", "Wind" },
		Cost = 15,
		Cooldown = 3,
		Damage = 12,
		Range = 12,
		Archetype = "Aoe",
		Effect = "WindGust",
		VfxId = "WindGust",
		SfxId = "CastWind",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.WindGust.name",
		DescriptionKey = "jutsu.WindGust.desc",
		Params = { Radius = 12, Offset = 10, Push = 70, Lift = 30 },
	},
	{
		Id = "BoilingMist",
		Element = "Water",
		Combo = { "Water", "Fire" },
		Cost = 28,
		Cooldown = 8,
		Damage = 8,
		Range = 12,
		Archetype = "Zone",
		Effect = "BoilingMist",
		VfxId = "BoilingMist",
		SfxId = "CastWater",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.BoilingMist.name",
		DescriptionKey = "jutsu.BoilingMist.desc",
		Params = { Radius = 9, Ticks = 3, TickInterval = 1, SlowFactor = 0.4, SlowDuration = 2.5, Offset = 12 },
	},
	{
		-- Water combo, Earth element: the wall is the Earth half of GAME_DESIGN §6 ("Earth blocks").
		Id = "MudWall",
		Element = "Earth",
		Combo = { "Water", "Water", "Earth" },
		Cost = 30,
		Cooldown = 10,
		Damage = 0,
		Range = 8,
		Archetype = "Wall",
		Effect = "MudWall",
		VfxId = "MudWall",
		SfxId = "CastEarth",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.MudWall.name",
		DescriptionKey = "jutsu.MudWall.desc",
		Params = { Duration = 6, Width = 14, Height = 9, Thickness = 2.5, Offset = 8 },
	},
	{
		Id = "EmberStorm",
		Element = "Fire",
		Combo = { "Fire", "Fire", "Wind" },
		Cost = 35,
		Cooldown = 12,
		Damage = 10,
		Range = 13,
		Archetype = "Zone",
		Effect = "EmberStorm",
		VfxId = "EmberStorm",
		SfxId = "CastFire",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.EmberStorm.name",
		DescriptionKey = "jutsu.EmberStorm.desc",
		Params = { Radius = 13, Ticks = 3, TickInterval = 0.8 },
	},
	{
		Id = "Earthquake",
		Element = "Earth",
		Combo = { "Earth", "Earth", "Earth" },
		Cost = 45,
		Cooldown = 15,
		Damage = 35,
		Range = 18,
		Archetype = "Ultimate",
		Effect = "Earthquake",
		VfxId = "Earthquake",
		SfxId = "CastEarth",
		Unlock = { Kind = "Default" },
		NameKey = "jutsu.Earthquake.name",
		DescriptionKey = "jutsu.Earthquake.desc",
		Params = { Radius = 18, Launch = 60, Stun = 0.8 },
	},

	-- Fire additions
	{
		-- Short forward dash (Range studs in DashDuration) that drops TrailSegments burning pools
		-- along the path; each pool ticks Ticks times, and a single target burns at most
		-- MaxHitsPerTarget times per cast (6 x 2 = 12 damage, GAME_DESIGN's 6 per crossing).
		Id = "EmberStep",
		Element = "Fire",
		Combo = { "Fire", "Wind" },
		Cost = 15,
		Cooldown = 6,
		Damage = 6,
		Range = 20,
		Archetype = "Mobility",
		Effect = "EmberStep",
		VfxId = "EmberStep",
		SfxId = "CastFire",
		Unlock = { Kind = "Level", Value = 10 },
		NameKey = "jutsu.EmberStep.name",
		DescriptionKey = "jutsu.EmberStep.desc",
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
		Id = "Meteor",
		Element = "Fire",
		Combo = { "Fire", "Fire", "Earth" },
		Cost = 50,
		Cooldown = 20,
		Damage = 45,
		Range = 75,
		Archetype = "Ultimate",
		Effect = "Meteor",
		VfxId = "Meteor",
		SfxId = "CastFire",
		Unlock = { Kind = "Level", Value = 25 },
		NameKey = "jutsu.Meteor.name",
		DescriptionKey = "jutsu.Meteor.desc",
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

	-- Water additions
	{
		-- Grabs MaxTargets target(s) inside a sphere of HitRadius centred Offset studs ahead and
		-- roots them: MovementService.applySlow(id, RootSlowFactor, RootDuration) pins WalkSpeed at
		-- zero while leaving the victim able to fight back (see docs/DECISIONS.md).
		Id = "WaterPrison",
		Element = "Water",
		Combo = { "Water", "Wind" },
		Cost = 30,
		Cooldown = 12,
		Damage = 10,
		Range = 15,
		Archetype = "Counter",
		Effect = "WaterPrison",
		VfxId = "WaterPrison",
		SfxId = "CastWater",
		Unlock = { Kind = "Level", Value = 10 },
		NameKey = "jutsu.WaterPrison.name",
		DescriptionKey = "jutsu.WaterPrison.desc",
		Params = { Offset = 8, HitRadius = 7, MaxTargets = 1, RootDuration = 1.5, RootSlowFactor = 0 },
	},

	-- Earth additions
	{
		-- Fast direct-hit projectile (no blast): Speed studs/s for at most Fuse seconds, damages the
		-- first model within HitRadius of the ray and slows it to SlowFactor for SlowDuration.
		Id = "MudShot",
		Element = "Earth",
		Combo = { "Earth", "Water" },
		Cost = 18,
		Cooldown = 4,
		Damage = 16,
		Range = 70,
		Archetype = "Projectile",
		Effect = "MudShot",
		VfxId = "MudShot",
		SfxId = "CastEarth",
		Unlock = { Kind = "Level", Value = 5 },
		NameKey = "jutsu.MudShot.name",
		DescriptionKey = "jutsu.MudShot.desc",
		Params = { Speed = 110, Fuse = 0.9, SpawnOffset = 4, HitRadius = 4, SlowFactor = 0.6, SlowDuration = 2 },
	},
	{
		-- Self buff, no target scan: the effect grants the CombatConfig.Status.StoneSkin buff, which
		-- owns every number (damage reduction, duration, knockback immunity) because CombatService
		-- reads it in ApplyDamage. Range is the aura radius the client renders around the caster.
		Id = "StoneSkin",
		Element = "Earth",
		Combo = { "Earth", "Wind" },
		Cost = 25,
		Cooldown = 14,
		Damage = 0,
		Range = 6,
		Archetype = "Buff",
		Effect = "StoneSkin",
		VfxId = "StoneSkin",
		SfxId = "CastEarth",
		Unlock = { Kind = "Level", Value = 15 },
		NameKey = "jutsu.StoneSkin.name",
		DescriptionKey = "jutsu.StoneSkin.desc",
		Params = {},
	},

	-- Wind additions
	{
		-- Fast direct-hit projectile; being a Wind jutsu it marks its target Fanned
		-- (CombatConfig.Status.Fanned) through CombatService, which amplifies the next Fire hit.
		Id = "WindBlade",
		Element = "Wind",
		Combo = { "Wind", "Fire" },
		Cost = 15,
		Cooldown = 3,
		Damage = 14,
		Range = 60,
		Archetype = "Projectile",
		Effect = "WindBlade",
		VfxId = "WindBlade",
		SfxId = "CastWind",
		Unlock = { Kind = "Level", Value = 5 },
		NameKey = "jutsu.WindBlade.name",
		DescriptionKey = "jutsu.WindBlade.desc",
		Params = { Speed = 130, Fuse = 0.6, SpawnOffset = 4, HitRadius = 3.5, Knockback = 14 },
	},
	{
		-- Zone centred Offset studs ahead (Range = that offset). Every tick it damages and drags
		-- targets toward the centre at PullSpeed, ignoring those already closer than PullMinDistance.
		Id = "Cyclone",
		Element = "Wind",
		Combo = { "Wind", "Wind", "Water" },
		Cost = 35,
		Cooldown = 12,
		Damage = 6,
		Range = 14,
		Archetype = "Zone",
		Effect = "Cyclone",
		VfxId = "Cyclone",
		SfxId = "CastWind",
		Unlock = { Kind = "Level", Value = 20 },
		NameKey = "jutsu.Cyclone.name",
		DescriptionKey = "jutsu.Cyclone.desc",
		Params = { Radius = 11, Offset = 14, Ticks = 4, TickInterval = 0.6, PullSpeed = 35, PullMinDistance = 3 },
	},
	{
		Id = "Sandstorm",
		Element = "Wind",
		Combo = { "Wind", "Wind", "Earth" },
		Cost = 30,
		Cooldown = 10,
		Damage = 5,
		Range = 14,
		Archetype = "Zone",
		Effect = "Sandstorm",
		VfxId = "Sandstorm",
		SfxId = "CastWind",
		Unlock = { Kind = "Level", Value = 15 },
		NameKey = "jutsu.Sandstorm.name",
		DescriptionKey = "jutsu.Sandstorm.desc",
		Params = { Radius = 13, Offset = 14, Ticks = 3, TickInterval = 0.9, SlowFactor = 0.7, SlowDuration = 1.5 },
	},

	-- Lightning: sidegrade element, gated by ElementConfig.Unlockable
	{
		-- Hitscan: one ray from SpawnOffset studs ahead of the caster out to Range, damaging the
		-- MaxTargets nearest models within HitRadius of that ray. No travel time, no Speed.
		Id = "LightningBolt",
		Element = "Lightning",
		Combo = { "Lightning", "Lightning" },
		Cost = 20,
		Cooldown = 4,
		Damage = 22,
		Range = 70,
		Archetype = "Projectile",
		Effect = "LightningBolt",
		VfxId = "LightningBolt",
		SfxId = "CastLightning",
		Unlock = { Kind = "Element", Value = 0 },
		NameKey = "jutsu.LightningBolt.name",
		DescriptionKey = "jutsu.LightningBolt.desc",
		Params = { SpawnOffset = 3, HitRadius = 3, MaxTargets = 1, Knockback = 18 },
	},
	{
		-- Teleport: the server raycasts Range studs forward, stops WallBackoffStuds short of the
		-- first obstruction, checks ClearanceRadius around the destination and snaps it down by at
		-- most GroundSnapStuds so the caster never lands inside geometry or over the void.
		Id = "LightningStep",
		Element = "Lightning",
		Combo = { "Lightning", "Wind" },
		Cost = 20,
		Cooldown = 7,
		Damage = 0,
		Range = 18,
		Archetype = "Mobility",
		Effect = "LightningStep",
		VfxId = "LightningStep",
		SfxId = "CastLightning",
		Unlock = { Kind = "Element", Value = 0 },
		NameKey = "jutsu.LightningStep.name",
		DescriptionKey = "jutsu.LightningStep.desc",
		Params = { IFrameSeconds = 0.4, WallBackoffStuds = 3, ClearanceRadius = 2.5, GroundSnapStuds = 12 },
	},
	{
		Id = "StaticField",
		Element = "Lightning",
		Combo = { "Lightning", "Lightning", "Earth" },
		Cost = 35,
		Cooldown = 12,
		Damage = 6,
		Range = 13,
		Archetype = "Zone",
		Effect = "StaticField",
		VfxId = "StaticField",
		SfxId = "CastLightning",
		Unlock = { Kind = "Element", Value = 0 },
		NameKey = "jutsu.StaticField.name",
		DescriptionKey = "jutsu.StaticField.desc",
		Params = { Radius = 12, Offset = 13, Ticks = 4, TickInterval = 0.7, StunSeconds = 0.18 },
	},
	{
		-- Hitscan to the first target, then arcs to the nearest untouched model within ChainRadius
		-- of the previous one until ChainCount models have been struck. Stuns every link.
		Id = "Raijin",
		Element = "Lightning",
		Combo = { "Lightning", "Lightning", "Lightning", "Lightning" },
		Cost = 55,
		Cooldown = 25,
		Damage = 40,
		Range = 60,
		Archetype = "Ultimate",
		Effect = "Raijin",
		VfxId = "Raijin",
		SfxId = "CastLightning",
		Unlock = { Kind = "Element", Value = 0 },
		NameKey = "jutsu.Raijin.name",
		DescriptionKey = "jutsu.Raijin.desc",
		Params = { SpawnOffset = 3, HitRadius = 5, ChainCount = 3, ChainRadius = 26, StunSeconds = 0.6, Knockback = 25 },
	},
} :: { JutsuDef }

-- Indexes built once at load.
JutsuConfig.ById = {} :: { [string]: JutsuDef }
for _, jutsu in ipairs(JutsuConfig.Jutsus) do
	JutsuConfig.ById[jutsu.Id] = jutsu
end

-- Recipes for ComboResolver ({Id, Combo} pairs).
function JutsuConfig.recipes(): { { Id: string, Combo: { string } } }
	local recipes = {}
	for _, jutsu in ipairs(JutsuConfig.Jutsus) do
		table.insert(recipes, { Id = jutsu.Id, Combo = jutsu.Combo })
	end
	return recipes
end

-- Ids unlocked for a brand-new profile.
function JutsuConfig.defaultUnlocks(): { string }
	local ids = {}
	for _, jutsu in ipairs(JutsuConfig.Jutsus) do
		if jutsu.Unlock.Kind == "Default" then
			table.insert(ids, jutsu.Id)
		end
	end
	return ids
end

-- Ids a player unlocks on reaching `level` (see ProgressionService).
function JutsuConfig.unlocksForLevel(level: number): { string }
	local ids = {}
	for _, jutsu in ipairs(JutsuConfig.Jutsus) do
		if jutsu.Unlock.Kind == "Level" and jutsu.Unlock.Value == level then
			table.insert(ids, jutsu.Id)
		end
	end
	return ids
end

-- Ids gated by `element` (Lightning): granted with the element itself, never before.
function JutsuConfig.unlocksForElement(element: string): { string }
	local ids = {}
	for _, jutsu in ipairs(JutsuConfig.Jutsus) do
		if jutsu.Unlock.Kind == "Element" and jutsu.Element == element then
			table.insert(ids, jutsu.Id)
		end
	end
	return ids
end

return JutsuConfig
