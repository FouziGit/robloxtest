--!strict
-- ToastQueue: which message the toast lane shows next, and for how long (D-147). Pure module: no require,
-- no Roblox global, tested under Lune (tests/ToastQueue.spec.luau). src/ui/components/Toast.luau draws the
-- messages; this decides which of them is on screen.
--
--   push      queues a message. A full queue drops its oldest Info first: a fight can post a line a second,
--             and a refused purchase or a claimed quest must not be what falls off the end behind them. An
--             Info arriving into a queue of nothing but the other kinds is refused.
--   take      the next message to present now, or nil: never more than MaxVisible on screen at once, never
--             a kind that is held, and nothing at all while paused.
--   finish    a message that was presented has left, and its place is free.
--   hold      kinds that wait in the queue without presenting: the value colours while the player fights
--             (docs/ART_BIBLE.md rule 11). They present, in the order they came, once no longer held.
--   pause     nothing new presents: a boss's warning is up, and the eye belongs to it. The queue keeps
--             filling, and presents in order once resumed.
--   duration  how long a message stays: long enough to read it, never so long it outstays the next one.

export type Entry = { Text: string, Kind: string, Amount: number? }

-- ThemeConfig.Timing.Toast.
export type Timing = {
	BaseSeconds: number,
	PerCharSeconds: number,
	FreeChars: number,
	MaxSeconds: number,
	CelebrateSeconds: number,
}

export type Queue = {
	MaxVisible: number,
	MaxPending: number,
	Pending: { Entry },
	-- Presented and not finished yet.
	Visible: number,
	Held: { [string]: boolean },
	Paused: boolean,
}

local ToastQueue = {}

local INFO = "Info"
local CELEBRATE = "Celebrate"

function ToastQueue.new(maxVisible: number, maxPending: number): Queue
	return { MaxVisible = maxVisible, MaxPending = maxPending, Pending = {}, Visible = 0, Held = {}, Paused = false }
end

-- Makes room for one message of `incoming` in a full queue: the oldest Info goes, or, when there is none, the
-- oldest message of any kind -- unless the newcomer is itself an Info, which is then the one not kept.
local function dropOne(queue: Queue, incoming: string): boolean
	for index, entry in ipairs(queue.Pending) do
		if entry.Kind == INFO then
			table.remove(queue.Pending, index)
			return true
		end
	end
	if incoming == INFO then
		return false
	end
	table.remove(queue.Pending, 1)
	return true
end

-- Queues `entry`; false when it was refused.
function ToastQueue.push(queue: Queue, entry: Entry): boolean
	if #queue.Pending >= queue.MaxPending and not dropOne(queue, entry.Kind) then
		return false
	end
	table.insert(queue.Pending, entry)
	return true
end

-- The next message to present, taken out of the queue and counted as visible; nil when the lane is full or
-- every message waiting is of a held kind.
function ToastQueue.take(queue: Queue): Entry?
	if queue.Paused or queue.Visible >= queue.MaxVisible then
		return nil
	end
	for index, entry in ipairs(queue.Pending) do
		if not queue.Held[entry.Kind] then
			table.remove(queue.Pending, index)
			queue.Visible += 1
			return entry
		end
	end
	return nil
end

-- A presented message has left the lane.
function ToastQueue.finish(queue: Queue)
	queue.Visible = math.max(0, queue.Visible - 1)
end

-- Holds the kinds set in `kinds` from now on, and only those: hold({}) releases everything held.
function ToastQueue.hold(queue: Queue, kinds: { [string]: boolean })
	queue.Held = table.clone(kinds)
end

-- Holds every new message back while `paused`, and lets them through again, in order, once not.
function ToastQueue.pause(queue: Queue, paused: boolean)
	queue.Paused = paused
end

-- How many messages the lane shows at once: fewer during a fight, where the eye has somewhere else to be.
-- The ones already on screen finish their time.
function ToastQueue.setMaxVisible(queue: Queue, maxVisible: number)
	queue.MaxVisible = maxVisible
end

-- Seconds a message of `kind` saying `text` stays on screen: BaseSeconds for a short line, PerCharSeconds more
-- for every character past FreeChars, never past MaxSeconds. A celebration stays its own CelebrateSeconds.
function ToastQueue.duration(text: string, kind: string, timing: Timing): number
	if kind == CELEBRATE then
		return timing.CelebrateSeconds
	end
	local length = utf8.len(text) or #text
	local extra = math.max(0, length - timing.FreeChars)
	return math.clamp(timing.BaseSeconds + extra * timing.PerCharSeconds, timing.BaseSeconds, timing.MaxSeconds)
end

return ToastQueue
