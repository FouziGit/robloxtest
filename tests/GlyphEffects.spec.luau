--!strict
-- The shared helpers of GlyphEffects the new roster leans on, and the rules the eight glyphs of the second
-- roster (D-145) keep on the server. The module touches Roblox, so its source is read here, the way
-- tests/HitFeel.spec.luau and tests/Flight.spec.luau read it; the numbers it reads come from the config.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local EFFECTS = "src/server/Effects/GlyphEffects.luau"

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

-- Whether `first` comes before `second` in `text`, both present: an order gate that found neither would pass.
local function before(text: string, first: string, second: string): boolean
	local a = text:find(first, 1, true)
	local b = text:find(second, 1, true)
	if a == nil or b == nil then
		error(("%q or %q is missing: this gate would check nothing"):format(first, second))
	end
	return a < b
end

local function count(text: string, needle: string): number
	local found, from = 0, 1
	while true do
		local start = text:find(needle, from, true)
		if start == nil then
			return found
		end
		found += 1
		from = start + #needle
	end
end

describe("a glyph's hit", function()
	it("deals what its tracker carries, and a tracker carries the glyph's damage unless told otherwise", function()
		expect(
			functionIn(EFFECTS, "local function damageModel("):find(
				'ctx.Combat.ApplyDamage(ctx.Caster, model, tracker.Amount, "Glyph", tracker.Tags, ctx.Def.Pigment)',
				1,
				true
			)
		).never.toBe(nil)
		expect(functionIn(EFFECTS, "local function newTracker("):find("Amount = def.Damage }", 1, true)).never.toBe(nil)
		-- Nothing reads the glyph's damage past the tracker: a site that did would ignore the tracker's amount.
		expect(count(strip(fs.readFile(EFFECTS)), "Def.Damage")).toBe(0)
	end)

	it("pushes away from a blast only what the blast hurt", function()
		local blast = functionIn(EFFECTS, "local function blast(")
		expect(blast:find("for _, model in ipairs(damageArea(ctx, tracker, point, radius)) do", 1, true)).never.toBe(
			nil
		)
		expect(
			blast:find("ctx.Combat.knockback(model, away * push + Vector3.yAxis * lift, KNOCKBACK_DURATION)", 1, true)
		).never.toBe(nil)
		expect(
			functionIn(EFFECTS, "local function explode("):find(
				"blast(ctx, tracker, point, radius, push, lift)",
				1,
				true
			)
		).never.toBe(nil)
	end)
end)

describe("a charged glyph", function()
	it("holds its caster for exactly the charge, and gives up the frame the hold breaks", function()
		local charge = functionIn(EFFECTS, "local function charge(")
		expect(charge:find("local token = ctx.Combat.channel(ctx.Caster, seconds + MAX_STEP_SECONDS)", 1, true)).never.toBe(
			nil
		)
		-- It asks about its own hold, never the gate (D-142): a dash then another glyph's hold is not its own, and
		-- a late frame past its deadline is no break.
		expect(
			charge:find(
				"if not casterAlive(ctx) or not ctx.Combat.holdsChannel(ctx.Caster, token) then ctx.Combat.endChannel(ctx.Caster, token) retract(ctx, vfxId) return nil end",
				1,
				true
			)
		).never.toBe(nil)
		expect(charge:find("isChanneling", 1, true)).toBe(nil)
		-- The telegraph says how long it lasts, and is reliable: the release packet must never overtake it.
		expect(charge:find("{ Windup = seconds, Pigment = ctx.Def.Pigment }", 1, true)).never.toBe(nil)
		expect(charge:find("Params = packetParams, }, true)", 1, true)).never.toBe(nil)
		-- It releases from where the server believes the caster stands now, and lets go of them either way.
		expect(
			before(
				charge,
				"local frame = ctx.Combat.trustedOrigin(ctx.Caster)",
				"ctx.Combat.endChannel(ctx.Caster, token) return frame"
			)
		).toBe(true)
		expect(
			functionIn(EFFECTS, "function GlyphEffects.Volute("):find(
				'charge(ctx, "VoluteCharge", params.Windup',
				1,
				true
			)
		).never.toBe(nil)
		local rubric = functionIn(EFFECTS, "function GlyphEffects.Rubric(")
		expect(rubric:find('charge(ctx, "RubricCharge", params.Windup', 1, true)).never.toBe(nil)
		-- Rooted by its own slow for the charge, and freed at once when the charge breaks.
		expect(before(rubric, "slowModel(ctx, character, params.ChargeSlowFactor, params.Windup)", "charge(ctx,")).toBe(
			true
		)
		expect(rubric:find("if frame == nil then ctx.Movement.clearSlow(ctx.Caster, ctx.Def.Id) return 0 end", 1, true)).never.toBe(
			nil
		)
		for _, id in ipairs({ "Volute", "Rubric" }) do
			expect(GlyphConfig.ById[id].Params.Windup).toBeGreaterThan(0)
		end
	end)
end)

describe("a play the server will not finish", function()
	it("is taken back on every path that gives up", function()
		-- A charge broken before its release, a rush a dash ended, a frame its caster stopped: left to play out,
		-- each drew a lane, strokes and shakes, or closing presses the server would never strike (D-141).
		local take = functionIn(EFFECTS, "local function retract(")
		expect(
			take:find(
				"ctx.Vfx.emit({ Id = vfxId, Origin = ctx.Origin.Position, Caster = ctx.Caster.UserId, Params = { Cancel = true }, }, true, alsoNear)",
				1,
				true
			)
		).never.toBe(nil)
		local rubric = functionIn(EFFECTS, "function GlyphEffects.Rubric(")
		expect(rubric:find('retract(ctx, "RubricCharge") return 0', 1, true)).never.toBe(nil)
		local hatching = functionIn(EFFECTS, "function GlyphEffects.Hatching(")
		expect(before(hatching, "local landed = 0", "for stroke = 1, params.Ticks do")).toBe(true)
		expect(
			before(hatching, "if landed < params.Ticks then retract(ctx, ctx.Def.VfxId) end", "ctx.Combat.endChannel(")
		).toBe(true)
		local cartouche = functionIn(EFFECTS, "function GlyphEffects.Cartouche(")
		expect(
			cartouche:find("if not casterAlive(ctx) then retract(ctx, ctx.Def.VfxId) return seal.Count end", 1, true)
		).never.toBe(nil)
		-- Its ticks run through the zone, which takes the frame back itself on the frame it stops: once, so the
		-- Cartouche asks nothing after it.
		expect(cartouche:find("tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval,", 1, true)).never.toBe(
			nil
		)
		expect(before(cartouche, "end, held)", "local struck = seal.Count")).toBe(true)
		expect(count(cartouche, "retract(")).toBe(1)
		-- The zone stops on that one question, and a stopped zone is taken back where it was drawn, before it stops.
		local zone = functionIn(EFFECTS, "local function tickZone(")
		expect(zone:find("if not casterAlive(ctx) then retract(ctx, ctx.Def.VfxId, center) break end", 1, true)).never.toBe(
			nil
		)
		expect(count(zone, "break")).toBe(1)
		expect(count(zone, "retract(")).toBe(1)
	end)
end)

describe("the Rubric", function()
	it("rules its line down the lane it painted, and loses a charge carried off it", function()
		local rubric = functionIn(EFFECTS, "function GlyphEffects.Rubric(")
		-- The lane is painted from the press point; the line leaves from there too, never from where the caster
		-- was pushed or slid to while the root held only his walk speed.
		expect(rubric:find("local muzzle = origin", 1, true)).never.toBe(nil)
		expect(rubric:find("local muzzle = frame.Position", 1, true)).toBe(nil)
		local lost =
			'local drift = frame.Position - origin if Vector3.new(drift.X, 0, drift.Z).Magnitude > params.ReleaseDriftStuds then retract(ctx, "RubricCharge") return 0 end'
		expect(rubric:find(lost, 1, true)).never.toBe(nil)
		-- Judged before anything is measured or struck from the release.
		expect(before(rubric, lost, "local start, clear = launchPoint(muzzle,")).toBe(true)
		expect(before(rubric, lost, "damageModel(ctx, tracker, model)")).toBe(true)
		expect((GlyphConfig.ById.Rubric.Params :: any).ReleaseDriftStuds).toBeGreaterThan(0)
	end)
end)

describe("the Hatching", function()
	it("holds its caster for the rush, and stops the stroke a dash broke it", function()
		local hatching = functionIn(EFFECTS, "function GlyphEffects.Hatching(")
		local held =
			"local token = ctx.Combat.channel(ctx.Caster, (params.Ticks - 1) * params.TickInterval + MAX_STEP_SECONDS)"
		expect(before(hatching, held, "for stroke = 1, params.Ticks do")).toBe(true)
		expect(hatching:find("if not ctx.Combat.holdsChannel(ctx.Caster, token) then break end", 1, true)).never.toBe(
			nil
		)
		expect(hatching:find("isChanneling", 1, true)).toBe(nil)
		expect(hatching:sub(-#"ctx.Combat.endChannel(ctx.Caster, token) return tracker.Count end " - 1)).toBe(
			" ctx.Combat.endChannel(ctx.Caster, token) return tracker.Count end "
		)
	end)

	it("strikes on a beat kept against its start, each stroke past the hit memory", function()
		local hatching = functionIn(EFFECTS, "function GlyphEffects.Hatching(")
		expect(
			hatching:find(
				"local due = math.max( started + (stroke - 1) * params.TickInterval, lastStrokeAt + CombatConfig.Hit.IFrameSeconds + EPSILON ) task.wait(math.max(due - os.clock(), 0))",
				1,
				true
			)
		).never.toBe(nil)
		-- A stroke that came late pushes only the next one, past the memory its hits wrote: the stamp is taken
		-- after them, at the end of the stroke.
		expect(hatching:find("local lastStrokeAt = -math.huge", 1, true)).never.toBe(nil)
		expect(
			hatching:find(
				"slowModel(ctx, model, params.SlowFactor, params.SlowDuration) end end lastStrokeAt = os.clock() landed += 1 end",
				1,
				true
			)
		).never.toBe(nil)
		-- The same glyph cannot hit the same body twice inside Hit.IFrameSeconds: a stroke closer than that, one
		-- frame of lateness at 30 Hz included, would be swallowed.
		expect(GlyphConfig.ById.Hatching.Params.TickInterval).toBeGreaterThan(CombatConfig.Hit.IFrameSeconds + 1 / 30)
		expect(hatching:find("local frame = ctx.Combat.trustedOrigin(ctx.Caster)", 1, true)).never.toBe(nil)
	end)

	it(
		"names its last stroke a finisher in its hit, for the impact frame five damage would not earn (E19-S3)",
		function()
			-- The client prints both bodies in ink on a heavy hit or on a finisher the server names (D-112): the last
			-- stroke is five damage, far under a heavy hit, and launched its body with no frame at all.
			local tag = CombatConfig.Hit.GlyphFinisherTag
			expect(type(tag)).toBe("string")
			expect(#tag).toBeGreaterThan(0)
			expect(tag).never.toBe("MeleeFinisher")
			expect(GlyphConfig.ById[tag]).toBeNil()
			expect((CombatConfig.Block.BrokenBy :: any)[tag]).toBeNil()
			expect(GlyphConfig.ById.Hatching.Damage).toBeLessThan(25)
			local hatching = functionIn(EFFECTS, "function GlyphEffects.Hatching(")
			local named =
				"local finisher = stroke == params.Ticks if finisher then table.insert(tracker.Tags, CombatConfig.Hit.GlyphFinisherTag) end"
			expect(hatching:find(named, 1, true)).never.toBe(nil)
			-- Before the stroke's hits, which carry it; after the glyph's own tags, so the hit memory keys on the glyph.
			expect(before(hatching, named, "for _, model in ipairs(damageBox(ctx, tracker,")).toBe(true)
			expect(count(hatching, "GlyphFinisherTag")).toBe(1)
			expect(functionIn(EFFECTS, "local function newTracker("):find("Tags = { def.Id, def.Archetype }", 1, true)).never.toBe(
				nil
			)
			-- And the hit it is dealt in says so.
			local apply = functionIn("src/server/Services/CombatService.luau", "function CombatService.ApplyDamage(")
			local says =
				'if kind == "Glyph" and table.find(tags, CombatConfig.Hit.GlyphFinisherTag) ~= nil then hitParams.Finisher = true end'
			expect(apply:find(says, 1, true)).never.toBe(nil)
			expect(before(apply, says, 'vfx.emit({ Id = "Hit",')).toBe(true)
		end
	)
end)

describe("the Cartouche", function()
	it("opens with a seal that breaks a guard, then ticks lighter under the glyph id alone", function()
		local tick = functionIn(EFFECTS, "local function tickTracker(")
		expect(tick:find("Tags = { def.Id }", 1, true)).never.toBe(nil)
		expect(tick:find("Amount = amount", 1, true)).never.toBe(nil)
		local zone = functionIn(EFFECTS, "local function tickZone(")
		expect(zone:find("local zone = if tracker ~= nil then tracker else newTracker(ctx.Def, math.huge)", 1, true)).never.toBe(
			nil
		)
		local cartouche = functionIn(EFFECTS, "function GlyphEffects.Cartouche(")
		expect(cartouche:find("local seal = newTracker(ctx.Def, 1)", 1, true)).never.toBe(nil)
		expect(cartouche:find("local held = tickTracker(ctx.Def, params.TickDamage)", 1, true)).never.toBe(nil)
		expect(cartouche:find("end, held)", 1, true)).never.toBe(nil)
		-- The first tick waits one interval past the seal: they share the glyph id, so the hit memory would
		-- swallow a tick that came sooner.
		expect(before(cartouche, "task.wait(params.TickInterval)", "tickZone(")).toBe(true)
		expect(GlyphConfig.ById.Cartouche.Params.TickInterval).toBeGreaterThan(CombatConfig.Hit.IFrameSeconds)
		-- Only the seal stuns; the ticks slow.
		expect(count(cartouche, "stunModel(ctx,")).toBe(1)
		expect(before(cartouche, "stunModel(ctx, model, params.StunSeconds)", "task.wait(params.TickInterval)")).toBe(
			true
		)
		expect(cartouche:find("Radius = params.Radius,", 1, true)).never.toBe(nil)
	end)
end)

describe("a thing released ahead of the body", function()
	it("starts at the first wall between the body and its release point (D-144)", function()
		local launch = functionIn(EFFECTS, "local function launchPoint(")
		expect(launch:find("local wall = geometryStop(from, direction, offset, character)", 1, true)).never.toBe(nil)
		expect(launch:find("return wall, (wall - from).Magnitude >= offset - EPSILON", 1, true)).never.toBe(nil)
		local rubric = functionIn(EFFECTS, "function GlyphEffects.Rubric(")
		expect(
			rubric:find("local start, clear = launchPoint(muzzle, direction, params.SpawnOffset, character)", 1, true)
		).never.toBe(nil)
		expect(
			rubric:find(
				"if clear then candidates, stop = hitscan(ctx, start, direction, ctx.Def.Range, params.HitRadius) end",
				1,
				true
			)
		).never.toBe(nil)
		local swash = functionIn(EFFECTS, "function GlyphEffects.Swash(")
		expect(
			swash:find("local start, clear = launchPoint(origin, direction, params.SpawnOffset, character)", 1, true)
		).never.toBe(nil)
		expect(
			swash:find(
				"local stop = if clear then geometryStop(start, direction, ctx.Def.Range - params.SpawnOffset, character) else start",
				1,
				true
			)
		).never.toBe(nil)
		local stitch = functionIn(EFFECTS, "function GlyphEffects.Stitch(")
		expect(
			stitch:find("local start, clear = launchPoint(origin, direction, params.SpawnOffset, character)", 1, true)
		).never.toBe(nil)
		expect(stitch:find("if clear then stop, last = stepProjectile(ctx, start,", 1, true)).never.toBe(nil)
	end)

	it("spares a body behind a wall beside the line its box is swept along", function()
		-- Only the centre line is stopped by a wall, and only by one it crosses: the Swash's box is 12 wide and the
		-- Rubric's 8, and a box query sees through walls. Behind a cover wall parallel to the line, or on the near
		-- side of a Margin at 45 degrees (the box ran up to six studs past it), a body was cut or pierced.
		local open = functionIn(EFFECTS, "local function inOpenFrom(")
		expect(
			open:find(
				"local along = math.clamp((model:GetPivot().Position - start):Dot(direction), 0, span) return inSight(start + direction * along, model, character)",
				1,
				true
			)
		).never.toBe(nil)
		expect(
			functionIn(EFFECTS, "local function damageBox("):find(
				"if (keep == nil or keep(model)) and damageModel(ctx, tracker, model) then",
				1,
				true
			)
		).never.toBe(nil)
		local swash = functionIn(EFFECTS, "function GlyphEffects.Swash(")
		expect(
			swash:find(
				"local function open(model: Model): boolean return inOpenFrom(start, direction, span, model, character) end",
				1,
				true
			)
		).never.toBe(nil)
		expect(swash:find("damageBox(ctx, tracker, box, size, open)", 1, true)).never.toBe(nil)
		local rubric = functionIn(EFFECTS, "function GlyphEffects.Rubric(")
		expect(
			rubric:find(
				"if inOpenFrom(start, direction, length, model, character) and damageModel(ctx, tracker, model) then",
				1,
				true
			)
		).never.toBe(nil)
		expect(rubric:find("local length = (stop - start).Magnitude", 1, true)).never.toBe(nil)
	end)

	it("catches in flight only a body no wall hides from it", function()
		-- The last clear step lies within one step of a wall's face, and a body hugging the far side of a cover
		-- wall (2 thick) or a Margin (2.5) was inside the Stitch's HitRadius of it: caught, dragged into the wall
		-- and rooted, through the one answer the Stitch has. The Hairline and the Stipple fly the same way.
		local step = functionIn(EFFECTS, "local function stepProjectile(")
		expect(
			step:find(
				"local nearby = humanoidsInRadius(position, hitRadius, character) for _, model in ipairs(nearestModels(nearby, position, #nearby)) do if inSight(position, model, character) then return { Point = position, Model = model }, position end end",
				1,
				true
			)
		).never.toBe(nil)
		expect(step:find("nearestModel(", 1, true)).toBe(nil)
		local sight = functionIn(EFFECTS, "local function inSight(")
		expect(sight:find("local line = model:GetPivot().Position - from", 1, true)).never.toBe(nil)
		expect(
			sight:find(
				"return (geometryStop(from, line / distance, distance, character) - from).Magnitude >= distance - EPSILON",
				1,
				true
			)
		).never.toBe(nil)
		-- The Dagger asks the same question of the body it would jump behind.
		expect(
			functionIn(EFFECTS, "function GlyphEffects.Dagger("):find("and inSight(start, model, character)", 1, true)
		).never.toBe(nil)
	end)

	it("lands the Swash on the frame its front meets the wall, not a step past it", function()
		-- Stepped by whole 0.05 s steps, the front's landing left up to a step late -- five studs at its speed --
		-- after the drawn front had already gouged the page past the wall (VfxTimeline.land keeps a gouge drawn).
		local swash = functionIn(EFFECTS, "function GlyphEffects.Swash(")
		expect(
			swash:find("elapsed += task.wait(math.min(WAVE_STEP_SECONDS, (span - reached) / params.Speed))", 1, true)
		).never.toBe(nil)
		expect(swash:find("if reached >= span - EPSILON then break end", 1, true)).never.toBe(nil)
		expect(swash:find("task.wait(WAVE_STEP_SECONDS)", 1, true)).toBe(nil)
	end)

	it("comes down on every client where the server's one ended", function()
		for _, id in ipairs({ "Swash", "Stitch" }) do
			local effect = functionIn(EFFECTS, "function GlyphEffects." .. id .. "(")
			expect(effect:find("local shot = nextShot()", 1, true)).never.toBe(nil)
			expect(effect:find('Id = "Fizzle",', 1, true)).never.toBe(nil)
			expect(
				effect:find("Params = { Shot = shot } }", 1, true) or effect:find("Params = { Shot = shot },", 1, true)
			).never.toBe(nil)
		end
		local stitch = functionIn(EFFECTS, "function GlyphEffects.Stitch(")
		expect(before(stitch, 'Id = "StitchCatch",', "Shot = shot, }, }, true, origin)")).toBe(true)
		expect(stitch:find("Victim = target,", 1, true)).never.toBe(nil)
	end)
end)

describe("the Dagger", function()
	it("jumps only to a body it may strike, and strikes it after the jump", function()
		local dagger = functionIn(EFFECTS, "function GlyphEffects.Dagger(")
		expect(before(dagger, "ctx.Combat.canDamage(ctx.Caster, model)", "character:PivotTo(")).toBe(true)
		expect(before(dagger, "character:PivotTo(", "ctx.Combat.resyncPosition(ctx.Caster, landing)")).toBe(true)
		expect(before(dagger, "ctx.Combat.resyncPosition(ctx.Caster, landing)", "damageModel(ctx, tracker, model)")).toBe(
			true
		)
		-- From the validated origin, and landing where the Caret would: on ground, in the clear.
		expect(dagger:find("local start = ctx.Origin.Position", 1, true)).never.toBe(nil)
		expect(
			dagger:find(
				"landingPosition(position + toward * reach, params.ClearanceRadius, params.GroundSnapStuds, character)",
				1,
				true
			)
		).never.toBe(nil)
		expect(dagger:find("excludeParams(character, model)", 1, true)).never.toBe(nil)
	end)

	it("draws its flight where it flew, climb included", function()
		-- The landing snaps to the ground behind the body, up to GroundSnapStuds below it: to a ledge eight studs
		-- up and twelve across, the packet said a flat aim and the 3D length, and the strike was drawn 2.4 studs
		-- past the landing and eight below it. The renderer lays every layer along the packet's Direction for
		-- Range (VfxLibrary.Dagger, directionOf, never flattened).
		local dagger = functionIn(EFFECTS, "function GlyphEffects.Dagger(")
		expect(dagger:find("local flight = landing - start", 1, true)).never.toBe(nil)
		expect(dagger:find("Direction = if flight.Magnitude > EPSILON then flight.Unit else aim,", 1, true)).never.toBe(
			nil
		)
		expect(dagger:find("Range = flight.Magnitude,", 1, true)).never.toBe(nil)
		expect(dagger:find("horizontal(flight)", 1, true)).toBe(nil)
		local renderer = functionIn("src/client/Controllers/VfxLibrary.luau", "VfxLibrary.Dagger = function(")
		expect(renderer:find("Direction = directionOf(packet),", 1, true)).never.toBe(nil)
		expect(renderer:find("flatDirectionOf", 1, true)).toBe(nil)
	end)
end)

describe("the second roster's hits", function()
	it("send the radius the server struck with", function()
		expect(functionIn(EFFECTS, "function GlyphEffects.Volute("):find("Radius = params.HitRadius,", 1, true)).never.toBe(
			nil
		)
		expect(functionIn(EFFECTS, "function GlyphEffects.Emboss("):find("Radius = params.Radius,", 1, true)).never.toBe(
			nil
		)
		expect(
			functionIn(EFFECTS, "function GlyphEffects.Emboss("):find(
				"blast(ctx, tracker, origin, params.Radius, params.Push, params.Lift)",
				1,
				true
			)
		).never.toBe(nil)
	end)
end)
