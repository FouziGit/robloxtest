--[[
	SoundConfig.lua — ModuleScript
	EMPLACEMENT : ReplicatedStorage > Modules > SoundConfig

	SOURCE UNIQUE de tous les sons du jeu. Tu changes un son ? C'est ICI,
	nulle part ailleurs.

	Par défaut, chaque son pointe vers un son INTÉGRÉ au moteur Roblox
	(`rbxasset://sounds/electronicpingshort.wav`) : il marche TOUJOURS, ne
	peut pas être modéré/supprimé, et je fais varier la hauteur (Speed) pour
	que chaque élément sonne différemment. C'est volontairement sobre pour
	que le jeu ne soit jamais muet ni buggé au premier lancement.

	POUR RENDRE ÇA ÉPIQUE (2 min) :
	  1. Dans Studio : onglet "View" > "Toolbox", ou le Creator Store,
	     onglet "Audio". Filtre sur les sons gratuits.
	  2. Clic droit sur un son > "Copy Asset ID".
	  3. Colle-le ici au format "rbxassetid://123456789" à la place du son
	     par défaut. Exemple : ElementCast.Feu.Id = "rbxassetid://9120386436".
	  Astuce : cherche "fireball", "water splash", "rock impact", "wind",
	  "level up", "hit" pour coller à l'univers.

	Note : si un ID collé ne joue rien, c'est qu'il a été modéré côté Roblox.
	Remets le son par défaut (BUILTIN) ou choisis-en un autre — aucun crash.
]]

local SoundConfig = {}

-- Son intégré au moteur, garanti disponible partout (valeur de secours).
local BUILTIN = "rbxasset://sounds/electronicpingshort.wav"

----------------------------------------------------------------
-- SONS DE LANCER, PAR ÉLÉMENT (joués dans le monde, en 3D/spatial)
----------------------------------------------------------------
SoundConfig.ElementCast = {
	Feu   = { Id = BUILTIN, Volume = 0.6, Speed = 0.70 }, -- grave, agressif
	Eau   = { Id = BUILTIN, Volume = 0.5, Speed = 1.00 },
	Terre = { Id = BUILTIN, Volume = 0.7, Speed = 0.55 }, -- lourd
	Vent  = { Id = BUILTIN, Volume = 0.45, Speed = 1.55 }, -- aigu, léger
}

----------------------------------------------------------------
-- SONS D'ÉVÉNEMENTS (joués localement pour le joueur concerné)
----------------------------------------------------------------
SoundConfig.Event = {
	LevelUp = { Id = BUILTIN, Volume = 0.8, Speed = 1.70 }, -- montée de niveau joueur
	TierUp  = { Id = BUILTIN, Volume = 0.8, Speed = 1.35 }, -- palier Battlepass
	Kill    = { Id = BUILTIN, Volume = 0.6, Speed = 0.90 }, -- ennemi vaincu
	Claim   = { Id = BUILTIN, Volume = 0.7, Speed = 1.50 }, -- récompense récupérée
}

----------------------------------------------------------------
-- MUSIQUE / AMBIANCE (jouée en boucle, localement)
----------------------------------------------------------------
-- Laisse Id = "" pour couper la musique. Colle un ID de musique gratuite
-- (Creator Store > Audio) pour une ambiance de fond.
SoundConfig.Ambient = { Id = "", Volume = 0.25 }

----------------------------------------------------------------
-- FABRIQUE : construit un objet Sound à partir d'une entrée ci-dessus.
-- Retourne nil si l'entrée est vide (Id absent) -> aucun son, pas d'erreur.
----------------------------------------------------------------
function SoundConfig.Build(entry)
	if entry == nil or type(entry.Id) ~= "string" or entry.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.Id
	sound.Volume = entry.Volume or 0.5
	sound.PlaybackSpeed = entry.Speed or 1
	return sound
end

return SoundConfig
