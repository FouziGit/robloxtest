--!strict
-- A client, a network and a server around Pure/MovementGuard, for tests/MovementScenarios.spec.luau and
-- tests/MovementGuard.spec.luau. The client simulates its own body at 240 Hz (walking, jumping, the double
-- jump, the granted movers on their FeelMath.impulseSpeed curve at the client's frame rate) and replicates it
-- every SendEvery seconds with latency, stalls, jitter and spikes. The server ticks at GameConfig.Server's
-- rate and does what MovementAudit does: support probe, barrier ray, path scan, contact, WalkSpeed, grants and
-- teleports, and a pivot on every correction. One horizontal axis (x) plus height (y).
--
-- The judge's config is built here the way CombatService builds it for MovementAudit: MovementGuardConfig, plus
-- the engine and GameConfig values it does not hold.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local FeelMath = require("../src/shared/Pure/FeelMath")
local GameConfig = require("../src/shared/Config/GameConfig")
local MovementGuard = require("../src/shared/Pure/MovementGuard")
local MovementGuardConfig = require("../src/server/Config/MovementGuardConfig")

-- Roblox's default gravity, which the game never changes. CombatService passes the live Workspace.Gravity.
local GRAVITY = 196.2
-- CombatService's GUARD.StillEpsilonStuds, which it passes on to the judge. It is a property of character
-- jitter kept in CombatService rather than in a config, so it is restated here as tests/OriginGuard.spec.luau
-- does.
local STILL_EPSILON_STUDS = 0.05

local function buildConfig(): MovementGuard.Config
	local config = table.clone(MovementGuardConfig) :: any
	config.Gravity = GRAVITY
	config.JumpVelocity = GameConfig.Movement.JumpPower
	config.DoubleJumpVelocity = GameConfig.Movement.DoubleJumpVelocity
	config.MaxSpeedStudsPerSecond = GameConfig.Latency.MaxSpeedStudsPerSecond
	config.MaxBudgetSeconds = GameConfig.Latency.MaxBudgetSeconds
	config.StillEpsilonStuds = STILL_EPSILON_STUDS
	config.TickSeconds = 1 / GameConfig.Server.TickRate
	return config :: MovementGuard.Config
end

local CONFIG = buildConfig()

-- An R15 body's standing root height: HipHeight 2 plus half its 2-stud root.
local STAND = 3
-- The support probe reaches this far past the feet.
local PROBE = MovementGuardConfig.GroundProbeSlackStuds
local CLIENT_STEP = 1 / 240
-- The server's first tick falls between two client steps, as it would.
local FIRST_TICK = 0.013

export type Floor = { X0: number, X1: number, Top: number, Tagged: boolean? }
export type Wall = { X0: number, X1: number, Bottom: number, Top: number }
-- A burst the server grants: { at, "Dash" | "Knockback", horizontal speed, vertical speed, seconds, exponent }.
export type Grant = { any }
-- A time window { from, to }, or { from, to, extra seconds } for a delay.
export type Window = { number }

export type Scenario = {
	Name: string,
	Seconds: number,
	-- One-way latency; the round trip the server reads is twice this, times RttScale.
	Latency: number,
	RttScale: number?,
	Fps: number?,
	SendEvery: number?,
	Seed: number?,
	-- Uplink jitter: up to this many extra seconds on every packet.
	Jitter: number?,
	StartX: number?,
	StartY: number?,
	-- Where the server spawned the body, when it is not the start.
	SpawnPoint: { number }?,
	Floors: { Floor }?,
	Walls: { Wall }?,
	Walk: ((t: number) -> number)?,
	WalkSpeedAt: ((t: number) -> number)?,
	-- A tampered client: overrides the body's x and y after physics.
	Cheat: ((t: number, x: number, y: number) -> (number?, number?))?,
	Jumps: { number }?,
	DoubleJumps: { number }?,
	-- Lands on the surface with this top and jumps and double jumps again at once.
	AutoJumpOn: number?,
	Grants: { Grant }?,
	-- { at, x, y }: the server pivots the body there.
	Teleports: { { number } }?,
	-- Uplink silent in these windows.
	Stalls: { Window }?,
	UpDelay: { Window }?,
	DownDelay: { Window }?,
	-- Downlink silent from [1] to [2]: everything sent in it arrives after it, in order.
	DownStall: { number }?,
	ServerHitch: { Window }?,
	-- { from, to, x offset, y offset? } on the replicated position.
	Spike: { number }?,
	-- After 2 s, one packet in this many is replicated 100 studs aside.
	FlickerPeriod: number?,
	Down: { Window }?,
	Contact: { Window }?,
	-- Validated remotes arrive every tick, one latency old.
	RemotesAlways: boolean?,
	-- The client plays no granted mover.
	IgnoreGrants: boolean?,
	-- The client never applies a server pivot.
	CheatIgnoresPivot: boolean?,
}

export type Stats = {
	Watch: number,
	Correct: number,
	Strike: number,
	Repivot: number,
	-- The first correction, repivot or strikeable watch, for a failure message.
	First: string?,
}

-- "clean": no correction, no repivot, no strike. "nostrike": corrections allowed, never a strike.
-- "correct": at least one correction or repivot. "strike": at least one strike.
export type Expectation = "clean" | "nostrike" | "correct" | "strike"

type Mover = { Duration: number, VX: number, VY: number, Exp: number, V: number, Since: number, El: number }

local function supportTop(floors: { Floor }, walls: { Wall }, x: number, y: number): number?
	for _, f in ipairs(floors) do
		if x >= f.X0 - 1 and x <= f.X1 + 1 and y >= f.Top + STAND - 2.01 and y <= f.Top + STAND + PROBE then
			return f.Top
		end
	end
	for _, w in ipairs(walls) do
		if x >= w.X0 - 1 and x <= w.X1 + 1 and y >= w.Top + STAND - 2.01 and y <= w.Top + STAND + PROBE then
			return w.Top
		end
	end
	return nil
end

local function surfaces(floors: { Floor }, walls: { Wall }): { Floor }
	local out: { Floor } = {}
	for _, f in ipairs(floors) do
		table.insert(out, f)
	end
	for _, w in ipairs(walls) do
		table.insert(out, { X0 = w.X0, X1 = w.X1, Top = w.Top })
	end
	return out
end

local function landingTop(all: { Floor }, x: number, yFrom: number, yTo: number): number?
	local best: number? = nil
	for _, f in ipairs(all) do
		if x >= f.X0 and x <= f.X1 and yFrom >= f.Top + STAND - 1e-6 and yTo < f.Top + STAND then
			if best == nil or f.Top > best then
				best = f.Top
			end
		end
	end
	return best
end

local function within(list: { Window }?, at: number): boolean
	for _, d in ipairs(list or {}) do
		if at >= d[1] and at < d[2] then
			return true
		end
	end
	return false
end

-- The server's barrier ray from the last judged sample to this one, against the walls and tagged floors.
local function crossing(
	floors: { Floor },
	walls: { Wall },
	x0: number,
	y0: number,
	x1: number,
	y1: number
): MovementGuard.Crossing?
	local found: MovementGuard.Crossing? = nil
	for _, w in ipairs(walls) do
		local entry: number? = nil
		if x0 < w.X0 and x1 > w.X1 then
			entry = w.X0
		elseif x0 > w.X1 and x1 < w.X0 then
			entry = w.X1
		end
		if entry ~= nil then
			local hy = y0 + (y1 - y0) * (entry - x0) / (x1 - x0)
			if hy <= w.Top and hy >= w.Bottom then
				local nx = if x0 < w.X0 then -1 else 1
				found = {
					HitY = hy,
					Top = w.Top,
					Floor = false,
					PassThrough = true,
					PlaneX = entry,
					PlaneY = 0,
					PlaneZ = 0,
					NormalX = nx,
					NormalY = 0,
					NormalZ = 0,
				}
			end
		end
	end
	for _, f in ipairs(floors) do
		if f.Tagged and y0 >= f.Top and y1 < f.Top - 1 then
			local cx = x0 + (x1 - x0) * (y0 - f.Top) / (y0 - y1)
			if cx >= f.X0 + 1 and cx <= f.X1 - 1 then
				found = {
					HitY = f.Top,
					Top = f.Top,
					Floor = true,
					PassThrough = true,
					PlaneX = cx,
					PlaneY = f.Top,
					PlaneZ = 0,
					NormalX = 0,
					NormalY = 1,
					NormalZ = 0,
				}
			end
		end
	end
	return found
end

local function note(stats: Stats, v: MovementGuard.Verdict, now: number)
	local kind = tostring(v.Kind)
	if v.Action == "Watch" then
		stats.Watch += 1
		if v.Strikeable then
			stats.Strike += 1
			if stats.First == nil then
				stats.First =
					string.format("Watch %s/%s t=%.2f (%.1f vs %.1f) STRIKE", kind, v.Rule, now, v.Measure, v.Budget)
			end
		end
		return
	end
	if v.Action == "Correct" then
		stats.Correct += 1
	else
		stats.Repivot += 1
	end
	if v.Strikeable then
		stats.Strike += 1
	end
	if stats.First == nil then
		stats.First = string.format(
			"%s %s/%s t=%.2f (%.1f vs %.1f)%s",
			v.Action,
			kind,
			v.Rule,
			now,
			v.Measure,
			v.Budget,
			if v.Strikeable then " STRIKE" else ""
		)
	end
end

-- Runs one scenario and counts the verdicts.
local function run(sc: Scenario): Stats
	local floors: { Floor } = sc.Floors or { { X0 = -1e9, X1 = 1e9, Top = 0 } }
	local walls: { Wall } = sc.Walls or {}
	local all = surfaces(floors, walls)
	local fps = sc.Fps or 60
	local latency = sc.Latency
	local rtt = 2 * latency * (sc.RttScale or 1)
	local jump = CONFIG.JumpVelocity
	local doubleJump = CONFIG.DoubleJumpVelocity
	local tick = CONFIG.TickSeconds
	local track = MovementGuard.newTrack(CONFIG)
	math.randomseed(sc.Seed or 1)
	local x = sc.StartX or 0
	local y = sc.StartY or (floors[1].Top + STAND)
	local vy = 0
	local grounded = true
	local jumpCount = 0
	local movers: { Mover } = {}
	local packets: { { number } } = {}
	local serverX, serverY = x, y
	local lastApplied = -1
	local pendingCmds: { { any } } = {}
	local function delayOf(list: { Window }?, at: number, down: boolean?): number
		local stall = if down then sc.DownStall else nil
		if stall ~= nil and at >= stall[1] and at < stall[2] then
			return stall[2] - at + latency -- an ordered stream: everything sent in the stall arrives after it
		end
		local extra = 0
		for _, d in ipairs(list or {}) do
			if at >= d[1] and at < d[2] then
				extra = d[3]
			end
		end
		return latency + extra
	end
	local serverEvents: { { any } } = {}
	for _, g in ipairs(sc.Grants or {}) do
		table.insert(pendingCmds, { g[1] + delayOf(sc.DownDelay, g[1], true), "grant", g })
		table.insert(serverEvents, { g[1], "grant", g })
	end
	for _, tp in ipairs(sc.Teleports or {}) do
		table.insert(serverEvents, { tp[1], "teleport", tp })
	end
	local sendEvery = sc.SendEvery or 1 / 20
	local nextSend = 0
	local nextTick = FIRST_TICK
	local lastTick = 0
	local frameEvery = 1 / fps
	local nextFrame = 0
	local stats: Stats = { Watch = 0, Correct = 0, Strike = 0, Repivot = 0, First = nil }
	local jumps = sc.Jumps or {}
	local djumps = table.clone(sc.DoubleJumps or {})
	local ji, di = 1, 1
	local t = 0
	local lastInbound = -math.huge
	local spawned = false
	local sent = 0
	while t < sc.Seconds do
		-- What the downlink delivers: grants start a mover, pivots move the body.
		for i = #pendingCmds, 1, -1 do
			local p = pendingCmds[i]
			if t >= p[1] then
				table.remove(pendingCmds, i)
				if p[2] == "grant" then
					local g = p[3]
					if not sc.IgnoreGrants then
						table.insert(
							movers,
							{ Duration = g[5], VX = g[3], VY = g[4], Exp = g[6], V = 0, Since = 0, El = 0 }
						)
						if g[2] == "Knockback" then
							vy = g[4]
						end
					end
				elseif p[2] == "pivot" and not sc.CheatIgnoresPivot then
					local tp = p[3]
					x, y, vy = tp[2], tp[3], 0
				end
			end
		end
		-- The client's frame: the movers re-evaluate their curve at most every Impulse.StepSeconds.
		if t >= nextFrame then
			nextFrame += frameEvery
			for i = #movers, 1, -1 do
				local m = movers[i]
				m.El += frameEvery
				if m.El >= m.Duration then
					table.remove(movers, i)
				else
					m.Since += frameEvery
					if m.Since >= FeelConfig.Impulse.StepSeconds then
						m.Since = 0
						m.V = FeelMath.impulseSpeed(m.El / m.Duration, m.Exp)
					end
				end
			end
		end
		if ji <= #jumps and t >= jumps[ji] then
			ji += 1
			if grounded then
				vy = jump
				grounded = false
				jumpCount = 1
			end
		end
		if di <= #djumps and t >= djumps[di] then
			di += 1
			if not grounded and jumpCount == 1 then
				vy = doubleJump
				jumpCount = 2
			end
		end
		local vx = if sc.Walk then sc.Walk(t) else 0
		local mover = movers[#movers]
		if mover ~= nil then
			local speed = if mover.V == 0 then FeelMath.impulseSpeed(0, mover.Exp) else mover.V
			vx = mover.VX * speed
			vy = mover.VY * speed
		elseif not grounded then
			vy -= GRAVITY * CLIENT_STEP
		end
		local ny = y + vy * CLIENT_STEP
		local nx = x + vx * CLIENT_STEP
		-- Walls block a body whose feet are below their top (a cheat moves through them on its own).
		for _, w in ipairs(walls) do
			if ny - STAND < w.Top - 0.01 then
				if x <= w.X0 and nx > w.X0 then
					nx = w.X0 - 1e-3
				elseif x >= w.X1 and nx < w.X1 then
					nx = w.X1 + 1e-3
				end
			end
		end
		if mover == nil or mover.VY <= 0 then
			local top = landingTop(all, nx, y, ny)
			if top ~= nil and vy <= 0 then
				ny = top + STAND
				vy = 0
				grounded = true
				jumpCount = 0
				if sc.AutoJumpOn ~= nil and top == sc.AutoJumpOn then
					vy = jump
					grounded = false
					jumpCount = 1
					table.insert(djumps, t + jump / GRAVITY)
					table.sort(djumps)
				end
			end
		end
		if grounded then
			local on = false
			for _, f in ipairs(all) do
				if nx >= f.X0 and nx <= f.X1 and math.abs(ny - (f.Top + STAND)) < 1e-3 then
					on = true
				end
			end
			if not on then
				grounded = false
			end
		end
		x, y = nx, ny
		if sc.Cheat then
			local cx, cy = sc.Cheat(t, x, y)
			if cx ~= nil then
				x = cx
			end
			if cy ~= nil then
				y = cy
				vy = 0
				grounded = supportTop(floors, walls, x, y) ~= nil
			end
		end
		-- The uplink: what the client replicates, and when it reaches the server.
		if t >= nextSend then
			nextSend += sendEvery
			if not within(sc.Stalls, t) then
				sent += 1
				local spike = sc.Spike
				local spiking = spike ~= nil and t >= spike[1] and t < spike[2]
				local px = if spike ~= nil and spiking then x + spike[3] else x
				if sc.FlickerPeriod ~= nil and t > 2 and sent % sc.FlickerPeriod == 0 then
					px = x + 100
				end
				local py = if spike ~= nil and spiking and spike[4] ~= nil then y + spike[4] else y
				local jitter = if sc.Jitter then math.random() * sc.Jitter else 0
				table.insert(packets, { t, t + delayOf(sc.UpDelay, t) + jitter, px, py })
			end
		end
		-- The server's tick, unless the server is hitched.
		if t >= nextTick then
			nextTick += tick
			if not within(sc.ServerHitch, t) then
				local now = t
				local hitch = lastTick > 0 and now - lastTick > MovementGuardConfig.HitchSeconds
				lastTick = now
				for i = #packets, 1, -1 do
					local p = packets[i]
					if p[2] <= now then
						if p[1] > lastApplied then
							lastApplied = p[1]
							serverX, serverY = p[3], p[4]
						end
						table.remove(packets, i)
					end
				end
				if sc.RemotesAlways then
					lastInbound = now - latency
				end
				if not spawned then
					spawned = true
					local sp = sc.SpawnPoint or { sc.StartX or 0, sc.StartY or (floors[1].Top + STAND) }
					MovementGuard.spawned(track, sp[1], sp[2], 0, now, CONFIG)
				end
				for i = #serverEvents, 1, -1 do
					local e = serverEvents[i]
					if now >= e[1] then
						table.remove(serverEvents, i)
						if e[2] == "grant" then
							local g = e[3]
							MovementGuard.grant(
								track,
								math.abs(g[3]) * g[5],
								math.max(0, g[4]) * g[5],
								g[5],
								now,
								rtt,
								CONFIG
							)
						else
							local tp = e[3]
							local fromX, fromY, fromZ = MovementGuard.heard(track)
							MovementGuard.teleported(track, tp[2], tp[3], 0, now, fromX, fromY, fromZ, true, CONFIG)
							serverX, serverY = tp[2], tp[3]
							table.insert(
								pendingCmds,
								{ now + delayOf(sc.DownDelay, now, true), "pivot", { now, tp[2], tp[3] } }
							)
						end
					end
				end
				local sample: MovementGuard.Sample = {
					At = now,
					X = serverX,
					Y = serverY,
					Z = 0,
					Supported = supportTop(floors, walls, serverX, serverY) ~= nil,
					StandHeight = STAND,
					Down = within(sc.Down, now),
					Contact = within(sc.Contact, now),
					WalkSpeed = if sc.WalkSpeedAt then sc.WalkSpeedAt(now) else GameConfig.Movement.WalkSpeed,
					Rtt = rtt,
					LastInboundAt = lastInbound,
					Hitch = hitch,
					Crossing = nil,
					SupportTops = nil,
				}
				if MovementGuard.wantsRay(track, sample, CONFIG) then
					local x0, y0 = MovementGuard.rayOrigin(track)
					sample.Crossing = crossing(floors, walls, x0, y0, serverX, serverY)
				end
				if MovementGuard.preview(track, sample, CONFIG) then
					local minX, minY, _, maxX, maxY = MovementGuard.scanBox(track, sample, CONFIG)
					local tops: { number } = {}
					for _, f in ipairs(all) do
						if f.X1 >= minX and f.X0 <= maxX and f.Top >= minY and f.Top <= maxY then
							table.insert(tops, f.Top)
						end
					end
					sample.SupportTops = tops
				end
				local v = MovementGuard.observe(track, sample, CONFIG)
				if v.Action ~= "None" then
					note(stats, v, now)
					if v.Action ~= "Watch" then
						if v.Action == "Correct" then
							local fromX, fromY, fromZ = MovementGuard.heard(track)
							local ground = supportTop(floors, walls, v.X, v.Y) ~= nil
							MovementGuard.teleported(track, v.X, v.Y, 0, now, fromX, fromY, fromZ, ground, CONFIG)
						end
						serverX, serverY = v.X, v.Y
						table.insert(
							pendingCmds,
							{ now + delayOf(sc.DownDelay, now, true), "pivot", { now, v.X, v.Y } }
						)
					end
				end
			end
		end
		t += CLIENT_STEP
	end
	return stats
end

local function meets(stats: Stats, expected: Expectation): boolean
	if expected == "clean" then
		return stats.Correct == 0 and stats.Repivot == 0 and stats.Strike == 0
	elseif expected == "nostrike" then
		return stats.Strike == 0
	elseif expected == "correct" then
		return stats.Correct + stats.Repivot > 0
	end
	return stats.Strike > 0
end

local function describe(stats: Stats): string
	return string.format(
		"watch %d, correct %d, repivot %d, strike %d; first: %s",
		stats.Watch,
		stats.Correct,
		stats.Repivot,
		stats.Strike,
		stats.First or "none"
	)
end

return {
	config = CONFIG,
	run = run,
	meets = meets,
	describe = describe,
}
