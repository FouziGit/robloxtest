--!strict
-- Quest selection, progress and claims. Pure module: no requires, no Roblox globals.

export type Period = "Daily" | "Weekly"
-- Whether a player alone on a server can finish the quest ("Solo"), or needs others to be there ("Players":
-- a match, a player to defeat, the Erasure's scheduled event).
export type Needs = "Solo" | "Players"
-- `Since`: the pool revision that added the quest (QuestConfig.PoolRevision); none for the first pool.
export type QuestDef = {
	Id: string,
	Period: Period,
	Event: string,
	Target: number,
	NameKey: string,
	Needs: Needs,
	Since: number?,
}
-- `Swaps`: the quests of the draw a reroll replaced, each by the quest that took its place (QuestLogic.reroll).
export type SetData = {
	PeriodKey: string,
	Progress: { [string]: number },
	Claimed: { [string]: boolean },
	Swaps: { [string]: string },
}
export type Status = { Id: string, Progress: number, Target: number, Claimed: boolean, Completed: boolean }
-- From the pool revision `Since` on, every draw holds at least `Count` Solo quests (QuestConfig.SoloFloor).
export type Floor = { Since: number, Count: number }
-- What a reroll draws from: the pool, the period's count and floor, and the rerolls a set may spend.
export type RerollRules = { Pool: { QuestDef }, Count: number, Floor: Floor?, Allowance: number }
-- "Rerolled", or why not: the quest is not in the live set, was claimed, is completed and waits to be claimed,
-- the set has spent its rerolls (or the quest is itself a reroll's), or no Solo quest is left to draw.
export type RerollVerdict = "Rerolled" | "NotLive" | "Claimed" | "Completed" | "Spent" | "NoCandidate"

local QuestLogic = {}

local SECONDS_PER_DAY = 86400

-- Days since the Unix epoch (UTC).
function QuestLogic.dayIndex(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

-- Weeks since the epoch, aligned so weeks start on Monday (1970-01-01 was a Thursday).
function QuestLogic.weekIndex(unixTime: number): number
	return math.floor((QuestLogic.dayIndex(unixTime) + 3) / 7)
end

function QuestLogic.periodKey(period: Period, unixTime: number): string
	if period == "Daily" then
		return "D" .. tostring(QuestLogic.dayIndex(unixTime))
	end
	return "W" .. tostring(QuestLogic.weekIndex(unixTime))
end

-- When the period `unixTime` falls in ends: the first second whose period key is another one, which is
-- the moment the server draws the next set. Periods are whole UTC days, so that second is a midnight, and
-- walking forward a day at a time finds it in at most a week. It is found through periodKey itself, so
-- a countdown to it can never disagree with the rollover it announces.
function QuestLogic.periodEndsAt(period: Period, unixTime: number): number
	local key = QuestLogic.periodKey(period, unixTime)
	local day = QuestLogic.dayIndex(unixTime) + 1
	while QuestLogic.periodKey(period, day * SECONDS_PER_DAY) == key do
		day += 1
	end
	return day * SECONDS_PER_DAY
end

-- A set's key names its period and the pool revision its quests were drawn from: "D20725" for the
-- first pool, "D20725@2" for the second. The revision stays with the set until its period ends, so a
-- deploy that adds a quest to the pool changes nobody's quests before their next day or week. Drawn
-- again from the grown pool, today's set changed under players who had already claimed it, and the
-- quests that newly entered it paid on top of the ones they had claimed. A key stored before revisions
-- existed has none, and reads as the first pool: the one it was drawn from.
local function splitKey(setKey: string): (string, number)
	local periodKey, revision = string.match(setKey, "^(.*)@(%d+)$")
	if periodKey ~= nil and revision ~= nil then
		return periodKey, tonumber(revision) :: number
	end
	return setKey, 1
end

-- The key of a set drawn now, in the period `periodKey`, from the pool at `revision`.
function QuestLogic.setKey(periodKey: string, revision: number): string
	if revision <= 1 then
		return periodKey
	end
	return periodKey .. "@" .. tostring(revision)
end

local function hash(text: string): number
	local value = 2166136261
	for index = 1, #text do
		value = (bit32.bxor(value, string.byte(text, index)) * 16777619) % 4294967296
	end
	return value
end

-- Deterministic selection of `count` distinct quests of `period` for the set key `setKey`. Only the
-- quests of the key's pool revision are candidates, and the draw hashes the period alone, so a key from
-- the first pool draws exactly what it drew before the pool grew.
--
-- From `floor.Since` on, a draw holding fewer than `floor.Count` Solo quests gives up its last Players quests,
-- each to a Solo quest drawn on from the same sequence among the candidates left. Any other draw is exactly
-- the draw it would have been, and a key of an earlier revision draws what it drew before the floor existed.
function QuestLogic.select(
	pool: { QuestDef },
	period: Period,
	count: number,
	setKey: string,
	floor: Floor?
): { QuestDef }
	local periodKey, revision = splitKey(setKey)
	local candidates = {}
	for _, def in ipairs(pool) do
		if def.Period == period and (def.Since or 1) <= revision then
			table.insert(candidates, def)
		end
	end
	local state = hash(periodKey .. period)
	-- xorshift32
	local function nextState(): number
		state = bit32.bxor(state, bit32.lshift(state, 13) % 4294967296)
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5) % 4294967296)
		return state
	end
	local selected = {}
	local solo = 0
	while #selected < count and #candidates > 0 do
		local index = (nextState() % #candidates) + 1
		local picked = table.remove(candidates, index) :: QuestDef
		table.insert(selected, picked)
		if picked.Needs == "Solo" then
			solo += 1
		end
	end
	if floor == nil or revision < floor.Since then
		return selected
	end
	for slot = #selected, 1, -1 do
		if solo >= floor.Count then
			break
		end
		if selected[slot].Needs ~= "Solo" then
			local left = {}
			for _, def in ipairs(candidates) do
				if def.Needs == "Solo" then
					table.insert(left, def)
				end
			end
			if #left == 0 then
				break
			end
			local picked = left[(nextState() % #left) + 1]
			table.remove(candidates, table.find(candidates, picked) :: number)
			selected[slot] = picked
			solo += 1
		end
	end
	return selected
end

-- The quests a set plays: its draw, each quest a reroll replaced standing where it was drawn, in its
-- replacement's place (`swaps`, from the set). A set without swaps plays its draw as it is.
function QuestLogic.swapped(pool: { QuestDef }, drawn: { QuestDef }, swaps: { [string]: string }?): { QuestDef }
	if swaps == nil or next(swaps) == nil then
		return drawn
	end
	local byId: { [string]: QuestDef } = {}
	for _, def in ipairs(pool) do
		byId[def.Id] = def
	end
	local live = {}
	for _, def in ipairs(drawn) do
		local swappedIn = swaps[def.Id]
		table.insert(live, if swappedIn ~= nil and byId[swappedIn] ~= nil then byId[swappedIn] else def)
	end
	return live
end

-- Rerolls `set` has left to spend of `allowance`: one is spent by each swap the set holds.
function QuestLogic.rerollsLeft(set: SetData, allowance: number): number
	local spent = 0
	for _ in pairs(set.Swaps) do
		spent += 1
	end
	return math.max(allowance - spent, 0)
end

-- Replaces the live quest `questId` of `set` by a Solo quest of the same period and pool revision that this
-- period has not drawn yet: never a quest of the draw, never one a reroll already brought in or sent away.
-- Refused on a quest claimed or completed (its reward would be lost), on a quest a reroll brought in, and once
-- the set has spent `rules.Allowance` rerolls. The quest drawn in is chosen by the period and the quest sent
-- away, so every player who sends the same quest away on the same day gets the same one. On "Rerolled" the
-- swap is written into the set, and the progress of the quest sent away is dropped.
function QuestLogic.reroll(
	rules: RerollRules,
	period: Period,
	set: SetData,
	questId: string
): (RerollVerdict, QuestDef?)
	local drawn = QuestLogic.select(rules.Pool, period, rules.Count, set.PeriodKey, rules.Floor)
	local live = QuestLogic.swapped(rules.Pool, drawn, set.Swaps)
	local slot = nil
	for index, def in ipairs(live) do
		if def.Id == questId then
			slot = index
		end
	end
	if slot == nil then
		return "NotLive", nil
	end
	local current = live[slot]
	if set.Claimed[questId] then
		return "Claimed", nil
	end
	if (set.Progress[questId] or 0) >= current.Target then
		return "Completed", nil
	end
	if QuestLogic.rerollsLeft(set, rules.Allowance) == 0 or drawn[slot].Id ~= current.Id then
		return "Spent", nil
	end
	local seen: { [string]: boolean } = {}
	for from, to in pairs(set.Swaps) do
		seen[from] = true
		seen[to] = true
	end
	for _, def in ipairs(drawn) do
		seen[def.Id] = true
	end
	local periodKey, revision = splitKey(set.PeriodKey)
	local candidates = {}
	for _, def in ipairs(rules.Pool) do
		if def.Period == period and (def.Since or 1) <= revision and def.Needs == "Solo" and not seen[def.Id] then
			table.insert(candidates, def)
		end
	end
	if #candidates == 0 then
		return "NoCandidate", nil
	end
	local chosen = candidates[(hash(periodKey .. ":" .. questId) % #candidates) + 1]
	set.Swaps[questId] = chosen.Id
	set.Progress[questId] = nil
	return "Rerolled", chosen
end

-- Resets the set when the period of `setKey` is not the set's own, and stores `setKey`. Within one
-- period the stored key stays, and with it the revision the set was drawn from. Returns true if a reset
-- happened.
function QuestLogic.ensurePeriod(set: SetData, setKey: string): boolean
	if (splitKey(set.PeriodKey)) == (splitKey(setKey)) then
		return false
	end
	set.PeriodKey = setKey
	set.Progress = {}
	set.Claimed = {}
	set.Swaps = {}
	return true
end

-- Applies a gameplay event to the active quests; returns the ids that just completed.
function QuestLogic.applyEvent(set: SetData, quests: { QuestDef }, event: string, amount: number): { string }
	local completed = {}
	if amount <= 0 then
		return completed
	end
	for _, def in ipairs(quests) do
		if def.Event == event and not set.Claimed[def.Id] then
			local before = set.Progress[def.Id] or 0
			if before < def.Target then
				local after = math.min(def.Target, before + amount)
				set.Progress[def.Id] = after
				if after >= def.Target then
					table.insert(completed, def.Id)
				end
			end
		end
	end
	return completed
end

function QuestLogic.canClaim(set: SetData, def: QuestDef): boolean
	return not set.Claimed[def.Id] and (set.Progress[def.Id] or 0) >= def.Target
end

-- Marks the quest claimed. Returns false if it was not claimable.
function QuestLogic.claim(set: SetData, def: QuestDef): boolean
	if not QuestLogic.canClaim(set, def) then
		return false
	end
	set.Claimed[def.Id] = true
	return true
end

function QuestLogic.status(set: SetData, quests: { QuestDef }): { Status }
	local result = {}
	for _, def in ipairs(quests) do
		local progress = math.min(def.Target, set.Progress[def.Id] or 0)
		table.insert(result, {
			Id = def.Id,
			Progress = progress,
			Target = def.Target,
			Claimed = set.Claimed[def.Id] == true,
			Completed = progress >= def.Target,
		})
	end
	return result
end

return QuestLogic
