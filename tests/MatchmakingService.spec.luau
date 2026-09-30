--!strict
-- The queues as MatchmakingService runs them, on a pretend server: its Heartbeat, its scans, and the matches it
-- hands to MatchService. The pairing rules themselves are MatchmakingCore's (tests/Matchmaking.spec.luau).
--
-- E16-S1: the Erasure's event no longer pauses ranked (D-25 is replaced). A match formed during the event keeps its
-- participant PvP, because every place owns its own damage rule (tests/DamageZones.spec.luau), so the queue has
-- nothing to wait for. E10-S7: a newcomer, as RankingService says, is held to the newcomer's window.
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local Server = require("./server")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Fixture = {
	world: Server.World,
	started: { { Mode: string, Teams: { { number } } } },
	queue: (player: any, modeId: string) -> (),
	boss: { Live: boolean },
	inMatch: { [any]: boolean },
	snapshots: { [any]: any },
	-- Each player's profile, which the Ranking stub reads the way RankingService.isNewcomer does, and their rating.
	profiles: { [any]: any },
	ratings: { [any]: number },
}

local function fixture(): Fixture
	local world = Server.world()
	local service = world.require("src/server/Services/MatchmakingService")
	local handlers: { [string]: (...any) -> () } = {}
	local started: { { Mode: string, Teams: { { number } } } } = {}
	local boss = { Live = false }
	local inMatch: { [any]: boolean } = {}
	local snapshots: { [any]: any } = {}
	local profiles: { [any]: any } = {}
	local ratings: { [any]: number } = {}
	-- The whole table the bootstrap hands every service, the Erasure among it: the queue must not ask it anything.
	service.Init({
		Registry = {
			on = function(name: string, handler: (...any) -> ())
				handlers[name] = handler
			end,
			fire = function(name: string, player: any, payload: any)
				if name == "QueueChanged" then
					snapshots[player] = payload
				end
			end,
		},
		Notify = { send = function(_player: any, _key: string, _params: any, _kind: any, _sfx: any) end },
		Ranking = {
			getRating = function(player: any, _modeId: string): number
				return ratings[player] or 1000
			end,
			isNewcomer = function(player: any): boolean
				local data = profiles[player]
				return data == nil
					or data.Stats.MatchesPlayed < MatchConfig.Newcomer.MinMatches
					or data.Progression.Level < MatchConfig.Newcomer.MinLevel
			end,
		},
		Match = {
			isInMatch = function(player: any): boolean
				return inMatch[player] == true
			end,
			isFinishing = function(_player: any): boolean
				return false
			end,
			releaseFromResult = function(_player: any): boolean
				return false
			end,
			start = function(modeId: string, teams: { { number } }): string?
				table.insert(started, { Mode = modeId, Teams = teams })
				return modeId .. "-" .. #started
			end,
		},
		WorldBoss = {
			isLive = function(): boolean
				return boss.Live
			end,
		},
	})
	service.Start()
	return {
		world = world,
		started = started,
		queue = function(player: any, modeId: string)
			handlers.JoinQueue(player, modeId)
		end,
		boss = boss,
		inMatch = inMatch,
		snapshots = snapshots,
		profiles = profiles,
		ratings = ratings,
	}
end

-- A player with a profile: `played` matches at `level`.
local function veteran(fx: Fixture, userId: number, played: number, level: number): any
	local player = fx.world:join(userId, "P" .. userId)
	fx.profiles[player] = { Stats = { MatchesPlayed = played }, Progression = { Level = level } }
	return player
end

describe("the queue during the Erasure's event", function()
	it("forms a ranked match while the event runs (E16-S1)", function()
		local fx = fixture()
		fx.boss.Live = true
		local a = veteran(fx, 1, 40, 20)
		local b = veteran(fx, 2, 40, 20)
		fx.queue(a, "Duel1v1")
		fx.queue(b, "Duel1v1")
		fx.world:advance(MatchConfig.Matchmaking.TickSeconds + 0.5)
		expect(#fx.started).toBe(1)
		expect(fx.started[1].Mode).toBe("Duel1v1")
		expect(fx.snapshots[a].Queued).toBe(false)
	end)

	it("counts a wait through the event like any other", function()
		local fx = fixture()
		fx.boss.Live = true
		local a = veteran(fx, 1, 40, 20)
		fx.queue(a, "Team3v3")
		fx.world:advance(30)
		-- Nobody slides a queue's clock back for the event any more: the wait shown is the wait served.
		expect(fx.snapshots[a].Queued).toBe(true)
		expect(fx.snapshots[a].WaitedSeconds).toBeGreaterThanOrEqual(28)
	end)
end)

describe("the quick duel for newcomers", function()
	it("flags a newcomer, and keeps a far veteran off them for their first two minutes", function()
		local fx = fixture()
		local novice = veteran(fx, 1, 2, 12)
		local old = veteran(fx, 2, 60, 30)
		fx.ratings[old] = 1700
		fx.queue(old, "Duel1v1")
		fx.world:advance(60)
		fx.queue(novice, "Duel1v1")
		fx.world:advance(MatchConfig.Newcomer.WindowSeconds - 4)
		expect(#fx.started).toBe(0)
		fx.world:advance(8)
		expect(#fx.started).toBe(1)
	end)

	it("pairs two veterans as far apart the same way it always did", function()
		local fx = fixture()
		local a = veteran(fx, 1, 60, 30)
		local b = veteran(fx, 2, 60, 30)
		fx.ratings[a] = 1700
		fx.queue(a, "Duel1v1")
		fx.world:advance(60)
		fx.queue(b, "Duel1v1")
		fx.world:advance(MatchConfig.Matchmaking.TickSeconds + 0.5)
		expect(#fx.started).toBe(1)
	end)

	it("takes a player RankingService cannot tell about for a newcomer", function()
		local fx = fixture()
		local unknown = fx.world:join(1, "Unknown")
		local old = veteran(fx, 2, 60, 30)
		fx.ratings[old] = 1700
		fx.queue(old, "Duel1v1")
		fx.world:advance(60)
		fx.queue(unknown, "Duel1v1")
		fx.world:advance(MatchConfig.Matchmaking.TickSeconds + 0.5)
		expect(#fx.started).toBe(0)
	end)
end)
