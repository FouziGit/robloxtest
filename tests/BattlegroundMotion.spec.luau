--!strict
-- A Forger's walk (D-131, D-282), run on a pretend server: where Motion sends it, and what it searches for on the
-- way. The body is a table with a position and a humanoid that remembers where it was told to go.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BattlegroundLayout = require("../src/server/Pure/BattlegroundLayout")
local BotConfig = require("../src/shared/Config/BotConfig")
local Harness = require("./harness")
local Server = require("./server")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DIR = "src/server/Services/BattlegroundService/"
local MAP = BattlegroundConfig.Map
local DRESSING: BattlegroundLayout.Dressing = {
	FloorName = BattlegroundConfig.Anchors.Floor,
	KillZoneName = BattlegroundConfig.Anchors.KillZone,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
	CampTop = WorldConfig.Ladder.Training,
	CampTransparency = WorldConfig.Battleground.CampTransparency,
}
local LAYOUT = BattlegroundLayout.build(MAP, DRESSING, BotConfig.Path.RadiusStuds)

type Walk = { Start: BattlegroundLayout.Point, Goal: BattlegroundLayout.Point, Elsewhere: BattlegroundLayout.Point }

local function distance(a: BattlegroundLayout.Point, b: BattlegroundLayout.Point): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

type Fixture = {
	motion: any,
	origin: any,
	-- Every point the humanoid was told to walk to, in the page's frame.
	moves: { BattlegroundLayout.Point },
	-- How many times the shortest way round was searched.
	searches: () -> number,
	forger: (at: BattlegroundLayout.Point, pit: any) -> any,
}

local function fixture(): Fixture
	local searches = 0
	local counted: any = table.clone(BattlegroundLayout)
	counted.path = function(layout: any, from: number, to: number): any
		searches += 1
		return BattlegroundLayout.path(layout, from, to)
	end
	local world = Server.world({
		Stubs = {
			[DIR .. "Bots"] = {},
			[DIR .. "Map"] = {},
			["src/server/Pure/BattlegroundLayout"] = counted,
		},
	})
	local motion = world.require(DIR .. "Motion")
	motion.Init({ Layout = LAYOUT })
	local origin = world.require(DIR .. "Context").Origin
	local moves: { BattlegroundLayout.Point } = {}
	local function forger(at: BattlegroundLayout.Point, pit: any): any
		return {
			Pit = pit,
			Goal = nil,
			GoalAt = 0,
			Waypoint = nil,
			Route = nil,
			Root = { Position = origin + roblox.Vector3.new(at.X, 0, at.Z) },
			Humanoid = {
				MoveTo = function(_self: any, point: any)
					table.insert(moves, { X = point.X - origin.X, Z = point.Z - origin.Z })
				end,
			},
		}
	end
	return {
		motion = motion,
		origin = origin,
		moves = moves,
		searches = function(): number
			return searches
		end,
		forger = forger,
	}
end

-- A walk across the page that takes a Forger round more than one corner: the straight line is cut, and from the
-- first waypoint it walks to the goal is still cut. The walks are tried on `fx`, between nodes spread over the page;
-- and a second goal, more than a node step from the first, that the line from the start is cut for too.
local function longWalk(fx: Fixture): Walk
	local spread: { BattlegroundLayout.Point } = {}
	for index = 1, #LAYOUT.Nodes, 97 do
		table.insert(spread, LAYOUT.Nodes[index])
	end
	for _, start in ipairs(spread) do
		for _, goal in ipairs(spread) do
			if not BattlegroundLayout.segmentClear(LAYOUT, start.X, start.Z, goal.X, goal.Z) then
				local probe = fx.forger(start, nil)
				fx.motion.walkTo(probe, goal.X, goal.Z, 0)
				local waypoint = probe.Waypoint
				if
					waypoint ~= nil
					and not BattlegroundLayout.segmentClear(
						LAYOUT,
						waypoint.X - fx.origin.X,
						waypoint.Z - fx.origin.Z,
						goal.X,
						goal.Z
					)
				then
					for _, node in ipairs(LAYOUT.Nodes) do
						if
							distance(node, goal) > 2 * MAP.Grid.StepStuds
							and not BattlegroundLayout.segmentClear(LAYOUT, start.X, start.Z, node.X, node.Z)
						then
							return { Start = start, Goal = goal, Elsewhere = node }
						end
					end
				end
			end
		end
	end
	error("the page has no walk round two corners: this gate would check nothing")
end

describe("a Forger's walk", function()
	it("is held to the roam on the page, and to nothing in a pit, which lies far outside it", function()
		local fx = fixture()
		local pit = { Live = true, Member = nil, Bounds = { MinX = 600, MaxX = 700, MinZ = -50, MaxZ = 50 } }
		local duellist = fx.forger({ X = 620, Z = 0 }, pit)
		fx.motion.walkTo(duellist, 650, 0, 0)
		expect(duellist.Goal.X - fx.origin.X).toBe(650)
		local roaming = fx.forger({ X = 0, Z = 200 }, nil)
		fx.motion.walkTo(roaming, 650, 200, 0)
		expect(roaming.Goal.X - fx.origin.X).toBe(LAYOUT.Roam.MaxX)
	end)

	it("keeps its way round while the goal stays put, and searches again only when the goal moves on", function()
		local walk = longWalk(fixture())
		local fx = fixture()
		local forger = fx.forger(walk.Start, nil)
		fx.motion.walkTo(forger, walk.Goal.X, walk.Goal.Z, 0)
		expect(fx.searches()).toBe(1)
		local first = fx.moves[1]
		-- It reaches its waypoint: on to the next one of the same route, with nothing searched.
		forger.Root.Position = forger.Waypoint
		fx.motion.walkTo(forger, walk.Goal.X, walk.Goal.Z, 0.01)
		expect(fx.searches()).toBe(1)
		expect(#fx.moves).toBe(2)
		expect(fx.moves[2].X ~= first.X or fx.moves[2].Z ~= first.Z).toBe(true)
		-- Back where it started, the goal moves on by more than a node step: a new search.
		forger.Root.Position = fx.origin + roblox.Vector3.new(walk.Start.X, 0, walk.Start.Z)
		fx.motion.walkTo(forger, walk.Elsewhere.X, walk.Elsewhere.Z, 0.02)
		expect(fx.searches()).toBe(2)
	end)
end)
