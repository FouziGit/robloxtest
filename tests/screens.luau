--!strict
-- The eleven screens run whole (tests/engine.luau), each built with the deps MenuController gives it: on a desktop or
-- a phone, played by any device (Engine.plays), its words the keys themselves or the player's own in a locale, for a
-- player part-way into everything -- or one who has everything, for what a screen costs at its fullest. Shared by
-- the layout rules (tests/LayoutRules.spec.luau), the object budgets (tests/ScreenBudget.spec.luau) and the
-- gamepad's selection graph (tests/GamepadGraph.spec.luau).
local BattlepassConfig = require("../src/shared/Config/BattlepassConfig")
local CosmeticConfig = require("../src/shared/Config/CosmeticConfig")
local DailyConfig = require("../src/shared/Config/DailyConfig")
local DrillConfig = require("../src/shared/Config/DrillConfig")
local Engine = require("./engine")
local ExLibrisConfig = require("../src/shared/Config/ExLibrisConfig")
local GameConfig = require("../src/shared/Config/GameConfig")
local GlyphConfig = require("../src/shared/Config/GlyphConfig")
local InputConfig = require("../src/shared/Config/InputConfig")
local MonetizationConfig = require("../src/shared/Config/MonetizationConfig")
local PigmentConfig = require("../src/shared/Config/PigmentConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local Strings = require("../src/shared/Strings")

local Screens = {}

local SECONDS_PER_DAY = 86400
-- The day every screen is opened on: noon UTC on 30 September 2026, the day docs/PERFORMANCE.md's counts were
-- measured. The Shop's Today tab draws that day's rotation, so a bench on the real clock drew a different
-- shop -- and a different count -- every day.
Screens.EPOCH = 1790769600
Screens.DESKTOP_HEIGHT = 1080
-- The local player's user id, twelfth on the leaderboard.
Screens.ME = 42

-- The nine screens of the menu and the Lectern of the hub, and the tabs each is opened on. The Result opens on a
-- match's end (Screens.result).
Screens.LIST = {
	{ Name = "MenuScreen" },
	{ Name = "PlayScreen" },
	{ Name = "ShopScreen", Tabs = { "Today", "Folios", "Passes", "Locker" } },
	{ Name = "BattlepassScreen" },
	{ Name = "DailyScreen" },
	{ Name = "LoadoutScreen" },
	{ Name = "QuestsScreen" },
	{ Name = "LeaderboardScreen" },
	{ Name = "SettingsScreen" },
	{ Name = "LecternScreen", Tabs = { "Drills", "Road", "ExLibris" } },
} :: { { Name: string, Tabs: { string }? } }

-- A player part-way into everything: a daily reward to claim, a pass tier to claim, three glyphs equipped.
function Screens.profile(today: number): any
	local quests = { PeriodKey = "", Claimed = {}, Progress = {}, Swaps = {} }
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
		Daily = {
			LastClaimDay = today - 1,
			Streak = 3,
			CalendarDay = 3,
			Signets = 0,
			FirstWinDay = 0,
			PremiumBonusDay = 0,
		},
		Quests = { Daily = quests, Weekly = table.clone(quests) },
		Battlepass = {
			[GameConfig.SeasonId] = { Tier = 3, XP = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {} },
		},
		Cosmetics = { Owned = {}, Equipped = {} },
		Passes = {},
		Rank = { SeasonId = GameConfig.SeasonId, Modes = {}, LastRewardedSeason = "" },
		Boosts = { XpUntil = 0, XpMultiplier = 1 },
		Drills = { KitString = 3, Brand = 1 },
		Milestones = {},
		ExLibris = { Pages25 = 0 },
	}
end

-- A player who has everything a screen can list: every glyph and pigment, every slot a pass opens filled, every
-- cosmetic and every pass owned, the pass at its last tier with every reward waiting, six days of a streak, a
-- balance of six figures, every drill at its best grade and every plate of the Ex-libris.
function Screens.fullest(today: number): any
	local data = Screens.profile(today)
	local glyphs = {}
	for _, glyph in ipairs(GlyphConfig.Glyphs) do
		table.insert(glyphs, glyph.Id)
	end
	local slots = {}
	for index = 1, ProgressionConfig.Loadout.MaxSlots do
		table.insert(slots, glyphs[index])
	end
	data.Loadout = { Slots = slots, SlotLimit = ProgressionConfig.Loadout.MaxSlots, ExtraSlots = 0 }
	data.Unlocks = { Glyphs = glyphs, Pigments = table.clone(PigmentConfig.Unlockable) }
	local owned = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		table.insert(owned, item.Id)
	end
	data.Cosmetics = { Owned = owned, Equipped = {} }
	local passes = {}
	for key in pairs(MonetizationConfig.Passes) do
		passes[key] = true
	end
	data.Passes = passes
	data.Progression = { Level = 40, XP = 10, TotalXP = 99999 }
	data.Currency = { Folios = 123456 }
	-- The calendar's week on its prize day, with every Signet a player may hold (DailyConfig.MaxSignets).
	data.Daily = {
		LastClaimDay = today - 1,
		Streak = 6,
		CalendarDay = 6,
		Signets = DailyConfig.MaxSignets,
		FirstWinDay = 0,
		PremiumBonusDay = 0,
	}
	data.Battlepass = {
		[GameConfig.SeasonId] = {
			Tier = BattlepassConfig.MaxTier,
			XP = 0,
			Premium = true,
			ClaimedFree = {},
			ClaimedPremium = {},
		},
	}
	local drills = {}
	for _, kit in ipairs(DrillConfig.Kit) do
		drills[kit.Id] = #DrillConfig.Grades
	end
	for _, glyph in ipairs(glyphs) do
		drills[glyph] = #DrillConfig.Grades
	end
	data.Drills = drills
	local plates = {}
	for _, plate in ipairs(ExLibrisConfig.Plates) do
		plates[plate.Id] = today * 86400
	end
	data.ExLibris = plates
	return data
end

export type Options = {
	-- A landscape phone, `{ width, height }` points, rather than a 1080p desktop.
	Phone: { number }?,
	-- What the screen is opened with (a tab).
	Args: any?,
	-- The player's own words in this locale, rather than the keys.
	Locale: string?,
	-- How the player plays (Engine.plays), after the phone or the desktop is set.
	Plays: Engine.Plays?,
	-- The profile, rather than Screens.profile: given the day the world starts on.
	Profile: ((today: number) -> any)?,
	-- How many rows of the leaderboard the server answers with: twenty unless told, its whole top at most.
	Entries: number?,
	-- Where the player stands on it: twelfth unless told.
	Rank: number?,
	-- A private server a player bought, where nothing is ranked (MatchController.rankedHere).
	Unranked: boolean?,
}

-- The Localize the screens are given: the keys themselves, or the player's words in `locale`.
local function localizer(locale: string?): any
	return {
		t = function(key: string, params: any?): string
			return if locale ~= nil then Strings.t(key, params, locale) else key
		end,
		resolveParams = function(params: any): any
			if locale == nil or params == nil then
				return params
			end
			local resolved = {}
			for field, value in pairs(params) do
				resolved[field] = if type(value) == "string" and Strings.has(value)
					then Strings.t(value, params, locale)
					else value
			end
			return resolved
		end,
	}
end

-- The world a screen opens in: the menu's Invite asks whether an invite can be sent (it cannot, here).
local function worldFor(options: Options): (any, number)
	local world = Engine.world({
		Epoch = Screens.EPOCH,
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
	local height = Screens.DESKTOP_HEIGHT
	local phone = options.Phone
	if phone ~= nil then
		height = Engine.phone(world, phone[1], phone[2])
	end
	local plays = options.Plays
	if plays ~= nil then
		Engine.plays(world, plays)
	end
	return world, height
end

-- `name` (a file of src/ui/screens), opened in a world set by `options`. Returns the screen, the height of its
-- ScreenGui in design units, the world, and the ClientData's Changed signal and profile (a push rebuilds).
function Screens.open(name: string, options: Options?): (any, number, any, any, any)
	local given: Options = options or {}
	local world, height = worldFor(given)
	local today = math.floor(world.workspace:GetServerTimeNow() / SECONDS_PER_DAY)
	local makeProfile = given.Profile or Screens.profile
	local data = makeProfile(today)
	local signal = Engine.signal
	local changed = signal()
	world.player.UserId = Screens.ME
	local entries = {}
	for rank = 1, math.min(given.Entries or 20, RankingConfig.Leaderboard.TopCount) do
		table.insert(entries, {
			Rank = rank,
			UserId = if rank == (given.Rank or 12) then Screens.ME else 1000 + rank,
			Name = "Player" .. rank,
			Rating = 2000 - rank,
			RankKey = "",
		})
	end
	local Screen = world.require("src/ui/screens/" .. name)
	local built = Screen.new({
		Localize = localizer(given.Locale),
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = changed,
		},
		RemoteClient = {
			fire = function() end,
			on = function(_name: string, handler: (...any) -> ()): any
				return signal():Connect(handler)
			end,
			-- The leaderboard's top, the player twelfth.
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
			rankedHere = function(): boolean
				return given.Unranked ~= true
			end,
			getMatch = function(): any
				return nil
			end,
			getLastOutcome = function(): any
				return nil
			end,
			joinQueue = function() end,
			leaveQueue = function() end,
			-- The practice duel the 1v1 card offers while its queue waits (E10-S6): not offered here.
			SparChanged = signal(),
			getSpar = function(): any
				return { Offered = false, Sparring = false, PaidLeft = 3, PaidPerDay = 3 }
			end,
			startSpar = function() end,
			leaveSpar = function() end,
		},
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return true
		end,
	})
	built:Open(given.Args)
	world:advance(0.5)
	return built, height, world, changed, data
end

-- The fullest card a match ends on: a new rank, the first win of the day, a glyph to unlock next, a best chain.
Screens.FULLEST_OUTCOME = {
	ModeId = "Duel1v1",
	Won = true,
	Draw = false,
	Scores = { 3, 1 },
	Xp = 120,
	Folios = 40,
	RatingBefore = RankingConfig.Tiers[2].Min - 10,
	RatingAfter = RankingConfig.Tiers[2].Min + 10,
	RankKeyBefore = RankingConfig.Tiers[1].NameKey,
	RankKeyAfter = RankingConfig.Tiers[2].NameKey,
	FirstWinOfDay = true,
	Casts = 24,
	Hits = 17,
	DamageDealt = 640,
	DamageTaken = 310,
	Grade = "grade.clean",
}

-- The Result, open on the fullest outcome, in a world set by `options`. Returns the screen, its height and the world.
function Screens.result(options: Options?): (any, number, any)
	local given: Options = options or {}
	local world, height = worldFor(given)
	local today = math.floor(world.workspace:GetServerTimeNow() / SECONDS_PER_DAY)
	local makeProfile = given.Profile or Screens.profile
	local data = makeProfile(today)
	data.Stats.BestChain = 4
	local Screen = world.require("src/ui/screens/ResultScreen")
	local built = Screen.new({
		Localize = localizer(given.Locale),
		ClientData = {
			get = function(): any
				return data
			end,
			Changed = Engine.signal(),
		},
		SoundController = { play = function() end },
		MatchController = {
			getLastOutcome = function(): any
				return Screens.FULLEST_OUTCOME
			end,
			joinQueue = function() end,
		},
		OnClose = function() end,
	})
	built:Open()
	world:advance(1)
	return built, height, world
end

return Screens
