--!strict
-- Invariants of the pure config modules.
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local ComboResolver = require("../src/shared/Pure/ComboResolver")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DeveloperConfig = require("../src/server/Config/DeveloperConfig")
local FeelConfig = require("../src/shared/Config/FeelConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local RankTiers = require("../src/shared/Pure/RankTiers")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local Spring = require("../src/shared/Pure/Spring")
local Strings = require("../src/shared/Strings")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Balance targets of docs/GAME_DESIGN.md §3 and §5.
local ROSTER_SIZE = 20
local COST_MIN, COST_MAX = 15, 55 -- §5 table: Slicing Gust 15 … Colophon 55
local COOLDOWN_MIN, COOLDOWN_MAX = 3, 25
local SUSTAINED_DPS_MAX = 7 -- a two-key basic, cast once per cooldown
local ULTIMATE_HIT_MAX = 50 -- an ultimate never removes more than half of CombatConfig.Health.Max

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Damage one target takes from a single full cast: zones and trails tick, everything else hits once.
local function castDamage(glyph: GlyphConfig.GlyphDef): number
	local hits = glyph.Params.MaxHitsPerTarget or glyph.Params.Ticks or 1
	return glyph.Damage * hits
end

describe("GlyphConfig", function()
	it("has unique ids and combos within the length limit", function()
		local ids: { [string]: boolean } = {}
		local combos: { [string]: boolean } = {}
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			expect(ids[glyph.Id]).toBeNil()
			ids[glyph.Id] = true
			local key = table.concat(glyph.Combo, "-")
			expect(combos[key]).toBeNil()
			combos[key] = true
			expect(#glyph.Combo).toBeGreaterThanOrEqual(2)
			expect(#glyph.Combo).toBeLessThanOrEqual(GameConfig.Combo.MaxLength)
			for _, pigment in ipairs(glyph.Combo) do
				expect(PigmentConfig.isPigment(pigment)).toBe(true)
			end
			expect(PigmentConfig.isPigment(glyph.Pigment)).toBe(true)
		end
	end)

	it("has sane numbers and localized keys", function()
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			expect(glyph.Cost).toBeGreaterThanOrEqual(COST_MIN)
			expect(glyph.Cost).toBeLessThanOrEqual(COST_MAX)
			expect(glyph.Cooldown).toBeGreaterThanOrEqual(COOLDOWN_MIN)
			expect(glyph.Cooldown).toBeLessThanOrEqual(COOLDOWN_MAX)
			expect(glyph.Damage).toBeGreaterThanOrEqual(0)
			expect(glyph.Damage).toBeLessThanOrEqual(ULTIMATE_HIT_MAX)
			expect(glyph.Range).toBeGreaterThan(0)
			expect(glyph.Effect).toBe(glyph.Id)
			expect(Strings.has(glyph.NameKey)).toBe(true)
			expect(Strings.has(glyph.DescriptionKey)).toBe(true)
			expect(VfxConfig.isId(glyph.VfxId)).toBe(true)
			for name, value in pairs(glyph.Params) do
				expect(type(name)).toBe("string")
				expect(type(value)).toBe("number")
				expect(isFinite(value)).toBe(true)
				expect(value).toBeGreaterThanOrEqual(0)
			end
			if glyph.Unlock.Kind == "Level" then
				expect(glyph.Unlock.Value).toBeGreaterThan(1)
				expect(glyph.Unlock.Value).toBeLessThanOrEqual(ProgressionConfig.MaxLevel)
			elseif glyph.Unlock.Kind == "Pigment" then
				-- gated by its own pigment (Orpiment): never part of a fresh profile
				expect(table.find(PigmentConfig.Unlockable, glyph.Pigment)).never.toBeNil()
				expect(table.find(GlyphConfig.defaultUnlocks(), glyph.Id)).toBeNil()
			else
				expect(table.find(PigmentConfig.Base, glyph.Pigment)).never.toBeNil()
			end
			if table.find(PigmentConfig.Unlockable, glyph.Pigment) ~= nil then
				expect(glyph.Unlock.Kind).toBe("Pigment")
			end
		end
		expect(#GlyphConfig.defaultUnlocks()).toBeGreaterThan(0)
		expect(GlyphConfig.ById.Brand).never.toBeNil()
	end)

	it("makes every glyph reachable through a level or its pigment", function()
		expect(#GlyphConfig.Glyphs).toBe(ROSTER_SIZE)
		local reachable: { [string]: boolean } = {}
		for _, id in ipairs(GlyphConfig.defaultUnlocks()) do
			reachable[id] = true
		end
		for level = 2, ProgressionConfig.MaxLevel do
			for _, id in ipairs(GlyphConfig.unlocksForLevel(level)) do
				reachable[id] = true
			end
		end
		for _, pigment in ipairs(PigmentConfig.Unlockable) do
			for _, id in ipairs(GlyphConfig.unlocksForPigment(pigment)) do
				reachable[id] = true
			end
		end
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			expect(reachable[glyph.Id]).toBe(true)
		end
		local levelFive = GlyphConfig.unlocksForLevel(5)
		expect(#levelFive).toBe(2)
		expect(levelFive).toContain("Hairline")
		expect(levelFive).toContain("Stipple")
		expect(#GlyphConfig.unlocksForPigment("Orpiment")).toBe(4)
		expect(#GlyphConfig.unlocksForPigment("Cinnabar")).toBe(0)
	end)

	it("builds a combo tree where every recipe still casts", function()
		local resolver = ComboResolver.new(GlyphConfig.recipes(), GameConfig.Combo.MaxLength)
		expect(#resolver.duplicates).toBe(0)
		expect(GameConfig.Combo.ExtendWindowSeconds).toBeLessThan(GameConfig.Combo.TimeoutSeconds)
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			expect(ComboResolver.resolve(resolver, glyph.Combo)).toBe(glyph.Id)
			local sequence: { string } = {}
			local decision: ComboResolver.Decision = { Action = "Reset", Reason = "Empty" }
			for _, pigment in ipairs(glyph.Combo) do
				sequence, decision = ComboResolver.push(resolver, sequence, pigment)
			end
			-- Typing the last pigment of a recipe either fires it or leaves it pending as a castable
			-- prefix, in which case the client only waits ExtendWindowSeconds: no recipe is shadowed.
			if decision.Action == "Wait" then
				expect(decision.Castable).toBe(true)
				expect(ComboResolver.timeout(resolver, glyph.Combo)).toEqual({ Action = "Cast", GlyphId = glyph.Id })
			else
				expect(decision.Action).toBe("Cast")
				expect(ComboResolver.resolve(resolver, glyph.Combo)).toBe(glyph.Id)
			end
		end
		-- Colophon's third press is the only intermediate that is not itself a recipe: it waits the
		-- full timeout instead of casting (docs/GAME_DESIGN.md §4 rule 5).
		local pending, third = ComboResolver.push(resolver, { "Orpiment", "Orpiment" }, "Orpiment")
		expect(#pending).toBe(3)
		expect(third.Action).toBe("Wait")
		if third.Action == "Wait" then
			expect(third.Castable).toBe(false)
		end
	end)

	it("keeps the sustained damage, burst and stun budgets of GAME_DESIGN §5", function()
		local basicBestHit = 0
		local basicBestCast: { [string]: number } = {}
		local longWorstCast: { [string]: number } = {}
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			local cast = castDamage(glyph)
			if #glyph.Combo == 2 then
				expect(cast / glyph.Cooldown).toBeLessThanOrEqual(SUSTAINED_DPS_MAX)
				basicBestHit = math.max(basicBestHit, glyph.Damage)
				basicBestCast[glyph.Pigment] = math.max(basicBestCast[glyph.Pigment] or 0, cast)
			elseif cast > 0 then
				local current = longWorstCast[glyph.Pigment]
				longWorstCast[glyph.Pigment] = if current == nil then cast else math.min(current, cast)
			end
			local stun = glyph.Params.StunSeconds or glyph.Params.Stun
			if stun ~= nil then
				expect(stun * (glyph.Params.Ticks or 1)).toBeLessThanOrEqual(CombatConfig.Hit.StunMaxSeconds)
			end
		end
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			if glyph.Archetype == "Ultimate" then
				-- long combo, big cost, big impact — and it always out-bursts every basic
				expect(glyph.Damage).toBeLessThanOrEqual(ULTIMATE_HIT_MAX)
				expect(glyph.Damage).toBeGreaterThan(basicBestHit)
				expect(CombatConfig.Block.BrokenBy[glyph.Archetype]).toBe(true)
			end
		end
		-- Every damaging longer combo of an pigment pays more per cast than that pigment's basics.
		for pigment, best in pairs(basicBestCast) do
			local worstLong = longWorstCast[pigment]
			if worstLong ~= nil then
				expect(worstLong).toBeGreaterThanOrEqual(best)
			end
		end
	end)
end)

describe("CombatConfig", function()
	it("defines the pigment interaction marks and the Gilding buff", function()
		local attributes: { [string]: boolean } = {
			[CombatConfig.Status.SlowAttribute] = true,
			[CombatConfig.Status.StunAttribute] = true,
			[CombatConfig.Status.BlockAttribute] = true,
		}
		for _, mark in ipairs({ CombatConfig.Status.Fanned, CombatConfig.Status.Conductive }) do
			expect(attributes[mark.Attribute]).toBeNil()
			attributes[mark.Attribute] = true
			expect(PigmentConfig.isPigment(mark.AppliedByPigment)).toBe(true)
			expect(PigmentConfig.isPigment(mark.AmplifiesPigment)).toBe(true)
			expect(mark.AppliedByPigment).never.toBe(mark.AmplifiesPigment)
			expect(mark.DurationSeconds).toBeGreaterThan(0)
			expect(mark.DamageMultiplier).toBeGreaterThan(1)
			expect(mark.DamageMultiplier).toBeLessThanOrEqual(1.5)
			expect(Strings.has(mark.NameKey)).toBe(true)
		end
		local buff = CombatConfig.Status.Gilding
		expect(attributes[buff.Attribute]).toBeNil()
		expect(buff.KnockbackImmune).toBe(true)
		expect(buff.DamageReduction).toBeGreaterThan(0)
		-- a buff you keep is weaker than holding guard, and never covers its own cooldown
		expect(buff.DamageReduction).toBeLessThan(CombatConfig.Block.DamageReduction)
		expect(buff.DurationSeconds).toBeGreaterThan(0)
		expect(buff.DurationSeconds).toBeLessThan(GlyphConfig.ById.Gilding.Cooldown)
		expect(Strings.has(buff.NameKey)).toBe(true)
		expect(Strings.has("hud.status.bonus")).toBe(true)
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
	it("keeps the capture cancel keys out of both rebind whitelists", function()
		-- A cancel key that is also assignable can never be assigned: pressing it aborts the capture
		-- instead of being recorded. ButtonB shipped in both roles and was silently unassignable.
		expect(#InputConfig.CaptureCancelKeys).toBeGreaterThan(0)
		for _, name in ipairs(InputConfig.CaptureCancelKeys) do
			expect(type(name)).toBe("string")
			expect(InputConfig.AllowedKeyboard[name]).toBeNil()
			expect(InputConfig.AllowedGamepad[name]).toBeNil()
		end
	end)

	it("makes every whitelisted key assignable", function()
		local cancels: { [string]: boolean } = {}
		for _, name in ipairs(InputConfig.CaptureCancelKeys) do
			cancels[name] = true
		end
		for name in pairs(InputConfig.AllowedKeyboard) do
			expect(cancels[name]).toBeNil()
		end
		for name in pairs(InputConfig.AllowedGamepad) do
			expect(cancels[name]).toBeNil()
		end
	end)
end)

describe("PigmentConfig", function()
	it("is consistent", function()
		for _, id in ipairs(PigmentConfig.Order) do
			expect(#PigmentConfig.Colors[id]).toBe(3)
			expect(Strings.has(PigmentConfig.NameKeys[id])).toBe(true)
			expect(PigmentConfig.Sigils[id]).never.toBeNil()
		end
		expect(PigmentConfig.isPigment("Lava")).toBe(false)
		expect(#PigmentConfig.Base + #PigmentConfig.Unlockable).toBe(#PigmentConfig.Order)
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
						-- The id must exist in CosmeticConfig, not merely have a name. An id that only has
						-- a Strings entry passes every gate and then refuses at grant time, while the
						-- player is told they received the reward.
						expect(CosmeticConfig.ById[reward.Id]).never.toBeNil()
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

describe("DeveloperConfig", function()
	it("is a well-formed allowlist", function()
		local dev = DeveloperConfig
		expect(type(dev.Names)).toBe("table")
		expect(type(dev.UserIds)).toBe("table")
		for _, name in ipairs(dev.Names) do
			expect(type(name)).toBe("string")
			-- Roblox usernames are 3 to 20 characters. A blank or padded entry would silently match nobody,
			-- or worse, match a name that a typo made up.
			expect(#name >= 3 and #name <= 20).toBe(true)
			expect(string.match(name, "^%s") == nil and string.match(name, "%s$") == nil).toBe(true)
		end
		for _, userId in ipairs(dev.UserIds) do
			expect(type(userId)).toBe("number")
			expect(userId > 0 and userId == math.floor(userId)).toBe(true)
		end
		expect(type(dev.UnlimitedSlots)).toBe("boolean")
		expect(type(dev.FreeCasting)).toBe("boolean")
		-- A floor, never zero: zero lets a glyph overlap itself and every cap in GlyphEffects is per cast.
		expect(dev.MinRecastSeconds > 0).toBe(true)
	end)

	it("matches only the listed accounts", function()
		local dev = DeveloperConfig
		for _, name in ipairs(dev.Names) do
			expect(DeveloperConfig.isDeveloper(0, name)).toBe(true)
			-- Exact match only: no case folding, no trimming, no prefix.
			expect(DeveloperConfig.isDeveloper(0, string.lower(name) .. "x")).toBe(false)
			expect(DeveloperConfig.isDeveloper(0, " " .. name)).toBe(false)
		end
		for _, userId in ipairs(dev.UserIds) do
			expect(DeveloperConfig.isDeveloper(userId, "")).toBe(true)
		end
		expect(DeveloperConfig.isDeveloper(0, "")).toBe(false)
		expect(DeveloperConfig.isDeveloper(-1, "SomeoneElse")).toBe(false)
		expect(DeveloperConfig.isDeveloper(123456789, "AnotherPlayer")).toBe(false)
	end)

	it("stays a short, explicit list", function()
		-- A list that grows is a list nobody reads. Every entry hands out the whole roster and free
		-- casting, so it must stay something a human checks at a glance before publishing.
		local dev = DeveloperConfig
		expect(#dev.Names + #dev.UserIds <= 5).toBe(true)
	end)
end)

describe("cosmetic references", function()
	it("every cosmetic id named anywhere in config exists in CosmeticConfig", function()
		local function check(source: string, cosmeticId: string)
			if CosmeticConfig.ById[cosmeticId] == nil then
				error(("%s names the unknown cosmetic %q"):format(source, cosmeticId))
			end
		end
		local seen = 0
		for _, cosmeticId in ipairs(MonetizationConfig.SkinPackCosmetics) do
			check("MonetizationConfig.SkinPackCosmetics", cosmeticId)
			seen += 1
		end
		for tierId, reward in pairs(RankingConfig.SeasonRewards) do
			local cosmeticId = reward.Cosmetic
			if cosmeticId ~= nil then
				check("RankingConfig.SeasonRewards." .. tierId, cosmeticId)
				seen += 1
			end
		end
		for seasonId, season in pairs(BattlepassConfig.Seasons) do
			for tier, def in ipairs(season.Tiers) do
				for _, reward in ipairs({ def.Free, def.Premium }) do
					if reward.Kind == "Cosmetic" then
						check(("BattlepassConfig.%s tier %d"):format(seasonId, tier), reward.Id)
						seen += 1
					end
				end
			end
		end
		expect(seen).toBeGreaterThan(5)
	end)

	it("every sellable cosmetic has a Ryo price and a Robux product for its rarity", function()
		for _, item in ipairs(CosmeticConfig.Items) do
			if item.Sellable then
				expect(ShopConfig.PriceRyo[item.Rarity]).never.toBeNil()
				expect(ShopConfig.RobuxProduct[item.Rarity]).never.toBeNil()
			end
		end
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

	it("keeps the ladder key cooldown at or under the periodic write interval", function()
		-- LeaderboardService waits a key's OrderedDataStore cooldown out only on the forced flush when a
		-- player leaves. The periodic scan skips that wait, which is sound only while the cooldown is the
		-- shorter of the two.
		local board = RankingConfig.Leaderboard
		expect(board.KeyCooldownSeconds).toBeGreaterThan(0)
		expect(board.KeyCooldownSeconds <= board.MinWriteIntervalSeconds).toBe(true)
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
				expect(GlyphConfig.ById[item.Target :: string]).never.toBeNil()
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

describe("VfxConfig", function()
	it("has unique ids and covers every glyph", function()
		local seen: { [string]: boolean } = {}
		for _, id in ipairs(VfxConfig.Ids) do
			expect(seen[id]).toBeNil()
			seen[id] = true
			expect(VfxConfig.IdSet[id]).toBe(true)
		end
		expect(#VfxConfig.Ids).toBe(#VfxConfig.GlyphIds + #VfxConfig.CombatIds + #VfxConfig.BossIds)
		expect(VfxConfig.isId("NotAnEffect")).toBe(false)
		for _, glyph in ipairs(GlyphConfig.Glyphs) do
			expect(VfxConfig.isId(glyph.VfxId)).toBe(true)
		end
	end)
end)

describe("WorldBossConfig", function()
	it("scales health with the player count and stays bounded", function()
		local schedule = WorldBossConfig.Schedule
		expect(WorldBossConfig.healthFor(schedule.MinPlayers)).toBe(WorldBossConfig.Health.Base)
		expect(WorldBossConfig.healthFor(schedule.MinPlayers - 5)).toBe(WorldBossConfig.Health.Base)
		expect(WorldBossConfig.healthFor(schedule.MinPlayers + 1)).toBe(
			WorldBossConfig.Health.Base + WorldBossConfig.Health.PerExtraPlayer
		)
		expect(WorldBossConfig.healthFor(10000)).toBe(WorldBossConfig.Health.Max)
		expect(schedule.AnnounceSeconds + schedule.FightSeconds + schedule.CleanupSeconds).toBeLessThan(
			schedule.IntervalSeconds
		)
	end)

	it("has ordered phases and reachable attacks", function()
		local phases = WorldBossConfig.Phases
		expect(#phases).toBeGreaterThanOrEqual(3)
		expect(phases[1].Threshold).toBe(1)
		for index = 2, #phases do
			expect(phases[index].Threshold).toBeLessThan(phases[index - 1].Threshold)
			expect(phases[index].AttackSpeed).toBeGreaterThan(phases[index - 1].AttackSpeed)
		end
		expect(WorldBossConfig.phaseFor(1)).toBe(1)
		expect(WorldBossConfig.phaseFor(0.5)).toBe(2)
		expect(WorldBossConfig.phaseFor(0.1)).toBe(#phases)

		local ids: { [string]: boolean } = {}
		local byPhase: { [number]: number } = {}
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			expect(ids[attack.Id]).toBeNil()
			ids[attack.Id] = true
			expect(Strings.has(attack.NameKey)).toBe(true)
			expect(attack.TelegraphSeconds).toBeGreaterThan(0.5)
			expect(attack.Damage).toBeGreaterThan(0)
			expect(attack.Radius).toBeGreaterThan(0)
			expect(attack.Range).toBeGreaterThanOrEqual(attack.Radius)
			expect(attack.CooldownSeconds).toBeGreaterThan(attack.TelegraphSeconds)
			expect(attack.MinPhase).toBeGreaterThanOrEqual(1)
			expect(attack.MinPhase).toBeLessThanOrEqual(#phases)
			byPhase[attack.MinPhase] = (byPhase[attack.MinPhase] or 0) + 1
		end
		-- phase 1 must have something to cast, and every phase adds at least one attack
		expect(byPhase[1]).toBeGreaterThanOrEqual(2)
		for index = 2, #phases do
			expect(byPhase[index]).toBeGreaterThanOrEqual(1)
		end
		expect(Strings.has(WorldBossConfig.Boss.NameKey)).toBe(true)
		expect(WorldBossConfig.Boss.BodySize).toHaveLength(3)
		for _, axis in ipairs(WorldBossConfig.Boss.BodySize) do
			expect(axis).toBeGreaterThan(0)
		end
		expect(WorldBossConfig.Rewards.KillBonusShare).toBeGreaterThan(WorldBossConfig.Rewards.MinShareToReward)
	end)
end)

-- FeelConfig is tuning, not balance, so it is free to move -- but docs/JUICE_PLAN.md fixed a few of its
-- numbers, and a value that drifts outside them stops being polish and becomes a bug the player feels
-- as input lag or motion sickness.
describe("FeelConfig", function()
	it("keeps hit-stop inside the 40 to 90 millisecond window", function()
		expect(FeelConfig.HitStop.MinSeconds).toBeGreaterThanOrEqual(0.04)
		expect(FeelConfig.HitStop.MaxSeconds).toBeLessThanOrEqual(0.09)
		expect(FeelConfig.HitStop.MinSeconds).toBeLessThan(FeelConfig.HitStop.MaxSeconds)
		expect(FeelConfig.HitStop.MinDamage).toBeLessThan(FeelConfig.HitStop.MaxDamage)
	end)

	it("spans the damage the roster can actually deal", function()
		-- If MaxDamage sat above every glyph in the game, no hit would ever reach the top of the window
		-- and the heaviest ultimate would feel the same as a mid-tier spell.
		local heaviest = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			heaviest = math.max(heaviest, def.Damage)
		end
		expect(FeelConfig.HitStop.MaxDamage).toBeLessThanOrEqual(heaviest)
		expect(FeelConfig.HitStop.MinDamage).toBeLessThanOrEqual(CombatConfig.Melee.Damage[1])
	end)

	it("gives every shake profile a duration and a survivable rotation", function()
		local count = 0
		for name, profile in pairs(FeelConfig.Shake.Profiles) do
			count += 1
			local total = profile.FadeInSeconds + profile.SustainSeconds + profile.FadeOutSeconds
			if total <= 0 then
				error(("shake profile %s lasts no time at all"):format(name))
			end
			expect(profile.Amplitude).toBeGreaterThan(0)
			expect(profile.Frequency).toBeGreaterThan(0)
			-- Past about 0.05 radians of camera roll, mobile players report motion sickness.
			for _, axis in ipairs(profile.RotationInfluence) do
				if axis > 0.05 then
					error(("shake profile %s rolls the camera by %.3f rad"):format(name, axis))
				end
			end
			expect(#profile.PositionInfluence).toBe(3)
			expect(#profile.RotationInfluence).toBe(3)
		end
		expect(count).toBeGreaterThanOrEqual(5)
	end)

	it("orders the shake profiles by the weight they stand for", function()
		local profiles = FeelConfig.Shake.Profiles
		expect(profiles.Heavy.Amplitude).toBeGreaterThan(profiles.Light.Amplitude)
		expect(profiles.Light.Amplitude).toBeGreaterThan(profiles.Cast.Amplitude)
		-- A heavy hit lets go slowly; a light one is over before it is read.
		expect(profiles.Heavy.FadeOutSeconds).toBeGreaterThan(profiles.Light.FadeOutSeconds)
	end)

	it("cannot leave the field of view permanently wrong", function()
		expect(FeelConfig.Fov.MaxOffsetDegrees).toBeGreaterThan(0)
		expect(FeelConfig.Fov.MaxOffsetDegrees).toBeLessThanOrEqual(15)
		expect(FeelConfig.Fov.Tension).toBeGreaterThan(0)
		expect(FeelConfig.Fov.Friction).toBeGreaterThan(0)
		expect(FeelConfig.Fov.SettleEpsilon).toBeGreaterThan(0)
	end)

	it("caps everything that can be spawned more than once at a time", function()
		-- Six players in one arena is the design target; every one of these is a per-frame cost.
		expect(FeelConfig.Shake.MaxConcurrent).toBeGreaterThan(0)
		expect(FeelConfig.Flash.MaxConcurrent).toBeGreaterThan(0)
		expect(FeelConfig.DamageNumbers.MaxConcurrent).toBeGreaterThan(0)
		expect(FeelConfig.Shake.MaxConcurrent).toBeLessThanOrEqual(8)
		expect(FeelConfig.DamageNumbers.MaxConcurrent).toBeLessThanOrEqual(30)
	end)

	it("holds a damage number long enough to read before it fades", function()
		expect(FeelConfig.DamageNumbers.HoldFraction).toBeGreaterThan(0.2)
		expect(FeelConfig.DamageNumbers.HoldFraction).toBeLessThan(1)
		expect(FeelConfig.DamageNumbers.Seconds).toBeGreaterThan(0.4)
		expect(FeelConfig.DamageNumbers.PopScale).toBeGreaterThan(1)
	end)

	it("keeps every haptic motor inside the range the engine accepts", function()
		local count = 0
		for name, pulse in pairs(FeelConfig.Haptics) do
			if type(pulse) == "table" then
				count += 1
				for _, key in ipairs({ "Small", "Large" }) do
					local value = pulse[key]
					if type(value) ~= "number" or value < 0 or value > 1 then
						error(("haptic %s.%s is %s, and the motors take 0 to 1"):format(name, key, tostring(value)))
					end
				end
				expect(pulse.Seconds).toBeGreaterThan(0)
				expect(pulse.Seconds).toBeLessThanOrEqual(0.3)
			end
		end
		expect(count).toBeGreaterThanOrEqual(4)
	end)

	it("gives every named spring a friction that settles", function()
		for name, spring in pairs(FeelConfig.Springs) do
			expect(spring.Tension).toBeGreaterThan(0)
			if spring.Friction <= 0 then
				error(("spring %s has no friction and would oscillate forever"):format(name))
			end
			-- Far under critical damping the value rings like a bell instead of arriving.
			if spring.Friction < Spring.criticalFriction(spring.Tension) * 0.4 then
				error(("spring %s is so underdamped it would visibly ring"):format(name))
			end
		end
	end)
end)

-- docs/ART_BIBLE.md rule 2: "Un joueur doit pouvoir nommer l'école d'un sort à la couleur seule, de dos,
-- à trente studs." That is a gameplay requirement, not a taste one -- a player who cannot tell Indigo
-- from Umber at a glance cannot read what is about to hit them -- so it is worth a test rather than an
-- opinion in a document.
describe("pigment readability", function()
	-- Weighted euclidean distance in sRGB ("redmean"), the cheap approximation of perceptual difference
	-- that is standard for exactly this question. It ranges from 0 to about 765.
	local function distance(a: { number }, b: { number }): number
		local rmean = (a[1] + b[1]) / 2
		local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
		return math.sqrt((2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db)
	end

	-- The closest pair in the shipped palette is Indigo and Umber at 179, and the next is Cinnabar and
	-- Umber at 182. The floor sits below both with room to spare, so it is a guard against a future edit
	-- rather than a restatement of today's values.
	local MIN_PAIR_DISTANCE = 150
	-- Against the world itself. Vellum #E8E0CE is the paper everything is drawn on, and the weakest
	-- pigment against it is Orpiment at 257: a yellow on cream is the hardest case the palette contains.
	local MIN_BACKGROUND_DISTANCE = 200
	local VELLUM = { 232, 224, 206 }

	it("keeps every pair of schools apart", function()
		local order = PigmentConfig.Order
		for i = 1, #order do
			for j = i + 1, #order do
				local a, b = order[i], order[j]
				local apart = distance(PigmentConfig.Colors[a], PigmentConfig.Colors[b])
				if apart < MIN_PAIR_DISTANCE then
					error(("%s and %s are %.0f apart; a player cannot name the school"):format(a, b, apart))
				end
			end
		end
	end)

	it("keeps every school off the page it is drawn on", function()
		for _, id in ipairs(PigmentConfig.Order) do
			local apart = distance(PigmentConfig.Colors[id], VELLUM)
			if apart < MIN_BACKGROUND_DISTANCE then
				error(("%s is %.0f from the world's own colour and would vanish into it"):format(id, apart))
			end
		end
	end)

	it("keeps the scenery out of the pigments' range", function()
		-- Art bible rule 1: "Le décor n'est jamais saturé. Le seul élément saturé de l'écran est un sort."
		-- Both halves are tested, because the rule only buys anything if both hold: a muted world with a
		-- muted spell is as unreadable as a loud world with a loud one.
		--
		-- Measured as absolute chroma, (max - min) / 255, not as HSV saturation. HSV saturation is
		-- meaningless on a near-black: Charcoal #17150F has eight units of spread across a value of 23,
		-- which reads as 0.35 saturated and looks exactly like black. Absolute chroma puts it at 0.03,
		-- which is what the eye agrees with.
		local function chroma(rgb: { number }): number
			return (math.max(rgb[1], rgb[2], rgb[3]) - math.min(rgb[1], rgb[2], rgb[3])) / 255
		end
		-- The world's two colours: Vellum #E8E0CE at 0.10 and Charcoal #17150F at 0.03.
		for _, world in ipairs({ VELLUM, { 23, 21, 15 } }) do
			local value = chroma(world)
			if value > 0.15 then
				error(("a world colour has chroma %.2f; the scenery is never saturated"):format(value))
			end
		end
		-- And every pigment above it. Umber is the narrowest at 0.24 -- a burnt earth is a muted colour by
		-- nature -- which is why the floor sits where it does rather than somewhere more comfortable.
		for _, id in ipairs(PigmentConfig.Order) do
			local value = chroma(PigmentConfig.Colors[id])
			if value < 0.2 then
				error(("%s has chroma %.2f and would read as scenery"):format(id, value))
			end
		end
	end)
end)
