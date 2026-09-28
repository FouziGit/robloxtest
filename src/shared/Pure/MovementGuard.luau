--!strict
-- Judges whether a character's body moved in a way the server can explain: its own walking and jumping, the
-- bursts the server granted (dash, knockback, Ligature), the teleports the server made and what it touched.
-- Pure: no require, no Roblox global, so every rule is unit-tested under Lune (tests/MovementGuard.spec.luau)
-- and replayed against a simulated client and network (tests/movementsim.luau,
-- tests/MovementScenarios.spec.luau).
--
-- MovementAudit measures (support probe, barrier ray, path scan, contact, round trip, remote liveness, server
-- hitches), this module judges, and MovementAudit acts on the verdict. It keeps a horizontal anchor of its own,
-- apart from OriginGuard's: OriginGuard decides where an ACTION starts, over half a second, while this one
-- audits the body itself and needs its own expiry, forgiveness and confirmation. Both are re-anchored by every
-- server teleport and every correction.
--
-- A rule that fires only flags. Two fresh flags of one kind within ConfirmWindowSeconds confirm it, and a
-- confirmed flag asks for a correction to a point the body was believed at. Whether the correction is also a
-- strike depends on every exemption its episode met: a grant, contact, a spawn, a server hitch, a stream
-- catching up, a body that is down. When the server cannot tell, it flags rather than moves anyone.
--
-- About 1400 lines, a quarter of them the declared shapes and the track's constructor: over the 500-line
-- guideline, like BotBrain. Splitting it would need a require between pure modules or functions injected by
-- the caller.

local MovementGuard = {}

-- The numbers the judge reads. MovementAudit builds this once: the first block from the engine and the shared
-- game config, the rest from MovementGuardConfig (src/server/Config), where each value has its reason.
export type Config = {
	-- Workspace.Gravity, GameConfig.Movement's two jump velocities, GameConfig.Latency's speed ceiling and
	-- budget window, the stillness epsilon of CombatService's GUARD, and the server tick.
	Gravity: number,
	JumpVelocity: number,
	DoubleJumpVelocity: number,
	MaxSpeedStudsPerSecond: number,
	MaxBudgetSeconds: number,
	StillEpsilonStuds: number,
	TickSeconds: number,
	-- Horizontal: the chased anchor (H1) and the walking average (H2).
	TeleportSlackStuds: number,
	StallSeconds: number,
	StallSpeedStudsPerSecond: number,
	StallCapSeconds: number,
	CleanGapStuds: number,
	SustainedFactor: number,
	SustainedSlackStudsPerSecond: number,
	SustainedWindowSeconds: number,
	SustainedEvidenceSeconds: number,
	WalkCeilingGraceSeconds: number,
	-- Grants.
	HorizontalOvershoot: number,
	LiftOvershoot: number,
	MaxAllowanceStuds: number,
	MaxLiftStuds: number,
	GraceOverheadSeconds: number,
	GraceMinSeconds: number,
	GraceMaxSeconds: number,
	AwaitCapSeconds: number,
	ActivationGraceSeconds: number,
	MaxRttSeconds: number,
	-- Vertical: altitude (F1), sink, hang (F2), frozen in the air (F3), and the path scan.
	AltitudeSlackStuds: number,
	JitterSeconds: number,
	AscentSeconds: number,
	RiseEpsilonStuds: number,
	HangGraceSeconds: number,
	DropSlackStuds: number,
	SinkSlackStuds: number,
	FrozenAirSeconds: number,
	FrozenMinHeightStuds: number,
	FrozenStrikeRepeat: number,
	FrozenRepeatWindowSeconds: number,
	InboundMarginSeconds: number,
	LandingSlackStuds: number,
	ScanPathSeconds: number,
	ScanMarginStuds: number,
	ScanHeightMarginStuds: number,
	ScanChainSteps: number,
	-- Noclip (N1).
	StandMinStuds: number,
	NoclipTopSlackStuds: number,
	NoclipMinStepStuds: number,
	FloorSinkStuds: number,
	-- Half a body's width: a chord this close to a barrier's edge cuts its corner rather than going through it.
	BodyHalfWidthStuds: number,
	TunnelSpeedStudsPerSecond: number,
	TunnelMinFallStuds: number,
	-- Confirmation and exemptions.
	ConfirmCount: number,
	ConfirmWindowSeconds: number,
	PersistSeconds: number,
	ContactLatchSeconds: number,
	ContactRttMarginSeconds: number,
	CoMoveDot: number,
	SpawnGraceSeconds: number,
	HitchGraceSeconds: number,
	-- Server teleports.
	SettleMinSeconds: number,
	SettleMaxSeconds: number,
	SettleOverheadSeconds: number,
	ArrivalRadiusStuds: number,
	ArrivalTimeoutSeconds: number,
	ResistTimeouts: number,
	RefusalWindowSeconds: number,
	ReturnWindowSeconds: number,
	ReturnExemptSeconds: number,
	-- Sanity and correction targets.
	MaxCoordinateStuds: number,
	GroundMaxAgeSeconds: number,
	-- Ring sizes, in entries.
	SegmentRing: number,
	SafeRing: number,
	PathRing: number,
	WalkRing: number,
}

export type Kind = "Invalid" | "Teleport" | "Flight" | "Noclip" | "Speed" | "Resist"
export type Action = "None" | "Watch" | "Correct" | "Repivot"
-- A tagged barrier the segment from the last judged sample went through. The plane is the face it entered
-- by, its normal pointing back to the side the body came from; Top comes from halfHeight, and PassThrough from
-- passesThrough.
export type Crossing = {
	HitY: number,
	Top: number,
	Floor: boolean,
	PassThrough: boolean,
	PlaneX: number,
	PlaneY: number,
	PlaneZ: number,
	NormalX: number,
	NormalY: number,
	NormalZ: number,
}
-- One server tick's view of a body. Every field is measured by the server; none is the client's word except
-- the root position itself, which is what is being judged.
export type Sample = {
	At: number,
	X: number,
	Y: number,
	Z: number,
	-- From the server's own spherecast, never FloorMaterial or the Humanoid state, which the client writes.
	Supported: boolean,
	StandHeight: number,
	Down: boolean,
	Contact: boolean,
	WalkSpeed: number,
	Rtt: number,
	LastInboundAt: number,
	Hitch: boolean,
	Crossing: Crossing?,
	-- Only when preview() asked for a path scan.
	SupportTops: { number }?,
}
export type Verdict = {
	Action: Action,
	Kind: Kind?,
	Rule: string,
	Strikeable: boolean,
	Measure: number,
	Budget: number,
	X: number,
	Y: number,
	Z: number,
}

type Episode = { Count: number, LastCountAt: number, Exempt: boolean, Touched: boolean }

export type Track = {
	Based: boolean,
	-- The last judged sample that moved, and when.
	LastX: number,
	LastY: number,
	LastZ: number,
	LastAt: number,
	LastMoveAt: number,
	-- The raw observation, judged or not, and when it last changed: a stall is a stream that stopped.
	HeardX: number,
	HeardY: number,
	HeardZ: number,
	HeardAt: number,
	-- The horizontal anchor, chasing the body at the speed ceiling, and what a stall's catch-up forgave.
	AnchorX: number,
	AnchorZ: number,
	AnchorAt: number,
	Forgiven: number,
	CatchUp: boolean,
	Gap: number,
	-- Server-granted bursts.
	Allowance: number,
	Lift: number,
	WindowEnd: number,
	AwaitUntil: number,
	Awaiting: boolean,
	GrantSeconds: number,
	GrantCoverUntil: number,
	-- The vertical references: the standing root height of the ground, the last explained high point, and
	-- the one ascent a body may start without a probe having seen it leave the ground.
	GroundY: number,
	HighY: number,
	HighAt: number,
	AscentUntil: number,
	TokenUsed: boolean,
	ContactUntil: number,
	-- A correction that was not struck keeps its cause for this long: a body still thrown by the same
	-- collision after it was pulled back is the same incident, not a new one.
	ExemptUntil: number,
	SpawnUntil: number,
	HitchUntil: number,
	-- The server WalkSpeed history, newest at WalkHead.
	WalkAt: { number },
	WalkValue: { number },
	WalkHead: number,
	WalkCount: number,
	-- Horizontal segments for H2: when, how long, how far, how far walking allowed, whether nothing else
	-- could have carried the body, and where each started.
	SegAt: { number },
	SegDt: { number },
	SegD: { number },
	SegAllowed: { number },
	SegFree: { boolean },
	SegX: { number },
	SegY: { number },
	SegZ: { number },
	SegHead: number,
	SegCount: number,
	-- Points the body was believed at, the correction targets. Ground marks a supported one.
	SafeAt: { number },
	SafeX: { number },
	SafeY: { number },
	SafeZ: { number },
	SafeGround: { boolean },
	SafeHead: number,
	SafeCount: number,
	-- The recent path, for the box the path scan covers.
	PathAt: { number },
	PathX: { number },
	PathZ: { number },
	PathHead: number,
	PathCount: number,
	Episodes: { [string]: Episode },
	FrozenAt: { number },
	-- A server teleport the body has not been seen to arrive at.
	Pending: boolean,
	PendingSince: number,
	DestX: number,
	DestY: number,
	DestZ: number,
	FromX: number,
	FromY: number,
	FromZ: number,
	TeleportAt: number,
	Refusals: number,
	RefusedAt: number,
	ReturnUntil: number,
	-- An impossible crossing waiting for its confirmation: the plane the body went through.
	Beyond: boolean,
	PlaneX: number,
	PlaneY: number,
	PlaneZ: number,
	NormalX: number,
	NormalY: number,
	NormalZ: number,
	BeyondRule: string,
}

-- A flag one rule raised on this sample.
type Flag = { Rule: string, Measure: number, Budget: number }

-- What one observation has worked out so far, handed from rule to rule.
type Step = {
	Rtt: number,
	Live: boolean,
	Moved: boolean,
	-- Seconds the raw stream had been silent before this sample changed it; 0 when it did not change.
	Quiet: number,
	Flags: { [string]: Flag },
	-- Where a Speed correction goes: the start of the oldest free segment in the window.
	SpeedX: number,
	SpeedY: number,
	SpeedZ: number,
}

-- The kinds a sample can flag, in the order a correction chooses between them. Resist is not one of them: it
-- comes from a teleport the client did not apply, never from a sample.
local KINDS: { Kind } = { "Invalid", "Teleport", "Flight", "Noclip", "Speed" }

local function newEpisode(): Episode
	return { Count = 0, LastCountAt = -math.huge, Exempt = false, Touched = false }
end

local function verdict(
	action: Action,
	kind: Kind?,
	rule: string,
	strikeable: boolean,
	measure: number,
	budget: number,
	x: number,
	y: number,
	z: number
): Verdict
	return {
		Action = action,
		Kind = kind,
		Rule = rule,
		Strikeable = strikeable,
		Measure = measure,
		Budget = budget,
		X = x,
		Y = y,
		Z = z,
	}
end

local function none(): Verdict
	return verdict("None", nil, "", false, 0, 0, 0, 0, 0)
end

-- Rings are arrays table.create'd at their configured size, so an array's length is its ring's size and
-- safePoint can walk one with nothing but the track.
local function nextSlot(head: number, size: number): number
	return head % size + 1
end

local function olderSlot(i: number, size: number): number
	return if i == 1 then size else i - 1
end

function MovementGuard.newTrack(config: Config): Track
	local episodes: { [string]: Episode } = {}
	for _, kind in ipairs(KINDS) do
		episodes[kind] = newEpisode()
	end
	local walks, segments, safe, path = config.WalkRing, config.SegmentRing, config.SafeRing, config.PathRing
	return {
		Based = false,
		LastX = 0,
		LastY = 0,
		LastZ = 0,
		LastAt = 0,
		LastMoveAt = 0,
		HeardX = 0,
		HeardY = 0,
		HeardZ = 0,
		HeardAt = 0,
		AnchorX = 0,
		AnchorZ = 0,
		AnchorAt = 0,
		Forgiven = 0,
		CatchUp = false,
		Gap = 0,
		Allowance = 0,
		Lift = 0,
		WindowEnd = 0,
		AwaitUntil = 0,
		Awaiting = false,
		GrantSeconds = 0,
		GrantCoverUntil = -math.huge,
		GroundY = 0,
		HighY = 0,
		HighAt = 0,
		AscentUntil = 0,
		TokenUsed = false,
		ContactUntil = -math.huge,
		ExemptUntil = -math.huge,
		SpawnUntil = -math.huge,
		HitchUntil = -math.huge,
		WalkAt = table.create(walks, 0),
		WalkValue = table.create(walks, 0),
		WalkHead = 0,
		WalkCount = 0,
		SegAt = table.create(segments, 0),
		SegDt = table.create(segments, 0),
		SegD = table.create(segments, 0),
		SegAllowed = table.create(segments, 0),
		SegFree = table.create(segments, false),
		SegX = table.create(segments, 0),
		SegY = table.create(segments, 0),
		SegZ = table.create(segments, 0),
		SegHead = 0,
		SegCount = 0,
		SafeAt = table.create(safe, 0),
		SafeX = table.create(safe, 0),
		SafeY = table.create(safe, 0),
		SafeZ = table.create(safe, 0),
		SafeGround = table.create(safe, false),
		SafeHead = 0,
		SafeCount = 0,
		PathAt = table.create(path, 0),
		PathX = table.create(path, 0),
		PathZ = table.create(path, 0),
		PathHead = 0,
		PathCount = 0,
		Episodes = episodes,
		FrozenAt = {},
		Pending = false,
		PendingSince = 0,
		DestX = 0,
		DestY = 0,
		DestZ = 0,
		FromX = 0,
		FromY = 0,
		FromZ = 0,
		TeleportAt = -math.huge,
		Refusals = 0,
		RefusedAt = -math.huge,
		ReturnUntil = -math.huge,
		Beyond = false,
		PlaneX = 0,
		PlaneY = 0,
		PlaneZ = 0,
		NormalX = 0,
		NormalY = 0,
		NormalZ = 0,
		BeyondRule = "",
	}
end

----------------------------------------------------------------
-- Physics and small helpers
----------------------------------------------------------------

-- Highest the root can rise above where it left the ground on its own: a jump, then the double jump at the
-- apex (MovementController sets the vertical velocity, it does not add to it).
function MovementGuard.maxRise(config: Config): number
	return (config.JumpVelocity ^ 2 + config.DoubleJumpVelocity ^ 2) / (2 * config.Gravity)
end

local function upSpeed(config: Config): number
	return math.max(config.JumpVelocity, config.DoubleJumpVelocity)
end

-- Most the root can climb in `dt` seconds on its own: a jump, and the double jump halfway through, which is
-- the timing that climbs highest.
local function riseWithin(dt: number, config: Config): number
	local v = upSpeed(config)
	if dt >= 2 * v / config.Gravity then
		return MovementGuard.maxRise(config)
	end
	return v * dt - 0.25 * config.Gravity * dt * dt
end

-- A NaN round trip reads as the worst one allowed, never as none.
local function clampRtt(rtt: number, config: Config): number
	return if rtt == rtt then math.clamp(rtt, 0, config.MaxRttSeconds) else config.MaxRttSeconds
end

-- How long a grant outlives its own duration, for the round trip before the client plays it. GetNetworkPing
-- leaves out frame and send time, hence the overhead. CombatService.allowTravel holds OriginGuard's allowance
-- open by the same grace.
function MovementGuard.grace(rtt: number, config: Config): number
	return math.clamp(
		clampRtt(rtt, config) + config.GraceOverheadSeconds,
		config.GraceMinSeconds,
		config.GraceMaxSeconds
	)
end

-- How long after a server pivot the stream may still carry the body where it stood before the pivot reached the
-- client: the round trip and an overhead, clamped. The judge waits this out before it looks for the body at the
-- destination, and CombatService holds OriginGuard's anchor through the same window.
function MovementGuard.settle(rtt: number, config: Config): number
	return math.clamp(
		clampRtt(rtt, config) + config.SettleOverheadSeconds,
		config.SettleMinSeconds,
		config.SettleMaxSeconds
	)
end

-- How long a touch keeps exempting: its effect reaches the server a round trip later.
local function contactLatch(rtt: number, config: Config): number
	return math.max(config.ContactLatchSeconds, rtt + config.ContactRttMarginSeconds)
end

local function dist3(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function finite(v: number, limit: number): boolean
	return v == v and v > -limit and v < limit
end

local function grantLive(track: Track, now: number): boolean
	return now < track.WindowEnd or (track.Awaiting and now < track.AwaitUntil)
end

-- The allowance a pending teleport's regions may grow by: only a grant still live carries the body.
local function liveAllowance(track: Track, now: number): number
	return if grantLive(track, now) then track.Allowance else 0
end

local function resetEpisodes(track: Track)
	for _, kind in ipairs(KINDS) do
		-- An invalid sample is judged on its own clock: the correction it causes must not forget it.
		if kind ~= "Invalid" then
			track.Episodes[kind] = newEpisode()
		end
	end
end

local function pushSafe(track: Track, now: number, x: number, y: number, z: number, ground: boolean)
	local size = #track.SafeAt
	track.SafeHead = nextSlot(track.SafeHead, size)
	local i = track.SafeHead
	track.SafeAt[i], track.SafeX[i], track.SafeY[i], track.SafeZ[i], track.SafeGround[i] = now, x, y, z, ground
	track.SafeCount = math.min(track.SafeCount + 1, size)
end

local function pushPath(track: Track, now: number, x: number, z: number)
	local size = #track.PathAt
	track.PathHead = nextSlot(track.PathHead, size)
	local i = track.PathHead
	track.PathAt[i], track.PathX[i], track.PathZ[i] = now, x, z
	track.PathCount = math.min(track.PathCount + 1, size)
end

-- Re-anchors everything on a point the SERVER chose: a spawn, a teleport, a correction. `groundY` is the standing
-- root height of the ground found under it, nil with none: the altitude rule measures from there.
local function base(track: Track, x: number, y: number, z: number, now: number, groundY: number?)
	track.Based = true
	track.LastX, track.LastY, track.LastZ, track.LastAt, track.LastMoveAt = x, y, z, now, now
	track.AnchorX, track.AnchorZ, track.AnchorAt = x, z, now
	track.HeardX, track.HeardY, track.HeardZ, track.HeardAt = x, y, z, now
	track.Forgiven, track.CatchUp, track.Gap = 0, false, 0
	if groundY ~= nil then
		track.GroundY = groundY
		track.TokenUsed = false
	end
	track.HighY, track.HighAt = y, now
	track.AscentUntil = now
	track.SegCount = 0
	track.PathCount = 0
	track.Beyond = false
	resetEpisodes(track)
	pushSafe(track, now, x, y, z, groundY ~= nil)
	pushPath(track, now, x, z)
end

----------------------------------------------------------------
-- What the server tells the judge
----------------------------------------------------------------

-- The body was (re)spawned at a point the server chose. Nothing from the previous body carries over: its
-- grants, its contact, its safe points, its WalkSpeed history.
function MovementGuard.spawned(track: Track, x: number, y: number, z: number, now: number, config: Config)
	track.Pending = false
	track.Allowance, track.Lift, track.WindowEnd, track.AwaitUntil, track.Awaiting = 0, 0, 0, 0, false
	track.ContactUntil = -math.huge
	track.SafeCount = 0
	track.WalkCount = 0
	base(track, x, y, z, now, y)
	track.SpawnUntil = now + config.SpawnGraceSeconds
end

-- The server moved the body: a server teleport or a correction. `from` is where the stream last put it, so
-- its stale samples are recognised by it. Grants survive: a client mover still running keeps carrying the
-- body from the new place. `groundY` is the standing root height of the ground under the destination, nil with
-- none: a pad drops a body a few studs above its floor, and the altitude rule must measure from that floor,
-- not from wherever the body stood before -- the hub, 900 studs under an arena.
function MovementGuard.teleported(
	track: Track,
	x: number,
	y: number,
	z: number,
	now: number,
	fromX: number,
	fromY: number,
	fromZ: number,
	groundY: number?,
	config: Config
)
	track.Pending = true
	track.PendingSince = now
	track.DestX, track.DestY, track.DestZ = x, y, z
	track.FromX, track.FromY, track.FromZ = fromX, fromY, fromZ
	if now - track.RefusedAt > config.RefusalWindowSeconds then
		track.Refusals = 0
	end
	track.ReturnUntil = -math.huge
	track.TeleportAt = now
	base(track, x, y, z, now, groundY)
end

-- The server granted a burst of `flat` horizontal and `lift` vertical studs over `seconds`. The client plays
-- it a round trip later, and its mover overshoots at a low frame rate, hence the grace and the overshoots;
-- the caps stop a stream of grants from banking unbounded travel.
function MovementGuard.grant(
	track: Track,
	flat: number,
	lift: number,
	seconds: number,
	now: number,
	rtt: number,
	config: Config
)
	if not grantLive(track, now) then
		track.Allowance = 0
		track.GrantSeconds = 0
	end
	track.Allowance =
		math.min(track.Allowance + math.max(0, flat) * config.HorizontalOvershoot, config.MaxAllowanceStuds)
	track.Lift = math.min(track.Lift + math.max(0, lift) * config.LiftOvershoot, config.MaxLiftStuds)
	track.WindowEnd = math.max(track.WindowEnd, now + seconds + MovementGuard.grace(rtt, config))
	track.AwaitUntil = math.max(track.AwaitUntil, now + config.AwaitCapSeconds)
	track.GrantSeconds = math.max(track.GrantSeconds, seconds)
	track.Awaiting = true
	track.GrantCoverUntil = now
end

-- MovementAudit's confirm probe, wider and deeper than the support probe, found ground under a body a flight
-- rule flagged: the body stands at root height `y`. The vertical references restart there as on a supported
-- sample, and the flight incident ends without a correction.
function MovementGuard.groundFound(track: Track, y: number, now: number)
	track.GroundY = y
	track.HighY, track.HighAt = y, now
	track.TokenUsed = false
	track.Episodes.Flight = newEpisode()
end

-- The last raw observation, judged or not: where a teleport takes the body from.
function MovementGuard.heard(track: Track): (number, number, number)
	return track.HeardX, track.HeardY, track.HeardZ
end

-- A grant starts counting once the motion it pays for shows up. Plain walking does not show it: a grant
-- played late must not have expired by the time it plays.
local function activate(track: Track, now: number, config: Config)
	if track.Awaiting then
		track.Awaiting = false
		track.WindowEnd = math.max(track.WindowEnd, now + track.GrantSeconds + config.ActivationGraceSeconds)
	end
end

-- The fastest server WalkSpeed in force over the last round trip and a grace: the client learns a slow late.
local function walkCeiling(track: Track, now: number, rtt: number, config: Config): number
	local horizon = now - rtt - config.WalkCeilingGraceSeconds
	local size = #track.WalkAt
	local ceiling = 0
	local i = track.WalkHead
	for _ = 1, track.WalkCount do
		ceiling = math.max(ceiling, track.WalkValue[i])
		if track.WalkAt[i] <= horizon then
			break -- the value in force at the horizon: older ones no longer matter
		end
		i = olderSlot(i, size)
	end
	return ceiling
end

local function noteWalk(track: Track, now: number, value: number)
	if track.WalkCount > 0 and track.WalkValue[track.WalkHead] == value then
		return
	end
	local size = #track.WalkAt
	track.WalkHead = nextSlot(track.WalkHead, size)
	track.WalkAt[track.WalkHead], track.WalkValue[track.WalkHead] = now, value
	track.WalkCount = math.min(track.WalkCount + 1, size)
end

----------------------------------------------------------------
-- The path scan and the vertical rules
----------------------------------------------------------------

-- Highest standing root height reachable from the known ground through the surfaces a scan found, each one
-- a jump (and any live lift) above the last.
local function reachable(track: Track, tops: { number }, stand: number, config: Config): number
	local ref = track.GroundY
	local reach = MovementGuard.maxRise(config) + track.Lift + config.AltitudeSlackStuds
	for _ = 1, config.ScanChainSteps do
		local raised = ref
		for _, top in ipairs(tops) do
			local standing = top + stand
			if standing > raised and standing <= ref + reach then
				raised = standing
			end
		end
		if raised == ref then
			break
		end
		ref = raised
	end
	return ref
end

-- Could the body have touched down on one of these surfaces between the last sample and this one, and jumped
-- again? Its root never climbs faster than the jump velocity, plus any live lift.
local function landedBetween(track: Track, s: Sample, tops: { number }, ref: number, config: Config): boolean
	local dt = math.max(s.At - track.LastAt, config.TickSeconds)
	local low = s.Y - (upSpeed(config) * dt + track.Lift) - config.LandingSlackStuds
	local high = math.min(track.LastY, s.Y) + config.LandingSlackStuds
	for _, top in ipairs(tops) do
		local standing = top + s.StandHeight
		if standing >= low and standing <= high and standing <= ref + config.LandingSlackStuds then
			return true
		end
	end
	return false
end

-- The vertical rules, without side effects: which of them this sample breaks, by how much against what.
local function verticalRule(track: Track, s: Sample, config: Config): (string?, number, number)
	local now = s.At
	local held = grantLive(track, now) or now < track.ContactUntil
	local rise = MovementGuard.maxRise(config) + track.Lift + config.AltitudeSlackStuds
	local height = s.Y - track.GroundY
	if height > rise then
		return "altitude", height, rise
	end
	-- Receive-time jitter can make a fall look faster than gravity; the envelope starts that much earlier.
	local drop = track.HighY - s.Y
	local fall = now - track.HighAt + config.JitterSeconds
	local sink = 0.5 * config.Gravity * fall * fall + config.SinkSlackStuds
	if drop > sink then
		return "sink", drop, sink
	end
	if not s.Supported and not s.Down and not held then
		local fresh = dist3(s.X, s.Y, s.Z, track.LastX, track.LastY, track.LastZ) > config.StillEpsilonStuds
		if fresh then
			-- A granted burst may hold the body up for its whole window: the hang is timed from its end.
			local hang = now - math.max(track.HighAt, track.WindowEnd) - config.JitterSeconds
			local need = 0.5 * config.Gravity * hang * hang - config.DropSlackStuds
			if hang > config.HangGraceSeconds and drop < need then
				return "hang", drop, need
			end
		end
	end
	return nil, 0, 0
end

-- True when a flight rule would fire on this sample: MovementAudit then scans the path for a surface the
-- body could have stood on between two samples, and passes the tops in s.SupportTops. A pending teleport does
-- not stop it: the sample that shows the body arrived is judged, after a settle in which it may have landed and
-- jumped again, and a hop on arrival read as a hang without its scan.
function MovementGuard.preview(track: Track, s: Sample, config: Config): boolean
	if not track.Based or s.Supported then
		return false
	end
	local rule = verticalRule(track, s, config)
	if rule == "altitude" or rule == "hang" then
		return true
	end
	-- An upward step with no impulse to explain it: a landing between two samples may.
	local fresh = dist3(s.X, s.Y, s.Z, track.LastX, track.LastY, track.LastZ) > config.StillEpsilonStuds
	return fresh
		and s.Y > track.HighY + config.RiseEpsilonStuds
		and s.At > track.AscentUntil
		and track.TokenUsed
		and not grantLive(track, s.At)
		and s.At >= track.ContactUntil
end

-- The world box the scan covers, as min x, y, z then max x, y, z: the recent path plus a margin, from below
-- the lowest feet to above the root.
function MovementGuard.scanBox(
	track: Track,
	s: Sample,
	config: Config
): (number, number, number, number, number, number)
	local minX, maxX, minZ, maxZ = s.X, s.X, s.Z, s.Z
	local size = #track.PathAt
	local i = track.PathHead
	for _ = 1, track.PathCount do
		if track.PathAt[i] < s.At - config.ScanPathSeconds then
			break
		end
		minX, maxX = math.min(minX, track.PathX[i]), math.max(maxX, track.PathX[i])
		minZ, maxZ = math.min(minZ, track.PathZ[i]), math.max(maxZ, track.PathZ[i])
		i = olderSlot(i, size)
	end
	local margin = config.ScanMarginStuds
	local height = config.ScanHeightMarginStuds
	local bottom = math.min(track.GroundY, s.Y) - s.StandHeight - height
	return minX - margin, bottom, minZ - margin, maxX + margin, s.Y + height, maxZ + margin
end

-- Whether MovementAudit should cast the barrier ray for this sample: a real step, and no teleport pending
-- (the stream still carries the old place).
function MovementGuard.wantsRay(track: Track, s: Sample, config: Config): boolean
	return track.Based
		and not track.Pending
		and dist3(s.X, s.Y, s.Z, track.LastX, track.LastY, track.LastZ) >= config.NoclipMinStepStuds
end

-- Where the barrier ray starts: the last judged sample, not the last safe point, so one old point cannot make
-- every later step look like a crossing.
function MovementGuard.rayOrigin(track: Track): (number, number, number)
	return track.LastX, track.LastY, track.LastZ
end

-- The n-th newest point the body was believed at (n = 1 is the newest), for MovementAudit to check for
-- clearance before pivoting. groundOnly skips the ones taken in the air.
function MovementGuard.safePoint(
	track: Track,
	n: number,
	groundOnly: boolean
): (boolean, number, number, number, number)
	local size = #track.SafeAt
	local i = track.SafeHead
	local seen = 0
	for _ = 1, track.SafeCount do
		if not groundOnly or track.SafeGround[i] then
			seen += 1
			if seen == n then
				return true, track.SafeX[i], track.SafeY[i], track.SafeZ[i], track.SafeAt[i]
			end
		end
		i = olderSlot(i, size)
	end
	return false, 0, 0, 0, 0
end

-- A flight is corrected to recent ground rather than to a point in the air it may have faked its way to.
local function safeTarget(track: Track, now: number, groundFirst: boolean, config: Config): (number, number, number)
	if groundFirst then
		local ok, x, y, z, at = MovementGuard.safePoint(track, 1, true)
		if ok and now - at <= config.GroundMaxAgeSeconds then
			return x, y, z
		end
	end
	local _, x, y, z = MovementGuard.safePoint(track, 1, false)
	return x, y, z
end

----------------------------------------------------------------
-- Barrier geometry
----------------------------------------------------------------

-- How far the top of a box of size (sx, sy, sz) stands above its centre, whatever its rotation: (r10, r11, r12) is
-- the rotation's world-up row, the height each of the box's own axes climbs per stud.
function MovementGuard.halfHeight(r10: number, r11: number, r12: number, sx: number, sy: number, sz: number): number
	return (math.abs(r10) * sx + math.abs(r11) * sy + math.abs(r12) * sz) / 2
end

-- Whether a step from a to b went THROUGH a barrier the ray between them hit, rather than past it: both points in
-- the barrier's own space, (hx, hy, hz) its half size. Through a wall, both points lie beyond opposite faces of
-- its thinner horizontal axis, and the step crosses its middle at least a body's half width inside its length: a
-- chord that cuts a corner, or that starts inside, is not a crossing. Through a floor, the step starts above its
-- top and ends FloorSinkStuds under it, inside its footprint shrunk by a body's half width.
function MovementGuard.passesThrough(
	floor: boolean,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	hx: number,
	hy: number,
	hz: number,
	config: Config
): boolean
	local inset = config.BodyHalfWidthStuds
	if floor then
		return ay > hy and by < hy - config.FloorSinkStuds and math.abs(bx) <= hx - inset and math.abs(bz) <= hz - inset
	end
	local thinX = hx <= hz
	local across, acrossTo, depth = az, bz, hz
	local along, alongTo, length = ax, bx, hx
	if thinX then
		across, acrossTo, depth = ax, bx, hx
		along, alongTo, length = az, bz, hz
	end
	if not ((across > depth and acrossTo < -depth) or (across < -depth and acrossTo > depth)) then
		return false
	end
	local middle = along + (alongTo - along) * across / (across - acrossTo)
	return math.abs(middle) <= length - inset
end

----------------------------------------------------------------
-- Contact between bodies
----------------------------------------------------------------

-- Both displacements longer than the teleport slack and pointing the same way.
local function coMoving(ax: number, ay: number, az: number, bx: number, by: number, bz: number, config: Config): boolean
	local a = math.sqrt(ax * ax + ay * ay + az * az)
	local b = math.sqrt(bx * bx + by * by + bz * bz)
	local slack = config.TeleportSlackStuds
	return a > slack and b > slack and (ax * bx + ay * by + az * bz) / (a * b) >= config.CoMoveDot
end

-- Which bodies touch another this tick, from their roots and last tick's displacements and flags. Body i
-- touches j when their roots are within `radius`. That contact does not count for i when j was flagged last
-- tick and both moved beyond the teleport slack the same way: a fling victim is thrown away from its flinger
-- and keeps the exemption, two cheaters teleporting together do not.
function MovementGuard.touching(
	xs: { number },
	ys: { number },
	zs: { number },
	dxs: { number },
	dys: { number },
	dzs: { number },
	flagged: { boolean },
	radius: number,
	config: Config
): { boolean }
	local count = #xs
	local touched = table.create(count, false)
	for i = 1, count - 1 do
		for j = i + 1, count do
			if dist3(xs[i], ys[i], zs[i], xs[j], ys[j], zs[j]) <= radius then
				local together = coMoving(dxs[i], dys[i], dzs[i], dxs[j], dys[j], dzs[j], config)
				if not (together and flagged[j]) then
					touched[i] = true
				end
				if not (together and flagged[i]) then
					touched[j] = true
				end
			end
		end
	end
	return touched
end

----------------------------------------------------------------
-- Server teleports
----------------------------------------------------------------

-- How far a body may be from a teleport's destination, or from where it came, `seconds` after the pivot: it
-- walks, or dashes on, from wherever the client last put it.
local function teleportReach(track: Track, now: number, seconds: number, config: Config): number
	return config.ArrivalRadiusStuds + liveAllowance(track, now) + config.StallSpeedStudsPerSecond * seconds
end

-- A teleport the body has not been seen to arrive at. Nil to go on judging this sample, a verdict to stop.
local function pending(track: Track, s: Sample, config: Config): Verdict?
	local now = s.At
	local age = now - track.PendingSince
	local settle = MovementGuard.settle(s.Rtt, config)
	if age < settle then
		return none()
	end
	local reach = teleportReach(track, now, age, config)
	-- The stale body has been walking since the FIRST pivot of this teleport, not since the last repivot.
	local reachFrom = teleportReach(track, now, math.min(now - track.TeleportAt, config.StallCapSeconds), config)
	local toDest = dist3(s.X, s.Y, s.Z, track.DestX, track.DestY, track.DestZ)
	local toFrom = dist3(s.X, s.Y, s.Z, track.FromX, track.FromY, track.FromZ)
	if toDest <= reach then
		track.Pending = false
		track.Refusals = 0
		track.ReturnUntil = now + config.ReturnWindowSeconds
		return nil
	end
	if toFrom <= reachFrom then
		if age < settle + config.ArrivalTimeoutSeconds then
			return none()
		end
		track.PendingSince = now
		track.Refusals += 1
		track.RefusedAt = now
		if track.Refusals < config.ResistTimeouts then
			return verdict("Repivot", nil, "timeout", false, toDest, reach, track.DestX, track.DestY, track.DestZ)
		end
		-- A downlink that stalled cannot deliver the pivot either: struck only while validated remotes keep
		-- arriving from a client that has had every chance to apply it.
		local alive = s.LastInboundAt > track.TeleportAt
		return verdict("Repivot", "Resist", "resist", alive, toDest, reach, track.DestX, track.DestY, track.DestZ)
	end
	-- Neither where the server put it nor on its way from where it was: judged from the destination by the
	-- ordinary rules (the anchor is already there), not as a refusal.
	track.Pending = false
	track.ReturnUntil = now + config.ReturnWindowSeconds
	return nil
end

-- Just after arrival, a sample back near where the body came from and away from where it arrived is one the
-- network delivered late: neither judged nor believed.
local function staleReturn(track: Track, s: Sample, config: Config): Verdict?
	local now = s.At
	if now > track.ReturnUntil then
		return nil
	end
	local reach = teleportReach(track, now, now - track.TeleportAt, config)
	if
		dist3(s.X, s.Y, s.Z, track.FromX, track.FromY, track.FromZ) <= reach
		and dist3(s.X, s.Y, s.Z, track.DestX, track.DestY, track.DestZ) > reach
	then
		return none()
	end
	return nil
end

----------------------------------------------------------------
-- The rules
----------------------------------------------------------------

local function raise(step: Step, kind: Kind, rule: string, measure: number, budget: number)
	if step.Flags[kind] == nil then
		step.Flags[kind] = { Rule = rule, Measure = measure, Budget = budget }
	end
end

-- A coordinate that is NaN or beyond MaxCoordinateStuds is never judged and never stored: one would poison
-- every sum after it. Like every other rule it needs a second sample: one broken sample is watched, a client
-- that keeps sending them is corrected and struck.
local function invalid(track: Track, now: number, config: Config): Verdict
	if not track.Based then
		return none()
	end
	local episode = track.Episodes.Invalid
	if now - episode.LastCountAt > config.ConfirmWindowSeconds then
		episode.Count = 0
	end
	episode.Count += 1
	episode.LastCountAt = now
	if episode.Count < config.ConfirmCount then
		return verdict("Watch", "Invalid", "invalid", false, 0, 0, 0, 0, 0)
	end
	local x, y, z = safeTarget(track, now, false, config)
	return verdict("Correct", "Invalid", "invalid", true, 0, 0, x, y, z)
end

-- Seconds the raw stream had been silent when this sample changed it, or 0.
local function hear(track: Track, s: Sample, config: Config): number
	if dist3(s.X, s.Y, s.Z, track.HeardX, track.HeardY, track.HeardZ) <= config.StillEpsilonStuds then
		return 0
	end
	local quiet = s.At - track.HeardAt
	track.HeardX, track.HeardY, track.HeardZ, track.HeardAt = s.X, s.Y, s.Z, s.At
	return quiet
end

-- H1: the anchor chases the body at the speed ceiling plus any live allowance. Returns the gap it could not
-- close.
local function stepAnchor(track: Track, s: Sample, step: Step, config: Config): number
	local dx, dz = s.X - track.AnchorX, s.Z - track.AnchorZ
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= config.StillEpsilonStuds then
		track.Gap = 0
		return 0
	end
	local elapsed = s.At - track.AnchorAt
	local bySpeed = config.MaxSpeedStudsPerSecond * math.clamp(elapsed, 0, config.MaxBudgetSeconds)
	if d > bySpeed and step.Live then
		activate(track, s.At, config)
	end
	local allowance = if step.Live then track.Allowance else 0
	local budget = bySpeed + allowance
	local gap = 0
	if d <= budget then
		track.AnchorX, track.AnchorZ = s.X, s.Z
		track.Allowance = math.max(0, allowance - math.max(0, d - bySpeed))
	else
		track.AnchorX += dx / d * budget
		track.AnchorZ += dz / d * budget
		track.Allowance = 0
		gap = d - budget
	end
	if step.Quiet > config.StallSeconds then
		-- A catch-up after a stream that stopped: forgive what walking through the silence could cover.
		local walkable = config.StallSpeedStudsPerSecond * math.min(step.Quiet, config.StallCapSeconds) - bySpeed
		track.Forgiven = math.clamp(walkable, 0, gap)
		track.CatchUp = gap > 0
	else
		track.Forgiven = math.min(track.Forgiven, gap)
		if gap <= 0 then
			track.CatchUp = false
		end
	end
	track.AnchorAt = s.At
	track.Gap = gap
	return gap
end

local function pushSegment(track: Track, at: number, dt: number, d: number, allowed: number, free: boolean)
	local size = #track.SegAt
	track.SegHead = nextSlot(track.SegHead, size)
	local i = track.SegHead
	track.SegAt[i], track.SegDt[i], track.SegD[i], track.SegAllowed[i], track.SegFree[i] = at, dt, d, allowed, free
	track.SegX[i], track.SegY[i], track.SegZ[i] = track.LastX, track.LastY, track.LastZ
	track.SegCount = math.min(track.SegCount + 1, size)
end

-- H2's sums over the free segments of the window: distance, what walking allowed, seconds, and where the
-- oldest one started.
local function sustained(track: Track, now: number, config: Config): (number, number, number, number, number, number)
	local d, allowed, dt = 0, 0, 0
	local ox, oy, oz = 0, 0, 0
	local size = #track.SegAt
	local i = track.SegHead
	for _ = 1, track.SegCount do
		if track.SegAt[i] < now - config.SustainedWindowSeconds then
			break
		end
		if track.SegFree[i] then
			d += track.SegD[i]
			allowed += track.SegAllowed[i]
			dt += track.SegDt[i]
			ox, oy, oz = track.SegX[i], track.SegY[i], track.SegZ[i]
		end
		i = olderSlot(i, size)
	end
	return d, allowed, dt, ox, oy, oz
end

-- H1 then H2. H2 counts only segments nothing else could have carried: not down, and no grant and no contact
-- reaching past the segment's start.
local function judgeHorizontal(track: Track, s: Sample, step: Step, config: Config)
	local now = s.At
	local gap = stepAnchor(track, s, step, config)
	if gap - track.Forgiven > config.TeleportSlackStuds then
		raise(step, "Teleport", "gap", gap - track.Forgiven, config.TeleportSlackStuds)
	end
	if step.Moved then
		local hd = math.sqrt((s.X - track.LastX) ^ 2 + (s.Z - track.LastZ) ^ 2)
		if hd > config.StillEpsilonStuds then
			local start = track.LastMoveAt
			local dt = math.max(now - start, config.TickSeconds)
			local counted = math.min(hd, config.MaxSpeedStudsPerSecond * dt)
			local free = not s.Down and track.GrantCoverUntil < start and track.ContactUntil < start
			local ceiling = walkCeiling(track, now, step.Rtt, config)
			local allowed = (ceiling * config.SustainedFactor + config.SustainedSlackStudsPerSecond) * dt
			pushSegment(track, now, dt, counted, allowed, free)
		end
	end
	local travelled, allowed, seconds, ox, oy, oz = sustained(track, now, config)
	step.SpeedX, step.SpeedY, step.SpeedZ = ox, oy, oz
	if seconds >= config.SustainedEvidenceSeconds and travelled > allowed then
		raise(step, "Speed", "sustained", travelled / seconds, allowed / seconds)
	end
end

-- F1, sink and F2, after crediting any surface the path scan found; then the vertical references, which a
-- flagged sample never moves.
local function judgeVertical(track: Track, s: Sample, step: Step, config: Config)
	local now = s.At
	local tops = s.SupportTops
	if tops ~= nil then
		local ref = reachable(track, tops, s.StandHeight, config)
		if ref > track.GroundY then
			track.GroundY = ref
		end
		if landedBetween(track, s, tops, ref, config) then
			track.HighY, track.HighAt = s.Y, now
			track.TokenUsed = false
			track.AscentUntil = now + config.AscentSeconds
		end
	end
	if step.Live and track.Awaiting and s.Y - track.GroundY > MovementGuard.maxRise(config) then
		activate(track, now, config)
	end
	local rule, measure, budget = verticalRule(track, s, config)
	if rule ~= nil then
		raise(step, if rule == "sink" then "Teleport" else "Flight", rule, measure, budget)
		return
	end
	if s.Supported then
		if not step.Live then
			track.Lift = 0
		end
		track.GroundY = s.Y
		track.HighY, track.HighAt = s.Y, now
		track.TokenUsed = false
		track.AscentUntil = now + config.AscentSeconds
	elseif step.Moved and s.Y > track.HighY + config.RiseEpsilonStuds then
		if step.Live or now < track.ContactUntil or now <= track.AscentUntil or s.Down then
			track.HighY, track.HighAt = s.Y, now
		elseif not track.TokenUsed then
			-- The one rise a body may start between two probes that saw it supported: a jump taken between
			-- samples.
			track.TokenUsed = true
			track.AscentUntil = now + config.AscentSeconds
			track.HighY, track.HighAt = s.Y, now
		end
		-- Otherwise the rise is unexplained: HighY and HighAt stay, so a hover cannot re-arm the hang rule.
	end
end

-- N1, from the ray between the last judged sample and this one. A crossing no honest body could have made
-- opens a "beyond" state: every later sample still on the far side of that plane flags again, so one glitched
-- sample that comes back is never confirmed, and one that stays is.
local function judgeNoclip(track: Track, s: Sample, step: Step, config: Config)
	local now = s.At
	local crossing = s.Crossing
	if
		crossing ~= nil
		and track.Beyond
		and crossing.NormalX * track.NormalX
				+ crossing.NormalY * track.NormalY
				+ crossing.NormalZ * track.NormalZ
			< 0
	then
		-- Back through the plane it went through: the sample beyond was a glitch, or the body came back.
		track.Beyond = false
		crossing = nil
	end
	if crossing ~= nil and crossing.PassThrough and not s.Down then
		local dt = math.max(now - track.LastAt, config.TickSeconds)
		local impossible = false
		local measure, budget = 0, 0
		if crossing.Floor then
			-- A long fall can carry a body through a thin floor between two physics steps; a short one cannot.
			local sinkSpeed = (track.LastY - s.Y) / dt
			local tunnel = sinkSpeed >= config.TunnelSpeedStudsPerSecond
				and track.HighY - crossing.Top >= config.TunnelMinFallStuds
			impossible = s.Y < crossing.Top - config.FloorSinkStuds and not tunnel
			measure, budget = crossing.Top - s.Y, config.FloorSinkStuds
		else
			-- The highest the root could have been when it crossed, by three bounds: from the ground, from the
			-- last sample going up, and from this one coming down.
			local lift = if step.Live then track.Lift else 0
			local apexAlt = track.GroundY + MovementGuard.maxRise(config) + track.Lift
			local apexRise = track.LastY + riseWithin(dt, config) + lift
			local apexFall = s.Y + 0.5 * config.Gravity * dt * dt + lift
			local apex = math.min(apexAlt, apexRise, apexFall)
			local needed = crossing.Top + config.StandMinStuds
			impossible = needed > apex + config.NoclipTopSlackStuds
			measure, budget = needed, apex
		end
		if impossible then
			local rule = if crossing.Floor then "floor" else "wall"
			raise(step, "Noclip", rule, measure, budget)
			track.Beyond = true
			track.BeyondRule = rule
			track.PlaneX, track.PlaneY, track.PlaneZ = crossing.PlaneX, crossing.PlaneY, crossing.PlaneZ
			track.NormalX, track.NormalY, track.NormalZ = crossing.NormalX, crossing.NormalY, crossing.NormalZ
		end
	elseif track.Beyond then
		local side = (s.X - track.PlaneX) * track.NormalX
			+ (s.Y - track.PlaneY) * track.NormalY
			+ (s.Z - track.PlaneZ) * track.NormalZ
		if side < 0 and now - track.Episodes.Noclip.LastCountAt <= config.ConfirmWindowSeconds then
			raise(step, "Noclip", track.BeyondRule, -side, 0)
		else
			track.Beyond = false
		end
	end
end

----------------------------------------------------------------
-- Confirmation and the verdict
----------------------------------------------------------------

-- Whether this count of `kind` falls under an exemption: corrected all the same, never struck.
local function exempt(track: Track, s: Sample, kind: Kind, live: boolean, config: Config): boolean
	local now = s.At
	if kind == "Invalid" then
		return false
	end
	-- Sent back to where it came from by a stream still delivering the old place.
	local returning = kind == "Teleport"
		and now - track.TeleportAt < config.ReturnExemptSeconds
		and dist3(s.X, s.Y, s.Z, track.FromX, track.FromY, track.FromZ) <= config.ArrivalRadiusStuds
	return live
		or now < track.ContactUntil
		or now < track.ExemptUntil
		or s.Down
		or now < track.SpawnUntil
		or now < track.HitchUntil
		or (kind == "Teleport" and track.CatchUp)
		or returning
end

-- Counts every flag of this sample into its kind's episode and returns the first kind flagged. A flag counts
-- on a new sample, or again once it has persisted PersistSeconds without one: a tick is not a sample. An
-- episode's exemption is sticky, so a confirmation cannot launder the reason its first count was exempt.
local function confirm(track: Track, s: Sample, step: Step, config: Config): Kind?
	local now = s.At
	local chosen: Kind? = nil
	-- Indexed into an annotated local: the type checker widens a for-in variable over a union of strings.
	for i = 1, #KINDS do
		local kind: Kind = KINDS[i]
		local episode = track.Episodes[kind]
		if step.Flags[kind] ~= nil then
			if step.Moved or now - episode.LastCountAt >= config.PersistSeconds then
				if now - episode.LastCountAt > config.ConfirmWindowSeconds then
					episode = newEpisode()
					track.Episodes[kind] = episode
				end
				episode.Count += 1
				episode.LastCountAt = now
				if exempt(track, s, kind, step.Live, config) then
					episode.Exempt = true
				end
				if now < track.ContactUntil or now < track.ExemptUntil then
					episode.Touched = true
				end
			end
			if chosen == nil then
				chosen = kind
			end
		elseif now - episode.LastCountAt > config.ConfirmWindowSeconds and episode.Count > 0 then
			-- Windowed, not consecutive: a flag that skips a sample is still the same episode.
			track.Episodes[kind] = newEpisode()
		end
	end
	return chosen
end

-- F3: a body that stopped moving in the air. The server cannot tell a body held up from a stream that stopped
-- mid-jump, so this rule never moves anyone: it is flagged once per FrozenAirSeconds of stillness, and struck
-- only when the client is visibly alive (validated remotes arriving) and it keeps happening. Nil when the body
-- is not frozen.
local function frozenAir(track: Track, s: Sample, step: Step, config: Config): Verdict?
	local now = s.At
	local frozenFor = now - track.LastMoveAt
	if
		step.Moved
		or s.Supported
		or s.Down
		or frozenFor < config.FrozenAirSeconds
		or s.Y - track.GroundY <= config.FrozenMinHeightStuds
	then
		return nil
	end
	local times = track.FrozenAt
	local last = times[#times]
	if last ~= nil and now - last < config.FrozenAirSeconds then
		return none()
	end
	while #times > 0 and times[1] < now - config.FrozenRepeatWindowSeconds do
		table.remove(times, 1)
	end
	table.insert(times, now)
	local alive = s.LastInboundAt > track.LastMoveAt + step.Rtt + config.InboundMarginSeconds
	local strikeable = alive
		and #times >= config.FrozenStrikeRepeat
		and not exempt(track, s, "Flight", step.Live, config)
	return verdict("Watch", "Flight", "frozen", strikeable, frozenFor, config.FrozenAirSeconds, 0, 0, 0)
end

-- A confirmed kind is corrected: Speed to where its evidence began, Flight to recent ground, anything else to
-- the newest point the body was believed at.
local function decide(track: Track, s: Sample, step: Step, kind: Kind, config: Config): Verdict
	local now = s.At
	local episode = track.Episodes[kind]
	local flag = step.Flags[kind]
	if episode.Count < config.ConfirmCount then
		return verdict("Watch", kind, flag.Rule, false, flag.Measure, flag.Budget, 0, 0, 0)
	end
	local x, y, z
	if kind == "Speed" then
		x, y, z = step.SpeedX, step.SpeedY, step.SpeedZ
	else
		x, y, z = safeTarget(track, now, kind == "Flight", config)
	end
	if episode.Touched then
		track.ExemptUntil = math.max(track.ExemptUntil, now + config.SettleMaxSeconds + contactLatch(step.Rtt, config))
	end
	return verdict("Correct", kind, flag.Rule, not episode.Exempt, flag.Measure, flag.Budget, x, y, z)
end

-- Judges one server tick's sample of a body.
function MovementGuard.observe(track: Track, s: Sample, config: Config): Verdict
	local now = s.At
	local limit = config.MaxCoordinateStuds
	if not (finite(s.X, limit) and finite(s.Y, limit) and finite(s.Z, limit)) then
		return invalid(track, now, config)
	end
	if not track.Based then
		-- Only when no spawn point was known: the first sample is all there is (MovementAudit logs it).
		base(track, s.X, s.Y, s.Z, now, if s.Supported then s.Y else nil)
		return none()
	end
	local rtt = clampRtt(s.Rtt, config)
	if s.Hitch then
		-- A strike grace only. It never rebases: the fall envelope has to survive a server hitch.
		track.HitchUntil = now + config.HitchGraceSeconds
	end
	if s.Contact then
		track.ContactUntil = math.max(track.ContactUntil, now + contactLatch(rtt, config))
	end
	noteWalk(track, now, s.WalkSpeed)
	local quiet = hear(track, s, config)
	local stop = if track.Pending then pending(track, s, config) else staleReturn(track, s, config)
	if stop ~= nil then
		return stop
	end

	local live = grantLive(track, now)
	if live then
		track.GrantCoverUntil = now
	else
		track.Allowance = 0
	end
	local step: Step = {
		Rtt = rtt,
		Live = live,
		Moved = dist3(s.X, s.Y, s.Z, track.LastX, track.LastY, track.LastZ) > config.StillEpsilonStuds,
		Quiet = quiet,
		Flags = {},
		SpeedX = 0,
		SpeedY = 0,
		SpeedZ = 0,
	}
	judgeHorizontal(track, s, step, config)
	judgeVertical(track, s, step, config)
	judgeNoclip(track, s, step, config)
	if step.Moved then
		track.LastX, track.LastY, track.LastZ, track.LastAt = s.X, s.Y, s.Z, now
		track.LastMoveAt = now
		pushPath(track, now, s.X, s.Z)
	end

	local kind: Kind? = confirm(track, s, step, config)
	if kind ~= nil then
		return decide(track, s, step, kind, config)
	end
	local frozen = frozenAir(track, s, step, config)
	if frozen ~= nil then
		return frozen
	end
	-- A sample becomes a correction target only once the anchor has nearly caught up with the body.
	if track.Gap <= track.Forgiven + config.CleanGapStuds and step.Moved then
		pushSafe(track, now, s.X, s.Y, s.Z, s.Supported)
	end
	return none()
end

return MovementGuard
