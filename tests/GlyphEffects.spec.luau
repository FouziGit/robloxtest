--!strict
-- The shared helpers of GlyphEffects the new roster leans on. The module touches Roblox, so its source is
-- read here, the way tests/HitFeel.spec.luau and tests/Flight.spec.luau read it.
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
