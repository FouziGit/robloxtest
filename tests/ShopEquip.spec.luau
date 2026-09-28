--!strict
-- Equipping from the Shop, run (tests/engine.luau): the real ShopScreen, its Today cards and its locker.
--
-- An equip fired straight away and waited for nothing. Two taps before the Cosmetics push sent it twice (two
-- toasts, two sounds); a push landing between them made the second tap take off what the player had just
-- put on. The server answers every equip with that push, a refusal too (CosmeticService.equip).
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ITEM = "TrailFolio"
local SLOT = "Trail"

type Fixture = { world: any, screen: any, data: any, changed: any, equips: { { any } }, shopChanged: any }

local function setup(tab: string): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local ShopRotation = world.require("src/shared/Pure/ShopRotation")
	local Screen = world.require("src/ui/screens/ShopScreen")
	local changed = Engine.signal()
	local equips: { { any } } = {}
	local handlers: { [string]: (...any) -> () } = {}
	local data = {
		Currency = { Folios = 0 },
		Cosmetics = { Owned = { ITEM }, Equipped = {} },
		Passes = {},
		Battlepass = {},
	}
	local screen = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = changed,
		},
		RemoteClient = {
			fire = function(name: string, ...: any)
				if name == "EquipCosmetic" then
					table.insert(equips, { ... })
				end
			end,
			on = function(name: string, handler: (...any) -> ()): any
				handlers[name] = handler
				return Engine.signal():Connect(handler)
			end,
		},
		InputController = { captureNext = function() end },
		SoundController = { play = function() end },
		HudController = { Notified = Engine.signal(), showLocalToast = function() end },
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	-- Today's rotation holds the owned item.
	handlers.ShopChanged({ DayKey = ShopRotation.dayKey(os.time()), Entries = { { CosmeticId = ITEM } } })
	screen:Open({ Tab = tab })
	world:advance(0.5)
	return { world = world, screen = screen, data = data, changed = changed, equips = equips }
end

-- The button whose word is `word` (the Localize here answers keys).
local function buttonSaying(fixture: Fixture, word: string): any
	for _, child in ipairs(fixture.screen.Instance:GetDescendants()) do
		if child:IsA("TextButton") then
			for _, label in ipairs(child:GetDescendants()) do
				if label:IsA("TextLabel") and label.Text == word and label.Visible then
					return child
				end
			end
		end
	end
	return nil
end

-- The server's answer: the slot as it now is, pushed.
local function answer(fixture: Fixture, worn: string?)
	fixture.data.Cosmetics.Equipped[SLOT] = worn
	fixture.changed:Fire("Cosmetics")
end

describe("equipping from the Shop, run", function()
	it("sends a locker equip once, however often it is tapped before the answer", function()
		local fixture = setup("Locker")
		local button = buttonSaying(fixture, "shop.equip")
		expect(button).never.toBeNil()
		button.Activated:Fire()
		fixture.world:advance(0.1)
		button.Activated:Fire()
		expect(#fixture.equips).toBe(1)
		expect(fixture.equips[1][2]).toBe(ITEM)
	end)

	it("takes it off only on a tap after the answer", function()
		local fixture = setup("Locker")
		local button = buttonSaying(fixture, "shop.equip")
		button.Activated:Fire()
		answer(fixture, ITEM)
		fixture.world:advance(0.1)
		button.Activated:Fire()
		expect(#fixture.equips).toBe(2)
		expect(fixture.equips[2][2]).toBe("")
	end)

	it("lets the player try again after a refusal", function()
		local fixture = setup("Locker")
		local button = buttonSaying(fixture, "shop.equip")
		button.Activated:Fire()
		answer(fixture, nil)
		button.Activated:Fire()
		expect(#fixture.equips).toBe(2)
		expect(fixture.equips[2][2]).toBe(ITEM)
	end)

	it("sends a Today card's equip once, however often it is tapped before the answer", function()
		local fixture = setup("Today")
		local button = buttonSaying(fixture, "shop.equip")
		expect(button).never.toBeNil()
		button.Activated:Fire()
		fixture.world:advance(0.1)
		button.Activated:Fire()
		expect(#fixture.equips).toBe(1)
		answer(fixture, nil)
		button.Activated:Fire()
		expect(#fixture.equips).toBe(2)
	end)
end)

return nil
