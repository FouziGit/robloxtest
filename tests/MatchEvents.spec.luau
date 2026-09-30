--!strict
-- Matches, queues and boss fights, told to the dashboards (E8-S4). Nothing said how a match ended, how long a queue
-- made a player wait before it gave up, or how often the Erasure fell: the retention questions of docs/ECONOMY.md
-- §8 had no data behind them. The real MatchService, MatchmakingService, WorldBossService and AnalyticsService run
-- in a pretend server (tests/server.luau) on a pretend Roblox analytics (tests/analytics.luau); the Erasure's body
-- and its blows (Encounter) are the one stand-in, since what is judged here is how a fight ends, not how it is
-- fought.
local Analytics = require("./analytics")
local AnalyticsConfig = require("../src/server/Config/AnalyticsConfig")
local Engine = require("./engine")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local Server = require("./server")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DUEL = MatchConfig.Modes.Duel1v1
local TEAM = MatchConfig.Modes.Team3v3
local QUEUE = MatchConfig.Matchmaking
local SCHEDULE = WorldBossConfig.Schedule
local PRACTICE = WorldBossConfig.Practice

-- The custom events `name` that reached Roblox, as { player, value, fields }.
local function sent(world: Server.World, name: string): { { any } }
	local found = {}
	for _, call in ipairs(world.analytics:of("LogCustomEvent", name)) do
		table.insert(found, { call.Player, call.Args[2], call.Args[3] })
	end
	return found
end

----------------------------------------------------------------
-- A ranked duel
----------------------------------------------------------------

local function duel(): (Server.Services, any, any)
	local setup = Server.services()
	local a = setup.world:join(401, "Ada")
	local b = setup.world:join(402, "Bea")
	expect(setup.match.start(DUEL.Id, { { a.UserId }, { b.UserId } })).never.toBe(nil)
	setup.world:advance(DUEL.CountdownSeconds + 0.5)
	expect(setup.match.getMatch(a).Phase).toBe("Playing")
	return setup, a, b
end

local function knockOut(setup: Server.Services, player: any)
	player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	setup.world:advance(0.2)
end

-- `a` wins 2-0: the match stands on its result.
local function sweep(setup: Server.Services, a: any, b: any)
	knockOut(setup, b)
	setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
	knockOut(setup, b)
	setup.world:advance(MatchConfig.RoundOverSeconds + 0.1)
	expect(setup.match.getMatch(a).Phase).toBe("Result")
end

-- Whole seconds from the start of `player`'s match to its result.
local function lasted(setup: Server.Services, player: any): number
	local match = setup.match.getMatch(player)
	return math.floor(match.EndedAt - match.StartedAt + 0.5)
end

----------------------------------------------------------------
-- The queue
----------------------------------------------------------------

type Queue = { join: (player: any, modeId: string) -> () }

local function queue(setup: Server.Services): Queue
	local handlers: { [string]: (...any) -> () } = {}
	local matchmaking = setup.world.require("src/server/Services/MatchmakingService")
	matchmaking.Init({
		Registry = {
			on = function(name: string, handler: (...any) -> ())
				handlers[name] = handler
			end,
			fire = function() end,
		},
		Notify = { send = function() end },
		Ranking = setup.ranking,
		Match = setup.match,
		WorldBoss = {
			isLive = function(): boolean
				return false
			end,
		},
		DataService = setup.data,
		Loadout = setup.loadout,
		Analytics = setup.analytics,
	})
	matchmaking.Start()
	return {
		join = function(player: any, modeId: string)
			handlers.JoinQueue(player, modeId)
		end,
	}
end

----------------------------------------------------------------
-- The Erasure's scheduled event, its body a stand-in
----------------------------------------------------------------

type Fight = {
	world: Server.World,
	worldBoss: any,
	players: { any },
	-- What the Erasure's next step reports: nil while the fight goes on, "Defeated" when it falls.
	outcome: { value: string? },
	advance: (seconds: number) -> (),
}

local function erasure(): Fight
	local outcome: { value: string? } = { value = nil }
	local workspace: any = nil
	local encounter = {
		Init = function() end,
		build = function(arena: any, health: number): any
			local model = Engine.instance("Model", workspace)
			local humanoid = Engine.instance("Humanoid", model)
			humanoid.Health = health
			humanoid.MaxHealth = health
			local body = Engine.instance("BasePart", model)
			body.Position = roblox.Vector3.new(0, 900, 0)
			return {
				Arena = arena,
				Model = model,
				Humanoid = humanoid,
				Body = body,
				Band = body,
				Center = roblox.Vector3.new(0, 900, 0),
				GroundY = 890,
				-- Under the floor, where WorldBossService judges a fall off the page (K2, D-214).
				FallY = 870,
				Facing = roblox.Vector3.new(0, 0, -1),
				LastHealth = health,
				ContactNextAt = {},
			}
		end,
		place = function(): { [number]: any }
			return {}
		end,
		placeOne = function() end,
		dress = function() end,
		recordDamage = function() end,
		step = function(): (string?, boolean)
			return outcome.value, false
		end,
	}
	local world = Server.world({ Stubs = { ["src/server/Services/WorldBossService/Encounter"] = encounter } })
	workspace = world.engine.workspace
	local analytics = world.require("src/server/Services/AnalyticsService")
	analytics.Init({})
	analytics.Start()
	local signal = Engine.signal()
	local worldBoss = world.require("src/server/Services/WorldBossService")
	worldBoss.Init({
		Registry = { fire = function() end, fireAll = function() end },
		DataService = {
			get = function(): any
				return nil
			end,
			push = function() end,
		},
		Notify = { send = function() end, sendAll = function() end },
		Combat = {
			ApplyDamage = function(): any
				return { Applied = 0, Killed = false, Blocked = false }
			end,
			knockback = function() end,
			resyncPosition = function() end,
			setPolicy = function(): any
				return nil
			end,
			Damaged = signal,
		},
		Movement = { applyStun = function() end },
		Progression = {
			addXp = function(): number
				return 0
			end,
		},
		Currency = {
			add = function(): number
				return 0
			end,
		},
		Hub = { teleportToHub = function() end },
		Arena = {
			acquire = function(arenaId: string): any
				local pad = Engine.instance("BasePart", workspace)
				pad.Position = roblox.Vector3.new(0, 890, 20)
				-- The plane a fall off the arena is judged over (WorldBossService.judgeFalls).
				local killZone = Engine.instance("BasePart", workspace)
				killZone.Size = roblox.Vector3.new(200, 1, 200)
				killZone.CFrame = roblox.CFrame.new(0, 850, 0)
				return {
					Instance = Engine.instance("Model", workspace),
					Id = arenaId,
					SlotIndex = 1,
					Spawns = { { pad } },
					KillZone = killZone,
				}
			end,
			release = function() end,
		},
		Match = {
			isInMatch = function(): boolean
				return false
			end,
		},
		Vfx = { emit = function() end },
		Quest = { report = function() end },
		Analytics = analytics,
	})
	worldBoss.Start()
	local players = {}
	for index, name in ipairs({ "Ada", "Bea" }) do
		local player = world:join(500 + index, name)
		player:LoadCharacterAsync()
		table.insert(players, player)
	end
	return {
		world = world,
		worldBoss = worldBoss,
		players = players,
		outcome = outcome,
		advance = function(seconds: number)
			world.engine:advance(seconds, 0.25)
		end,
	}
end

----------------------------------------------------------------
-- Specs
----------------------------------------------------------------

describe("the custom events of the game (E8-S4)", function()
	it("stay under the 100 names Roblox keeps for an experience", function()
		expect(AnalyticsConfig.Limits.CustomEventNames).toBe(100)
		local count = 0
		for _ in pairs(AnalyticsConfig.Events) do
			count += 1
		end
		expect(count).toBeGreaterThan(0)
		if count > AnalyticsConfig.Limits.CustomEventNames then
			error(("%d custom event names: Roblox keeps %d"):format(count, AnalyticsConfig.Limits.CustomEventNames))
		end
	end)

	it("name the match, queue and boss events with the fields their story asks for", function()
		expect(AnalyticsConfig.Events.MatchEnded).toEqual({ "Mode", "MatchOutcome" })
		expect(AnalyticsConfig.Events.MatchFormed).toEqual({ "Mode" })
		expect(AnalyticsConfig.Events.QueueTimedOut).toEqual({ "Mode" })
		expect(AnalyticsConfig.Events.MatchVoided).toEqual({ "Mode", "VoidCause" })
		expect(AnalyticsConfig.Events.BossEnded).toEqual({ "BossKind", "BossOutcome" })
		expect(Analytics.domains().Mode).toEqual(MatchConfig.ModeOrder)
	end)
end)

describe("a match played to its result (E8-S4)", function()
	it("tells MatchEnded for each player: the mode, the outcome, and how long it lasted", function()
		local setup, a, b = duel()
		sweep(setup, a, b)
		local seconds = lasted(setup, a)
		expect(seconds).toBeGreaterThan(DUEL.CountdownSeconds)
		expect(sent(setup.world, "MatchEnded")).toEqual({
			{ a, seconds, { CustomField01 = DUEL.Id, CustomField02 = "Win" } },
			{ b, seconds, { CustomField01 = DUEL.Id, CustomField02 = "Loss" } },
		})
		expect(sent(setup.world, "MatchVoided")).toEqual({})
	end)

	it("tells a draw as a draw", function()
		local setup, a = duel()
		-- Three rounds run out at full health on both sides.
		for round = 1, 3 do
			setup.world:advance(DUEL.DurationSeconds / 3 + 0.5)
			if round < 3 then
				setup.world:advance(MatchConfig.RoundOverSeconds + DUEL.CountdownSeconds + 0.5)
			end
		end
		setup.world:advance(MatchConfig.RoundOverSeconds + 0.5)
		expect(setup.match.getMatch(a).Phase).toBe("Result")
		local ended = sent(setup.world, "MatchEnded")
		expect(#ended).toBe(2)
		for _, event in ipairs(ended) do
			expect(event[3]).toEqual({ CustomField01 = DUEL.Id, CustomField02 = "Draw" })
		end
	end)

	it("is never voided once it has its result, whoever then leaves", function()
		local setup, a, b = duel()
		sweep(setup, a, b)
		setup.world:leave(a)
		setup.world:leave(b)
		setup.world:advance(DUEL.ResultSeconds + 1)
		expect(sent(setup.world, "MatchVoided")).toEqual({})
	end)
end)

describe("a match that ends with no result (E8-S4)", function()
	it("is told once, by the last player to leave, when everybody walks out", function()
		local setup, a, b = duel()
		setup.world:leave(a)
		setup.world:advance(0.2)
		setup.world:leave(b)
		setup.world:advance(2)
		local voided = sent(setup.world, "MatchVoided")
		expect(#voided).toBe(1)
		expect(voided[1][1]).toBe(b)
		expect(voided[1][3]).toEqual({ CustomField01 = DUEL.Id, CustomField02 = "Empty" })
		expect(sent(setup.world, "MatchEnded")).toEqual({})
	end)

	it("is told once, by whoever is still there, when the server closes", function()
		local setup, a, b = duel()
		setup.world:close()
		setup.world:leave(a)
		setup.world:advance(2)
		expect(setup.match.isInMatch(b)).toBe(false)
		local voided = sent(setup.world, "MatchVoided")
		expect(#voided).toBe(1)
		expect(voided[1][1]).toBe(b)
		expect(voided[1][3]).toEqual({ CustomField01 = DUEL.Id, CustomField02 = "Closing" })
	end)

	it("is told when its mode cannot say who won", function()
		local setup, a, b = duel()
		local mode = setup.world.require("src/server/GameModes").get(DUEL.Id)
		local finishes = mode.End
		mode.End = function()
			error("the mode broke")
		end
		sweep(setup, a, b)
		mode.End = finishes
		local voided = sent(setup.world, "MatchVoided")
		expect(#voided).toBe(1)
		expect(voided[1][1]).toBe(a)
		expect(voided[1][3]).toEqual({ CustomField01 = DUEL.Id, CustomField02 = "Error" })
		expect(sent(setup.world, "MatchEnded")).toEqual({})
	end)

	-- The void forfeit (D-255): a side walks out before the match was really played, and whoever stayed is let go
	-- with no result.
	it("is told once, by whoever stayed, when a side walks out of a match nobody really played", function()
		local setup, a, b = duel()
		setup.world:leave(b)
		setup.world:advance(3)
		expect(setup.match.isInMatch(a)).toBe(false)
		local voided = sent(setup.world, "MatchVoided")
		expect(#voided).toBe(1)
		expect(voided[1][1]).toBe(a)
		expect(voided[1][3]).toEqual({ CustomField01 = DUEL.Id, CustomField02 = "Unplayed" })
		expect(sent(setup.world, "MatchEnded")).toEqual({})
	end)

	-- MatchService.cancel (D-220): a match whose tick keeps failing is ended with no result.
	it("is told once, by whoever is still there, when the server cancels a match whose tick keeps failing", function()
		local setup, a, _b = duel()
		local mode = setup.world.require("src/server/GameModes").get(DUEL.Id)
		local verdict = mode.RoundVerdict
		mode.RoundVerdict = function()
			error("a verdict nobody can give")
		end
		setup.world:advance(2)
		mode.RoundVerdict = verdict
		expect(setup.match.isInMatch(a)).toBe(false)
		local voided = sent(setup.world, "MatchVoided")
		expect(#voided).toBe(1)
		expect(voided[1][1]).toBe(a)
		expect(voided[1][3]).toEqual({ CustomField01 = DUEL.Id, CustomField02 = "Cancelled" })
		expect(sent(setup.world, "MatchEnded")).toEqual({})
	end)

	it("is not told again when a match that has its result is cancelled because its end throws", function()
		local setup, a, b = duel()
		sweep(setup, a, b)
		local fire = setup.registry.fire
		setup.registry.fire = function(name: string, player: any, payload: any)
			if name == "MatchChanged" and payload == nil then
				error("the result screen could not be closed")
			end
			fire(name, player, payload)
		end
		setup.world:advance(DUEL.ResultSeconds + 2)
		setup.registry.fire = fire
		expect(setup.match.isInMatch(a)).toBe(false)
		expect(#sent(setup.world, "MatchEnded")).toBe(2)
		expect(sent(setup.world, "MatchVoided")).toEqual({})
	end)

	it("is not told again when a match is cancelled on its result screen, before its end", function()
		local setup, a, b = duel()
		sweep(setup, a, b)
		-- The winner's body can no longer be read: every tick of the result screen throws, until the server
		-- cancels the match.
		local body = a.Character
		a.Character = {
			FindFirstChildOfClass = function()
				error("a body nobody can read")
			end,
		}
		setup.world:advance(2)
		a.Character = body
		expect(setup.match.isInMatch(a)).toBe(false)
		expect(#sent(setup.world, "MatchEnded")).toBe(2)
		expect(sent(setup.world, "MatchVoided")).toEqual({})
	end)
end)

describe("the queue (E8-S4)", function()
	it("tells MatchFormed for each player of a match it forms, with the seconds they waited", function()
		local setup = Server.services()
		local lanes = queue(setup)
		local a = setup.world:join(411, "Ada")
		local b = setup.world:join(412, "Bea")
		lanes.join(a, DUEL.Id)
		setup.world:advance(3)
		lanes.join(b, DUEL.Id)
		setup.world:advance(QUEUE.TickSeconds + 0.1)
		expect(setup.match.isInMatch(a)).toBe(true)
		local formed = sent(setup.world, "MatchFormed")
		expect(#formed).toBe(2)
		local waits: { [any]: number } = {}
		for _, event in ipairs(formed) do
			expect(event[3]).toEqual({ CustomField01 = DUEL.Id })
			waits[event[1]] = event[2]
		end
		expect(waits[a]).toBeGreaterThanOrEqual(3)
		expect(waits[a]).toBeLessThanOrEqual(3 + QUEUE.TickSeconds + 1)
		expect(waits[a] - waits[b]).toBeGreaterThanOrEqual(2)
	end)

	it("tells QueueTimedOut for a player it lets go, with the seconds they waited", function()
		local setup = Server.services()
		local lanes = queue(setup)
		local alone = setup.world:join(413, "Cleo")
		lanes.join(alone, TEAM.Id)
		setup.world:advance(QUEUE.MaxQueueSeconds + QUEUE.TickSeconds + 0.5)
		local timedOut = sent(setup.world, "QueueTimedOut")
		expect(#timedOut).toBe(1)
		expect(timedOut[1][1]).toBe(alone)
		expect(timedOut[1][3]).toEqual({ CustomField01 = TEAM.Id })
		expect(timedOut[1][2]).toBeGreaterThanOrEqual(QUEUE.MaxQueueSeconds)
		expect(timedOut[1][2]).toBeLessThanOrEqual(QUEUE.MaxQueueSeconds + QUEUE.TickSeconds + 1)
		expect(sent(setup.world, "MatchFormed")).toEqual({})
	end)
end)

describe("a fight against the Erasure (E8-S4)", function()
	it("tells BossEnded for each participant: the event, its fall, and how long it lasted", function()
		local fight = erasure()
		fight.advance(SCHEDULE.IntervalSeconds + SCHEDULE.AnnounceSeconds + 1)
		expect(sent(fight.world, "BossEnded")).toEqual({})
		fight.advance(40)
		fight.outcome.value = "Defeated"
		fight.advance(0.5)
		local ended = sent(fight.world, "BossEnded")
		expect(#ended).toBe(2)
		for index, event in ipairs(ended) do
			expect(event[1]).toBe(fight.players[index])
			expect(event[3]).toEqual({ CustomField01 = "Event", CustomField02 = "Defeated" })
			expect(event[2]).toBeGreaterThanOrEqual(40)
			expect(event[2]).toBeLessThanOrEqual(42)
		end
	end)

	it("tells an escape at the end of the clock, once", function()
		local fight = erasure()
		fight.advance(SCHEDULE.IntervalSeconds + SCHEDULE.AnnounceSeconds + 1)
		fight.advance(SCHEDULE.FightSeconds + SCHEDULE.CleanupSeconds + 1)
		local ended = sent(fight.world, "BossEnded")
		expect(#ended).toBe(2)
		for _, event in ipairs(ended) do
			expect(event[3]).toEqual({ CustomField01 = "Event", CustomField02 = "Expired" })
			expect(event[2]).toBe(SCHEDULE.FightSeconds)
		end
	end)

	it("tells a practice as a practice, to the one who fought it", function()
		local fight = erasure()
		local starter = fight.players[1]
		expect(fight.worldBoss.enterFromPortal(starter)).toBe(true)
		fight.advance(PRACTICE.FightSeconds + PRACTICE.CleanupSeconds + 1)
		expect(sent(fight.world, "BossEnded")).toEqual({
			{ starter, PRACTICE.FightSeconds, { CustomField01 = "Practice", CustomField02 = "Expired" } },
		})
	end)
end)

return nil
