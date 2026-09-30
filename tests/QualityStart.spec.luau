--!strict
-- Where a client's quality starts, and how far a Driven flow may beat the engine (QualityConfig.Start,
-- DrivenOverEngine, D-XXX), run (tests/engine.luau): the real QualityController, with InputMode as the bootstrap
-- starts it and the player's Roblox settings as a LocalScript reads them.
--
-- Every client started at High whatever it was. A modest phone spent a new player's first seconds at twenty
-- frames until three bad seconds brought it down, and a player who had told Roblox their device was weak (a
-- graphics level of 1 to 3) was drawn the same as a desktop's.
local Engine = require("./engine")
local Harness = require("./harness")
local QualityConfig = require("../src/shared/Config/QualityConfig")
local VfxTimelineConfig = require("../src/shared/Config/VfxTimelineConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local RENDERER = "src/client/Controllers/VfxTimeline.luau"

type Device = { Plays: Engine.Plays, Height: number, Level: number?, Chosen: string? }
type Started = { world: any, quality: any, choose: (tier: string) -> () }

-- The controller started on `device`: a window `Height` points tall, played as `Plays`, the Roblox graphics level
-- set by hand to `Level` (automatic without one), and a profile whose choice is `Chosen` (none yet without one).
local function start(device: Device): Started
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	world.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(device.Height * 2, device.Height)
	Engine.plays(world, device.Plays)
	if device.Level ~= nil then
		world.gameSettings.SavedQualityLevel = (roblox.Enum.SavedQualitySetting :: any)["QualityLevel" .. device.Level]
	end
	local data: any = if device.Chosen ~= nil then { Settings = { Quality = device.Chosen } } else nil
	local changed = Engine.signal()
	-- InputMode as the bootstrap starts it: Theme is handed it as it loads.
	world.require("src/ui/Theme")
	local quality = world.require("src/client/Controllers/QualityController")
	quality.Init({
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = changed,
		},
		InputMode = world.require("src/client/Controllers/InputMode"),
	})
	quality.Start()
	return {
		world = world,
		quality = quality,
		choose = function(tier: string)
			data = { Settings = { Quality = tier } }
			changed:Fire("Settings")
		end,
	}
end

describe("where a client's quality starts, run", function()
	it("starts a phone at Medium, and a tablet, a small window or a tall phone where they chose", function()
		expect(QualityConfig.Start.Phone).toBe("Medium")
		expect(QualityConfig.Start.PhoneMaxHeight).toBe(430)
		local phone = start({ Plays = "Touch", Height = 390 })
		expect(phone.quality.get()).toBe("Medium")
		-- The profile's choice, when it comes, is the ceiling; the phone's start stays under it.
		phone.choose("High")
		expect(phone.quality.get()).toBe("Medium")
		expect(phone.quality.chosen()).toBe("High")
		-- At its edge, and played with a pad: still a phone in the hand.
		expect(start({ Plays = "Touch", Height = 430 }).quality.get()).toBe("Medium")
		expect(start({ Plays = "TouchGamepad", Height = 375 }).quality.get()).toBe("Medium")
		-- Not a phone: a tablet, a phone taller than the edge, a desktop window as short as a phone.
		expect(start({ Plays = "Touch", Height = 820 }).quality.get()).toBe("High")
		expect(start({ Plays = "Touch", Height = 431 }).quality.get()).toBe("High")
		expect(start({ Plays = "Pointer", Height = 390 }).quality.get()).toBe("High")
		expect(start({ Plays = "TouchKeyboard", Height = 390 }).quality.get()).toBe("High")
	end)

	it("starts at Low under a low Roblox graphics level the player set by hand, and not when Roblox chooses", function()
		expect(QualityConfig.Start.LowLevel).toBe("Low")
		for level = 1, 10 do
			local started = start({ Plays = "Pointer", Height = 1080, Level = level, Chosen = "High" })
			local expected = if level <= QualityConfig.Start.LowLevelAtOrUnder then "Low" else "High"
			if started.quality.get() ~= expected then
				error(("a graphics level of %d starts at %s, not %s"):format(level, started.quality.get(), expected))
			end
		end
		expect(start({ Plays = "Pointer", Height = 1080, Chosen = "High" }).quality.get()).toBe("High")
		-- A phone set low by hand: the lower of the two.
		expect(start({ Plays = "Touch", Height = 390, Level = 1 }).quality.get()).toBe("Low")
	end)

	it("keeps the player's choice as the ceiling, and follows a choice made later as it is", function()
		-- Chosen below the start: never raised to it.
		local low = start({ Plays = "Touch", Height = 390, Chosen = "Performance" })
		expect(low.quality.get()).toBe("Performance")
		-- A phone that starts at Medium, and whose player then asks for High in the Options, gets High.
		local phone = start({ Plays = "Touch", Height = 390, Chosen = "High" })
		expect(phone.quality.get()).toBe("Medium")
		phone.choose("Low")
		expect(phone.quality.get()).toBe("Low")
		phone.choose("High")
		expect(phone.quality.get()).toBe("High")
		-- The profile's first choice is the one the start lowers, even when it is the default; the next is the
		-- player's, followed as it is: set low by hand, a desktop that starts at Low is asked for Medium and gets it.
		local set = start({ Plays = "Pointer", Height = 1080, Level = 2 })
		set.choose("High")
		expect(set.quality.get()).toBe("Low")
		set.choose("Medium")
		expect(set.quality.get()).toBe("Medium")
		-- And the frame rate never lifts a start above the ceiling: sixty frames for longer than it waits.
		local capped = start({ Plays = "Pointer", Height = 1080, Level = 2, Chosen = "Medium" })
		expect(capped.quality.get()).toBe("Low")
		capped.world:advance(QualityConfig.Auto.RaiseAfterSeconds * 3, 1 / 60)
		expect(capped.quality.get()).toBe("Medium")
	end)

	it("starts as if Roblox chose the level when the engine refuses to say it, and says so once", function()
		local refused: Started? = nil
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		world.userSettings.GetService = function(): any
			error("The current thread cannot access 'UserGameSettings' (lacking capability RobloxScript)")
		end
		world.require("src/ui/Theme")
		local quality = world.require("src/client/Controllers/QualityController")
		quality.Init({
			ClientData = {
				get = function(): any
					return nil
				end,
				Changed = Engine.signal(),
			},
			InputMode = world.require("src/client/Controllers/InputMode"),
		})
		quality.Start()
		refused = { world = world, quality = quality, choose = function() end }
		expect((refused :: Started).quality.get()).toBe("High")
		local said = 0
		for _, line in ipairs(world.warnings) do
			if string.find(line, "SavedQualityLevel", 1, true) ~= nil then
				said += 1
			end
		end
		expect(said).toBe(1)
	end)
end)

describe("a Driven flow against the engine's thinning", function()
	-- Every Driven layer of every timeline.
	local function drivenLayers(): { any }
		local found = {}
		for _, timeline in pairs(VfxTimelineConfig.Timelines) do
			for _, phase in ipairs(timeline.Phases) do
				for _, layer in ipairs(phase.Layers) do
					if layer.Driven == true then
						table.insert(found, layer)
					end
				end
			end
		end
		return found
	end

	it("never draws more than twice what the engine would, at any tier", function()
		expect(QualityConfig.DrivenOverEngine).toBe(2)
		local layers = drivenLayers()
		expect(#layers).toBeGreaterThan(10)
		for _, name in ipairs(QualityConfig.Order) do
			local tier = QualityConfig.Tiers[name]
			for _, layer in ipairs(layers) do
				-- What the engine would draw of the same Rate the game's tier sets, and what the flow emits.
				local engine = layer.Rate * tier.ParticleScale * tier.EngineShare
				local drawn = layer.Rate * tier.ParticleScale * QualityConfig.drivenShare(tier)
				if drawn > QualityConfig.DrivenOverEngine * engine + 1e-9 then
					error(("a Driven flow of %g draws %g at %s, the engine %g"):format(layer.Rate, drawn, name, engine))
				end
			end
		end
		-- Where the engine draws a Rate whole, the fire is whole too (D-124 kept on a device that holds High).
		expect(QualityConfig.drivenShare(QualityConfig.Tiers.High)).toBe(1)
	end)

	it("models the engine from the one measurement there is, thinning down the tiers", function()
		-- The lab (D-124): eighty flames a second drawn as five at the engine's lowest automatic quality.
		expect(QualityConfig.Tiers.Performance.EngineShare).toBe(5 / 80)
		expect(QualityConfig.Tiers.High.EngineShare).toBe(1)
		local previous = math.huge
		for _, name in ipairs(QualityConfig.Order) do
			local share = QualityConfig.Tiers[name].EngineShare
			expect(share).toBeLessThan(previous)
			expect(share).toBeGreaterThan(0)
			previous = share
		end
	end)

	it("is what the renderer emits: the flow owes its rate times the tier's share", function()
		local source = fs.readFile(RENDERER)
		expect(
			string.find(
				source,
				"{ Rate = layer.Rate * density * QualityConfig.drivenShare(tier), Carry = 0, At = entry.StartedAt }",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(source, "local tier: QualityConfig.TierDef = quality.def()", 1, true)).never.toBeNil()
	end)
end)

return nil
