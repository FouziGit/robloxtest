--[[
	MovementController — LocalScript
	EMPLACEMENT : StarterPlayer > StarterPlayerScripts > MovementController

	Deux mécaniques de déplacement, côté client :
	  - SPRINT : maintiens Maj gauche (Left Shift) pour courir. Une jauge
	    d'endurance se vide en courant et se recharge au repos. Vide -> tu
	    repasses en marche jusqu'à la recharge.
	  - DOUBLE SAUT : appuie une 2e fois sur Espace en l'air pour un saut
	    supplémentaire. Se réarme à l'atterrissage.

	Respecte les ralentissements imposés par le serveur (ex. Brume
	Bouillante) : tant que le Humanoid porte l'attribut "BrumeSlow", ce
	script ne touche pas à la vitesse.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- RÉGLAGES
----------------------------------------------------------------
local WALK_SPEED = 16
local SPRINT_SPEED = 26
local SPRINT_KEY = Enum.KeyCode.LeftShift

local MAX_STAMINA = 100
local STAMINA_DRAIN = 26   -- par seconde en sprint
local STAMINA_REGEN = 18   -- par seconde au repos
local REGEN_DELAY = 0.6    -- délai avant recharge après avoir sprinté
local MIN_STAMINA_TO_START = 8 -- il faut au moins ça pour relancer un sprint

local MAX_JUMPS = 2
local DOUBLE_JUMP_VELOCITY = 50
local JUMP_DEBOUNCE = 0.18

local SLOW_ATTRIBUTE = "BrumeSlow" -- posé par le serveur pendant un ralentissement

----------------------------------------------------------------
-- ÉTAT
----------------------------------------------------------------
local humanoid = nil
local rootPart = nil

local stamina = MAX_STAMINA
local sprintHeld = false
local isSprinting = false
local lastSprintTime = 0

local jumpsUsed = 0
local lastJumpAt = 0

----------------------------------------------------------------
-- INTERFACE : JAUGE D'ENDURANCE (créée en code, cachée quand pleine)
----------------------------------------------------------------
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MovementHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local staminaBack = Instance.new("Frame")
staminaBack.Name = "StaminaBar"
staminaBack.AnchorPoint = Vector2.new(0, 1)
staminaBack.Position = UDim2.new(0, 16, 1, -16)
staminaBack.Size = UDim2.new(0, 200, 0, 12)
staminaBack.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
staminaBack.BackgroundTransparency = 0.25
staminaBack.Visible = false
staminaBack.Parent = screenGui
local backCorner = Instance.new("UICorner")
backCorner.CornerRadius = UDim.new(1, 0)
backCorner.Parent = staminaBack

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = Color3.fromRGB(120, 210, 120)
staminaFill.Parent = staminaBack
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = staminaFill

local staminaLabel = Instance.new("TextLabel")
staminaLabel.AnchorPoint = Vector2.new(0, 1)
staminaLabel.Position = UDim2.new(0, 16, 1, -30)
staminaLabel.Size = UDim2.new(0, 200, 0, 16)
staminaLabel.BackgroundTransparency = 1
staminaLabel.Font = Enum.Font.GothamBold
staminaLabel.TextSize = 12
staminaLabel.TextXAlignment = Enum.TextXAlignment.Left
staminaLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
staminaLabel.TextStrokeTransparency = 0.6
staminaLabel.Text = "Endurance"
staminaLabel.Visible = false
staminaLabel.Parent = screenGui

----------------------------------------------------------------
-- RATTACHEMENT AU PERSONNAGE (gère les réapparitions)
----------------------------------------------------------------
local function onCharacter(character)
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")

	humanoid.WalkSpeed = WALK_SPEED
	jumpsUsed = 0
	isSprinting = false
	sprintHeld = false

	-- Réarme le double saut à l'atterrissage / au sol.
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics then
			jumpsUsed = 0
		end
	end)
end

if localPlayer.Character then
	onCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacter)

----------------------------------------------------------------
-- ENTRÉES
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == SPRINT_KEY then
		sprintHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == SPRINT_KEY then
		sprintHeld = false
	end
end)

-- Le perso touche-t-il le sol (ou un mur d'escalade) ?
local function isGrounded()
	if humanoid == nil then
		return false
	end
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.RunningNoPhysics
		or state == Enum.HumanoidStateType.Landed
		or state == Enum.HumanoidStateType.Climbing
end

-- Double saut : JumpRequest se déclenche à chaque demande de saut (Espace,
-- bouton de saut mobile...). Le 1er saut au sol est géré par le moteur ; on
-- ajoute les sauts en l'air (y compris si on a marché dans le vide).
UserInputService.JumpRequest:Connect(function()
	if humanoid == nil or rootPart == nil then
		return
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return
	end

	local now = os.clock()
	if now - lastJumpAt < JUMP_DEBOUNCE then
		return
	end

	if isGrounded() then
		-- Saut au sol : le moteur effectue le saut, on le comptabilise.
		jumpsUsed = 1
		lastJumpAt = now
	elseif jumpsUsed < MAX_JUMPS then
		-- Saut en l'air. Si on n'avait encore jamais sauté (chute depuis un
		-- rebord), on passe directement au 2e cran pour n'accorder qu'un
		-- seul saut aérien.
		jumpsUsed = math.max(jumpsUsed, 1) + 1
		lastJumpAt = now
		rootPart.AssemblyLinearVelocity = Vector3.new(
			rootPart.AssemblyLinearVelocity.X,
			DOUBLE_JUMP_VELOCITY,
			rootPart.AssemblyLinearVelocity.Z
		)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

----------------------------------------------------------------
-- BOUCLE : ENDURANCE + VITESSE + AFFICHAGE
----------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	if humanoid == nil or humanoid.Health <= 0 then
		staminaBack.Visible = false
		staminaLabel.Visible = false
		return
	end

	-- Le perso bouge-t-il vraiment ? (inutile de vider l'endurance à l'arrêt)
	local isMoving = humanoid.MoveDirection.Magnitude > 0.1

	local wantSprint = sprintHeld and isMoving and stamina > 0
	if wantSprint and not isSprinting and stamina < MIN_STAMINA_TO_START then
		wantSprint = false -- endurance trop basse pour (re)lancer un sprint
	end
	isSprinting = wantSprint

	if isSprinting then
		stamina = math.max(0, stamina - STAMINA_DRAIN * dt)
		lastSprintTime = os.clock()
	elseif os.clock() - lastSprintTime >= REGEN_DELAY then
		stamina = math.min(MAX_STAMINA, stamina + STAMINA_REGEN * dt)
	end

	-- On ne force la vitesse QUE si le serveur ne nous ralentit pas.
	if humanoid:GetAttribute(SLOW_ATTRIBUTE) == nil then
		local targetSpeed = isSprinting and SPRINT_SPEED or WALK_SPEED
		if humanoid.WalkSpeed ~= targetSpeed then
			humanoid.WalkSpeed = targetSpeed
		end
	end

	-- Affichage : visible seulement si on n'est pas au max.
	local ratio = stamina / MAX_STAMINA
	local showBar = ratio < 0.999
	staminaBack.Visible = showBar
	staminaLabel.Visible = showBar
	staminaFill.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
	if ratio < 0.25 then
		staminaFill.BackgroundColor3 = Color3.fromRGB(220, 110, 90) -- rouge : presque vide
	elseif isSprinting then
		staminaFill.BackgroundColor3 = Color3.fromRGB(240, 210, 90) -- jaune : en train de courir
	else
		staminaFill.BackgroundColor3 = Color3.fromRGB(120, 210, 120) -- vert : recharge
	end
end)
