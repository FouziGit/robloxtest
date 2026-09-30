--!strict
-- The Roblox Premium daily bonus, run (tests/engine.luau): the real DailyRewardService, CurrencyService and
-- BattlepassService, with the profile and the player's toasts as the only fakes.
--
-- docs/ECONOMY.md §6 promised 150 Folios and 30 minutes of boosted XP; the code paid 150 Folios and 300 XP,
-- and only when the profile loaded, so a player who subscribed during the session waited for the next join
-- (R10).
local DailyConfig = require("../src/shared/Config/DailyConfig")
local Engine = require("./engine")
local Harness = require("./harness")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PREMIUM = roblox.Enum.MembershipType.Premium
local NONE = roblox.Enum.MembershipType.None

type Toast = { Key: string, Params: { [string]: any }? }
type Fixture = {
	world: any,
	player: any,
	data: any,
	toasts: { Toast },
	-- The profile finishes loading (DataService.ProfileLoaded).
	load: () -> (),
	-- Roblox reports a membership change during the session (Players.PlayerMembershipChanged).
	subscribe: (membership: any) -> (),
}

local function setup(membership: any): Fixture
	local world = Engine.world()
	local players = world.game:GetService("Players")
	local membershipChanged = Engine.signal()
	players.PlayerMembershipChanged = membershipChanged
	local player = world.player
	player.UserId = 7
	player.MembershipType = membership

	local data = {
		Daily = { LastClaimDay = 0, Streak = 0, FirstWinDay = 0, PremiumBonusDay = 0 },
		Currency = { Folios = 0 },
		Passes = {},
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
	}
	local loaded = false
	local fixture = { world = world, player = player, data = data, toasts = {} :: { Toast } } :: any
	local profileLoaded = Engine.signal()
	local dataService = {
		get = function(): any
			return if loaded then data else nil
		end,
		push = function() end,
		ProfileLoaded = profileLoaded,
	}
	local notify = {
		send = function(_player: any, key: string, params: { [string]: any }?)
			table.insert(fixture.toasts, { Key = key, Params = params })
		end,
	}
	local currency = world.require("src/server/Services/CurrencyService")
	currency.Init({ DataService = dataService, Analytics = { economy = function() end } })
	local battlepass = world.require("src/server/Services/BattlepassService")
	battlepass.Init({
		Registry = { on = function() end },
		DataService = dataService,
		Notify = notify,
		Currency = currency,
		Cosmetic = {
			grant = function(): boolean
				return true
			end,
		},
	})
	local daily = world.require("src/server/Services/DailyRewardService")
	daily.Init({
		Registry = { on = function() end },
		DataService = dataService,
		Notify = notify,
		Progression = {
			addXp = function(_player: any, amount: number): number
				return amount
			end,
		},
		Currency = currency,
		Battlepass = battlepass,
	})
	daily.Start()

	fixture.load = function()
		loaded = true
		profileLoaded:Fire(player, data)
	end
	fixture.subscribe = function(next: any)
		player.MembershipType = next
		membershipChanged:Fire(player)
	end
	return fixture
end

local function premiumToasts(fixture: Fixture): { Toast }
	local found = {}
	for _, toast in ipairs(fixture.toasts) do
		if toast.Key == "daily.premium" then
			table.insert(found, toast)
		end
	end
	return found
end

-- The bonus as docs/ECONOMY.md §6 words it, paid once: its Folios, and a boost running for its minutes.
local function expectPaidOnce(fixture: Fixture)
	local bonus = DailyConfig.PremiumBonus
	expect(fixture.data.Currency.Folios).toBe(bonus.Folios)
	expect(fixture.data.Boosts.XpMultiplier).toBe(ProgressionConfig.XpBoostMultiplier)
	local left = fixture.data.Boosts.XpUntil - os.time()
	expect(left).toBeGreaterThanOrEqual(bonus.BoostMinutes * 60 - 5)
	expect(left).toBeLessThanOrEqual(bonus.BoostMinutes * 60)
	local toasts = premiumToasts(fixture)
	expect(#toasts).toBe(1)
	expect(toasts[1].Params).toEqual({ folios = bonus.Folios, minutes = bonus.BoostMinutes })
end

describe("the Premium daily bonus", function()
	it("is what docs/ECONOMY.md §6 promises: 150 Folios and 30 minutes of double XP", function()
		expect(DailyConfig.PremiumBonus).toEqual({ Folios = 150, BoostMinutes = 30 })
		expect(ProgressionConfig.XpBoostMultiplier).toBe(2)
	end)

	it("pays a Premium member when the profile loads, once a day", function()
		local fixture = setup(PREMIUM)
		fixture.load()
		expectPaidOnce(fixture)
		fixture.load()
		fixture.subscribe(PREMIUM)
		expectPaidOnce(fixture)
	end)

	it("pays a player who becomes Premium during the session, at once (R10)", function()
		local fixture = setup(NONE)
		fixture.load()
		expect(fixture.data.Currency.Folios).toBe(0)
		expect(#premiumToasts(fixture)).toBe(0)
		fixture.subscribe(PREMIUM)
		expectPaidOnce(fixture)
		fixture.subscribe(PREMIUM)
		expectPaidOnce(fixture)
	end)

	it("waits for the profile when the membership changes before it loads, then pays once", function()
		local fixture = setup(NONE)
		fixture.subscribe(PREMIUM)
		expect(#premiumToasts(fixture)).toBe(0)
		expect(fixture.world.warnings).toEqual({})
		fixture.load()
		expectPaidOnce(fixture)
	end)

	it("pays nothing to a player whose membership ends", function()
		local fixture = setup(NONE)
		fixture.load()
		fixture.subscribe(NONE)
		expect(fixture.data.Currency.Folios).toBe(0)
		expect(fixture.data.Boosts.XpUntil).toBe(0)
	end)
end)

return nil
