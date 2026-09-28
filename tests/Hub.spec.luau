--!strict
-- The hub, read (D-128). The boards stood blank -- the ladder looked for a part named like the board's
-- model -- and would have been unreadable had they filled (fifteen-pixel rows, a third of a stud); the
-- terminal and the kiosk looked like the way in to a match and the shop and did nothing.
local GameConfig = require("../src/shared/Config/GameConfig")
local Gate = require("./gate")
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local PortalConfig = require("../src/shared/Config/PortalConfig")
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

-- Whitespace folded to one space, and none just inside a bracket, so a call reads the same however the
-- formatter wrapped it.
local function tight(text: string): string
	return (text:gsub("%s+", " "):gsub("%( ", "("):gsub(" %)", ")"))
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
		local literals = {
			'"LeaderboardBoard_"',
			'"QueueTerminal"',
			'"ShopKiosk"',
			'"Hub"',
			'"Entries"',
			'"BattlegroundPortal"',
			'"BossPortal"',
			'"PortalSeal"',
		}
		for _, path in ipairs({ HUB, LADDER, SIGNS }) do
			local source = code(path)
			for _, literal in ipairs(literals) do
				if source:find(literal, 1, true) ~= nil then
					error(
						("%s spells %s instead of reading WorldConfig.HubAnchors or PortalConfig"):format(path, literal)
					)
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
		-- Each gate under its anchor, leading where its name says.
		local folded = tight(hub)
		for _, use in ipairs({
			'PortalGate.build(folder, ANCHORS.BattlegroundPortal, layout.BattlegroundPortalCFrame, "Battleground")',
			'PortalGate.build(folder, ANCHORS.BossPortal, layout.BossPortalCFrame, "WorldBoss")',
		}) do
			expect(folded:find(use, 1, true)).never.toBe(nil)
		end
		expect(ANCHORS.Folder).toBe("Hub")
	end)

	it("names everything it builds once", function()
		local seen: { [string]: string } = {}
		for key, name in pairs(ANCHORS) do
			if type(name) == "string" then
				if seen[name] ~= nil then
					error(("HubAnchors.%s and HubAnchors.%s are both %q"):format(seen[name], key, name))
				end
				seen[name] = key
			end
		end
		-- The two portal gates stand in the hub's folder beside the rest.
		expect(seen[ANCHORS.BattlegroundPortal]).toBe("BattlegroundPortal")
		expect(seen[ANCHORS.BossPortal]).toBe("BossPortal")
	end)
end)

-- The two portal gates (D-130), placed from PortalConfig.Hub against the hub's own numbers: HubService needs
-- an engine to require, so the numbers it places things by are read from its source.
describe("the hub's portal gates", function()
	local function hubNumber(pattern: string): number
		local value = string.match(code(HUB), pattern)
		if value == nil then
			error(("%s does not match %s: this gate would check nothing"):format(HUB, pattern))
		end
		return tonumber(value) :: number
	end

	it(
		"stand on the platform's empty north, clear of each other, the training ground, the furniture and the ruling",
		function()
			local hub = code(HUB)
			-- The training ground and the furniture ring, as HubService computes them.
			local training = GameConfig.Enemy.DummyRingRadius + GameConfig.Spawn.SafeZoneMarginStuds
			expect(
				hub:find(
					"local TRAINING_RADIUS_STUDS = GameConfig.Enemy.DummyRingRadius + GameConfig.Spawn.SafeZoneMarginStuds",
					1,
					true
				)
			).never.toBe(nil)
			local props = training + hubNumber("\nlocal PROP_RING_RADIUS_STUDS = TRAINING_RADIUS_STUDS %+ (%d+)\n")
			local ruling = hubNumber("\nlocal PLATFORM_SIZE_STUDS = (%d+)\n") / 2 - WorldConfig.Hub.RuleInsetStuds
			-- The terminal at angle 0 and the kiosk at pi, both on the furniture ring.
			expect(hub:find("QueueCFrame = facingCenter(ringPosition(0, PROP_RING_RADIUS_STUDS, 0))", 1, true)).never.toBe(
				nil
			)
			expect(hub:find("ShopCFrame = facingCenter(ringPosition(math.pi, PROP_RING_RADIUS_STUDS, 0))", 1, true)).never.toBe(
				nil
			)
			local furniture = { { props, 0 }, { -props, 0 } }

			local radius = PortalConfig.Hub.RingRadiusStuds
			local footprint = Gate.footprint()
			local bases: { { number } } = {}
			for _, side in ipairs({ -1, 1 }) do
				local angle = -math.pi / 2 + side * PortalConfig.Hub.AngleOffsetRadians
				local x, z = math.cos(angle) * radius, math.sin(angle) * radius
				table.insert(bases, { x, z })
				-- Every corner of the gate inside the ruling; its rim's inner edge outside the training ground.
				for _, corner in ipairs(Gate.corners(x, z, -x / radius, -z / radius)) do
					expect(math.sqrt(corner[1] ^ 2 + corner[2] ^ 2)).toBeLessThan(ruling)
				end
				expect(radius - footprint.Front).toBeGreaterThan(training)
				for _, prop in ipairs(furniture) do
					local apart = math.sqrt((x - prop[1]) ^ 2 + (z - prop[2]) ^ 2)
					expect(apart).toBeGreaterThanOrEqual(PortalConfig.ZoneRadiusStuds + 12)
				end
			end
			local between = math.sqrt((bases[1][1] - bases[2][1]) ^ 2 + (bases[1][2] - bases[2][2]) ^ 2)
			expect(between).toBeGreaterThan(2 * footprint.RimRadius)
			-- Either side of the north, the empty side of the platform (the boards stand south, at pi / 2).
			expect(bases[1][1] < 0 and bases[2][1] > 0).toBe(true)
			expect(bases[1][2] < 0 and bases[2][2] < 0).toBe(true)
		end
	)

	it("are placed where the case above measured them, facing the spawn", function()
		-- The clearance above is computed from PortalConfig.Hub; this is HubService placing them by it, so the
		-- two cannot drift apart. facingCenter points a base's LookVector at the spawn, as Gate.corners assumes.
		local layout = tight(body(HUB, "local function computeLayout("))
		expect(code(HUB):find("\nlocal PORTALS = PortalConfig.Hub\n", 1, true)).never.toBe(nil)
		for _, placement in ipairs({
			"BattlegroundPortalCFrame = facingCenter(ringPosition(-math.pi / 2 - PORTALS.AngleOffsetRadians, PORTALS.RingRadiusStuds, 0))",
			"BossPortalCFrame = facingCenter(ringPosition(-math.pi / 2 + PORTALS.AngleOffsetRadians, PORTALS.RingRadiusStuds, 0))",
		}) do
			expect(layout:find(placement, 1, true)).never.toBe(nil)
		end
		local facing = body(HUB, "local function facingCenter(")
		expect(facing:find("CFrame.lookAt(position, Vector3.new(0, position.Y, 0))", 1, true)).never.toBe(nil)
	end)

	it("are drawn with the hub's own seal, from the helpers they share", function()
		-- One way to draw a part, a disc and an emblem (World/Draw): the hub keeps no copy of any.
		local hub = code(HUB)
		expect(hub:find("local function flatDisc(", 1, true)).toBe(nil)
		expect(hub:find("local function buildEmblem(", 1, true)).toBe(nil)
		expect(hub:find('Instance.new("Part")', 1, true)).toBe(nil)
		local folded = tight(hub)
		for _, use in ipairs({
			'Draw.flatDisc("HubSpawnRim", rimDiameter, Vector3.zero, LADDER.SealRim,',
			'Draw.flatDisc("HubSpawnSeal", SPAWN_SIZE_STUDS.X, Vector3.zero, LADDER.Seal,',
			'Draw.flatDisc("TrainingArea", TRAINING_RADIUS_STUDS * 2, Vector3.zero, LADDER.Training,',
			"Draw.emblem(panel, accent, bars)",
			"local newPart = Draw.part",
		}) do
			expect(folded:find(use, 1, true)).never.toBe(nil)
		end
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

-- The portal gates' words (D-130): every gate names where its circle leads and what it asks, in the reader's
-- language, wherever it stands -- the hub's, the Battleground's camp, each copy of the Erasure's arena -- found by
-- its seal's tag, so a gate built anywhere is worded without a list of places. No prompt and no remote: the server
-- moves whoever stands in the circle.
describe("the portal gates' words", function()
	it("word every seal by the zone it names, the way PortalService counts it", function()
		local seal = body(SIGNS, "local function wordSeal(")
		for _, line in ipairs({
			"local id = seal:GetAttribute(PortalConfig.SealAttribute)",
			'local zone = if type(id) == "string" then PortalConfig.Zones[id] else nil',
			"namePlate(seal, localize.t(zone.NameKey), localize.t(zone.HintKey), SEAL_PLATE_STUDS_ABOVE, trove)",
		}) do
			if seal:find(line, 1, true) == nil then
				error("wordSeal no longer does: " .. line)
			end
		end
		expect(seal:find("ProximityPrompt", 1, true)).toBe(nil)
		expect(seal:find("remoteClient", 1, true)).toBe(nil)
		-- In the Workspace only, as PortalService: an arena template's seal is no circle, and has no words.
		expect(
			body(SIGNS, "local function onSealAdded("):find(
				'if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) and sealSigns[instance] == nil then wordSeal(instance) end',
				1,
				true
			)
		).never.toBe(nil)
		expect(body(SIGNS, "local function unwordSeal("):find("trove:Destroy()", 1, true)).never.toBe(nil)
	end)

	it("follows the seals' tag as they come and go, and the ones already there", function()
		local start = body(SIGNS, "function HubSignsController.Start(")
		for _, line in ipairs({
			"CollectionService:GetInstanceAddedSignal(PortalConfig.SealTag):Connect(onSealAdded)",
			"CollectionService:GetInstanceRemovedSignal(PortalConfig.SealTag):Connect(onSealRemoved)",
			"for _, seal in ipairs(CollectionService:GetTagged(PortalConfig.SealTag)) do onSealAdded(seal) end",
		}) do
			if start:find(line, 1, true) == nil then
				error("HubSignsController.Start no longer does: " .. line)
			end
		end
	end)

	it("sets one plate the pedestals and the gates share, over the gate's lintel", function()
		local pedestal = body(SIGNS, "local function wordPedestal(")
		expect(pedestal:find("namePlate(panel, name, nil, PLATE_STUDS_ABOVE, trove)", 1, true)).never.toBe(nil)
		local plate = body(SIGNS, "local function namePlate(")
		expect(plate:find("billboard.StudsOffsetWorldSpace = Vector3.new(0, above, 0)", 1, true)).never.toBe(nil)
		expect(plate:find('local line = textLabel("Hint", hint,', 1, true)).never.toBe(nil)
		-- Above the lintel's top (WorldConfig.Portal), read from the seal on the floor at the gate's foot.
		local above = tonumber(string.match(code(SIGNS), "\nlocal SEAL_PLATE_STUDS_ABOVE = ([%d%.]+)\n"))
		assert(above ~= nil, "HubSignsController has no SEAL_PLATE_STUDS_ABOVE")
		expect(above).toBeGreaterThan(WorldConfig.Portal.PostStuds[2] + WorldConfig.Portal.LintelStuds)
	end)
end)
