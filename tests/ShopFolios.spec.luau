--!strict
-- A Folios purchase settled by the server, run (tests/engine.luau): the real ShopService and CurrencyService,
-- with the profile, the cosmetic grant and the player's toasts as the only fakes.
--
-- The shop debits first and grants second. A grant that failed after the debit kept the Folios and gave
-- nothing (R12): the purchase must pay the debit back, exactly, and never more than it took.
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
}

local function setup(userId: number): Fixture
	local world = Engine.world()
	local player = world.player
	player.UserId = userId

	local data = {
		Currency = { Folios = BALANCE },
		Cosmetics = { Owned = {} :: { string }, Equipped = {} },
		Passes = {} :: { [string]: boolean },
	}
	local fixture = { data = data, toasts = {} :: { string } } :: any
	local handlers: { [string]: (...any) -> () } = {}
	local dataService = {
		get = function(): any
			return data
		end,
		push = function() end,
		ProfileLoaded = Engine.signal(),
	}
	local currency = world.require("src/server/Services/CurrencyService")
	currency.Init({ DataService = dataService })
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
		Analytics = { economy = function() end },
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

return nil
