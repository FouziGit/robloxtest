--!strict
-- Profile schema migration. Pure module (no requires, no Roblox globals), tested under Lune.
--
-- Versions:
--   1  V1 (ProfileService era): flat table {DataVersion=1, Keybinds{Feu,Eau,Terre,Vent}, PlayerLevel,
--      PlayerXP, BattlepassLevel, BattlepassXP, ClaimedRewards{["5"]=true}, Currency=number,
--      Cosmetics={frenchIds}, TotalKills, TotalJutsusCast}
--   2  V2 (ProfileStore): see Types.ProfileData
--
-- migrate(raw, template) returns a complete V2 table built from a deep copy of `template` with every
-- recognizable value of `raw` carried over. Unknown / malformed values fall back to the template.

local DataMigration = {}

-- 4: the currency. `Currency.Ryo` became `Currency.Folios`: Ryo is the borrowed licence's coin and the
-- lexicon of docs/ART_BIBLE.md had missed it (a folio is a leaf of a manuscript, so the page is the
-- money). The template no longer declares the old key, so the generic overlay cannot carry it and a
-- migrated profile would read as a player who had never earned anything: upgradeToV4 moves the balance.
--
-- 3: the lexicon rename (docs/ART_BIBLE.md). Element and jutsu ids became pigment and glyph ids,
-- cosmetics named after a rank or after the spell they reskin were renamed too, and the two lifetime
-- spell counters moved with them. A version 2 profile still holds every one of those under its old key,
-- and the template no longer declares those keys, so the generic overlay cannot carry them: upgradeToV3
-- below reads them out of the raw table before they are lost.
DataMigration.CurrentVersion = 4

-- V1 cosmetic ids (French) -> V2 ids.
local LEGACY_COSMETICS: { [string]: string } = {
	BandeauGenin = "BlankHeadband",
	KatanaAcier = "SteelStylus",
	CapeBrume = "PalimpsestCape",
	MasqueAnbu = "FrisketMask",
	AuraChakraBleu = "BlueInkAura",
	KimonoClan = "ScriptoriumRobe",
	AuraChakraViolet = "VioletInkAura",
	ManteauSage = "ScribeCloak",
	AuraChakraDore = "GoldenInkAura",
	ManteauHokage = "CodexCloak",
}

-- V1 element names (French, as the first version shipped them) -> current pigment action ids, and the
-- V1 default keys that must be replaced by current defaults.
local LEGACY_PIGMENTS: { [string]: string } = { Feu = "Cinnabar", Eau = "Indigo", Terre = "Umber", Vent = "Verdigris" }
local LEGACY_DEFAULT_KEYS: { [string]: string } = { Feu = "A", Eau = "E", Terre = "R", Vent = "T" }

-- Keys that conflict with movement (QWERTY/AZERTY) or Roblox defaults: never carried over.
local FORBIDDEN_KEYS: { [string]: boolean } =
	{ A = true, D = true, S = true, W = true, Z = true, Q = true, I = true, O = true }

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value :: any) do
		copy[key] = deepCopy(item)
	end
	return (copy :: any) :: T
end

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value == math.floor(value) and math.abs(value) < 1e15
end

local function nonNegativeInteger(value: any, fallback: number): number
	if isInteger(value) and value >= 0 then
		return value
	end
	return fallback
end

-- V1 player-level curve, needed to reconstruct TotalXP from (Level, XP).
local function legacyXpForLevel(level: number): number
	return math.floor(80 * level ^ 1.3)
end

local function migrateV1(raw: { [string]: any }, result: { [string]: any }, seasonId: string)
	-- Keybinds (keyboard only in V1).
	local keybinds = raw.Keybinds
	if type(keybinds) == "table" then
		for legacyName, action in pairs(LEGACY_PIGMENTS) do
			local key = keybinds[legacyName]
			if
				type(key) == "string"
				and #key == 1
				and key ~= LEGACY_DEFAULT_KEYS[legacyName]
				and string.match(key, "^%u$") ~= nil
				and not FORBIDDEN_KEYS[key]
			then
				result.Settings.Keyboard[action] = key
			end
		end
	end

	-- Progression.
	local level = nonNegativeInteger(raw.PlayerLevel, 1)
	if level < 1 then
		level = 1
	end
	local xp = nonNegativeInteger(raw.PlayerXP, 0)
	local total = xp
	for previous = 1, level - 1 do
		total += legacyXpForLevel(previous)
	end
	result.Progression.Level = level
	result.Progression.XP = xp
	result.Progression.TotalXP = total

	-- Currency.
	-- V1 kept one number; the current profile keeps it under the name the lexicon gave it (see version 4
	-- above), so this writes the new key rather than the old one it read.
	result.Currency.Folios = nonNegativeInteger(raw.Currency, 0)

	-- Battle pass (single V1 track -> free track of the current season).
	local season = result.Battlepass[seasonId]
	if season == nil then
		season = deepCopy(result.Battlepass._template)
		result.Battlepass[seasonId] = season
	end
	local tier = nonNegativeInteger(raw.BattlepassLevel, 1)
	season.Tier = math.max(1, tier)
	season.XP = nonNegativeInteger(raw.BattlepassXP, 0)
	if type(raw.ClaimedRewards) == "table" then
		for tierKey, claimed in pairs(raw.ClaimedRewards) do
			if type(tierKey) == "string" and claimed == true and tonumber(tierKey) ~= nil then
				season.ClaimedFree[tierKey] = true
			end
		end
	end

	-- Cosmetics.
	if type(raw.Cosmetics) == "table" then
		local seen: { [string]: boolean } = {}
		for _, id in ipairs(result.Cosmetics.Owned) do
			seen[id] = true
		end
		for _, legacyId in ipairs(raw.Cosmetics) do
			local newId = if type(legacyId) == "string" then LEGACY_COSMETICS[legacyId] else nil
			if newId ~= nil and not seen[newId] then
				seen[newId] = true
				table.insert(result.Cosmetics.Owned, newId)
			end
		end
	end

	-- Stats.
	result.Stats.Kills = nonNegativeInteger(raw.TotalKills, 0)
	result.Stats.GlyphsCast = nonNegativeInteger(raw.TotalJutsusCast, 0)
end

-- Copies every key of `source` that exists in `target` (recursively for tables), keeping the
-- template's shape; unknown keys are dropped, type mismatches keep the template value.
local function overlay(target: { [string]: any }, source: { [string]: any })
	for key, templateValue in pairs(target) do
		local incoming = source[key]
		if incoming == nil then
			continue
		end
		if type(templateValue) == "table" and type(incoming) == "table" then
			if #templateValue > 0 or next(templateValue) == nil then
				-- arrays and free-form maps are replaced wholesale
				target[key] = deepCopy(incoming)
			else
				overlay(templateValue, incoming)
			end
		elseif type(templateValue) == type(incoming) then
			target[key] = incoming
		end
	end
end

export type MigrationInfo = { From: number, Migrated: boolean }

-- `template` must be a complete V2 profile (see DataService). `template.Battlepass._template` holds
-- the per-season default that new seasons are cloned from; it is removed from the result.
-- `legacy` carries the old-to-new identifier maps (src/shared/Pure/LegacyNames.luau). It is a parameter
-- rather than a require because this module may not require anything: passing it in keeps the rule and
-- lets a test drive the rename with its own fixtures.
export type LegacyMaps = {
	Pigments: { [string]: string },
	Glyphs: { [string]: string },
	Cosmetics: { [string]: string },
}

-- Rewrites a version 2 profile's identifiers and moves the four keys that held them. Every old key is
-- read from `raw`, never from `result`: the generic overlay could not copy them, because the template no
-- longer declares them, so `result` holds the template's empty defaults at this point.
local function upgradeToV3(raw: { [string]: any }, result: { [string]: any }, legacy: LegacyMaps)
	local unlocks = result.Unlocks
	if type(unlocks) ~= "table" then
		return
	end
	local oldUnlocks = if type(raw.Unlocks) == "table" then raw.Unlocks else {}

	if type(oldUnlocks.Jutsus) == "table" then
		local glyphs = {}
		for _, id in ipairs(oldUnlocks.Jutsus) do
			if type(id) == "string" then
				table.insert(glyphs, legacy.Glyphs[id] or id)
			end
		end
		unlocks.Glyphs = glyphs
	end
	if type(oldUnlocks.Elements) == "table" then
		local pigments = {}
		for _, id in ipairs(oldUnlocks.Elements) do
			if type(id) == "string" then
				table.insert(pigments, legacy.Pigments[id] or id)
			end
		end
		unlocks.Pigments = pigments
	end

	local loadout = result.Loadout
	if type(loadout) == "table" and type(loadout.Slots) == "table" then
		for index, id in ipairs(loadout.Slots) do
			if type(id) == "string" then
				loadout.Slots[index] = legacy.Glyphs[id] or id
			end
		end
	end

	-- Cosmetics are rewards, not purchases that can be re-granted: a dropped id is a player who paid a
	-- season of play for a title that vanished. Owned is a plain list. Equipped is a slot -> id map whose
	-- Skin slot carries the glyph it reskins in its own key ("Skin:Brand"), so the key is translated
	-- with the glyph map and the value with the cosmetic map.
	local cosmetics = result.Cosmetics
	local oldCosmetics = if type(raw.Cosmetics) == "table" then raw.Cosmetics else {}
	if type(cosmetics) == "table" then
		if type(oldCosmetics.Owned) == "table" then
			local owned = {}
			for _, id in ipairs(oldCosmetics.Owned) do
				if type(id) == "string" then
					table.insert(owned, legacy.Cosmetics[id] or id)
				end
			end
			cosmetics.Owned = owned
		end
		if type(oldCosmetics.Equipped) == "table" then
			local equipped: { [string]: string } = {}
			for slot, id in pairs(oldCosmetics.Equipped) do
				if type(slot) == "string" and type(id) == "string" then
					local glyph = string.match(slot, "^Skin:(.+)$")
					local freshSlot = if glyph ~= nil then "Skin:" .. (legacy.Glyphs[glyph] or glyph) else slot
					equipped[freshSlot] = legacy.Cosmetics[id] or id
				end
			end
			cosmetics.Equipped = equipped
		end
	end

	-- Two lifetime counters were named after the old word for a spell. They feed quests and the profile
	-- screen, so losing them would reset a player's whole history to zero.
	local stats = result.Stats
	local oldStats = if type(raw.Stats) == "table" then raw.Stats else {}
	if type(stats) == "table" then
		stats.GlyphsCast = nonNegativeInteger(oldStats.JutsusCast, stats.GlyphsCast)
		stats.GlyphsHit = nonNegativeInteger(oldStats.JutsusHit, stats.GlyphsHit)
	end
end

-- The currency's rename. Reads the old key out of the raw profile, because the template has only the new
-- one and the overlay walks the template.
local function upgradeToV4(raw: { [string]: any }, result: { [string]: any })
	local currency = result.Currency
	local oldCurrency = if type(raw.Currency) == "table" then raw.Currency else {}
	if type(currency) == "table" then
		currency.Folios = nonNegativeInteger(oldCurrency.Ryo, currency.Folios)
	end
end

function DataMigration.migrate(
	raw: any,
	template: { [string]: any },
	seasonId: string,
	legacy: LegacyMaps?
): ({ [string]: any }, MigrationInfo)
	local result = deepCopy(template)
	local info: MigrationInfo = { From = 0, Migrated = false }

	if type(raw) ~= "table" then
		-- A fresh profile is stamped current too. Leaving the template's own version here meant a brand new
		-- profile claimed to be whatever version the template literal happened to say, and would be
		-- migrated again on its next load.
		result.DataVersion = DataMigration.CurrentVersion
		result.Battlepass._template = nil
		return result, info
	end

	local version = if isInteger(raw.DataVersion) then raw.DataVersion else 1
	info.From = version

	if version <= 1 then
		migrateV1(raw, result, seasonId)
		info.Migrated = true
	else
		local seasonTemplate = result.Battlepass._template
		overlay(result, raw)
		-- Battlepass is a free-form map of seasons: make sure every season has the full shape.
		if type(raw.Battlepass) == "table" then
			result.Battlepass = {}
			for id, seasonData in pairs(raw.Battlepass) do
				if type(id) == "string" and id ~= "_template" and type(seasonData) == "table" then
					local season = deepCopy(seasonTemplate)
					overlay(season, seasonData)
					result.Battlepass[id] = season
				end
			end
		end
		info.Migrated = version < DataMigration.CurrentVersion
	end

	if version < 3 and legacy ~= nil then
		upgradeToV3(raw, result, legacy)
		info.Migrated = true
	end

	-- After V1's own path too: migrateV1 writes the balance it found under the old key.
	if version < 4 then
		upgradeToV4(raw, result)
		info.Migrated = true
	end

	result.DataVersion = DataMigration.CurrentVersion
	result.Battlepass._template = nil
	return result, info
end

return DataMigration
