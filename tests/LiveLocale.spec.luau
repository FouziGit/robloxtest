--!strict
-- The player's language, followed live (E12-S3). It comes from the Translator Roblox gives for the player
-- (LocalizationService:GetTranslatorForPlayerAsync), which follows the language picked in the experience menu, on
-- the client and on the server alike; the Roblox app's language stands in until it answers. A change mid-session
-- writes the HUD, the screens and the world's words again without the player rejoining.
--
-- Run in the pretend engine (tests/engine): the real Localize, LocaleService, AntiCheatService, HudController with
-- the controllers that draw in its column, and MenuController with the real screens.
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local Hud = require("./hud")
local InputConfig = require("../src/shared/Config/InputConfig")
local Strings = require("../src/shared/Strings")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SECONDS_PER_DAY = 86400

-- Every word drawn under `root`.
local function texts(root: any): { string }
	local found: { string } = {}
	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			table.insert(found, child.Text)
		end
	end
	return found
end

-- Whether a label under `root` reads exactly `words`.
local function reads(root: any, words: string): boolean
	return table.find(texts(root), words) ~= nil
end

local function shows(root: any, words: string): boolean
	for _, text in ipairs(texts(root)) do
		if string.find(text, words, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function source(path: string): string
	local lines = {}
	for line in string.gmatch(fs.readFile(path) .. "\n", "(.-)\n") do
		table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
	end
	return table.concat(lines, "\n")
end

local function files(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			if entry ~= "Vendor" then
				files(path, out)
			end
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

-- What the controllers read their words through, in a language the spec changes (Localize.Changed).
local function switchable(): (any, (locale: string) -> ())
	local state = { Locale = "en" }
	local localize = {
		t = function(key: string, params: { [string]: any }?): string
			return Strings.t(key, params, state.Locale)
		end,
		resolveParams = function(params: any): any
			return params
		end,
		Changed = Engine.signal(),
	}
	local function switch(locale: string)
		state.Locale = locale
		localize.Changed:Fire(locale)
	end
	return localize, switch
end

-- A player a day into the game: a daily reward waiting, three glyphs equipped.
local function profile(): any
	local today = math.floor(os.time() / SECONDS_PER_DAY)
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
		Currency = { Folios = 2480 },
		Stats = { GlyphsCast = 0, GlyphsHit = 0, Kills = 0, Deaths = 0, MatchesPlayed = 0, BestChain = 0 },
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

----------------------------------------------------------------
-- Where the language comes from
----------------------------------------------------------------

-- The client's Localize, started with the app in `app` and the platform answering with `answer`.
local function client(app: string, answer: () -> any): (any, any, { string })
	local world = Engine.world({
		Services = {
			LocalizationService = {
				RobloxLocaleId = app,
				GetTranslatorForPlayerAsync = function(_self: any, _player: any): any
					return answer()
				end,
			},
		},
	})
	local Localize = world.require("src/client/Controllers/Localize")
	local fired: { string } = {}
	Localize.Changed:Connect(function(locale: string)
		table.insert(fired, locale)
	end)
	Localize.Init()
	Localize.Start()
	return world, Localize, fired
end

local function translator(localeId: string): any
	local found = Engine.instance("Translator")
	found.LocaleId = localeId
	return found
end

describe("the client's language", function()
	it("is the translator's, and follows it when the player picks another in the experience menu", function()
		local picked = translator("fr-fr")
		local _, Localize, fired = client("en-us", function(): any
			return picked
		end)
		expect(Localize.locale()).toBe("fr")
		expect(fired).toEqual({ "fr" })
		expect(Localize.t("menu.shop")).toBe("Boutique")
		expect(Localize.plural("quest.winMatches", 1)).toBe("Gagne 1 match")
		picked.LocaleId = "en-us"
		expect(Localize.locale()).toBe("en")
		expect(fired).toEqual({ "fr", "en" })
		expect(Localize.t("menu.shop")).toBe("Shop")
		-- Another English, or a language the game does not hold (read in English): nothing to write again.
		picked.LocaleId = "en-gb"
		picked.LocaleId = "de-de"
		expect(fired).toEqual({ "fr", "en" })
		picked.LocaleId = "fr-ca"
		expect(fired).toEqual({ "fr", "en", "fr" })
	end)

	it("is the app's until the translator answers, and stays it when the platform gives none", function()
		local world, Localize, fired = client("fr-fr", function(): any
			error("HTTP 503 (Service Unavailable)")
		end)
		expect(Localize.locale()).toBe("fr")
		expect(#fired).toBe(0)
		local warned = false
		for _, line in ipairs(world.warnings) do
			if string.find(line, "[Localize] no translator", 1, true) ~= nil then
				warned = true
			end
		end
		expect(warned).toBe(true)
		-- The same language from both: nothing to write again.
		local _, same, none = client("en-us", function(): any
			return translator("en-us")
		end)
		expect(same.locale()).toBe("en")
		expect(#none).toBe(0)
	end)
end)

describe("the server's language for a player", function()
	-- The server with `players` joined before it started, their translators given by `answers` (false: none).
	local function server(): (any, any, any, (userId: number, localeId: string, answer: any) -> any)
		local answers: { [any]: any } = {}
		local world = Engine.world({
			Services = {
				LocalizationService = {
					GetTranslatorForPlayerAsync = function(_self: any, player: any): any
						local answer = answers[player]
						if answer == false then
							error("HTTP 503 (Service Unavailable)")
						end
						return answer
					end,
				},
			},
		})
		local players = world.game:GetService("Players")
		local joined: { any } = {}
		players.GetPlayers = function(): { any }
			return joined
		end
		local function join(userId: number, localeId: string, answer: any): any
			local player = Engine.instance("Player", players)
			player.UserId = userId
			player.Name = "P" .. userId
			player.LocaleId = localeId
			answers[player] = answer
			table.insert(joined, player)
			return player
		end
		return world, world.require("src/server/Services/LocaleService"), players, join
	end

	it("is the player's translator, followed when it changes, and their app's without one", function()
		local world, LocaleService, players, join = server()
		local picked = translator("en-us")
		local early = join(1, "fr-fr", picked)
		LocaleService.Init({})
		-- Before anything answered: the language of the player's app.
		expect(LocaleService.of(early)).toBe("fr")
		LocaleService.Start()
		expect(LocaleService.of(early)).toBe("en")
		picked.LocaleId = "fr-ca"
		expect(LocaleService.of(early)).toBe("fr")
		-- A player who joins later, whose translator the platform cannot give: their app's, and a warning.
		local late = join(2, "fr-fr", false)
		players.PlayerAdded:Fire(late)
		expect(LocaleService.of(late)).toBe("fr")
		local warned = false
		for _, line in ipairs(world.warnings) do
			if string.find(line, "[LocaleService] no translator for user 2", 1, true) ~= nil then
				warned = true
			end
		end
		expect(warned).toBe(true)
		-- A player who left is forgotten: nothing of theirs is held.
		players.PlayerRemoving:Fire(early)
		picked.LocaleId = "en-us"
		expect(LocaleService.of(early)).toBe("fr")
	end)

	it("is the language a kick for abuse is written in", function()
		local world, LocaleService, _, join = server()
		local player = join(3, "en-us", translator("fr-fr"))
		LocaleService.Init({})
		LocaleService.Start()
		local reasons: { string } = {}
		player.Kick = function(_self: any, reason: string)
			table.insert(reasons, reason)
		end
		local AntiCheat = world.require("src/server/Services/AntiCheatService")
		AntiCheat.Init({ Locale = LocaleService })
		for _ = 1, GameConfig.Server.AbuseKickThreshold do
			AntiCheat.strike(player, "Remote", "bad payload")
		end
		expect(reasons).toEqual({ Strings.t("kick.abuse", nil, "fr") })
	end)
end)

----------------------------------------------------------------
-- What is written again
----------------------------------------------------------------

-- The words `key` says in both languages, for a spec that looks for one and then the other.
local function both(key: string, params: { [string]: any }?): (string, string)
	return Strings.t(key, params, "en"), Strings.t(key, params, "fr")
end

describe("a change of language, mid-session", function()
	it("writes the HUD's words again in the hub, the Folios grouped the new language's way", function()
		local localize, switch = switchable()
		local fixture = Hud.build({ Profile = profile(), Localize = localize })
		fixture.world:advance(1)
		local hud = fixture.screen
		local wordsBefore: { string } = {}
		local wordsAfter: { string } = {}
		for _, key in ipairs({ "menu.shop", "leaderboard.title", "hud.checklist.title", "hud.checklist.daily" }) do
			local en, fr = both(key)
			table.insert(wordsBefore, en)
			table.insert(wordsAfter, fr)
		end
		for _, words in ipairs(wordsBefore) do
			expect(shows(hud, words)).toBe(true)
		end
		expect(shows(hud, "2,480")).toBe(true)
		switch("fr")
		fixture.world:advance(1)
		for index, words in ipairs(wordsAfter) do
			expect(shows(hud, words)).toBe(true)
			expect(shows(hud, wordsBefore[index])).toBe(false)
		end
		expect(shows(hud, "2\u{202F}480")).toBe(true)
		expect(shows(hud, "2,480")).toBe(false)
	end)

	it("writes the wait in the queue again, counted from where it was", function()
		local localize, switch = switchable()
		local fixture = Hud.build({ Profile = profile(), Localize = localize })
		fixture.queue({ Queued = true, ModeId = "Duel1v1", WaitedSeconds = 40, QueuedCount = 1, NeededCount = 2 })
		fixture.world:advance(2.5)
		local waitedEn = Strings.t("queue.searching", { waited = 42 }, "en")
		local waitedFr = Strings.t("queue.searching", { waited = 42 }, "fr")
		assert(reads(fixture.screen, waitedEn), "the hub does not count the wait: this gate would check nothing")
		switch("fr")
		expect(reads(fixture.screen, waitedFr)).toBe(true)
		expect(reads(fixture.screen, waitedEn)).toBe(false)
	end)

	it("writes the Play sticker again on a phone", function()
		local localize, switch = switchable()
		local fixture = Hud.build({ Profile = profile(), Localize = localize, Phone = { 844, 390 } })
		fixture.world:advance(1)
		local sticker = fixture.screen:FindFirstChild("PlaySticker", true)
		assert(sticker ~= nil, "a phone's HUD has no Play sticker: this gate would check nothing")
		local en, fr = both("queue.title")
		expect(shows(sticker, en)).toBe(true)
		switch("fr")
		expect(shows(sticker, fr)).toBe(true)
		expect(shows(sticker, en)).toBe(false)
	end)

	-- The portal band fills on a tween, which the pretend engine has none of: its words are held by the pins of
	-- tests/Travel.spec.luau (wordPortal) and the relabel below.
	it("writes the bands again: the match, the Battleground, the Erasure and the one watched", function()
		local localize, switch = switchable()
		local fixture = Hud.build({ Profile = profile(), Localize = localize })
		fixture.remote("BattlegroundChanged", { Standing = 1, Defeated = 2 })
		fixture.remote("BossChanged", {
			Phase = "Fighting",
			SecondsLeft = 1,
			Health = 50,
			MaxHealth = 100,
			PhaseIndex = 1,
			Participants = 2,
			MyShare = 0.25,
		})
		fixture.match(Hud.match("Duel1v1", 1))
		fixture.world.require("src/client/Controllers/HudController").showSpectating("Ann", function() end)
		fixture.world:advance(1)
		local root = fixture.world.playerGui
		local function lines(locale: string): { string }
			local function t(key: string, params: { [string]: any }?): string
				return Strings.t(key, params, locale)
			end
			return {
				t("battleground.status", {
					standing = t("battleground.standing", { standing = 1 }),
					defeated = t("battleground.defeated", { defeated = 2 }),
				}),
				t("boss.name"),
				t("boss.timeLeft", { seconds = 1 }),
				t("match.band", { round = 1, mode = t("leaderboard.board.Duel1v1") }),
				t("match.watching", { name = "Ann" }),
			}
		end
		local english, french = lines("en"), lines("fr")
		expect(source("src/client/Controllers/TravelController.luau")).toContain(
			"local function relabel()\n\twordPortal()\n\twordPlace()\nend"
		)
		-- Exactly, label by label: a toast that came with the old words keeps them, and may name the same things.
		for _, words in ipairs(english) do
			if not reads(root, words) then
				error(("the HUD does not say %q: this gate would check nothing"):format(words))
			end
		end
		switch("fr")
		fixture.world:advance(1)
		for index, words in ipairs(french) do
			if not reads(root, words) then
				error(("after the change the HUD does not say %q"):format(words))
			end
			if english[index] ~= words and reads(root, english[index]) then
				error(("after the change the HUD still says %q"):format(english[index]))
			end
		end
	end)
end)

describe("the lock's mark, when the language changes", function()
	it("writes its miss again, and its target's words through SetTarget", function()
		local localize, switch = switchable()
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local marker = world.require("src/ui/components/LockMarker").new(world.playerGui, 64, localize)
		local noneEn, noneFr = both("hud.lock.none")
		expect(reads(world.playerGui, noneEn)).toBe(true)
		switch("fr")
		marker:Relabel()
		expect(reads(world.playerGui, noneFr)).toBe(true)
		expect(reads(world.playerGui, noneEn)).toBe(false)
		-- The controller hands the mark its target's name again, in the new language.
		local lockOn = source("src/client/Controllers/LockOnController.luau")
		expect(lockOn).toContain("mark:Relabel()")
		expect(lockOn).toContain("mark:SetTarget(nameOf(lock), lock.Humanoid)")
		expect(lockOn).toContain("localize.Changed:Connect(relabel)")
	end)

	it("has the titles over heads and the touch discs written again by their controllers", function()
		local cosmetic = source("src/client/Controllers/CosmeticController.luau")
		expect(cosmetic).toContain("for _, entry in pairs(tracked) do\n\t\twear(entry, TITLE_SLOT)\n\tend")
		expect(cosmetic).toContain("localize.Changed:Connect(rewordTitles)")
		expect(source("src/client/Controllers/InputController.luau")).toContain(
			"localize.Changed:Connect(relayoutTouch)"
		)
	end)
end)

-- What the screens asked of InputController's key capture: the captures begun, and those given back.
type Captures = { Begun: number, Cancelled: number }

-- MenuController and its screens, as the client wires them, in a language the spec changes.
local function menu(): (any, any, (locale: string) -> (), Captures)
	local localize, switch = switchable()
	local captures: Captures = { Begun = 0, Cancelled = 0 }
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
	local signal = Engine.signal
	local data = profile()
	local MenuController = world.require("src/client/Controllers/MenuController")
	MenuController.Init({
		Localize = localize,
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
			invoke = function(): (boolean, any)
				return true, { Entries = {} }
			end,
		},
		InputController = {
			setSuspended = function() end,
			captureNext = function()
				captures.Begun += 1
			end,
			cancelCapture = function()
				captures.Cancelled += 1
			end,
		},
		SoundController = { play = function() end },
		MatchController = {
			QueueChanged = signal(),
			MatchChanged = signal(),
			MatchEnded = signal(),
			getQueue = function(): any
				return { Queued = false, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 2 }
			end,
			rankedHere = function(): boolean
				return true
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
		HudController = { Notified = signal(), showLocalToast = function() end },
		TravelController = { Travelled = signal() },
	})
	MenuController.Start()
	return world, MenuController, switch, captures
end

describe("the screens, when the language changes", function()
	it(
		"builds the one in front again in the new language, where it was, and the one under it when Back comes",
		function()
			local world, MenuController, switch = menu()
			MenuController.open("Menu")
			world:advance(0.5)
			-- The Play tile opens the queue on top of the Menu, as a player's click does.
			local tile = world.playerGui:FindFirstChild("PlayTile", true)
			assert(tile ~= nil, "the Menu has no Play tile: this gate would check nothing")
			local press = if tile:IsA("TextButton") then tile else tile:FindFirstChildWhichIsA("TextButton", true)
			press.Activated:Fire()
			world:advance(0.5)
			local play = world.playerGui:FindFirstChild("PlayScreen")
			assert(play ~= nil and play.Enabled, "the Play screen did not open: this gate would check nothing")
			local joinEn, joinFr = both("queue.join")
			expect(shows(play, joinEn)).toBe(true)

			switch("fr")
			world:advance(0.5)
			-- The old screen is gone, and the one in its place speaks French, open.
			expect(Engine.destroyed(play)).toBe(true)
			local again = world.playerGui:FindFirstChild("PlayScreen")
			assert(again ~= nil, "the Play screen was not built again")
			expect(again.Enabled).toBe(true)
			expect(shows(again, joinFr)).toBe(true)
			expect(shows(again, joinEn)).toBe(false)
			expect(MenuController.isOpen()).toBe(true)
			expect(MenuController.canGoBack()).toBe(true)

			-- Back: the Menu, built again in French.
			MenuController.back()
			world:advance(0.5)
			local back = world.playerGui:FindFirstChild("MenuScreen")
			assert(back ~= nil and back.Enabled, "Back did not bring the Menu")
			local shopEn, shopFr = both("menu.shop")
			expect(shows(back, shopFr)).toBe(true)
			expect(shows(back, shopEn)).toBe(false)
		end
	)

	it("gives the key a Settings row was waiting for back to the game when the screen is built again", function()
		local world, MenuController, switch, captures = menu()
		MenuController.open("Settings")
		world:advance(0.5)
		local row = world.playerGui:FindFirstChild("Melee", true)
		local key = if row ~= nil then row:FindFirstChildWhichIsA("TextButton", true) else nil
		assert(key ~= nil, "the Settings show no Melee key: this gate would check nothing")
		key.Activated:Fire()
		assert(captures.Begun == 1, "the Melee key began no capture: this gate would check nothing")
		expect(captures.Cancelled).toBe(0)

		-- The page that asked for the key is let go: InputController stops waiting for it, and the rebuilt
		-- Settings, open where they were, wait for nothing.
		switch("fr")
		world:advance(0.5)
		expect(captures.Cancelled).toBe(1)
		local again = world.playerGui:FindFirstChild("SettingsScreen")
		assert(again ~= nil and again.Enabled, "the Settings were not built again, open")
		expect(captures.Begun).toBe(1)
	end)

	it("lets a closed screen go, to be built in the new language the next time it opens", function()
		local world, MenuController, switch = menu()
		MenuController.open("Quests")
		world:advance(0.5)
		MenuController.close()
		world:advance(0.5)
		local first = world.playerGui:FindFirstChild("QuestsScreen")
		assert(first ~= nil, "the Quests screen was never built: this gate would check nothing")
		switch("fr")
		expect(Engine.destroyed(first)).toBe(true)
		expect(world.playerGui:FindFirstChild("QuestsScreen")).toBeNil()
		MenuController.open("Quests")
		world:advance(0.5)
		local again = world.playerGui:FindFirstChild("QuestsScreen")
		assert(again ~= nil and again.Enabled, "the Quests screen did not open again")
		local _, daily = both("quest.daily")
		expect(shows(again, daily)).toBe(true)
	end)
end)

----------------------------------------------------------------
-- One source, and nobody left behind
----------------------------------------------------------------

describe("the language's source", function()
	it("is read in one place on each side: Localize on the client, LocaleService on the server", function()
		local all: { string } = {}
		files("src", all)
		for _, path in ipairs(all) do
			local code = source(path)
			local onClient = path == "src/client/Controllers/Localize.luau"
			local onServer = path == "src/server/Services/LocaleService.luau"
			for _, read in ipairs({ "RobloxLocaleId", "GetTranslatorForPlayer", "SystemLocaleId", "%.LocaleId" }) do
				if string.find(code, read) ~= nil and not onClient and not onServer then
					error(("%s reads the language itself (%s): ask Localize or LocaleService"):format(path, read))
				end
			end
		end
		expect(source("src/client/Controllers/Localize.luau")).toContain("GetTranslatorForPlayerAsync")
		expect(source("src/server/Services/LocaleService.luau")).toContain("GetTranslatorForPlayerAsync")
		-- Both kicks read it there.
		expect(source("src/server/Services/DataService.luau")).toContain(
			"player:Kick(Strings.t(key, nil, locale.of(player)))"
		)
		expect(source("src/server/Services/DataService.luau")).toContain("locale = deps.Locale")
	end)

	it("has every controller that writes words listen for a change of language", function()
		local controllers: { string } = {}
		files("src/client/Controllers", controllers)
		local writers = 0
		for _, path in ipairs(controllers) do
			local code = source(path)
			if
				path ~= "src/client/Controllers/Localize.luau"
				and string.find(code, "localize = deps.Localize", 1, true)
			then
				writers += 1
				if string.find(code, "localize.Changed:Connect(", 1, true) == nil then
					error(
						("%s writes words and never hears Localize.Changed: they stay in the old language"):format(path)
					)
				end
			end
		end
		expect(writers).toBeGreaterThanOrEqual(8)
	end)
end)

describe("the languages the game speaks", function()
	it("are English and French; Spanish, Brazilian Portuguese and every other read English", function()
		expect(Strings.Locales).toEqual({ "en", "fr" })
		expect(Strings.DefaultLocale).toBe("en")
		for _, id in ipairs({ "es-es", "es-mx", "pt-br", "pt-pt", "de-de", "ja-jp" }) do
			expect(Strings.localeFromId(id)).toBe("en")
		end
		expect(Strings.localeFromId("fr-fr")).toBe("fr")
		expect(Strings.localeFromId("fr-ca")).toBe("fr")
	end)

	it("keeps Roblox's automatic translation off every surface the code draws words on", function()
		local all: { string } = {}
		files("src", all)
		local roots = 0
		for _, path in ipairs(all) do
			local code = source(path)
			local named = 0
			for name in string.gmatch(code, 'local (%w+) = Instance%.new%("%w+Gui"%)') do
				named += 1
				if string.find(code, name .. ".AutoLocalize = false", 1, true) == nil then
					error(("%s draws on a %s that Roblox's automatic translation may rewrite"):format(path, name))
				end
			end
			-- A surface made any other way would go unread: each one has its own name to be switched off by.
			local made = 0
			for _ in string.gmatch(code, 'Instance%.new%("%w+Gui"%)') do
				made += 1
			end
			if made ~= named then
				error(
					("%s makes a surface this gate cannot follow: give it `local <name> = Instance.new(...)`"):format(
						path
					)
				)
			end
			roots += named
		end
		expect(roots).toBeGreaterThanOrEqual(11)
		-- Run: a screen's root, and so everything under it, is not auto-localised.
		local world = Engine.world({ Stubs = Engine.interfaceStubs() })
		local root = world.require("src/ui/components/ScreenRoot").new({ Name = "Probe", DisplayOrder = 1 })
		expect(root.Instance.AutoLocalize).toBe(false)
		local marker = world.require("src/ui/components/LockMarker")
		marker.new(world.playerGui, 64, {
			t = function(key: string): string
				return key
			end,
		})
		expect(world.playerGui:FindFirstChild("LockMarker").AutoLocalize).toBe(false)
		expect(world.playerGui:FindFirstChild("LockPlate").AutoLocalize).toBe(false)
	end)
end)
