--[[
	JutsuController — LocalScript
	EMPLACEMENT : StarterPlayer > StarterPlayerScripts > JutsuController

	Côté client du système de Jutsus :
	  - Écoute le clavier et traduit les touches en mantras via les
	    keybinds du profil (personnalisables dans le menu Options)
	  - Gère le buffer de combo : lance immédiatement quand la séquence
	    correspond à un jutsu sans suite possible, sinon attend la suite
	    ou le timeout (GameConfig.ComboTimeout)
	  - Affiche le HUD : séquence en cours (pastilles colorées) +
	    messages de feedback envoyés par le serveur
	Le serveur re-valide TOUT : ce script n'est que du confort d'input.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local JutsuConfig = require(Modules:WaitForChild("JutsuConfig"))

local localPlayer = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild(GameConfig.Remotes.FolderName)
local getProfileDataRemote = remotesFolder:WaitForChild(GameConfig.Remotes.GetProfileData)
local castJutsuRemote = remotesFolder:WaitForChild(GameConfig.Remotes.CastJutsu)
local dataChangedRemote = remotesFolder:WaitForChild(GameConfig.Remotes.DataChanged)
local jutsuFeedbackRemote = remotesFolder:WaitForChild(GameConfig.Remotes.JutsuFeedback)

----------------------------------------------------------------
-- ÉTAT
----------------------------------------------------------------
local keyToElement = {} -- ["A"] = "Feu", ... reconstruit à chaque changement de keybinds
local sequence = {}     -- séquence de mantras en cours
local sequenceGeneration = 0 -- invalide les timers de timeout obsolètes

local function rebuildKeyMap(keybinds)
	keyToElement = {}
	for element, keyName in pairs(keybinds) do
		keyToElement[keyName] = element
	end
end

-- Valeurs par défaut immédiates, remplacées dès que le profil arrive.
rebuildKeyMap(GameConfig.DefaultKeybinds)

----------------------------------------------------------------
-- HUD (créé en code : rien à construire dans Studio)
----------------------------------------------------------------
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JutsuHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Conteneur de la séquence en cours (bas-centre)
local comboFrame = Instance.new("Frame")
comboFrame.Name = "ComboFrame"
comboFrame.AnchorPoint = Vector2.new(0.5, 1)
comboFrame.Position = UDim2.new(0.5, 0, 1, -30)
comboFrame.Size = UDim2.new(0, 260, 0, 56)
comboFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
comboFrame.BackgroundTransparency = 0.35
comboFrame.Parent = screenGui
local comboCorner = Instance.new("UICorner")
comboCorner.CornerRadius = UDim.new(0, 10)
comboCorner.Parent = comboFrame

local comboLayout = Instance.new("UIListLayout")
comboLayout.FillDirection = Enum.FillDirection.Horizontal
comboLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
comboLayout.VerticalAlignment = Enum.VerticalAlignment.Center
comboLayout.Padding = UDim.new(0, 8)
comboLayout.Parent = comboFrame

-- Message de feedback (au-dessus de la séquence)
local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "FeedbackLabel"
feedbackLabel.AnchorPoint = Vector2.new(0.5, 1)
feedbackLabel.Position = UDim2.new(0.5, 0, 1, -92)
feedbackLabel.Size = UDim2.new(0, 420, 0, 28)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextSize = 18
feedbackLabel.TextColor3 = Color3.new(1, 1, 1)
feedbackLabel.TextStrokeTransparency = 0.5
feedbackLabel.Text = ""
feedbackLabel.Parent = screenGui

-- Rappel des touches (petit texte discret sous la séquence)
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintLabel"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 1, -8)
hintLabel.Size = UDim2.new(0, 480, 0, 18)
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextSize = 13
hintLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
hintLabel.TextStrokeTransparency = 0.7
hintLabel.Text = ""
hintLabel.Parent = screenGui

local function refreshHint()
	local parts = {}
	for _, element in ipairs(GameConfig.Elements) do
		for keyName, mappedElement in pairs(keyToElement) do
			if mappedElement == element then
				table.insert(parts, ("%s = %s"):format(keyName, element))
				break
			end
		end
	end
	hintLabel.Text = table.concat(parts, "   |   ") .. "   |   O = Options   |   B = Battlepass"
end
refreshHint()

local function refreshComboDisplay()
	for _, child in ipairs(comboFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, element in ipairs(sequence) do
		local chip = Instance.new("Frame")
		chip.Name = "Chip" .. index
		chip.Size = UDim2.new(0, 44, 0, 44)
		chip.BackgroundColor3 = GameConfig.ElementColors[element] or Color3.new(1, 1, 1)
		chip.LayoutOrder = index
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0, 8)
		chipCorner.Parent = chip

		local chipLabel = Instance.new("TextLabel")
		chipLabel.Size = UDim2.new(1, 0, 1, 0)
		chipLabel.BackgroundTransparency = 1
		chipLabel.Font = Enum.Font.GothamBold
		chipLabel.TextSize = 16
		chipLabel.TextColor3 = Color3.new(1, 1, 1)
		chipLabel.TextStrokeTransparency = 0.4
		chipLabel.Text = string.sub(element, 1, 1) -- F / E / T / V
		chipLabel.Parent = chip

		chip.Parent = comboFrame
	end
end

local feedbackGeneration = 0
local function showFeedback(message, isSuccess)
	feedbackGeneration += 1
	local myGeneration = feedbackGeneration
	feedbackLabel.Text = message
	feedbackLabel.TextColor3 = isSuccess and Color3.fromRGB(140, 230, 140) or Color3.fromRGB(235, 120, 110)
	task.delay(2.5, function()
		if feedbackGeneration == myGeneration then
			feedbackLabel.Text = ""
		end
	end)
end

----------------------------------------------------------------
-- LOGIQUE DE COMBO
----------------------------------------------------------------
local function clearSequence()
	sequenceGeneration += 1
	sequence = {}
	refreshComboDisplay()
end

local function castCurrentSequence()
	if #sequence == 0 then
		return
	end
	local toSend = table.clone(sequence)
	clearSequence()
	castJutsuRemote:FireServer(toSend)
end

local function onSequenceTimeout(myGeneration)
	if myGeneration ~= sequenceGeneration then
		return -- une touche a été pressée entre-temps, ce timer est obsolète
	end
	local comboKey = JutsuConfig.GetComboKey(sequence)
	if JutsuConfig.ByCombo[comboKey] ~= nil then
		castCurrentSequence()
	else
		clearSequence()
		showFeedback("La combinaison s'est dissipée...", false)
	end
end

local function onMantraPressed(element)
	table.insert(sequence, element)
	if #sequence > GameConfig.ComboMaxLength then
		-- Ne devrait pas arriver (on lance avant), mais on reste sûr.
		clearSequence()
		return
	end
	refreshComboDisplay()

	local comboKey = JutsuConfig.GetComboKey(sequence)
	local isCombo = JutsuConfig.ByCombo[comboKey] ~= nil
	local isPrefix = JutsuConfig.PrefixSet[comboKey] == true

	if isCombo and not isPrefix then
		-- Jutsu trouvé et aucune recette plus longue ne commence ainsi : feu !
		castCurrentSequence()
	elseif not isCombo and not isPrefix then
		-- Séquence morte : aucun jutsu ne peut plus en sortir.
		clearSequence()
		showFeedback("Aucun jutsu ne correspond...", false)
	else
		-- Peut encore devenir un combo (ou en est déjà un avec une suite
		-- possible) : on attend la touche suivante ou le timeout.
		sequenceGeneration += 1
		local myGeneration = sequenceGeneration
		task.delay(GameConfig.ComboTimeout, function()
			onSequenceTimeout(myGeneration)
		end)
	end
end

----------------------------------------------------------------
-- ENTRÉES CLAVIER
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	-- Le menu Options est en train de capturer une touche : on ne lance rien.
	if localPlayer:GetAttribute("RebindCapture") then
		return
	end

	local element = keyToElement[input.KeyCode.Name]
	if element ~= nil then
		onMantraPressed(element)
	end
end)

----------------------------------------------------------------
-- SYNCHRONISATION AVEC LE SERVEUR
----------------------------------------------------------------
jutsuFeedbackRemote.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and type(payload.Message) == "string" then
		showFeedback(payload.Message, payload.Success == true)
	end
end)

dataChangedRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" and type(snapshot.Keybinds) == "table" then
		rebuildKeyMap(snapshot.Keybinds)
		refreshHint()
	end
end)

-- Chargement initial des keybinds depuis le profil.
task.spawn(function()
	local ok, snapshot = pcall(function()
		return getProfileDataRemote:InvokeServer()
	end)
	if ok and type(snapshot) == "table" and type(snapshot.Keybinds) == "table" then
		rebuildKeyMap(snapshot.Keybinds)
		refreshHint()
	end
end)
