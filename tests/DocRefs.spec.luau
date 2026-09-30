--!strict
-- docs/PUBLISH.md and docs/QA.md name the code they send a reader to, never a line of it (E2-S5). Both pinned
-- their line numbers to commit c0b6687: every commit since moved some of them, and a reader following
-- `MatchService.luau:616-636` in the middle of a release landed on whatever sits there now. A reference gives the
-- file and the function or the constant; a name survives the commits that move it.
--
-- The rules: no line number on a reference to a code file, bare (`File.luau:42`) or trailing (`:42`), in backticks
-- or not, or as a link's anchor (`File.luau#L42`); and every code file a reference names exists, once, in the
-- repository, so a rename shows up here instead of in a release.
local Harness = require("./harness")
local fs = require("@lune/fs")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local DOCS = { "docs/PUBLISH.md", "docs/QA.md" }
-- Where the files a reference can name live, and the files at the root.
local ROOTS = { "src", "tests", "scripts", "tools", "assets", ".github" }
local CODE = { "luau", "lua", "json", "sh", "yml", "yaml", "py", "toml" }

local function isCode(path: string): boolean
	local extension = path:match("%.(%w+)$")
	return extension ~= nil and table.find(CODE, extension) ~= nil
end

local function collect(directory: string, out: { string })
	for _, entry in ipairs(fs.readDir(directory)) do
		local path = if directory == "." then entry else directory .. "/" .. entry
		if fs.isDir(path) then
			if directory ~= "." then
				collect(path, out)
			end
		else
			table.insert(out, path)
		end
	end
end

local function repositoryFiles(): { string }
	local files: { string } = {}
	collect(".", files)
	for _, root in ipairs(ROOTS) do
		collect(root, files)
	end
	return files
end

-- Every reference of `text` to a line of a code file, backticked or not, alone or followed by words, or as the anchor
-- of a link (`File.luau#L42`); and every lone backticked `:42`.
local function lineReferences(text: string): { string }
	local found: { string } = {}
	for reference in text:gmatch("[%w_%.%-/]+[:#]L?%d[%d,%-]*") do
		-- A document with a line number (`docs/PERFORMANCE.md:98`) is not code: its sections are its names.
		local path = reference:match("^(.-)[:#]L?%d")
		if path ~= nil and isCode(path) then
			table.insert(found, reference)
		end
	end
	for span in text:gmatch("`([^`\n]+)`") do
		if span:match("^:%d[%d,%-]*$") ~= nil then
			table.insert(found, span)
		end
	end
	return found
end

-- Every code file `text` names in a backticked span.
local function codeFiles(text: string): { string }
	local found: { string } = {}
	for span in text:gmatch("`([^`\n]+)`") do
		local path = span:gsub("^%./", "")
		if path:match("^[%w_%.%-/]+$") ~= nil and isCode(path) then
			table.insert(found, path)
		end
	end
	return found
end

-- The repository files `path` names: itself, or every file whose path ends with it.
local function matches(files: { string }, path: string): { string }
	local found: { string } = {}
	for _, file in ipairs(files) do
		if file == path or file:sub(-(#path + 1)) == "/" .. path then
			table.insert(found, file)
		end
	end
	return found
end

describe("the references of the release documents (E2-S5)", function()
	it("never give a line of a code file: they name the function or the constant", function()
		for _, doc in ipairs(DOCS) do
			local refs = lineReferences(fs.readFile(doc))
			if #refs > 0 then
				error(
					("%s refers to code by line: %s. Name the function or the constant instead"):format(
						doc,
						table.concat(refs, ", ")
					)
				)
			end
		end
	end)

	it("name code files that exist, once each", function()
		local files = repositoryFiles()
		expect(#files).toBeGreaterThan(100)
		for _, doc in ipairs(DOCS) do
			for _, path in ipairs(codeFiles(fs.readFile(doc))) do
				local found = matches(files, path)
				if #found ~= 1 then
					error(
						("%s names %s, which is %s"):format(
							doc,
							path,
							if #found == 0 then "nowhere in the repository" else table.concat(found, " and ")
						)
					)
				end
			end
		end
	end)

	it("recognise a reference by line when there is one", function()
		expect(lineReferences("see (`MatchService.luau:616-636`) and (`:73`)")).toEqual({
			"MatchService.luau:616-636",
			":73",
		})
		expect(lineReferences("(`allowDamage`, `MatchService.luau`) and `docs/PERFORMANCE.md:98`")).toEqual({})
		-- Out of backticks, followed by the name it should have been, or as a link: still a line.
		expect(lineReferences("voir MatchService.luau:616 et `GameConfig.luau:6 (Version)`")).toEqual({
			"MatchService.luau:616",
			"GameConfig.luau:6",
		})
		expect(lineReferences("[allowDamage](../src/server/Services/MatchService.luau#L616)")).toEqual({
			"../src/server/Services/MatchService.luau#L616",
		})
		expect(lineReferences("http://localhost:8080 à 12:30, `luau-lsp@1.69.0`, `docs/QA.md#L3`")).toEqual({})
		expect(codeFiles("(`./scripts/check.sh`, `GameConfig.Version`, `build/Vellum.rbxl`)")).toEqual({
			"scripts/check.sh",
		})
	end)
end)

describe("the stale mentions of the release documents (E2-S5)", function()
	it("are gone: no commits ahead counted at c0b6687, no gaps dated to it", function()
		expect(fs.readFile("docs/PUBLISH.md"):find("commits d'avance sur `main` : la fusionner", 1, true)).toBeNil()
		expect(fs.readFile("docs/PUBLISH.md"):find("12 commits", 1, true)).toBeNil()
		expect(fs.readFile("docs/QA.md"):find("## 12. Écarts connus au commit", 1, true)).toBeNil()
	end)
end)

return nil
