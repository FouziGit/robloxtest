--!strict
-- One server teleport, and it streams the destination in first (E6-S7, D-XXX).
--
-- Before it, only BattlegroundService.enter asked a client for the world around a landing; a match pad 900 studs
-- up, the hub and the Erasure's ring were each put down by their own copy of the same five lines, none of which
-- waited for anything. src/server/World/Teleport is now the one module that moves a player's body elsewhere and the
-- one that calls RequestStreamAroundAsync. It is run here on the pretend engine, with a place that streams and one
-- that does not; the services that move players are held to it by their sources.
local Engine = require("./engine")
local Harness = require("./harness")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local PortalConfig = require("../src/shared/Config/PortalConfig")

type Trip = {
	Teleport: any,
	world: any,
	player: any,
	character: any,
	root: any,
	events: { string },
	requests: { { Position: any, Timeout: number } },
	resyncs: { any },
	combat: any,
}

-- A player with a moving body, on a place that streams or not. Every request, pivot and resync is written to
-- `events` in the order it happened.
local function trip(streaming: boolean): Trip
	local players = Engine.instance("Players")
	local world = Engine.world({ Services = { Players = players } })
	world.workspace.StreamingEnabled = streaming
	local events: { string } = {}
	local requests: { { Position: any, Timeout: number } } = {}
	local resyncs: { any } = {}
	local player = Engine.instance("Player", players)
	player.Name = "Traveller"
	player.RequestStreamAroundAsync = function(_self: any, position: any, timeout: number)
		table.insert(events, "stream")
		table.insert(requests, { Position = position, Timeout = timeout })
	end
	local character = Engine.instance("Model", world.workspace)
	local root = Engine.instance("BasePart", character)
	root.Name = "HumanoidRootPart"
	root.AssemblyLinearVelocity = Vector3.new(0, -80, 0)
	root.AssemblyAngularVelocity = Vector3.new(3, 0, 0)
	character.PrimaryPart = root
	character.PivotTo = function(_self: any, frame: any)
		table.insert(events, "pivot")
		root.CFrame = frame
	end
	player.Character = character
	local combat = {
		resyncPosition = function(_player: any, position: any)
			table.insert(events, "resync")
			table.insert(resyncs, position)
		end,
	}
	return {
		Teleport = world.require("src/server/World/Teleport"),
		world = world,
		player = player,
		character = character,
		root = root,
		events = events,
		requests = requests,
		resyncs = resyncs,
		combat = combat,
	}
end

local TARGET = CFrame.new(1500, 40, 12)

describe("Teleport on a place that streams", function()
	it("asks for the world around the destination, then puts the body down there", function()
		local t = trip(true)
		expect(t.Teleport.travel(t.combat, t.player, t.character, TARGET)).toBe(true)
		expect(t.events).toEqual({ "stream", "pivot", "resync" })
		expect(t.requests[1].Position).toBe(TARGET.Position)
		expect(t.requests[1].Timeout).toBe(PortalConfig.StreamTimeoutSeconds)
		expect(t.root.CFrame).toBe(TARGET)
	end)

	it("moves nothing when the trip is off by the time the world has streamed in", function()
		local t = trip(true)
		local asked = 0
		expect(t.Teleport.travel(t.combat, t.player, t.character, TARGET, function(): boolean
			asked += 1
			return false
		end)).toBe(false)
		expect(asked).toBe(1)
		expect(t.events).toEqual({ "stream" })
	end)

	it("moves nothing when the body changed while it streamed", function()
		local t = trip(true)
		t.player.RequestStreamAroundAsync = function()
			t.player.Character = Engine.instance("Model", t.world.workspace)
		end
		expect(t.Teleport.travel(t.combat, t.player, t.character, TARGET)).toBe(false)
		expect(t.resyncs).toEqual({})
	end)

	it("asks ahead without waiting", function()
		local t = trip(true)
		t.Teleport.prestream(t.player, TARGET.Position)
		expect(t.requests[1].Position).toBe(TARGET.Position)
		expect(t.events).toEqual({ "stream" })
	end)
end)

describe("Teleport on a place that does not stream", function()
	it("asks for nothing and moves at once", function()
		local t = trip(false)
		expect(t.Teleport.travel(t.combat, t.player, t.character, TARGET)).toBe(true)
		t.Teleport.prestream(t.player, TARGET.Position)
		expect(t.events).toEqual({ "pivot", "resync" })
	end)
end)

describe("Teleport.place", function()
	it("stills the body and anchors trust on the destination itself", function()
		local t = trip(true)
		t.Teleport.place(t.combat, t.player, t.character, TARGET)
		expect(t.events).toEqual({ "pivot", "resync" })
		expect(t.root.AssemblyLinearVelocity).toBe(Vector3.zero)
		expect(t.root.AssemblyAngularVelocity).toBe(Vector3.zero)
		expect(t.resyncs[1]).toBe(TARGET.Position)
	end)
end)

describe("the services that move a player", function()
	local function code(path: string): string
		return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""):gsub("%s+", " "))
	end

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

	it("leave streaming to Teleport alone", function()
		local files: { string } = {}
		collect("src/server", files)
		local callers: { string } = {}
		for _, path in ipairs(files) do
			if code(path):find("RequestStreamAroundAsync", 1, true) ~= nil then
				table.insert(callers, path)
			end
		end
		expect(callers).toEqual({ "src/server/World/Teleport.luau" })
	end)

	it("go through it: a match pad, the hub, the Erasure's ring and the Battleground's camp", function()
		local uses: { [string]: { string } } = {
			["src/server/Services/MatchService.luau"] = {
				"Teleport.prestream(participant.Player, padFrame(pad, center).Position)",
				"return Teleport.travel(combat, player, character, padFrame(spawn, center), current)",
			},
			["src/server/Services/HubService.luau"] = {
				"Teleport.place(combat, player, character, landing)",
				"return Teleport.travel(combat, player, character, landing)",
			},
			["src/server/Services/WorldBossService/Encounter.luau"] = {
				"Teleport.place(deps.Combat, player, character,",
			},
			["src/server/Services/WorldBossService/init.luau"] = { "Teleport.streamAround(player, live.Center)" },
			["src/server/Services/BattlegroundService/init.luau"] = { "Teleport.streamAround(player, landing)" },
			["src/server/Services/BattlegroundService/Roster.luau"] = {
				"Teleport.streamAround(player, landing)",
				"Teleport.place(deps.Combat, player, character,",
			},
			["src/server/Services/PortalService.luau"] = { "return deps.Hub.travelToHub(player), nil, nil" },
		}
		for path, needles in pairs(uses) do
			local source = code(path)
			for _, needle in ipairs(needles) do
				if source:find(needle, 1, true) == nil then
					error(("%s no longer moves a player through Teleport: %s"):format(path, needle))
				end
			end
		end
	end)

	it("ask again, after the wait, everything it may have changed", function()
		-- The gate of the Erasure streams first, then asks whether the player may still go at all.
		local enter = code("src/server/Services/WorldBossService/init.luau")
		local streams = enter:find("Teleport.streamAround(player, live.Center)", 1, true) :: number
		expect(enter:find("if deps.Match.isInMatch(player) then", streams, true)).never.toBeNil()
		-- A body that died in the camp streams its landing, then is asked everything before it is placed.
		local roster = code("src/server/Services/BattlegroundService/Roster.luau")
		local waited = roster:find("Teleport.streamAround(player, landing) if player.Character ~= character", 1, true)
		expect(waited).never.toBeNil()
		-- A round's pad is taken only while the round still wants it after the wait.
		expect(code("src/server/Services/MatchService.luau")).toContain(
			"local function current(): boolean return not active.Finished and active.Generation == generation end"
		)
		expect(code("src/server/Services/MatchService.luau")).toContain(
			"elseif placeCharacter(player, character, pad, center, current) then active.Placed[player] = { Character = character, At = os.clock() } end if not current() then return end participant.Alive = true"
		)
	end)
end)
