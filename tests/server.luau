--!strict
-- A pretend server for the services' own lifecycle, on top of tests/engine.luau: players who join and leave,
-- a DataModel that can close, and a ProfileStore whose sessions end the ways the vendored one ends them. The
-- services themselves are the real modules of src/server, given this world instead of Roblox.
--
-- Most server gates read the services' source, because Lune has no engine. That cannot see an order of
-- events: a session another server takes before this one sees the player go, a shutdown that removes the
-- players a moment before it says so. Those are what this runs.
local Engine = require("./engine")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local Server = {}

-- The one DataModel of a pretend server, its players, and what the services said and did to them.
export type World = {
	engine: Engine.World,
	players: any,
	-- Every line the services logged, "[Service] message" as the Log module renders it; warnings prefixed "WARN ".
	lines: { string },
	-- Every kick, as the player and the message they read.
	kicks: { { Player: any, Message: string } },
	-- What game:BindToClose was handed, run by close().
	closers: { () -> () },
	store: Store,
	require: (path: string) -> any,
	join: (self: World, userId: number, name: string) -> any,
	leave: (self: World, player: any) -> (),
	close: (self: World) -> (),
	advance: (self: World, seconds: number) -> (),
	said: (self: World, needle: string) -> boolean,
}

-- One session of the pretend ProfileStore.
export type Profile = {
	Key: string,
	Data: { [string]: any },
	SessionLoadCount: number,
	OnLastSave: Engine.Signal,
	OnSessionEnd: Engine.Signal,
	OnAfterSave: Engine.Signal,
	Active: boolean,
	IsActive: (self: Profile) -> boolean,
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	Save: (self: Profile) -> (),
}

-- The pretend ProfileStore: the module DataService requires, and the levers a spec pulls on it.
export type Store = {
	module: { [string]: any },
	-- The data each key last wrote to the DataStore, by key.
	written: { [string]: { [string]: any } },
	sessions: { [string]: Profile },
	-- Another server takes the profile the way ProfileStore hands it over: a final write for "External".
	external: (self: Store, key: string) -> (),
	-- Another server stole it: this one learns it on an autosave, and writes nothing.
	steal: (self: Store, key: string) -> (),
	-- ProfileStore's own game:BindToClose, with DataStore access: a final write for "Shutdown" per session.
	shutdown: (self: Store) -> (),
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- A session's final write, in the order the vendored SaveProfileAsync runs it (ProfileStore.luau,
-- `local function SaveProfileAsync`): OnLastSave with its reason, the session leaves this server
-- (RemoveProfileFromAutoSave, so IsActive turns false), OnSessionEnd, and only then the UpdateAsync that
-- writes Profile.Data. What the listeners of both signals left in the data is what reaches the DataStore.
local function finalWrite(store: Store, profile: Profile, reason: string)
	profile.OnLastSave:Fire(reason)
	profile.Active = false
	profile.OnSessionEnd:Fire()
	store.written[profile.Key] = deepCopy(profile.Data)
end

function Server.profileStore(): Store
	local store: any = { written = {}, sessions = {} }
	local module: { [string]: any } = { IsClosing = false, DataStoreState = "Access" }
	store.module = module

	function module.New(_name: string, template: { [string]: any }): any
		return {
			StartSessionAsync = function(_self: any, key: string, _params: any): Profile
				local existing = store.sessions[key]
				if existing ~= nil and existing.Active then
					-- The vendored StartSessionAsync errors on a key this server still holds.
					error(("Profile (KEY:%s) is already loaded in this session"):format(key))
				end
				local profile: any = {
					Key = key,
					Data = deepCopy(store.written[key] or template),
					SessionLoadCount = 1,
					OnLastSave = Engine.signal(),
					OnSessionEnd = Engine.signal(),
					OnAfterSave = Engine.signal(),
					Active = true,
				}
				function profile.IsActive(self: Profile): boolean
					return self.Active
				end
				function profile.EndSession(self: Profile)
					if self.Active then
						finalWrite(store, self, "Manual")
					end
				end
				function profile.AddUserId(_self: Profile, _userId: number) end
				function profile.Reconcile(_self: Profile) end
				function profile.Save(_self: Profile) end
				store.sessions[key] = profile
				return profile
			end,
		}
	end

	function store.external(self: Store, key: string)
		local profile = self.sessions[key]
		assert(profile ~= nil and profile.Active, "no live session for " .. key)
		finalWrite(self, profile, "External")
	end

	function store.steal(self: Store, key: string)
		local profile = self.sessions[key]
		assert(profile ~= nil and profile.Active, "no live session for " .. key)
		profile.Active = false
		profile.OnSessionEnd:Fire()
	end

	function store.shutdown(self: Store)
		module.IsClosing = true
		for _, profile in pairs(self.sessions) do
			if profile.Active then
				finalWrite(self, profile, "Shutdown")
			end
		end
	end

	return store :: Store
end

-- The real Log module, printing into `lines` instead of the output.
local function capturingLog(lines: { string }): any
	local chunk = luau.load(fs.readFile("src/shared/Util/Log.luau"), {
		debugName = "src/shared/Util/Log",
		environment = {
			print = function(line: string)
				table.insert(lines, line)
			end,
			warn = function(line: string)
				table.insert(lines, "WARN " .. line)
			end,
		},
	})
	return chunk()
end

-- A character the way LoadCharacterAsync leaves one: a Humanoid at full health and a root that follows PivotTo.
local function character(name: string): any
	local model = Engine.instance("Model")
	model.Name = name
	local humanoid = Engine.instance("Humanoid", model)
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	local root = Engine.instance("BasePart", model)
	root.Name = "HumanoidRootPart"
	root.Position = roblox.Vector3.new(0, 0, 0)
	model.PivotTo = function(_self: any, frame: any)
		root.Position = frame.Position
	end
	return model
end

export type Options = {
	-- Modules replaced by a table, by their path without extension.
	Stubs: { [string]: any }?,
}

function Server.world(options: Options?): World
	local lines: { string } = {}
	local kicks: { { Player: any, Message: string } } = {}
	local closers: { () -> () } = {}
	local store = Server.profileStore()

	local players = Engine.instance("Players")
	players.Name = "Players"
	local function list(): { any }
		local found = {}
		for _, child in ipairs(players:GetChildren()) do
			if child.ClassName == "Player" then
				table.insert(found, child)
			end
		end
		return found
	end
	players.GetPlayers = function(_self: any): { any }
		return list()
	end
	players.GetPlayerByUserId = function(_self: any, userId: number): any
		for _, player in ipairs(list()) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end
	players.GetPlayerFromCharacter = function(_self: any, model: any): any
		for _, player in ipairs(list()) do
			if player.Character == model then
				return player
			end
		end
		return nil
	end

	local stubs: { [string]: any } = {
		["src/shared/Util/Log"] = capturingLog(lines),
		["src/server/Vendor/ProfileStore"] = store.module,
	}
	if options ~= nil and options.Stubs ~= nil then
		for path, stub in pairs(options.Stubs) do
			stubs[path] = stub
		end
	end
	local engine = Engine.world({
		Stubs = stubs,
		Services = {
			Players = players,
			-- DataService reads the V1 store of a brand new profile: there is none here.
			DataStoreService = {
				GetDataStore = function(_self: any, _name: string): any
					return {
						GetAsync = function(_store: any, _key: string): any
							return nil
						end,
					}
				end,
			},
		},
	})
	engine.game.BindToClose = function(_self: any, fn: () -> ())
		table.insert(closers, fn)
	end

	local world: any = {
		engine = engine,
		players = players,
		lines = lines,
		kicks = kicks,
		closers = closers,
		store = store,
		require = engine.require,
	}

	function world.join(_self: World, userId: number, name: string): any
		local player = Engine.instance("Player")
		player.Name = name
		player.DisplayName = name
		player.UserId = userId
		player.LocaleId = "fr-fr"
		player.Kick = function(self: any, message: string)
			table.insert(kicks, { Player = self, Message = message })
		end
		player.LoadCharacterAsync = function(self: any)
			self.Character = character(name)
		end
		player.Parent = players
		players.PlayerAdded:Fire(player)
		return player
	end

	-- Roblox fires PlayerRemoving while the player is still parented, then takes them out.
	function world.leave(_self: World, player: any)
		players.PlayerRemoving:Fire(player)
		player.Parent = nil
	end

	-- The DataModel starts closing: every function bound with game:BindToClose runs.
	function world.close(_self: World)
		for _, fn in ipairs(closers) do
			fn()
		end
	end

	function world.advance(_self: World, seconds: number)
		engine:advance(seconds, 1 / 20)
	end

	function world.said(_self: World, needle: string): boolean
		for _, line in ipairs(lines) do
			if string.find(line, needle, 1, true) ~= nil then
				return true
			end
		end
		return false
	end

	return world :: World
end

return Server
