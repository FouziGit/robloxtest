--!strict
-- The HUD run whole (tests/engine.luau): the real HudController, TravelController and BossController, wired as
-- the client bootstrap wires them, with the controllers they only talk to replaced by what they are asked,
-- and the server's remotes fired by hand. On a desktop, or on a landscape phone when asked.
local Engine = require("./engine")

local Hud = {}

export type Options = {
	-- The profile the HUD reads (ClientData.get); nil before one has come.
	Profile: any?,
	-- A landscape phone, `{ width, height }` points, rather than a desktop.
	Phone: { number }?,
	-- How the player plays there (Engine.plays), when it is not the phone's touch or the desktop's pointer.
	Plays: Engine.Plays?,
	-- Seconds before the client hears the servers' clock: until then GetServerTimeNow() is 0, as the engine
	-- answers a client that has just started.
	ClockHeardAfter: number?,
	-- What the controllers read their words through (Localize): by default each key as itself, in a language
	-- that never changes.
	Localize: any?,
}

export type Fixture = {
	world: any,
	-- The server firing `name` to this client.
	remote: (name: string, ...any) -> (),
	-- The match the player is in, or nil.
	match: (snapshot: any) -> (),
	-- The server's queue snapshot for this player, as QueueChanged brings it.
	queue: (snapshot: any) -> (),
	-- The HUD's own ScreenGui.
	screen: any,
	-- The hub's meta cluster.
	cluster: any,
	-- The real TravelController, run beside the HUD: whether the local player fights, for the auras.
	travel: any,
}

-- A match of `mode` in its Playing phase, `perTeam` a side, full health.
function Hud.match(mode: string, perTeam: number): any
	local teams = {}
	for side = 1, 2 do
		local team = {}
		for index = 1, perTeam do
			-- Every field a real snapshot carries (Types.MatchPlayerSnapshot): the announcement's versus plate reads
			-- the level and the rank of each opponent (E10-S7).
			table.insert(team, {
				UserId = side * 100 + index,
				Name = "P" .. side .. index,
				Team = side,
				Health = 100,
				MaxHealth = 100,
				Alive = true,
				Level = 12,
				RankKey = "rank.blank",
			})
		end
		table.insert(teams, team)
	end
	return {
		MatchId = "m",
		ModeId = mode,
		Phase = "Playing",
		SecondsLeft = 60,
		Round = 1,
		RoundsToWin = 2,
		Scores = { 0, 0 },
		Teams = teams,
		LocalTeam = 1,
		Ranked = true,
	}
end

function Hud.build(options: Options?): Fixture
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		-- The portal band's fill is a tween (TravelController) and the boss is found by its tag
		-- (BossController): no circle is stood in and no boss is looked for here.
		Services = { TweenService = {}, CollectionService = {} },
	})
	local heardAfter = if options ~= nil then options.ClockHeardAfter else nil
	if heardAfter ~= nil then
		local heard = world.workspace.GetServerTimeNow
		world.workspace.GetServerTimeNow = function(): number
			return if world.now < heardAfter then 0 else heard()
		end
	end
	local phone = if options ~= nil then options.Phone else nil
	if phone ~= nil then
		Engine.phone(world, phone[1], phone[2])
	end
	local plays = if options ~= nil then options.Plays else nil
	if plays ~= nil then
		Engine.plays(world, plays)
	end
	local profile = if options ~= nil then options.Profile else nil
	-- Every listener of a remote, in the order it connected: the real RemoteClient connects each one to the
	-- remote's OnClientEvent, and BossChanged is heard by TravelController and BossController both.
	local handlers: { [string]: { (...any) -> () } } = {}
	local signal = Engine.signal
	local remoteClient = {
		on = function(name: string, handler: (...any) -> ()): any
			local listeners = handlers[name]
			if listeners == nil then
				listeners = {}
				handlers[name] = listeners
			end
			table.insert(listeners, handler)
			return signal():Connect(handler)
		end,
		fire = function() end,
	}
	local localize = if options ~= nil and options.Localize ~= nil
		then options.Localize
		else {
			t = function(key: string): string
				return key
			end,
			resolveParams = function(params: any): any
				return params
			end,
			Changed = signal(),
		}
	local sound = { play = function() end, wantMusic = function() end }
	local matchChanged = signal()
	local queueChanged = signal()
	local current: any = nil
	local waiting: any = { Queued = false, WaitedSeconds = 0 }
	local matchController = {
		MatchChanged = matchChanged,
		QueueChanged = queueChanged,
		getMatch = function(): any
			return current
		end,
		getQueue = function(): any
			return waiting
		end,
		leaveQueue = function() end,
	}
	local HudController = world.require("src/client/Controllers/HudController")
	-- Required before any Init, as the bootstrap's first pass does: the HUD hears whether the player fights from it.
	local Travel = world.require("src/client/Controllers/TravelController")
	HudController.Init({
		Localize = localize,
		ClientData = {
			get = function(): any
				return profile
			end,
			Changed = signal(),
		},
		RemoteClient = remoteClient,
		SoundController = sound,
		ComboController = { SequenceChanged = signal(), PreviewChanged = signal(), SequenceBroken = signal() },
		CombatController = {
			StateChanged = signal(),
			getState = function(): any
				return { Health = 100, MaxHealth = 100, Ink = 100, MaxInk = 100, Cooldowns = {}, InCombat = false }
			end,
		},
		MatchController = matchController,
		MenuController = {
			open = function() end,
			toggle = function() end,
			isOpen = function(): boolean
				return false
			end,
		},
		VfxController = { LocalCast = signal() },
		InputController = {
			TouchLayoutChanged = signal(),
			touchRects = function(): any
				return {}
			end,
			setAffordable = function() end,
			setHints = function() end,
		},
		QualityController = {
			Changed = signal(),
			get = function(): string
				return "High"
			end,
		},
		TravelController = Travel,
		-- The same reader Theme was handed as it loaded (tests/engine.luau), as the bootstrap hands it both.
		InputMode = world.require("src/client/Controllers/InputMode"),
	})
	Travel.Init({
		RemoteClient = remoteClient,
		Localize = localize,
		HudController = HudController,
		SoundController = sound,
		MatchController = matchController,
	})
	local Boss = world.require("src/client/Controllers/BossController")
	Boss.Init({
		Localize = localize,
		HudController = HudController,
		RemoteClient = remoteClient,
		WorldLighting = { pulse = function() end },
		SoundController = sound,
	})
	HudController.Start()
	Travel.Start()
	Boss.Start()
	return {
		world = world,
		remote = function(name: string, ...: any)
			local listeners = handlers[name]
			assert(listeners ~= nil, "nothing listens to " .. name)
			for _, handler in ipairs(listeners) do
				handler(...)
			end
		end,
		match = function(snapshot: any)
			current = snapshot
			matchChanged:Fire(snapshot)
		end,
		queue = function(snapshot: any)
			waiting = snapshot
			queueChanged:Fire(snapshot)
		end,
		screen = world.playerGui:FindFirstChild("Hud"),
		cluster = world.playerGui:FindFirstChild("MetaCluster", true),
		travel = Travel,
	}
end

return Hud
