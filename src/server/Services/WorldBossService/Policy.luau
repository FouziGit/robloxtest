--!strict
-- Policy: the PvP rule the scheduled event borrows for its whole duration (docs/GAME_DESIGN.md §7). Only the
-- event takes it. A practice never does (D-132): MatchService's own rule already keeps players from hurting
-- each other outside a match, and one player practising must not change the rule for the whole server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Context = require(script.Parent.Context)
local Log = require(Shared.Util.Log)

local log = Log.new("WorldBoss.Policy")

local Policy = {}

local deps: Context.Deps
local restorePolicy: Context.Policy? = nil

-- Damage rule while the event is live. It NARROWS the rule it borrowed, it does not replace it: any
-- pair where either side is in a match is decided by the borrowed rule, so a duel or a 3v3 that was
-- already running when the boss spawned keeps its participant PvP. Everything else follows the event
-- rule of docs/GAME_DESIGN.md §7 — server-authored damage carries no source so the boss, its attacks
-- and the environment still land, players still hit the boss and the training dummies, and no player
-- can damage another one.
--
-- Replacing the rule outright made every live match undamageable for the whole event: nobody could be
-- eliminated, so each round ran to its timer and resolved as a draw, and a ranked series was scored on
-- a fight that was physically impossible to play. Roughly a third of every event cycle was exposed.
local function bossPolicy(source: Player?, targetModel: Model): boolean
	if source == nil then
		return true
	end
	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	local borrowed = restorePolicy
	if
		borrowed ~= nil
		and (deps.Match.isInMatch(source) or (targetPlayer ~= nil and deps.Match.isInMatch(targetPlayer)))
	then
		return borrowed(source, targetModel)
	end
	return targetPlayer == nil
end

-- CombatService keeps a single policy slot and MatchService owns it from its Start, so the event borrows
-- the slot instead of stacking on it: setPolicy hands back the policy it replaced, bossPolicy defers to
-- it for anything a live match governs, and the cleanup puts it back. A build where nothing comes back
-- is logged rather than guessed — the event would otherwise restore a rule it never read, and
-- bossPolicy would have nothing to defer to.
function Policy.take()
	local replaced = deps.Combat.setPolicy(bossPolicy)
	restorePolicy = replaced
	if replaced == nil then
		log.warn("Combat.setPolicy returned no previous policy: PvP stays off until an owner installs one")
	end
end

-- Puts back the rule the event borrowed. Nothing when none was borrowed (a practice, a cancelled event).
function Policy.release()
	local previous = restorePolicy
	restorePolicy = nil
	if previous ~= nil then
		deps.Combat.setPolicy(previous)
	end
end

function Policy.Init(injected: Context.Deps)
	deps = injected
end

return Policy
