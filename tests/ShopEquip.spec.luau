--!strict
-- Equipping from the Shop, run (tests/engine.luau): the real ShopScreen, its Today cards and its locker.
--
-- An equip fired straight away and waited for nothing. Two taps before the Cosmetics push sent it twice (two
-- toasts, two sounds); a push landing between them made the second tap take off what the player had just
-- put on. The server answers every equip with that push, a refusal too (CosmeticService.equip).
local Engine = require("./engine")
local Harness = require("./harness")
local Measure = require("./measure")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ITEM = "TrailFolio"
local SLOT = "Trail"

type Fixture = { world: any, screen: any, data: any, changed: any, equips: { { any } }, shopChanged: any }

-- The Shop open on `tab`; on a touch phone `phone` points wide and tall when given.
local function setup(tab: string, phone: { number }?): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	if phone ~= nil then
		Engine.phone(world, phone[1], phone[2])
	end
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

-- The longest prices a Today card can carry: every rarity's Folios price and every cosmetic product's Robux.
local function longestPrices(locale: string): (string, string)
	local folios, robux = "", ""
	for rarity, price in pairs(ShopConfig.PriceFolios) do
		local text = Strings.t("shop.buyFolios", { price = price }, locale)
		if #text > #folios then
			folios = text
		end
		local product = MonetizationConfig.Products[ShopConfig.RobuxProduct[rarity]]
		local robuxText = Strings.t("shop.robuxPrice", { price = product.PriceRobux }, locale)
		if #robuxText > #robux then
			robux = robuxText
		end
	end
	return folios, robux
end

describe("today's cards on a phone, run", function()
	for _, phone in ipairs({ { 667, 375 }, { 844, 390 } }) do
		it(
			("fit both prices on one row and keep the preview, on a %d x %d phone"):format(phone[1], phone[2]),
			function()
				local fixture = setup("Today", phone)
				local world = fixture.world
				local Theme = world.require("src/ui/Theme")
				local scale = Theme.activeScale()
				expect(scale).toBeCloseTo(0.68, 5)
				local screenHeight = phone[2] / scale
				local cards = 0
				for _, holder in ipairs(fixture.screen.Instance:GetDescendants()) do
					local actions = holder:FindFirstChild("Actions", true)
					if not holder:IsA("Frame") or holder.Parent.Name ~= "Content" or actions == nil then
						continue
					end
					cards += 1
					local body = actions.Parent
					local padding = body:FindFirstChildOfClass("UIPadding")
					local gap = body:FindFirstChildOfClass("UIListLayout").Padding.Offset
					-- Across: the two prices side by side, the longest of them, in either language.
					local across = holder.Size.X.Offset - padding.PaddingLeft.Offset - padding.PaddingRight.Offset
					local row = actions:FindFirstChildOfClass("UIListLayout").Padding.Offset
					for _, locale in ipairs(Strings.Locales) do
						local folios, robux = longestPrices(locale)
						local need = Measure.buttonWidth(folios, Theme.Sizes.TextButton, true)
							+ row
							+ Measure.buttonWidth(robux, Theme.Sizes.TextButton, false)
						if need > across then
							error(
								("%s: the prices need %.1f across and the card has %.1f"):format(locale, need, across)
							)
						end
					end
					-- Down: the preview's floor, the name and one row of buttons at the touch floor fit the face.
					local inside = Measure.heightOf(body, screenHeight)
						- padding.PaddingTop.Offset
						- padding.PaddingBottom.Offset
					local well = body:FindFirstChild("Preview")
					local floor = well:FindFirstChildOfClass("UISizeConstraint").MinSize.Y
					local name = body:FindFirstChild("Name").Size.Y.Offset
					local buttons = Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
					local fixed = floor + name + buttons + gap * 2
					if fixed > inside then
						error(("the card needs %.1f down and its face has %.1f"):format(fixed, inside))
					end
					expect(floor).toBeGreaterThan(0)
				end
				expect(cards).toBeGreaterThan(0)
			end
		)
	end
end)

-- The Shop built with `on` for a RemoteClient's listening, a Localize that keeps what each key was given.
local function builtWith(on: (name: string, handler: (...any) -> ()) -> any): (any, { [string]: any })
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Screen = world.require("src/ui/screens/ShopScreen")
	local given: { [string]: any } = {}
	local data = {
		Currency = { Folios = 0 },
		Cosmetics = { Owned = {}, Equipped = {} },
		Passes = {},
		Battlepass = {},
	}
	local screen = Screen.new({
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
			Changed = Engine.signal(),
		},
		RemoteClient = { fire = function() end, on = on },
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
	return screen, given
end

describe("the Shop's words and pushes, run", function()
	it("is built when a rotation the server pushed before it reaches it as it listens", function()
		local ShopRotation = require("../src/shared/Pure/ShopRotation")
		-- The engine hands a remote's queued events to its first listener: the screen was still being built,
		-- and its refresh read a screen it did not have yet (seen in Studio's output).
		local screen = builtWith(function(name: string, handler: (...any) -> ()): any
			if name == "ShopChanged" then
				handler({ DayKey = ShopRotation.dayKey(os.time()), Entries = { { CosmeticId = ITEM } } })
			end
			return Engine.signal():Connect(handler)
		end)
		expect(screen.Instance:FindFirstChild(ITEM, true)).never.toBeNil()
	end)

	it("names the level Orpiment is free at, in the shop and in the offer the server makes", function()
		local screen, given = builtWith(function(_name: string, handler: (...any) -> ()): any
			return Engine.signal():Connect(handler)
		end)
		screen:Open({ Tab = "Passes" })
		local params = given["pass.orpiment.desc"]
		assert(params ~= nil, "the shop never writes the Orpiment pass: this gate would check nothing")
		expect(params.level).toBe(ProgressionConfig.OrpimentUnlockLevel)
		-- Every placeholder of every offer's words is one the shop fills, in both languages.
		for _, catalog in ipairs({ MonetizationConfig.Passes, MonetizationConfig.Products } :: { any }) do
			for _, offer in pairs(catalog) do
				for _, locale in ipairs({ "en", "fr" }) do
					local text = Strings.t(offer.DescKey, params, locale)
					if string.find(text, "{", 1, true) ~= nil then
						error(("%s (%s) leaves a placeholder: %s"):format(offer.DescKey, locale, text))
					end
				end
			end
		end
		-- The server's offer toast gives the same words the same level.
		local prompts = fs.readFile("src/server/Services/MonetizationService/Prompts.luau")
		expect(string.find(prompts, "local DESC_PARAMS = { level = ProgressionConfig.OrpimentUnlockLevel }", 1, true)).never.toBeNil()
		expect(string.find(prompts, 'deps.Notify.send(player, descKey, DESC_PARAMS, "Info")', 1, true)).never.toBeNil()
	end)
end)

return nil
