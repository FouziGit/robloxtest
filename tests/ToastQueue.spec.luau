--!strict
-- The toast lane's queue (D-147): how many messages show at once, which one falls off a full queue, how long
-- each stays, and the value kinds a fight holds back until the player is out of it (rule 11).
local Harness = require("./harness")
local PortalConfig = require("../src/shared/Config/PortalConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local ToastQueue = require("../src/shared/Pure/ToastQueue")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local TIMING = ThemeConfig.Timing.Toast
local HUD = "src/client/Controllers/HudController.luau"
local TRAVEL = "src/client/Controllers/TravelController.luau"
local TOAST = "src/ui/components/Toast.luau"

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

-- The body of the local function or the function `header` in `source`, up to its closing `end`, folded.
local function body(source: string, header: string): string
	local start = string.find(source, header, 1, true)
	assert(start ~= nil, ("no %s: this gate would check nothing"):format(header))
	local finish = string.find(source, "\nend\n", start :: number, true)
	return (string.gsub(string.sub(source, start :: number, finish or #source), "%s+", " "))
end

-- The keys of the table literal `name` in `source`.
local function keysOf(source: string, name: string): { [string]: boolean }
	local block = string.match(source, "local " .. name .. ": { %[string%]: boolean } = (%b{})")
	assert(block ~= nil, ("no table %s: this gate would check nothing"):format(name))
	local keys: { [string]: boolean } = {}
	for key in string.gmatch(block :: string, '%["([%w%.]+)"%] = true') do
		keys[key] = true
	end
	for key in string.gmatch(block :: string, "(%w+) = true") do
		keys[key] = true
	end
	return keys
end

-- Every Strings key the server sends as a Notify.
local function serverKeys(): { [string]: boolean }
	local keys: { [string]: boolean } = {}
	local function scan(directory: string)
		for _, entry in ipairs(fs.readDir(directory)) do
			local path = directory .. "/" .. entry
			if fs.isDir(path) then
				scan(path)
			elseif string.match(entry, "%.luau$") then
				local source = stripComments(fs.readFile(path))
				for key in string.gmatch(source, 'notify%.send%(%s*[%w_%.]+,%s*"([%w%.]+)"') do
					keys[key] = true
				end
			end
		end
	end
	scan("src/server")
	return keys
end

local function entry(kind: string, text: string?): ToastQueue.Entry
	return { Kind = kind, Text = text or kind }
end

-- Every message the queue presents from now until it has nothing presentable left, each finished at once.
local function drain(queue: ToastQueue.Queue): { string }
	local shown: { string } = {}
	while true do
		local next = ToastQueue.take(queue)
		if next == nil then
			return shown
		end
		table.insert(shown, next.Text)
		ToastQueue.finish(queue)
	end
end

describe("the toast queue", function()
	it("never shows more than its lane holds, and frees a place when a message leaves", function()
		local queue = ToastQueue.new(2, 8)
		for index = 1, 4 do
			expect(ToastQueue.push(queue, entry("Success", "m" .. index))).toBe(true)
		end
		expect((ToastQueue.take(queue) :: ToastQueue.Entry).Text).toBe("m1")
		expect((ToastQueue.take(queue) :: ToastQueue.Entry).Text).toBe("m2")
		expect(ToastQueue.take(queue)).toBeNil()
		ToastQueue.finish(queue)
		expect((ToastQueue.take(queue) :: ToastQueue.Entry).Text).toBe("m3")
		expect(ToastQueue.take(queue)).toBeNil()
		-- A fight shows fewer at once; the hub more.
		ToastQueue.setMaxVisible(queue, 3)
		expect((ToastQueue.take(queue) :: ToastQueue.Entry).Text).toBe("m4")
	end)

	it("drops the oldest Info when full, so a refusal never falls off behind the chatter", function()
		local queue = ToastQueue.new(1, 3)
		ToastQueue.push(queue, entry("Error", "refused"))
		ToastQueue.push(queue, entry("Info", "chatter"))
		ToastQueue.push(queue, entry("Success", "claimed"))
		expect(ToastQueue.push(queue, entry("Error", "failed"))).toBe(true)
		expect(drain(queue)).toEqual({ "refused", "claimed", "failed" })
	end)

	it("drops the oldest of anything for a message that matters, when no Info is left to drop", function()
		local queue = ToastQueue.new(1, 2)
		ToastQueue.push(queue, entry("Success", "first"))
		ToastQueue.push(queue, entry("Error", "second"))
		expect(ToastQueue.push(queue, entry("Reward", "third"))).toBe(true)
		expect(drain(queue)).toEqual({ "second", "third" })
	end)

	it("refuses a new Info into a full queue of Success and Error", function()
		local queue = ToastQueue.new(1, 2)
		ToastQueue.push(queue, entry("Success", "kept"))
		ToastQueue.push(queue, entry("Error", "also kept"))
		expect(ToastQueue.push(queue, entry("Info", "refused"))).toBe(false)
		expect(drain(queue)).toEqual({ "kept", "also kept" })
	end)

	it("holds the value kinds in a fight and releases them, in order, once out of it", function()
		local queue = ToastQueue.new(3, 8)
		ToastQueue.hold(queue, { Reward = true, Celebrate = true })
		ToastQueue.push(queue, entry("Celebrate", "level"))
		ToastQueue.push(queue, entry("Info", "info"))
		ToastQueue.push(queue, entry("Reward", "folios"))
		ToastQueue.push(queue, entry("Celebrate", "quest"))
		-- Only what a fight may show goes through.
		expect(drain(queue)).toEqual({ "info" })
		expect(#queue.Pending).toBe(3)
		ToastQueue.hold(queue, {})
		expect(drain(queue)).toEqual({ "level", "folios", "quest" })
	end)

	it("presents nothing while paused, and everything that waited, in order, once resumed", function()
		local queue = ToastQueue.new(3, 8)
		ToastQueue.pause(queue, true)
		ToastQueue.push(queue, entry("Info", "first"))
		ToastQueue.push(queue, entry("Error", "second"))
		expect(ToastQueue.take(queue)).toBeNil()
		expect(#queue.Pending).toBe(2)
		ToastQueue.pause(queue, false)
		expect(drain(queue)).toEqual({ "first", "second" })
	end)

	it("keeps what it holds apart from the table it was given", function()
		local queue = ToastQueue.new(3, 8)
		local kinds = { Reward = true }
		ToastQueue.hold(queue, kinds)
		kinds.Reward = nil
		ToastQueue.push(queue, entry("Reward", "folios"))
		expect(ToastQueue.take(queue)).toBeNil()
	end)
end)

describe("a toast's time on screen", function()
	it("is the base for a short line, a little more per character past it, and never past the ceiling", function()
		expect(TIMING.BaseSeconds).toBe(2.5)
		expect(TIMING.PerCharSeconds).toBe(0.06)
		expect(TIMING.FreeChars).toBe(30)
		expect(TIMING.MaxSeconds).toBe(5)
		expect(ToastQueue.duration(string.rep("a", 30), "Info", TIMING)).toBe(2.5)
		expect(ToastQueue.duration("", "Success", TIMING)).toBe(2.5)
		expect(ToastQueue.duration(string.rep("a", 40), "Info", TIMING)).toBeCloseTo(3.1, 6)
		expect(ToastQueue.duration(string.rep("a", 400), "Error", TIMING)).toBe(5)
	end)

	it("counts characters, not bytes: a French line is not held longer for its accents", function()
		-- 30 characters, 36 bytes.
		local french = "Récompense récupérée à l'été é"
		expect(utf8.len(french)).toBe(30)
		expect(#french > 30).toBe(true)
		expect(ToastQueue.duration(french, "Info", TIMING)).toBe(2.5)
	end)

	it("gives a celebration its own time", function()
		expect(TIMING.CelebrateSeconds).toBe(3.5)
		expect(ToastQueue.duration("Level 7 reached!", "Celebrate", TIMING)).toBe(3.5)
		expect(ToastQueue.duration(string.rep("a", 400), "Celebrate", TIMING)).toBe(3.5)
	end)
end)

describe("the HUD's toasts", function()
	it("hold the value kinds while the player fights, in a match or in an arena (rule 11)", function()
		local hud = code(HUD)
		expect(keysOf(hud, "FIGHT_HELD")).toEqual({ Reward = true, Celebrate = true })
		local fight = body(hud, "local function refreshFight(")
		expect(string.find(fight, "local fighting = inMatch or inArena", 1, true)).never.toBeNil()
		expect(string.find(fight, "toast:Hold(if fighting then FIGHT_HELD else {})", 1, true)).never.toBeNil()
		expect(
			string.find(
				fight,
				"if fighting then Theme.Timing.Toast.MaxVisibleMatch else Theme.Timing.Toast.MaxVisibleHub",
				1,
				true
			)
		).never.toBeNil()
		expect(string.find(body(hud, "local function refreshMatch("), "inMatch = active", 1, true)).never.toBeNil()
		expect(string.find(body(hud, "local function refreshMatch("), "refreshFight()", 1, true)).never.toBeNil()
		local place = body(hud, "function HudController.setPlace(")
		expect(string.find(place, "local arena = ARENA_ZONES[zoneId] == true", 1, true)).never.toBeNil()
		expect(string.find(place, "refreshFight()", 1, true)).never.toBeNil()
		-- Every place a portal leads is decided: the two arenas are fights, the way back is the hub.
		local arenas = keysOf(hud, "ARENA_ZONES")
		for id in pairs(PortalConfig.Zones) do
			expect(arenas[id] == true).toBe(id ~= "Return")
		end
		-- The HUD hears where the player went from the controller that moved them, once it has said so.
		local travelled = body(code(TRAVEL), "local function onTravelled(")
		local fired = string.find(travelled, "TravelController.Travelled:Fire(id)", 1, true)
		local placed = string.find(travelled, "hud.setPlace(id)", 1, true)
		assert(fired ~= nil and placed ~= nil, "TravelController no longer tells the HUD where the player is")
		expect(fired :: number).toBeLessThan(placed :: number)
	end)

	it("celebrate and pay only what the server really says, and a reward names its Folios", function()
		local hud = code(HUD)
		local sent = serverKeys()
		expect(sent["hud.levelUp"]).toBe(true)
		local celebrate = keysOf(hud, "CELEBRATE_KEYS")
		local reward = keysOf(hud, "REWARD_KEYS")
		for _, key in ipairs({ "hud.levelUp", "hud.tierUp", "quest.completed", "daily.firstWin" }) do
			expect(celebrate[key]).toBe(true)
		end
		for key in pairs(celebrate) do
			if not sent[key] then
				error(("%s is celebrated, and the server never sends it"):format(key))
			end
			expect(reward[key]).toBeNil()
		end
		for key in pairs(reward) do
			if not sent[key] then
				error(("%s is paid as a reward, and the server never sends it"):format(key))
			end
			local words = Strings.Table[key]
			assert(words ~= nil, key .. " has no words")
			if
				string.find(words.en, "{folios}", 1, true) == nil
				and string.find(words.en, "{amount}", 1, true) == nil
			then
				error(("%s is a reward that pays no Folios"):format(key))
			end
		end
		local routed = body(hud, "local function show(")
		expect(string.find(routed, 'if CELEBRATE_KEYS[key] then toast:Show(text, "Celebrate")', 1, true)).never.toBeNil()
		expect(
			string.find(routed, 'elseif REWARD_KEYS[key] then toast:Show(text, "Reward", amountOf(params))', 1, true)
		).never.toBeNil()
		-- A message from the HUD itself is routed the same way as the server's.
		expect(
			string.find(
				body(hud, "function HudController.showLocalToast("),
				'show(key, params, kind or "Info", params)',
				1,
				true
			)
		).never.toBeNil()
	end)

	it("say their kind with a medallion whose sign reads on it", function()
		local toast = code(TOAST)
		for _, line in ipairs({
			"Info = Theme.Colors.InfoFill,",
			"Success = Theme.Colors.SuccessFill,",
			"Error = Theme.Colors.DangerFill,",
			"Celebrate = Theme.Colors.PanelRaised,",
		}) do
			expect(string.find(toast, "\t" .. line, 1, true)).never.toBeNil()
		end
		expect(string.find(toast, 'Icon.new("Coin", MEDALLION)', 1, true)).never.toBeNil()
		expect(string.find(toast, "Theme.inkOn(fill)", 1, true)).never.toBeNil()
		local colors = ThemeConfig.Colors
		for _, fill in ipairs({ colors.InfoFill, colors.SuccessFill, colors.DangerFill, colors.PanelRaised }) do
			expect(ThemeConfig.contrast(ThemeConfig.inkOn(fill), fill)).toBeGreaterThanOrEqual(4.5)
		end
		-- The celebration's words on the primary yellow.
		expect(ThemeConfig.contrast(colors.Text, colors.Primary)).toBeGreaterThanOrEqual(4.5)
	end)

	it("run down the right edge under the player list with a pointer, and hang under the Menu disc on touch", function()
		local toast = code(TOAST)
		expect(string.find(toast, "local POINTER_TOP = 0.34\n", 1, true)).never.toBeNil()
		expect(string.find(toast, "container.AnchorPoint = Vector2.new(1, 0)", 1, true)).never.toBeNil()
		local share = tonumber(string.match(toast, "local POINTER_SHARE = ([%d%.]+)"))
		local touch = tonumber(string.match(toast, "local TOUCH_SHARE = ([%d%.]+)"))
		local width = tonumber(string.match(toast, "local LANE_MAX_WIDTH = (%d+)"))
		assert(share ~= nil and touch ~= nil and width ~= nil, "the lane no longer names its width")
		expect(share :: number).toBeLessThanOrEqual(0.26)
		expect(touch :: number).toBeLessThanOrEqual(0.3)
		expect(width :: number).toBeLessThanOrEqual(380)
		local hud = code(HUD)
		expect(string.find(hud, 'Lane = if Theme.touchOnly() then "Touch" else "Pointer"', 1, true)).never.toBeNil()
		local place = body(hud, "local function placeToasts(")
		expect(string.find(place, "inputController.touchRects()[MENU_ACTION]", 1, true)).never.toBeNil()
		expect(string.find(place, "toast:SetTop(", 1, true)).never.toBeNil()
		expect(string.find(hud, "inputController.TouchLayoutChanged:Connect(placeToasts)", 1, true)).never.toBeNil()
	end)

	it("slide in from the edge and leave the way they came (rule 3)", function()
		local toast = code(TOAST)
		expect(string.find(toast, 'Motion.to(group, { Position = UDim2.new() }, "UiPop")', 1, true)).never.toBeNil()
		expect(string.find(toast, 'Motion.to(group, { GroupTransparency = 0 }, "Ui")', 1, true)).never.toBeNil()
		expect(
			string.find(
				toast,
				'Motion.to(group, { Position = UDim2.fromOffset(SLIDE, 0), GroupTransparency = 1 }, "UiExit", release)',
				1,
				true
			)
		).never.toBeNil()
		expect(
			string.find(
				toast,
				"local seconds = ToastQueue.duration(entry.Text, entry.Kind, Theme.Timing.Toast)",
				1,
				true
			)
		).never.toBeNil()
	end)
end)
