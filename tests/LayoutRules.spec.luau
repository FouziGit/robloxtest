--!strict
-- The interface held to what the engine does with its layouts (tests/layout.luau, D-170), run
-- (tests/engine.luau): the real HUD in the hub and in a fight, on a desktop and on a phone, every kind of toast,
-- and each screen of the colour pass on each of its tabs.
--
-- Seen in Studio, where the Lune gates had all passed:
-- - the quick bar's buttons, the meta cluster, the first-steps card and the toasts, all automatically sized, grew
--   to the screen's width or height around a sticker that filled them from a frame of its own.
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Layout = require("./layout")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SECONDS_PER_DAY = 86400
local DESKTOP_HEIGHT = 1080
local PHONE = { 844, 390 }
local ME = 42

-- A player part-way into everything: a daily reward to claim, a pass tier to claim, three glyphs equipped.
local function profile(today: number): any
	local quests = { PeriodKey = "", Claimed = {}, Progress = {} }
	return {
		Settings = {
			Keyboard = table.clone(InputConfig.DefaultKeyboard),
			Gamepad = table.clone(InputConfig.DefaultGamepad),
			CameraShake = true,
			MusicVolume = 0.5,
			SfxVolume = 1,
			Quality = "High",
		},
		Loadout = { Slots = { "Brand", "Wash", "Serif" }, SlotLimit = 6, ExtraSlots = 0 },
		Unlocks = { Glyphs = { "Brand", "Wash", "Serif" }, Pigments = {} },
		Progression = { Level = 5, XP = 10, TotalXP = 410 },
		Currency = { Folios = 100 },
		Stats = { GlyphsCast = 3, GlyphsHit = 1, Kills = 0, Deaths = 0, MatchesPlayed = 2, BestChain = 0 },
		Daily = { LastClaimDay = today - 1, Streak = 3, FirstWinDay = 0, PremiumBonusDay = 0 },
		Quests = { Daily = quests, Weekly = table.clone(quests) },
		Battlepass = {
			[GameConfig.SeasonId] = { Tier = 3, XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
		},
		Cosmetics = { Owned = {}, Equipped = {} },
		Passes = {},
		Rank = { SeasonId = GameConfig.SeasonId, Modes = {}, LastRewardedSeason = "" },
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
	}
end

local function expectClean(root: any, screenHeight: number)
	local found = Layout.check(root, screenHeight)
	if #found > 0 then
		error(table.concat(found, "\n"))
	end
end

-- `name` (a file of src/ui/screens), opened with `args` in a world on `phone` or a desktop.
local function screen(name: string, phone: { number }?, args: any?): (any, number, any)
	local world = Engine.world({
		Stubs = Engine.interfaceStubs(),
		-- The menu's Invite asks whether an invite can be sent: it cannot, here.
		Services = {
			SocialService = {
				CanSendGameInviteAsync = function(): boolean
					return false
				end,
				PromptGameInvite = function() end,
			},
		},
	})
	local height = DESKTOP_HEIGHT
	if phone ~= nil then
		height = Engine.phone(world, phone[1], phone[2])
	end
	local today = math.floor(world.workspace:GetServerTimeNow() / SECONDS_PER_DAY)
	local data = profile(today)
	local signal = Engine.signal
	world.player.UserId = ME
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
	local Screen = world.require("src/ui/screens/" .. name)
	local built = Screen.new({
		Localize = {
			t = function(key: string): string
				return key
			end,
			resolveParams = function(params: any): any
				return params
			end,
		},
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = signal(),
		},
		RemoteClient = {
			fire = function() end,
			on = function(_name: string, handler: (...any) -> ()): any
				return signal():Connect(handler)
			end,
			-- A leaderboard of twenty, the player twelfth.
			invoke = function(): (boolean, any)
				return true, { Entries = entries }
			end,
		},
		InputController = { captureNext = function() end, cancelCapture = function() end },
		SoundController = { play = function() end },
		HudController = { Notified = signal(), showLocalToast = function() end },
		MatchController = {
			QueueChanged = signal(),
			MatchChanged = signal(),
			MatchEnded = signal(),
			getQueue = function(): any
				return { Queued = false, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 2 }
			end,
			getMatch = function(): any
				return nil
			end,
			getLastOutcome = function(): any
				return nil
			end,
			joinQueue = function() end,
			leaveQueue = function() end,
		},
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return true
		end,
	})
	built:Open(args)
	world:advance(0.5)
	return built, height, world
end

local SCREENS: { { Name: string, Tabs: { string }? } } = {
	{ Name = "MenuScreen" },
	{ Name = "PlayScreen" },
	{ Name = "ShopScreen", Tabs = { "Today", "Folios", "Passes", "Locker" } },
	{ Name = "BattlepassScreen" },
	{ Name = "DailyScreen" },
	{ Name = "LoadoutScreen" },
	{ Name = "QuestsScreen" },
	{ Name = "LeaderboardScreen" },
	{ Name = "SettingsScreen" },
}

describe("the interface, held to the engine's layouts", function()
	local devices: { { Phone: { number }? } } = { {}, { Phone = PHONE } }
	for _, device in ipairs(devices) do
		local phone = device.Phone
		local where = if phone ~= nil then "on a phone" else "with a pointer"

		it("keeps the HUD's own sizes, in the hub " .. where, function()
			local today = math.floor(os.time() / SECONDS_PER_DAY)
			local fixture = Hud.build({ Profile = profile(today), Phone = phone })
			fixture.world:advance(1)
			local height = if phone ~= nil then Engine.phone(fixture.world, phone[1], phone[2]) else DESKTOP_HEIGHT
			expectClean(fixture.screen, height)
			-- The frames this rule was learnt on are there to be checked.
			expect(fixture.screen:FindFirstChild("QuickBar", true)).never.toBeNil()
			expect(fixture.screen:FindFirstChild("Steps", true)).never.toBeNil()
		end)

		it("keeps the HUD's own sizes, in a fight " .. where, function()
			local today = math.floor(os.time() / SECONDS_PER_DAY)
			local fixture = Hud.build({ Profile = profile(today), Phone = phone })
			fixture.match(Hud.match("Team3v3", 3))
			fixture.world:advance(1)
			local height = if phone ~= nil then Engine.phone(fixture.world, phone[1], phone[2]) else DESKTOP_HEIGHT
			expectClean(fixture.screen, height)
			expect(fixture.screen:FindFirstChild("Match", true).Visible).toBe(true)
		end)

		for _, entry in ipairs(SCREENS) do
			local tabs: { string } = entry.Tabs or { "" }
			for _, tab in ipairs(tabs) do
				local label = entry.Name .. (if tab ~= "" then " (" .. tab .. ")" else "")
				it("keeps " .. label .. "'s own sizes " .. where, function()
					local built, height = screen(entry.Name, phone, if tab ~= "" then { Tab = tab } else nil)
					expectClean(built.Instance, height)
				end)
			end
		end
	end

	it("keeps every kind of toast its own height", function()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local Toast = world.require("src/ui/components/Toast")
		local ScreenRoot = world.require("src/ui/components/ScreenRoot")
		local root = ScreenRoot.new({ Name = "Toasts", DisplayOrder = 50 })
		root.Instance.Parent = world.playerGui
		local toast = Toast.new({ Parent = root.Content, Lane = "Pointer" })
		for _, kind in ipairs({ "Info", "Success", "Error", "Reward", "Celebrate" }) do
			toast:Show("toast." .. kind, kind :: any, if kind == "Reward" then 50 else nil)
		end
		world:advance(0.2)
		expect(#root.Content:GetDescendants()).toBeGreaterThan(10)
		expectClean(root.Instance, DESKTOP_HEIGHT)
	end)
end)

return nil
