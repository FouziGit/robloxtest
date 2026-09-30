--!strict
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("Strings", function()
	it("has en and fr for every key", function()
		for key, entry in pairs(Strings.Table) do
			expect(type(entry.en)).toBe("string")
			expect(type(entry.fr)).toBe("string")
			expect(#entry.en).toBeGreaterThan(0)
			expect(#entry.fr).toBeGreaterThan(0)
			-- Both locales must use the same SET of placeholders. A placeholder may legitimately repeat
			-- inside one locale ("{size}v{size}"), so compare sets, never occurrence counts.
			local function placeholders(text: string): { [string]: boolean }
				local found: { [string]: boolean } = {}
				for name in string.gmatch(text, "{(%w+)}") do
					found[name] = true
				end
				return found
			end
			local enParams = placeholders(entry.en)
			local frParams = placeholders(entry.fr)
			for name in pairs(frParams) do
				if not enParams[name] then
					error(("key %s: placeholder {%s} only in fr"):format(key, name))
				end
			end
			for name in pairs(enParams) do
				if not frParams[name] then
					error(("key %s: placeholder {%s} only in en"):format(key, name))
				end
			end
		end
	end)

	it("substitutes params and falls back to English", function()
		expect(Strings.t("hud.levelUp", { level = 7 })).toBe("Level 7 reached!")
		expect(Strings.t("hud.levelUp", { level = 7 }, "fr")).toBe("Niveau 7 atteint !")
		expect(Strings.t("hud.levelUp", { level = 7 }, "de")).toBe("Level 7 reached!")
		expect(Strings.t("hud.levelUp")).toBe("Level {level} reached!")
	end)

	it("marks missing keys visibly instead of throwing", function()
		expect(Strings.t("does.not.exist")).toBe("[does.not.exist]")
		expect(Strings.has("does.not.exist")).toBe(false)
		expect(Strings.has("common.ok")).toBe(true)
	end)

	it("groups a whole number from a thousand up by three, the way each language writes it", function()
		local thin = "\u{202F}"
		expect(Strings.number(999, "en")).toBe("999")
		expect(Strings.number(999, "fr")).toBe("999")
		expect(Strings.number(1000, "en")).toBe("1,000")
		expect(Strings.number(1000, "fr")).toBe("1" .. thin .. "000")
		expect(Strings.number(12345, "fr")).toBe("12" .. thin .. "345")
		expect(Strings.number(1000000, "en")).toBe("1,000,000")
		expect(Strings.number(1000000, "fr")).toBe("1" .. thin .. "000" .. thin .. "000")
		-- The sign stays; under a thousand either way, and anything but a whole number, reads as tostring does.
		expect(Strings.number(-1000, "en")).toBe("-1,000")
		expect(Strings.number(-2480, "fr")).toBe("-2" .. thin .. "480")
		expect(Strings.number(-999, "fr")).toBe("-999")
		expect(Strings.number(1234.5, "en")).toBe(tostring(1234.5))
		expect(Strings.number(1234.5, "fr")).toBe(tostring(1234.5))
		expect(Strings.number(math.huge, "en")).toBe(tostring(math.huge))
		-- No locale, or one the table does not hold, writes English.
		expect(Strings.number(3120)).toBe("3,120")
		expect(Strings.number(3120, "de")).toBe("3,120")
	end)

	it("groups the amounts a sentence carries, and nothing else", function()
		local thin = "\u{202F}"
		expect(Strings.t("level.xp", { xp = 3120, needed = 4000 }, "fr")).toBe(
			"3" .. thin .. "120 / 4" .. thin .. "000 XP"
		)
		expect(Strings.t("level.xp", { xp = 3120, needed = 4000 }, "en")).toBe("3,120 / 4,000 XP")
		expect(Strings.t("quest.reward", { xp = 1500, folios = 2000 }, "en")).toBe("+1,500 XP, +2,000 Folios")
		expect(Strings.t("reward.folios", { amount = 2480 }, "fr")).toBe("+2" .. thin .. "480")
		expect(Strings.t("folios.balance", { folios = 2480 }, "fr")).toBe("2" .. thin .. "480")
		expect(Strings.t("folios.balance", { folios = 2480 }, "en")).toBe("2,480")
		expect(Strings.t("shop.confirm.balance", { before = 2480, after = 1680 }, "en")).toBe("2,480 → 1,680 Folios")
		-- A rating, a level, a count or health is no amount: it stays as the server sent it.
		expect(Strings.t("leaderboard.rating", { rating = 1500 }, "en")).toBe("1500")
		expect(Strings.t("hud.levelUp", { level = 1200 }, "fr")).toBe("Niveau 1200 atteint !")
		expect(Strings.t("boss.health", { health = 12000, max = 50000 }, "en")).toBe("12000 / 50000")
		-- Nor, yet, is a price: the Today card has no room for its separator (tests/ShopEquip.spec.luau).
		expect(Strings.t("shop.buyFolios", { price = 1800 }, "en")).toBe("1800 Folios")
		-- An amount the caller already wrote, and the bare substitution, are left alone.
		expect(Strings.t("reward.xp", { xp = "3120" }, "en")).toBe("+3120 XP")
		expect(Strings.format("{xp} XP", { xp = 3120 })).toBe("3120 XP")
	end)

	it("reads every amount placeholder as Folios or XP, in every sentence that names one", function()
		expect(Strings.Quantities).toEqual({
			xp = true,
			needed = true,
			folios = true,
			amount = true,
			before = true,
			after = true,
		})
		-- Every sentence that names one, read: a new one joins this list once its placeholder is read as an amount
		-- too. The one exception, queue.waiting's {needed}, counts the players a queue waits for, never a thousand.
		local audited: { [string]: boolean } = {
			["hud.killReward"] = true,
			["hud.playerKill"] = true,
			["level.xp"] = true,
			["battlepass.xp"] = true,
			["battlepass.reward.folio"] = true,
			["quest.reward"] = true,
			["daily.claimed"] = true,
			["daily.firstWin"] = true,
			["daily.premium"] = true,
			["levelroad.folios"] = true,
			["levelroad.foliosAndTitle"] = true,
			["milestone.caughtUp"] = true,
			["milestone.reached"] = true,
			["milestone.reachedTitle"] = true,
			["queue.waiting"] = true,
			["season.rewardGranted"] = true,
			["match.level"] = true,
			["boss.reward"] = true,
			["purchase.grantedFoliosInstead"] = true,
			["shop.confirm.balance"] = true,
			["reward.folios"] = true,
			["reward.xp"] = true,
			["folios.balance"] = true,
		}
		local named: { [string]: boolean } = {}
		for key, entry in pairs(Strings.Table) do
			for name in string.gmatch(entry.en, "{(%w+)}") do
				if Strings.Quantities[name] then
					named[key] = true
				end
			end
		end
		expect(named).toEqual(audited)
	end)

	it("says a claim « réclamer » in French, the whole family, as the board does", function()
		local count = 0
		for key, entry in pairs(Strings.Table) do
			if string.find(string.lower(entry.en), "claim", 1, true) ~= nil then
				count += 1
				if
					string.find(entry.fr, "écupér", 1, true) ~= nil
					or string.find(entry.fr, "éclam", 1, true) == nil
				then
					error(("%s says a claim %q in French"):format(key, entry.fr))
				end
			end
		end
		expect(count).toBeGreaterThanOrEqual(8)
		expect(Strings.t("quest.claim", nil, "fr")).toBe("Réclamer")
		expect(Strings.t("battlepass.claim", nil, "fr")).toBe("Réclamer")
		expect(Strings.t("daily.claim", nil, "fr")).toBe("Réclamer")
		expect(Strings.t("battlepass.claimAll", { count = 3 }, "fr")).toBe("Tout réclamer (3)")
		expect(Strings.t("quest.claim", nil, "en")).toBe("Claim")
		-- The leaderboard's way to the player's own row.
		expect(Strings.t("leaderboard.findMe", nil, "fr")).toBe("Ma place")
		expect(Strings.t("leaderboard.findMe", nil, "en")).toBe("My place")
	end)

	it("lists keys sorted", function()
		local keys = Strings.keys()
		expect(#keys).toBeGreaterThan(50)
		for index = 2, #keys do
			expect(keys[index - 1] < keys[index]).toBe(true)
		end
	end)
end)
