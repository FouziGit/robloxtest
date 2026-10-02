--!strict
-- What the developer list hands out stays in the hub, and leaves with the list (docs/QA.md R6). In a ranked
-- match the developer account kept the whole roster, all of it equipped, and the cosmetics it bought with
-- waived Folios stayed owned once it left the list. The services run for real in a pretend server
-- (tests/server.luau).
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DeveloperConfig = require("../src/server/Config/DeveloperConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local Server = require("./server")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
local DEVELOPER = DeveloperConfig.UserIds[1]
-- An Orpiment glyph, a level-25 glyph, then the eight defaults in order: at level 1 with no pass, the glyphs a
-- player could field from it are the first six defaults, Brand to Margin; Scorch is earned, but a seventh.
local LOADOUT = { "Colophon", "Brand", "Blot", "Wash", "Serif", "Sweep", "Bleed", "Margin", "Scorch" }
local FIELDED = { "Brand", "Wash", "Serif", "Sweep", "Bleed", "Margin" }

local function lastNotice(setup: Server.Services): string
	return setup.notices[#setup.notices].Key
end

-- The developer, with LOADOUT equipped and a character, in the hub.
local function developer(): (Server.Services, any)
	local setup = Server.services()
	local dev = setup.world:join(DEVELOPER, "Developer")
	dev:LoadCharacterAsync()
	expect(setup.data.get(dev).Loadout.SlotLimit).toBe(#GlyphConfig.Glyphs)
	expect(setup.loadout.setLoadout(dev, LOADOUT)).toBe(true)
	return setup, dev
end

-- A ranked duel against somebody else, past the countdown. Returns the opponent.
local function ranked(setup: Server.Services, dev: any): any
	local foe = setup.world:join(401, "Foe")
	expect(setup.match.start(DUEL.Id, { { dev.UserId }, { foe.UserId } })).never.toBe(nil)
	setup.world:advance(DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(dev).Phase).toBe("Playing")
	return foe
end

local function knockOut(setup: Server.Services, player: any)
	player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.world:advance(0.2)
end

-- The account leaves the list, then comes back: its profile is loaded as a player's.
local function delisted(setup: Server.Services, dev: any): any
	table.clear(setup.world.require("src/server/Config/DeveloperConfig").UserIds)
	setup.world:leave(dev)
	setup.world:advance(GameConfig.Server.LeaveGraceSeconds + 1)
	local back = setup.world:join(DEVELOPER, "Developer")
	expect(setup.data.get(back)).never.toBeNil()
	return back
end

-- Buys the first item of today's rotation with Folios, and returns its id.
local function buy(setup: Server.Services, player: any): string
	local entry = setup.shop.getSnapshot(player).Entries[1]
	setup.handlers.BuyCosmetic(player, entry.CosmeticId)
	expect(table.find(setup.data.get(player).Cosmetics.Owned, entry.CosmeticId)).never.toBeNil()
	return entry.CosmeticId
end

describe("a developer's roster and slots (R6)", function()
	it("are the hub's: the whole loadout casts there", function()
		local setup, dev = developer()
		expect(setup.cast(dev, "Colophon")).toBe(true)
		expect(setup.cast(dev, "Scorch")).toBe(true)
	end)

	it("stay in the hub: a ranked match fields what a player with the same profile would", function()
		local setup, dev = developer()
		ranked(setup, dev)
		local _, slots = setup.loadout.fielded(setup.data.get(dev))
		expect(slots).toEqual(FIELDED)
		expect(setup.cast(dev, "Margin")).toBe(true)
		expect(setup.cast(dev, "Colophon")).toBe(false)
		expect(lastNotice(setup)).toBe("hud.cast.locked")
		expect(setup.cast(dev, "Blot")).toBe(false)
		expect(lastNotice(setup)).toBe("hud.cast.locked")
		expect(setup.cast(dev, "Scorch")).toBe(false)
		expect(lastNotice(setup)).toBe("hud.cast.notEquipped")
	end)

	it("follow what the profile really earned: its level, its passes, its slots", function()
		local setup, dev = developer()
		local data = setup.data.get(dev)
		data.Progression.Level = GlyphConfig.ById.Blot.Unlock.Value :: number
		-- The key the Orpiment pass is cached under once owned (MonetizationService/Passes.luau).
		expect(MonetizationConfig.Passes.Orpiment).never.toBeNil()
		data.Passes.Orpiment = true
		ranked(setup, dev)
		expect(setup.cast(dev, "Colophon")).toBe(true)
		expect(setup.cast(dev, "Blot")).toBe(true)
		-- Six slots hold Colophon, Brand, Blot, Wash, Serif and Sweep; the pass's slots make room for the rest.
		expect(setup.cast(dev, "Bleed")).toBe(false)
		data.Loadout.ExtraSlots = ProgressionConfig.Loadout.PassExtraSlots
		expect(setup.cast(dev, "Bleed")).toBe(true)
		expect(setup.cast(dev, "Scorch")).toBe(true)
	end)

	it("stay out of every place that pays: the World Boss, a practice, the Battleground", function()
		for _, place in ipairs({ "BossLive", "Engaged", "Inside" }) do
			local setup, dev = developer()
			if place == "BossLive" then
				setup.places.BossLive = true
			elseif place == "Engaged" then
				setup.places.Engaged[dev] = true
			else
				setup.places.Inside[dev] = true
			end
			expect(setup.cast(dev, "Colophon")).toBe(false)
			expect(setup.cast(dev, "Brand")).toBe(true)
		end
	end)

	it("come back in the hub once the match is over", function()
		local setup, dev = developer()
		local foe = ranked(setup, dev)
		expect(setup.cast(dev, "Colophon")).toBe(false)
		knockOut(setup, foe)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
		knockOut(setup, foe)
		setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.ResultSeconds + 0.5)
		expect(setup.match.isInMatch(dev)).toBe(false)
		expect(setup.cast(dev, "Colophon")).toBe(true)
	end)
end)

describe("leaving the developer list (R6)", function()
	it("rebuilds the profile as a player's: earned unlocks, the base pigments, a loadout it can field", function()
		local setup, dev = developer()
		local back = delisted(setup, dev)
		local data = setup.data.get(back)
		expect(data.Unlocks.Glyphs).toEqual(GlyphConfig.defaultUnlocks())
		expect(data.Unlocks.Pigments).toEqual(PigmentConfig.Base)
		expect(data.Loadout.Slots).toEqual(FIELDED)
		expect(data.Loadout.SlotLimit).toBe(ProgressionConfig.Loadout.BaseSlots)
		expect(data.Meta.DevGranted).toBe(false)
	end)

	it("takes back the cosmetics the waived Folios bought, worn or not, and nothing else", function()
		local setup, dev = developer()
		local bought = buy(setup, dev)
		local data = setup.data.get(dev)
		expect(data.Currency.Folios).toBe(0)
		expect(data.Cosmetics.Waived).toEqual({ bought })
		local item = CosmeticConfig.ById[bought]
		local slotKey = CosmeticConfig.slotKey(item)
		expect(setup.cosmetic.equip(dev, slotKey, bought)).toBe(true)
		-- Earned, not bought: a reward the list never paid for.
		local reward = MonetizationConfig.VipCosmetics[1]
		expect(setup.cosmetic.grant(dev, reward)).toBe(true)
		local back = delisted(setup, dev)
		local after = setup.data.get(back)
		expect(table.find(after.Cosmetics.Owned, bought)).toBeNil()
		expect((after.Cosmetics.Equipped :: any)[slotKey]).toBeNil()
		expect(after.Cosmetics.Waived).toEqual({})
		expect(table.find(after.Cosmetics.Owned, reward)).never.toBeNil()
	end)

	it("keeps a cosmetic the list paid for and the account then earned", function()
		local setup, dev = developer()
		local bought = buy(setup, dev)
		expect(setup.cosmetic.grant(dev, bought)).toBe(false)
		expect(setup.data.get(dev).Cosmetics.Waived).toEqual({})
		local back = delisted(setup, dev)
		expect(table.find(setup.data.get(back).Cosmetics.Owned, bought)).never.toBeNil()
	end)

	it("never marks what a player pays for", function()
		local setup = Server.services()
		local player = setup.world:join(402, "Payer")
		setup.data.get(player).Currency.Folios = 100000
		buy(setup, player)
		local data = setup.data.get(player)
		expect(data.Currency.Folios < 100000).toBe(true)
		expect(data.Cosmetics.Waived).toEqual({})
	end)
end)
