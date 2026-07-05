--[[
	SoundController — LocalScript
	EMPLACEMENT : StarterPlayer > StarterPlayerScripts > SoundController

	Sons personnels du joueur (non spatiaux) + musique d'ambiance :
	  - Musique de fond en boucle (si SoundConfig.Ambient.Id est renseigné)
	  - Sons d'événements déclenchés par les messages de feedback du serveur :
	    montée de niveau, palier de Battlepass, ennemi vaincu, récompense.

	Les sons de LANCER de jutsu sont, eux, joués côté serveur (spatial, tout
	le monde les entend) par JutsuService. Ici on ne gère que ton retour à toi.

	Tout est réglé dans ReplicatedStorage > Modules > SoundConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local SoundConfig = require(Modules:WaitForChild("SoundConfig"))

local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild(GameConfig.Remotes.FolderName)
local jutsuFeedbackRemote = remotesFolder:WaitForChild(GameConfig.Remotes.JutsuFeedback)

----------------------------------------------------------------
-- LECTURE D'UN SON LOCAL (non spatial)
----------------------------------------------------------------
local function playLocal(entry)
	local sound = SoundConfig.Build(entry)
	if sound == nil then
		return
	end
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	-- Filet de sécurité : si Ended ne se déclenche pas (ID invalide), on nettoie.
	task.delay(6, function()
		if sound and sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

----------------------------------------------------------------
-- MUSIQUE D'AMBIANCE (boucle)
----------------------------------------------------------------
do
	local music = SoundConfig.Build(SoundConfig.Ambient)
	if music ~= nil then
		music.Name = "AmbientMusic"
		music.Looped = true
		music.Parent = SoundService
		music:Play()
	end
end

----------------------------------------------------------------
-- SONS D'ÉVÉNEMENTS (déduits du message de feedback)
----------------------------------------------------------------
jutsuFeedbackRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.Message) ~= "string" then
		return
	end
	if payload.Success ~= true then
		return -- on ne sonorise que les bonnes nouvelles
	end

	local message = payload.Message

	if string.find(message, "Niveau %d") then
		playLocal(SoundConfig.Event.LevelUp)
	elseif string.find(message, "palier") then
		playLocal(SoundConfig.Event.TierUp)
	elseif string.find(message, "Ennemi vaincu") then
		playLocal(SoundConfig.Event.Kill)
	elseif string.find(message, "Récupéré") then
		playLocal(SoundConfig.Event.Claim)
	end
end)
