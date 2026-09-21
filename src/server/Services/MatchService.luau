--!strict
-- MatchService: the match lifecycle. Acquires an arena, teleports the roster to its team spawns,
-- restricts PvP to the participants of the same live match, runs Countdown → Playing → RoundOver → …
-- → Result, pays the rewards, applies the ranking and brings everybody back to the hub.
--
-- One Heartbeat accumulator drives every live match (no per-match thread, no per-player loop): it
-- refreshes the participants from their Humanoid, asks the mode for a round verdict, advances the
-- phases and pushes MatchChanged at SNAPSHOT_HZ. Everything a match owns (arena, kill-zone
-- connection) hangs from its Trove, so a normal end, an abandon and a disconnect all release it the
-- same way. The rules themselves live in GameModes: this service never decides who won.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Elo = require(Shared.Pure.Elo)
local Execution = require(Shared.Pure.Execution)
local GameConfig = require(Shared.Config.GameConfig)
local GameModes = require(script.Parent.Parent.GameModes)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local RankTiers = require(Shared.Pure.RankTiers)
local RankingConfig = require(Shared.Config.RankingConfig)
local Trove = require(Packages.Trove)
local Types = require(Shared.Types)

local log = Log.new("MatchService")

-- Built by ArenaService: one free instance of a MatchConfig.Arenas entry, with its team spawn pads.
-- Mirrors ArenaService.Arena exactly (acquire validates the pads and the kill zone before handing it
-- over, so both are guaranteed here).
export type Arena = {
	Instance: Model,
	Id: string,
	SlotIndex: number,
	Spawns: { { BasePart } }, -- team index -> spawn pads of that team
	KillZone: BasePart,
}
export type RatingChange = { Before: number, After: number, RankKeyBefore: string, RankKeyAfter: string }

type ProfileData = Types.ProfileData
type BeforeReleaseSignal = {
	Connect: (self: BeforeReleaseSignal, fn: (player: Player, data: ProfileData) -> ()) -> any,
}
type DataApi = {
	get: (player: Player) -> ProfileData?,
	push: (player: Player, section: string) -> (),
	BeforeRelease: BeforeReleaseSignal,
}
type NotifyKind = "Info" | "Success" | "Error"
type NotifyApi = {
	send: (player: Player, key: string, params: { [string]: any }?, kind: NotifyKind?, sfx: string?) -> (),
}
type Registry = { fire: (name: string, player: Player, ...any) -> () }
type CombatApi = {
	Damaged: DamagedSignal,
	setPolicy: (fn: (source: Player?, targetModel: Model) -> boolean) -> (),
	resyncPosition: (player: Player, position: Vector3?) -> (),
}
type MovementApi = {
	applyStun: (player: Player, seconds: number) -> (),
	applyFreeze: (player: Player, seconds: number) -> (),
	isStunned: (player: Player) -> boolean,
}
type ProgressionApi = { addXp: (player: Player, amount: number, reason: string) -> () }
type CurrencyApi = { add: (player: Player, amount: number, reason: string) -> () }
type HubApi = { teleportToHub: (player: Player) -> () }
type ArenaApi = { acquire: (arenaId: string) -> Arena?, release: (arena: Arena) -> () }
type RankingApi = {
	getRating: (player: Player, modeId: string) -> number,
	lastKnownRating: (modeId: string, userId: number) -> number,
	applyResult: (result: Types.MatchResult) -> { [number]: RatingChange },
	applyAbandon: (player: Player, matchId: string, modeId: string, opponentRating: number) -> RatingChange?,
}
type QuestApi = { report: (player: Player, event: string, amount: number) -> () }
type CastSignal = { Connect: (self: CastSignal, fn: (player: Player, glyphId: string, hits: number) -> ()) -> any }
type DamagedSignal = {
	Connect: (
		self: DamagedSignal,
		fn: (sourceUserId: number, targetModel: Model, applied: number, kind: string) -> ()
	) -> any,
}
type GlyphApi = { Cast: CastSignal }
type DailyApi = { markFirstWin: (player: Player) -> boolean }
type Deps = {
	Registry: Registry,
	DataService: DataApi,
	Notify: NotifyApi,
	Combat: CombatApi,
	Movement: MovementApi,
	Progression: ProgressionApi,
	Currency: CurrencyApi,
	Hub: HubApi,
	Arena: ArenaApi,
	Ranking: RankingApi,
	Quest: QuestApi,
	Daily: DailyApi,
	Glyph: GlyphApi,
}
type TroveType = typeof(Trove.new())

-- What one participant did over the match, counted from the signals of the services that saw it.
type ParticipantStats = { Casts: number, Hits: number, DamageDealt: number, DamageTaken: number }

type Active = {
	Match: GameModes.Match,
	Mode: GameModes.GameMode,
	Def: GameModes.ModeDef,
	Arena: Arena,
	Trove: TroveType,
	PhaseEndsAt: number, -- os.clock; equals Match.RoundEndsAt while Playing
	Preparing: boolean, -- a round setup thread is yielding on LoadCharacterAsync
	Finished: boolean,
	Generation: number, -- bumped per round: a stale setup thread drops out
	Ticks: number,
	Stats: { [number]: ParticipantStats }, -- user id -> the execution, graded at the result
}

local TICK_SECONDS = 1 / GameConfig.Server.TickRate
-- MatchChanged pushes per second; the client tweens between snapshots (see notes: a MatchConfig entry
-- would be the proper home for this rate).
local SNAPSHOT_HZ = MatchConfig.SnapshotHz
local TICKS_PER_SNAPSHOT = math.max(1, math.floor(GameConfig.Server.TickRate / SNAPSHOT_HZ))
-- Characters are pivoted this far above their spawn pad so they never start clipped into it.
local SPAWN_CLEARANCE_STUDS = 4
local XP = ProgressionConfig.XP
local RYO = ProgressionConfig.Ryo
-- Per-mode reward multipliers; MatchConfig.Rewards is keyed by mode id.
local REWARD_SCALES = (MatchConfig.Rewards :: any) :: { [string]: { Xp: number, Ryo: number } }
local DEFAULT_SCALE = { Xp = 1, Ryo = 1 }

local MatchService = {}

local registry: Registry
local dataService: DataApi
local notify: NotifyApi
local combat: CombatApi
local movement: MovementApi
local progression: ProgressionApi
local currency: CurrencyApi
local hub: HubApi
local arenas: ArenaApi
local ranking: RankingApi
local quest: QuestApi
local daily: DailyApi
local glyph: GlyphApi

local actives: { Active } = {}
local activeByUserId: { [number]: Active } = {}
local accumulator = 0
local nextMatchIndex = 0

----------------------------------------------------------------
-- Participants and geometry
----------------------------------------------------------------

local function isLive(participant: GameModes.Participant): boolean
	return participant.Present and participant.Player.Parent == Players
end

local function arenaCenter(arena: Arena): Vector3
	local total = Vector3.zero
	local count = 0
	for _, spawns in ipairs(arena.Spawns) do
		for _, spawn in ipairs(spawns) do
			total += spawn.Position
			count += 1
		end
	end
	if count == 0 then
		return Vector3.zero
	end
	return total / count
end

local function spawnFor(arena: Arena, team: number, slot: number): BasePart?
	local teamSpawns = arena.Spawns[team]
	if teamSpawns == nil or #teamSpawns == 0 then
		return nil
	end
	return teamSpawns[((slot - 1) % #teamSpawns) + 1]
end

-- Drops the character on its pad, facing the middle of the arena. `player` is the owner, so the position
-- the server trusts follows the teleport: without it the player's next hitbox would be built at the hub
-- and hit nothing (CombatService.trustedCFrame).
local function placeCharacter(player: Player, character: Model, spawn: BasePart, center: Vector3)
	local position = spawn.Position + Vector3.new(0, SPAWN_CLEARANCE_STUDS, 0)
	if position.X == center.X and position.Z == center.Z then
		character:PivotTo(CFrame.new(position))
	else
		character:PivotTo(CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
	end
	-- The destination, passed explicitly: re-reading the character would anchor trust on whatever the
	-- client replicates next rather than on the pad the server just put them on.
	combat.resyncPosition(player, position)
end

-- Health and death come from the live Humanoid: no per-player connection, and a player who respawns
-- in the hub after losing a round never comes back to life inside it.
local function refresh(active: Active)
	for _, participant in ipairs(active.Match.Participants) do
		if not participant.Alive then
			participant.Health = 0
			continue
		end
		local character = if isLive(participant) then participant.Player.Character else nil
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid == nil or humanoid.Health <= 0 then
			participant.Alive = false
			participant.Health = 0
			continue
		end
		participant.Health = humanoid.Health
		participant.MaxHealth = humanoid.MaxHealth
	end
end

----------------------------------------------------------------
-- Replication
----------------------------------------------------------------

local function pushSnapshots(active: Active, now: number)
	-- Not while a round is being prepared: PhaseEndsAt is reset when the preparation finishes, so a
	-- countdown pushed before that counts down, restarts, and counts down again -- which the clients
	-- now tick aloud.
	if active.Preparing then
		return
	end
	local snapshot = GameModes.snapshot(active.Match, math.max(0, math.ceil(active.PhaseEndsAt - now)))
	for _, participant in ipairs(active.Match.Participants) do
		if isLive(participant) then
			-- One table, one field rewritten per receiver: FireClient serializes it on the spot.
			snapshot.LocalTeam = participant.Team
			registry.fire("MatchChanged", participant.Player, snapshot)
		end
	end
end

local function notifyRound(active: Active, winnerTeam: number?)
	for _, participant in ipairs(active.Match.Participants) do
		if isLive(participant) then
			if winnerTeam == nil then
				notify.send(participant.Player, "match.draw", nil, "Info")
			elseif winnerTeam == participant.Team then
				notify.send(participant.Player, "match.roundWon", nil, "Success")
			else
				notify.send(participant.Player, "match.roundLost", nil, "Error")
			end
		end
	end
end

----------------------------------------------------------------
-- Rewards
----------------------------------------------------------------

local function ratingFallback(player: Player, modeId: string): RatingChange
	local ok, rating = pcall(ranking.getRating, player, modeId)
	local value = if ok and type(rating) == "number" then rating else RankingConfig.InitialRating
	if not ok then
		log.warn("getRating failed for %s (%s): %s", player.Name, modeId, tostring(rating))
	end
	local key = RankTiers.tierFor(value, RankingConfig.Tiers).NameKey
	return { Before = value, After = value, RankKeyBefore = key, RankKeyAfter = key }
end

local function bumpMatchesPlayed(player: Player)
	local data = dataService.get(player)
	if data == nil then
		return
	end
	data.Stats.MatchesPlayed += 1
	dataService.push(player, "Stats")
end

-- Daily first-win bonus. DailyRewardService owns the Daily section (streak, first win, Premium
-- bonus); it marks the day, pays ProgressionConfig.*.FirstWinOfDay and notifies the player.
local function grantFirstWin(player: Player): boolean
	return daily.markFirstWin(player)
end

local function ratingChanges(active: Active, result: Types.MatchResult): { [number]: RatingChange }
	if not active.Def.Ranked then
		return {}
	end
	local ok, applied = pcall(ranking.applyResult, result)
	if not ok or type(applied) ~= "table" then
		log.warn("Ranking.applyResult failed for match %s: %s", active.Match.Id, tostring(applied))
		return {}
	end
	return (applied :: any) :: { [number]: RatingChange }
end

-- XP, Ryo, stats, ranking and the single MatchEnded summary, for everybody still in the server.
local function award(active: Active, result: Types.MatchResult)
	local match = active.Match
	local scale = REWARD_SCALES[active.Def.Id] or DEFAULT_SCALE
	local changes = ratingChanges(active, result)
	for _, participant in ipairs(match.Participants) do
		if not isLive(participant) then
			continue
		end
		local player = participant.Player
		local draw = result.WinnerTeam == nil
		local won = result.WinnerTeam == participant.Team
		local baseXp = if draw then XP.MatchDraw elseif won then XP.MatchWin else XP.MatchLoss
		local baseRyo = if draw then RYO.MatchDraw elseif won then RYO.MatchWin else RYO.MatchLoss
		local reason = if draw then "MatchDraw" elseif won then "MatchWin" else "MatchLoss"
		local xp = math.floor(baseXp * scale.Xp + 0.5)
		local ryo = math.floor(baseRyo * scale.Ryo + 0.5)
		-- DailyRewardService pays the first-win bonus itself, so it is reported but never added here.
		local firstWin = won and grantFirstWin(player)
		progression.addXp(player, xp, reason)
		currency.add(player, ryo, reason)
		bumpMatchesPlayed(player)
		quest.report(player, "MatchPlayed", 1)
		if won then
			quest.report(player, "MatchWin", 1)
		end
		local change = changes[participant.UserId] or ratingFallback(player, active.Def.Id)
		local stats = active.Stats[participant.UserId] or { Casts = 0, Hits = 0, DamageDealt = 0, DamageTaken = 0 }
		local outcome: Types.MatchOutcome = {
			ModeId = match.ModeId,
			Won = won,
			Draw = draw,
			Scores = table.clone(match.Scores),
			Xp = xp,
			Ryo = ryo,
			RatingBefore = change.Before,
			RatingAfter = change.After,
			RankKeyBefore = change.RankKeyBefore,
			RankKeyAfter = change.RankKeyAfter,
			FirstWinOfDay = firstWin,
			Casts = stats.Casts,
			Hits = stats.Hits,
			DamageDealt = math.floor(stats.DamageDealt + 0.5),
			DamageTaken = math.floor(stats.DamageTaken + 0.5),
			Grade = Execution.grade(stats.Casts, stats.Hits, stats.DamageDealt, stats.DamageTaken, won),
		}
		registry.fire("MatchEnded", player, outcome)
	end
end

----------------------------------------------------------------
-- Phases
----------------------------------------------------------------

-- Last step of every path out of a match: clear the participants, send them home, drop the Trove
-- (which releases the arena and disconnects the kill zone) and forget the match.
local function finish(active: Active)
	if active.Finished then
		return
	end
	active.Finished = true
	for _, participant in ipairs(active.Match.Participants) do
		-- Only while the slot still holds THIS match, exactly as ArenaService.release guards a slot. A
		-- player who disconnected mid-match stays in Participants with Present = false, so they can
		-- reconnect and be booked into a new match before this one finishes winding down. Clearing
		-- unconditionally would erase that live match: allowDamage would then refuse every hit from and
		-- against them, and isInMatch would let them queue for a third one.
		if activeByUserId[participant.UserId] == active then
			activeByUserId[participant.UserId] = nil
		end
		if isLive(participant) then
			registry.fire("MatchChanged", participant.Player, nil)
			notify.send(participant.Player, "match.returning", nil, "Info")
			log.try("teleportToHub " .. participant.Player.Name, hub.teleportToHub, participant.Player)
		end
	end
	active.Trove:Destroy()
	local index = table.find(actives, active)
	if index ~= nil then
		table.remove(actives, index)
	end
	log.info("match %s ended (arena %s slot %d)", active.Match.Id, active.Arena.Id, active.Arena.SlotIndex)
end

local function enterResult(active: Active, now: number)
	local match = active.Match
	match.Phase = "Result"
	match.EndedAt = now
	active.PhaseEndsAt = now + active.Def.ResultSeconds
	active.Generation += 1
	-- Nobody keeps fighting over the result screen.
	for _, participant in ipairs(match.Participants) do
		if isLive(participant) then
			movement.applyFreeze(participant.Player, active.Def.ResultSeconds)
		end
	end
	local ok, result = pcall(active.Mode.End, match)
	if not ok then
		log.warn("mode %s End failed for match %s: %s", active.Def.Id, match.Id, tostring(result))
		return
	end
	local outcome = (result :: any) :: Types.MatchResult
	log.try("award " .. match.Id, award, active, outcome)
end

-- Round setup: yields on LoadCharacterAsync, so it runs in its own thread and bails out when the match
-- moved on meanwhile. A fresh character is the only reset CombatService exposes — it restores full
-- health, full ink and spawn protection on CharacterAdded — so every round starts on one.
local function prepareRound(active: Active)
	local generation = active.Generation
	local center = arenaCenter(active.Arena)
	for _, participant in ipairs(active.Match.Participants) do
		if active.Finished or active.Generation ~= generation then
			return
		end
		if isLive(participant) then
			local player = participant.Player
			local loaded = log.try("LoadCharacterAsync " .. player.Name, function()
				player:LoadCharacterAsync()
			end)
			local character = player.Character
			if loaded and character ~= nil and not active.Finished and active.Generation == generation then
				local pad = spawnFor(active.Arena, participant.Team, participant.Slot)
				if pad ~= nil then
					placeCharacter(player, character, pad, center)
				else
					log.warn("arena %s has no spawn for team %d", active.Arena.Id, participant.Team)
				end
				participant.Alive = true
				movement.applyFreeze(player, active.Def.CountdownSeconds)
			end
		end
	end
	if active.Finished or active.Generation ~= generation then
		return
	end
	local now = os.clock()
	active.PhaseEndsAt = now + active.Def.CountdownSeconds
	active.Match.RoundEndsAt = active.PhaseEndsAt + active.Match.RoundSeconds
	active.Preparing = false
end

local function beginRound(active: Active)
	local match = active.Match
	match.Phase = "Countdown"
	active.Generation += 1
	active.Preparing = true
	local now = os.clock()
	active.PhaseEndsAt = now + active.Def.CountdownSeconds
	match.RoundEndsAt = active.PhaseEndsAt + match.RoundSeconds
	task.spawn(function()
		if not log.try("prepareRound " .. match.Id, prepareRound, active) then
			-- A setup that blew up must never leave the match stuck in Countdown.
			active.Preparing = false
		end
	end)
end

local function applyVerdict(active: Active, verdict: GameModes.Verdict, now: number)
	local match = active.Match
	if verdict.Reason == "Forfeit" then
		if GameModes.presentCount(active.Match) == 0 then
			log.warn("match %s abandoned: no participant left", match.Id)
			finish(active)
			return
		end
		local winner = verdict.WinnerTeam
		if winner ~= nil then
			-- Two cases, and the old code collapsed them into one. Raising the survivor to RoundsToWin
			-- unconditionally turned a 2-0 series abandoned during RoundOver into 2-2, which
			-- GameModes.scoreWinner reads as a tie: the player who had already won every round got a draw,
			-- and so did the one who walked out.
			--
			-- A series already decided on the field keeps its real winner, whoever then left. An
			-- undecided series goes to the team still standing, and its score is raised just past the
			-- best other score so the number the result screen prints agrees with the verdict it prints.
			if GameModes.decidedWinner(match) == nil then
				match.ForfeitWinner = winner
				match.Scores[winner] = math.max(match.Scores[winner], GameModes.bestOtherScore(match, winner) + 1)
			end
			for _, participant in ipairs(match.Participants) do
				if isLive(participant) then
					notify.send(participant.Player, "match.opponentLeft", nil, "Info")
				end
			end
		end
		enterResult(active, now)
		return
	end
	if verdict.WinnerTeam ~= nil then
		match.Scores[verdict.WinnerTeam] += 1
	end
	notifyRound(active, verdict.WinnerTeam)
	match.Phase = "RoundOver"
	active.Generation += 1
	active.PhaseEndsAt = now + MatchConfig.RoundOverSeconds
end

local function advance(active: Active, now: number)
	local match = active.Match
	if match.Phase ~= "Result" then
		local ok, verdict = pcall(active.Mode.RoundVerdict, match, now)
		if not ok then
			log.warn("mode %s RoundVerdict failed for match %s: %s", active.Def.Id, match.Id, tostring(verdict))
		elseif verdict ~= nil then
			applyVerdict(active, (verdict :: any) :: GameModes.Verdict, now)
			return
		end
	end
	if match.Phase == "Countdown" then
		-- applyFreeze is uncapped and set once per phase, so nothing has to be topped up here; this only
		-- catches a participant who respawned mid-countdown.
		local remaining = active.PhaseEndsAt - now
		if remaining > 0 then
			for _, participant in ipairs(match.Participants) do
				if isLive(participant) and not movement.isStunned(participant.Player) then
					movement.applyFreeze(participant.Player, remaining)
				end
			end
		end
		if now >= active.PhaseEndsAt then
			match.Phase = "Playing"
			match.RoundEndsAt = now + match.RoundSeconds
			active.PhaseEndsAt = match.RoundEndsAt
		end
		return
	end
	if match.Phase == "Playing" then
		active.PhaseEndsAt = match.RoundEndsAt
		return
	end
	if now < active.PhaseEndsAt then
		return
	end
	if match.Phase == "RoundOver" then
		if GameModes.isDecided(match) or match.Round >= match.MaxRounds then
			enterResult(active, now)
		else
			match.Round += 1
			beginRound(active)
		end
		return
	end
	finish(active)
end

local function onHeartbeat(deltaTime: number)
	accumulator += deltaTime
	if accumulator < TICK_SECONDS then
		return
	end
	accumulator = math.min(accumulator - TICK_SECONDS, TICK_SECONDS)
	local now = os.clock()
	for index = #actives, 1, -1 do
		local active = actives[index]
		if active.Preparing and now > active.PhaseEndsAt + active.Def.CountdownSeconds then
			-- A setup thread that never came back must not strand the match (and its arena) forever.
			log.warn("match %s round setup stalled: the round resumes without it", active.Match.Id)
			active.Preparing = false
		end
		if not active.Finished and not active.Preparing then
			refresh(active)
			advance(active, now)
		end
		if not active.Finished then
			active.Ticks += 1
			if active.Ticks % TICKS_PER_SNAPSHOT == 0 then
				pushSnapshots(active, now)
			end
		end
	end
end

----------------------------------------------------------------
-- Arena hazards, PvP policy, disconnects
----------------------------------------------------------------

-- The arena kill zone under the floor. Health = 0 makes it an environment death, so CombatService
-- still credits the last attacker when a knockback is what sent the victim over the edge.
local function onKillZoneTouched(active: Active, part: BasePart)
	if active.Finished or active.Match.Phase ~= "Playing" then
		return
	end
	local character = part:FindFirstAncestorOfClass("Model")
	if character == nil then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil then
		return
	end
	local participant = GameModes.participantOf(active.Match, player.UserId)
	if participant == nil or not participant.Alive then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

-- PvP is a match privilege: two participants of the same match hurt each other while it is being
-- played, and nothing else. Server-authored damage (no source: environment, NPC, boss) is not a PvP
-- decision and stays allowed. This replaces CombatService's hub policy, so hub players can no longer
-- damage each other at all, while training dummies stay open to everyone outside a match.
local function allowDamage(source: Player?, targetModel: Model): boolean
	if source == nil then
		return true
	end
	local sourceActive = activeByUserId[source.UserId]
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	if targetPlayer == nil then
		return sourceActive == nil
	end
	if sourceActive == nil or activeByUserId[targetPlayer.UserId] ~= sourceActive then
		return false
	end
	return not sourceActive.Finished and sourceActive.Match.Phase == "Playing"
end

-- Average rating of the teams `player` is NOT on, for the forfeit debit below. Read from RankingService
-- so an opponent who also left still counts at the rating this server last saw for them.
-- Team index `userId` plays for in `active`, nil when they are not on its roster.
local function teamOfParticipant(active: Active, userId: number): number?
	for _, participant in ipairs(active.Match.Participants) do
		if participant.UserId == userId then
			return participant.Team
		end
	end
	return nil
end

local function opposingRating(active: Active, player: Player): number
	local ownTeam = teamOfParticipant(active, player.UserId)
	if ownTeam == nil then
		return RankingConfig.InitialRating
	end
	local ratings: { number } = {}
	for _, participant in ipairs(active.Match.Participants) do
		if participant.Team ~= ownTeam then
			-- lastKnownRating, not getRating: an opponent who also disconnected has no live Player, and
			-- their real rating must still count or the debit would be scored against a beginner.
			table.insert(ratings, ranking.lastKnownRating(active.Def.Id, participant.UserId))
		end
	end
	if #ratings == 0 then
		return RankingConfig.InitialRating
	end
	return Elo.teamRating(ratings)
end

-- Walking out of a live ranked match costs exactly what losing it costs. Settled here, on
-- DataService.BeforeRelease, because this is the last instant the leaver's profile is still loaded: the
-- match resolves seconds later in their absence, and nothing could be written for them by then. Without
-- it, quitting was strictly better than losing and a rating could only ever go up.
-- The live ranked match `userId` is walking out of. `activeByUserId` is the fast path, but Roblox does
-- not contract the order in which two connections to the same signal fire: if MatchService's own
-- PlayerRemoving handler happened to run before DataService's, the slot would already be clear and the
-- forfeit would be silently skipped. So the list is scanned as a fallback, which no ordering can defeat.
-- A double debit is impossible either way: RankingService settles a user id once per match.
local function liveRankedMatchOf(userId: number): Active?
	local direct = activeByUserId[userId]
	if direct ~= nil then
		return if direct.Finished or not direct.Def.Ranked then nil else direct
	end
	local fallback: Active? = nil
	for _, active in ipairs(actives) do
		if not active.Finished and active.Def.Ranked then
			for _, participant in ipairs(active.Match.Participants) do
				if participant.UserId == userId then
					if participant.Present then
						return active
					end
					fallback = fallback or active
					break
				end
			end
		end
	end
	return fallback
end

local function onBeforeRelease(player: Player)
	local active = liveRankedMatchOf(player.UserId)
	if active == nil then
		return
	end
	if active.Match.Phase == "Result" then
		-- The result is already being applied; applyResult owns this player's rating move.
		return
	end
	-- A series this player has ALREADY won on rounds stays theirs whoever then walks out (D-34), and
	-- applyResult is about to credit them for it. Debiting a loss here would both contradict that and, by
	-- marking them settled, make applyResult skip the win it is about to declare. The window is real: a
	-- won series sits in RoundOver for MatchConfig.RoundOverSeconds before the result is entered, which is
	-- exactly when a player who just saw "round won" closes the client.
	local decided = GameModes.decidedWinner(active.Match)
	if decided ~= nil and decided == teamOfParticipant(active, player.UserId) then
		return
	end
	log.try(
		"applyAbandon " .. active.Def.Id,
		ranking.applyAbandon,
		player,
		active.Match.Id,
		active.Def.Id,
		opposingRating(active, player)
	)
end

local function onPlayerRemoving(player: Player)
	local active = activeByUserId[player.UserId]
	if active == nil then
		return
	end
	activeByUserId[player.UserId] = nil
	if not log.try("OnPlayerLeft " .. active.Def.Id, active.Mode.OnPlayerLeft, active.Match, player) then
		-- A hook that blew up must not leave a phantom teammate holding a team against a forfeit.
		GameModes.markLeft(active.Match, player)
	end
	log.info("%s left match %s", player.Name, active.Match.Id)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Starts `modeId` for the given teams (team index -> user ids). Returns the match id, or nil when the
-- roster, the mode or the arena pool refuses it — MatchmakingService then puts the players back in
-- the queue.
function MatchService.start(modeId: string, teams: { { number } }): string?
	local def = MatchConfig.Modes[modeId]
	if def == nil then
		log.warn("start rejected: unknown mode %s", tostring(modeId))
		return nil
	end
	local mode = GameModes.get(modeId)
	if mode == nil then
		log.warn("start rejected: no game mode implements %s", modeId)
		return nil
	end
	local participants: { GameModes.Participant } = {}
	local rosterTeams: { { number } } = {}
	local userIds: { number } = {}
	for team, members in ipairs(teams) do
		rosterTeams[team] = {}
		for slot, userId in ipairs(members) do
			local player = Players:GetPlayerByUserId(userId)
			if player == nil or activeByUserId[userId] ~= nil then
				log.warn("start rejected: user %d is unavailable for %s", userId, modeId)
				return nil
			end
			table.insert(participants, {
				UserId = userId,
				Player = player,
				Name = player.DisplayName,
				Team = team,
				Slot = slot,
				Present = true,
				Alive = false,
				Health = 0,
				MaxHealth = 0,
			})
			table.insert(rosterTeams[team], userId)
			table.insert(userIds, userId)
		end
	end
	if not mode.CanStart(userIds) then
		log.warn("start rejected: mode %s refused a roster of %d", modeId, #userIds)
		return nil
	end
	local arena = arenas.acquire(def.ArenaId)
	if arena == nil then
		log.warn("start rejected: no free %s arena for %s", def.ArenaId, modeId)
		return nil
	end

	nextMatchIndex += 1
	local scores: { number } = {}
	for team = 1, def.Teams do
		scores[team] = 0
	end
	local match: GameModes.Match = {
		Id = string.format("%s-%d", modeId, nextMatchIndex),
		ModeId = (def.Id :: any) :: Types.MatchModeId,
		Def = def,
		Phase = "Countdown",
		Round = 1,
		MaxRounds = 1,
		RoundSeconds = def.DurationSeconds,
		Scores = scores,
		Teams = rosterTeams,
		Participants = participants,
		StartedAt = os.clock(),
		RoundEndsAt = 0,
		EndedAt = 0,
	}
	local trove = Trove.new()
	local active: Active = {
		Match = match,
		Mode = mode,
		Def = def,
		Arena = arena,
		Trove = trove,
		PhaseEndsAt = 0,
		Preparing = true,
		Finished = false,
		Generation = 0,
		Ticks = 0,
		Stats = {},
	}
	trove:Add(function()
		log.try("Arena.release " .. arena.Id, arenas.release, arena)
	end)
	trove:Connect(arena.KillZone.Touched, function(part: BasePart)
		onKillZoneTouched(active, part)
	end)
	for _, participant in ipairs(participants) do
		activeByUserId[participant.UserId] = active
	end
	table.insert(actives, active)
	log.try("mode " .. def.Id .. " Start", mode.Start, match)
	beginRound(active)
	log.info("match %s started on arena %s slot %d (%d players)", match.Id, arena.Id, arena.SlotIndex, #userIds)
	return match.Id
end

function MatchService.isInMatch(player: Player): boolean
	return activeByUserId[player.UserId] ~= nil
end

-- True while the player's match is on its result screen: over, but not yet let go. MatchmakingService
-- keeps a queue asked for now and honours it the moment isInMatch turns false.
function MatchService.isFinishing(player: Player): boolean
	local active = activeByUserId[player.UserId]
	return active ~= nil and active.Match.Phase == "Result"
end

-- The execution counters, fed by GlyphService.Cast and CombatService.Damaged while a match is live.
local function statsOf(active: Active, userId: number): ParticipantStats
	local stats = active.Stats[userId]
	if stats == nil then
		stats = { Casts = 0, Hits = 0, DamageDealt = 0, DamageTaken = 0 }
		active.Stats[userId] = stats
	end
	return stats
end

local function onCast(player: Player, _glyphId: string, hits: number)
	local active = activeByUserId[player.UserId]
	if active == nil or active.Match.Phase == "Result" then
		return
	end
	local stats = statsOf(active, player.UserId)
	stats.Casts += 1
	if hits > 0 then
		stats.Hits += 1
	end
end

local function onDamaged(sourceUserId: number, targetModel: Model, applied: number, _kind: string)
	local active = activeByUserId[sourceUserId]
	if active == nil or active.Match.Phase == "Result" then
		return
	end
	local target = Players:GetPlayerFromCharacter(targetModel)
	if target == nil or activeByUserId[target.UserId] ~= active then
		return
	end
	statsOf(active, sourceUserId).DamageDealt += applied
	statsOf(active, target.UserId).DamageTaken += applied
end

-- Live match of `player`, or nil. Read-only: MatchService owns every field.
function MatchService.getMatch(player: Player): GameModes.Match?
	local active = activeByUserId[player.UserId]
	if active == nil then
		return nil
	end
	return active.Match
end

function MatchService.Init(deps: Deps)
	registry = deps.Registry
	dataService = deps.DataService
	notify = deps.Notify
	combat = deps.Combat
	movement = deps.Movement
	progression = deps.Progression
	currency = deps.Currency
	hub = deps.Hub
	arenas = deps.Arena
	ranking = deps.Ranking
	quest = deps.Quest
	daily = deps.Daily
	glyph = deps.Glyph
end

function MatchService.Start()
	combat.setPolicy(allowDamage)
	-- Before PlayerRemoving: DataService fires BeforeRelease from inside its own PlayerRemoving handler,
	-- which runs first, so the forfeit is debited while activeByUserId still holds the match.
	dataService.BeforeRelease:Connect(onBeforeRelease)
	glyph.Cast:Connect(onCast)
	combat.Damaged:Connect(onDamaged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(onHeartbeat)
	log.info("started (tick %d Hz, snapshots %d Hz)", GameConfig.Server.TickRate, SNAPSHOT_HZ)
end

return MatchService
