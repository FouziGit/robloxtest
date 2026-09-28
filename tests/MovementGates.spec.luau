--!strict
-- The movement guard's wiring, held to the promises no Lune test can run: every piece here needs an engine,
-- so their sources are read. The judge itself is pure and proved on whole motions elsewhere
-- (tests/MovementScenarios.spec.luau); these gates are about what the services around it must keep doing
-- for its verdicts to mean anything.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ANTICHEAT = "src/server/Services/AntiCheatService.luau"
local COMBAT = "src/server/Services/CombatService.luau"
local REGISTRY = "src/server/RemoteRegistry.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

-- Whether `first` appears in `text`, and `later` after it.
local function ordered(text: string, first: string, later: string): boolean
	local at = text:find(first, 1, true)
	return at ~= nil and text:find(later, at + #first, true) ~= nil
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

-- The anchor OriginGuard judges actions against (CombatService.trustedCFrame). Its arithmetic is pure and
-- simulated in tests/OriginGuard.spec.luau, on a model of this function; these hold the function to that model.
describe("the trusted anchor", function()
	it("is judged by follow, and only an action may spend the tolerance", function()
		local trusted = functionIn(COMBAT, "local function trustedCFrame(")
		expect(trusted).toContain(
			"OriginGuard.follow(travelled, elapsed, allowance, strikeOnFailure, state.ToleranceSpent, GUARD)"
		)
		expect(trusted).toContain("state.ToleranceSpent = toleranceSpent")
		expect(trusted).never.toContain("OriginGuard.judge(")
	end)

	it("never stores a position that is not a sane number", function()
		local trusted = functionIn(COMBAT, "local function trustedCFrame(")
		-- Checked before anything is stored, the first sample of a body included.
		expect(ordered(trusted, "if not isSanePosition(position) then", "state.TrustedPosition =")).toBe(true)
		expect(trusted).toContain(
			"if not isSanePosition(position) then return if trusted ~= nil then CFrame.new(trusted) else observed end"
		)
		expect(functionIn(COMBAT, "local function isSanePosition(")).toContain(
			"local limit = MovementGuardConfig.MaxCoordinateStuds"
		)
	end)

	it("chases, and counts no violation while it converges after a stall", function()
		local trusted = functionIn(COMBAT, "local function trustedCFrame(")
		expect(trusted).toContain("if elapsed >= MovementGuardConfig.StallSeconds then state.Converging = true end")
		-- The clock restarts with every step of the chase, so the anchor never gains faster than the ceiling.
		expect(trusted).toContain(
			"local chased = trusted + flatDelta.Unit * advance local anchor = Vector3.new(chased.X, position.Y, chased.Z) state.TrustedPosition = anchor state.TrustedAt = now"
		)
		expect(ordered(trusted, 'if verdict == "Accepted" then state.Converging = false', "return observed")).toBe(true)
		expect(trusted).toContain(
			'if verdict == "Refused" and strikeOnFailure and not state.Converging then countViolation('
		)
		local _, violations = trusted:gsub("countViolation%(", "")
		expect(violations).toBe(1)
	end)

	it("starts every body and every server teleport with the tolerance whole and nothing converging", function()
		for _, header in ipairs({ "function CombatService.resyncPosition(", "local function resetState(" }) do
			local reset = functionIn(COMBAT, header)
			expect(reset).toContain("state.ToleranceSpent = false")
			expect(reset).toContain("state.Converging = false")
		end
	end)
end)
