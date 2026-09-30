--!strict
-- The movement guard's wiring, held to the promises no Lune test can run: every piece here needs an engine,
-- so their sources are read. The judge itself is pure and proved on whole motions elsewhere
-- (tests/MovementScenarios.spec.luau); these gates are about what the services around it must keep doing
-- for its verdicts to mean anything.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/shared/Pure/BattlegroundLayout")
local BotConfig = require("../src/shared/Config/BotConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local MovementGuardConfig = require("../src/server/Config/MovementGuardConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ANTICHEAT = "src/server/Services/AntiCheatService.luau"
local COMBAT = "src/server/Services/CombatService.luau"
local ARENA = "src/server/Services/ArenaService.luau"
local HUB = "src/server/Services/HubService.luau"
local BATTLEGROUND_MAP = "src/server/Services/BattlegroundService/Map.luau"
local TAG_BARRIER = "CollectionService:AddTag(part, MovementGuardConfig.BarrierTag)"
local REGISTRY = "src/server/RemoteRegistry.luau"
local AUDIT_MODULE = "src/server/Security/MovementAudit.luau"
local GUARD = "src/shared/Pure/MovementGuard.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function count(text: string, needle: string): number
	local found, from = 0, 1
	while true do
		local at = text:find(needle, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + #needle
	end
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

	it("chases, and counts no violation while it converges after a stall, for as long as that can take", function()
		local trusted = functionIn(COMBAT, "local function trustedCFrame(")
		-- Bounded: a latch that lasted until the next accepted sample let one second of stillness and one blink
		-- turn off every Origin violation of a client that then kept outrunning the chase.
		expect(trusted).toContain(
			"if elapsed >= MovementGuardConfig.StallSeconds then state.ConvergingUntil = now + OriginGuard.convergeSeconds( travelled - advance, MovementGuardConfig.StallSpeedStudsPerSecond, MovementGuardConfig.StallCapSeconds, GUARD ) end"
		)
		-- The clock restarts with every step of the chase, so the anchor never gains faster than the ceiling.
		expect(trusted).toContain(
			"local chased = trusted + flatDelta.Unit * advance local anchor = Vector3.new(chased.X, position.Y, chased.Z) state.TrustedPosition = anchor state.TrustedAt = now"
		)
		expect(ordered(trusted, 'if verdict == "Accepted" then state.ConvergingUntil = -math.huge', "return observed")).toBe(
			true
		)
		expect(trusted).toContain(
			'if verdict == "Refused" and strikeOnFailure and now >= state.ConvergingUntil then countViolation('
		)
		local _, violations = trusted:gsub("countViolation%(", "")
		expect(violations).toBe(1)
		expect(strip(fs.readFile(COMBAT))).never.toContain("Converging =")
	end)

	it("holds its anchor, whole, through a server pivot's stale samples", function()
		local trusted = functionIn(COMBAT, "local function trustedCFrame(")
		-- Before anything the verdict would change is stored: no advance, no allowance, no tolerance. Only the clock
		-- restarts, so the budget cannot grow through the wait into accepting a stale sample.
		expect(trusted).toContain(
			'OriginGuard.follow(travelled, elapsed, allowance, strikeOnFailure, state.ToleranceSpent, GUARD) if verdict ~= "Still" and verdict ~= "Accepted" and settling(state, now) then state.TrustedAt = now return CFrame.new(trusted) * (observed - position) end state.TravelAllowanceStuds = allowanceLeft'
		)
		-- The window the audit waits out after a pivot, on the round trip the audit reads.
		expect(functionIn(COMBAT, "local function settling(")).toContain(
			"local since = now - state.TeleportAt return since < AUDIT.SettleMaxSeconds and since < MovementGuard.settle(MovementAudit.rtt(state.Player), AUDIT)"
		)
		expect(functionIn(GUARD, "local function pending(")).toContain(
			"local settle = MovementGuard.settle(s.Rtt, config) if age < settle then return none() end"
		)
		-- Every server pivot starts it: a teleport, and the audit's own correction or repivot.
		expect(functionIn(COMBAT, "function CombatService.resyncPosition(")).toContain(
			"anchorOn(state, position, now, true) state.TeleportAt = now"
		)
		expect(functionIn(COMBAT, "local function reanchor(")).toContain(
			"local now = os.clock() anchorOn(state, position, now, false) state.TeleportAt = now"
		)
	end)

	it("starts every body and every server teleport with the tolerance whole and nothing converging", function()
		-- One place resets the anchor, and every way onto a new point goes through it.
		local anchor = functionIn(COMBAT, "local function anchorOn(")
		expect(anchor).toContain(
			"state.TrustedPosition = position state.TrustedAt = now state.TravelAllowanceStuds = 0 state.TravelAllowanceUntil = 0 state.ToleranceSpent = false state.ConvergingUntil = -math.huge state.TeleportAt = -math.huge if clearViolations then table.clear(state.OriginViolations) end"
		)
		local resync = functionIn(COMBAT, "function CombatService.resyncPosition(")
		expect(resync).toContain(
			"if position == nil then local root = playerRoot(player) anchorOn(state, if root ~= nil then root.Position else nil, now, true) return end anchorOn(state, position, now, true)"
		)
		local reset = functionIn(COMBAT, "local function resetState(")
		expect(reset).toContain("anchorOn(state, spawnPoint(character), now, true)")
		-- A correction keeps the violations: pulling a body back absolves nothing.
		expect(functionIn(COMBAT, "local function reanchor(")).toContain(
			"if state ~= nil then local now = os.clock() anchorOn(state, position, now, false)"
		)
		-- Neither sets the anchor by hand, so neither can forget a field of it.
		for _, entry in ipairs({ resync, reset }) do
			expect(entry).never.toContain("state.TrustedPosition =")
			expect(entry).never.toContain("state.ToleranceSpent =")
		end
	end)

	it(
		"counts a violation only for what the player chose: the cast and the swing, never a loop of the server's",
		function()
			-- The same anchor either way; only an action may count a violation or spend the tolerance
			-- (tests/OriginGuard.spec.luau, "a server loop's origin through a network freeze").
			expect(functionIn(COMBAT, "function CombatService.trustedOrigin(")).toContain(
				"return trustedCFrame(state, root, os.clock(), true)"
			)
			expect(functionIn(COMBAT, "function CombatService.currentOrigin(")).toContain(
				"if state == nil or root == nil then return nil end return trustedCFrame(state, root, os.clock(), false)"
			)
			expect(functionIn(COMBAT, "local function onMelee(")).toContain(
				"local rootCFrame = trustedCFrame(state, root, now, true)"
			)
			local source = strip(fs.readFile(COMBAT))
			expect(count(source, "trustedCFrame(state, root, now, true)")).toBe(1)
			expect(count(source, "trustedCFrame(state, root, os.clock(), true)")).toBe(1)
			expect(count(source, "trustedCFrame(state, root, os.clock(), false)")).toBe(1)
			expect(count(source, "trustedCFrame(state, sampleRoot, now, false)")).toBe(1)
			expect(count(source, "trustedCFrame(")).toBe(5)
			-- The cast is the player's action.
			expect(functionIn("src/server/Services/GlyphService.luau", "local function onCastGlyph(")).toContain(
				"local origin = combat.trustedOrigin(player) if origin == nil then return end"
			)
			-- Every loop an effect runs after it asks for the current origin: the charge's release, the Scorch's ticks,
			-- the Stitch's pull and the Hatching's strokes, and nothing in the effects judges an action.
			local EFFECTS = "src/server/Effects/GlyphEffects.luau"
			local loops = {
				["local function charge("] = "local frame = ctx.Combat.currentOrigin(ctx.Caster)",
				["function GlyphEffects.Scorch("] = "local centre = ctx.Combat.currentOrigin(ctx.Caster)",
				["function GlyphEffects.Stitch("] = "local anchor = ctx.Combat.currentOrigin(ctx.Caster)",
				["function GlyphEffects.Hatching("] = "local frame = ctx.Combat.currentOrigin(ctx.Caster)",
			}
			for header, ask in pairs(loops) do
				expect(functionIn(EFFECTS, header)).toContain(ask)
			end
			local effects = strip(fs.readFile(EFFECTS))
			expect(count(effects, "ctx.Combat.currentOrigin(")).toBe(4)
			expect(effects).never.toContain("trustedOrigin")
		end
	)
end)

-- CombatService around the audit: every server-authored move reaches it, and nothing it is told comes from the
-- client.
describe("the movement audit's wiring", function()
	it("is stepped once per tick, after every player, with the server's own hitch, under its own label", function()
		local beat = functionIn(COMBAT, "local function onHeartbeat(")
		expect(beat).toContain(
			'for player, state in pairs(states) do tickPlayer(player, state, now, elapsed, replicate) end debug.profilebegin(AUDIT_PROFILE_LABEL) log.try("MovementAudit.step", MovementAudit.step, now, elapsed > MovementGuardConfig.HitchSeconds) debug.profileend() end'
		)
		expect(count(strip(fs.readFile(COMBAT)), "MovementAudit.step,")).toBe(1)
		expect(strip(fs.readFile(COMBAT))).toContain('local AUDIT_PROFILE_LABEL = "MovementAudit"')
	end)

	it("is given every server grant, a knockback's lift apart from its flat distance", function()
		local grant = functionIn(COMBAT, "function CombatService.grantMovement(")
		expect(grant).toContain(
			'local now = os.clock() local rtt = MovementAudit.rtt(player) if command.Kind == "Dash" then allowTravel(state, command.Distance, command.Duration, now, rtt) MovementAudit.grant(player, command.Distance, 0, command.Duration)'
		)
		expect(grant).toContain(
			'elseif command.Kind == "Knockback" then local velocity = command.Velocity local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude * command.Duration local lift = math.max(0, velocity.Y) * command.Duration allowTravel(state, flat, command.Duration, now, rtt) MovementAudit.grant(player, flat, lift, command.Duration) end'
		)
		expect(
			ordered(
				grant,
				"MovementAudit.grant(player, flat, lift, command.Duration)",
				"movement.command(player, command)"
			)
		).toBe(true)
	end)

	it("holds OriginGuard's allowance open by the audit's grace, and caps it", function()
		expect(functionIn(COMBAT, "local function allowTravel(")).toContain(
			"local deadline = now + seconds + MovementGuard.grace(rtt, AUDIT) if now >= state.TravelAllowanceUntil then state.TravelAllowanceStuds = 0 end state.TravelAllowanceStuds = math.min(state.TravelAllowanceStuds + math.max(0, studs), AUDIT.MaxAllowanceStuds)"
		)
		-- The fixed half second it replaces is gone, so nothing can go back to reading it.
		expect((GameConfig.Latency :: any).AllowanceGraceSeconds).toBeNil()
	end)

	it(
		"follows a server teleport, and only one: a teleport without a position adopts nothing the client said",
		function()
			local resync = functionIn(COMBAT, "function CombatService.resyncPosition(")
			expect(resync).toContain(
				"anchorOn(state, position, now, true) state.TeleportAt = now state.TeleportCharacter = player.Character MovementAudit.teleported(player, position) end"
			)
			expect(ordered(resync, "if position == nil then", "return end anchorOn(state, position")).toBe(true)
			expect(count(resync, "MovementAudit.")).toBe(1)
		end
	)

	it("starts a new body where the engine spawned it, unless a teleport of that body already ran", function()
		local reset = functionIn(COMBAT, "local function resetState(")
		expect(reset).toContain(
			"if character ~= nil and state.TeleportCharacter == character then return end anchorOn(state, spawnPoint(character), now, true) if character ~= nil then MovementAudit.spawned(state.Player, character) end end"
		)
		-- The fields every body resets come first, so a kept teleport keeps nothing else of the old body.
		expect(ordered(reset, "state.HitMemory = {}", "if character ~= nil and state.TeleportCharacter")).toBe(true)
		expect(functionIn(COMBAT, "local function onCharacterAdded(")).toContain(
			"releaseCharacter(state, now) resetState(state, now, character)"
		)
		-- The root of this body standing on the pad, at its own height: a small avatar stands under 2 studs, an
		-- Rthro one over 4, and a default 3 put the judge's ground and first safe point beside the body.
		expect(functionIn(COMBAT, "local function spawnPoint(")).toContain(
			"local stand = if character ~= nil then MovementAudit.standingHeight(character) else MovementGuardConfig.DefaultStandHeightStuds return spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + stand, 0)"
		)
	end)

	it("is set up with CombatService, keeps a record per player, and learns of every body", function()
		expect(functionIn(COMBAT, "function CombatService.Init(")).toContain(
			"MovementAudit.init({ AntiCheat = antiCheat, Movement = movement, Registry = registry, Reanchor = reanchor, SpawnPoint = spawnPoint, }, AUDIT)"
		)
		local start = functionIn(COMBAT, "function CombatService.Start(")
		expect(ordered(start, "MovementAudit.start()", "Players.PlayerAdded:Connect(onPlayerAdded)")).toBe(true)
		local added = functionIn(COMBAT, "local function onPlayerAdded(")
		expect(
			ordered(added, "states[player] = state MovementAudit.add(player)", "onCharacterAdded(player, character)")
		).toBe(true)
		expect(functionIn(COMBAT, "local function onPlayerRemoving(")).toContain("MovementAudit.remove(player)")
	end)

	it("hands the judge every number it reads", function()
		-- The judge's Config type, and what CombatService adds to MovementGuardConfig for it: together they must
		-- cover it, or a key would read nil in the engine and nowhere under Lune (the simulator builds its own).
		local guard = fs.readFile(GUARD)
		local block = guard:match("\nexport type Config = {(.-)\n}")
		assert(block ~= nil, "MovementGuard has no Config type: this gate would check nothing")
		local builder = functionIn(COMBAT, "local function auditConfig(")
		expect(builder).toContain(
			"local config = table.clone(MovementGuardConfig) :: any config.Gravity = Workspace.Gravity"
		)
		local keys = 0
		for key in block:gmatch("\n\t(%w+): number,") do
			keys += 1
			if (MovementGuardConfig :: any)[key] == nil and builder:find("config." .. key .. " = ", 1, true) == nil then
				error("the judge reads " .. key .. ", which neither MovementGuardConfig nor auditConfig gives it")
			end
		end
		expect(keys).toBeGreaterThan(60)
	end)
end)

-- Every server teleport of a player's body must re-anchor both guards on the point the server chose, or the next
-- hitbox is built where the body was and the audit reads the move as a teleport.
describe("a server teleport of a player", function()
	-- The only PivotTo in src/server that moves something else than a player's body: file -> its receiver.
	local NOT_A_PLAYER: { [string]: string } = {
		["src/server/Services/ArenaService.luau"] = "clone", -- an arena, onto its slot
		["src/server/Services/WorldBossService/Encounter.luau"] = "boss.Model", -- the Erasure
		["src/server/Services/BattlegroundService/Bots.luau"] = "model", -- a Forger
	}

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

	-- The innermost function around `at`: its header up to the first `end` at its own indentation.
	local function enclosing(source: string, at: number): string?
		local best: string? = nil
		local bestStart = 0
		for start, indent in source:gmatch("()\n(\t*)[%w ]-function [%w_%.:]+%(") do
			local finish = source:find("\n" .. indent .. "end\n", start + 1, true)
			if start < at and finish ~= nil and finish > at and start > bestStart then
				best, bestStart = source:sub(start, finish), start
			end
		end
		return best
	end

	it("calls resyncPosition after its PivotTo, wherever it happens", function()
		local files: { string } = {}
		collect("src/server", files)
		local players, others = 0, 0
		for _, path in ipairs(files) do
			if path ~= AUDIT_MODULE then
				local source = strip(fs.readFile(path))
				for at in source:gmatch("()[%w_%.]+:PivotTo%(") do
					local receiver = source:match("^([%w_%.]+):PivotTo%(", at)
					if NOT_A_PLAYER[path] == receiver then
						others += 1
					else
						players += 1
						local body = enclosing(source, at)
						if body == nil then
							error(path .. ": a PivotTo of " .. tostring(receiver) .. " outside any function")
						end
						local pivot = body:find(":PivotTo(", 1, true) :: number
						if body:find("resyncPosition(", pivot, true) == nil then
							error(path .. ": " .. tostring(receiver) .. ":PivotTo is not followed by resyncPosition")
						end
					end
				end
			end
		end
		-- Caret, the Dagger, a match pad (twice), the hub, the Erasure's pads and the Battleground's camp.
		expect(players).toBe(7)
		expect(others).toBe(3)
	end)

	it("sends the destination itself, never a position read back from the body", function()
		for path, call in pairs({
			["src/server/Effects/GlyphEffects.luau"] = "ctx.Combat.resyncPosition(ctx.Caster, landing)",
			["src/server/Services/MatchService.luau"] = "combat.resyncPosition(player, position)",
			["src/server/Services/HubService.luau"] = "combat.resyncPosition(player, landing)",
			["src/server/Services/WorldBossService/Encounter.luau"] = "deps.Combat.resyncPosition(player, position)",
			["src/server/Services/BattlegroundService/Roster.luau"] = "deps.Combat.resyncPosition(player, landing)",
		}) do
			expect(strip(fs.readFile(path))).toContain(call)
		end
	end)
end)

-- The engine layer: what it measures, and what it may do with a verdict.
describe("the movement audit", function()
	local function audit(header: string): string
		return functionIn(AUDIT_MODULE, header)
	end

	it("reads nothing the client writes about its own body", function()
		-- Support comes from the server's spherecast, never FloorMaterial or the Humanoid's state, and no
		-- velocity is ever read: the only writes are the zeros after a pivot.
		local source = strip(fs.readFile(AUDIT_MODULE))
		for _, banned in ipairs({ "FloorMaterial", ":GetState(", "MoveDirection", ".Velocity" }) do
			if source:find(banned, 1, true) ~= nil then
				error("MovementAudit reads " .. banned)
			end
		end
		for _, velocity in ipairs({ "AssemblyLinearVelocity", "AssemblyAngularVelocity" }) do
			expect(count(source, velocity)).toBe(count(source, velocity .. " = Vector3.zero"))
		end
	end)

	it(
		"probes for support under every body on every tick, and stands on a player only if the world holds it",
		function()
			-- Every body's support is known before any is judged, and the sample reads it.
			expect(audit("function MovementAudit.step(")).toContain(
				"local bodies = gather() markContacts(bodies) markSupport(bodies)"
			)
			expect(audit("local function sampleOf(")).toContain("Supported = record.Supported,")
			-- The world first, seen by a probe blind to every player's body; a body found by the second probe carries
			-- this one only through MovementGuard.carried, on this tick's support alone. Last tick's word let two bodies
			-- hold each other up at any height.
			local support = audit("local function markSupport(")
			expect(support).toContain("worldProbe.FilterDescendantsInstances = excluded")
			expect(support).toContain(
				"if castDown(worldProbe, position, stand, radius, reach) ~= nil then world[n] = true else local hit = castDown(body.Record.Probe, position, stand, radius, reach) local owner = if hit ~= nil then bodyOf(hit.Instance) else nil if owner ~= nil then carrier[n] = index[owner] or 0 end end"
			)
			expect(support).toContain(
				"local held = MovementGuard.carried(world, carrier) for n, body in ipairs(bodies) do body.Record.Supported = held[n] end"
			)
			local source = (strip(fs.readFile(AUDIT_MODULE)):gsub("%s+", " "))
			expect(source).toContain(
				"worldProbe.FilterType = Enum.RaycastFilterType.Exclude worldProbe.RespectCanCollide = true"
			)
			expect(source).never.toContain("WasSupported")
			-- Every player's body, dead or not yet adopted: a corpse holds nobody up.
			expect(audit("local function gather(")).toContain(
				"table.clear(playerBodies) local bodies: { Body } = {} for player, record in pairs(records) do record.Supported = false local current = player.Character if current ~= nil then playerBodies[current] = true end"
			)
			expect(audit("local function bodyOf(")).toContain(
				"local owner = characters[ancestor] if owner ~= nil then return owner, true end if playerBodies[ancestor] then return nil, true end"
			)
			expect(audit("local function holdsUp(")).toContain(
				"local owner, isBody = bodyOf(instance) if owner ~= nil then return owner.Supported end return not isBody"
			)
			expect(audit("local function supportedAt(")).toContain(
				"local hit = castDown(record.Probe, origin, stand, AUDIT.GroundProbeRadiusStuds, AUDIT.GroundProbeSlackStuds) return hit ~= nil and holdsUp(hit.Instance)"
			)
			-- Every probe starts clear of the feet: a shape cast never sees what it starts inside, and a sphere centred on
			-- a small avatar's root started inside its ground (MovementGuard.probe, proved in tests/MovementGuard.spec).
			expect(audit("local function castDown(")).toContain(
				"local lift, depth = MovementGuard.probe(stand, radius, reach, AUDIT.ProbeClearanceStuds) return Workspace:Spherecast(origin + Vector3.new(0, lift, 0), radius, Vector3.new(0, -depth, 0), params)"
			)
			expect(count(source, "Workspace:Spherecast(")).toBe(1)
			local added = audit("function MovementAudit.add(")
			expect(added).toContain("probe.FilterType = Enum.RaycastFilterType.Exclude probe.RespectCanCollide = true")
			expect(added).toContain(
				"overlap.FilterType = Enum.RaycastFilterType.Exclude overlap.RespectCanCollide = true"
			)
			expect(audit("local function adopt(")).toContain(
				"record.Probe.FilterDescendantsInstances = { character } record.Overlap.FilterDescendantsInstances = { character }"
			)
		end
	)

	it("judges every avatar from its own standing height, a default body's only where none can be measured", function()
		-- The developer's avatar stands 2.89 studs, the default description 3.19, a small one under 2, an Rthro one
		-- over 4: a fixed 3 put the ground a teleport and a spawn start from beside the body.
		expect(audit("function MovementAudit.standingHeight(")).toContain(
			'local root = character:FindFirstChild(ROOT_PART_NAME) if root == nil or not root:IsA("BasePart") then return AUDIT.DefaultStandHeightStuds end return standHeight(character:FindFirstChildOfClass("Humanoid"), root)'
		)
		expect(audit("function MovementAudit.teleported(")).toContain(
			"local stand = MovementAudit.standingHeight(character) local groundY = groundUnder(record, position, stand)"
		)
		-- No root, no Humanoid, or no character yet: nowhere else.
		expect(count(strip(fs.readFile(AUDIT_MODULE)), "DefaultStandHeightStuds")).toBe(2)
		expect(count(strip(fs.readFile(COMBAT)), "DefaultStandHeightStuds")).toBe(1)
	end)

	it("audits a live body even without its Humanoid, and never a dead one", function()
		local gather = audit("local function gather(")
		expect(gather).toContain(
			"if character == nil or player.Character ~= character or character.Parent == nil then continue end"
		)
		expect(gather).toContain("if humanoid ~= nil and humanoid.Health <= 0 then continue end")
		expect(count(gather, "continue")).toBe(3)
		expect(audit("local function standHeight(")).toContain(
			"if humanoid == nil then return AUDIT.DefaultStandHeightStuds end return humanoid.HipHeight + root.Size.Y / 2"
		)
		expect(audit("local function walkSpeed(")).toContain(
			"return if humanoid ~= nil then humanoid.WalkSpeed else GameConfig.Movement.WalkSpeed"
		)
	end)

	it("tells the judge what the server measured and nothing else", function()
		local sample = audit("local function sampleOf(")
		for _, field in ipairs({
			"Down = deps.Movement.isDown(record.Player),",
			"Contact = body.Contact,",
			"Rtt = heldRtt(record, now),",
			"LastInboundAt = deps.Registry.lastInbound(record.Player),",
			"Hitch = hitch,",
			"if MovementGuard.wantsRay(record.Track, sample, config) then sample.Crossing = crossing(record.Track, position) end",
			"if MovementGuard.preview(record.Track, sample, config) then sample.SupportTops = scan(record, sample) end",
		}) do
			expect(sample).toContain(field)
		end
		-- The round trip rises at once and falls only once the hold is over. GetNetworkPing is read as one way until
		-- Studio says otherwise: twice it can only over-grant.
		expect(strip(fs.readFile(AUDIT_MODULE))).toContain("local PINGS_PER_ROUND_TRIP = 2\n")
		expect(audit("local function heldRtt(")).toContain(
			"local measured = PINGS_PER_ROUND_TRIP * record.Player:GetNetworkPing() if measured >= record.RttValue or now - record.RttAt >= AUDIT.RttHoldSeconds then record.RttValue = measured record.RttAt = now end return record.RttValue"
		)
	end)

	it("casts the barrier ray from the last point outside every barrier, against the tagged barriers only", function()
		local source = (strip(fs.readFile(AUDIT_MODULE)):gsub("%s+", " "))
		expect(source).toContain(
			"barrierParams.FilterType = Enum.RaycastFilterType.Include barrierParams.RespectCanCollide = true"
		)
		expect(audit("function MovementAudit.start(")).toContain(
			"watchParts(AUDIT.BarrierTag, barriers, noteBarriersChanged)"
		)
		local cross = audit("local function crossing(")
		expect(cross).toContain("local ox, oy, oz = MovementGuard.rayOrigin(track)")
		-- Whatever the step's length: a catch-up H1 forgives after a long stall runs past 200 studs, and a ray
		-- skipped above that let a blink through any wall.
		expect(cross).toContain(
			"local origin = Vector3.new(ox, oy, oz) local hit = Workspace:Raycast(origin, position - origin, barrierFilter()) if hit == nil then return nil end"
		)
		expect(cross).never.toContain("Magnitude")
		expect((MovementGuardConfig :: any).RaySkipStuds).toBeNil()
		-- Where the step ended: inside the barrier it hit, the next ray still starts outside it.
		expect(cross).toContain("Inside = MovementGuard.insideBox(b.X, b.Y, b.Z, half.X, half.Y, half.Z),")
		expect(cross).toContain("Top = topOf(part),")
		expect(cross).toContain("local floor = hit.Normal.Y > AUDIT.FloorNormalY")
		expect(cross).toContain(
			"PassThrough = MovementGuard.passesThrough(floor, a.X, a.Y, a.Z, b.X, b.Y, b.Z, half.X, half.Y, half.Z, config),"
		)
		-- The one ray it casts.
		expect(count(source, "Workspace:Raycast(")).toBe(1)
	end)

	it("counts contact with players, the Forgers, the proofs, the Erasure's hull and the Margin walls", function()
		expect(audit("local function markContacts(")).toContain(
			"local touched = MovementGuard.touching(xs, ys, zs, dxs, dys, dzs, flagged, AUDIT.ContactRadiusStuds, config) for n, body in ipairs(listed) do body.Contact = touched[n] or nearServerBody(body.Root.Position) end"
		)
		local start = audit("function MovementAudit.start(")
		for _, watched in ipairs({
			"watchModels(GameConfig.Enemy.Tag, npcs)",
			"watchModels(BotConfig.Tag, npcs)",
			"watchModels(WorldBossConfig.Boss.Tag, hulls)",
			"watchParts(WorldConfig.Glyphs.CollisionTag, walls, nil)",
		}) do
			expect(start).toContain(watched)
		end
		local near = audit("local function nearServerBody(")
		expect(near).toContain("(root.Position - position).Magnitude <= AUDIT.ContactRadiusStuds")
		expect(near).toContain("insideGrown(hull, position, AUDIT.ShoveMarginStuds)")
		expect(near).toContain("insideGrown(wall, position, AUDIT.ShoveMarginStuds)")
	end)

	it("in Observe, and on a verdict it only watches, moves nobody", function()
		local enforce = audit("local function enforce(")
		expect(ordered(enforce, 'if MovementGuardConfig.Mode == "Observe" then', "correct(body,")).toBe(true)
		expect(ordered(enforce, 'if MovementGuardConfig.Mode == "Observe" then', "repivot(body,")).toBe(true)
		expect(enforce).toContain(
			'if action == "Watch" then report(record, verdict, now, "watch", back, strike(record, verdict, now), true) return end'
		)
		expect(enforce).toContain(
			'if action == "Correct" then correct(body, sample.StandHeight, verdict, now) elseif action == "Repivot" then repivot(body, verdict, now) end end'
		)
		expect(enforce).toContain(
			'if MovementGuardConfig.Mode == "Observe" then local heading = if action == "Watch" then "watch" else "observe " .. string.lower(action) report(record, verdict, now, heading, back, strike(record, verdict, now), true) return end'
		)
		expect(enforce).toContain(
			'if now < record.PausedUntil then report(record, verdict, now, "paused " .. string.lower(action), back, strike(record, verdict, now), true) return end'
		)
		-- The only two pivots it makes.
		expect(count(strip(fs.readFile(AUDIT_MODULE)), ":PivotTo(")).toBe(2)
	end)

	it("strikes only in Enforce, one strike per kind per spacing, and only a verdict that may", function()
		local strike = audit("local function strike(")
		expect(strike).toContain('if not verdict.Strikeable then return "exempt" end')
		expect(strike).toContain('if MovementGuardConfig.Mode ~= "Enforce" then return "would strike" end')
		expect(strike).toContain(
			'if now - (record.StruckAt[key] or -math.huge) < AUDIT.StrikeSpacingSeconds then return "strike spaced out" end record.StruckAt[key] = now deps.AntiCheat.strike('
		)
		expect(strike).toContain('"Movement" ) return "struck"')
		expect(count(strip(fs.readFile(AUDIT_MODULE)), "deps.AntiCheat.strike(")).toBe(1)
	end)

	it("confirms a flight against the ground before pulling anyone down, in every mode", function()
		local enforce = audit("local function enforce(")
		expect(enforce).toContain(
			'if action == "Correct" and verdict.Kind == "Flight" and groundBelow(body, sample.StandHeight, now) then return end'
		)
		expect(ordered(enforce, "groundBelow(", 'if MovementGuardConfig.Mode == "Observe" then')).toBe(true)
		local ground = audit("local function groundBelow(")
		expect(ground).toContain(
			"castDown(record.Probe, body.Root.Position, stand, AUDIT.ConfirmProbeRadiusStuds, AUDIT.ConfirmProbeReachStuds)"
		)
		expect(ground).toContain("MovementGuard.groundFound(record.Track, hit.Position.Y + stand, now)")
	end)

	it("corrects to a point the body fits at, and re-anchors both guards there", function()
		local correct = audit("local function correct(")
		expect(correct).toContain("local target = clearTarget(record, verdict, stand)")
		expect(correct).toContain(
			"local fromX, fromY, fromZ = MovementGuard.heard(track) body.Character:PivotTo(CFrame.new(target) * root.CFrame.Rotation) root.AssemblyLinearVelocity = Vector3.zero root.AssemblyAngularVelocity = Vector3.zero deps.Reanchor(record.Player, target) local groundY = if supportedAt(record, target, stand) then target.Y else nil MovementGuard.corrected(track, target.X, target.Y, target.Z, now, fromX, fromY, fromZ, groundY, config) countCorrection(record, now)"
		)
		-- A correction is no server teleport: taken for one, it excused a body bouncing back to where it was pulled
		-- from after every correction. Only MovementAudit.teleported, told by resyncPosition, arms that excuse.
		expect(count(strip(fs.readFile(AUDIT_MODULE)), "MovementGuard.teleported(")).toBe(1)
		expect(audit("function MovementAudit.teleported(")).toContain(
			"MovementGuard.teleported(track, position.X, position.Y, position.Z, now, fromX, fromY, fromZ, groundY, config)"
		)
		local clear = audit("local function clearTarget(")
		expect(clear).toContain('MovementGuard.safePoint(record.Track, n, verdict.Kind == "Flight")')
		expect(count(clear, "fits(record,")).toBe(2)
		expect(audit("local function fits(")).toContain(
			"local bottom = point.Y - stand + AUDIT.ClearanceFootStuds local top = point.Y + AUDIT.ClearanceHeadStuds local width = 2 * AUDIT.BodyHalfWidthStuds"
		)
		-- A repivot puts the body back on a destination the teleport already told the judge about.
		local repivot = audit("local function repivot(")
		expect(repivot).toContain(
			"body.Character:PivotTo(CFrame.new(destination) * root.CFrame.Rotation) root.AssemblyLinearVelocity = Vector3.zero root.AssemblyAngularVelocity = Vector3.zero deps.Reanchor(record.Player, destination)"
		)
		expect(repivot).never.toContain("MovementGuard.teleported(")
	end)

	it("pauses corrections caught in a loop, without striking for it", function()
		local burst = audit("local function countCorrection(")
		expect(burst).toContain(
			"if #times > AUDIT.CorrectionBurstLimit then table.clear(times) record.PausedUntil = now + AUDIT.LoopPauseSeconds"
		)
		expect(burst).never.toContain("strike(")
	end)

	it("finds the ground under a server teleport's destination as far down as the pads drop a body", function()
		-- The support probe missed the floor under a pad, and the altitude rule kept measuring from the hub 900
		-- studs below: every arrival read as a flight, and one that hopped on landing as a flight to correct.
		expect(audit("function MovementAudit.teleported(")).toContain(
			"local groundY = groundUnder(record, position, stand) MovementGuard.teleported(track, position.X, position.Y, position.Z, now, fromX, fromY, fromZ, groundY, config)"
		)
		expect(audit("local function groundUnder(")).toContain(
			"local hit = castDown(record.Probe, destination, stand, AUDIT.GroundProbeRadiusStuds, MovementGuard.maxRise(config)) if hit == nil or not holdsUp(hit.Instance) then return nil end return hit.Position.Y + stand"
		)
		-- A jump's fall past the feet covers every pad: its marker stands a body's height over the floor and the
		-- root is pivoted above the marker.
		local function localNumber(path: string, pattern: string): number
			local found = tonumber(strip(fs.readFile(path)):match(pattern))
			assert(found ~= nil, path .. " has no " .. pattern .. ": this gate would check nothing")
			return found :: number
		end
		local marker = localNumber(ARENA, "\nlocal CHARACTER_PIVOT_STUDS = ([%d%.]+)\n")
		local maxRise = (GameConfig.Movement.JumpPower ^ 2 + GameConfig.Movement.DoubleJumpVelocity ^ 2) / (2 * 196.2)
		for _, clearance in ipairs({
			localNumber("src/server/Services/MatchService.luau", "\nlocal SPAWN_CLEARANCE_STUDS = ([%d%.]+)\n"),
			localNumber(
				"src/server/Services/WorldBossService/Context.luau",
				"\nContext.SpawnClearanceStuds = ([%d%.]+)\n"
			),
		}) do
			expect(marker + clearance - MovementGuardConfig.DefaultStandHeightStuds).toBeLessThan(maxRise)
			-- And the support probe alone does not: without the deeper cast the floor stays out of reach.
			expect(marker + clearance - MovementGuardConfig.DefaultStandHeightStuds).toBeGreaterThan(
				MovementGuardConfig.GroundProbeSlackStuds
			)
		end
	end)

	it("follows a teleport's new body from where the engine spawned it", function()
		local teleported = audit("function MovementAudit.teleported(")
		expect(teleported).toContain("if record.Character ~= character then adopt(record, character, now) end")
		expect(teleported).toContain("local fromX, fromY, fromZ = MovementGuard.heard(track)")
		expect(ordered(teleported, "adopt(record, character, now)", "MovementGuard.heard(track)")).toBe(true)
		expect(audit("local function adopt(")).toContain(
			"local point = deps.SpawnPoint(character) if point == nil then record.Track = MovementGuard.newTrack(config)"
		)
		expect(audit("local function adopt(")).toContain(
			"MovementGuard.spawned(record.Track, point.X, point.Y, point.Z, now, config)"
		)
	end)
end)

-- The noclip ray is cast against MovementGuardConfig.BarrierTag and nothing else: geometry left untagged can be
-- walked through unseen, and a tagged part that touches nothing -- a kill zone, a marker -- would read an honest
-- fall into it as a body passing through a floor.
describe("the barriers", function()
	it("are the arena's floor, walls, wall rules and cover walls", function()
		expect(functionIn(ARENA, "local function asBarrier(")).toContain(
			"CollectionService:AddTag(part, MovementGuardConfig.BarrierTag) return part"
		)
		expect(functionIn(ARENA, "local function buildTemplate(")).toContain(
			"local floor = asBarrier( newPart( FLOOR_NAME,"
		)
		local walls = functionIn(ARENA, "local function buildWalls(")
		expect(walls).toContain("asBarrier(newPart(wall.Name, wall.Size,")
		expect(walls).toContain('asBarrier(newPart(wall.Name .. "Rule", ruleSize,')
		expect(count(walls, "newPart(")).toBe(count(walls, "asBarrier(newPart("))
		local covers = functionIn(ARENA, "local function buildCoverWalls(")
		expect(covers).toContain('asBarrier(newPart("CoverWall" .. index,')
		for _, header in ipairs({ "local function buildKillZone(", "local function buildMarker(" }) do
			local builder = functionIn(ARENA, header)
			expect(builder).never.toContain("asBarrier(")
			expect(builder).never.toContain("AddTag(")
		end
		-- Only through asBarrier, so the list above is the whole of it: its definition and four builders.
		local source = strip(fs.readFile(ARENA))
		expect(count(source, "asBarrier(")).toBe(5)
		expect(count(source, "BarrierTag")).toBe(1)
	end)

	it("are the hub platform and its kerbs, and nothing else there", function()
		local platform = functionIn(HUB, "local function buildPlatform(")
		expect(platform).toContain(
			"CollectionService:AddTag(platform, MovementGuardConfig.BarrierTag) platform.Parent = parent"
		)
		expect(platform).toContain(
			"local kerb = newPart(side.Name, side.Size, CFrame.new(side.Position), Palette.world(HUB.Kerb)) CollectionService:AddTag(kerb, MovementGuardConfig.BarrierTag)"
		)
		expect(count(strip(fs.readFile(HUB)), "BarrierTag")).toBe(2)
	end)

	it("are the Battleground's solids, which are its floor, walls, pillars, stele and cover", function()
		local build = functionIn(BATTLEGROUND_MAP, "local function buildBox(")
		expect(build).toContain("if box.Solid then " .. TAG_BARRIER .. " end")
		expect(functionIn(BATTLEGROUND_MAP, "local function buildMarker(")).never.toContain("AddTag(")
		expect(count(strip(fs.readFile(BATTLEGROUND_MAP)), "BarrierTag")).toBe(1)
		-- And what is solid there is exactly the geometry a body stands on or runs into: never the kill plane,
		-- a rule or the camp's wash.
		local dressing: BattlegroundLayout.Dressing = {
			FloorName = BattlegroundConfig.Anchors.Floor,
			KillZoneName = BattlegroundConfig.Anchors.KillZone,
			WallRuleStuds = WorldConfig.Arena.WallRuleStuds,
			WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,
			FlatThickness = WorldConfig.FlatThicknessStuds,
			RuleTop = WorldConfig.Ladder.Rule,
			CampTop = WorldConfig.Ladder.Training,
			CampTransparency = WorldConfig.Battleground.CampTransparency,
		}
		local layout = BattlegroundLayout.build(BattlegroundConfig.Map, dressing, BotConfig.Path.RadiusStuds)
		local barriers = { Floor = true, Wall = true, Pillar = true, Stele = true, Cover = true }
		local seen: { [string]: boolean } = {}
		for _, box in ipairs(layout.Boxes) do
			expect(box.Solid).toBe(barriers[box.Role] == true)
			seen[box.Role] = true
		end
		for role in pairs(barriers) do
			expect(seen[role]).toBe(true)
		end
		expect(seen.KillZone).toBe(true)
	end)
end)

-- Touched on a kill zone is reported by the client that owns the falling body, so a tampered client never
-- touches one. The server looks for itself, every tick; Touched stays as the fast path.
describe("the kill zone, judged by the server", function()
	local MATCH = "src/server/Services/MatchService.luau"
	local BATTLEGROUND = "src/server/Services/BattlegroundService/init.luau"

	it(
		"kills a match participant still alive whose root fell under the arena's zone, while the round is played",
		function()
			local kill = functionIn(MATCH, "local function killInZone(")
			expect(kill).toContain(
				'if active.Finished or active.Match.Phase ~= "Playing" or not participant.Alive then return end local humanoid = character:FindFirstChildOfClass("Humanoid") if humanoid ~= nil and humanoid.Health > 0 then humanoid.Health = 0 end'
			)
			local judge = functionIn(MATCH, "local function judgeFalls(")
			expect(judge).toContain('if active.Match.Phase ~= "Playing" then return end')
			expect(judge).toContain(
				"local depth = active.Arena.KillZone.Position.Y for _, participant in ipairs(active.Match.Participants) do"
			)
			expect(judge).toContain(
				'local placed = active.Placed[participant.Player] if participant.Alive and placed ~= nil and now - placed.At >= MovementGuardConfig.SettleMaxSeconds then local character = participant.Player.Character local root = if character ~= nil then character:FindFirstChild(ROOT_PART_NAME) else nil if character == placed.Character and root ~= nil and root:IsA("BasePart") and root.Position.Y < depth then killInZone(active, participant, placed.Character) end end'
			)
			-- Alive, not merely present: an eliminated player respawned at the hub stands far under every arena's
			-- zone, and would be killed again on every tick.
			expect(judge).never.toContain("isLive(")
			expect(strip(fs.readFile(MATCH))).toContain('local ROOT_PART_NAME = "HumanoidRootPart"')
		end
	)

	it("judges falls on every match tick, before the verdict, and keeps Touched through the same kill", function()
		expect(functionIn(MATCH, "local function onHeartbeat(")).toContain(
			"if not active.Finished and not active.Preparing then judgeFalls(active, now) refresh(active) advance(active, now) end"
		)
		local touched = functionIn(MATCH, "local function onKillZoneTouched(")
		expect(touched).toContain(
			"local participant = GameModes.participantOf(active.Match, player.UserId) if participant ~= nil then killInZone(active, participant, character) end"
		)
		expect((strip(fs.readFile(MATCH)):gsub("%s+", " "))).toContain(
			"trove:Connect(arena.KillZone.Touched, function(part: BasePart) onKillZoneTouched(active, part) end)"
		)
		expect(count(strip(fs.readFile(MATCH)), "humanoid.Health = 0")).toBe(1)
	end)

	it("judges only the body the round placed, once its pivot has settled", function()
		-- A setup that stalls past the countdown lets the round play while it still reloads people: a survivor's
		-- new body stands on the hub, far under the arena, and the client replicates the hub for a round trip after
		-- its pad. Judged on those, an honest player was killed at the start of the round.
		expect(functionIn(MATCH, "local function prepareRound(")).toContain(
			"placeCharacter(player, character, pad, center) active.Placed[player] = { Character = character, At = os.clock() }"
		)
		local source = strip(fs.readFile(MATCH))
		expect(count(source, "active.Placed[")).toBe(2)
		expect(source).toContain("local MovementGuardConfig = require(script.Parent.Parent.Config.MovementGuardConfig)")
		-- A round placed on time is judged from its first tick: the countdown outlasts the settle.
		for _, mode in pairs(MatchConfig.Modes :: { [string]: { CountdownSeconds: number } }) do
			expect(mode.CountdownSeconds).toBeGreaterThan(MovementGuardConfig.SettleMaxSeconds)
		end
	end)

	it("kills a player under the Battleground's kill plane as Touched would, every tick", function()
		local judge = functionIn(BATTLEGROUND, "local function judgeFalls(")
		expect(judge).toContain("local plane = map.KillZone local half = plane.Size / 2")
		expect(judge).toContain(
			"for _, player in ipairs(Players:GetPlayers()) do local root = Context.liveRoot(player) local character = player.Character if root ~= nil and character ~= nil then local offset = plane.CFrame:PointToObjectSpace(root.Position) if offset.Y < 0 and math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then fell(character) end end"
		)
		expect(functionIn(BATTLEGROUND, "local function tick(")).toContain("judgeFalls(map) Roster.step(now, dt)")
		expect(functionIn(BATTLEGROUND, "local function onKillZoneTouched(")).toContain(
			"Bots.kill(bot, os.clock()) return end fell(model) end"
		)
		expect(functionIn(BATTLEGROUND, "local function fell(")).toContain(
			"if humanoid ~= nil and humanoid.Health > 0 and Players:GetPlayerFromCharacter(model) ~= nil then humanoid.Health = 0 end"
		)
		expect(count(strip(fs.readFile(BATTLEGROUND)), "humanoid.Health = 0")).toBe(1)
	end)

	it("covers only the page: whoever is under the Battleground's plane fell off it", function()
		-- Every player is looked at, member or not, so the plane's footprint must hold nothing else: not the
		-- column over the world's origin, where the hub and every arena stand, centred.
		local hub = tonumber(strip(fs.readFile(HUB)):match("\nlocal PLATFORM_SIZE_STUDS = (%d+)\n"))
		assert(hub ~= nil, "HubService has no PLATFORM_SIZE_STUDS: this gate would check nothing")
		local reach = hub / 2
		for _, arena in pairs(MatchConfig.Arenas :: { [string]: { Size: number } }) do
			reach = math.max(reach, arena.Size / 2)
		end
		local dressing: BattlegroundLayout.Dressing = {
			FloorName = BattlegroundConfig.Anchors.Floor,
			KillZoneName = BattlegroundConfig.Anchors.KillZone,
			WallRuleStuds = WorldConfig.Arena.WallRuleStuds,
			WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,
			FlatThickness = WorldConfig.FlatThicknessStuds,
			RuleTop = WorldConfig.Ladder.Rule,
			CampTop = WorldConfig.Ladder.Training,
			CampTransparency = WorldConfig.Battleground.CampTransparency,
		}
		local layout = BattlegroundLayout.build(BattlegroundConfig.Map, dressing, BotConfig.Path.RadiusStuds)
		local origin = BattlegroundConfig.Map.Origin
		local found = false
		for _, box in ipairs(layout.Boxes) do
			if box.Role == "KillZone" then
				found = true
				expect(origin[1] + box.X - box.SizeX / 2).toBeGreaterThan(reach)
			end
		end
		expect(found).toBe(true)
	end)
end)

-- K2 (D-XXXc): the Erasure's arena stands in the stack the duels stand in, and a body that fell off it fell into the
-- match below. The server looks for itself, every fight tick, and takes the body home instead of killing it.
describe("a fall from the Erasure's arena", function()
	local BOSS_DIR = "src/server/Services/WorldBossService/"
	local INIT = BOSS_DIR .. "init.luau"

	it("takes a participant under the arena's floor back to the hub, and never kills them", function()
		local judge = functionIn(INIT, "local function judgeFalls(")
		expect(judge).toContain("local plane = live.Arena.KillZone local half = plane.Size / 2")
		expect(judge).toContain(
			"for userId, placed in pairs(slot.Placed) do local player = Players:GetPlayerByUserId(userId) local root = if player ~= nil then Context.liveRoot(player) else nil"
		)
		expect(judge).toContain(
			"player ~= nil and root ~= nil and not slot.Departed[userId] and player.Character == placed.Character and now - placed.At >= MovementGuardConfig.SettleMaxSeconds and root.Position.Y < live.FallY then"
		)
		expect(judge).toContain(
			'local offset = plane.CFrame:PointToObjectSpace(root.Position) if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z then slot.Placed[userId] = nil log.info("%s: %s fell off the arena, back to the hub", slot.Kind, player.Name) log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player) end'
		)
		-- Every fight tick, before the fight looks at who is left in the arena.
		expect(functionIn(INIT, "local function tickFight(")).toContain(
			"if now >= slot.PhaseEndsAt then expire(current, now) return end judgeFalls(live, now) Audience.releaseMatched()"
		)
		-- Nobody in the folder kills a player: the Erasure's blows go through ApplyDamage, a fall goes home.
		for _, entry in ipairs(fs.readDir(BOSS_DIR)) do
			local source = strip(fs.readFile(BOSS_DIR .. entry))
			expect(source).never.toContain("Health = 0")
			expect(source).never.toContain(":BreakJoints(")
		end
		expect(strip(fs.readFile(INIT))).never.toContain("KillZone.Touched")
	end)

	it("judges only the body the fight placed, from the underside of the arena's floor", function()
		-- Each placement is the body placed, when: the opening's and the hub gate's, forgotten with the fight.
		expect(functionIn(INIT, "local function openFight(")).toContain(
			"for userId, character in pairs(Encounter.place(arena, participants, live.Center)) do slot.Placed[userId] = { Character = character, At = now } end"
		)
		expect(functionIn(BOSS_DIR .. "Admission.luau", "local function admit(")).toContain(
			"local character = Encounter.placeOne(live.Arena, player, pad, live.Center) if character ~= nil then slot.Placed[userId] = { Character = character, At = now } end"
		)
		expect(functionIn(INIT, "local function reset(")).toContain("slot.Placed = {}")
		local placeOne = functionIn(BOSS_DIR .. "Encounter.luau", "function Encounter.placeOne(")
		expect(placeOne).toContain("deps.Combat.resyncPosition(player, position) return character end")
		expect(functionIn(BOSS_DIR .. "Encounter.luau", "local function floorOf(")).toContain(
			"return floor.Position.Y + floor.Size.Y / 2, floor.Position.Y - floor.Size.Y / 2 end return fallback, fallback end"
		)
		expect(functionIn(BOSS_DIR .. "Encounter.luau", "function Encounter.build(")).toContain(
			"local floorY, fallY = floorOf(arena, center.Y)"
		)
	end)

	it("brings a body home before it can reach any pad, wall or match plane of an arena below", function()
		-- Relative to the centre of the Erasure's floor, which ArenaService puts on its slot's altitude; the slot below
		-- is MatchConfig.ArenaSpacingStuds lower. The body is thrown as high as the audit grants lift, plus a jump and a
		-- double jump, off the edge of the page; it crosses the underside of the floor, the server sees it a way
		-- later, judges it on its tick, and the hub's pivot reaches the client a way after that -- at the longest
		-- round trip a server pivot is waited out for.
		local function localNumber(path: string, pattern: string): number
			local found = tonumber(strip(fs.readFile(path)):match(pattern))
			assert(found ~= nil, path .. " has no " .. pattern .. ": this gate would check nothing")
			return found :: number
		end
		local GRAVITY = 196.2
		local TICK = 1 / GameConfig.Server.TickRate
		local thickness = localNumber(ARENA, "\nlocal FLOOR_THICKNESS_STUDS = ([%d%.]+)\n")
		local marker = localNumber(ARENA, "\nlocal CHARACTER_PIVOT_STUDS = ([%d%.]+)\n")
		local floorTop = thickness / 2
		local fallY = -thickness / 2
		local jumps = (GameConfig.Movement.JumpPower ^ 2 + GameConfig.Movement.DoubleJumpVelocity ^ 2) / (2 * GRAVITY)
		local peak = floorTop + MovementGuardConfig.MaxLiftStuds + jumps
		local speed = math.sqrt(2 * GRAVITY * (peak - fallY))
		local late = MovementGuardConfig.SettleMaxSeconds + TICK
		local feet = fallY - (speed * late + GRAVITY * late * late / 2) - MovementGuardConfig.DefaultStandHeightStuds
		-- The highest thing any arena below holds: its wall rule, over its pads and its kill zone.
		local below = -MatchConfig.ArenaSpacingStuds + floorTop
		local highest = -math.huge
		for _, def in pairs(MatchConfig.Arenas :: { [string]: { WallHeight: number, KillZoneDepth: number } }) do
			highest = math.max(highest, below + def.WallHeight + WorldConfig.Arena.WallRuleProudStuds)
			expect(below + marker).toBeLessThan(below + def.WallHeight)
			expect(def.KillZoneDepth).toBeLessThan(0)
		end
		expect(feet).toBeGreaterThan(highest)
		-- Judged at the kill zone, as a match judges its own, the same body would already stand in the duel below.
		local zone = floorTop + (MatchConfig.Arenas :: any).Boss.KillZoneDepth
		local fromZone = math.sqrt(2 * GRAVITY * (peak - zone))
		expect(zone - (fromZone * late + GRAVITY * late * late / 2) - MovementGuardConfig.DefaultStandHeightStuds).toBeLessThan(
			highest
		)
	end)
end)
