--!strict
-- The client's half of the portals and the Battleground (D-130, D-131, D-132). The server moves players and asks
-- them nothing, so the client only says what the server is doing -- and that is where it can quietly fail: a band
-- that never shows, a fill that is not the server's dwell, a menu left open over an arrival, a loop nobody asked
-- for, a remote with nobody at one of its ends. The controllers touch the engine, so their source is read.
local Harness = require("./harness")
local PortalConfig = require("../src/shared/Config/PortalConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CONTROLLERS = "src/client/Controllers/"
local TRAVEL = CONTROLLERS .. "TravelController.luau"
local HUD = CONTROLLERS .. "HudController.luau"
local SOUND = CONTROLLERS .. "SoundController.luau"
local MENU = CONTROLLERS .. "MenuController.luau"
local BOSS = CONTROLLERS .. "BossController.luau"
local BOOTSTRAP = "src/client/Bootstrap.client.luau"
local REMOTES = "src/shared/Remotes.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function fold(source: string): string
	return (source:gsub("%s+", " "))
end

local function code(path: string): string
	return fold(strip(fs.readFile(path)))
end

-- A function's body in a file, comments stripped and whitespace folded.
local function body(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return fold(source:sub(start, finish or #source))
end

local function requireAll(text: string, lines: { string }, what: string)
	for _, line in ipairs(lines) do
		if text:find(line, 1, true) == nil then
			error(("%s no longer does: %s"):format(what, line))
		end
	end
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				collect(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function sources(roots: { string }): string
	local files: { string } = {}
	for _, root in ipairs(roots) do
		collect(root, files)
	end
	local parts: { string } = {}
	for _, path in ipairs(files) do
		table.insert(parts, strip(fs.readFile(path)))
	end
	return table.concat(parts, "\n")
end

describe("the portal band", function()
	it("names where the circle leads and fills over the server's own dwell", function()
		local changed = body(TRAVEL, "local function onPortalChanged(")
		requireAll(changed, {
			"if payload == nil then stopFill() portalBand.Visible = false return end",
			"then PortalConfig.Zones[payload.Id]",
			"local seconds = if finite(snapshot.Seconds) and snapshot.Seconds > 0 then snapshot.Seconds else zone.DwellSeconds",
			"portalZone = zone wordPortal() startFill(seconds)",
			"grow(portalBand, portalScale)",
		}, "onPortalChanged")
		requireAll(body(TRAVEL, "local function wordPortal("), {
			"local zone = portalZone if zone ~= nil then",
			'portalTitle.Text = localize.t("portal.entering", { place = localize.t(zone.NameKey) })',
		}, "wordPortal")
		-- One tween from empty to full over exactly those seconds, cancelled by the next packet: no loop.
		requireAll(body(TRAVEL, "local function startFill("), {
			"stopFill() portalFill.Size = UDim2.fromScale(0, 1)",
			"TweenInfo.new(seconds, FILL_STYLE, FILL_DIRECTION)",
			"{ Size = UDim2.fromScale(1, 1) }",
		}, "startFill")
		requireAll(body(TRAVEL, "local function stopFill("), { "tween:Cancel()", "fillTween = nil" }, "stopFill")
		-- A clock the player reads: eased (docs/ART_BIBLE.md rule 4) and symmetric, so it is half full at half time.
		local travel = code(TRAVEL)
		expect(travel:find("local FILL_STYLE = Enum.EasingStyle.Sine", 1, true)).never.toBe(nil)
		expect(travel:find("local FILL_DIRECTION = Enum.EasingDirection.InOut", 1, true)).never.toBe(nil)
		-- Every zone's name is a key the band can say.
		for id, zone in pairs(PortalConfig.Zones) do
			expect(type(zone.NameKey)).toBe("string")
			expect(zone.DwellSeconds > 0).toBe(true)
			expect(type(id)).toBe("string")
		end
	end)

	it("hears every remote the portals and the Battleground speak on, and only once they can be drawn", function()
		local start = body(TRAVEL, "function TravelController.Start(")
		local travelled = start:find('remoteClient.on("Travelled", onTravelled)', 1, true)
		local built = start:find("if not build() then", 1, true)
		local portal = start:find('remoteClient.on("PortalChanged", onPortalChanged)', 1, true)
		local place = start:find('remoteClient.on("BattlegroundChanged", onBattlegroundChanged)', 1, true)
		expect(travelled).never.toBe(nil)
		expect(built).never.toBe(nil)
		expect(portal).never.toBe(nil)
		expect(place).never.toBe(nil)
		-- An arrival closes the menu even with no HUD; the bands' packets wait for the bands.
		expect((travelled :: number) < (built :: number)).toBe(true)
		expect((built :: number) < (portal :: number)).toBe(true)
		expect((built :: number) < (place :: number)).toBe(true)
		requireAll(body(TRAVEL, "local function onTravelled("), {
			'if type(id) ~= "string" or PortalConfig.Zones[id] == nil then',
			"TravelController.Travelled:Fire(id)",
		}, "onTravelled")
	end)
end)

describe("the Battleground band", function()
	it(
		"says how many Forgers stand and how many the member defeated, and plays the fight's loop while a member",
		function()
			local changed = body(TRAVEL, "local function onBattlegroundChanged(")
			requireAll(changed, {
				"if payload == nil then placeBand.Visible = false if member then member = false soundController.wantMusic(MUSIC_SOURCE, nil) refreshFight() end local hud = hudController if hud ~= nil then hud.leftPlace(BATTLEGROUND_ZONE) end return end",
				"local defeated = math.max(0, math.floor(snapshot.Defeated))",
				"standingCount = math.max(0, math.floor(snapshot.Standing))",
				"defeatedCount = defeated wordPlace()",
				"if not member then member = true soundController.wantMusic(MUSIC_SOURCE, MUSIC_ID) refreshFight() end",
			}, "onBattlegroundChanged")
			requireAll(body(TRAVEL, "local function wordPlace("), {
				'placeTitle.Text = localize.t("portal.battleground.name")',
				'placeLine.Text = localize.t("battleground.status", {',
				'standing = localize.t("battleground.standing", { standing = standingCount }),',
				'defeated = localize.t("battleground.defeated", { defeated = defeatedCount }),',
			}, "wordPlace")
			local travel = code(TRAVEL)
			expect(travel:find('local MUSIC_SOURCE = "Battleground"', 1, true)).never.toBe(nil)
			expect(travel:find('local MUSIC_ID = "Match"', 1, true)).never.toBe(nil)
		end
	)

	it("is the Flyleaf's too: rivals, takedowns and the run, the fight's loop, and a way out of fight mode", function()
		local changed = body(TRAVEL, "local function onFlyleafChanged(")
		requireAll(changed, {
			"if payload == nil then if flyleafMember then flyleafMember = false placeBand.Visible = false soundController.wantMusic(MUSIC_SOURCE, nil) refreshFight() end local hud = hudController if hud ~= nil then hud.leftPlace(FLYLEAF_ZONE) end return end",
			'placeTitle.Text = localize.t("portal.flyleaf.name")',
			'placeLine.Text = localize.t("flyleaf.status", {',
			"members = math.max(0, math.floor(snapshot.Members) - 1),",
			"if not flyleafMember then flyleafMember = true soundController.wantMusic(MUSIC_SOURCE, MUSIC_ID) refreshFight() end",
		}, "onFlyleafChanged")
		expect(code(TRAVEL):find('local FLYLEAF_ZONE = "Flyleaf"', 1, true)).never.toBe(nil)
		local start = body(TRAVEL, "function TravelController.Start(")
		local built = start:find("if not build() then", 1, true)
		local heard = start:find('remoteClient.on("FlyleafChanged", onFlyleafChanged)', 1, true)
		expect(heard).never.toBe(nil)
		expect((built :: number) < (heard :: number)).toBe(true)
		-- The HUD takes the Flyleaf for a fight, like the Battleground.
		expect(
			code(HUD):find(
				"local ARENA_ZONES: { [string]: boolean } = { Battleground = true, WorldBoss = true, Flyleaf = true }",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("is outranked by a match and by the Erasure for the music", function()
		-- A member the event draws in hears the boss; one a match takes hears the match.
		expect(code(SOUND):find('local MUSIC_SOURCES = { "Match", "Boss", "Battleground" }', 1, true)).never.toBe(nil)
	end)
end)

describe("the top-centre column", function()
	it("stacks the portal band first, then the match, the boss and the place", function()
		local hud = code(HUD)
		expect(hud:find("local MATCH_BAND_ORDER = 1", 1, true)).never.toBe(nil)
		expect(hud:find("local BAND_ORDERS: { [string]: number } = { Portal = 0, Boss = 2, Place = 3 }", 1, true)).never.toBe(
			nil
		)
		expect(
			body(HUD, "function HudController.topStack("):find('return topStack, BAND_ORDERS[band or "Boss"]', 1, true)
		).never.toBe(nil)
		-- Each band asks for its own place in it.
		local build = body(TRAVEL, "local function build(")
		expect(build:find('local stack, portalOrder = hud.topStack("Portal")', 1, true)).never.toBe(nil)
		expect(build:find('local _, placeOrder = hud.topStack("Place")', 1, true)).never.toBe(nil)
		expect(body(BOSS, "local function build("):find("local stack, layoutOrder = hud.topStack()", 1, true)).never.toBe(
			nil
		)
	end)
end)

describe("a fight the portals know of", function()
	-- D-148: while the local player fights, every aura on their screen steps back so the glyphs keep the colour
	-- of the fight. A ranked match is MatchController's to say; the Battleground, the Flyleaf and the Erasure's arena
	-- are the portals', and each way out of them has to end the fight, or an aura stays quiet in the hub for good.
	it(
		"holds while a member of the Battleground or the Flyleaf, or inside the Erasure's arena, and says so once per change",
		function()
			requireAll(body(TRAVEL, "local function refreshFight("), {
				"local now = member or flyleafMember or inArena",
				"if now == fighting then return end",
				"fighting = now TravelController.FightChanged:Fire(now)",
			}, "refreshFight")
			requireAll(body(TRAVEL, "function TravelController.inFight("), { "return fighting" }, "inFight")
			expect(code(TRAVEL):find("TravelController.FightChanged = Signal.new()", 1, true)).never.toBe(nil)
		end
	)

	it("enters the arena by its gate and leaves it by the way back, a death, or the fight's end", function()
		local travel = code(TRAVEL)
		expect(travel:find('local ARENA_PORTAL = "WorldBoss"', 1, true)).never.toBe(nil)
		local isPortal = false
		for _, id in ipairs(PortalConfig.Ids) do
			isPortal = isPortal or id == "WorldBoss"
		end
		expect(isPortal).toBe(true)
		-- Any trip sets it: the gate in, the Return gate (or any other) out.
		requireAll(body(TRAVEL, "local function onTravelled("), {
			"inArena = id == ARENA_PORTAL refreshFight()",
		}, "onTravelled")
		requireAll(body(TRAVEL, "local function onBossChanged("), {
			"if payload == nil then bossPhase = nil if inArena then inArena = false refreshFight() end return end",
			-- The scheduled event pulls in everybody alive and in no match as it starts fighting, with no portal.
			"if phase == PULL_PHASE and bossPhase == ANNOUNCED_PHASE and payload.Practice ~= true then",
			"if matchController.getMatch() == nil then inArena = true refreshFight() end",
			'bossPhase = if type(phase) == "string" then phase else nil',
		}, "onBossChanged")
		expect(travel:find('local ANNOUNCED_PHASE = "Announced"', 1, true)).never.toBe(nil)
		expect(travel:find('local PULL_PHASE = "Fighting"', 1, true)).never.toBe(nil)
		-- Two phases the server really sends, in that order.
		expect(
			code("src/shared/Types.luau"):find('export type BossPhaseSnapshot = "Announced" | "Fighting" |', 1, true)
		).never.toBe(nil)
		expect(body(TRAVEL, "function TravelController.Init("):find("matchController = deps.MatchController", 1, true)).never.toBe(
			nil
		)
		requireAll(body(TRAVEL, "local function onRespawn("), {
			"if inArena then inArena = false refreshFight() end",
		}, "onRespawn")
		-- Heard whatever the bands did: none of it draws.
		local start = body(TRAVEL, "function TravelController.Start(")
		local boss = start:find('remoteClient.on("BossChanged", onBossChanged)', 1, true)
		local respawn = start:find("Players.LocalPlayer.CharacterAdded:Connect(onRespawn)", 1, true)
		local built = start:find("if not build() then", 1, true)
		expect(boss).never.toBe(nil)
		expect(respawn).never.toBe(nil)
		expect((boss :: number) < (built :: number)).toBe(true)
		expect((respawn :: number) < (built :: number)).toBe(true)
	end)
end)

describe("an arrival", function()
	it("closes whatever screen was open, so nobody arrives with their input suspended", function()
		expect(
			body(MENU, "function MenuController.Start("):find(
				"travelController.Travelled:Connect(MenuController.close)",
				1,
				true
			)
		).never.toBe(nil)
		expect(body(MENU, "function MenuController.Init("):find("travelController = deps.TravelController", 1, true)).never.toBe(
			nil
		)
	end)

	it("is heard by a controller started after the HUD and the boss band, and before the menu", function()
		local order = strip(fs.readFile(BOOTSTRAP))
		local function rank(name: string): number
			local at = order:find('"' .. name .. '",', 1, true)
			if at == nil then
				error(("%s is not in the client's ORDER"):format(name))
			end
			return at
		end
		expect(rank("HudController") < rank("TravelController")).toBe(true)
		expect(rank("BossController") < rank("TravelController")).toBe(true)
		expect(rank("TravelController") < rank("MenuController")).toBe(true)
	end)
end)

describe("a practice's band", function()
	it("titles itself a practice, and never pulses the page as the event's arrival does", function()
		requireAll(
			body(BOSS, "local function read("),
			{ "Practice = payload.Practice == true," },
			"BossController.read"
		)
		requireAll(body(BOSS, "local function refresh("), {
			'titleLabel.Text = localize.t(if current.Practice then "boss.practice.title" else "boss.name")',
		}, "BossController.refresh")
		-- The pulse is the scheduled event's, and only its Announced phase has one: a practice opens fighting.
		requireAll(body(BOSS, "local function announce("), {
			'if current.Phase == "Announced" and worldLighting ~= nil then worldLighting.pulse("Erasure") end',
		}, "BossController.announce")
	end)
end)

describe("a remote", function()
	-- Every server-to-client remote, cut out of Remotes.Definitions (it needs an engine to require).
	local function serverToClient(): { string }
		local source = strip(fs.readFile(REMOTES))
		local start = source:find("Remotes.Definitions = {", 1, true)
		if start == nil then
			error(REMOTES .. " has no Remotes.Definitions: this gate would check nothing")
		end
		local block = source:sub(start, source:find("\n}", start, true) or #source)
		local names: { string } = {}
		for name, definition in block:gmatch("\n\t(%w+) = (%b{})") do
			if definition:find('Direction = "ServerToClient"', 1, true) ~= nil then
				table.insert(names, name)
			end
		end
		table.sort(names)
		return names
	end

	it("that the server speaks on has a listener on the client, and the server names it", function()
		local names = serverToClient()
		expect(#names).toBeGreaterThanOrEqual(14)
		local client = sources({ "src/client", "src/ui" })
		local server = sources({ "src/server" })
		for _, name in ipairs(names) do
			if client:find('.on("' .. name .. '"', 1, true) == nil then
				error(("%s is sent to clients and no client listens to it"):format(name))
			end
			if server:find('"' .. name .. '"', 1, true) == nil then
				error(("%s is declared server-to-client and the server never names it"):format(name))
			end
		end
	end)

	it("that the client listens to is one the server declared for it", function()
		local declared: { [string]: boolean } = {}
		for _, name in ipairs(serverToClient()) do
			declared[name] = true
		end
		local client = sources({ "src/client", "src/ui" })
		local heard = 0
		for name in client:gmatch('[Rr]emoteClient%.on%("(%w+)"') do
			heard += 1
			if not declared[name] then
				error(("the client listens to %s, which no server-to-client definition declares"):format(name))
			end
		end
		expect(heard).toBeGreaterThanOrEqual(14)
	end)
end)
