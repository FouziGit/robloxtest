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

	it("orders the candidates nearest the aim first, and leaves out what it may not take", function()
		local order = LockOnMath.order({
			{ Angle = 12, Distance = 5 },
			{ Angle = 2, Distance = 80 },
			{ Angle = nil, Distance = 3 },
			{ Angle = 50, Distance = 5 },
			{ Angle = 1, Distance = 95 },
			{ Angle = 2, Distance = 20 },
		}, 90, 40)
		-- 6 before 2 (same angle, nearer), 2 before 1; the eye itself, the one out of the cone and the one
		-- out of reach are not there at all.
		expect(#order).toBe(3)
		expect(order[1]).toBe(6)
		expect(order[2]).toBe(2)
		expect(order[3]).toBe(1)
		expect(#LockOnMath.order({}, 90, 40)).toBe(0)
	end)

	it("takes a height difference only beyond the deadband, and only what is beyond it", function()
		expect(LockOnMath.lift(12, 13)).toBe(0)
		expect(LockOnMath.lift(-13, 13)).toBe(0)
		expect(LockOnMath.lift(20, 13)).toBe(7)
		expect(LockOnMath.lift(-20, 13)).toBe(-7)
	end)

	it("reads a look as yaw and pitch and back, and turns the short way round", function()
		for _, look in ipairs({ { 0, 0, -1 }, { 1, 0, 0 }, { -0.6, 0.48, -0.64 }, { 0.36, -0.8, 0.48 } }) do
			local yaw, pitch = LockOnMath.yawPitch(look[1], look[2], look[3])
			local x, y, z = LockOnMath.fromYawPitch(yaw, pitch)
			expect(x).toBeCloseTo(look[1], 9)
			expect(y).toBeCloseTo(look[2], 9)
			expect(z).toBeCloseTo(look[3], 9)
		end
		-- Looking down -Z is yaw 0; +X is a quarter turn clockwise seen from above.
		expect(LockOnMath.yawPitch(0, 0, -1)).toBeCloseTo(0, 9)
		expect(LockOnMath.yawPitch(1, 0, 0)).toBeCloseTo(-math.pi / 2, 9)
		-- From just short of a half turn to just past it: a small turn, not most of a circle.
		local turned = LockOnMath.turnAngle(math.pi - 0.1, -math.pi + 0.1, 0.5)
		expect(math.abs(turned - math.pi)).toBeLessThan(1e-9)
		expect(LockOnMath.turnAngle(0.2, 0.6, 0.25)).toBeCloseTo(0.3, 9)
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
		-- Up and down slower than across, and not at all for a double jump: two jumps of JumpPower each
		-- rise v^2 / 2g apiece under Roblox's default gravity, which the place keeps.
		expect(config.PitchTurn).toBeLessThan(config.Turn)
		local jump = GameConfig.Movement.JumpPower ^ 2 / (2 * 196.2)
		local second = GameConfig.Movement.DoubleJumpVelocity ^ 2 / (2 * 196.2)
		expect(config.HeightDeadbandStuds).toBeGreaterThanOrEqual(jump + second)
		expect(config.CameraMarginStuds).toBeGreaterThan(0)
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
		expect(has(functionIn(FEEL, "local function releaseAll("), "lockTarget = nil")).toBe(true)
		-- The controller frames through Feel and writes no camera of its own.
		local controller = flat(CONTROLLER)
		expect(has(controller, "feel.lockOn(lock.Root)")).toBe(true)
		expect(has(controller, "CurrentCamera.CFrame =")).toBe(false)
	end)

	it("looks from above at the target's footing, turns up and down slowly, and stays out of the walls", function()
		local aim = functionIn(FEEL, "local function aimAtLock(")
		for _, line in ipairs({
			"local focus = camera.Focus.Position",
			"local distance = (camera.CFrame.Position - focus).Magnitude",
			"local across = target.Position - focus",
			-- Footing, not roots: a boss on your floor is not above you, and a jump is not a ledge.
			"local rise = LockOnMath.lift(footOf(target) - footOf(own), config.HeightDeadbandStuds)",
			"local x, y, z = LockOnMath.look( across.X, rise, across.Z, config.PitchBiasDegrees, config.PitchMinDegrees, config.PitchMaxDegrees )",
			"local yaw, pitch = LockOnMath.yawPitch(current.X, current.Y, current.Z)",
			"local goalYaw, goalPitch = LockOnMath.yawPitch(x, y, z)",
			"yaw = LockOnMath.turnAngle(yaw, goalYaw, LockOnMath.turnShare(config.Turn, deltaTime))",
			"pitch += (goalPitch - pitch) * LockOnMath.turnShare(config.PitchTurn, deltaTime)",
			"local look = Vector3.new(LockOnMath.fromYawPitch(yaw, pitch))",
			"lockSight.FilterDescendantsInstances = { ownModel, targetModel }",
			"local blocked = Workspace:Raycast(focus, -look * distance, lockSight)",
			"distance = math.max(blocked.Distance - config.CameraMarginStuds, 0)",
			"camera.CFrame = CFrame.lookAlong(focus - look * distance, look)",
		}) do
			if not has(aim, line) then
				error("aimAtLock no longer does: " .. line)
			end
		end
		local foot = functionIn(FEEL, "local function footOf(")
		expect(has(foot, "local frame, size = model:GetBoundingBox() return frame.Position.Y - size.Y / 2")).toBe(true)
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
		expect(
			has(
				face,
				"local x, z = LockOnMath.facing(position.X, position.Z, target.X, target.Z, LockOnConfig.FacingMinStuds)"
			)
		).toBe(true)
		expect(has(face, "local position = root.Position local target = lock.Root.Position")).toBe(true)
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

	it("takes on a press, lets go on the next, holds each frame, and lets go when it no longer holds", function()
		local start = functionIn(CONTROLLER, "function LockOnController.Start(")
		expect(has(start, "if actionId == ACTION and began then toggle() end")).toBe(true)
		expect(has(start, "if suspended then release() end")).toBe(true)
		expect(has(start, "player.CharacterRemoving:Connect(release)")).toBe(true)
		expect(has(start, "matchController.MatchChanged:Connect(onMatchChanged)")).toBe(true)
		expect(
			has(
				functionIn(CONTROLLER, "local function toggle("),
				"if current ~= nil then release() return end local lock = acquire() if lock ~= nil then engage(lock) end"
			)
		).toBe(true)
		expect(
			has(
				functionIn(CONTROLLER, "local function step("),
				"local lock = current if lock == nil then return end if not holds(lock) then release() return end face(lock)"
			)
		).toBe(true)
		local engage = functionIn(CONTROLLER, "local function engage(")
		expect(has(engage, "current = lock feel.lockOn(lock.Root)")).toBe(true)
		expect(has(engage, "marker:Show(lock.Root, liftOf(lock))")).toBe(true)
		expect(has(engage, "face(lock)")).toBe(true)
		local release = functionIn(CONTROLLER, "local function release(")
		expect(has(release, "current = nil feel.lockOn(nil)")).toBe(true)
		expect(has(release, "marker:Hide()")).toBe(true)
		expect(has(release, "humanoid.AutoRotate = true")).toBe(true)
		expect(
			has(
				functionIn(CONTROLLER, "local function onMatchChanged("),
				"for _, opponent in ipairs(opponents()) do if opponent.Model == lock.Model then return end end release()"
			)
		).toBe(true)
	end)

	it("takes only an opponent standing, nearest the aim, in sight past any body", function()
		local acquire = functionIn(CONTROLLER, "local function acquire(")
		for _, line in ipairs({
			"local eye = camera.CFrame.Position local look = camera.CFrame.LookVector",
			"table.insert(bodies, other.Character)",
			"table.insert(bodies, lock.Model) if lock.Model:GetAttribute(RAGDOLL) == nil then",
			"local toward = lock.Root.Position - eye",
			"Angle = LockOnMath.angle(look.X, look.Y, look.Z, toward.X, toward.Y, toward.Z),",
			"Distance = (lock.Root.Position - root.Position).Magnitude,",
			"for _, index in ipairs(LockOnMath.order(candidates, LockOnConfig.AcquireStuds, LockOnConfig.ConeDegrees)) do if inSight(eye, standing[index], bodies) then return standing[index] end end",
		}) do
			if not has(acquire, line) then
				error("acquire no longer does: " .. line)
			end
		end
		expect(
			has(
				functionIn(CONTROLLER, "local function inSight("),
				"sightParams.FilterDescendantsInstances = bodies return Workspace:Raycast(from, lock.Root.Position - from, sightParams) == nil"
			)
		).toBe(true)
		local opponents = functionIn(CONTROLLER, "local function opponents(")
		expect(has(opponents, "if match.LocalTeam < 1 or mine == nil then return out end")).toBe(true)
		expect(has(opponents, "if member.UserId == player.UserId and not member.Alive then return out end")).toBe(true)
		expect(has(opponents, "if team ~= match.LocalTeam then")).toBe(true)
		expect(has(opponents, "local other = if member.Alive then Players:GetPlayerByUserId(member.UserId) else nil")).toBe(
			true
		)
		expect(has(opponents, "CollectionService:GetTagged(GameConfig.Enemy.Tag)")).toBe(true)
		expect(has(opponents, "CollectionService:GetTagged(WorldBossConfig.Boss.Tag)")).toBe(true)
		local lockOf = functionIn(CONTROLLER, "local function lockOf(")
		expect(has(lockOf, "model == player.Character then return nil end")).toBe(true)
		expect(has(lockOf, "humanoid.Health <= 0")).toBe(true)
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
		expect(has(holds, "return CollectionService:HasTag(lock.Model, WorldBossConfig.Boss.Tag)")).toBe(true)
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
			"for kind, allowed in pairs({ Keyboard = InputConfig.AllowedKeyboard, Gamepad = InputConfig.AllowedGamepad }) do if DataMigration.settleKeybinds(migrated.Settings[kind], DEFAULT_KEYS[kind], allowed, ACTION_ORDER) then",
			1,
			true
		)
		local replaced = data:find("replaceContents(profile.Data, migrated)", 1, true)
		expect(settled).never.toBe(nil)
		local service = flat("src/server/Services/DataService.luau")
		expect(
			has(
				service,
				"for action, key in pairs(InputConfig.DefaultKeyboard) do DEFAULT_KEYS.Keyboard[action] = key end"
			)
		).toBe(true)
		expect(
			has(
				service,
				"for action, key in pairs(InputConfig.DefaultGamepad) do DEFAULT_KEYS.Gamepad[action] = key end"
			)
		).toBe(true)
		expect(replaced).never.toBe(nil)
		expect((settled :: number) < (replaced :: number)).toBe(true)
	end)
end)
