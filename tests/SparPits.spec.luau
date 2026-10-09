--!strict
-- The pits of the practice duel (E10-S6, BattlegroundConfig.Pits): where they stand, what the real Pits module builds
-- and lends, and what the real Attacks lets a pit's Forger strike. Pits and Attacks run on tests/engine.luau with
-- stand-ins for the bodies (Bots), the roster and the motion, which need the engine's humanoids; the geometry and
-- the gate in front of every blow are the modules' own.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BotBrain = require("../src/server/Pure/BotBrain")
local BotConfig = require("../src/shared/Config/BotConfig")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PITS = BattlegroundConfig.Pits
local MAP = BattlegroundConfig.Map
local DIR = "src/server/Services/BattlegroundService/"
local GRAVITY = 196.2
local DUELIST = BotConfig.Tiers[MatchConfig.Spar.TierId]

-- The east and west edge of pit `index`, walls included, in the page's frame.
local function edges(index: number): (number, number)
	local centre = PITS.FirstX + (index - 1) * PITS.SpacingX
	local half = PITS.Size / 2 + PITS.WallThickness
	return centre - half, centre + half
end

describe("where the pits stand", function()
	it("each more than a packet's reach from the page and from the next, clear of the page's kill plane", function()
		local radius = GameConfig.Vfx.BroadcastRadiusStuds
		local pageEast = MAP.Size / 2
		local west = edges(1)
		expect(west - pageEast).toBeGreaterThan(radius)
		for index = 2, PITS.Count do
			local _, previousEast = edges(index - 1)
			local nextWest = edges(index)
			expect(nextWest - previousEast).toBeGreaterThan(radius)
		end
		-- The page's kill plane spreads KillZoneSpread times its size round its centre: no pit stands over it.
		expect(west).toBeGreaterThan(MAP.Size * MAP.KillZoneSpread / 2)
		-- A Duelist's bolt reaches no other pit.
		local bolt = DUELIST.Bolt
		assert(bolt ~= nil, "the Duelist throws no bolt: this gate would check nothing")
		expect(bolt.SpawnOffset + bolt.Range).toBeLessThan(PITS.SpacingX - PITS.Size)
	end)

	it("are walled higher than a double jump, with the two pads inside, on the page's axis", function()
		local movement = GameConfig.Movement
		local reach = (movement.JumpPower ^ 2 + movement.DoubleJumpVelocity ^ 2) / (2 * GRAVITY)
		expect(PITS.WallHeight).toBeGreaterThan(reach)
		expect(PITS.PadInsetStuds).toBeGreaterThan(0)
		expect(PITS.PadInsetStuds * 2).toBeLessThan(PITS.Size)
		-- The Forger's pad west of the player's, far enough apart that nobody starts in reach of a swing.
		expect(PITS.Size - 2 * PITS.PadInsetStuds).toBeGreaterThan(DUELIST.Melee.Range * 2)
		expect(PITS.FallDepthStuds).toBeGreaterThan(0)
		expect(PITS.Count).toBeGreaterThanOrEqual(1)
	end)

	it("stand in a folder no other service rebuilds", function()
		local anchors = BattlegroundConfig.Anchors
		local folders = { anchors.Map, BotConfig.FolderName, WorldConfig.HubAnchors.Folder, "Arenas", anchors.Pits }
		for first = 1, #folders do
			for second = first + 1, #folders do
				expect(folders[first] ~= folders[second]).toBe(true)
			end
		end
	end)
end)

-- The real Pits, with stand-ins for what it moves and puts down: every call recorded.
type Recorded = { Name: string, Args: { any } }
local function pitsWorld(): (any, any, { Recorded }, any)
	local calls: { Recorded } = {}
	local function recorder(name: string, result: any?): (...any) -> any
		return function(...: any): any
			table.insert(calls, { Name = name, Args = { ... } })
			return result
		end
	end
	local tagged: { [any]: { string } } = {}
	local world = Engine.world({
		Stubs = {
			["src/server/Services/BattlegroundService/Bots"] = {
				spawnInPit = function(slot: number, tierId: string, placement: any): any
					table.insert(calls, { Name = "spawnInPit", Args = { slot, tierId, placement } })
					return {
						Slot = slot,
						Memory = BotBrain.newMemory(),
						Dead = false,
						Humanoid = { Health = 160, MaxHealth = 160 },
						Model = Engine.instance("Model"),
					}
				end,
				destroy = recorder("destroy"),
			},
			["src/server/Services/BattlegroundService/Roster"] = { place = recorder("place") },
			["src/server/Services/BattlegroundService/Attacks"] = { retract = recorder("retract") },
			["src/server/Services/BattlegroundService/Motion"] = {
				stand = recorder("stand"),
				release = recorder("release"),
			},
		},
		Services = {
			CollectionService = {
				AddTag = function(_self: any, instance: any, tag: string)
					local list = tagged[instance] or {}
					table.insert(list, tag)
					tagged[instance] = list
				end,
			},
		},
	})
	local Pits = world.require(DIR .. "Pits")
	local trusted: { [any]: any } = {}
	Pits.Init({
		Combat = {
			trustedPosition = function(player: any): any
				return trusted[player]
			end,
		},
	})
	Pits.build()
	return world, Pits, calls, { Tagged = tagged, Trusted = trusted }
end

describe("the pits, run", function()
	it("are built as walled floors, every solid a barrier, in their own folder", function()
		local world, _, _, extra = pitsWorld()
		local folder = world.workspace:FindFirstChild(BattlegroundConfig.Anchors.Pits)
		assert(folder ~= nil, "no pits were built")
		expect(#folder:GetChildren()).toBe(PITS.Count)
		local barrier = require("../src/server/Config/MovementGuardConfig").BarrierTag
		for _, pit in ipairs(folder:GetChildren()) do
			local floor = pit:FindFirstChild(BattlegroundConfig.Anchors.Floor)
			assert(floor ~= nil, pit.Name .. " has no floor")
			-- Its top face at the page's.
			expect(floor.CFrame.Position.Y + floor.Size.Y / 2).toBeCloseTo(MAP.Origin[2], 6)
			local solids = 0
			for _, part in ipairs(pit:GetChildren()) do
				solids += 1
				expect(table.find(extra.Tagged[part] or {}, barrier)).never.toBeNil()
			end
			-- The floor, four walls and their four rules.
			expect(solids).toBe(9)
		end
	end)

	it("are lent one to a player, the same again to the same, none past the last, and taken back", function()
		local _, Pits = pitsWorld()
		local players = {}
		for index = 1, PITS.Count + 1 do
			players[index] = Engine.instance("Player")
		end
		local first = Pits.acquire(players[1])
		expect(first).never.toBeNil()
		expect(Pits.acquire(players[1])).toBe(first)
		for index = 2, PITS.Count do
			expect(Pits.acquire(players[index])).never.toBeNil()
		end
		expect(Pits.acquire(players[PITS.Count + 1])).toBeNil()
		Pits.release(first)
		expect(Pits.acquire(players[PITS.Count + 1])).toBe(first)
	end)

	it("seats a round: a fresh Forger facing the player's pad, the player on it, the round not on yet", function()
		local _, Pits, calls = pitsWorld()
		local player = Engine.instance("Player")
		player.UserId = 5
		local character = Engine.instance("Model")
		local pit = Pits.acquire(player)
		expect(Pits.seat(pit, player, character, 10)).toBe(true)
		local spawned, placed = nil, nil
		for _, call in ipairs(calls) do
			if call.Name == "spawnInPit" then
				spawned = call.Args
			elseif call.Name == "place" then
				placed = call.Args
			end
		end
		assert(spawned ~= nil and placed ~= nil, "the round put nobody down")
		-- Its own tell id, past every slot of the page's, and the spar's tier, fighting on this pit's ground.
		expect(spawned[1]).toBeGreaterThan(BotConfig.MaxBots)
		expect(spawned[2]).toBe(MatchConfig.Spar.TierId)
		expect(spawned[3].Pit).toBe(pit.Ground)
		local landing = placed[3]
		expect(placed[1]).toBe(player)
		expect(placed[2]).toBe(character)
		-- The player east of the Forger, on the page's axis, the Forger looking at them.
		local frame = spawned[3].Frame
		expect(landing.X).toBeGreaterThan(frame.Position.X)
		expect(landing.Z).toBeCloseTo(MAP.Origin[3], 6)
		expect(frame.Position.Z).toBeCloseTo(MAP.Origin[3], 6)
		expect(frame.LookVector.X).toBeGreaterThan(0.99)
		expect(pit.Ground.Member).never.toBeNil()
		expect(pit.Ground.Member.Player).toBe(player)
		expect(pit.Ground.Live).toBe(false)
		Pits.setLive(pit, true)
		expect(pit.Ground.Live).toBe(true)
		Pits.setLive(pit, false)
		expect(pit.Ground.Live).toBe(false)
		-- A second round replaces the Forger: the first is removed.
		Pits.seat(pit, player, character, 20)
		local destroyed = 0
		for _, call in ipairs(calls) do
			if call.Name == "destroy" then
				destroyed += 1
			end
		end
		expect(destroyed).toBe(1)
		Pits.release(pit)
		expect(pit.Ground.Member).toBeNil()
		expect(pit.Owner).toBeNil()
	end)

	it("holds its player only while the position the server trusts is on its floor", function()
		local _, Pits, _, extra = pitsWorld()
		local player = Engine.instance("Player")
		local pit = Pits.acquire(player)
		local bounds = pit.Ground.Bounds
		local centreX = MAP.Origin[1] + (bounds.MinX + bounds.MaxX) / 2
		extra.Trusted[player] = roblox.Vector3.new(centreX, MAP.Origin[2] + 3, MAP.Origin[3])
		expect(Pits.holds(player)).toBe(true)
		extra.Trusted[player] = roblox.Vector3.new(MAP.Origin[1], MAP.Origin[2] + 3, MAP.Origin[3])
		expect(Pits.holds(player)).toBe(false)
		extra.Trusted[player] = nil
		expect(Pits.holds(player)).toBe(false)
		expect(Pits.holds(Engine.instance("Player"))).toBe(false)
	end)
end)

-- The real Attacks, one Duelist's swing at a player standing right in front of it.
local function swing(setupGround: (ground: any, member: any, bot: any, player: any) -> ()): number
	local struck = 0
	local world = Engine.world({
		Stubs = {
			["src/server/Services/BattlegroundService/Bots"] = {},
			["src/server/Services/BattlegroundService/Map"] = {},
			["src/server/Services/BattlegroundService/Roster"] = {
				get = function(): any
					return nil
				end,
			},
		},
	})
	local Attacks = world.require(DIR .. "Attacks")
	local Context = world.require(DIR .. "Context")
	local players = world.game:GetService("Players")
	local player = Engine.instance("Player", players)
	player.UserId = 9
	local character = Engine.instance("Model", world.workspace)
	local humanoid = Engine.instance("Humanoid", character)
	humanoid.Health = 100
	local root = Engine.instance("BasePart", character)
	root.Name = "HumanoidRootPart"
	player.Character = character
	-- In a pit, three studs east of its Forger.
	local pitX = PITS.FirstX
	root.Position = Context.toWorld(pitX + 3, BattlegroundConfig.StandingRootStuds, 0)
	local botRoot = { Position = Context.toWorld(pitX, BattlegroundConfig.StandingRootStuds, 0) }
	local trusted = root.Position
	Attacks.Init({
		Combat = {
			ApplyDamage = function(source: any): any
				expect(source).toBeNil()
				struck += 1
				return { Applied = 5, Killed = false, Blocked = false }
			end,
			trustedPosition = function(): any
				return trusted
			end,
			knockback = function() end,
		},
		Movement = {
			applyStun = function() end,
			ragdoll = function() end,
			isDown = function(): boolean
				return false
			end,
		},
		Vfx = { emit = function() end },
	}, { FloorY = 0, Layout = { Camp = { MinX = -85, MaxX = -59, MinZ = -22, MaxZ = 22 } } })
	local ground = {
		Live = true,
		Member = nil :: any,
		Bounds = {
			MinX = pitX - PITS.Size / 2,
			MaxX = pitX + PITS.Size / 2,
			MinZ = -PITS.Size / 2,
			MaxZ = PITS.Size / 2,
		},
	}
	local member = { Player = player, UserId = player.UserId, ArrivedAt = -100 }
	ground.Member = member
	local bot = { Root = botRoot, Def = DUELIST, Memory = BotBrain.newMemory(), Pit = ground :: any, Slot = 11 }
	setupGround(ground, member, bot, player)
	trusted = root.Position
	Attacks.resolve(bot, {
		Kind = "Melee",
		Step = 1,
		AimX = 1,
		AimZ = 0,
		Final = false,
		TargetUserId = player.UserId,
	}, { member }, 0)
	return struck
end

describe("a pit's Forger's blow, run", function()
	it("lands on its one duellist, on its floor, while the round is on", function()
		expect(swing(function() end)).toBe(1)
	end)

	it("lands on nobody while the round is off", function()
		expect(swing(function(ground)
			ground.Live = false
		end)).toBe(0)
	end)

	it("lands on nobody the pit does not hold", function()
		expect(swing(function(ground)
			ground.Member = { Player = Engine.instance("Player"), UserId = 1 }
		end)).toBe(0)
	end)

	it("lands on nobody the server believes off its floor", function()
		expect(swing(function(ground)
			ground.Bounds = { MinX = -10, MaxX = 10, MinZ = -10, MaxZ = 10 }
		end)).toBe(0)
	end)

	it("of a page's Forger lands on no duellist of a pit, who is no member of the page", function()
		expect(swing(function(_, _, bot)
			bot.Pit = nil
		end)).toBe(0)
	end)
end)

-- The real Roster, with one member of the page whose body has just died there; `claim` runs before their next body
-- arrives, as a pit claims them before its round loads one. Returns whether that body was taken back to the camp.
local function nextBodyToCamp(claim: (roster: any, player: any) -> ()): boolean
	local world = Engine.world({ Stubs = { ["src/server/Services/BattlegroundService/Map"] = {} } })
	local Roster = world.require(DIR .. "Roster")
	local players = world.game:GetService("Players")
	players.RespawnTime = 5
	local player = Engine.instance("Player", players)
	player.UserId = 7
	local landing =
		roblox.Vector3.new(MAP.Origin[1], MAP.Origin[2] + BattlegroundConfig.StandingRootStuds, MAP.Origin[3])
	local placed = 0
	Roster.Init({
		Registry = { fire = function() end },
		Combat = {
			resyncPosition = function()
				placed += 1
			end,
			trustedPosition = function(): any
				return nil
			end,
			protect = function() end,
		},
		Match = {
			isInMatch = function(): boolean
				return false
			end,
		},
		WorldBoss = {
			isEngaged = function(): boolean
				return false
			end,
		},
	}, { Arrivals = { { Position = landing } } }, function(): number
		return 0
	end)
	local function body(): (any, any)
		local character = Engine.instance("Model", world.workspace)
		local humanoid = Engine.instance("Humanoid", character)
		humanoid.Health = 100
		local root = Engine.instance("BasePart", character)
		root.Name = "HumanoidRootPart"
		root.Position = landing
		character.PivotTo = function() end
		return character, humanoid
	end
	Roster.track(player)
	local first, humanoid = body()
	player.Character = first
	Roster.admit(player, first, landing, 0, 0)
	humanoid.Health = 0
	humanoid.Died:Fire()
	claim(Roster, player)
	local second = body()
	player.Character = second
	player.CharacterAdded:Fire(second)
	world:advance(0.1)
	return Roster.get(player) ~= nil and placed > 0
end

describe("a pit taking its player from the page, run", function()
	it("leaves the page a body that died there, whose next body comes back to the camp", function()
		expect(nextBodyToCamp(function() end)).toBe(true)
	end)

	it("keeps the next body for the pit once the pit has claimed its player", function()
		expect(nextBodyToCamp(function(roster, player)
			roster.release(player)
		end)).toBe(false)
	end)
end)

describe("the pits in the Battleground's own source", function()
	local function code(name: string): string
		return ((fs.readFile(DIR .. name .. ".luau"):gsub("%-%-[^\n]*", "")):gsub("%s+", " "))
	end

	it("keep a pit's Forger out of the page's slots, its count and its tick", function()
		local bots = code("Bots")
		local spawnInPit = bots:match("function Bots%.spawnInPit%(.-\nend")
			or bots:match("function Bots%.spawnInPit%(.- end ")
		assert(spawnInPit ~= nil, "Bots has no spawnInPit: this gate would check nothing")
		expect(spawnInPit:find("bySlot", 1, true)).toBeNil()
		expect(bots:find("Slot = BotConfig.MaxBots + index", 1, true)).toBeNil()
		expect(code("Pits"):find("Slot = BotConfig.MaxBots + index,", 1, true)).never.toBeNil()
	end)

	it("think for a pit's Forger only while its round is on, against its one duellist", function()
		local init = code("init")
		local step = init:match("local function stepPits%(.-%send%send ")
		assert(step ~= nil, "init has no stepPits: this gate would check nothing")
		expect(step:find("and pit.Ground.Live and not bot.Dead", 1, true)).never.toBeNil()
		expect(
			step:find("apply(bot, BotBrain.decide(bot.Def, RULES, bot.Memory, perception), now, { member })", 1, true)
		).never.toBeNil()
		expect(init:find("think(now) stepPits(map, now)", 1, true)).never.toBeNil()
		expect(
			init:find(
				"apply(bot, BotBrain.decide(bot.Def, RULES, bot.Memory, perception), now, Roster.list())",
				1,
				true
			)
		).never.toBeNil()
	end)

	it("claim their player from the page before the round loads a body, as a match does", function()
		local open = code("init"):match("function BattlegroundService%.openPit%(.-return true end ")
		assert(open ~= nil, "init has no openPit: this gate would check nothing")
		local acquired = open:find("Pits.acquire(player) == nil then return false end", 1, true)
		local released = open:find("Roster.release(player) return true", 1, true)
		assert(acquired ~= nil and released ~= nil, "openPit no longer claims its player: " .. open)
		expect(released).toBeGreaterThan(acquired)
	end)

	it("pay nothing for a pit's Forger's kill, whose duel pays", function()
		expect(DUELIST.RewardKey).toBeNil()
		local rewards = code("Rewards")
		expect(rewards:find("if killerUserId == 0 or key == nil then return end", 1, true)).never.toBeNil()
	end)
end)

return nil
