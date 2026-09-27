--!strict
-- The way to the screens (D-128). Play, the Shop and the Leaderboard were reachable only through the M key,
-- whose only sign was a small muted "M = Menu"; the Shop was tenth in a menu that shows about seven rows;
-- the key that opened the menu could not close it; and every Robux button in Studio offered a purchase that
-- could only fail.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local HUD = "src/client/Controllers/HudController.luau"
local MENU = "src/ui/screens/MenuScreen.luau"
local INPUT = "src/client/Controllers/InputController.luau"
local SHOP = "src/ui/screens/ShopScreen.luau"

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

local function folded(path: string): string
	return (code(path):gsub("%s+", " "))
end

local function body(path: string, header: string): string
	local source = code(path)
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
end

describe("the HUD's quick bar", function()
	it("puts Play, the Shop and the Leaderboard one click away, and names the Menu key", function()
		local hud = folded(HUD)
		for _, entry in ipairs({
			'{ Screen = "Play", NameKey = "queue.title", Variant = "Primary" }',
			'{ Screen = "Shop", NameKey = "menu.shop", Variant = "Secondary" }',
			'{ Screen = "Leaderboard", NameKey = "leaderboard.title", Variant = "Secondary" }',
		}) do
			if hud:find(entry, 1, true) == nil then
				error("the quick bar lost " .. entry)
			end
		end
		local bar = body(HUD, "local function buildQuickBar(")
		expect(bar:find("menuController.open(entry.Screen)", 1, true)).never.toBe(nil)
		expect(bar:find("menuController.toggle()", 1, true)).never.toBe(nil)
		expect(hud:find("quickBar.Visible = true", 1, true)).never.toBe(nil)
	end)

	it("stands where nothing draws over it, and keeps a gamepad selection in the panel", function()
		-- The top-right is the engine's player list, a CoreGui over every ScreenGui that takes the clicks.
		local bar = body(HUD, "local function buildQuickBar(")
		expect(bar:find("quickBar.AnchorPoint = Vector2.new(1, 1)", 1, true)).never.toBe(nil)
		expect(bar:find("quickBar.Position = UDim2.new(1, -pad, 1, -pad)", 1, true)).never.toBe(nil)
		local button = body(HUD, "local function quickButton(")
		expect(button:find("button.Instance.Selectable = false", 1, true)).never.toBe(nil)
	end)
end)

describe("the menu", function()
	it("lists a match, the shop and the ladder first, and a gamepad lands on Play", function()
		local menu = folded(MENU)
		local function order(name: string): number
			local value = menu:match("local " .. name .. " = Button.new%(%{[^}]-LayoutOrder = (%d+),")
			if value == nil then
				error(("%s has no LayoutOrder"):format(name))
			end
			return tonumber(value) :: number
		end
		expect(order("playButton")).toBe(3)
		expect(order("shopButton")).toBe(4)
		expect(order("leaderboardButton")).toBe(5)
		expect(menu:find("panel:FocusForGamepad(playButton.Instance)", 1, true)).never.toBe(nil)
	end)

	it("closes with the key that opened it", function()
		local apply = body(INPUT, "local function applyBindings(")
		-- Whole statements: "unbindMenuClose()" contains "bindMenuClose()".
		expect(
			apply:find(
				"task.defer(function() if suspended and capture == nil then bindMenuClose() end end) else unbindMenuClose() end",
				1,
				true
			)
		).never.toBe(nil)
		local close = body(INPUT, "local function onMenuClose(")
		expect(close:find("task.defer(menuController.close)", 1, true)).never.toBe(nil)
	end)
end)

describe("the shop", function()
	it("offers Robux only for a product that exists on Roblox", function()
		local offered = body(SHOP, "local function robuxOffered(")
		expect(offered:find("return product ~= nil and product.Id ~= 0", 1, true)).never.toBe(nil)
		expect(folded(SHOP):find("card.Action:SetDisabled(not robuxOffered(entry.ProductKey))", 1, true)).never.toBe(
			nil
		)
	end)
end)
