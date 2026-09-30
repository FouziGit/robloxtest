--!strict
-- What the loadout card says a glyph deals, run (tests/engine.luau): the real GlyphCard. The whole cast, every
-- tick of a zone, stroke of a rush and pass of a trail, and an ultimate's opening hit with its ticks -- the
-- Cartouche 48, where the card said 28, the seal alone, and the Hatching 25 where it said 5 (E19-S3).
local Engine = require("./engine")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Counted by hand from GlyphConfig and GAME_DESIGN §5, on purpose: a card that read its number from the same
-- helper as this test would agree with it whatever the helper said.
local WHOLE_CAST: { [string]: number } = {
	Cartouche = 28 + 4 * 5, -- its seal, then five ticks of 4 (D-140)
	Hatching = 5 * 5, -- five strokes, the finisher included
	Bleed = 8 * 3,
	Scorch = 10 * 3,
	Spiral = 6 * 4,
	Pounce = 5 * 3,
	Watermark = 6 * 4,
	Ligature = 6 * 2, -- five passes of its pools, two of them at most on one body
}

local localize = {
	t = function(key: string): string
		return key
	end,
}

-- The number a card built for `def` shows beside its hit mark.
local function shown(world: any, parent: any, def: GlyphConfig.GlyphDef): string
	local GlyphCard = world.require("src/ui/components/GlyphCard")
	local card = GlyphCard.new({
		Def = def,
		Localize = localize,
		Bindings = GlyphCard.bindings(nil, "Keyboard"),
		Device = "Keyboard",
		OnAction = function() end,
		OnRefused = function() end,
		Parent = parent,
	})
	local stats = card.Instance:FindFirstChild("Stats", true)
	assert(stats ~= nil, def.Id .. "'s card has no Stats row: this gate would check nothing")
	local hit = stats:FindFirstChild("Cross")
	assert(hit ~= nil, def.Id .. "'s card has no hit mark: this gate would check nothing")
	local value = hit:FindFirstChild("Value")
	assert(value ~= nil, def.Id .. "'s hit mark has no number: this gate would check nothing")
	local text = value.Text
	card:Destroy()
	return text
end

describe("a glyph card's damage, run", function()
	it("is the whole cast's for a glyph that strikes more than once, and the hit's for the rest", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.game))
		local multi = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			local params = def.Params :: any
			local expected = WHOLE_CAST[def.Id]
			if expected ~= nil then
				multi += 1
			else
				-- A glyph missing from the table above strikes once: one that ticks and was left out fails here.
				expect(params.Ticks).toBeNil()
				expect(params.TickDamage).toBeNil()
				expected = def.Damage
			end
			local text = shown(world, parent, def)
			if text ~= tostring(expected) then
				error(("%s's card shows %s; one cast deals %d"):format(def.Id, text, expected))
			end
			expect(GlyphConfig.castDamage(def)).toBe(expected)
		end
		expect(multi).toBe(8)
	end)

	it("counts the Cartouche's seal and ticks, never the seal alone", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.game))
		local cartouche = GlyphConfig.ById.Cartouche
		expect(shown(world, parent, cartouche)).toBe("48")
		expect(shown(world, parent, cartouche)).never.toBe(tostring(cartouche.Damage))
		expect(shown(world, parent, GlyphConfig.ById.Hatching)).toBe("25")
	end)
end)
