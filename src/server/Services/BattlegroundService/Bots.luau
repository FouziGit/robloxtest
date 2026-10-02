--!strict
-- Bots: the Forgers' bodies (D-131). One R15 template per tier, built once from a HumanoidDescription in ink
-- with the tier's chalk bars on the chest, then cloned into a slot, owned by the server and walked by it.
--
-- A Forger is an unanchored humanoid the SERVER simulates (SetNetworkOwner(nil)): no client can take it over,
-- move it or delete it, and every position the service reads off it is one the server computed. Nothing here
-- decides anything -- BotBrain does, and the service applies it.
--
-- A body outlives its death by BotConfig.CorpseSeconds and keeps its tag until it is destroyed: the kill
-- effect a player wears (CosmeticService) and the kill credit both find it by model, in whatever order the
-- engine fires Died and CombatService fires Killed. How a living body moves -- thrown, slowed, walked, turned,
-- animated -- is Motion.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local AnimationConfig = require(Shared.Config.AnimationConfig)
local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BotBrain = require(script.Parent.Parent.Parent.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Context = require(script.Parent.Context)
local Log = require(Shared.Util.Log)
local Map = require(script.Parent.Map)
local Palette = require(Shared.Util.Palette)
local Trove = require(Packages.Trove)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("Battleground.Bots")

-- A throw in progress: the flat velocity it carries and how far through its duration the mover has gone.
export type Shove = { Velocity: Vector3, StartedAt: number, Duration: number, Alpha: number }
export type Bot = {
	Slot: number,
	TierId: string,
	Def: BotConfig.TierDef,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	-- Its spawn point, in the page's frame: where it walks back to and heals with nobody to chase.
	Home: BotBrain.Point,
	-- The pit a spar's Forger fights in, nil for one of the page's (Pits): whom its blows may reach, and when.
	Pit: Context.PitGround?,
	Memory: BotBrain.Memory,
	Tracks: { [string]: AnimationTrack },
	-- The attack or flinch clip playing now, stopped when a stagger cuts it.
	Action: AnimationTrack?,
	Mover: LinearVelocity,
	Shove: Shove?,
	-- Each glyph's slow on it, by glyph id (BotBrain.addSlow): it walks at the strongest one still running.
	Slows: { [string]: BotBrain.Slow },
	-- Damage each player dealt it (user id -> points), for the assists (BotBrain.creditedUsers).
	Ledger: { [number]: number },
	Dead: boolean,
	Credited: boolean,
	DiedAt: number,
	DestroyAt: number,
	-- An attack clip waiting for its start (ClipAt), so its blow lands on the server's resolve.
	PendingClip: string?,
	ClipAt: number,
	ClipSpeed: number,
	Walking: boolean,
	-- The last walk order: the goal it was for, when it was issued, and the point the humanoid walks to.
	Goal: Vector3?,
	GoalAt: number,
	Waypoint: Vector3?,
	Trove: Context.TroveType,
}

local HUMANOID = BotConfig.Humanoid
local LOCOMOTION = BotConfig.Locomotion
local FORGERS = WorldConfig.Forgers
local FADE_SECONDS = Context.FadeSeconds
local WALK = Context.WalkTrack
local IDLE = Context.IdleTrack

local Bots = {}

local handle: Map.Handle
local folder: Folder
local templates: { [string]: Model } = {}
local isReady = false
local bySlot: { [number]: Bot } = {}
local byModel: { [Model]: Bot } = {}
-- Slot -> when the Forger it held fell. Absent: the slot may be filled at once.
local vacant: { [number]: number } = {}

local function rebuildFolder(parent: Instance, name: string): Folder
	local previous = parent:FindFirstChild(name)
	if previous ~= nil then
		previous:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

----------------------------------------------------------------
-- Templates
----------------------------------------------------------------

-- A body of ink: every limb the Body role, no accessory, no face.
local function description(): HumanoidDescription
	local body = Palette.world(FORGERS.Body)
	local described = Instance.new("HumanoidDescription")
	described.HeadColor = body
	described.TorsoColor = body
	described.LeftArmColor = body
	described.RightArmColor = body
	described.LeftLegColor = body
	described.RightLegColor = body
	return described
end

-- The tier's chalk bars, welded to the UpperTorso's front: what tells the three Forgers apart, never a colour.
local function markChest(model: Model, tierId: string)
	local torso = model:FindFirstChild("UpperTorso")
	if torso == nil or not torso:IsA("BasePart") then
		error(("the %s rig has no UpperTorso to mark"):format(tierId))
	end
	local bars = FORGERS.Marks[tierId]
	if bars == nil then
		error(("WorldConfig.Forgers has no mark for %s"):format(tierId))
	end
	for index, bar in ipairs(bars) do
		local part = Instance.new("Part")
		part.Name = "Mark" .. index
		part.Size = Palette.vector(bar.Size)
		part.CFrame = torso.CFrame * CFrame.new(Palette.vector(bar.Offset))
		part.Color = Palette.world(FORGERS.Mark)
		part.Material = Palette.material()
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
end

-- One tier's body. The engine builds the rig (the call yields); everything that would run on it is removed --
-- the Animate script would fight the server's clips, a Health script its own regeneration -- and it is dressed
-- in the world's one material, marked, scaled and given an Animator the server plays through.
local function buildTemplate(tierId: string, def: BotConfig.TierDef): Model
	local model = Players:CreateHumanoidModelFromDescription(description(), Enum.HumanoidRigType.R15)
	model.Name = tierId
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Material = Palette.material()
		end
	end
	local head = model:FindFirstChild("Head")
	local face = if head ~= nil then head:FindFirstChild("face") else nil
	if face ~= nil then
		face:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		error(("the %s rig has no Humanoid"):format(tierId))
	end
	-- No name: the server cannot word one in each player's language. The bar shows once it is hurt.
	humanoid.DisplayName = ""
	humanoid.NameDisplayDistance = HUMANOID.NameDisplayDistance
	humanoid.HealthDisplayDistance = HUMANOID.HealthDisplayDistance
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	-- The body comes apart when it falls, which is what a corpse is for its CorpseSeconds.
	humanoid.BreakJointsOnDeath = true
	if humanoid:FindFirstChildOfClass("Animator") == nil then
		Instance.new("Animator").Parent = humanoid
	end
	markChest(model, tierId)
	if def.Scale ~= 1 then
		model:ScaleTo(def.Scale)
	end
	return model
end

-- Builds every tier's template into ServerStorage. Yields (the engine builds each rig), so the service runs it
-- in its own thread. Throws on the first tier that cannot be built: the Battleground then stays closed
-- (Bots.ready), because a page missing one of its Forgers is a half feature.
function Bots.buildTemplates(): boolean
	local storage = rebuildFolder(ServerStorage, Context.TemplatesFolderName)
	for tierId, def in pairs(BotConfig.Tiers) do
		local model = buildTemplate(tierId, def)
		model.Parent = storage
		templates[tierId] = model
	end
	isReady = true
	return true
end

function Bots.ready(): boolean
	return isReady
end

----------------------------------------------------------------
-- Spawn, death, removal
----------------------------------------------------------------

local function loadTrack(
	tracks: { [string]: AnimationTrack },
	animator: Animator,
	name: string,
	id: string,
	looped: boolean,
	priority: Enum.AnimationPriority
)
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	log.try("LoadAnimation " .. name, function()
		local track = animator:LoadAnimation(animation)
		track.Looped = looped
		track.Priority = priority
		tracks[name] = track
	end)
end

-- The clips a Forger plays: the stock walk and idle, the players' own melee chain, the generic cast and the
-- flinch. A clip that is not uploaded yet has no track, and the blow lands on its tell alone.
local function loadTracks(humanoid: Humanoid): { [string]: AnimationTrack }
	local tracks: { [string]: AnimationTrack } = {}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		log.warn("a Forger has no Animator: it moves without clips")
		return tracks
	end
	loadTrack(tracks, animator, WALK, LOCOMOTION.Walk, true, Enum.AnimationPriority.Movement)
	loadTrack(tracks, animator, IDLE, LOCOMOTION.Idle, true, Enum.AnimationPriority.Idle)
	for _, action in ipairs({ "Melee", "Cast", "Flinch" }) do
		for index, name in ipairs(AnimationConfig.Actions[action]) do
			local clip = AnimationConfig.clipFor(action, index)
			if clip ~= nil then
				local priority = (Enum.AnimationPriority :: any)[clip.Priority]
				if typeof(priority) == "EnumItem" then
					loadTrack(tracks, animator, name, clip.Id, clip.Looped, priority :: Enum.AnimationPriority)
				end
			end
		end
	end
	return tracks
end

-- The throw: one velocity constraint on the root, off until a shove turns it on. Motion.shove bounds its force
-- by the body's mass (BotConfig.ShoveForcePerMass): an unbounded one flings a body through the walls.
local function buildMover(root: BasePart): LinearVelocity
	local attachment = Instance.new("Attachment")
	attachment.Name = "ShoveAttachment"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Shove"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = Vector3.zero
	mover.Enabled = false
	mover.Parent = root
	return mover
end

-- Where a new Forger stands: the frame it is put down at, its spawn point in the page's frame, and the pit it
-- fights in (nil on the page).
export type Placement = { Frame: CFrame, Home: BotBrain.Point, Pit: Context.PitGround? }

-- A Forger of `tierId` put down as `placement` says, registered by its model: CombatService's signals find it, the
-- page's slots do not. nil (logged) when the template is missing or its clone has no humanoid body.
local function build(slot: number, tierId: string, placement: Placement): Bot?
	local template: Model? = templates[tierId]
	local def: BotConfig.TierDef? = BotConfig.Tiers[tierId]
	if template == nil or def == nil then
		log.warn("slot %d: no template for %s", slot, tostring(tierId))
		return nil
	end
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild(Context.RootPartName)
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		log.warn("slot %d: the %s template lost its humanoid body", slot, tierId)
		model:Destroy()
		return nil
	end
	CollectionService:AddTag(model, BotConfig.Tag)
	humanoid.MaxHealth = def.Health
	humanoid.Health = def.Health
	humanoid.WalkSpeed = def.WalkSpeed
	-- Per body: a humanoid's enabled states are not part of what a clone copies.
	for _, name in ipairs(HUMANOID.DisabledStates) do
		local state = (Enum.HumanoidStateType :: any)[name]
		if typeof(state) == "EnumItem" then
			humanoid:SetStateEnabled(state :: Enum.HumanoidStateType, false)
		end
	end
	model.Parent = folder
	-- A scaled body stands taller: its root sits Scale times as high as a standing one's.
	local lift = BattlegroundConfig.StandingRootStuds * (def.Scale - 1)
	model:PivotTo(placement.Frame + Vector3.yAxis * lift)
	log.try("SetNetworkOwner " .. tierId, function()
		root:SetNetworkOwner(nil)
	end)

	local trove = Trove.new()
	trove:Add(model)
	local bot: Bot = {
		Slot = slot,
		TierId = tierId,
		Def = def,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Home = placement.Home,
		Pit = placement.Pit,
		Memory = BotBrain.newMemory(),
		Tracks = loadTracks(humanoid),
		Action = nil,
		Mover = buildMover(root),
		Shove = nil,
		Slows = {},
		Ledger = {},
		Dead = false,
		Credited = false,
		DiedAt = 0,
		DestroyAt = 0,
		PendingClip = nil,
		ClipAt = 0,
		ClipSpeed = 1,
		Walking = false,
		Goal = nil,
		GoalAt = 0,
		Waypoint = nil,
		Trove = trove,
	}
	trove:Connect(humanoid.Died, function()
		Bots.kill(bot, os.clock())
	end)
	local idle: AnimationTrack? = bot.Tracks[IDLE]
	if idle ~= nil then
		idle:Play(FADE_SECONDS)
	end
	byModel[model] = bot
	return bot
end

-- Puts a Forger of `tierId` in `slot`, standing on spawn marker `spawnIndex`. nil (logged) when the template is
-- missing, the marker is, or its clone has no humanoid body.
function Bots.spawn(slot: number, tierId: string, spawnIndex: number): Bot?
	local marker: BasePart? = handle.BotSpawns[spawnIndex]
	if marker == nil then
		log.warn("slot %d: no spawn %d", slot, spawnIndex)
		return nil
	end
	local bot = build(slot, tierId, { Frame = marker.CFrame, Home = handle.Layout.BotSpawns[spawnIndex], Pit = nil })
	if bot ~= nil then
		bySlot[slot] = bot
		vacant[slot] = nil
	end
	return bot
end

-- Puts the Forger of a pit (Pits) down: in no slot of the page's, so the page's tick, its population and its count
-- never see it. `slot` is the pit's own tell id, past every slot of the page's.
function Bots.spawnInPit(slot: number, tierId: string, placement: Placement): Bot?
	return build(slot, tierId, placement)
end

-- Marks a Forger dead: from its Died event, a fall, or the kill plane (none of them credited here -- a kill is
-- credited by model from CombatService.Killed, whichever of the two arrives first). The body stays a corpse for
-- CorpseSeconds, out of every query, still tagged; the tick destroys it at DestroyAt.
function Bots.kill(bot: Bot, now: number)
	if bot.Dead then
		return
	end
	bot.Dead = true
	bot.DiedAt = now
	bot.DestroyAt = now + BotConfig.CorpseSeconds
	bot.PendingClip = nil
	bot.Shove = nil
	bot.Mover.Enabled = false
	for _, track in pairs(bot.Tracks) do
		track:Stop(FADE_SECONDS)
	end
	for _, descendant in ipairs(bot.Model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
		end
	end
	if bot.Humanoid.Health > 0 then
		bot.Humanoid.Health = 0
	end
end

-- Removes the body and frees its slot. A slot freed by a death refills after the respawn delay counted from
-- the death; one freed alive (an idle page emptied) refills at once.
function Bots.destroy(bot: Bot)
	if bySlot[bot.Slot] == bot then
		bySlot[bot.Slot] = nil
		if bot.Dead then
			vacant[bot.Slot] = bot.DiedAt
		else
			vacant[bot.Slot] = nil
		end
	end
	byModel[bot.Model] = nil
	bot.Trove:Destroy()
end

function Bots.destroyAll()
	for _, bot in ipairs(Bots.all()) do
		Bots.destroy(bot)
	end
end

function Bots.byModel(model: Model): Bot?
	return byModel[model]
end

function Bots.bySlot(slot: number): Bot?
	return bySlot[slot]
end

-- When the Forger `slot` held fell; nil when the slot may be filled at once.
function Bots.vacantSince(slot: number): number?
	return vacant[slot]
end

-- Every body, dead or alive, in slot order.
function Bots.all(): { Bot }
	local list: { Bot } = {}
	for slot = 1, BotConfig.MaxBots do
		local bot = bySlot[slot]
		if bot ~= nil then
			table.insert(list, bot)
		end
	end
	return list
end

-- How many Forgers stand on the page.
function Bots.standing(): number
	local count = 0
	for _, bot in pairs(bySlot) do
		if not bot.Dead then
			count += 1
		end
	end
	return count
end

function Bots.Init(map: Map.Handle)
	handle = map
	folder = rebuildFolder(Workspace, BotConfig.FolderName)
end

return Bots
