--!strict
-- The screens a player opens to play and to collect (D-147, slice A of the colour pass): the menu's tiles,
-- the play cards, the shop, the battle pass, the daily reward. They are engine code Lune cannot run, so what
-- can regress without a sound is held by reading them: two tiles of one colour side by side, a purchase made
-- on one tap, a burst of claims the server would refuse, a red button where nothing is dangerous.
local Harness = require("./harness")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MENU = "src/ui/screens/MenuScreen.luau"
local PLAY = "src/ui/screens/PlayScreen.luau"
local SHOP = "src/ui/screens/ShopScreen.luau"
-- The screens of this slice, for the rules every one of them keeps.
local SCREENS = { MENU, PLAY, SHOP }
local SERVER = "src/server"

local function stripComments(source: string): string
	local withoutBlocks = string.gsub(source, "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function code(path: string): string
	return stripComments(fs.readFile(path))
end

local function folded(path: string): string
	return (string.gsub(code(path), "%s+", " "))
end

local function count(source: string, plain: string): number
	local found, from = 0, 1
	while true do
		local at = string.find(source, plain, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + 1
	end
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

type Tile = { Name: string, Chapter: string, Order: number }

-- Every tile the menu builds: its local's name, its chapter and its LayoutOrder, read from its props.
local function menuTiles(): { Tile }
	local tiles: { Tile } = {}
	for name, props in string.gmatch(code(MENU), "local (%w+) = Button%.new%((%b{})%)") do
		if string.find(props, 'Variant = "Tile"', 1, true) ~= nil then
			local chapter = string.match(props, 'Chapter = "(%w+)"')
			local order = string.match(props, "LayoutOrder = (%d+)")
			assert(chapter ~= nil and order ~= nil, ("tile %s names no chapter or no order"):format(name))
			table.insert(tiles, { Name = name, Chapter = chapter :: string, Order = tonumber(order) :: number })
		end
	end
	return tiles
end

describe("the menu", function()
	it("never sets two tiles of one colour side by side", function()
		local columns = tonumber(string.match(code(MENU), "local GRID_COLUMNS = (%d+)"))
		assert(columns ~= nil, "the menu names no GRID_COLUMNS: this gate would check nothing")
		local tiles = menuTiles()
		-- Play, and the six of the grid.
		expect(#tiles).toBe(7)
		local play: Tile? = nil
		local grid: { Tile } = {}
		for _, tile in ipairs(tiles) do
			if tile.Chapter == "Play" then
				play = tile
			else
				table.insert(grid, tile)
			end
		end
		assert(play ~= nil, "the menu has no Play tile")
		-- Two tiles in one place of the order are laid out however the engine breaks the tie.
		local taken: { [number]: string } = {}
		for _, tile in ipairs(grid) do
			if taken[tile.Order] ~= nil then
				error(("%s and %s share the LayoutOrder %d"):format(taken[tile.Order], tile.Name, tile.Order))
			end
			taken[tile.Order] = tile.Name
		end
		-- The grid fills row by row in LayoutOrder; Play stands to its left, the height of every row.
		table.sort(grid, function(a: Tile, b: Tile): boolean
			return a.Order < b.Order
		end)
		local function colour(tile: Tile): string
			local role = ThemeConfig.Chapters[tile.Chapter]
			assert(role ~= nil, ("tile %s names no chapter colour"):format(tile.Name))
			return role
		end
		local function apart(a: Tile, b: Tile)
			if colour(a) == colour(b) then
				error(("%s and %s touch in one colour (%s)"):format(a.Name, b.Name, colour(a)))
			end
		end
		for index, tile in ipairs(grid) do
			local column = (index - 1) % columns
			if column == 0 then
				apart(play :: Tile, tile)
			end
			local right = grid[index + 1]
			if right ~= nil and column < columns - 1 then
				apart(tile, right)
			end
			local below = grid[index + columns]
			if below ~= nil then
				apart(tile, below)
			end
		end
	end)
end)

describe("these screens", function()
	it("never paint a button red: nothing in them is a danger", function()
		for _, path in ipairs(SCREENS) do
			local source = code(path)
			if string.find(source, '"Danger"', 1, true) ~= nil then
				error(("%s draws a Danger button: leaving a queue, buying or claiming is no danger"):format(path))
			end
		end
	end)

	it("keep no per-frame loop: their clocks tick on task.delay", function()
		for _, path in ipairs(SCREENS) do
			local source = code(path)
			for _, signal in ipairs({ "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation" }) do
				if string.find(source, signal, 1, true) ~= nil then
					error(("%s listens to %s: a screen's clock is a task.delay a second"):format(path, signal))
				end
			end
		end
	end)
end)

describe("the play cards", function()
	it("wait for the very message the server sends when the queue gives up", function()
		local key = string.match(code(PLAY), 'local TIMED_OUT_KEY = "([%w%.]+)"')
		assert(key ~= nil, "the play screen names no TIMED_OUT_KEY: this gate would check nothing")
		local files: { string } = {}
		collect(SERVER, files)
		local sent = false
		for _, path in ipairs(files) do
			if string.find(code(path), ('send(player, "%s"'):format(key :: string), 1, true) ~= nil then
				sent = true
			end
		end
		if not sent then
			error(("no server service sends %s: the timed-out card would never show"):format(key :: string))
		end
		-- And the screen hears it from the HUD, which hears every message.
		expect(string.find(code(PLAY), "trove:Connect(deps.HudController.Notified,", 1, true)).never.toBeNil()
	end)
end)

describe("the shop", function()
	it("buys with Folios only once the sheet has asked: never on one tap", function()
		local shop = folded(SHOP)
		-- One place sends the purchase, and it is the sheet's confirmation that reaches it.
		expect(count(shop, 'fire("BuyCosmetic"')).toBe(1)
		local buy = string.match(shop, "local function buy%(current: Purchase%)(.-) end local function ")
		assert(buy ~= nil, "the shop has no buy(current): this gate would check nothing")
		expect(string.find(buy :: string, 'fire("BuyCosmetic", current.CosmeticId)', 1, true)).never.toBeNil()
		expect(count(shop, "buy(current)")).toBe(1)
		expect(string.find(shop, "OnConfirm = function() buy(current) end", 1, true)).never.toBeNil()
		-- The card's price opens the sheet.
		expect(string.find(shop, "confirmPurchase(card.Entry)", 1, true)).never.toBeNil()
	end)
end)
