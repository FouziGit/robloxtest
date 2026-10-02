--!strict
-- Battle pass: 50 tiers per season, free track + premium track. Pure data.
-- Reward kinds: {Kind="Folios", Amount=n} | {Kind="Cosmetic", Id="…"} | {Kind="XpBoost", Minutes=n}

export type Reward =
	{ Kind: "Folios", Amount: number }
	| { Kind: "Cosmetic", Id: string }
	| { Kind: "XpBoost", Minutes: number }
export type Tier = { Free: Reward?, Premium: Reward? }

local BattlepassConfig = {}

BattlepassConfig.MaxTier = 50

-- XP needed to go from tier n to n+1: 1,200 for the first, 80 more for each after, 152,880 for the whole pass. A
-- pass lasts a Volume, not a week (E10-S5): scripts/pacing.luau, playing the real configs, finishes it on day 34
-- at 20 minutes a day of duels, day 41 at 20 minutes a day alone, and day 15 at an hour a day of duels, and
-- tests/Pacing.spec.luau holds those days between 28 and 42, and past 14.
function BattlepassConfig.xpForTier(tier: number): number
	return 1200 + (tier - 1) * 80
end

local function folios(amount: number): Reward
	return { Kind = "Folios", Amount = amount }
end

local function cosmetic(id: string): Reward
	return { Kind = "Cosmetic", Id = id }
end

local function boost(minutes: number): Reward
	return { Kind = "XpBoost", Minutes = minutes }
end

-- Free track: the V1 rewards (cosmetic ids re-identified in English, see DataMigration).
-- Premium track: doubled Folios, extra cosmetics and boosts.
BattlepassConfig.Seasons = {
	S1 = {
		Tiers = {
			{ Free = folios(50), Premium = folios(100) },
			{ Free = folios(60), Premium = boost(30) },
			{ Free = folios(70), Premium = folios(150) },
			{ Free = folios(80), Premium = folios(150) },
			{ Free = cosmetic("BlankHeadband"), Premium = cosmetic("TrailEmber") },
			{ Free = folios(90), Premium = folios(200) },
			{ Free = folios(100), Premium = boost(30) },
			{ Free = folios(110), Premium = folios(200) },
			{ Free = folios(120), Premium = folios(250) },
			{ Free = cosmetic("SteelStylus"), Premium = cosmetic("AuraCrimson") },
			{ Free = folios(130), Premium = folios(250) },
			{ Free = folios(140), Premium = boost(60) },
			{ Free = folios(150), Premium = folios(300) },
			{ Free = folios(160), Premium = folios(300) },
			{ Free = cosmetic("PalimpsestCape"), Premium = cosmetic("KillEffectShatter") },
			{ Free = folios(170), Premium = folios(350) },
			{ Free = folios(180), Premium = boost(60) },
			{ Free = folios(190), Premium = folios(350) },
			{ Free = folios(200), Premium = folios(400) },
			{ Free = cosmetic("FrisketMask"), Premium = cosmetic("TitleShadow") },
			{ Free = folios(220), Premium = folios(400) },
			{ Free = folios(240), Premium = boost(60) },
			{ Free = folios(260), Premium = folios(450) },
			{ Free = folios(280), Premium = folios(450) },
			{ Free = cosmetic("BlueInkAura"), Premium = cosmetic("SkinBrandAzure") },
			{ Free = folios(300), Premium = folios(500) },
			{ Free = folios(320), Premium = boost(90) },
			{ Free = folios(340), Premium = folios(500) },
			{ Free = folios(360), Premium = folios(550) },
			{ Free = cosmetic("ScriptoriumRobe"), Premium = cosmetic("TrailStorm") },
			{ Free = folios(380), Premium = folios(550) },
			{ Free = folios(400), Premium = boost(90) },
			{ Free = folios(420), Premium = folios(600) },
			{ Free = folios(440), Premium = folios(600) },
			{ Free = cosmetic("VioletInkAura"), Premium = cosmetic("SkinRuptureMagma") },
			{ Free = folios(460), Premium = folios(650) },
			{ Free = folios(480), Premium = boost(120) },
			{ Free = folios(500), Premium = folios(650) },
			{ Free = folios(550), Premium = folios(700) },
			{ Free = cosmetic("ScribeCloak"), Premium = cosmetic("KillEffectRedaction") },
			{ Free = folios(600), Premium = folios(750) },
			{ Free = folios(650), Premium = boost(120) },
			{ Free = folios(700), Premium = folios(800) },
			{ Free = folios(750), Premium = folios(850) },
			{ Free = cosmetic("GoldenInkAura"), Premium = cosmetic("TitleCodex") },
			{ Free = folios(800), Premium = folios(900) },
			{ Free = folios(900), Premium = boost(180) },
			{ Free = folios(1000), Premium = folios(1000) },
			{ Free = folios(1250), Premium = folios(1500) },
			{ Free = cosmetic("CodexCloak"), Premium = cosmetic("AuraCodex") },
		},
	},
} :: { [string]: { Tiers: { Tier } } }

function BattlepassConfig.getTier(seasonId: string, tier: number): Tier?
	local season = BattlepassConfig.Seasons[seasonId]
	if season == nil then
		return nil
	end
	return season.Tiers[tier]
end

return BattlepassConfig
