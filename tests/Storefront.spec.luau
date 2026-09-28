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
