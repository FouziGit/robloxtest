--!strict
-- The screens a player opens to play and to collect (D-147, slice A of the colour pass): the menu's tiles,
-- the play cards, the shop, the battle pass, the daily reward. They are engine code Lune cannot run, so what
-- can regress without a sound is held by reading them: two tiles of one colour side by side, a purchase made
-- on one tap, a burst of claims the server would refuse, a red button where nothing is dangerous.
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local TokenBucket = require("../src/shared/Util/TokenBucket")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MENU = "src/ui/screens/MenuScreen.luau"
local PLAY = "src/ui/screens/PlayScreen.luau"
local SHOP = "src/ui/screens/ShopScreen.luau"
local PURCHASE = "src/ui/screens/shop/Purchase.luau"
local SHELVES = "src/ui/screens/shop/Shelves.luau"
local PASS = "src/ui/screens/BattlepassScreen.luau"
local PASS_CELL = "src/ui/screens/pass/Cell.luau"
local PASS_TRACK = "src/ui/screens/pass/Track.luau"
local REMOTES = "src/shared/Remotes.luau"
local DAILY = "src/ui/screens/DailyScreen.luau"
-- The screens of this slice and their parts, for the rules every one of them keeps.
local SCREENS = { MENU, PLAY, SHOP, PURCHASE, SHELVES, PASS, PASS_CELL, PASS_TRACK, DAILY }
-- How much sooner than it was sent a claim may reach the server, one after another, over a real network.
local NETWORK_JITTER = 0.05
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

describe("the Play tile's ribbon", function()
	it("says Ranked because every mode the queue offers is ranked, as the ranked tag it matches does", function()
		-- The tile's ribbon names no mode: it is true only while each one is ranked.
		expect(#MatchConfig.ModeOrder).toBeGreaterThan(0)
		for _, mode in ipairs(MatchConfig.ModeOrder) do
			local def = MatchConfig.Modes[mode]
			assert(def ~= nil, ("the queue offers %s, which is no mode"):format(mode))
			if def.Ranked ~= true then
				error(("%s is not ranked: the Play tile's ribbon would say otherwise"):format(mode))
			end
		end
		expect(string.find(code(MENU), 'ribbon.Text = t("queue.ranked")', 1, true)).never.toBeNil()
		-- The play card's tag is the same ribbon lying flat: ink, the sheet's word, corners of 8.
		local play = code(PLAY)
		expect(tonumber(string.match(play, "local TAG_CORNER = (%d+)\n"))).toBe(8)
		expect(string.find(play, "tag.BackgroundColor3 = Theme.Colors.Plate", 1, true)).never.toBeNil()
		expect(string.find(play, "tag.TextColor3 = Theme.Colors.PanelRaised", 1, true)).never.toBeNil()
		expect(string.find(play, "Theme.corner(tag, TAG_CORNER)", 1, true)).never.toBeNil()
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
		-- Nothing but the sheet's purchase sends it.
		expect(count(folded(SHOP), '"BuyCosmetic"')).toBe(0)
		expect(count(folded(SHELVES), '"BuyCosmetic"')).toBe(0)
		local purchase = folded(PURCHASE)
		expect(count(purchase, 'fire("BuyCosmetic"')).toBe(1)
		local buy = string.match(purchase, "local function buy%(pending: Pending%)(.-) end local function ")
		assert(buy ~= nil, "the purchase has no buy(pending): this gate would check nothing")
		expect(string.find(buy :: string, 'fire("BuyCosmetic", pending.CosmeticId)', 1, true)).never.toBeNil()
		-- And the one way to it is the sheet's confirmation.
		expect(count(purchase, "buy(pending)")).toBe(1)
		expect(string.find(purchase, "OnConfirm = function() buy(pending) end", 1, true)).never.toBeNil()
		-- A card's price asks.
		expect(string.find(folded(SHOP), "purchases:Ask(card.Entry)", 1, true)).never.toBeNil()
	end)

	it("offers a Robux product or pass only when it exists on Roblox", function()
		local shelves = folded(SHELVES)
		-- The packs and the products go through the shop's own rule (Reach.spec pins it), the passes check
		-- their own id.
		expect(string.find(folded(SHOP), "RobuxOffered = robuxOffered,", 1, true)).never.toBeNil()
		expect(string.find(shelves, "button:SetDisabled(not context.RobuxOffered(key))", 1, true)).never.toBeNil()
		expect(string.find(shelves, "return pass ~= nil and pass.Id ~= 0", 1, true)).never.toBeNil()
		expect(string.find(shelves, "return context.RobuxOffered(offer.Key)", 1, true)).never.toBeNil()
		expect(string.find(shelves, "offer.Button:SetDisabled(not offerOpen(context, data, offer))", 1, true)).never.toBeNil()
		-- The pass's own buttons: the premium track and the tier skip.
		local pass = folded(PASS)
		local offered = string.match(pass, "local function productOffered%(productKey: string%): boolean (.-) end")
		expect(offered).toBe(
			"local product = MonetizationConfig.Products[productKey] return product ~= nil and product.Id ~= 0"
		)
		expect(string.find(pass, 'premiumButton:SetDisabled(not productOffered("PremiumPass"))', 1, true)).never.toBeNil()
		expect(string.find(pass, 'skipButton:SetDisabled(not productOffered("TierSkip5"))', 1, true)).never.toBeNil()
	end)

	it("opens on the tab it is asked for, and on no tab it does not have", function()
		local tabs = string.match(code(SHOP), "local TAB_ORDER[^=]*= (%b{})")
		assert(tabs ~= nil, "the shop names no TAB_ORDER: this gate would check nothing")
		local known: { [string]: boolean } = {}
		for id in string.gmatch(tabs :: string, '"(%w+)"') do
			known[id] = true
		end
		-- Every tab anything asks for: the Menu's "+", the sheet of a player short of Folios.
		local asked = 0
		for id in string.gmatch(code(MENU), '{ Tab = "(%w+)" }') do
			asked += 1
			if not known[id] then
				error(("the menu opens the shop on %s, a tab it does not have"):format(id))
			end
		end
		for id in string.gmatch(code(SHOP), 'tabs:Select%("(%w+)"%)') do
			asked += 1
			if not known[id] then
				error(("the shop selects %s, a tab it does not have"):format(id))
			end
		end
		expect(asked >= 2).toBe(true)
		expect(string.find(code(SHOP), "TAB_KEYS[args.Tab] ~= nil", 1, true)).never.toBeNil()
	end)
end)

describe("the battle pass", function()
	it("claims through a mirror of the remote's own bucket, and nowhere else", function()
		local pass = folded(PASS)
		local remote = string.match(pass, 'local CLAIM_REMOTE = "(%w+)"')
		assert(remote ~= nil, "the pass names no CLAIM_REMOTE: this gate would check nothing")
		expect(string.find(pass, "local CLAIM_RATE = Remotes.Definitions[CLAIM_REMOTE].Rate", 1, true)).never.toBeNil()
		expect(string.find(pass, "TokenBucket.new(CLAIM_RATE.Capacity, CLAIM_RATE.Refill, os.clock())", 1, true)).never.toBeNil()
		-- One send, and only once the mirror has given its token.
		expect(count(pass, "fire(CLAIM_REMOTE")).toBe(1)
		expect(
			string.find(
				pass,
				"if TokenBucket.tryTake(bucket, now) then lastSent = now deps.RemoteClient.fire(CLAIM_REMOTE,",
				1,
				true
			)
		).never.toBeNil()
		for _, path in ipairs(SCREENS) do
			if path ~= PASS and string.find(code(path), remote :: string, 1, true) ~= nil then
				error(("%s sends %s past the pass's pacing"):format(path, remote :: string))
			end
		end
	end)

	it("never sends a claim the server's bucket would refuse, even when the network bunches them", function()
		local pass = code(PASS)
		local spacing = tonumber(string.match(pass, "local CLAIM_SPACING = ([%d%.]+)"))
		local margin = tonumber(string.match(pass, "local CLAIM_MARGIN = ([%d%.]+)"))
		assert(spacing ~= nil and margin ~= nil, "the pass names no CLAIM_SPACING or CLAIM_MARGIN")
		local rate = string.match(code(REMOTES), "ClaimBattlepassReward = %b{}")
		assert(rate ~= nil, "Remotes has no ClaimBattlepassReward")
		local capacity = tonumber(string.match(rate :: string, "Capacity = (%d+)"))
		local refill = tonumber(string.match(rate :: string, "Refill = ([%d%.]+)"))
		assert(capacity ~= nil and refill ~= nil, "ClaimBattlepassReward has no rate")
		-- The screen's schedule for fifty claims at once (its pump), and the server's bucket receiving each
		-- one NETWORK_JITTER early every other time.
		local mirror = TokenBucket.new(capacity :: number, refill :: number, 0)
		local server = TokenBucket.new(capacity :: number, refill :: number, 0)
		local now, last = 0, -math.huge
		for index = 1, 50 do
			-- The pump: a spacing after the last send, and no sooner than the mirror holds a token and its margin.
			local wait = math.max(0, (spacing :: number) - (now - last))
			local shortfall = 1 + (margin :: number) - TokenBucket.available(mirror, now)
			if shortfall > 0 then
				wait = math.max(wait, shortfall / (refill :: number))
			end
			now += wait
			assert(TokenBucket.tryTake(mirror, now), "the mirror refused its own schedule")
			last = now
			local arrival = if index % 2 == 0 then now - NETWORK_JITTER else now
			if not TokenBucket.tryTake(server, arrival) then
				error(("claim %d, sent at %.2fs, would be refused as abuse"):format(index, now))
			end
		end
	end)
end)

describe("the daily reward", function()
	it("warns of a streak only while it is whole and worth keeping, in the green of what is kept", function()
		local daily = folded(DAILY)
		expect(tonumber(string.match(daily, "local AT_RISK_STREAK = (%d+)"))).toBe(2)
		expect(
			string.find(
				daily,
				"local atRisk = evaluation.CanClaim and not evaluation.Broken and daily.Streak >= AT_RISK_STREAK",
				1,
				true
			)
		).never.toBeNil()
		-- Nothing is lost yet: the line is the success ink, never the danger one.
		expect(string.find(daily, "atRiskLine.TextColor3 = Theme.Colors.Success", 1, true)).never.toBeNil()
		expect(string.find(daily, "Theme.Colors.Danger", 1, true)).toBeNil()
	end)

	it("claims once and waits for the profile to show it", function()
		local daily = folded(DAILY)
		expect(count(daily, 'fire("ClaimDaily")')).toBe(1)
		expect(
			string.find(
				daily,
				'if waiting then return end waiting = true claimButton:SetPending(true) deps.RemoteClient.fire("ClaimDaily")',
				1,
				true
			)
		).never.toBeNil()
		-- The stamp comes from the profile, not from the press.
		expect(string.find(daily, 'if waiting and before ~= nil and before.State == "Past" then', 1, true)).never.toBeNil()
	end)
end)
