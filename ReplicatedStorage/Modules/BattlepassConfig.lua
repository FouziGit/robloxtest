--[[
	BattlepassConfig.lua — ModuleScript
	EMPLACEMENT : ReplicatedStorage > Modules > BattlepassConfig

	Définition du Battlepass : courbe d'XP par palier et récompenses
	des paliers 1 à 50. Pour MODIFIER une récompense, édite simplement
	l'entrée correspondante dans Rewards. Deux types :
	  { Type = "Currency", Amount = 100 }
	  { Type = "Cosmetic", Id = "MasqueAnbu", Name = "Masque Anbu" }
	Les cosmétiques sont stockés dans le profil (Data.Cosmetics) ;
	à toi de brancher leur apparence en jeu (accessoires, auras...).
]]

local BattlepassConfig = {}

BattlepassConfig.MaxLevel = 50

-- XP nécessaire pour passer du palier n au palier n+1.
function BattlepassConfig.XPForTier(tier)
	return 100 + (tier - 1) * 20
end

-- NOTE : le joueur démarre au palier 1, donc la récompense du palier 1 est
-- un cadeau de bienvenue réclamable immédiatement (choix de game design —
-- ça apprend au joueur le geste "ouvrir le pass et réclamer" dès la 1re
-- session). Atteindre le palier N débloque la récompense N ; la courbe
-- XPForTier(N) donne le coût du passage N -> N+1.
BattlepassConfig.Rewards = {
	[1]  = { Type = "Currency", Amount = 50 },
	[2]  = { Type = "Currency", Amount = 60 },
	[3]  = { Type = "Currency", Amount = 70 },
	[4]  = { Type = "Currency", Amount = 80 },
	[5]  = { Type = "Cosmetic", Id = "BandeauGenin", Name = "Bandeau du Genin" },
	[6]  = { Type = "Currency", Amount = 90 },
	[7]  = { Type = "Currency", Amount = 100 },
	[8]  = { Type = "Currency", Amount = 110 },
	[9]  = { Type = "Currency", Amount = 120 },
	[10] = { Type = "Cosmetic", Id = "KatanaAcier", Name = "Katana d'Acier" },
	[11] = { Type = "Currency", Amount = 130 },
	[12] = { Type = "Currency", Amount = 140 },
	[13] = { Type = "Currency", Amount = 150 },
	[14] = { Type = "Currency", Amount = 160 },
	[15] = { Type = "Cosmetic", Id = "CapeBrume", Name = "Cape de Brume" },
	[16] = { Type = "Currency", Amount = 170 },
	[17] = { Type = "Currency", Amount = 180 },
	[18] = { Type = "Currency", Amount = 190 },
	[19] = { Type = "Currency", Amount = 200 },
	[20] = { Type = "Cosmetic", Id = "MasqueAnbu", Name = "Masque Anbu" },
	[21] = { Type = "Currency", Amount = 220 },
	[22] = { Type = "Currency", Amount = 240 },
	[23] = { Type = "Currency", Amount = 260 },
	[24] = { Type = "Currency", Amount = 280 },
	[25] = { Type = "Cosmetic", Id = "AuraChakraBleu", Name = "Aura de Chakra Bleu" },
	[26] = { Type = "Currency", Amount = 300 },
	[27] = { Type = "Currency", Amount = 320 },
	[28] = { Type = "Currency", Amount = 340 },
	[29] = { Type = "Currency", Amount = 360 },
	[30] = { Type = "Cosmetic", Id = "KimonoClan", Name = "Kimono du Clan" },
	[31] = { Type = "Currency", Amount = 380 },
	[32] = { Type = "Currency", Amount = 400 },
	[33] = { Type = "Currency", Amount = 420 },
	[34] = { Type = "Currency", Amount = 440 },
	[35] = { Type = "Cosmetic", Id = "AuraChakraViolet", Name = "Aura de Chakra Violet" },
	[36] = { Type = "Currency", Amount = 460 },
	[37] = { Type = "Currency", Amount = 480 },
	[38] = { Type = "Currency", Amount = 500 },
	[39] = { Type = "Currency", Amount = 550 },
	[40] = { Type = "Cosmetic", Id = "ManteauSage", Name = "Manteau de Sage" },
	[41] = { Type = "Currency", Amount = 600 },
	[42] = { Type = "Currency", Amount = 650 },
	[43] = { Type = "Currency", Amount = 700 },
	[44] = { Type = "Currency", Amount = 750 },
	[45] = { Type = "Cosmetic", Id = "AuraChakraDore", Name = "Aura de Chakra Doré" },
	[46] = { Type = "Currency", Amount = 800 },
	[47] = { Type = "Currency", Amount = 900 },
	[48] = { Type = "Currency", Amount = 1000 },
	[49] = { Type = "Currency", Amount = 1250 },
	[50] = { Type = "Cosmetic", Id = "ManteauHokage", Name = "Manteau du Hokage" },
}

-- Texte affiché dans l'interface pour une récompense donnée.
function BattlepassConfig.GetRewardText(reward)
	if reward == nil then
		return "Aucune récompense"
	elseif reward.Type == "Currency" then
		return ("%d Ryo"):format(reward.Amount)
	elseif reward.Type == "Cosmetic" then
		return ("Cosmétique : %s"):format(reward.Name or reward.Id)
	end
	return "Récompense inconnue"
end

return BattlepassConfig
