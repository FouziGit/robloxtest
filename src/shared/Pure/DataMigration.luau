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

DataMigration.CurrentVersion = 2

-- V1 cosmetic ids (French) -> V2 ids.
local LEGACY_COSMETICS: { [string]: string } = {
	BandeauGenin = "GeninHeadband",
	KatanaAcier = "SteelKatana",
	CapeBrume = "MistCape",
	MasqueAnbu = "AnbuMask",
	AuraChakraBleu = "BlueChakraAura",
	KimonoClan = "ClanKimono",
	AuraChakraViolet = "VioletChakraAura",
	ManteauSage = "SageCloak",
	AuraChakraDore = "GoldenChakraAura",
	ManteauHokage = "HokageCloak",
}

-- V1 element names -> V2 action ids, and the V1 default keys that must be replaced by V2 defaults.
local LEGACY_ELEMENTS: { [string]: string } = { Feu = "Fire", Eau = "Water", Terre = "Earth", Vent = "Wind" }
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
		for legacyName, action in pairs(LEGACY_ELEMENTS) do
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
	result.Currency.Ryo = nonNegativeInteger(raw.Currency, 0)

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
	result.Stats.JutsusCast = nonNegativeInteger(raw.TotalJutsusCast, 0)
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
function DataMigration.migrate(
	raw: any,
	template: { [string]: any },
	seasonId: string
): ({ [string]: any }, MigrationInfo)
	local result = deepCopy(template)
	local info: MigrationInfo = { From = 0, Migrated = false }

	if type(raw) ~= "table" then
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

	result.DataVersion = DataMigration.CurrentVersion
	result.Battlepass._template = nil
	return result, info
end

return DataMigration
