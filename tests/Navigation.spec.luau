--!strict
-- The way through the menus (D-147): a screen opened from another stacks on it and Back returns there; the
-- HUD, a prompt or a key start over; B on a gamepad goes back; and a screen that waits for a server message
-- hears it from the HUD. The stack's rules are pure and run here; the wiring is read.
local Harness = require("./harness")
local MenuStack = require("../src/shared/Pure/MenuStack")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MENU = "src/client/Controllers/MenuController.luau"
local INPUT = "src/client/Controllers/InputController.luau"
local HUD = "src/client/Controllers/HudController.luau"

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

-- The body of `header` up to its closing `end`, whitespace folded.
local function body(path: string, header: string): string
	local source = code(path)
	local start = string.find(source, header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = string.find(source, "\nend\n", start, true)
	return (string.gsub(string.sub(source, start, finish or #source), "%s+", " "))
end

local function ids(stack: MenuStack.Stack): string
	local names = {}
	for _, entry in ipairs(stack.Entries) do
		table.insert(names, entry.Id)
	end
	return table.concat(names, ">")
end

describe("the menu stack", function()
	it("stacks a screen opened from another, and Back returns there", function()
		local stack = MenuStack.new()
		local first = MenuStack.open(stack, "Menu", nil, false)
		expect(first.Leave).toBeNil()
		expect((first.Arrive :: MenuStack.Entry).Id).toBe("Menu")
		local push = MenuStack.open(stack, "Shop", { Tab = "Folios" }, true)
		expect((push.Leave :: MenuStack.Entry).Id).toBe("Menu")
		expect((push.Arrive :: MenuStack.Entry).Args.Tab).toBe("Folios")
		expect(ids(stack)).toBe("Menu>Shop")
		local back = MenuStack.back(stack)
		expect((back.Leave :: MenuStack.Entry).Id).toBe("Shop")
		expect((back.Arrive :: MenuStack.Entry).Id).toBe("Menu")
		expect(MenuStack.depth(stack)).toBe(1)
	end)

	it("closes the first screen on Back, and does nothing with none open", function()
		local stack = MenuStack.new()
		MenuStack.open(stack, "Play", nil, false)
		local back = MenuStack.back(stack)
		expect((back.Leave :: MenuStack.Entry).Id).toBe("Play")
		expect(back.Arrive).toBeNil()
		expect(MenuStack.depth(stack)).toBe(0)
		local none = MenuStack.back(stack)
		expect(none.Leave).toBeNil()
		expect(none.Arrive).toBeNil()
	end)

	it("starts over when something else than a screen opens one", function()
		local stack = MenuStack.new()
		MenuStack.open(stack, "Menu", nil, false)
		MenuStack.open(stack, "Quests", nil, true)
		local replaced = MenuStack.open(stack, "Result", nil, false)
		expect((replaced.Leave :: MenuStack.Entry).Id).toBe("Quests")
		expect((replaced.Arrive :: MenuStack.Entry).Id).toBe("Result")
		expect(ids(stack)).toBe("Result")
		-- A screen asking with nothing open starts the stack like anything else.
		local fresh = MenuStack.new()
		MenuStack.open(fresh, "Shop", nil, true)
		expect(ids(fresh)).toBe("Shop")
	end)

	it("goes back down to a screen already on the stack instead of stacking it twice", function()
		local stack = MenuStack.new()
		MenuStack.open(stack, "Menu", { From = "Hud" }, false)
		MenuStack.open(stack, "Play", nil, true)
		MenuStack.open(stack, "Shop", nil, true)
		local down = MenuStack.open(stack, "Menu", nil, true)
		expect((down.Leave :: MenuStack.Entry).Id).toBe("Shop")
		expect((down.Arrive :: MenuStack.Entry).Id).toBe("Menu")
		-- Kept what it was opened with, since the new call brought nothing.
		expect((down.Arrive :: MenuStack.Entry).Args.From).toBe("Hud")
		expect(ids(stack)).toBe("Menu")
	end)

	it("leaves the screen in front alone when it is asked for again", function()
		local stack = MenuStack.new()
		MenuStack.open(stack, "Menu", nil, false)
		MenuStack.open(stack, "Shop", nil, true)
		local same = MenuStack.open(stack, "Shop", nil, true)
		expect(same.Leave).toBeNil()
		expect(same.Arrive).toBeNil()
		expect(ids(stack)).toBe("Menu>Shop")
	end)

	it("closes everything at once", function()
		local stack = MenuStack.new()
		MenuStack.open(stack, "Menu", nil, false)
		MenuStack.open(stack, "Loadout", nil, true)
		local cleared = MenuStack.clear(stack)
		expect((cleared.Leave :: MenuStack.Entry).Id).toBe("Loadout")
		expect(cleared.Arrive).toBeNil()
		expect(MenuStack.depth(stack)).toBe(0)
		expect(MenuStack.top(stack)).toBeNil()
	end)
end)

describe("the menu controller", function()
	it("stacks what a screen opens and starts over for anything else", function()
		expect(string.find(body(MENU, "local function navigate("), "present(id, args, true)", 1, true)).never.toBeNil()
		expect(string.find(body(MENU, "function MenuController.open("), "present(id, args, false)", 1, true)).never.toBeNil()
		local init = body(MENU, "function MenuController.Init(")
		expect(string.find(init, "OnNavigate = navigate,", 1, true)).never.toBeNil()
		expect(string.find(init, "OnBack = MenuController.back,", 1, true)).never.toBeNil()
		expect(string.find(init, "CanGoBack = MenuController.canGoBack,", 1, true)).never.toBeNil()
	end)

	it("shows the way back only over another screen, and suspends play exactly while one is open", function()
		expect(
			string.find(body(MENU, "function MenuController.canGoBack("), "return MenuStack.depth(stack) > 1", 1, true)
		).never.toBeNil()
		local apply = body(MENU, "local function apply(")
		expect(string.find(apply, "screen:Open(arrive.Args)", 1, true)).never.toBeNil()
		expect(string.find(apply, "inputController.setSuspended(MenuStack.depth(stack) > 0)", 1, true)).never.toBeNil()
		-- The screen that leaves closes before the one that arrives opens.
		expect(
			(string.find(apply, "screen:Close()", 1, true) :: number)
				< string.find(apply, "screen:Open(", 1, true) :: number
		).toBe(true)
	end)

	it("goes back on B, bound and unbound with the key that closes, so a rebind capture still receives it", function()
		local bind = body(INPUT, "local function bindMenuClose(")
		expect(
			string.find(
				bind,
				"ContextActionService:BindActionAtPriority(MENU_BACK_ACTION, onMenuBack, false, ACTION_PRIORITY, MENU_BACK_KEY)",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(code(INPUT), "local MENU_BACK_KEY = Enum.KeyCode.ButtonB\n", 1, true)).never.toBeNil()
		expect(
			string.find(
				body(INPUT, "local function unbindMenuClose("),
				"ContextActionService:UnbindAction(MENU_BACK_ACTION)",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(body(INPUT, "local function onMenuBack("), "task.defer(menuController.back)", 1, true)).never.toBeNil()
	end)
end)

describe("the HUD's messages", function()
	it("reach a waiting screen before, and whether or not, a toast shows them", function()
		local notify = body(HUD, "local function onNotify(")
		local fired = string.find(notify, "HudController.Notified:Fire(payload.Key, params, kind)", 1, true)
		local toast = string.find(notify, "if toast == nil then", 1, true)
		assert(fired ~= nil and toast ~= nil, "onNotify no longer tells its listeners")
		expect(fired :: number).toBeLessThan(toast :: number)
	end)
end)
