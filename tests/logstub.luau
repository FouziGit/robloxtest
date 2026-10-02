--!strict
-- A stand-in for src/shared/Util/Log that keeps what a module logs, for a spec to read, instead of printing
-- it. Handed to Engine.world as the stub of "src/shared/Util/Log"; `try` and `succeeded` keep the real ones'
-- meaning (did not throw; did not throw and returned a truthy value).
local LogStub = {}

-- The stub module, and the lines every logger it makes has written, formatted, in order.
function LogStub.new(): (any, { string })
	local lines: { string } = {}
	local function record(message: string, ...: any)
		local ok, text = pcall(string.format, message, ...)
		table.insert(lines, if ok then text else message)
	end
	local module = {
		new = function(_prefix: string): any
			return {
				info = record,
				warn = record,
				error = record,
				try = function(_context: string, fn: (...any) -> ...any, ...: any): boolean
					return (pcall(fn, ...))
				end,
				succeeded = function(_context: string, fn: (...any) -> ...any, ...: any): boolean
					local ok, result = pcall(fn, ...)
					return ok and result and true or false
				end,
			}
		end,
	}
	return module, lines
end

return LogStub
