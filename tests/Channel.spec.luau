--!strict
-- The channel (D-142): a charged glyph or a rush holds its caster. Nothing else starts meanwhile -- no M1, no
-- other glyph -- and a dash is the one way out. Without it a caster could turn a charged line mid-charge with
-- the Caret, or stack M1 on top of a rush. Every hold is numbered and its effect asks about its own number
-- (ChannelHold, pure, held to its outcomes below); the services touch Roblox, so their sources are read here.
local ChannelHold = require("../src/shared/Pure/ChannelHold")
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local COMBAT = "src/server/Services/CombatService.luau"
local GLYPHS = "src/server/Services/GlyphService.luau"

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

local function before(text: string, first: string, second: string): boolean
	local a = text:find(first, 1, true)
	local b = text:find(second, 1, true)
	if a == nil or b == nil then
		error(("%q or %q is missing: this gate would check nothing"):format(first, second))
	end
	return a < b
end

describe("a channel", function()
	it("refuses every other glyph while it holds, before a drop of ink is spent", function()
		local cast = functionIn(GLYPHS, "local function onCastGlyph(")
		local refusal =
			"if combat.isStunned(player) or combat.isBlocking(player) or combat.isChanneling(player) then return end"
		expect(cast:find(refusal, 1, true)).never.toBe(nil)
		expect(before(cast, refusal, "combat.trySpendInk(player, def.Cost)")).toBe(true)
	end)

	it("refuses the M1 while it holds", function()
		expect(
			functionIn(COMBAT, "local function onMelee("):find(
				"if movement.isStunned(player) or state.Blocking or ChannelHold.refuses(state.Channel, now) then return end",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("is broken by a dash, and only by one the server granted", function()
		local dash = functionIn(COMBAT, "local function onDash(")
		expect(dash:find("ChannelHold.breaks(state.Channel)", 1, true)).never.toBe(nil)
		-- After the ink and the cooldown: a refused dash (on cooldown, too poor) leaves the charge alone.
		expect(before(dash, "CombatService.trySpendInk(player, cost)", "ChannelHold.breaks(state.Channel)")).toBe(true)
		expect(
			before(dash, "state.DashCooldownUntil = now + dash.CooldownSeconds", "ChannelHold.breaks(state.Channel)")
		).toBe(true)
	end)

	it("holds for a finite time the server set, and is read against the clock", function()
		local channel = functionIn(COMBAT, "function CombatService.channel(")
		expect(channel:find("if seconds ~= seconds or seconds < 0 or seconds == math.huge then", 1, true)).never.toBe(
			nil
		)
		expect(channel:find("return ChannelHold.open(state.Channel, os.clock(), seconds)", 1, true)).never.toBe(nil)
		expect(
			functionIn(COMBAT, "function CombatService.isChanneling("):find(
				"return state ~= nil and ChannelHold.refuses(state.Channel, os.clock())",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("answers an effect about its own hold, and lets it end only that one", function()
		local holds = functionIn(COMBAT, "function CombatService.holdsChannel(")
		expect(holds:find("return state ~= nil and token ~= nil and ChannelHold.owns(state.Channel, token)", 1, true)).never.toBe(
			nil
		)
		-- Never the gate: read against the clock, a late frame past the deadline would break a charge.
		expect(holds:find("refuses", 1, true)).toBe(nil)
		expect(holds:find("os.clock", 1, true)).toBe(nil)
		expect(
			functionIn(COMBAT, "function CombatService.endChannel("):find(
				"ChannelHold.close(state.Channel, token)",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("never outlives the character that started it", function()
		expect(functionIn(COMBAT, "local function resetState("):find("ChannelHold.breaks(state.Channel)", 1, true)).never.toBe(
			nil
		)
	end)
end)

describe("a numbered hold", function()
	it("refuses until its deadline, and lets go at it", function()
		local hold = ChannelHold.new()
		expect(ChannelHold.refuses(hold, 0)).toBe(false)
		local token = ChannelHold.open(hold, 10, 0.8)
		expect(ChannelHold.refuses(hold, 10.79)).toBe(true)
		expect(ChannelHold.refuses(hold, 10.8)).toBe(false)
		expect(ChannelHold.owns(hold, token)).toBe(true)
	end)

	it("is not the rush's own once a dash broke it and another glyph opened a hold", function()
		-- The Hatching at 0, a dash at 0.1, a Rubric's charge at 0.15: the rush's next stroke must not read the
		-- charge's hold as its own.
		local hold = ChannelHold.new()
		local rush = ChannelHold.open(hold, 0, 1.46)
		ChannelHold.breaks(hold)
		expect(ChannelHold.owns(hold, rush)).toBe(false)
		expect(ChannelHold.refuses(hold, 0.12)).toBe(false)
		local charge = ChannelHold.open(hold, 0.15, 0.8)
		expect(ChannelHold.refuses(hold, 0.34)).toBe(true)
		expect(ChannelHold.owns(hold, rush)).toBe(false)
		expect(ChannelHold.owns(hold, charge)).toBe(true)
	end)

	it("never ends a later cast's hold when an earlier effect finishes", function()
		local hold = ChannelHold.new()
		local rush = ChannelHold.open(hold, 0, 1.46)
		ChannelHold.breaks(hold)
		local charge = ChannelHold.open(hold, 1.05, 0.5)
		ChannelHold.close(hold, rush)
		expect(ChannelHold.owns(hold, charge)).toBe(true)
		expect(ChannelHold.refuses(hold, 1.3)).toBe(true)
		ChannelHold.close(hold, charge)
		expect(ChannelHold.owns(hold, charge)).toBe(false)
		expect(ChannelHold.refuses(hold, 1.3)).toBe(false)
	end)

	it("stays its effect's own past a late frame over its deadline", function()
		-- A server frame longer than the grace, straddling the end, is not a break: nothing broke it.
		local hold = ChannelHold.new()
		local charge = ChannelHold.open(hold, 0, 0.8)
		expect(ChannelHold.refuses(hold, 0.95)).toBe(false)
		expect(ChannelHold.owns(hold, charge)).toBe(true)
	end)

	it("is never a hold nobody opened", function()
		local hold = ChannelHold.new()
		expect(ChannelHold.owns(hold, 0)).toBe(false)
		ChannelHold.breaks(hold)
		expect(ChannelHold.owns(hold, 0)).toBe(false)
	end)
end)
