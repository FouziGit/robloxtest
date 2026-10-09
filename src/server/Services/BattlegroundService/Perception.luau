--!strict
-- Perception: what a Forger knows when it thinks (D-131), gathered by the server and handed to BotBrain as
-- plain numbers in the page's frame. Members only -- nobody outside the Battleground is ever a target -- and
-- each one where the server believes they stand (Context.targetPoint), never merely where their client says.
--
-- Sight is three rays at most per think (the current target and the two nearest others), head to head over
-- the page's own parts and the glyph walls, through one cached set of parameters (Map.SightParams).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BattlegroundLayout = require(script.Parent.Parent.Parent.Pure.BattlegroundLayout)
local BotBrain = require(script.Parent.Parent.Parent.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Bots = require(script.Parent.Bots)
local Context = require(script.Parent.Context)
local Map = require(script.Parent.Map)
local Roster = require(script.Parent.Roster)

type Bot = Bots.Bot
type Member = Roster.Member
-- A member as every Forger sees them this tick: where (the page's frame), in the camp, on the ground.
export type Seen = { Member: Member, Point: Vector3, X: number, Y: number, Z: number, InCamp: boolean, Down: boolean }
-- User id -> the Forgers chasing them: slot and distance, for the load and the ranks.
export type Engaged = { [number]: { { Index: number, Distance: number } } }

local REACH = BotConfig.Reach
-- Besides its current target, a Forger looks at this many of the nearest members per think: three rays at most.
local LOOKED_NEAREST = 2
-- The page's centre, in its own frame: what an idle Forger faces.
local CENTER: BotBrain.Point = { X = 0, Z = 0 }

local Perception = {}

local deps: Context.Deps
local handle: Map.Handle

local function flatDistance(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
end

-- Where a Forger sees `member`, or nil while they have no live body.
function Perception.see(member: Member): Seen?
	local point = Context.targetPoint(deps.Combat, member.Player)
	if point == nil then
		return nil
	end
	local x, y, z = Context.toLocal(point)
	return {
		Member = member,
		Point = point,
		X = x,
		-- How high over the ground they stand on, as the Forger's own (Perception.perceive): the raised place's
		-- steps are no escape from a Forger that walks up them.
		Y = y - BattlegroundLayout.groundAt(handle.Layout, x, z),
		Z = z,
		InCamp = BattlegroundLayout.inRect(handle.Layout.Camp, x, z),
		Down = deps.Movement.isDown(member.Player),
	}
end

-- Every member with a live body, where a Forger sees them.
function Perception.survey(): { Seen }
	local seen: { Seen } = {}
	for _, member in ipairs(Roster.list()) do
		local entry = Perception.see(member)
		if entry ~= nil then
			table.insert(seen, entry)
		end
	end
	return seen
end

-- Who chases whom, from every Forger's memory at the start of the tick.
function Perception.engagement(bots: { Bot }, seen: { Seen }): Engaged
	local byUser: { [number]: Seen } = {}
	for _, entry in ipairs(seen) do
		byUser[entry.Member.UserId] = entry
	end
	local engaged: Engaged = {}
	for _, bot in ipairs(bots) do
		local userId = bot.Memory.TargetUserId
		local target = if userId ~= nil then byUser[userId] else nil
		if userId ~= nil and target ~= nil then
			local list = engaged[userId] or {}
			engaged[userId] = list
			local x, _, z = Context.toLocal(bot.Root.Position)
			table.insert(list, { Index = bot.Slot, Distance = flatDistance(x, z, target.X, target.Z) })
		end
	end
	return engaged
end

-- Every wind-up pending right now, the ones started earlier in this same tick included: two Forgers thinking
-- on one tick must never both start a chain on the same player.
local function pendingAttacks(bots: { Bot }): { BotBrain.Attack }
	local pending: { BotBrain.Attack } = {}
	for _, bot in ipairs(bots) do
		local attack = bot.Memory.Attack
		if attack ~= nil and not bot.Dead then
			table.insert(pending, attack)
		end
	end
	return pending
end

-- A ray from head to head, stopped by the page and by glyph walls only.
local function sees(from: Vector3, to: Vector3): boolean
	local eyes = Vector3.yAxis * REACH.SightHeightStuds
	local origin = from + eyes
	return Workspace:Raycast(origin, to + eyes - origin, handle.SightParams) == nil
end

-- The members this Forger looks at this think: its current target and the two nearest others. Three rays at
-- most; everyone else counts as unseen until they come closer.
local function lookedAt(bot: Bot, x: number, z: number, seen: { Seen }): { [number]: boolean }
	local looked: { [number]: boolean } = {}
	local current = bot.Memory.TargetUserId
	if current ~= nil then
		looked[current] = true
	end
	local others = table.clone(seen)
	table.sort(others, function(a: Seen, b: Seen): boolean
		return flatDistance(x, z, a.X, a.Z) < flatDistance(x, z, b.X, b.Z)
	end)
	local picked = 0
	for _, entry in ipairs(others) do
		if picked >= LOOKED_NEAREST then
			break
		end
		if entry.Member.UserId ~= current then
			looked[entry.Member.UserId] = true
			picked += 1
		end
	end
	return looked
end

-- What one Forger knows this think (BotBrain.Perception): every member it could chase, how many others chase
-- each and its rank among them, whether a melee chain may start on each (`restUntil`: user id -> the end of
-- their rest after the last chain), and where it stands, lives and faces when idle.
function Perception.perceive(
	bot: Bot,
	now: number,
	seen: { Seen },
	engaged: Engaged,
	bots: { Bot },
	restUntil: { [number]: number }
): BotBrain.Perception
	local x, y, z = Context.toLocal(bot.Root.Position)
	local looked = lookedAt(bot, x, z, seen)
	local pending = pendingAttacks(bots)
	local targets: { BotBrain.Target } = {}
	local rankFor: { [number]: number } = {}
	local tokenFreeFor: { [number]: boolean } = {}
	for _, entry in ipairs(seen) do
		local userId = entry.Member.UserId
		local others: { { Index: number, Distance: number } } = {}
		for _, other in ipairs(engaged[userId] or {}) do
			if other.Index ~= bot.Slot then
				table.insert(others, other)
			end
		end
		table.insert(targets, {
			UserId = userId,
			X = entry.X,
			Y = entry.Y,
			Z = entry.Z,
			Visible = looked[userId] == true and sees(bot.Root.Position, entry.Point),
			InCamp = entry.InCamp,
			Down = entry.Down,
			ArrivedAt = entry.Member.ArrivedAt,
			Load = #others,
		})
		rankFor[userId] = BotBrain.engagedRank(bot.Slot, flatDistance(x, z, entry.X, entry.Z), others)
		tokenFreeFor[userId] = BotBrain.tokenFree(pending, restUntil[userId] or 0, userId, now)
	end
	local perception: BotBrain.Perception = {
		Now = now,
		Index = bot.Slot,
		X = x,
		Y = y - BattlegroundLayout.groundAt(handle.Layout, x, z),
		Z = z,
		HomeX = bot.Home.X,
		HomeZ = bot.Home.Z,
		CenterX = CENTER.X,
		CenterZ = CENTER.Z,
		Targets = targets,
		RankFor = rankFor,
		TokenFreeFor = tokenFreeFor,
	}
	return perception
end

function Perception.Init(injected: Context.Deps, map: Map.Handle)
	deps = injected
	handle = map
end

return Perception
