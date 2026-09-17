--!strict
-- Invariants of the pure config modules.
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local ElementConfig = require("../src/shared/Config/ElementConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local JutsuConfig = require("../src/shared/Config/JutsuConfig")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local RankTiers = require("../src/shared/Pure/RankTiers")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local Strings = require("../src/shared/Strings")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("JutsuConfig", function()
	it("has unique ids and combos within the length limit", function()
		local ids: { [string]: boolean } = {}
		local combos: { [string]: boolean } = {}
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			expect(ids[jutsu.Id]).toBeNil()
			ids[jutsu.Id] = true
			local key = table.concat(jutsu.Combo, "-")
			expect(combos[key]).toBeNil()
			combos[key] = true
			expect(#jutsu.Combo).toBeGreaterThanOrEqual(2)
			expect(#jutsu.Combo).toBeLessThanOrEqual(GameConfig.Combo.MaxLength)
			for _, element in ipairs(jutsu.Combo) do
				expect(ElementConfig.isElement(element)).toBe(true)
			end
			expect(ElementConfig.isElement(jutsu.Element)).toBe(true)
		end
	end)

	it("has sane numbers and localized keys", function()
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			expect(jutsu.Cost).toBeGreaterThan(0)
			expect(jutsu.Cooldown).toBeGreaterThan(0)
			expect(jutsu.Damage).toBeGreaterThanOrEqual(0)
			expect(jutsu.Range).toBeGreaterThan(0)
			expect(Strings.has(jutsu.NameKey)).toBe(true)
			expect(Strings.has(jutsu.DescriptionKey)).toBe(true)
			expect(SoundConfig.Sfx[jutsu.SfxId]).never.toBeNil()
			for name, value in pairs(jutsu.Params) do
				expect(type(name)).toBe("string")
				expect(type(value)).toBe("number")
			end
			if jutsu.Unlock.Kind == "Level" then
				expect(jutsu.Unlock.Value).toBeGreaterThan(1)
			end
		end
		expect(#JutsuConfig.defaultUnlocks()).toBeGreaterThan(0)
		expect(JutsuConfig.ById.Fireball).never.toBeNil()
	end)
end)

describe("InputConfig", function()
	it("defaults avoid movement and reserved keys and are allowed", function()
		local forbidden =
			{ A = true, D = true, S = true, W = true, Z = true, Q = true, I = true, O = true, Space = true, Tab = true }
		local seenKeyboard: { [string]: boolean } = {}
		local seenGamepad: { [string]: boolean } = {}
		for _, action in ipairs(InputConfig.Actions) do
			local key = InputConfig.DefaultKeyboard[action]
			expect(forbidden[key]).toBeNil()
			expect(InputConfig.AllowedKeyboard[key]).toBe(true)
			expect(seenKeyboard[key]).toBeNil()
			seenKeyboard[key] = true

			local button = InputConfig.DefaultGamepad[action]
			expect(InputConfig.AllowedGamepad[button]).toBe(true)
			expect(seenGamepad[button]).toBeNil()
			seenGamepad[button] = true

			expect(Strings.has(InputConfig.ActionNameKeys[action])).toBe(true)
			expect(InputConfig.Touch.Positions[action]).never.toBeNil()
		end
		expect(InputConfig.AllowedKeyboard.A).toBeNil()
		expect(InputConfig.AllowedKeyboard.Q).toBeNil()
		expect(InputConfig.AllowedGamepad.ButtonA).toBeNil()
		expect(InputConfig.AllowedGamepad.ButtonStart).toBeNil()
	end)
end)

describe("ElementConfig", function()
	it("is consistent", function()
		for _, id in ipairs(ElementConfig.Order) do
			expect(#ElementConfig.Colors[id]).toBe(3)
			expect(Strings.has(ElementConfig.NameKeys[id])).toBe(true)
			expect(ElementConfig.Glyphs[id]).never.toBeNil()
		end
		expect(ElementConfig.isElement("Lava")).toBe(false)
		expect(#ElementConfig.Base + #ElementConfig.Unlockable).toBe(#ElementConfig.Order)
	end)
end)

describe("BattlepassConfig", function()
	it("defines 50 tiers per season with valid rewards", function()
		for seasonId, season in pairs(BattlepassConfig.Seasons) do
			expect(#season.Tiers).toBe(BattlepassConfig.MaxTier)
			for tier, def in ipairs(season.Tiers) do
				expect(def.Free).never.toBeNil()
				expect(def.Premium).never.toBeNil()
				for _, reward in ipairs({ def.Free, def.Premium }) do
					if reward.Kind == "Ryo" then
						expect(reward.Amount).toBeGreaterThan(0)
					elseif reward.Kind == "Cosmetic" then
						expect(Strings.has("cosmetic." .. reward.Id)).toBe(true)
					elseif reward.Kind == "XpBoost" then
						expect(reward.Minutes).toBeGreaterThan(0)
					else
						error(("season %s tier %d: unknown reward kind"):format(seasonId, tier))
					end
				end
			end
		end
		expect(BattlepassConfig.getTier("S1", 1)).never.toBeNil()
		expect(BattlepassConfig.getTier("S1", 51)).toBeNil()
		expect(BattlepassConfig.getTier("S9", 1)).toBeNil()
		expect(BattlepassConfig.xpForTier(1)).toBe(100)
		expect(BattlepassConfig.xpForTier(50)).toBe(1080)
	end)
end)

describe("ProgressionConfig", function()
	it("has a monotonic level curve", function()
		local previous = 0
		local total = 0
		for level = 1, ProgressionConfig.MaxLevel - 1 do
			local needed = ProgressionConfig.xpForLevel(level)
			expect(needed).toBeGreaterThan(previous)
			previous = needed
			total += needed
		end
		expect(ProgressionConfig.xpForLevel(1)).toBe(100)
		expect(total).toBeGreaterThan(400000)
		expect(total).toBeLessThan(600000)
	end)
end)

describe("RankingConfig", function()
	it("has valid tiers, K schedule and localized rewards", function()
		expect((RankTiers.validate(RankingConfig.Tiers))).toBe(true)
		for _, tier in ipairs(RankingConfig.Tiers) do
			expect(Strings.has(tier.NameKey)).toBe(true)
			local reward = RankingConfig.SeasonRewards[tier.Id]
			expect(reward).never.toBeNil()
			expect(reward.Ryo).toBeGreaterThan(0)
			if reward.Cosmetic ~= nil then
				expect(Strings.has("cosmetic." .. reward.Cosmetic)).toBe(true)
			end
		end
		local schedule = RankingConfig.KFactorSchedule
		expect(schedule[#schedule].MaxMatches).toBeNil()
		for index = 2, #schedule do
			expect(schedule[index].K).toBeLessThan(schedule[index - 1].K)
		end
		expect(RankingConfig.RatingFloor).toBeLessThan(RankingConfig.InitialRating)
		for _, mode in ipairs(RankingConfig.Modes) do
			expect(MatchConfig.Modes[mode]).never.toBeNil()
		end
	end)
end)

describe("MatchConfig", function()
	it("defines coherent modes and arenas", function()
		for _, modeId in ipairs(MatchConfig.ModeOrder) do
			local mode = MatchConfig.Modes[modeId]
			expect(mode).never.toBeNil()
			expect(mode.Id).toBe(modeId)
			expect(Strings.has(mode.NameKey)).toBe(true)
			expect(mode.TeamSize * mode.Teams).toBeGreaterThanOrEqual(2)
			expect(mode.RoundsToWin).toBeGreaterThanOrEqual(1)
			expect(mode.DurationSeconds).toBeGreaterThan(30)
			expect(MatchConfig.Arenas[mode.ArenaId]).never.toBeNil()
			expect(MatchConfig.Rewards[modeId]).never.toBeNil()
		end
		expect(MatchConfig.Matchmaking.MaxWindow).toBeGreaterThan(MatchConfig.Matchmaking.BaseWindow)
	end)
end)

describe("CosmeticConfig", function()
	it("has unique, localized items and every reward references the catalog", function()
		local seen = {}
		for _, item in ipairs(CosmeticConfig.Items) do
			expect(seen[item.Id]).toBeNil()
			seen[item.Id] = true
			expect(Strings.has(item.NameKey)).toBe(true)
			expect(ShopConfig.PriceRyo[item.Rarity]).never.toBeNil()
			expect(table.find(CosmeticConfig.Slots, item.Slot)).never.toBeNil()
			if item.Slot == "Skin" then
				expect(JutsuConfig.ById[item.Target :: string]).never.toBeNil()
			end
		end
		for _, season in pairs(BattlepassConfig.Seasons) do
			for _, tier in ipairs(season.Tiers) do
				for _, reward in ipairs({ tier.Free, tier.Premium }) do
					if reward.Kind == "Cosmetic" then
						expect(CosmeticConfig.ById[reward.Id]).never.toBeNil()
					end
				end
			end
		end
		for _, reward in pairs(RankingConfig.SeasonRewards) do
			if reward.Cosmetic ~= nil then
				expect(CosmeticConfig.ById[reward.Cosmetic]).never.toBeNil()
			end
		end
		for _, id in ipairs(MonetizationConfig.SkinPackCosmetics) do
			expect(CosmeticConfig.ById[id]).never.toBeNil()
		end
		for rarity, productKey in pairs(ShopConfig.RobuxProduct) do
			local product = MonetizationConfig.Products[productKey]
			expect(product).never.toBeNil()
			expect(product.Rarity).toBe(rarity)
		end
		for _, rarity in ipairs(ShopConfig.RarityOrder) do
			expect(Strings.has("shop.rarity." .. rarity)).toBe(true)
		end
	end)
end)

describe("MonetizationConfig", function()
	it("lists every unfilled id and localizes every entry", function()
		local missing = MonetizationConfig.missingIds()
		local total = 0
		for key, pass in pairs(MonetizationConfig.Passes) do
			total += 1
			expect(Strings.has(pass.NameKey)).toBe(true)
			expect(Strings.has(pass.DescKey)).toBe(true)
			expect(pass.PriceRobux).toBeGreaterThan(0)
			if pass.Id == 0 then
				expect(table.find(missing, "Passes." .. key)).never.toBeNil()
			end
		end
		for key, product in pairs(MonetizationConfig.Products) do
			total += 1
			expect(Strings.has(product.NameKey)).toBe(true)
			expect(Strings.has(product.DescKey)).toBe(true)
			expect(product.PriceRobux).toBeGreaterThan(0)
			if product.Kind == "Ryo" or product.Kind == "TierSkip" then
				expect(product.Amount).toBeGreaterThan(0)
			elseif product.Kind == "XpBoost" then
				expect(product.Minutes).toBeGreaterThan(0)
			elseif product.Kind == "Cosmetic" then
				expect(ShopConfig.PriceRyo[product.Rarity :: string]).never.toBeNil()
			end
			if product.Id == 0 then
				expect(table.find(missing, "Products." .. key)).never.toBeNil()
			end
		end
		expect(#missing).toBeLessThanOrEqual(total)
		expect((MonetizationConfig.productByAssetId(0))).toBeNil()
		expect((MonetizationConfig.passByAssetId(0))).toBeNil()
	end)
end)
