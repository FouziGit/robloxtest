--!strict
-- The daily reward on a phone, run (tests/engine.luau, tests/measure.luau): the real DailyScreen.
--
-- Its content does not scroll: the calendar and two lines under it -- what tomorrow brings, and the nudge
-- that a streak of two days or more is about to be lost -- stand in the card's window. A calendar fixed at
-- 170 left a 667 x 375 phone about 205 units of window: tomorrow's line was cut through its letters and the
-- nudge the retention loop asks for never showed.
local Engine = require("./engine")
local Harness = require("./harness")
local Measure = require("./measure")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SECONDS_PER_DAY = 86400

local function build(width: number, height: number): (any, number)
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local screenHeight = Engine.phone(world, width, height)
	local Screen = world.require("src/ui/screens/DailyScreen")
	local today = math.floor(world.workspace:GetServerTimeNow() / SECONDS_PER_DAY)
	-- A three-day streak claimed yesterday: today can be claimed, and the nudge has something to say.
	local data = {
		Currency = { Folios = 0 },
		Daily = { LastClaimDay = today - 1, Streak = 3, FirstWinDay = 0, PremiumBonusDay = 0 },
	}
	local screen = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = Engine.signal(),
		},
		RemoteClient = { fire = function() end },
		InputController = { captureNext = function() end },
		SoundController = { play = function() end },
		HudController = { showLocalToast = function() end },
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	return screen, screenHeight
end

-- The height the frames of `parent` laid out in a list take: their heights and the list's gaps.
local function stacked(parent: any, names: { string }): number
	local gap = parent:FindFirstChildOfClass("UIListLayout").Padding.Offset
	local total = 0
	for index, name in ipairs(names) do
		total += parent:FindFirstChild(name).Size.Y.Offset + (if index > 1 then gap else 0)
	end
	return total
end

describe("the daily reward on a phone, run", function()
	for _, phone in ipairs({ { 667, 375 }, { 844, 390 } }) do
		it(
			("keeps tomorrow's line and the nudge in the window, on a %d x %d phone"):format(phone[1], phone[2]),
			function()
				local screen, screenHeight = build(phone[1], phone[2])
				local content = screen.Instance:FindFirstChild("Content", true)
				local padding = content:FindFirstChildOfClass("UIPadding")
				local window = Measure.heightOf(content, screenHeight)
					- padding.PaddingTop.Offset
					- padding.PaddingBottom.Offset
				local column = content:FindFirstChild("Streak")
				expect(column:FindFirstChild("AtRisk").Text).toBe("daily.atRisk")
				-- The column is the window's height, no more: a canvas of fromScale(1, 1), which the engine
				-- takes from the card rather than the window, left it the card's height with its header and
				-- footer, and the content scrolled onto nothing (D-171).
				expect(Measure.heightOf(column, screenHeight)).toBeLessThanOrEqual(window)
				-- The calendar takes what the lines leave, down to its floor.
				local calendar = column:FindFirstChild("Calendar")
				local range = calendar:FindFirstChildOfClass("UISizeConstraint")
				expect(calendar:FindFirstChildOfClass("UIFlexItem")).never.toBeNil()
				local floor = math.max(range.MinSize.Y, calendar.Size.Y.Offset)
				local gap = column:FindFirstChildOfClass("UIListLayout").Padding.Offset
				local needed = floor + gap + stacked(column, { "Tomorrow", "AtRisk" })
				if needed > window then
					error(("the calendar and its lines need %.1f and the window has %.1f"):format(needed, window))
				end
			end
		)
	end

	it("never squeezes a day card below what it holds", function()
		local screen = build(667, 375)
		local calendar = screen.Instance:FindFirstChild("Calendar", true)
		local floor = calendar:FindFirstChildOfClass("UISizeConstraint").MinSize.Y
		for _, day in ipairs(calendar:GetChildren()) do
			local face = day:FindFirstChild("Face")
			if face == nil then
				continue
			end
			local body = face:FindFirstChild("Body")
			local padding = body:FindFirstChildOfClass("UIPadding")
			local gap = body:FindFirstChildOfClass("UIListLayout").Padding.Offset
			-- Its day, its XP and its Folios, one under the other, in its padding, over its shadow.
			local heights, rows = 0, 0
			for _, child in ipairs(body:GetChildren()) do
				if child:IsA("GuiObject") then
					heights += child.Size.Y.Offset
					rows += 1
				end
			end
			expect(rows).toBe(3)
			local card = heights
				+ (rows - 1) * gap
				+ padding.PaddingTop.Offset
				+ padding.PaddingBottom.Offset
				- face.Size.Y.Offset
			expect(floor).toBeGreaterThanOrEqual(card)
		end
	end)
end)

return nil
