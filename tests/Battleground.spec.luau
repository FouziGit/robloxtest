--!strict
-- The Battleground on the server (D-131, D-282), held to the promises no Lune test can run: every service here needs
-- an engine, so their sources are read -- all but Rewards, run on a pretend server (tests/server.luau). Each case is
-- a rule a Forger or the roster must never break -- damage
-- with no source reaches nobody who is not standing on the page, a body is the server's and is thrown with a
-- bounded force, a player is placed where the server trusts them, every wait is followed by the questions it
-- could have changed the answer to, and a kill is paid once, by model, only where a Forger could answer.
local BattlegroundConfig = require("../src/shared/Config/BattlegroundConfig")
local BotConfig = require("../src/shared/Config/BotConfig")
local DailyStreak = require("../src/shared/Pure/DailyStreak")
local Harness = require("./harness")
local Server = require("./server")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DIR = "src/server/Services/BattlegroundService/"
local MODULES = { "init", "Context", "Map", "Bots", "Motion", "Roster", "Perception", "Attacks", "Rewards", "Pits" }
local COMBAT = "src/server/Services/CombatService.luau"
local EFFECTS = "src/server/Effects/GlyphEffects.luau"
local GLYPHS = "src/server/Services/GlyphService.luau"
local BOOTSTRAP = "src/server/Bootstrap.server.luau"
local LOCK_ON = "src/client/Controllers/LockOnController.luau"

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

local function module(name: string): string
	return code(DIR .. name .. ".luau")
end

-- Every module of the folder, comments stripped, and the folder must hold exactly these: a new module is a new
-- place for a blow or a loop to hide, and it has to be named here to be read.
local function folder(): { [string]: string }
	local found: { [string]: string } = {}
	for _, entry in ipairs(fs.readDir(DIR)) do
		local name = string.match(entry, "^(.+)%.luau$")
		if name == nil then
			error(("%s holds %s, which is not a module"):format(DIR, entry))
		end
		found[name] = module(name)
	end
	for _, name in ipairs(MODULES) do
		if found[name] == nil then
			error(("%s has no %s: this gate would check nothing"):format(DIR, name))
		end
	end
	for name in pairs(found) do
		if table.find(MODULES, name) == nil then
			error(("%s%s.luau is new: add it to MODULES so these gates read it"):format(DIR, name))
		end
	end
	return found
end

-- One function's source, from its header to the first `end` at column 0, whitespace folded.
local function body(source: string, header: string, where: string): string
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(where, header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "))
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

describe("a Forger's blow", function()
	it("carries no source, and reaches ApplyDamage only through the gate", function()
		local total = 0
		for name, source in pairs(folder()) do
			local calls = count(source, "ApplyDamage(")
			local sourceless = count(source, "ApplyDamage(nil,")
			if calls ~= sourceless then
				error(("%s has %d ApplyDamage call(s), %d with no source"):format(name, calls, sourceless))
			end
			total += calls
		end
		expect(total).toBe(2)
		-- Every function that deals a blow asked `strikeable` first, about the very member it hits.
		local attacks = module("Attacks")
		for _, header in ipairs({ "local function resolveMelee(", "local function resolveBolt(" }) do
			local blow = body(attacks, header, "Attacks")
			expect(ordered(blow, "strikeable(bot, member, now)", "ApplyDamage(nil,")).toBe(true)
		end
	end)

	it("asks, before each blow, whether the member is still one, on the page and still a target", function()
		local gate = body(module("Attacks"), "local function strikeable(", "Attacks")
		for _, question in ipairs({
			"if Roster.get(player) ~= member then return nil, nil end",
			"if trusted == nil or not Context.insideBounds(handle.Layout, trusted) then return nil, nil end",
			"if not BotBrain.isValidTarget(Context.Rules, bot.Memory, target, now) then return nil, nil end",
		}) do
			if gate:find(question, 1, true) == nil then
				error("strikeable no longer asks: " .. question)
			end
		end
		-- On the page: over the floor, and between BoundsDepthStuds under it and BoundsHeightStuds above.
		local bounds = body(module("Context"), "function Context.insideBounds(", "Context")
		for _, clause in ipairs({
			"BattlegroundLayout.inRect(layout.Bounds, x, z)",
			"y >= -BattlegroundConfig.BoundsDepthStuds",
			"y <= BattlegroundConfig.BoundsHeightStuds",
		}) do
			if bounds:find(clause, 1, true) == nil then
				error("insideBounds no longer checks " .. clause)
			end
		end
	end)

	it("holds nobody with a step they blocked, and throws them on a finisher", function()
		local melee = body(module("Attacks"), "local function resolveMelee(", "Attacks")
		expect(
			melee:find(
				"elseif not result.Blocked then deps.Movement.applyStun(member.Player, BotConfig.MeleeHitStunSeconds)",
				1,
				true
			)
		).never.toBe(nil)
		expect(melee:find("if result.Applied > 0 then if resolve.Final then", 1, true)).never.toBe(nil)
	end)

	it("rests every player its finisher held, and never cuts a rest short", function()
		local melee = body(module("Attacks"), "local function resolveMelee(", "Attacks")
		expect(
			melee:find(
				"if resolve.Final then local held = finish(melee, member.Player, character, aim) if held > 0 then outcome.Held[member.UserId] = held end",
				1,
				true
			)
		).never.toBe(nil)
		local apply = body(module("init"), "local function apply(", "init")
		expect(
			apply:find(
				"for userId, untilTime in pairs(BotBrain.finisherRests(RULES, now, resolve.TargetUserId, outcome.Held)) do rest(userId, untilTime) end",
				1,
				true
			)
		).never.toBe(nil)
		local rest = body(module("init"), "local function rest(", "init")
		expect(rest:find("restUntil[userId] = math.max(restUntil[userId] or 0, untilTime)", 1, true)).never.toBe(nil)
	end)

	it("is announced on the reliable remote for its whole wind-up, on the aim it will land on", function()
		local windup = body(module("Attacks"), "function Attacks.windup(", "Attacks")
		expect(windup:find("Id = Context.TellVfxId,", 1, true)).never.toBe(nil)
		expect(windup:find("Seconds = window,", 1, true)).never.toBe(nil)
		expect(windup:find("Direction = Vector3.new(attack.AimX, 0, attack.AimZ),", 1, true)).never.toBe(nil)
		expect(windup:find("}, true)", 1, true)).never.toBe(nil)
		expect(module("Context"):find('Context.TellVfxId = "ForgerTell"', 1, true)).never.toBe(nil)
		-- The window a wind-up is shown for is the one the brain will resolve it at.
		local apply = body(module("init"), "local function apply(", "init")
		expect(apply:find("Attacks.windup(bot, attack, attack.ResolveAt - now, now)", 1, true)).never.toBe(nil)
	end)
end)

describe("a Forger's body", function()
	it("is simulated by the server, and thrown with a force bounded by its mass", function()
		expect(module("Bots"):find("root:SetNetworkOwner(nil)", 1, true)).never.toBe(nil)
		local forces = 0
		for name, source in pairs(folder()) do
			for line in string.gmatch(source, "[^\n]*MaxForce%s*=[^\n]*") do
				forces += 1
				if
					line:find("math.huge", 1, true) ~= nil
					or line:find("BotConfig.ShoveForcePerMass", 1, true) == nil
				then
					error(("%s sets an unbounded force: %s"):format(name, line))
				end
			end
		end
		expect(forces).toBe(1)
		-- The throw integrates the impulse over each tick, so it covers exactly the flat velocity's distance.
		local step = body(module("Motion"), "function Motion.stepMover(", "Motion")
		expect(step:find("FeelMath.impulseStep(shove.Alpha, alpha, KNOCKBACK_EXPONENT)", 1, true)).never.toBe(nil)
	end)

	it("keeps its tag until it is removed, so a kill effect finds a corpse whatever the event order", function()
		for name, source in pairs(folder()) do
			if source:find("RemoveTag", 1, true) ~= nil then
				error(name .. " removes a Forger's tag before its body is gone")
			end
		end
		expect(module("Bots"):find("CollectionService:AddTag(model, BotConfig.Tag)", 1, true)).never.toBe(nil)
		local kill = body(module("Bots"), "function Bots.kill(", "Bots")
		expect(kill:find(":Destroy(", 1, true)).toBe(nil)
		expect(kill:find("bot.DestroyAt = now + BotConfig.CorpseSeconds", 1, true)).never.toBe(nil)
	end)
end)

describe("a member", function()
	it("is placed with trust re-anchored on the landing the server chose", function()
		local place = body(module("Roster"), "function Roster.place(", "Roster")
		expect(
			place:find(
				"Teleport.place(deps.Combat, player, character, CFrame.lookAt(landing, Vector3.new(center.X, landing.Y, center.Z)))",
				1,
				true
			)
		).never.toBe(nil)
		local enter = body(module("init"), "function BattlegroundService.enter(", "init")
		expect(ordered(enter, "Roster.place(player, character, landing)", "Roster.admit(")).toBe(true)
		local redirect = body(module("Roster"), "local function redirect(", "Roster")
		expect(ordered(redirect, "Roster.place(player, character, landing)", "Roster.admit(")).toBe(true)
	end)

	it("is asked everything again after the world streams in", function()
		-- Whether the page takes them at all is one question, which the hub's gate asks too (PortalService).
		local admits = body(module("init"), "function BattlegroundService.admits(", "init")
		local refusals = {
			'return false, "portal.unavailable"',
			'return false, "queue.inMatch"',
			'return false, "battleground.full"',
		}
		local cursor = 1
		for _, refusal in ipairs(refusals) do
			local found = admits:find(refusal, cursor, true)
			if found == nil then
				error("admits no longer refuses, in order: " .. refusal)
			end
			cursor = found + #refusal
		end
		expect(admits:find("if handle == nil or not Bots.ready() then", 1, true)).never.toBe(nil)
		local enter = body(module("init"), "function BattlegroundService.enter(", "init")
		local steps = {
			"local admitted, refusal = BattlegroundService.admits(player)",
			"if not admitted then return false, refusal end",
			"Teleport.streamAround(player, landing)",
			"deps.Match.isInMatch(player)",
			"Roster.hasRoom(player)",
			"deps.WorldBoss.isEngaged(player)",
			"player.Character ~= character",
			"Roster.place(",
		}
		local from = 1
		for _, step in ipairs(steps) do
			local at = enter:find(step, from, true)
			if at == nil then
				error("enter no longer asks, in order: " .. step)
			end
			from = at + #step
		end
	end)

	it("who died inside comes back only if nothing claimed them while the body loaded", function()
		local redirect = body(module("Roster"), "local function redirect(", "Roster")
		expect(ordered(redirect, "WaitForChild(", "deps.Match.isInMatch(player)")).toBe(true)
		expect(ordered(redirect, "WaitForChild(", "deps.WorldBoss.isEngaged(player)")).toBe(true)
		expect(ordered(redirect, "WaitForChild(", "player.Character ~= character")).toBe(true)
		local added = body(module("Roster"), "local function onCharacterAdded(", "Roster")
		expect(added:find("task.defer(redirect,", 1, true)).never.toBe(nil)
		expect(added:find("Players.RespawnTime + BattlegroundConfig.RespawnRedirectGraceSeconds", 1, true)).never.toBe(
			nil
		)
	end)

	it("is off the floor sunk under it as much as hung over it", function()
		local observe = body(module("Roster"), "local function observe(", "Roster")
		expect(
			observe:find(
				"if BotBrain.outOfReach(Context.Rules, point.Y - standingRoot) then member.OffFloorSince = member.OffFloorSince or now else member.OffFloorSince = nil end",
				1,
				true
			)
		).never.toBe(nil)
	end)

	it("is measured from the ground under them, so the raised place is floor to a Forger and its credit", function()
		local observe = body(module("Roster"), "local function observe(", "Roster")
		expect(
			observe:find(
				"local standingRoot = handle.FloorY + BattlegroundLayout.groundAt(handle.Layout, x, z) + BattlegroundConfig.StandingRootStuds",
				1,
				true
			)
		).never.toBe(nil)
		-- A Forger and its quarry are each as high as they stand over their own ground, so the place's stairs are
		-- no escape from one that walks up them.
		expect(count(module("Perception"), "Y = y - BattlegroundLayout.groundAt(handle.Layout, x, z),")).toBe(2)
		-- A tell is drawn on the ground its Forger stands on.
		local attacks = module("Attacks")
		local under = body(attacks, "local function groundUnder(", "Attacks")
		expect(under:find("handle.FloorY + BattlegroundLayout.groundAt(handle.Layout, x, z)", 1, true)).never.toBe(nil)
		expect(count(attacks, "Origin = groundUnder(bot.Root.Position),")).toBe(2)
		expect(attacks:find("handle.FloorY, root.Z", 1, true)).toBe(nil)
	end)

	it("stays one only while in no match, not the Erasure's, and on the page by trusted position", function()
		local stays = body(module("Roster"), "local function stays(", "Roster")
		for _, question in ipairs({
			"deps.Match.isInMatch(player)",
			"deps.WorldBoss.isEngaged(player)",
			"local trusted = deps.Combat.trustedPosition(player)",
			"return Context.insideBounds(handle.Layout, trusted)",
			"deps.Combat.resyncPosition(player, member.Landing)",
		}) do
			if stays:find(question, 1, true) == nil then
				error("the roster no longer asks: " .. question)
			end
		end
		-- The raw root is what a client says; nothing that decides membership may read it.
		expect(stays:find(".Position", 1, true)).toBe(nil)
		expect(stays:find("liveRoot", 1, true)).toBe(nil)
	end)
end)

describe("the page's free-for-all (D-282)", function()
	it("claims the Battleground zone for its members, any pair of them", function()
		local start = body(module("init"), "function BattlegroundService.Start(", "init")
		expect(start).toContain(
			'deps.Combat.claimZone("Battleground", { Holds = function(player: Player): boolean return Roster.get(player) ~= nil end, Pair = function(_source: Player, _target: Player): boolean return true end, })'
		)
	end)

	it("puts the arrival bubble on every member it admits, through the gate or back from a death", function()
		local admit = body(module("Roster"), "function Roster.admit(", "Roster")
		expect(
			ordered(
				admit,
				"members[player] = member",
				"deps.Combat.protect(player, BattlegroundConfig.ArrivalProtectionSeconds)"
			)
		).toBe(true)
	end)
end)

describe("a member's landing (D-282)", function()
	-- Three arrivals in a row, 100 studs apart, on a Roster whose members stand wherever the test says.
	local function landings(): (any, any, { [any]: any }, (userId: number) -> any)
		local world = Server.world({ Stubs = { [DIR .. "Map"] = {} } })
		local Roster = world.require(DIR .. "Roster")
		local origin = world.require(DIR .. "Context").Origin
		local markers, points, trusted = {}, {}, {}
		for index = 1, 3 do
			local x = (index - 2) * 100
			markers[index] = { Position = origin + roblox.Vector3.new(x, 0, 0) }
			points[index] = { X = x, Z = 0 }
		end
		Roster.Init({
			Registry = { fire = function() end },
			Combat = {
				protect = function() end,
				trustedPosition = function(player: any): any
					return trusted[player]
				end,
			},
		}, { Arrivals = markers, Layout = { Arrivals = points } }, function(): number
			return 0
		end)
		local function admitAt(index: number): any
			local player = world:join(index, "P" .. index)
			player:LoadCharacterAsync()
			Roster.admit(player, player.Character, markers[index].Position, 0, 0)
			trusted[player] = markers[index].Position
			return player
		end
		return Roster, markers, trusted, admitAt
	end

	it("is the arrival furthest from every member already standing, never one in somebody's reach", function()
		local Roster, markers, _, admitAt = landings()
		admitAt(1)
		admitAt(2)
		expect(Roster.nextLanding().X).toBe(markers[3].Position.X)
	end)

	it("takes the arrivals in turn on an empty page, so two who arrive together never share one", function()
		local Roster, markers = landings()
		expect(Roster.nextLanding().X).toBe(markers[1].Position.X)
		expect(Roster.nextLanding().X).toBe(markers[2].Position.X)
	end)
end)

describe("the lock-on onto the page's members (D-282)", function()
	it("marks a member's body for the lock, and takes the mark off when the page lets them go or they die", function()
		local world = Server.world({ Stubs = { [DIR .. "Map"] = {} } })
		local Roster = world.require(DIR .. "Roster")
		Roster.Init({
			Registry = { fire = function() end },
			Combat = { protect = function() end },
		}, { Arrivals = {} }, function(): number
			return 0
		end)
		local mark = BattlegroundConfig.MemberAttribute
		local function admitted(userId: number): (any, any, any)
			local player = world:join(userId, "P" .. userId)
			player:LoadCharacterAsync()
			local character = player.Character
			Roster.admit(player, character, roblox.Vector3.new(0, 0, 0), 0, 0)
			return player, character, character:FindFirstChildOfClass("Humanoid")
		end
		local dropped, droppedBody = admitted(1)
		expect(droppedBody:GetAttribute(mark)).toBe(true)
		Roster.drop(dropped)
		expect(droppedBody:GetAttribute(mark)).toBeNil()
		local _, deadBody, humanoid = admitted(2)
		expect(deadBody:GetAttribute(mark)).toBe(true)
		humanoid.Health = 0
		humanoid.Died:Fire()
		expect(deadBody:GetAttribute(mark)).toBeNil()
	end)

	it("lets the lock take another member only from a member's body, on the page both stand on", function()
		local source = code(LOCK_ON)
		local members = body(source, "local function addMembers(", "LockOnController")
		for _, line in ipairs({
			"if own == nil or own:GetAttribute(attribute) ~= true then",
			"if other ~= player and body ~= nil and body:GetAttribute(attribute) == true then",
			'local lock = lockOf(body, "Player")',
		}) do
			expect(members).toContain(line)
		end
		local opponents = body(source, "local function opponents(", "LockOnController")
		expect(opponents).toContain("addMembers(out, FlyleafConfig.MemberAttribute)")
		expect(opponents).toContain("addMembers(out, BattlegroundConfig.MemberAttribute)")
	end)
end)

-- Rewards on a pretend server, the roster and the bubble stubbed: what a member's kill of another pays.
type Kills = {
	rewards: any,
	held: { [any]: boolean },
	-- Held by the page but not a member: they died inside and wait for their next body.
	pending: { [any]: boolean },
	shielded: { [any]: boolean },
	xp: { [any]: number },
	folios: { [any]: number },
	profiles: { [any]: any },
	said: { string },
	join: (userId: number) -> any,
}

local function kills(): Kills
	local fx: any = { held = {}, pending = {}, shielded = {}, xp = {}, folios = {}, profiles = {}, said = {} }
	local world = Server.world({
		Stubs = {
			[DIR .. "Bots"] = {},
			[DIR .. "Map"] = {},
			[DIR .. "Roster"] = {
				holds = function(player: any): boolean
					return fx.held[player] == true
				end,
				get = function(player: any): any
					return if fx.held[player] == true and fx.pending[player] ~= true then { Player = player } else nil
				end,
			},
		},
	})
	fx.rewards = world.require(DIR .. "Rewards")
	fx.rewards.Init({
		DataService = {
			get = function(player: any): any
				local data = fx.profiles[player]
				if data == nil then
					data = { Daily = { ForgerDay = 0, ForgerFolios = 0, PlayerKillDay = 0, PlayerKillXp = 0 } }
					fx.profiles[player] = data
				end
				return data
			end,
			push = function(_player: any, _section: string) end,
		},
		Notify = {
			send = function(_player: any, key: string, _params: any, _kind: any, _sfx: any)
				table.insert(fx.said, key)
			end,
		},
		Combat = {
			isProtected = function(player: any): boolean
				return fx.shielded[player] == true
			end,
		},
		Progression = {
			addXp = function(player: any, amount: number, _reason: string): number
				fx.xp[player] = (fx.xp[player] or 0) + amount
				return amount
			end,
		},
		Currency = {
			add = function(player: any, amount: number, _reason: string): number
				fx.folios[player] = (fx.folios[player] or 0) + amount
				return amount
			end,
		},
	}, {})
	function fx.join(userId: number): any
		local player = world:join(userId, "P" .. userId)
		fx.held[player] = true
		return player
	end
	return fx :: Kills
end

describe("a member's kill of another (D-282)", function()
	local KILL = BattlegroundConfig.PlayerKill

	it("pays once, then nothing for the same victim until the pair has rested PairCooldownSeconds", function()
		local fx = kills()
		local a, b = fx.join(1), fx.join(2)
		fx.rewards.payPlayer(a, b, 100)
		expect(fx.xp[a]).toBe(KILL.Xp)
		expect(fx.folios[a]).toBe(KILL.Folios)
		expect(table.find(fx.said, "hud.playerKill") ~= nil).toBe(true)
		fx.rewards.payPlayer(a, b, 100 + KILL.PairCooldownSeconds - 1)
		expect(fx.xp[a]).toBe(KILL.Xp)
		-- The other way round is the same pair: two players trading kills earn once, not each time.
		fx.rewards.payPlayer(b, a, 101)
		expect(fx.xp[b]).toBeNil()
		-- PairCooldownSeconds after the pair's last kill, paid or not, it pays again.
		fx.rewards.payPlayer(a, b, 100 + 2 * KILL.PairCooldownSeconds)
		expect(fx.xp[a]).toBe(2 * KILL.Xp)
	end)

	it(
		"pays nothing to a killer who died inside and waits for their next body, though the page still holds them",
		function()
			local fx = kills()
			local a, b = fx.join(1), fx.join(2)
			fx.pending[a] = true
			fx.rewards.payPlayer(a, b, 0)
			expect(fx.xp[a]).toBeNil()
			-- A refused kill took no payment from the pair.
			fx.pending[a] = false
			fx.rewards.payPlayer(a, b, 1)
			expect(fx.xp[a]).toBe(KILL.Xp)
			-- A victim in the same state is still paid for: the death the hub credits to the last blow.
			fx.pending[b] = true
			fx.rewards.payPlayer(a, b, 2 * KILL.PairCooldownSeconds)
			expect(fx.xp[a]).toBe(2 * KILL.Xp)
		end
	)

	it("pays nothing under a bubble, nor for a killer or a victim the page does not hold, nor for oneself", function()
		local fx = kills()
		local a, b = fx.join(1), fx.join(2)
		fx.shielded[b] = true
		fx.rewards.payPlayer(a, b, 0)
		fx.shielded[b] = false
		fx.held[a] = false
		fx.rewards.payPlayer(a, b, 0)
		fx.held[a] = true
		-- A victim who walked home before the death the hub credits to the last blow.
		fx.held[b] = false
		fx.rewards.payPlayer(a, b, 0)
		fx.held[b] = true
		fx.rewards.payPlayer(a, a, 0)
		expect(fx.xp[a]).toBeNil()
		-- None of those took the pair's payment.
		fx.rewards.payPlayer(a, b, 1)
		expect(fx.xp[a]).toBe(KILL.Xp)
	end)

	it("takes its Folios out of the Forgers' daily allowance in the profile, and says once when it is spent", function()
		local fx = kills()
		local a, b, c = fx.join(1), fx.join(2), fx.join(3)
		local cap = BotConfig.Credit.DailyFolioCap
		fx.profiles[a] = { Daily = { ForgerDay = DailyStreak.dayIndex(os.time()), ForgerFolios = cap - 1 } }
		fx.rewards.payPlayer(a, b, 0)
		expect(fx.folios[a]).toBe(1)
		expect(fx.profiles[a].Daily.ForgerFolios).toBe(cap)
		fx.rewards.payPlayer(a, c, 0)
		expect(fx.folios[a]).toBe(1)
		expect(fx.xp[a]).toBe(2 * KILL.Xp)
		fx.rewards.payPlayer(b, c, 0)
		local told = 0
		for _, key in ipairs(fx.said) do
			if key == "battleground.folioCap" then
				told += 1
			end
		end
		expect(told).toBe(1)
	end)

	it("pays its XP out of a daily allowance in the profile too, so another server does not reopen it", function()
		local fx = kills()
		local a, b, c = fx.join(1), fx.join(2), fx.join(3)
		local cap = KILL.DailyXpCap
		expect(cap).toBeGreaterThan(KILL.Xp)
		fx.profiles[a] = {
			Daily = {
				ForgerDay = 0,
				ForgerFolios = 0,
				PlayerKillDay = DailyStreak.dayIndex(os.time()),
				PlayerKillXp = cap - 10,
			},
		}
		-- What is left of the day's allowance is paid, and the count goes back to the profile.
		fx.rewards.payPlayer(a, b, 0)
		expect(fx.xp[a]).toBe(10)
		expect(fx.profiles[a].Daily.PlayerKillXp).toBe(cap)
		-- Past it a kill pays no XP, and the Folios still come out of their own allowance.
		fx.rewards.payPlayer(a, c, 0)
		expect(fx.xp[a]).toBe(10)
		expect(fx.folios[a]).toBe(2 * KILL.Folios)
		-- Another day starts from nothing.
		fx.profiles[a].Daily.PlayerKillDay -= 1
		fx.rewards.payPlayer(a, b, 2 * KILL.PairCooldownSeconds)
		expect(fx.xp[a]).toBe(10 + KILL.Xp)
		expect(fx.profiles[a].Daily.PlayerKillXp).toBe(KILL.Xp)
	end)

	it("is heard on Killed for a player's body, before any Forger is looked for, and pruned every tick", function()
		local init = module("init")
		local killed = body(init, "local function onKilled(", "init")
		expect(
			ordered(
				killed,
				'log.try("Rewards.payPlayer", Rewards.payPlayer, killer, victim, os.clock())',
				"Bots.byModel(model)"
			)
		).toBe(true)
		expect(body(init, "local function tick(", "init")).toContain("Rewards.prune(now)")
	end)
end)

describe("a Forger's kill", function()
	it("is credited once, by model, and only where a Forger could have answered", function()
		local init = module("init")
		expect(init:find("deps.Combat.Killed:Connect(onKilled)", 1, true)).never.toBe(nil)
		local killed = body(init, "local function onKilled(", "init")
		expect(ordered(killed, "bot.Credited = true", "Rewards.pay")).toBe(true)
		expect(killed:find("if bot == nil or bot.Credited then return end", 1, true)).never.toBe(nil)
		local pay = body(module("Rewards"), "function Rewards.pay(", "Rewards")
		expect(pay:find("BotBrain.creditable(inCamp, ignoredUntil, member.OffFloorSince, now, Context.Rules)", 1, true)).never.toBe(
			nil
		)
		expect(ordered(pay, "BotBrain.creditable(", "payOne(")).toBe(true)
		for name, source in pairs(folder()) do
			if source:find("LastAttackerUserId", 1, true) ~= nil then
				error(name .. " reads the last attacker off a Humanoid: attribution comes from the signals")
			end
		end
	end)

	it("earns nothing for a hit from the camp, whose points go back to the Forger", function()
		local damaged = body(module("init"), "local function onDamaged(", "init")
		for _, line in ipairs({
			"local fromCamp = hitFromCamp(map, sourceUserId) local refund = BotBrain.creditHit(bot.Ledger, sourceUserId, applied, fromCamp)",
			"if refund > 0 and humanoid.Health > 0 then humanoid.Health = math.min(humanoid.Health + refund, humanoid.MaxHealth) end",
		}) do
			if damaged:find(line, 1, true) == nil then
				error("onDamaged no longer holds: " .. line)
			end
		end
		-- The killing blow is weighed like any other, before the dead are turned away.
		expect(ordered(damaged, "BotBrain.creditHit(", "if bot.Dead then return end")).toBe(true)
		-- A camp hit neither staggers the Forger nor draws it: it is told to its dealer and ends there.
		expect(damaged:find("if fromCamp then noticeCampHit(sourceUserId, now) return end", 1, true)).never.toBe(nil)
		expect(ordered(damaged, "if fromCamp then", "BotBrain.noteHit(")).toBe(true)
		expect(ordered(damaged, "if fromCamp then", "stagger(bot, now,")).toBe(true)
		local notice = body(module("init"), "local function noticeCampHit(", "init")
		expect(notice:find("campNoticeUntil[source] = now + CAMP.HitNoticeSeconds", 1, true)).never.toBe(nil)
		expect(notice:find('deps.Notify.send(source, "battleground.campHit", nil, "Info")', 1, true)).never.toBe(nil)
		local removing = body(module("init"), "local function onPlayerRemoving(", "init")
		expect(removing:find("campNoticeUntil[player] = nil", 1, true)).never.toBe(nil)
		-- Where the hit came from is where a Forger sees its dealer, in the camp the pay reads.
		local camp = body(module("init"), "local function hitFromCamp(", "init")
		expect(camp:find("Context.targetPoint(deps.Combat, source)", 1, true)).never.toBe(nil)
		expect(camp:find("return point ~= nil and Context.inCamp(map.Layout, point)", 1, true)).never.toBe(nil)
		-- BotBrain.creditHit is the only way into a ledger.
		for name, source in pairs(folder()) do
			if source:find("Ledger[", 1, true) ~= nil then
				error(name .. " writes a Forger's ledger past BotBrain.creditHit")
			end
		end
	end)

	it("pays its Folios out of the day's allowance kept in the profile", function()
		local take = body(module("Rewards"), "local function takeFolios(", "Rewards")
		expect(take:find("DailyCap.take(daily.ForgerDay, daily.ForgerFolios, today, CREDIT.DailyFolioCap,", 1, true)).never.toBe(
			nil
		)
		expect(take:find("daily.ForgerDay = today daily.ForgerFolios = used", 1, true)).never.toBe(nil)
	end)
end)

describe("the service's running", function()
	it("starts no timer, waits nowhere but in its own threads, and wraps every pcall in a log", function()
		for name, source in pairs(folder()) do
			for _, banned in ipairs({ "task.delay", "task.wait", "while true", "pcall(", "Debris" }) do
				if source:find(banned, 1, true) ~= nil then
					error(("%s uses %s"):format(name, banned))
				end
			end
		end
		-- The one wait on the world: a respawned body's root, in the deferred thread that redirects it.
		local waits = 0
		for _, source in pairs(folder()) do
			waits += count(source, "WaitForChild(") - count(source, 'ReplicatedStorage:WaitForChild("')
		end
		expect(waits).toBe(1)
		expect(module("Roster"):find("character:WaitForChild(Context.RootPartName, Context.RootWaitSeconds)", 1, true)).never.toBe(
			nil
		)
	end)
end)

describe("the rests", function()
	it("are forgotten once over, so nobody who left mid-chain stays in the table", function()
		local tick = body(module("init"), "local function tick(", "init")
		expect(
			tick:find(
				"for userId, untilTime in pairs(restUntil) do if untilTime <= now then restUntil[userId] = nil end end",
				1,
				true
			)
		).never.toBe(nil)
		-- Every other write goes through rest(), which only lengthens one, or forgets a player leaving.
		local allowed = {
			["restUntil[userId] = math.max(restUntil[userId] or 0, untilTime)"] = true,
			["restUntil[userId] = nil"] = true,
			["restUntil[player.UserId] = nil"] = true,
		}
		local writes = 0
		for write in string.gmatch(module("init"), "restUntil%[[%w%.]+%] = [^\n]*") do
			writes += 1
			if not allowed[write] then
				error("restUntil is written outside rest(): " .. write)
			end
		end
		expect(writes).toBe(3)
	end)
end)

describe("what the Battleground asked of the rest of the server", function()
	it("CombatService throws a body no player owns through Shoved, and trusts without judging", function()
		local combat = code(COMBAT)
		local knockback = body(combat, "function CombatService.knockback(", "CombatService")
		expect(
			knockback:find(
				"if player == nil then CombatService.Shoved:Fire(targetModel, velocity, duration) return end",
				1,
				true
			)
		).never.toBe(nil)
		local trusted = body(combat, "function CombatService.trustedPosition(", "CombatService")
		expect(trusted:find("trustedCFrame", 1, true)).toBe(nil)
		expect(trusted:find("countViolation", 1, true)).toBe(nil)
		expect(trusted:find("return state.TrustedPosition", 1, true)).never.toBe(nil)
		local control = body(combat, "function CombatService.controlNpc(", "CombatService")
		expect(ordered(control, "Players:GetPlayerFromCharacter(targetModel) ~= nil", "Controlled:Fire(")).toBe(true)
		local heal = body(combat, "function CombatService.heal(", "CombatService")
		expect(heal:find("if os.clock() - state.LastDamageTakenAt < quietSeconds then return 0 end", 1, true)).never.toBe(
			nil
		)
		expect(heal:find("math.min(amount, humanoid.MaxHealth - humanoid.Health)", 1, true)).never.toBe(nil)
	end)

	it("GlyphEffects holds a Forger with every stun and slow it holds a player with", function()
		local effects = code(EFFECTS)
		-- Movement is asked once for each, inside the helpers; every other site goes through them. A player's stun is
		-- a glyph's, which the grace may refuse (D-213), never a combat hold.
		expect(count(effects, "ctx.Movement.applyGlyphStun(")).toBe(1)
		expect(count(effects, "ctx.Movement.applyStun(")).toBe(0)
		expect(count(effects, "ctx.Movement.applySlow(")).toBe(1)
		local stun = body(effects, "local function stunModel(", "GlyphEffects")
		expect(stun:find('else ctx.Combat.controlNpc(model, "Stun", seconds, 0, ctx.Def.Id) end', 1, true)).never.toBe(
			nil
		)
		local slow = body(effects, "local function slowModel(", "GlyphEffects")
		expect(slow:find('else ctx.Combat.controlNpc(model, "Slow", seconds, factor, ctx.Def.Id) end', 1, true)).never.toBe(
			nil
		)
		-- The eight sites that held players only: four stuns (a spike line, a launch, a zone, a chain) and four
		-- slows (two zones, a root, a single target).
		expect(count(effects, "stunModel(ctx,")).toBeGreaterThanOrEqual(4)
		expect(count(effects, "slowModel(ctx,")).toBeGreaterThanOrEqual(4)
	end)

	it("CombatService hands a Forger each glyph's slow under that glyph, and the Forger keeps them apart", function()
		local control = body(code(COMBAT), "function CombatService.controlNpc(", "CombatService")
		expect(control:find("CombatService.Controlled:Fire(targetModel, kind, seconds, factor, key)", 1, true)).never.toBe(
			nil
		)
		expect(ordered(control, 'if type(key) ~= "string" or key == "" then', "Controlled:Fire(")).toBe(true)
		local controlled = body(module("init"), "local function onControlled(", "init")
		expect(controlled:find("Motion.slow(bot, key, factor, seconds, now)", 1, true)).never.toBe(nil)
		local motion = module("Motion")
		expect(
			body(motion, "function Motion.slow(", "Motion"):find(
				"BotBrain.addSlow(bot.Slows, key, factor, seconds, now)",
				1,
				true
			)
		).never.toBe(nil)
		expect(
			body(motion, "local function pace(", "Motion"):find(
				"local speed = bot.Def.WalkSpeed * BotBrain.slowFactor(bot.Slows, now)",
				1,
				true
			)
		).never.toBe(nil)
		expect(body(motion, "function Motion.stepSlow(", "Motion"):find("pace(bot, now)", 1, true)).never.toBe(nil)
		-- And every living Forger is stepped each tick, or a root would hold until the next slow came along.
		expect(body(module("init"), "local function maintain(", "init"):find("Motion.stepSlow(bot, now)", 1, true)).never.toBe(
			nil
		)
		-- Nothing sets a Forger's pace but its spawn and the slows.
		local paces = 0
		for _, source in pairs(folder()) do
			paces += count(source, "WalkSpeed =")
		end
		expect(paces).toBe(2)
	end)

	it(
		"GlyphService refuses free casting on the page, and the bootstrap wires the service after the Erasure",
		function()
			local glyphs = code(GLYPHS)
			local perks = body(glyphs, "local function developerPerks(", "GlyphService")
			expect(perks:find("and not battleground.isInside(player)", 1, true)).never.toBe(nil)
			local free = body(glyphs, "local function freeCasting(", "GlyphService")
			expect(free:find("DeveloperConfig.FreeCasting and developerPerks(player)", 1, true)).never.toBe(nil)
			local bootstrap = code(BOOTSTRAP)
			expect(bootstrap:find("Battleground = BattlegroundService,", 1, true)).never.toBe(nil)
			expect(
				ordered(
					bootstrap,
					'{ Name = "WorldBossService", Service = WorldBossService }',
					'{ Name = "BattlegroundService", Service = BattlegroundService }'
				)
			).toBe(true)
		end
	)
end)
