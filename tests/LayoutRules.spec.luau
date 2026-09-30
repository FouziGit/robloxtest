--!strict
-- The interface held to what the engine does with its layouts (tests/layout.luau, D-170), run
-- (tests/engine.luau): the real HUD in the hub and in a fight, on a desktop and on a phone, every kind of toast,
-- and each screen of the colour pass on each of its tabs.
--
-- Seen in Studio, where the Lune gates had all passed:
-- - the quick bar's buttons, the meta cluster, the first-steps card and the toasts, all automatically sized, grew
--   to the screen's width or height around a sticker that filled them from a frame of its own;
-- - the Daily, the Menu, Play and the pass took their canvas from the card rather than its window, and scrolled
--   onto nothing;
-- - the menu's third tile of a row, 2 pixels too wide, wrapped under the other two;
-- - a quest's count, a label sized to its words on a 14-unit bar, was cut to nothing.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Layout = require("./layout")
local Measure = require("./measure")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SECONDS_PER_DAY = 86400
local DESKTOP_HEIGHT = 1080
local PHONE = { 844, 390 }
local ME = 42

-- A player part-way into everything: a daily reward to claim, a pass tier to claim, three glyphs equipped.
local function profile(today: number): any
	local quests = { PeriodKey = "", Claimed = {}, Progress = {} }
	return {
		Settings = {
			Keyboard = table.clone(InputConfig.DefaultKeyboard),
			Gamepad = table.clone(InputConfig.DefaultGamepad),
			CameraShake = true,
			MusicVolume = 0.5,
			SfxVolume = 1,
			Quality = "High",
		},
		Loadout = { Slots = { "Brand", "Wash", "Serif" }, SlotLimit = 6, ExtraSlots = 0 },
		Unlocks = { Glyphs = { "Brand", "Wash", "Serif" }, Pigments = {} },
		Progression = { Level = 5, XP = 10, TotalXP = 410 },
		Currency = { Folios = 100 },
		Stats = { GlyphsCast = 3, GlyphsHit = 1, Kills = 0, Deaths = 0, MatchesPlayed = 2, BestChain = 0 },
		Daily = { LastClaimDay = today - 1, Streak = 3, FirstWinDay = 0, PremiumBonusDay = 0 },
		Quests = { Daily = quests, Weekly = table.clone(quests) },
		Battlepass = {
			[GameConfig.SeasonId] = { Tier = 3, XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
		},
		Cosmetics = { Owned = {}, Equipped = {} },
		Passes = {},
		Rank = { SeasonId = GameConfig.SeasonId, Modes = {}, LastRewardedSeason = "" },
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
	}
end

local function expectClean(root: any, screenHeight: number)
	local found = Layout.check(root, screenHeight)
	if #found > 0 then
		error(table.concat(found, "\n"))
	end
end

-- `name` (a file of src/ui/screens), opened with `args` in a world on `phone` or a desktop.
local function screen(name: string, phone: { number }?, args: any?): (any, number, any)
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		-- The menu's Invite asks whether an invite can be sent: it cannot, here.
		Services = {
			SocialService = {
				CanSendGameInviteAsync = function(): boolean
					return false
				end,
				PromptGameInvite = function() end,
			},
		},
	})
	local height = DESKTOP_HEIGHT
	if phone ~= nil then
		height = Engine.phone(world, phone[1], phone[2])
	end
	local today = math.floor(world.workspace:GetServerTimeNow() / SECONDS_PER_DAY)
	local data = profile(today)
	local signal = Engine.signal
	world.player.UserId = ME
	local entries = {}
	for rank = 1, 20 do
		table.insert(entries, {
			Rank = rank,
			UserId = if rank == 12 then ME else 1000 + rank,
			Name = "Player" .. rank,
			Rating = 2000 - rank,
			RankKey = "",
		})
	end
	local Screen = world.require("src/ui/screens/" .. name)
	local built = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
			resolveParams = function(params: any): any
				return params
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = signal(),
		},
		RemoteClient = {
			fire = function() end,
			on = function(_name: string, handler: (...any) -> ()): any
				return signal():Connect(handler)
			end,
			-- A leaderboard of twenty, the player twelfth.
			invoke = function(): (boolean, any)
				return true, { Entries = entries }
			end,
		},
		InputController = { captureNext = function() end, cancelCapture = function() end },
		SoundController = { play = function() end },
		HudController = { Notified = signal(), showLocalToast = function() end },
		MatchController = {
			QueueChanged = signal(),
			MatchChanged = signal(),
			MatchEnded = signal(),
			getQueue = function(): any
				return { Queued = false, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 2 }
			end,
			getMatch = function(): any
				return nil
			end,
			getLastOutcome = function(): any
				return nil
			end,
			joinQueue = function() end,
			leaveQueue = function() end,
		},
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return true
		end,
	})
	built:Open(args)
	world:advance(0.5)
	return built, height, world
end

local SCREENS: { { Name: string, Tabs: { string }? } } = {
	{ Name = "MenuScreen" },
	{ Name = "PlayScreen" },
	{ Name = "ShopScreen", Tabs = { "Today", "Folios", "Passes", "Locker" } },
	{ Name = "BattlepassScreen" },
	{ Name = "DailyScreen" },
	{ Name = "LoadoutScreen" },
	{ Name = "QuestsScreen" },
	{ Name = "LeaderboardScreen" },
	{ Name = "SettingsScreen" },
}

describe("the interface, held to the engine's layouts", function()
	local devices: { { Phone: { number }? } } = { {}, { Phone = PHONE } }
	for _, device in ipairs(devices) do
		local phone = device.Phone
		local where = if phone ~= nil then "on a phone" else "with a pointer"

		it("keeps the HUD's own sizes, in the hub " .. where, function()
			local today = math.floor(os.time() / SECONDS_PER_DAY)
			local fixture = Hud.build({ Profile = profile(today), Phone = phone })
			fixture.world:advance(1)
			local height = if phone ~= nil then Engine.phone(fixture.world, phone[1], phone[2]) else DESKTOP_HEIGHT
			expectClean(fixture.screen, height)
			-- The frames this rule was learnt on are there to be checked.
			expect(fixture.screen:FindFirstChild("QuickBar", true)).never.toBeNil()
			expect(fixture.screen:FindFirstChild("Steps", true)).never.toBeNil()
		end)

		it("keeps the HUD's own sizes, in a fight " .. where, function()
			local today = math.floor(os.time() / SECONDS_PER_DAY)
			local fixture = Hud.build({ Profile = profile(today), Phone = phone })
			fixture.match(Hud.match("Team3v3", 3))
			fixture.world:advance(1)
			local height = if phone ~= nil then Engine.phone(fixture.world, phone[1], phone[2]) else DESKTOP_HEIGHT
			expectClean(fixture.screen, height)
			expect(fixture.screen:FindFirstChild("Match", true).Visible).toBe(true)
		end)

		for _, entry in ipairs(SCREENS) do
			local tabs: { string } = entry.Tabs or { "" }
			for _, tab in ipairs(tabs) do
				local label = entry.Name .. (if tab ~= "" then " (" .. tab .. ")" else "")
				it("keeps " .. label .. "'s own sizes " .. where, function()
					local built, height = screen(entry.Name, phone, if tab ~= "" then { Tab = tab } else nil)
					expectClean(built.Instance, height)
				end)
			end
		end

		it("sets a menu tile's icon at its top and its word at its foot, wrapped, " .. where, function()
			local built = screen("MenuScreen", phone)
			local grid = built.Instance:FindFirstChild("Grid", true)
			local playTile = built.Instance:FindFirstChild("PlayTile", true)
			assert(
				grid ~= nil and playTile ~= nil,
				"the menu has no grid or no Play tile: this gate would check nothing"
			)
			local tiles = {}
			for _, child in ipairs(grid:GetChildren()) do
				if child:IsA("TextButton") then
					table.insert(tiles, child)
				end
			end
			expect(#tiles).toBe(6)
			for _, tile in ipairs(tiles) do
				local content = tile:FindFirstChild("Content", true)
				local layout = content:FindFirstChildOfClass("UIListLayout")
				-- The board's `padding: 1.2cqw` inside the tile's ink.
				expect(content.Position).toBe(roblox.UDim2.fromOffset(15, 15))
				expect(content.Size).toBe(roblox.UDim2.new(1, -30, 1, -30))
				-- The board's `align-content: space-between`: the icon up top, the word down at the foot.
				expect(layout.VerticalFlex.Name).toBe("SpaceBetween")
				local word = content:FindFirstChild("Label", true)
				local cap = word:FindFirstChildOfClass("UITextSizeConstraint")
				-- Wrapped at full size onto two lines 1.05 apart, shrunk only where two are not enough.
				expect(word.TextWrapped).toBe(true)
				expect(word.TextScaled).toBe(true)
				expect(cap.MaxTextSize).toBe(24)
				expect(cap.MinTextSize).toBeGreaterThanOrEqual(14)
				expect(word.LineHeight).toBe(1.05)
				expect(word.Size.Y.Offset).toBeGreaterThanOrEqual(2 * cap.MaxTextSize * word.LineHeight)
				expect(word.TextYAlignment.Name).toBe("Bottom")
			end
			-- The Play tile keeps its words together at its foot, under its disc.
			local playLayout = playTile:FindFirstChild("Content", true):FindFirstChildOfClass("UIListLayout")
			expect(playLayout.VerticalFlex.Name).toBe("None")
			expect(playLayout.VerticalAlignment.Name).toBe("Bottom")
		end)

		it("lays the menu's tiles out in the board's proportions " .. where, function()
			local built, _, world = screen("MenuScreen", phone)
			local Theme = world.require("src/ui/Theme")
			local screenWidth = world.workspace.CurrentCamera.ViewportSize.X / Theme.activeScale()
			local deck = built.Instance:FindFirstChild("Deck", true)
			local grid = built.Instance:FindFirstChild("Grid", true)
			local playTile = built.Instance:FindFirstChild("PlayTile", true)
			assert(
				deck ~= nil and grid ~= nil and playTile ~= nil,
				"the menu has no deck: this gate would check nothing"
			)
			-- The board's 1.5cqw between any two tiles, across and down.
			expect(deck:FindFirstChildOfClass("UIListLayout").Padding.Offset).toBe(16)
			local cells = grid:FindFirstChildOfClass("UIGridLayout")
			expect(cells.CellPadding.X.Offset).toBe(16)
			expect(cells.CellPadding.Y.Offset).toBe(16)
			-- Its `1.35fr 1fr 1fr 1fr`: Play is 1.35 tiles wide, whatever the width the deck is given.
			local tiles: { any } = {}
			local daily: any = nil
			for _, child in ipairs(grid:GetChildren()) do
				if child:IsA("TextButton") then
					table.insert(tiles, child)
					if child:FindFirstChild("Label", true).Text == "daily.title" then
						daily = child
					end
				end
			end
			local tileWidth = Measure.widthOf(tiles[1], screenWidth)
			expect(Measure.widthOf(playTile, screenWidth) / tileWidth).toBeCloseTo(1.35, 2)
			-- Three tiles and their gaps fit their row, the third never wrapping under the others.
			expect(3 * tileWidth + 2 * cells.CellPadding.X.Offset).toBeLessThanOrEqual(
				Measure.widthOf(grid, screenWidth)
			)
			-- And the longest word of the menu, "Récompense du jour", wraps onto two lines at full size, every word
			-- whole (measured the conservative way).
			assert(daily ~= nil, "the menu has no daily tile: this gate would check nothing")
			local word = daily:FindFirstChild("Label", true)
			local size = word:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize
			local width = Measure.widthOf(word, screenWidth)
			local french = Strings.t("daily.title", nil, "fr")
			expect(french).toBe("Récompense du jour")
			for _, title in ipairs({ french, Strings.t("daily.title", nil, "en") }) do
				for part in string.gmatch(title, "%S+") do
					expect(Measure.textWidth(part, size)).toBeLessThanOrEqual(width)
				end
				expect(Measure.lines(title, size, width)).toBeLessThanOrEqual(2)
			end
			expect(Measure.lines(french, size, width)).toBe(2)
		end)

		it("runs the Loadout tile's pigments edge to edge along its foot, its ends in its corner, " .. where, function()
			local built, _, world = screen("MenuScreen", phone)
			local Theme = world.require("src/ui/Theme")
			local PigmentConfig = world.require("src/shared/Config/PigmentConfig")
			local loadout: any = nil
			for _, tile in ipairs(built.Instance:FindFirstChild("Grid", true):GetChildren()) do
				if tile:IsA("TextButton") and tile:FindFirstChild("Label", true).Text == "menu.loadout" then
					loadout = tile
				end
			end
			local stripe = if loadout ~= nil then loadout:FindFirstChild("Stripe", true) else nil
			assert(stripe ~= nil, "the Loadout tile has no stripe: this gate would check nothing")
			local stroke = Theme.Sizes.Stroke
			-- Right inside the ink, edge to edge, 8 tall.
			expect(stripe.AnchorPoint).toBe(roblox.Vector2.new(0.5, 1))
			expect(stripe.Position).toBe(roblox.UDim2.new(0.5, 0, 1, -stroke))
			expect(stripe.Size).toBe(roblox.UDim2.new(1, -2 * stroke, 0, 8))
			local corner = Theme.Sizes.CornerTile - stroke
			local count = #PigmentConfig.Order
			for index, pigment in ipairs(PigmentConfig.Order) do
				local segment = stripe:FindFirstChild(pigment)
				assert(segment ~= nil, pigment .. " has no segment")
				expect(segment.LayoutOrder).toBe(index)
				expect(segment.Size).toBe(roblox.UDim2.fromScale(1 / count, 1))
				local color = Theme.pigmentColor(pigment)
				if index == 1 or index == count then
					-- A frame rounded like the tile's inner corner, clipped to the segment: only its outer foot shows.
					expect(segment.ClipsDescendants).toBe(true)
					expect(segment.BackgroundTransparency).toBe(1)
					local rounded = segment:FindFirstChild("Corner")
					expect(rounded.BackgroundColor3).toBe(color)
					expect(rounded:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(corner)
					local side = if index == 1 then 0 else 1
					expect(rounded.AnchorPoint).toBe(roblox.Vector2.new(side, 1))
					expect(rounded.Position).toBe(roblox.UDim2.fromScale(side, 1))
					expect(rounded.Size).toBe(roblox.UDim2.new(1, corner, 0, 2 * corner))
				else
					expect(segment.BackgroundColor3).toBe(color)
					expect(#segment:GetChildren()).toBe(0)
				end
			end
		end)

		it(
			"sets Play's ► on a disc of the sheet and its ribbon over its corner, riding its face, " .. where,
			function()
				local built, _, world = screen("MenuScreen", phone)
				local Theme = world.require("src/ui/Theme")
				local screenWidth = world.workspace.CurrentCamera.ViewportSize.X / Theme.activeScale()
				local playTile = built.Instance:FindFirstChild("PlayTile", true)
				assert(playTile ~= nil, "the menu has no Play tile: this gate would check nothing")
				local disc = playTile:FindFirstChild("Disc", true)
				local ribbon = playTile:FindFirstChild("Ribbon", true)
				assert(disc ~= nil and ribbon ~= nil, "the Play tile has no disc or no ribbon")
				local content = playTile:FindFirstChild("Content", true)
				-- On the tile's face, beside its words: they ride a press together.
				expect(disc.Parent).toBe(content.Parent)
				expect(ribbon.Parent).toBe(content.Parent)
				expect(playTile:FindFirstChild("Splat", true)).toBeNil()
				-- The disc: the sheet in its ink, round, a third of the tile across, in the tile's top-left padding.
				expect(disc.BackgroundColor3).toBe(Theme.Colors.PanelRaised)
				expect(disc:FindFirstChildOfClass("UICorner").CornerRadius).toBe(Theme.Pill)
				local line = disc:FindFirstChildOfClass("UIStroke")
				expect(line.Color).toBe(Theme.Colors.Accent)
				expect(line.Thickness).toBe(Theme.Sizes.Stroke)
				expect(disc.Position).toBe(content.Position)
				expect(disc.Size).toBe(roblox.UDim2.fromScale(0.35, 0.35))
				local round = disc:FindFirstChildOfClass("UIAspectRatioConstraint")
				expect(round.AspectRatio).toBe(1)
				expect(round.DominantAxis.Name).toBe("Width")
				local across = Measure.widthOf(disc, screenWidth)
				if phone == nil then
					-- About 96 on the pointer card, as the board's 9cqw on a tile of 25.
					expect(across).toBeGreaterThan(90)
					expect(across).toBeLessThan(100)
				end
				local glyph = disc:FindFirstChild("Glyph")
				expect(glyph.Text).toBe("►")
				expect(glyph.TextColor3).toBe(Theme.Colors.Text)
				expect(glyph.AnchorPoint).toBe(roblox.Vector2.new(0.5, 0.5))
				expect(glyph.Position.X.Scale).toBeCloseTo(0.545, 4)
				expect(glyph.Position.Y.Scale).toBe(0.5)
				-- Its word at the board's 4.4cqw, its line in the bold.
				local word = content:FindFirstChild("Label", true)
				expect(word:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize).toBe(Theme.Sizes.TextHero)
				local sub = content:FindFirstChild("Sublabel", true)
				expect(sub.FontFace.Weight).toBe(Theme.Fonts.Bold.Weight)
				expect(sub.FontFace.Family).toBe(Theme.Fonts.Bold.Family)
				-- The ribbon: ink, the sheet's heavy word, corners of 8, padded 6 and 12, turned 8 degrees.
				expect(ribbon.Text).toBe("queue.ranked")
				expect(ribbon.BackgroundColor3).toBe(Theme.Colors.Plate)
				expect(ribbon.TextColor3).toBe(Theme.Colors.PanelRaised)
				expect(ribbon.FontFace.Weight).toBe(Theme.Fonts.Label.Weight)
				expect(ribbon.TextSize).toBe(Theme.Sizes.TextLabel)
				expect(ribbon.Rotation).toBe(8)
				expect(ribbon:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(8)
				local padding = ribbon:FindFirstChildOfClass("UIPadding")
				expect(padding.PaddingLeft.Offset).toBe(12)
				expect(padding.PaddingRight.Offset).toBe(12)
				expect(ribbon.Size.Y.Offset).toBe(Theme.Sizes.TextLabel + 2 * 6)
				expect(ribbon.AutomaticSize.Name).toBe("X")
				expect(ribbon.AnchorPoint).toBe(roblox.Vector2.new(1, 0))
				expect(ribbon.Position.X.Scale).toBe(1)
				expect(ribbon.Position.Y.Offset).toBe(16)
				-- Past the tile's edge, turned, by less than the gap to the Shop: it never covers it. Its width is the
				-- widest its word is drawn in either language.
				local gap =
					built.Instance:FindFirstChild("Deck", true):FindFirstChildOfClass("UIListLayout").Padding.Offset
				local tilt = math.rad(ribbon.Rotation)
				for _, locale in ipairs(Strings.Locales) do
					local wide = Measure.textWidth(Strings.t("queue.ranked", nil, locale), ribbon.TextSize) + 2 * 12
					local tall = ribbon.Size.Y.Offset
					local swing = (wide * math.cos(tilt) + tall * math.sin(tilt) - wide) / 2
					expect(ribbon.Position.X.Offset + swing).toBeLessThan(gap)
				end
				expect(ribbon.Position.X.Offset).toBe(12)
			end
		)

		it("wears the board's chip on every menu tile, in the tile's own ink, " .. where, function()
			local built, _, world = screen("MenuScreen", phone)
			local Theme = world.require("src/ui/Theme")
			local grid = built.Instance:FindFirstChild("Grid", true)
			assert(grid ~= nil, "the menu has no grid: this gate would check nothing")
			-- By the key each tile is titled with (this Localize answers keys): the board's glyphs, its ◆ and ✓
			-- drawn as the ♦ and the √ the engine has (tests/Sigils.spec.luau).
			local glyphs = {
				["menu.shop"] = { "●", Theme.Fonts.Symbol },
				["leaderboard.title"] = { "▲", Theme.Fonts.Symbol },
				["menu.battlepass"] = { "♦", Theme.Fonts.Symbol },
				["menu.quests"] = { "√", Theme.Fonts.Symbol },
				["daily.title"] = { "7", Theme.Fonts.Numeric },
				["menu.loadout"] = { "■", Theme.Fonts.Symbol },
			}
			local seen = 0
			for _, tile in ipairs(grid:GetChildren()) do
				if tile:IsA("TextButton") then
					local word = tile:FindFirstChild("Label", true)
					local expected = glyphs[word.Text]
					assert(expected ~= nil, ("a tile titled %s has no chip to check"):format(word.Text))
					seen += 1
					local chip = tile:FindFirstChild("Chip", true)
					assert(chip ~= nil, ("%s has no chip"):format(word.Text))
					local glyph = chip:FindFirstChild("Glyph")
					local line = chip:FindFirstChildOfClass("UIStroke")
					-- A rounded square outlined 3 in the tile's ink, the glyph in that ink, half its height.
					expect(chip.Parent.Size.X.Offset).toBe(42)
					expect(chip:FindFirstChildOfClass("UICorner").CornerRadius.Offset).toBe(10)
					expect(line.Thickness).toBe(Theme.Sizes.Stroke)
					expect(line.Color).toBe(word.TextColor3)
					expect(glyph.TextColor3).toBe(word.TextColor3)
					expect(glyph.Text).toBe(expected[1])
					expect(glyph.FontFace.Family).toBe(expected[2].Family)
					expect(glyph.FontFace.Weight).toBe(expected[2].Weight)
					expect(glyph.TextSize).toBe(21)
					-- Alone in the icon's place: the pictogram it replaces is gone.
					expect(chip.Parent.Name).toBe("Icon")
					expect(#chip.Parent:GetChildren()).toBe(1)
				end
			end
			expect(seen).toBe(6)
		end)
	end

	it("keeps every kind of toast its own height", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Toast = world.require("src/ui/components/Toast")
		local ScreenRoot = world.require("src/ui/components/ScreenRoot")
		local root = ScreenRoot.new({ Name = "Toasts", DisplayOrder = 50 })
		root.Instance.Parent = world.playerGui
		local toast = Toast.new({ Parent = root.Content, Lane = "Pointer" })
		for _, kind in ipairs({ "Info", "Success", "Error", "Reward", "Celebrate" }) do
			toast:Show("toast." .. kind, kind :: any, if kind == "Reward" then 50 else nil)
		end
		world:advance(0.2)
		expect(#root.Content:GetDescendants()).toBeGreaterThan(10)
		expectClean(root.Instance, DESKTOP_HEIGHT)
	end)
end)

-- A world with a screen to build parts on, and a Localize that answers keys.
local function bench(): (any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local ScreenRoot = world.require("src/ui/components/ScreenRoot")
	local root = ScreenRoot.new({ Name = "Bench", DisplayOrder = 1 })
	root.Instance.Parent = world.playerGui
	local localize = {
		t = function(key: string): string
			return key
		end,
	}
	return world, root.Content, localize
end

describe("the parts, as Studio drew them", function()
	it("sets a hotbar key's letter whole above its pigment strip, at 13 or more", function()
		local world, parent, localize = bench()
		local Keycap = world.require("src/ui/components/Keycap")
		local height = ThemeConfig.Hud.HotbarKeyStrip - 3
		local cap = Keycap.new({
			Key = "J",
			Device = "Keyboard",
			Localize = localize,
			Size = height,
			Pigment = "Cinnabar",
			Parent = parent,
		})
		local word = cap.Instance:FindFirstChild("Key", true)
		local strip = cap.Instance:FindFirstChild("Pigment")
		assert(word ~= nil and strip ~= nil, "the cap has no word or no strip: this gate would check nothing")
		local reserve = strip.Size.Y.Offset + world.require("src/ui/Theme").Sizes.StrokeThin
		-- The word's box ends where the strip begins, and its letters fit the box.
		expect(word.Size.Y.Scale).toBe(1)
		expect(word.Size.Y.Offset).toBe(-reserve)
		expect(word.TextSize).toBeLessThanOrEqual(height - reserve)
		expect(word.TextSize).toBeGreaterThanOrEqual(13)
		-- A cap with no strip keeps its whole face and its full size.
		local plain = Keycap.new({ Key = "M", Device = "Keyboard", Localize = localize, Parent = parent })
		expect(plain.Instance:FindFirstChild("Key", true).TextSize).toBe(16)
	end)

	it("rims a Premium button in gold, hugging it, only while it can be pressed", function()
		local world, parent = bench()
		local Button = world.require("src/ui/components/Button")
		local button = Button.new({ Text = "Buy", Variant = "Premium", Sublabel = "R$ 99", Parent = parent })
		local rim = button.Instance:FindFirstChild("Rim")
		assert(rim ~= nil, "the Premium button has no rim: this gate would check nothing")
		-- A pill outline on the button's own size: the seal's ring, stretched to 120% of a pill, was an ellipse
		-- standing out past both of its ends.
		expect(rim.ClassName).toBe("Frame")
		expect(rim.Size.X.Scale).toBe(1)
		expect(rim.Size.Y.Scale).toBe(1)
		expect(rim.Size.X.Offset).toBe(0)
		local stroke = rim:FindFirstChildOfClass("UIStroke")
		expect(stroke.BorderStrokePosition.Name).toBe("Outer")
		expect(rim.Visible).toBe(true)
		button:SetDisabled(true, "Premium")
		expect(rim.Visible).toBe(false)
		button:SetDisabled(false)
		expect(rim.Visible).toBe(true)
	end)

	it("lays a section's swash on the row, under its title, not in the title's row", function()
		local world, parent = bench()
		local ListRow = world.require("src/ui/components/ListRow")
		local row = ListRow.new({ Left = "quest.daily", Right = "quest.resetsIn", Variant = "Header", Parent = parent })
		local swash = row.Instance:FindFirstChild("Swash", true)
		assert(swash ~= nil, "the header has no swash: this gate would check nothing")
		-- Its parent lays nothing out: in the title's slot, a list, it took half the slot and pushed the title
		-- off to the right.
		expect(swash.Parent).toBe(row.Instance)
		expect(swash.Parent:FindFirstChildOfClass("UIListLayout")).toBeNil()
		expect(swash.ZIndex).toBeLessThan(row.Instance:FindFirstChild("Body").ZIndex)
	end)

	it("writes a title the pass rewards in words a player can read", function()
		local world, parent, localize = bench()
		local Cell = world.require("src/ui/screens/pass/Cell")
		local title: string? = nil
		for id, item in pairs(CosmeticConfig.ById) do
			if item.Slot == "Title" and item.Look.TextKey ~= nil then
				title = id
				break
			end
		end
		assert(title ~= nil, "no title in the catalog: this gate would check nothing")
		local cell = Cell.new(5, "Free", { Kind = "Cosmetic", Id = title } :: any, localize, parent, function() end)
		local root = if cell.Instance ~= nil then cell.Instance else parent
		-- Not on a scrap the size of an icon: its words were four pixels tall there.
		expect(root:FindFirstChild("Scrap", true)).toBeNil()
		local words = root:FindFirstChild("Title", true)
		assert(words ~= nil, "the title is not written: this gate would check nothing")
		expect(words.Text).toBe(CosmeticConfig.ById[title :: string].Look.TextKey)
		expect(words:FindFirstChildOfClass("UITextSizeConstraint").MinTextSize).toBeGreaterThanOrEqual(11)
	end)

	it("sets a title's drop cap flush with the rest of its word, in a row of their own", function()
		local world, parent, localize = bench()
		local Theme = world.require("src/ui/Theme")
		local ChapterBand = world.require("src/ui/components/ChapterBand")
		local band = ChapterBand.new({
			Title = "Menu",
			Chapter = "Menu",
			Position = roblox.UDim2.new(),
			Closable = true,
			OnClose = function() end,
			OnBack = function() end,
			Localize = localize,
			Parent = parent,
		})
		local cap = band.Instance:FindFirstChild("DropCap", true)
		local title = band.Instance:FindFirstChild("Title", true)
		assert(cap ~= nil and title ~= nil, "the band has no drop cap or no title: this gate would check nothing")
		expect(title.Text).toBe("enu")
		local function placed(frame: any): { any }
			local found = {}
			for _, child in ipairs(frame:GetChildren()) do
				if child:IsA("GuiObject") then
					table.insert(found, child)
				end
			end
			table.sort(found, function(a: any, b: any): boolean
				return a.LayoutOrder < b.LayoutOrder
			end)
			return found
		end
		local function fills(object: any): boolean
			local item = object:FindFirstChildOfClass("UIFlexItem")
			return item ~= nil and item.FlexMode.Name == "Fill"
		end
		-- The cap and the rest of its word, alone in a row of their own, the cap first and next to the word: at the
		-- band's own gap between its parts, "Menu" read "M enu" (seen in Studio).
		local heading = cap.Parent
		expect(title.Parent).toBe(heading)
		local inHeading = placed(heading)
		expect(#inHeading).toBe(2)
		expect(inHeading[1]).toBe(cap)
		expect(inHeading[2]).toBe(title)
		local layout = heading:FindFirstChildOfClass("UIListLayout")
		assert(layout ~= nil, "the drop cap's row lays nothing out: this gate would check nothing")
		expect(layout.FillDirection.Name).toBe("Horizontal")
		expect(layout.Padding.Scale).toBe(0)
		expect(layout.Padding.Offset).toBeGreaterThanOrEqual(2)
		expect(layout.Padding.Offset).toBeLessThanOrEqual(3)
		-- That row takes what the band's other parts leave, the word what the cap leaves, and it truncates there.
		expect(fills(heading)).toBe(true)
		expect(fills(title)).toBe(true)
		expect(title.TextTruncate.Name).toBe("AtEnd")
		local automatic = title.AutomaticSize
		expect(automatic == nil or automatic.Name == "None").toBe(true)
		-- The band's other parts are where they were: back, the title, the screen's slot, the cross, at its gap.
		local row = heading.Parent
		local inRow = placed(row)
		expect(#inRow).toBe(4)
		expect(inRow[1].Name).toBe("Back")
		expect(inRow[2]).toBe(heading)
		expect(inRow[3]).toBe(band.Right)
		expect(inRow[4]).toBe(band.CloseButton)
		expect(row:FindFirstChildOfClass("UIListLayout").Padding.Offset).toBe(Theme.Sizes.Gap)
		-- A new title keeps the row: an accented cap in it, or no cap and the whole title.
		band:SetTitle("Équipement")
		cap = heading:FindFirstChild("DropCap")
		assert(cap ~= nil, "a new title lost its drop cap's row")
		expect(cap:FindFirstChild("Letter", true).Text).toBe("É")
		expect(title.Text).toBe("quipement")
		band:SetTitle("3v3")
		expect(band.Instance:FindFirstChild("DropCap", true)).toBeNil()
		expect(title.Parent).toBe(heading)
		expect(title.Text).toBe("3v3")
		expectClean(band.Instance, DESKTOP_HEIGHT)
	end)

	it("gives each side of every Play card the same blot, so the fighters make the difference", function()
		local built = screen("PlayScreen", nil)
		local sizes: { number } = {}
		for _, part in ipairs(built.Instance:GetDescendants()) do
			if part.Name == "Splat" and (part.Parent.Name == "Allies" or part.Parent.Name == "Opponents") then
				table.insert(sizes, part.Size.X.Offset)
			end
		end
		expect(#sizes).toBeGreaterThanOrEqual(4)
		for _, size in ipairs(sizes) do
			expect(size).toBe(sizes[1])
		end
	end)
end)

return nil
