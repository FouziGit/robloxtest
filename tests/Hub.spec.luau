--!strict
-- The hub, read (D-128). The boards stood blank -- the ladder looked for a part named like the board's
-- model -- and would have been unreadable had they filled (fifteen-pixel rows, a third of a stud); the
-- terminal and the kiosk looked like the way in to a match and the shop and did nothing.
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local HUB = "src/server/Services/HubService.luau"
local LADDER = "src/server/Services/LeaderboardService.luau"
local SIGNS = "src/client/Controllers/HubSignsController.luau"
local BOARD = WorldConfig.HubBoard
local ANCHORS = WorldConfig.HubAnchors

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
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

describe("a hub board", function()
	it("fits its title and its rows on its panel", function()
		local height = BOARD.PanelStuds[2] * BOARD.PixelsPerStud
		local title = BOARD.TitleBand * height
		local rows = BOARD.Rows * BOARD.RowPixels + (BOARD.Rows - 1) * BOARD.RowGapPixels
		expect(title + 2 * BOARD.PaddingPixels + rows <= height).toBe(true)
		expect(BOARD.TitlePixels <= title).toBe(true)
		expect(BOARD.TextPixels <= BOARD.RowPixels).toBe(true)
	end)

	it("writes a line tall enough to read from across the hub", function()
		expect(BOARD.TextPixels / BOARD.PixelsPerStud >= 0.75).toBe(true)
		expect(BOARD.TitlePixels / BOARD.PixelsPerStud >= 1).toBe(true)
	end)

	it("is filled through the row container the hub hands over, not found by a name", function()
		local render = body(LADDER, "renderBoard = function(")
		expect(render:find("local frame = hub.getLeaderboardEntries(boardId)", 1, true)).never.toBe(nil)
		expect(render:find("if index > BOARD.Rows then break end", 1, true)).never.toBe(nil)
		expect(code(LADDER):find("hub = deps.Hub", 1, true)).never.toBe(nil)
	end)

	it("is found by every reader under the names in one contract", function()
		for _, path in ipairs({ HUB, LADDER, SIGNS }) do
			local source = code(path)
			for _, literal in ipairs({ '"LeaderboardBoard_"', '"QueueTerminal"', '"ShopKiosk"', '"Hub"', '"Entries"' }) do
				if source:find(literal, 1, true) ~= nil then
					error(("%s spells %s instead of reading WorldConfig.HubAnchors"):format(path, literal))
				end
			end
		end
		local hub = code(HUB)
		for _, use in ipairs({
			"model.Name = ANCHORS.BoardPrefix .. board.BoardId",
			"newPart(ANCHORS.Panel, BOARD_PANEL_SIZE_STUDS",
			"gui.Name = ANCHORS.BoardGui",
			"entries.Name = ANCHORS.Entries",
			"buildPedestal(folder, ANCHORS.Queue,",
			"buildPedestal(folder, ANCHORS.Shop,",
		}) do
			expect(hub:find(use, 1, true)).never.toBe(nil)
		end
		expect(ANCHORS.Folder).toBe("Hub")
	end)
end)

describe("the hub's words", function()
	it("titles every board and says when it is empty", function()
		local board = body(SIGNS, "local function wordBoard(")
		expect(
			board:find(
				'localize.t("hub.board.title", { board = localize.t("leaderboard.board." .. boardId) })',
				1,
				true
			)
		).never.toBe(nil)
		expect(board:find('localize.t("leaderboard.empty")', 1, true)).never.toBe(nil)
		expect(board:find('empty.Visible = entries:FindFirstChildWhichIsA("Frame") == nil', 1, true)).never.toBe(nil)
		expect(board:find("surface.PixelsPerStud = BOARD.PixelsPerStud", 1, true)).never.toBe(nil)
	end)

	it("opens the Play screen at the terminal and the Shop at the kiosk", function()
		local hub = body(SIGNS, "local function wordHub(")
		expect(hub:find('wordPedestal, folder, ANCHORS.Queue, "hub.queue.name", "queue.title", "Play", trove', 1, true)).never.toBe(
			nil
		)
		expect(hub:find('wordPedestal, folder, ANCHORS.Shop, "shop.title", "hub.prompt.open", "Shop", trove', 1, true)).never.toBe(
			nil
		)
		local pedestal = body(SIGNS, "local function wordPedestal(")
		expect(pedestal:find("menuController.open(screen)", 1, true)).never.toBe(nil)
	end)

	it("prompts only while its key is free", function()
		local refresh = body(SIGNS, "local function refreshPrompts(")
		expect(refresh:find("local live = not inputController.isSuspended() and not promptKeyTaken()", 1, true)).never.toBe(
			nil
		)
		local taken = body(SIGNS, "local function promptKeyTaken(")
		expect(taken:find("data.Settings.Keyboard", 1, true)).never.toBe(nil)
		expect(taken:find("data.Settings.Gamepad", 1, true)).never.toBe(nil)
		local pedestal = body(SIGNS, "local function wordPedestal(")
		expect(pedestal:find("if not menuController.isOpen() then menuController.open(screen) end", 1, true)).never.toBe(
			nil
		)
		expect(code(SIGNS):find("inputController.SuspendedChanged:Connect(refreshPrompts)", 1, true)).never.toBe(nil)
	end)

	it("prompts on keys no action already owns", function()
		for action, key in pairs(InputConfig.DefaultKeyboard) do
			if key == InputConfig.HubPrompt.Keyboard then
				error(("the hub prompt's key %s is %s's"):format(key, action))
			end
		end
		for action, button in pairs(InputConfig.DefaultGamepad) do
			if button == InputConfig.HubPrompt.Gamepad then
				error(("the hub prompt's button %s is %s's"):format(button, action))
			end
		end
	end)
end)
