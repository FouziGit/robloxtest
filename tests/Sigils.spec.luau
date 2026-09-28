--!strict
-- The pigment sigils (PigmentConfig.Sigils) are written in the interface's face, and a shape that face lacks
-- is drawn from the engine's fallback fonts -- or as an empty box when none of them has it, which is what
-- the Orpiment chip showed with its four-pointed star (U+2726). Lune has no font engine, so the fonts were
-- read outside it and what they hold is written here.
local Harness = require("./harness")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Codepoints present in both bundled faces of Arimo (content/fonts/Arimo-Regular.ttf and Arimo-Bold.ttf),
-- the first font the engine falls back to. tools/fonts/sigils.py established it on the Studio installed on
-- 2026-09-28: it read the fallback chain out of the Studio executable (Arimo, then the two emoji fonts, then
-- one Noto face per script) and each face's cmap. A codepoint here is drawn whatever face the interface is
-- set in. Rerun the script when Studio updates, when a sigil changes or when a string needs a character
-- neither here nor in the ranges below, and paste the list and the ranges it prints.
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

-- Whole blocks the same script found in both faces, every assigned codepoint of each: the accents and
-- ligatures of the French strings, and the dashes, ellipsis and quotes of both locales.
local PROVEN_RANGES = {
	{ 0x00A0, 0x017F }, -- Latin-1 Supplement and Latin Extended-A
	{ 0x2010, 0x205E }, -- General Punctuation
}

local PROVEN: { [number]: boolean } = {}
for _, code in ipairs(PROVEN_LIST) do
	PROVEN[code] = true
end

local function drawn(code: number): boolean
	if code <= 0x7F or PROVEN[code] then
		return true
	end
	for _, range in ipairs(PROVEN_RANGES) do
		if code >= range[1] and code <= range[2] then
			return true
		end
	end
	return false
end

-- Every character past ASCII the code writes, with the first file that writes it. An identifier is ASCII, so
-- once the comments are out what is left of it is the contents of strings.
local function written(directory: string, out: { [number]: string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				written(path, out)
			end
		elseif entry:match("%.luau$") ~= nil then
			local code = (fs.readFile(path):gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", ""))
			for _, point in utf8.codes(code) do
				if point > 0x7F and out[point] == nil then
					out[point] = path
				end
			end
		end
	end
end

describe("the pigment sigils", function()
	it("are drawn with a glyph the engine ships, never an empty box", function()
		for _, pigment in ipairs(PigmentConfig.Order) do
			local sigil = PigmentConfig.Sigils[pigment]
			expect(sigil ~= nil and #sigil > 0).toBe(true)
			for _, code in utf8.codes(sigil) do
				if not drawn(code) then
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

describe("the interface's text", function()
	it("writes no character the engine draws as an empty box", function()
		-- The same box, anywhere else on the page: the panels' close cross and the roster's dead mark were
		-- U+2715, which no face of the fallback has either. Every string in src is held to the proven set,
		-- the French ones included, whichever face its label is set in.
		local found: { [number]: string } = {}
		written("src", found)
		local count = 0
		for point, path in pairs(found) do
			count += 1
			if not drawn(point) then
				error(("%s writes U+%04X, which no bundled face of the fallback is proven to draw"):format(path, point))
			end
		end
		-- The French strings alone hold accents, so a scan that read nothing fails here.
		expect(count > 0).toBe(true)
	end)
end)
