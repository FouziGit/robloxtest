--!strict
-- Boot: runs Init then Start of every service in the Bootstrap's order, and closes the server when a CRITICAL one
-- failed (E9-S3, D-XXX).
--
-- Each step still runs under log.try, so one service that throws never stops the others from starting. That was
-- the whole policy before, and it left a server half up: a DataService that never started loads no profile and
-- saves nothing, a MonetizationService that never bound ProcessReceipt takes Robux and grants nothing, a
-- CombatService or an AntiCheatService that never started lets a fight or a cheat run unrefereed. Players stayed
-- on such a server and lost what they did there. The services the game cannot run without are marked Critical;
-- if one of them failed, every player present and every player who arrives is kicked with a message in their
-- language telling them to rejoin, and the empty server is left to close. A non-critical failure (a leaderboard,
-- a quest board) keeps the server open, as it always did.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local log = Log.new("Bootstrap")

export type Service = { Init: (deps: any) -> (), Start: () -> () }
export type Entry = { Name: string, Service: Service, Critical: boolean? }

local KICK_KEY = "kick.serverError"

local Boot = {}

-- Init of every entry, then Start of every entry, each under log.try. Returns the names of the critical entries
-- whose Init or Start threw, in boot order; empty when the server may open.
function Boot.run(ordered: { Entry }, deps: any): { string }
	local broken: { [Entry]: true } = {}
	for _, entry in ipairs(ordered) do
		if not log.try(entry.Name .. ".Init", entry.Service.Init, deps) then
			broken[entry] = true
		end
	end
	for _, entry in ipairs(ordered) do
		if not log.try(entry.Name .. ".Start", entry.Service.Start) then
			broken[entry] = true
		end
	end
	local failed: { string } = {}
	for _, entry in ipairs(ordered) do
		if broken[entry] and entry.Critical then
			table.insert(failed, entry.Name)
		end
	end
	return failed
end

local function turnAway(player: Player)
	player:Kick(Strings.t(KICK_KEY, nil, Strings.localeFromId(player.LocaleId)))
end

-- Turns away everyone on the server now and everyone who joins it later: `failed` names what did not start.
function Boot.close(failed: { string })
	log.error("critical service(s) failed to start: %s. Every player is sent away", table.concat(failed, ", "))
	Players.PlayerAdded:Connect(turnAway)
	for _, player in ipairs(Players:GetPlayers()) do
		turnAway(player)
	end
end

return Boot
