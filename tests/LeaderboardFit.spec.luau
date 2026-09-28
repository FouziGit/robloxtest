--!strict
-- The leaderboard on a phone, run (tests/engine.luau, tests/measure.luau): the real LeaderboardScreen.
--
-- Scrolling the player's own row out of sight pins it at the foot of the card, under a header that still
-- held the tabs and the player's standing: on a 667 x 375 phone the list kept about one row in view, and the
-- more-below fade covered half of it. Pinned, the row says what the standing says; the standing steps aside.
local Engine = require("./engine")
local Harness = require("./harness")
local Measure = require("./measure")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ME = 42
local ROWS_IN_VIEW = 2

type Fixture = { world: any, screen: any, content: any, screenHeight: number, played: { string } }

local function setup(width: number, height: number): Fixture
	local world = Engine.world({ Stubs = Engine.interfaceStubs() })
	local screenHeight = Engine.phone(world, width, height)
	world.player.UserId = ME
	local Screen = world.require("src/ui/screens/LeaderboardScreen")
	local entries = {}
	for rank = 1, 20 do
		table.insert(entries, {
			Rank = rank,
			UserId = if rank == 12 then ME else 1000 + rank,
			Name = "Player" .. rank,
			Rating = 2000 - rank,
			RankKey = "",
		})
	end
	local played: { string } = {}
	local screen = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
		},
		ClientData = {
			get = function(): any
				return { Rank = { Modes = {} } }
			end,
			Changed = Engine.signal(),
		},
		RemoteClient = {
			fire = function() end,
			invoke = function(): (boolean, any)
				return true, { Entries = entries }
			end,
		},
		SoundController = {
			play = function(id: string)
				table.insert(played, id)
			end,
		},
		OnClose = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	})
	screen:Open()
	world:advance(0.5)
	local content = screen.Instance:FindFirstChild("Content", true)
	return { world = world, screen = screen, content = content, screenHeight = screenHeight, played = played }
end

-- Scrolls the player's row out of the window the way the engine reports it: the row far below, then the
-- window's size changing, which is what the screen listens to.
local function scrollPast(fixture: Fixture)
	local mine
	for _, row in ipairs(fixture.content:GetChildren()) do
		for _, label in ipairs(row:GetDescendants()) do
			if label:IsA("TextLabel") and label.Text == "Player12" then
				mine = row
			end
		end
	end
	assert(mine ~= nil, "the board has no row for the player: this gate would check nothing")
	mine.AbsolutePosition = roblox.Vector2.new(0, 900)
	fixture.content.AbsoluteWindowSize = roblox.Vector2.new(800, 100)
end

-- The rows of the list the window shows, whole, between its padding.
local function rowsInView(fixture: Fixture): number
	local window = Measure.heightOf(fixture.content, fixture.screenHeight)
	local padding = fixture.content:FindFirstChildOfClass("UIPadding")
	local inside = window - padding.PaddingTop.Offset - padding.PaddingBottom.Offset
	local layout = fixture.content:FindFirstChildOfClass("UIListLayout")
	local Theme = fixture.world.require("src/ui/Theme")
	local pitch = Theme.Sizes.RowHeight + layout.Padding.Offset
	return (inside + layout.Padding.Offset) / pitch
end

describe("the leaderboard on a phone, run", function()
	for _, phone in ipairs({ { 667, 375 }, { 844, 390 } }) do
		it(
			("keeps two rows in view with the player's row pinned, on a %d x %d phone"):format(phone[1], phone[2]),
			function()
				local fixture = setup(phone[1], phone[2])
				scrollPast(fixture)
				local footer = fixture.screen.Instance:FindFirstChild("Footer", true)
				expect(footer.Size.Y.Offset).toBeGreaterThan(0)
				local rows = rowsInView(fixture)
				if rows < ROWS_IN_VIEW then
					error(("the list shows %.2f rows"):format(rows))
				end
			end
		)
	end

	it("lets the pinned row find the player, where the standing did", function()
		local fixture = setup(667, 375)
		local standing = fixture.screen.Instance:FindFirstChild("Standing", true)
		expect(standing.Visible).toBe(true)
		scrollPast(fixture)
		expect(standing.Visible).toBe(false)
		local footer = fixture.screen.Instance:FindFirstChild("Footer", true)
		local find = footer:FindFirstChild("FindMe", true)
		expect(find).never.toBeNil()
		-- Scrolled somewhere else in a long list, a tap brings the row to the middle of the window.
		fixture.content.AbsoluteCanvasSize = roblox.Vector2.new(800, 2000)
		fixture.content.CanvasPosition = roblox.Vector2.new(0, 300)
		find.Activated:Fire()
		expect(fixture.played[#fixture.played]).toBe("UiClick")
		expect(fixture.content.CanvasPosition.Y).toBe(900 + 300 - 100 / 2)
	end)
end)

return nil
