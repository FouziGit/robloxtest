--!strict
-- Quest selection, progress and claims. Pure module: no requires, no Roblox globals.

export type Period = "Daily" | "Weekly"
-- `Since`: the pool revision that added the quest (QuestConfig.PoolRevision); none for the first pool.
export type QuestDef = { Id: string, Period: Period, Event: string, Target: number, NameKey: string, Since: number? }
export type SetData = { PeriodKey: string, Progress: { [string]: number }, Claimed: { [string]: boolean } }
export type Status = { Id: string, Progress: number, Target: number, Claimed: boolean, Completed: boolean }

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
function QuestLogic.select(pool: { QuestDef }, period: Period, count: number, setKey: string): { QuestDef }
	local periodKey, revision = splitKey(setKey)
	local candidates = {}
	for _, def in ipairs(pool) do
		if def.Period == period and (def.Since or 1) <= revision then
			table.insert(candidates, def)
		end
	end
	local state = hash(periodKey .. period)
	local selected = {}
	while #selected < count and #candidates > 0 do
		-- xorshift32
		state = bit32.bxor(state, bit32.lshift(state, 13) % 4294967296)
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5) % 4294967296)
		local index = (state % #candidates) + 1
		table.insert(selected, candidates[index])
		table.remove(candidates, index)
	end
	return selected
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
