--!strict
-- MatchController: the client mirror of the server's queue and match state. It owns no UI: it keeps the
-- last QueueChanged / MatchChanged / MatchEnded payloads, re-fires them as Signals (HudController for the
-- in-match band, UI/screens for Play and Result) and forwards the only two queue intents the client is
-- allowed to send. Every value exposed here is server-authored; payloads are sanitized before use so a
-- truncated push can never error a screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Execution = require(Shared.Pure.Execution)
local Log = require(Shared.Util.Log)
local MatchConfig = require(Shared.Config.MatchConfig)
local Signal = require(Packages.Signal)
local Types = require(Shared.Types)

local log = Log.new("MatchController")

export type QueueSnapshot = Types.QueueSnapshot
export type MatchSnapshot = Types.MatchSnapshot
export type MatchOutcome = Types.MatchOutcome

type Deps = { RemoteClient: any, SoundController: any }

local PHASES: { [string]: boolean } = { Countdown = true, Playing = true, RoundOver = true, Result = true }
local COUNTDOWN_PHASE = "Countdown"
local PLAYING_PHASE = "Playing"

local MatchController = {}

MatchController.QueueChanged = Signal.new() -- (snapshot: QueueSnapshot)
MatchController.MatchChanged = Signal.new() -- (snapshot: MatchSnapshot?)
MatchController.MatchEnded = Signal.new() -- (outcome: MatchOutcome)

local remoteClient: any
local soundController: any

-- A fresh table per call: the state below is handed to listeners, never shared with a constant.
local function idleQueue(): QueueSnapshot
	return { Queued = false, ModeId = nil, WaitedSeconds = 0, QueuedCount = 0, NeededCount = 0 }
end

local queue: QueueSnapshot = idleQueue()
local match: MatchSnapshot? = nil
local lastOutcome: MatchOutcome? = nil
local malformedWarned: { [string]: boolean } = {}

local function warnOnce(remoteName: string, payload: any)
	if malformedWarned[remoteName] then
		return
	end
	malformedWarned[remoteName] = true
	log.warn("malformed %s dropped (%s)", remoteName, typeof(payload))
end

local function finite(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function count(value: any, fallback: number): number
	return math.max(0, math.floor(finite(value, fallback)))
end

local function stringOr(value: any, fallback: string): string
	return if type(value) == "string" then value else fallback
end

local function isKnownMode(value: any): boolean
	return type(value) == "string" and MatchConfig.Modes[value] ~= nil
end

-- Only called behind isKnownMode: the payload field is a mode id of MatchConfig.Modes.
local function asModeId(value: any): Types.MatchModeId
	return (value :: any) :: Types.MatchModeId
end

local function readScores(payload: any): { number }
	local scores: { number } = {}
	if type(payload) ~= "table" then
		return scores
	end
	for index, value in ipairs(payload) do
		scores[index] = count(value, 0)
	end
	return scores
end

local function readQueue(payload: any): QueueSnapshot?
	if type(payload) ~= "table" then
		return nil
	end
	local queued = payload.Queued == true and isKnownMode(payload.ModeId)
	local modeId: Types.MatchModeId? = if queued then asModeId(payload.ModeId) else nil
	return {
		Queued = queued,
		ModeId = modeId,
		WaitedSeconds = math.max(0, finite(payload.WaitedSeconds, 0)),
		QueuedCount = count(payload.QueuedCount, 0),
		NeededCount = count(payload.NeededCount, 0),
	}
end

local function readTeams(payload: any): { { Types.MatchPlayerSnapshot } }
	local teams: { { Types.MatchPlayerSnapshot } } = {}
	if type(payload) ~= "table" then
		return teams
	end
	for teamIndex, rawTeam in ipairs(payload) do
		local members: { Types.MatchPlayerSnapshot } = {}
		if type(rawTeam) == "table" then
			for _, raw in ipairs(rawTeam) do
				if type(raw) == "table" and type(raw.Name) == "string" then
					table.insert(members, {
						UserId = count(raw.UserId, 0),
						Name = raw.Name,
						Team = count(raw.Team, teamIndex),
						Alive = raw.Alive ~= false,
						Health = math.max(0, finite(raw.Health, 0)),
						MaxHealth = math.max(0, finite(raw.MaxHealth, 0)),
					})
				end
			end
		end
		teams[teamIndex] = members
	end
	return teams
end

local function readMatch(payload: any): MatchSnapshot?
	if type(payload) ~= "table" then
		return nil
	end
	if not isKnownMode(payload.ModeId) or type(payload.MatchId) ~= "string" or not PHASES[payload.Phase] then
		return nil
	end
	return {
		MatchId = payload.MatchId,
		ModeId = asModeId(payload.ModeId),
		Phase = (payload.Phase :: any) :: Types.MatchPhase,
		SecondsLeft = math.max(0, finite(payload.SecondsLeft, 0)),
		Round = math.max(1, count(payload.Round, 1)),
		RoundsToWin = math.max(1, count(payload.RoundsToWin, 1)),
		Scores = readScores(payload.Scores),
		Teams = readTeams(payload.Teams),
		LocalTeam = count(payload.LocalTeam, 0),
	}
end

local function readOutcome(payload: any): MatchOutcome?
	if type(payload) ~= "table" then
		return nil
	end
	if not isKnownMode(payload.ModeId) then
		return nil
	end
	return {
		ModeId = asModeId(payload.ModeId),
		Won = payload.Won == true,
		Draw = payload.Draw == true,
		Scores = readScores(payload.Scores),
		Xp = count(payload.Xp, 0),
		Folios = count(payload.Folios, 0),
		RatingBefore = count(payload.RatingBefore, 0),
		RatingAfter = count(payload.RatingAfter, 0),
		-- Empty when the mode is unranked: the result screen then hides its rating line.
		RankKeyBefore = stringOr(payload.RankKeyBefore, ""),
		RankKeyAfter = stringOr(payload.RankKeyAfter, ""),
		FirstWinOfDay = payload.FirstWinOfDay == true,
		-- The execution the server counted, and the grade it cut from it. A grade the server did not send
		-- is the lowest one rather than an empty string: the card always has a letter to stamp.
		Casts = count(payload.Casts, 0),
		Hits = count(payload.Hits, 0),
		DamageDealt = count(payload.DamageDealt, 0),
		DamageTaken = count(payload.DamageTaken, 0),
		Grade = stringOr(payload.Grade, Execution.grade(0, 0, 0, 0, false)),
	}
end

local function onQueueChanged(payload: any)
	local snapshot = readQueue(payload)
	if snapshot == nil then
		warnOnce("QueueChanged", payload)
		return
	end
	queue = snapshot
	MatchController.QueueChanged:Fire(snapshot)
end

-- Single site so the signal carries an optional snapshot: nil means "the match is over".
local function fireMatch(snapshot: MatchSnapshot?)
	match = snapshot
	MatchController.MatchChanged:Fire(snapshot)
end

-- What the match sounds like, from its snapshots: the music switches when one begins and ends, the
-- countdown ticks on every whole second it loses, and the round opening is the one beat played when
-- the count reaches zero. All of it from the snapshot the HUD already draws, so the ear and the eye
-- cannot disagree about when the round started.
local lastCountdownSecond = -1
local lastPhase: string? = nil

local function soundMatch(previous: MatchSnapshot?, current: MatchSnapshot?)
	if current == nil then
		if previous ~= nil then
			soundController.wantMusic("Match", nil)
		end
		lastPhase = nil
		lastCountdownSecond = -1
		return
	end
	if previous == nil or previous.MatchId ~= current.MatchId then
		soundController.wantMusic("Match", "Match")
		lastPhase = nil
		lastCountdownSecond = -1
	end
	if current.Phase == COUNTDOWN_PHASE then
		local second = math.ceil(current.SecondsLeft)
		if second ~= lastCountdownSecond and second > 0 then
			soundController.play("Countdown")
		end
		lastCountdownSecond = second
	elseif current.Phase == PLAYING_PHASE and lastPhase == COUNTDOWN_PHASE then
		soundController.play("MatchStart")
	end
	lastPhase = current.Phase
end

local function onMatchChanged(payload: any)
	if payload == nil then
		if match == nil then
			return
		end
		soundMatch(match, nil)
		fireMatch(nil)
		return
	end
	local snapshot = readMatch(payload)
	if snapshot == nil then
		warnOnce("MatchChanged", payload)
		return
	end
	soundMatch(match, snapshot)
	fireMatch(snapshot)
end

local function onMatchEnded(payload: any)
	local outcome = readOutcome(payload)
	if outcome == nil then
		warnOnce("MatchEnded", payload)
		return
	end
	lastOutcome = outcome
	-- A draw is neither phrase: the page stays as it was.
	if outcome.Won then
		soundController.play("MatchWin")
	elseif not outcome.Draw then
		soundController.play("MatchLose")
	end
	MatchController.MatchEnded:Fire(outcome)
end

function MatchController.getQueue(): QueueSnapshot
	return queue
end

function MatchController.getMatch(): MatchSnapshot?
	return match
end

-- Last MatchEnded payload, kept so the result screen can render it when it opens (the screen is built
-- lazily, after the signal has already fired).
function MatchController.getLastOutcome(): MatchOutcome?
	return lastOutcome
end

function MatchController.joinQueue(modeId: string)
	if MatchConfig.Modes[modeId] == nil then
		log.warn("join refused: unknown mode %s", modeId)
		return
	end
	if queue.Queued and queue.ModeId == modeId then
		return -- already waiting in that queue: nothing to ask the server
	end
	remoteClient.fire("JoinQueue", modeId)
end

function MatchController.leaveQueue()
	if not queue.Queued then
		return
	end
	remoteClient.fire("LeaveQueue")
end

function MatchController.Init(deps: Deps)
	remoteClient = deps.RemoteClient
	soundController = deps.SoundController
end

function MatchController.Start()
	remoteClient.on("QueueChanged", onQueueChanged)
	remoteClient.on("MatchChanged", onMatchChanged)
	remoteClient.on("MatchEnded", onMatchEnded)
	log.info("started")
end

return MatchController
