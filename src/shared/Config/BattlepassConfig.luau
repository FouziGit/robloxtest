--!strict
-- Battle pass: 50 tiers per season, free track + premium track. Pure data.
-- Reward kinds: {Kind="Ryo", Amount=n} | {Kind="Cosmetic", Id="…"} | {Kind="XpBoost", Minutes=n}

export type Reward =
	{ Kind: "Ryo", Amount: number }
	| { Kind: "Cosmetic", Id: string }
	| { Kind: "XpBoost", Minutes: number }
export type Tier = { Free: Reward?, Premium: Reward? }

local BattlepassConfig = {}

BattlepassConfig.MaxTier = 50

-- XP needed to go from tier n to n+1. Total for 50 tiers = 100 + 120 + … = 28,420 → with the V2
-- income of ~600-900 pass XP per match, the pass takes ≈ 35-45 matches (5-7 h) to complete.
function BattlepassConfig.xpForTier(tier: number): number
	return 100 + (tier - 1) * 20
end

local function ryo(amount: number): Reward
	return { Kind = "Ryo", Amount = amount }
end

local function cosmetic(id: string): Reward
	return { Kind = "Cosmetic", Id = id }
end

local function boost(minutes: number): Reward
	return { Kind = "XpBoost", Minutes = minutes }
end

-- Free track: the V1 rewards (cosmetic ids re-identified in English, see DataMigration).
-- Premium track: doubled Ryo, extra cosmetics and boosts.
BattlepassConfig.Seasons = {
	S1 = {
		Tiers = {
			{ Free = ryo(50), Premium = ryo(100) },
			{ Free = ryo(60), Premium = boost(30) },
			{ Free = ryo(70), Premium = ryo(150) },
			{ Free = ryo(80), Premium = ryo(150) },
			{ Free = cosmetic("BlankHeadband"), Premium = cosmetic("TrailEmber") },
			{ Free = ryo(90), Premium = ryo(200) },
			{ Free = ryo(100), Premium = boost(30) },
			{ Free = ryo(110), Premium = ryo(200) },
			{ Free = ryo(120), Premium = ryo(250) },
			{ Free = cosmetic("SteelStylus"), Premium = cosmetic("AuraCrimson") },
			{ Free = ryo(130), Premium = ryo(250) },
			{ Free = ryo(140), Premium = boost(60) },
			{ Free = ryo(150), Premium = ryo(300) },
			{ Free = ryo(160), Premium = ryo(300) },
			{ Free = cosmetic("PalimpsestCape"), Premium = cosmetic("KillEffectShatter") },
			{ Free = ryo(170), Premium = ryo(350) },
			{ Free = ryo(180), Premium = boost(60) },
			{ Free = ryo(190), Premium = ryo(350) },
			{ Free = ryo(200), Premium = ryo(400) },
			{ Free = cosmetic("FrisketMask"), Premium = cosmetic("TitleShadow") },
			{ Free = ryo(220), Premium = ryo(400) },
			{ Free = ryo(240), Premium = boost(60) },
			{ Free = ryo(260), Premium = ryo(450) },
			{ Free = ryo(280), Premium = ryo(450) },
			{ Free = cosmetic("BlueInkAura"), Premium = cosmetic("SkinBrandAzure") },
			{ Free = ryo(300), Premium = ryo(500) },
			{ Free = ryo(320), Premium = boost(90) },
			{ Free = ryo(340), Premium = ryo(500) },
			{ Free = ryo(360), Premium = ryo(550) },
			{ Free = cosmetic("ScriptoriumRobe"), Premium = cosmetic("TrailStorm") },
			{ Free = ryo(380), Premium = ryo(550) },
			{ Free = ryo(400), Premium = boost(90) },
			{ Free = ryo(420), Premium = ryo(600) },
			{ Free = ryo(440), Premium = ryo(600) },
			{ Free = cosmetic("VioletInkAura"), Premium = cosmetic("SkinRuptureMagma") },
			{ Free = ryo(460), Premium = ryo(650) },
			{ Free = ryo(480), Premium = boost(120) },
			{ Free = ryo(500), Premium = ryo(650) },
			{ Free = ryo(550), Premium = ryo(700) },
			{ Free = cosmetic("ScribeCloak"), Premium = cosmetic("KillEffectRedaction") },
			{ Free = ryo(600), Premium = ryo(750) },
			{ Free = ryo(650), Premium = boost(120) },
			{ Free = ryo(700), Premium = ryo(800) },
			{ Free = ryo(750), Premium = ryo(850) },
			{ Free = cosmetic("GoldenInkAura"), Premium = cosmetic("TitleCodex") },
			{ Free = ryo(800), Premium = ryo(900) },
			{ Free = ryo(900), Premium = boost(180) },
			{ Free = ryo(1000), Premium = ryo(1000) },
			{ Free = ryo(1250), Premium = ryo(1500) },
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
