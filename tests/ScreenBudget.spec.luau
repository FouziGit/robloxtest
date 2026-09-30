--!strict
-- What each screen draws as it opens, counted (E11-S5, D-234), run (tests/engine.luau, tests/screens.luau): the ten
-- screens and each tab of the Shop, on an 844 x 390 phone at the touch floor, for a player who owns everything
-- they list -- every glyph, every cosmetic, every pass, the pass at its last tier, the leaderboard's whole top --
-- against ThemeConfig.Budget: a screen at most MaxScreenObjects, the pass's road at most MaxPassObjects.
--
-- Nothing counted them: a locker of everything drew 1 282 objects, the leaderboard's fifty rows 684 and ten
-- equipped glyphs 510. Those lists are built a chunk at a time now (src/ui/Progressive.luau). A GuiObject counted
-- is one the engine lays out and draws, as tests/HudBudget.spec.luau counts the HUD: shown, with every ancestor
-- up to the screen, each screen laid out as the engine lays it out as it opens (laidOut). The table of
-- docs/PERFORMANCE.md is these counts, and is held to them here.
local Engine = require("./engine")
local Harness = require("./harness")
local Measure = require("./measure")
local Screens = require("./screens")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PHONE = { 844, 390 }
local BUDGET = ThemeConfig.Budget
local PERFORMANCE = "docs/PERFORMANCE.md"

-- The GuiObjects under `root` the engine draws: each one shown, with every ancestor up to `root`.
local function shownUnder(root: any): number
	local count = 0
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("GuiObject") then
			local shown = true
			local current = part
			while current ~= nil and current ~= root do
				if current:IsA("GuiObject") and not current.Visible then
					shown = false
					break
				end
				current = current.Parent
			end
			if shown then
				count += 1
			end
		end
	end
	return count
end

type Measured = { Label: string, Count: number, Limit: number }

-- Whether an automatic size (or an automatic canvas size) grows down: the engine's default is none.
local function growsDown(automatic: any): boolean
	return automatic ~= nil and (automatic.Name == "Y" or automatic.Name == "XY")
end

-- The least height `frame` lays its shown children out to: a grid's rows of cells, as many to a row as the widest
-- the frame can be holds (Measure.widthOf, an upper bound); a vertical list's rows, each its fixed height or, sized
-- by its content, the least its own layout needs. Never more than the engine lays out, so a canvas measured this
-- way lets a list built as it is scrolled (Progressive) build at least what the engine has it build.
local function leastHeight(frame: any, screenWidth: number): number
	local shown: { any } = {}
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(shown, child)
		end
	end
	local grid = frame:FindFirstChildOfClass("UIGridLayout")
	if grid ~= nil then
		if #shown == 0 then
			return 0
		end
		local width = Measure.widthOf(frame, screenWidth)
		local cell = grid.CellSize.X.Scale * width + grid.CellSize.X.Offset
		local gap = grid.CellPadding.X.Scale * width + grid.CellPadding.X.Offset
		local across = math.max(1, math.floor((width + gap) / (cell + gap)))
		local rows = math.ceil(#shown / across)
		return rows * grid.CellSize.Y.Offset + (rows - 1) * grid.CellPadding.Y.Offset
	end
	local list = frame:FindFirstChildOfClass("UIListLayout")
	if list == nil or (list.FillDirection ~= nil and list.FillDirection.Name ~= "Vertical") then
		return 0
	end
	local total = 0
	for _, child in ipairs(shown) do
		local own = child.Size.Y.Offset
		total += if growsDown(child.AutomaticSize) then math.max(own, leastHeight(child, screenWidth)) else own
	end
	return total + math.max(0, #shown - 1) * list.Padding.Offset
end

-- The screen's list laid out as the engine lays it out once it opens: its window, and its canvas, never shorter
-- than the window and only taller where it grows down (CardContent). A list built as it is scrolled hears both and
-- may build more (Progressive); laid out again until nothing moves, as the engine does frame after frame. Lune lays
-- nothing out, and without this a list that builds as far as its view needs was counted at its first chunk.
local function laidOut(root: any, height: number, width: number)
	local content = root:FindFirstChild("Content", true)
	if content == nil or not content:IsA("ScrollingFrame") then
		return
	end
	for _ = 1, 100 do
		local window = Measure.heightOf(content, height)
		local canvas = if growsDown(content.AutomaticCanvasSize)
			then math.max(window, leastHeight(content, width))
			else window
		-- A Vector2 holds single precision: equal to within a hundredth of a unit is equal.
		if
			math.abs(content.AbsoluteWindowSize.Y - window) < 0.01
			and math.abs(content.AbsoluteCanvasSize.Y - canvas) < 0.01
		then
			return
		end
		-- The canvas first, as the engine lays it out before it reports the view on it (and as the scroll below).
		content.AbsoluteCanvasSize = roblox.Vector2.new(width, canvas)
		content.AbsoluteWindowSize = roblox.Vector2.new(width, window)
	end
	error(root.Name .. "'s list never settles")
end

-- `name` opened on the phone by the player who owns everything, and laid out as the engine lays it out.
local function openLaidOut(name: string, args: any?): any
	local built, height = Screens.open(name, {
		Phone = PHONE,
		Args = args,
		Profile = Screens.fullest,
		Entries = math.huge,
	})
	laidOut(built.Instance, height, PHONE[1] * height / PHONE[2])
	return built
end

-- Every screen and tab, as the player who owns everything opens it on the phone.
local function measureAll(): { Measured }
	local measured: { Measured } = {}
	for _, entry in ipairs(Screens.LIST) do
		for _, tab in ipairs(entry.Tabs or { "" }) do
			local built = openLaidOut(entry.Name, if tab ~= "" then { Tab = tab } else nil)
			table.insert(measured, {
				Label = entry.Name .. (if tab ~= "" then " (" .. tab .. ")" else ""),
				Count = shownUnder(built.Instance),
				Limit = if entry.Name == "BattlepassScreen" then BUDGET.MaxPassObjects else BUDGET.MaxScreenObjects,
			})
		end
	end
	local result = Screens.result({ Phone = PHONE, Profile = Screens.fullest })
	table.insert(
		measured,
		{ Label = "ResultScreen", Count = shownUnder(result.Instance), Limit = BUDGET.MaxScreenObjects }
	)
	return measured
end

-- What breaks the budget, one line per screen.
local function over(measured: { Measured }): { string }
	local found: { string } = {}
	for _, entry in ipairs(measured) do
		if entry.Count > entry.Limit then
			table.insert(
				found,
				("%s draws %d objects as it opens, over %d"):format(entry.Label, entry.Count, entry.Limit)
			)
		end
	end
	return found
end

-- The rows of the table "Objets par écran" in docs/PERFORMANCE.md: `| label | count | limit |`.
local function documented(): { [string]: number }
	local source = fs.readFile(PERFORMANCE)
	local section = string.match(source, "## Objets par écran.-\n(.-)\n## ")
	assert(section ~= nil, "PERFORMANCE.md has no section « Objets par écran »: this gate would check nothing")
	local rows: { [string]: number } = {}
	for label, count in string.gmatch(section :: string, "\n| `([%w%s%(%)]+)` | (%d+) |") do
		rows[label] = tonumber(count) :: number
	end
	return rows
end

describe("what a screen draws as it opens, counted", function()
	local measured = measureAll()

	it("holds every screen and every Shop tab to 400 on a phone, and the pass's road to 700", function()
		expect(#measured).toBe(13)
		expect(BUDGET.MaxScreenObjects).toBe(400)
		expect(BUDGET.MaxPassObjects).toBe(700)
		local found = over(measured)
		if #found > 0 then
			error(table.concat(found, "\n"))
		end
		for _, entry in ipairs(measured) do
			-- Counted, not vacuous: every screen draws something.
			expect(entry.Count).toBeGreaterThan(40)
		end
	end)

	it("is the table docs/PERFORMANCE.md prints", function()
		local rows = documented()
		for _, entry in ipairs(measured) do
			local written = rows[entry.Label]
			if written ~= entry.Count then
				error(
					("PERFORMANCE.md says %s for %s, which draws %d"):format(
						tostring(written),
						entry.Label,
						entry.Count
					)
				)
			end
		end
	end)

	it("fails a screen given three hundred frames more", function()
		local built = Screens.open("MenuScreen", { Phone = PHONE, Profile = Screens.fullest })
		local before =
			over({ { Label = "MenuScreen", Count = shownUnder(built.Instance), Limit = BUDGET.MaxScreenObjects } })
		expect(#before).toBe(0)
		for _ = 1, 300 do
			Engine.instance("Frame", built.Instance)
		end
		local after =
			over({ { Label = "MenuScreen", Count = shownUnder(built.Instance), Limit = BUDGET.MaxScreenObjects } })
		expect(#after).toBe(1)
	end)
end)

-- The lists that are built a chunk at a time (src/ui/Progressive.luau): the first chunk as the screen opens, more
-- while the view at rest at the top is not full, the next as a moved view comes within a window of its foot, and as
-- far as an item that must be there.
describe("a long list built as it is scrolled, run", function()
	-- A view `window` tall over a canvas `canvas` tall, scrolled to `at`, as the engine would lay it out.
	-- The canvas first: the engine lays the canvas out before it reports where the view stands on it.
	local function scroll(scroller: any, window: number, canvas: number, at: number)
		scroller.AbsoluteCanvasSize = roblox.Vector2.new(300, canvas)
		scroller.CanvasPosition = roblox.Vector2.new(0, at)
		scroller.AbsoluteWindowSize = roblox.Vector2.new(300, window)
	end

	it(
		"builds the Locker's next cards as the shelf nears its foot, each worn or not, and every one in the end",
		function()
			-- Something worn in every slot, so a card built late must say it is worn.
			local worn = 0
			local function wearing(today: number): any
				local data = Screens.fullest(today)
				local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
				for _, item in ipairs(CosmeticConfig.Items) do
					local key = CosmeticConfig.slotKey(item)
					if data.Cosmetics.Equipped[key] == nil then
						data.Cosmetics.Equipped[key] = item.Id
						worn += 1
					end
				end
				return data
			end
			local built = Screens.open("ShopScreen", { Phone = PHONE, Args = { Tab = "Locker" }, Profile = wearing })
			local content = built.Instance:FindFirstChild("Content", true)
			local function cards(): number
				local count = 0
				for _, part in ipairs(content:GetDescendants()) do
					if part.Name == "Item" and part:FindFirstChild("Preview") ~= nil then
						count += 1
					end
				end
				return count
			end
			local first = cards()
			expect(first).toBeGreaterThan(0)
			-- Far from the foot: nothing more.
			scroll(content, 300, 3000, 0)
			expect(cards()).toBe(first)
			-- Within a window of it: the next chunk.
			scroll(content, 300, 3000, 2500)
			expect(cards()).toBeGreaterThan(first)
			-- Scrolled to the foot again and again, the whole locker.
			for step = 1, 20 do
				scroll(content, 300, 3000 + step * 1000, 2500 + step * 1000)
			end
			local owned = #Screens.fullest(0).Cosmetics.Owned
			expect(cards()).toBe(owned)
			local unequip = 0
			for _, part in ipairs(content:GetDescendants()) do
				if part.Name == "Label" and part:IsA("TextLabel") and part.Text == "shop.unequip" then
					unequip += 1
				end
			end
			expect(worn).toBeGreaterThan(1)
			expect(unequip).toBe(worn)
		end
	)

	it("builds the leaderboard down to the player's own row before it scrolls there, and pins it until then", function()
		local built, _height, world =
			Screens.open("LeaderboardScreen", { Phone = PHONE, Entries = math.huge, Rank = 45 })
		local content = built.Instance:FindFirstChild("Content", true)
		local function rows(): number
			local count = 0
			for _, child in ipairs(content:GetChildren()) do
				if string.match(child.Name, "^Row%d+$") then
					count += 1
				end
			end
			return count
		end
		local first = rows()
		expect(first).toBeGreaterThan(0)
		-- Forty-fifth, below the rows built: not built yet, and pinned at the card's foot meanwhile.
		expect(content:FindFirstChild("Row45")).toBeNil()
		local footer = built.Instance:FindFirstChild("Footer", true)
		local pinned = footer:FindFirstChild("Row45", true)
		assert(pinned ~= nil, "the player's row is not pinned while it is not built")
		-- "Find me" builds down to it, and the page goes there on the next frame.
		pinned:FindFirstChild("FindMe").Activated:Fire()
		expect(content:FindFirstChild("Row45")).never.toBeNil()
		expect(rows()).toBeGreaterThan(first)
		world:advance(0.1)
	end)

	it("builds the Loadout's cards a few rows at a time", function()
		local built = Screens.open("LoadoutScreen", { Phone = PHONE, Profile = Screens.fullest })
		local content = built.Instance:FindFirstChild("Content", true)
		local function cards(): number
			local count = 0
			for _, child in ipairs(content:GetChildren()) do
				if child:IsA("GuiObject") and child:FindFirstChild("Recipe", true) ~= nil then
					count += 1
				end
			end
			return count
		end
		local first = cards()
		expect(first).toBeGreaterThan(0)
		expect(first).toBeLessThan(#Screens.fullest(0).Loadout.Slots)
		scroll(content, 300, 900, 700)
		expect(cards()).toBe(#Screens.fullest(0).Loadout.Slots)
		-- Every card of the Equipped tab, built late or not, is worn.
		for _, child in ipairs(content:GetChildren()) do
			if child:IsA("GuiObject") and child:FindFirstChild("Recipe", true) ~= nil then
				expect(child:FindFirstChild("Equipped", true).Visible).toBe(true)
			end
		end
	end)

	-- At rest at the top a list builds what fills its view and no more; the window ahead is for a view that moves.
	it("fills the view it opens on, and looks a window ahead only once the view moves", function()
		local built =
			Screens.open("ShopScreen", { Phone = PHONE, Args = { Tab = "Locker" }, Profile = Screens.fullest })
		local content = built.Instance:FindFirstChild("Content", true)
		local function cards(): number
			local count = 0
			for _, part in ipairs(content:GetDescendants()) do
				if part.Name == "Item" and part:FindFirstChild("Preview") ~= nil then
					count += 1
				end
			end
			return count
		end
		local first = cards()
		-- Taller than its view, at the top, the foot within a window: nothing more.
		scroll(content, 300, 500, 0)
		expect(cards()).toBe(first)
		-- A first chunk that does not fill the view (the canvas is the window): the next, and only it.
		scroll(content, 300, 300, 0)
		local filled = cards()
		expect(filled).toBeGreaterThan(first)
		scroll(content, 300, 700, 0)
		expect(cards()).toBe(filled)
		-- Moved down by a unit, the foot within a window of the view: the next again.
		scroll(content, 300, 600, 1)
		expect(cards()).toBeGreaterThan(filled)
	end)
end)

return nil
