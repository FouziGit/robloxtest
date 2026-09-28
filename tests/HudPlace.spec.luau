--!strict
-- Where the HUD thinks the player is, run (tests/engine.luau): the real HudController, TravelController and
-- BossController, wired as the client bootstrap wires them, with the server's remotes fired by hand.
--
-- A portal into the Battleground or the Erasure's arena puts the HUD in fight mode: no level, no Folios, no
-- shortcuts, rewards held (rule 11). Only a portal took it out again, and the server sends players home
-- without one: the Erasure's end, a match, a death in the Erasure's arena, a Battleground membership that
-- ends. After a normal World Boss event the hub stayed in fight mode until the player walked through
-- another portal.
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Fixture = {
	world: any,
	remote: (name: string, ...any) -> (),
	match: (snapshot: any) -> (),
	cluster: any,
}

local function setup(): Fixture
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		-- The portal band's fill is a tween (TravelController) and the boss is found by its tag
		-- (BossController): no circle is stood in and no boss is looked for here.
		Services = { TweenService = {}, CollectionService = {} },
	})
	local handlers: { [string]: (...any) -> () } = {}
	local signal = Engine.signal
	local remoteClient = {
		on = function(name: string, handler: (...any) -> ()): any
			handlers[name] = handler
			return signal():Connect(handler)
		end,
		fire = function() end,
	}
	local localize = {
		t = function(key: string): string
			return key
		end,
		resolveParams = function(params: any): any
			return params
		end,
	}
	local sound = { play = function() end, wantMusic = function() end }
	local matchChanged = signal()
	local current: any = nil
	local Hud = world.require("src/client/Controllers/HudController")
	Hud.Init({
		Localize = localize,
		ClientData = {
			get = function(): any
				return nil
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
		MatchController = {
			MatchChanged = matchChanged,
			QueueChanged = signal(),
			getMatch = function(): any
				return current
			end,
			getQueue = function(): any
				return { Queued = false, WaitedSeconds = 0 }
			end,
			leaveQueue = function() end,
		},
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
	})
	local Travel = world.require("src/client/Controllers/TravelController")
	Travel.Init({ RemoteClient = remoteClient, Localize = localize, HudController = Hud, SoundController = sound })
	local Boss = world.require("src/client/Controllers/BossController")
	Boss.Init({
		Localize = localize,
		HudController = Hud,
		RemoteClient = remoteClient,
		WorldLighting = { pulse = function() end },
		SoundController = sound,
	})
	Hud.Start()
	Travel.Start()
	Boss.Start()
	return {
		world = world,
		remote = function(name: string, ...: any)
			local handler = handlers[name]
			assert(handler ~= nil, "nothing listens to " .. name)
			handler(...)
		end,
		match = function(snapshot: any)
			current = snapshot
			matchChanged:Fire(snapshot)
		end,
		cluster = world.playerGui:FindFirstChild("MetaCluster", true),
	}
end

local function inHub(fixture: Fixture): boolean
	return fixture.cluster.Visible
end

local SNAPSHOT = {
	MatchId = "m",
	ModeId = "Duel",
	Phase = "Playing",
	SecondsLeft = 60,
	Round = 1,
	RoundsToWin = 2,
	Scores = { 0, 0 },
	Teams = { {}, {} },
	LocalTeam = 1,
}

describe("where the HUD thinks the player is, run", function()
	it("fights in an arena a portal took them to, and is home through the way back", function()
		local fixture = setup()
		expect(inHub(fixture)).toBe(true)
		fixture.remote("Travelled", "WorldBoss")
		expect(inHub(fixture)).toBe(false)
		fixture.remote("Travelled", "Return")
		expect(inHub(fixture)).toBe(true)
	end)

	it("is home when the Erasure's fight ends and sends everyone in it back", function()
		local fixture = setup()
		fixture.remote("Travelled", "WorldBoss")
		fixture.remote("BossChanged", nil)
		expect(inHub(fixture)).toBe(true)
	end)

	it("is home when a body that died in the Erasure's arena comes back at the hub", function()
		local fixture = setup()
		fixture.remote("Travelled", "WorldBoss")
		fixture.world.player.CharacterAdded:Fire(Engine.instance("Model"))
		expect(inHub(fixture)).toBe(true)
	end)

	it("stays in the Battleground through a respawn the camp takes back, and leaves with its membership", function()
		local fixture = setup()
		fixture.remote("Travelled", "Battleground")
		fixture.world.player.CharacterAdded:Fire(Engine.instance("Model"))
		expect(inHub(fixture)).toBe(false)
		-- The Erasure ending elsewhere is not this player's way out.
		fixture.remote("BossChanged", nil)
		expect(inHub(fixture)).toBe(false)
		fixture.remote("BattlegroundChanged", nil)
		expect(inHub(fixture)).toBe(true)
	end)

	it("is home after a match that took them from an arena", function()
		local fixture = setup()
		fixture.remote("Travelled", "Battleground")
		fixture.match(SNAPSHOT)
		expect(inHub(fixture)).toBe(false)
		fixture.match(nil)
		expect(inHub(fixture)).toBe(true)
	end)
end)

-- The medallion of the toast `kind` showing now, as the toast lane draws it.
local function medallionOf(fixture: Fixture, kind: string): any
	local toasts = fixture.world.playerGui:FindFirstChild("Toasts")
	assert(toasts ~= nil, "the HUD has no toast lane")
	for _, slot in ipairs(toasts:GetDescendants()) do
		if slot.Name == kind and slot:FindFirstChild("Disc", true) ~= nil then
			return slot:FindFirstChild("Disc", true)
		end
	end
	error("no " .. kind .. " toast is showing")
end

describe("a success in a fight, run", function()
	-- The value colours no fight shows (docs/ART_BIBLE.md rule 11).
	local function valueColours(fixture: Fixture): { any }
		local Theme = fixture.world.require("src/ui/Theme")
		local colours = Theme.Colors
		return { colours.Primary, colours.Epic, colours.Premium, colours.SuccessFill, colours.Success }
	end

	it("draws a takedown's tick in ink, not the green, in an arena", function()
		local fixture = setup()
		fixture.remote("Travelled", "Battleground")
		fixture.remote("Notify", { Key = "hud.playerKill", Kind = "Success", Params = { name = "Ada" } })
		fixture.world:advance(0.5)
		local fill = medallionOf(fixture, "Success").BackgroundColor3
		for _, colour in ipairs(valueColours(fixture)) do
			expect(fill == colour).toBe(false)
		end
	end)

	it("and in a match", function()
		local fixture = setup()
		fixture.match(SNAPSHOT)
		fixture.remote("Notify", { Key = "hud.playerKill", Kind = "Success", Params = { name = "Ada" } })
		fixture.world:advance(0.5)
		local fill = medallionOf(fixture, "Success").BackgroundColor3
		for _, colour in ipairs(valueColours(fixture)) do
			expect(fill == colour).toBe(false)
		end
	end)

	it("keeps the green for a success in the hub", function()
		local fixture = setup()
		fixture.remote("Notify", { Key = "cosmetics.equipped", Kind = "Success", Params = { name = "x" } })
		fixture.world:advance(0.5)
		local Theme = fixture.world.require("src/ui/Theme")
		expect(medallionOf(fixture, "Success").BackgroundColor3).toBe(Theme.Colors.SuccessFill)
	end)
end)

return nil
