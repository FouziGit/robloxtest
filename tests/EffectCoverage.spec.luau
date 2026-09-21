--!strict
-- Every glyph names two functions it cannot reach on its own: the server effect that resolves its damage
-- and the client renderer that draws it. Both live in modules a Lune test cannot require, because they
-- touch Roblox services, so this reads their source and matches the declared names against the config.
--
-- This test exists because the lexicon rename broke exactly that link and nothing noticed. GlyphConfig
-- said Effect = "Brand" while GlyphEffects still declared Fireball, so effects[def.Effect] was nil for all
-- twenty glyphs: not one spell could be cast. The only thing standing between that and a shipped build
-- was a log.warn at startup, which no gate reads and no player reports. Seven gates were green.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local VfxConfig = require("../src/shared/Config/VfxConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local EFFECTS_PATH = "src/server/Effects/GlyphEffects.luau"
local VFX_PATH = "src/client/Controllers/VfxLibrary.luau"

-- Collects the keys a module assigns on itself, in either form Luau allows:
--   function Module.Name(...)      -- a declaration
--   Module.Name = function(...)    -- an assignment, which is how VfxLibrary writes its renderers
local function declaredMembers(path: string, moduleName: string): { [string]: boolean }
	local source = fs.readFile(path)
	local found: { [string]: boolean } = {}
	for name in string.gmatch(source, "\nfunction " .. moduleName .. "%.([%a_][%w_]*)%s*%(") do
		found[name] = true
	end
	for name in string.gmatch(source, "\n" .. moduleName .. "%.([%a_][%w_]*)%s*=") do
		found[name] = true
	end
	return found
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local keys: { string } = {}
	for key in pairs(set) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

describe("glyph effect coverage", function()
	local effects = declaredMembers(EFFECTS_PATH, "GlyphEffects")

	it("finds the effects module at all", function()
		-- A typo in EFFECTS_PATH, or a rename of the module, would otherwise make every check below pass
		-- against an empty set.
		expect(#sortedKeys(effects)).toBeGreaterThan(19)
	end)

	it("declares an effect for every glyph", function()
		local missing: { string } = {}
		for _, def in ipairs(GlyphConfig.Glyphs) do
			if not effects[def.Effect] then
				table.insert(missing, ("%s wants GlyphEffects.%s"):format(def.Id, def.Effect))
			end
		end
		if #missing > 0 then
			error(table.concat(missing, "\n"))
		end
	end)

	it("declares no effect no glyph asks for", function()
		-- Dead code is banned (CLAUDE.md), and an orphan effect is the shape a half-finished rename leaves:
		-- the old function survives beside the new one and the roster looks complete.
		local wanted: { [string]: boolean } = {}
		for _, def in ipairs(GlyphConfig.Glyphs) do
			wanted[def.Effect] = true
		end
		local orphans: { string } = {}
		for _, name in ipairs(sortedKeys(effects)) do
			if not wanted[name] then
				table.insert(orphans, name)
			end
		end
		if #orphans > 0 then
			error("GlyphEffects declares " .. table.concat(orphans, ", ") .. ", which no glyph names")
		end
	end)
end)

describe("vfx renderer coverage", function()
	local renderers = declaredMembers(VFX_PATH, "VfxLibrary")

	it("finds the vfx library at all", function()
		expect(#sortedKeys(renderers)).toBeGreaterThan(25)
	end)

	it("renders every declared effect id", function()
		local missing: { string } = {}
		for _, id in ipairs(VfxConfig.Ids) do
			if not renderers[id] then
				table.insert(missing, id)
			end
		end
		if #missing > 0 then
			error("no renderer for " .. table.concat(missing, ", "))
		end
	end)

	it("renders the effect every glyph asks for by name", function()
		local missing: { string } = {}
		for _, def in ipairs(GlyphConfig.Glyphs) do
			if not renderers[def.VfxId] then
				table.insert(missing, ("%s wants VfxLibrary.%s"):format(def.Id, def.VfxId))
			end
			if not VfxConfig.IdSet[def.VfxId] then
				table.insert(missing, ("%s wants vfx id %s, which VfxConfig never declares"):format(def.Id, def.VfxId))
			end
		end
		if #missing > 0 then
			error(table.concat(missing, "\n"))
		end
	end)
end)

-- The World Boss names its effects in two places that are not VfxConfig: the four attacks in
-- WorldBossConfig, and the spawn and defeat bookends in WorldBossService's own Context. Both are real
-- emissions in a real fight, and before this neither was reachable from any list a gate walks.
describe("world boss effect coverage", function()
	local renderers = declaredMembers(VFX_PATH, "VfxLibrary")

	it("declares every attack the encounter can play", function()
		local missing: { string } = {}
		for _, attack in ipairs(WorldBossConfig.Attacks) do
			if not VfxConfig.IdSet[attack.VfxId] then
				table.insert(
					missing,
					("%s names vfx %s, which VfxConfig does not declare"):format(attack.Id, attack.VfxId)
				)
			end
			if not renderers[attack.VfxId] then
				table.insert(missing, ("%s wants VfxLibrary.%s"):format(attack.Id, attack.VfxId))
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(table.concat(missing, "\n"))
		end
	end)

	it("declares the spawn, the phase change and the defeat", function()
		-- Read out of the server module's source: it touches Roblox services, so it cannot be required
		-- here, and hard-coding the two strings would be a test that cannot notice a rename.
		local source = fs.readFile("src/server/Services/WorldBossService/Context.luau")
		local found = 0
		for _, field in ipairs({ "SpawnVfxId", "PhaseVfxId", "DefeatVfxId" }) do
			local id = string.match(source, "Context%." .. field .. ' = "([%w_]+)"')
			if id == nil then
				error(("WorldBossService Context has no %s; this test is checking nothing"):format(field))
			end
			found += 1
			if not VfxConfig.IdSet[id] then
				error(("Context.%s is %s, which VfxConfig does not declare"):format(field, id))
			end
			if not renderers[id] then
				error(("Context.%s is %s, and VfxLibrary has no renderer for it"):format(field, id))
			end
		end
		expect(found).toBe(3)
	end)
end)
