--[[
	DataManager.lua — ModuleScript
	EMPLACEMENT : ServerScriptService > Modules > DataManager

	BASE DE DONNÉES UNIQUE du jeu, désormais propulsée par PROFILESERVICE
	(lib open-source de loleris/MadStudio — la référence communautaire pour
	la sauvegarde Roblox). Un seul profil par joueur contient : touches
	personnalisées, niveau/XP joueur, niveau/XP Battlepass, monnaie,
	récompenses réclamées, cosmétiques, statistiques.

	CE FICHIER EST UN ADAPTATEUR : il garde EXACTEMENT la même interface
	publique qu'avant (LoadProfile / GetProfile / GetDataSnapshot /
	SaveProfile / HandlePlayerRemoving / GetTemplate), donc BattlepassService,
	JutsuService et MainServer n'ont pas changé d'une ligne. Seul le moteur
	de sauvegarde en dessous a changé.

	Ce que ProfileService gère automatiquement (et qu'on n'a plus à coder) :
	  - Verrouillage de session (un seul serveur écrit un profil à la fois)
	  - Sauvegarde auto périodique + à la déconnexion + à la fermeture serveur
	  - Retries robustes sur les requêtes DataStore
	  - Reconciliation : les nouveaux champs du template sont injectés dans
	    les anciens profils
	  - Mode "mock" automatique en Studio sans accès API : le jeu tourne,
	    rien n'est persisté (aucun crash)

	Dépendance : ServerScriptService > Modules > ProfileService (ModuleScript).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local ProfileService = require(script.Parent:WaitForChild("ProfileService"))

local DataManager = {}

----------------------------------------------------------------
-- RÉGLAGES
----------------------------------------------------------------
local PROFILE_STORE_NAME = "JutsuGame_PlayerData_v1"
local KEY_PREFIX = "Player_"

----------------------------------------------------------------
-- TEMPLATE DU PROFIL (source de vérité du schéma)
----------------------------------------------------------------
-- IMPORTANT (contraintes ProfileService/JSON) : uniquement des types
-- sérialisables — nombres, strings, booléens, tableaux denses, tables à
-- clés string. Jamais d'Instances, de Color3/Vector3/CFrame, ni de tables
-- à clés numériques éparses.
local PROFILE_TEMPLATE = {
	DataVersion = 1,

	-- Options : touches personnalisées des Mantras
	Keybinds = {
		Feu = GameConfig.DefaultKeybinds.Feu,
		Eau = GameConfig.DefaultKeybinds.Eau,
		Terre = GameConfig.DefaultKeybinds.Terre,
		Vent = GameConfig.DefaultKeybinds.Vent,
	},

	-- Progression joueur
	PlayerLevel = 1,
	PlayerXP = 0, -- XP accumulée DANS le niveau courant

	-- Battlepass
	BattlepassLevel = 1,
	BattlepassXP = 0, -- XP accumulée DANS le palier courant
	ClaimedRewards = {}, -- { ["5"] = true, ... } — clés STRING (contrainte JSON)

	-- Inventaire
	Currency = 0,
	Cosmetics = {}, -- tableau d'Ids : { "BandeauGenin", ... }

	-- Statistiques
	TotalKills = 0,
	TotalJutsusCast = 0,
}

----------------------------------------------------------------
-- STORE PROFILESERVICE
----------------------------------------------------------------
local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)

----------------------------------------------------------------
-- ÉTAT INTERNE
----------------------------------------------------------------
-- profiles[player] = wrapper conservant l'interface historique :
--   { Data = <table auto-sauvegardée>, CanSave = bool, UserId = number, Profile = <ProfileService.Profile> }
-- wrapper.Data pointe sur profile.Data : toute mutation faite par
-- BattlepassService/JutsuService est donc sauvegardée automatiquement.
local profiles = {}

----------------------------------------------------------------
-- OUTIL
----------------------------------------------------------------
local function deepCopy(source)
	local copy = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function keyFor(userId)
	return KEY_PREFIX .. tostring(userId)
end

----------------------------------------------------------------
-- CHARGEMENT
----------------------------------------------------------------
--[[
	Charge (ou crée) le profil d'un joueur. YIELDS.
	Appelé par MainServer dans PlayerAdded.
	Retourne le wrapper de profil, ou nil si le joueur a été kick / est parti.
]]
function DataManager.LoadProfile(player)
	-- not_released_handler par défaut = "ForceLoad" : si une autre session
	-- détient encore le profil (changement de serveur rapide, crash), il est
	-- récupéré proprement après quelques tentatives.
	local profile = ProfileStore:LoadProfileAsync(keyFor(player.UserId))

	if profile == nil then
		-- Cas très rare : impossible de charger (DataStore HS / chargement annulé).
		player:Kick("Impossible de charger tes données pour l'instant. Réessaie dans une minute.")
		return nil
	end

	profile:AddUserId(player.UserId) -- conformité RGPD
	profile:Reconcile() -- injecte les nouveaux champs du template

	profile:ListenToRelease(function()
		profiles[player] = nil
		-- Si le profil est libéré par une AUTRE session (force-load ailleurs),
		-- on éjecte le joueur pour éviter deux serveurs qui écrivent le même
		-- profil. Sur un départ normal, le joueur est déjà parti : no-op.
		if player:IsDescendantOf(Players) then
			player:Kick("Ta session de jeu a été ouverte ailleurs. Rejoins à nouveau.")
		end
	end)

	if player:IsDescendantOf(Players) then
		local wrapper = {
			Data = profile.Data,
			CanSave = true,
			UserId = player.UserId,
			Profile = profile,
		}
		profiles[player] = wrapper
		return wrapper
	else
		-- Le joueur est parti pendant le chargement : on libère tout de suite.
		profile:Release()
		return nil
	end
end

----------------------------------------------------------------
-- SAUVEGARDE (compatibilité d'interface)
----------------------------------------------------------------
--[[
	ProfileService sauvegarde AUTOMATIQUEMENT (auto-save périodique + à la
	libération du profil). Cette fonction est conservée pour ne pas casser
	l'interface historique ; il n'y a plus de sauvegarde manuelle à déclencher.
	Retourne true si un profil actif existe pour ce joueur.
]]
function DataManager.SaveProfile(player)
	local wrapper = profiles[player]
	if wrapper == nil or wrapper.Profile == nil then
		return false
	end
	return wrapper.Profile:IsActive()
end

----------------------------------------------------------------
-- ACCÈS
----------------------------------------------------------------
-- Retourne le wrapper de profil (ou nil s'il n'est pas/plus chargé).
function DataManager.GetProfile(player)
	return profiles[player]
end

-- Retourne une copie du Data, sûre à envoyer au client.
function DataManager.GetDataSnapshot(player)
	local wrapper = profiles[player]
	if wrapper == nil then
		return nil
	end
	return deepCopy(wrapper.Data)
end

-- Copie du template (utile pour des vérifications côté serveur).
function DataManager.GetTemplate()
	return deepCopy(PROFILE_TEMPLATE)
end

----------------------------------------------------------------
-- CYCLE DE VIE
----------------------------------------------------------------
function DataManager.HandlePlayerRemoving(player)
	local wrapper = profiles[player]
	if wrapper ~= nil and wrapper.Profile ~= nil then
		-- Sauvegarde + libère le verrou de session. ListenToRelease nettoiera
		-- profiles[player] ; on le fait aussi ici par sécurité.
		wrapper.Profile:Release()
	end
	profiles[player] = nil
end

-- Note : l'auto-save périodique et la sauvegarde à la fermeture du serveur
-- (BindToClose) sont gérées EN INTERNE par ProfileService. Rien à câbler ici.

return DataManager
