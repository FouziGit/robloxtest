--!strict
-- What the money code offers must be something the game uses. The contextual offers of docs/ECONOMY.md §5
-- had a whole entry point, MonetizationService.maybePrompt, with every guard-rail, and a config table of
-- thresholds; nothing called the one and nothing read CloseLossHealthFraction, so the offers the economy
-- counted on never showed (R8, D-205). A rule nothing reads is a promise the game does not keep.
local Harness = require("./harness")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SERVICE_DIR = "src/server/Services/MonetizationService"
local SERVICE = SERVICE_DIR .. "/init.luau"
-- Called for every service by Bootstrap's loop, never by name.
local LIFECYCLE: { [string]: boolean } = { Init = true, Start = true }

local function code(path: string): string
	return (fs.readFile(path):gsub("%-%-[^\n]*", ""))
end

-- Every source under `directory`, comments stripped, except the paths `skip` names.
local function sources(directory: string, skip: { [string]: boolean }, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if skip[path] then
			continue
		end
		if fs.isDir(path) then
			sources(path, skip, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, code(path))
		end
	end
end

local function readsOf(skip: { [string]: boolean }): string
	local out = {}
	sources("src", skip, out)
	return table.concat(out, "\n")
end

describe("the money code", function()
	it("has no config entry, rule or product field that nothing reads", function()
		local all = readsOf({ ["src/shared/Config"] = true })
		local checked = 0
		local function read(pattern: string, name: string)
			checked += 1
			if string.find(all, pattern) == nil then
				error(("MonetizationConfig.%s is read by nothing"):format(name))
			end
		end
		for key, value in pairs(MonetizationConfig :: any) do
			read("MonetizationConfig%." .. key .. "%f[^%w_]", key)
			if type(value) ~= "table" then
				continue
			end
			for field, entry in pairs(value) do
				if type(entry) == "table" then
					-- A catalog record (a pass, a product): each of its fields is read by name.
					for name in pairs(entry) do
						read("%." .. name .. "%f[^%w_]", key .. "." .. field .. "." .. name)
					end
				elseif type(field) == "string" then
					-- A rules table: each of its numbers is read by name.
					read("%." .. field .. "%f[^%w_]", key .. "." .. field)
				end
			end
		end
		expect(checked).toBeGreaterThan(20)
	end)

	it("exposes no entry point that nothing outside the service calls", function()
		local service = code(SERVICE)
		local outside = readsOf({ [SERVICE_DIR] = true })
		local lifecycle = 0
		for name in string.gmatch(service, "function MonetizationService%.([%w_]+)%(") do
			if LIFECYCLE[name] then
				lifecycle += 1
			elseif string.find(outside, "%." .. name .. "%(") == nil then
				error(("MonetizationService.%s is called by nothing"):format(name))
			end
		end
		-- Init and Start were found, so the pattern reads the module as it is written.
		expect(lifecycle).toBe(2)
	end)
end)

return nil
