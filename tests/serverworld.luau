--!strict
-- MovementService running in the pretend engine (tests/engine.luau), with one player and everything the service
-- tells the rest of the server kept for a spec to read: the commands it sends, the strikes it reports, the bodies it
-- asks the engine for, the collision groups it registers and the lines it logs. The world's clock is the service's
-- os.clock, and its Heartbeat the service's tick.
local Engine = require("./engine")

local ServerWorld = {}

export type Server = {
	world: any,
	service: any,
	player: any,
	-- The body standing now, its Humanoid and its root.
	character: any,
	humanoid: any,
	root: any,
	-- { remote name, player, payload } per command sent.
	sent: { { any } },
	-- { source, reason, kind } per strike.
	strikes: { { any } },
	-- One entry per LoadCharacter the service asked for.
	loads: { number },
	-- The collision groups registered, and { a, b, collidable } per pair set.
	groups: { string },
	pairs: { { any } },
	lines: { string },
	-- Gives the player a fresh body, as the engine does on a respawn, and returns it.
	spawn: (self: Server) -> any,
}

-- A Log whose lines are kept, so the world prints nothing and a spec can read what was said.
function ServerWorld.recordingLog(lines: { string }): any
	local function line(prefix: string, message: string, ...: any): string
		local ok, text = pcall(string.format, message, ...)
		return "[" .. prefix .. "] " .. (if ok then text else message)
	end
	return {
		new = function(prefix: string): any
			return {
				info = function(message: string, ...: any)
					table.insert(lines, line(prefix, message, ...))
				end,
				warn = function(message: string, ...: any)
					table.insert(lines, line(prefix, message, ...))
				end,
				error = function(message: string, ...: any)
					table.insert(lines, line(prefix, "ERROR " .. message, ...))
				end,
				try = function(context: string, fn: (...any) -> ...any, ...: any): boolean
					local ok, err = pcall(fn, ...)
					if not ok then
						table.insert(lines, line(prefix, "%s failed: %s", context, tostring(err)))
					end
					return ok
				end,
				succeeded = function(context: string, fn: (...any) -> ...any, ...: any): boolean
					local ok, result = pcall(fn, ...)
					if not ok then
						table.insert(lines, line(prefix, "%s failed: %s", context, tostring(result)))
					end
					return ok and result ~= nil and result ~= false
				end,
			}
		end,
	}
end

-- A character as the engine builds one: a root, a head, a hat with its handle, and a Humanoid.
local function body(parent: any): (any, any, any)
	local character = Engine.instance("Model")
	character.Name = "Player"
	local root = Engine.instance("Part", character)
	root.Name = "HumanoidRootPart"
	local head = Engine.instance("MeshPart", character)
	head.Name = "Head"
	local hat = Engine.instance("Accessory", character)
	local handle = Engine.instance("Part", hat)
	handle.Name = "Handle"
	local humanoid = Engine.instance("Humanoid", character)
	humanoid.Health = 100
	character.Parent = parent
	return character, humanoid, root
end

-- MovementService started with one player standing in a fresh character.
function ServerWorld.start(): Server
	local lines: { string } = {}
	local groups: { string } = {}
	local pairsSet: { { any } } = {}
	local physics = {
		IsCollisionGroupRegistered = function(_self: any, name: string): boolean
			return table.find(groups, name) ~= nil
		end,
		RegisterCollisionGroup = function(_self: any, name: string)
			table.insert(groups, name)
		end,
		CollisionGroupSetCollidable = function(_self: any, a: string, b: string, collidable: boolean)
			table.insert(pairsSet, { a, b, collidable })
		end,
	}
	local world = Engine.world({
		Stubs = { ["src/shared/Util/Log"] = ServerWorld.recordingLog(lines) },
		Services = { PhysicsService = physics },
	})
	local players = world.game:GetService("Players")
	players.GetPlayers = function(): { any }
		return { world.player }
	end
	local player = world.player
	player.UserId = 1
	local server: any = {
		world = world,
		player = player,
		sent = {},
		strikes = {},
		loads = {},
		groups = groups,
		pairs = pairsSet,
		lines = lines,
	}
	function server.spawn(self: any): any
		local previous = player.Character
		if previous ~= nil then
			player.CharacterRemoving:Fire(previous)
			previous:Destroy()
		end
		local character, humanoid, root = body(world.workspace)
		self.character, self.humanoid, self.root = character, humanoid, root
		player.Character = character
		player.CharacterAdded:Fire(character)
		return character
	end
	-- The engine builds the new body and fires CharacterAdded for it.
	player.LoadCharacter = function()
		table.insert(server.loads, world.now)
		server:spawn()
	end
	local service = world.require("src/server/Services/MovementService")
	service.Init({
		Registry = {
			fire = function(name: string, target: any, payload: any)
				table.insert(server.sent, { name, target, payload })
			end,
		},
		AntiCheat = {
			strike = function(_target: any, source: string, reason: string, kind: string?)
				table.insert(server.strikes, { source, reason, kind })
			end,
		},
	})
	service.Start()
	server.service = service
	server:spawn()
	return server :: Server
end

return ServerWorld
