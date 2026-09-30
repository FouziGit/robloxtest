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
			-- CosmeticService asks whether a kill was a proof or a Forger: nothing here is tagged. A world builder tags
			-- what it builds (a barrier, a gate's seal); nothing here reads those tags back.
			CollectionService = {
				HasTag = function(_self: any, _instance: any, _tag: string): boolean
					return false
				end,
				AddTag = function(_self: any, _instance: any, _tag: string) end,
			},
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

-- The services of a profile, a ranked match and the shop, wired as Bootstrap.server.luau wires them:
-- DataService, RankingService, MatchService, GlyphService, LoadoutService, CosmeticService, CurrencyService and
-- ShopService are the real modules; everything they reach beyond is a stub that answers what they ask.
-- Movement keeps a freeze the way MovementService does, so a frozen player cannot cast.
export type Services = {
	world: World,
	data: any,
	ranking: any,
	match: any,
	glyph: any,
	loadout: any,
	cosmetic: any,
	currency: any,
	shop: any,
	-- The handler each client remote was given, by remote name.
	handlers: { [string]: (...any) -> () },
	-- Where the players stand beyond the hub and the match, as WorldBossService and BattlegroundService would
	-- answer it: the scheduled event running, a player engaged against the Erasure, a player on the page.
	places: { BossLive: boolean, Engaged: { [any]: boolean }, Inside: { [any]: boolean } },
	-- Every Notify sent, as the player and the Strings key.
	notices: { { Player: any, Key: string } },
	-- Runs the CastGlyph remote's handler with the recipe of `glyphId`; true when the server accepted the cast.
	cast: (player: any, glyphId: string) -> boolean,
}

local DUEL_ARENA = "Duel"

local function pad(x: number): any
	local part = Engine.instance("BasePart")
	part.Position = roblox.Vector3.new(x, 500, 0)
	return part
end

function Server.services(): Services
	local world = Server.world()
	local GlyphConfig = world.require("src/shared/Config/GlyphConfig")
	local data = world.require("src/server/Services/DataService")
	local ranking = world.require("src/server/Services/RankingService")
	local match = world.require("src/server/Services/MatchService")
	local glyph = world.require("src/server/Services/GlyphService")
	local loadout = world.require("src/server/Services/LoadoutService")
	local cosmetic = world.require("src/server/Services/CosmeticService")
	local currency = world.require("src/server/Services/CurrencyService")
	local shop = world.require("src/server/Services/ShopService")

	local handlers: { [string]: (...any) -> () } = {}
	local registry = {
		fire = function(_name: string, _player: any, _payload: any) end,
		on = function(name: string, handler: (...any) -> ())
			handlers[name] = handler
		end,
	}
	local notices: { { Player: any, Key: string } } = {}
	local notify = {
		send = function(player: any, key: string, _params: any, _kind: any, _sfx: any)
			table.insert(notices, { Player = player, Key = key })
		end,
	}
	local places = { BossLive = false, Engaged = {}, Inside = {} }
	local frozenUntil: { [any]: number } = {}
	local movement = {
		applyStun = function(_player: any, _seconds: number) end,
		applyFreeze = function(player: any, seconds: number)
			frozenUntil[player] = math.max(frozenUntil[player] or 0, world.engine.now + seconds)
		end,
		clearStun = function(player: any)
			frozenUntil[player] = nil
		end,
		isStunned = function(player: any): boolean
			return (frozenUntil[player] or 0) > world.engine.now
		end,
		applySlow = function(_player: any, _key: string, _factor: number, _seconds: number) end,
		command = function(_player: any, _payload: any) end,
	}
	local combat = {
		Damaged = Engine.signal(),
		Killed = Engine.signal(),
		claimZone = function(_zone: string, _claim: any) end,
		resyncPosition = function(_player: any, _position: any) end,
		trustedOrigin = function(player: any): any
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			return if root ~= nil then roblox.CFrame.new(root.Position) else nil
		end,
		trySpendInk = function(_player: any, _cost: number): boolean
			return true
		end,
		addInk = function(_player: any, _amount: number) end,
		isBlocking = function(_player: any): boolean
			return false
		end,
		isStunned = movement.isStunned,
		isChanneling = function(_player: any): boolean
			return false
		end,
		zoneOf = function(_player: any): string
			return "Hub"
		end,
	}
	local killZone = Engine.instance("BasePart")
	killZone.Position = roblox.Vector3.new(0, 460, 0)
	killZone.Touched = Engine.signal()
	local progression = {
		LevelUp = Engine.signal(),
		addXp = function(_player: any, _amount: number, _reason: string) end,
	}
	local quest = { report = function(_player: any, _event: string, _amount: number) end }
	local vfx = { emit = function(_packet: any, _reliable: boolean?, _alsoNear: any) end }

	data.Init({ Registry = registry })
	currency.Init({ DataService = data })
	cosmetic.Init({ Registry = registry, Vfx = vfx, Combat = combat, DataService = data, Notify = notify })
	loadout.Init({
		Registry = registry,
		DataService = data,
		Notify = notify,
		Progression = progression,
		Cosmetic = cosmetic,
	})
	shop.Init({
		Registry = registry,
		DataService = data,
		Notify = notify,
		Currency = currency,
		Cosmetic = cosmetic,
		Analytics = {
			economy = function(
				_player: any,
				_flow: string,
				_currency: string,
				_amount: number,
				_balance: number,
				_category: string,
				_sku: string?
			)
			end,
		},
	})
	ranking.Init({
		DataService = data,
		Currency = currency,
		Cosmetic = cosmetic,
		Notify = notify,
	})
	match.Init({
		Registry = registry,
		DataService = data,
		Notify = notify,
		Combat = combat,
		Movement = movement,
		Progression = progression,
		Currency = currency,
		Hub = { teleportToHub = function(_player: any) end },
		Arena = {
			acquire = function(_arenaId: string): any
				return {
					Instance = Engine.instance("Model"),
					Id = DUEL_ARENA,
					SlotIndex = 1,
					Spawns = { { pad(-30) }, { pad(30) } },
					KillZone = killZone,
				}
			end,
			release = function(_arena: any) end,
		},
		Ranking = ranking,
		Quest = quest,
		Daily = {
			markFirstWin = function(_player: any): boolean
				return false
			end,
		},
		Glyph = glyph,
	})
	glyph.Init({
		Registry = registry,
		DataService = data,
		Notify = notify,
		Combat = combat,
		-- Every effect resolves at once and hits nothing: what is judged here is whether the cast is accepted.
		Effects = setmetatable({}, {
			__index = function(): any
				return function(_ctx: any): number
					return 0
				end
			end,
		}),
		Vfx = vfx,
		Movement = movement,
		Progression = progression,
		Quest = quest,
		Match = match,
		WorldBoss = {
			isLive = function(): boolean
				return places.BossLive
			end,
			isEngaged = function(player: any): boolean
				return places.Engaged[player] == true
			end,
		},
		Battleground = {
			isInside = function(player: any): boolean
				return places.Inside[player] == true
			end,
		},
		Loadout = loadout,
		Cosmetic = cosmetic,
	})
	-- In the bootstrap's order.
	data.Start()
	currency.Start()
	cosmetic.Start()
	loadout.Start()
	shop.Start()
	glyph.Start()
	ranking.Start()
	match.Start()

	local casts: { string } = {}
	glyph.Cast:Connect(function(_player: any, glyphId: string, _chain: number)
		table.insert(casts, glyphId)
	end)
	local function cast(player: any, glyphId: string): boolean
		local before = #casts
		handlers.CastGlyph(player, table.clone(GlyphConfig.ById[glyphId].Combo))
		return #casts > before
	end

	return {
		world = world,
		data = data,
		ranking = ranking,
		match = match,
		glyph = glyph,
		loadout = loadout,
		cosmetic = cosmetic,
		currency = currency,
		shop = shop,
		handlers = handlers,
		places = places,
		notices = notices,
		cast = cast,
	}
end

return Server
