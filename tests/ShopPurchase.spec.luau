--!strict
-- A Folios purchase in the Shop, run (tests/engine.luau): the real Purchase, ConfirmSheet and Button.
--
-- Buy stayed live after "Acquired!" for the 1.2 s before the sheet went, and through the sheet's slide away
-- after Cancel: a tap then sent BuyCosmetic again. The first came back as purchase.alreadyOwned and shook the
-- sheet that had just stamped the item; the second bought what the player had just cancelled, with nothing
-- on screen to say so.
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ITEM = "BlankHeadband"
local ACQUIRED_SECONDS = 1.2

type Fixture = {
	world: any,
	purchases: any,
	data: any,
	notified: any,
	card: any,
	bought: { string },
	toasts: { string },
}

local function setup(folios: number): Fixture
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		Services = {
			ContextActionService = {
				BindActionAtPriority = function() end,
				UnbindAction = function() end,
			},
		},
	})
	local Purchase = world.require("src/ui/screens/shop/Purchase")
	local screen = Engine.instance("ScreenGui", world.playerGui)
	local card = Engine.instance("Frame", screen)
	local bought: { string } = {}
	local toasts: { string } = {}
	local notified = Engine.signal()
	local data = { Currency = { Folios = folios }, Cosmetics = { Owned = {} } }
	local purchases = Purchase.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
		},
		RemoteClient = {
			fire = function(name: string, id: string)
				if name == "BuyCosmetic" then
					table.insert(bought, id)
				end
			end,
		},
		HudController = {
			Notified = notified,
			showLocalToast = function(key: string)
				table.insert(toasts, key)
			end,
		},
		Card = card,
		ShowFolios = function() end,
	})
	purchases:Ask({
		CosmeticId = ITEM,
		NameKey = "cosmetic." .. ITEM,
		Slot = "Title",
		Rarity = "Common",
		PriceFolios = 100,
		ProductKey = "",
		Owned = false,
	})
	world:advance(0.5)
	return {
		world = world,
		purchases = purchases,
		data = data,
		notified = notified,
		card = card,
		bought = bought,
		toasts = toasts,
	}
end

-- The sheet's answer called `word` (its buttons read their Localize key here).
local function answer(fixture: Fixture, word: string): any
	for _, child in ipairs(fixture.card:GetDescendants()) do
		if child:IsA("TextButton") then
			for _, label in ipairs(child:GetDescendants()) do
				if label:IsA("TextLabel") and label.Text == word then
					return child
				end
			end
		end
	end
	return nil
end

local function sheetOpen(fixture: Fixture): boolean
	return fixture.card:FindFirstChild("ConfirmSheet") ~= nil
end

describe("a confirm sheet closing, run", function()
	it("takes no answer while it slides away", function()
		local world = Engine.world({
			Stubs = Engine.interfaceStubs(),
			Services = {
				ContextActionService = {
					BindActionAtPriority = function() end,
					UnbindAction = function() end,
				},
			},
		})
		local ConfirmSheet = world.require("src/ui/components/ConfirmSheet")
		local card = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
		local answers = {}
		local sheet = ConfirmSheet.new({
			Title = "",
			Body = "",
			Confirm = { Text = "yes" },
			Cancel = { Text = "no" },
			OnConfirm = function()
				table.insert(answers, "yes")
			end,
			OnCancel = function()
				table.insert(answers, "no")
			end,
			Parent = card,
		})
		world:advance(0.5)
		sheet:Close()
		world:advance(0.1)
		sheet.ConfirmButton.Instance.Activated:Fire()
		sheet.CancelButton.Instance.Activated:Fire()
		expect(#answers).toBe(0)
		expect(sheet.ConfirmButton.Instance.Selectable).toBe(false)
	end)
end)

describe("a Folios purchase, run", function()
	it("sends BuyCosmetic once, whatever is tapped after the item arrives", function()
		local fixture = setup(500)
		local buy = answer(fixture, "shop.buy")
		expect(buy).never.toBeNil()
		buy.Activated:Fire()
		expect(#fixture.bought).toBe(1)
		fixture.world:advance(0.2)
		-- The item lands, and the player is still tapping.
		table.insert(fixture.data.Cosmetics.Owned, ITEM)
		fixture.purchases:Refresh()
		for _ = 1, 5 do
			fixture.world:advance(0.2)
			buy.Activated:Fire()
		end
		expect(#fixture.bought).toBe(1)
		-- The server would have refused a second one; nothing is waiting to hear it.
		fixture.notified:Fire("purchase.alreadyOwned", nil, "Error")
		fixture.world:advance(ACQUIRED_SECONDS)
		expect(sheetOpen(fixture)).toBe(false)
		expect(#fixture.bought).toBe(1)
	end)

	it("says Owned on the button once the item has come", function()
		local fixture = setup(500)
		local buy = answer(fixture, "shop.buy")
		buy.Activated:Fire()
		table.insert(fixture.data.Cosmetics.Owned, ITEM)
		fixture.purchases:Refresh()
		fixture.world:advance(0.6)
		expect(answer(fixture, "shop.owned")).toBe(buy)
	end)

	it("buys nothing from a sheet sliding away after Cancel", function()
		local fixture = setup(500)
		local buy = answer(fixture, "shop.buy")
		answer(fixture, "common.cancel").Activated:Fire()
		fixture.world:advance(0.1)
		expect(sheetOpen(fixture)).toBe(true)
		buy.Activated:Fire()
		fixture.world:advance(1)
		expect(#fixture.bought).toBe(0)
		expect(sheetOpen(fixture)).toBe(false)
		expect(#fixture.toasts).toBe(0)
	end)

	it("buys nothing from a sheet the Shop took away", function()
		local fixture = setup(500)
		local buy = answer(fixture, "shop.buy")
		fixture.purchases:Close()
		fixture.world:advance(0.1)
		buy.Activated:Fire()
		expect(#fixture.bought).toBe(0)
	end)
end)

return nil
