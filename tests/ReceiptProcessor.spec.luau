--!strict
local Harness = require("./harness")
local ReceiptProcessor = require("../src/shared/Pure/ReceiptProcessor")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type World = {
	profiles: { [number]: any },
	grants: { string },
	saves: number,
	failSave: boolean,
	failGrant: boolean,
	logs: { string },
}

local products = {
	[101] = { key = "FolioSmall", def = { Kind = "Folios", Amount = 1000 } },
	[102] = { key = "XpBoost1h", def = { Kind = "XpBoost", Minutes = 60 } },
}

local function makeWorld(): (World, ReceiptProcessor.Deps)
	local world: World = { profiles = {}, grants = {}, saves = 0, failSave = false, failGrant = false, logs = {} }
	local deps: ReceiptProcessor.Deps = {
		findProduct = function(productId: number)
			local entry = products[productId]
			if entry == nil then
				return nil, nil
			end
			return entry.key, entry.def
		end,
		getProfile = function(userId: number)
			return world.profiles[userId]
		end,
		isRecorded = function(data: any, purchaseId: string)
			return table.find(data.Receipts, purchaseId) ~= nil
		end,
		record = function(data: any, purchaseId: string)
			table.insert(data.Receipts, purchaseId)
		end,
		grant = function(data: any, productKey: string, product: ReceiptProcessor.ProductDef)
			if world.failGrant then
				return false
			end
			table.insert(world.grants, productKey)
			if product.Kind == "Folios" then
				data.Folios += product.Amount :: number
			end
			return true
		end,
		save = function()
			world.saves += 1
			return not world.failSave
		end,
		log = function(message: string)
			table.insert(world.logs, message)
		end,
	}
	return world, deps
end

local function receipt(purchaseId: string, productId: number)
	return { PlayerId = 7, PurchaseId = purchaseId, ProductId = productId }
end

describe("ReceiptProcessor", function()
	it("grants once and is idempotent on retries", function()
		local world, deps = makeWorld()
		world.profiles[7] = { Receipts = {}, Folios = 0 }
		local decision, reason = ReceiptProcessor.process(receipt("p1", 101), deps)
		expect(decision).toBe("PurchaseGranted")
		expect(reason).toBe("granted")
		expect(world.profiles[7].Folios).toBe(1000)
		expect(world.grants).toEqual({ "FolioSmall" })
		expect(world.saves).toBe(1)

		decision, reason = ReceiptProcessor.process(receipt("p1", 101), deps)
		expect(decision).toBe("PurchaseGranted")
		expect(reason).toBe("already granted")
		expect(world.profiles[7].Folios).toBe(1000)
		expect(world.grants).toHaveLength(1)
	end)

	it("defers when the profile is not loaded", function()
		local world, deps = makeWorld()
		local decision = ReceiptProcessor.process(receipt("p2", 101), deps)
		expect(decision).toBe("NotProcessedYet")
		expect(world.grants).toHaveLength(0)
	end)

	it("defers unknown products without granting", function()
		local world, deps = makeWorld()
		world.profiles[7] = { Receipts = {}, Folios = 0 }
		local decision = ReceiptProcessor.process(receipt("p3", 999), deps)
		expect(decision).toBe("NotProcessedYet")
		expect(world.logs).toHaveLength(1)
		expect(world.grants).toHaveLength(0)
	end)

	it("defers when the grant fails and does not record", function()
		local world, deps = makeWorld()
		world.profiles[7] = { Receipts = {}, Folios = 0 }
		world.failGrant = true
		local decision = ReceiptProcessor.process(receipt("p4", 102), deps)
		expect(decision).toBe("NotProcessedYet")
		expect(world.profiles[7].Receipts).toEqual({})
	end)

	it("defers when the save fails, then grants on retry without a double grant", function()
		local world, deps = makeWorld()
		world.profiles[7] = { Receipts = {}, Folios = 0 }
		world.failSave = true
		local decision = ReceiptProcessor.process(receipt("p5", 101), deps)
		expect(decision).toBe("NotProcessedYet")
		expect(world.profiles[7].Folios).toBe(1000)
		expect(world.profiles[7].Receipts).toEqual({ "p5" })

		world.failSave = false
		decision = ReceiptProcessor.process(receipt("p5", 101), deps)
		expect(decision).toBe("PurchaseGranted")
		expect(world.profiles[7].Folios).toBe(1000)
		expect(world.grants).toHaveLength(1)
	end)
end)
