--!strict
-- A private server a player bought plays unranked (E4-S4): its owner fills it with whoever they like, so
-- two accounts of one player could trade wins there forever. No Elo and no ladder move there, its matches pay a
-- share of their rewards, and the queue says so. A reserved server, which the game fills itself, stays ranked.
--
-- The three kinds of server run for real: RankingService, LeaderboardService (on OrderedDataStores that keep every
-- write) and MatchService in the pretend engine (tests/engine), a duel started, fought and walked out of, as the
-- engine would have it on each kind.
local Engine = require("./engine")
local GameConfig = require("../src/shared/Config/GameConfig")
local Harness = require("./harness")
local MatchConfig = require("../src/shared/Config/MatchConfig")
local ProgressionConfig = require("../src/shared/Config/ProgressionConfig")
local RankingConfig = require("../src/shared/Config/RankingConfig")
local ServerKind = require("../src/server/Pure/ServerKind")
local Strings = require("../src/shared/Strings")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

type Kind = { Name: string, Id: string, Owner: number }

local PUBLIC: Kind = { Name = "a public server", Id = "", Owner = 0 }
local PURCHASED: Kind = { Name = "a private server a player bought", Id = "ps-1", Owner = 4242 }
local RESERVED: Kind = { Name = "a reserved server", Id = "rs-1", Owner = 0 }

-- What one duel left behind on a server of `kind`: player 1 won it when player 2 walked out.
type Played = {
	world: any,
	profiles: { [number]: any },
	moved: { string },
	-- Every write the ladders took: "<store> <user id> = <value>".
	ladders: { string },
	outcome: any,
	xp: number,
	folios: number,
	firstWins: number,
	quests: { [string]: boolean },
}

local function play(kind: Kind): Played
	-- The ladders' OrderedDataStores, as LeaderboardService opens them: every write kept, every board read empty.
	local ladders: { string } = {}
	local dataStores = {
		GetOrderedDataStore = function(_self: any, name: string): any
			return {
				SetAsync = function(_store: any, key: string, value: number)
					table.insert(ladders, ("%s %s = %d"):format(name, key, value))
				end,
				GetSortedAsync = function(): any
					return {
						GetCurrentPage = function(): { any }
							return {}
						end,
					}
				end,
			}
		end,
	}
	local world = Engine.world({ Services = { DataStoreService = dataStores } })
	world.game.PrivateServerId = kind.Id
	world.game.PrivateServerOwnerId = kind.Owner
	world.game.BindToClose = function() end
	local players = world.game:GetService("Players")
	local byId: { [number]: any } = {}
	local profiles: { [number]: any } = {}
	local function join(userId: number): any
		local player = Engine.instance("Player", players)
		player.Name = "P" .. userId
		player.DisplayName = "P" .. userId
		player.UserId = userId
		-- Each round's body, so the hits of the fight below land on somebody.
		player.LoadCharacterAsync = function(self: any)
			local character = Engine.instance("Model")
			local humanoid = Engine.instance("Humanoid", character)
			humanoid.Health = 100
			humanoid.MaxHealth = 100
			local root = Engine.instance("Part", character)
			root.Name = "HumanoidRootPart"
			root.Position = roblox.Vector3.new(0, 500, 0)
			character.PrimaryPart = root
			character.PivotTo = function(_model: any, frame: any)
				root.Position = frame.Position
			end
			self.Character = character
		end
		byId[userId] = player
		-- The sections of DataService's template the match and the ladder read and write.
		profiles[userId] = {
			Rank = { SeasonId = "S1", Modes = {}, LastRewardedSeason = "", Opponents = { Day = 0, Counts = {} } },
			Stats = { MatchesPlayed = 0 },
			Daily = { MatchDay = 0, MatchFolios = 0 },
		}
		return player
	end
	-- As the engine answers it: a player who left is no longer found.
	players.GetPlayerByUserId = function(_self: any, userId: number): any
		local player = byId[userId]
		return if player ~= nil and player.Parent == players then player else nil
	end
	players.GetPlayerFromCharacter = function(_self: any, character: any): any
		for _, player in pairs(byId) do
			if player.Character == character and player.Parent == players then
				return player
			end
		end
		return nil
	end
	local winner = join(1)
	local leaver = join(2)
	players.GetPlayers = function(): { any }
		return if leaver.Parent == players then { winner, leaver } else { winner }
	end

	local data = {
		get = function(player: any): any
			return profiles[player.UserId]
		end,
		push = function() end,
		ProfileLoaded = Engine.signal(),
		BeforeRelease = Engine.signal(),
		ProfileReleased = Engine.signal(),
		isClosing = function(): boolean
			return false
		end,
	}
	local played: Played = {
		world = world,
		profiles = profiles,
		moved = {},
		ladders = ladders,
		outcome = nil,
		xp = 0,
		folios = 0,
		firstWins = 0,
		quests = {},
	}

	local Ranking = world.require("src/server/Services/RankingService")
	Ranking.Init({
		DataService = data,
		Currency = { add = function() end },
		Cosmetic = {
			grant = function(): boolean
				return true
			end,
		},
		Notify = { send = function() end },
	})
	Ranking.Start()
	-- Every rating move.
	Ranking.RatingChanged:Connect(function(player: any, modeId: string, before: number, after: number)
		table.insert(played.moved, ("%s %s %d -> %d"):format(player.Name, modeId, before, after))
	end)
	-- And the ladders' writer itself, on the stores above: whatever it would write to a S1_* ladder, and however
	-- it came to write it, the spec sees.
	local Leaderboard = world.require("src/server/Services/LeaderboardService")
	Leaderboard.Init({
		Registry = { setCallback = function() end },
		Ranking = Ranking,
		Hub = {
			getLeaderboardEntries = function(): any
				return nil
			end,
		},
	})
	Leaderboard.Start()

	local function pad(x: number): any
		local part = Engine.instance("Part")
		part.Position = roblox.Vector3.new(x, 500, 0)
		return part
	end
	local killZone = Engine.instance("Part")
	killZone.Position = roblox.Vector3.new(0, 460, 0)
	killZone.Touched = Engine.signal()
	local arena = {
		Instance = Engine.instance("Model"),
		Id = "Duel",
		SlotIndex = 1,
		Spawns = { { pad(-30) }, { pad(30) } },
		KillZone = killZone,
	}

	local damaged = Engine.signal()
	local Match = world.require("src/server/Services/MatchService")
	Match.Init({
		Registry = {
			fire = function(name: string, player: any, payload: any)
				if name == "MatchEnded" and player.UserId == 1 then
					played.outcome = payload
				end
			end,
		},
		DataService = data,
		Notify = { send = function() end },
		Combat = {
			Damaged = damaged,
			-- A match kill's Folios are paid by MatchService under the day's cap (D-255).
			Killed = Engine.signal(),
			setPolicy = function() end,
			resyncPosition = function() end,
		},
		Movement = {
			applyStun = function() end,
			applyFreeze = function() end,
			clearStun = function() end,
			isStunned = function(): boolean
				return false
			end,
		},
		Progression = {
			addXp = function(player: any, amount: number)
				if player.UserId == 1 then
					played.xp += amount
				end
			end,
		},
		Currency = {
			add = function(player: any, amount: number)
				if player.UserId == 1 then
					played.folios += amount
				end
			end,
		},
		Hub = { teleportToHub = function() end },
		Arena = {
			acquire = function(): any
				return arena
			end,
			release = function() end,
		},
		Ranking = Ranking,
		Quest = {
			report = function(player: any, event: string)
				played.quests[event .. ":" .. player.UserId] = true
			end,
		},
		Daily = {
			markFirstWin = function(): boolean
				played.firstWins += 1
				return true
			end,
		},
		Glyph = { Cast = Engine.signal(), CastLanded = Engine.signal(), resetCooldowns = function() end },
	})
	Match.Start()

	assert(Match.start("Duel1v1", { { 1 }, { 2 } }) ~= nil, "the duel did not start: this gate would check nothing")
	-- The duel is fought, a hit each way past MatchConfig.MinPlayedSeconds: a walk-out before that is void (D-255)
	-- and would leave the winner no result to read.
	world:advance(MatchConfig.Modes.Duel1v1.CountdownSeconds + 1)
	damaged:Fire(1, leaver.Character, 10, "Glyph")
	damaged:Fire(2, winner.Character, 10, "Glyph")
	world:advance(MatchConfig.MinPlayedSeconds)
	-- Then player 2 walks out: Players says they left, the match waits out the grace in which a server closing would
	-- take everybody (D-206), and their profile's session ends with its last save.
	players.PlayerRemoving:Fire(leaver)
	leaver.Parent = nil
	world:advance(GameConfig.Server.LeaveGraceSeconds + 1)
	data.BeforeRelease:Fire(leaver, profiles[2])
	world:advance(1)
	assert(played.outcome ~= nil, "the duel never ended for its winner: this gate would check nothing")
	-- Long enough for the ladders' periodic pass to take the winner's rating as well as the leaver's flush.
	world:advance(RankingConfig.Leaderboard.MinWriteIntervalSeconds)
	return played
end

describe("ranked play on each kind of server", function()
	it("tells a bought private server from a reserved one and a public one, as the DataModel page does", function()
		expect(ServerKind.of("", 0)).toBe("Public")
		expect(ServerKind.of("ps-1", 4242)).toBe("Purchased")
		expect(ServerKind.of("rs-1", 0)).toBe("Reserved")
		expect(ServerKind.ranked("Public")).toBe(true)
		expect(ServerKind.ranked("Reserved")).toBe(true)
		expect(ServerKind.ranked("Purchased")).toBe(false)
	end)

	for _, kind in ipairs({ PUBLIC, RESERVED }) do
		it("moves the Elo and pays the whole match on " .. kind.Name, function()
			local played = play(kind)
			local winner = played.profiles[1].Rank.Modes.Duel1v1
			local leaver = played.profiles[2].Rank.Modes.Duel1v1
			assert(winner ~= nil and leaver ~= nil, "a ranked duel wrote no rank")
			expect(winner.Rating).toBeGreaterThan(RankingConfig.InitialRating)
			expect(leaver.Rating).toBeLessThan(RankingConfig.InitialRating)
			-- The leaver's forfeit and the winner's result, each on its way to the ladder.
			expect(#played.moved).toBe(2)
			-- Both reached the duel's ladder, the winner above where they started and the leaver below it.
			local duel = GameConfig.SeasonId .. "_Duel1v1"
			expect(played.ladders).toContain(("%s 1 = %d"):format(duel, winner.Rating))
			expect(played.ladders).toContain(("%s 2 = %d"):format(duel, leaver.Rating))
			expect(played.outcome.RatingAfter).toBeGreaterThan(played.outcome.RatingBefore)
			expect(played.outcome.RankKeyAfter).never.toBe("")
			local scale = MatchConfig.Rewards.Duel1v1
			expect(played.xp).toBe(math.floor(ProgressionConfig.XP.MatchWin * scale.Xp + 0.5))
			expect(played.folios).toBe(math.floor(ProgressionConfig.Folios.MatchWin * scale.Folios + 0.5))
			expect(played.firstWins).toBe(1)
			expect(played.quests["MatchWin:1"]).toBe(true)
			expect(played.quests["MatchPlayed:1"]).toBe(true)
			expect(played.world.workspace:GetAttribute(MatchConfig.PrivateServer.UnrankedAttribute)).toBeNil()
		end)
	end

	it("moves no Elo, reaches no ladder and pays a share of the match on " .. PURCHASED.Name, function()
		local played = play(PURCHASED)
		-- Neither the winner's result nor the leaver's forfeit wrote a rank.
		expect(played.profiles[1].Rank.Modes.Duel1v1).toBeNil()
		expect(played.profiles[2].Rank.Modes.Duel1v1).toBeNil()
		expect(#played.moved).toBe(0)
		-- Nothing reached a ladder, the leaver's forced flush as they left included.
		expect(played.ladders).toEqual({})
		-- The Result says nothing of a rating that could not move.
		expect(played.outcome.RatingAfter).toBe(played.outcome.RatingBefore)
		expect(played.outcome.RankKeyBefore).toBe("")
		expect(played.outcome.RankKeyAfter).toBe("")
		local scale = MatchConfig.Rewards.Duel1v1
		local share = MatchConfig.PrivateServer.RewardShare
		expect(share).toBeGreaterThan(0)
		expect(share).toBeLessThan(1)
		expect(played.xp).toBe(math.floor(ProgressionConfig.XP.MatchWin * scale.Xp * share + 0.5))
		expect(played.folios).toBe(math.floor(ProgressionConfig.Folios.MatchWin * scale.Folios * share + 0.5))
		expect(played.xp).toBeLessThan(ProgressionConfig.XP.MatchWin * scale.Xp)
		-- No first win of the day and no won match towards a quest; the match still counts as played.
		expect(played.firstWins).toBe(0)
		expect(played.quests["MatchWin:1"]).toBeNil()
		expect(played.quests["MatchPlayed:1"]).toBe(true)
		expect(played.outcome.FirstWinOfDay).toBe(false)
		-- And the server says so to its clients.
		expect(played.world.workspace:GetAttribute(MatchConfig.PrivateServer.UnrankedAttribute)).toBe(true)
	end)
end)

-- A fake of what a screen is given, in `locale`, on a server ranked or not.
local function screenDeps(locale: string, ranked: boolean): any
	local signal = Engine.signal
	return {
		Localize = {
			t = function(key: string, params: { [string]: any }?): string
				return Strings.t(key, params, locale)
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
		HudController = { Notified = signal(), showLocalToast = function() end },
		MatchController = {
			QueueChanged = signal(),
			getQueue = function(): any
				return { Queued = false, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 2 }
			end,
			rankedHere = function(): boolean
				return ranked
			end,
			joinQueue = function() end,
			leaveQueue = function() end,
		},
		OnClose = function() end,
		OnNavigate = function() end,
		OnBack = function() end,
		CanGoBack = function(): boolean
			return false
		end,
	}
end

local function socialWorld(): any
	return Engine.world({
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
end

describe("the queue on a private server", function()
	it("reads the server's word from the Workspace", function()
		local world = Engine.world()
		local MatchController = world.require("src/client/Controllers/MatchController")
		expect(MatchController.rankedHere()).toBe(true)
		world.workspace:SetAttribute(MatchConfig.PrivateServer.UnrankedAttribute, true)
		expect(MatchController.rankedHere()).toBe(false)
	end)

	it("says « Non classé en serveur privé » on each ranked card, in both languages, and no Ranked tag", function()
		expect(Strings.t("queue.unranked", nil, "fr")).toBe("Non classé en serveur privé")
		expect(Strings.t("queue.unranked", nil, "en")).toBe("Unranked in a private server")
		for _, locale in ipairs(Strings.Locales) do
			local world = socialWorld()
			local screen = world.require("src/ui/screens/PlayScreen").new(screenDeps(locale, false))
			screen:Open()
			world:advance(0.5)
			local notices = 0
			for _, modeId in ipairs(MatchConfig.ModeOrder) do
				local card = screen.Instance:FindFirstChild(modeId, true)
				assert(card ~= nil, modeId .. " has no card")
				local notice = card:FindFirstChild("Unranked", true)
				if MatchConfig.Modes[modeId].Ranked then
					assert(notice ~= nil, modeId .. " says nothing of the private server")
					expect(notice.Text).toBe(Strings.t("queue.unranked", nil, locale))
					expect(notice.TextWrapped).toBe(true)
					notices += 1
				end
				expect(card:FindFirstChild("Ranked", true)).toBeNil()
			end
			expect(notices).toBeGreaterThan(0)
		end
	end)

	it("keeps the Ranked tag, and no notice, where ranked play counts", function()
		local world = socialWorld()
		local screen = world.require("src/ui/screens/PlayScreen").new(screenDeps("en", true))
		screen:Open()
		world:advance(0.5)
		for _, modeId in ipairs(MatchConfig.ModeOrder) do
			local card = screen.Instance:FindFirstChild(modeId, true)
			expect(card:FindFirstChild("Unranked", true)).toBeNil()
			expect(card:FindFirstChild("Ranked", true).Text).toBe("Ranked")
		end
	end)

	it("lets the Menu's Play ribbon say what the queue says", function()
		for _, ranked in ipairs({ true, false }) do
			local world = socialWorld()
			local screen = world.require("src/ui/screens/MenuScreen").new(screenDeps("fr", ranked))
			screen:Open()
			world:advance(0.5)
			local ribbon = screen.Instance:FindFirstChild("Ribbon", true)
			assert(ribbon ~= nil, "the Play tile has no ribbon: this gate would check nothing")
			expect(ribbon.Text).toBe(if ranked then "Classé" else "Non classé")
		end
	end)
end)
