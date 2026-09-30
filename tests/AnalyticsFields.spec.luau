--!strict
-- The custom fields Roblox reads (E8-S2). Its analytics reads three keys and no others, CustomField01 to
-- CustomField03, and reads them as text: any other key is dropped without a word, and the event lands with its
-- dimensions gone. Every prompt and purchase event went out as { product = key } or { pass = key }: the Creator
-- Dashboard counted them and could not say which product or which pass.
--
-- The real AnalyticsService in a pretend server (tests/server.luau), on a pretend Roblox analytics that writes down
-- what it is given (tests/analytics.luau); then every custom event of src/server, read from the sources.
local AnalyticsConfig = require("../src/server/Config/AnalyticsConfig")
local Harness = require("./harness")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local Server = require("./server")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SERVICE = "src/server/Services/AnalyticsService"

local function started(): (Server.World, any, any)
	local world = Server.world()
	local analytics = world.require(SERVICE)
	analytics.Init({})
	analytics.Start()
	local player = world:join(11, "Ada")
	return world, analytics, player
end

-- How many lines the service warned with that mention `needle`.
local function warnings(world: Server.World, needle: string): number
	local count = 0
	for _, line in ipairs(world.lines) do
		if line:sub(1, 5) == "WARN " and line:find(needle, 1, true) ~= nil then
			count += 1
		end
	end
	return count
end

----------------------------------------------------------------
-- The sources: every custom event of src/server
----------------------------------------------------------------

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif entry:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

-- The top-level arguments of a call, given the text between its parentheses.
local function arguments(inside: string): { string }
	local found: { string } = {}
	local depth = 0
	local quote: string? = nil
	local start = 1
	for index = 1, #inside do
		local char = inside:sub(index, index)
		if quote ~= nil then
			if char == quote then
				quote = nil
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char == "(" or char == "{" or char == "[" then
			depth += 1
		elseif char == ")" or char == "}" or char == "]" then
			depth -= 1
		elseif char == "," and depth == 0 then
			table.insert(found, (inside:sub(start, index - 1):match("^%s*(.-)%s*$")) :: string)
			start = index + 1
		end
	end
	table.insert(found, (inside:sub(start):match("^%s*(.-)%s*$")) :: string)
	return found
end

export type Site = { Path: string, Text: string, Arguments: { string } }

-- Every call of the analytics' `custom` in src/server, with its arguments as written. A function's own
-- parameter list is not a call: the definition in AnalyticsService is left out.
local function customCalls(): { Site }
	local files: { string } = {}
	collect("src/server", files)
	local sites: { Site } = {}
	for _, path in ipairs(files) do
		local source = code(path):gsub("function%s+[%w_%.:]+%b()", "")
		for call in source:gmatch("[%w_]%.custom(%b())") do
			table.insert(sites, { Path = path, Text = call, Arguments = arguments(call:sub(2, -2)) })
		end
	end
	return sites
end

-- The lists a custom field may name, and how many words each holds.
local function vocabularies(): { [string]: number }
	local sizes: { [string]: number } = {}
	for name, words in pairs(AnalyticsConfig.Vocabulary) do
		sizes[name] = #words
	end
	local passes, products = 0, 0
	for _ in pairs(MonetizationConfig.Passes) do
		passes += 1
	end
	for _ in pairs(MonetizationConfig.Products) do
		products += 1
	end
	sizes.Pass = passes
	sizes.Product = products
	sizes.PurchaseKey = passes + products
	return sizes
end

----------------------------------------------------------------
-- Specs
----------------------------------------------------------------

describe("AnalyticsService.fields (E8-S2)", function()
	it("writes CustomField01 to CustomField03, in order, as text", function()
		local _world, analytics = started()
		expect(analytics.fields("Duel1v1", 3, "Win")).toEqual({
			CustomField01 = "Duel1v1",
			CustomField02 = "3",
			CustomField03 = "Win",
		})
		expect(analytics.fields("Vip")).toEqual({ CustomField01 = "Vip" })
		expect(analytics.fields("Product", "FolioSmall")).toEqual({
			CustomField01 = "Product",
			CustomField02 = "FolioSmall",
		})
	end)

	it("is keyed exactly as Roblox names its three custom fields", function()
		expect(AnalyticsConfig.FieldKeys).toEqual({ "CustomField01", "CustomField02", "CustomField03" })
	end)
end)

describe("AnalyticsService.custom (E8-S2)", function()
	it("sends an event of the catalogue with the fields it declares, counting 1 unless given a value", function()
		local world, analytics, player = started()
		analytics.custom(player, "PassPurchased", 399, analytics.fields("Vip"))
		analytics.custom(player, "PromptDeclined", nil, analytics.fields("Product", "FolioSmall"))
		local sent = world.analytics:of("LogCustomEvent")
		expect(#sent).toBe(2)
		expect(sent[1].Player).toBe(player)
		expect(sent[1].Args[1]).toBe("PassPurchased")
		expect(sent[1].Args[2]).toBe(399)
		expect(sent[1].Args[3]).toEqual({ CustomField01 = "Vip" })
		expect(sent[2].Args[2]).toBe(1)
		expect(sent[2].Args[3]).toEqual({ CustomField01 = "Product", CustomField02 = "FolioSmall" })
	end)

	it("refuses a key Roblox does not read, sends nothing and says so once", function()
		local world, analytics, player = started()
		analytics.custom(player, "ProductPurchased", 99, { product = "FolioSmall" } :: any)
		analytics.custom(player, "ProductPurchased", 99, { product = "FolioSmall" } :: any)
		expect(#world.analytics:of("LogCustomEvent")).toBe(0)
		expect(warnings(world, "custom event ProductPurchased dropped")).toBe(1)
	end)

	it("refuses a field that is not text", function()
		local world, analytics, player = started()
		analytics.custom(player, "PassPurchased", 399, { CustomField01 = 7 } :: any)
		expect(#world.analytics:of("LogCustomEvent")).toBe(0)
		expect(warnings(world, "is not text")).toBe(1)
	end)

	it("refuses fewer or more fields than the catalogue declares, or a gap between them", function()
		local world, analytics, player = started()
		analytics.custom(player, "PromptAccepted", nil, analytics.fields("Pass"))
		analytics.custom(player, "PassPurchased", 399, analytics.fields("Vip", "Extra"))
		analytics.custom(player, "ProductPurchased", 99, nil)
		analytics.custom(player, "PromptDeclined", nil, analytics.fields("Pass", nil, "Vip"))
		expect(#world.analytics:of("LogCustomEvent")).toBe(0)
		expect(warnings(world, "declared")).toBe(2)
		expect(warnings(world, "is not one it declares")).toBe(2)
	end)

	it("refuses a name the catalogue does not hold", function()
		local world, analytics, player = started()
		analytics.custom(player, "SomethingNew", nil, analytics.fields("x"))
		expect(#world.analytics:of("LogCustomEvent")).toBe(0)
		expect(warnings(world, "SomethingNew dropped: not in AnalyticsConfig.Events")).toBe(1)
	end)
end)

describe("every custom event of src/server (E8-S2)", function()
	it("names an event of the catalogue in words, and builds its fields with fields()", function()
		local sites = customCalls()
		expect(#sites).toBeGreaterThanOrEqual(5)
		for _, site in ipairs(sites) do
			local where = site.Path .. ": custom(" .. table.concat(site.Arguments, ", ") .. ")"
			local name = site.Arguments[2]:match('^"([%w_]+)"$')
			if name == nil or AnalyticsConfig.Events[name] == nil then
				error(where .. " does not name an event of AnalyticsConfig.Events in words")
			end
			local fields = site.Arguments[4]
			if fields ~= nil and fields ~= "nil" and fields:match("^[%w_%.]+%.fields%(") == nil then
				error(where .. " builds its custom fields without fields()")
			end
		end
	end)

	it("never hands the analytics a table of keys of its own", function()
		for _, site in ipairs(customCalls()) do
			for _, key in ipairs({ "product", "pass" }) do
				if site.Text:find("{%s*" .. key .. "%s*=") ~= nil then
					error(("%s still writes { %s = … }, a key Roblox never reads"):format(site.Path, key))
				end
			end
			if site.Text:find("{", 1, true) ~= nil then
				error(site.Path .. " writes custom fields by hand: " .. site.Text)
			end
		end
	end)

	it("sends every event of the catalogue, whose fields each name a list the game keeps", function()
		local sent: { [string]: boolean } = {}
		for _, site in ipairs(customCalls()) do
			local name = site.Arguments[2]:match('^"([%w_]+)"$')
			if name ~= nil then
				sent[name] = true
			end
		end
		local sizes = vocabularies()
		for name, declared in pairs(AnalyticsConfig.Events) do
			if not sent[name] then
				error(name .. " is in AnalyticsConfig.Events and nothing sends it")
			end
			expect(#declared).toBeLessThanOrEqual(#AnalyticsConfig.FieldKeys)
			for _, field in ipairs(declared) do
				if sizes[field] == nil or sizes[field] == 0 then
					error(("%s declares the field %s, which names no list"):format(name, field))
				end
			end
		end
	end)
end)

return nil
