--[[
	BattlepassMenu — LocalScript
	EMPLACEMENT : StarterPlayer > StarterPlayerScripts > BattlepassMenu

	Interface du Battlepass :
	  - Ouverture/fermeture : touche B (ou le bouton 🎖 en haut à gauche)
	  - En-tête : niveau joueur + barre d'XP, palier Battlepass + barre d'XP
	  - Liste déroulante des 50 paliers avec leur récompense et leur état
	    (Verrouillé / Récupérable / Récupéré) + bouton de réclamation
	  - Se rafraîchit automatiquement à chaque DataChanged du serveur
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local BattlepassConfig = require(Modules:WaitForChild("BattlepassConfig"))

local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild(GameConfig.Remotes.FolderName)
local getProfileDataRemote = remotesFolder:WaitForChild(GameConfig.Remotes.GetProfileData)
local claimRewardRemote = remotesFolder:WaitForChild(GameConfig.Remotes.ClaimBattlepassReward)
local dataChangedRemote = remotesFolder:WaitForChild(GameConfig.Remotes.DataChanged)

local currentData = nil -- dernier snapshot du profil reçu du serveur

----------------------------------------------------------------
-- INTERFACE (créée en code)
----------------------------------------------------------------
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BattlepassMenu"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Bouton d'ouverture (sous le bouton Options)
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleBattlepass"
toggleButton.Position = UDim2.new(0, 12, 0, 52)
toggleButton.Size = UDim2.new(0, 110, 0, 32)
toggleButton.BackgroundColor3 = Color3.fromRGB(120, 90, 40)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.TextColor3 = Color3.new(1, 1, 1)
toggleButton.Text = "🎖 Pass (B)"
toggleButton.Parent = screenGui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

-- Panneau principal
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 460, 0, 480)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
panel.Visible = false
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Battlepass"
title.Parent = panel

-- Fabrique une ligne "label + barre de progression".
local function createProgressBar(yOffset, barColor)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 20, 0, yOffset)
	label.Size = UDim2.new(1, -40, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.Parent = panel

	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 20, 0, yOffset + 20)
	barBack.Size = UDim2.new(1, -40, 0, 12)
	barBack.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	barBack.Parent = panel
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = barBack

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = barColor
	barFill.Parent = barBack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	return label, barFill
end

local playerLevelLabel, playerLevelFill = createProgressBar(44, Color3.fromRGB(90, 170, 240))
local battlepassLabel, battlepassFill = createProgressBar(88, Color3.fromRGB(230, 180, 60))

-- Liste des paliers
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Position = UDim2.new(0, 12, 0, 132)
scrollFrame.Size = UDim2.new(1, -24, 1, -144)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 6
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, BattlepassConfig.MaxLevel * 46)
scrollFrame.Parent = panel

local tierRows = {} -- [tier] = { StateLabel, ClaimButton, Row }

for tier = 1, BattlepassConfig.MaxLevel do
	local row = Instance.new("Frame")
	row.Name = "Tier_" .. tier
	row.Position = UDim2.new(0, 0, 0, (tier - 1) * 46)
	row.Size = UDim2.new(1, -8, 0, 40)
	row.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
	row.Parent = scrollFrame
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Position = UDim2.new(0, 10, 0, 0)
	tierLabel.Size = UDim2.new(0, 60, 1, 0)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextSize = 15
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.TextColor3 = Color3.fromRGB(230, 180, 60)
	tierLabel.Text = "Palier " .. tier
	tierLabel.Parent = row

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Position = UDim2.new(0, 75, 0, 0)
	rewardLabel.Size = UDim2.new(0, 200, 1, 0)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.Gotham
	rewardLabel.TextSize = 13
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.TextColor3 = Color3.new(1, 1, 1)
	rewardLabel.TextTruncate = Enum.TextTruncate.AtEnd
	rewardLabel.Text = BattlepassConfig.GetRewardText(BattlepassConfig.Rewards[tier])
	rewardLabel.Parent = row

	local claimButton = Instance.new("TextButton")
	claimButton.AnchorPoint = Vector2.new(1, 0.5)
	claimButton.Position = UDim2.new(1, -8, 0.5, 0)
	claimButton.Size = UDim2.new(0, 110, 0, 28)
	claimButton.Font = Enum.Font.GothamBold
	claimButton.TextSize = 13
	claimButton.TextColor3 = Color3.new(1, 1, 1)
	claimButton.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
	claimButton.Text = "Verrouillé"
	claimButton.AutoButtonColor = false
	claimButton.Parent = row
	local claimCorner = Instance.new("UICorner")
	claimCorner.CornerRadius = UDim.new(0, 6)
	claimCorner.Parent = claimButton

	claimButton.MouseButton1Click:Connect(function()
		if currentData == nil then
			return
		end
		local claimed = currentData.ClaimedRewards[tostring(tier)] == true
		if tier <= currentData.BattlepassLevel and not claimed then
			claimRewardRemote:FireServer(tier)
		end
	end)

	tierRows[tier] = { ClaimButton = claimButton, Row = row }
end

----------------------------------------------------------------
-- RAFRAÎCHISSEMENT
----------------------------------------------------------------
local function refresh()
	if currentData == nil then
		return
	end

	-- Barre de niveau joueur
	local neededPlayerXP = GameConfig.PlayerXPForLevel(currentData.PlayerLevel)
	playerLevelLabel.Text = ("Niveau %d   —   %d / %d XP"):format(
		currentData.PlayerLevel, currentData.PlayerXP, neededPlayerXP)
	playerLevelFill.Size = UDim2.new(math.clamp(currentData.PlayerXP / neededPlayerXP, 0, 1), 0, 1, 0)

	-- Barre du Battlepass
	if currentData.BattlepassLevel >= BattlepassConfig.MaxLevel then
		battlepassLabel.Text = ("Battlepass palier %d / %d — TERMINÉ !"):format(
			BattlepassConfig.MaxLevel, BattlepassConfig.MaxLevel)
		battlepassFill.Size = UDim2.new(1, 0, 1, 0)
	else
		local neededTierXP = BattlepassConfig.XPForTier(currentData.BattlepassLevel)
		battlepassLabel.Text = ("Battlepass palier %d / %d   —   %d / %d XP"):format(
			currentData.BattlepassLevel, BattlepassConfig.MaxLevel, currentData.BattlepassXP, neededTierXP)
		battlepassFill.Size = UDim2.new(math.clamp(currentData.BattlepassXP / neededTierXP, 0, 1), 0, 1, 0)
	end

	-- État de chaque palier
	for tier = 1, BattlepassConfig.MaxLevel do
		local entry = tierRows[tier]
		local claimed = currentData.ClaimedRewards[tostring(tier)] == true
		local unlocked = tier <= currentData.BattlepassLevel

		if claimed then
			entry.ClaimButton.Text = "Récupéré ✓"
			entry.ClaimButton.BackgroundColor3 = Color3.fromRGB(45, 90, 55)
			entry.Row.BackgroundColor3 = Color3.fromRGB(32, 42, 36)
		elseif unlocked then
			entry.ClaimButton.Text = "Récupérer !"
			entry.ClaimButton.BackgroundColor3 = Color3.fromRGB(70, 150, 90)
			entry.Row.BackgroundColor3 = Color3.fromRGB(48, 44, 34)
		else
			entry.ClaimButton.Text = "Verrouillé"
			entry.ClaimButton.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
			entry.Row.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
		end
	end
end

----------------------------------------------------------------
-- OUVERTURE / FERMETURE
----------------------------------------------------------------
local function togglePanel()
	panel.Visible = not panel.Visible
	if panel.Visible then
		refresh()
	end
end

toggleButton.MouseButton1Click:Connect(togglePanel)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if localPlayer:GetAttribute("RebindCapture") then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		togglePanel()
	end
end)

----------------------------------------------------------------
-- SYNCHRONISATION AVEC LE SERVEUR
----------------------------------------------------------------
dataChangedRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" then
		currentData = snapshot
		refresh()
	end
end)

task.spawn(function()
	local ok, snapshot = pcall(function()
		return getProfileDataRemote:InvokeServer()
	end)
	if ok and type(snapshot) == "table" then
		currentData = snapshot
		refresh()
	end
end)
