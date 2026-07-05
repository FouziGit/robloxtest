--[[
	JutsuService.lua — ModuleScript
	EMPLACEMENT : ServerScriptService > Modules > JutsuService

	Cerveau serveur du système de Jutsus :
	  - Valide la séquence de mantras envoyée par le client (types,
	    longueur, éléments valides) — un exploiteur ne peut rien injecter
	  - Résout le combo via JutsuConfig et vérifie les cooldowns
	    (par jutsu + anti-spam global)
	  - Exécute l'effet côté serveur (JutsuEffects)
	  - Crédite l'XP du jutsu via BattlepassService
	  - Valide et sauvegarde les changements de touches (Options)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local JutsuConfig = require(Modules:WaitForChild("JutsuConfig"))
local SoundConfig = require(Modules:WaitForChild("SoundConfig"))

local JutsuEffects = require(script.Parent:WaitForChild("JutsuEffects"))

local JutsuService = {}

-- Injectés par MainServer via Init()
local DataManager = nil
local BattlepassService = nil
local feedbackRemote = nil
local dataChangedRemote = nil

-- État par joueur (mémoire serveur uniquement)
local cooldowns = {}      -- [Player] = { [jutsuId] = os.clock() de fin de cooldown }
local lastCastAt = {}     -- [Player] = os.clock() du dernier lancer (anti-spam global)
local lastKeybindAt = {}  -- [Player] = os.clock() du dernier rebind (anti-spam remote)

local KEYBIND_DEBOUNCE = 0.5

-- Ensemble des éléments valides, dérivé de la config.
local validElements = {}
for _, element in ipairs(GameConfig.Elements) do
	validElements[element] = true
end

----------------------------------------------------------------
-- INITIALISATION
----------------------------------------------------------------
function JutsuService.Init(deps)
	DataManager = deps.DataManager
	BattlepassService = deps.BattlepassService
	feedbackRemote = deps.FeedbackRemote
	dataChangedRemote = deps.DataChangedRemote
end

local function sendFeedback(player, success, message)
	feedbackRemote:FireClient(player, { Success = success, Message = message })
end

-- Joue le son de lancer à l'emplacement du personnage (spatial : tous les
-- joueurs proches l'entendent). Le son est choisi selon le 1er élément du combo.
local function playCastSound(character, jutsu)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end
	local element = jutsu.Combo[1]
	local sound = SoundConfig.Build(SoundConfig.ElementCast[element])
	if sound == nil then
		return
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 120
	sound.Parent = rootPart
	sound:Play()
	Debris:AddItem(sound, 4)
end

----------------------------------------------------------------
-- LANCER DE JUTSU (handler de la remote CastJutsu)
----------------------------------------------------------------
function JutsuService.HandleCast(player, sequence)
	-- 1) Validation stricte du paramètre client
	if type(sequence) ~= "table" then
		return
	end
	local length = #sequence
	if length < 1 or length > GameConfig.ComboMaxLength then
		return
	end
	for i = 1, length do
		local element = sequence[i]
		if type(element) ~= "string" or not validElements[element] then
			return
		end
	end

	-- 2) Anti-spam global (armé plus bas, seulement si le lancer est accepté :
	-- une tentative ratée ne doit pas consommer la fenêtre)
	local now = os.clock()
	if lastCastAt[player] ~= nil and now - lastCastAt[player] < GameConfig.GlobalCastCooldown then
		sendFeedback(player, false, "Trop rapide ! Reprends ton souffle...")
		return
	end

	-- 3) Le profil doit être chargé
	local profile = DataManager.GetProfile(player)
	if profile == nil then
		return
	end

	-- 4) Résolution du combo
	local comboKey = JutsuConfig.GetComboKey(sequence)
	local jutsu = JutsuConfig.ByCombo[comboKey]
	if jutsu == nil then
		sendFeedback(player, false, "Aucun jutsu ne correspond à cette combinaison...")
		return
	end

	-- 5) Cooldown propre au jutsu
	local playerCooldowns = cooldowns[player]
	if playerCooldowns == nil then
		playerCooldowns = {}
		cooldowns[player] = playerCooldowns
	end
	local readyAt = playerCooldowns[jutsu.Id]
	if readyAt ~= nil and now < readyAt then
		sendFeedback(player, false, ("%s : encore %.1f s de recharge."):format(jutsu.Name, readyAt - now))
		return
	end

	-- 6) Le personnage doit être vivant
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end

	-- 7) Exécution de l'effet (isolée : un bug d'effet ne casse pas le service)
	local effectFunction = JutsuEffects[jutsu.Effect]
	if effectFunction == nil then
		warn(("[JutsuService] Effet introuvable : %s (jutsu %s)"):format(tostring(jutsu.Effect), jutsu.Id))
		return
	end

	local ok, err = pcall(effectFunction, player, character, jutsu)
	if not ok then
		warn(("[JutsuService] Erreur dans l'effet %s : %s"):format(jutsu.Effect, tostring(err)))
		sendFeedback(player, false, ("%s a échoué... (bug d'effet, voir l'Output serveur)"):format(jutsu.Name))
		return
	end

	-- Lancer accepté : on arme les cooldowns MAINTENANT (un effet en erreur
	-- ne coûte donc ni le cooldown du jutsu ni la fenêtre anti-spam).
	lastCastAt[player] = now
	playerCooldowns[jutsu.Id] = now + jutsu.Cooldown

	playCastSound(character, jutsu)

	-- 8) Statistiques + XP (via la source unique de progression)
	profile.Data.TotalJutsusCast += 1
	sendFeedback(player, true, ("%s !"):format(jutsu.Name))
	BattlepassService.AddXP(player, jutsu.XPReward, "Jutsu")
end

----------------------------------------------------------------
-- OPTIONS : RÉASSIGNATION DES TOUCHES (handler de UpdateKeybinds)
----------------------------------------------------------------
function JutsuService.HandleKeybindUpdate(player, newKeybinds)
	-- Anti-spam
	local now = os.clock()
	if lastKeybindAt[player] ~= nil and now - lastKeybindAt[player] < KEYBIND_DEBOUNCE then
		return
	end
	lastKeybindAt[player] = now

	-- Validation stricte : table contenant EXACTEMENT les 4 éléments,
	-- avec des touches de la liste blanche, sans doublons.
	if type(newKeybinds) ~= "table" then
		return
	end

	local cleanKeybinds = {}
	local usedKeys = {}

	for _, element in ipairs(GameConfig.Elements) do
		local keyName = newKeybinds[element]
		if type(keyName) ~= "string" or not GameConfig.ValidKeybindKeys[keyName] then
			sendFeedback(player, false, "Touche invalide pour " .. element .. ".")
			return
		end
		if usedKeys[keyName] then
			sendFeedback(player, false, "La touche " .. keyName .. " est utilisée deux fois.")
			return
		end
		usedKeys[keyName] = true
		cleanKeybinds[element] = keyName
	end

	-- Refuse toute clé parasite envoyée en plus par un exploiteur.
	for key in pairs(newKeybinds) do
		if not validElements[key] then
			return
		end
	end

	local profile = DataManager.GetProfile(player)
	if profile == nil then
		return
	end

	profile.Data.Keybinds = cleanKeybinds

	-- Pousse le profil à jour : le client reconstruit sa map touche -> élément.
	local snapshot = DataManager.GetDataSnapshot(player)
	if snapshot ~= nil then
		dataChangedRemote:FireClient(player, snapshot)
	end
	sendFeedback(player, true, "Touches sauvegardées !")
end

----------------------------------------------------------------
-- NETTOYAGE
----------------------------------------------------------------
function JutsuService.HandlePlayerRemoving(player)
	cooldowns[player] = nil
	lastCastAt[player] = nil
	lastKeybindAt[player] = nil
end

return JutsuService
