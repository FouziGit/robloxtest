--!strict
-- The lock's mark (D-115, D-147): a diamond of ink on a sheet edge over the target, a plate under it with the
-- target's name and health, a warning before the lock breaks, a chevron toward a target out of view, and a
-- word for a press that locks nothing. It is drawn in the world, so it stays in ink (docs/ART_BIBLE.md rule
-- 1). The edge arithmetic is pure and run here; the rest is engine code, held by reading it.
local Engine = require("./engine")
local Harness = require("./harness")
local LockOnConfig = require("../src/shared/Config/LockOnConfig")
local ScreenEdge = require("../src/shared/Pure/ScreenEdge")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local MARKER = "src/ui/components/LockMarker.luau"
local CONTROLLER = "src/client/Controllers/LockOnController.luau"
local COLORS = ThemeConfig.Colors

local function code(path: string): string
	local withoutBlocks = string.gsub(fs.readFile(path), "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

-- The body of the local function `name` in `source`, up to its closing `end` at the same indent, folded.
local function body(source: string, name: string): string
	local indent, rest = string.match(source, "\n(\t*)local function " .. name .. "%((.*)")
	assert(indent ~= nil and rest ~= nil, ("no local function %s: this gate would check nothing"):format(name))
	local finish = string.find(rest :: string, "\n" .. (indent :: string) .. "end\n", 1, true)
	assert(finish ~= nil, ("%s has no end"):format(name))
	return (string.gsub(string.sub(rest :: string, 1, finish :: number), "%s+", " "))
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

local function number(source: string, name: string): number
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("no number %s: this gate would check nothing"):format(name))
	return value :: number
end

describe("the edge of the screen", function()
	it("is where a line from the middle toward the target leaves it, and which way it points", function()
		local x, y, angle = ScreenEdge.toward(10, 0, 100, 50)
		expect(x).toBe(100)
		expect(y).toBe(0)
		expect(angle).toBe(0)
		x, y, angle = ScreenEdge.toward(0, -5, 100, 50)
		expect(x).toBe(0)
		expect(y).toBe(-50)
		expect(angle).toBe(-90)
		-- The nearer edge stops it: here the bottom, before the right.
		x, y, angle = ScreenEdge.toward(10, 10, 100, 50)
		expect(x).toBe(50)
		expect(y).toBe(50)
		expect(angle).toBe(45)
		-- Here the left, before the bottom.
		x, y = ScreenEdge.toward(-30, 10, 100, 50)
		expect(x).toBeCloseTo(-100, 6)
		expect(y).toBeCloseTo(100 / 3, 6)
		expect(ScreenEdge.toward(0, 0, 100, 50)).toBeNil()
	end)
end)

describe("the lock's mark", function()
	it("is a diamond of ink on a sheet edge, with a sheet dot, and never red (rule 1)", function()
		local marker = code(MARKER)
		expect(has(marker, 'local ink = Theme.stroke(inkFrame, "Accent", INK_THICKNESS)')).toBe(true)
		expect(has(marker, 'local edge = Theme.stroke(edgeFrame, "PanelRaised", EDGE_THICKNESS, "Border", "Outer")')).toBe(
			true
		)
		expect(number(marker, "INK_THICKNESS")).toBe(4)
		expect(number(marker, "EDGE_THICKNESS")).toBe(2)
		expect(has(marker, "dot.BackgroundColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(string.find(marker, "Danger")).toBeNil()
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Accent)).toBeGreaterThanOrEqual(3)
	end)

	it("names the target and draws its health on an ink plate under it, following the target's own health", function()
		local marker = code(MARKER)
		expect(number(marker, "PLATE_WIDTH")).toBe(120)
		expect(number(marker, "PLATE_HEIGHT")).toBe(40)
		expect(has(marker, "plate.BackgroundColor3 = Theme.Colors.Plate")).toBe(true)
		expect(has(marker, "plate.BackgroundTransparency = PLATE_TRANSPARENCY * UiPrefs.transparency()")).toBe(true)
		expect(number(marker, "PLATE_TRANSPARENCY")).toBe(0.1)
		expect(has(marker, "nameLabel.TextColor3 = Theme.Colors.TextInverse")).toBe(true)
		expect(has(marker, "nameLabel.TextTruncate = Enum.TextTruncate.AtEnd")).toBe(true)
		expect(number(marker, "NAME_TEXT")).toBe(14)
		expect(has(marker, "track.BackgroundColor3 = Theme.Colors.Well")).toBe(true)
		expect(has(marker, "fill.BackgroundColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(number(marker, "STRIP_WIDTH")).toBe(80)
		expect(number(marker, "STRIP_HEIGHT")).toBe(6)
		expect(ThemeConfig.contrast(COLORS.TextInverse, COLORS.Plate)).toBeGreaterThanOrEqual(4.5)
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Well)).toBeGreaterThanOrEqual(3)
		local target = body(marker, "setTarget")
		expect(has(target, "unfollow()")).toBe(true)
		expect(
			has(
				target,
				"local share = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0"
			)
		).toBe(true)
		expect(has(target, 'humanoid:GetPropertyChangedSignal("Health"):Connect(refresh)')).toBe(true)
		expect(has(target, 'humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)')).toBe(true)
		-- Followed only while it shows: let go, it hears nothing more.
		expect(has(body(marker, "hide"), "unfollow()")).toBe(true)
		-- The plate springs in and out with the diamond, never simply there or gone (rule 3).
		expect(has(body(marker, "show"), 'Motion.to(plateScale, { Scale = 1 }, "UiPop")')).toBe(true)
		expect(has(body(marker, "hide"), 'Motion.to(plateScale, { Scale = 0 }, "UiSnappy")')).toBe(true)
		-- The controller names a player by their display name, anything else by what it is.
		local controller = code(CONTROLLER)
		expect(has(body(controller, "engage"), "marker:SetTarget(nameOf(lock), lock.Humanoid)")).toBe(true)
		expect(has(body(controller, "nameOf"), "return other.DisplayName")).toBe(true)
		expect(
			has(
				(string.gsub(controller, "%s+", " ")),
				'local KIND_NAMES: { [Kind]: string } = { Proof = "hud.lock.dummy", Bot = "hud.lock.forger", Boss = WorldBossConfig.Boss.NameKey }'
			)
		).toBe(true)
		for _, key in ipairs({ "hud.lock.dummy", "hud.lock.forger", WorldBossConfig.Boss.NameKey }) do
			expect(Strings.has(key)).toBe(true)
		end
	end)

	it("warns in chalk, breathing, twenty studs before the lock breaks, and says so only when it changes", function()
		local controller = code(CONTROLLER)
		expect(has(controller, "local WARN_STUDS = LockOnConfig.BreakStuds - ThemeConfig.Hud.LockWarnStuds\n")).toBe(
			true
		)
		expect(ThemeConfig.Hud.LockWarnStuds).toBe(20)
		-- A lock just taken is never already warning.
		expect(LockOnConfig.BreakStuds - ThemeConfig.Hud.LockWarnStuds).toBeGreaterThan(LockOnConfig.AcquireStuds)
		local track = body(controller, "track")
		expect(has(track, "local warning = (lock.Root.Position - root.Position).Magnitude > WARN_STUDS")).toBe(true)
		expect(has(track, "if warning ~= warned then warned = warning mark:SetWarning(warning) end")).toBe(true)
		expect(has(body(controller, "step"), "face(lock) track(lock)")).toBe(true)
		expect(has(body(controller, "engage"), "warned = false current = lock")).toBe(true)
		local marker = code(MARKER)
		local warning = body(marker, "setWarning")
		expect(has(warning, "ink.Color = Theme.Colors.Chalk")).toBe(true)
		expect(
			has(
				warning,
				'stopWarning = Motion.loop(ink, { Transparency = WARN_FROM }, { Transparency = WARN_TO }, "Ui")'
			)
		).toBe(true)
		expect(has(marker, "local WARN_FROM, WARN_TO = 0, 0.5")).toBe(true)
		expect(has(body(marker, "endWarning"), "ink.Color = Theme.Colors.Accent")).toBe(true)
		expect(has(body(marker, "hide"), "endWarning()")).toBe(true)
	end)

	it("points to a target out of view from the edge of the safe area, in the frame the lock already runs", function()
		local controller = code(CONTROLLER)
		local track = body(controller, "track")
		expect(has(track, "local point, visible = camera:WorldToScreenPoint(lock.Root.Position)")).toBe(true)
		expect(has(track, "if visible then mark:SetOffscreen(nil) return end")).toBe(true)
		-- Behind the camera the projection is mirrored.
		expect(
			has(
				track,
				"local toward = if point.Z < 0 then centre - Vector2.new(point.X, point.Y) else Vector2.new(point.X, point.Y) - centre"
			)
		).toBe(true)
		local marker = code(MARKER)
		local offscreen = body(marker, "setOffscreen")
		expect(has(offscreen, "local reach = CHEVRON_INSET + CHEVRON / 2")).toBe(true)
		expect(has(offscreen, "ScreenEdge.toward(direction.X, direction.Y, area.X / 2 - reach, area.Y / 2 - reach)")).toBe(
			true
		)
		expect(has(offscreen, "chevron.Instance.Rotation = angle")).toBe(true)
		expect(number(marker, "CHEVRON")).toBe(32)
		expect(number(marker, "CHEVRON_INSET")).toBe(24)
		expect(
			has(marker, 'ScreenRoot.new({ Name = "LockOverlay", DisplayOrder = Theme.Layers.Hud, Parent = parent })')
		).toBe(true)
		expect(has(marker, "arrow.TextColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(has(marker, "arrow.Text = Theme.Glyphs.Play")).toBe(true)
		-- Written as it moves, with no spring: a spring would trail a turning camera.
		expect(has(offscreen, "Motion.")).toBe(false)
	end)

	it("says so when a press finds nothing to lock, a little under the middle, with a lower click", function()
		local controller = code(CONTROLLER)
		local toggle = body(controller, "toggle")
		expect(
			has(
				toggle,
				"if lock == nil and marker ~= nil then marker:ShowMiss() soundController.play(MISS_SOUND, nil, { Pitch = MISS_PITCH }) end"
			)
		).toBe(true)
		expect(has(controller, 'local MISS_SOUND = "UiClick"\n')).toBe(true)
		expect(number(controller, "MISS_PITCH")).toBe(0.8)
		expect(SoundConfig.Sfx.UiClick ~= nil).toBe(true)
		local marker = code(MARKER)
		expect(number(marker, "MISS_HEIGHT")).toBe(0.58)
		expect(number(marker, "MISS_SECONDS")).toBe(0.8)
		expect(has(marker, 'local MISS_KEY = "hud.lock.none"\n')).toBe(true)
		expect(Strings.has("hud.lock.none")).toBe(true)
		local miss = body(marker, "showMiss")
		expect(has(miss, 'Motion.to(missScale, { Scale = 1 }, "UiPop")')).toBe(true)
		expect(has(miss, 'Motion.to(missScale, { Scale = 0 }, "UiExit"')).toBe(true)
		expect(has(miss, "if token ~= missToken then return end")).toBe(true)
		expect(has(marker, "missLabel.TextColor3 = Theme.Colors.TextInverse")).toBe(true)
	end)
end)

describe("the lock's plate, run", function()
	it("rings the health track in the sheet, which the inkwell alone does not show on the plate", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local LockMarker = world.require("src/ui/components/LockMarker")
		local Theme = world.require("src/ui/Theme")
		LockMarker.new(world.playerGui, 34, {
			t = function(key: string): string
				return key
			end,
		})
		local track = world.playerGui:FindFirstChild("LockPlate"):FindFirstChild("Health", true)
		expect(track).never.toBeNil()
		expect(track.BackgroundColor3).toBe(Theme.Colors.Well)
		local ring = track:FindFirstChildOfClass("UIStroke")
		expect(ring).never.toBeNil()
		expect(ring.Color).toBe(Theme.Colors.PanelRaised)
		expect(ThemeConfig.contrast(COLORS.Well, COLORS.Plate)).toBeLessThan(3)
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Plate)).toBeGreaterThanOrEqual(3)
	end)
end)

return nil
