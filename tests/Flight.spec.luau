--!strict
-- One flight (D-114): the Brand a player sees is where the Brand that hurts is, and it comes down where it
-- burst. Measured before this: the drawn one left 0.2 s after the real one, on Sine Out from the chest,
-- and trailed the damage by up to 22 studs; a Brand that burst at twenty studs flew on alone to ninety;
-- one whose caster was stunned mid-flight did too. Then, reviewed and measured live: at full range the
-- burst reached the client a frame after the drawn flight ended in three throws out of four, so the trail
-- vanished at once and the dust hung at the thrower's hand; and a tail sound kept playing in the pool.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- One top-level function of a file, flattened, or an error: a gate that found nothing would pass.
local function functionIn(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local finish = source:find("\nend\n", start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + 4):gsub("%s+", " "))
end

local function has(code: string, fragment: string): boolean
	return code:find(fragment, 1, true) ~= nil
end

local EFFECTS = "src/server/Effects/GlyphEffects.luau"
local TIMELINE = "src/client/Controllers/VfxTimeline.luau"
local LIBRARY = "src/client/Controllers/VfxLibrary.luau"

local params = GlyphConfig.ById.Brand.Params :: any

local function brandCarrier(): any
	for _, phase in ipairs(VfxTimelineConfig.Timelines.Brand.Phases) do
		for _, layer in ipairs(phase.Layers) do
			if layer.Kind == "Carrier" then
				return layer
			end
		end
	end
	error("Brand has no carrier")
end

describe("the drawn Brand", function()
	it("leaves the hand when the server lets go of it", function()
		expect(params.Windup).toBeGreaterThan(0)
		-- Imperceptible, and the same at every range: it moves no balance.
		expect(params.Windup).toBeLessThanOrEqual(0.1)
		local travel = VfxTimelineConfig.phaseAt("Brand", "Travel", nil) :: number
		expect(math.abs(travel - params.Windup)).toBeLessThanOrEqual(1 / 60)
	end)

	it("flies the server's flight: from its spawn point, as far, as long", function()
		local carrier = brandCarrier()
		expect(carrier.Offset[3]).toBe(params.SpawnOffset)
		expect(carrier.Travel).toBe(params.Speed * params.Fuse)
		expect(carrier.For).toBe(params.Fuse)
		expect(carrier.Ease).toBe("Sine")
		expect(carrier.EaseDirection).toBe("In")
	end)

	it("stays inside the blast of the real one the whole way, and is never ahead of it", function()
		-- Roblox's Sine In, the ease the carrier declares, against the server's constant speed from its
		-- spawn point at the thrower's height. The gap is three-dimensional: the drawn one is offset and
		-- arcs, the real one does neither.
		local carrier = brandCarrier()
		local share = carrier.EaseShare :: number
		local worst, ahead = 0, 0
		for step = 0, 200 do
			local t = step / 200
			local sine = 1 - math.cos(t * math.pi / 2)
			local progress = (1 - share) * t + share * sine
			local drawn = carrier.Offset[3] + carrier.Travel * progress
			local real = params.SpawnOffset + params.Speed * params.Fuse * t
			local up = (carrier.Arc or 0) * math.sin(progress * math.pi) + carrier.Offset[2]
			local gap = math.sqrt((real - drawn) ^ 2 + up ^ 2 + carrier.Offset[1] ^ 2)
			worst = math.max(worst, gap)
			ahead = math.max(ahead, drawn - real)
		end
		expect(worst).toBeLessThanOrEqual(params.BlastRadius / 2)
		expect(ahead).toBeLessThanOrEqual(0.5)
	end)

	it("is drawn by the runtime the way the gate above computes it", function()
		-- The carrier is timed on its own Seconds, not on its life, which a thrown one extends by a grace.
		local carrier = functionIn(TIMELINE, "local function stepCarrier(")
		expect(
			has(
				carrier,
				"local flight = if entry.Seconds > 0 then math.clamp((now - entry.StartedAt) / entry.Seconds, 0, 1) else 1 local share = layer.EaseShare or 1 local progress = (1 - share) * flight + share * eased(layer, flight)"
			)
		).toBe(true)
		expect(has(carrier, "local here = flightPoint(entry, progress)")).toBe(true)
		expect(has(functionIn(TIMELINE, "local function stepLive("), "stepCarrier(entry, now)")).toBe(true)
		local point = functionIn(TIMELINE, "local function flightPoint(")
		expect(has(point, "local distance = (layer.Travel or 0) * scale * progress")).toBe(true)
		expect(has(point, "local rise = (layer.Arc or 0) * scale * math.sin(math.clamp(progress, 0, 1) * math.pi)")).toBe(
			true
		)
	end)
end)

describe("the server's Brand", function()
	it("is numbered, thrown reliably, waits for the hand, and fizzles when it cannot land", function()
		local throw = functionIn(EFFECTS, "function GlyphEffects.Brand(")
		expect(has(throw, "local shot = nextShot()")).toBe(true)
		expect(has(throw, "local start = ctx.Origin.Position + direction * params.SpawnOffset")).toBe(true)
		expect(has(throw, "Shot = shot, }, }, true)")).toBe(true)
		local wait = throw:find("task.wait(params.Windup)", 1, true)
		local check = throw:find(
			"if casterAlive(ctx) then stop, last = stepProjectile(ctx, start, direction * params.Speed, 0, fuse, ctx.Def.Range, 0)",
			1,
			true
		)
		expect(wait).never.toBe(nil)
		expect(check).never.toBe(nil)
		expect((check :: number) > (wait :: number)).toBe(true)
		expect(
			has(
				throw,
				'if stop == nil then ctx.Vfx.emit( { Id = "Fizzle", Origin = last, Caster = ctx.Caster.UserId, Params = { Shot = shot } }, true, ctx.Origin.Position ) return 0 end'
			)
		).toBe(true)
		expect(has(throw, "return explode(ctx, stop.Point, params.BlastRadius, BRAND_PUSH, BRAND_LIFT, shot)")).toBe(
			true
		)
	end)

	it("bursts reliably, naming the thrower and the shot, to everyone who saw it thrown", function()
		local burst = functionIn(EFFECTS, "local function explode(")
		expect(
			has(
				burst,
				"Caster = ctx.Caster.UserId, Params = { Radius = radius, Pigment = ctx.Def.Pigment, Shot = shot }, }, true, if shot ~= nil then ctx.Origin.Position else nil)"
			)
		).toBe(true)
		local broadcast = functionIn("src/server/Services/VfxBroadcaster.luau", "function VfxBroadcaster.emit(")
		expect(
			has(
				broadcast,
				"local near = shouldReceive(recipient.Position, packet.Origin) or (alsoNear ~= nil and shouldReceive(recipient.Position, alsoNear)) if near then"
			)
		).toBe(true)
		-- Where the projectile last was, even when the cast stopped qualifying: that is where it fizzles.
		local step = functionIn(EFFECTS, "local function stepProjectile(")
		expect(has(step, "): (ProjectileStop?, Vector3)")).toBe(true)
		expect(has(step, "if not casterAlive(ctx) then return nil, position end")).toBe(true)
		expect(VfxConfig.IdSet.Fizzle).toBe(true)
	end)
end)

describe("a landing", function()
	it("is keyed by the thrower and the shot, and asked for by the burst and the fizzle", function()
		local library = strip(fs.readFile(LIBRARY)):gsub("%s+", " ")
		expect(has(library, 'return string.format("%d:%d", caster, shot)')).toBe(true)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Brand = function("), "Shot = shotKey(packet),")).toBe(true)
		local explosion = functionIn(LIBRARY, "VfxLibrary.Explosion = function(")
		local landed = explosion:find("api.Timeline.land(shot, packet.Origin)", 1, true)
		local played = explosion:find('api.Timeline.play("Explosion"', 1, true)
		expect(landed).never.toBe(nil)
		expect((landed :: number) < (played :: number)).toBe(true)
		expect(has(functionIn(LIBRARY, "VfxLibrary.Fizzle = function("), "api.Timeline.land(shot, packet.Origin)")).toBe(
			true
		)
	end)

	it("drops what is still to fly, brings the carrier down, drains what rode it, and moves what lingers", function()
		local land = functionIn(TIMELINE, "function VfxTimeline.land(")
		expect(
			has(
				land,
				'if item.PlayId == playId and (item.Phase == "Travel" or (chain ~= nil and cut[chain])) then table.remove(pending, index)'
			)
		).toBe(true)
		expect(
			has(
				land,
				'item.Phase == "Residue" then local moved = table.clone(item.Context) moved.Origin = point item.Context = moved item.At = now + settings.Seconds + item.Layer.At'
			)
		).toBe(true)
		expect(has(land, "entry.Landing = { From = primary.CFrame, To = point, At = now }")).toBe(true)
		expect(
			has(
				land,
				'if primary:IsA("Trail") then primary.Enabled = false entry.EndsAt = now + primary.Lifetime elseif'
			)
		).toBe(true)
		expect(
			has(
				land,
				'primary:IsA("ParticleEmitter") then primary.Enabled = false entry.EndsAt = now + primary.Lifetime.Max'
			)
		).toBe(true)
		expect(has(land, "entry.Ending = { At = now, From = primary.Brightness }")).toBe(true)
		-- The carrier glides into the point, accelerating: never a snap, never linear.
		expect(
			has(
				functionIn(TIMELINE, "local function stepCarrier("),
				"part.CFrame = landing.From:Lerp(CFrame.new(landing.To) * landing.From.Rotation, t ^ 5)"
			)
		).toBe(true)
		-- A dimming light dims from the brightness it had, eased like every fade (rule 4).
		expect(
			has(
				functionIn(TIMELINE, "local function stepLight("),
				"local left = 1 - math.clamp((now - ending.At) / VfxTimelineConfig.Land.Fade, 0, 1) light.Brightness = ending.From * left * left"
			)
		).toBe(true)
	end)

	it(
		"ends every thrown flight: a burst that comes late still lands it, one that never comes lands it where it stopped",
		function()
			expect(VfxTimelineConfig.Land.Grace).toBeGreaterThanOrEqual(0.1)
			expect(VfxTimelineConfig.Land.Grace).toBeLessThanOrEqual(0.5)
			local activate = functionIn(TIMELINE, "local function activate(")
			expect(
				has(
					activate,
					'if context.Shot ~= nil and (layer.Kind == "Carrier" or layer.Ride == true) then lives += VfxTimelineConfig.Land.Grace end'
				)
			).toBe(true)
			-- What lingers waits for the landing, which puts it where the flight came down.
			local timeline = strip(fs.readFile(TIMELINE)):gsub("%s+", " ")
			expect(
				has(
					timeline,
					'At = if context.Shot ~= nil and name == "Residue" then math.huge else now + phaseStart + layer.At * factor,'
				)
			).toBe(true)
			local settle = functionIn(TIMELINE, "local function settle(")
			expect(
				has(
					settle,
					"if entry.Landing == nil and shot ~= nil and shots[shot] == entry.PlayId then return VfxTimeline.land(shot, primary.Position) end"
				)
			).toBe(true)
			expect(
				has(
					functionIn(TIMELINE, "local function onHeartbeat("),
					"if now >= entry.EndsAt and not settle(entry, now) then"
				)
			).toBe(true)
		end
	)

	it("never sends a carrier back to the pool with its sound still playing", function()
		local settle = functionIn(TIMELINE, "local function settle(")
		expect(has(settle, 'if child:IsA("Sound") and child.IsPlaying and not child.Looped then')).toBe(true)
		expect(
			has(
				settle,
				"if tail <= 0 then return false end entry.EndsAt = now + math.min(tail, VfxTimelineConfig.MaxLayerSeconds) return true"
			)
		).toBe(true)
	end)

	it("forgets a shot once it has landed or flown out, and every one on a clear", function()
		local timeline = strip(fs.readFile(TIMELINE)):gsub("%s+", " ")
		expect(has(timeline, "if context.Shot ~= nil then shots[context.Shot] = playId end")).toBe(true)
		expect(has(functionIn(TIMELINE, "function VfxTimeline.land("), "shots[shot] = nil")).toBe(true)
		expect(
			has(
				functionIn(TIMELINE, "local function releaseLive("),
				"if shot ~= nil and shots[shot] == entry.PlayId then shots[shot] = nil end"
			)
		).toBe(true)
		expect(has(functionIn(TIMELINE, "function VfxTimeline.clear("), "table.clear(shots)")).toBe(true)
	end)
end)

describe("a carrier", function()
	it("turns along its own path", function()
		expect(has(functionIn(TIMELINE, "local function stepCarrier("), "then CFrame.lookAlong(here, ahead)")).toBe(
			true
		)
	end)

	it("spins by an angle, never by an increment", function()
		-- Added every frame to a frame rebuilt every frame, it was one sixtieth of the spin.
		local carrier = functionIn(TIMELINE, "local function stepCarrier(")
		expect(has(carrier, "CFrame.Angles(0, 0, spin * (now - entry.StartedAt))")).toBe(true)
		expect(has(carrier, "1 / 60")).toBe(false)
	end)
end)
