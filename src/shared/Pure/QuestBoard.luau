--!strict
-- What the quests board shows of a period (D-147): each quest's state, the order they are listed in, and
-- the time left before the set is drawn again. Pure module: no requires, no Roblox globals, so the order a
-- player reads is the order the test computed.
--
-- A quest waiting to be claimed comes first, because it is the one thing on the board the player can act
-- on; the ones still in progress follow, and the claimed ones sink to the bottom. Within a state the
-- quests keep the order the period drew them in, so nothing reshuffles while it is being played.

export type State = "Claimable" | "InProgress" | "Claimed"
-- The fields of QuestLogic.Status the board reads.
export type Status = { Claimed: boolean, Completed: boolean }

local QuestBoard = {}

local RANKS: { [State]: number } = { Claimable = 1, InProgress = 2, Claimed = 3 }
local SECONDS_PER_MINUTE = 60
local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = 24 * MINUTES_PER_HOUR

function QuestBoard.state(status: Status): State
	if status.Claimed then
		return "Claimed"
	elseif status.Completed then
		return "Claimable"
	end
	return "InProgress"
end

-- The indices of `states` (each quest's state, in the order the period drew them) in the order the board
-- lists them.
function QuestBoard.order(states: { State }): { number }
	local indices: { number } = {}
	for index in ipairs(states) do
		table.insert(indices, index)
	end
	table.sort(indices, function(a: number, b: number): boolean
		local rankA = RANKS[states[a]]
		local rankB = RANKS[states[b]]
		if rankA ~= rankB then
			return rankA < rankB
		end
		return a < b
	end)
	return indices
end

-- The Strings key and parameters that say how long `seconds` is: hours and minutes under a day, days and
-- hours from a day on. Rounded up to the minute, so a period with time left never reads as none.
function QuestBoard.countdown(seconds: number): (string, { [string]: number })
	local minutes = math.max(0, math.ceil(seconds / SECONDS_PER_MINUTE))
	if minutes < MINUTES_PER_DAY then
		return "time.hoursMinutes",
			{ hours = math.floor(minutes / MINUTES_PER_HOUR), minutes = minutes % MINUTES_PER_HOUR }
	end
	return "time.daysHours",
		{
			days = math.floor(minutes / MINUTES_PER_DAY),
			hours = math.floor((minutes % MINUTES_PER_DAY) / MINUTES_PER_HOUR),
		}
end

return QuestBoard
