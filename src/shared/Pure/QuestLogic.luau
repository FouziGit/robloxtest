--!strict
-- Quest selection, progress and claims. Pure module: no requires, no Roblox globals.

export type Period = "Daily" | "Weekly"
export type QuestDef = { Id: string, Period: Period, Event: string, Target: number, NameKey: string }
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

local function hash(text: string): number
	local value = 2166136261
	for index = 1, #text do
		value = (bit32.bxor(value, string.byte(text, index)) * 16777619) % 4294967296
	end
	return value
end

-- Deterministic selection of `count` distinct quests of `period` for `periodKey`.
function QuestLogic.select(pool: { QuestDef }, period: Period, count: number, periodKey: string): { QuestDef }
	local candidates = {}
	for _, def in ipairs(pool) do
		if def.Period == period then
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

-- Resets the set when the period changed. Returns true if a reset happened.
function QuestLogic.ensurePeriod(set: SetData, periodKey: string): boolean
	if set.PeriodKey == periodKey then
		return false
	end
	set.PeriodKey = periodKey
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
