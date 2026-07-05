--[[
	MainServer — Script (serveur)
	EMPLACEMENT : ServerScriptService > MainServer

	Point d'entrée UNIQUE du serveur. Dans l'ordre :
	  1. Crée le dossier Remotes et toutes les remotes (noms dans GameConfig)
	  2. Initialise les services (DataManager, BattlepassService, JutsuService)
	  3. Branche le cycle de vie joueur : chargement du profil à l'arrivée,
	     sauvegarde + libération du verrou au départ
	  4. Branche les remotes sur leurs handlers
	  5. Gère les ennemis : tout Model tagué "Enemy" (ou placé dans
	     workspace.Enemies) donne de l'XP à son tueur quand il meurt
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local ServerModules = ServerScriptService:WaitForChild("Modules")
local DataManager = require(ServerModules:WaitForChild("DataManager"))
local BattlepassService = require(ServerModules:WaitForChild("BattlepassService"))
local JutsuService = require(ServerModules:WaitForChild("JutsuService"))

----------------------------------------------------------------
-- 1) CRÉATION DES REMOTES
----------------------------------------------------------------
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = GameConfig.Remotes.FolderName

local function createRemoteEvent(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local function createRemoteFunction(name)
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local getProfileDataRemote = createRemoteFunction(GameConfig.Remotes.GetProfileData)
local castJutsuRemote = createRemoteEvent(GameConfig.Remotes.CastJutsu)
local updateKeybindsRemote = createRemoteEvent(GameConfig.Remotes.UpdateKeybinds)
local claimRewardRemote = createRemoteEvent(GameConfig.Remotes.ClaimBattlepassReward)
local dataChangedRemote = createRemoteEvent(GameConfig.Remotes.DataChanged)
local jutsuFeedbackRemote = createRemoteEvent(GameConfig.Remotes.JutsuFeedback)

remotesFolder.Parent = ReplicatedStorage

----------------------------------------------------------------
-- 2) INITIALISATION DES SERVICES (injection de dépendances)
----------------------------------------------------------------
BattlepassService.Init({
	DataManager = DataManager,
	DataChangedRemote = dataChangedRemote,
	FeedbackRemote = jutsuFeedbackRemote,
})

JutsuService.Init({
	DataManager = DataManager,
	BattlepassService = BattlepassService,
	FeedbackRemote = jutsuFeedbackRemote,
	DataChangedRemote = dataChangedRemote,
})

----------------------------------------------------------------
-- 3) CYCLE DE VIE JOUEUR
----------------------------------------------------------------
-- État de GetProfileData (déclaré ici car onPlayerRemoving le nettoie) :
local profileWaiters = {} -- [Player] = nb d'invocations en attente du profil
local snapshotCache = {}  -- [Player] = { At = os.clock(), Snapshot = table }

local function onPlayerAdded(player)
	local profile = DataManager.LoadProfile(player) -- yield (DataStore)
	if profile == nil then
		return -- joueur kick ou parti pendant le chargement
	end

	BattlepassService.SetupLeaderstats(player)

	-- Pousse le profil initial (au cas où le client écoute déjà DataChanged).
	local snapshot = DataManager.GetDataSnapshot(player)
	if snapshot ~= nil then
		dataChangedRemote:FireClient(player, snapshot)
	end
end

local function onPlayerRemoving(player)
	JutsuService.HandlePlayerRemoving(player)
	BattlepassService.HandlePlayerRemoving(player)
	DataManager.HandlePlayerRemoving(player) -- sauvegarde + libère le verrou
	profileWaiters[player] = nil
	snapshotCache[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Couvre les joueurs déjà présents si le script démarre en retard.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

----------------------------------------------------------------
-- 4) BRANCHEMENT DES REMOTES
----------------------------------------------------------------
-- Le client demande son profil (keybinds, XP, battlepass...).
-- On attend le chargement (max 30 s, le pire cas des retries de verrou)
-- pour couvrir la course "client prêt avant la fin du LoadProfile".
-- Anti-flood : cache court (une rafale d'appels rend la même copie) et
-- plafond de threads en attente par joueur (un exploiteur qui spamme
-- InvokeServer ne peut pas accumuler des coroutines côté serveur).
local MAX_PROFILE_WAITERS = 4
local SNAPSHOT_CACHE_TTL = 1

getProfileDataRemote.OnServerInvoke = function(player)
	local cached = snapshotCache[player]
	if cached ~= nil and os.clock() - cached.At < SNAPSHOT_CACHE_TTL then
		return cached.Snapshot
	end

	if DataManager.GetProfile(player) == nil then
		local waiters = profileWaiters[player] or 0
		if waiters >= MAX_PROFILE_WAITERS then
			return nil -- déjà assez d'appels légitimes en attente (3 LocalScripts)
		end
		profileWaiters[player] = waiters + 1
		-- Décrément qui ne recrée JAMAIS la clé : si onPlayerRemoving a déjà
		-- nettoyé l'entrée pendant qu'on attendait, on ne la ressuscite pas
		-- (sinon : joueur parti épinglé en mémoire + compteur négatif).
		local function releaseWaiter()
			local count = profileWaiters[player]
			if count ~= nil then
				profileWaiters[player] = count - 1
			end
		end
		local deadline = os.clock() + 30
		while DataManager.GetProfile(player) == nil and os.clock() < deadline do
			if player.Parent == nil then
				releaseWaiter()
				return nil
			end
			task.wait(0.5)
		end
		releaseWaiter()
	end

	local snapshot = DataManager.GetDataSnapshot(player)
	if snapshot ~= nil and player.Parent ~= nil then
		snapshotCache[player] = { At = os.clock(), Snapshot = snapshot }
	end
	return snapshot
end

castJutsuRemote.OnServerEvent:Connect(function(player, sequence)
	JutsuService.HandleCast(player, sequence)
end)

updateKeybindsRemote.OnServerEvent:Connect(function(player, newKeybinds)
	JutsuService.HandleKeybindUpdate(player, newKeybinds)
end)

claimRewardRemote.OnServerEvent:Connect(function(player, tier)
	BattlepassService.HandleClaimReward(player, tier)
end)

----------------------------------------------------------------
-- 5) ENNEMIS : XP DE KILL
----------------------------------------------------------------
-- Un ennemi = un Model avec un Humanoid, tagué GameConfig.EnemyTag.
-- Quand il meurt, l'attribut "LastAttackerUserId" (posé par JutsuEffects
-- au moment des dégâts) désigne le joueur à créditer.

local function hookEnemy(model)
	if model:GetAttribute("DeathHooked") then
		return
	end
	model:SetAttribute("DeathHooked", true)

	task.spawn(function()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then
			humanoid = model:WaitForChild("Humanoid", 10)
		end
		if humanoid == nil or not humanoid:IsA("Humanoid") then
			return
		end

		humanoid.Died:Connect(function()
			local attackerUserId = model:GetAttribute("LastAttackerUserId")
			if attackerUserId == nil then
				return
			end
			local attacker = Players:GetPlayerByUserId(attackerUserId)
			if attacker == nil then
				return
			end

			local profile = DataManager.GetProfile(attacker)
			if profile ~= nil then
				profile.Data.TotalKills += 1
			end
			jutsuFeedbackRemote:FireClient(attacker, {
				Success = true,
				Message = ("Ennemi vaincu ! +%d XP"):format(GameConfig.XP.PerEnemyKill),
			})
			BattlepassService.AddXP(attacker, GameConfig.XP.PerEnemyKill, "Kill")
		end)
	end)
end

-- Ennemis déjà tagués + futurs tags.
for _, model in ipairs(CollectionService:GetTagged(GameConfig.EnemyTag)) do
	hookEnemy(model)
end
CollectionService:GetInstanceAddedSignal(GameConfig.EnemyTag):Connect(hookEnemy)

-- Confort : tout Model déposé dans workspace.Enemies est tagué automatiquement.
local function watchEnemyFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			CollectionService:AddTag(child, GameConfig.EnemyTag)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			CollectionService:AddTag(child, GameConfig.EnemyTag)
		end
	end)
end

local enemyFolder = workspace:FindFirstChild(GameConfig.EnemyFolderName)
if enemyFolder ~= nil then
	watchEnemyFolder(enemyFolder)
else
	workspace.ChildAdded:Connect(function(child)
		if child.Name == GameConfig.EnemyFolderName and child:IsA("Folder") then
			watchEnemyFolder(child)
		end
	end)
end

print("[MainServer] Systèmes Jutsus / Options / Battlepass / DataStore initialisés.")
