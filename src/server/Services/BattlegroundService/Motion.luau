--!strict
-- Motion: how a living Forger moves (D-131), applied by the service from BotBrain's orders and from what
-- CombatService announces. Thrown by a knockback (Shoved), slowed by a glyph (Controlled), walked around the
-- page's obstacles, stopped, turned toward its aim, and animated: a clip for each blow, timed so the blow lands
-- on the server's resolve, and the stock walk and idle switched by its real speed.
--
-- Every actuator runs on the service's tick or in the handler of the event that asked for it: nothing here
-- starts a timer or a thread, so a Forger that dies or is staggered stops everything it was doing at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local AnimationConfig = require(Shared.Config.AnimationConfig)
local BattlegroundLayout = require(Shared.Pure.BattlegroundLayout)
local BotBrain = require(Shared.Pure.BotBrain)
local BotConfig = require(Shared.Config.BotConfig)
local Bots = require(script.Parent.Bots)
local Context = require(script.Parent.Context)
local FeelConfig = require(Shared.Config.FeelConfig)
local FeelMath = require(Shared.Pure.FeelMath)
local GameConfig = require(Shared.Config.GameConfig)
local Map = require(script.Parent.Map)

type Bot = Bots.Bot

local LOCOMOTION = BotConfig.Locomotion
local PATH = BotConfig.Path
local TICK_SECONDS = 1 / GameConfig.Server.TickRate
local KNOCKBACK_EXPONENT = FeelConfig.Impulse.KnockbackExponent
local FADE_SECONDS = Context.FadeSeconds
local WALK = Context.WalkTrack
local IDLE = Context.IdleTrack
local FLINCH = AnimationConfig.Actions.Flinch[1]
-- Below this a direction has no length to turn toward.
local EPSILON = 1e-3
-- A facing already within this cosine of the one asked is left alone, so standing still never jitters.
local FACE_TOLERANCE = math.cos(math.rad(5))

local Motion = {}

local handle: Map.Handle

----------------------------------------------------------------
-- Being thrown, being slowed
----------------------------------------------------------------

-- Sets the velocity for the tick about to run: the impulse curve's mean over that tick's share of the throw
-- (FeelMath.impulseStep), so the ticks add up to exactly the distance of the flat velocity -- sampling the
-- curve at each tick's start instead overshot by a third. Off on the tick after the throw is spent.
function Motion.stepMover(bot: Bot, now: number)
	local shove = bot.Shove
	if shove == nil then
		return
	end
	if shove.Alpha >= 1 then
		bot.Shove = nil
		bot.Mover.Enabled = false
		return
	end
	local alpha = math.min(1, (now + TICK_SECONDS - shove.StartedAt) / shove.Duration)
	bot.Mover.VectorVelocity = shove.Velocity * FeelMath.impulseStep(shove.Alpha, alpha, KNOCKBACK_EXPONENT)
	shove.Alpha = alpha
end

-- Throws the body along `velocity` for `duration`, starting now, replacing any throw in progress.
function Motion.shove(bot: Bot, velocity: Vector3, duration: number, now: number)
	local finite = velocity.Magnitude == velocity.Magnitude and velocity.Magnitude < math.huge
	if bot.Dead or not finite or not (duration > 0 and duration < math.huge) then
		return
	end
	bot.Shove = { Velocity = velocity, StartedAt = now, Duration = duration, Alpha = 0 }
	bot.Mover.MaxForce = bot.Root.AssemblyMass * BotConfig.ShoveForcePerMass
	bot.Mover.Enabled = true
	Motion.stepMover(bot, now)
end

-- Walks the body at its tier's pace times its strongest slow still running; the tier's own pace once none is.
local function pace(bot: Bot, now: number)
	local speed = bot.Def.WalkSpeed * BotBrain.slowFactor(bot.Slows, now)
	if bot.Humanoid.WalkSpeed ~= speed then
		bot.Humanoid.WalkSpeed = speed
	end
end

-- Slows the body to `factor` of its tier's pace for `seconds`, under the glyph `key`: kept apart from every
-- other glyph's slow, as a player's are (BotBrain.addSlow), so a root ends on its own time.
function Motion.slow(bot: Bot, key: string, factor: number, seconds: number, now: number)
	BotBrain.addSlow(bot.Slows, key, factor, seconds, now)
	pace(bot, now)
end

-- Each tick while any slow runs: the one that ran out lets go, and the pace follows the strongest left.
function Motion.stepSlow(bot: Bot, now: number)
	if next(bot.Slows) ~= nil then
		pace(bot, now)
	end
end

----------------------------------------------------------------
-- Clips
----------------------------------------------------------------

-- Plays an action clip (an attack or the flinch), replacing the one before it.
function Motion.play(bot: Bot, clipName: string, speed: number)
	local track: AnimationTrack? = bot.Tracks[clipName]
	if track == nil then
		return
	end
	local current = bot.Action
	if current ~= nil and current ~= track then
		current:Stop(FADE_SECONDS)
	end
	track:Play(FADE_SECONDS, 1, speed)
	bot.Action = track
end

-- Starts the attack clip the wind-up scheduled, on the tick it is due: never through a timer, so a stagger
-- that cancels the attack cancels its clip with it.
function Motion.stepClip(bot: Bot, now: number)
	local name = bot.PendingClip
	if name ~= nil and now >= bot.ClipAt then
		bot.PendingClip = nil
		Motion.play(bot, name, bot.ClipSpeed)
	end
end

-- A stagger: the attack clip it cut stops, and the body takes the blow.
function Motion.flinch(bot: Bot)
	bot.PendingClip = nil
	local clip = AnimationConfig.Clips[FLINCH]
	Motion.play(bot, FLINCH, if clip ~= nil then clip.Speed else 1)
end

-- Walk or idle, switched only when the body's horizontal speed crosses WalkClipThreshold: the walk plays at
-- the tier's pace over the pace the stock walk is keyed for, and is never re-timed on every step.
function Motion.stepLocomotion(bot: Bot)
	local velocity = bot.Root.AssemblyLinearVelocity
	local walking = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > PATH.WalkClipThreshold
	if walking == bot.Walking then
		return
	end
	bot.Walking = walking
	local walk: AnimationTrack?, idle: AnimationTrack? = bot.Tracks[WALK], bot.Tracks[IDLE]
	if walking then
		if idle ~= nil then
			idle:Stop(FADE_SECONDS)
		end
		if walk ~= nil then
			walk:Play(FADE_SECONDS, 1, bot.Def.WalkSpeed / LOCOMOTION.WalkReferenceSpeed)
		end
	else
		if walk ~= nil then
			walk:Stop(FADE_SECONDS)
		end
		if idle ~= nil then
			idle:Play(FADE_SECONDS)
		end
	end
end

----------------------------------------------------------------
-- Walking, standing, facing
----------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The point to walk to now on the way to (x, z) of the page's frame: the goal itself when the way there is
-- clear, else the furthest waypoint of the shortest way round (BattlegroundLayout.path) it can walk to straight,
-- so it never walks back to a node behind it. nil when the graph has no way there.
local function nextStep(bot: Bot, x: number, z: number): Vector3?
	local layout = handle.Layout
	local bx, _, bz = Context.toLocal(bot.Root.Position)
	local goal = Context.toWorld(x, 0, z)
	if BattlegroundLayout.segmentClear(layout, bx, bz, x, z) then
		return goal
	end
	local from = BattlegroundLayout.nearestNode(layout, bx, bz)
	local to = BattlegroundLayout.nearestNode(layout, x, z)
	local route = if from ~= nil and to ~= nil then BattlegroundLayout.path(layout, from, to) else nil
	if route == nil then
		return nil
	end
	local step = 1
	for index = #route, 2, -1 do
		local node = layout.Nodes[route[index]]
		if BattlegroundLayout.segmentClear(layout, bx, bz, node.X, node.Z) then
			step = index
			break
		end
	end
	local node = layout.Nodes[route[step]]
	local point = Context.toWorld(node.X, 0, node.Z)
	if flatDistance(point, bot.Root.Position) > PATH.WaypointReachedStuds then
		return point
	end
	-- Standing on that waypoint already: on to the next one, or, past the last, straight to a goal that hugs an
	-- obstacle.
	local following = route[step + 1]
	if following == nil then
		return goal
	end
	local nextNode = layout.Nodes[following]
	return Context.toWorld(nextNode.X, 0, nextNode.Z)
end

-- Walks toward (x, z) of the page's frame, never into the camp. The order is re-issued only when the goal
-- moved RepathStuds, after RepathSeconds, or on reaching the waypoint it walks to -- a path is searched at most
-- a couple of times a second per Forger.
function Motion.walkTo(bot: Bot, x: number, z: number, now: number)
	local gx, gz = BattlegroundLayout.clampOutOfCamp(handle.Layout, x, z)
	local goal = Context.toWorld(gx, 0, gz)
	local previous, waypoint = bot.Goal, bot.Waypoint
	local moved = previous == nil or flatDistance(previous, goal) > PATH.RepathStuds
	local stale = now - bot.GoalAt >= PATH.RepathSeconds
	local reached = waypoint ~= nil and flatDistance(waypoint, bot.Root.Position) <= PATH.WaypointReachedStuds
	if not (moved or stale or reached) then
		return
	end
	bot.Goal = goal
	bot.GoalAt = now
	local step = nextStep(bot, gx, gz)
	bot.Waypoint = step
	if step ~= nil then
		bot.Humanoid:MoveTo(step)
	else
		bot.Humanoid:MoveTo(bot.Root.Position)
	end
end

-- Stops where it stands. Re-issued on every think it stands through: a body thrown while standing would
-- otherwise walk back to where the throw found it.
function Motion.stand(bot: Bot)
	bot.Goal = nil
	bot.Waypoint = nil
	bot.Humanoid:MoveTo(bot.Root.Position)
end

-- Turns the body toward (x, z) of the page's frame. `hold`: a wind-up is showing, so the humanoid must not turn
-- it back on its own until the blow has landed.
function Motion.face(bot: Bot, x: number, z: number, hold: boolean)
	bot.Humanoid.AutoRotate = not hold
	local root = bot.Root
	local point = Context.toWorld(x, 0, z)
	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	if flat.Magnitude < EPSILON then
		return
	end
	local direction = flat.Unit
	local look = root.CFrame.LookVector
	if Vector3.new(look.X, 0, look.Z).Unit:Dot(direction) >= FACE_TOLERANCE then
		return
	end
	root.CFrame = CFrame.lookAlong(root.Position, direction)
end

-- Lets the humanoid turn the body again once no wind-up holds it.
function Motion.release(bot: Bot)
	bot.Humanoid.AutoRotate = true
end

function Motion.Init(map: Map.Handle)
	handle = map
end

return Motion
