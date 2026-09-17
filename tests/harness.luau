--!strict
-- Minimal test harness for Lune (see docs/DECISIONS.md D-6).
-- API: describe(name, fn) / it(name, fn) / expect(value):matcher(...)
-- Pure modules under test must have no Roblox globals and no `require`.

export type TestCase = { name: string, fn: () -> () }
export type Suite = { name: string, cases: { TestCase }, suites: { Suite } }
export type Failure = { path: string, message: string }
export type Summary = { passed: number, failed: number, failures: { Failure } }

local Harness = {}

local root: Suite = { name = "", cases = {}, suites = {} }
local current: Suite = root

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function describeValue(value: any): string
	if type(value) == "table" then
		local parts = {}
		local count = 0
		for key, item in pairs(value) do
			count += 1
			if count > 8 then
				table.insert(parts, "…")
				break
			end
			table.insert(parts, tostring(key) .. "=" .. describeValue(item))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function Harness.describe(name: string, fn: () -> ())
	local suite: Suite = { name = name, cases = {}, suites = {} }
	table.insert(current.suites, suite)
	local previous = current
	current = suite
	fn()
	current = previous
end

function Harness.it(name: string, fn: () -> ())
	table.insert(current.cases, { name = name, fn = fn })
end

local function fail(message: string)
	error(message, 0)
end

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeCloseTo: (expected: number, digits: number?) -> (),
	toBeGreaterThan: (expected: number) -> (),
	toBeGreaterThanOrEqual: (expected: number) -> (),
	toBeLessThan: (expected: number) -> (),
	toBeLessThanOrEqual: (expected: number) -> (),
	toContain: (expected: any) -> (),
	toHaveLength: (expected: number) -> (),
	toThrow: (substring: string?) -> (),
	never: Expectation,
}

local function buildExpectation(value: any, negated: boolean): Expectation
	local function check(condition: boolean, message: string)
		if negated then
			if condition then
				fail("expected NOT: " .. message)
			end
		else
			if not condition then
				fail(message)
			end
		end
	end

	local expectation = {}

	function expectation.toBe(expected: any)
		check(value == expected, "expected " .. describeValue(value) .. " to be " .. describeValue(expected))
	end

	function expectation.toEqual(expected: any)
		check(
			deepEqual(value, expected),
			"expected " .. describeValue(value) .. " to equal " .. describeValue(expected)
		)
	end

	function expectation.toBeTruthy()
		check(value and true or false, "expected " .. describeValue(value) .. " to be truthy")
	end

	function expectation.toBeFalsy()
		check(not value, "expected " .. describeValue(value) .. " to be falsy")
	end

	function expectation.toBeNil()
		check(value == nil, "expected " .. describeValue(value) .. " to be nil")
	end

	function expectation.toBeCloseTo(expected: number, digits: number?)
		local precision = 10 ^ -(digits or 2)
		check(
			type(value) == "number" and math.abs(value - expected) < precision,
			"expected " .. describeValue(value) .. " to be close to " .. tostring(expected)
		)
	end

	function expectation.toBeGreaterThan(expected: number)
		check(
			type(value) == "number" and value > expected,
			"expected " .. describeValue(value) .. " > " .. tostring(expected)
		)
	end

	function expectation.toBeGreaterThanOrEqual(expected: number)
		check(
			type(value) == "number" and value >= expected,
			"expected " .. describeValue(value) .. " >= " .. tostring(expected)
		)
	end

	function expectation.toBeLessThan(expected: number)
		check(
			type(value) == "number" and value < expected,
			"expected " .. describeValue(value) .. " < " .. tostring(expected)
		)
	end

	function expectation.toBeLessThanOrEqual(expected: number)
		check(
			type(value) == "number" and value <= expected,
			"expected " .. describeValue(value) .. " <= " .. tostring(expected)
		)
	end

	function expectation.toContain(expected: any)
		local found = false
		if type(value) == "table" then
			for _, item in ipairs(value) do
				if deepEqual(item, expected) then
					found = true
					break
				end
			end
		elseif type(value) == "string" and type(expected) == "string" then
			found = string.find(value, expected, 1, true) ~= nil
		end
		check(found, "expected " .. describeValue(value) .. " to contain " .. describeValue(expected))
	end

	function expectation.toHaveLength(expected: number)
		local length = if type(value) == "table" then #value elseif type(value) == "string" then #value else -1
		check(length == expected, "expected length " .. tostring(length) .. " to be " .. tostring(expected))
	end

	function expectation.toThrow(substring: string?)
		local ok, err = pcall(value)
		local threw = not ok
		if threw and substring ~= nil then
			threw = string.find(tostring(err), substring, 1, true) ~= nil
		end
		check(
			threw,
			"expected function to throw" .. (if substring then " containing " .. describeValue(substring) else "")
		)
	end

	if not negated then
		expectation.never = buildExpectation(value, true)
	end

	return (expectation :: any) :: Expectation
end

function Harness.expect(value: any): Expectation
	return buildExpectation(value, false)
end

local function runSuite(suite: Suite, path: string, summary: Summary)
	local prefix = if path == "" then suite.name else path .. " › " .. suite.name
	for _, case in ipairs(suite.cases) do
		local ok, err = pcall(case.fn)
		if ok then
			summary.passed += 1
		else
			summary.failed += 1
			table.insert(summary.failures, { path = prefix .. " › " .. case.name, message = tostring(err) })
		end
	end
	for _, child in ipairs(suite.suites) do
		runSuite(child, prefix, summary)
	end
end

function Harness.run(): Summary
	local summary: Summary = { passed = 0, failed = 0, failures = {} }
	for _, suite in ipairs(root.suites) do
		runSuite(suite, "", summary)
	end
	return summary
end

function Harness.reset()
	root = { name = "", cases = {}, suites = {} }
	current = root
end

return Harness
