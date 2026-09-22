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
-- Who is being watched right now, so the toast is shown on a change and not five times a second.
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
end

-- The living teammate to watch: the first of the local team, by the order the server sent them, that is
-- alive and has a character loaded. Stable, so the camera does not hop between two teammates on every
-- snapshot.
local function pick(snapshot: Types.MatchSnapshot): (number?, string?)
	local members = snapshot.Teams[snapshot.LocalTeam]
	if members == nil then
		return nil, nil
	end
	for _, member in ipairs(members) do
		if member.Alive and member.UserId ~= player.UserId and humanoidOf(member.UserId) ~= nil then
			return member.UserId, member.Name
		end
	end
	return nil, nil
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
	local humanoid = humanoidOf(userId)
	if humanoid == nil then
		return
	end
	watching = userId
	feel.watch(humanoid)
	hudController.showLocalToast("match.watching", { name = name }, "Info")
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
