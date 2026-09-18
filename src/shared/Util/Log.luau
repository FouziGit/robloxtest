--!strict
-- Structured logging with a per-service prefix. Errors are never swallowed: `Log.try` always warns.

export type Logger = {
	info: (message: string, ...any) -> (),
	warn: (message: string, ...any) -> (),
	error: (message: string, ...any) -> (),
	try: <T...>(context: string, fn: (T...) -> ...any, T...) -> boolean,
	succeeded: <T...>(context: string, fn: (T...) -> ...any, T...) -> boolean,
}

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

	return logger :: Logger
end

return Log
