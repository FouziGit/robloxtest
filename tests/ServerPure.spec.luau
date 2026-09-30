--!strict
-- What ships to every client, and what stays on the server (E9-S8, D-217).
--
-- src/shared is ReplicatedStorage: every module in it is downloaded by every player, and a client can read it. A
-- pure module that only the server requires has no business there. The movement judge, the origin judge and the
-- Forgers' brain were all in src/shared/Pure: every slack, window and reaction time they decide with could be read
-- off the client, which is all a cheat needs to fly or blink just inside them. They live in src/server/Pure now,
-- under ServerScriptService, which no client ever receives.
--
-- These gates keep it that way from the sources: a module of src/shared/Pure that neither the client nor the
-- interface requires is refused, and every require of a pure module names a file that exists where it looks for
-- it -- which is what a merge that still asks Shared.Pure for a module that moved would get wrong. The built place
-- is checked too, after the build (tests/place.luau).
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SHARED_PURE = "src/shared/Pure"
local SERVER_PURE = "src/server/Pure"
-- The two sides a player downloads and runs.
local CLIENT_ROOTS = { "src/client", "src/ui" }
local ALL_ROOTS = { "src/client", "src/ui", "src/server", "src/shared" }

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

local function modulesIn(directory: string): { string }
	local names: { string } = {}
	for _, entry in ipairs(fs.readDir(directory)) do
		local name = entry:match("^(.-)%.luau$")
		if name ~= nil then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

-- Every pure module a source requires: its name, and whether it is asked of ReplicatedStorage ("Shared") or of
-- the server's own tree ("Server"). The three forms in use: `Shared.Pure.X`, `...:WaitForChild("Pure"):WaitForChild("X")`
-- (or a `Pure` local bound to that folder), and `script.Parent...Pure.X`.
type Wanted = { Name: string, Side: "Shared" | "Server" }

local function pureRequires(source: string): { Wanted }
	local found: { Wanted } = {}
	for call in source:gmatch("require(%b())") do
		local dotted = call:match("Pure%.([%w_]+)%)$")
		local waited = call:match('Pure"?%)?:WaitForChild%("([%w_]+)"%)%)$')
		local name = dotted or waited
		if name ~= nil then
			local side: "Shared" | "Server" = if call:match("^%(script[%.%w_]*%.Pure%.") then "Server" else "Shared"
			table.insert(found, { Name = name, Side = side })
		end
	end
	return found
end

local function requiredBy(roots: { string }): { [string]: { string } }
	local users: { [string]: { string } } = {}
	for _, root in ipairs(roots) do
		local files: { string } = {}
		collect(root, files)
		for _, path in ipairs(files) do
			for _, wanted in ipairs(pureRequires(code(path))) do
				local list = users[wanted.Name] or {}
				table.insert(list, path)
				users[wanted.Name] = list
			end
		end
	end
	return users
end

describe("the pure modules a client downloads", function()
	it("are found by the require patterns, so nothing below passes vacuously", function()
		local users = requiredBy(CLIENT_ROOTS)
		local count = 0
		for _ in pairs(users) do
			count += 1
		end
		expect(count).toBeGreaterThanOrEqual(20)
		-- Each form the sources use is recognised.
		expect(#pureRequires("local A = require(Shared.Pure.Spring)")).toBe(1)
		expect(#pureRequires('local A = require(Pure:WaitForChild("Claimables"))')).toBe(1)
		expect(#pureRequires('local A = require(Shared:WaitForChild("Pure"):WaitForChild("RankTiers"))')).toBe(1)
		expect(pureRequires("local A = require(script.Parent.Parent.Pure.Elo)")[1].Side).toBe("Server")
		expect(pureRequires("local A = require(Shared.Pure.Elo)")[1].Side).toBe("Shared")
	end)

	it(
		"are each required by the client or the interface: a module only the server wants lives in src/server/Pure",
		function()
			local users = requiredBy(CLIENT_ROOTS)
			local strays: { string } = {}
			for _, name in ipairs(modulesIn(SHARED_PURE)) do
				if users[name] == nil then
					table.insert(
						strays,
						("%s/%s.luau is replicated to every player, and neither src/client nor src/ui requires it: move it to %s"):format(
							SHARED_PURE,
							name,
							SERVER_PURE
						)
					)
				end
			end
			if #strays > 0 then
				error(table.concat(strays, "\n"))
			end
		end
	)

	it("never include the movement judge, the origin judge or the Forgers' brain", function()
		for _, name in ipairs({ "MovementGuard", "OriginGuard", "BotBrain" }) do
			expect(fs.isFile(("%s/%s.luau"):format(SHARED_PURE, name))).toBe(false)
			expect(fs.isFile(("%s/%s.luau"):format(SERVER_PURE, name))).toBe(true)
		end
	end)
end)

describe("every require of a pure module", function()
	it("names a file that exists on the side it asks", function()
		local shared, server = {}, {}
		for _, name in ipairs(modulesIn(SHARED_PURE)) do
			shared[name] = true
		end
		for _, name in ipairs(modulesIn(SERVER_PURE)) do
			server[name] = true
		end
		expect(#modulesIn(SERVER_PURE)).toBeGreaterThanOrEqual(10)
		local broken: { string } = {}
		for _, root in ipairs(ALL_ROOTS) do
			local files: { string } = {}
			collect(root, files)
			for _, path in ipairs(files) do
				for _, wanted in ipairs(pureRequires(code(path))) do
					local exists = if wanted.Side == "Server" then server[wanted.Name] else shared[wanted.Name]
					if not exists then
						table.insert(
							broken,
							("%s requires %s from %s, where there is no such module"):format(
								path,
								wanted.Name,
								if wanted.Side == "Server" then SERVER_PURE else SHARED_PURE
							)
						)
					end
				end
			end
		end
		if #broken > 0 then
			error(table.concat(broken, "\n"))
		end
	end)

	it("from the client or the interface never reaches for the server's tree", function()
		for _, root in ipairs(CLIENT_ROOTS) do
			local files: { string } = {}
			collect(root, files)
			for _, path in ipairs(files) do
				for _, wanted in ipairs(pureRequires(code(path))) do
					if wanted.Side == "Server" then
						error(
							("%s requires %s from the server's tree, which a client never has"):format(
								path,
								wanted.Name
							)
						)
					end
				end
				expect(code(path):find("ServerScriptService", 1, true)).toBeNil()
			end
		end
	end)
end)
