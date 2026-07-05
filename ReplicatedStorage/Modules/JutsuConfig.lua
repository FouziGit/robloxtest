--[[
	JutsuConfig.lua — ModuleScript
	EMPLACEMENT : ReplicatedStorage > Modules > JutsuConfig

	Base de données des Jutsus. Pour AJOUTER UN JUTSU :
	  1. Ajoute une entrée dans JutsuConfig.Jutsus ci-dessous
	  2. Ajoute la fonction d'effet correspondante (champ "Effect")
	     dans ServerScriptService > Modules > JutsuEffects
	C'est tout : le client (détection de combo, HUD) et le serveur
	(validation, cooldown, XP) se construisent automatiquement dessus.

	Chaque jutsu :
	  Id          : identifiant unique (string, sans espaces)
	  Name        : nom affiché au joueur
	  Combo       : séquence de mantras { "Feu" | "Eau" | "Terre" | "Vent" }
	  Damage      : dégâts de base (utilisé par JutsuEffects)
	  Cooldown    : secondes avant de pouvoir relancer CE jutsu
	  XPReward    : XP donnée au lanceur quand le jutsu part avec succès
	                (même sans toucher de cible — un joueur peut donc farmer
	                en lançant dans le vide ; mets 0 pour réserver l'XP aux
	                kills si tu veux l'empêcher)
	  Effect      : nom de la fonction dans JutsuEffects (côté serveur)
	  Description : texte d'aide
]]

local JutsuConfig = {}

JutsuConfig.Jutsus = {
	{
		Id = "BouleDeFeu",
		Name = "Boule de Feu",
		Combo = { "Feu", "Feu" },
		Damage = 25,
		Cooldown = 4,
		XPReward = 15,
		Effect = "Fireball",
		Description = "Projette une sphère de flammes qui explose à l'impact.",
	},
	{
		Id = "VagueAquatique",
		Name = "Vague Aquatique",
		Combo = { "Eau", "Eau" },
		Damage = 18,
		Cooldown = 5,
		XPReward = 15,
		Effect = "WaterWave",
		Description = "Une vague déferle devant toi et balaie les ennemis.",
	},
	{
		Id = "PiquesDeTerre",
		Name = "Piques de Terre",
		Combo = { "Terre", "Terre" },
		Damage = 22,
		Cooldown = 5,
		XPReward = 15,
		Effect = "EarthSpikes",
		Description = "Des piques rocheuses jaillissent du sol en ligne droite.",
	},
	{
		Id = "RafaleTranchante",
		Name = "Rafale Tranchante",
		Combo = { "Vent", "Vent" },
		Damage = 12,
		Cooldown = 3,
		XPReward = 10,
		Effect = "WindGust",
		Description = "Un cône de vent repousse violemment les ennemis proches.",
	},
	{
		Id = "BrumeBouillante",
		Name = "Brume Bouillante",
		Combo = { "Eau", "Feu" },
		Damage = 8, -- par tick (3 ticks)
		Cooldown = 8,
		XPReward = 20,
		Effect = "BoilingMist",
		Description = "Un nuage brûlant qui blesse et ralentit les ennemis à l'intérieur.",
	},
	{
		Id = "MurDeBoue",
		Name = "Mur de Boue",
		Combo = { "Eau", "Eau", "Terre" },
		Damage = 0,
		Cooldown = 10,
		XPReward = 25,
		Effect = "MudWall",
		Description = "Érige un mur de boue défensif devant toi pendant 8 secondes.",
	},
	{
		Id = "TempeteDeBraises",
		Name = "Tempête de Braises",
		Combo = { "Feu", "Feu", "Vent" },
		Damage = 10, -- par tick (3 ticks)
		Cooldown = 12,
		XPReward = 30,
		Effect = "EmberStorm",
		Description = "Un anneau de braises tourbillonne autour de toi et brûle tout.",
	},
	{
		Id = "Seisme",
		Name = "Séisme",
		Combo = { "Terre", "Terre", "Terre" },
		Damage = 35,
		Cooldown = 15,
		XPReward = 35,
		Effect = "Earthquake",
		Description = "Frappe le sol : onde de choc massive qui projette les ennemis en l'air.",
	},
}

----------------------------------------------------------------
-- INDEX AUTOMATIQUES (ne pas modifier)
----------------------------------------------------------------

-- Transforme une séquence {"Eau","Eau","Terre"} en clé "Eau-Eau-Terre"
function JutsuConfig.GetComboKey(sequence)
	return table.concat(sequence, "-")
end

-- ByCombo["Eau-Eau-Terre"] -> définition du jutsu
JutsuConfig.ByCombo = {}

-- ById["MurDeBoue"] -> définition du jutsu
JutsuConfig.ById = {}

-- PrefixSet["Eau-Eau"] = true si une recette PLUS LONGUE commence ainsi.
-- Le client s'en sert : si la séquence tapée est un jutsu ET un préfixe,
-- il attend (le joueur veut peut-être un combo plus long) ; sinon il lance direct.
JutsuConfig.PrefixSet = {}

for _, jutsu in ipairs(JutsuConfig.Jutsus) do
	local key = JutsuConfig.GetComboKey(jutsu.Combo)
	if JutsuConfig.ByCombo[key] then
		warn(("[JutsuConfig] Combo en double : %s (%s et %s)"):format(key, JutsuConfig.ByCombo[key].Id, jutsu.Id))
	end
	JutsuConfig.ByCombo[key] = jutsu
	JutsuConfig.ById[jutsu.Id] = jutsu

	for i = 1, #jutsu.Combo - 1 do
		local prefix = table.concat(jutsu.Combo, "-", 1, i)
		JutsuConfig.PrefixSet[prefix] = true
	end
end

return JutsuConfig
