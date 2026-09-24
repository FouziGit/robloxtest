--!strict
local DataMigration = require("../src/shared/Pure/DataMigration")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function template(): { [string]: any }
	return {
		DataVersion = 2,
		Settings = {
			Keyboard = {
				Cinnabar = "J",
				Indigo = "K",
				Umber = "L",
				Verdigris = "H",
				Orpiment = "U",
				Melee = "MouseButton1",
				Dash = "LeftShift",
				Block = "F",
				Menu = "M",
			},
			Gamepad = {
				Cinnabar = "DPadUp",
				Indigo = "DPadRight",
				Umber = "DPadDown",
				Verdigris = "DPadLeft",
				Orpiment = "ButtonY",
				Melee = "ButtonX",
				Dash = "ButtonB",
				Block = "ButtonL2",
				Menu = "ButtonSelect",
			},
			MusicVolume = 0.5,
			SfxVolume = 1,
			CameraShake = true,
		},
		Progression = { Level = 1, XP = 0, TotalXP = 0 },
		Currency = { Folios = 0 },
		Battlepass = { _template = { XP = 0, Tier = 1, Premium = false, ClaimedFree = {}, ClaimedPremium = {} } },
		Cosmetics = { Owned = {}, Equipped = {} },
		Loadout = { Slots = { "Brand", "Wash" }, ExtraSlots = 0, SlotLimit = 6 },
		Unlocks = { Glyphs = { "Brand" }, Pigments = { "Cinnabar", "Indigo", "Umber", "Verdigris" } },
		Rank = { SeasonId = "S1", Modes = {}, LastRewardedSeason = "" },
		Stats = {
			Kills = 0,
			Deaths = 0,
			GlyphsCast = 0,
			GlyphsHit = 0,
			MatchesPlayed = 0,
			BossKills = 0,
			PlayTimeSeconds = 0,
		},
		Quests = {
			Daily = { PeriodKey = "", Progress = {}, Claimed = {} },
			Weekly = { PeriodKey = "", Progress = {}, Claimed = {} },
		},
		Daily = { LastClaimDay = 0, Streak = 0, FirstWinDay = 0, PremiumBonusDay = 0 },
		Purchases = { Receipts = {}, ProductCounts = {} },
		Passes = {},
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
		Meta = {
			FirstJoin = 0,
			LastJoin = 0,
			SessionCount = 0,
			LegacyImported = false,
			FirstSessionPromptGate = false,
			SaveToken = 0,
			DevGranted = false,
		},
	}
end

local function legacyProfile(): { [string]: any }
	return {
		DataVersion = 1,
		Keybinds = { Feu = "T", Eau = "E", Terre = "Y", Vent = "A" },
		PlayerLevel = 7,
		PlayerXP = 123,
		BattlepassLevel = 12,
		BattlepassXP = 40,
		ClaimedRewards = { ["1"] = true, ["5"] = true, ["10"] = true },
		Currency = 1234,
		Cosmetics = { "BandeauGenin", "KatanaAcier", "Inconnu", "BandeauGenin" },
		TotalKills = 31,
		TotalJutsusCast = 500,
	}
end

describe("DataMigration", function()
	it("returns a fresh template for nil data", function()
		local data, info = DataMigration.migrate(nil, template(), "S1")
		expect(info).toEqual({ From = 0, Migrated = false })
		expect(data.DataVersion).toBe(DataMigration.CurrentVersion)
		expect(data.Battlepass._template).toBeNil()
		expect(data.Progression.Level).toBe(1)
	end)

	it("migrates a V1 profile without losing progress", function()
		local data, info = DataMigration.migrate(legacyProfile(), template(), "S1")
		expect(info).toEqual({ From = 1, Migrated = true })
		expect(data.DataVersion).toBe(DataMigration.CurrentVersion)

		-- custom keys kept when allowed, legacy defaults / movement keys replaced by V2 defaults
		expect(data.Settings.Keyboard.Cinnabar).toBe("T") -- custom, allowed
		expect(data.Settings.Keyboard.Indigo).toBe("K") -- was legacy default "E"
		expect(data.Settings.Keyboard.Umber).toBe("Y") -- custom, allowed
		expect(data.Settings.Keyboard.Verdigris).toBe("H") -- "A" conflicts with movement
		expect(data.Settings.Keyboard.Menu).toBe("M")

		expect(data.Progression.Level).toBe(7)
		expect(data.Progression.XP).toBe(123)
		-- legacy curve floor(80*n^1.3) for n = 1..6 = 80+196+333+485+648+821 = 2563, plus 123
		expect(data.Progression.TotalXP).toBe(2563 + 123)

		expect(data.Currency.Folios).toBe(1234)

		local season = data.Battlepass.S1
		expect(season.Tier).toBe(12)
		expect(season.XP).toBe(40)
		expect(season.Premium).toBe(false)
		expect(season.ClaimedFree).toEqual({ ["1"] = true, ["5"] = true, ["10"] = true })
		expect(season.ClaimedPremium).toEqual({})
		expect(data.Battlepass._template).toBeNil()

		expect(data.Cosmetics.Owned).toEqual({ "BlankHeadband", "SteelStylus" })
		expect(data.Stats.Kills).toBe(31)
		expect(data.Stats.GlyphsCast).toBe(500)
		expect(data.Stats.Deaths).toBe(0)
		expect(data.Loadout.Slots).toEqual({ "Brand", "Wash" })
	end)

	it("tolerates malformed V1 values", function()
		local raw = legacyProfile()
		raw.PlayerLevel = -3
		raw.PlayerXP = "lots"
		raw.Currency = 0 / 0
		raw.Keybinds = "nope"
		raw.Cosmetics = { 42 }
		raw.ClaimedRewards = { [5] = true, ["x"] = true, ["7"] = false }
		local data = DataMigration.migrate(raw, template(), "S1")
		expect(data.Progression.Level).toBe(1)
		expect(data.Progression.XP).toBe(0)
		expect(data.Currency.Folios).toBe(0)
		expect(data.Settings.Keyboard.Cinnabar).toBe("J")
		expect(data.Cosmetics.Owned).toEqual({})
		expect(data.Battlepass.S1.ClaimedFree).toEqual({})
	end)

	it("fills a field a saved profile predates", function()
		-- Every field added after a profile was written arrives through the template, so a partial section
		-- must come back complete. SlotLimit, SaveToken and DevGranted were all added to live profiles.
		local raw = {
			DataVersion = DataMigration.CurrentVersion,
			Loadout = { Slots = { "Brand" }, ExtraSlots = 2 },
			Meta = { SessionCount = 4 },
		}
		local result = DataMigration.migrate(raw, template(), "S1")
		expect(result.Loadout.SlotLimit).toBe(6)
		expect(result.Loadout.ExtraSlots).toBe(2)
		expect(result.Meta.SessionCount).toBe(4)
		expect(result.Meta.SaveToken).toBe(0)
		expect(result.Meta.DevGranted).toBe(false)
	end)

	it("keeps a V2 profile and fills missing fields", function()
		local raw = {
			DataVersion = 2,
			Progression = { Level = 20, XP = 5, TotalXP = 9000 },
			Currency = { Ryo = 77 }, -- the borrowed name a saved profile still holds
			Battlepass = { S1 = { Tier = 3, XP = 10, ClaimedFree = { ["1"] = true } } },
			Cosmetics = { Owned = { "FrisketMask" }, Equipped = { Aura = "BlueInkAura" } },
			Unknown = { junk = true },
			Stats = { Kills = "many" },
		}
		-- Migrated is true: a version 2 profile still holds the borrowed lexicon and the borrowed currency,
		-- so every load upgrades it (see the rename tests below).
		local data, info = DataMigration.migrate(raw, template(), "S1")
		expect(info).toEqual({ From = 2, Migrated = true })
		expect(data.Progression.Level).toBe(20)
		expect(data.Currency.Folios).toBe(77)
		expect(data.Battlepass.S1.Tier).toBe(3)
		expect(data.Battlepass.S1.Premium).toBe(false)
		expect(data.Battlepass.S1.ClaimedPremium).toEqual({})
		expect(data.Cosmetics.Equipped.Aura).toBe("BlueInkAura")
		expect(data.Stats.Kills).toBe(0) -- type mismatch keeps template
		expect(data.Unknown).toBeNil()
		expect(data.Settings.Keyboard.Cinnabar).toBe("J")
	end)

	it("carries a V3 balance into the currency's new name", function()
		-- Version 4 is the currency's rename. The template no longer declares the old key, so the generic
		-- overlay cannot carry it: without the upgrade the player reads as somebody who never earned a coin.
		local raw = {
			DataVersion = 3,
			Currency = { Ryo = 4821 },
			Progression = { Level = 12, XP = 40, TotalXP = 5000 },
		}
		local data, info = DataMigration.migrate(raw, template(), "S1")
		expect(info).toEqual({ From = 3, Migrated = true })
		expect(data.Currency.Folios).toBe(4821)
		expect(data.DataVersion).toBe(DataMigration.CurrentVersion)
		-- And the rest of the profile is untouched by the currency's upgrade.
		expect(data.Progression.Level).toBe(12)
	end)

	it("leaves a profile already on the current version alone", function()
		local raw = {
			DataVersion = DataMigration.CurrentVersion,
			Currency = { Folios = 99 },
		}
		local data, info = DataMigration.migrate(raw, template(), "S1")
		expect(info).toEqual({ From = DataMigration.CurrentVersion, Migrated = false })
		expect(data.Currency.Folios).toBe(99)
	end)

	it("never mutates the template", function()
		local tpl = template()
		DataMigration.migrate(legacyProfile(), tpl, "S1")
		expect(tpl.Progression.Level).toBe(1)
		expect(tpl.Battlepass._template).never.toBeNil()
		expect(tpl.Cosmetics.Owned).toEqual({})
	end)
end)

describe("DataMigration boosts", function()
	it("gives new and legacy profiles an inactive boost", function()
		local fresh = DataMigration.migrate(nil, template(), "S1")
		expect(fresh.Boosts).toEqual({ XpUntil = 0, XpMultiplier = 1 })

		local fromV1 = DataMigration.migrate(legacyProfile(), template(), "S1")
		expect(fromV1.Boosts).toEqual({ XpUntil = 0, XpMultiplier = 1 })
	end)

	it("keeps a live boost across a V2 reload and drops malformed ones", function()
		local kept = DataMigration.migrate(
			{ DataVersion = 2, Boosts = { XpUntil = 1893456000, XpMultiplier = 2 } },
			template(),
			"S1"
		)
		expect(kept.Boosts.XpUntil).toBe(1893456000)
		expect(kept.Boosts.XpMultiplier).toBe(2)

		local malformed =
			DataMigration.migrate({ DataVersion = 2, Boosts = { XpMultiplier = "lots" } }, template(), "S1")
		expect(malformed.Boosts.XpMultiplier).toBe(1)
		expect(malformed.Boosts.XpUntil).toBe(0)
	end)
end)

describe("DataMigration.settleKeybinds", function()
	local ORDER = { "Cinnabar", "Melee", "Dash", "Block", "LockOn", "Menu" }
	local ALLOWED = {
		J = true,
		F = true,
		M = true,
		B = true,
		C = true,
		LeftShift = true,
		MouseButton1 = true,
		MouseButton3 = true,
	}

	local function unique(map: { [string]: string }): boolean
		local seen: { [string]: boolean } = {}
		for _, key in pairs(map) do
			if seen[key] then
				return false
			end
			seen[key] = true
		end
		return true
	end

	it("keeps the player's key and moves the new default off it", function()
		-- Saved before LockOn existed, with the wheel's click on Block: the template's LockOn default
		-- arrives with the same key.
		local saved = { Cinnabar = "J", Melee = "MouseButton1", Dash = "LeftShift", Block = "MouseButton3", Menu = "M" }
		local map = table.clone(saved) :: { [string]: string }
		map.LockOn = "MouseButton3"
		expect(DataMigration.settleKeybinds(map, saved, ALLOWED, ORDER)).toBe(true)
		expect(map.Block).toBe("MouseButton3")
		-- The first free allowed key, sorted: B.
		expect(map.LockOn).toBe("B")
		expect(unique(map)).toBe(true)
		-- Settled once, it stays settled.
		local again = table.clone(map)
		expect(DataMigration.settleKeybinds(again, map, ALLOWED, ORDER)).toBe(false)
		expect(again.LockOn).toBe("B")
	end)

	it("moves nothing when nothing clashes, saved or fresh", function()
		local saved = { Cinnabar = "J", Melee = "MouseButton1", Dash = "LeftShift", Block = "F", Menu = "M" }
		local map = table.clone(saved) :: { [string]: string }
		map.LockOn = "MouseButton3"
		expect(DataMigration.settleKeybinds(map, saved, ALLOWED, ORDER)).toBe(false)
		expect(map.LockOn).toBe("MouseButton3")
		local fresh = table.clone(map)
		expect(DataMigration.settleKeybinds(fresh, nil, ALLOWED, ORDER)).toBe(false)
		expect(fresh.LockOn).toBe("MouseButton3")
	end)

	it("settles a profile loaded over a template that grew an action", function()
		local grown = template()
		grown.Settings.Keyboard.LockOn = "MouseButton3"
		local raw = template()
		raw.DataVersion = DataMigration.CurrentVersion
		raw.Settings.Keyboard.Block = "MouseButton3"
		local migrated = DataMigration.migrate(raw, grown, "S1", nil)
		-- The overlay alone leaves the clash: this is what the settling is for.
		expect(migrated.Settings.Keyboard.LockOn).toBe("MouseButton3")
		expect(migrated.Settings.Keyboard.Block).toBe("MouseButton3")
		local allowed: { [string]: boolean } = {}
		for _, key in pairs(grown.Settings.Keyboard) do
			allowed[key] = true
		end
		allowed.G = true
		local order =
			{ "Cinnabar", "Indigo", "Umber", "Verdigris", "Orpiment", "Melee", "Dash", "Block", "LockOn", "Menu" }
		expect(DataMigration.settleKeybinds(migrated.Settings.Keyboard, raw.Settings.Keyboard, allowed, order)).toBe(
			true
		)
		expect(migrated.Settings.Keyboard.Block).toBe("MouseButton3")
		-- F was Block's default and is free again once the player moved Block off it.
		expect(migrated.Settings.Keyboard.LockOn).toBe("F")
		expect(unique(migrated.Settings.Keyboard)).toBe(true)
	end)
end)
