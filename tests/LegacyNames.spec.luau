--!strict
-- The rename is only safe if a profile written under the old lexicon keeps everything it earned. These
-- tests are the proof: they migrate a realistic version 2 profile and check that every unlock, every
-- equipped slot and every owned pigment survived, translated.
local DataMigration = require("../src/shared/Pure/DataMigration")
local GlyphConfig = require("../src/shared/Config/JutsuConfig")
local Harness = require("./harness")
local LegacyNames = require("../src/shared/Pure/LegacyNames")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("LegacyNames", function()
	it("maps every old identifier exactly once", function()
		for _, map in ipairs({ LegacyNames.Pigments, LegacyNames.Glyphs, LegacyNames.Ranks }) do
			local seen: { [string]: string } = {}
			local count = 0
			for old, fresh in pairs(map) do
				expect(type(old)).toBe("string")
				expect(type(fresh)).toBe("string")
				expect(old ~= fresh).toBe(true)
				-- Two old names must never collapse onto one new name: that would silently merge unlocks.
				if seen[fresh] ~= nil then
					error(("%s and %s both map to %s"):format(seen[fresh], old, fresh))
				end
				seen[fresh] = old
				count += 1
			end
			expect(count).toBeGreaterThan(4)
		end
	end)

	it("covers the whole roster and the five schools", function()
		expect(#GlyphConfig.Jutsus).toBe(20)
		local mapped = 0
		for _ in pairs(LegacyNames.Glyphs) do
			mapped += 1
		end
		expect(mapped).toBe(20)
		local pigments = 0
		for _ in pairs(LegacyNames.Pigments) do
			pigments += 1
		end
		expect(pigments).toBe(5)
	end)

	it("passes an unknown id through instead of dropping it", function()
		expect(LegacyNames.glyph("SomethingNobodyShipped")).toBe("SomethingNobodyShipped")
		expect(LegacyNames.pigment("")).toBe("")
	end)

	it("translates a list in place and reports how many moved", function()
		local list = { "Fireball", "Brand", "Meteor" }
		local changed = LegacyNames.translateList(LegacyNames.Glyphs, list)
		expect(changed).toBe(2)
		expect(list[1]).toBe("Brand")
		expect(list[2]).toBe("Brand")
		expect(list[3]).toBe("Blot")
	end)
end)

describe("migration of a profile written before the rename", function()
	local function template(): { [string]: any }
		return {
			DataVersion = DataMigration.CurrentVersion,
			Progression = { Level = 1, Xp = 0 },
			Currency = { Ryo = 0 },
			Unlocks = { Glyphs = {}, Pigments = {} },
			Loadout = { Slots = {}, ExtraSlots = 0, SlotLimit = 6 },
			Battlepass = { _template = { Tier = 1, XP = 0 } },
			Meta = { SaveToken = 0 },
		}
	end

	it("keeps every unlock, translated", function()
		-- A player who had ground to the Lightning element and eight glyphs.
		local raw = {
			DataVersion = 2,
			Progression = { Level = 42, Xp = 900 },
			Unlocks = {
				Jutsus = { "Fireball", "WaterWave", "Meteor", "Raijin", "LightningStep" },
				Elements = { "Orpiment" },
			},
			Loadout = { Slots = { "Fireball", "Raijin" }, ExtraSlots = 4 },
		}
		local data, info = DataMigration.migrate(raw, template(), "S1", LegacyNames)

		expect(info.From).toBe(2)
		expect(info.Migrated).toBe(true)
		expect(data.DataVersion).toBe(DataMigration.CurrentVersion)
		-- Nothing lost: five unlocks in, five out.
		expect(#data.Unlocks.Glyphs).toBe(5)
		expect(data.Unlocks.Glyphs[1]).toBe("Brand")
		expect(data.Unlocks.Glyphs[3]).toBe("Blot")
		expect(data.Unlocks.Glyphs[4]).toBe("Colophon")
		expect(data.Unlocks.Glyphs[5]).toBe("Caret")
		expect(#data.Unlocks.Pigments).toBe(1)
		expect(data.Unlocks.Pigments[1]).toBe("Orpiment")
		-- The equipped loadout follows, or the player logs in with slots the server refuses.
		expect(data.Loadout.Slots[1]).toBe("Brand")
		expect(data.Loadout.Slots[2]).toBe("Colophon")
		expect(data.Loadout.ExtraSlots).toBe(4)
		-- And the rest of the profile is untouched by the rename.
		expect(data.Progression.Level).toBe(42)
	end)

	it("leaves an already-renamed profile alone", function()
		local raw = {
			DataVersion = DataMigration.CurrentVersion,
			Unlocks = { Glyphs = { "Brand", "Blot" }, Pigments = { "Orpiment" } },
			Loadout = { Slots = { "Brand" }, ExtraSlots = 0 },
		}
		local data, info = DataMigration.migrate(raw, template(), "S1", LegacyNames)
		expect(info.Migrated).toBe(false)
		expect(data.Unlocks.Glyphs[1]).toBe("Brand")
		expect(data.Unlocks.Glyphs[2]).toBe("Blot")
		expect(data.Loadout.Slots[1]).toBe("Brand")
	end)

	it("survives a version 2 profile with no unlocks at all", function()
		local data = DataMigration.migrate({ DataVersion = 2 }, template(), "S1", LegacyNames)
		expect(#data.Unlocks.Glyphs).toBe(0)
		expect(#data.Unlocks.Pigments).toBe(0)
	end)
end)
