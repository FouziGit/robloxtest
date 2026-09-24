--!strict
-- Lock-on (D-115): the arithmetic by its outputs (Pure/LockOnMath), its numbers tied to the ones they
-- answer to, and the wiring that makes it one lock -- the camera turned by Feel alone, the character
-- faced just before physics and never while it falls, what may be taken and when it is let go.
local FeelConfig = require("../src/shared/Config/FeelConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local Harness = require("./harness")
local InputConfig = require("../src/shared/Config/InputConfig")
local LockOnConfig = require("../src/shared/Config/LockOnConfig")
local LockOnMath = require("../src/shared/Pure/LockOnMath")
local PostureConfig = require("../src/shared/Config/PostureConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local CONTROLLER = "src/client/Controllers/LockOnController.luau"
local FEEL = "src/client/Controllers/Feel.luau"

local function strip(source: string): string
	return (source:gsub("%-%-[^\n]*", ""))
end

local function flat(path: string): string
	return (strip(fs.readFile(path)):gsub("%s+", " "))
end

local function functionIn(path: string, header: string): string
	local source = strip(fs.readFile(path))
	local start = source:find(header, 1, true)
	if start == nil then
		error(header .. " is not in " .. path .. ": this gate would check nothing")
	end
	local finish = source:find("\nend\n", start, true)
	if finish == nil then
		error(header .. " has no end in " .. path)
	end
	return (source:sub(start, finish + 4):gsub("%s+", " "))
end

local function has(code: string, fragment: string): boolean
	return code:find(fragment, 1, true) ~= nil
end

describe("the arithmetic of a lock (LockOnMath)", function()
	it("measures how far off the aim a target is", function()
		expect(LockOnMath.angle(0, 0, -1, 0, 0, -10)).toBeCloseTo(0, 6)
		expect(LockOnMath.angle(0, 0, -1, 10, 0, 0)).toBeCloseTo(90, 6)
		expect(LockOnMath.angle(0, 0, -1, 0, 0, 10)).toBeCloseTo(180, 6)
		expect(LockOnMath.angle(0, 0, -1, 0, 0, 0)).toBe(nil)
	end)

	it("takes what the camera looks at: within reach and the cone, nearest the aim, then the nearer", function()
		expect(LockOnMath.rank(10, 91, 90, 40)).toBe(nil)
		expect(LockOnMath.rank(41, 10, 90, 40)).toBe(nil)
		local onAim = LockOnMath.rank(2, 80, 90, 40) :: number
		local offAim = LockOnMath.rank(12, 5, 90, 40) :: number
		expect(onAim < offAim).toBe(true)
		-- The same angle: the nearer one.
		expect((LockOnMath.rank(5, 10, 90, 40) :: number) < (LockOnMath.rank(5, 60, 90, 40) :: number)).toBe(true)
		-- A degree nearer the aim always beats any distance within reach.
		expect((LockOnMath.rank(4, 90, 90, 40) :: number) < (LockOnMath.rank(5, 0, 90, 40) :: number)).toBe(true)
	end)

	it("looks at the target, a little from above, and never into the sky or the floor", function()
		local config = FeelConfig.LockOn
		local function look(dx: number, dy: number, dz: number): (number, number, number)
			local x, y, z =
				LockOnMath.look(dx, dy, dz, config.PitchBiasDegrees, config.PitchMinDegrees, config.PitchMaxDegrees)
			assert(x ~= nil and y ~= nil and z ~= nil, "no look")
			return x, y, z
		end
		-- Level with it: straight at it across the floor, tilted down by the bias.
		local x, y, z = look(30, 0, 40)
		expect(math.sqrt(x * x + y * y + z * z)).toBeCloseTo(1, 9)
		expect(x / z).toBeCloseTo(30 / 40, 9)
		expect(math.deg(math.asin(y))).toBeCloseTo(config.PitchBiasDegrees, 6)
		-- A boss's head far above, a target far below: held at the bounds.
		local _, up = look(2, 50, 0)
		expect(math.deg(math.asin(up))).toBeCloseTo(config.PitchMaxDegrees, 6)
		local _, down = look(2, -50, 0)
		expect(math.deg(math.asin(down))).toBeCloseTo(config.PitchMinDegrees, 6)
		-- Straight overhead there is no way to face.
		expect(LockOnMath.look(0, 10, 0, 0, -40, 25)).toBe(nil)
	end)

	it("faces the target across the floor, and not at all from on top of it", function()
		local x, z = LockOnMath.facing(1, 1, 4, 5, 0.5)
		expect(x).toBeCloseTo(0.6, 9)
		expect(z).toBeCloseTo(0.8, 9)
		expect(LockOnMath.facing(1, 1, 1.2, 1.2, 0.5)).toBe(nil)
	end)

	it("turns the same whatever the frame rate", function()
		expect(LockOnMath.turnShare(12, 0)).toBe(0)
		local half = LockOnMath.turnShare(12, 1 / 120)
		local whole = LockOnMath.turnShare(12, 1 / 60)
		-- Two half frames cover what one whole frame does.
		expect(1 - (1 - half) * (1 - half)).toBeCloseTo(whole, 9)
	end)
end)

describe("the numbers of a lock", function()
	it("reaches as far as the longest glyph, and lets go before a body stops being posed", function()
		local longest = 0
		for _, def in ipairs(GlyphConfig.Glyphs) do
			longest = math.max(longest, def.Range)
		end
		expect(LockOnConfig.AcquireStuds).toBeGreaterThanOrEqual(longest)
		expect(LockOnConfig.BreakStuds).toBeGreaterThan(LockOnConfig.AcquireStuds)
		expect(LockOnConfig.BreakStuds).toBeLessThanOrEqual(PostureConfig.RangeStuds)
		expect(LockOnConfig.ConeDegrees).toBeGreaterThan(0)
		expect(LockOnConfig.ConeDegrees).toBeLessThan(90)
		expect(LockOnConfig.FacingMinStuds).toBeGreaterThan(0)
	end)

	it("turns the camera most of the way in a fifth of a second, never in one frame", function()
		local config = FeelConfig.LockOn
		expect(LockOnMath.turnShare(config.Turn, 0.2)).toBeGreaterThanOrEqual(0.9)
		expect(LockOnMath.turnShare(config.Turn, 1 / 60)).toBeLessThanOrEqual(0.5)
		-- Inside the default camera's own ±80° and around the bias.
		expect(config.PitchMinDegrees).toBeGreaterThanOrEqual(-80)
		expect(config.PitchMaxDegrees).toBeLessThanOrEqual(80)
		expect(config.PitchMinDegrees < config.PitchBiasDegrees).toBe(true)
		expect(config.PitchBiasDegrees < config.PitchMaxDegrees).toBe(true)
	end)

	it("is on the wheel's click and the right stick's, rebindable, with a disc on touch", function()
		expect(InputConfig.DefaultKeyboard.LockOn).toBe("MouseButton3")
		expect(InputConfig.DefaultGamepad.LockOn).toBe("ButtonR3")
		expect(table.find(InputConfig.Rebindable, "LockOn")).never.toBe(nil)
		expect(InputConfig.Touch.Positions.LockOn).never.toBe(nil)
		expect(InputConfig.ActionShortKeys.LockOn).never.toBe(nil)
	end)

	it("finds the boss by a tag of its own, never the proofs' one", function()
		expect(type(WorldBossConfig.Boss.Tag)).toBe("string")
		expect(WorldBossConfig.Boss.Tag).never.toBe(GameConfig.Enemy.Tag)
		local encounter = flat("src/server/Services/WorldBossService/Encounter.luau")
		expect(has(encounter, "CollectionService:AddTag(model, BOSS.Tag)")).toBe(true)
	end)
end)

describe("the wiring of a lock", function()
	it("turns the camera in Feel alone, before any shake or hit-stop is laid on it", function()
		local render = functionIn(FEEL, "local function onRender(")
		local aimed = render:find("aimAtLock(camera, deltaTime)", 1, true)
		local held = render:find("if hitStopRemaining > 0 then", 1, true)
		expect(aimed).never.toBe(nil)
		expect(held).never.toBe(nil)
		expect((aimed :: number) < (held :: number)).toBe(true)
		local aim = functionIn(FEEL, "local function aimAtLock(")
		expect(has(aim, "local focus = camera.Focus.Position")).toBe(true)
		expect(has(aim, "local distance = (camera.CFrame.Position - focus).Magnitude")).toBe(true)
		expect(has(aim, "LockOnMath.look(")).toBe(true)
		-- Level with level: only a real difference in height tilts the view, never the pivot's own height.
		expect(has(aim, "local toward = target.Position + Vector3.yAxis * (focus.Y - own.Position.Y) - focus")).toBe(
			true
		)
		expect(has(aim, "local look = from:Lerp(to, LockOnMath.turnShare(config.Turn, deltaTime)).LookVector")).toBe(
			true
		)
		expect(has(aim, "camera.CFrame = CFrame.lookAlong(focus - look * distance, look)")).toBe(true)
		expect(has(functionIn(FEEL, "local function releaseAll("), "lockTarget = nil")).toBe(true)
		-- The controller frames through Feel and writes no camera of its own.
		local controller = flat(CONTROLLER)
		expect(has(controller, "feel.lockOn(lock.Root)")).toBe(true)
		expect(has(controller, "CurrentCamera.CFrame =")).toBe(false)
	end)

	it("faces the target just before physics, and never while the character falls or gets up", function()
		local face = functionIn(CONTROLLER, "local function face(")
		expect(has(face, "character:GetAttribute(RAGDOLL) ~= nil then return end")).toBe(true)
		expect(
			has(
				face,
				"if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.GettingUp then return end"
			)
		).toBe(true)
		expect(has(face, "humanoid.AutoRotate = false")).toBe(true)
		expect(has(face, "root.CFrame = CFrame.lookAlong(position, Vector3.new(x, 0, z))")).toBe(true)
		local start = functionIn(CONTROLLER, "function LockOnController.Start(")
		expect(has(start, "RunService.PreSimulation:Connect(step)")).toBe(true)
		-- Nothing else in the client turns the character off its walk.
		for _, path in ipairs({
			"src/client/Controllers/MovementController.luau",
			"src/client/Controllers/Posture.luau",
		}) do
			expect(has(flat(path), "AutoRotate")).toBe(false)
		end
	end)

	it("gives the character back its own turning when it lets go", function()
		local release = functionIn(CONTROLLER, "local function release(")
		expect(has(release, "feel.lockOn(nil)")).toBe(true)
		expect(has(release, "humanoid.AutoRotate = true")).toBe(true)
		local start = functionIn(CONTROLLER, "function LockOnController.Start(")
		expect(has(start, "if suspended then release() end")).toBe(true)
		expect(has(start, "player.CharacterRemoving:Connect(release)")).toBe(true)
		expect(has(start, "matchController.MatchChanged:Connect(onMatchChanged)")).toBe(true)
	end)

	it("takes only an opponent standing, in sight, and lets go of one that is no longer one", function()
		local acquire = functionIn(CONTROLLER, "local function acquire(")
		expect(has(acquire, "if lock.Model:GetAttribute(RAGDOLL) == nil then")).toBe(true)
		expect(has(acquire, "LockOnConfig.AcquireStuds, LockOnConfig.ConeDegrees")).toBe(true)
		expect(has(acquire, "if inSight(eye, entry.Lock) then return entry.Lock end")).toBe(true)
		local opponents = functionIn(CONTROLLER, "local function opponents(")
		expect(has(opponents, "if match.LocalTeam < 1 or mine == nil then return out end")).toBe(true)
		expect(has(opponents, "if member.UserId == player.UserId and not member.Alive then return out end")).toBe(true)
		expect(has(opponents, "if team ~= match.LocalTeam then")).toBe(true)
		expect(has(opponents, "CollectionService:GetTagged(GameConfig.Enemy.Tag)")).toBe(true)
		expect(has(opponents, "CollectionService:GetTagged(WorldBossConfig.Boss.Tag)")).toBe(true)
		local holds = functionIn(CONTROLLER, "local function holds(")
		expect(
			has(
				holds,
				"if (lock.Root.Position - root.Position).Magnitude > LockOnConfig.BreakStuds then return false end"
			)
		).toBe(true)
		expect(has(holds, "lock.Humanoid.Health <= 0")).toBe(true)
		expect(has(holds, "return Players:GetPlayerFromCharacter(lock.Model) ~= nil")).toBe(true)
		expect(has(holds, "return CollectionService:HasTag(lock.Model, GameConfig.Enemy.Tag)")).toBe(true)
	end)

	it("binds above the default camera, and shift-lock no longer shares the dash's key", function()
		local input = flat("src/client/Controllers/InputController.luau")
		expect(has(input, "local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value")).toBe(true)
		expect(
			has(
				input,
				"ContextActionService:BindActionAtPriority(action, onAction, touch, ACTION_PRIORITY, table.unpack(inputs))"
			)
		).toBe(true)
		expect(has(input, "ContextActionService:BindAction(")).toBe(false)
		local project = fs.readFile("default.project.json")
		expect(has(project, '"EnableMouseLockOption": false')).toBe(true)
	end)

	it("settles a player's keys around the new default when their profile loads", function()
		local data = functionIn("src/server/Services/DataService.luau", "local function loadProfile(")
		local settled = data:find(
			'for kind, allowed in pairs({ Keyboard = InputConfig.AllowedKeyboard, Gamepad = InputConfig.AllowedGamepad }) do local chosen = saved[kind] if DataMigration.settleKeybinds( migrated.Settings[kind], if type(chosen) == "table" then chosen else nil, allowed, ACTION_ORDER ) then',
			1,
			true
		)
		local replaced = data:find("replaceContents(profile.Data, migrated)", 1, true)
		expect(settled).never.toBe(nil)
		expect(replaced).never.toBe(nil)
		expect((settled :: number) < (replaced :: number)).toBe(true)
	end)
end)
