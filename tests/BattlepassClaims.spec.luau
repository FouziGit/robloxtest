--!strict
-- The battle pass's claims, run (tests/engine.luau): the real BattlepassScreen, its road, cells and buttons.
--
-- A claim's reward still reads Claimable until the server's push lands. A second tap on a cell's Claim in that
-- time was queued and sent 0.3 s later, and "Claim all" pressed again once its queue drained sent every claim
-- still on its way: each duplicate came back as battlepass.alreadyClaimed in red, and spent a token of the
-- bucket the screen mirrors.
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

local function setup(tier: number): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local Screen = world.require("src/ui/screens/BattlepassScreen")
	local fired: { { any } } = {}
	local changed = Engine.signal()
	local data = {
		Battlepass = {
			[SEASON] = { Tier = tier, XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
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

return nil
