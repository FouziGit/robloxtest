--[[
	JutsuEffects.lua — ModuleScript
	EMPLACEMENT : ServerScriptService > Modules > JutsuEffects

	Implémentation SERVEUR des effets de chaque jutsu (physique, dégâts,
	visuels). Chaque fonction porte le nom référencé par le champ
	"Effect" dans JutsuConfig et reçoit (player, character, jutsuDef).

	Pour AJOUTER UN JUTSU : écris ici une nouvelle fonction
	JutsuEffects.MonEffet = function(player, character, def) ... end
	puis référence Effect = "MonEffet" dans JutsuConfig.

	Tout est exécuté côté serveur : les dégâts sont autoritaires,
	un exploiteur ne peut pas les falsifier.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

local JutsuEffects = {}

local EFFECT_TAG = "JutsuEffect" -- marque les parts créées ici (ignorées par les collisions de jutsus)

----------------------------------------------------------------
-- OUTILS PARTAGÉS
----------------------------------------------------------------

-- Inflige des dégâts avec attribution (pour l'XP de kill) et respect du réglage PvP.
local function dealDamage(casterPlayer, humanoid, damage)
	if damage <= 0 or humanoid.Health <= 0 then
		return
	end
	local model = humanoid.Parent
	if model == nil then
		return
	end

	local targetPlayer = Players:GetPlayerFromCharacter(model)
	if targetPlayer == casterPlayer then
		return -- jamais de dégâts sur soi-même
	end
	if targetPlayer ~= nil and not GameConfig.PvPEnabled then
		return -- PvP désactivé : on ne touche pas les autres joueurs
	end

	-- Attribution du dernier attaquant : MainServer lit cet attribut
	-- quand un ennemi meurt pour créditer l'XP de kill.
	model:SetAttribute("LastAttackerUserId", casterPlayer.UserId)
	humanoid:TakeDamage(damage)
end

-- Retourne la liste des Humanoids (dédupliqués) dans une sphère,
-- en excluant le lanceur et les parts d'effets de jutsus.
local function getHumanoidsInRadius(position, radius, casterCharacter)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { casterCharacter }

	local parts = workspace:GetPartBoundsInRadius(position, radius, params)
	local humanoids = {}
	local seenModels = {}

	for _, part in ipairs(parts) do
		if not CollectionService:HasTag(part, EFFECT_TAG) then
			local model = part:FindFirstAncestorOfClass("Model")
			if model ~= nil and not seenModels[model] then
				seenModels[model] = true
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid ~= nil and humanoid.Health > 0 then
					table.insert(humanoids, humanoid)
				end
			end
		end
	end
	return humanoids
end

-- Crée une part d'effet avec les réglages communs.
local function createEffectPart(props)
	local part = Instance.new("Part")
	part.Anchored = props.Anchored ~= false
	part.CanCollide = props.CanCollide == true
	part.CanQuery = false
	part.CastShadow = false
	part.Material = props.Material or Enum.Material.Neon
	part.Color = props.Color or Color3.new(1, 1, 1)
	part.Size = props.Size or Vector3.new(1, 1, 1)
	part.CFrame = props.CFrame or CFrame.new()
	part.Transparency = props.Transparency or 0
	part.Shape = props.Shape or Enum.PartType.Block
	part.Name = props.Name or "JutsuEffect"
	CollectionService:AddTag(part, EFFECT_TAG)
	part.Parent = workspace
	return part
end

-- Position et direction de lancer devant le personnage.
local function getCastOrigin(character)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return nil, nil
	end
	return rootPart.CFrame, rootPart.CFrame.LookVector
end

----------------------------------------------------------------
-- FEU + FEU : BOULE DE FEU (projectile explosif)
----------------------------------------------------------------
function JutsuEffects.Fireball(player, character, def)
	local rootCFrame, direction = getCastOrigin(character)
	if rootCFrame == nil then
		return
	end

	local ball = createEffectPart({
		Name = "BouleDeFeu",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.5, 2.5, 2.5),
		Color = GameConfig.ElementColors.Feu,
		CFrame = rootCFrame * CFrame.new(0, 1, -4),
		Anchored = false,
		CanCollide = false,
	})

	local fire = Instance.new("Fire")
	fire.Heat = 12
	fire.Size = 6
	fire.Parent = ball

	local attachment = Instance.new("Attachment")
	attachment.Parent = ball
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = direction * 90
	velocity.Parent = ball

	pcall(function()
		ball:SetNetworkOwner(nil) -- trajectoire contrôlée par le serveur
	end)

	local exploded = false
	local function explode()
		if exploded or ball.Parent == nil then
			return
		end
		exploded = true

		local blastPosition = ball.Position
		local blast = createEffectPart({
			Name = "Explosion",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			Color = Color3.fromRGB(255, 170, 60),
			CFrame = CFrame.new(blastPosition),
			Transparency = 0.2,
		})
		TweenService:Create(blast, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(12, 12, 12),
			Transparency = 1,
		}):Play()
		Debris:AddItem(blast, 0.5)
		ball:Destroy()

		for _, humanoid in ipairs(getHumanoidsInRadius(blastPosition, 7, character)) do
			dealDamage(player, humanoid, def.Damage)
		end
	end

	ball.Touched:Connect(function(hit)
		if hit:IsDescendantOf(character) then
			return
		end
		if CollectionService:HasTag(hit, EFFECT_TAG) then
			return
		end
		explode()
	end)

	-- Sécurité : explose au bout de 3 s même sans impact.
	task.delay(3, explode)
end

----------------------------------------------------------------
-- EAU + EAU : VAGUE AQUATIQUE (mur d'eau qui avance)
----------------------------------------------------------------
function JutsuEffects.WaterWave(player, character, def)
	local rootCFrame, direction = getCastOrigin(character)
	if rootCFrame == nil then
		return
	end

	local wave = createEffectPart({
		Name = "VagueAquatique",
		Size = Vector3.new(12, 6, 3),
		Color = GameConfig.ElementColors.Eau,
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CFrame = rootCFrame * CFrame.new(0, 1, -6),
	})

	local damagedModels = {} -- chaque cible n'est touchée qu'une fois par vague
	local travelTime = 0.8
	local travelDistance = 40

	TweenService:Create(wave, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		CFrame = wave.CFrame * CFrame.new(0, 0, -travelDistance),
		Transparency = 0.85,
	}):Play()

	task.spawn(function()
		local elapsed = 0
		while elapsed < travelTime and wave.Parent ~= nil do
			for _, humanoid in ipairs(getHumanoidsInRadius(wave.Position, 8, character)) do
				local model = humanoid.Parent
				if model and not damagedModels[model] then
					damagedModels[model] = true
					dealDamage(player, humanoid, def.Damage)
				end
			end
			elapsed += task.wait(0.1)
		end
	end)

	Debris:AddItem(wave, travelTime + 0.1)
end

----------------------------------------------------------------
-- TERRE + TERRE : PIQUES DE TERRE (ligne de piques devant)
----------------------------------------------------------------
function JutsuEffects.EarthSpikes(player, character, def)
	local rootCFrame, direction = getCastOrigin(character)
	if rootCFrame == nil then
		return
	end

	local basePosition = rootCFrame.Position - Vector3.new(0, 2.5, 0)
	local damagedModels = {}

	for i = 1, 5 do
		task.delay((i - 1) * 0.08, function()
			local spikePosition = basePosition + direction * (6 + i * 5)
			local spike = createEffectPart({
				Name = "PiqueDeTerre",
				Size = Vector3.new(3, 8, 3),
				Color = GameConfig.ElementColors.Terre,
				Material = Enum.Material.Slate,
				CFrame = CFrame.new(spikePosition - Vector3.new(0, 8, 0))
					* CFrame.Angles(math.rad(math.random(-12, 12)), 0, math.rad(math.random(-12, 12))),
			})

			-- La pique jaillit du sol...
			TweenService:Create(spike, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = spike.CFrame * CFrame.new(0, 8, 0),
			}):Play()

			for _, humanoid in ipairs(getHumanoidsInRadius(spikePosition + Vector3.new(0, 3, 0), 5, character)) do
				local model = humanoid.Parent
				if model and not damagedModels[model] then
					damagedModels[model] = true
					dealDamage(player, humanoid, def.Damage)
				end
			end

			-- ...puis se rétracte.
			task.delay(1.5, function()
				if spike.Parent ~= nil then
					TweenService:Create(spike, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						CFrame = spike.CFrame * CFrame.new(0, -8, 0),
					}):Play()
				end
			end)
			Debris:AddItem(spike, 2)
		end)
	end
end

----------------------------------------------------------------
-- VENT + VENT : RAFALE TRANCHANTE (repoussée en cône)
----------------------------------------------------------------
function JutsuEffects.WindGust(player, character, def)
	local rootCFrame, direction = getCastOrigin(character)
	if rootCFrame == nil then
		return
	end

	local gust = createEffectPart({
		Name = "RafaleTranchante",
		Size = Vector3.new(4, 4, 4),
		Color = GameConfig.ElementColors.Vent,
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
		CFrame = rootCFrame * CFrame.new(0, 0, -4),
	})
	TweenService:Create(gust, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(18, 10, 18),
		CFrame = gust.CFrame * CFrame.new(0, 0, -8),
		Transparency = 1,
	}):Play()
	Debris:AddItem(gust, 0.5)

	local centerPosition = (rootCFrame * CFrame.new(0, 0, -10)).Position
	for _, humanoid in ipairs(getHumanoidsInRadius(centerPosition, 12, character)) do
		dealDamage(player, humanoid, def.Damage)

		local model = humanoid.Parent
		local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
		if targetRoot ~= nil then
			local pushDirection = (targetRoot.Position - rootCFrame.Position)
			pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
			if pushDirection.Magnitude > 0.01 then
				pushDirection = pushDirection.Unit
				targetRoot.AssemblyLinearVelocity = pushDirection * 70 + Vector3.new(0, 30, 0)
			end
		end
	end
end

----------------------------------------------------------------
-- EAU + FEU : BRUME BOUILLANTE (zone de dégâts + ralentissement)
----------------------------------------------------------------
function JutsuEffects.BoilingMist(player, character, def)
	local rootCFrame, direction = getCastOrigin(character)
	if rootCFrame == nil then
		return
	end

	local mistCenter = (rootCFrame * CFrame.new(0, 0, -12)).Position
	local mist = createEffectPart({
		Name = "BrumeBouillante",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(16, 8, 16),
		Color = Color3.fromRGB(200, 210, 220),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.6,
		CFrame = CFrame.new(mistCenter),
	})
	local smoke = Instance.new("Smoke")
	smoke.Size = 8
	smoke.Opacity = 0.25
	smoke.RiseVelocity = 2
	smoke.Parent = mist

	local SLOW_ATTRIBUTE = "BrumeSlow"
	local tickCount = 3

	task.spawn(function()
		for _ = 1, tickCount do
			if mist.Parent == nil then
				break
			end
			for _, humanoid in ipairs(getHumanoidsInRadius(mistCenter, 9, character)) do
				dealDamage(player, humanoid, def.Damage)

				-- Ralentissement temporaire, sans cumul entre brumes.
				if humanoid:GetAttribute(SLOW_ATTRIBUTE) == nil and humanoid.Health > 0 then
					humanoid:SetAttribute(SLOW_ATTRIBUTE, humanoid.WalkSpeed)
					humanoid.WalkSpeed = math.max(4, humanoid.WalkSpeed * 0.4)
					task.delay(2.5, function()
						local originalSpeed = humanoid:GetAttribute(SLOW_ATTRIBUTE)
						if originalSpeed ~= nil then
							humanoid.WalkSpeed = originalSpeed
							humanoid:SetAttribute(SLOW_ATTRIBUTE, nil)
						end
					end)
				end
			end
			task.wait(1)
		end
	end)

	task.delay(3, function()
		if mist.Parent ~= nil then
			TweenService:Create(mist, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(mist, 4)
end

----------------------------------------------------------------
-- EAU + EAU + TERRE : MUR DE BOUE (défensif — le combo signature)
----------------------------------------------------------------
function JutsuEffects.MudWall(player, character, def)
	local rootCFrame, direction = getCastOrigin(character)
	if rootCFrame == nil then
		return
	end

	local wallCFrame = rootCFrame * CFrame.new(0, 0, -8)
	-- On aligne le mur face au joueur, posé au sol.
	local groundY = rootCFrame.Position.Y - 2.5

	local wall = createEffectPart({
		Name = "MurDeBoue",
		Size = Vector3.new(14, 9, 2.5),
		Color = Color3.fromRGB(110, 80, 50),
		Material = Enum.Material.Mud,
		CanCollide = true,
		CFrame = CFrame.new(wallCFrame.Position.X, groundY - 4.5, wallCFrame.Position.Z)
			* CFrame.Angles(0, math.atan2(-direction.X, -direction.Z), 0),
	})

	-- Le mur surgit du sol.
	TweenService:Create(wall, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = wall.CFrame * CFrame.new(0, 9, 0),
	}):Play()

	-- Puis s'effondre après 8 secondes.
	task.delay(8, function()
		if wall.Parent ~= nil then
			wall.CanCollide = false
			TweenService:Create(wall, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = wall.CFrame * CFrame.new(0, -9, 0),
				Transparency = 1,
			}):Play()
		end
	end)
	Debris:AddItem(wall, 9)
end

----------------------------------------------------------------
-- FEU + FEU + VENT : TEMPÊTE DE BRAISES (anneau de feu autour du lanceur)
----------------------------------------------------------------
function JutsuEffects.EmberStorm(player, character, def)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end

	local ring = createEffectPart({
		Name = "TempeteDeBraises",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 24, 24),
		Color = GameConfig.ElementColors.Feu,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CFrame = rootPart.CFrame * CFrame.Angles(0, 0, math.rad(90)), -- cylindre à plat
	})
	local fire = Instance.new("Fire")
	fire.Heat = 15
	fire.Size = 10
	fire.Parent = ring

	local tickCount = 3
	task.spawn(function()
		for tickIndex = 1, tickCount do
			if ring.Parent == nil or rootPart.Parent == nil then
				break
			end
			ring.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, math.rad(tickIndex * 40), math.rad(90))
			for _, humanoid in ipairs(getHumanoidsInRadius(rootPart.Position, 13, character)) do
				dealDamage(player, humanoid, def.Damage)
			end
			task.wait(0.8)
		end
		if ring.Parent ~= nil then
			TweenService:Create(ring, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(ring, tickCount * 0.8 + 0.6)
end

----------------------------------------------------------------
-- TERRE + TERRE + TERRE : SÉISME (AoE massive + projection)
----------------------------------------------------------------
function JutsuEffects.Earthquake(player, character, def)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end
	local epicenter = rootPart.Position

	-- Onde de choc visuelle : trois anneaux successifs.
	for i = 1, 3 do
		task.delay((i - 1) * 0.12, function()
			local shockwave = createEffectPart({
				Name = "OndeDeChoc",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 4, 4),
				Color = GameConfig.ElementColors.Terre,
				Material = Enum.Material.Slate,
				Transparency = 0.2,
				CFrame = CFrame.new(epicenter - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			})
			TweenService:Create(shockwave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.4, 36, 36),
				Transparency = 1,
			}):Play()
			Debris:AddItem(shockwave, 0.6)
		end)
	end

	for _, humanoid in ipairs(getHumanoidsInRadius(epicenter, 18, character)) do
		dealDamage(player, humanoid, def.Damage)

		-- Projection verticale
		local model = humanoid.Parent
		local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
		if targetRoot ~= nil then
			targetRoot.AssemblyLinearVelocity = Vector3.new(
				targetRoot.AssemblyLinearVelocity.X,
				60,
				targetRoot.AssemblyLinearVelocity.Z
			)
		end
	end
end

return JutsuEffects
