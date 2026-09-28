--!strict
-- SpectateController: an eliminated player keeps watching the match.
--
-- docs/JUICE_PLAN.md phase 8, item 5. Without it a player knocked out in the first ten seconds of a 3v3
-- stares at their own body for the rest of the round -- which is the moment they are most likely to leave,
-- and the moment their team is most worth watching.
--
-- It decides nothing about the camera itself: it names a subject and Feel sets it (Feel.watch), because
-- Feel is the only module in the game allowed to touch the camera (tests/FeelOwnership.spec.luau). The
-- shakes, the hit-stop and the field of view keep working on top of whoever is being watched.
--
-- Everything it reads is a match snapshot the server pushed: who is alive, on which team, and under which
-- name. The client picks a teammate from that and finds their character through Players -- it never
-- decides who is alive.
--
-- Who is watched is said on a plate where the dock was (HudController.showSpectating, D-147), whose discs step
-- to the previous or the next living teammate (cycle); a teammate chosen that way is kept while they live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)

local log = Log.new("SpectateController")

type Deps = { MatchController: any, Feel: any, HudController: any }

local SpectateController = {}

local matchController: any
local feel: any
local hudController: any
local player = Players.LocalPlayer
-- Who is being watched right now, kept across snapshots while they live.
local watching: number? = nil

local function humanoidOf(userId: number): Humanoid?
	local other = Players:GetPlayerByUserId(userId)
	if other == nil then
		return nil
	end
	local character = other.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function stop()
	if watching == nil then
		return
	end
	watching = nil
	feel.watch(nil)
	hudController.showSpectating(nil)
end

type Candidate = { UserId: number, Name: string }

-- The teammates the player may watch, in the order the server sent them: alive, not the player, with a
-- character loaded.
local function candidates(snapshot: Types.MatchSnapshot): { Candidate }
	local list: { Candidate } = {}
	local members = snapshot.Teams[snapshot.LocalTeam]
	if members == nil then
		return list
	end
	for _, member in ipairs(members) do
		if member.Alive and member.UserId ~= player.UserId and humanoidOf(member.UserId) ~= nil then
			table.insert(list, { UserId = member.UserId, Name = member.Name })
		end
	end
	return list
end

-- The living teammate to watch: the one watched now while they live, else the first. Stable, so the camera
-- does not hop between two teammates on every snapshot.
local function pick(snapshot: Types.MatchSnapshot): (number?, string?)
	local list = candidates(snapshot)
	for _, candidate in ipairs(list) do
		if candidate.UserId == watching then
			return candidate.UserId, candidate.Name
		end
	end
	local first = list[1]
	if first == nil then
		return nil, nil
	end
	return first.UserId, first.Name
end

-- Watches `userId`, and says so on the plate.
local function watch(userId: number, name: string)
	local humanoid = humanoidOf(userId)
	if humanoid == nil then
		return
	end
	watching = userId
	feel.watch(humanoid)
	hudController.showSpectating(name, SpectateController.cycle)
end

local function isEliminated(snapshot: Types.MatchSnapshot): boolean
	local members = snapshot.Teams[snapshot.LocalTeam]
	if members == nil then
		return false
	end
	for _, member in ipairs(members) do
		if member.UserId == player.UserId then
			return not member.Alive
		end
	end
	return false
end

local function refresh(snapshot: Types.MatchSnapshot?)
	if snapshot == nil or not isEliminated(snapshot) then
		stop()
		return
	end
	local userId, name = pick(snapshot)
	if userId == nil then
		-- Nobody left to watch: the round is about to end anyway, and moving the camera onto an opponent
		-- would show the player a fight they are not allowed to read.
		stop()
		return
	end
	if userId == watching then
		return
	end
	watch(userId, name :: string)
end

-- Steps to the previous (-1) or the next (1) living teammate, round the team (the plate's discs).
function SpectateController.cycle(step: number)
	local snapshot = matchController.getMatch()
	if snapshot == nil or watching == nil then
		return
	end
	local list = candidates(snapshot)
	local index = 0
	for position, candidate in ipairs(list) do
		if candidate.UserId == watching then
			index = position
		end
	end
	if index == 0 or #list < 2 then
		return
	end
	local next = list[(index - 1 + step) % #list + 1]
	watch(next.UserId, next.Name)
end

function SpectateController.Init(deps: Deps)
	matchController = deps.MatchController
	feel = deps.Feel
	hudController = deps.HudController
end

function SpectateController.Start()
	matchController.MatchChanged:Connect(refresh)
	-- A respawn hands the camera back: the engine points it at the new humanoid on its own, and this makes
	-- sure nothing here is still holding a subject from the round before.
	player.CharacterAdded:Connect(stop)
	refresh(matchController.getMatch())
	log.info("started")
end

return SpectateController
