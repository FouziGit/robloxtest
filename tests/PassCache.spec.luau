--!strict
-- Studio test purchases, and a pass cache that follows Roblox (D-211). In Studio with API access a test
-- purchase wrote into the real profile, and a cached pass never left the cache again (docs/QA.md R9).
--
-- The cache rule is pure (PassCache); the real Passes and Receipts modules are then run over a pretend
-- MarketplaceService, on a Studio server and on a live one, and what is checked is what reaches the profile.
local ChatConfig = require("../src/shared/Config/ChatConfig")
local Engine = require("./engine")
local Harness = require("./harness")
local LogStub = require("./logstub")
local PassCache = require("../src/shared/Pure/PassCache")
local StudioConfig = require("../src/server/Config/StudioConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

-- Asset ids given to the catalog inside the pretend world (the real config ships them at 0).
local PASS_IDS = { Vip = 1001, LoadoutSlots = 1002, Orpiment = 1003, SkinPack = 1004 }
local FOLIO_SMALL_ID = 2001

type Options = {
	studio: boolean,
	persist: boolean?,
	-- Roblox's answer per pass key; a pass left out is never asked about.
	owns: { [string]: boolean }?,
	passes: { [string]: boolean }?,
}

type Shop = {
	Passes: any,
	Receipts: any,
	player: any,
	data: any,
	lines: { string },
	calls: { [string]: { any } },
	saves: number,
}

-- The real Passes and Receipts on a server that is Studio or not, for one player whose profile holds
-- `passes`.
local function shop(options: Options): Shop
	local Log, lines = LogStub.new()
	local market = {
		UserOwnsGamePassAsync = function(_self: any, _userId: number, passId: number): boolean
			for key, id in pairs(PASS_IDS) do
				if id == passId and options.owns ~= nil and options.owns[key] ~= nil then
					return options.owns[key]
				end
			end
			error("the spec did not expect a question about pass " .. passId)
		end,
	}
	local world = Engine.world({
		Services = { MarketplaceService = market },
		Stubs = {
			["src/shared/Util/Log"] = Log,
			["src/server/Config/StudioConfig"] = {
				PersistTestPurchases = options.persist == true,
				WriteLadders = false,
			},
		},
	})
	world.game:GetService("RunService").IsStudio = function(): boolean
		return options.studio
	end
	local catalog = world.require("src/shared/Config/MonetizationConfig")
	for key, id in pairs(PASS_IDS) do
		catalog.Passes[key].Id = id
	end
	catalog.Products.FolioSmall.Id = FOLIO_SMALL_ID

	local players = world.game:GetService("Players")
	local player = Engine.instance("Player", players)
	player.Name = "Buyer"
	player.UserId = 42
	players.GetPlayerByUserId = function(_self: any, userId: number): any
		return if userId == 42 then player else nil
	end

	local data = {
		Passes = table.clone(options.passes or {}),
		Purchases = { Receipts = {}, ProductCounts = {} },
		Currency = { Folios = 0 },
	}
	local session: Shop
	local calls: { [string]: { any } } = {}
	local function called(name: string, value: any)
		calls[name] = calls[name] or {}
		table.insert(calls[name], value)
	end
	local deps = {
		DataService = {
			get = function(_player: any): any
				return data
			end,
			waitFor = function(_player: any, _timeout: number?): any
				return data
			end,
			push = function(_player: any, section: string)
				called("push", section)
			end,
			recordReceipt = function(_player: any, purchaseId: string): boolean
				table.insert(data.Purchases.Receipts, purchaseId)
				return true
			end,
			saveNow = function(_player: any): boolean
				session.saves += 1
				return true
			end,
			isActive = function(_player: any): boolean
				return true
			end,
		},
		Loadout = {
			grantPigment = function(_player: any, pigmentId: string): boolean
				called("grantPigment", pigmentId)
				return true
			end,
			setExtraSlots = function(_player: any, count: number): boolean
				called("setExtraSlots", count)
				return true
			end,
		},
		Cosmetic = {
			grant = function(_player: any, cosmeticId: string): boolean
				called("cosmetic", cosmeticId)
				return true
			end,
		},
		Currency = {
			add = function(_player: any, amount: number, _reason: string): number
				called("folios", amount)
				data.Currency.Folios += amount
				return amount
			end,
			get = function(_player: any): number
				return data.Currency.Folios
			end,
		},
		Notify = {
			send = function(_player: any, key: string)
				called("notify", key)
			end,
		},
		Analytics = { custom = function() end, economy = function() end },
		Battlepass = {},
		Progression = {},
		Shop = {},
		Match = {},
		Registry = {},
	}
	local Passes = world.require("src/server/Services/MonetizationService/Passes")
	local Receipts = world.require("src/server/Services/MonetizationService/Receipts")
	world.require("src/server/Services/MonetizationService/Sandbox").Init(deps)
	Passes.Init(deps)
	Receipts.Init(deps)
	session = {
		Passes = Passes,
		Receipts = Receipts,
		player = player,
		data = data,
		lines = lines,
		calls = calls,
		saves = 0,
	}
	return session
end

local function count(session: Shop, name: string): number
	local list = session.calls[name]
	return if list == nil then 0 else #list
end

local function sent(session: Shop, key: string): boolean
	return table.find(session.calls.notify or {}, key) ~= nil
end

local function receipt(session: Shop, purchaseId: string): any
	return session.Receipts.process({ PlayerId = 42, ProductId = FOLIO_SMALL_ID, PurchaseId = purchaseId })
end

describe("the pass cache rule", function()
	it("takes in what Roblox says is owned and lets go of what it held and Roblox says is not", function()
		local cache = { Vip = true, SkinPack = true }
		local added, removed =
			PassCache.reconcile(cache, { Vip = false, Orpiment = true, LoadoutSlots = true }, table.clone(cache))
		expect(added).toEqual({ "LoadoutSlots", "Orpiment" })
		expect(removed).toEqual({ "Vip" })
		expect(cache).toEqual({ SkinPack = true, Orpiment = true, LoadoutSlots = true })
	end)

	it("keeps whatever Roblox gave no answer for", function()
		local cache = { Vip = true }
		local added, removed = PassCache.reconcile(cache, {}, table.clone(cache))
		expect(#added + #removed).toBe(0)
		expect(cache).toEqual({ Vip = true })
	end)

	it("never lets go of a pass bought while Roblox was being asked", function()
		-- Asked with an empty cache; Vip was bought before the answer, "not owned", came back.
		local cache = { Vip = true }
		local _added, removed = PassCache.reconcile(cache, { Vip = false }, {})
		expect(#removed).toBe(0)
		expect(cache).toEqual({ Vip = true })
	end)

	it("ships with Studio test purchases kept out of the profile", function()
		expect(StudioConfig.PersistTestPurchases).toBe(false)
	end)
end)

describe("a Studio test purchase", function()
	it("of a pass is told and logged, and writes nothing into the profile", function()
		local session = shop({ studio = true })
		session.Passes.onPurchaseFinished(session.player, PASS_IDS.Vip, true)
		session.Passes.onPurchaseFinished(session.player, PASS_IDS.SkinPack, true)
		expect(session.data.Passes).toEqual({})
		expect(session.saves).toBe(0)
		expect(count(session, "cosmetic")).toBe(0)
		expect(count(session, "push")).toBe(0)
		expect(session.player:GetAttribute(ChatConfig.VipAttribute)).toBeNil()
		expect(sent(session, "purchase.sandboxed")).toBe(true)
		expect(sent(session, "purchase.passGranted")).toBe(false)
		expect(#session.lines).toBeGreaterThan(0)
	end)

	it("of a product is acknowledged to Roblox and grants nothing", function()
		local session = shop({ studio = true })
		expect(receipt(session, "test-1")).toBe(roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(count(session, "folios")).toBe(0)
		expect(session.data.Currency.Folios).toBe(0)
		expect(session.data.Purchases.Receipts).toEqual({})
		expect(session.saves).toBe(0)
		expect(sent(session, "purchase.sandboxed")).toBe(true)
	end)

	it("never sneaks into the cache through the recheck of a closed dialog", function()
		local session = shop({ studio = true, owns = { Vip = true } })
		session.Passes.onPurchaseFinished(session.player, PASS_IDS.Vip, false)
		expect(session.data.Passes).toEqual({})
	end)

	it("is granted and saved as on a live server once StudioConfig.PersistTestPurchases is on", function()
		local session = shop({ studio = true, persist = true })
		session.Passes.onPurchaseFinished(session.player, PASS_IDS.Vip, true)
		expect(session.data.Passes).toEqual({ Vip = true })
		expect(session.saves).toBe(1)
		expect(receipt(session, "test-2")).toBe(roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(count(session, "folios")).toBe(1)
	end)
end)

describe("a purchase on a live server", function()
	it("of a pass is cached, applied and saved at once", function()
		local session = shop({ studio = false })
		session.Passes.onPurchaseFinished(session.player, PASS_IDS.Vip, true)
		expect(session.data.Passes).toEqual({ Vip = true })
		expect(session.saves).toBe(1)
		expect(session.player:GetAttribute(ChatConfig.VipAttribute)).toBe(true)
		expect(sent(session, "purchase.passGranted")).toBe(true)
	end)

	it("of a product is granted", function()
		local session = shop({ studio = false })
		expect(receipt(session, "live-1")).toBe(roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(count(session, "folios")).toBe(1)
		expect(session.data.Purchases.Receipts).toEqual({ "live-1" })
	end)

	it("closed without a sale on a pass already owned takes the pass in", function()
		local session = shop({ studio = false, owns = { Vip = true } })
		session.Passes.onPurchaseFinished(session.player, PASS_IDS.Vip, false)
		expect(session.data.Passes).toEqual({ Vip = true })
		expect(sent(session, "purchase.passGranted")).toBe(true)
	end)
end)

describe("the pass cache at join", function()
	it("lets go of a pass Roblox says the player does not own, with what it gave while held", function()
		local session = shop({
			studio = true,
			passes = { Vip = true, LoadoutSlots = true, SkinPack = true },
			owns = { Vip = false, LoadoutSlots = false, SkinPack = true, Orpiment = false },
		})
		session.Passes.sync(session.player)
		expect(session.data.Passes).toEqual({ SkinPack = true })
		expect(session.player:GetAttribute(ChatConfig.VipAttribute)).toBeNil()
		expect(session.calls.setExtraSlots).toEqual({ 0 })
		-- What stays is still applied: the skin pack's cosmetics are granted again (idempotent).
		expect(count(session, "cosmetic")).toBeGreaterThan(0)
	end)

	it("takes in a pass Roblox says the player owns", function()
		local session = shop({
			studio = false,
			owns = { Vip = false, LoadoutSlots = false, SkinPack = false, Orpiment = true },
		})
		session.Passes.sync(session.player)
		expect(session.data.Passes).toEqual({ Orpiment = true })
		expect(session.calls.grantPigment).toEqual({ "Orpiment" })
	end)
end)
