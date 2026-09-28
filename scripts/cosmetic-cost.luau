--!strict
-- What every aura and trail costs a client, computed from the data that draws it (D-148).
--
-- `lune run scripts/cosmetic-cost` prints the table docs/PERFORMANCE.md quotes: for each aura and trail, its
-- layers, the emitters and ribbons it builds on one body, and the particles it keeps alive at once at each
-- tier (Pure/AuraMath.live, the rate times the longest life, times the tier's ParticleScale). The worst
-- pair of an aura and a trail on one body is what CosmeticConfig.Budget caps and tests/Cosmetics.spec.luau
-- holds. Nothing here was measured on a device.

local AuraMath = require("../src/shared/Pure/AuraMath")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local QualityConfig = require("../src/shared/Config/QualityConfig")

type Row = { Id: string, Slot: string, Rarity: string, Layers: number, Emitters: number, Ribbons: number, Live: number }

local function rowOf(item: CosmeticConfig.CosmeticDef, styles: { [string]: CosmeticConfig.Style }): Row
	local row: Row = {
		Id = item.Id,
		Slot = item.Slot,
		Rarity = item.Rarity,
		Layers = #(item.Look.Styles or {}),
		Emitters = 0,
		Ribbons = 0,
		Live = 0,
	}
	for _, name in ipairs(item.Look.Styles or {}) do
		local style = styles[name] or {}
		for _, emission in ipairs(style.Emissions or {}) do
			row.Emitters += 1
			row.Live += AuraMath.live(emission)
		end
		for _, ribbon in ipairs(style.Ribbons or {}) do
			row.Ribbons += ribbon.Count
		end
	end
	return row
end

local rows: { Row } = {}
local worst: { [string]: Row } = {}
for slot, styles in pairs({ Aura = CosmeticConfig.AuraStyles, Trail = CosmeticConfig.TrailStyles }) do
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Slot == slot then
			local row = rowOf(item, styles)
			table.insert(rows, row)
			if worst[slot] == nil or row.Live > worst[slot].Live then
				worst[slot] = row
			end
		end
	end
end
local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
table.sort(rows, function(a: Row, b: Row): boolean
	if a.Slot ~= b.Slot then
		return a.Slot < b.Slot
	elseif a.Rarity ~= b.Rarity then
		return RANK[a.Rarity] > RANK[b.Rarity]
	end
	return a.Id < b.Id
end)

-- The tiers as the options screen names them in French (docs/PERFORMANCE.md).
local TIER_NAMES = { High = "Élevée", Medium = "Moyenne", Low = "Basse", Performance = "Performance" }
local header = { "Objet", "Emplacement", "Rareté", "Couches", "Émetteurs", "Rubans" }
for _, tier in ipairs(QualityConfig.Order) do
	table.insert(header, "Vivantes " .. (TIER_NAMES[tier] or tier))
end
print("| " .. table.concat(header, " | ") .. " |")
print("|" .. string.rep("---|", #header))
for _, row in ipairs(rows) do
	local cells = {
		row.Id,
		row.Slot,
		row.Rarity,
		tostring(row.Layers),
		tostring(row.Emitters),
		tostring(row.Ribbons),
	}
	for _, tier in ipairs(QualityConfig.Order) do
		table.insert(cells, string.format("%.1f", row.Live * QualityConfig.Tiers[tier].ParticleScale))
	end
	print("| " .. table.concat(cells, " | ") .. " |")
end
print("")
local pair = worst.Aura.Live + worst.Trail.Live
print(
	("Pire corps : %s et %s, %.1f particules vivantes au niveau Élevé, pour un budget de %d (CosmeticConfig.Budget)."):format(
		worst.Aura.Id,
		worst.Trail.Id,
		pair,
		CosmeticConfig.Budget.LiveParticles
	)
)
print(("En combat (CosmeticConfig.Fight) : %.1f au niveau Élevé."):format(pair * CosmeticConfig.Fight.Density))
