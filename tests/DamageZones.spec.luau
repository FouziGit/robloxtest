--!strict
-- Who may hurt whom, place by place (E16-S1, D-XXX). The rule is ZoneConfig's, judged by the pure DamageZones,
-- and CombatService applies it to every hit through the claims of the zones' owners. The rule is run first; then
-- the real CombatService, in a pretend server, judges the hits QA plays by hand: no PvP in the hub while the
-- proofs take damage (docs/QA.md §5.10), none between the Erasure's players while the boss takes it (§6.5), the
-- opponents of one match and nobody else, even while the event runs, and a kill paid as it always was.
local DamageZones = require("../src/server/Pure/DamageZones")
local Harness = require("./harness")
local Server = require("./server")
local ZoneConfig = require("../src/shared/Config/ZoneConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local RULES = (ZoneConfig.Rules :: any) :: { [string]: DamageZones.Rule }

describe("the zones' rule", function()
	it("places a player in the first zone that holds them, the hub when none does", function()
		local held: { [string]: boolean } = {}
		local function holds(zone: string, _who: string): boolean
			return held[zone] == true
		end
		expect(DamageZones.zoneOf(ZoneConfig.Order, ZoneConfig.Fallback, holds, "a")).toBe("Hub")
		-- Nobody claims the hub: a claim that said so is never asked.
		held.Hub = false
		expect(DamageZones.zoneOf(ZoneConfig.Order, ZoneConfig.Fallback, holds, "a")).toBe("Hub")
		held.Boss = true
		expect(DamageZones.zoneOf(ZoneConfig.Order, ZoneConfig.Fallback, holds, "a")).toBe("Boss")
		-- A ranked match takes a participant of the event: the duel's rule, and the event lets them go.
		held.Match = true
		expect(DamageZones.zoneOf(ZoneConfig.Order, ZoneConfig.Fallback, holds, "a")).toBe("Match")
		expect(ZoneConfig.Order[#ZoneConfig.Order]).toBe(ZoneConfig.Fallback)
	end)

	it("is the story's: the hub none, a match its participants, the Erasure never", function()
		expect(RULES.Hub.BetweenPlayers).toBe("Never")
		expect(RULES.Match.BetweenPlayers).toBe("Owner")
		expect(RULES.Boss.BetweenPlayers).toBe("Never")
		-- The proofs and the Erasure take hits; nothing that is not a player stands in a duel.
		expect(RULES.Hub.OnBodies).toBe(true)
		expect(RULES.Boss.OnBodies).toBe(true)
		expect(RULES.Match.OnBodies).toBe(false)
		expect(DamageZones.combatPays(RULES, "Match")).toBe(true)
		for _, zone in ipairs(ZoneConfig.Order) do
			expect(RULES[zone] ~= nil).toBe(true)
		end
	end)

	it("never lets two zones hurt each other, and hands a pair to the owner only where it may", function()
		for _, source in ipairs(ZoneConfig.Order) do
			for _, target in ipairs(ZoneConfig.Order) do
				local verdict = DamageZones.judge(RULES, source, target)
				if source ~= target or RULES[source].BetweenPlayers == "Never" then
					expect(verdict).toBe("Refuse")
				else
					expect(verdict).toBe("Owner")
				end
			end
			expect(DamageZones.judge(RULES, source, nil)).toBe(if RULES[source].OnBodies then "Allow" else "Refuse")
		end
		-- A zone nobody wrote a rule for allows nothing.
		expect(DamageZones.judge(RULES, "Nowhere", nil)).toBe("Refuse")
		expect(DamageZones.combatPays(RULES, "Nowhere")).toBe(false)
	end)
end)

----------------------------------------------------------------
-- The real CombatService
----------------------------------------------------------------

type Fixture = {
	world: Server.World,
	combat: any,
	xp: { { Player: any, Reason: string } },
	killed: { { Source: number, Victim: any } },
	join: (userId: number, x: number) -> any,
	proof: (x: number) -> any,
	-- Past every spawn protection, without running a tick.
	settle: () -> (),
}

local function fixture(): Fixture
	-- The movement audit needs the engine's physics; nothing here moves, so every call to it is a no-op.
	local audit = setmetatable({}, {
		__index = function(): any
			return function() end
		end,
	})
	local world = Server.world({ Stubs = { ["src/server/Security/MovementAudit"] = audit } })
	local combat = world.require("src/server/Services/CombatService")
	local xp: { { Player: any, Reason: string } } = {}
	local profiles: { [any]: any } = {}
	combat.Init({
		Registry = {
			on = function(_name: string, _handler: any) end,
			fire = function(_name: string, _player: any, _payload: any) end,
			lastInbound = function(_player: any): number
				return 0
			end,
		},
		DataService = {
			get = function(player: any): any
				local data = profiles[player]
				if data == nil then
					data = { Stats = { Kills = 0, Deaths = 0 } }
					profiles[player] = data
				end
				return data
			end,
			push = function(_player: any, _section: string) end,
		},
		Notify = { send = function(_player: any, _key: string, _params: any, _kind: any, _sfx: any) end },
		Movement = {
			applySlow = function() end,
			clearSlow = function() end,
			applyStun = function() end,
			ragdoll = function() end,
			isStunned = function(): boolean
				return false
			end,
			isDown = function(): boolean
				return false
			end,
			command = function() end,
		},
		AntiCheat = { strike = function() end },
		Vfx = { emit = function(_packet: any, _reliable: boolean?) end },
		Progression = {
			addXp = function(player: any, _amount: number, reason: string)
				table.insert(xp, { Player = player, Reason = reason })
			end,
		},
		Currency = { add = function(_player: any, _amount: number, _reason: string) end },
		Cosmetic = {
			skinShade = function(_player: any, _glyphId: string): number
				return 0
			end,
		},
	})
	combat.Start()
	local killed: { { Source: number, Victim: any } } = {}
	combat.Killed:Connect(function(source: number, victim: any)
		table.insert(killed, { Source = source, Victim = victim })
	end)

	local function body(model: any, x: number)
		local root = model:FindFirstChild("HumanoidRootPart")
		root.Position = roblox.Vector3.new(x, 0, 0)
		model.GetPivot = function(_self: any): any
			return roblox.CFrame.new(root.Position)
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		humanoid.TakeDamage = function(self: any, amount: number)
			self.Health = math.max(0, self.Health - amount)
		end
	end

	local function join(userId: number, x: number): any
		local player = world:join(userId, "P" .. userId)
		player:LoadCharacterAsync()
		body(player.Character, x)
		player.CharacterAdded:Fire(player.Character)
		return player
	end

	-- A training proof, or the Erasure: a body with a Humanoid that no player owns.
	local function proof(x: number): any
		local Engine = require("./engine")
		local model = Engine.instance("Model")
		local humanoid = Engine.instance("Humanoid", model)
		humanoid.MaxHealth = 150
		humanoid.Health = 150
		local root = Engine.instance("BasePart", model)
		root.Name = "HumanoidRootPart"
		body(model, x)
		return model
	end

	return {
		world = world,
		combat = combat,
		xp = xp,
		killed = killed,
		join = join,
		proof = proof,
		settle = function()
			world.engine.now += 10
		end,
	}
end

-- A zone owner as a set of players, and the pairs it lets through (every pair, unless told otherwise).
local function owner(fx: Fixture, zone: string, members: { any }, pair: ((any, any) -> boolean)?)
	local held: { [any]: boolean } = {}
	for _, player in ipairs(members) do
		held[player] = true
	end
	fx.combat.claimZone(zone, {
		Holds = function(player: any): boolean
			return held[player] == true
		end,
		Pair = if zone == "Boss"
			then nil
			else pair or function(_source: any, _target: any): boolean
				return true
			end,
	})
	return held
end

describe("CombatService's zones", function()
	it("keep every player of the hub from every other, and the proofs open to them (QA §5.10)", function()
		local fx = fixture()
		local a, b = fx.join(1, 0), fx.join(2, 4)
		local dummy = fx.proof(8)
		fx.settle()
		expect(fx.combat.zoneOf(a)).toBe("Hub")
		expect(fx.combat.canDamage(a, b.Character)).toBe(false)
		expect(fx.combat.ApplyDamage(a, b.Character, 20, "Melee", {}).Applied).toBe(0)
		expect(fx.combat.canDamage(a, dummy)).toBe(true)
		expect(fx.combat.ApplyDamage(a, dummy, 20, "Melee", {}).Applied).toBe(20)
		-- Damage the server authors is no zone's business.
		expect(fx.combat.ApplyDamage(nil, b.Character, 20, "Environment", {}).Applied).toBe(20)
	end)

	it("keep the Erasure's players off each other while the boss takes their hits (QA §6.5)", function()
		local fx = fixture()
		local a, b, c = fx.join(1, 0), fx.join(2, 4), fx.join(3, 8)
		local boss = fx.proof(12)
		owner(fx, "Boss", { a, b })
		fx.settle()
		expect(fx.combat.zoneOf(a)).toBe("Boss")
		expect(fx.combat.canDamage(a, b.Character)).toBe(false)
		expect(fx.combat.canDamage(b, a.Character)).toBe(false)
		expect(fx.combat.canDamage(a, c.Character)).toBe(false)
		expect(fx.combat.canDamage(c, a.Character)).toBe(false)
		expect(fx.combat.ApplyDamage(a, boss, 30, "Glyph", { "Brand" }).Applied).toBe(30)
	end)

	it("let a match's opponents fight while the event runs, and nobody else, nor anything else", function()
		local fx = fixture()
		local red, blue, mate, watcher = fx.join(1, 0), fx.join(2, 4), fx.join(3, 8), fx.join(4, 12)
		local teams = { [red] = 1, [mate] = 1, [blue] = 2 }
		owner(fx, "Match", { red, blue, mate }, function(source: any, target: any): boolean
			return teams[source] ~= teams[target]
		end)
		-- Every one of them was engaged by the Erasure's event before the match took them.
		owner(fx, "Boss", { red, blue, mate, watcher })
		local dummy = fx.proof(16)
		fx.settle()
		expect(fx.combat.zoneOf(red)).toBe("Match")
		expect(fx.combat.canDamage(red, blue.Character)).toBe(true)
		expect(fx.combat.canDamage(blue, red.Character)).toBe(true)
		expect(fx.combat.canDamage(red, mate.Character)).toBe(false)
		expect(fx.combat.canDamage(red, watcher.Character)).toBe(false)
		expect(fx.combat.canDamage(watcher, red.Character)).toBe(false)
		expect(fx.combat.canDamage(red, dummy)).toBe(false)
		expect(fx.combat.canDamage(watcher, dummy)).toBe(true)
	end)

	it("pay a match's kill as they always did, and tell whoever listens", function()
		local fx = fixture()
		local red, blue = fx.join(1, 0), fx.join(2, 4)
		owner(fx, "Match", { red, blue })
		fx.settle()
		expect(fx.combat.ApplyDamage(red, blue.Character, 1000, "Melee", {}).Killed).toBe(true)
		expect(#fx.xp).toBe(1)
		expect(fx.xp[1].Reason).toBe("PlayerKill")
		expect(#fx.killed).toBe(1)
		expect(fx.killed[1].Source).toBe(red.UserId)
	end)

	it("take one claim per zone, never the hub's, and say so", function()
		local fx = fixture()
		fx.combat.claimZone("Hub", {
			Holds = function(): boolean
				return true
			end,
		})
		expect(fx.world:said("claimZone rejected: Hub")).toBe(true)
		local a = fx.join(1, 0)
		expect(fx.combat.zoneOf(a)).toBe("Hub")
		fx.combat.claimZone("Match", {
			Holds = function(): boolean
				return true
			end,
		})
		expect(fx.world:said("claimZone for Match has no Pair")).toBe(true)
		local b = fx.join(2, 4)
		fx.settle()
		-- Without its Pair, a match lets no participant hurt another.
		expect(fx.combat.canDamage(a, b.Character)).toBe(false)
		owner(fx, "Match", { a, b })
		expect(fx.world:said("zone Match claimed twice")).toBe(true)
		expect(fx.combat.canDamage(a, b.Character)).toBe(true)
	end)
end)

describe("the single PvP slot is gone", function()
	it("leaves no policy to borrow anywhere on the server", function()
		local function collect(directory: string, out: { string })
			for _, entry in ipairs(fs.readDir(directory)) do
				local path = directory .. "/" .. entry
				if fs.isDir(path) then
					collect(path, out)
				elseif entry:match("%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files: { string } = {}
		collect("src/server", files)
		local claimed: { [string]: number } = {}
		for _, path in ipairs(files) do
			local source = fs.readFile(path):gsub("%-%-[^\n]*", "")
			expect(source:find("setPolicy", 1, true)).toBeNil()
			for zone in source:gmatch('claimZone%("(%a+)"') do
				claimed[zone] = (claimed[zone] or 0) + 1
			end
		end
		-- Every zone but the hub has exactly one owner on the server.
		for _, zone in ipairs(ZoneConfig.Order) do
			expect(claimed[zone]).toBe(if zone == ZoneConfig.Fallback then nil else 1)
		end
	end)
end)
