--!strict
-- A player's body as MovementService keeps it: every part in the players' collision group, which does not collide
-- with itself (D-215), and replaced when its client takes its Humanoid away (D-216), whose holds it keeps (D-XXX).
-- MovementService runs in the pretend engine (tests/serverworld.luau), CombatService and GlyphService in the pretend
-- server (tests/server.luau); what only a live server can show -- two clients passing through each other, a finisher
-- still throwing -- is QA §7.
local CombatConfig = require("../src/shared/Config/CombatConfig")
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local Server = require("./server")
local ServerWorld = require("./serverworld")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local GROUP = GameConfig.Movement.CharacterCollisionGroup
local STUN = CombatConfig.Status.StunAttribute
local SLOW = CombatConfig.Status.SlowAttribute
local RAGDOLL = CombatConfig.Status.RagdollAttribute

local function code(path: string): string
	return ((fs.readFile(path):gsub("%-%-[^\n]*", "")):gsub("%s+", " "))
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

describe("the players' collision group", function()
	it("is registered before any body joins it, and does not collide with itself", function()
		local s = ServerWorld.start()
		expect(s.groups).toEqual({ GROUP })
		expect(s.pairs).toEqual({ { GROUP, GROUP, false } })
		expect(GROUP).never.toBe("Default")
	end)

	it("holds every part of a player's body from the start, and whatever it is given later", function()
		local s = ServerWorld.start()
		for _, part in ipairs(s.character:GetDescendants()) do
			if part:IsA("Part") or part:IsA("MeshPart") then
				expect(part.CollisionGroup).toBe(GROUP)
			end
		end
		-- An accessory that loads late, with its handle already inside it, and a part added on its own.
		local hat = Engine.instance("Accessory")
		local handle = Engine.instance("Part", hat)
		hat.Parent = s.character
		expect(handle.CollisionGroup).toBe(GROUP)
		local tool = Engine.instance("Part", s.character)
		expect(tool.CollisionGroup).toBe(GROUP)
		-- Only parts: the Humanoid and the accessory are not given a group.
		expect(s.humanoid.CollisionGroup).toBe(nil)
		expect(hat.CollisionGroup).toBe(nil)
	end)

	it("holds a respawned body too, and lets the old one go", function()
		local s = ServerWorld.start()
		local old = s.character
		local listening = old.DescendantAdded:count()
		expect(listening).toBe(1)
		s:spawn()
		expect(s.character).never.toBe(old)
		expect(s.root.CollisionGroup).toBe(GROUP)
		expect(s.character.DescendantAdded:count()).toBe(1)
	end)

	it("never takes a body that is not a player's: the Forgers and the Erasure stay Default", function()
		local s = ServerWorld.start()
		local forger = Engine.instance("Model", s.world.workspace)
		local part = Engine.instance("Part", forger)
		Engine.instance("Humanoid", forger)
		s.world:advance(1)
		expect(part.CollisionGroup).toBe(nil)
		-- Nothing else in the game writes a collision group: the Forgers' rigs, the Erasure's hull and every arena
		-- are Default, and collide with players as before.
		local files: { string } = {}
		collect("src", files)
		local writers: { string } = {}
		for _, path in ipairs(files) do
			local source = code(path)
			if source:find(".CollisionGroup =", 1, true) ~= nil or source:find("PhysicsService", 1, true) ~= nil then
				table.insert(writers, path)
			end
		end
		expect(writers).toEqual({ "src/server/Services/MovementService.luau" })
		local movement = code("src/server/Services/MovementService.luau")
		expect(movement).toContain(
			"state.CharacterTrove = characterTrove groupCharacter(character, characterTrove) local humanoid = findHumanoid(character)"
		)
		expect(movement).toContain(
			'log.try("register the " .. CHARACTER_GROUP .. " collision group", registerGroup) Players.PlayerAdded:Connect(onPlayerAdded)'
		)
	end)
end)

-- A client can take the Humanoid out of its own body, and the deletion replicates: with no Humanoid nothing can hurt
-- the body. MovementService replaces it once GameConfig.Spawn.HumanoidReturnSeconds pass without it (D-216).
describe("a body whose Humanoid was taken away", function()
	local RETURN = GameConfig.Spawn.HumanoidReturnSeconds
	local TICK = 1 / GameConfig.Server.TickRate

	it("is replaced once, with one Schema strike, when its Humanoid does not come back", function()
		-- The half second decided with the respawn (D-216).
		expect(RETURN).toBe(0.5)
		for _, how in ipairs({ "unparented", "destroyed" }) do
			local s = ServerWorld.start()
			local old = s.character
			s.world:advance(1)
			if how == "destroyed" then
				s.humanoid:Destroy()
			else
				s.humanoid.Parent = nil
			end
			local at = s.world.now
			s.world:advance(RETURN - 2 * TICK)
			expect(#s.loads).toBe(0)
			expect(#s.strikes).toBe(0)
			s.world:advance(3 * TICK)
			expect(#s.loads).toBe(1)
			expect(s.loads[1] - at).toBeLessThanOrEqual(RETURN + TICK + 1e-9)
			expect(#s.strikes).toBe(1)
			expect(s.strikes[1][1]).toBe("Humanoid")
			expect(s.strikes[1][3]).toBe("Schema")
			-- The places that keep a player heard of it first, once.
			expect(s.lost).toEqual({ s.loads[1] })
			-- Asked for once, however long the engine takes to bring the new body.
			s.world:advance(2)
			expect(#s.loads).toBe(1)
			s:spawn()
			expect(s.character).never.toBe(old)
			s.world:advance(5)
			expect(#s.loads).toBe(1)
			expect(#s.strikes).toBe(1)
			expect(#s.lost).toBe(1)
			-- And the new body is held as any other.
			s.service.applyStun(s.player, 0.5)
			expect(s.humanoid.WalkSpeed).toBe(0)
		end
	end)

	it("is left alone, and held again, when its Humanoid comes back in time", function()
		local s = ServerWorld.start()
		local humanoid = s.humanoid
		humanoid.Parent = nil
		s.world:advance(RETURN / 2)
		humanoid.Parent = s.character
		s.world:advance(2)
		expect(#s.loads).toBe(0)
		expect(#s.strikes).toBe(0)
		s.service.applyStun(s.player, 0.5)
		expect(humanoid.WalkSpeed).toBe(0)
	end)

	it("keeps its stun, slow and fall while its Humanoid is away, and is held by them again", function()
		-- Cleared on the way out, a client that took its Humanoid out and put it back within a frame walked, and cast,
		-- out of any stun the server had put on it (E2-S1, D-XXX). Moved out of the body or into one of its parts.
		local WALK = GameConfig.Movement.WalkSpeed
		for _, into in ipairs({ "nowhere", "Head" }) do
			local s = ServerWorld.start()
			local humanoid = s.humanoid
			local joint = Engine.instance("AnimationConstraint", s.character)
			joint.Name = "LeftShoulder"
			joint.IsKinematic = true
			joint.MaxTorque = 1000
			s.world:advance(1)
			s.service.applySlow(s.player, "Glyph", 0.5, 2.5)
			s.service.ragdoll(s.player, CombatConfig.Hit.RagdollSeconds)
			local stunUntil = humanoid:GetAttribute(STUN)
			local slowUntil = humanoid:GetAttribute(SLOW)
			humanoid.Parent = if into == "Head" then s.character:FindFirstChild("Head") else nil
			s.world:advance(1 / 60)
			expect(s.service.isStunned(s.player)).toBe(true)
			humanoid.Parent = s.character
			expect(s.service.isStunned(s.player)).toBe(true)
			expect(s.service.isDown(s.player)).toBe(true)
			expect(humanoid.WalkSpeed).toBe(0)
			expect(humanoid.JumpPower).toBe(0)
			expect(humanoid:GetAttribute(STUN)).toBe(stunUntil)
			expect(humanoid:GetAttribute(SLOW)).toBe(slowUntil)
			expect(joint.MaxTorque).toBe(0)
			expect(s.character:GetAttribute(RAGDOLL)).toBe(CombatConfig.Status.RagdollLimp)
			-- Each runs out on its own date: the body gets up, the stun ends and the slow takes over, then nothing.
			s.world:advance(stunUntil - s.world.now + 2 * TICK)
			expect(s.service.isStunned(s.player)).toBe(false)
			expect(s.service.isDown(s.player)).toBe(false)
			expect(joint.MaxTorque).toBe(1000)
			expect(joint.IsKinematic).toBe(true)
			expect(humanoid:GetAttribute(STUN)).toBe(nil)
			expect(humanoid.WalkSpeed).toBe(WALK * 0.5)
			s.world:advance(slowUntil - s.world.now + 2 * TICK)
			expect(humanoid:GetAttribute(SLOW)).toBe(nil)
			expect(humanoid.WalkSpeed).toBe(WALK)
			expect(#s.loads).toBe(0)
			expect(#s.strikes).toBe(0)
		end
	end)

	it("comes back without what the server let go of while its Humanoid was away", function()
		-- A stun the server ends early (the result screen's freeze) and a slow it lifts, while nothing can be written
		-- on the body: the Humanoid given back is not marked with them, as no tick would ever take the marks off.
		local s = ServerWorld.start()
		local humanoid = s.humanoid
		s.world:advance(1)
		s.service.applyFreeze(s.player, 5)
		s.service.applySlow(s.player, "Block", 0.5, 5)
		humanoid.Parent = nil
		s.world:advance(1 / 60)
		s.service.clearStun(s.player)
		s.service.clearSlow(s.player, "Block")
		humanoid.Parent = s.character
		expect(humanoid:GetAttribute(STUN)).toBe(nil)
		expect(humanoid:GetAttribute(SLOW)).toBe(nil)
		expect(humanoid.WalkSpeed).toBe(GameConfig.Movement.WalkSpeed)
		s.world:advance(1)
		expect(humanoid:GetAttribute(STUN)).toBe(nil)
		expect(humanoid:GetAttribute(SLOW)).toBe(nil)
	end)

	it("lets its holds go with the body when its Humanoid does not come back", function()
		local s = ServerWorld.start()
		s.world:advance(1)
		s.service.applyStun(s.player, 2)
		s.humanoid.Parent = nil
		s.world:advance(RETURN + 2 * TICK)
		expect(#s.loads).toBe(1)
		s:spawn()
		expect(s.service.isStunned(s.player)).toBe(false)
		expect(s.humanoid.WalkSpeed).toBe(GameConfig.Movement.WalkSpeed)
	end)

	it("is replaced once its time away adds up, however often its Humanoid comes back", function()
		-- A client that takes it out and puts it back a little before the half second, again and again, spends
		-- most of its time where nothing can hurt it.
		local s = ServerWorld.start()
		local humanoid = s.humanoid
		local away = RETURN * 0.6
		humanoid.Parent = nil
		s.world:advance(away)
		humanoid.Parent = s.character
		s.world:advance(1)
		expect(#s.loads).toBe(0)
		humanoid.Parent = nil
		s.world:advance(RETURN - away - 2 * TICK)
		expect(#s.loads).toBe(0)
		s.world:advance(3 * TICK)
		expect(#s.loads).toBe(1)
		expect(#s.strikes).toBe(1)
	end)

	it("is replaced when its Humanoid comes back between the half second and the next tick", function()
		-- The service looks once a tick: a Humanoid given back in the gap between the half second and that tick did
		-- not come back in time. Every phase of the detach against the tick, a 240th of a second apart.
		local FRAME = 1 / 240
		local late = 0
		for offset = 0, math.round(TICK / FRAME) - 1 do
			local s = ServerWorld.start()
			s.world:advance(offset * FRAME, FRAME)
			local humanoid = s.humanoid
			humanoid.Parent = nil
			local at = s.world.now
			while s.world.now - at <= RETURN + 1e-9 do
				s.world:advance(FRAME, FRAME)
			end
			if #s.loads == 0 then
				late += 1
				humanoid.Parent = s.character
			end
			s.world:advance(2)
			expect(#s.loads).toBe(1)
			expect(#s.strikes).toBe(1)
			expect(#s.lost).toBe(1)
		end
		-- A sweep that never fell in the gap would check nothing.
		expect(late).toBeGreaterThan(0)
	end)

	it("leaves a normal death, and a body the server replaces, to the engine", function()
		local s = ServerWorld.start()
		s.humanoid.Health = 0
		s.humanoid.Died:Fire()
		s.world:advance(2)
		-- A dead body's Humanoid taken away changes nothing: the engine brings the next body at its time.
		s.humanoid.Parent = nil
		s.world:advance(2)
		s:spawn()
		s.world:advance(2)
		expect(#s.loads).toBe(0)
		expect(#s.strikes).toBe(0)
		expect(#s.lost).toBe(0)
		s.service.applyStun(s.player, 0.5)
		expect(s.humanoid.WalkSpeed).toBe(0)
	end)

	it("comes back at the hub, or in the Battleground's camp for a member", function()
		-- A member's lost body is a death inside: the camp takes the new one back, as after any death there.
		local roster = code("src/server/Services/BattlegroundService/Roster.luau")
		expect(roster).toContain(
			"function Roster.lost(player: Player) local member = members[player] if member ~= nil then onDied(member) end end"
		)
		expect(code("src/server/Services/BattlegroundService/init.luau")).toContain(
			"trove:Add(deps.Movement.BodyLost:Connect(Roster.lost))"
		)
		-- Told before the new body is asked for, so the camp is waiting for it.
		local movement = code("src/server/Services/MovementService.luau")
		expect(movement).toContain(
			'antiCheat.strike(player, "Humanoid", "the Humanoid left the character and did not come back", "Schema") if player.Parent ~= Players then return end MovementService.BodyLost:Fire(player) task.spawn(function() log.try("LoadCharacterAsync " .. player.Name, function() player:LoadCharacterAsync() end) end)'
		)
		-- Nothing in the Erasure's fight places a new body: a participant's comes back at the hub's SpawnLocation.
		local files: { string } = {}
		collect("src/server/Services/WorldBossService", files)
		for _, path in ipairs(files) do
			expect(code(path)).never.toContain("CharacterAdded")
		end
	end)
end)

-- CombatService refuses the melee, the dash and the guard from the moment a client takes its Humanoid out until its
-- next body, even put back in time; a glyph is refused with them (D-XXX), so that no hold MovementService gives back
-- with the Humanoid is all that stands between that body and a cast.
describe("a glyph from a body whose Humanoid was taken out", function()
	-- The real CombatService in a pretend server, with one player standing in a body.
	local function combatWorld(): (any, any)
		-- The movement audit needs the engine's physics; nothing here moves.
		local audit = setmetatable({}, {
			__index = function(): any
				return function() end
			end,
		})
		local world = Server.world({ Stubs = { ["src/server/Security/MovementAudit"] = audit } })
		local combat = world.require("src/server/Services/CombatService")
		local function nothing() end
		combat.Init({
			Registry = {
				on = nothing,
				fire = nothing,
				lastInbound = function(): number
					return 0
				end,
			},
			DataService = {
				get = function(): any
					return { Stats = { Kills = 0, Deaths = 0 } }
				end,
				push = nothing,
			},
			Notify = { send = nothing },
			Movement = {
				applySlow = nothing,
				clearSlow = nothing,
				applyStun = nothing,
				ragdoll = nothing,
				isStunned = function(): boolean
					return false
				end,
				isDown = function(): boolean
					return false
				end,
				command = nothing,
			},
			AntiCheat = { strike = nothing },
			Vfx = { emit = nothing },
			Progression = { addXp = nothing },
			Currency = { add = nothing },
			Cosmetic = {
				skinShade = function(): number
					return 0
				end,
			},
		})
		combat.Start()
		local player = world:join(1, "Ada")
		player:LoadCharacterAsync()
		player.CharacterAdded:Fire(player.Character)
		return combat, player
	end

	it("finds no live body from the moment its Humanoid leaves until the next body, even put back in time", function()
		local combat, player = combatWorld()
		expect(combat.hasLiveBody(player)).toBe(true)
		local character = player.Character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		humanoid.Parent = nil
		expect(combat.hasLiveBody(player)).toBe(false)
		humanoid.Parent = character
		expect(combat.hasLiveBody(player)).toBe(false)
		player:LoadCharacterAsync()
		player.CharacterAdded:Fire(player.Character)
		expect(combat.hasLiveBody(player)).toBe(true)
		-- Nor a dead one.
		player.Character:FindFirstChildOfClass("Humanoid").Health = 0
		expect(combat.hasLiveBody(player)).toBe(false)
	end)

	it("is refused while CombatService holds no live body, Humanoid in place or not", function()
		local setup = Server.services()
		local player = setup.world:join(501, "Ada")
		player:LoadCharacterAsync()
		setup.bodiless[player] = true
		expect(setup.cast(player, "Brand")).toBe(false)
		setup.bodiless[player] = nil
		expect(setup.cast(player, "Brand")).toBe(true)
	end)
end)
