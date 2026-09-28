--!strict
-- The movement guard's wiring, held to the promises no Lune test can run: every piece here needs an engine,
-- so their sources are read. The judge itself is pure and proved on whole motions elsewhere
-- (tests/MovementScenarios.spec.luau); these gates are about what the services around it must keep doing
-- for its verdicts to mean anything.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ANTICHEAT = "src/server/Services/AntiCheatService.luau"
local REGISTRY = "src/server/RemoteRegistry.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- One function of a file, from its header to the first `end` at its own indentation, whitespace folded; or an
-- error: a gate that found nothing would pass.
local function functionIn(path: string, header: string, indent: string?): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local close = "\n" .. (indent or "") .. "end\n"
	local finish = source:find(close, start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + #close - 1):gsub("%s+", " "))
end

describe("a Movement strike", function()
	it("is counted against its own threshold, from the server-only config", function()
		local threshold = functionIn(ANTICHEAT, "local function thresholdFor(")
		expect(threshold).toContain('if kind == "Movement" then return MovementGuardConfig.KickThreshold end')
		local source = strip(fs.readFile(ANTICHEAT))
		expect(source).toContain("require(script.Parent.Parent.Config.MovementGuardConfig)")
		expect(source).toContain('export type StrikeKind = "Schema" | "RateLimit" | "Origin" | "Movement"')
	end)
end)

describe("remote liveness", function()
	it("is stamped only once a call has passed validation, on events and on functions", function()
		-- Right after the refusal returns and before the handler runs: a refused call proves nothing, and a
		-- handler that throws was still sent by a live client.
		local refusals = {
			["function registry.on("] = "if not validate(player, name, args, args.n) then return end",
			["function registry.setCallback("] = "if not validate(player, name, args, args.n) then return nil end",
		}
		for header, refusal in pairs(refusals) do
			local entry = functionIn(REGISTRY, header, "\t")
			expect(entry).toContain(refusal .. " lastInbound[player] = os.clock()")
			local _, stamps = entry:gsub("lastInbound%[player%] = os%.clock%(%)", "")
			expect(stamps).toBe(1)
		end
	end)

	it("is read as never for a player with no valid call, and forgotten when the player leaves", function()
		expect(functionIn(REGISTRY, "function registry.lastInbound(", "\t")).toContain(
			"return lastInbound[player] or -math.huge"
		)
		expect(functionIn(REGISTRY, "function registry.removePlayer(", "\t")).toContain("lastInbound[player] = nil")
	end)
end)
