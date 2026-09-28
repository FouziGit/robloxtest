--!strict
-- The Loadout on a gamepad, run (tests/engine.luau): the real LoadoutScreen, SocketBar, GlyphCard and Panel.
--
-- Every change rebuilds the socket row, and on the Equipped tab the cards: A on a socket, or Unequip on a
-- card, destroyed the very control the pad was on, and the D-pad was dead until the player pressed the
-- navigation button again.
local Engine = require("./engine")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Fixture = { world: any, screen: any, data: any, changed: any }

local function setup(slots: { string }): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	world.userInput.GamepadEnabled = true
	local Screen = world.require("src/ui/screens/LoadoutScreen")
	local changed = Engine.signal()
	local data = {
		Loadout = { Slots = table.clone(slots), SlotLimit = 6 },
		Unlocks = { Glyphs = { "Brand", "Wash", "Serif" } },
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
			Changed = changed,
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
	return { world = world, screen = screen, data = data, changed = changed }
end

-- The filled sockets, in the row's order.
local function sockets(fixture: Fixture): { any }
	local found = {}
	for _, child in ipairs(fixture.screen.Instance:GetDescendants()) do
		if child.Name == "Socket" and child.Selectable then
			table.insert(found, child)
		end
	end
	table.sort(found, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	return found
end

local function selected(fixture: Fixture): any
	return fixture.world.guiService.SelectedObject
end

local function live(fixture: Fixture, object: any): boolean
	return object ~= nil and not Engine.destroyed(object) and object:IsDescendantOf(fixture.screen.Instance)
end

describe("the Loadout on a gamepad, run", function()
	it("keeps the pad on the socket that slides into the place of the one taken off", function()
		local fixture = setup({ "Brand", "Wash", "Serif" })
		local first = sockets(fixture)[1]
		fixture.world.guiService.SelectedObject = first
		first.Activated:Fire()
		expect(Engine.destroyed(first)).toBe(true)
		local now = sockets(fixture)
		expect(#now).toBe(2)
		expect(selected(fixture)).toBe(now[1])
	end)

	it("moves to the last socket left when the last one comes off", function()
		local fixture = setup({ "Brand", "Wash" })
		local second = sockets(fixture)[2]
		fixture.world.guiService.SelectedObject = second
		second.Activated:Fire()
		expect(selected(fixture)).toBe(sockets(fixture)[1])
	end)

	it("goes to a card when no socket is left", function()
		local fixture = setup({ "Brand" })
		local only = sockets(fixture)[1]
		fixture.world.guiService.SelectedObject = only
		only.Activated:Fire()
		expect(#sockets(fixture)).toBe(0)
		expect(live(fixture, selected(fixture))).toBe(true)
		expect(selected(fixture):IsA("TextButton")).toBe(true)
	end)

	it("goes on to a card when the card it was on leaves the Equipped tab", function()
		local fixture = setup({ "Brand", "Wash" })
		local card = selected(fixture)
		expect(live(fixture, card)).toBe(true)
		card.Activated:Fire()
		expect(Engine.destroyed(card)).toBe(true)
		expect(live(fixture, selected(fixture))).toBe(true)
	end)

	it("goes on when a push rebuilds under it", function()
		local fixture = setup({ "Brand", "Wash" })
		local card = selected(fixture)
		fixture.data.Loadout.Slots = { "Wash" }
		fixture.changed:Fire("Loadout")
		expect(Engine.destroyed(card)).toBe(true)
		expect(live(fixture, selected(fixture))).toBe(true)
	end)

	it("leaves the pad alone when it was not on the screen", function()
		local fixture = setup({ "Brand", "Wash" })
		fixture.world.guiService.SelectedObject = nil
		fixture.data.Loadout.Slots = { "Wash" }
		fixture.changed:Fire("Loadout")
		expect(selected(fixture)).toBeNil()
	end)
end)

return nil
