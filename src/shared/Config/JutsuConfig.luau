--!strict
-- Jutsu roster. Pure data (no requires, no Roblox globals) so tests can validate it under Lune.
-- Phase 1 carries the 8 V1 jutsus with their tuning moved out of effect code; Phase 2 extends the
-- roster to 16+ and adds Lightning (see docs/PLAN.md, docs/GAME_DESIGN.md).
--
-- Field reference (see Types.JutsuDef):
--   Id           stable identifier (persisted in loadouts/unlocks): never rename
--   Element      primary element (cast sound, skins, interactions)
--   Combo        element sequence, 2..4 entries
--   Cost         chakra spent on cast
--   Cooldown     seconds before the same jutsu can be cast again
--   Damage       per hit (or per tick for Zone/Aoe with Params.Ticks)
--   Range        studs; reach of the effect (projectile travel / AoE radius / zone offset)
--   Archetype    Projectile | Aoe | Zone | Wall | Mobility | Counter | Ultimate | Buff
--   Effect       server effect function id (JutsuEffects)
--   VfxId/SfxId  client rendering ids (VfxConfig / SoundConfig)
--   Unlock       {Kind="Default"} | {Kind="Level", Value=n} | {Kind="Element", Value=0}
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
		Params = { Duration = 6, Width = 14, Height = 9, Thickness = 2.5, Offset = 8, Health = 120 },
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

return JutsuConfig
