--!strict
-- The lock's mark (D-115, D-147): the board's diamond, the sheet in a thick ink outline, over the target, a pill
-- over it with the target's name and health, a warning before the lock breaks, a chevron toward a target out
-- of view, and a word for a press that locks nothing. It is drawn in the world, so it stays in ink and the
-- sheet (docs/ART_BIBLE.md rule 1). The edge arithmetic is pure and run here; the rest is engine code, held by
-- reading it and by running it on tests/engine.luau.
local Engine = require("./engine")
local Harness = require("./harness")
local LockOnConfig = require("../src/shared/Config/LockOnConfig")
local ScreenEdge = require("../src/shared/Pure/ScreenEdge")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local WorldBossConfig = require("../src/shared/Config/WorldBossConfig")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

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
	it("is the sheet in an ink outline of four, and never red (rule 1)", function()
		local marker = code(MARKER)
		expect(has(marker, "diamond.BackgroundColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(has(marker, 'local ink = Theme.stroke(diamond, "Accent", INK_THICKNESS)')).toBe(true)
		expect(number(marker, "INK_THICKNESS")).toBe(4)
		-- One frame: no sheet edge outside it and no dot in it.
		expect(has(marker, '"Edge"')).toBe(false)
		expect(has(marker, '"Dot"')).toBe(false)
		expect(string.find(marker, "Danger")).toBeNil()
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Accent)).toBeGreaterThanOrEqual(3)
		-- Taken and let go on the springs: the sheet and its outline fade together.
		local show = body(marker, "show")
		expect(has(show, 'Motion.to(ink, { Transparency = 0 }, "UiSnappy")')).toBe(true)
		expect(has(show, 'Motion.to(diamond, { BackgroundTransparency = 0 }, "UiSnappy")')).toBe(true)
		local hide = body(marker, "hide")
		expect(has(hide, 'Motion.to(diamond, { BackgroundTransparency = 1 }, "UiSnappy")')).toBe(true)
		expect(has(hide, 'Motion.to(ink, { Transparency = 1 }, "UiSnappy", function()')).toBe(true)
	end)

	it("names the target and its health on an ink pill over it, following the target's own health", function()
		local marker = code(MARKER)
		expect(number(marker, "PLATE_HEIGHT")).toBe(22)
		expect(number(marker, "PLATE_CORNER")).toBe(6)
		expect(number(marker, "PLATE_PADDING_Y")).toBe(2)
		expect(number(marker, "PLATE_PADDING_X")).toBe(8)
		expect(has(marker, "plate.AnchorPoint = Vector2.new(0.5, 1)")).toBe(true)
		expect(has(marker, "plate.Position = UDim2.new(0.5, 0, 0.5, -(size / 2 + PLATE_GAP))")).toBe(true)
		expect(has(marker, "plate.AutomaticSize = Enum.AutomaticSize.X")).toBe(true)
		expect(has(marker, "plate.BackgroundColor3 = Theme.Colors.Plate")).toBe(true)
		expect(has(marker, "plate.BackgroundTransparency = PLATE_TRANSPARENCY * UiPrefs.transparency()")).toBe(true)
		expect(number(marker, "PLATE_TRANSPARENCY")).toBe(0.1)
		expect(has(marker, "nameLabel.TextColor3 = Theme.Colors.PanelRaised")).toBe(true)
		expect(has(marker, "nameLabel.TextTruncate = Enum.TextTruncate.AtEnd")).toBe(true)
		-- In the heavy face, the board's 900 (the Bold face is its 800).
		expect(has(marker, "nameLabel.FontFace = Theme.Fonts.Label")).toBe(true)
		expect(ThemeConfig.Fonts.Label.Weight).toBe("Heavy")
		expect(number(marker, "NAME_TEXT")).toBe(14)
		expect(has(marker, 'local TARGET_KEY = "hud.lock.target"\n')).toBe(true)
		expect(Strings.Table["hud.lock.target"].en).toBe("{name} · {health}")
		expect(Strings.Table["hud.lock.target"].fr).toBe("{name} · {health}")
		expect(ThemeConfig.contrast(COLORS.PanelRaised, COLORS.Plate)).toBeGreaterThanOrEqual(4.5)
		-- The health strip is gone: the number says it.
		expect(has(marker, "STRIP")).toBe(false)
		local target = body(marker, "setTarget")
		expect(has(target, "unfollow()")).toBe(true)
		expect(has(target, "local health = math.max(0, math.ceil(humanoid.Health))")).toBe(true)
		expect(has(target, "nameLabel.Text = localize.t(TARGET_KEY, { name = name, health = health })")).toBe(true)
		expect(has(target, 'humanoid:GetPropertyChangedSignal("Health"):Connect(refresh)')).toBe(true)
		-- Followed only while it shows: let go, it hears nothing more.
		expect(has(body(marker, "hide"), "unfollow()")).toBe(true)
		-- The pill springs in and out with the diamond, never simply there or gone (rule 3).
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
		expect(has(warning, "diamond.BackgroundColor3 = Theme.Colors.Chalk")).toBe(true)
		expect(
			has(
				warning,
				'stopWarning = Motion.loop( diamond, { BackgroundTransparency = WARN_FROM }, { BackgroundTransparency = WARN_TO }, "Ui" )'
			)
		).toBe(true)
		expect(has(marker, "local WARN_FROM, WARN_TO = 0, 0.5")).toBe(true)
		-- The ink outline stays ink through the warning: only the sheet turns chalk.
		expect(has(marker, "ink.Color")).toBe(false)
		expect(has(body(marker, "endWarning"), "diamond.BackgroundColor3 = Theme.Colors.PanelRaised")).toBe(true)
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

describe("the lock's mark, run", function()
	local function build(): (any, any, any)
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local LockMarker = world.require("src/ui/components/LockMarker")
		local marker = LockMarker.new(world.playerGui, LockOnConfig.Marker.SizePx, {
			t = function(key: string, params: { [string]: any }?): string
				return Strings.t(key, params, "fr")
			end,
		})
		return world, marker, world.require("src/ui/Theme")
	end

	it("draws one sheet diamond in its ink, turned, and the pill over it", function()
		local world, marker, Theme = build()
		local diamond = world.playerGui:FindFirstChild("LockMarker"):FindFirstChild("Diamond")
		expect(diamond.Rotation).toBe(45)
		expect(diamond.BackgroundColor3).toBe(Theme.Colors.PanelRaised)
		local strokes, frames = 0, 0
		for _, part in ipairs(diamond:GetChildren()) do
			if part.ClassName == "UIStroke" then
				strokes += 1
				expect(part.Color).toBe(Theme.Colors.Accent)
				expect(part.Thickness).toBeGreaterThanOrEqual(4)
				expect(part.BorderStrokePosition).toBe(roblox.Enum.BorderStrokePosition.Inner)
			elseif part:IsA("GuiObject") then
				frames += 1
			end
		end
		expect(strokes).toBe(1)
		expect(frames).toBe(0)
		-- Hidden until a lock is taken; taken, both fade in.
		expect(diamond.BackgroundTransparency).toBe(1)
		local root = Engine.instance("Part", world.workspace)
		marker:Show(root, 3)
		world:advance(1)
		expect(diamond.BackgroundTransparency).toBeCloseTo(0, 2)
		expect(diamond:FindFirstChildOfClass("UIStroke").Transparency).toBeCloseTo(0, 2)
		-- The pill stands over the diamond, its foot the gap above its top.
		local plate = world.playerGui:FindFirstChild("LockPlate"):FindFirstChild("Plate")
		expect(plate.AnchorPoint).toBe(roblox.Vector2.new(0.5, 1))
		expect(plate.Position).toBe(roblox.UDim2.new(0.5, 0, 0.5, -(LockOnConfig.Marker.SizePx / 2 + 6)))
		expect(plate.Size.Y.Offset).toBe(22)
		expect(plate.BackgroundColor3).toBe(Theme.Colors.Plate)
		expect(plate:FindFirstChild("Health", true)).toBeNil()
		-- Near the break it turns chalk and breathes, its outline still ink.
		marker:SetWarning(true)
		expect(diamond.BackgroundColor3).toBe(Theme.Colors.Chalk)
		expect(diamond:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Colors.Accent)
		marker:SetWarning(false)
		expect(diamond.BackgroundColor3).toBe(Theme.Colors.PanelRaised)
		world:advance(1)
		expect(diamond.BackgroundTransparency).toBeCloseTo(0, 2)
	end)

	it("writes the target's name and health, follows its health, and lets go when hidden", function()
		local world, marker, Theme = build()
		local humanoid = Engine.instance("Humanoid", world.workspace)
		humanoid.MaxHealth = 100
		humanoid.Health = 64
		local root = Engine.instance("Part", world.workspace)
		marker:Show(root, 3)
		marker:SetTarget("Rival_07", humanoid)
		local name = world.playerGui:FindFirstChild("LockPlate"):FindFirstChild("Name", true)
		expect(name.Text).toBe("Rival_07 · 64")
		-- The sheet, in the heavy face, as the board writes it.
		expect(name.TextColor3).toBe(Theme.Colors.PanelRaised)
		expect(name.FontFace.Family).toBe(Theme.Fonts.Label.Family)
		expect(name.FontFace.Weight).toBe(roblox.Enum.FontWeight.Heavy)
		humanoid.Health = 50.2
		expect(name.Text).toBe("Rival_07 · 51")
		humanoid.Health = 0
		expect(name.Text).toBe("Rival_07 · 0")
		marker:Hide()
		humanoid.Health = 90
		expect(name.Text).toBe("Rival_07 · 0")
		expect(humanoid:GetPropertyChangedSignal("Health"):count()).toBe(0)
	end)
end)

return nil
