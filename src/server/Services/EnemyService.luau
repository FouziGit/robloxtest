--!strict
-- EnemyService: training dummies in a ring around the spawn. Builds anchored Humanoid models tagged
-- GameConfig.Enemy.Tag, credits the killer that CombatService recorded in the model attribute
-- LastAttackerUserId, and rebuilds each dummy in its slot after the respawn delay.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Util.Palette)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("EnemyService")

type ProfileData = Types.ProfileData
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> () }
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> () }
type Deps = { DataService: DataApi, Notify: NotifyApi, Progression: ProgressionApi, Currency: CurrencyApi }
type TroveType = typeof(Trove.new())
type Dummy = { Model: Model, Trove: TroveType, Slot: number }

local ENEMIES_FOLDER = "Enemies"
local DUMMY_NAME = "TrainingDummy"
-- Written by CombatService on every damaging hit, read once on death, then cleared.
local LAST_ATTACKER_ATTRIBUTE = "LastAttackerUserId"
local ROOT_SIZE = Vector3.new(2, 3, 1)
local HEAD_SIZE = Vector3.new(1.4, 1.4, 1.4)
local HEAD_OFFSET = Vector3.new(0, 2.2, 0)
-- A proof (docs/ART_BIBLE.md: Épreuve): a blank figure wearing a registration cross, roles of
-- WorldConfig.Proof (D-86).
local PROOF = WorldConfig.Proof

local EnemyService = {}

local dataService: DataApi
local notify: NotifyApi
local progression: ProgressionApi
local currency: CurrencyApi

local folder: Folder
local slots: { CFrame } = {}
-- Live dummies keyed by model: the hook registry (a model in here has its Died handler bound).
local hooked: { [Model]: Dummy } = {}

local spawnDummy: (slot: number) -> ()

local function ensureFolder(): Folder
	local existing = Workspace:FindFirstChild(ENEMIES_FOLDER)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = ENEMIES_FOLDER
	created.Parent = Workspace
	return created
end

-- Ring centre and ground height: the first SpawnLocation in the workspace, else the origin.
local function ringCenter(): (Vector3, number)
	local found = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if found ~= nil and found:IsA("SpawnLocation") then
		return found.Position, found.Position.Y + found.Size.Y / 2
	end
	return Vector3.zero, 0
end

local function computeSlots(): { CFrame }
	local center, groundY = ringCenter()
	local count = GameConfig.Enemy.DummyCount
	local radius = GameConfig.Enemy.DummyRingRadius
	local result = {}
	for index = 1, count do
		local angle = (index - 1) * (2 * math.pi / count)
		local position = Vector3.new(
			center.X + math.cos(angle) * radius,
			groundY + ROOT_SIZE.Y / 2,
			center.Z + math.sin(angle) * radius
		)
		local lookAt = Vector3.new(center.X, position.Y, center.Z)
		table.insert(result, CFrame.lookAt(position, lookAt))
	end
	return result
end

local function buildDummy(rootCFrame: CFrame): (Model, Humanoid)
	local model = Instance.new("Model")
	model.Name = DUMMY_NAME

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE
	root.Anchored = true
	root.Material = Palette.material()
	root.Color = Palette.world(PROOF.Body)
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.CFrame = rootCFrame
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = HEAD_SIZE
	head.Anchored = true
	head.Material = Palette.material()
	head.Color = Palette.world(PROOF.Head)
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.CFrame = rootCFrame * CFrame.new(HEAD_OFFSET)
	head.Parent = model

	-- The registration cross on the chest: two ink bars, the thing a printer aims at on a proof.
	local arm = PROOF.MarkStuds
	local markCFrame = rootCFrame * CFrame.new(Palette.vector(PROOF.MarkOffset))
	for index, size in ipairs({ Vector3.new(arm[1], arm[2], arm[3]), Vector3.new(arm[2], arm[1], arm[3]) }) do
		local bar = Instance.new("Part")
		bar.Name = "Mark" .. index
		bar.Size = size
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.Material = Palette.material()
		bar.Color = Palette.world(PROOF.Mark)
		bar.TopSurface = Enum.SurfaceType.Smooth
		bar.BottomSurface = Enum.SurfaceType.Smooth
		bar.CFrame = markCFrame
		bar.Parent = model
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = GameConfig.Enemy.DummyHealth
	humanoid.Health = GameConfig.Enemy.DummyHealth
	-- A nameplate cannot be localized per viewer from the server, so none is shown.
	humanoid.DisplayName = ""
	humanoid.NameDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model

	model.PrimaryPart = root
	CollectionService:AddTag(model, GameConfig.Enemy.Tag)
	return model, humanoid
end

local function creditKiller(model: Model)
	local attackerId = model:GetAttribute(LAST_ATTACKER_ATTRIBUTE)
	if type(attackerId) ~= "number" then
		return
	end
	local killer = Players:GetPlayerByUserId(attackerId)
	if killer == nil then
		return
	end
	local data = dataService.get(killer)
	if data == nil then
		return
	end
	local xp = ProgressionConfig.XP.DummyKill
	progression.addXp(killer, xp, "DummyKill")
	currency.add(killer, ProgressionConfig.Folios.DummyKill, "DummyKill")
	data.Stats.Kills += 1
	dataService.push(killer, "Stats")
	notify.send(killer, "hud.killReward", { xp = xp }, "Success", "Kill")
end

-- Unhooks the dummy and rebuilds it in its slot after the respawn delay.
local function scheduleRespawn(dummy: Dummy)
	task.delay(GameConfig.Enemy.DummyRespawnSeconds, function()
		dummy.Trove:Destroy()
		spawnDummy(dummy.Slot)
	end)
end

local function onDied(dummy: Dummy)
	if hooked[dummy.Model] ~= dummy then
		return
	end
	hooked[dummy.Model] = nil
	-- A corpse is no longer a target.
	CollectionService:RemoveTag(dummy.Model, GameConfig.Enemy.Tag)
	creditKiller(dummy.Model)
	dummy.Model:SetAttribute(LAST_ATTACKER_ATTRIBUTE, nil)
	scheduleRespawn(dummy)
end

-- The model was destroyed while alive (outside this service): rebuild it without credit.
local function onDestroyed(dummy: Dummy)
	if hooked[dummy.Model] ~= dummy then
		return
	end
	hooked[dummy.Model] = nil
	log.warn("dummy %d destroyed externally, respawning", dummy.Slot)
	scheduleRespawn(dummy)
end

spawnDummy = function(slot: number)
	local model, humanoid = buildDummy(slots[slot])
	local trove = Trove.new()
	local dummy: Dummy = { Model = model, Trove = trove, Slot = slot }
	trove:Add(model)
	trove:Connect(humanoid.Died, function()
		onDied(dummy)
	end)
	trove:Connect(model.Destroying, function()
		onDestroyed(dummy)
	end)
	hooked[model] = dummy
	model.Parent = folder
end

function EnemyService.Init(deps: Deps)
	dataService = deps.DataService
	notify = deps.Notify
	progression = deps.Progression
	currency = deps.Currency
end

function EnemyService.Start()
	folder = ensureFolder()
	slots = computeSlots()
	for slot = 1, #slots do
		spawnDummy(slot)
	end
	log.info("%d training dummies spawned", #slots)
end

return EnemyService
