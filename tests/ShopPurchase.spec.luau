--!strict
-- A Folios purchase in the Shop, run (tests/engine.luau): the real Purchase, ConfirmSheet and Button.
--
-- Buy stayed live after "Acquired!" for the 1.2 s before the sheet went, and through the sheet's slide away
-- after Cancel: a tap then sent BuyCosmetic again. The first came back as purchase.alreadyOwned and shook the
-- sheet that had just stamped the item; the second bought what the player had just cancelled, with nothing
-- on screen to say so.
local Engine = require("./engine")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

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
	given: { [string]: any },
}

local function setup(folios: number, rarity: string?): Fixture
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
	})
	local Purchase = world.require("src/ui/screens/shop/Purchase")
	local screen = Engine.instance("ScreenGui", world.playerGui)
	local card = Engine.instance("Frame", screen)
	local bought: { string } = {}
	local toasts: { string } = {}
	local notified = Engine.signal()
	local given: { [string]: any } = {}
	local data = { Currency = { Folios = folios }, Cosmetics = { Owned = {} } }
	local purchases = Purchase.new({
		Localize = {
			t = function(key: string, params: any?): string
				given[key] = params
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
		Rarity = rarity or "Common",
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
		given = given,
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

-- A bare sheet over a card that holds two selectable buttons, the first of them focused, as a pad leaves it.
local function sheetOnCard(gamepad: boolean): (any, any, any, { string }, { any })
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
	})
	world.userInput.GamepadEnabled = gamepad
	local ConfirmSheet = world.require("src/ui/components/ConfirmSheet")
	local card = Engine.instance("Frame", Engine.instance("ScreenGui", world.playerGui))
	local buttons = {}
	for index = 1, 2 do
		local button = Engine.instance("TextButton", card)
		button.Name = "CardButton" .. index
		button.Selectable = true
		table.insert(buttons, button)
	end
	world.guiService.SelectedObject = buttons[2]
	local answers: { string } = {}
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
	return world, sheet, card, answers, buttons
end

describe("a confirm sheet on a gamepad, run", function()
	it("keeps the D-pad on the sheet while it is open", function()
		local world, sheet = sheetOnCard(true)
		expect(world.guiService.SelectedObject).toBe(sheet.CancelButton.Instance)
		local root = sheet.Instance:FindFirstChild("Sheet")
		expect(root.SelectionGroup).toBe(true)
		for _, side in ipairs({ "Up", "Down", "Left", "Right" }) do
			expect(root["SelectionBehavior" .. side]).toBe(roblox.Enum.SelectionBehavior.Stop)
		end
	end)

	it("gives the focus back where it was when it goes", function()
		local world, sheet, _card, _answers, buttons = sheetOnCard(true)
		sheet:Close()
		expect(world.guiService.SelectedObject).toBe(buttons[2])
	end)

	it("gives it to the card when what had it went meanwhile", function()
		local world, sheet, _card, _answers, buttons = sheetOnCard(true)
		buttons[2]:Destroy()
		sheet:Close()
		expect(world.guiService.SelectedObject).toBe(buttons[1])
	end)

	it("leaves a pointer's selection empty", function()
		local world, sheet = sheetOnCard(false)
		world.guiService.SelectedObject = sheet.CancelButton.Instance
		sheet:Close()
		expect(world.guiService.SelectedObject).toBeNil()
	end)
end)

describe("a confirm sheet closing, run", function()
	it("takes no answer while it slides away", function()
		local world, sheet, _card, answers = sheetOnCard(false)
		sheet:Close()
		world:advance(0.1)
		sheet.ConfirmButton.Instance.Activated:Fire()
		sheet.CancelButton.Instance.Activated:Fire()
		expect(#answers).toBe(0)
		expect(sheet.ConfirmButton.Instance.Selectable).toBe(false)
	end)
end)

describe("a purchase sheet, run", function()
	it("shows the item's rarity in its colour and its pips beside its name, as well as in words", function()
		for rarity, def in pairs(ThemeConfig.Rarity) do
			local fixture = setup(500, rarity)
			local Theme = fixture.world.require("src/ui/Theme")
			local row = fixture.card:FindFirstChild("Item", true)
			assert(row ~= nil, "the sheet has no item row: this gate would check nothing")
			local name = row:FindFirstChild("Name")
			local pill = row:FindFirstChild("Rarity")
			assert(pill ~= nil, rarity .. ": the sheet does not show the item's rarity")
			expect(pill.LayoutOrder).toBeGreaterThan(name.LayoutOrder)
			expect(pill.BackgroundColor3).toBe(Theme.rarity(rarity).Fill)
			expect(pill:FindFirstChild("Word", true).Text).toBe("shop.rarity." .. rarity)
			local pips = 0
			for _, pip in ipairs(pill:FindFirstChild("Pips", true):GetChildren()) do
				if pip:IsA("TextLabel") then
					pips += 1
				end
			end
			expect(pips).toBe(def.Pips)
			-- A Legendary's shimmers, as its card does.
			expect(pill:FindFirstChild("Shine") ~= nil).toBe(def.Shimmer == true)
			-- The sheet still says it in words.
			local said = false
			for _, label in ipairs(fixture.card:GetDescendants()) do
				if
					label:IsA("TextLabel")
					and label.Text == "shop.rarity." .. rarity
					and not label:IsDescendantOf(pill)
				then
					said = true
				end
			end
			expect(said).toBe(true)
			-- Gone with the sheet.
			fixture.purchases:Close()
			fixture.world:advance(1)
			expect(fixture.card:FindFirstChild("Rarity", true)).toBeNil()
		end
	end)
end)

describe("a purchase sheet's price, run", function()
	it("is asked for on the yellow, marked with its dot, as on the card that asked", function()
		-- The board's after: "● 450 Folios" where the sheet said "Buy".
		local fixture = setup(500)
		local Theme = fixture.world.require("src/ui/Theme")
		local buy = answer(fixture, "shop.buyFolios")
		assert(buy ~= nil, "the sheet does not ask for the price")
		expect(fixture.given["shop.buyFolios"].price).toBe(100)
		expect(answer(fixture, "shop.buy")).toBeNil()
		expect(buy:FindFirstChild("Face", true).BackgroundColor3).toBe(Theme.Colors.Primary)
		local slot = buy:FindFirstChild("Icon", true)
		expect(slot.Visible).toBe(true)
		expect(slot:FindFirstChild("Dot")).never.toBeNil()
		expect(slot:FindFirstChild("Coin")).toBeNil()
		-- Cancel is the sheet's plain answer.
		local cancel = answer(fixture, "common.cancel")
		expect(cancel:FindFirstChild("Icon", true).Visible).toBe(false)
		-- Short of Folios, it says why it waits, with its lock in the dot's place.
		local short = setup(10)
		local waiting = answer(short, "shop.notEnoughFolios")
		assert(waiting ~= nil, "a sheet short of Folios does not say so")
		local lock = waiting:FindFirstChild("Icon", true)
		expect(lock:FindFirstChild("Lock")).never.toBeNil()
		expect(lock:FindFirstChild("Dot")).toBeNil()
	end)
end)

describe("a Folios purchase, run", function()
	it("sends BuyCosmetic once, whatever is tapped after the item arrives", function()
		local fixture = setup(500)
		local buy = answer(fixture, "shop.buyFolios")
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
		local buy = answer(fixture, "shop.buyFolios")
		buy.Activated:Fire()
		table.insert(fixture.data.Cosmetics.Owned, ITEM)
		fixture.purchases:Refresh()
		fixture.world:advance(0.6)
		expect(answer(fixture, "shop.owned")).toBe(buy)
	end)

	it("buys nothing from a sheet sliding away after Cancel", function()
		local fixture = setup(500)
		local buy = answer(fixture, "shop.buyFolios")
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
		local buy = answer(fixture, "shop.buyFolios")
		fixture.purchases:Close()
		fixture.world:advance(0.1)
		buy.Activated:Fire()
		expect(#fixture.bought).toBe(0)
	end)
end)

return nil
