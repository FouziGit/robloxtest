--[[
	BattlepassService.lua — ModuleScript
	EMPLACEMENT : ServerScriptService > Modules > BattlepassService

	Gère TOUTE la progression :
	  - XP et niveau du joueur (courbe dans GameConfig.PlayerXPForLevel)
	  - XP et paliers du Battlepass 1 → 50 (courbe dans BattlepassConfig)
	  - Réclamation des récompenses (monnaie / cosmétiques)
	  - leaderstats (Niveau + Ryo affichés dans la liste des joueurs)

	Toute source d'XP du jeu passe par BattlepassService.AddXP :
	jutsu réussi (JutsuService) et ennemi vaincu (MainServer).
	Après chaque changement, un snapshot du profil est poussé au client
	via le RemoteEvent DataChanged (l'interface se met à jour seule).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local BattlepassConfig = require(Modules:WaitForChild("BattlepassConfig"))

local BattlepassService = {}

-- Injectés par MainServer via Init()
local DataManager = nil
local dataChangedRemote = nil
local feedbackRemote = nil

-- Anti-spam de la remote ClaimBattlepassReward : [Player] = os.clock() du dernier appel
local lastClaimAt = {}
local CLAIM_DEBOUNCE = 0.5

----------------------------------------------------------------
-- INITIALISATION
----------------------------------------------------------------
function BattlepassService.Init(deps)
	DataManager = deps.DataManager
	dataChangedRemote = deps.DataChangedRemote
	feedbackRemote = deps.FeedbackRemote
end

----------------------------------------------------------------
-- OUTILS INTERNES
----------------------------------------------------------------
local function pushData(player)
	local snapshot = DataManager.GetDataSnapshot(player)
	if snapshot then
		dataChangedRemote:FireClient(player, snapshot)
	end
end

local function sendFeedback(player, success, message)
	feedbackRemote:FireClient(player, { Success = success, Message = message })
end

local function updateLeaderstats(player, data)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil then
		return
	end
	local levelValue = leaderstats:FindFirstChild("Niveau")
	if levelValue then
		levelValue.Value = data.PlayerLevel
	end
	local currencyValue = leaderstats:FindFirstChild(GameConfig.CurrencyName)
	if currencyValue then
		currencyValue.Value = data.Currency
	end
end

----------------------------------------------------------------
-- LEADERSTATS
----------------------------------------------------------------
-- Appelé par MainServer une fois le profil chargé.
function BattlepassService.SetupLeaderstats(player)
	local profile = DataManager.GetProfile(player)
	if profile == nil or player.Parent == nil then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Niveau"
	levelValue.Value = profile.Data.PlayerLevel
	levelValue.Parent = leaderstats

	local currencyValue = Instance.new("IntValue")
	currencyValue.Name = GameConfig.CurrencyName
	currencyValue.Value = profile.Data.Currency
	currencyValue.Parent = leaderstats

	leaderstats.Parent = player
end

----------------------------------------------------------------
-- XP (source unique de progression)
----------------------------------------------------------------
--[[
	Ajoute de l'XP au joueur ET au Battlepass, gère les montées de
	niveau/palier en cascade, met à jour leaderstats et pousse le
	nouveau snapshot au client.
	reason : "Jutsu" | "Kill" | ... — libellé libre, non affiché pour
	l'instant ; branche-y tes futurs hooks (analytics, quêtes, bonus d'XP).
]]
function BattlepassService.AddXP(player, amount, reason)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end
	local profile = DataManager.GetProfile(player)
	if profile == nil then
		return
	end
	local data = profile.Data

	local messages = {}

	-- 1) Progression du niveau joueur
	if data.PlayerLevel < GameConfig.PlayerMaxLevel then
		data.PlayerXP += amount
		local guard = 0
		while data.PlayerLevel < GameConfig.PlayerMaxLevel
			and data.PlayerXP >= GameConfig.PlayerXPForLevel(data.PlayerLevel) do
			data.PlayerXP -= GameConfig.PlayerXPForLevel(data.PlayerLevel)
			data.PlayerLevel += 1
			table.insert(messages, ("Niveau %d atteint !"):format(data.PlayerLevel))
			guard += 1
			if guard > 100 then break end -- sécurité anti-boucle infinie
		end
		if data.PlayerLevel >= GameConfig.PlayerMaxLevel then
			data.PlayerXP = 0
		end
	end

	-- 2) Progression du Battlepass
	local bpAmount = math.floor(amount * GameConfig.XP.BattlepassMultiplier)
	if bpAmount > 0 and data.BattlepassLevel < BattlepassConfig.MaxLevel then
		data.BattlepassXP += bpAmount
		local guard = 0
		while data.BattlepassLevel < BattlepassConfig.MaxLevel
			and data.BattlepassXP >= BattlepassConfig.XPForTier(data.BattlepassLevel) do
			data.BattlepassXP -= BattlepassConfig.XPForTier(data.BattlepassLevel)
			data.BattlepassLevel += 1
			table.insert(messages, ("Battlepass palier %d débloqué !"):format(data.BattlepassLevel))
			guard += 1
			if guard > 100 then break end
		end
		if data.BattlepassLevel >= BattlepassConfig.MaxLevel then
			data.BattlepassXP = 0 -- battlepass terminé, barre pleine
		end
	end

	updateLeaderstats(player, data)
	pushData(player)

	for _, message in ipairs(messages) do
		sendFeedback(player, true, message)
	end
end

----------------------------------------------------------------
-- RÉCLAMATION DES RÉCOMPENSES
----------------------------------------------------------------
-- Handler de la remote ClaimBattlepassReward. Toutes les validations
-- sont faites ICI, côté serveur : le client ne peut rien tricher.
function BattlepassService.HandleClaimReward(player, tier)
	-- Anti-spam
	local now = os.clock()
	if lastClaimAt[player] and now - lastClaimAt[player] < CLAIM_DEBOUNCE then
		return
	end
	lastClaimAt[player] = now

	-- Validation du paramètre envoyé par le client
	if type(tier) ~= "number" or tier ~= math.floor(tier)
		or tier < 1 or tier > BattlepassConfig.MaxLevel then
		return
	end

	local profile = DataManager.GetProfile(player)
	if profile == nil then
		return
	end
	local data = profile.Data

	if tier > data.BattlepassLevel then
		sendFeedback(player, false, ("Palier %d pas encore atteint."):format(tier))
		return
	end

	local tierKey = tostring(tier) -- clés STRING : contrainte JSON du DataStore
	if data.ClaimedRewards[tierKey] then
		sendFeedback(player, false, "Récompense déjà récupérée.")
		return
	end

	local reward = BattlepassConfig.Rewards[tier]
	if reward == nil then
		sendFeedback(player, false, "Aucune récompense à ce palier.")
		return
	end

	-- Application de la récompense
	if reward.Type == "Currency" then
		data.Currency += reward.Amount
	elseif reward.Type == "Cosmetic" then
		local alreadyOwned = false
		for _, cosmeticId in ipairs(data.Cosmetics) do
			if cosmeticId == reward.Id then
				alreadyOwned = true
				break
			end
		end
		if not alreadyOwned then
			table.insert(data.Cosmetics, reward.Id)
		end
	else
		warn(("[BattlepassService] Type de récompense inconnu au palier %d : %s"):format(tier, tostring(reward.Type)))
		return
	end

	data.ClaimedRewards[tierKey] = true

	updateLeaderstats(player, data)
	pushData(player)
	sendFeedback(player, true, ("Récupéré : %s"):format(BattlepassConfig.GetRewardText(reward)))
end

----------------------------------------------------------------
-- NETTOYAGE
----------------------------------------------------------------
function BattlepassService.HandlePlayerRemoving(player)
	lastClaimAt[player] = nil
end

return BattlepassService
