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
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

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
					-- The card's face: its rarity band across the top, then a column of the preview and the body.
					local body = actions.Parent
					local column = body.Parent
					local face = column.Parent
					local band = face:FindFirstChild("RarityBand")
					assert(band ~= nil, "the card has no rarity band: this gate would check nothing")
					local padding = body:FindFirstChildOfClass("UIPadding")
					local gap = body:FindFirstChildOfClass("UIListLayout").Padding.Offset
					-- Across: the two prices side by side, the longest of them, in either language, inside the
					-- card's outline.
					local across = holder.Size.X.Offset
						+ column.Size.X.Offset
						- padding.PaddingLeft.Offset
						- padding.PaddingRight.Offset
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
					-- Down: the band and its rule, the preview's floor, the name and one row of buttons at the touch
					-- floor fit the face. The column starts under the band and ends at the face's foot.
					expect(column.Position.Y.Offset).toBe(band.Position.Y.Offset + band.Size.Y.Offset)
					expect(column.Size.Y.Scale).toBe(1)
					expect(column.Size.Y.Offset).toBe(-column.Position.Y.Offset)
					local well = column:FindFirstChild("Preview")
					local floor = well:FindFirstChildOfClass("UISizeConstraint").MinSize.Y
					local name = body:FindFirstChild("Name").Size.Y.Offset
					local buttons = Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
					local fixed = column.Position.Y.Offset
						+ floor
						+ padding.PaddingTop.Offset
						+ name
						+ gap
						+ buttons
						+ padding.PaddingBottom.Offset
					local inside = Measure.heightOf(face, screenHeight)
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
local function builtWith(on: (name: string, handler: (...any) -> ()) -> any): (any, { [string]: any }, any)
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
	return screen, given, world
end

-- The TextButton whose visible word is `word`, under `root`.
local function buttonUnder(root: any, word: string): any
	for _, child in ipairs(root:GetDescendants()) do
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

describe("a price on the primary yellow, run", function()
	it("is marked with a dot of ink, never with the yellow coin", function()
		local ShopRotation = require("../src/shared/Pure/ShopRotation")
		local screen = builtWith(function(name: string, handler: (...any) -> ()): any
			if name == "ShopChanged" then
				handler({ DayKey = ShopRotation.dayKey(os.time()), Entries = { { CosmeticId = ITEM } } })
			end
			return Engine.signal():Connect(handler)
		end)
		screen:Open({ Tab = "Today" })
		local buy = buttonUnder(screen.Instance, "shop.buyFolios")
		assert(buy ~= nil, "no card sells its item for Folios: this gate would check nothing")
		expect(buy:FindFirstChild("Coin", true)).toBeNil()
		local dot = buy:FindFirstChild("Dot", true)
		assert(dot ~= nil, "the price has no dot")
		-- One disc, in the ink the yellow face writes its word in, half the icon's square.
		local disc = dot:FindFirstChild("Disc")
		assert(disc ~= nil, "the dot draws no disc")
		expect(#dot:GetChildren()).toBe(1)
		local word = nil
		for _, label in ipairs(buy:GetDescendants()) do
			if label:IsA("TextLabel") and label.Text == "shop.buyFolios" then
				word = label
			end
		end
		expect(disc.BackgroundColor3).toBe(word.TextColor3)
		expect(disc.BackgroundTransparency).toBe(0)
		expect(disc.Size.X.Scale).toBe(0.5)
		expect(disc.Size.Y.Scale).toBe(0.5)
		expect(disc.AnchorPoint.X).toBe(0.5)
		expect(disc.Position.X.Scale).toBe(0.5)
		expect(disc.Position.Y.Scale).toBe(0.5)
	end)
end)

-- The Shop, open on Today with a pointer, its rotation the Legendary `LEGENDARY` and the Common `ITEM`.
local LEGENDARY = "GoldenInkAura"

local function todayCards(): (any, { [string]: any }, any)
	local ShopRotation = require("../src/shared/Pure/ShopRotation")
	local screen, _given, world = builtWith(function(name: string, handler: (...any) -> ()): any
		if name == "ShopChanged" then
			handler({
				DayKey = ShopRotation.dayKey(os.time()),
				Entries = { { CosmeticId = LEGENDARY }, { CosmeticId = ITEM } },
			})
		end
		return Engine.signal():Connect(handler)
	end)
	screen:Open({ Tab = "Today" })
	world:advance(0.5)
	local faces: { [string]: any } = {}
	for _, id in ipairs({ LEGENDARY, ITEM }) do
		local holder = screen.Instance:FindFirstChild(id, true)
		assert(holder ~= nil, id .. " has no card: this gate would check nothing")
		local actions = holder:FindFirstChild("Actions", true)
		faces[id] = actions.Parent.Parent.Parent
	end
	return screen, faces, world
end

describe("a Today card, run", function()
	it("is its rarity band over the item on vellum, then its name and its prices", function()
		local _screen, faces, world = todayCards()
		local Theme = world.require("src/ui/Theme")
		local stroke = Theme.Sizes.Stroke
		for id, face in pairs(faces) do
			local band = face:FindFirstChild("RarityBand")
			assert(band ~= nil, id .. "'s card has no rarity band")
			-- The full band with a pointer, in the card's words.
			expect(band:FindFirstChild("Fill").Size.Y.Offset).toBe(37)
			expect(band:FindFirstChild("Word", true).Text).toBe(
				"shop.rarity." .. (if id == ITEM then "Common" else "Legendary")
			)
			-- The ribbon it replaces is gone, and so is the Legendary's gold rim.
			expect(face:FindFirstChild("Rarity", true)).toBeNil()
			expect(face:FindFirstChild("Rim", true)).toBeNil()
			-- Right under the rule, inside the outline on both sides: the preview, on the page's own vellum, square.
			local column = face:FindFirstChild("Column")
			expect(column.Position.X.Offset).toBe(stroke)
			expect(column.Position.Y.Offset).toBe(band.Position.Y.Offset + band.Size.Y.Offset)
			expect(column.Size.X.Scale).toBe(1)
			expect(column.Size.X.Offset).toBe(-stroke * 2)
			local preview = column:FindFirstChild("Preview")
			local body = column:FindFirstChild("Body")
			expect(preview.LayoutOrder).toBeLessThan(body.LayoutOrder)
			expect(preview.BackgroundColor3).toBe(Theme.Colors.Panel)
			expect(preview.BackgroundTransparency).toBe(0)
			expect(preview:FindFirstChildOfClass("UICorner")).toBeNil()
			expect(preview.Size.X.Scale).toBe(1)
			expect(preview:FindFirstChildOfClass("UIFlexItem").FlexMode.Name).toBe("Fill")
			expect(preview:FindFirstChildOfClass("UISizeConstraint").MinSize.Y).toBeGreaterThan(0)
			expect(#preview:GetChildren()).toBeGreaterThan(2)
			-- The name and the prices, 10 under the preview and 12 in from the sides and the foot.
			local padding = body:FindFirstChildOfClass("UIPadding")
			expect(padding.PaddingTop.Offset).toBe(10)
			expect(padding.PaddingLeft.Offset).toBe(12)
			expect(padding.PaddingRight.Offset).toBe(12)
			expect(padding.PaddingBottom.Offset).toBe(12)
			expect(body:FindFirstChildOfClass("UIListLayout").Padding.Offset).toBe(Theme.Sizes.PaddingSmall)
			expect(body:FindFirstChild("Name").Size.Y.Offset).toBe(26)
		end
	end)

	it("once owned, offers to equip it on the chapter's own sticker, with no price mark", function()
		-- The board's Legendary card: a green "Équiper", no dot beside it. The price button turned into it, and
		-- kept the dot it was built with.
		local fixture = setup("Today")
		local Theme = fixture.world.require("src/ui/Theme")
		local holder = fixture.screen.Instance:FindFirstChild(ITEM, true)
		local actions = holder:FindFirstChild("Actions", true)
		local shown = {}
		for _, child in ipairs(actions:GetChildren()) do
			if child:IsA("TextButton") and child.Visible then
				table.insert(shown, child)
			end
		end
		expect(#shown).toBe(1)
		local equip = shown[1]
		expect(equip).toBe(buttonSaying(fixture, "shop.equip"))
		expect(equip:FindFirstChild("Face", true).BackgroundColor3).toBe(Theme.chapter("Shop").Band)
		-- Its icon slot holds nothing and takes no room (a button's pending dots are also named Dot).
		local slot = equip:FindFirstChild("Icon", true)
		expect(#slot:GetChildren()).toBe(0)
		expect(slot.Visible).toBe(false)
		-- Not owned, the price shows with its dot, and nothing on the card offers to equip it.
		local _screen, faces = todayCards()
		local price = buttonUnder(faces[LEGENDARY], "shop.buyFolios")
		assert(price ~= nil and price.Visible, "the Legendary card shows no price")
		expect(price:FindFirstChild("Icon", true):FindFirstChild("Dot")).never.toBeNil()
		for _, child in ipairs(faces[LEGENDARY]:FindFirstChild("Actions", true):GetChildren()) do
			if child:IsA("TextButton") and child.Visible then
				for _, label in ipairs(child:GetDescendants()) do
					if label:IsA("TextLabel") and label.Text == "shop.equip" then
						error("a card not owned offers to equip it")
					end
				end
			end
		end
	end)
end)

describe("a Legendary card, run", function()
	it("shimmers across its whole face, over its prices, which still take the clicks", function()
		local screen, faces, world = todayCards()
		local Theme = world.require("src/ui/Theme")
		local shine = faces[LEGENDARY]:FindFirstChild("Shine")
		assert(shine ~= nil, "the Legendary card does not shimmer")
		expect(faces[ITEM]:FindFirstChild("Shine", true)).toBeNil()
		-- Over the whole face, above everything else on it.
		-- Inside its ink outline, which the sweep leaves crisp, on the outline's inner curve.
		local stroke = Theme.Sizes.Stroke
		expect(shine.Position).toBe(roblox.UDim2.fromOffset(stroke, stroke))
		expect(shine.Size).toBe(roblox.UDim2.new(1, -stroke * 2, 1, -stroke * 2))
		expect(shine:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(Theme.Sizes.CornerCard - stroke)
		for _, sibling in ipairs(faces[LEGENDARY]:GetChildren()) do
			if sibling ~= shine and sibling:IsA("GuiObject") then
				expect(shine.ZIndex).toBeGreaterThan(sibling.ZIndex)
			end
		end
		-- It sweeps, a pause between two sweeps.
		local gradient = shine:FindFirstChildOfClass("UIGradient")
		local moved = 0
		local last = gradient.Offset
		for _ = 1, 5 * 60 do
			world:frames(1)
			if gradient.Offset ~= last then
				moved += 1
				last = gradient.Offset
			end
		end
		expect(moved).toBeGreaterThan(10)
		-- The price under it asks, as on any card.
		expect(shine.Interactable).toBe(false)
		expect(shine.Active).toBe(false)
		local price = buttonUnder(faces[LEGENDARY], "shop.buyFolios")
		assert(price ~= nil, "the Legendary card has no price")
		price.Activated:Fire()
		expect(screen.Instance:FindFirstChild("ConfirmSheet", true)).never.toBeNil()
	end)

	it("keeps the Shop within the animated gradients a screen may sweep, its sheet open", function()
		-- The rotation's Legendary cards, and the ribbon of the one the sheet asks about.
		expect(ShopConfig.Rotation.Legendary + 1).toBeLessThanOrEqual(ThemeConfig.Budget.MaxAnimatedGradients)
		local screen, faces, world = todayCards()
		buttonUnder(faces[LEGENDARY], "shop.buyFolios").Activated:Fire()
		world:advance(0.5)
		local gradients = {}
		for _, part in ipairs(screen.Instance:GetDescendants()) do
			if part.Name == "Shine" then
				table.insert(gradients, part:FindFirstChildOfClass("UIGradient"))
			end
		end
		expect(#gradients).toBe(2)
		-- Both sweep: neither is the one past the budget held still.
		local moved: { [number]: boolean } = {}
		local last = {}
		for index, gradient in ipairs(gradients) do
			last[index] = gradient.Offset
		end
		for _ = 1, 5 * 60 do
			world:frames(1)
			for index, gradient in ipairs(gradients) do
				if gradient.Offset ~= last[index] then
					moved[index] = true
				end
				last[index] = gradient.Offset
			end
		end
		expect(moved[1] == true and moved[2] == true).toBe(true)
	end)
end)

describe("the Locker, run", function()
	for _, phone in ipairs({ false, true }) do
		local where = if phone then "on a phone" else "with a pointer"
		it("names each item's rarity on a band over its card, in the card's ink outline, " .. where, function()
			local fixture = setup("Locker", if phone then { 667, 375 } else nil)
			local Theme = fixture.world.require("src/ui/Theme")
			local RarityBand = fixture.world.require("src/ui/components/RarityBand")
			local holder = fixture.screen.Instance:FindFirstChild(ITEM, true)
			assert(holder ~= nil and holder:FindFirstChild("Body", true) ~= nil, "the locker has no card for the item")
			local body = holder:FindFirstChild("Body", true)
			local face = body.Parent
			local band = face:FindFirstChild("RarityBand")
			assert(band ~= nil, "the locker card has no rarity band")
			expect(band:FindFirstChild("Word", true).Text).toBe("shop.rarity.Common")
			expect(band:FindFirstChild("Fill").Size.Y.Offset).toBe(if phone then 22 else 37)
			-- The board's outline, not the thin one of a row.
			expect(face:FindFirstChildOfClass("UIStroke").Thickness).toBe(Theme.Sizes.Stroke)
			-- The body starts under the band and ends at the face's foot.
			local bottom = band.Position.Y.Offset + band.Size.Y.Offset
			expect(body.Position.Y.Offset).toBe(bottom)
			expect(body.Size.Y.Scale).toBe(1)
			expect(body.Size.Y.Offset).toBe(-bottom)
			expect(RarityBand.bottom(phone)).toBe(bottom)
			-- And the cell holds the band, the preview, the button at its touch floor and the card's shadow.
			local grid = holder.Parent:FindFirstChildOfClass("UIGridLayout")
			local padding = body:FindFirstChildOfClass("UIPadding")
			local gap = body:FindFirstChildOfClass("UIListLayout").Padding.Offset
			local preview = body:FindFirstChild("Item").Size.Y.Offset
			local sticker = face.Parent
			local elevation = sticker:FindFirstChild("Base").Position.Y.Offset
			local needed = bottom
				+ padding.PaddingTop.Offset
				+ preview
				+ gap
				+ Theme.touchTargetHeight(Theme.Sizes.ButtonHeight)
				+ padding.PaddingBottom.Offset
				+ elevation
			if needed > grid.CellSize.Y.Offset then
				error(("the locker card needs %.1f and its cell is %.1f"):format(needed, grid.CellSize.Y.Offset))
			end
		end)
	end
end)

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

	it("names the level Orpiment is free at, in the shop", function()
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
	end)
end)

return nil
