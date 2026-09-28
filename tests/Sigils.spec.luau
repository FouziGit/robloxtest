--!strict
-- The pigment sigils (PigmentConfig.Sigils) are written in the interface's face, and a shape that face lacks
-- is drawn from the engine's fallback fonts -- or as an empty box when none of them has it, which is what
-- the Orpiment chip showed with its four-pointed star (U+2726). Lune has no font engine, so the fonts were
-- read outside it and what they hold is written here.
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Codepoints present in both bundled faces of Arimo (content/fonts/Arimo-Regular.ttf and Arimo-Bold.ttf),
-- the first font the engine falls back to. tools/fonts/sigils.py established it on the Studio installed on
-- 2026-09-28: it read the fallback chain out of the Studio executable (Arimo, then the two emoji fonts, then
-- one Noto face per script) and each face's cmap. A codepoint here is drawn whatever face the interface is
-- set in. Rerun the script when Studio updates or a sigil changes, and paste the list it prints.
local PROVEN_LIST = {
	0x00BB, -- » RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
	0x03DF, -- ϟ GREEK SMALL LETTER KOPPA
	0x2021, -- ‡ DOUBLE DAGGER
	0x203B, -- ※ REFERENCE MARK
	0x2042, -- ⁂ ASTERISM
	0x2248, -- ≈ ALMOST EQUAL TO
	0x25A0, -- ■ BLACK SQUARE
	0x25B2, -- ▲ BLACK UP-POINTING TRIANGLE
	0x25CA, -- ◊ LOZENGE
	0x25CF, -- ● BLACK CIRCLE
	0x263C, -- ☼ WHITE SUN WITH RAYS
}

local PROVEN: { [number]: boolean } = {}
for _, code in ipairs(PROVEN_LIST) do
	PROVEN[code] = true
end

describe("the pigment sigils", function()
	it("are drawn with a glyph the engine ships, never an empty box", function()
		for _, pigment in ipairs(PigmentConfig.Order) do
			local sigil = PigmentConfig.Sigils[pigment]
			expect(sigil ~= nil and #sigil > 0).toBe(true)
			for _, code in utf8.codes(sigil) do
				if not PROVEN[code] then
					error(
						("%s's sigil %s holds U+%04X, which no bundled face of the fallback is proven to draw"):format(
							pigment,
							sigil,
							code
						)
					)
				end
			end
		end
	end)

	it("give each pigment its own shape", function()
		-- Colour is not the only cue: a player who cannot separate the five hues reads the shape.
		local seen: { [string]: string } = {}
		for _, pigment in ipairs(PigmentConfig.Order) do
			local sigil = PigmentConfig.Sigils[pigment]
			if seen[sigil] ~= nil then
				error(("%s and %s share the sigil %s"):format(seen[sigil], pigment, sigil))
			end
			seen[sigil] = pigment
		end
	end)
end)
