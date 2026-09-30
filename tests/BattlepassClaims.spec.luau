--!strict
-- The battle pass's claims, run (tests/engine.luau): the real BattlepassScreen, its road, cells and buttons.
--
-- A claim's reward still reads Claimable until the server's push lands. A second tap on a cell's Claim in that
-- time was queued and sent 0.3 s later, and "Claim all" pressed again once its queue drained sent every claim
-- still on its way: each duplicate came back as battlepass.alreadyClaimed in red, and spent a token of the
-- bucket the screen mirrors.
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SEASON = "S1"
local TIMEOUT = require("../src/shared/Config/ThemeConfig").Timing.PendingTimeoutSeconds

type Fixture = {
	world: any,
	screen: any,
	data: any,
	changed: any,
	fired: { { any } },
}

local function setup(tier: number, claimed: { number }?, gamepad: boolean?): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	world.userInput.GamepadEnabled = gamepad == true
	local Screen = world.require("src/ui/screens/BattlepassScreen")
	local fired: { { any } } = {}
	local changed = Engine.signal()
	local claimedFree = {}
	for _, done in ipairs(claimed or {}) do
		claimedFree[tostring(done)] = true
	end
	local data = {
		Battlepass = {
			[SEASON] = { Tier = tier, XP = 0, Premium = false, ClaimedFree = claimedFree, ClaimedPremium = {} },
		},
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
				if name == "ClaimBattlepassReward" then
					table.insert(fired, { ... })
				end
			end,
		},
		InputController = { captureNext = function() end },
		SoundController = { play = function() end },
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	return { world = world, screen = screen, data = data, changed = changed, fired = fired }
end

local function claimButton(fixture: Fixture, tier: number): any
	for _, child in ipairs(fixture.screen.Instance:GetDescendants()) do
		if child.Name == "Free" .. tier then
			for _, inner in ipairs(child:GetDescendants()) do
				if inner:IsA("TextButton") then
					return inner
				end
			end
		end
	end
	return nil
end

local function claimAll(fixture: Fixture): any
	for _, child in ipairs(fixture.screen.Instance:GetDescendants()) do
		if child:IsA("TextButton") and child.LayoutOrder == 5 and child.Parent.Name == "Season" then
			return child
		end
	end
	error("the header has no Claim all")
end

-- The server's answer to a granted claim: the reward marked, and the profile pushed.
local function land(fixture: Fixture, tier: number)
	fixture.data.Battlepass[SEASON].ClaimedFree[tostring(tier)] = true
	fixture.changed:Fire("Battlepass")
end

local function sentFor(fixture: Fixture, tier: number): number
	local count = 0
	for _, args in ipairs(fixture.fired) do
		if args[1] == tier and args[2] == "Free" then
			count += 1
		end
	end
	return count
end

describe("the battle pass's claims, run", function()
	it("sends a cell's claim once, however often it is tapped before its push", function()
		local fixture = setup(3)
		local button = claimButton(fixture, 3)
		expect(button).never.toBeNil()
		button.Activated:Fire()
		fixture.world:advance(0.1)
		button.Activated:Fire()
		fixture.world:advance(1)
		expect(sentFor(fixture, 3)).toBe(1)
	end)

	it("does not send again what Claim all already sent, while its pushes are on their way", function()
		local fixture = setup(5)
		claimAll(fixture).Activated:Fire()
		-- Four leave on the bucket's capacity, the fifth on its refill: all five are out in two seconds.
		fixture.world:advance(2)
		expect(#fixture.fired).toBe(5)
		-- Three pushes have landed, two have not: nothing is left to claim, and pressing again sends nothing.
		land(fixture, 1)
		land(fixture, 2)
		land(fixture, 3)
		claimAll(fixture).Activated:Fire()
		fixture.world:advance(1)
		expect(#fixture.fired).toBe(5)
		for tier = 1, 5 do
			expect(sentFor(fixture, tier)).toBe(1)
		end
		-- And the button says so: with nothing left to claim it is gone.
		expect(claimAll(fixture).Visible).toBe(false)
	end)

	it("drops a queued claim whose push landed while it waited its turn", function()
		local fixture = setup(5)
		claimAll(fixture).Activated:Fire()
		-- The first leaves at once; the others wait their spacing. Tier 4's push lands before its turn.
		land(fixture, 4)
		fixture.world:advance(8)
		expect(sentFor(fixture, 4)).toBe(0)
		expect(#fixture.fired).toBe(4)
	end)

	it("lets a claim the server never answered be sent again once the wait is over", function()
		local fixture = setup(3)
		local button = claimButton(fixture, 3)
		button.Activated:Fire()
		fixture.world:advance(TIMEOUT + 0.5)
		button.Activated:Fire()
		fixture.world:advance(1)
		expect(sentFor(fixture, 3)).toBe(2)
	end)

	it("offers Claim all again for the claims the server never answered", function()
		local fixture = setup(5)
		claimAll(fixture).Activated:Fire()
		fixture.world:advance(2)
		expect(claimAll(fixture).Visible).toBe(false)
		fixture.world:advance(TIMEOUT)
		expect(claimAll(fixture).Visible).toBe(true)
	end)
end)

-- The cell of `tier`'s `track` reward on the road, when it is built.
local function cellOf(fixture: Fixture, track: string, tier: number): any
	for _, child in ipairs(fixture.screen.Instance:GetDescendants()) do
		if child.Name == track .. tier and child.Parent.Name == "Track" then
			return child
		end
	end
	return nil
end

-- The rarity of `tier`'s `track` reward, when it is an item.
local function rarityOf(track: string, tier: number): string?
	local def = BattlepassConfig.Seasons[SEASON].Tiers[tier]
	local reward = if track == "Premium" then def.Premium else def.Free
	if reward == nil or reward.Kind ~= "Cosmetic" then
		return nil
	end
	return CosmeticConfig.ById[reward.Id].Rarity
end

describe("the battle pass's items, run", function()
	it("heads an item's cell with its rarity's colour and pips, and no other cell", function()
		-- On tier 40 the road holds the season's Legendary aura, at 45.
		local fixture = setup(40)
		local Theme = fixture.world.require("src/ui/Theme")
		local banded, legendary = 0, 0
		for tier = 30, 50 do
			for _, track in ipairs({ "Free", "Premium" }) do
				local cell = cellOf(fixture, track, tier)
				if cell == nil then
					continue
				end
				local band = cell:FindFirstChild("RarityBand")
				local rarity = rarityOf(track, tier)
				if rarity == nil then
					expect(band).toBeNil()
					continue
				end
				banded += 1
				assert(band ~= nil, ("%s%d holds an item and no rarity band"):format(track, tier))
				-- The word-less band: the colour and the pips, inside the cell's own outline.
				expect(band:FindFirstChild("Word", true)).toBeNil()
				expect(band:FindFirstChild("Fill").BackgroundColor3).toBe(Theme.rarity(rarity).Fill)
				local pips = 0
				for _, pip in ipairs(band:FindFirstChild("Pips", true):GetChildren()) do
					if pip:IsA("TextLabel") then
						pips += 1
					end
				end
				expect(pips).toBe(Theme.rarity(rarity).Pips)
				local outline = cell:FindFirstChildOfClass("UIStroke").Thickness
				expect(band.Position.Y.Offset).toBe(outline)
				-- Under the locked veil, and no shimmer, even Legendary.
				expect(band.ZIndex).toBeLessThan(cell:FindFirstChild("Veil").ZIndex)
				expect(cell:FindFirstChild("Shine", true)).toBeNil()
				if rarity == "Legendary" then
					legendary += 1
				end
				-- The reward starts under the band, and the cell is tall enough for it and its Claim.
				local body = cell:FindFirstChild("Body")
				local padding = body:FindFirstChildOfClass("UIPadding")
				expect(padding.PaddingTop.Offset).toBeGreaterThan(band.Position.Y.Offset + band.Size.Y.Offset)
				local needed = padding.PaddingTop.Offset
					+ 32
					+ body:FindFirstChildOfClass("UIListLayout").Padding.Offset
					+ Theme.touchTargetHeight(40)
					+ padding.PaddingBottom.Offset
				if needed > cell.Size.Y.Offset then
					error(("%s%d needs %.1f and is %.1f tall"):format(track, tier, needed, cell.Size.Y.Offset))
				end
			end
		end
		expect(banded).toBeGreaterThanOrEqual(4)
		expect(legendary).toBeGreaterThanOrEqual(1)
	end)

	it("makes every cell of the road tall enough for an item's band and its Claim, on a phone", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		Engine.phone(world, 667, 375)
		local Cell = world.require("src/ui/screens/pass/Cell")
		local Theme = world.require("src/ui/Theme")
		local parent = Engine.instance("Frame", Engine.instance("ScreenGui", world.game))
		local localize = {
			t = function(key: string): string
				return key
			end,
		}
		local height = Cell.height(112)
		for _, track in ipairs({ "Free", "Premium" }) do
			local reward = BattlepassConfig.Seasons[SEASON].Tiers[5][track]
			local cell = Cell.new(5, track, reward, localize, parent, function() end)
			local band = cell.Frame:FindFirstChild("RarityBand")
			assert(band ~= nil, track .. ": tier 5's item has no band")
			-- Clear of the outline as the phone draws it: the thin one is floored to 2.94 there.
			local outline = cell.Frame:FindFirstChildOfClass("UIStroke").Thickness
			expect(band.Position.X.Offset).toBeGreaterThanOrEqual(outline)
			expect(band.Position.Y.Offset).toBeGreaterThanOrEqual(outline)
			expect(band.Position.Y.Offset).toBeLessThan(outline + 1)
			local body = cell.Frame:FindFirstChild("Body")
			local padding = body:FindFirstChildOfClass("UIPadding")
			local needed = padding.PaddingTop.Offset
				+ 32
				+ body:FindFirstChildOfClass("UIListLayout").Padding.Offset
				+ Theme.touchTargetHeight(40)
				+ padding.PaddingBottom.Offset
			if needed > height then
				error(
					("%s: an item's cell needs %.1f on a phone and the road gives %.1f"):format(track, needed, height)
				)
			end
			cell:Destroy()
		end
	end)

	it("shows the next reward's rarity under its name when it is an item, and only then", function()
		local Theme = Engine.world({ Stubs = Engine.interfaceStubs() }).require("src/ui/Theme")
		-- Tier 4 reached: the next reward is tier 5's item.
		local fixture = setup(4)
		local showcase = fixture.screen.Instance:FindFirstChild("NextReward", true)
		local body = showcase:FindFirstChild("Body", true)
		local pill = body:FindFirstChild("Rarity")
		assert(pill ~= nil, "the showcase does not say how rare the next item is")
		local rarity = rarityOf("Free", 5) :: string
		expect(pill:FindFirstChild("Word", true).Text).toBe(Theme.rarity(rarity).WordKey)
		expect(pill.BackgroundColor3).toBe(Theme.rarity(rarity).Fill)
		-- Under the name, over the tier.
		expect(pill.LayoutOrder).toBeGreaterThan(body:FindFirstChild("Name").LayoutOrder)
		expect(pill.LayoutOrder).toBeLessThan(body:FindFirstChild("Tier").LayoutOrder)
		-- Tier 5 reached: the next is Folios, and the pill goes rather than stays or doubles.
		fixture.data.Battlepass[SEASON].Tier = 5
		fixture.changed:Fire("Battlepass")
		fixture.world:advance(0.1)
		expect(body:FindFirstChild("Rarity")).toBeNil()
		-- Tier 9 reached: tier 10's item, one pill.
		fixture.data.Battlepass[SEASON].Tier = 9
		fixture.changed:Fire("Battlepass")
		fixture.world:advance(0.1)
		local pills = 0
		for _, child in ipairs(body:GetChildren()) do
			if child.Name == "Rarity" then
				pills += 1
			end
		end
		expect(pills).toBe(1)
	end)
end)

describe("the battle pass on a gamepad, run", function()
	it("hands the pad on to the next claim when the one it was on lands", function()
		-- Tiers 3, 4 and 5 wait: once 3 lands, Claim all still shows, and the pad goes on down the road.
		local fixture = setup(5, { 1, 2 }, true)
		local third = claimButton(fixture, 3)
		fixture.world.guiService.SelectedObject = third
		third.Activated:Fire()
		fixture.world:advance(0.2)
		land(fixture, 3)
		expect(Engine.destroyed(third)).toBe(true)
		expect(fixture.world.guiService.SelectedObject).toBe(claimButton(fixture, 4))
	end)

	it("leaves the pad alone when it was not on the pass", function()
		local fixture = setup(4, { 1, 2 }, true)
		fixture.world.guiService.SelectedObject = nil
		claimButton(fixture, 3).Activated:Fire()
		fixture.world:advance(0.2)
		land(fixture, 3)
		expect(fixture.world.guiService.SelectedObject).toBeNil()
	end)
end)

return nil
