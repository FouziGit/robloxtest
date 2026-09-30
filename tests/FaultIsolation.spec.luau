--!strict
-- One player or one match that throws no longer stops the whole tick (E9-S2, D-XXX).
--
-- Every per-frame loop of the server visits many elements -- each player's combat state, timers and portal watch,
-- each live match -- and a single `error` inside one of them used to end the loop there for everybody else, on
-- every tick, and write a line twenty times a second. Each element's step now runs under Log.faults: it counts how
-- many times in a row that element has failed, writes its failure at once and then at most once per
-- GameConfig.Server.FaultLogSeconds, and lets the loop carry on. A match whose tick keeps failing is cancelled
-- (MatchService.cancel) and its arena released.
--
-- The tracker itself, PortalService and MatchService are run here on the pretend engine of tests/engine.luau;
-- CombatService and MovementService are held to the same wiring by their sources.
local Engine = require("./engine")
local Harness = require("./harness")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local Vector3 = roblox.Vector3

local GameConfig = require("../src/shared/Config/GameConfig")
local MatchConfig = require("../src/shared/Config/MatchConfig")

local WINDOW = GameConfig.Server.FaultLogSeconds

-- How many of `lines` mention `needle`.
local function mentioning(lines: { string }, needle: string): number
	local found = 0
	for _, line in ipairs(lines) do
		if line:find(needle, 1, true) ~= nil then
			found += 1
		end
	end
	return found
end

-- Whitespace folded, comments gone: one function's source, from its header to the first `end` at column 0.
local function functionIn(path: string, header: string): string
	local source = (fs.readFile(path)):gsub("%-%-[^\n]*", "")
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
end

----------------------------------------------------------------
-- The tracker
----------------------------------------------------------------

describe("Log.faults", function()
	local function tracker(): (any, any)
		local world = Engine.world()
		local Log = world.require("src/shared/Util/Log")
		return world, Log.new("Spec").faults(WINDOW)
	end

	local function boom()
		error("boom")
	end

	it("counts the failures of an element in a row, and a clean run resets them", function()
		local _, faults = tracker()
		expect(faults.try("a", "step of", function() end)).toBe(0)
		expect(faults.try("a", "step of", boom)).toBe(1)
		expect(faults.try("a", "step of", boom)).toBe(2)
		expect(faults.try("b", "step of", boom)).toBe(1)
		expect(faults.try("a", "step of", function() end)).toBe(0)
		expect(faults.try("a", "step of", boom)).toBe(1)
	end)

	it("passes its arguments through", function()
		local _, faults = tracker()
		local seen: { any } = {}
		faults.try("a", "step of", function(x: number, y: string)
			seen = { x, y }
		end, 7, "z")
		expect(seen).toEqual({ 7, "z" })
	end)

	it("writes an element's first failure at once, with its context, its key and the error", function()
		local world, faults = tracker()
		faults.try("Match-7", "tick of match", boom)
		expect(#world.warnings).toBe(1)
		local line = world.warnings[1]
		expect(line).toContain("[Spec]")
		expect(line).toContain("tick of match Match-7 failed (1 in a row, 0 not shown)")
		expect(line).toContain("boom")
	end)

	it("writes at most one line per element per window, however long it keeps failing", function()
		local world, faults = tracker()
		-- 25 seconds of an element failing on every tick, next to one that never does.
		for _ = 1, 25 * GameConfig.Server.TickRate do
			faults.try("broken", "tick of", boom)
			faults.try("sound", "tick of", function() end)
			world:advance(1 / GameConfig.Server.TickRate, 1 / GameConfig.Server.TickRate)
		end
		expect(mentioning(world.warnings, "broken")).toBe(3)
		expect(mentioning(world.warnings, "sound")).toBe(0)
		-- The next line says how many were held back since the last one.
		expect(world.warnings[2]).toContain(
			("(%d in a row, %d not shown)"):format(
				WINDOW * GameConfig.Server.TickRate + 1,
				WINDOW * GameConfig.Server.TickRate - 1
			)
		)
	end)

	it("never lets an element that fails every other tick write more often", function()
		local world, faults = tracker()
		for tick = 1, 25 * GameConfig.Server.TickRate do
			faults.try("flaky", "tick of", if tick % 2 == 0 then boom else function() end)
			world:advance(1 / GameConfig.Server.TickRate, 1 / GameConfig.Server.TickRate)
		end
		expect(mentioning(world.warnings, "flaky")).toBe(3)
	end)

	it("gives every element its own window, and a forgotten one starts over", function()
		local world, faults = tracker()
		faults.try("a", "tick of", boom)
		faults.try("b", "tick of", boom)
		faults.try("a", "tick of", boom)
		expect(#world.warnings).toBe(2)
		faults.forget("a")
		expect(faults.try("a", "tick of", boom)).toBe(1)
		expect(#world.warnings).toBe(3)
	end)
end)

----------------------------------------------------------------
-- A state that throws: PortalService
----------------------------------------------------------------

-- A player with a living body, on `players`.
local function newPlayer(players: any, name: string, userId: number): any
	local player = Engine.instance("Player", players)
	player.Name = name
	player.UserId = userId
	local character = Engine.instance("Model")
	local humanoid = Engine.instance("Humanoid", character)
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	player.Character = character
	return player
end

local function fakePlayers(): any
	local players = Engine.instance("Players")
	players.Name = "Players"
	players.GetPlayers = function(self: any): { any }
		return self:GetChildren()
	end
	players.GetPlayerByUserId = function(self: any, userId: number): any
		for _, each in ipairs(self:GetChildren()) do
			if each.UserId == userId then
				return each
			end
		end
		return nil
	end
	players.GetPlayerFromCharacter = function(self: any, character: any): any
		for _, each in ipairs(self:GetChildren()) do
			if each.Character == character then
				return each
			end
		end
		return nil
	end
	return players
end

describe("a player's state that throws", function()
	it("leaves every other player's portal watch running, and writes one line per 10 s", function()
		local players = fakePlayers()
		local seals = Engine.signal()
		local world = Engine.world({
			Services = {
				Players = players,
				CollectionService = {
					GetInstanceAddedSignal = function(_self: any)
						return seals
					end,
					GetInstanceRemovedSignal = function(_self: any)
						return Engine.signal()
					end,
					GetTagged = function(_self: any)
						return {}
					end,
				},
			},
		})
		local PortalConfig = world.require("src/shared/Config/PortalConfig")
		local broken = newPlayer(players, "Broken", 1)
		local walker = newPlayer(players, "Walker", 2)
		local travelled: { any } = {}
		local PortalService = world.require("src/server/Services/PortalService")
		PortalService.Init({
			Registry = {
				fire = function(name: string, player: any, id: any)
					if name == "Travelled" then
						table.insert(travelled, { player, id })
					end
				end,
			},
			Notify = { send = function() end },
			Combat = {
				trustedPosition = function(_player: any)
					return Vector3.new(0, 3, 0)
				end,
				grantIFrames = function() end,
			},
			Movement = {
				isDown = function()
					return false
				end,
			},
			Match = {
				isInMatch = function(player: any): boolean
					if player == broken then
						error("a corrupted state")
					end
					return false
				end,
			},
			Hub = {
				travelToHub = function()
					return true
				end,
			},
			Battleground = {
				admits = function()
					return true, nil
				end,
				enter = function()
					return true, nil
				end,
				leave = function() end,
			},
			WorldBoss = {
				enterFromPortal = function()
					return true, nil, nil
				end,
				leave = function() end,
			},
		} :: any)
		PortalService.Start()
		-- A seal under both of them, found through its tag.
		local seal = Engine.instance("BasePart", world.workspace)
		seal.Position = Vector3.new(0, 0, 0)
		seal:SetAttribute(PortalConfig.SealAttribute, "WorldBoss")
		seals:Fire(seal)

		world:advance(25)

		-- The walker stood in the circle and was taken, although the broken state threw on every look before theirs
		-- or after it.
		expect(#travelled).toBeGreaterThanOrEqual(1)
		expect(travelled[1][1]).toBe(walker)
		expect(travelled[1][2]).toBe("WorldBoss")
		-- 250 failed looks in 25 s, three lines.
		expect(mentioning(world.warnings, "watch of Broken failed")).toBe(3)
	end)
end)

----------------------------------------------------------------
-- A mode that throws: MatchService
----------------------------------------------------------------

type Arena = { Instance: any, Id: string, SlotIndex: number, Spawns: { { any } }, KillZone: any }

local function newArena(world: any, slot: number): Arena
	local model = Engine.instance("Model", world.workspace)
	local function pad(x: number): any
		local part = Engine.instance("BasePart", model)
		part.Position = Vector3.new(x, 900 * slot, 0)
		return part
	end
	local killZone = Engine.instance("BasePart", model)
	killZone.Position = Vector3.new(0, 900 * slot - 50, 0)
	killZone.Touched = Engine.signal()
	return {
		Instance = model,
		Id = "Duel",
		SlotIndex = slot,
		Spawns = { { pad(-20) }, { pad(20) } },
		KillZone = killZone,
	}
end

-- A duelist whose respawn is a fresh body with a root that can be moved.
local function duelist(players: any, name: string, userId: number): any
	local player = newPlayer(players, name, userId)
	player.DisplayName = name
	player.LoadCharacterAsync = function(self: any)
		local character = Engine.instance("Model")
		local humanoid = Engine.instance("Humanoid", character)
		humanoid.Health = 100
		humanoid.MaxHealth = 100
		local root = Engine.instance("BasePart", character)
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(0, 0, 0)
		character.PrimaryPart = root
		character.PivotTo = function(_self: any, frame: any)
			root.Position = frame.Position
		end
		self.Character = character
	end
	return player
end

describe("a match whose mode throws", function()
	local players = fakePlayers()
	local world = Engine.world({ Services = { Players = players } })
	local released: { Arena } = {}
	local releasedAt: number? = nil
	local firstThrowAt: number? = nil
	local sentHome: { any } = {}
	local told: { [any]: string } = {}
	local resultsApplied = 0
	local slots = 0
	local deps = {
		Registry = { fire = function() end },
		DataService = {
			get = function()
				return nil
			end,
			push = function() end,
			BeforeRelease = Engine.signal(),
		},
		Notify = {
			send = function(player: any, key: string)
				told[player] = key
			end,
		},
		Combat = {
			Damaged = Engine.signal(),
			setPolicy = function() end,
			resyncPosition = function() end,
		},
		Movement = {
			applyStun = function() end,
			applyFreeze = function() end,
			clearStun = function() end,
			isStunned = function()
				return false
			end,
		},
		Progression = { addXp = function() end },
		Currency = { add = function() end },
		Hub = {
			teleportToHub = function(player: any)
				table.insert(sentHome, player)
			end,
		},
		Arena = {
			acquire = function(_id: string): Arena
				slots += 1
				return newArena(world, slots)
			end,
			release = function(arena: Arena)
				table.insert(released, arena)
				releasedAt = releasedAt or world.now
			end,
		},
		Ranking = {
			getRating = function()
				return 1000
			end,
			lastKnownRating = function()
				return 1000
			end,
			applyResult = function()
				resultsApplied += 1
				return {}
			end,
			applyAbandon = function()
				return nil
			end,
			hold = function() end,
			release = function() end,
		},
		Quest = { report = function() end },
		Daily = {
			markFirstWin = function()
				return false
			end,
		},
		Glyph = { Cast = Engine.signal(), CastLanded = Engine.signal() },
	}
	local MatchService = world.require("src/server/Services/MatchService")
	local GameModes = world.require("src/server/GameModes")
	MatchService.Init(deps :: any)
	MatchService.Start()

	local a1, a2 = duelist(players, "HealthyA", 11), duelist(players, "HealthyB", 12)
	local b1, b2 = duelist(players, "BrokenA", 21), duelist(players, "BrokenB", 22)
	local healthy = MatchService.start("Duel1v1", { { 11 }, { 12 } })
	local broken = MatchService.start("Duel1v1", { { 21 }, { 22 } })
	assert(healthy ~= nil and broken ~= nil, "the spec could not start its two duels")

	-- The mode's verdict breaks for one match only, from this tick on.
	local duel = GameModes.get("Duel1v1")
	local verdict = duel.RoundVerdict
	duel.RoundVerdict = function(match: any, now: number): any
		if match.Id == broken then
			firstThrowAt = firstThrowAt or world.now
			error("a verdict nobody can give")
		end
		return verdict(match, now)
	end
	world:advance(2)
	duel.RoundVerdict = verdict

	it("is cancelled within a second, and its arena released", function()
		expect(MatchService.isInMatch(b1)).toBe(false)
		expect(MatchService.isInMatch(b2)).toBe(false)
		expect(#released).toBe(1)
		expect(released[1].SlotIndex).toBe(2)
		assert(firstThrowAt ~= nil and releasedAt ~= nil, "the broken match never threw, or was never released")
		expect(releasedAt - firstThrowAt).toBeLessThanOrEqual(1)
	end)

	it("sends its players home, told why, with nothing applied", function()
		expect(table.find(sentHome, b1)).never.toBeNil()
		expect(table.find(sentHome, b2)).never.toBeNil()
		expect(told[b1]).toBe("match.cancelled")
		expect(told[b2]).toBe("match.cancelled")
		expect(resultsApplied).toBe(0)
	end)

	it("leaves the other match running", function()
		expect(MatchService.isInMatch(a1)).toBe(true)
		expect(MatchService.isInMatch(a2)).toBe(true)
		expect(table.find(sentHome, a1)).toBeNil()
		-- Past its countdown, it plays.
		world:advance(MatchConfig.Modes.Duel1v1.CountdownSeconds)
		expect(MatchService.getMatch(a1).Phase).toBe("Playing")
	end)

	it("writes one warning, and says in its last line that it was cancelled", function()
		expect(mentioning(world.warnings, broken)).toBe(1)
		expect(mentioning(world.warnings, healthy)).toBe(0)
	end)
end)

----------------------------------------------------------------
-- The other loops, by their sources
----------------------------------------------------------------

describe("every per-element step of the server's loops", function()
	it("runs under Log.faults, keyed by its element, and forgets it when it leaves", function()
		local cases = {
			{
				Path = "src/server/Services/CombatService.luau",
				Loop = "local function onHeartbeat(",
				Step = 'faults.try(player, "tick of", tickPlayer, player, state, now, elapsed, replicate)',
				Leave = "local function onPlayerRemoving(",
			},
			{
				Path = "src/server/Services/MovementService.luau",
				Loop = "local function onHeartbeat(",
				Step = 'faults.try(player, "tick of", tickState, player, state, now)',
				Leave = "local function onPlayerRemoving(",
			},
			{
				Path = "src/server/Security/MovementAudit.luau",
				Loop = "function MovementAudit.step(",
				Step = 'faults.try(body.Record.Player, "audit of", audit, body, now, hitch)',
				Leave = "function MovementAudit.remove(",
			},
			{
				Path = "src/server/Services/PortalService.luau",
				Loop = "local function onHeartbeat(",
				Step = 'faults.try(player, "watch of", step, player, watch, now)',
				Leave = "local function forget(",
			},
			{
				Path = "src/server/Services/MatchService.luau",
				Loop = "local function onHeartbeat(",
				Step = 'faults.try(active.Match.Id, "tick of match", tickMatch, active, now)',
				Leave = "local function finish(",
			},
		}
		for _, case in ipairs(cases) do
			local loop = functionIn(case.Path, case.Loop)
			if loop:find(case.Step, 1, true) == nil then
				error(("%s: its loop no longer runs each step under Log.faults: %s"):format(case.Path, case.Step))
			end
			if functionIn(case.Path, case.Leave):find("faults.forget(", 1, true) == nil then
				error(("%s: %s no longer forgets the element"):format(case.Path, case.Leave))
			end
			local source = fs.readFile(case.Path)
			expect(source).toContain("local faults = log.faults(GameConfig.Server.FaultLogSeconds)")
		end
	end)

	it("cancel a match well within a second of its first failure", function()
		expect(GameConfig.Server.FaultLogSeconds).toBe(10)
		expect(GameConfig.Server.MatchFaultTicks).toBeGreaterThanOrEqual(1)
		expect((GameConfig.Server.MatchFaultTicks - 1) / GameConfig.Server.TickRate).toBeLessThan(1)
	end)
end)
