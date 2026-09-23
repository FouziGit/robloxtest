--!strict
-- One loop per system, and the list of them is here.
--
-- The convention (CLAUDE.md, docs/ARCHITECTURE.md): no per-player loop, and every system that needs a tick
-- opens exactly ONE. It is the rule that decides whether a full server costs nine connections or nine
-- hundred, and nothing else in the repository can see it: a second `Heartbeat:Connect` inside a service
-- that already has one passes every other gate, runs correctly, and costs a connection per system per
-- session for the rest of the game's life.
--
-- It is also the closest a Lune test can come to the phase 9 promise that "a duel leaves no connection
-- behind": a connection that is never opened cannot leak, and a system whose loop is not in this list has
-- to be added here with a reason.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ROOTS = { "src/server", "src/client", "src/ui", "src/shared" }
-- Vendored ProfileStore opens its own; it is not ours to change (docs/DECISIONS.md D-4).
local IGNORED = "/Vendor/"

-- Every way to ask the engine for a per-frame callback.
local PATTERNS = {
	"Heartbeat:Connect",
	"RenderStepped:Connect",
	"Stepped:Connect",
	"PreSimulation:Connect",
	"PostSimulation:Connect",
	"PreRender:Connect",
	"BindToRenderStep",
}

-- path -> how many loops that file is allowed, and why it has one at all.
local ALLOWED: { [string]: { Count: number, Why: string } } = {
	-- Server: nine, each on an accumulator at GameConfig.Server.TickRate.
	["src/server/Services/CombatService.luau"] = { Count = 1, Why = "ink, cooldowns and the travel audit" },
	["src/server/Services/MovementService.luau"] = { Count = 1, Why = "stuns, slows and freezes expiring" },
	["src/server/Services/MatchService.luau"] = { Count = 1, Why = "match phases and snapshots" },
	["src/server/Services/MatchmakingService.luau"] = { Count = 1, Why = "the queue scan" },
	["src/server/Services/QuestService.luau"] = { Count = 1, Why = "period rollover" },
	["src/server/Services/ShopService.luau"] = { Count = 1, Why = "the daily rotation" },
	["src/server/Services/LeaderboardService.luau"] = { Count = 1, Why = "the board refresh" },
	["src/server/Services/WorldBossService/init.luau"] = { Count = 1, Why = "the event schedule and the fight" },
	["src/server/Services/VfxBroadcaster.luau"] = {
		Count = 1,
		Why = "invalidating the recipient snapshot once a frame",
	},
	-- Client: seven, and one of them is the only render-step binding in the game.
	["src/client/Controllers/Feel.luau"] = { Count = 1, Why = "the camera, which only Feel may write" },
	["src/client/Controllers/VfxTimeline.luau"] = { Count = 1, Why = "every layer of every effect" },
	["src/client/Controllers/WorldLighting.luau"] = { Count = 1, Why = "the post-processing pulses" },
	["src/client/Controllers/FootprintController.luau"] = { Count = 1, Why = "the prints of every character" },
	["src/client/Controllers/Posture.luau"] = { Count = 1, Why = "the joints of every character" },
	["src/client/Controllers/CosmeticController.luau"] = {
		Count = 1,
		Why = "orbiting strokes and walking dust of every worn cosmetic",
	},
	["src/client/Controllers/QualityController.luau"] = { Count = 1, Why = "the frame rate it decides the tier from" },
	-- Interface: one, opened when something moves and closed when nothing does.
	["src/ui/Motion.luau"] = { Count = 1, Why = "every spring in the interface" },
}

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function loopsPerFile(): { [string]: number }
	local files: { string } = {}
	for _, root in ipairs(ROOTS) do
		collect(root, files)
	end
	assert(#files > 40, "found almost no sources: the roots are wrong")
	local counts: { [string]: number } = {}
	for _, path in ipairs(files) do
		if string.find(path, IGNORED, 1, true) == nil then
			local code = stripComments(fs.readFile(path))
			local found = 0
			for _, pattern in ipairs(PATTERNS) do
				local from = 1
				while true do
					local at = string.find(code, pattern, from, true)
					if at == nil then
						break
					end
					found += 1
					from = at + 1
				end
			end
			if found > 0 then
				counts[path] = found
			end
		end
	end
	return counts
end

describe("per-frame loops", function()
	local counts = loopsPerFile()

	it("exist, so nothing below passes vacuously", function()
		local total = 0
		for _, count in pairs(counts) do
			total += count
		end
		expect(total).toBeGreaterThanOrEqual(15)
	end)

	it("are one per system, and every one of them is declared here", function()
		local problems: { string } = {}
		for path, count in pairs(counts) do
			local allowed = ALLOWED[path]
			if allowed == nil then
				table.insert(
					problems,
					("%s opens %d per-frame loop(s) and is not in the list: add it with the reason it needs one"):format(
						path,
						count
					)
				)
			elseif count > allowed.Count then
				table.insert(
					problems,
					("%s opens %d loops and is allowed %d (%s)"):format(path, count, allowed.Count, allowed.Why)
				)
			end
		end
		table.sort(problems)
		if #problems > 0 then
			error("one loop per system (CLAUDE.md):\n" .. table.concat(problems, "\n"))
		end
	end)

	it("still all exist: a system that lost its loop stopped ticking", function()
		local missing: { string } = {}
		for path, allowed in pairs(ALLOWED) do
			if counts[path] == nil then
				table.insert(missing, ("%s is listed for %s and has no loop at all"):format(path, allowed.Why))
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(table.concat(missing, "\n"))
		end
	end)
end)
