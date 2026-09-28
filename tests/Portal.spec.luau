--!strict
-- The portals (D-130), held to the promises no Lune test can run: PortalService and the gates need an engine,
-- so their sources are read. A portal is a circle the SERVER sees a player stand in, and each case here is one
-- way it could otherwise be asked for, forged, farmed or fired twice: a remote the client calls, a position
-- the client reports, a seal lying in ServerStorage, a circle that re-arms under a player's feet, a cooldown
-- written for a player who has left, a gate whose circle is not the zone.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PORTALS = "src/server/Services/PortalService.luau"
local GATE = "src/server/World/PortalGate.luau"
local GATE_FOOTPRINT = "tests/gate.luau"
local REMOTES = "src/shared/Remotes.luau"
local ARENA = "src/server/Services/ArenaService.luau"
local MAP = "src/server/Services/BattlegroundService/Map.luau"
local BOOTSTRAP = "src/server/Bootstrap.server.luau"
local SERVER = "src/server"

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

-- Whitespace folded to one space, and none just inside a bracket, so a call reads the same however the
-- formatter wrapped it.
local function tight(text: string): string
	return (text:gsub("%s+", " "):gsub("%( ", "("):gsub(" %)", ")"))
end

-- One function's source, from its header to the first `end` at column 0, folded.
local function body(path: string, header: string): string
	local source = code(path)
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return tight(source:sub(start, finish or #source))
end

local function has(text: string, needle: string): boolean
	return text:find(needle, 1, true) ~= nil
end

-- Whether `first` appears in `text`, and `later` after it.
local function ordered(text: string, first: string, later: string): boolean
	local at = text:find(first, 1, true)
	return at ~= nil and text:find(later, at + #first, true) ~= nil
end

local function count(text: string, needle: string): number
	local found, from = 0, 1
	while true do
		local at = text:find(needle, from, true)
		if at == nil then
			return found
		end
		found += 1
		from = at + #needle
	end
end

local function requireAll(text: string, needles: { string }, what: string)
	for _, needle in ipairs(needles) do
		if not has(text, needle) then
			error(("%s no longer holds: %s"):format(what, needle))
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

-- Every remote of Remotes.Definitions, by name, with the text of its definition. Remotes needs an engine to
-- require (its schemas are built from engine-side modules), so its definitions are cut out of the source.
local function definitions(): { [string]: string }
	local source = code(REMOTES)
	local start = source:find("Remotes.Definitions = {", 1, true)
	if start == nil then
		error(REMOTES .. " has no Remotes.Definitions: this gate would check nothing")
	end
	-- The table's own closing brace is the first one at column 0 after it opens.
	local block = source:sub(start, source:find("\n}", start, true) or #source)
	local found: { [string]: string } = {}
	local names: { { Name: string, At: number } } = {}
	for at, name in block:gmatch("\n\t()(%w+) = {") do
		table.insert(names, { Name = name, At = at :: number })
	end
	for index, entry in ipairs(names) do
		local finish = if names[index + 1] ~= nil then names[index + 1].At - 1 else #block
		found[entry.Name] = block:sub(entry.At, finish)
	end
	return found
end

describe("a trip", function()
	it("is never asked for: the client is only told", function()
		local remotes = definitions()
		local total = 0
		for name, definition in pairs(remotes) do
			total += 1
			local travel = name:find("Portal") ~= nil or name:find("Travel") ~= nil or name:find("Teleport") ~= nil
			if travel and definition:find('"ClientToServer"', 1, true) ~= nil then
				error(("%s lets a client ask to be moved: a portal is a place the server sees it stand"):format(name))
			end
		end
		expect(total).toBeGreaterThan(20)
		for _, name in ipairs({ "PortalChanged", "Travelled" }) do
			local definition = remotes[name]
			if definition == nil then
				error(("%s is not a remote: the band and the arrival have no way to the client"):format(name))
			end
			expect(has(definition, 'Direction = "ServerToClient"')).toBe(true)
		end
		-- No handler of any client call, and no engine prompt, whose Triggered is a client call outside the registry.
		local service = code(PORTALS)
		for _, banned in ipairs({
			".on(",
			"setCallback(",
			"OnServerEvent",
			"ProximityPrompt",
			"Touched",
			"trustedOrigin(",
		}) do
			if has(service, banned) then
				error(("PortalService uses %s"):format(banned))
			end
		end
		expect(has(code(GATE), "ProximityPrompt")).toBe(false)
	end)

	it("starts where the server trusts the player stands, never where the client says", function()
		local standing = body(PORTALS, "local function standing(")
		requireAll(standing, {
			"if deps.Match.isInMatch(player) then return nil end",
			"if humanoid == nil or humanoid.Health <= 0 then return nil end",
			"return deps.Combat.trustedPosition(player)",
		}, "standing")
		expect(ordered(standing, "deps.Match.isInMatch(player)", "deps.Combat.trustedPosition(player)")).toBe(true)
		local step = body(PORTALS, "local function step(")
		expect(has(step, "local position = standing(player)")).toBe(true)
		expect(has(step, "sealAt(position)")).toBe(true)
		-- The only place anything here reads a position of a player.
		expect(count(code(PORTALS), "trustedPosition(")).toBe(1)
		for _, banned in ipairs({ "HumanoidRootPart", "PrimaryPart", ":GetPivot(", "AssemblyLinearVelocity" }) do
			expect(has(code(PORTALS), banned)).toBe(false)
		end
	end)

	it("is measured on the ground and in height, within the zone's own numbers", function()
		local at = body(PORTALS, "local function sealAt(")
		requireAll(at, {
			"if math.abs(position.Y - center.Y) <= HEIGHT then",
			"local dx, dz = position.X - center.X, position.Z - center.Z",
			"if distance <= RADIUS and distance < nearest then",
		}, "sealAt")
		requireAll(code(PORTALS), {
			"local RADIUS = PortalConfig.ZoneRadiusStuds",
			"local HEIGHT = PortalConfig.ZoneHeightStuds",
			"local CHECK_SECONDS = 1 / PortalConfig.CheckHz",
		}, "PortalService")
	end)
end)

describe("the circles", function()
	it("are the seals standing in the Workspace that lead somewhere known, on every path in", function()
		local add = body(PORTALS, "local function addSeal(")
		requireAll(add, {
			'if not instance:IsA("BasePart") or not instance:IsDescendantOf(Workspace) then return end',
			'if type(id) ~= "string" or ZONES[id] == nil then',
			"local id = instance:GetAttribute(PortalConfig.SealAttribute)",
		}, "addSeal")
		expect(ordered(add, "IsDescendantOf(Workspace)", "seals[instance] =")).toBe(true)
		-- Both the first look and the signal go through that filter, and the seal of a destroyed copy leaves.
		local start = body(PORTALS, "function PortalService.Start(")
		requireAll(start, {
			"CollectionService:GetInstanceAddedSignal(PortalConfig.SealTag):Connect(addSeal)",
			"CollectionService:GetInstanceRemovedSignal(PortalConfig.SealTag):Connect(removeSeal)",
			"for _, instance in ipairs(CollectionService:GetTagged(PortalConfig.SealTag)) do addSeal(instance) end",
		}, "PortalService.Start")
		expect(count(code(PORTALS), "seals[instance] = id")).toBe(1)
		expect(has(body(PORTALS, "local function removeSeal("), "seals[instance] = nil")).toBe(true)
	end)

	it("show their band only off cooldown, and fire once per stay", function()
		local moveTo = body(PORTALS, "local function moveTo(")
		expect(ordered(moveTo, "watch.Fired = false", "show(player, watch, id)")).toBe(true)
		expect(has(moveTo, "if id ~= nil and not onCooldown(player, now) then show(player, watch, id) else")).toBe(true)
		local step = body(PORTALS, "local function step(")
		requireAll(step, {
			"if seal ~= watch.Seal then moveTo(player, watch, seal, now) return end",
			-- Re-arms only once they step out: a stay that already fired, or was told off, does nothing more.
			"if id == nil or watch.Fired then return end",
			"if not cooling and not watch.Shown then watch.Since = now show(player, watch, id) return end",
			"if now - watch.Since < ZONES[id].DwellSeconds or deps.Movement.isDown(player) then return end",
			'if cooling then deps.Notify.send(player, "portal.cooldown", nil, "Info") return end',
		}, "step")
		expect(ordered(step, "deps.Movement.isDown(player)", "watch.Fired = true")).toBe(true)
		expect(ordered(step, "watch.Fired = true", "portal.cooldown")).toBe(true)
		expect(ordered(step, "watch.Fired = true", "task.spawn(travel, player, id)")).toBe(true)
		expect(ordered(step, "hide(player, watch)", "task.spawn(travel, player, id)")).toBe(true)
		expect(ordered(step, "travelling[player] = true", "task.spawn(travel, player, id)")).toBe(true)
		expect(has(body(PORTALS, "local function onCooldown("), "return now < (cooldownUntil[player] or 0)")).toBe(true)
	end)

	it("leave a traveller alone until the trip is over, whatever happens in it", function()
		local heartbeat = body(PORTALS, "local function onHeartbeat(")
		expect(has(heartbeat, "if travelling[player] == nil then step(player, watch, now) end")).toBe(true)
		local travel = body(PORTALS, "local function travel(")
		expect(ordered(travel, "log.try(", "travelling[player] = nil")).toBe(true)
		expect(has(travel, ", journey, player, id)")).toBe(true)
		-- Every map keyed by a player forgets them when they leave.
		requireAll(body(PORTALS, "local function forget("), {
			"watches[player] = nil",
			"travelling[player] = nil",
			"cooldownUntil[player] = nil",
		}, "forget")
		expect(has(code(PORTALS), "Players.PlayerRemoving:Connect(forget)")).toBe(true)
	end)
end)

describe("where a trip goes", function()
	it("takes each gate's player out of where it stood before putting them anywhere", function()
		local dispatch = body(PORTALS, "local function dispatch(")
		expect(ordered(dispatch, "deps.WorldBoss.leave(player)", "deps.Battleground.enter(player)")).toBe(true)
		expect(has(dispatch, 'elseif id == "WorldBoss" then return deps.WorldBoss.enterFromPortal(player)')).toBe(true)
		-- Return, the rest: out of the Battleground and out of the Erasure's fight, then home.
		local home = dispatch:sub(dispatch:find("deps.WorldBoss.enterFromPortal(player)", 1, true) :: number)
		expect(ordered(home, "deps.Battleground.leave(player)", "deps.Hub.teleportToHub(player)")).toBe(true)
		expect(ordered(home, "deps.WorldBoss.leave(player)", "deps.Hub.teleportToHub(player)")).toBe(true)
		expect(ordered(dispatch, 'if id == "Battleground" then', 'elseif id == "WorldBoss" then')).toBe(true)
	end)

	it("lets a player out of the Erasure's fight only for a trip the Battleground will take", function()
		local dispatch = body(PORTALS, "local function dispatch(")
		-- The Battleground's branch alone: the Return branch below it lets go of the fight too, and would
		-- otherwise answer for a branch that left it before asking.
		local from = dispatch:find('if id == "Battleground" then', 1, true)
		local to = dispatch:find('elseif id == "WorldBoss" then', 1, true)
		if from == nil or to == nil or to < from then
			error("dispatch has no Battleground branch ahead of the WorldBoss one: this gate would check nothing")
		end
		local branch = dispatch:sub(from, to)
		requireAll(branch, {
			"local open, closed = deps.Battleground.admits(player)",
			"if not open then return false, closed, nil end",
			"deps.WorldBoss.leave(player)",
		}, "dispatch's Battleground branch")
		local refused = branch:find("if not open then return false, closed, nil end", 1, true) :: number
		expect((branch:find("deps.WorldBoss.leave(player)", 1, true) :: number) > refused).toBe(true)
	end)

	it("cools down and protects only a player still on the server, and says why it refused", function()
		local journey = body(PORTALS, "local function journey(")
		expect(ordered(journey, "if player.Parent ~= Players then return end", "cooldownUntil[player] =")).toBe(true)
		requireAll(journey, {
			"cooldownUntil[player] = os.clock() + PortalConfig.CooldownSeconds",
			"deps.Combat.grantIFrames(player, PortalConfig.EntryIFrameSeconds)",
			"deps.Registry.fire(TRAVELLED_REMOTE, player, id)",
			'if refusal ~= nil then deps.Notify.send(player, refusal, params, "Error") end',
		}, "journey")
		expect(ordered(journey, "if not moved then", "if player.Parent ~= Players then")).toBe(true)
		expect(count(code(PORTALS), "cooldownUntil[player] = os.clock()")).toBe(1)
	end)
end)

describe("a gate", function()
	it("is a circle exactly as wide as the zone, whose seal is tagged before anything can see it", function()
		local build = body(GATE, "function PortalGate.build(")
		requireAll(build, {
			'add(Draw.flatDisc("SealDisc", 2 * RADIUS, ground, LADDER.Seal,',
			"local sealSize = Vector3.new(2 * RADIUS, SEAL_THICKNESS_STUDS, 2 * RADIUS)",
			"seal.Transparency = 1",
			"seal.CanCollide = false",
			"seal.CanQuery = false",
			"seal.CanTouch = false",
			"seal:SetAttribute(PortalConfig.SealAttribute, portalId)",
			"CollectionService:AddTag(seal, PortalConfig.SealTag)",
		}, "PortalGate.build")
		expect(ordered(build, "CollectionService:AddTag(seal, PortalConfig.SealTag)", "model.Parent = parent")).toBe(
			true
		)
		expect(ordered(build, "seal:SetAttribute(PortalConfig.SealAttribute, portalId)", "model.Parent = parent")).toBe(
			true
		)
		expect(has(code(GATE), "local RADIUS = PortalConfig.ZoneRadiusStuds")).toBe(true)
	end)

	it("stands where the placement tests measured it", function()
		-- tests/gate.luau reads the gate's footprint from WorldConfig.Portal for the hub, the arena and the
		-- Battleground: the posts across OpeningStuds / 2 + a post, behind the circle by a post; the lintel on them.
		local build = body(GATE, "function PortalGate.build(")
		requireAll(build, {
			"local postX = PORTAL.OpeningStuds / 2 + POST_SIZE.X / 2",
			"local postZ = RADIUS + POST_SIZE.Z / 2",
			"base * CFrame.new(postX * side, POST_SIZE.Y / 2, postZ)",
			"local lintelSize = Vector3.new(PORTAL.OpeningStuds + 2 * POST_SIZE.X, lintel, lintel)",
			"base * CFrame.new(0, POST_SIZE.Y + lintel / 2, RADIUS + lintel / 2)",
			"local rimDiameter = 2 * (RADIUS + PORTAL.SealRimStuds)",
			"local panelAt = base * CFrame.new(0, POST_SIZE.Y - PANEL_SIZE.Y / 2, RADIUS - PANEL_SIZE.Z / 2)",
		}, "PortalGate.build")
		requireAll(tight(code(GATE_FOOTPRINT)), {
			"HalfWidth = portal.OpeningStuds / 2 + portal.PostStuds[1],",
			"Front = radius + portal.SealRimStuds,",
			"Back = radius + math.max(portal.PostStuds[3], portal.LintelStuds),",
		}, GATE_FOOTPRINT)
	end)

	it("is built by PortalGate alone, and one contract names its seal", function()
		local files: { string } = {}
		collect(SERVER, files)
		local taggers: { string } = {}
		for _, path in ipairs(files) do
			local source = code(path)
			for _, literal in ipairs({ '"PortalSeal"', '"PortalId"', '"ReturnPortal"' }) do
				if has(source, literal) then
					error(("%s spells %s instead of reading PortalConfig"):format(path, literal))
				end
			end
			if has(source, "PortalConfig.SealTag)") and has(source, "AddTag(") then
				table.insert(taggers, path)
			end
		end
		expect(#taggers).toBe(1)
		expect(taggers[1]).toBe(GATE)
	end)

	it("leads home from the Erasure's arena and from the Battleground's camp", function()
		-- The arena's gate, in the template of the arena no mode references (the Erasure's), facing its centre --
		-- the placement tests/Config.spec.luau measures.
		local template = body(ARENA, "local function buildTemplate(")
		expect(count(template, "PortalGate.build(")).toBe(1)
		expect(ordered(template, "if teamSize > 1 then buildCoverWalls(", "local ring = ringSpawnCFrames(")).toBe(true)
		expect(ordered(template, "local ring = ringSpawnCFrames(", "PortalGate.build(")).toBe(true)
		expect(ordered(template, "buildMarker(BOSS_SPAWN_NAME", "PortalGate.build(")).toBe(true)
		requireAll(template, {
			"local inset = def.Size / 2 - PortalConfig.BossArenaGateInsetStuds",
			"local gate = Vector3.new(-inset, floorTop, -inset)",
			"local base = CFrame.lookAt(gate, Vector3.new(0, floorTop, 0))",
			'PortalGate.build(model, PortalConfig.Anchors.ReturnGate, base, "Return")',
		}, "ArenaService.buildTemplate")
		expect(ordered(template, "PortalGate.build(", "model.Parent = templatesFolder")).toBe(true)
		-- The camp's gate, facing east into the page -- the placement tests/BattlegroundLayout.spec.luau measures.
		local map = body(MAP, "function Map.build(")
		requireAll(map, {
			"local gate = Context.toWorld(layout.ReturnGate.X, 0, layout.ReturnGate.Z)",
			'PortalGate.build(model, PortalConfig.Anchors.ReturnGate, CFrame.lookAt(gate, gate + Vector3.xAxis), "Return")',
		}, "Map.build")
		expect(ordered(map, "PortalGate.build(", "model.Parent = Workspace")).toBe(true)
	end)
end)

describe("the service's place", function()
	it("starts after every gate is built and every place a gate leads to is up", function()
		local bootstrap = code(BOOTSTRAP)
		expect(has(bootstrap, "Portal = PortalService,")).toBe(true)
		for _, before in ipairs({ "HubService", "ArenaService", "WorldBossService", "BattlegroundService" }) do
			local entry = ('{ Name = "%s", Service = %s }'):format(before, before)
			expect(ordered(bootstrap, entry, '{ Name = "PortalService", Service = PortalService }')).toBe(true)
		end
	end)
end)
