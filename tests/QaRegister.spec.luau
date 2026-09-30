--!strict
-- The register at the top of docs/QA.md: what no Lune test has ever seen, the tool that can see it and who owns it
-- (E6-S4). Those behaviours were scattered through PROGRESS, STUDIO_SETUP and the QA pass itself, each with no
-- owner, and none of them had ever been looked at. A row without a tool or without an owner is a wish.
--
-- The smoke test (E6-S2) reads one of them in the client's output: whether the touch layout was measured on the
-- engine's JumpButton or on the corner kept for it. InputController says which, once per change, in the words the
-- register quotes.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local QA = "docs/QA.md"
local INPUT = "src/client/Controllers/InputController.luau"
local HEADING = "## Ce que Lune ne peut pas voir"
local COLUMNS =
	{ "Élément", "Pourquoi Lune ne peut pas le voir", "Outil", "Responsable", "Statut", "Dernier commit vu" }
local OWNERS = { "Claude", "toi", "Claude et toi" }
-- Each behaviour the story names, by a word its row carries.
local REQUIRED = {
	"billboards",
	"ragdoll",
	"Faussaires",
	"`docs/STUDIO_SETUP.md` §10",
	"`JumpButton`",
	"iOS et Android",
	"`CanvasGroup`",
	"`UIStroke` sous `UIScale`",
}

type Row = { string }

local function cells(line: string): Row
	local row: Row = {}
	for cell in line:sub(2, -2):gmatch("([^|]*)|?") do
		table.insert(row, (cell:match("^%s*(.-)%s*$")) :: string)
	end
	if row[#row] == "" then
		table.remove(row)
	end
	return row
end

-- The register's header and rows, and where it stands in the document.
local function register(): (Row, { Row }, number)
	local text = fs.readFile(QA)
	local at = text:find(HEADING, 1, true)
	assert(at ~= nil, "docs/QA.md has no register: " .. HEADING)
	local section = text:sub(at):match("^.-\n(.-)\n## ") or ""
	local lines: { string } = {}
	for line in section:gmatch("[^\n]+") do
		if line:sub(1, 1) == "|" then
			table.insert(lines, line)
		end
	end
	local rows: { Row } = {}
	for index = 3, #lines do
		table.insert(rows, cells(lines[index]))
	end
	return cells(lines[1] or "|"), rows, at
end

local function code(path: string): string
	return ((fs.readFile(path)):gsub("%-%-[^\n]*", ""))
end

local function functionIn(source: string, header: string): string
	local start = source:find(header, 1, true)
	assert(start ~= nil, "missing " .. header)
	local finish = source:find("\nend\n", start, true)
	return source:sub(start, finish)
end

describe("the register of what Lune cannot see (E6-S4)", function()
	it("opens docs/QA.md, before the pass itself", function()
		local _, _, at = register()
		local pass = fs.readFile(QA):find("## 0. Avant de commencer", 1, true)
		assert(pass ~= nil, "docs/QA.md lost its §0")
		expect(at).toBeLessThan(pass)
	end)

	it("gives each row a tool, an owner, a status and the last commit seen", function()
		local header, rows = register()
		expect(header).toEqual(COLUMNS)
		expect(#rows).toBeGreaterThanOrEqual(#REQUIRED)
		for _, row in ipairs(rows) do
			local name = row[1] or "?"
			expect(#row).toBe(#COLUMNS)
			for index, column in ipairs(COLUMNS) do
				if (row[index] or "") == "" then
					error(("the row %q has no %s"):format(name, column))
				end
			end
			if table.find(OWNERS, row[4]) == nil then
				error(("the row %q is owned by %q, not by Claude, toi, or Claude et toi"):format(name, row[4]))
			end
			if row[6] ~= "—" and row[6]:match("^`?%x%x%x%x%x%x%x+`?$") == nil then
				error(("the row %q was last seen at %q, neither a commit nor —"):format(name, row[6]))
			end
		end
	end)

	it("holds every behaviour never observed that the story names", function()
		local _, rows = register()
		for _, needle in ipairs(REQUIRED) do
			local found = false
			for _, row in ipairs(rows) do
				if row[1]:find(needle, 1, true) ~= nil then
					found = true
				end
			end
			if not found then
				error("the register has no row for " .. needle)
			end
		end
	end)
end)

describe("the JumpButton the smoke test reads (E6-S4)", function()
	local input = code(INPUT)

	it("is told once per change, measured on the engine's button or on the corner kept for it", function()
		local told = functionIn(input, "local function measuredOn(")
		expect(told).toContain("if jumpMeasuredOn == source then")
		local jump = functionIn(input, "local function jumpRect(")
		local found = jump:find('measuredOn("JumpButton")', 1, true)
		local fallback = jump:find('measuredOn("Reserve")', 1, true)
		local reserve = jump:find("InputConfig.Touch.JumpReserve", 1, true)
		assert(found ~= nil and fallback ~= nil and reserve ~= nil, "jumpRect does not say what it measured on")
		expect(found).toBeLessThan(fallback)
		expect(fallback).toBeLessThan(reserve)
	end)

	it("is told in the words the register quotes", function()
		local source = fs.readFile(INPUT)
		local qa = fs.readFile(QA)
		for _, line in ipairs({
			"touch layout measured on the engine's JumpButton",
			"touch layout measured on the reserved corner: TouchGui has no JumpButton yet",
		}) do
			expect(source).toContain('log.info("' .. line .. '")')
			expect(qa).toContain("`[InputController] " .. line .. "`")
		end
	end)
end)

return nil
