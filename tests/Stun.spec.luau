--!strict
-- A fair stun (D-XXXb): dated on the server's clock, ended by a message the owning client applies, never chained by
-- glyphs into one long hold, and watched for a body that walks through it. The clock and the watch are pure and run
-- here on whole chains and motions; MovementService and the client's MovementController run in the pretend engine
-- (tests/engine.luau), so what goes over the wire is the service's own.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local MovementGuard = require("../src/shared/Pure/MovementGuard")
local MovementGuardConfig = require("../src/server/Config/MovementGuardConfig")
local ServerWorld = require("./serverworld")
local Sim = require("./movementsim")
local StunClock = require("../src/shared/Pure/StunClock")
local StunWatch = require("../src/shared/Pure/StunWatch")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local GRACE = CombatConfig.Hit.StunGraceSeconds
local TICK = 1 / GameConfig.Server.TickRate
local WALK = GameConfig.Movement.WalkSpeed

describe("StunClock", function()
	it("dates a stun from when it began to when it ends, and never shortens it", function()
		local clock = StunClock.new()
		expect(StunClock.hold(clock, 1, 0.8)).toBeCloseTo(0.8, 9)
		expect(clock.StartedAt).toBe(1)
		expect(clock.Until).toBeCloseTo(1.8, 9)
		-- A shorter hold leaves it; a longer one extends it and keeps its start.
		expect(StunClock.hold(clock, 1.5, 0.1)).toBeCloseTo(0.3, 9)
		expect(clock.Until).toBeCloseTo(1.8, 9)
		StunClock.hold(clock, 1.5, 0.5)
		expect(clock.StartedAt).toBe(1)
		expect(clock.Until).toBeCloseTo(2, 9)
		expect(StunClock.running(clock, 1.99)).toBe(true)
		expect(StunClock.running(clock, 2)).toBe(false)
	end)

	it("ends a stun on its own date, however late the tick that notices", function()
		local clock = StunClock.new()
		StunClock.hold(clock, 1, 0.8)
		expect(StunClock.expire(clock, 1.7)).toBe(false)
		expect(StunClock.expire(clock, 2.3)).toBe(true)
		expect(clock.EndedAt).toBeCloseTo(1.8, 9)
		expect(clock.StartedAt).toBe(0)
		expect(clock.Until).toBe(0)
		expect(StunClock.expire(clock, 2.4)).toBe(false)
		-- The next one is dated anew, even when nothing swept the last one first.
		StunClock.hold(clock, 3, 0.4)
		StunClock.hold(clock, 3.6, 0.4)
		expect(clock.EndedAt).toBeCloseTo(3.4, 9)
		expect(clock.StartedAt).toBe(3.6)
	end)

	it("admits a glyph's stun only with no stun running and the grace passed since the last one", function()
		local clock = StunClock.new()
		expect(StunClock.admits(clock, 0, GRACE)).toBe(true)
		StunClock.hold(clock, 1, 0.8)
		expect(StunClock.admits(clock, 1.2, GRACE)).toBe(false)
		expect(StunClock.admits(clock, 1.8 + GRACE - 0.01, GRACE)).toBe(false)
		expect(StunClock.admits(clock, 1.8 + GRACE, GRACE)).toBe(true)
	end)

	it("ends a stun now when the server lets go of it, and says whether one ran", function()
		local clock = StunClock.new()
		expect(StunClock.clear(clock, 1)).toBe(false)
		StunClock.hold(clock, 1, 5)
		expect(StunClock.clear(clock, 2)).toBe(true)
		expect(StunClock.running(clock, 2)).toBe(false)
		expect(clock.EndedAt).toBe(2)
	end)
end)

-- Empattement (Serif), Rupture and Filigrane (Watermark) on one target, cast by three players at every offset: the
-- longest the target is held without a break. Every hit is taken to land, the worst case.
describe("a chain of stun glyphs on one target", function()
	local serif = GlyphConfig.ById.Serif.Params
	local rupture = GlyphConfig.ById.Rupture.Params
	local watermark = GlyphConfig.ById.Watermark.Params
	local LONGEST = math.max(serif.Stun, rupture.Stun, watermark.StunSeconds)
	local STEP = 0.05
	local SPAN = 3

	type Event = { At: number, Seconds: number }

	-- The events of one cast of each: the Serif's spike reaching the target, the Rupture's wave, every Watermark tick.
	local function events(serifAt: number, ruptureAt: number, watermarkAt: number): { Event }
		local list: { Event } = {
			{ At = serifAt, Seconds = serif.Stun },
			{ At = ruptureAt, Seconds = rupture.Stun },
		}
		for tick = 1, watermark.Ticks do
			table.insert(
				list,
				{ At = watermarkAt + (tick - 1) * watermark.TickInterval, Seconds = watermark.StunSeconds }
			)
		end
		table.sort(list, function(a: Event, b: Event): boolean
			return a.At < b.At
		end)
		return list
	end

	-- Applies `list` to one target, each event through the grace when `graced` (MovementService.applyGlyphStun) or as
	-- a plain hold (the rule before). Returns the longest unbroken hold, the shortest break between two, and how many
	-- stuns landed.
	local function hold(list: { Event }, graced: boolean): (number, number, number)
		local clock = StunClock.new()
		local spans: { { number } } = {}
		local landed = 0
		for _, event in ipairs(list) do
			if not graced or StunClock.admits(clock, event.At, GRACE) then
				StunClock.hold(clock, event.At, event.Seconds)
				landed += 1
				local last = spans[#spans]
				if last ~= nil and last[1] == clock.StartedAt then
					last[2] = clock.Until
				else
					table.insert(spans, { clock.StartedAt, clock.Until })
				end
			end
		end
		-- Two holds that touch are one.
		local longest, gap = 0, math.huge
		local from, to = spans[1][1], spans[1][2]
		for index = 2, #spans do
			local span = spans[index]
			if span[1] <= to + 1e-9 then
				to = math.max(to, span[2])
			else
				gap = math.min(gap, span[1] - to)
				longest = math.max(longest, to - from)
				from, to = span[1], span[2]
			end
		end
		return math.max(longest, to - from), gap, landed
	end

	local function worst(graced: boolean): (number, number)
		local longest, gap = 0, math.huge
		local steps = math.round(SPAN / STEP)
		for a = 0, steps do
			for b = 0, steps do
				for c = 0, steps do
					local held, apart = hold(events(a * STEP, b * STEP, c * STEP), graced)
					longest, gap = math.max(longest, held), math.min(gap, apart)
				end
			end
		end
		return longest, gap
	end

	it("never holds the target longer than its longest glyph, and gives the grace back between two", function()
		local longest, gap = worst(true)
		expect(longest).toBeLessThanOrEqual(LONGEST + 1e-9)
		expect(longest).toBeCloseTo(rupture.Stun, 9)
		expect(gap).toBeGreaterThanOrEqual(GRACE - 1e-9)
		expect(LONGEST).toBeLessThanOrEqual(CombatConfig.Hit.StunMaxSeconds)
	end)

	it("held it far longer when a glyph's stun extended the one running", function()
		local longest = worst(false)
		expect(longest).toBeGreaterThan(LONGEST + 0.4)
	end)

	it("keeps every tick of a Watermark alone", function()
		local alone: { Event } = {}
		for _, event in ipairs(events(-100, -100, 0)) do
			if event.At >= 0 then
				table.insert(alone, event)
			end
		end
		local _, _, landed = hold(alone, true)
		expect(landed).toBe(watermark.Ticks)
		expect(watermark.TickInterval - watermark.StunSeconds).toBeGreaterThanOrEqual(GRACE)
	end)
end)

-- A body stunned at 1 s for `stun` s, simulated at 240 Hz and replicated every tick with `latency` one way; the
-- server audits it every tick. `walks(t)` is how fast the client walks it at t (an honest client stops once the stun
-- reaches it), `grant` an interval the server's push carries it. Returns what the watch reported, or nil.
local function audit(stun: number, latency: number, walks: (number) -> number, grant: { number }?): number?
	local STEPS = 240
	local START = 1
	local watch = StunWatch.new()
	local x = 0
	local packets: { { number } } = {}
	local seen = 0
	local reported: number? = nil
	for step = 1, 4 * STEPS do
		local now = step / STEPS
		x += walks(now) / STEPS
		local onTick = step % (STEPS / GameConfig.Server.TickRate) == 0
		if onTick then
			table.insert(packets, { now + latency, x })
		end
		while #packets > 0 and packets[1][1] <= now + 1e-9 do
			seen = table.remove(packets, 1)[2]
		end
		if onTick then
			local running = now >= START and now < START + stun
			local startedAt = if running then START else 0
			local endsAt = if running then START + stun else 0
			local learned = StunWatch.learnedAt(startedAt, 2 * latency, MovementGuardConfig.SettleOverheadSeconds)
			local carried = grant ~= nil and now >= grant[1] and now < grant[2]
			local found = StunWatch.step(
				watch,
				now,
				startedAt,
				endsAt,
				learned,
				seen,
				0,
				carried,
				MovementGuardConfig.StunWalkSlackStuds
			)
			if found ~= nil then
				expect(reported).toBe(nil)
				reported = found
			end
		end
	end
	return reported
end

describe("the stun watch", function()
	local LATENCIES = { 0.025, 0.05, 0.1, 0.2, 0.3, 0.45 }

	it("reports nothing of an honest body that stops once the stun reaches it", function()
		-- It walks until the stun reaches its client, then comes to rest over a tenth of a second, and walks on
		-- once the end has reached it.
		for _, latency in ipairs(LATENCIES) do
			for _, stun in ipairs({ 0.4, 0.8, CombatConfig.Block.BreakStunSeconds, CombatConfig.Hit.StunMaxSeconds }) do
				local honest = function(t: number): number
					local since = t - (1 + latency)
					if since < 0 or t >= 1 + stun + latency then
						return WALK
					end
					return WALK * math.max(0, 1 - since / 0.1)
				end
				expect(audit(stun, latency, honest, nil)).toBe(nil)
			end
		end
	end)

	it("reports, once, a body that walks through a stun it was told of", function()
		local function walker(): number
			return WALK
		end
		-- A Rupture's stun up to a tenth of a second one way; beyond that it is over before it can be judged.
		for _, latency in ipairs({ 0.025, 0.05, 0.1 }) do
			local walked = audit(0.8, latency, walker, nil)
			expect(walked).never.toBe(nil)
			expect(walked :: number).toBeGreaterThan(MovementGuardConfig.StunWalkSlackStuds)
		end
		-- The longest a stun lasts, through every latency above.
		for _, latency in ipairs(LATENCIES) do
			expect(audit(CombatConfig.Hit.StunMaxSeconds, latency, walker, nil)).never.toBe(nil)
		end
	end)

	it("counts nothing the server's own push carried", function()
		-- A Rupture launches as it stuns: the push the server granted is not the victim walking.
		local pushed = function(t: number): number
			return if t >= 1.05 and t < 1.6 then 60 else 0
		end
		expect(audit(0.8, 0.05, pushed, { 1, 1.7 })).toBe(nil)
		expect(audit(0.8, 0.05, pushed, nil)).never.toBe(nil)
	end)

	it("reads a grant as carrying the body for as long as the judge does", function()
		local track = MovementGuard.newTrack(Sim.config)
		expect(MovementGuard.granting(track, 0)).toBe(false)
		MovementGuard.grant(track, 20, 0, 0.25, 1, 0.1, Sim.config)
		expect(MovementGuard.granting(track, 1.1)).toBe(true)
		expect(MovementGuard.granting(track, 1 + Sim.config.AwaitCapSeconds + 0.01)).toBe(false)
	end)

	it("never opens a window on a round trip that is not a number", function()
		expect(StunWatch.learnedAt(1, 0 / 0, 0.1)).toBe(math.huge)
		expect(StunWatch.learnedAt(1, -1, 0.1)).toBeCloseTo(1.1, 9)
	end)
end)

----------------------------------------------------------------
-- The service and the client, in the pretend engine
----------------------------------------------------------------

describe("MovementService's stuns", function()
	it("dates each stun and tells the client its seconds, then its end when it lets go early", function()
		local s = ServerWorld.start()
		s.world:advance(1)
		s.service.applyStun(s.player, 0.8)
		local startedAt, endsAt = s.service.stunDates(s.player)
		expect(startedAt).toBeCloseTo(s.world.now, 9)
		expect(endsAt).toBeCloseTo(s.world.now + 0.8, 9)
		expect(s.humanoid.WalkSpeed).toBe(0)
		local last = s.sent[#s.sent]
		expect(last[1]).toBe("MovementCommand")
		expect(last[3].Kind).toBe("Stun")
		expect(last[3].Seconds).toBeCloseTo(0.8, 9)
		s.service.clearStun(s.player)
		expect(s.sent[#s.sent][3]).toEqual({ Kind = "StunEnd" })
		expect(s.humanoid:GetAttribute(CombatConfig.Status.StunAttribute)).toBe(nil)
		expect(s.humanoid.WalkSpeed).toBe(GameConfig.Movement.WalkSpeed)
		expect(s.service.isStunned(s.player)).toBe(false)
		local none, zero = s.service.stunDates(s.player)
		expect(none).toBe(0)
		expect(zero).toBe(0)
	end)

	it("ends a stun on the tick after its date, and the attribute with it", function()
		local s = ServerWorld.start()
		s.service.applyStun(s.player, 0.5)
		s.world:advance(0.4)
		expect(s.service.isStunned(s.player)).toBe(true)
		s.world:advance(0.2)
		expect(s.service.isStunned(s.player)).toBe(false)
		expect(s.humanoid:GetAttribute(CombatConfig.Status.StunAttribute)).toBe(nil)
		expect(s.humanoid.WalkSpeed).toBe(GameConfig.Movement.WalkSpeed)
	end)

	it("refuses a glyph's stun while one runs and within the grace after it, and says so to nobody", function()
		local s = ServerWorld.start()
		s.service.applyStun(s.player, 0.5)
		local before = #s.sent
		expect(s.service.applyGlyphStun(s.player, 0.8)).toBe(false)
		expect(#s.sent).toBe(before)
		s.world:advance(0.5 + GRACE / 2)
		expect(s.service.applyGlyphStun(s.player, 0.8)).toBe(false)
		expect(s.service.isStunned(s.player)).toBe(false)
		s.world:advance(GRACE / 2 + TICK)
		expect(s.service.applyGlyphStun(s.player, 0.8)).toBe(true)
		expect(s.sent[#s.sent][3].Kind).toBe("Stun")
		-- A combat hold still extends it.
		s.service.applyStun(s.player, 1.2)
		local startedAt, endsAt = s.service.stunDates(s.player)
		expect(endsAt - startedAt).toBeCloseTo(1.2, 9)
	end)
end)

describe("the client's MovementController", function()
	local function client(): (any, (any) -> ())
		local world = Engine.world({ Stubs = { ["src/shared/Util/Log"] = ServerWorld.recordingLog({}) } })
		local controller = world.require("src/client/Controllers/MovementController")
		local handler: ((any) -> ())? = nil
		controller.Init({
			RemoteClient = {
				on = function(name: string, fn: (any) -> ())
					if name == "MovementCommand" then
						handler = fn
					end
				end,
			},
			Feel = nil,
		})
		controller.Start()
		assert(handler ~= nil, "MovementController never listened to MovementCommand")
		return world, handler :: (any) -> ()
	end

	it("locks the input for a stun's seconds, and gives it back the moment the server says it ended", function()
		local world, command = client()
		command({ Kind = "Stun", Seconds = 2 })
		expect(world.bindings.MovementStun).never.toBe(nil)
		world:advance(0.5)
		command({ Kind = "StunEnd" })
		expect(world.bindings.MovementStun).toBe(nil)
		-- The timer the first stun armed ends nothing: a stun that came after it runs its own time.
		command({ Kind = "Stun", Seconds = 2 })
		world:advance(1.6)
		expect(world.bindings.MovementStun).never.toBe(nil)
		world:advance(0.5)
		expect(world.bindings.MovementStun).toBe(nil)
	end)
end)

describe("the stun rule's wiring", function()
	local function code(path: string): string
		return ((fs.readFile(path):gsub("%-%-[^\n]*", "")):gsub("%s+", " "))
	end

	it("sends every glyph's stun through the grace, and every other hold around it", function()
		local effects = code("src/server/Effects/GlyphEffects.luau")
		expect(effects).toContain("if player ~= nil then ctx.Movement.applyGlyphStun(player, seconds) else")
		local movement = code("src/server/Services/MovementService.luau")
		expect(movement).toContain(
			"if not StunClock.admits(state.Stun, os.clock(), CombatConfig.Hit.StunGraceSeconds) then return false end MovementService.applyStun(player, seconds) return true"
		)
		expect(movement).never.toContain('Kind = "Stun", Seconds = 0')
	end)

	it("logs a walk through a stun in every mode, and never moves nor strikes for it", function()
		local source = code("src/server/Security/MovementAudit.luau")
		local start = source:find("local function watchStun(", 1, true)
		assert(start ~= nil, "MovementAudit has no watchStun: this gate would check nothing")
		local watch = source:sub(start, (source:find("local function audit(", start, true)))
		expect(watch).toContain("local startedAt, endsAt = deps.Movement.stunDates(record.Player)")
		expect(watch).toContain(
			"local carried = sample.Down or body.Contact or MovementGuard.granting(track, now) or now < track.ContactUntil"
		)
		expect(watch).toContain("log.warn(")
		for _, never in ipairs({ "strike(", "PivotTo(", "MovementGuardConfig.Mode", "Reanchor(" }) do
			expect(watch).never.toContain(never)
		end
		expect(source).toContain(
			"enforce(body, sample, verdict, now) if body.Sane then watchStun(body, sample, now) end"
		)
	end)
end)
