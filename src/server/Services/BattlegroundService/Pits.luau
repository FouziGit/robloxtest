--!strict
-- Pits: where a practice duel is fought (E10-S6, SparService). Walled floors in the page's own frame, east of it,
-- one player against one Duelist Forger in each (BattlegroundConfig.Pits). Built once at Start, like the page, and
-- never released: about ten parts each.
--
-- A pit is lent to one player at a time (acquire, release). Each round its Forger is put down fresh on its pad and
-- the player's new body on theirs (seat), and its blows land only while the round is on (setLive). The Forger is
-- one of the Forgers (Bots), thought for by BotBrain like the page's -- the service's tick steps it -- and what
-- its blows may reach is asked of the pit, not of the roster (Context.PitGround, Attacks.strikeable).
--
-- The solids -- the floor and the walls -- carry MovementGuardConfig.BarrierTag, as the page's do; the pads are
-- only positions, never parts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Attacks = require(script.Parent.Attacks)
local BattlegroundConfig = require(Shared.Config.BattlegroundConfig)
local BotBrain = require(script.Parent.Parent.Parent.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Bots = require(script.Parent.Bots)
local Context = require(script.Parent.Context)
local MatchConfig = require(Shared.Config.MatchConfig)
local Motion = require(script.Parent.Motion)
local MovementGuardConfig = require(script.Parent.Parent.Parent.Config.MovementGuardConfig)
local Palette = require(Shared.Util.Palette)
local Roster = require(script.Parent.Roster)
local Trove = require(Packages.Trove)
local WorldConfig = require(Shared.Config.WorldConfig)

type Bot = Bots.Bot
type Member = Roster.Member

export type Pit = {
	Index: number,
	-- Its Forger's tell id, past every slot of the page's.
	Slot: number,
	Ground: Context.PitGround,
	-- Where the player's root stands on their pad, and where the Forger is put down, facing it.
	Landing: Vector3,
	ForgerFrame: CFrame,
	ForgerHome: BotBrain.Point,
	-- What an idle Forger faces: the player's pad, in the page's frame.
	FaceX: number,
	FaceZ: number,
	Owner: Player?,
	Member: Member?,
	Bot: Bot?,
}

local PITS = BattlegroundConfig.Pits
local MAP = BattlegroundConfig.Map
local ANCHORS = BattlegroundConfig.Anchors
local ARENA = WorldConfig.Arena
local TIER = MatchConfig.Spar.TierId
local STANDING = BattlegroundConfig.StandingRootStuds

local Pits = {}

local deps: Context.Deps
local pits: { Pit } = {}

-- One box of a pit: what it is called, how big, where its centre stands in the world, and its WorldConfig colour.
type Box = { Name: string, Size: Vector3, Position: Vector3, Role: string }

-- A solid: it collides, stops a query and is a barrier to the movement audit; nothing touches it.
local function solid(box: Box, parent: Instance): Part
	local block = Instance.new("Part")
	block.Name = box.Name
	block.Size = box.Size
	block.CFrame = CFrame.new(box.Position)
	block.Anchored = true
	block.Color = Palette.world(box.Role)
	block.Material = Palette.material()
	block.TopSurface = Enum.SurfaceType.Smooth
	block.BottomSurface = Enum.SurfaceType.Smooth
	block.CanTouch = false
	CollectionService:AddTag(block, MovementGuardConfig.BarrierTag)
	block.Parent = parent
	return block
end

-- One pit's floor, its four walls and their ink rules, round (x, 0) of the page's frame; its top face at the page's.
local function buildPit(index: number, x: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = ANCHORS.Pit .. index
	local size, height, thickness = PITS.Size, PITS.WallHeight, PITS.WallThickness
	local floor = solid({
		Name = ANCHORS.Floor,
		Size = Vector3.new(size, MAP.FloorThickness, size),
		Position = Context.toWorld(x, -MAP.FloorThickness / 2, 0),
		Role = ARENA.Floor,
	}, model)
	model.PrimaryPart = floor
	local span = size + thickness * 2
	local offset = size / 2 + thickness / 2
	local rule = ARENA.WallRuleStuds
	local proud = ARENA.WallRuleProudStuds
	for _, wall in ipairs({
		{ Name = "WallNorth", Size = Vector3.new(span, height, thickness), X = x, Z = -offset },
		{ Name = "WallSouth", Size = Vector3.new(span, height, thickness), X = x, Z = offset },
		{ Name = "WallWest", Size = Vector3.new(thickness, height, span), X = x - offset, Z = 0 },
		{ Name = "WallEast", Size = Vector3.new(thickness, height, span), X = x + offset, Z = 0 },
	}) do
		solid({
			Name = wall.Name,
			Size = wall.Size,
			Position = Context.toWorld(wall.X, height / 2, wall.Z),
			Role = ARENA.Wall,
		}, model)
		-- The border of the sheet, raised and widened a hair past the wall's top face: coplanar faces flicker.
		solid({
			Name = wall.Name .. "Rule",
			Size = wall.Size + Vector3.new(proud, 0, proud) - Vector3.new(0, wall.Size.Y - rule, 0),
			Position = Context.toWorld(wall.X, height - rule / 2 + proud, wall.Z),
			Role = ARENA.WallRule,
		}, model)
	end
	model.Parent = parent

	local playerX = x + size / 2 - PITS.PadInsetStuds
	local forgerX = x - size / 2 + PITS.PadInsetStuds
	local ground: Context.PitGround = {
		Live = false,
		Member = nil,
		Bounds = { MinX = x - size / 2, MaxX = x + size / 2, MinZ = -size / 2, MaxZ = size / 2 },
	}
	local forgerAt = Context.toWorld(forgerX, STANDING, 0)
	table.insert(pits, {
		Index = index,
		Slot = BotConfig.MaxBots + index,
		Ground = ground,
		Landing = Context.toWorld(playerX, STANDING, 0),
		ForgerFrame = CFrame.lookAt(forgerAt, Context.toWorld(playerX, STANDING, 0)),
		ForgerHome = { X = forgerX, Z = 0 },
		FaceX = playerX,
		FaceZ = 0,
		Owner = nil,
		Member = nil,
		Bot = nil,
	})
end

-- Builds every pit, replacing any previous ones.
function Pits.build()
	local previous = Workspace:FindFirstChild(ANCHORS.Pits)
	if previous ~= nil then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ANCHORS.Pits
	table.clear(pits)
	for index = 1, PITS.Count do
		buildPit(index, PITS.FirstX + (index - 1) * PITS.SpacingX, folder)
	end
	folder.Parent = Workspace
end

-- The pit `player` holds, or nil.
function Pits.of(player: Player): Pit?
	for _, pit in ipairs(pits) do
		if pit.Owner == player then
			return pit
		end
	end
	return nil
end

-- Every pit a player holds.
function Pits.occupied(): { Pit }
	local held: { Pit } = {}
	for _, pit in ipairs(pits) do
		if pit.Owner ~= nil then
			table.insert(held, pit)
		end
	end
	return held
end

-- The Forger's wind-up that will never land now -- its round stopped, or its body is being replaced -- taken back
-- from every client that drew it.
local function drop(bot: Bot)
	if bot.Memory.Attack ~= nil then
		bot.Memory.Attack = nil
		Attacks.retract(bot)
	end
end

local function clear(pit: Pit)
	local bot = pit.Bot
	pit.Bot = nil
	if bot ~= nil then
		drop(bot)
		Bots.destroy(bot)
	end
	local member = pit.Member
	pit.Member = nil
	pit.Ground.Member = nil
	pit.Ground.Live = false
	if member ~= nil then
		member.Trove:Destroy()
	end
end

-- Lends `player` a free pit: the one they hold already, or the first nobody does. nil when every pit is taken.
function Pits.acquire(player: Player): Pit?
	local held = Pits.of(player)
	if held ~= nil then
		return held
	end
	for _, pit in ipairs(pits) do
		if pit.Owner == nil then
			pit.Owner = player
			return pit
		end
	end
	return nil
end

-- Gives the pit back: its Forger removed, its duellist forgotten.
function Pits.release(pit: Pit)
	clear(pit)
	pit.Owner = nil
end

-- Sets a round up: a fresh Forger on its pad at full health and the owner's `character` on theirs, facing it, with
-- trust re-anchored there (Roster.place). The round is not on yet (setLive). Returns false when the Forger could
-- not be put down.
function Pits.seat(pit: Pit, player: Player, character: Model, now: number): boolean
	clear(pit)
	local bot = Bots.spawnInPit(pit.Slot, TIER, { Frame = pit.ForgerFrame, Home = pit.ForgerHome, Pit = pit.Ground })
	if bot == nil then
		return false
	end
	pit.Bot = bot
	Roster.place(player, character, pit.Landing)
	local member: Member = {
		Player = player,
		UserId = player.UserId,
		ArrivedAt = now,
		Landing = pit.Landing,
		Defeated = 0,
		OffFloorSince = nil,
		OutsideCampAt = now,
		Trove = Trove.new(),
	}
	pit.Member = member
	pit.Ground.Member = member
	return true
end

-- Starts or stops the round: while it is off the Forger stands where it is and no blow of its lands.
function Pits.setLive(pit: Pit, live: boolean)
	pit.Ground.Live = live
	local bot = pit.Bot
	if live or bot == nil or bot.Dead then
		return
	end
	drop(bot)
	Motion.stand(bot)
	Motion.release(bot)
end

-- The pit's Forger as the round reads it: standing or not, and its health.
function Pits.forger(pit: Pit): (boolean, number, number)
	local bot = pit.Bot
	if bot == nil or bot.Dead then
		return false, 0, if bot ~= nil then bot.Humanoid.MaxHealth else 0
	end
	return true, bot.Humanoid.Health, bot.Humanoid.MaxHealth
end

-- Whether `player` holds a pit and stands on its floor, by the position the server trusts.
function Pits.holds(player: Player): boolean
	local pit = Pits.of(player)
	if pit == nil then
		return false
	end
	local trusted = deps.Combat.trustedPosition(player)
	return trusted ~= nil and Context.insideRect(pit.Ground.Bounds, trusted)
end

function Pits.Init(injected: Context.Deps)
	deps = injected
end

return Pits
