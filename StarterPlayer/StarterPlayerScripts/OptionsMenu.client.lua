--[[
	OptionsMenu — LocalScript
	EMPLACEMENT : StarterPlayer > StarterPlayerScripts > OptionsMenu

	Menu Options : réassignation des touches des 4 Mantras.
	  - Ouverture/fermeture : touche O (ou le bouton ⚙ en haut à gauche)
	  - Clic sur une touche -> "Appuyez sur une touche..." -> capture
	    de la prochaine touche clavier (liste blanche GameConfig)
	  - "Sauvegarder" envoie le tout au serveur (UpdateKeybinds), qui
	    valide, écrit dans le profil DataStore et repousse le snapshot
	Pendant la capture, l'attribut local "RebindCapture" empêche
	JutsuController de lancer des mantras par accident.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild(GameConfig.Remotes.FolderName)
local getProfileDataRemote = remotesFolder:WaitForChild(GameConfig.Remotes.GetProfileData)
local updateKeybindsRemote = remotesFolder:WaitForChild(GameConfig.Remotes.UpdateKeybinds)
local dataChangedRemote = remotesFolder:WaitForChild(GameConfig.Remotes.DataChanged)

----------------------------------------------------------------
-- ÉTAT
----------------------------------------------------------------
-- Touches en cours d'édition dans le menu (copie locale, envoyée
-- au serveur seulement quand le joueur clique "Sauvegarder").
local pendingKeybinds = {}
for element, keyName in pairs(GameConfig.DefaultKeybinds) do
	pendingKeybinds[element] = keyName
end

local capturingElement = nil -- élément dont on attend la nouvelle touche
local keyButtons = {}        -- [element] = TextButton (pour rafraîchir l'affichage)

----------------------------------------------------------------
-- INTERFACE (créée en code)
----------------------------------------------------------------
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OptionsMenu"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Bouton d'ouverture (haut gauche)
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleOptions"
toggleButton.Position = UDim2.new(0, 12, 0, 12)
toggleButton.Size = UDim2.new(0, 110, 0, 32)
toggleButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 14
toggleButton.TextColor3 = Color3.new(1, 1, 1)
toggleButton.Text = "⚙ Options (O)"
toggleButton.Parent = screenGui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

-- Panneau principal
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 380, 0, 330)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
panel.Visible = false
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 44)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Options — Touches des Mantras"
title.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -56)
statusLabel.Size = UDim2.new(1, -24, 0, 22)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
statusLabel.Text = "Clique sur une touche pour la changer."
statusLabel.Parent = panel

-- Une ligne par élément
for index, element in ipairs(GameConfig.Elements) do
	local row = Instance.new("Frame")
	row.Name = "Row_" .. element
	row.Position = UDim2.new(0, 20, 0, 44 + (index - 1) * 48)
	row.Size = UDim2.new(1, -40, 0, 40)
	row.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
	row.Parent = panel
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local colorDot = Instance.new("Frame")
	colorDot.Position = UDim2.new(0, 10, 0.5, -8)
	colorDot.Size = UDim2.new(0, 16, 0, 16)
	colorDot.BackgroundColor3 = GameConfig.ElementColors[element] or Color3.new(1, 1, 1)
	colorDot.Parent = row
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = colorDot

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position = UDim2.new(0, 36, 0, 0)
	nameLabel.Size = UDim2.new(0, 120, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Text = element
	nameLabel.Parent = row

	local keyButton = Instance.new("TextButton")
	keyButton.AnchorPoint = Vector2.new(1, 0.5)
	keyButton.Position = UDim2.new(1, -10, 0.5, 0)
	keyButton.Size = UDim2.new(0, 90, 0, 28)
	keyButton.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
	keyButton.Font = Enum.Font.GothamBold
	keyButton.TextSize = 14
	keyButton.TextColor3 = Color3.new(1, 1, 1)
	keyButton.Text = pendingKeybinds[element]
	keyButton.Parent = row
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 6)
	keyCorner.Parent = keyButton

	keyButtons[element] = keyButton

	keyButton.MouseButton1Click:Connect(function()
		capturingElement = element
		localPlayer:SetAttribute("RebindCapture", true)
		keyButton.Text = "..."
		statusLabel.Text = ("Appuie sur la nouvelle touche pour %s (Échap pour annuler)."):format(element)
	end)
end

-- Bouton Sauvegarder
local saveButton = Instance.new("TextButton")
saveButton.AnchorPoint = Vector2.new(0.5, 1)
saveButton.Position = UDim2.new(0.5, 0, 1, -14)
saveButton.Size = UDim2.new(0, 180, 0, 34)
saveButton.BackgroundColor3 = Color3.fromRGB(70, 150, 90)
saveButton.Font = Enum.Font.GothamBold
saveButton.TextSize = 16
saveButton.TextColor3 = Color3.new(1, 1, 1)
saveButton.Text = "Sauvegarder"
saveButton.Parent = panel
local saveCorner = Instance.new("UICorner")
saveCorner.CornerRadius = UDim.new(0, 8)
saveCorner.Parent = saveButton

----------------------------------------------------------------
-- LOGIQUE
----------------------------------------------------------------
local function refreshButtons()
	for element, button in pairs(keyButtons) do
		button.Text = pendingKeybinds[element]
	end
end

local function stopCapture()
	capturingElement = nil
	localPlayer:SetAttribute("RebindCapture", nil)
	refreshButtons()
end

local function togglePanel()
	panel.Visible = not panel.Visible
	if not panel.Visible then
		stopCapture()
		statusLabel.Text = "Clique sur une touche pour la changer."
	end
end

toggleButton.MouseButton1Click:Connect(togglePanel)

saveButton.MouseButton1Click:Connect(function()
	stopCapture()
	-- Vérification locale des doublons (le serveur re-vérifie de toute façon).
	local used = {}
	for _, element in ipairs(GameConfig.Elements) do
		local keyName = pendingKeybinds[element]
		if used[keyName] then
			statusLabel.Text = ("Conflit : la touche %s est utilisée deux fois."):format(keyName)
			return
		end
		used[keyName] = true
	end
	updateKeybindsRemote:FireServer(pendingKeybinds)
	statusLabel.Text = "Envoyé ! Sauvegarde en cours..."
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	-- 1) Mode capture : la prochaine touche devient le nouveau bind.
	-- (Échap est géré par GuiService.MenuOpened plus bas : Roblox consomme
	-- cette touche avant InputBegan pour ouvrir son menu système.)
	if capturingElement ~= nil then
		local keyName = input.KeyCode.Name
		if not GameConfig.ValidKeybindKeys[keyName] then
			statusLabel.Text = ("Touche %s non autorisée. Essaie une lettre (A-Z)."):format(keyName)
			return
		end
		-- Si la touche est déjà prise par un autre élément, on échange les deux.
		local swappedWith = nil
		for otherElement, otherKey in pairs(pendingKeybinds) do
			if otherKey == keyName and otherElement ~= capturingElement then
				pendingKeybinds[otherElement] = pendingKeybinds[capturingElement]
				swappedWith = otherElement
			end
		end
		pendingKeybinds[capturingElement] = keyName
		if swappedWith ~= nil then
			statusLabel.Text = ("Touches échangées entre %s et %s. N'oublie pas de sauvegarder !"):format(capturingElement, swappedWith)
		else
			statusLabel.Text = ("%s est maintenant sur %s. N'oublie pas de sauvegarder !"):format(capturingElement, keyName)
		end
		stopCapture()
		return
	end

	-- 2) Raccourci d'ouverture du menu.
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.O then
		togglePanel()
	end
end)

-- Échap ouvre le menu Roblox : on en profite pour annuler la capture en cours.
GuiService.MenuOpened:Connect(function()
	if capturingElement ~= nil then
		statusLabel.Text = "Capture annulée."
		stopCapture()
	end
end)

----------------------------------------------------------------
-- SYNCHRONISATION AVEC LE PROFIL
----------------------------------------------------------------
local function applyServerKeybinds(keybinds)
	for _, element in ipairs(GameConfig.Elements) do
		if type(keybinds[element]) == "string" then
			pendingKeybinds[element] = keybinds[element]
		end
	end
	refreshButtons()
end

dataChangedRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" and type(snapshot.Keybinds) == "table" then
		applyServerKeybinds(snapshot.Keybinds)
	end
end)

task.spawn(function()
	local ok, snapshot = pcall(function()
		return getProfileDataRemote:InvokeServer()
	end)
	if ok and type(snapshot) == "table" and type(snapshot.Keybinds) == "table" then
		applyServerKeybinds(snapshot.Keybinds)
	end
end)
