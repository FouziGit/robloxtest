--!strict
-- Structured logging with a per-service prefix. Errors are never swallowed: `Log.try` always warns.

export type Logger = {
	info: (message: string, ...any) -> (),
	warn: (message: string, ...any) -> (),
	error: (message: string, ...any) -> (),
	try: <T...>(context: string, fn: (T...) -> ...any, T...) -> boolean,
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
	-- The boolean is "it did not throw", NOT "it succeeded", and it DISCARDS whatever fn returned. A
	-- caller that needs fn's own result must use pcall directly: returning this value as if it were the
	-- result is how a failed profile save once read as a successful one.
	function logger.try<T...>(context: string, fn: (T...) -> ...any, ...: T...): boolean
		local ok, err = pcall(fn, ...)
		if not ok then
			warn(render(prefix, "%s failed: %s", context, tostring(err)))
		end
		return ok
	end

	return logger :: Logger
end

return Log
