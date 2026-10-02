--!strict
-- The zones that tick (Bleed, Scorch, Spiral, Pounce, Watermark): each stops drawing the frame its caster stops
-- it, and each is drawn on the server's clock, never held by the hits it lands (E19-S1). Their caster
-- stops them by dying, leaving, raising guard or being stunned; the server then strikes no more ticks and takes
-- the play back on every screen (GlyphEffects' retract, D-141), and the renderer cuts it. Left to play out, a
-- zone burned, pulled, slowed or pressed a floor that no longer hurt, for up to two seconds.
--
-- GlyphEffects and VfxLibrary touch Roblox, so their sources are read here, the way tests/GlyphEffects.spec.luau
-- and tests/VfxStyle.spec.luau read them; the numbers come from the config.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local EFFECTS = "src/server/Effects/GlyphEffects.luau"
local LIBRARY = "src/client/Controllers/VfxLibrary.luau"
local TIMELINES = VfxTimelineConfig.Timelines

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

local function has(text: string, needle: string, what: string)
	if text:find(needle, 1, true) == nil then
		error(("%s: %s is missing"):format(what, needle))
	end
end

-- What every ticking zone owes, whichever way it ticks: its play under its own id, reliable so the retraction
-- never overtakes it; a renderer under that id that keeps the play and cuts it on a retraction; a timeline on
-- the server's clock; and one play at a time per caster, which is what lets the renderer keep one per caster.
local function common(id: string)
	local def = GlyphConfig.ById[id]
	expect(def).never.toBeNil()
	local params = def.Params :: any
	expect(def.VfxId).toBe(id)
	expect(table.find(VfxConfig.GlyphIds, id)).never.toBeNil()
	expect(params.Ticks).toBeGreaterThan(1)
	expect(params.TickInterval).toBeGreaterThan(0)
	-- Recast only once the last one has stopped ticking: a caster never has two of it running, so the renderer's
	-- one play per caster is always the one the server takes back.
	expect(def.Cooldown).toBeGreaterThan((params.Ticks - 1) * params.TickInterval)
	local effect = functionIn(EFFECTS, ("function GlyphEffects.%s("):format(id))
	has(effect, "ctx.Vfx.emit({ Id = ctx.Def.VfxId,", id)
	has(effect, "Pigment = ctx.Def.Pigment, }, }, true)", id)
	expect(VfxTimelineConfig.steady(TIMELINES[id])).toBe(true)
	expect(TIMELINES[id].Steady).toBe(true)
end

-- A zone laid ahead of its caster ticks through tickZone, which takes it back where it was drawn.
local function laidAhead(id: string)
	common(id)
	local effect = functionIn(EFFECTS, ("function GlyphEffects.%s("):format(id))
	has(effect, "local center = ctx.Origin.Position + ctx.Direction * params.Offset", id)
	has(effect, "ctx.Vfx.emit({ Id = ctx.Def.VfxId, Origin = center,", id)
	has(
		effect,
		"return tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval, function(model: Model)",
		id
	)
	-- Nothing of its own stops it early: the one stop is tickZone's, which retracts.
	expect(effect:find("break", 1, true)).toBe(nil)
	local renderer = functionIn(LIBRARY, ("VfxLibrary.%s = function("):format(id))
	has(
		renderer,
		('if not retracted("%s", packet, api) then remember("%s", packet, playGlyph("%s", packet, api)) end'):format(
			id,
			id,
			id
		),
		id
	)
end

describe("a ticking zone", function()
	it("is taken back by tickZone on the frame its caster stops it, where it was drawn, and only then", function()
		local zone = functionIn(EFFECTS, "local function tickZone(")
		local stop = "if not casterAlive(ctx) then retract(ctx, ctx.Def.VfxId, center) break end"
		has(zone, stop, "tickZone")
		-- Asked after each wait, before the tick it would strike: a stopped caster's zone strikes nothing more.
		expect(before(zone, "task.wait(interval)", stop)).toBe(true)
		expect(before(zone, stop, "damageArea(ctx, zone, center, radius)")).toBe(true)
		-- Played to its end, it is never taken back.
		local _, retracts = zone:gsub("retract%(", "")
		expect(retracts).toBe(1)
		-- The retraction reaches whoever the play reached: the play went out from the zone, laid ahead of the
		-- caster, and the retraction from the cast; it goes to both.
		local take = functionIn(EFFECTS, "local function retract(")
		has(take, "local function retract(ctx: Context, vfxId: string, alsoNear: Vector3?)", "retract")
		has(take, "Params = { Cancel = true }, }, true, alsoNear)", "retract")
		-- Defined before the zone that calls it.
		local source = strip(fs.readFile(EFFECTS))
		expect(before(source, "local function retract(", "local function tickZone(")).toBe(true)
	end)

	it("cuts its play on every screen when the server takes it back", function()
		local cut = functionIn(LIBRARY, "local function retracted(")
		has(cut, "if params == nil or params.Cancel ~= true then return false end", "retracted")
		has(cut, "if playId ~= nil then api.Timeline.cancel(playId) end return true", "retracted")
		has(functionIn(LIBRARY, "local function remember("), "plays[id] = playId", "remember")
	end)
end)

describe("the Bleed", function()
	it("stops drawing when its caster stops it, on the server's clock", function()
		common("Bleed")
		local effect = functionIn(EFFECTS, "function GlyphEffects.Bleed(")
		has(effect, "ctx.Vfx.emit({ Id = ctx.Def.VfxId, Origin = center,", "Bleed")
		has(
			effect,
			"return tickZone(ctx, center, params.Radius, params.Ticks, params.TickInterval, function(model: Model)",
			"Bleed"
		)
		expect(effect:find("break", 1, true)).toBe(nil)
		-- Its renderer plays its own measure (the radius it drinks from), and keeps that play to cut it.
		local renderer = functionIn(LIBRARY, "VfxLibrary.Bleed = function(")
		has(renderer, 'if retracted("Bleed", packet, api) then return end', "Bleed")
		has(renderer, 'local _, playId = api.Timeline.play("Bleed", {', "Bleed")
		has(renderer, 'remember("Bleed", packet, playId)', "Bleed")
		expect(before(renderer, 'retracted("Bleed"', 'api.Timeline.play("Bleed"')).toBe(true)
	end)
end)

describe("the Scorch", function()
	it("stops drawing its ring when its caster stops it, on the server's clock", function()
		common("Scorch")
		local effect = functionIn(EFFECTS, "function GlyphEffects.Scorch(")
		-- Its ring follows the caster, so it is drawn and taken back from the cast.
		has(effect, "ctx.Vfx.emit({ Id = ctx.Def.VfxId, Origin = ctx.Origin.Position,", "Scorch")
		-- Every tick it strikes is counted, and one it did not strike takes the ring back.
		has(effect, "local burned = 0 for tick = 1, params.Ticks do", "Scorch")
		has(effect, "if centre == nil or not casterAlive(ctx) then break end", "Scorch")
		has(effect, "damageArea(ctx, tracker, centre.Position, params.Radius) burned += 1 end", "Scorch")
		has(effect, "if burned < params.Ticks then retract(ctx, ctx.Def.VfxId) end return tracker.Count end", "Scorch")
		local _, retracts = effect:gsub("retract%(", "")
		expect(retracts).toBe(1)
		local renderer = functionIn(LIBRARY, "VfxLibrary.Scorch = function(")
		has(
			renderer,
			'if not retracted("Scorch", packet, api) then remember("Scorch", packet, playGlyph("Scorch", packet, api)) end',
			"Scorch"
		)
	end)
end)

describe("the Spiral", function()
	it("stops drawing when its caster stops it, on the server's clock", function()
		laidAhead("Spiral")
	end)
end)

describe("the Pounce", function()
	it("stops drawing when its caster stops it, on the server's clock", function()
		laidAhead("Pounce")
	end)
end)

describe("the Watermark", function()
	it("stops drawing when its caster stops it, on the server's clock", function()
		laidAhead("Watermark")
	end)
end)

describe("a glyph that strikes on the server's ticks", function()
	it("is drawn on the server's clock, never held by the hits it lands", function()
		-- An impact holds the effect clock (D-118); a glyph whose ticks, strokes or presses the server counts would
		-- be drawn later than it hurts after every hit it landed. D-141 left the zones, the Cartouche and the
		-- Hatching on the held clock, to be decided together: all of them now run on the steady one.
		local ticking = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			local params = def.Params :: any
			if params.Ticks ~= nil and params.TickInterval ~= nil then
				ticking += 1
				if not VfxTimelineConfig.steady(TIMELINES[def.VfxId]) then
					error(("%s strikes on the server's ticks and is drawn on the held clock"):format(def.Id))
				end
			end
		end
		expect(ticking).toBeGreaterThanOrEqual(8)
	end)
end)
