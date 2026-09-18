--!strict
-- Every key of Strings.Table must be reachable from the code, and every key the code names must exist.
-- A key nothing references is dead weight a translator still pays for; a key the code names but the
-- table lacks renders as "[some.key]" on the player's screen.
--
-- Keys assembled at runtime ("shop.rarity." .. rarity) are covered by discovering the prefixes from
-- the sources themselves, in both spellings: concatenated inline, or held in a constant.
local Harness = require("./harness")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOTS = { "src/server", "src/client", "src/ui", "src/shared" }
local STRINGS_MODULE = "src/shared/Strings.luau"

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") and path ~= STRINGS_MODULE then
			table.insert(out, path)
		end
	end
end

-- Every source outside Strings.luau, concatenated once.
local function sources(): string
	local files: { string } = {}
	for _, root in ipairs(ROOTS) do
		collect(root, files)
	end
	local parts = {}
	for _, path in ipairs(files) do
		table.insert(parts, fs.readFile(path))
	end
	return table.concat(parts, "\n")
end

describe("strings usage", function()
	local code = sources()

	-- Any dotted string literal the code mentions, whatever the call that takes it.
	local mentioned: { [string]: boolean } = {}
	for literal in string.gmatch(code, '"([%w_%.]+%.[%w_%.]+)"') do
		mentioned[literal] = true
	end
	-- Prefixes a key can be built from: `"shop.rarity." .. rarity` and `local P = "shop.rarity."`.
	local prefixes: { string } = {}
	for prefix in string.gmatch(code, '"([%w_%.]+%.)"%s*%.%.') do
		table.insert(prefixes, prefix)
	end
	for prefix in string.gmatch(code, '=%s*"([%w_%.]+%.)"') do
		table.insert(prefixes, prefix)
	end

	local function reachable(key: string): boolean
		if mentioned[key] then
			return true
		end
		for _, prefix in ipairs(prefixes) do
			if string.sub(key, 1, #prefix) == prefix then
				return true
			end
		end
		return false
	end

	it("found sources and runtime prefixes", function()
		expect(#code > 100000).toBe(true)
		expect(#prefixes).toBeGreaterThan(0)
	end)

	it("has no unreachable key", function()
		local dead: { string } = {}
		for key in pairs(Strings.Table) do
			if not reachable(key) then
				table.insert(dead, key)
			end
		end
		table.sort(dead)
		if #dead > 0 then
			error(("%d key(s) nothing can reach: %s"):format(#dead, table.concat(dead, ", ")))
		end
	end)

	it("declares every key the code names under a known namespace", function()
		-- Only literals that look like a Strings key are checked: the first segment must be one that
		-- Strings.Table actually uses, so module paths and attribute names are not mistaken for keys.
		local namespaces: { [string]: boolean } = {}
		for key in pairs(Strings.Table) do
			namespaces[string.match(key, "^([%w_]+)%.") or key] = true
		end
		local missing: { string } = {}
		for literal in pairs(mentioned) do
			local head = string.match(literal, "^([%w_]+)%.")
			if head ~= nil and namespaces[head] and not Strings.has(literal) then
				local isPrefixHolder = false
				for _, prefix in ipairs(prefixes) do
					if string.sub(literal .. ".", 1, #prefix) == prefix then
						isPrefixHolder = true
						break
					end
				end
				if not isPrefixHolder then
					table.insert(missing, literal)
				end
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(
				("%d key(s) named by the code but absent from Strings: %s"):format(
					#missing,
					table.concat(missing, ", ")
				)
			)
		end
	end)
end)
