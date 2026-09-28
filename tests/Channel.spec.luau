--!strict
-- The channel (D-136): a charged glyph or a rush holds its caster. Nothing else starts meanwhile -- no M1, no
-- other glyph -- and a dash is the one way out. Without it a caster could turn a charged line mid-charge with
-- the Caret, or stack M1 on top of a rush. The services touch Roblox, so their sources are read here.
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
				"if movement.isStunned(player) or state.Blocking or now < state.ChannelUntil then return end",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("is broken by a dash, and only by one the server granted", function()
		local dash = functionIn(COMBAT, "local function onDash(")
		expect(dash:find("state.ChannelUntil = 0", 1, true)).never.toBe(nil)
		-- After the ink and the cooldown: a refused dash (on cooldown, too poor) leaves the charge alone.
		expect(before(dash, "CombatService.trySpendInk(player, cost)", "state.ChannelUntil = 0")).toBe(true)
		expect(before(dash, "state.DashCooldownUntil = now + dash.CooldownSeconds", "state.ChannelUntil = 0")).toBe(
			true
		)
	end)

	it("holds for a finite time the server set, and is read against the clock", function()
		local channel = functionIn(COMBAT, "function CombatService.channel(")
		expect(channel:find("if seconds ~= seconds or seconds < 0 or seconds == math.huge then", 1, true)).never.toBe(
			nil
		)
		expect(channel:find("state.ChannelUntil = os.clock() + seconds", 1, true)).never.toBe(nil)
		expect(
			functionIn(COMBAT, "function CombatService.isChanneling("):find(
				"return state ~= nil and os.clock() < state.ChannelUntil",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("never outlives the character that started it", function()
		expect(functionIn(COMBAT, "local function resetState("):find("state.ChannelUntil = 0", 1, true)).never.toBe(nil)
	end)
end)
