--!strict
-- A developer product receipt, run (tests/engine.luau): the real Receipts, BattlepassService and
-- CurrencyService, with the profile, its save and the player's toasts as the only fakes.
--
-- The Robux are taken when the player confirms the dialog, and only PurchaseGranted settles a receipt:
-- NotProcessedYet leaves it pending, and Roblox delivers it again at every join. A tier skip that found the
-- pass at its last tier answered NotProcessedYet for ever (R2), and one bought between tiers 46 and 49 gave
-- fewer tiers than it sold, without a word (R14).
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local USER_ID = 7
local SEASON = GameConfig.SeasonId
local GRANTED = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
local TIER_SKIP = "TierSkip5"

type Toast = { Key: string, Params: { [string]: any }? }
type Fixture = {
	data: any,
	-- This world's MonetizationConfig, ids filled in.
	config: any,
	toasts: { Toast },
	saves: number,
	-- Product ids of every Roblox purchase dialog the server opened.
	opened: { number },
	-- The player presses a Robux button (the PromptPurchase remote).
	ask: (productKey: string) -> (),
	-- Roblox delivers the receipt of a confirmed dialog.
	deliver: (productKey: string, purchaseId: string) -> any,
}

local function profile(tier: number, xp: number): any
	return {
		Battlepass = {
			[SEASON] = { Tier = tier, XP = xp, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
		},
		Currency = { Folios = 0 },
		Passes = {},
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
		Purchases = { Receipts = {}, ProductCounts = {} },
	}
end

local function setup(tier: number, xp: number?): Fixture
	local opened: { number } = {}
	local world = Engine.world({
		Services = {
			MarketplaceService = {
				PromptProductPurchase = function(_self: any, _player: any, productId: number)
					table.insert(opened, productId)
				end,
			},
		},
	})
	-- The ids ship at 0 until the Creator Dashboard fills them; this world's copy of the config gets its own.
	local config = world.require("src/shared/Config/MonetizationConfig")
	local keys: { string } = {}
	for key in pairs(config.Products) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for index, key in ipairs(keys) do
		config.Products[key].Id = 1000 + index
	end

	local player = world.player
	player.UserId = USER_ID
	world.game:GetService("Players").GetPlayerByUserId = function(_self: any, userId: number): any
		return if userId == USER_ID then player else nil
	end

	local data = profile(tier, xp or 0)
	local fixture = { data = data, toasts = {} :: { Toast }, saves = 0, opened = opened, config = config } :: any
	local dataService = {
		get = function(): any
			return data
		end,
		waitFor = function(): any
			return data
		end,
		push = function() end,
		recordReceipt = function(_player: any, purchaseId: string): boolean
			table.insert(data.Purchases.Receipts, purchaseId)
			return true
		end,
		saveNow = function(): boolean
			fixture.saves += 1
			return true
		end,
		isActive = function(): boolean
			return true
		end,
		-- Saving works: tests/SaveOutage.spec.luau is where it does not.
		isCritical = function(): boolean
			return false
		end,
	}
	local notify = {
		send = function(_player: any, key: string, params: { [string]: any }?)
			table.insert(fixture.toasts, { Key = key, Params = params })
		end,
	}
	local currency = world.require("src/server/Services/CurrencyService")
	currency.Init({ DataService = dataService })
	local battlepass = world.require("src/server/Services/BattlepassService")
	battlepass.Init({
		Registry = { on = function() end },
		DataService = dataService,
		Notify = notify,
		Currency = currency,
		Cosmetic = {
			grant = function(): boolean
				return true
			end,
		},
	})
	local deps = {
		DataService = dataService,
		Notify = notify,
		Currency = currency,
		Battlepass = battlepass,
		Analytics = { economy = function() end, custom = function() end },
	}
	local receipts = world.require("src/server/Services/MonetizationService/Receipts")
	receipts.Init(deps)
	local purchases = world.require("src/server/Services/MonetizationService/Purchases")
	purchases.Init(deps)

	fixture.ask = function(productKey: string)
		purchases.prompt(player, "Product", productKey)
	end

	fixture.deliver = function(productKey: string, purchaseId: string): any
		return receipts.process({
			PlayerId = USER_ID,
			ProductId = config.Products[productKey].Id,
			PurchaseId = purchaseId,
		})
	end
	return fixture
end

local function keysOf(toasts: { Toast }): { string }
	local keys = {}
	for _, toast in ipairs(toasts) do
		table.insert(keys, toast.Key)
	end
	return keys
end

local function toastOf(toasts: { Toast }, key: string): Toast?
	for _, toast in ipairs(toasts) do
		if toast.Key == key then
			return toast
		end
	end
	return nil
end

local MAX = BattlepassConfig.MaxTier
local PER_TIER = MonetizationConfig.Products[TIER_SKIP].CompensationFolios :: number
local TIERS = MonetizationConfig.Products[TIER_SKIP].Amount :: number

describe("a tier skip receipt", function()
	it("grants every tier below the last one and keeps the XP already earned towards the next", function()
		local fixture = setup(10, 40)
		expect(fixture.deliver(TIER_SKIP, "below")).toBe(GRANTED)
		local season = fixture.data.Battlepass[SEASON]
		expect(season.Tier).toBe(10 + TIERS)
		expect(season.XP).toBe(40)
		expect(fixture.data.Currency.Folios).toBe(0)
		expect(toastOf(fixture.toasts, "purchase.tiersPastLast")).toBeNil()
	end)

	it("pays the whole skip in Folios when the pass already stands at the last tier, and settles once (R2)", function()
		local fixture = setup(MAX, 0)
		expect(fixture.deliver(TIER_SKIP, "at-max")).toBe(GRANTED)
		expect(fixture.data.Battlepass[SEASON].Tier).toBe(MAX)
		expect(fixture.data.Currency.Folios).toBe(PER_TIER * TIERS)
		expect(fixture.data.Purchases.Receipts).toEqual({ "at-max" })
		expect(fixture.saves).toBe(1)
		local paid = toastOf(fixture.toasts, "purchase.tiersPastLast")
		assert(paid ~= nil, "the player is never told where the purchase went")
		expect((paid.Params :: any).amount).toBe(PER_TIER * TIERS)
		-- No tier moved, so nothing says one did.
		expect(toastOf(fixture.toasts, "purchase.tiersGranted")).toBeNil()

		-- Roblox delivering the same receipt again (a join, a lost answer) pays nothing twice.
		expect(fixture.deliver(TIER_SKIP, "at-max")).toBe(GRANTED)
		expect(fixture.data.Currency.Folios).toBe(PER_TIER * TIERS)
		expect(fixture.data.Purchases.Receipts).toEqual({ "at-max" })
	end)

	it("settles a skip whose dialog opened a tier short of the last one (R2)", function()
		-- The server refuses a skip at the last tier only when the dialog opens. A match can finish the
		-- pass while the dialog is open, and the receipt then finds it full.
		local fixture = setup(MAX - 1, 0)
		fixture.ask(TIER_SKIP)
		expect(#fixture.opened).toBe(1)
		fixture.data.Battlepass[SEASON].Tier = MAX
		expect(fixture.deliver(TIER_SKIP, "raced")).toBe(GRANTED)
		expect(fixture.data.Currency.Folios).toBe(PER_TIER * TIERS)

		fixture.ask(TIER_SKIP)
		expect(#fixture.opened).toBe(1)
		expect(toastOf(fixture.toasts, "purchase.unavailable")).never.toBeNil()
	end)

	it("pays each tier past the last one in Folios between tiers 46 and 49 (R14)", function()
		for tier = MAX - TIERS + 1, MAX - 1 do
			local fixture = setup(tier, 25)
			expect(fixture.deliver(TIER_SKIP, "near-" .. tier)).toBe(GRANTED)
			local fits = MAX - tier
			expect(fixture.data.Battlepass[SEASON].Tier).toBe(MAX)
			expect(fixture.data.Currency.Folios).toBe(PER_TIER * (TIERS - fits))
			local tiers = toastOf(fixture.toasts, "purchase.tiersGranted")
			assert(tiers ~= nil, "the tiers that fit are never announced")
			expect((tiers.Params :: any).tiers).toBe(fits)
			local paid = toastOf(fixture.toasts, "purchase.tiersPastLast")
			assert(paid ~= nil, "the tiers past the last one are paid without a word")
			expect((paid.Params :: any).amount).toBe(PER_TIER * (TIERS - fits))
			-- The tiers first, then what they could not hold.
			local order = keysOf(fixture.toasts)
			local first = table.find(order, "purchase.tiersGranted") :: number
			local second = table.find(order, "purchase.tiersPastLast") :: number
			expect(first).toBeLessThan(second)
		end
	end)

	it("moves no tier and stays pending when what is past the last tier cannot be paid", function()
		-- The retried receipt must start from the same pass: had the tiers moved first, it would find fewer
		-- to give and pay the rest again, or give them twice.
		local fixture = setup(MAX - 2, 25)
		fixture.config.Products[TIER_SKIP].CompensationFolios = nil
		expect(fixture.deliver(TIER_SKIP, "unpaid")).never.toBe(GRANTED)
		expect(fixture.data.Battlepass[SEASON].Tier).toBe(MAX - 2)
		expect(fixture.data.Battlepass[SEASON].XP).toBe(25)
		expect(fixture.data.Purchases.Receipts).toEqual({})
		expect(fixture.toasts).toEqual({})
	end)

	it("pays past the last tier at the VIP rate, the rate every Folios product is paid at", function()
		local fixture = setup(MAX, 0)
		fixture.data.Passes.Vip = true
		expect(fixture.deliver(TIER_SKIP, "vip")).toBe(GRANTED)
		expect(fixture.data.Currency.Folios).toBeGreaterThan(PER_TIER * TIERS)
		local paid = toastOf(fixture.toasts, "purchase.tiersPastLast")
		assert(paid ~= nil, "the VIP is paid without a word")
		expect((paid.Params :: any).amount).toBe(fixture.data.Currency.Folios)
	end)
end)

describe("a Premium Pass receipt", function()
	it("opens the premium track", function()
		local fixture = setup(3, 0)
		expect(fixture.deliver("PremiumPass", "first")).toBe(GRANTED)
		expect(fixture.data.Battlepass[SEASON].Premium).toBe(true)
		expect(fixture.data.Currency.Folios).toBe(0)
	end)

	it("pays the pass in Folios when it lands on a player who already has the track, and settles once (R11)", function()
		-- The dialog is refused to a Premium player; a second dialog confirmed before the first receipt
		-- arrived is how a receipt still lands on one.
		local fixture = setup(3, 0)
		fixture.ask("PremiumPass")
		fixture.ask("PremiumPass")
		expect(#fixture.opened).toBe(2)
		expect(fixture.deliver("PremiumPass", "first")).toBe(GRANTED)
		expect(fixture.deliver("PremiumPass", "second")).toBe(GRANTED)
		local worth = MonetizationConfig.Products.PremiumPass.CompensationFolios :: number
		expect(fixture.data.Currency.Folios).toBe(worth)
		local paid = toastOf(fixture.toasts, "purchase.premiumOwnedFolios")
		assert(paid ~= nil, "the second pass is paid without a word")
		expect((paid.Params :: any).amount).toBe(worth)

		expect(fixture.deliver("PremiumPass", "second")).toBe(GRANTED)
		expect(fixture.data.Currency.Folios).toBe(worth)
		expect(fixture.data.Purchases.Receipts).toEqual({ "first", "second" })

		-- Once Premium, the dialog does not open again.
		fixture.ask("PremiumPass")
		expect(#fixture.opened).toBe(2)
	end)
end)

describe("what a receipt pays instead of what it can no longer deliver (D-202)", function()
	-- Folios one Robux buys in each pack: FolioSmall gives the fewest, FolioLarge the most.
	local fewest, most = math.huge, 0
	for _, product in pairs(MonetizationConfig.Products) do
		if product.Kind == "Folios" then
			local rate = (product.Amount :: number) / product.PriceRobux
			fewest = math.min(fewest, rate)
			most = math.max(most, rate)
		end
	end
	-- What one undeliverable unit of each kind cost: a tier of a skip, or the whole pass.
	local UNIT: { [string]: (product: MonetizationConfig.ProductDef) -> number } = {
		TierSkip = function(product: MonetizationConfig.ProductDef): number
			return product.PriceRobux / (product.Amount :: number)
		end,
		PremiumPass = function(product: MonetizationConfig.ProductDef): number
			return product.PriceRobux
		end,
	}

	it("is worth at least what the same Robux buy in Folios, and no more than the biggest pack gives", function()
		local checked: { [string]: boolean } = {}
		for key, product in pairs(MonetizationConfig.Products) do
			local unit = UNIT[product.Kind]
			if unit ~= nil then
				checked[product.Kind] = true
				local each = product.CompensationFolios
				assert(each ~= nil, key .. " has nothing to pay what it cannot deliver with")
				expect(each % 10).toBe(0)
				local robux = unit(product)
				if each < robux * fewest or each > robux * most then
					error(
						("%s pays %d Folios a unit, outside %.0f to %.0f"):format(
							key,
							each,
							robux * fewest,
							robux * most
						)
					)
				end
			end
		end
		expect(checked).toEqual({ TierSkip = true, PremiumPass = true })
	end)
end)

return nil
