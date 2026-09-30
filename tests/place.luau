--!strict
-- Gates on the BUILT place, not on the sources: what Rojo actually wrote into build/Vellum.rbxl is what Roblox
-- ships. scripts/check.sh runs this right after `rojo build`; it is not a spec, because the specs run before
-- the build and a stale place would prove nothing.
--
-- Usage: lune run tests/place [path/to/place.rbxl]
local Harness = require("./harness")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PLACE = process.args[1] or "build/Vellum.rbxl"

if not fs.isFile(PLACE) then
	print(("✖ no built place at %s: run rojo build first"):format(PLACE))
	process.exit(1)
end

local game = roblox.deserializePlace(fs.readFile(PLACE))

-- A child the FILE holds. GetService would make one up with the engine's defaults, which is exactly what a
-- missing pin must not be allowed to pass as.
local function child(parent: any, className: string): any
	for _, each in ipairs(parent:GetChildren()) do
		if each.ClassName == className then
			return each
		end
	end
	return nil
end

-- The server-only pure modules (E9-S8, D-217): what they decide with must never reach a client.
describe("the built place keeps the server's judges on the server", function()
	local replicated = child(game, "ReplicatedStorage")
	local server = child(game, "ServerScriptService")

	it("has the two trees, so nothing below passes vacuously", function()
		expect(replicated).never.toBeNil()
		expect(server).never.toBeNil()
		local shared = replicated:FindFirstChild("Shared")
		expect(shared).never.toBeNil()
		expect(#shared:FindFirstChild("Pure"):GetChildren()).toBeGreaterThanOrEqual(20)
	end)

	it("replicates no module of src/server/Pure, under any name", function()
		local serverPure = server:FindFirstChild("Pure")
		expect(serverPure).never.toBeNil()
		local names: { [string]: boolean } = {}
		for _, module in ipairs(serverPure:GetChildren()) do
			expect(module.ClassName).toBe("ModuleScript")
			names[module.Name] = true
		end
		for _, name in ipairs({ "MovementGuard", "OriginGuard", "BotBrain" }) do
			expect(names[name]).toBe(true)
		end
		for _, each in ipairs(replicated:GetDescendants()) do
			if names[each.Name] then
				error(
					("%s is under ReplicatedStorage (%s): every client downloads it"):format(
						each.Name,
						each:GetFullName()
					)
				)
			end
		end
	end)
end)

-- The Workspace's streaming, pinned in default.project.json (E6-S7, D-221). A place with no Workspace, or a Workspace
-- without these properties, takes whatever defaults the engine has that day: exactly what the pin is there to stop.
-- A value equal to Lune's own default reads the same whether it is written or not, so the project's declaration is
-- read too: removing either the Workspace or one of its properties fails here.
local PINNED: { [string]: any } = {
	StreamingEnabled = false,
	StreamingIntegrityMode = roblox.Enum.StreamingIntegrityMode.PauseOutsideLoadedArea,
	StreamingMinRadius = 64,
	StreamingTargetRadius = 1024,
	StreamOutBehavior = roblox.Enum.StreamOutBehavior.LowMemory,
	ModelStreamingBehavior = roblox.Enum.ModelStreamingBehavior.Improved,
}

describe("the built place's Workspace", function()
	local workspace = child(game, "Workspace")

	it("is in the file, not made up by the engine", function()
		expect(workspace).never.toBeNil()
	end)

	it("holds every streaming value the decision chose", function()
		for property, value in pairs(PINNED) do
			local built = workspace[property]
			if built ~= value then
				error(
					("Workspace.%s is %s in the built place, the decision is %s"):format(
						property,
						tostring(built),
						tostring(value)
					)
				)
			end
		end
	end)

	it("is declared with every one of them in default.project.json", function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local declared = project.tree.Workspace
		expect(declared).never.toBeNil()
		expect(declared["$className"]).toBe("Workspace")
		local properties = declared["$properties"]
		for property, value in pairs(PINNED) do
			local written = properties[property]
			local expected = if typeof(value) == "EnumItem" then value.Name else value
			if written ~= expected then
				error(
					("default.project.json pins Workspace.%s to %s, the decision is %s"):format(
						property,
						tostring(written),
						tostring(expected)
					)
				)
			end
		end
	end)
end)

local summary = Harness.run()
for _, failure in ipairs(summary.failures) do
	print(("✖ %s\n    %s"):format(failure.path, failure.message))
end
print(("%d passed, %d failed on %s"):format(summary.passed, summary.failed, PLACE))
process.exit(if summary.failed == 0 then 0 else 1)
