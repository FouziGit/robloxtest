--!strict
-- Structured logging with a per-service prefix. Errors are never swallowed: `Log.try` always warns.

-- The steps of a loop that visits many elements (a player's state, a match), each isolated from the others. See
-- `logger.faults`.
export type Faults = {
	try: <T...>(key: any, context: string, fn: (T...) -> ...any, T...) -> number,
	forget: (key: any) -> (),
}

export type Logger = {
	info: (message: string, ...any) -> (),
	warn: (message: string, ...any) -> (),
	error: (message: string, ...any) -> (),
	try: <T...>(context: string, fn: (T...) -> ...any, T...) -> boolean,
	succeeded: <T...>(context: string, fn: (T...) -> ...any, T...) -> boolean,
	faults: (everySeconds: number, clock: (() -> number)?) -> Faults,
}

type FaultRecord = { Count: number, LoggedAt: number, Hidden: number }

local Log = {}

local function render(prefix: string, message: string, ...: any): string
	local count = select("#", ...)
	if count == 0 then
		return "[" .. prefix .. "] " .. message
	end
	local ok, formatted = pcall(string.format, message, ...)
	if ok then
		return "[" .. prefix .. "] " .. formatted
	end
	local parts = { message }
	for index = 1, count do
		table.insert(parts, tostring((select(index, ...))))
	end
	return "[" .. prefix .. "] " .. table.concat(parts, " ")
end

function Log.new(prefix: string): Logger
	local logger = {}

	function logger.info(message: string, ...: any)
		print(render(prefix, message, ...))
	end

	function logger.warn(message: string, ...: any)
		warn(render(prefix, message, ...))
	end

	function logger.error(message: string, ...: any)
		warn(render(prefix, "ERROR " .. message, ...))
	end

	-- Runs fn in a pcall; on failure warns with context and returns false.
	--
	-- The boolean is "it did not throw", NOT "it succeeded", and it DISCARDS whatever fn returned. Use it
	-- for a fn that returns nothing. For a fn whose result says whether it did the thing, use `succeeded`:
	-- reading this value as that result is how a refused grant and a failed profile save both once read
	-- as having worked.
	function logger.try<T...>(context: string, fn: (T...) -> ...any, ...: T...): boolean
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(render(prefix, "%s failed: %s", context, tostring(err)))
		end
		return ok
	end

	-- True only when fn neither threw NOR returned a falsy first value, warning with context in either
	-- case. This is the question a caller has about a function that reports whether it did the thing:
	-- granting a cosmetic, persisting a profile, spending currency.
	function logger.succeeded<T...>(context: string, fn: (T...) -> ...any, ...: T...): boolean
		local ok, result = pcall(fn, ...)
		if not ok then
			warn(render(prefix, "%s failed: %s", context, tostring(result)))
			return false
		end
		if not result then
			warn(render(prefix, "%s refused", context))
			return false
		end
		return true
	end

	-- log.try for the step of a loop that runs every tick over many elements, keyed by element (a Player, a match
	-- id). One element that throws never stops the loop from reaching the others, and never floods the log: its
	-- failure is written at once, then at most once per `everySeconds` for as long as it keeps failing, with how
	-- many times in a row it has failed and how many lines were held back since the last one. `try` returns that
	-- count, 0 when fn did not throw, so the caller can give up on an element that keeps failing (a match is
	-- cancelled). An element is forgotten when it leaves (`forget`), or once it has run clean for a whole window.
	-- `clock` is os.clock unless a test gives its own.
	function logger.faults(everySeconds: number, clock: (() -> number)?): Faults
		local now = clock or os.clock
		local records: { [any]: FaultRecord } = {}
		local faults = {}

		function faults.try<T...>(key: any, context: string, fn: (T...) -> ...any, ...: T...): number
			local ok, err = pcall(fn, ...)
			local record = records[key]
			if ok then
				if record ~= nil then
					record.Count = 0
					if now() - record.LoggedAt >= everySeconds then
						records[key] = nil
					end
				end
				return 0
			end
			local at = now()
			if record == nil then
				record = { Count = 0, LoggedAt = -math.huge, Hidden = 0 }
				records[key] = record
			end
			record.Count += 1
			if at - record.LoggedAt >= everySeconds then
				warn(
					render(
						prefix,
						"%s %s failed (%d in a row, %d not shown): %s",
						context,
						tostring(key),
						record.Count,
						record.Hidden,
						tostring(err)
					)
				)
				record.LoggedAt = at
				record.Hidden = 0
			else
				record.Hidden += 1
			end
			return record.Count
		end

		function faults.forget(key: any)
			records[key] = nil
		end

		return faults :: Faults
	end

	return logger :: Logger
end

return Log
