--!strict
-- A player's body as MovementService keeps it: every part in the players' collision group, which does not collide
-- with itself (D-XXXd). MovementService runs in the pretend engine (tests/serverworld.luau); what only a live server
-- can show -- two clients passing through each other, a finisher still throwing -- is QA §7.
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local ServerWorld = require("./serverworld")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local GROUP = GameConfig.Movement.CharacterCollisionGroup

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
