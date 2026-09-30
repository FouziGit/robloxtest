--!strict
-- The login calendar's claim, run (tests/engine.luau): the real DailyRewardService, CosmeticService and
-- CurrencyService over one profile, whose calendar the spec sets as a day of it would find it (E15-S1). What a
-- claim pays, gives and writes is judged on the profile and the player's toasts.
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DailyConfig = require("../src/shared/Config/DailyConfig")
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Engine = require("./engine")
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CALENDAR = DailyConfig.Calendar

type Fixture = { data: any, keys: { string }, claim: () -> boolean, today: number }

-- A profile that last claimed calendar day `day`, `missed` days before yesterday, with `signets` held and `owned`.
local function setup(day: number, missed: number, signets: number, owned: { string }?): Fixture
	-- CosmeticService asks whether a kill was a proof or a Forger: nothing here is tagged.
	local world = Engine.world({
		Services = {
			CollectionService = {
				HasTag = function(_self: any, _instance: any, _tag: string): boolean
					return false
				end,
			},
		},
	})
	local player = world.player
	player.UserId = 7
	local today = DailyStreak.dayIndex(os.time())
	local data = {
		Daily = {
			LastClaimDay = today - 1 - missed,
			Streak = day,
			CalendarDay = day,
			Signets = signets,
			FirstWinDay = 0,
			PremiumBonusDay = 0,
		},
		Currency = { Folios = 0 },
		Cosmetics = { Owned = table.clone(owned or {}), Equipped = {}, Waived = {} },
		Passes = {},
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
	}
	local keys: { string } = {}
	local dataService = {
		get = function(): any
			return data
		end,
		push = function() end,
		ProfileLoaded = Engine.signal(),
	}
	local notify = {
		send = function(_player: any, key: string)
			table.insert(keys, key)
		end,
	}
	local currency = world.require("src/server/Services/CurrencyService")
	-- What the dashboards are told of each Folio (AnalyticsService, D-258): nothing here reads it.
	currency.Init({ DataService = dataService, Analytics = { economy = function() end } })
	local cosmetic = world.require("src/server/Services/CosmeticService")
	cosmetic.Init({ Registry = { on = function() end }, DataService = dataService, Notify = notify })
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
		Battlepass = {
			grantXpBoost = function(): boolean
				return true
			end,
		},
		Cosmetic = cosmetic,
	})
	return {
		data = data,
		keys = keys,
		today = today,
		claim = function(): boolean
			return daily.claim(player)
		end,
	}
end

local function said(fixture: Fixture, key: string): number
	local count = 0
	for _, seen in ipairs(fixture.keys) do
		if seen == key then
			count += 1
		end
	end
	return count
end

describe("a claim of the login calendar, run", function()
	it("gives the week's cosmetic on its last day, once, and its Folios with it", function()
		local fixture = setup(6, 0, 0)
		expect(fixture.claim()).toBe(true)
		local prize = CALENDAR[7]
		expect(table.find(fixture.data.Cosmetics.Owned, prize.Cosmetic)).never.toBeNil()
		expect(fixture.data.Currency.Folios).toBe(prize.Folios)
		expect(fixture.data.Daily.CalendarDay).toBe(7)
		expect(said(fixture, "daily.cosmetic")).toBe(1)
		-- The same day again: refused, nothing more.
		expect(fixture.claim()).toBe(false)
		expect(fixture.data.Currency.Folios).toBe(prize.Folios)
		expect(#fixture.data.Cosmetics.Owned).toBe(1)
	end)

	it("pays the owned cosmetic's Folios instead, on a second month", function()
		local prize = CALENDAR[28]
		local fixture = setup(27, 0, 0, { prize.Cosmetic :: string })
		expect(fixture.claim()).toBe(true)
		expect(fixture.data.Currency.Folios).toBe(prize.Folios + DailyConfig.OwnedCosmeticFolios)
		expect(#fixture.data.Cosmetics.Owned).toBe(1)
		expect(said(fixture, "daily.cosmetic")).toBe(0)
		-- And the day after the 28th is the first again.
		fixture.data.Daily.LastClaimDay = fixture.today - 1
		expect(fixture.claim()).toBe(true)
		expect(fixture.data.Daily.CalendarDay).toBe(1)
	end)

	it("slips a Signet in on its day, never past the book's size", function()
		local fixture = setup(2, 0, 0)
		expect(CALENDAR[3].Signet).toBe(true)
		expect(fixture.claim()).toBe(true)
		expect(fixture.data.Daily.Signets).toBe(1)
		expect(said(fixture, "daily.signetEarned")).toBe(1)
		local full = setup(2, 0, DailyConfig.MaxSignets)
		expect(full.claim()).toBe(true)
		expect(full.data.Daily.Signets).toBe(DailyConfig.MaxSignets)
		expect(said(full, "daily.signetEarned")).toBe(0)
	end)

	it("spends a Signet on a missed day and says so; without one, starts over", function()
		local kept = setup(4, 1, 1)
		expect(kept.claim()).toBe(true)
		expect(kept.data.Daily.CalendarDay).toBe(5)
		expect(kept.data.Daily.Streak).toBe(5)
		expect(kept.data.Daily.Signets).toBe(0)
		expect(said(kept, "daily.signetUsed")).toBe(1)
		local lost = setup(4, 1, 0)
		expect(lost.claim()).toBe(true)
		expect(lost.data.Daily.CalendarDay).toBe(1)
		expect(lost.data.Daily.Streak).toBe(1)
		expect(lost.data.Currency.Folios).toBe(CALENDAR[1].Folios)
		expect(said(lost, "daily.signetUsed")).toBe(0)
	end)
end)

describe("the calendar's cosmetics", function()
	it("are named in both languages and never on the shop's shelves", function()
		local Strings = require("../src/shared/Strings")
		for _, day in ipairs(CALENDAR) do
			local cosmeticId = day.Cosmetic
			if cosmeticId ~= nil then
				local item = CosmeticConfig.ById[cosmeticId]
				expect(item.Sellable).toBe(false)
				expect(Strings.has(item.NameKey)).toBe(true)
				local text = item.Look.TextKey
				if text ~= nil then
					expect(Strings.has(text)).toBe(true)
				end
			end
		end
	end)

	it("reach the player through the one grant CosmeticService keeps, never written by hand", function()
		local source = (fs.readFile("src/server/Services/DailyRewardService.luau"):gsub("%-%-[^\n]*", ""))
		expect(source:find("cosmetic.grant(player, cosmeticId)", 1, true)).never.toBeNil()
		expect(source:find("Cosmetics.Owned", 1, true)).toBeNil()
	end)
end)

return nil
