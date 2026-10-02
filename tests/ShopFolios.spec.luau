--!strict
-- A Folios purchase settled by the server, run (tests/engine.luau): the real ShopService, CurrencyService and
-- AnalyticsService, with the profile, the cosmetic grant, the player's toasts and Roblox's analytics
-- (tests/analytics.luau) as the only fakes.
--
-- The shop debits first and grants second. A grant that failed after the debit kept the Folios and gave
-- nothing (R12): the purchase must pay the debit back, exactly, and never more than it took.
local Analytics = require("./analytics")
local DeveloperConfig = require("../src/server/Config/DeveloperConfig")
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local BALANCE = 20000
local PLAYER_ID = 7

-- "Delivered": the grant writes the item and throws after, the way a failure past the write would.
type Outcome = "Grant" | "Refuse" | "Throw" | "Delivered"
type Fixture = {
	data: any,
	toasts: { string },
	item: string,
	price: number,
	buy: (outcome: Outcome) -> (),
	-- What reached Roblox's analytics.
	analytics: Analytics.Recorder,
}

local function setup(userId: number): Fixture
	local analytics = Analytics.recorder()
	local world = Engine.world({ Services = analytics.services })
	local player = world.player
	player.UserId = userId
	-- The head count AnalyticsService sizes the server's budget by.
	world.game:GetService("Players").GetPlayers = function(_self: any): { any }
		return { player }
	end

	local data = {
		Currency = { Folios = BALANCE },
		Cosmetics = { Owned = {} :: { string }, Equipped = {} },
		Passes = {} :: { [string]: boolean },
	}
	local fixture = { data = data, toasts = {} :: { string }, analytics = analytics } :: any
	local handlers: { [string]: (...any) -> () } = {}
	local dataService = {
		get = function(): any
			return data
		end,
		push = function() end,
		ProfileLoaded = Engine.signal(),
	}
	local currency = world.require("src/server/Services/CurrencyService")
	currency.Init({ DataService = dataService, Analytics = world.require("src/server/Services/AnalyticsService") })
	local outcome: Outcome = "Grant"
	local shop = world.require("src/server/Services/ShopService")
	shop.Init({
		Registry = {
			on = function(name: string, handler: (...any) -> ())
				handlers[name] = handler
			end,
			fire = function() end,
		},
		DataService = dataService,
		Notify = {
			send = function(_player: any, key: string)
				table.insert(fixture.toasts, key)
			end,
		},
		Currency = currency,
		Cosmetic = {
			grant = function(_player: any, cosmeticId: string): boolean
				if outcome == "Throw" then
					error("CosmeticService broke")
				end
				if outcome == "Refuse" then
					return false
				end
				table.insert(data.Cosmetics.Owned, cosmeticId)
				if outcome == "Delivered" then
					error("CosmeticService broke after the write")
				end
				return true
			end,
		},
	})
	shop.Start()

	local snapshot = shop.getSnapshot(player)
	assert(snapshot ~= nil and #snapshot.Entries > 0, "today's rotation is empty: this spec would buy nothing")
	fixture.item = snapshot.Entries[1].CosmeticId
	fixture.price = snapshot.Entries[1].PriceFolios
	fixture.buy = function(next: Outcome)
		outcome = next
		handlers.BuyCosmetic(player, fixture.item)
	end
	return fixture
end

describe("a Folios purchase in the shop", function()
	it("debits the price and grants the item", function()
		local fixture = setup(PLAYER_ID)
		fixture.buy("Grant")
		expect(fixture.data.Currency.Folios).toBe(BALANCE - fixture.price)
		expect(fixture.data.Cosmetics.Owned).toEqual({ fixture.item })
		expect(fixture.toasts).toEqual({ "shop.purchased" })
	end)

	it("pays the debit back when the grant is refused, and says the purchase failed (R12)", function()
		local fixture = setup(PLAYER_ID)
		fixture.buy("Refuse")
		expect(fixture.data.Currency.Folios).toBe(BALANCE)
		expect(fixture.data.Cosmetics.Owned).toEqual({})
		expect(fixture.toasts).toEqual({ "purchase.failed" })
	end)

	it("pays the debit back when the grant throws (R12)", function()
		local fixture = setup(PLAYER_ID)
		fixture.buy("Throw")
		expect(fixture.data.Currency.Folios).toBe(BALANCE)
		expect(fixture.toasts).toEqual({ "purchase.failed" })
	end)

	it("keeps the debit when the grant throws after writing the item: never the item and the Folios both", function()
		local fixture = setup(PLAYER_ID)
		fixture.buy("Delivered")
		expect(fixture.data.Cosmetics.Owned).toEqual({ fixture.item })
		expect(fixture.data.Currency.Folios).toBe(BALANCE - fixture.price)
		expect(fixture.toasts).toEqual({ "shop.purchased" })
	end)

	it("pays a VIP back what was taken, not the VIP rate a reward is paid at", function()
		local fixture = setup(PLAYER_ID)
		fixture.data.Passes.Vip = true
		fixture.buy("Refuse")
		expect(fixture.data.Currency.Folios).toBe(BALANCE)
	end)

	it("pays nothing back to a developer, who was not debited (D-129)", function()
		expect(DeveloperConfig.UnlimitedFolios).toBe(true)
		local fixture = setup(DeveloperConfig.UserIds[1])
		fixture.buy("Refuse")
		expect(fixture.data.Currency.Folios).toBe(BALANCE)
		fixture.buy("Grant")
		expect(fixture.data.Currency.Folios).toBe(BALANCE)
		expect(fixture.data.Cosmetics.Owned).toEqual({ fixture.item })
	end)
end)

-- The shop reported its own sink as well as CurrencyService's: every purchase counted twice (E8-S1).
describe("what the Economy dashboards learn of a Folios purchase (E8-S1)", function()
	-- The economy events that reached Roblox, as { flow, amount, balance, transaction, item }.
	local function economy(fixture: Fixture): { { any } }
		local found = {}
		for _, call in ipairs(fixture.analytics:of("LogEconomyEvent")) do
			local args = call.Args
			table.insert(found, { args[1].Name, args[3], args[4], args[5], args[6] })
		end
		return found
	end

	it("is one sink, under Shop, with the article as its item", function()
		local fixture = setup(PLAYER_ID)
		fixture.buy("Grant")
		expect(economy(fixture)).toEqual({
			{ "Sink", fixture.price, BALANCE - fixture.price, "Shop", fixture.item },
		})
	end)

	it("is a sink and the source that pays it back when the grant fails", function()
		local fixture = setup(PLAYER_ID)
		fixture.buy("Refuse")
		expect(economy(fixture)).toEqual({
			{ "Sink", fixture.price, BALANCE - fixture.price, "Shop", fixture.item },
			{ "Source", fixture.price, BALANCE, "Shop", fixture.item },
		})
	end)

	it("is nothing for a developer, whose purchase moved no Folio (D-129)", function()
		local fixture = setup(DeveloperConfig.UserIds[1])
		fixture.buy("Refuse")
		fixture.buy("Grant")
		expect(economy(fixture)).toEqual({})
	end)
end)

return nil
