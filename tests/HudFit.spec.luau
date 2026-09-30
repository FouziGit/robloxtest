--!strict
-- The HUD fits the screens it is played on (D-147). Its geometry is measured, never scaled by the player's text
-- size (ThemeConfig.Hud), and this adds it up the conservative way: the top-centre column at its ceiling over
-- the bottom stack with everything in it counted as stacked -- the dock (its pips on touch), the hotbar with a
-- pointer, the combo row, and the preview pill as its own row although it shares the chips' -- against the
-- height a landscape phone gives at the touch floor, and the smallest window a pointer plays in. How wide the
-- dock may be between a phone's thumbs is tests/TouchCluster.spec.luau's, which lays the discs out on the
-- phones themselves.
local Engine = require("./engine")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Measure = require("./measure")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local Strings = require("../src/shared/Strings")
local ThemeConfig = require("../src/shared/Config/ThemeConfig")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local HUD = ThemeConfig.Hud
local HUD_CONTROLLER = "src/client/Controllers/HudController.luau"
local DOCK = "src/ui/components/CombatDock.luau"
local KEYCAP = "src/ui/components/Keycap.luau"
local BUTTON = "src/ui/components/Button.luau"
-- The safe area's own insets, top and bottom together, at most.
local SAFE_SLACK = 2 * 16
-- Landscape phones by their height in points: the small one, the 12-to-14 one, the Plus-sized one.
local PHONE_HEIGHTS = { 375, 390, 414 }
-- The smallest window a mouse or a gamepad plays in, and its width at 16:9.
local POINTER_HEIGHT = 720
local POINTER_WIDTH = 1280

local function code(path: string): string
	local withoutBlocks = string.gsub(fs.readFile(path), "%-%-%[%[.-%]%]", " ")
	local lines = {}
	for line in string.gmatch(withoutBlocks .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function has(source: string, plain: string): boolean
	return string.find(source, plain, 1, true) ~= nil
end

local function number(source: string, name: string): number
	local value = tonumber(string.match(source, "local " .. name .. " = ([%d%.]+)\n"))
	assert(value ~= nil, ("no number %s: this gate would check nothing"):format(name))
	return value :: number
end

-- The design units a screen `points` tall gives, at the scale the interface takes there.
local function room(points: number, touch: boolean): number
	return points / ThemeConfig.scaleFor(points, touch) - SAFE_SLACK
end

local function top(): number
	return HUD.TopPad + HUD.TopStackMaxHeight
end

-- The bottom stack on touch: off the edge, the dock with its pips over it in a row of their own, the combo row
-- over it, the preview over that.
local function touchBottom(): number
	local dockGap = number(code(DOCK), "GAP")
	return HUD.DockBottomPadTouch
		+ HUD.DockHeight
		+ HUD.HotbarPipsHeight
		+ dockGap
		+ HUD.ChipRowGap
		+ HUD.ChipSize
		+ HUD.ChipRowGap
		+ HUD.PreviewHeight
end

-- With a pointer: the dock, the hotbar's slots over their keys, the air the combo row stands off them, the combo
-- row, the preview.
local function pointerBottom(): number
	return HUD.DockBottomPad
		+ HUD.DockHeight
		+ HUD.ChipRowGap
		+ HUD.HotbarSlot
		+ HUD.HotbarKeyStrip
		+ HUD.ChipRowGap
		+ HUD.ComboLift
		+ HUD.ChipSize
		+ HUD.ChipRowGap
		+ HUD.PreviewHeight
end

describe("the HUD's fit", function()
	it("stacks the top column over the bottom one on every landscape phone, at the touch floor", function()
		for _, points in ipairs(PHONE_HEIGHTS) do
			local available = room(points, true)
			if top() + touchBottom() > available then
				error(
					("on a %d-point phone the HUD needs %d units and has %.1f"):format(
						points,
						top() + touchBottom(),
						available
					)
				)
			end
		end
		-- The smallest phone is the one the ceiling is set for: it leaves a margin, and not a vast one.
		expect(room(375, true) - (top() + touchBottom())).toBeLessThan(HUD.TopStackMaxHeight)
	end)

	it("stacks them in the smallest window a pointer plays in, at the pointer's floor", function()
		expect(ThemeConfig.scaleFor(POINTER_HEIGHT, false)).toBe(ThemeConfig.Scale.PointerFloor)
		expect(top() + pointerBottom()).toBeLessThanOrEqual(room(POINTER_HEIGHT, false))
	end)

	it("keeps the quick bar beside the bottom stack in the narrowest window a pointer plays in", function()
		-- The bar is a column in the bottom-right corner: its widest row is its width.
		local bar = code(HUD_CONTROLLER)
		local build = string.match(bar, "local function buildQuickBar%(.-\nend\n")
		assert(build ~= nil, "no buildQuickBar: this gate would check nothing")
		expect(has(build, "layout.FillDirection = Enum.FillDirection.Vertical")).toBe(true)
		expect(has(build, "quickBar.AnchorPoint = Vector2.new(1, 1)")).toBe(true)
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Theme = world.require("src/ui/Theme")
		local function buttonWidth(text: string): number
			return Measure.buttonWidth(text, Theme.Sizes.TextButton, true)
		end
		local keycap = code(KEYCAP)
		local function capWidth(text: string): number
			return number(keycap, "PADDING") * 2 + Measure.textWidth(text, number(keycap, "TEXT_SIZE"))
		end
		-- The fight's Menu pill: its word alone, in the label face, snug, never narrower than a thumb.
		local button = code(BUTTON)
		local function pillWidth(text: string): number
			local drawn = number(button, "COMPACT_PADDING") * 2
				+ Measure.textWidth(text, number(button, "COMPACT_TEXT_SIZE"))
			return math.max(Theme.MinTouchTarget, drawn)
		end
		local widest = 0
		for _, locale in ipairs(Strings.Locales) do
			for _, key in ipairs({ "queue.title", "menu.shop", "leaderboard.title" }) do
				widest = math.max(widest, buttonWidth(Strings.t(key, nil, locale)))
			end
			-- The Menu's row: its key cap, on the default key of either device, and the button.
			for _, cap in ipairs({ InputConfig.DefaultKeyboard.Menu, Strings.t("key.ButtonSelect", nil, locale) }) do
				local word = Strings.t("action.menu", nil, locale)
				widest = math.max(widest, capWidth(cap) + Theme.Sizes.Gap + buttonWidth(word))
				-- In a fight the same row holds the pill, which is narrower than the hub's button.
				local fighting = capWidth(cap) + Theme.Sizes.Gap + pillWidth(word)
				expect(fighting).toBeLessThan(capWidth(cap) + Theme.Sizes.Gap + buttonWidth(word))
				widest = math.max(widest, fighting)
			end
		end
		-- The bottom stack at its widest with a pointer: the dock, or a hotbar of every slot a pass opens.
		local slots = ProgressionConfig.Loadout.MaxSlots
		local hotbar = slots * HUD.HotbarSlot + (slots - 1) * HUD.HotbarGap
		local stackRight = POINTER_WIDTH / 2 + math.max(HUD.DockWidthPointer, hotbar) / 2
		local barLeft = POINTER_WIDTH - Theme.Sizes.Padding - widest
		if stackRight + Theme.Sizes.Gap > barLeft then
			error(("the quick bar starts at %.1f, the bottom stack ends at %.1f"):format(barLeft, stackRight))
		end
	end)

	it("lifts the combo row off the hotbar with a pointer only, by ComboLift in all", function()
		-- The board's combo row stands clear of the hotbar's keys; on touch the dock's pips are there instead.
		expect(HUD.ComboLift).toBeGreaterThan(HUD.ChipRowGap)
		for _, phone in ipairs({ false, true }) do
			local fixture = Hud.build({ Phone = if phone then { 844, 390 } else nil })
			local stack = fixture.screen:FindFirstChild("BottomStack", true)
			assert(stack ~= nil, "the HUD has no bottom stack: this gate would check nothing")
			local layout = stack:FindFirstChildOfClass("UIListLayout")
			expect(layout.Padding.Offset).toBe(HUD.ChipRowGap)
			local lift = stack:FindFirstChild("ComboLift")
			if phone then
				expect(lift).toBeNil()
			else
				assert(lift ~= nil, "the pointer's stack has no lift")
				-- A gap, the lift, a gap: ComboLift between the row and the hotbar, where the one gap stood.
				expect(layout.Padding.Offset * 2 + lift.Size.Y.Offset).toBe(HUD.ChipRowGap + HUD.ComboLift)
				expect(lift.Size.Y.Scale).toBe(0)
				expect(lift.BackgroundTransparency).toBe(1)
				local combo = stack:FindFirstChild("Combo")
				local hotbar: any = nil
				for _, child in ipairs(stack:GetChildren()) do
					if child:IsA("GuiObject") and child.LayoutOrder > lift.LayoutOrder and child ~= combo then
						if hotbar == nil or child.LayoutOrder < hotbar.LayoutOrder then
							hotbar = child
						end
					end
				end
				expect(combo.LayoutOrder).toBeLessThan(lift.LayoutOrder)
				assert(hotbar ~= nil, "nothing stands under the lift")
				expect(hotbar.Name).toBe("Hotbar")
			end
		end
		-- And the preview pill is the board's, about 41 tall, inside its row.
		expect(HUD.PreviewHeight).toBe(40)
		expect(HUD.PreviewHeight).toBeLessThanOrEqual(HUD.ChipSize)
	end)

	it(
		"shows the Menu as the board's small pill in a fight, beside its key, and the hub's button in the hub",
		function()
			-- A player whose settings name the Menu's key, which the cap draws.
			local quests = { PeriodKey = "", Claimed = {}, Progress = {} }
			local fixture = Hud.build({
				Profile = {
					Settings = {
						Keyboard = table.clone(InputConfig.DefaultKeyboard),
						Gamepad = table.clone(InputConfig.DefaultGamepad),
						CameraShake = true,
					},
					Loadout = { Slots = { "Brand" }, SlotLimit = 6 },
					Progression = { Level = 5, XP = 10 },
					Currency = { Folios = 100 },
					Stats = { GlyphsCast = 3, MatchesPlayed = 2 },
					Daily = { LastClaimDay = 0, Streak = 0 },
					Quests = { Daily = quests, Weekly = table.clone(quests) },
					Battlepass = {},
				},
			})
			fixture.world:advance(1)
			local row = fixture.screen:FindFirstChild("MenuRow", true)
			assert(row ~= nil, "the quick bar has no Menu row: this gate would check nothing")
			local cap = row:FindFirstChild("MenuKey")
			local hubButton: any, pill: any = nil, nil
			for _, child in ipairs(row:GetChildren()) do
				if child:IsA("TextButton") and child.Name == "action.menu" then
					if child:FindFirstChild("Icon", true):FindFirstChildWhichIsA("GuiObject") ~= nil then
						hubButton = child
					else
						pill = child
					end
				end
			end
			assert(
				cap ~= nil and hubButton ~= nil and pill ~= nil,
				"the Menu row lacks its cap, its button or its pill"
			)
			expect(cap.LayoutOrder).toBeLessThan(hubButton.LayoutOrder)
			expect(cap.LayoutOrder).toBeLessThan(pill.LayoutOrder)
			local function shown(): (boolean, boolean)
				return hubButton.Visible, pill.Visible
			end
			-- In the hub: the button with its icon.
			local button, small = shown()
			expect(button).toBe(true)
			expect(small).toBe(false)
			-- In a fight: the pill, its word alone in the label face, as short as a touch target, no badge.
			fixture.match(Hud.match("Duel1v1", 1))
			fixture.world:advance(1)
			button, small = shown()
			expect(button).toBe(false)
			expect(small).toBe(true)
			local world = fixture.world
			local Theme = world.require("src/ui/Theme")
			local word = pill:FindFirstChild("Label", true)
			expect(word.FontFace.Weight).toBe(Theme.Fonts.Label.Weight)
			expect(word.TextSize).toBe(14)
			expect(pill.Size.Y.Offset).toBe(Theme.MinTouchTarget)
			expect(pill.Selectable).toBe(false)
			expect(pill:FindFirstChild("Badge", true)).toBeNil()
			-- Back in the hub, the button returns.
			fixture.match(nil)
			fixture.world:advance(1)
			button, small = shown()
			expect(button).toBe(true)
			expect(small).toBe(false)
		end
	)

	it("keeps the dock's widest inside the gap a phone's thumbs leave", function()
		expect(HUD.DockWidthTouchMax * ThemeConfig.Scale.TouchFloor).toBeLessThanOrEqual(264)
	end)

	it("lays the HUD out by these numbers and no others", function()
		local hud = code(HUD_CONTROLLER)
		expect(has(hud, "topStack.Position = UDim2.new(0.5, 0, 0, HUD.TopPad)")).toBe(true)
		expect(has(hud, "ceiling.MaxSize = Vector2.new(math.huge, HUD.TopStackMaxHeight)")).toBe(true)
		expect(
			has(
				hud,
				"bottomStack.Position = UDim2.new(0.5, 0, 1, -(if touch then HUD.DockBottomPadTouch else HUD.DockBottomPad))"
			)
		).toBe(true)
		expect(has(hud, "layout.Padding = UDim.new(0, HUD.ChipRowGap)")).toBe(true)
		local dock = code(DOCK)
		expect(has(dock, "local height = HUD.DockHeight + (if props.Pips then HUD.HotbarPipsHeight + GAP else 0)")).toBe(
			true
		)
	end)
end)
