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
local Hud = require("./hud")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Fixture = Hud.Fixture

local function setup(): Fixture
	return Hud.build()
end

local function inHub(fixture: Fixture): boolean
	return fixture.cluster.Visible
end

local SNAPSHOT = Hud.match("Duel", 1)

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

-- The same ways in and out, for the auras (D-148): TravelController says whether the local player stands where
-- others fight, and CosmeticController quiets every aura on their screen while it holds. BossChanged reaches
-- TravelController and BossController both, as the engine delivers a remote to every listener; a fixture that
-- kept one handler per remote let BossController's hide TravelController's, and the Erasure's end never ended
-- the auras' fight here.
local function erasure(phase: string, practice: boolean): any
	return {
		Phase = phase,
		SecondsLeft = 60,
		Health = 1000,
		MaxHealth = 1000,
		PhaseIndex = 1,
		Participants = 1,
		MyShare = 0,
		Practice = practice,
	}
end

describe("whether the player fights, for the auras, run", function()
	it("fights in the Erasure's arena from its gate until its fight ends", function()
		local fixture = setup()
		expect(fixture.travel.inFight()).toBe(false)
		fixture.remote("Travelled", "WorldBoss")
		expect(fixture.travel.inFight()).toBe(true)
		fixture.remote("BossChanged", nil)
		expect(fixture.travel.inFight()).toBe(false)
		expect(inHub(fixture)).toBe(true)
	end)

	it("stops fighting when a body that died in the Erasure's arena comes back at the hub", function()
		local fixture = setup()
		fixture.remote("Travelled", "WorldBoss")
		fixture.world.player.CharacterAdded:Fire(Engine.instance("Model"))
		expect(fixture.travel.inFight()).toBe(false)
	end)

	it("fights as a member of the Battleground through a respawn and the Erasure's end, until it lets go", function()
		local fixture = setup()
		fixture.remote("Travelled", "Battleground")
		fixture.remote("BattlegroundChanged", { Standing = 3, Defeated = 0 })
		expect(fixture.travel.inFight()).toBe(true)
		fixture.world.player.CharacterAdded:Fire(Engine.instance("Model"))
		fixture.remote("BossChanged", nil)
		expect(fixture.travel.inFight()).toBe(true)
		fixture.remote("BattlegroundChanged", nil)
		expect(fixture.travel.inFight()).toBe(false)
		expect(inHub(fixture)).toBe(true)
	end)

	it("is pulled into the scheduled Erasure as it starts fighting, never into a practice", function()
		local fixture = setup()
		fixture.remote("BossChanged", erasure("Announced", false))
		expect(fixture.travel.inFight()).toBe(false)
		fixture.remote("BossChanged", erasure("Fighting", false))
		expect(fixture.travel.inFight()).toBe(true)
		fixture.remote("BossChanged", nil)
		expect(fixture.travel.inFight()).toBe(false)
		fixture.remote("BossChanged", erasure("Announced", true))
		fixture.remote("BossChanged", erasure("Fighting", true))
		expect(fixture.travel.inFight()).toBe(false)
	end)

	it("is not pulled out of a match", function()
		local fixture = setup()
		fixture.match(SNAPSHOT)
		fixture.remote("BossChanged", erasure("Announced", false))
		fixture.remote("BossChanged", erasure("Fighting", false))
		expect(fixture.travel.inFight()).toBe(false)
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
