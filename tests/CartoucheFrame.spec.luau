--!strict
-- The Cartouche keeps its promise (E19-S4, D-140, D-XXXframe): while its caster stands inside their own frame, their
-- other glyphs recharge Hasten times as fast, for as long as its ticks last and no longer. The real GlyphService runs
-- in a pretend server (tests/server.luau): what is read is the cooldown it reports, the one the HUD draws.
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local Server = require("./server")
local Strings = require("../src/shared/Strings")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CARTOUCHE = GlyphConfig.ById.Cartouche
local PARAMS = CARTOUCHE.Params
local LIFE = PARAMS.Ticks * PARAMS.TickInterval
-- A long cooldown among the first roster: long enough that the frame's whole saving still leaves some of it.
local SLOW = GlyphConfig.ById.Rupture
-- One step of the service's Heartbeat, the most a reading can be off by.
local STEP = 0.06

type Caster = { setup: Server.Services, player: any, root: any }

-- A player in the hub, standing at the origin, with the Cartouche, the Rupture and the Brand equipped.
local function caster(): Caster
	local setup = Server.services()
	local player = setup.world:join(501, "Ada")
	player:LoadCharacterAsync()
	local data = setup.data.get(player)
	for _, id in ipairs({ "Cartouche", SLOW.Id }) do
		if table.find(data.Unlocks.Glyphs, id) == nil then
			table.insert(data.Unlocks.Glyphs, id)
		end
	end
	data.Loadout.Slots = { "Brand", SLOW.Id, "Cartouche" }
	return { setup = setup, player = player, root = player.Character:FindFirstChild("HumanoidRootPart") }
end

local function cast(state: Caster, glyphId: string)
	expect(state.setup.cast(state.player, glyphId)).toBe(true)
end

local function left(state: Caster, glyphId: string): number
	return state.setup.glyph.getCooldowns(state.player)[glyphId] or 0
end

local function near(value: number, expected: number, tolerance: number?)
	expect(math.abs(value - expected) <= (tolerance or STEP)).toBe(true)
end

describe("the Cartouche's frame (D-140)", function()
	it("recharges the caster's other glyphs twice as fast while they stand inside it", function()
		local state = caster()
		cast(state, SLOW.Id)
		cast(state, "Cartouche")
		state.setup.world:advance(1)
		near(left(state, SLOW.Id), SLOW.Cooldown - 1 - (PARAMS.Hasten - 1))
		-- Its own cooldown runs at its own pace: the frame does not recharge the ultimate that laid it.
		near(left(state, "Cartouche"), CARTOUCHE.Cooldown - 1)
	end)

	it("hastens a glyph cast inside the frame from its cast on", function()
		local state = caster()
		cast(state, "Cartouche")
		state.setup.world:advance(1)
		cast(state, "Brand")
		state.setup.world:advance(1)
		near(left(state, "Brand"), GlyphConfig.ById.Brand.Cooldown - PARAMS.Hasten)
	end)

	it("hastens nothing while the caster stands outside it, and again once back inside", function()
		local state = caster()
		cast(state, SLOW.Id)
		cast(state, "Cartouche")
		state.root.Position = roblox.Vector3.new(PARAMS.Radius + 2, 0, 0)
		state.setup.world:advance(1)
		near(left(state, SLOW.Id), SLOW.Cooldown - 1)
		state.root.Position = roblox.Vector3.new(PARAMS.Radius - 2, 0, 0)
		state.setup.world:advance(1)
		near(left(state, SLOW.Id), SLOW.Cooldown - 2 - (PARAMS.Hasten - 1))
	end)

	it("ends with its ticks: no frame saves more than (Hasten - 1) x Ticks x TickInterval", function()
		-- Stepped on frames that never land on the frame's end, as a live server's do: the last one counts only
		-- what was left of it.
		local state = caster()
		cast(state, SLOW.Id)
		cast(state, "Cartouche")
		local castAt = state.setup.world.engine.now
		state.setup.world.engine:advance(LIFE + 5, 0.11)
		local elapsed = state.setup.world.engine.now - castAt
		near(left(state, SLOW.Id), SLOW.Cooldown - elapsed - (PARAMS.Hasten - 1) * LIFE, 0.001)
	end)

	it("stops for good when its caster is stunned, even once the stun is over", function()
		local state = caster()
		cast(state, SLOW.Id)
		cast(state, "Cartouche")
		state.setup.world:advance(1)
		state.setup.movement.applyFreeze(state.player, 0.3)
		state.setup.world:advance(2)
		near(left(state, SLOW.Id), SLOW.Cooldown - 3 - (PARAMS.Hasten - 1))
	end)

	it("stops for good when its caster raises their guard", function()
		local state = caster()
		cast(state, SLOW.Id)
		cast(state, "Cartouche")
		state.setup.world:advance(1)
		state.setup.guarding[state.player] = true
		state.setup.world:advance(0.5)
		state.setup.guarding[state.player] = nil
		state.setup.world:advance(1.5)
		near(left(state, SLOW.Id), SLOW.Cooldown - 3 - (PARAMS.Hasten - 1))
	end)

	it("stops for good when its caster dies", function()
		local state = caster()
		cast(state, SLOW.Id)
		cast(state, "Cartouche")
		state.setup.world:advance(1)
		local humanoid = state.player.Character:FindFirstChildOfClass("Humanoid")
		humanoid.Health = 0
		state.setup.world:advance(0.5)
		humanoid.Health = 100
		state.setup.world:advance(1.5)
		near(left(state, SLOW.Id), SLOW.Cooldown - 3 - (PARAMS.Hasten - 1))
	end)

	it("is forgotten with the cooldowns when a round starts over (D-207)", function()
		local state = caster()
		cast(state, "Cartouche")
		state.setup.glyph.resetCooldowns(state.player)
		cast(state, "Brand")
		state.setup.world:advance(1)
		near(left(state, "Brand"), GlyphConfig.ById.Brand.Cooldown - 1)
	end)
end)

describe("the Cartouche's numbers", function()
	it("keeps its whole cast at 48, under the ultimate's budget: the frame changes no damage", function()
		expect(CARTOUCHE.Damage + PARAMS.TickDamage * PARAMS.Ticks).toBe(48)
	end)

	it("hastens, and saves each cooldown at most a fifth of its own", function()
		expect(PARAMS.Hasten > 1).toBe(true)
		expect((PARAMS.Hasten - 1) * LIFE <= CARTOUCHE.Cooldown / 5).toBe(true)
		-- Laid with the zone's own radius: the frame the caster stands in is the frame the ticks strike.
		expect(PARAMS.Radius).toBe(CARTOUCHE.Range)
	end)

	it("says what it does, in both languages, at the rate it has", function()
		expect(PARAMS.Hasten).toBe(2)
		expect(string.find(Strings.t(CARTOUCHE.DescriptionKey, nil, "en"), "twice as fast", 1, true)).never.toBeNil()
		expect(string.find(Strings.t(CARTOUCHE.DescriptionKey, nil, "fr"), "deux fois plus vite", 1, true)).never.toBeNil()
	end)

	it("is the only glyph that hastens", function()
		for _, def in ipairs(GlyphConfig.Glyphs) do
			if def.Id ~= "Cartouche" then
				expect(def.Params.Hasten).toBeNil()
			end
		end
	end)
end)
