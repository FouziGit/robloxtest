--!strict
-- What Studio showed of the approved board and left uncorrected (PROGRESS, D-199 to D-201; E12-S5, D-XXX), run
-- (tests/engine.luau): the way back's chevron was a speck, the Menu left an empty band under its tiles with a
-- pointer, the hub's Folios were gold round a coin struck with an F where every screen's are the sheet round the
-- board's coin, and an icon nothing drew was still drawn in the code.
local Engine = require("./engine")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Measure = require("./measure")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local ICON = "src/ui/components/Icon.luau"

describe("the interface's leftovers, run", function()
	it("draws the way back as a chevron of two strokes across its square, not a guillemet", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Icon = world.require("src/ui/components/Icon")
		local Theme = world.require("src/ui/Theme")
		local back = Icon.new("Back", 28, Theme.Colors.Text)
		local strokes, words = 0, 0
		local top, bottom = math.huge, -math.huge
		for _, part in ipairs(back:GetDescendants()) do
			if part:IsA("TextLabel") then
				words += 1
			elseif part.Name == "Bar" then
				strokes += 1
				-- Each stroke's reach up and down the square, turned as it is drawn.
				local reach = part.Size.X.Scale / 2 * math.sin(math.rad(math.abs(part.Rotation)))
				top = math.min(top, part.Position.Y.Scale - reach)
				bottom = math.max(bottom, part.Position.Y.Scale + reach)
			end
		end
		expect(words).toBe(0)
		expect(strokes).toBe(2)
		-- Two thirds of its square high at least: the "‹" of the label face was a third.
		expect(bottom - top).toBeGreaterThan(0.6)
		expect(Theme.Glyphs.Back).toBeNil()
	end)

	it("draws no icon nothing asks for: the Check is gone with its last caller", function()
		local source = fs.readFile(ICON)
		expect(string.find(source, '"Check"', 1, true)).toBeNil()
		expect(string.find(source, "Check = function", 1, true)).toBeNil()
		-- Every drawing the file keeps is a name its type allows, and the other way round.
		local union: { [string]: boolean } = {}
		local typeBlock = string.match(source, "export type Name =(.-)\n\n")
		assert(typeBlock ~= nil, "Icon has no Name type: this gate would check nothing")
		for name in string.gmatch(typeBlock :: string, '"(%a+)"') do
			union[name] = true
		end
		local drawn: { [string]: boolean } = {}
		local builders = string.match(source, "local builders.-\n}\n")
		assert(builders ~= nil, "Icon has no builders: this gate would check nothing")
		for name in string.gmatch(builders :: string, "\n\t(%a+) = function") do
			drawn[name] = true
		end
		expect(drawn).toEqual(union)
	end)

	it("stands the Menu's card as tall as its tiles with a pointer, with no band under them", function()
		local world = Engine.world({
			Stubs = Engine.interfaceStubs(),
			Services = {
				SocialService = {
					CanSendGameInviteAsync = function(): boolean
						return false
					end,
					PromptGameInvite = function() end,
				},
			},
		})
		local Screen = world.require("src/ui/screens/MenuScreen")
		local signal = Engine.signal
		local screen = Screen.new({
			Localize = {
				t = function(key: string): string
					return key
				end,
			},
			ClientData = {
				get = function(): any
					return nil
				end,
				Changed = signal(),
			},
			RemoteClient = { fire = function() end },
			InputController = { captureNext = function() end },
			SoundController = { play = function() end },
			HudController = { showLocalToast = function() end },
			MatchController = {
				QueueChanged = signal(),
				getQueue = function(): any
					return { Queued = false, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 2 }
				end,
			},
			OnClose = function() end,
			OnNavigate = function() end,
			OnBack = function() end,
			CanGoBack = function(): boolean
				return false
			end,
		})
		screen:Open()
		world:advance(0.5)
		local deck = screen.Instance:FindFirstChild("Deck", true)
		assert(deck ~= nil, "the Menu has no deck: this gate would check nothing")
		-- The window the tiles stand in (its canvas never scrolls, so no bar is drawn in it), and the height the
		-- two rows stand at with a pointer: the one is the other.
		local content = deck.Parent
		local padding = content:FindFirstChildOfClass("UIPadding")
		local room = Measure.heightOf(content, 1080) - padding.PaddingTop.Offset - padding.PaddingBottom.Offset
		local tiles = deck:FindFirstChildOfClass("UISizeConstraint").MaxSize.Y
		expect(tiles).toBeGreaterThan(200)
		if math.abs(room - tiles) > 1 then
			error(("the Menu's tiles stand %.1f tall in a window of %.1f"):format(tiles, room))
		end
	end)

	it("writes the hub's Folios as every screen writes them: the board's coin, the count in the sheet", function()
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
				Currency = { Folios = 2480 },
				Stats = { GlyphsCast = 3, MatchesPlayed = 2 },
				Daily = { LastClaimDay = 0, Streak = 0 },
				Quests = { Daily = quests, Weekly = table.clone(quests) },
				Battlepass = {},
			},
		})
		fixture.world:advance(1)
		local hub = fixture.cluster:FindFirstChild("Folios", true)
		assert(hub ~= nil, "the hub has no Folios: this gate would check nothing")
		local FoliosPill = fixture.world.require("src/ui/components/FoliosPill")
		local gui = Engine.instance("ScreenGui", fixture.world.playerGui)
		local pill = FoliosPill.new({
			Localize = {
				t = function(key: string): string
					return key
				end,
			},
			Parent = gui,
		})
		pill:Set(2480, false)
		local function look(root: any): (any, any)
			local coin = root:FindFirstChild("Coin", true)
			local count = root:FindFirstChild("Count", true)
			assert(coin ~= nil and count ~= nil, root:GetFullName() .. " has no coin or no count")
			return coin, count
		end
		local hubCoin, hubCount = look(hub)
		local screenCoin, screenCount = look(pill.Instance)
		expect(hubCount.TextColor3).toBe(screenCount.TextColor3)
		expect(hubCoin.BackgroundColor3).toBe(screenCoin.BackgroundColor3)
		expect(hubCoin.Size).toBe(screenCoin.Size)
		expect(hubCoin:FindFirstChild("Ring")).never.toBeNil()
		-- No letter struck on it.
		expect(hubCoin:FindFirstChildWhichIsA("TextLabel", true)).toBeNil()
	end)
end)

return nil
