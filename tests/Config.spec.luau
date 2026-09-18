--!strict
-- Invariants of the pure config modules.
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local CombatConfig = require("../src/shared/Config/CombatConfig")
local ComboResolver = require("../src/shared/Pure/ComboResolver")
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
local VfxConfig = require("../src/shared/Config/VfxConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Balance targets of docs/GAME_DESIGN.md §3 and §5.
local ROSTER_SIZE = 20
local COST_MIN, COST_MAX = 15, 55 -- §5 table: Slicing Gust 15 … Raijin 55
local COOLDOWN_MIN, COOLDOWN_MAX = 3, 25
local SUSTAINED_DPS_MAX = 7 -- a two-key basic, cast once per cooldown
local ULTIMATE_HIT_MAX = 50 -- an ultimate never removes more than half of CombatConfig.Health.Max

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Damage one target takes from a single full cast: zones and trails tick, everything else hits once.
local function castDamage(jutsu: JutsuConfig.JutsuDef): number
	local hits = jutsu.Params.MaxHitsPerTarget or jutsu.Params.Ticks or 1
	return jutsu.Damage * hits
end

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
			expect(jutsu.Cost).toBeGreaterThanOrEqual(COST_MIN)
			expect(jutsu.Cost).toBeLessThanOrEqual(COST_MAX)
			expect(jutsu.Cooldown).toBeGreaterThanOrEqual(COOLDOWN_MIN)
			expect(jutsu.Cooldown).toBeLessThanOrEqual(COOLDOWN_MAX)
			expect(jutsu.Damage).toBeGreaterThanOrEqual(0)
			expect(jutsu.Damage).toBeLessThanOrEqual(ULTIMATE_HIT_MAX)
			expect(jutsu.Range).toBeGreaterThan(0)
			expect(jutsu.Effect).toBe(jutsu.Id)
			expect(Strings.has(jutsu.NameKey)).toBe(true)
			expect(Strings.has(jutsu.DescriptionKey)).toBe(true)
			expect(SoundConfig.Sfx[jutsu.SfxId]).never.toBeNil()
			expect(VfxConfig.isId(jutsu.VfxId)).toBe(true)
			for name, value in pairs(jutsu.Params) do
				expect(type(name)).toBe("string")
				expect(type(value)).toBe("number")
				expect(isFinite(value)).toBe(true)
				expect(value).toBeGreaterThanOrEqual(0)
			end
			if jutsu.Unlock.Kind == "Level" then
				expect(jutsu.Unlock.Value).toBeGreaterThan(1)
				expect(jutsu.Unlock.Value).toBeLessThanOrEqual(ProgressionConfig.MaxLevel)
			elseif jutsu.Unlock.Kind == "Element" then
				-- gated by its own element (Lightning): never part of a fresh profile
				expect(table.find(ElementConfig.Unlockable, jutsu.Element)).never.toBeNil()
				expect(table.find(JutsuConfig.defaultUnlocks(), jutsu.Id)).toBeNil()
			else
				expect(table.find(ElementConfig.Base, jutsu.Element)).never.toBeNil()
			end
			if table.find(ElementConfig.Unlockable, jutsu.Element) ~= nil then
				expect(jutsu.Unlock.Kind).toBe("Element")
			end
		end
		expect(#JutsuConfig.defaultUnlocks()).toBeGreaterThan(0)
		expect(JutsuConfig.ById.Fireball).never.toBeNil()
	end)

	it("makes every jutsu reachable through a level or its element", function()
		expect(#JutsuConfig.Jutsus).toBe(ROSTER_SIZE)
		local reachable: { [string]: boolean } = {}
		for _, id in ipairs(JutsuConfig.defaultUnlocks()) do
			reachable[id] = true
		end
		for level = 2, ProgressionConfig.MaxLevel do
			for _, id in ipairs(JutsuConfig.unlocksForLevel(level)) do
				reachable[id] = true
			end
		end
		for _, element in ipairs(ElementConfig.Unlockable) do
			for _, id in ipairs(JutsuConfig.unlocksForElement(element)) do
				reachable[id] = true
			end
		end
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			expect(reachable[jutsu.Id]).toBe(true)
		end
		local levelFive = JutsuConfig.unlocksForLevel(5)
		expect(#levelFive).toBe(2)
		expect(levelFive).toContain("WindBlade")
		expect(levelFive).toContain("MudShot")
		expect(#JutsuConfig.unlocksForElement("Lightning")).toBe(4)
		expect(#JutsuConfig.unlocksForElement("Fire")).toBe(0)
	end)

	it("builds a combo tree where every recipe still casts", function()
		local resolver = ComboResolver.new(JutsuConfig.recipes(), GameConfig.Combo.MaxLength)
		expect(#resolver.duplicates).toBe(0)
		expect(GameConfig.Combo.ExtendWindowSeconds).toBeLessThan(GameConfig.Combo.TimeoutSeconds)
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			expect(ComboResolver.resolve(resolver, jutsu.Combo)).toBe(jutsu.Id)
			local sequence: { string } = {}
			local decision: ComboResolver.Decision = { Action = "Reset", Reason = "Empty" }
			for _, element in ipairs(jutsu.Combo) do
				sequence, decision = ComboResolver.push(resolver, sequence, element)
			end
			-- Typing the last element of a recipe either fires it or leaves it pending as a castable
			-- prefix, in which case the client only waits ExtendWindowSeconds: no recipe is shadowed.
			if decision.Action == "Wait" then
				expect(decision.Castable).toBe(true)
				expect(ComboResolver.timeout(resolver, jutsu.Combo)).toEqual({ Action = "Cast", JutsuId = jutsu.Id })
			else
				expect(decision.Action).toBe("Cast")
				expect(ComboResolver.resolve(resolver, jutsu.Combo)).toBe(jutsu.Id)
			end
		end
		-- Raijin's third press is the only intermediate that is not itself a recipe: it waits the
		-- full timeout instead of casting (docs/GAME_DESIGN.md §4 rule 5).
		local pending, third = ComboResolver.push(resolver, { "Lightning", "Lightning" }, "Lightning")
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
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			local cast = castDamage(jutsu)
			if #jutsu.Combo == 2 then
				expect(cast / jutsu.Cooldown).toBeLessThanOrEqual(SUSTAINED_DPS_MAX)
				basicBestHit = math.max(basicBestHit, jutsu.Damage)
				basicBestCast[jutsu.Element] = math.max(basicBestCast[jutsu.Element] or 0, cast)
			elseif cast > 0 then
				local current = longWorstCast[jutsu.Element]
				longWorstCast[jutsu.Element] = if current == nil then cast else math.min(current, cast)
			end
			local stun = jutsu.Params.StunSeconds or jutsu.Params.Stun
			if stun ~= nil then
				expect(stun * (jutsu.Params.Ticks or 1)).toBeLessThanOrEqual(CombatConfig.Hit.StunMaxSeconds)
			end
		end
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			if jutsu.Archetype == "Ultimate" then
				-- long combo, big cost, big impact — and it always out-bursts every basic
				expect(jutsu.Damage).toBeLessThanOrEqual(ULTIMATE_HIT_MAX)
				expect(jutsu.Damage).toBeGreaterThan(basicBestHit)
				expect(CombatConfig.Block.BrokenBy[jutsu.Archetype]).toBe(true)
			end
		end
		-- Every damaging longer combo of an element pays more per cast than that element's basics.
		for element, best in pairs(basicBestCast) do
			local worstLong = longWorstCast[element]
			if worstLong ~= nil then
				expect(worstLong).toBeGreaterThanOrEqual(best)
			end
		end
	end)
end)

describe("CombatConfig", function()
	it("defines the elemental interaction marks and the StoneSkin buff", function()
		local attributes: { [string]: boolean } = {
			[CombatConfig.Status.SlowAttribute] = true,
			[CombatConfig.Status.StunAttribute] = true,
			[CombatConfig.Status.BlockAttribute] = true,
		}
		for _, mark in ipairs({ CombatConfig.Status.Fanned, CombatConfig.Status.Conductive }) do
			expect(attributes[mark.Attribute]).toBeNil()
			attributes[mark.Attribute] = true
			expect(ElementConfig.isElement(mark.AppliedByElement)).toBe(true)
			expect(ElementConfig.isElement(mark.AmplifiesElement)).toBe(true)
			expect(mark.AppliedByElement).never.toBe(mark.AmplifiesElement)
			expect(mark.DurationSeconds).toBeGreaterThan(0)
			expect(mark.DamageMultiplier).toBeGreaterThan(1)
			expect(mark.DamageMultiplier).toBeLessThanOrEqual(1.5)
			expect(Strings.has(mark.NameKey)).toBe(true)
		end
		local buff = CombatConfig.Status.StoneSkin
		expect(attributes[buff.Attribute]).toBeNil()
		expect(buff.KnockbackImmune).toBe(true)
		expect(buff.DamageReduction).toBeGreaterThan(0)
		-- a buff you keep is weaker than holding guard, and never covers its own cooldown
		expect(buff.DamageReduction).toBeLessThan(CombatConfig.Block.DamageReduction)
		expect(buff.DurationSeconds).toBeGreaterThan(0)
		expect(buff.DurationSeconds).toBeLessThan(JutsuConfig.ById.StoneSkin.Cooldown)
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

describe("VfxConfig", function()
	it("has unique ids and covers every jutsu", function()
		local seen: { [string]: boolean } = {}
		for _, id in ipairs(VfxConfig.Ids) do
			expect(seen[id]).toBeNil()
			seen[id] = true
			expect(VfxConfig.IdSet[id]).toBe(true)
		end
		expect(#VfxConfig.Ids).toBe(#VfxConfig.JutsuIds + #VfxConfig.CombatIds)
		expect(VfxConfig.isId("NotAnEffect")).toBe(false)
		for _, jutsu in ipairs(JutsuConfig.Jutsus) do
			expect(VfxConfig.isId(jutsu.VfxId)).toBe(true)
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
