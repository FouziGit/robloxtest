--!strict
-- The old vocabulary was borrowed from an existing licence. It is gone (docs/ART_BIBLE.md), and this test
-- is what keeps it gone: a name that carries a moderation and DMCA risk comes back one identifier at a
-- time, in a hurry, in a file nobody re-reads, and by then it is in a shipped build and in a thousand
-- saved profiles.
--
-- Each word below is one this game has its own replacement for. Adding a word here is cheap. Removing one
-- means deciding to ship it, which is a decision for docs/DECISIONS.md, not for a commit message.
--
-- The docs are scanned too, and they are where the words actually came back: the design document still
-- listed the five ranks by their borrowed names, and the economy still priced an "aura Kage", long after
-- the code was clean. A player never reads the code.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOTS = { "src", "tests", "docs" }
-- The front door is a page a player reads before anything else.
local EXTRA_FILES = { "README.md" }

-- Lowercased; the scan lowercases the source, so each entry covers every capitalisation.
local BORROWED: { [string]: string } = {
	jutsu = "glyph",
	chakra = "ink",
	genin = "the Blank rank",
	chunin = "the Sketch rank",
	jonin = "the Script rank",
	anbu = "the Illumination rank",
	kage = "the Codex rank",
	hokage = "the Codex rank",
	raijin = "Colophon",
	shinobi = "scribe",
	konoha = "no equivalent: invent one",
	uchiha = "no equivalent: invent one",
	sharingan = "no equivalent: invent one",
	rasengan = "no equivalent: invent one",
	-- The ban list catches a borrowed NAME. It does not catch the same borrow translated, and that is how
	-- one came back: the Colophon's own tooltip called it "the thunder god's wrath" in both languages, in a
	-- player-facing string, for the whole of phases 1 to 4 -- while "raijin" three lines above was clean.
	-- A word list only ever catches the spelling somebody used last time.
	["thunder god"] = "Colophon",
	["dieu du tonnerre"] = "Colophon",
	-- The currency. It went through the whole of phases 1 to 9 unnoticed, in every reward toast, because a
	-- ban list only holds the words somebody thought of: the lexicon of docs/ART_BIBLE.md replaced fifteen
	-- borrowed terms and never had a row for money. A folio is a leaf of a manuscript, so in Vellum the
	-- page is the coin.
	ryo = "folio",
}

-- Where an old spelling is data rather than a name, and must survive untouched.
--
-- The four modules are the migration and its tests: every old string in them is a key a saved profile
-- still holds, so renaming them is what this test exists to prevent, not what it should demand.
--
-- The two literals are DataStore names. A DataStore is addressed by its name: change the string and the
-- engine returns a different, empty store, and every profile ever saved reads as a brand new player.
local EXEMPT_FILES: { [string]: boolean } = {
	["src/shared/Pure/LegacyNames.luau"] = true,
	["src/shared/Pure/DataMigration.luau"] = true,
	["tests/LegacyNames.spec.luau"] = true,
	["tests/DataMigration.spec.luau"] = true,
	["tests/Lexicon.spec.luau"] = true,
	-- The art bible is where the replacement was argued, so it prints the old lexicon beside the new one.
	["docs/ART_BIBLE.md"] = true,
	-- The V1 audit is a dated record of a codebase that used those names; rewriting it would be a lie.
	["docs/AUDIT.md"] = true,
	-- The decision log is where a name is argued about, so it quotes the ones that were refused.
	["docs/DECISIONS.md"] = true,
}

local EXEMPT_LITERALS: { string } = { '"JutsuBattlegrounds_v2"', '"JutsuGame_PlayerData_v1"' }

-- A borrowed word hides inside innocent ones: "kage" sits in Packages, linkage and breakage, and "genin"
-- sits in RegenInCombat. A plain substring search flags all three and the test gets deleted for crying
-- wolf. But the word also has to be found inside an identifier, because CastJutsu and trySpendChakra are
-- exactly what this catches, so a whole-word search is too weak.
--
-- The rule that separates them is capitalisation, which is what every naming convention in this codebase
-- already uses as a word break. A hit counts when the matched text starts a word: either it begins with a
-- capital (CastJutsu, RAIJIN_LINK, trySpendChakra) or the character before it is not a letter (a comment
-- saying "the jutsu lands", a quoted id). A lowercase run in the middle of a longer lowercase word is
-- somebody else's word.
local function startsWord(source: string, index: number): boolean
	if string.match(string.sub(source, index, index), "%u") ~= nil then
		return true
	end
	return index == 1 or string.match(string.sub(source, index - 1, index - 1), "%a") == nil
end

local function findsWord(source: string, word: string): boolean
	local lowered = string.lower(source)
	local from = 1
	while true do
		local start = string.find(lowered, word, from, true)
		if start == nil then
			return false
		end
		if startsWord(source, start) then
			return true
		end
		from = start + 1
	end
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			-- Vendored code is not ours to rename.
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") ~= nil or string.match(entry, "%.md$") ~= nil then
			table.insert(out, path)
		end
	end
end

describe("lexicon", function()
	it("never uses a borrowed name", function()
		local files: { string } = table.clone(EXTRA_FILES)
		for _, root in ipairs(ROOTS) do
			collect(root, files)
		end
		expect(#files).toBeGreaterThan(80)

		local offences: { string } = {}
		for _, path in ipairs(files) do
			if not EXEMPT_FILES[path] then
				local source = fs.readFile(path)
				for _, literal in ipairs(EXEMPT_LITERALS) do
					source = string.gsub(source, literal, " ")
				end
				for word, replacement in pairs(BORROWED) do
					if findsWord(source, word) then
						table.insert(offences, ("%s says %q; this game says %s"):format(path, word, replacement))
					end
				end
			end
		end
		table.sort(offences)
		if #offences > 0 then
			error(table.concat(offences, "\n"))
		end
	end)

	it("still holds the two DataStore names that may never be renamed", function()
		-- If either literal is ever reworded, the exemption above silently stops matching and this test
		-- starts passing for the wrong reason. Assert they are still there, spelled exactly so.
		local source = fs.readFile("src/server/Services/DataService.luau")
		for _, literal in ipairs(EXEMPT_LITERALS) do
			if string.find(source, literal, 1, true) == nil then
				error(("DataService no longer contains %s; a DataStore name cannot be changed"):format(literal))
			end
		end
	end)

	it("keeps the art bible's before column spelled the old way", function()
		-- Twice now a sweep has rewritten an exempt file into nonsense: it turned this table's "Avant" column
		-- into "glyph -> Glyphe", which argues nothing, and it flattened LegacyNames into an identity map.
		-- An exemption is only safe while the file still contains what it was exempted for.
		local bible = fs.readFile("docs/ART_BIBLE.md")
		for _, word in ipairs({ "jutsu", "chakra", "Genin", "Kage" }) do
			if string.find(bible, word, 1, true) == nil then
				error(("docs/ART_BIBLE.md no longer names %q, so it no longer explains the rename"):format(word))
			end
		end
	end)

	it("keeps the migration maps keyed by the old names", function()
		-- The exemption above lets these four files hold old spellings. That is only safe while they
		-- actually still do: a sweep that "tidied" LegacyNames into an identity map would leave every
		-- other test green and quietly wipe the profiles it exists to save.
		local legacy = fs.readFile("src/shared/Pure/LegacyNames.luau")
		for _, pair in ipairs({ { "Fireball", "Brand" }, { "Raijin", "Colophon" }, { "Genin", "Blank" } }) do
			local old, fresh = pair[1], pair[2]
			local expected = ("%s = %q,"):format(old, fresh)
			if string.find(legacy, expected, 1, true) == nil then
				error(("LegacyNames no longer maps %s to %s"):format(old, fresh))
			end
		end
	end)
end)
