--!strict
-- A DataStore outage the players are told of, and that pauses the Robux (E3-S6, D-254). ProfileStore says when
-- its DataStore calls keep failing (OnCriticalToggle), when one call failed (OnError) and when a key held no
-- profile and was overwritten (OnOverwrite); nothing listened. DataService, ShopService and the real
-- MonetizationService run here in a pretend server (tests/server.luau) whose ProfileStore fires those signals as
-- the vendored one does, and a pretend MarketplaceService records every dialog that would have opened.
local Engine = require("./engine")
local Harness = require("./harness")
local Server = require("./server")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local VENDOR = "src/server/Vendor/ProfileStore.luau"
-- The store DataService opens: its name is the one the warnings must carry.
local STORE_NAME = "JutsuBattlegrounds_v2"
local BALANCE = 20000

type Prompt = { Player: any, Kind: string, Id: number }
type Outage = {
	setup: Server.Services,
	prompts: { Prompt },
	a: any,
	b: any,
	-- The first item of today's rotation, and its price in Folios.
	item: string,
	price: number,
}

local function marketplace(prompts: { Prompt }): any
	return {
		PromptGamePassPurchase = function(_self: any, player: any, id: number)
			table.insert(prompts, { Player = player, Kind = "Pass", Id = id })
		end,
		PromptProductPurchase = function(_self: any, player: any, id: number)
			table.insert(prompts, { Player = player, Kind = "Product", Id = id })
		end,
		PromptGamePassPurchaseFinished = Engine.signal(),
		PromptProductPurchaseFinished = Engine.signal(),
		UserOwnsGamePassAsync = function(_self: any, _userId: number, _passId: number): boolean
			return false
		end,
	}
end

-- Two players on a server whose catalog has every id, with the real MonetizationService behind PromptPurchase.
local function outage(): Outage
	local prompts: { Prompt } = {}
	local setup = Server.services({ Services = { MarketplaceService = marketplace(prompts) } })
	local catalog = setup.world.require("src/shared/Config/MonetizationConfig")
	local next = 1000
	for _, group in ipairs({ catalog.Passes, catalog.Products }) do
		local keys: { string } = {}
		for key in pairs(group) do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			next += 1
			group[key].Id = next
		end
	end
	local monetization = setup.world.require("src/server/Services/MonetizationService")
	monetization.Init({
		Registry = setup.registry,
		DataService = setup.data,
		Notify = setup.notify,
		Currency = setup.currency,
		Battlepass = {
			addXp = function(_player: any, _amount: number) end,
			isPremium = function(_player: any): boolean
				return false
			end,
			setPremium = function(_player: any, _value: boolean) end,
			grantXpBoost = function(_player: any, _minutes: number): boolean
				return true
			end,
		},
		Loadout = setup.loadout,
		Cosmetic = setup.cosmetic,
		Shop = setup.shop,
		Analytics = {
			economy = function() end,
			custom = function() end,
		},
	})
	monetization.Start()
	local a = setup.world:join(301, "Ada")
	local b = setup.world:join(302, "Bea")
	setup.data.get(a).Currency.Folios = BALANCE
	local snapshot = setup.shop.getSnapshot(a)
	assert(snapshot ~= nil and #snapshot.Entries > 0, "today's rotation is empty: this spec would buy nothing")
	return {
		setup = setup,
		prompts = prompts,
		a = a,
		b = b,
		item = snapshot.Entries[1].CosmeticId,
		price = snapshot.Entries[1].PriceFolios,
	}
end

-- How many times `player` was sent `key`.
local function told(setup: Server.Services, player: any, key: string): number
	local count = 0
	for _, notice in ipairs(setup.notices) do
		if notice.Player == player and notice.Key == key then
			count += 1
		end
	end
	return count
end

-- Every Robux purchase a player can ask for: a pass, a product, and an item of today's rotation.
local function askForEverything(state: Outage, player: any)
	state.setup.handlers.PromptPurchase(player, "Pass", "Vip")
	state.setup.handlers.PromptPurchase(player, "Product", "FolioSmall")
	state.setup.handlers.PromptPurchase(player, "Cosmetic", state.item)
end

describe("a DataStore outage (ProfileStore's critical state)", function()
	it("opens every Robux purchase while saving works", function()
		-- The fixture itself: without this, the refusals below could come from a catalog that sells nothing.
		local state = outage()
		askForEverything(state, state.a)
		expect(#state.prompts).toBe(3)
	end)

	it("tells every player once that saving is delayed, however often ProfileStore says so", function()
		local state = outage()
		state.setup.world.store:critical(true)
		state.setup.world.store:critical(true)
		expect(told(state.setup, state.a, "save.delayed")).toBe(1)
		expect(told(state.setup, state.b, "save.delayed")).toBe(1)
		expect(state.setup.data.isCritical()).toBe(true)
	end)

	it("refuses a pass, a product and a cosmetic in Robux while it lasts, and says why", function()
		local state = outage()
		state.setup.world.store:critical(true)
		askForEverything(state, state.a)
		expect(#state.prompts).toBe(0)
		expect(told(state.setup, state.a, "purchase.savesDelayed")).toBe(3)
		-- Refused before the shop records which item the player wanted: no receipt can come to claim it.
		expect(state.setup.shop.getPurchaseIntent(state.a)).toBeNil()
	end)

	it("keeps a purchase in Folios open", function()
		local state = outage()
		state.setup.world.store:critical(true)
		state.setup.handlers.BuyCosmetic(state.a, state.item)
		local data = state.setup.data.get(state.a)
		expect(data.Currency.Folios).toBe(BALANCE - state.price)
		expect(table.find(data.Cosmetics.Owned, state.item)).never.toBeNil()
		expect(told(state.setup, state.a, "shop.purchased")).toBe(1)
	end)

	it("tells a player who joins during the outage, once their profile is there", function()
		local state = outage()
		state.setup.world.store:critical(true)
		local c = state.setup.world:join(303, "Cyd")
		expect(told(state.setup, c, "save.delayed")).toBe(1)
		state.setup.world.store:critical(true)
		expect(told(state.setup, c, "save.delayed")).toBe(1)
	end)

	it("tells a player whose profile was still loading when it began, once", function()
		-- StartSessionAsync waits on the DataStore, which is exactly what is failing: the player is in the server,
		-- told with everybody, and their load finishing later tells them nothing twice.
		local state = outage()
		state.setup.world.store:stall()
		local c = state.setup.world:join(303, "Cyd")
		expect(state.setup.data.get(c)).toBeNil()
		state.setup.world.store:critical(true)
		state.setup.world.store:resume()
		expect(state.setup.data.get(c)).never.toBeNil()
		expect(told(state.setup, c, "save.delayed")).toBe(1)
	end)

	it("does not tell a player who left during the outage that it ended", function()
		local state = outage()
		state.setup.world.store:critical(true)
		state.setup.world:leave(state.b)
		state.setup.world.store:critical(false)
		expect(told(state.setup, state.a, "save.restored")).toBe(1)
		expect(told(state.setup, state.b, "save.restored")).toBe(0)
	end)

	it("reopens the Robux and says so, once, when saving is back", function()
		local state = outage()
		state.setup.world.store:critical(true)
		state.setup.world.store:critical(false)
		state.setup.world.store:critical(false)
		expect(told(state.setup, state.a, "save.restored")).toBe(1)
		expect(told(state.setup, state.b, "save.restored")).toBe(1)
		expect(state.setup.data.isCritical()).toBe(false)
		askForEverything(state, state.a)
		expect(#state.prompts).toBe(3)
	end)

	it("tells a second outage as it told the first", function()
		local state = outage()
		state.setup.world.store:critical(true)
		state.setup.world.store:critical(false)
		state.setup.world.store:critical(true)
		expect(told(state.setup, state.a, "save.delayed")).toBe(2)
	end)

	it("says nothing of an outage that never began", function()
		local state = outage()
		state.setup.world.store:critical(false)
		expect(told(state.setup, state.a, "save.restored")).toBe(0)
		expect(told(state.setup, state.a, "save.delayed")).toBe(0)
	end)

	it("is told in the player's language", function()
		for _, key in ipairs({ "save.delayed", "save.restored", "purchase.savesDelayed" }) do
			expect(Strings.has(key)).toBe(true)
			expect(Strings.t(key, nil, "fr")).never.toBe(Strings.t(key, nil, "en"))
		end
	end)
end)

describe("what ProfileStore reports of a single key", function()
	local function said(setup: Server.Services, needles: { string }): boolean
		for _, line in ipairs(setup.world.lines) do
			local all = true
			for _, needle in ipairs(needles) do
				if string.find(line, needle, 1, true) == nil then
					all = false
					break
				end
			end
			if all then
				return true
			end
		end
		return false
	end

	it("warns of a failed DataStore call with its store and its key", function()
		local state = outage()
		state.setup.world.store:fail("502: API services rejected request", "Player_301")
		expect(said(state.setup, { "WARN [DataService]", STORE_NAME, "Player_301", "502" })).toBe(true)
	end)

	it("logs an overwritten key as an error, with its store and its key", function()
		local state = outage()
		state.setup.world.store:overwrite("Player_302")
		expect(said(state.setup, { "WARN [DataService] ERROR", STORE_NAME, "Player_302" })).toBe(true)
	end)
end)

describe("the pretend ProfileStore's signals", function()
	-- What tests/server.luau fires is what the vendored module fires: if an update changes an argument's place,
	-- the spec above is listening to a store that no longer exists.
	local source = fs.readFile(VENDOR)

	it("reports an error with its message, store and key, and an overwrite with its store and key", function()
		expect(string.find(source, "OnError:Fire(tostring(error_message), store_name, profile_key)", 1, true)).never.toBeNil()
		expect(string.find(source, "OnOverwrite:Fire(store_name, profile_key)", 1, true)).never.toBeNil()
	end)

	it("toggles its critical state both ways, flag first", function()
		local on = string.find(
			source,
			"ProfileStore.IsCriticalState = true\n\t\t\tProfileStore.OnCriticalToggle:Fire(true)",
			1,
			true
		)
		local off = string.find(
			source,
			"ProfileStore.IsCriticalState = false\n\t\t\tProfileStore.OnCriticalToggle:Fire(false)",
			1,
			true
		)
		expect(on).never.toBeNil()
		expect(off).never.toBeNil()
	end)
end)
