--!strict
-- Audience: who is in the fight in the slot, and who hears about it (BossChanged and the fight's toasts).
--
-- The scheduled event is server-wide: everybody hears of it, wherever they are. A practice (D-132) is its
-- participants' own business: only those still in the server, not let go since, and not in a match. A
-- participant is let go by a gate (WorldBossService.leave) or by a ranked match taking them; they then stop
-- counting as engaged, and keep their share.

local Players = game:GetService("Players")

local Context = require(script.Parent.Context)
local WorldBossMode = require(script.Parent.Parent.Parent.GameModes.WorldBossMode)

local Audience = {}

local deps: Context.Deps
local slot: Context.Slot

-- Everyone who hears about the fight in the slot right now.
function Audience.recipients(): { Player }
	if slot.Kind == "Event" then
		return Players:GetPlayers()
	end
	local result: { Player } = {}
	for _, player in ipairs(Context.livePlayers(slot.Participants)) do
		if not slot.Departed[player.UserId] and not deps.Match.isInMatch(player) then
			table.insert(result, player)
		end
	end
	return result
end

-- A toast about the fight, to whoever hears about it.
function Audience.tell(key: string, params: { [string]: any }?, notifyKind: Context.NotifyKind)
	if slot.Kind == "Event" then
		deps.Notify.sendAll(key, params, notifyKind)
		return
	end
	for _, player in ipairs(Audience.recipients()) do
		deps.Notify.send(player, key, params, notifyKind)
	end
end

-- BossChanged goes to whoever hears about the fight, with the damage share resolved per receiver: one table,
-- one field rewritten per player, FireClient serializes it on the spot.
function Audience.push(now: number)
	local current = slot.State
	if current == nil then
		return
	end
	local snapshot = WorldBossMode.snapshot(current, slot.PhaseEndsAt - now, 0, slot.Kind == "Practice")
	for _, player in ipairs(Audience.recipients()) do
		snapshot.MyShare = WorldBossMode.shareOf(current, player.UserId)
		deps.Registry.fire("BossChanged", player, snapshot)
	end
end

-- Lets a participant go, and records how (`how`: a gate, or a match): they stop counting as engaged, and a
-- practice, whose band only its own participants see, takes it off their screen. They may walk back in through
-- the hub's gate (Admission).
function Audience.release(player: Player, how: Context.Release)
	slot.Departed[player.UserId] = how
	if slot.Kind == "Practice" then
		deps.Registry.fire("BossChanged", player, nil)
	end
end

-- A participant a ranked match took (MatchService.start places them wherever they stood): a match is a way out of
-- the arena like a gate, so they are let go the same way -- event or practice, now that ranked keeps pairing
-- through the event (E16-S1) -- and keep their share. They stop counting as engaged, so after the match the
-- Battleground and the Flyleaf take them in again; a practice's band leaves their screen instead of freezing over
-- the match, while the event's stays up, as it does for the whole server.
function Audience.releaseMatched()
	for _, player in ipairs(Context.livePlayers(slot.Participants)) do
		if not slot.Departed[player.UserId] and deps.Match.isInMatch(player) then
			Audience.release(player, "Match")
		end
	end
end

function Audience.Init(injected: Context.Deps, shared: Context.Slot)
	deps = injected
	slot = shared
end

return Audience
