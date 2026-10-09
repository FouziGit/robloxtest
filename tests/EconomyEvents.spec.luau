--!strict
-- Every Folio earned or spent is reported once, where it moves (E8-S1). The Economy dashboards saw two movements
-- out of fifteen: the shop and the Robux packs reported their own, and every reward of play, of the calendar and
-- of the pass reached the balance without a word. They now all go through CurrencyService, which reports each one
-- itself, with the reason it was handed.
--
-- Three parts. The sources list every call that moves Folios, and the reasons each can hand over, so a new one
-- cannot join without being filed. Each of those reasons, run through the real CurrencyService and
-- AnalyticsService on a pretend Roblox analytics (tests/analytics.luau), reaches it exactly once, under a
-- transaction type Roblox knows. And nothing else in src/server reports a movement of its own.
local AnalyticsConfig = require("../src/server/Config/AnalyticsConfig")
local BotConfig = require("../src/shared/Config/BotConfig")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DeveloperConfig = require("../src/server/Config/DeveloperConfig")
local DrillConfig = require("../src/shared/Config/DrillConfig")
local ExLibrisConfig = require("../src/shared/Config/ExLibrisConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local LevelRoad = require("../src/shared/Pure/LevelRoad")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local Server = require("./server")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

----------------------------------------------------------------
-- Every call that moves Folios, and the reasons it hands over
----------------------------------------------------------------

type Flow = "Source" | "Sink" | "Refund"
type Site = { File: string, Call: string, Flow: Flow, Reasons: { string } }

local function productReasons(filter: (product: MonetizationConfig.ProductDef) -> string?): { string }
	local reasons: { string } = {}
	for key, product in pairs(MonetizationConfig.Products) do
		local reason = filter(product)
		if reason ~= nil then
			table.insert(reasons, (reason:gsub("<key>", key)))
		end
	end
	table.sort(reasons)
	return reasons
end

local function shopReasons(): { string }
	local reasons: { string } = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Sellable then
			table.insert(reasons, "Shop:" .. item.Id)
		end
	end
	return reasons
end

-- What the Battleground pays under: each Forger tier's RewardKey, and a member's kill of another (D-282).
local function battlegroundReasons(): { string }
	local reasons: { string } = {}
	for _, tier in pairs(BotConfig.Tiers) do
		table.insert(reasons, tier.RewardKey)
	end
	table.insert(reasons, "BattlegroundKill")
	table.sort(reasons)
	return reasons
end

-- The reasons of a family (AnalyticsConfig.FamilyTransactions): one per milestone of the level road, per plate of the
-- Ex-libris, per grade of each Lectern drill, as HonoursService and DrillService build them.
local function milestoneReasons(): { string }
	local reasons: { string } = {}
	for _, milestone in ipairs(ProgressionConfig.Milestones) do
		table.insert(reasons, "Milestone" .. LevelRoad.milestoneKey(milestone.Level))
	end
	return reasons
end

local function plateReasons(): { string }
	local reasons: { string } = {}
	for _, plate in ipairs(ExLibrisConfig.Plates) do
		table.insert(reasons, "ExLibris" .. plate.Id)
	end
	return reasons
end

local function drillReasons(): { string }
	local catalog = Server.world().require("src/shared/DrillCatalog")
	local reasons: { string } = {}
	for _, drill in ipairs(catalog.List) do
		for _, grade in ipairs(DrillConfig.Grades) do
			table.insert(reasons, "Drill" .. drill.Id .. grade.Id)
		end
	end
	return reasons
end

local SERVICES = "src/server/Services/"

-- Written as each call is written: a new call that moves Folios fails the count below until it is listed here,
-- with the reasons it hands over, and every one of those reasons is then filed and run.
local SITES: { Site } = {
	{
		File = "DailyRewardService",
		Call = '(player, day.Folios + (if owned then OWNED_COSMETIC_FOLIOS else 0), "DailyStreak")',
		Flow = "Source",
		Reasons = { "DailyStreak" },
	},
	{
		File = "DailyRewardService",
		Call = '(player, FIRST_WIN_FOLIOS, "FirstWinOfDay")',
		Flow = "Source",
		Reasons = { "FirstWinOfDay" },
	},
	{
		File = "DailyRewardService",
		Call = '(player, PREMIUM_BONUS.Folios, "PremiumBonus")',
		Flow = "Source",
		Reasons = { "PremiumBonus" },
	},
	{
		File = "BattlepassService",
		Call = '(player, reward.Amount, "Battlepass")',
		Flow = "Source",
		Reasons = { "Battlepass" },
	},
	{
		File = "EnemyService",
		Call = '(killer, pay.Folios, "DummyKill")',
		Flow = "Source",
		Reasons = { "DummyKill" },
	},
	{
		File = "QuestService",
		Call = '(player, reward.RewardFolios, "Quest" .. period)',
		Flow = "Source",
		Reasons = { "QuestDaily", "QuestWeekly" },
	},
	{
		File = "RankingService",
		Call = "(player, reward.Folios, SEASON_REWARD_REASON)",
		Flow = "Source",
		Reasons = { "SeasonReward" },
	},
	{
		File = "MatchService",
		Call = "(player, folios, reason)",
		Flow = "Source",
		Reasons = { "MatchWin", "MatchLoss", "MatchDraw" },
	},
	-- A match's kills, paid with its result and under the same rules (D-255).
	{
		File = "MatchService",
		Call = '(player, killFolios, "PlayerKill")',
		Flow = "Source",
		Reasons = { "PlayerKill" },
	},
	{
		File = "HonoursService",
		Call = '(player, step.Folios, "Milestone" .. step.Id)',
		Flow = "Source",
		Reasons = milestoneReasons(),
	},
	{
		File = "HonoursService",
		Call = '(player, plate.Folios, "ExLibris" .. plate.Id)',
		Flow = "Source",
		Reasons = plateReasons(),
	},
	{
		File = "DrillService",
		Call = "(player, def.Folios, reason)",
		Flow = "Source",
		Reasons = drillReasons(),
	},
	{
		File = "WorldBossService/Rewards",
		Call = '(player, reward.Folios, "BossParticipation")',
		Flow = "Source",
		Reasons = { "BossParticipation" },
	},
	{
		File = "WorldBossService/Rewards",
		Call = '(player, reward.BonusFolios, "BossKillBonus")',
		Flow = "Source",
		Reasons = { "BossKillBonus" },
	},
	-- A Forger's kill, and a member's kill of another, under the same daily cap (D-282).
	{
		File = "BattlegroundService/Rewards",
		Call = "(player, folios, reason)",
		Flow = "Source",
		Reasons = battlegroundReasons(),
	},
	-- A practice duel against a Forger, under its daily allowance (D-272).
	{
		File = "SparService",
		Call = '(player, SparRules.scaled(base.Folios, SPAR.RewardFactor), "Spar")',
		Flow = "Source",
		Reasons = { "Spar" },
	},
	-- A victory on the Flyleaf, paid by the page itself under its daily cap (D-267).
	{
		File = "FlyleafService/Rewards",
		Call = "(killer, folios, REASON)",
		Flow = "Source",
		Reasons = { "FlyleafKill" },
	},
	{
		File = "MonetizationService/Receipts",
		Call = '(player, amount, "Product:" .. productKey)',
		Flow = "Source",
		Reasons = productReasons(function(product): string?
			return if product.Kind == "Folios" then "Product:<key>" else nil
		end),
	},
	{
		File = "MonetizationService/Receipts",
		Call = '(player, rate * units, "Product:" .. productKey .. ":Compensation")',
		Flow = "Source",
		Reasons = productReasons(function(product): string?
			return if product.CompensationFolios ~= nil then "Product:<key>:Compensation" else nil
		end),
	},
	{
		File = "MonetizationService/Receipts",
		Call = '(player, price, "Product:Cosmetic" .. rarity)',
		Flow = "Source",
		Reasons = productReasons(function(product): string?
			return if product.Kind == "Cosmetic" then "Product:Cosmetic" .. (product.Rarity :: string) else nil
		end),
	},
	{
		File = "ShopService",
		Call = '(player, price, TRANSACTION_SHOP .. ":" .. cosmeticId)',
		Flow = "Sink",
		Reasons = shopReasons(),
	},
	{
		File = "ShopService",
		Call = '(player, price, TRANSACTION_SHOP .. ":" .. cosmeticId)',
		Flow = "Refund",
		Reasons = shopReasons(),
	},
}

local METHOD: { [Flow]: string } = { Source = "add", Sink = "trySpend", Refund = "refund" }

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif entry:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

-- How many times `needle` is written in `haystack`.
local function occurrences(haystack: string, needle: string): number
	local count, from = 0, 1
	while true do
		local at = haystack:find(needle, from, true)
		if at == nil then
			return count
		end
		count += 1
		from = at + #needle
	end
end

----------------------------------------------------------------
-- A server with the currency and the analytics, nothing else
----------------------------------------------------------------

type Bank = {
	world: Server.World,
	currency: any,
	data: { [any]: any },
	join: (userId: number) -> any,
	-- The economy events that reached Roblox, as { player, flow, currency, amount, balance, transaction, item }.
	events: () -> { { any } },
	-- Long enough for the player's analytics budget to hold one more event.
	rest: () -> (),
}

local START = 1000000

local function bank(): Bank
	local world = Server.world()
	local analytics = world.require("src/server/Services/AnalyticsService")
	analytics.Init({})
	analytics.Start()
	local profiles: { [any]: any } = {}
	local currency = world.require("src/server/Services/CurrencyService")
	currency.Init({
		DataService = {
			get = function(player: any): any
				return profiles[player]
			end,
			push = function() end,
		},
		Analytics = analytics,
	})
	currency.Start()
	local result: any = { world = world, currency = currency, data = profiles }
	function result.join(userId: number): any
		local player = world:join(userId, "Player" .. userId)
		profiles[player] = { Currency = { Folios = START }, Passes = {} }
		return player
	end
	function result.events(): { { any } }
		local found = {}
		for _, call in ipairs(world.analytics:of("LogEconomyEvent")) do
			local args = call.Args
			table.insert(found, { call.Player, args[1].Name, args[2], args[3], args[4], args[5], args[6] })
		end
		return found
	end
	function result.rest()
		world:advance(60 / AnalyticsConfig.Budget.PerMinute + 0.05)
	end
	return result :: Bank
end

----------------------------------------------------------------
-- Specs
----------------------------------------------------------------

describe("every call that moves Folios (E8-S1)", function()
	it("is listed with the reasons it hands over, and nothing moves Folios unlisted", function()
		local files: { string } = {}
		collect("src/server", files)
		local found = 0
		for _, path in ipairs(files) do
			local source = code(path):gsub("function%s+[%w_%.:]+%b()", "")
			for _, method in ipairs({ "add", "trySpend", "refund" }) do
				found += occurrences(source, "urrency." .. method .. "(")
			end
		end
		expect(found).toBe(#SITES)
		for _, site in ipairs(SITES) do
			local path = SERVICES .. site.File .. ".luau"
			local call = "urrency." .. METHOD[site.Flow] .. site.Call
			if occurrences(code(path), call) ~= 1 then
				error(("%s does not write %s once"):format(path, call))
			end
			expect(#site.Reasons).toBeGreaterThan(0)
		end
	end)

	it("hands over reasons AnalyticsConfig files under a transaction type Roblox knows", function()
		local used: { [string]: boolean } = {}
		for _, site in ipairs(SITES) do
			for _, reason in ipairs(site.Reasons) do
				local transaction, item, listed = AnalyticsConfig.economyOf(reason)
				if not listed then
					error(("%s hands over %s, which AnalyticsConfig does not file"):format(site.File, reason))
				end
				expect(table.find(AnalyticsConfig.TransactionTypes, transaction)).never.toBeNil()
				expect(#item).toBeGreaterThan(0)
				used[transaction] = true
			end
		end
		local count = 0
		for _ in pairs(used) do
			count += 1
		end
		expect(count).toBeLessThanOrEqual(AnalyticsConfig.Limits.TransactionTypes)
		expect(#AnalyticsConfig.TransactionTypes).toBeLessThanOrEqual(AnalyticsConfig.Limits.TransactionTypes)
	end)

	it("files every Robux product under IAP with the product as its item, and every article under Shop", function()
		for key, product in pairs(MonetizationConfig.Products) do
			local transaction, item = AnalyticsConfig.economyOf("Product:" .. key)
			expect(transaction).toBe("IAP")
			expect(item).toBe(key)
			if product.Kind == "Cosmetic" then
				-- What a cosmetic receipt pays instead of an article is filed under its product.
				local _, instead = AnalyticsConfig.economyOf("Product:Cosmetic" .. (product.Rarity :: string))
				expect(instead).toBe(key)
			end
			local _, compensation = AnalyticsConfig.economyOf("Product:" .. key .. ":Compensation")
			expect(compensation).toBe(key)
		end
		local transaction, item = AnalyticsConfig.economyOf("Shop:" .. CosmeticConfig.Items[1].Id)
		expect(transaction).toBe("Shop")
		expect(item).toBe(CosmeticConfig.Items[1].Id)
		expect(AnalyticsConfig.economyOf("DailyStreak")).toBe("TimedReward")
		expect(AnalyticsConfig.economyOf("MatchWin")).toBe("Gameplay")
	end)

	it("lists no reason nothing hands over", function()
		local handed: { [string]: boolean } = {}
		for _, site in ipairs(SITES) do
			for _, reason in ipairs(site.Reasons) do
				handed[reason] = true
			end
		end
		for reason in pairs(AnalyticsConfig.Transactions) do
			if not handed[reason] then
				error(reason .. " is filed in AnalyticsConfig.Transactions and no call hands it over")
			end
		end
		for family in pairs(AnalyticsConfig.FamilyTransactions) do
			local used = false
			for reason in pairs(handed) do
				if reason:sub(1, #family) == family and AnalyticsConfig.Transactions[reason] == nil then
					used = true
				end
			end
			if not used then
				error(family .. " is a family of AnalyticsConfig.FamilyTransactions and no call hands one over")
			end
		end
	end)

	it("files a reason of a family under its family, with the whole reason as its item", function()
		expect({ AnalyticsConfig.economyOf("Milestone45") }).toEqual({ "Gameplay", "Milestone45", true })
		expect({ AnalyticsConfig.economyOf("ExLibrisBreath4") }).toEqual({ "Gameplay", "ExLibrisBreath4", true })
		expect({ AnalyticsConfig.economyOf("DrillKitStringDraft") }).toEqual({
			"Onboarding",
			"DrillKitStringDraft",
			true,
		})
		-- The family's name alone is no reward of it.
		expect(select(3, AnalyticsConfig.economyOf("Drill"))).toBe(false)
	end)
end)

describe("every Folio earned or spent reaches Roblox's analytics once (E8-S1)", function()
	it("reports each source once, as a Source of Folios, with the credited amount and the balance", function()
		local setup = bank()
		local player = setup.join(21)
		local balance = START
		local expected: { { any } } = {}
		for _, site in ipairs(SITES) do
			if site.Flow == "Source" then
				for _, reason in ipairs(site.Reasons) do
					setup.rest()
					expect(setup.currency.add(player, 30, reason)).toBe(30)
					balance += 30
					local transaction, item = AnalyticsConfig.economyOf(reason)
					table.insert(expected, { player, "Source", GameConfig.Currency.Id, 30, balance, transaction, item })
				end
			end
		end
		expect(setup.events()).toEqual(expected)
		expect(#expected).toBeGreaterThan(20)
	end)

	it("reports each sink once, as a Sink, and the refund that pays it back as a Source", function()
		local setup = bank()
		local player = setup.join(22)
		for _, reason in ipairs(shopReasons()) do
			setup.world.analytics:clear()
			setup.rest()
			expect(setup.currency.trySpend(player, 600, reason)).toBe(true)
			setup.rest()
			expect(setup.currency.refund(player, 600, reason)).toBe(600)
			local _, item = AnalyticsConfig.economyOf(reason)
			expect(setup.events()).toEqual({
				{ player, "Sink", GameConfig.Currency.Id, 600, START - 600, "Shop", item },
				{ player, "Source", GameConfig.Currency.Id, 600, START, "Shop", item },
			})
		end
	end)

	it("reports what a VIP is really credited", function()
		local setup = bank()
		local player = setup.join(23)
		setup.data[player].Passes.Vip = true
		local credited = setup.currency.add(player, 100, "MatchWin")
		expect(credited).toBe(math.floor(100 * ProgressionConfig.VipFolioMultiplier))
		expect(setup.events()).toEqual({
			{ player, "Source", GameConfig.Currency.Id, credited, START + credited, "Gameplay", "MatchWin" },
		})
	end)

	it("reports nothing for a movement that did not happen", function()
		local setup = bank()
		local player = setup.join(24)
		expect(setup.currency.add(player, 0, "MatchWin")).toBe(0)
		expect(setup.currency.add(player, 2.5, "MatchWin")).toBe(0)
		expect(setup.currency.trySpend(player, START + 1, "Shop:" .. CosmeticConfig.Items[1].Id)).toBe(false)
		expect(setup.currency.refund(player, -3, "Shop:" .. CosmeticConfig.Items[1].Id)).toBe(0)
		local stranger = setup.world:join(25, "Stranger")
		expect(setup.currency.add(stranger, 30, "MatchWin")).toBe(0)
		expect(setup.events()).toEqual({})
	end)

	it("reports nothing for a developer's waived spend or its refund, which moved no Folio (D-129)", function()
		expect(DeveloperConfig.UnlimitedFolios).toBe(true)
		local setup = bank()
		local developer = setup.join(DeveloperConfig.UserIds[1])
		local reason = "Shop:" .. CosmeticConfig.Items[1].Id
		expect(setup.currency.trySpend(developer, 600, reason)).toBe(true)
		expect(setup.currency.refund(developer, 600, reason)).toBe(0)
		expect(setup.events()).toEqual({})
	end)

	it("still reports an unfiled reason, and warns about it once", function()
		local setup = bank()
		local player = setup.join(26)
		setup.currency.add(player, 10, "SomethingNew")
		setup.rest()
		setup.currency.add(player, 10, "SomethingNew")
		local events = setup.events()
		expect(#events).toBe(2)
		expect(events[1][6]).toBe(AnalyticsConfig.FallbackTransaction)
		expect(events[1][7]).toBe("SomethingNew")
		local warned = 0
		for _, line in ipairs(setup.world.lines) do
			if line:find("economy reason SomethingNew is not in AnalyticsConfig", 1, true) ~= nil then
				warned += 1
			end
		end
		expect(warned).toBe(1)
	end)

	it("keeps the balance when the report throws", function()
		local setup = bank()
		local player = setup.join(27)
		local analytics = setup.world.require("src/server/Services/AnalyticsService")
		local economy = analytics.economy
		analytics.economy = function()
			error("analytics broke")
		end
		expect(setup.currency.add(player, 30, "MatchWin")).toBe(30)
		expect(setup.data[player].Currency.Folios).toBe(START + 30)
		expect(setup.world:said("economy event MatchWin failed")).toBe(true)
		analytics.economy = economy
	end)
end)

describe("nothing else reports a movement of Folios (E8-S1)", function()
	it("leaves every economy event to CurrencyService", function()
		local files: { string } = {}
		collect("src/server", files)
		for _, path in ipairs(files) do
			local source = code(path):gsub("function%s+[%w_%.:]+%b()", "")
			if path ~= SERVICES .. "CurrencyService.luau" and source:find("%.economy%(") ~= nil then
				error(path .. " reports a movement of Folios of its own: CurrencyService already did")
			end
		end
	end)
end)

return nil
