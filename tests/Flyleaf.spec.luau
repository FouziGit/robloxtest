--!strict
-- The Flyleaf (« La Page de garde », E16-S2). Its page is built by the pure FlyleafLayout from FlyleafConfig, and
-- what it decides -- where a member lands, what a kill pays, who wears the Manicule -- is the pure FlyleafRules':
-- both are run here first. Then the real FlyleafService, on a pretend server: members who enter and fight, die and
-- come back on the furthest seal three seconds later, a pair of friends who stop earning off each other, the day's
-- Folios cap, the Manicule, and every way out.
local DamageZones = require("../src/server/Pure/DamageZones")
local FlyleafConfig = require("../src/shared/Config/FlyleafConfig")
local FlyleafLayout = require("../src/server/Pure/FlyleafLayout")
local FlyleafRules = require("../src/server/Pure/FlyleafRules")
local GameConfig = require("../src/shared/Config/GameConfig")
local Gate = require("./gate")
local Harness = require("./harness")
local PortalConfig = require("../src/shared/Config/PortalConfig")
local Server = require("./server")
local WorldConfig = require("../src/shared/Config/WorldConfig")
local ZoneConfig = require("../src/shared/Config/ZoneConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MAP = FlyleafConfig.Map
local DRESSING: FlyleafLayout.Dressing = {
	FloorName = FlyleafConfig.Anchors.Floor,
	KillZoneName = FlyleafConfig.Anchors.KillZone,
	WallRuleStuds = WorldConfig.Arena.WallRuleStuds,
	WallRuleProudStuds = WorldConfig.Arena.WallRuleProudStuds,
	FlatThickness = WorldConfig.FlatThicknessStuds,
	RuleTop = WorldConfig.Ladder.Rule,
}
-- The double jump's reach: two jumps of GameConfig.Movement under the engine's gravity.
local DOUBLE_JUMP_STUDS = 2 * GameConfig.Movement.JumpPower ^ 2 / (2 * 196.2)

local function distance(a: { X: number, Z: number }, b: { X: number, Z: number }): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

describe("the Flyleaf's page", function()
	local layout = FlyleafLayout.build(MAP, DRESSING)

	it(
		"is a page of 120 studs, far from the hub and the Battleground, every packet on it reaching all of it",
		function()
			expect(MAP.Size).toBe(120)
			local origin = MAP.Origin
			-- Past the fog and every packet's reach from the hub's 200-stud platform, and from the Battleground's page.
			expect(math.abs(origin[1]) - MAP.Size / 2 - 100).toBeGreaterThan(860)
			expect(math.abs(origin[1] - 1500)).toBeGreaterThan(GameConfig.Vfx.BroadcastRadiusStuds + 85 + MAP.Size / 2)
			expect(MAP.Size * math.sqrt(2)).toBeLessThan(GameConfig.Vfx.BroadcastRadiusStuds)
		end
	)

	it("has six arrival seals on the floor, apart, clear of the cover and of the circle home", function()
		expect(#layout.Seals).toBe(6)
		local sealRadius = MAP.SealDiameterStuds / 2 + MAP.SealRimStuds
		for index, seal in ipairs(layout.Seals) do
			expect(FlyleafLayout.inRect(layout.Bounds, seal.X - sealRadius, seal.Z - sealRadius)).toBe(true)
			expect(FlyleafLayout.inRect(layout.Bounds, seal.X + sealRadius, seal.Z + sealRadius)).toBe(true)
			-- Nobody lands in the circle that sends them home.
			expect(distance(seal, layout.ReturnGate)).toBeGreaterThan(PortalConfig.ZoneRadiusStuds + sealRadius + 2)
			for _, rect in ipairs(layout.Obstacles) do
				local dx = math.max(rect.MinX - seal.X, 0, seal.X - rect.MaxX)
				local dz = math.max(rect.MinZ - seal.Z, 0, seal.Z - rect.MaxZ)
				expect(math.sqrt(dx * dx + dz * dz)).toBeGreaterThan(sealRadius + 4)
			end
			for other = index + 1, #layout.Seals do
				expect(distance(seal, layout.Seals[other])).toBeGreaterThan(2 * sealRadius + 20)
			end
		end
	end)

	it("stands its gate home against the north wall, inside it, facing the page", function()
		local gate = layout.ReturnGate
		local footprint = Gate.footprint()
		-- Facing south (+z): behind the gate is the north wall, whose inner face is the floor's edge.
		for _, corner in ipairs(Gate.corners(gate.X, gate.Z, 0, 1)) do
			expect(FlyleafLayout.inRect(layout.Bounds, corner[1], corner[2])).toBe(true)
		end
		expect(math.abs(gate.Z - footprint.Back - layout.Bounds.MinZ) < 1e-9).toBe(true)
		for _, rect in ipairs(layout.Obstacles) do
			expect(rect.MinZ).toBeGreaterThan(gate.Z + footprint.Front)
		end
	end)

	it("offers cover, and no perch above the fight", function()
		expect(#layout.Obstacles).toBeGreaterThanOrEqual(4)
		expect(MAP.CoverHeight).toBeGreaterThan(DOUBLE_JUMP_STUDS)
		local walls = 0
		for _, box in ipairs(layout.Boxes) do
			expect(WorldConfig.Flyleaf[box.Role] ~= nil).toBe(true)
			if box.Role == "Wall" then
				walls += 1
				expect(box.SizeY).toBeGreaterThan(DOUBLE_JUMP_STUDS)
			end
		end
		expect(walls).toBe(4)
	end)

	it("is a hub gate away, and two players trade their first blows within ten seconds", function()
		-- The stay in the circle, the most a trip waits for the page to stream in, then the longer of the protection
		-- and the walk that brings the two furthest seals within a swing of each other: the protection runs while
		-- they walk. Measured with two clients in Studio too (docs/QA.md §6 ter).
		local furthest = 0
		for index, seal in ipairs(layout.Seals) do
			for other = index + 1, #layout.Seals do
				furthest = math.max(furthest, distance(seal, layout.Seals[other]))
			end
		end
		local walk = (furthest / 2) / GameConfig.Movement.WalkSpeed
		local budget = PortalConfig.Zones.Flyleaf.DwellSeconds
			+ PortalConfig.StreamTimeoutSeconds
			+ math.max(FlyleafConfig.ProtectionSeconds, walk)
		expect(budget).toBeLessThanOrEqual(10)
	end)
end)

describe("the Flyleaf's rules", function()
	it("are the story's numbers", function()
		expect(FlyleafConfig.ProtectionSeconds).toBe(4)
		expect(FlyleafConfig.RespawnSeconds).toBe(3)
		expect(FlyleafConfig.Rewards).toEqual({ Xp = 60, Folios = 5, DailyFolioCap = 100 })
		expect(FlyleafConfig.ManiculeKills).toBe(3)
		expect(FlyleafConfig.Farm).toEqual({ MaxPaidDeaths = 3, WindowSeconds = 600 })
		-- Its zone: members hurt members, nothing else, and it pays its own kills.
		local rules = (ZoneConfig.Rules :: any) :: { [string]: DamageZones.Rule }
		expect(DamageZones.judge(rules, "Flyleaf", "Flyleaf")).toBe("Owner")
		expect(DamageZones.judge(rules, "Flyleaf", "Hub")).toBe("Refuse")
		expect(DamageZones.judge(rules, "Hub", "Flyleaf")).toBe("Refuse")
		expect(DamageZones.judge(rules, "Flyleaf", nil)).toBe("Refuse")
		expect(DamageZones.combatPays(rules, "Flyleaf")).toBe(false)
	end)

	it("land a member on the seal furthest from every other one, and take turns on an empty page", function()
		local seals = FlyleafLayout.seals(MAP)
		expect(FlyleafRules.farthestSeal(seals, {}, 1)).toBe(1)
		expect(FlyleafRules.farthestSeal(seals, {}, 2)).toBe(2)
		expect(FlyleafRules.farthestSeal(seals, {}, 7)).toBe(1)
		-- One rival on seal 1 (due east): the new member lands opposite, due west.
		expect(FlyleafRules.farthestSeal(seals, { seals[1] }, 1)).toBe(4)
		-- Two rivals, east and west: the four others are as far from the nearest; the first of them wins.
		expect(FlyleafRules.farthestSeal(seals, { seals[1], seals[4] }, 1)).toBe(2)
		-- Somebody standing in the middle of the page does not decide anything by being near every seal alike.
		local near = { X = seals[3].X * 0.9, Z = seals[3].Z * 0.9 }
		expect(FlyleafRules.farthestSeal(seals, { near }, 1)).toBe(6)
	end)

	it("pay three deaths to the same killer within ten minutes, and nothing past them", function()
		local ledger: FlyleafRules.Ledger = {}
		local rules = FlyleafConfig.Farm
		expect(FlyleafRules.recordKill(ledger, 1, 2, 0, rules)).toBe(true)
		expect(FlyleafRules.recordKill(ledger, 1, 2, 100, rules)).toBe(true)
		expect(FlyleafRules.recordKill(ledger, 1, 2, 200, rules)).toBe(true)
		expect(FlyleafRules.recordKill(ledger, 1, 2, 300, rules)).toBe(false)
		expect(FlyleafRules.recordKill(ledger, 1, 2, 599, rules)).toBe(false)
		-- Anybody else is still worth it, and so is the victim to anybody else.
		expect(FlyleafRules.recordKill(ledger, 1, 3, 300, rules)).toBe(true)
		expect(FlyleafRules.recordKill(ledger, 3, 2, 300, rules)).toBe(true)
		-- A death leaves the window after ten minutes: at 700 the ones at 100, 200 and 300 still count (the one at 0
		-- has left), so it is still one too many.
		expect(FlyleafRules.recordKill(ledger, 1, 2, 700, rules)).toBe(false)
		-- Ten quiet minutes and the pair starts again from nothing.
		expect(FlyleafRules.recordKill(ledger, 1, 2, 1400, rules)).toBe(true)
	end)

	it("forget a pair once its last death has left the window, and only then", function()
		local ledger: FlyleafRules.Ledger = {}
		local rules = FlyleafConfig.Farm
		FlyleafRules.recordKill(ledger, 1, 2, 0, rules)
		FlyleafRules.recordKill(ledger, 1, 3, 500, rules)
		FlyleafRules.prune(ledger, 599, rules)
		expect(ledger[1][2] ~= nil).toBe(true)
		FlyleafRules.prune(ledger, 600, rules)
		expect(ledger[1][2]).toBeNil()
		expect(ledger[1][3] ~= nil).toBe(true)
		FlyleafRules.prune(ledger, 1100, rules)
		expect(ledger[1]).toBeNil()
	end)

	it("put the Manicule on a run of three", function()
		expect(FlyleafRules.wearsManicule(2, FlyleafConfig.ManiculeKills)).toBe(false)
		expect(FlyleafRules.wearsManicule(3, FlyleafConfig.ManiculeKills)).toBe(true)
		expect(FlyleafRules.wearsManicule(5, FlyleafConfig.ManiculeKills)).toBe(true)
	end)
end)

----------------------------------------------------------------
-- The real FlyleafService
----------------------------------------------------------------

type Fixture = {
	world: Server.World,
	service: any,
	claim: any,
	killed: any,
	snapshots: { [any]: any },
	notices: { { Player: any, Key: string, Params: any } },
	xp: { [any]: number },
	folios: { [any]: number },
	profiles: { [any]: any },
	inMatch: { [any]: boolean },
	engaged: { [any]: boolean },
	join: (userId: number) -> any,
	advance: (seconds: number) -> (),
	die: (player: any) -> (),
	said: (player: any, key: string) -> number,
}

local function fixture(): Fixture
	local world = Server.world()
	local service = world.require("src/server/Services/FlyleafService")
	local killed = require("./engine").signal()
	local snapshots: { [any]: any } = {}
	local notices: { { Player: any, Key: string, Params: any } } = {}
	local xp: { [any]: number } = {}
	local folios: { [any]: number } = {}
	local profiles: { [any]: any } = {}
	local inMatch: { [any]: boolean } = {}
	local engaged: { [any]: boolean } = {}
	local fx: any = {}
	service.Init({
		Registry = {
			fire = function(name: string, player: any, payload: any)
				if name == "FlyleafChanged" then
					snapshots[player] = payload
				end
			end,
		},
		DataService = {
			get = function(player: any): any
				local data = profiles[player]
				if data == nil then
					data = { Daily = { FlyleafDay = 0, FlyleafFolios = 0 } }
					profiles[player] = data
				end
				return data
			end,
			push = function(_player: any, _section: string) end,
		},
		Notify = {
			send = function(player: any, key: string, params: any, _kind: any, _sfx: any)
				table.insert(notices, { Player = player, Key = key, Params = params })
			end,
		},
		Combat = {
			claimZone = function(_zone: string, claim: any)
				fx.claim = claim
			end,
			resyncPosition = function(_player: any, _position: any) end,
			trustedPosition = function(player: any): any
				if fx.broken == player then
					error("no trusted position for " .. player.Name)
				end
				local body = player.Character
				local root = if body ~= nil then body:FindFirstChild("HumanoidRootPart") else nil
				return if root ~= nil then root.Position else nil
			end,
			Killed = killed,
		},
		Progression = {
			addXp = function(player: any, amount: number, _reason: string): number
				xp[player] = (xp[player] or 0) + amount
				return amount
			end,
		},
		Currency = {
			add = function(player: any, amount: number, _reason: string): number
				folios[player] = (folios[player] or 0) + amount
				return amount
			end,
		},
		Match = {
			isInMatch = function(player: any): boolean
				return inMatch[player] == true
			end,
		},
		WorldBoss = {
			isEngaged = function(player: any): boolean
				return engaged[player] == true
			end,
		},
	})
	service.Start()
	fx.world = world
	fx.service = service
	fx.killed = killed
	fx.snapshots = snapshots
	fx.notices = notices
	fx.xp = xp
	fx.folios = folios
	fx.profiles = profiles
	fx.inMatch = inMatch
	fx.engaged = engaged
	function fx.join(userId: number): any
		local player = world:join(userId, "P" .. userId)
		player:LoadCharacterAsync()
		return player
	end
	function fx.advance(seconds: number)
		world:advance(seconds)
	end
	-- A member's body dies: CombatService says who killed it first, then the engine fires Died.
	function fx.die(player: any)
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		humanoid.Health = 0
		humanoid.Died:Fire()
	end
	function fx.said(player: any, key: string): number
		local count = 0
		for _, notice in ipairs(notices) do
			if notice.Player == player and notice.Key == key then
				count += 1
			end
		end
		return count
	end
	return fx :: Fixture
end

local function sealOf(player: any): number?
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	local seals = FlyleafLayout.seals(MAP)
	for index, seal in ipairs(seals) do
		local x = MAP.Origin[1] + seal.X
		local z = MAP.Origin[3] + seal.Z
		if math.abs(root.Position.X - x) < 1e-6 and math.abs(root.Position.Z - z) < 1e-6 then
			return index
		end
	end
	return nil
end

-- `killer` takes `victim` down: CombatService's Killed, then the body's death.
local function takeDown(fx: Fixture, killer: any, victim: any)
	fx.killed:Fire(killer.UserId, victim.Character)
	fx.die(victim)
end

describe("FlyleafService", function()
	it("lands two members on opposite seals, protected for four seconds, then lets them fight", function()
		local fx = fixture()
		local a, b = fx.join(1), fx.join(2)
		expect(fx.service.enter(a)).toBe(true)
		fx.advance(0.5)
		expect(fx.service.enter(b)).toBe(true)
		local first, second = sealOf(a), sealOf(b)
		expect(first ~= nil and second ~= nil).toBe(true)
		expect(math.abs((first :: number) - (second :: number))).toBe(3)
		expect(fx.said(a, "flyleaf.entered")).toBe(1)
		expect(fx.snapshots[b]).toEqual({ Members = 2, Kills = 0, Streak = 0 })
		-- The zone holds its members only, and the pair waits for both protections.
		expect(fx.claim.Holds(a)).toBe(true)
		expect(fx.claim.Pair(a, b)).toBe(false)
		expect(a.Character:FindFirstChildOfClass("ForceField") ~= nil).toBe(true)
		fx.advance(FlyleafConfig.ProtectionSeconds - 0.6)
		expect(fx.claim.Pair(a, b)).toBe(false)
		expect(a.Character:FindFirstChildOfClass("ForceField") ~= nil).toBe(true)
		-- Past a's protection, not yet b's: still neither may hurt the other.
		fx.advance(0.3)
		expect(a.Character:FindFirstChildOfClass("ForceField")).toBeNil()
		expect(b.Character:FindFirstChildOfClass("ForceField") ~= nil).toBe(true)
		expect(fx.claim.Pair(a, b)).toBe(false)
		fx.advance(0.5)
		expect(fx.claim.Pair(a, b)).toBe(true)
		expect(fx.claim.Pair(b, a)).toBe(true)
		expect(a.Character:GetAttribute(FlyleafConfig.MemberAttribute)).toBe(true)
	end)

	it("pays a kill 60 XP and 5 Folios, and brings the fallen back on the furthest seal three seconds later", function()
		local fx = fixture()
		local a, b = fx.join(1), fx.join(2)
		fx.service.enter(a)
		fx.service.enter(b)
		fx.advance(5)
		takeDown(fx, a, b)
		expect(fx.xp[a]).toBe(60)
		expect(fx.folios[a]).toBe(5)
		expect(fx.said(a, "hud.playerKill")).toBe(1)
		-- The fallen rival still counts: they are back in three seconds.
		expect(fx.snapshots[a]).toEqual({ Members = 2, Kills = 1, Streak = 1 })
		local dead = b.Character
		fx.advance(FlyleafConfig.RespawnSeconds - 0.3)
		expect(b.Character).toBe(dead)
		fx.advance(0.6)
		expect(b.Character ~= dead).toBe(true)
		-- Back on the page, on the seal opposite the killer, protected again, the band never cleared.
		expect(sealOf(b)).toBe(((sealOf(a) :: number) + 2) % 6 + 1)
		expect(fx.claim.Holds(b)).toBe(true)
		expect(fx.claim.Pair(a, b)).toBe(false)
		expect(b.Character:FindFirstChildOfClass("ForceField") ~= nil).toBe(true)
		expect(fx.snapshots[b] ~= nil).toBe(true)
	end)

	it("stops paying for the same rival after three deaths in ten minutes", function()
		local fx = fixture()
		local a, b = fx.join(1), fx.join(2)
		fx.service.enter(a)
		fx.service.enter(b)
		for _ = 1, 4 do
			fx.advance(5)
			takeDown(fx, a, b)
		end
		expect(fx.xp[a]).toBe(3 * 60)
		expect(fx.folios[a]).toBe(3 * 5)
		expect(fx.said(a, "flyleaf.noPay")).toBe(1)
		-- The fourth still counts on the band: it was taken, it was not paid.
		expect(fx.snapshots[a].Kills).toBe(4)
	end)

	it("pays Folios out of the day's 100 kept in the profile, and says so once when they run out", function()
		local fx = fixture()
		local a, b = fx.join(1), fx.join(2)
		fx.service.enter(a)
		fx.service.enter(b)
		local today = math.floor(os.time() / 86400)
		fx.profiles[a] = { Daily = { FlyleafDay = today, FlyleafFolios = 95 } }
		fx.advance(5)
		takeDown(fx, a, b)
		expect(fx.folios[a]).toBe(5)
		expect(fx.profiles[a].Daily.FlyleafFolios).toBe(100)
		fx.advance(5)
		takeDown(fx, a, b)
		fx.advance(5)
		takeDown(fx, a, b)
		expect(fx.folios[a]).toBe(5)
		expect(fx.xp[a]).toBe(3 * 60)
		expect(fx.said(a, "flyleaf.folioCap")).toBe(1)
	end)

	it("puts the Manicule on a run of three, tells every member, and takes it off with the body", function()
		local fx = fixture()
		local a, b, c = fx.join(1), fx.join(2), fx.join(3)
		for _, player in ipairs({ a, b, c }) do
			fx.service.enter(player)
		end
		fx.advance(5)
		takeDown(fx, a, b)
		fx.advance(4)
		takeDown(fx, a, c)
		expect(a.Character:GetAttribute(FlyleafConfig.ManiculeAttribute)).toBeNil()
		fx.advance(4)
		takeDown(fx, a, b)
		expect(a.Character:GetAttribute(FlyleafConfig.ManiculeAttribute)).toBe(true)
		expect(fx.said(c, "flyleaf.manicule")).toBe(1)
		expect(fx.snapshots[a].Streak).toBe(3)
		fx.advance(5)
		local worn = a.Character
		takeDown(fx, c, a)
		expect(fx.said(b, "flyleaf.maniculeTaken")).toBe(1)
		-- Off at the death, not three seconds later with the body: no hand hangs over a fallen rival (found by review).
		expect(worn:GetAttribute(FlyleafConfig.ManiculeAttribute)).toBeNil()
		fx.advance(4)
		expect(a.Character:GetAttribute(FlyleafConfig.ManiculeAttribute)).toBeNil()
		expect(fx.snapshots[a].Streak).toBe(0)
		expect(fx.snapshots[a].Kills).toBe(3)
	end)

	it("lets a member go when a match or the Erasure takes them, or when they stand anywhere else", function()
		local fx = fixture()
		local a, b, c = fx.join(1), fx.join(2), fx.join(3)
		for _, player in ipairs({ a, b, c }) do
			fx.service.enter(player)
		end
		fx.advance(1)
		fx.inMatch[a] = true
		fx.engaged[b] = true
		c.Character:PivotTo(roblox.CFrame.new(0, 3, 0))
		fx.advance(0.5)
		for _, player in ipairs({ a, b, c }) do
			expect(fx.claim.Holds(player)).toBe(false)
			expect(fx.snapshots[player]).toBeNil()
			expect(player.Character:GetAttribute(FlyleafConfig.MemberAttribute)).toBeNil()
		end
	end)

	it("kills a body that falls under the page, by where the server sees it, not by the client's word", function()
		local fx = fixture()
		local a = fx.join(1)
		fx.service.enter(a)
		fx.advance(1)
		a.Character:PivotTo(roblox.CFrame.new(MAP.Origin[1] + 10, MAP.KillZoneDepth - 5, 0))
		fx.advance(0.2)
		expect(a.Character:FindFirstChildOfClass("Humanoid").Health).toBe(0)
	end)

	it("keeps stepping every other member when one member's step throws", function()
		local fx: any = fixture()
		local a, b = fx.join(1), fx.join(2)
		fx.service.enter(a)
		fx.service.enter(b)
		fx.advance(1)
		fx.broken = a
		b.Character:PivotTo(roblox.CFrame.new(0, 3, 0))
		fx.advance(0.5)
		expect(fx.claim.Holds(b)).toBe(false)
		expect(fx.snapshots[b]).toBeNil()
		expect(fx.world:said("step of")).toBe(true)
	end)

	it("refuses a player in a match, and past its members, and a gate lets a member go", function()
		local fx = fixture()
		local players = {}
		for index = 1, FlyleafConfig.MaxMembers + 1 do
			players[index] = fx.join(index)
		end
		fx.inMatch[players[1]] = true
		expect(select(2, fx.service.admits(players[1]))).toBe("queue.inMatch")
		for index = 2, FlyleafConfig.MaxMembers + 1 do
			expect(fx.service.enter(players[index])).toBe(true)
		end
		fx.inMatch[players[1]] = nil
		expect(select(2, fx.service.enter(players[1]))).toBe("flyleaf.full")
		fx.service.leave(players[2])
		expect(fx.snapshots[players[2]]).toBeNil()
		expect(fx.service.enter(players[1])).toBe(true)
	end)

	it("does not bring back a fallen member a match took while they were down", function()
		local fx = fixture()
		local a, b = fx.join(1), fx.join(2)
		fx.service.enter(a)
		fx.service.enter(b)
		fx.advance(5)
		takeDown(fx, a, b)
		local dead = b.Character
		fx.inMatch[b] = true
		fx.advance(FlyleafConfig.RespawnSeconds + 0.5)
		expect(b.Character).toBe(dead)
		expect(fx.claim.Holds(b)).toBe(false)
		expect(fx.snapshots[b]).toBeNil()
	end)

	it("asks again once the new body has loaded: a match that took them meanwhile keeps them", function()
		local fx = fixture()
		local a, b = fx.join(1), fx.join(2)
		fx.service.enter(a)
		fx.service.enter(b)
		fx.advance(5)
		takeDown(fx, a, b)
		-- MatchService.start marks its participants, then loads their bodies: the race the respawn must lose, and
		-- without waiting for the page to stream in around a seal they will never stand on.
		fx.world.engine.workspace.StreamingEnabled = true
		local streamed = 0
		b.RequestStreamAroundAsync = function(_self: any, _position: any, _timeout: number)
			streamed += 1
		end
		local load = b.LoadCharacterAsync
		b.LoadCharacterAsync = function(self: any)
			fx.inMatch[b] = true
			load(self)
		end
		fx.advance(FlyleafConfig.RespawnSeconds + 0.5)
		expect(fx.claim.Holds(b)).toBe(false)
		expect(fx.snapshots[b]).toBeNil()
		expect(sealOf(b)).toBeNil()
		expect(streamed).toBe(0)
	end)
end)

----------------------------------------------------------------
-- What the rest of the game does for the Flyleaf, read from its sources
----------------------------------------------------------------

local function folded(path: string, header: string): string
	local source = fs.readFile(path):gsub("%-%-[^\n]*", "")
	local start = source:find(header, 1, true)
	if start == nil then
		error(("%s has no %s: this gate would check nothing"):format(path, header))
	end
	local finish = source:find("\nend\n", start, true)
	return (source:sub(start, finish or #source):gsub("%s+", " "):gsub("%( ", "("):gsub(" %)", ")"))
end

describe("around the Flyleaf", function()
	it("keeps a developer's perks off the page: they reach the hub's zone only", function()
		local perks = folded("src/server/Services/GlyphService.luau", "local function developerPerks(")
		expect(perks:find('and combat.zoneOf(player) == "Hub"', 1, true) ~= nil).toBe(true)
	end)

	it("lets the lock take another member only from a member's body, by the server's mark", function()
		local opponents = folded("src/client/Controllers/LockOnController.luau", "local function opponents(")
		for _, line in ipairs({
			"if own ~= nil and own:GetAttribute(FlyleafConfig.MemberAttribute) == true then",
			"if other ~= player and body ~= nil and body:GetAttribute(FlyleafConfig.MemberAttribute) == true then",
			'local lock = lockOf(body, "Player")',
		}) do
			if opponents:find(line, 1, true) == nil then
				error("opponents no longer does: " .. line)
			end
		end
	end)

	it("draws the Manicule from the server's mark alone, in sight only, growing into place", function()
		local path = "src/client/Controllers/ManiculeController.luau"
		local refresh = folded(path, "local function refresh(")
		expect(
			refresh:find(
				"if character:GetAttribute(ATTRIBUTE) == true and character.Parent ~= nil then draw(character)",
				1,
				true
			) ~= nil
		).toBe(true)
		local draw = folded(path, "local function draw(")
		for _, line in ipairs({
			"mark.AlwaysOnTop = false",
			"mark.MaxDistance = MAX_DISTANCE_STUDS",
			'local ink = Palette.world("Ink")',
			'local chalk = Palette.world("Chalk")',
			'Motion.to(scale, { Scale = 1 }, "UiPop")',
		}) do
			if draw:find(line, 1, true) == nil then
				error("draw no longer does: " .. line)
			end
		end
		expect(fs.readFile(path):find("Color3.fromRGB", 1, true)).toBeNil()
		local order = fs.readFile("src/client/Bootstrap.client.luau")
		expect(order:find('"ManiculeController",', 1, true) ~= nil).toBe(true)
	end)
end)
