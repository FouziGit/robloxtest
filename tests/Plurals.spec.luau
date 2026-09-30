--!strict
-- A sentence that counts something takes the form its count calls for, in each language (E12-S3).
--
-- Seen in Studio on the Quests screen: the one daily quest of one read "Win 1 matches", "Gagne 1 matchs". The
-- fix there gave that quest its own words, and every other count in the table could still say it the same way:
-- "+1 Folios" on a balance left at one, "1 Forgers standing" on the Battleground's band, "+1 battle pass tiers"
-- on a pass bought one tier at a time. Strings.plural chooses between a sentence's two forms, and the gate below
-- refuses a sentence that writes a count straight into a plural noun ("{n} <word>s") outside those forms.
local Engine = require("./engine")
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- The placeholders that never count things, and why. A new placeholder is a count until it is listed here, so
-- the gate reads it: failing closed is the point of a gate.
local NOT_COUNTS: { [string]: string } = {
	a = "a key's name (settings.swapped)",
	b = "a key's name (settings.swapped)",
	action = "an action's name",
	board = "a leaderboard's name",
	grade = "a grade's name",
	key = "a key's name",
	mode = "a mode's name",
	name = "a name",
	pigment = "a pigment's name",
	place = "a place's name",
	rank = "a rank's name",
	reward = "a reward already written out",
	time = "a duration already written out",
	waited = "a duration already written out",
	tier = "a tier's number, not a count of tiers",
	level = "a level's number",
	day = "a day's number in a streak",
	season = "a season's number",
	phase = "a phase's number",
	round = "a round's number",
	progress = "the first half of a fraction",
	value = "a percentage",
	rating = "a rating",
	delta = "a rating's move",
}

-- Letters as the table writes them: ASCII, the bytes of an accented letter, an apostrophe or a hyphen.
local WORD = "[%w\128-\255'%-]+"

-- Every key that is one of the two forms of a counting sentence.
local function isForm(key: string): boolean
	local counted = string.match(key, "^(.+)%.one$") or string.match(key, "^(.+)%.other$")
	return counted ~= nil and Strings.Plurals[counted] ~= nil
end

-- The first plural-looking word after each counting placeholder of `text`, up to two words on, stopping at any
-- punctuation: "{target} glyphs", "{target} training dummies", "{casts} glyphes placés". A single letter is a
-- unit ("{seconds} s") and says nothing of the count.
local function countedPlurals(text: string): { string }
	local found: { string } = {}
	local from = 1
	while true do
		local first, last, name = string.find(text, "{(%w+)}", from)
		if first == nil then
			break
		end
		from = (last :: number) + 1
		if NOT_COUNTS[name :: string] == nil then
			local at = from
			for step = 1, 2 do
				local gap = string.match(text, "^%s*", at) :: string
				-- The first word may stand against the count ("{seconds}s"); the second follows a space.
				local word = if step == 1 or #gap > 0 then string.match(text, "^" .. WORD, at + #gap) else nil
				if word == nil then
					break
				end
				local ending = string.sub(word, -1)
				if #word >= 2 and (ending == "s" or ending == "x") then
					table.insert(found, ("{%s} %s"):format(name :: string, word))
					break
				end
				at += #gap + #word
			end
		end
	end
	return found
end

describe("plurals", function()
	it("counts as the Unicode CLDR says English and French count", function()
		expect(Strings.pluralForm(1, "en")).toBe("one")
		expect(Strings.pluralForm(0, "en")).toBe("other")
		expect(Strings.pluralForm(2, "en")).toBe("other")
		expect(Strings.pluralForm(1.5, "en")).toBe("other")
		expect(Strings.pluralForm(-1, "en")).toBe("one")
		-- French says "0 glyphe" and "1,5 glyphe": anything under two is one.
		expect(Strings.pluralForm(0, "fr")).toBe("one")
		expect(Strings.pluralForm(1, "fr")).toBe("one")
		expect(Strings.pluralForm(1.5, "fr")).toBe("one")
		expect(Strings.pluralForm(2, "fr")).toBe("other")
		expect(Strings.pluralForm(1000, "fr")).toBe("other")
		-- A language the table does not hold reads English, so it counts as English does.
		expect(Strings.pluralForm(0, "de")).toBe("other")
		expect(Strings.pluralForm(1, nil)).toBe("one")
	end)

	it("says a count of one in the singular and more in the plural, in both languages", function()
		expect(Strings.plural("quest.winMatches", 1)).toBe("Win 1 match")
		expect(Strings.plural("quest.winMatches", 3)).toBe("Win 3 matches")
		expect(Strings.plural("quest.winMatches", 1, nil, "fr")).toBe("Gagne 1 match")
		expect(Strings.plural("quest.winMatches", 3, nil, "fr")).toBe("Gagne 3 matchs")
		expect(Strings.plural("quest.defeatDummies", 1)).toBe("Defeat 1 training dummy")
		expect(Strings.plural("purchase.tiersGranted", 1)).toBe("+1 battle pass tier")
		expect(Strings.plural("purchase.tiersGranted", 5, nil, "fr")).toBe("+5 paliers de battle pass")
		expect(Strings.plural("loadout.moreSlots", 4, nil, "fr")).toBe("+4 emplacements")
		-- A one-round rule has its own words, with no count at all.
		expect(Strings.plural("queue.rule", 1)).toBe("A single round decides")
		expect(Strings.plural("queue.rule", 2, nil, "fr")).toBe("Le premier à 2 manches gagne")
	end)

	it("takes the form from the sentence's own placeholder when read through Strings.t", function()
		-- What the screens and the server's messages do: the key and its params, the count among them.
		expect(Strings.t("quest.castGlyphs", { target = 1 })).toBe("Cast 1 glyph")
		expect(Strings.t("quest.castGlyphs", { target = 30 })).toBe("Cast 30 glyphs")
		expect(Strings.t("quest.castGlyphs", { target = 0 }, "fr")).toBe("Trace 0 glyphe")
		expect(Strings.t("shop.confirm.balance", { before = 2480, after = 1 }, "en")).toBe("2,480 → 1 Folio")
		expect(Strings.t("battleground.standing", { standing = 1 }, "en")).toBe("1 Forger standing")
		expect(Strings.t("battleground.defeated", { defeated = 2 }, "fr")).toBe("2 vaincus")
		-- The amount keeps its grouping, whichever form it takes.
		expect(Strings.t("quest.reward", { xp = 1500, folios = 2000 }, "en")).toBe("+1,500 XP, +2,000 Folios")
		expect(Strings.t("quest.reward", { xp = 10, folios = 1 }, "en")).toBe("+10 XP, +1 Folio")
		-- A count given as words already is read as its number.
		expect(Strings.t("quest.castGlyphs", { target = "1" })).toBe("Cast 1 glyph")
		-- With no count at all, the plural form, its placeholder left showing.
		expect(Strings.t("quest.castGlyphs")).toBe("Cast {target} glyphs")
		expect(Strings.t("quest.castGlyphs", { target = "many" })).toBe("Cast many glyphs")
	end)

	it("fills the counting placeholder with the count, unless the params already write it", function()
		expect(Strings.plural("queue.waiting", 1, { queued = 0 })).toBe("0 / 1 player")
		expect(Strings.plural("quest.reward", 4000, { xp = 10 }, "fr")).toBe("+10 XP, +4\u{202F}000 Folios")
		expect(Strings.plural("quest.reward", 1, { xp = 10, folios = "one" })).toBe("+10 XP, +one Folio")
		-- The caller's table is never written to.
		local params = { queued = 0 }
		Strings.plural("queue.waiting", 2, params)
		expect(params.needed).toBeNil()
	end)

	it("knows a counting sentence by its key, and shows a key that counts nothing", function()
		expect(Strings.has("quest.castGlyphs")).toBe(true)
		expect(Strings.has("quest.castGlyphs.one")).toBe(true)
		expect(Strings.has("quest.nothing")).toBe(false)
		expect(Strings.plural("common.ok", 2)).toBe("[common.ok]")
		expect(Strings.plural("quest.nothing", 2)).toBe("[quest.nothing]")
		expect(Strings.t("quest.nothing", { target = 2 })).toBe("[quest.nothing]")
	end)

	it("gives every counting sentence its two forms, and no form without its sentence", function()
		local count = 0
		for key, counted in pairs(Strings.Plurals) do
			count += 1
			expect(Strings.Table[key]).toBeNil()
			local one = Strings.Table[key .. ".one"]
			local other = Strings.Table[key .. ".other"]
			assert(one ~= nil and other ~= nil, key .. " is missing a form")
			-- The plural form always writes its count; the singular may say it in words ("A single round").
			for _, words in ipairs({ other.en, other.fr }) do
				if string.find(words, "{" .. counted .. "}", 1, true) == nil then
					error(("%s counts {%s} and its plural %q never writes it"):format(key, counted, words))
				end
			end
		end
		expect(count).toBeGreaterThanOrEqual(30)
		for key in pairs(Strings.Table) do
			if string.match(key, "%.one$") ~= nil or string.match(key, "%.other$") ~= nil then
				if not isForm(key) then
					error(("%s is a form of no counting sentence: add its key to Strings.Plurals"):format(key))
				end
			end
		end
	end)

	it('refuses a count written straight into a plural ("{n} <word>s") outside the two forms', function()
		local refused: { string } = {}
		for _, key in ipairs(Strings.keys()) do
			if not isForm(key) then
				local entry = Strings.Table[key]
				for _, text in ipairs({ entry.en, entry.fr }) do
					for _, found in ipairs(countedPlurals(text)) do
						table.insert(refused, ("%s: %s in %q"):format(key, found, text))
					end
				end
			end
		end
		if #refused > 0 then
			error(
				"counted in the plural whatever the count, give them Strings.Plurals forms:\n"
					.. table.concat(refused, "\n")
			)
		end
		-- The gate reads what it should: each shape it exists for, and nothing it should not.
		expect(#countedPlurals("Win {target} matches")).toBe(1)
		expect(#countedPlurals("Defeat {target} training dummies")).toBe(1)
		expect(#countedPlurals("{hits} / {casts} glyphes placés")).toBe(1)
		expect(#countedPlurals("{seconds}s restantes")).toBe(1)
		expect(#countedPlurals("Palier {tier} pas encore atteint.")).toBe(0)
		expect(#countedPlurals("{name} is locked")).toBe(0)
		expect(#countedPlurals("{seconds} s")).toBe(0)
		expect(#countedPlurals("+{xp} XP, +{folios} Folio")).toBe(0)
		expect(#countedPlurals("Win {target}. Matches")).toBe(0)
	end)

	it("exempts only placeholders the table uses", function()
		local used: { [string]: boolean } = {}
		for _, entry in pairs(Strings.Table) do
			for _, text in ipairs({ entry.en, entry.fr }) do
				for name in string.gmatch(text, "{(%w+)}") do
					used[name] = true
				end
			end
		end
		for name in pairs(NOT_COUNTS) do
			if not used[name] then
				error(("{%s} is exempted from the plural gate and no sentence uses it"):format(name))
			end
		end
	end)

	it("counts the Result's execution line in the player's words", function()
		local cases = {
			{ Locale = "en", Hits = 1, Casts = 1, Damage = 1, Text = "1 / 1 glyph landed · 1 damage" },
			{ Locale = "fr", Hits = 0, Casts = 1, Damage = 1, Text = "0 / 1 glyphe placé · 1 dégât" },
			{ Locale = "fr", Hits = 12, Casts = 20, Damage = 640, Text = "12 / 20 glyphes placés · 640 dégâts" },
			{ Locale = "en", Hits = 12, Casts = 20, Damage = 640, Text = "12 / 20 glyphs landed · 640 damage" },
		}
		for _, case in ipairs(cases) do
			local world = Engine.world({ Stubs = Engine.interfaceStubs() })
			local ResultCard = world.require("src/ui/components/ResultCard")
			local parent = Engine.instance("Frame")
			local card = ResultCard.new({
				t = function(key: string, params: { [string]: any }?): string
					return Strings.t(key, params, case.Locale)
				end,
			}, parent)
			card:Render({
				ModeId = "Duel1v1",
				Won = true,
				Draw = false,
				Scores = { 2, 0 },
				Xp = 0,
				Folios = 0,
				RatingBefore = 1000,
				RatingAfter = 1000,
				RankKeyBefore = "",
				RankKeyAfter = "",
				FirstWinOfDay = false,
				Casts = case.Casts,
				Hits = case.Hits,
				DamageDealt = case.Damage,
				DamageTaken = 0,
				Grade = "grade.clean",
			} :: any)
			expect(parent:FindFirstChild("Execution", true).Text).toBe(case.Text)
		end
	end)

	it('says "emplacement" in French, never the English "slot"', function()
		local count = 0
		for key, entry in pairs(Strings.Table) do
			local lower = string.lower(entry.fr)
			if string.find(lower, "slot", 1, true) ~= nil then
				error(("%s says %q in French"):format(key, entry.fr))
			end
			if string.find(string.lower(entry.en), "slot", 1, true) ~= nil then
				count += 1
			end
		end
		expect(count).toBeGreaterThanOrEqual(6)
		expect(Strings.t("loadout.slots", { used = 3, total = 6 }, "fr")).toBe("3 / 6 emplacements")
		expect(Strings.t("pass.loadoutSlots", nil, "fr")).toBe("Emplacements d'équipement")
	end)
end)
