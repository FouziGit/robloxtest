--!strict
-- MovementAudit: the server's side of the movement guard. Characters are simulated by their owning clients, so
-- every replicated root position is the client's word; once per CombatService tick this module measures what the
-- server can see around each body -- whether something holds it up, what it touched, which barrier the step
-- since it was last seen outside every barrier went into, the surfaces it could have landed on, the round trip,
-- whether the client is still sending, whether the server itself stalled -- and hands it to Pure/MovementGuard,
-- which judges.
-- Then it acts on the verdict, as far as MovementGuardConfig.Mode lets it: Observe only logs, Correct also
-- pivots a body back to a point it was believed at, Enforce also strikes.
--
-- Nothing here trusts what the client writes about its own body: support is the server's spherecast, never
-- FloorMaterial or the Humanoid's state, and no velocity is ever read (tests/MovementGates.spec.luau). The only
-- client value is the root position itself, which is what is being judged.
--
-- No loop of its own: CombatService calls step once per tick, and owns the records' lifecycle (add, remove,
-- spawned, teleported, grant) because it owns every server-authored move. Its thresholds live in
-- src/server/Config, where no client reads them.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local BotConfig = require(Shared.Config.BotConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local MovementGuard = require(script.Parent.Parent.Pure.MovementGuard)
local MovementGuardConfig = require(script.Parent.Parent.Config.MovementGuardConfig)
local StunWatch = require(script.Parent.Parent.Pure.StunWatch)
local WorldBossConfig = require(Shared.Config.WorldBossConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

local log = Log.new("Combat.MovementAudit")
-- One body's audit is a step of its own, logged at most once per body per GameConfig.Server.FaultLogSeconds.
local faults = log.faults(GameConfig.Server.FaultLogSeconds)

export type Deps = {
	AntiCheat: {
		strike: (
			player: Player,
			source: string,
			reason: string,
			kind: ("Schema" | "RateLimit" | "Origin" | "Movement")?
		) -> (),
	},
	Movement: {
		isDown: (player: Player) -> boolean,
		-- When the running stun began and when it ends, on os.clock; 0, 0 when none runs.
		stunDates: (player: Player) -> (number, number),
	},
	Registry: { lastInbound: (player: Player) -> number },
	-- CombatService re-anchors OriginGuard's trusted position on a point this module pulled a body back to.
	Reanchor: (player: Player, position: Vector3) -> (),
	-- Where the engine puts a new body: the root of this character standing on the hub's SpawnLocation, nil with
	-- none.
	SpawnPoint: (character: Model) -> Vector3?,
}

type Record = {
	Player: Player,
	Track: MovementGuard.Track,
	-- The body the track follows. Another one under the same player is not audited until spawned or teleported
	-- adopts it.
	Character: Model?,
	-- The round trip, held at its highest for RttHoldSeconds.
	RttValue: number,
	RttAt: number,
	-- Whether something holds it up this tick, the world or a body the world holds up (markSupport): another body
	-- may stand on this one only then.
	Supported: boolean,
	-- Last tick's verdict raised a flag, and where the root was: the co-moving rule of MovementGuard.touching.
	Flagged: boolean,
	HasLast: boolean,
	LastX: number,
	LastY: number,
	LastZ: number,
	-- The loop breaker.
	Corrections: { number },
	PausedUntil: number,
	-- When each kind (or rule) last struck, and when each heading and kind was last logged while only watched or
	-- observed.
	StruckAt: { [string]: number },
	LoggedAt: { [string]: number },
	-- Queries that leave the body itself out and pass through whatever does not collide.
	Probe: RaycastParams,
	Overlap: OverlapParams,
	-- What the body did through the stun that runs (watchStun).
	Stun: StunWatch.Watch,
}

-- One audited body on this tick.
type Body = {
	Record: Record,
	Character: Model,
	Root: BasePart,
	Humanoid: Humanoid?,
	X: number,
	Y: number,
	Z: number,
	-- Every coordinate a number within MaxCoordinateStuds: nothing else is fed to a spatial query.
	Sane: boolean,
	Contact: boolean,
}

local AUDIT = MovementGuardConfig
local ROOT_PART_NAME = "HumanoidRootPart"
-- The round trip is read as twice GetNetworkPing, the larger of the two things the engine may mean by it, until a
-- Studio check compares it with the Shift+F3 display.
local PINGS_PER_ROUND_TRIP = 2

local MovementAudit = {}

local deps: Deps
local config: MovementGuard.Config
local records: { [Player]: Record } = {}
-- Every audited body this tick, by character, so a probe that hits a player's body finds whose it is; and every
-- player's body, audited or not (dead, or not yet adopted), which holds nobody up on its own word.
local characters: { [Instance]: Record } = {}
local playerBodies: { [Instance]: true } = {}
-- The support probe that sees no player's body at all: what it finds is the world.
local worldProbe = RaycastParams.new()
worldProbe.FilterType = Enum.RaycastFilterType.Exclude
worldProbe.RespectCanCollide = true
-- Bodies the server owns and moves (MovementAudit.start keeps them from their tags): training proofs and
-- Forgers touch by their root, the Erasure's hull and the Margin walls by their box.
local npcs: { [Model]: true } = {}
local hulls: { [Model]: true } = {}
local walls: { [BasePart]: true } = {}
-- The geometry no body may pass through (MovementGuardConfig.BarrierTag), and the ray that only sees it.
local barriers: { [BasePart]: true } = {}
local barrierParams = RaycastParams.new()
barrierParams.FilterType = Enum.RaycastFilterType.Include
barrierParams.RespectCanCollide = true
local barriersChanged = true

----------------------------------------------------------------
-- Tagged bodies and barriers
----------------------------------------------------------------

-- Keeps `set` equal to the models tagged `tag` that stand in the Workspace (a template in ServerStorage is not a
-- body anyone can touch).
local function watchModels(tag: string, set: { [Model]: true })
	local function add(instance: Instance)
		if instance:IsA("Model") and instance:IsDescendantOf(Workspace) then
			set[instance] = true
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			set[instance] = nil
		end
	end)
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		add(instance)
	end
end

-- The same for parts, telling `changed` whenever the set does.
local function watchParts(tag: string, set: { [BasePart]: true }, changed: (() -> ())?)
	local function add(instance: Instance)
		if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
			set[instance] = true
			if changed ~= nil then
				changed()
			end
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			set[instance] = nil
			if changed ~= nil then
				changed()
			end
		end
	end)
	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		add(instance)
	end
end

local function noteBarriersChanged()
	barriersChanged = true
end

-- The barrier ray's filter, rebuilt only after a barrier came or went.
local function barrierFilter(): RaycastParams
	if barriersChanged then
		local list: { Instance } = {}
		for part in pairs(barriers) do
			table.insert(list, part)
		end
		barrierParams.FilterDescendantsInstances = list
		barriersChanged = false
	end
	return barrierParams
end

local function rootOf(model: Model): BasePart?
	local root: Instance? = model.PrimaryPart or model:FindFirstChild(ROOT_PART_NAME)
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

-- Whether `position` lies in `part`'s box grown by `margin` on every side.
local function insideGrown(part: BasePart, position: Vector3, margin: number): boolean
	local offset = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(offset.X) <= half.X + margin
		and math.abs(offset.Y) <= half.Y + margin
		and math.abs(offset.Z) <= half.Z + margin
end

-- A root against a body the server moves: never a grant (it could be banked without end), only contact.
local function nearServerBody(position: Vector3): boolean
	for model in pairs(npcs) do
		local root = rootOf(model)
		if root ~= nil and (root.Position - position).Magnitude <= AUDIT.ContactRadiusStuds then
			return true
		end
	end
	for model in pairs(hulls) do
		local hull = rootOf(model)
		if hull ~= nil and insideGrown(hull, position, AUDIT.ShoveMarginStuds) then
			return true
		end
	end
	for wall in pairs(walls) do
		if insideGrown(wall, position, AUDIT.ShoveMarginStuds) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------
-- Measures
----------------------------------------------------------------

local function sane(position: Vector3): boolean
	local limit = MovementGuardConfig.MaxCoordinateStuds
	return math.abs(position.X) <= limit and math.abs(position.Y) <= limit and math.abs(position.Z) <= limit
end

local function topOf(part: BasePart): number
	local _, _, _, _, _, _, r10, r11, r12 = part.CFrame:GetComponents()
	local size = part.Size
	return part.Position.Y + MovementGuard.halfHeight(r10, r11, r12, size.X, size.Y, size.Z)
end

-- The player's body `instance` is part of: its record when that body is audited this tick, and whether it is a
-- player's body at all.
local function bodyOf(instance: Instance): (Record?, boolean)
	local ancestor = instance.Parent
	while ancestor ~= nil and ancestor ~= Workspace do
		local owner = characters[ancestor]
		if owner ~= nil then
			return owner, true
		end
		if playerBodies[ancestor] then
			return nil, true
		end
		ancestor = ancestor.Parent
	end
	return nil, false
end

-- A surface counts unless it is a player's body that nothing holds up this tick: a torso a client detached and
-- parked in the air, two bodies propping each other up, a corpse.
local function holdsUp(instance: Instance): boolean
	local owner, isBody = bodyOf(instance)
	if owner ~= nil then
		return owner.Supported
	end
	return not isBody
end

-- A sphere cast straight down to `reach` studs past the feet of a body whose root, at `origin`, stands `stand`
-- high, from clear of its feet (MovementGuard.probe): a sphere that started inside the ground would not see it.
local function castDown(
	params: RaycastParams,
	origin: Vector3,
	stand: number,
	radius: number,
	reach: number
): RaycastResult?
	local lift, depth = MovementGuard.probe(stand, radius, reach, AUDIT.ProbeClearanceStuds)
	return Workspace:Spherecast(origin + Vector3.new(0, lift, 0), radius, Vector3.new(0, -depth, 0), params)
end

-- The support probe: whether something that collides is right under the feet.
local function supportedAt(record: Record, origin: Vector3, stand: number): boolean
	local hit = castDown(record.Probe, origin, stand, AUDIT.GroundProbeRadiusStuds, AUDIT.GroundProbeSlackStuds)
	return hit ~= nil and holdsUp(hit.Instance)
end

-- The standing root height of the ground under a server teleport's destination, nil with none within a jump's
-- fall of the feet. A pad drops a body 4 studs above its marker, which already stands a body's height over the
-- floor: the support probe, a stud and a half past the feet, does not reach it.
local function groundUnder(record: Record, destination: Vector3, stand: number): number?
	local hit = castDown(record.Probe, destination, stand, AUDIT.GroundProbeRadiusStuds, MovementGuard.maxRise(config))
	if hit == nil or not holdsUp(hit.Instance) then
		return nil
	end
	return hit.Position.Y + stand
end

-- How high a body's root stands over its feet, from the server's own Humanoid; a body whose Humanoid the client
-- detached is still audited on its root, as a default body.
local function standHeight(humanoid: Humanoid?, root: BasePart): number
	if humanoid == nil then
		return AUDIT.DefaultStandHeightStuds
	end
	return humanoid.HipHeight + root.Size.Y / 2
end

-- The same for a whole character, as a default body while it has no root: every avatar is judged from its own
-- standing height, a small one's root under 2 studs over its feet, an Rthro one's over 4.
function MovementAudit.standingHeight(character: Model): number
	local root = character:FindFirstChild(ROOT_PART_NAME)
	if root == nil or not root:IsA("BasePart") then
		return AUDIT.DefaultStandHeightStuds
	end
	return standHeight(character:FindFirstChildOfClass("Humanoid"), root)
end

local function walkSpeed(body: Body): number
	local humanoid = body.Humanoid
	return if humanoid ~= nil then humanoid.WalkSpeed else GameConfig.Movement.WalkSpeed
end

-- The round trip: the highest reading of the last RttHoldSeconds. It rises at once and falls late.
local function heldRtt(record: Record, now: number): number
	local measured = PINGS_PER_ROUND_TRIP * record.Player:GetNetworkPing()
	if measured >= record.RttValue or now - record.RttAt >= AUDIT.RttHoldSeconds then
		record.RttValue = measured
		record.RttAt = now
	end
	return record.RttValue
end

-- The barrier the step from where the last ray left the body outside every barrier to `position` went into, if
-- any, however long the step: after a long stall H1 lets over 200 studs of catch-up through, more with a grant.
local function crossing(track: MovementGuard.Track, position: Vector3): MovementGuard.Crossing?
	local ox, oy, oz = MovementGuard.rayOrigin(track)
	local origin = Vector3.new(ox, oy, oz)
	local hit = Workspace:Raycast(origin, position - origin, barrierFilter())
	if hit == nil then
		return nil
	end
	local part = hit.Instance
	local frame, half = part.CFrame, part.Size / 2
	local a = frame:PointToObjectSpace(origin)
	local b = frame:PointToObjectSpace(position)
	local floor = hit.Normal.Y > AUDIT.FloorNormalY
	return {
		HitY = hit.Position.Y,
		Top = topOf(part),
		Floor = floor,
		PassThrough = MovementGuard.passesThrough(floor, a.X, a.Y, a.Z, b.X, b.Y, b.Z, half.X, half.Y, half.Z, config),
		Inside = MovementGuard.insideBox(b.X, b.Y, b.Z, half.X, half.Y, half.Z),
		PlaneX = hit.Position.X,
		PlaneY = hit.Position.Y,
		PlaneZ = hit.Position.Z,
		NormalX = hit.Normal.X,
		NormalY = hit.Normal.Y,
		NormalZ = hit.Normal.Z,
	}
end

-- The path scan: the tops of every surface along the recent path a flight rule may have missed a landing on.
local function scan(record: Record, sample: MovementGuard.Sample): { number }
	local x0, y0, z0, x1, y1, z1 = MovementGuard.scanBox(record.Track, sample, config)
	local center = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	record.Overlap.MaxParts = AUDIT.ScanMaxParts
	local parts = Workspace:GetPartBoundsInBox(center, Vector3.new(x1 - x0, y1 - y0, z1 - z0), record.Overlap)
	local tops: { number } = {}
	for _, part in ipairs(parts) do
		if holdsUp(part) then
			table.insert(tops, topOf(part))
		end
	end
	return tops
end

-- Whether a body standing `stand` high fits at `point`: nothing that collides from just above its feet to above
-- its root.
local function fits(record: Record, point: Vector3, stand: number): boolean
	local bottom = point.Y - stand + AUDIT.ClearanceFootStuds
	local top = point.Y + AUDIT.ClearanceHeadStuds
	local width = 2 * AUDIT.BodyHalfWidthStuds
	record.Overlap.MaxParts = 1
	local blocking = Workspace:GetPartBoundsInBox(
		CFrame.new(point.X, (bottom + top) / 2, point.Z),
		Vector3.new(width, top - bottom, width),
		record.Overlap
	)
	return #blocking == 0
end

local function sampleOf(body: Body, now: number, hitch: boolean): MovementGuard.Sample
	local record = body.Record
	local stand = standHeight(body.Humanoid, body.Root)
	local position = body.Root.Position
	local sample: MovementGuard.Sample = {
		At = now,
		X = body.X,
		Y = body.Y,
		Z = body.Z,
		Supported = record.Supported,
		StandHeight = stand,
		Down = deps.Movement.isDown(record.Player),
		Contact = body.Contact,
		WalkSpeed = walkSpeed(body),
		Rtt = heldRtt(record, now),
		LastInboundAt = deps.Registry.lastInbound(record.Player),
		Hitch = hitch,
		Crossing = nil,
		SupportTops = nil,
	}
	if body.Sane then
		if MovementGuard.wantsRay(record.Track, sample, config) then
			sample.Crossing = crossing(record.Track, position)
		end
		if MovementGuard.preview(record.Track, sample, config) then
			sample.SupportTops = scan(record, sample)
		end
	end
	return sample
end

----------------------------------------------------------------
-- Acting on a verdict
----------------------------------------------------------------

local function keyOf(verdict: MovementGuard.Verdict): string
	return verdict.Kind or verdict.Rule
end

-- Strikes when the verdict may, the mode is Enforce and the kind has not struck within StrikeSpacingSeconds, and
-- says which of those it was, for the log.
local function strike(record: Record, verdict: MovementGuard.Verdict, now: number): string
	if not verdict.Strikeable then
		return "exempt"
	end
	if MovementGuardConfig.Mode ~= "Enforce" then
		return "would strike"
	end
	local key = keyOf(verdict)
	if now - (record.StruckAt[key] or -math.huge) < AUDIT.StrikeSpacingSeconds then
		return "strike spaced out"
	end
	record.StruckAt[key] = now
	deps.AntiCheat.strike(
		record.Player,
		"Movement",
		string.format("%s/%s: %.1f against %.1f", key, verdict.Rule, verdict.Measure, verdict.Budget),
		"Movement"
	)
	return "struck"
end

-- One line per verdict acted on. What is only watched or observed is `limited` to one line per heading and kind
-- per WatchLogIntervalSeconds, so a client that trips a rule every tick cannot flood the log, and the watch that
-- opens an incident never hides the correction that confirms it.
local function report(
	record: Record,
	verdict: MovementGuard.Verdict,
	now: number,
	heading: string,
	back: number,
	struck: string,
	limited: boolean
)
	local key = keyOf(verdict)
	if limited then
		local slot = heading .. " " .. key
		if now - (record.LoggedAt[slot] or -math.huge) < AUDIT.WatchLogIntervalSeconds then
			return
		end
		record.LoggedAt[slot] = now
	end
	local line = "%s %s (%s/%s): %.1f against %.1f, back %.0f studs; %s"
	local name, rule = record.Player.Name, verdict.Rule
	if verdict.Action == "Watch" then
		log.info(line, name, heading, key, rule, verdict.Measure, verdict.Budget, back, struck)
	else
		log.warn(line, name, heading, key, rule, verdict.Measure, verdict.Budget, back, struck)
	end
end

-- The confirm probe, before a flight is ever pulled down: wider and deeper than the support probe. Ground under
-- the body ends the incident where it stands, in every mode, so Observe logs what Correct would do.
local function groundBelow(body: Body, stand: number, now: number): boolean
	local record = body.Record
	local hit =
		castDown(record.Probe, body.Root.Position, stand, AUDIT.ConfirmProbeRadiusStuds, AUDIT.ConfirmProbeReachStuds)
	if hit == nil or not holdsUp(hit.Instance) then
		return false
	end
	MovementGuard.groundFound(record.Track, hit.Position.Y + stand, now)
	if now - (record.LoggedAt.Ground or -math.huge) >= AUDIT.WatchLogIntervalSeconds then
		record.LoggedAt.Ground = now
		log.info(
			"%s: a flight flag found ground %.1f studs under the root, nothing done",
			record.Player.Name,
			body.Y - hit.Position.Y
		)
	end
	return true
end

-- The first point a body fits at: the verdict's, then the points it was believed at, newest first (on the ground
-- only, for a flight).
local function clearTarget(record: Record, verdict: MovementGuard.Verdict, stand: number): Vector3?
	local first = Vector3.new(verdict.X, verdict.Y, verdict.Z)
	if fits(record, first, stand) then
		return first
	end
	for n = 1, AUDIT.SafeRing do
		local found, x, y, z = MovementGuard.safePoint(record.Track, n, verdict.Kind == "Flight")
		if not found then
			break
		end
		local point = Vector3.new(x, y, z)
		if fits(record, point, stand) then
			return point
		end
	end
	return nil
end

-- More than CorrectionBurstLimit corrections within CorrectionBurstSeconds: a loop the audit and a body are
-- caught in. Corrections stop for LoopPauseSeconds; flags and strikes go on, and the pause strikes nothing itself.
local function countCorrection(record: Record, now: number)
	local times = record.Corrections
	while #times > 0 and times[1] < now - AUDIT.CorrectionBurstSeconds do
		table.remove(times, 1)
	end
	table.insert(times, now)
	if #times > AUDIT.CorrectionBurstLimit then
		table.clear(times)
		record.PausedUntil = now + AUDIT.LoopPauseSeconds
		log.warn(
			"%s corrected more than %d times within %ds: corrections paused for %ds",
			record.Player.Name,
			AUDIT.CorrectionBurstLimit,
			AUDIT.CorrectionBurstSeconds,
			AUDIT.LoopPauseSeconds
		)
	end
end

-- Pulls the body back to a point it fits at, re-anchors both guards there, and tells the judge it was moved. The
-- origin violations CombatService counted are kept: a correction absolves nothing.
local function correct(body: Body, stand: number, verdict: MovementGuard.Verdict, now: number)
	local record = body.Record
	local target = clearTarget(record, verdict, stand)
	if target == nil then
		log.warn(
			"%s no clear point to correct %s/%s to: left where it is; %s",
			record.Player.Name,
			keyOf(verdict),
			verdict.Rule,
			strike(record, verdict, now)
		)
		return
	end
	local root = body.Root
	local track = record.Track
	local back = (target - root.Position).Magnitude
	local fromX, fromY, fromZ = MovementGuard.heard(track)
	body.Character:PivotTo(CFrame.new(target) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	deps.Reanchor(record.Player, target)
	-- A point the body was believed at: ground under it only as the support probe finds it, never from deeper.
	local groundY = if supportedAt(record, target, stand) then target.Y else nil
	MovementGuard.corrected(track, target.X, target.Y, target.Z, now, fromX, fromY, fromZ, groundY, config)
	countCorrection(record, now)
	report(record, verdict, now, "corrected", back, strike(record, verdict, now), false)
end

-- Puts the body on a server teleport's destination again: the judge still waits for it to arrive there, and the
-- teleport already anchored both guards on it; they are set back on it, since OriginGuard chased the stale
-- samples once the pivot's settle was over, and held there while this one settles.
local function repivot(body: Body, verdict: MovementGuard.Verdict, now: number)
	local record = body.Record
	local root = body.Root
	local destination = Vector3.new(verdict.X, verdict.Y, verdict.Z)
	local back = (destination - root.Position).Magnitude
	body.Character:PivotTo(CFrame.new(destination) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	deps.Reanchor(record.Player, destination)
	report(record, verdict, now, "repivoted", back, strike(record, verdict, now), false)
end

local function enforce(body: Body, sample: MovementGuard.Sample, verdict: MovementGuard.Verdict, now: number)
	local action = verdict.Action
	if action == "None" then
		return
	end
	local record = body.Record
	if action == "Correct" and verdict.Kind == "Flight" and groundBelow(body, sample.StandHeight, now) then
		return
	end
	local target = Vector3.new(verdict.X, verdict.Y, verdict.Z)
	local back = if action == "Watch" then 0 else (target - body.Root.Position).Magnitude
	if MovementGuardConfig.Mode == "Observe" then
		local heading = if action == "Watch" then "watch" else "observe " .. string.lower(action)
		report(record, verdict, now, heading, back, strike(record, verdict, now), true)
		return
	end
	if action == "Watch" then
		report(record, verdict, now, "watch", back, strike(record, verdict, now), true)
		return
	end
	if now < record.PausedUntil then
		report(record, verdict, now, "paused " .. string.lower(action), back, strike(record, verdict, now), true)
		return
	end
	if action == "Correct" then
		correct(body, sample.StandHeight, verdict, now)
	elseif action == "Repivot" then
		repivot(body, verdict, now)
	end
end

----------------------------------------------------------------
-- The tick
----------------------------------------------------------------

-- The bodies audited this tick: each player's live character, the one its track follows, not dead. Every player's
-- body, audited or not, is noted too.
local function gather(): { Body }
	table.clear(characters)
	table.clear(playerBodies)
	local bodies: { Body } = {}
	for player, record in pairs(records) do
		record.Supported = false
		local current = player.Character
		if current ~= nil then
			playerBodies[current] = true
		end
		local character = record.Character
		if character == nil or player.Character ~= character or character.Parent == nil then
			continue
		end
		local root = character:FindFirstChild(ROOT_PART_NAME)
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health <= 0 then
			continue
		end
		local position = root.Position
		characters[character] = record
		table.insert(bodies, {
			Record = record,
			Character = character,
			Root = root,
			Humanoid = humanoid,
			X = position.X,
			Y = position.Y,
			Z = position.Z,
			Sane = sane(position),
			Contact = false,
		})
	end
	return bodies
end

-- Contact between players (MovementGuard.touching, on last tick's flags and this tick's displacements), then
-- with the bodies the server moves.
local function markContacts(bodies: { Body })
	local listed: { Body } = {}
	local xs: { number }, ys: { number }, zs: { number } = {}, {}, {}
	local dxs: { number }, dys: { number }, dzs: { number } = {}, {}, {}
	local flagged: { boolean } = {}
	for _, body in ipairs(bodies) do
		if body.Sane then
			local record = body.Record
			table.insert(listed, body)
			local n = #listed
			xs[n], ys[n], zs[n] = body.X, body.Y, body.Z
			if record.HasLast then
				dxs[n], dys[n], dzs[n] = body.X - record.LastX, body.Y - record.LastY, body.Z - record.LastZ
			else
				dxs[n], dys[n], dzs[n] = 0, 0, 0
			end
			flagged[n] = record.Flagged
		end
	end
	local touched = MovementGuard.touching(xs, ys, zs, dxs, dys, dzs, flagged, AUDIT.ContactRadiusStuds, config)
	for n, body in ipairs(listed) do
		body.Contact = touched[n] or nearServerBody(body.Root.Position)
	end
end

-- Support under every body, before any is judged. First a probe that sees no player's body at all; for a body it
-- found nothing under, one that sees the others, and a body found there holds this one up only if the world holds
-- it up this tick, directly or through the bodies under it (MovementGuard.carried). Last tick's word let two
-- bodies hold each other up at any height, and a body with no record -- a corpse -- held up anyone.
local function markSupport(bodies: { Body })
	local excluded: { Instance } = {}
	for character in pairs(playerBodies) do
		table.insert(excluded, character)
	end
	worldProbe.FilterDescendantsInstances = excluded
	local index: { [Record]: number } = {}
	for n, body in ipairs(bodies) do
		index[body.Record] = n
	end
	local world: { boolean }, carrier: { number } = {}, {}
	for n, body in ipairs(bodies) do
		world[n], carrier[n] = false, 0
		if body.Sane then
			local stand = standHeight(body.Humanoid, body.Root)
			local position = body.Root.Position
			local radius, reach = AUDIT.GroundProbeRadiusStuds, AUDIT.GroundProbeSlackStuds
			if castDown(worldProbe, position, stand, radius, reach) ~= nil then
				world[n] = true
			else
				local hit = castDown(body.Record.Probe, position, stand, radius, reach)
				local owner = if hit ~= nil then bodyOf(hit.Instance) else nil
				if owner ~= nil then
					carrier[n] = index[owner] or 0
				end
			end
		end
	end
	local held = MovementGuard.carried(world, carrier)
	for n, body in ipairs(bodies) do
		body.Record.Supported = held[n]
	end
end

-- A body that walked through a stun it had been told of (Pure/StunWatch, D-213): logged, once per stun and in every
-- mode, and never acted on. A push the server granted, a touch or a fall carries the body and is not walking, nor is
-- a step past the speed ceiling (a pivot, a correction, a stall's catch-up), which the judge's own rules weigh.
local function watchStun(body: Body, sample: MovementGuard.Sample, now: number)
	local record = body.Record
	local startedAt, endsAt = deps.Movement.stunDates(record.Player)
	local track = record.Track
	local carried = sample.Down or body.Contact or MovementGuard.granting(track, now) or now < track.ContactUntil
	local learned = StunWatch.learnedAt(startedAt, sample.Rtt, AUDIT.SettleOverheadSeconds)
	local walked = StunWatch.step(
		record.Stun,
		now,
		startedAt,
		endsAt,
		learned,
		body.X,
		body.Z,
		carried,
		AUDIT.StunWalkSlackStuds,
		config.MaxSpeedStudsPerSecond
	)
	if walked ~= nil then
		log.warn(
			"%s observe stun walk: %.1f studs through a %.2f s stun it had been told of; logged only",
			record.Player.Name,
			walked,
			endsAt - startedAt
		)
	end
end

local function audit(body: Body, now: number, hitch: boolean)
	local record = body.Record
	local track = record.Track
	local sample = sampleOf(body, now, hitch)
	local based = track.Based
	local verdict = MovementGuard.observe(track, sample, config)
	if not based and track.Based then
		log.info("%s had no spawn point: the audit starts from this first sample", record.Player.Name)
	end
	record.Flagged = verdict.Action ~= "None"
	if body.Sane then
		record.HasLast = true
		record.LastX, record.LastY, record.LastZ = body.X, body.Y, body.Z
	end
	enforce(body, sample, verdict, now)
	if body.Sane then
		watchStun(body, sample, now)
	end
end

-- One CombatService tick. `hitch` says the server itself stalled since the last one.
function MovementAudit.step(now: number, hitch: boolean)
	local bodies = gather()
	markContacts(bodies)
	markSupport(bodies)
	for _, body in ipairs(bodies) do
		-- One body's failure must not blind the audit to the others.
		faults.try(body.Record.Player, "audit of", audit, body, now, hitch)
	end
end

----------------------------------------------------------------
-- What CombatService tells it
----------------------------------------------------------------

-- The track follows `character` from now on, rebased where the engine spawns bodies. With no SpawnLocation it
-- starts over and takes the body's first sample as it comes, which the log says.
local function adopt(record: Record, character: Model, now: number)
	record.Character = character
	record.Probe.FilterDescendantsInstances = { character }
	record.Overlap.FilterDescendantsInstances = { character }
	record.HasLast = false
	record.Flagged = false
	local point = deps.SpawnPoint(character)
	if point == nil then
		record.Track = MovementGuard.newTrack(config)
		log.warn("no SpawnLocation to rebase %s on", record.Player.Name)
		return
	end
	MovementGuard.spawned(record.Track, point.X, point.Y, point.Z, now, config)
end

function MovementAudit.add(player: Player)
	if records[player] ~= nil then
		return
	end
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Exclude
	probe.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.RespectCanCollide = true
	records[player] = {
		Player = player,
		Track = MovementGuard.newTrack(config),
		Character = nil,
		RttValue = 0,
		RttAt = -math.huge,
		Supported = false,
		Flagged = false,
		HasLast = false,
		LastX = 0,
		LastY = 0,
		LastZ = 0,
		Corrections = {},
		PausedUntil = 0,
		StruckAt = {},
		LoggedAt = {},
		Probe = probe,
		Overlap = overlap,
		Stun = StunWatch.new(),
	}
end

function MovementAudit.remove(player: Player)
	records[player] = nil
	faults.forget(player)
end

-- A new body, where the engine spawned it.
function MovementAudit.spawned(player: Player, character: Model)
	local record = records[player]
	if record ~= nil then
		adopt(record, character, os.clock())
	end
end

-- The server put the body at `position` (CombatService.resyncPosition). The stale samples still on their way come
-- from where the stream last put it; when the teleport reached a new body before its CharacterAdded did, that is
-- where the engine spawned it.
function MovementAudit.teleported(player: Player, position: Vector3)
	local record = records[player]
	local character = player.Character
	if record == nil or character == nil then
		return
	end
	local now = os.clock()
	if record.Character ~= character then
		adopt(record, character, now)
	end
	local track = record.Track
	local fromX, fromY, fromZ = MovementGuard.heard(track)
	local stand = MovementAudit.standingHeight(character)
	local groundY = groundUnder(record, position, stand)
	MovementGuard.teleported(track, position.X, position.Y, position.Z, now, fromX, fromY, fromZ, groundY, config)
end

-- The server granted `player` a burst: `flat` horizontal and `lift` vertical studs over `seconds`.
function MovementAudit.grant(player: Player, flat: number, lift: number, seconds: number)
	local record = records[player]
	if record ~= nil then
		local now = os.clock()
		MovementGuard.grant(record.Track, flat, lift, seconds, now, heldRtt(record, now), config)
	end
end

-- The round trip the audit reads for `player`, for CombatService to stretch its own grants by.
function MovementAudit.rtt(player: Player): number
	local record = records[player]
	if record == nil then
		return PINGS_PER_ROUND_TRIP * player:GetNetworkPing()
	end
	return heldRtt(record, os.clock())
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function MovementAudit.init(injected: Deps, judged: MovementGuard.Config)
	deps = injected
	config = judged
end

-- Whether a connected handler runs inside Fire or later: Workspace.SignalBehavior is not readable from a script,
-- so it is observed.
local function signalsDeferred(): boolean
	local event = Instance.new("BindableEvent")
	local ran = false
	event.Event:Connect(function()
		ran = true
	end)
	event:Fire()
	event:Destroy()
	return not ran
end

function MovementAudit.start()
	watchModels(GameConfig.Enemy.Tag, npcs)
	watchModels(BotConfig.Tag, npcs)
	watchModels(WorldBossConfig.Boss.Tag, hulls)
	watchParts(WorldConfig.Glyphs.CollisionTag, walls, nil)
	watchParts(AUDIT.BarrierTag, barriers, noteBarriersChanged)
	local barrierCount = 0
	for _ in pairs(barriers) do
		barrierCount += 1
	end
	log.info(
		"mode %s: gravity %.1f (judged at %.1f), streaming %s, signals %s, %d barrier parts",
		MovementGuardConfig.Mode,
		Workspace.Gravity,
		config.Gravity,
		tostring(Workspace.StreamingEnabled),
		if signalsDeferred() then "deferred" else "immediate",
		barrierCount
	)
end

return MovementAudit
