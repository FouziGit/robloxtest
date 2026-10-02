--!strict
-- SparService: the practice duel against a Duelist Forger, fought while the player waits in the 1v1 queue (E10-S6,
-- MatchConfig.Spar). After OfferAfterSeconds alone in that queue, the queue's card offers it (SparChanged);
-- StartSpar takes it. The player keeps their place in the queue, is put in one of the Battleground's pits against a
-- fresh Forger (BattlegroundService.openPit, seatPit), and plays first to RoundsToWin rounds, unranked, on the
-- match's own HUD and result card: its snapshots and its outcome are a match's, in the Spar1v1 mode (MatchChanged,
-- MatchEnded). A human who arrives in the queue takes over at the next break: while a round is played the
-- matchmaker holds the player out of every pairing (MatchmakingService.setSparring), and when it pairs them at a
-- break, Handover ends the spar before the match starts, paying nothing (and a match that then refuses to start
-- sends them home, still queued). LeaveSpar walks out of it, paying nothing.
--
-- It pays PaidPerDay spars a day, counted in the profile (Daily.SparDay / SparPaid, DailyCap, so switching servers
-- never resets the count), at RewardFactor of what the ranked duel pays for the same result; a spar past the
-- allowance is still fought, and says it pays nothing. It never writes the profile's Rank, never reports a match
-- to the quests, the first win of the day or MatchesPlayed: a spar is practice against the server.
--
-- One Heartbeat accumulator steps every spar, and every queued player's offer OfferTickSeconds apart. A round's
-- setup yields on LoadCharacterAsync, so it runs in its own thread and drops out when the spar moved on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DailyCap = require(script.Parent.Parent.Pure.DailyCap)
local DailyStreak = require(Shared.Pure.DailyStreak)
local Execution = require(Shared.Pure.Execution)
local GameConfig = require(Shared.Config.GameConfig)
local GlyphConfig = require(Shared.Config.GlyphConfig)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local SeriesOutcome = require(script.Parent.Parent.Pure.SeriesOutcome)
local SparRules = require(script.Parent.Parent.Pure.SparRules)
local Types = require(Shared.Types)

local log = Log.new("SparService")

type NotifyKind = "Info" | "Success" | "Error"
type Signal<T...> = { Connect: (self: any, fn: (T...) -> ()) -> any }
type Deps = {
	Registry: {
		on: (name: string, handler: (player: Player, ...any) -> ()) -> (),
		fire: (name: string, player: Player, ...any) -> (),
	},
	DataService: { get: (player: Player) -> Types.ProfileData?, push: (player: Player, section: string) -> () },
	Notify: {
		send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
	},
	Battleground: {
		openPit: (player: Player) -> boolean,
		seatPit: (player: Player, character: Model) -> boolean,
		setPitLive: (player: Player, live: boolean) -> (),
		pitForger: (player: Player) -> (boolean, number, number, Model?),
		closePit: (player: Player) -> (),
	},
	Matchmaking: {
		waiting: (player: Player) -> (string?, number, number),
		setSparring: (player: Player, inRound: boolean?) -> (),
		Handover: Signal<Player>,
	},
	Match: { isInMatch: (player: Player) -> boolean },
	WorldBoss: { isLive: () -> boolean, isEngaged: (player: Player) -> boolean },
	Movement: { applyFreeze: (player: Player, seconds: number) -> (), clearStun: (player: Player) -> () },
	Glyph: { Cast: Signal<Player, string, number>, CastLanded: Signal<Player, string, number> },
	Combat: { Damaged: Signal<number, Model, number, string> },
	Progression: { addXp: (player: Player, amount: number, reason: string) -> number },
	Currency: { add: (player: Player, amount: number, reason: string) -> number },
	Hub: { teleportToHub: (player: Player) -> () },
}

-- What the player did over the spar, for the result card's grade (Pure/Execution).
type Stats = { Casts: number, Hits: number, DamageDealt: number, DamageTaken: number }
-- Why a spar ends: its result is over, the player walked out, a match took them, the Erasure's event did, they
-- left the server, or its round could not be set up.
type Ending = "Done" | "Left" | "Handover" | "Taken" | "Gone" | "Failed"
type Spar = {
	Id: string,
	Player: Player,
	Phase: Types.MatchPhase,
	Round: number,
	-- Rounds won: the player's first, the Forger's second.
	Scores: { number },
	PhaseEndsAt: number,
	RoundEndsAt: number,
	-- A round setup thread is yielding on LoadCharacterAsync.
	Preparing: boolean,
	-- Bumped per round: a stale setup thread drops out.
	Generation: number,
	-- The body this round put on the pad, which its health is read from.
	Character: Model?,
	Stats: Stats,
	Ticks: number,
	Ended: boolean,
}

local DEF = MatchConfig.Modes.Spar1v1
local SPAR = MatchConfig.Spar
local TICK_SECONDS = 1 / GameConfig.Server.TickRate
local TICKS_PER_SNAPSHOT = math.max(1, math.floor(GameConfig.Server.TickRate / MatchConfig.SnapshotHz))
local MAX_ROUNDS = (DEF.RoundsToWin - 1) * DEF.Teams + 1
local ROUND_SECONDS = DEF.DurationSeconds / MAX_ROUNDS
local PLAYER_TEAM = 1
local FORGER_TEAM = 2
local OFFER_RULES: SparRules.OfferRules = { QueueModeId = SPAR.QueueModeId, OfferAfterSeconds = SPAR.OfferAfterSeconds }
local XP = ProgressionConfig.XP
local FOLIOS = ProgressionConfig.Folios
-- What the ranked duel pays for each result, before RewardFactor.
local BASE: { [SparRules.Outcome]: { Xp: number, Folios: number } } = {
	Win = { Xp = XP.MatchWin, Folios = FOLIOS.MatchWin },
	Loss = { Xp = XP.MatchLoss, Folios = FOLIOS.MatchLoss },
	Draw = { Xp = XP.MatchDraw, Folios = FOLIOS.MatchDraw },
}
local ROUND_KEYS: { [SparRules.Verdict]: { Key: string, Kind: NotifyKind } } = {
	Player = { Key = "match.roundWon", Kind = "Success" },
	Forger = { Key = "match.roundLost", Kind = "Error" },
	Draw = { Key = "match.draw", Kind = "Info" },
}

local SparService = {}

local deps: Deps
local spars: { [Player]: Spar } = {}
-- The offer each player was last shown, so SparChanged is sent only when it changes.
local shown: { [Player]: Types.SparSnapshot } = {}
local nextId = 0
local accumulator = 0
local offerAccumulator = 0

----------------------------------------------------------------
-- The offer
----------------------------------------------------------------

local function today(): number
	return DailyStreak.dayIndex(os.time())
end

-- The paid spars `player` has left today; all of them while the profile is not loaded.
local function paidLeft(player: Player): number
	local data = deps.DataService.get(player)
	if data == nil then
		return SPAR.PaidPerDay
	end
	local _, used = DailyCap.take(data.Daily.SparDay, data.Daily.SparPaid, today(), SPAR.PaidPerDay, 0)
	return SparRules.paidLeft(used, SPAR.PaidPerDay)
end

local function offered(player: Player): boolean
	local queuedFor, waited, queued = deps.Matchmaking.waiting(player)
	return SparRules.offered({
		QueuedFor = queuedFor,
		WaitedSeconds = waited,
		Others = queued - 1,
		Sparring = spars[player] ~= nil,
		InMatch = deps.Match.isInMatch(player),
		EventLive = deps.WorldBoss.isLive(),
		Engaged = deps.WorldBoss.isEngaged(player),
	}, OFFER_RULES)
end

-- Sends `player` the offer as it stands, when it differs from the one they were last shown.
local function pushOffer(player: Player)
	if player.Parent ~= Players then
		return
	end
	local snapshot: Types.SparSnapshot = {
		Offered = offered(player),
		Sparring = spars[player] ~= nil,
		PaidLeft = paidLeft(player),
		PaidPerDay = SPAR.PaidPerDay,
	}
	local last = shown[player]
	if
		last ~= nil
		and last.Offered == snapshot.Offered
		and last.Sparring == snapshot.Sparring
		and last.PaidLeft == snapshot.PaidLeft
	then
		return
	end
	shown[player] = snapshot
	deps.Registry.fire("SparChanged", player, snapshot)
end

----------------------------------------------------------------
-- The duel's two sides
----------------------------------------------------------------

local function playerSide(spar: Spar): SparRules.Side
	local character = spar.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or humanoid == nil or spar.Player.Character ~= character or humanoid.Health <= 0 then
		return { Alive = false, Health = 0, MaxHealth = if humanoid ~= nil then humanoid.MaxHealth else 0 }
	end
	return { Alive = true, Health = humanoid.Health, MaxHealth = humanoid.MaxHealth }
end

local function forgerSide(spar: Spar): SparRules.Side
	local alive, health, maxHealth = deps.Battleground.pitForger(spar.Player)
	return { Alive = alive, Health = health, MaxHealth = maxHealth }
end

-- The spar as a match's snapshot, for the HUD's band: the player on team 1, the Forger on team 2 under
-- MatchConfig.Spar.ForgerUserId, with no name (the server words nothing for the player). Unranked, and nobody in it
-- holds a rank; the Forger has no level either (the announcement names no one for a spar, E10-S7).
local function snapshot(spar: Spar, now: number): Types.MatchSnapshot
	local player = spar.Player
	local mine, theirs = playerSide(spar), forgerSide(spar)
	local data = deps.DataService.get(player)
	return {
		MatchId = spar.Id,
		ModeId = DEF.Id :: any,
		Phase = spar.Phase,
		SecondsLeft = math.max(0, math.ceil(spar.PhaseEndsAt - now)),
		Round = spar.Round,
		RoundsToWin = DEF.RoundsToWin,
		Scores = table.clone(spar.Scores),
		Teams = {
			{
				{
					UserId = player.UserId,
					Name = player.DisplayName,
					Team = PLAYER_TEAM,
					Alive = mine.Alive,
					Health = mine.Health,
					MaxHealth = mine.MaxHealth,
					Level = if data ~= nil then data.Progression.Level else 1,
					RankKey = "",
				},
			},
			{
				{
					UserId = SPAR.ForgerUserId,
					Name = "",
					Team = FORGER_TEAM,
					Alive = theirs.Alive,
					Health = theirs.Health,
					MaxHealth = theirs.MaxHealth,
					Level = 0,
					RankKey = "",
				},
			},
		},
		LocalTeam = PLAYER_TEAM,
		Ranked = false,
	}
end

----------------------------------------------------------------
-- Ending
----------------------------------------------------------------

-- Every way out of a spar: its pit given back, its hold on the queue lifted, and the player told as the ending
-- asks. A match that took them now owns their HUD and their body; the Erasure's event their body.
local function finish(spar: Spar, ending: Ending)
	if spar.Ended then
		return
	end
	spar.Ended = true
	local player = spar.Player
	spars[player] = nil
	deps.Battleground.closePit(player)
	deps.Matchmaking.setSparring(player, nil)
	log.info("%s's spar %s ends: %s, %d-%d", player.Name, spar.Id, ending, spar.Scores[1], spar.Scores[2])
	if ending == "Gone" then
		shown[player] = nil
		return
	end
	deps.Registry.fire("MatchChanged", player, nil)
	if ending == "Handover" then
		deps.Notify.send(player, "spar.handover", nil, "Success")
	elseif ending ~= "Taken" then
		if ending == "Left" then
			deps.Notify.send(player, "spar.left", nil, "Info")
		elseif ending == "Failed" then
			deps.Notify.send(player, "spar.unavailable", nil, "Error")
		end
		deps.Movement.clearStun(player)
		log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player)
	end
	pushOffer(player)
end

----------------------------------------------------------------
-- Rounds
----------------------------------------------------------------

-- The matchmaker may take the player at every break, never during a round.
local function hold(spar: Spar)
	deps.Matchmaking.setSparring(spar.Player, not SparRules.pairable(spar.Phase))
end

-- A round's setup: a fresh body (full health, full ink, spawn protection -- the only reset the combat has),
-- put on the pad with a fresh Forger facing it, frozen for the count.
local function prepareRound(spar: Spar)
	local player = spar.Player
	local generation = spar.Generation
	local loaded = log.try("LoadCharacterAsync " .. player.Name, function()
		player:LoadCharacterAsync()
	end)
	if spar.Ended or spar.Generation ~= generation then
		return
	end
	-- Only the body just loaded: the one before it may lie dead in the pit.
	local character = player.Character
	if not loaded or character == nil or not deps.Battleground.seatPit(player, character) then
		finish(spar, "Failed")
		return
	end
	spar.Character = character
	deps.Movement.applyFreeze(player, DEF.CountdownSeconds)
	local now = os.clock()
	spar.PhaseEndsAt = now + DEF.CountdownSeconds
	spar.RoundEndsAt = spar.PhaseEndsAt + ROUND_SECONDS
	spar.Preparing = false
end

local function beginRound(spar: Spar)
	spar.Phase = "Countdown"
	spar.Generation += 1
	spar.Preparing = true
	spar.Character = nil
	local now = os.clock()
	spar.PhaseEndsAt = now + DEF.CountdownSeconds
	spar.RoundEndsAt = spar.PhaseEndsAt + ROUND_SECONDS
	deps.Battleground.setPitLive(spar.Player, false)
	hold(spar)
	task.spawn(function()
		if not log.try("prepareRound " .. spar.Id, prepareRound, spar) then
			finish(spar, "Failed")
		end
	end)
end

local function endRound(spar: Spar, verdict: SparRules.Verdict, now: number)
	if verdict == "Player" then
		spar.Scores[1] += 1
	elseif verdict == "Forger" then
		spar.Scores[2] += 1
	end
	local said = ROUND_KEYS[verdict]
	deps.Notify.send(spar.Player, said.Key, nil, said.Kind)
	spar.Phase = "RoundOver"
	spar.PhaseEndsAt = now + MatchConfig.RoundOverSeconds
	deps.Battleground.setPitLive(spar.Player, false)
	hold(spar)
end

-- Today's paid spar, if one is left: RewardFactor of what the duel pays for `outcome`, charged to the day's
-- allowance kept in the profile. Returns the XP and Folios really credited.
local function pay(player: Player, outcome: SparRules.Outcome): (number, number)
	local data = deps.DataService.get(player)
	if data == nil then
		log.warn("spar pay skipped for %s: profile not loaded", player.Name)
		return 0, 0
	end
	local daily = data.Daily
	local day = today()
	local granted, used = DailyCap.take(daily.SparDay, daily.SparPaid, day, SPAR.PaidPerDay, 1)
	daily.SparDay = day
	daily.SparPaid = used
	deps.DataService.push(player, "Daily")
	if granted < 1 then
		deps.Notify.send(player, "spar.unpaid", nil, "Info")
		return 0, 0
	end
	local base = BASE[outcome]
	local xp = deps.Progression.addXp(player, SparRules.scaled(base.Xp, SPAR.RewardFactor), "Spar")
	local folios = deps.Currency.add(player, SparRules.scaled(base.Folios, SPAR.RewardFactor), "Spar")
	return xp, folios
end

local function enterResult(spar: Spar, now: number)
	local player = spar.Player
	spar.Phase = "Result"
	spar.PhaseEndsAt = now + DEF.ResultSeconds
	deps.Battleground.setPitLive(player, false)
	deps.Movement.applyFreeze(player, DEF.ResultSeconds)
	hold(spar)
	local outcome: SparRules.Outcome = SparRules.outcome(spar.Scores)
	local xp, folios = pay(player, outcome)
	local stats = spar.Stats
	local won = outcome == "Win"
	-- No rating and no rank: the result card hides its rating line on an empty rank key.
	local result: Types.MatchOutcome = {
		ModeId = DEF.Id :: any,
		Won = won,
		Draw = outcome == "Draw",
		Scores = table.clone(spar.Scores),
		Xp = xp,
		Folios = folios,
		RatingBefore = 0,
		RatingAfter = 0,
		RankKeyBefore = "",
		RankKeyAfter = "",
		FirstWinOfDay = false,
		Casts = stats.Casts,
		Hits = stats.Hits,
		DamageDealt = math.floor(stats.DamageDealt + 0.5),
		DamageTaken = math.floor(stats.DamageTaken + 0.5),
		Grade = Execution.grade(stats.Casts, stats.Hits, stats.DamageDealt, stats.DamageTaken, won),
	}
	deps.Registry.fire("MatchEnded", player, result)
end

local function advance(spar: Spar, now: number)
	local phase = spar.Phase
	if phase == "Countdown" then
		if now >= spar.PhaseEndsAt then
			spar.Phase = "Playing"
			spar.RoundEndsAt = now + ROUND_SECONDS
			spar.PhaseEndsAt = spar.RoundEndsAt
			deps.Battleground.setPitLive(spar.Player, true)
			hold(spar)
		end
	elseif phase == "Playing" then
		local verdict: SparRules.Verdict? =
			SparRules.roundVerdict(playerSide(spar), forgerSide(spar), now >= spar.RoundEndsAt)
		if verdict ~= nil then
			endRound(spar, verdict, now)
		end
	elseif phase == "RoundOver" then
		if now < spar.PhaseEndsAt then
			return
		end
		if SeriesOutcome.decided(spar.Scores, DEF.Teams, DEF.RoundsToWin) ~= nil or spar.Round >= MAX_ROUNDS then
			enterResult(spar, now)
		else
			spar.Round += 1
			beginRound(spar)
		end
	elseif now >= spar.PhaseEndsAt then
		finish(spar, "Done")
	end
end

local function step(spar: Spar, now: number)
	local player = spar.Player
	if player.Parent ~= Players then
		finish(spar, "Gone")
		return
	end
	if deps.Match.isInMatch(player) then
		finish(spar, "Handover")
		return
	end
	if deps.WorldBoss.isEngaged(player) then
		finish(spar, "Taken")
		return
	end
	if spar.Preparing then
		-- A setup thread that never came back must not strand the spar, nor hold its pit forever.
		if now > spar.PhaseEndsAt + DEF.CountdownSeconds then
			log.warn("spar %s round setup stalled for %s", spar.Id, player.Name)
			finish(spar, "Failed")
		end
		return
	end
	advance(spar, now)
	if spar.Ended then
		return
	end
	spar.Ticks += 1
	if spar.Ticks % TICKS_PER_SNAPSHOT == 0 then
		deps.Registry.fire("MatchChanged", player, snapshot(spar, now))
	end
end

----------------------------------------------------------------
-- The player's asks
----------------------------------------------------------------

-- Takes the spar the card offers, if the server still offers it and a pit is free.
function SparService.start(player: Player): boolean
	if spars[player] ~= nil then
		return false
	end
	if not offered(player) or not deps.Battleground.openPit(player) then
		deps.Notify.send(player, "spar.unavailable", nil, "Error")
		pushOffer(player)
		return false
	end
	nextId += 1
	local spar: Spar = {
		Id = ("spar-%d"):format(nextId),
		Player = player,
		Phase = "Countdown",
		Round = 1,
		Scores = { 0, 0 },
		PhaseEndsAt = 0,
		RoundEndsAt = 0,
		Preparing = true,
		Generation = 0,
		Character = nil,
		Stats = { Casts = 0, Hits = 0, DamageDealt = 0, DamageTaken = 0 },
		Ticks = 0,
		Ended = false,
	}
	spars[player] = spar
	deps.Notify.send(player, "spar.started", nil, "Info")
	log.info("%s starts spar %s (%d paid left today)", player.Name, spar.Id, paidLeft(player))
	beginRound(spar)
	pushOffer(player)
	return true
end

-- Walks out of the spar being fought: nothing paid, back to the hub, still in the queue.
function SparService.leave(player: Player)
	local spar = spars[player]
	if spar ~= nil then
		finish(spar, "Left")
	end
end

-- A match the queue formed takes the player at a break of their spar, which ends before it starts. The match can
-- still refuse to start -- no free arena, the other player gone -- and the queue then puts them back: once the
-- start is settled, a player no match took is sent home from the pit, where nothing else would ever fetch them.
local function onHandover(player: Player)
	local spar = spars[player]
	if spar == nil then
		return
	end
	finish(spar, "Handover")
	task.defer(function()
		if player.Parent ~= Players or spars[player] ~= nil or deps.Match.isInMatch(player) then
			return
		end
		log.info("%s's match was refused after the handover: sent home, still queued", player.Name)
		deps.Movement.clearStun(player)
		log.try("teleportToHub " .. player.Name, deps.Hub.teleportToHub, player)
	end)
end

----------------------------------------------------------------
-- What the player did, for the result's grade
----------------------------------------------------------------

-- A cast that could never hit anything -- a wall, a buff, a teleport -- is neither a hit nor a miss, as in a match.
local function counted(player: Player, glyphId: string): Spar?
	local spar = spars[player]
	if spar == nil or spar.Phase == "Result" or GlyphConfig.isUtility(glyphId) then
		return nil
	end
	return spar
end

local function onCast(player: Player, glyphId: string, _chain: number)
	local spar = counted(player, glyphId)
	if spar ~= nil then
		spar.Stats.Casts += 1
	end
end

local function onCastLanded(player: Player, glyphId: string, hits: number)
	local spar = counted(player, glyphId)
	if spar ~= nil and hits > 0 then
		spar.Stats.Hits += 1
	end
end

-- The player's hits on their pit's Forger, and the Forger's (which carry no source) on the player's body.
local function onDamaged(sourceUserId: number, targetModel: Model, applied: number, _kind: string)
	for player, spar in pairs(spars) do
		if spar.Phase ~= "Result" then
			local _, _, _, forger = deps.Battleground.pitForger(player)
			if sourceUserId == player.UserId and forger ~= nil and targetModel == forger then
				spar.Stats.DamageDealt += applied
			elseif sourceUserId == 0 and targetModel == spar.Character then
				spar.Stats.DamageTaken += applied
			end
		end
	end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	offerAccumulator += deltaTime
	if accumulator >= TICK_SECONDS then
		accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
		local now = os.clock()
		for _, spar in pairs(table.clone(spars)) do
			if not log.try("spar " .. spar.Id, step, spar, now) then
				-- A spar whose step throws is ended, not retried twenty times a second.
				local ending: Ending = "Failed"
				log.try("finish " .. spar.Id, finish, spar, ending)
			end
		end
	end
	if offerAccumulator >= SPAR.OfferTickSeconds then
		offerAccumulator = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pushOffer(player)
		end
	end
end

local function onPlayerRemoving(player: Player)
	local spar = spars[player]
	if spar ~= nil then
		finish(spar, "Gone")
	end
	shown[player] = nil
end

function SparService.Init(injected: Deps)
	deps = injected
end

function SparService.Start()
	deps.Registry.on("StartSpar", function(player: Player)
		SparService.start(player)
	end)
	deps.Registry.on("LeaveSpar", SparService.leave)
	deps.Matchmaking.Handover:Connect(onHandover)
	deps.Glyph.Cast:Connect(onCast)
	deps.Glyph.CastLanded:Connect(onCastLanded)
	deps.Combat.Damaged:Connect(onDamaged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info(
		"started (offered after %ds alone in %s, %d paid a day at %d%%)",
		SPAR.OfferAfterSeconds,
		SPAR.QueueModeId,
		SPAR.PaidPerDay,
		math.floor(SPAR.RewardFactor * 100 + 0.5)
	)
end

return SparService
