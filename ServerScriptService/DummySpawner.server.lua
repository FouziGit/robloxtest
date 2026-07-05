--[[
	DummySpawner — Script (serveur)
	EMPLACEMENT : ServerScriptService (à la racine, à côté de MainServer)

	Fait apparaître des mannequins d'entraînement pour :
	  - remplir le monde vide,
	  - te donner des cibles pour tester tes jutsus,
	  - alimenter la boucle XP (chaque mannequin détruit = XP de kill,
	    via le système d'ennemis déjà présent dans MainServer).

	Chaque mannequin est un Model avec un Humanoid, tagué "Enemy" et rangé
	dans workspace.Enemies. Quand il meurt, il réapparaît après quelques
	secondes. Règle le nombre / la vie / les positions dans CONFIG.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CONFIG = {
	Health = 100,
	RespawnDelay = 3,     -- secondes avant réapparition après la mort
	Ring = {
		Count = 5,        -- nombre de mannequins
		Radius = 26,      -- distance autour du point (0,0)
		Center = Vector3.new(0, 0, 0),
		GroundY = 0.5,    -- hauteur du sol (haut de la Baseplate par défaut)
	},
}

----------------------------------------------------------------
-- DOSSIER D'ACCUEIL
----------------------------------------------------------------
local enemiesFolder = workspace:FindFirstChild(GameConfig.EnemyFolderName)
if enemiesFolder == nil then
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = GameConfig.EnemyFolderName
	enemiesFolder.Parent = workspace
end

----------------------------------------------------------------
-- CONSTRUCTION D'UN MANNEQUIN
----------------------------------------------------------------
local function buildDummy(spawnCFrame)
	local model = Instance.new("Model")
	model.Name = "MannequinEntrainement"

	-- Torse = HumanoidRootPart (obligatoire pour un Humanoid)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 3, 1)
	root.Anchored = true -- statique : ne tombe pas, ne glisse pas
	root.Material = Enum.Material.SmoothPlastic
	root.Color = Color3.fromRGB(90, 70, 70)
	root.CFrame = spawnCFrame * CFrame.new(0, 2, 0) -- centre du torse à ~2 studs du sol
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	-- Tête
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Anchored = true
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(215, 185, 150)
	head.CFrame = root.CFrame * CFrame.new(0, 2.2, 0)
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.Parent = model

	-- Un visage simple (décor)
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = CONFIG.Health
	humanoid.Health = CONFIG.Health
	humanoid.DisplayName = "Mannequin"
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	model.PrimaryPart = root
	return model, humanoid
end

----------------------------------------------------------------
-- APPARITION + RÉAPPARITION
----------------------------------------------------------------
local function spawnDummy(spawnCFrame)
	local model, humanoid = buildDummy(spawnCFrame)
	model.Parent = enemiesFolder

	-- Tag "Enemy" : MainServer branche alors la mort du mannequin sur l'XP
	-- de kill. (Le dossier Enemies le taguerait aussi, mais on le fait
	-- explicitement pour éviter toute course au démarrage.)
	CollectionService:AddTag(model, GameConfig.EnemyTag)

	local respawned = false
	humanoid.Died:Connect(function()
		if respawned then
			return
		end
		respawned = true
		-- Petit effet de "chute" visuel avant de disparaître.
		task.delay(CONFIG.RespawnDelay, function()
			if model.Parent ~= nil then
				model:Destroy()
			end
			spawnDummy(spawnCFrame) -- un nouveau mannequin au même endroit
		end)
	end)

	return model
end

----------------------------------------------------------------
-- MISE EN PLACE EN CERCLE
----------------------------------------------------------------
local ring = CONFIG.Ring
for i = 1, ring.Count do
	local angle = (i - 1) * (2 * math.pi / ring.Count)
	local position = ring.Center + Vector3.new(
		math.cos(angle) * ring.Radius,
		ring.GroundY,
		math.sin(angle) * ring.Radius
	)
	-- Le mannequin regarde vers le centre.
	local lookAt = Vector3.new(ring.Center.X, position.Y, ring.Center.Z)
	spawnDummy(CFrame.lookAt(position, lookAt))
end

print(("[DummySpawner] %d mannequins d'entraînement en place."):format(ring.Count))
