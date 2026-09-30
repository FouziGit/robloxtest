--!strict
-- What each screen draws as it opens, counted (E11-S5, D-XXX), run (tests/engine.luau, tests/screens.luau): the ten
-- screens and each tab of the Shop, on an 844 x 390 phone at the touch floor, for a player who owns everything
-- they list -- every glyph, every cosmetic, every pass, the pass at its last tier, the leaderboard's whole top --
-- against ThemeConfig.Budget: a screen at most MaxScreenObjects, the pass's road at most MaxPassObjects.
--
-- Nothing counted them: a locker of everything drew 1 282 objects, the leaderboard's fifty rows 684 and ten
-- equipped glyphs 510. Those lists are built a chunk at a time now (src/ui/Progressive.luau). A GuiObject counted
-- is one the engine lays out and draws, as tests/HudBudget.spec.luau counts the HUD: shown, with every ancestor
-- up to the screen. The table of docs/PERFORMANCE.md is these counts, and is held to them here.
local Engine = require("./engine")
local Harness = require("./harness")
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

-- Every screen and tab, as the player who owns everything opens it on the phone.
local function measureAll(): { Measured }
	local measured: { Measured } = {}
	for _, entry in ipairs(Screens.LIST) do
		for _, tab in ipairs(entry.Tabs or { "" }) do
			local built = Screens.open(entry.Name, {
				Phone = PHONE,
				Args = if tab ~= "" then { Tab = tab } else nil,
				Profile = Screens.fullest,
				Entries = math.huge,
			})
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

-- The lists that are built a chunk at a time (src/ui/Progressive.luau): the first chunk as the screen opens, the
-- next as the view comes within a window of its foot, and as far as an item that must be there.
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
end)

return nil
