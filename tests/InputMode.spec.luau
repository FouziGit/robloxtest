--!strict
-- How the player plays, decided in one place (src/client/Controllers/InputMode, D-XXX), run (tests/engine.luau).
--
-- Three modules decided it three ways: Theme called a touch screen with no keyboard a phone, the HUD and the discs
-- called any touch screen one, and the key hints followed the last input's type. A touch laptop got the pointer's
-- scale and corner with the phone's discs over them; a tablet with a pad pressed its buttons under discs nobody
-- touched. InputMode reads the engine's own answer (UserInputService.PreferredInput) and, where there is none,
-- the devices as Theme did; nothing else in src reads the touch screen.
local Engine = require("./engine")
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local INPUT_MODE = "src/client/Controllers/InputMode.luau"
local BOOTSTRAP = "src/client/Bootstrap.client.luau"
local ROOTS = { "src/client", "src/server", "src/shared", "src/ui" }
-- What only InputMode reads: the touch screen, and the engine's answer.
local READS_ONLY_HERE = { "TouchEnabled", "PreferredInput" }

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

-- The world on `plays`, and its InputMode, started as the bootstrap starts it: Theme is handed it as it loads.
local function on(plays: Engine.Plays): (any, any, any)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	Engine.plays(world, plays)
	local Theme = world.require("src/ui/Theme")
	return world, world.require("src/client/Controllers/InputMode"), Theme
end

describe("one reader of how the player plays", function()
	it("is InputMode: nothing else in src reads the touch screen or the engine's answer", function()
		local files: { string } = {}
		for _, root in ipairs(ROOTS) do
			collect(root, files)
		end
		expect(#files).toBeGreaterThan(50)
		local offences: { string } = {}
		for _, path in ipairs(files) do
			local code = stripComments(fs.readFile(path))
			for _, member in ipairs(READS_ONLY_HERE) do
				local read = string.find(code, "%f[%w_]" .. member .. "%f[^%w_]") ~= nil
				if read and path ~= INPUT_MODE then
					table.insert(
						offences,
						("%s reads %s: ask InputMode (or Theme.input/touchOnly in src/ui)"):format(path, member)
					)
				end
			end
		end
		table.sort(offences)
		if #offences > 0 then
			error(table.concat(offences, "\n"))
		end
		-- And InputMode does read them: a gate over a reader that reads nothing would pass on nothing.
		local own = stripComments(fs.readFile(INPUT_MODE))
		expect(string.find(own, "UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled", 1, true)).never.toBeNil()
		expect(string.find(own, 'local PREFERRED = "PreferredInput"', 1, true)).never.toBeNil()
	end)

	it("is started with the interface's doors, before any Init builds a screen, and handed to Theme", function()
		local boot = stripComments(fs.readFile(BOOTSTRAP))
		local first = string.find(boot, 'local ORDER = {%s*"InputMode",')
		local started = string.find(boot, "inputMode.start()", 1, true)
		local handed = string.find(boot, 'require(UI:WaitForChild("Theme")).useInput(inputMode)', 1, true)
		local inits = string.find(boot, "controller.Init", 1, true)
		assert(
			first ~= nil and started ~= nil and handed ~= nil and inits ~= nil,
			"the bootstrap no longer wires InputMode"
		)
		expect(started :: number).toBeLessThan(handed :: number)
		expect(handed :: number).toBeLessThan(inits :: number)
	end)
end)

describe("how the player plays, run", function()
	-- Each device and the engine's answer to it: the input in use, and whether the screen is in the hand.
	local CASES: { { Plays: Engine.Plays, Mode: string, Handheld: boolean } } = {
		{ Plays = "Touch", Mode = "Touch", Handheld = true },
		{ Plays = "Pointer", Mode = "Pointer", Handheld = false },
		{ Plays = "Gamepad", Mode = "Gamepad", Handheld = false },
		-- A touch laptop or a tablet typed on is used like a desktop.
		{ Plays = "TouchKeyboard", Mode = "Pointer", Handheld = false },
		-- A phone with a pad: the pad plays, the screen is still in the hand.
		{ Plays = "TouchGamepad", Mode = "Gamepad", Handheld = true },
		-- A touch laptop touched: touch, in the hand.
		{ Plays = "TouchLaptop", Mode = "Touch", Handheld = true },
	}

	it("follows the engine's answer, and holds a phone with a pad in the hand", function()
		for _, case in ipairs(CASES) do
			local _world, InputMode, Theme = on(case.Plays)
			if InputMode.get() ~= case.Mode or InputMode.handheld() ~= case.Handheld then
				error(
					("%s plays by %s (in the hand: %s), not %s (%s)"):format(
						case.Plays,
						InputMode.get(),
						tostring(InputMode.handheld()),
						case.Mode,
						tostring(case.Handheld)
					)
				)
			end
			-- src/ui reads the same answers through its door.
			expect(Theme.input()).toBe(case.Mode)
			expect(Theme.touchOnly()).toBe(case.Handheld)
		end
	end)

	it("says so once when a touch laptop is touched, and again when it is typed on", function()
		local world, InputMode = on("TouchKeyboard")
		local heard: { string } = {}
		InputMode.Changed:Connect(function(mode: string)
			table.insert(heard, mode)
		end)
		Engine.plays(world, "TouchLaptop")
		expect(#heard).toBe(1)
		expect(heard[1]).toBe("Touch")
		expect(InputMode.handheld()).toBe(true)
		-- The same answer again is no change.
		world.userInput.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Touch)
		expect(#heard).toBe(1)
		Engine.plays(world, "TouchKeyboard")
		expect(#heard).toBe(2)
		expect(heard[2]).toBe("Pointer")
		expect(InputMode.handheld()).toBe(false)
	end)

	it("lets the devices decide where the engine gives no answer, as Theme did, and says it once", function()
		local world, InputMode = on("Touch")
		world.userInput.PreferredInput = nil
		world.userInput.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Touch)
		expect(InputMode.get()).toBe("Touch")
		expect(InputMode.handheld()).toBe(true)
		-- A touch laptop with no answer is a pointer until a pad's input comes.
		world.userInput.TouchEnabled = true
		world.userInput.KeyboardEnabled = true
		world.userInput.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.MouseButton1)
		expect(InputMode.get()).toBe("Pointer")
		expect(InputMode.handheld()).toBe(false)
		world.userInput.GamepadEnabled = true
		world.userInput.LastInputTypeChanged:Fire(roblox.Enum.UserInputType.Gamepad1)
		expect(InputMode.get()).toBe("Gamepad")
		local said = 0
		for _, line in ipairs(world.warnings) do
			if string.find(line, "PreferredInput", 1, true) ~= nil then
				said += 1
			end
		end
		expect(said).toBe(1)
	end)

	it("draws a recipe's hint for the input in use: the pad's buttons on a phone played with a pad", function()
		local DEVICES: { [string]: string } = {
			Touch = "Touch",
			Pointer = "Keyboard",
			Gamepad = "Gamepad",
			TouchKeyboard = "Keyboard",
			TouchGamepad = "Gamepad",
			TouchLaptop = "Touch",
		}
		for plays, device in pairs(DEVICES) do
			local world = on(plays :: Engine.Plays)
			local GlyphCard = world.require("src/ui/components/GlyphCard")
			if GlyphCard.device() ~= device then
				error(("%s draws its recipes for %s, not %s"):format(plays, GlyphCard.device(), device))
			end
		end
		-- And a screen that draws them hears the switch (the Loadout's cards, through Theme.bindInput).
		local world, _InputMode, Theme = on("Pointer")
		local GlyphCard = world.require("src/ui/components/GlyphCard")
		local heard: { string } = {}
		local unbind = Theme.bindInput(function()
			table.insert(heard, GlyphCard.device())
		end)
		Engine.plays(world, "Gamepad")
		expect(heard[#heard]).toBe("Gamepad")
		unbind()
		Engine.plays(world, "Pointer")
		expect(#heard).toBe(1)
	end)

	it("redraws the Loadout's recipes with the pad's buttons when a pad is picked up", function()
		local world = on("Pointer")
		local Screen = world.require("src/ui/screens/LoadoutScreen")
		local data = {
			Loadout = { Slots = { "Brand" }, SlotLimit = 6 },
			Unlocks = { Glyphs = { "Brand" } },
			Passes = {},
			Settings = { Keyboard = {}, Gamepad = {} },
		}
		local screen = Screen.new({
			Localize = {
				t = function(key: string): string
					return key
				end,
			},
			ClientData = {
				get = function(): any
					return data
				end,
				Changed = Engine.signal(),
			},
			RemoteClient = { fire = function() end },
			SoundController = { play = function() end },
			OnClose = function() end,
			OnBack = function() end,
			CanGoBack = function(): boolean
				return false
			end,
		})
		screen:Open()
		world:advance(0.5)
		-- The words the first card's recipe draws (Brand: Cinnabar, Cinnabar).
		local function recipe(): string
			local found = screen.Instance:FindFirstChild("Recipe", true)
			assert(found ~= nil, "the Loadout draws no recipe: this gate would check nothing")
			local words = {}
			for _, part in ipairs(found:GetDescendants()) do
				if part:IsA("TextLabel") and part.Text ~= "" then
					table.insert(words, part.Text)
				end
			end
			return table.concat(words, " ")
		end
		local keys = recipe()
		expect(string.find(keys, "J", 1, true)).never.toBeNil()
		expect(string.find(keys, "↑", 1, true)).toBeNil()
		Engine.plays(world, "Gamepad")
		local buttons = recipe()
		expect(string.find(buttons, "↑", 1, true)).never.toBeNil()
		expect(string.find(buttons, "J", 1, true)).toBeNil()
	end)

	it("moves every screen's scale to the hand's floor when a touch laptop is touched", function()
		local world, _InputMode, Theme = on("TouchKeyboard")
		world.workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(1366, 700)
		local applied: { number } = {}
		local unbind = Theme.bindScale(function()
			table.insert(applied, Theme.activeScale())
		end)
		expect(applied[#applied]).toBe(ThemeConfig.Scale.PointerFloor)
		Engine.plays(world, "TouchLaptop")
		expect(applied[#applied]).toBe(ThemeConfig.scaleFor(700, true))
		expect(applied[#applied]).toBeLessThan(ThemeConfig.Scale.PointerFloor)
		unbind()
		Engine.plays(world, "TouchKeyboard")
		expect(applied[#applied]).toBe(ThemeConfig.scaleFor(700, true))
	end)
end)

return nil
