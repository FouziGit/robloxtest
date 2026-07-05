--[[
	GameConfig.lua — ModuleScript
	EMPLACEMENT : ReplicatedStorage > Modules > GameConfig

	Configuration centrale du jeu, partagée entre le serveur et le client.
	C'est ICI que tu modifies les réglages globaux (touches par défaut,
	XP, timings, noms des remotes). Un seul endroit, zéro duplication.
]]

local GameConfig = {}

----------------------------------------------------------------
-- ÉLÉMENTS (MANTRAS)
----------------------------------------------------------------
-- L'ordre est celui affiché dans le menu Options.
GameConfig.Elements = { "Feu", "Eau", "Terre", "Vent" }

-- Touches par défaut (noms d'Enum.KeyCode). Le joueur peut les
-- réassigner dans le menu Options ; c'est sauvegardé dans son profil.
GameConfig.DefaultKeybinds = {
	Feu = "A",
	Eau = "E",
	Terre = "R",
	Vent = "T",
}

-- Couleurs d'affichage de chaque élément (HUD de combo, menus).
GameConfig.ElementColors = {
	Feu = Color3.fromRGB(235, 90, 40),
	Eau = Color3.fromRGB(60, 140, 235),
	Terre = Color3.fromRGB(150, 105, 60),
	Vent = Color3.fromRGB(170, 220, 190),
}

----------------------------------------------------------------
-- COMBOS / CASTING
----------------------------------------------------------------
GameConfig.ComboMaxLength = 3      -- longueur maximale d'une séquence de mantras
GameConfig.ComboTimeout = 1.5      -- secondes d'inactivité avant validation/reset de la séquence
GameConfig.GlobalCastCooldown = 0.5 -- délai minimal (anti-spam) entre deux lancers, tous jutsus confondus
GameConfig.PvPEnabled = true       -- false = les jutsus ne blessent pas les autres joueurs

----------------------------------------------------------------
-- XP & PROGRESSION
----------------------------------------------------------------
GameConfig.XP = {
	PerEnemyKill = 50,        -- XP par ennemi vaincu (le XP par jutsu est dans JutsuConfig)
	BattlepassMultiplier = 1, -- 1 = chaque point d'XP joueur donne aussi 1 point d'XP Battlepass
}

-- Courbe de niveau du JOUEUR : XP nécessaire pour passer du niveau n au niveau n+1.
-- (La courbe du Battlepass est dans BattlepassConfig.)
function GameConfig.PlayerXPForLevel(level)
	return math.floor(80 * level ^ 1.3)
end

GameConfig.PlayerMaxLevel = 200

----------------------------------------------------------------
-- ENNEMIS
----------------------------------------------------------------
GameConfig.EnemyTag = "Enemy"          -- tag CollectionService qui marque un ennemi
GameConfig.EnemyFolderName = "Enemies" -- tout Model placé dans workspace.Enemies est tagué automatiquement
                                       -- (il lui faut un Humanoid — présent ou ajouté sous 10 s — pour donner l'XP de kill)

----------------------------------------------------------------
-- MONNAIE
----------------------------------------------------------------
GameConfig.CurrencyName = "Ryo"

----------------------------------------------------------------
-- REMOTES (noms uniques, créés par le serveur au démarrage)
----------------------------------------------------------------
GameConfig.Remotes = {
	FolderName = "Remotes",

	-- RemoteFunction : le client demande son profil complet (keybinds, XP, battlepass...)
	GetProfileData = "GetProfileData",

	-- RemoteEvents client -> serveur
	CastJutsu = "CastJutsu",                         -- (sequenceElements: {string})
	UpdateKeybinds = "UpdateKeybinds",               -- (newKeybinds: {[element]: keyName})
	ClaimBattlepassReward = "ClaimBattlepassReward", -- (tier: number)

	-- RemoteEvents serveur -> client
	DataChanged = "DataChanged",     -- (dataSnapshot: table) — pousse le profil à jour
	JutsuFeedback = "JutsuFeedback", -- ({Success: boolean, Message: string})
}

----------------------------------------------------------------
-- TOUCHES AUTORISÉES POUR LE REBIND (liste blanche, validée serveur)
----------------------------------------------------------------
GameConfig.ValidKeybindKeys = {}
do
	-- Lettres A à Z
	for byte = 65, 90 do
		GameConfig.ValidKeybindKeys[string.char(byte)] = true
	end
	-- Quelques touches supplémentaires confortables
	for _, keyName in ipairs({ "F1", "F2", "F3", "F4", "One", "Two", "Three", "Four" }) do
		GameConfig.ValidKeybindKeys[keyName] = true
	end
	-- Touches réservées par l'interface du jeu : jamais assignables
	GameConfig.ValidKeybindKeys["O"] = nil -- menu Options
	GameConfig.ValidKeybindKeys["B"] = nil -- menu Battlepass
	-- Touches de déplacement (QWERTY : WASD / AZERTY : ZQSD) : retirées de
	-- la liste. "A" reste autorisée car c'est le Mantra Feu par défaut du
	-- jeu (aucun conflit sur AZERTY) ; les joueurs en clavier QWERTY, chez
	-- qui A = pas de côté, devraient la réassigner dans le menu Options.
	GameConfig.ValidKeybindKeys["W"] = nil
	GameConfig.ValidKeybindKeys["S"] = nil
	GameConfig.ValidKeybindKeys["D"] = nil
	GameConfig.ValidKeybindKeys["Z"] = nil
	GameConfig.ValidKeybindKeys["Q"] = nil
end

return GameConfig
