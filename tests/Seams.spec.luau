--!strict
-- Where the slices of the colour pass meet (D-147, slice G). Slices A, B and C each held their own screens
-- to the spec; what none of them could see alone is two of them doing one thing two ways -- a badge counted
-- on the player's clock beside one counted on the server's. These rules hold the joins. The screens are
-- engine code Lune cannot run, so they are read.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CLAIMS = "src/ui/Claims.luau"
local CLAIMABLES = "src/shared/Pure/Claimables.luau"
local MENU = "src/ui/screens/MenuScreen.luau"
local DAILY = "src/ui/screens/DailyScreen.luau"
local SHOP = "src/ui/screens/ShopScreen.luau"

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

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
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

describe("a claim", function()
	it("is counted in one place, on the day the servers keep", function()
		-- Claims is the one caller of the pure count: every badge, seal and the daily reward's own opening go
		-- through it, so none of them can count on another clock or another context.
		local files = {}
		collect("src", files)
		local callers = {}
		for _, path in ipairs(files) do
			if path ~= CLAIMABLES and has(code(path), "Claimables.count(") then
				table.insert(callers, path)
			end
		end
		expect(#callers).toBe(1)
		expect(callers[1]).toBe(CLAIMS)
		-- The menu's tiles count as the HUD's Menu button and seals do, on the server's clock.
		expect(has(code(MENU), "Claims.count(data, workspace:GetServerTimeNow())")).toBe(true)
		-- And the screen they open agrees: its "today" is the server's, never the player's own clock.
		local daily = code(DAILY)
		expect(has(daily, "DailyStreak.dayIndex(workspace:GetServerTimeNow())")).toBe(true)
		expect(has(daily, "os.time(")).toBe(false)
	end)
end)

describe("the Folios in a chapter band", function()
	it("are one pill, whichever slice drew the screen", function()
		-- A screen that shows the balance shows it in FoliosPill: the same coin, count and count-up
		-- everywhere, rather than a copy of it that drifts.
		local screens = {}
		for _, entry in ipairs(fs.readDir("src/ui/screens")) do
			if string.match(entry, "Screen%.luau$") then
				table.insert(screens, "src/ui/screens/" .. entry)
			end
		end
		local showing = 0
		for _, path in ipairs(screens) do
			local source = code(path)
			if has(source, "Currency.Folios") then
				showing += 1
				if not has(source, "FoliosPill.new(") then
					error(path .. " shows the Folios without FoliosPill")
				end
			end
		end
		-- The Menu, the Shop, the Daily reward and the Quests: this gate checks something.
		expect(showing).toBeGreaterThanOrEqual(4)
	end)
end)

describe("a claim or a purchase the server never answers", function()
	it("is said, on every button that waits for one", function()
		-- Button gives up after Timing.PendingTimeoutSeconds and calls OnTimeout. Every screen that waits on a
		-- claim or a purchase then says common.pendingTimeout, or hands the timeout to the one that does:
		-- a silent button would read as a claim that worked.
		local files = {}
		collect("src/ui", files)
		local waiting = 0
		for _, path in ipairs(files) do
			for body in string.gmatch(code(path), "OnTimeout = function%(%)(.-)\n%s*end,") do
				waiting += 1
				if not has(body, '"common.pendingTimeout"') and not has(body, "props.OnTimeout()") then
					error(path .. " gives up on the server without saying so")
				end
			end
		end
		-- The Daily reward, the quest card and the Quests screen that words its timeout.
		expect(waiting).toBeGreaterThanOrEqual(3)
	end)
end)

describe("a tab", function()
	it("clicks when the player picks it, on every screen, and only then", function()
		-- Tabs makes no sound of its own (only Button does): each strip's OnSelect clicks.
		local screens = {}
		collect("src/ui/screens", screens)
		local strips = 0
		for _, path in ipairs(screens) do
			for body in string.gmatch(code(path), "OnSelect = function%(id: string%)(.-)\n%s*end,") do
				strips += 1
				if not has(body, 'play("UiClick")') then
					error(path .. " has a tab strip that switches in silence")
				end
			end
		end
		-- The Shop, the Loadout, the Leaderboard, the Settings and its quality strip.
		expect(strips).toBeGreaterThanOrEqual(5)
		-- Select fires OnSelect as a click would, and the Shop switches tabs itself (Open's Tab, Get Folios):
		-- each of those is marked as the screen's own, which keeps it quiet.
		local shop = code(SHOP)
		local selects = count(shop, "tabs:Select(")
		expect(selects).toBeGreaterThanOrEqual(2)
		local _, marked = string.gsub(shop, "switching = true\n%s*tabs:Select%(", "")
		expect(marked).toBe(selects)
		expect(has(shop, 'if not switching then\n\t\t\t\tdeps.SoundController.play("UiClick")')).toBe(true)
	end)
end)
